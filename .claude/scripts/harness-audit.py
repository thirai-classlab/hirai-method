#!/usr/bin/env python3
"""harness-audit.py — Claude Code ハーネスの健全性を実測値で出力。

Read-only 集計。観察ログ・GateGuard state・TaskGuard state・failure-window から
完成率 / リトライ率 / ブロック頻度 / failure-loop 件数 / hook timeout 件数を抽出。

Usage:
    python3 .claude/scripts/harness-audit.py            # default: human-readable
    python3 .claude/scripts/harness-audit.py --json     # machine-readable
    python3 .claude/scripts/harness-audit.py --window=N # 直近 N 件のみ集計（default 100）

外部依存なし（標準ライブラリのみ）。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path.cwd()

# === harness-config.yml: 軽量パーサ ===
# bash 側 config-loader.sh と同等の subset (フラット key:value / [a,b,c] / コメント) を読む。
# 不在 / 該当 key 欠如時はハードコード fallback (旧来挙動と同一)。
DEFAULTS: dict[str, str] = {
    "gateguard_state_dir": ".claude/.gateguard-state",
    "taskguard_state_dir": ".claude/.taskguard-state",
    "failure_window_dir": ".claude/.failure-window",
    "confidence_state_dir": ".claude/.confidence-gate-state",
    "homunculus_root": str(Path.home() / ".claude" / "homunculus"),
}


def _expand_tilde(value: str) -> str:
    if value == "~":
        return str(Path.home())
    if value.startswith("~/"):
        return str(Path.home() / value[2:])
    return value


def _load_harness_config(path: Path) -> dict[str, str]:
    """フラット YAML から scalar key を抽出。配列 / ネストは無視。"""
    cfg: dict[str, str] = {}
    if not path.exists():
        return cfg
    try:
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.rstrip("\r")
            stripped = line.lstrip()
            # コメント / 空行
            if not stripped or stripped.startswith("#"):
                continue
            # ネスト行 (先頭インデントあり) は subset 対象外
            if line != stripped:
                continue
            if ":" not in stripped:
                continue
            key, _, value = stripped.partition(":")
            value = value.strip()
            # 配列構文 [..] は audit が消費する key には現状不要 → スキップ
            if value.startswith("["):
                continue
            # 外側 quote strip
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            cfg[key.strip().lower()] = _expand_tilde(value)
    except OSError:
        return {}
    return cfg


_CFG_PATH = ROOT / ".claude" / "harness-config.yml"
_CFG = _load_harness_config(_CFG_PATH)


def _cfg(key: str) -> str:
    return _CFG.get(key, DEFAULTS[key])


HOMUNCULUS = Path(_cfg("homunculus_root"))


def _normalize_remote_url(url: str) -> str:
    """observe.sh と同じ正規化: ssh→https + 末尾 .git strip。

    observe.sh 内では `sed -E 's|^git@([^:]+):|https://\\1/|; s|\\.git$||'` 相当。
    両者の hash を一致させないと harness-audit.py が observations.jsonl を
    project-scoped で発見できず global fallback すら空になる。
    """
    s = url.strip()
    # git@host:owner/repo  →  https://host/owner/repo
    m = re.match(r"^git@([^:]+):(.*)$", s)
    if m:
        s = f"https://{m.group(1)}/{m.group(2)}"
    # 末尾 .git を strip
    if s.endswith(".git"):
        s = s[:-4]
    return s


def project_hash() -> str | None:
    """git remote URL から project hash を導出（observe.sh と同じロジック）。"""
    try:
        out = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        if not out:
            return None
        canon = _normalize_remote_url(out)
        return hashlib.sha256(canon.encode()).hexdigest()[:12]
    except Exception:
        return None


def find_observations() -> Path | None:
    """observations.jsonl の場所を探す（project-scoped → global fallback）。"""
    ph = project_hash()
    if ph:
        p = HOMUNCULUS / "projects" / ph / "observations.jsonl"
        if p.exists():
            return p
    g = HOMUNCULUS / "observations.jsonl"
    if g.exists():
        return g
    return None


def tail_jsonl(path: Path, n: int) -> list[dict]:
    """末尾 N 行を JSON parse。壊れた行はスキップ。"""
    if not path.exists():
        return []
    try:
        with path.open("rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            chunk = min(size, max(n * 4096, 65536))
            f.seek(size - chunk)
            data = f.read().decode("utf-8", errors="replace")
    except Exception:
        return []
    lines = data.splitlines()[-n:]
    out = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def summarize_observations(records: list[dict]) -> dict:
    """observations から指標を抽出。"""
    if not records:
        return {
            "total": 0,
            "tools": {},
            "errors": 0,
            "error_rate": 0.0,
            "timeouts": 0,
            "first_ts": None,
            "last_ts": None,
        }
    total = len(records)
    tool_counts: Counter[str] = Counter()
    tool_errors: Counter[str] = Counter()
    timeouts = 0
    errors = 0
    timestamps: list[str] = []

    for r in records:
        tool = r.get("tool_name") or r.get("tool") or "unknown"
        tool_counts[tool] += 1
        ts = r.get("timestamp") or r.get("ts")
        if ts:
            timestamps.append(str(ts))
        # error detection (best-effort)
        resp = r.get("tool_response") or {}
        if isinstance(resp, dict):
            if resp.get("is_error") or resp.get("decision") == "block":
                errors += 1
                tool_errors[tool] += 1
            err_str = json.dumps(resp).lower() if resp else ""
            if "timeout" in err_str or "timed out" in err_str:
                timeouts += 1

    return {
        "total": total,
        "tools": dict(tool_counts.most_common()),
        "tool_errors": dict(tool_errors.most_common()),
        "errors": errors,
        "error_rate": round(errors / total, 3) if total else 0.0,
        "timeouts": timeouts,
        "first_ts": min(timestamps) if timestamps else None,
        "last_ts": max(timestamps) if timestamps else None,
    }


def count_state_dir(d: Path, suffix: str = ".cleared") -> int:
    if not d.is_dir():
        return 0
    return sum(1 for p in d.iterdir() if p.is_file() and p.name.endswith(suffix))


def gateguard_breakdown() -> dict:
    """GateGuard state file 名から edit / write / bash 別に集計。"""
    d = ROOT / _cfg("gateguard_state_dir")
    out = {"total": 0, "edit": 0, "write": 0, "bash": 0}
    if not d.is_dir():
        return out
    for p in d.iterdir():
        if not p.is_file() or not p.name.endswith(".cleared"):
            continue
        out["total"] += 1
        if p.name.startswith("edit-"):
            out["edit"] += 1
        elif p.name.startswith("write-"):
            out["write"] += 1
        elif p.name.startswith("bash-"):
            out["bash"] += 1
    return out


def failure_window_summary() -> dict:
    """failure-window 内の各 session log を集計。"""
    d = ROOT / _cfg("failure_window_dir")
    out: dict[str, dict] = {"sessions": {}, "active_loops": 0}
    if not d.is_dir():
        return out
    for log in d.glob("*.log"):
        try:
            lines = [ln.strip() for ln in log.read_text().splitlines() if ln.strip()]
        except Exception:
            continue
        if not lines:
            continue
        # active loop = 直近 3 行が同 signature
        active = False
        if len(lines) >= 3 and len(set(lines[-3:])) == 1:
            active = True
            out["active_loops"] += 1
        out["sessions"][log.stem] = {
            "events": len(lines),
            "active_loop": active,
            "last_signature": lines[-1] if lines else None,
        }
    return out


def confidence_gate_breakdown() -> dict:
    """Confidence Gate (F3) bypass.log を集計。

    出力:
      - bypasses: 累計 bypass 回数（ファイル行数）
      - recent_reasons: 直近 5 件の bypass reason（時刻 + reason）
      - bypass_marker_pending: 未消化の bypass.cleared が残っているか
    """
    d = ROOT / _cfg("confidence_state_dir")
    out: dict = {"bypasses": 0, "recent_reasons": [], "bypass_marker_pending": False}
    if not d.is_dir():
        return out
    log = d / "bypass.log"
    if log.is_file():
        try:
            lines = [ln.rstrip() for ln in log.read_text().splitlines() if ln.strip()]
        except Exception:
            lines = []
        out["bypasses"] = len(lines)
        out["recent_reasons"] = lines[-5:]
    out["bypass_marker_pending"] = (d / "bypass.cleared").is_file()
    return out


def fmt_human(report: dict) -> str:
    obs = report["observations"]
    gg = report["gateguard"]
    tg = report["taskguard"]
    fw = report["failure_window"]

    lines: list[str] = []
    lines.append("# Harness Audit Report")
    lines.append(f"_generated: {datetime.now().isoformat(timespec='seconds')}_")
    lines.append("")

    # Observations
    lines.append("## 観察ログ (observations.jsonl)")
    if not report["observations_path"]:
        lines.append("- 観測ログが見つかりません（git remote 未設定 or 観察未開始）。")
    else:
        lines.append(f"- source: `{report['observations_path']}`")
        lines.append(f"- window: 直近 {report['window']} 件")
        lines.append(f"- total events: **{obs['total']}**")
        lines.append(
            f"- errors: **{obs['errors']}**（error rate {obs['error_rate']:.1%}）"
        )
        lines.append(f"- timeouts: {obs['timeouts']}")
        if obs["first_ts"] and obs["last_ts"]:
            lines.append(f"- range: {obs['first_ts']} → {obs['last_ts']}")
        if obs["tools"]:
            lines.append("")
            lines.append("### tool 別 (top 10)")
            for t, c in list(obs["tools"].items())[:10]:
                err = obs["tool_errors"].get(t, 0)
                rate = (err / c) if c else 0
                marker = " ⚠️" if rate >= 0.3 and c >= 5 else ""
                lines.append(f"  - `{t}`: {c} calls / {err} errors ({rate:.0%}){marker}")
    lines.append("")

    # GateGuard
    lines.append("## GateGuard state (F1)")
    lines.append(f"- cleared: **{gg['total']}** files")
    lines.append(f"  - edit: {gg['edit']} / write: {gg['write']} / bash: {gg['bash']}")
    if gg["total"] == 0:
        lines.append("  - (まだ初回 Edit/Write/破壊的 Bash の事実調査が発生していない)")
    lines.append("")

    # TaskGuard
    lines.append("## TaskGuard bypass (タスク管理)")
    lines.append(f"- cleared: **{tg}** files (slug-単位 bypass)")
    if tg > 0:
        lines.append("  - ⚠️ bypass の根拠を CLAUDE.md / docs/tasks/ に記録すること")
    lines.append("")

    # Failure window
    lines.append("## Failure-loop window (W2.1)")
    lines.append(f"- active loops: **{fw['active_loops']}**")
    if fw["sessions"]:
        for sid, s in fw["sessions"].items():
            badge = " 🔁 ACTIVE LOOP" if s["active_loop"] else ""
            lines.append(f"  - `{sid}`: {s['events']} events{badge}")
            if s["last_signature"]:
                lines.append(f"    last: `{s['last_signature']}`")
    else:
        lines.append("- (no failure events recorded in current windows)")
    lines.append("")

    # Confidence Gate (F3)
    cg = report["confidence_gate"]
    lines.append("## Confidence Gate (F3)")
    lines.append(f"- bypasses (累計): **{cg['bypasses']}**")
    if cg["bypass_marker_pending"]:
        lines.append("  - ⚠️ bypass.cleared が未消化（次回の SubagentStop で 1 回 PASS）")
    if cg["recent_reasons"]:
        lines.append("  - 直近 5 件の bypass reason:")
        for r in cg["recent_reasons"]:
            lines.append(f"    - `{r}`")
    if cg["bypasses"] == 0 and not cg["bypass_marker_pending"]:
        lines.append("  - (まだ bypass されていない)")
    lines.append("")

    # Health badge
    lines.append("## Health")
    health = []
    if obs["total"] > 0:
        if obs["error_rate"] >= 0.3:
            health.append("🔴 high error rate")
        elif obs["error_rate"] >= 0.1:
            health.append("🟡 moderate error rate")
        else:
            health.append("🟢 low error rate")
    if fw["active_loops"] > 0:
        health.append(f"🔴 {fw['active_loops']} active failure loop(s)")
    if obs["timeouts"] > 5:
        health.append(f"🟡 {obs['timeouts']} timeouts in window")
    if not health:
        health.append("🟢 no issues detected")
    for h in health:
        lines.append(f"- {h}")

    return "\n".join(lines)


def swe_bench_breakdown() -> dict:
    """SWE-bench Lite dry-run / 本番 results を集計。

    .claude/skills/eval-harness/swe-bench/results/*.json を読み、
    各 run の completion rate / 平均 cost / 平均時間 / patch 適用率を返す。
    """
    d = ROOT / ".claude" / "skills" / "eval-harness" / "swe-bench" / "results"
    out: dict = {"runs": [], "total_runs": 0}
    if not d.is_dir():
        return out
    for p in sorted(d.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
        s = data.get("summary") or {}
        results = data.get("results") or []
        if not results:
            continue
        n = len(results)
        applied = sum(1 for r in results if r.get("score", {}).get("patch_applies"))
        # resolved = patch applied AND tests run AND f2p tests pass with no failures
        resolved = sum(
            1 for r in results
            if r.get("score", {}).get("patch_applies")
            and r.get("score", {}).get("tests_run")
            and r.get("score", {}).get("tests_passed", 0) > 0
            and r.get("score", {}).get("tests_failed", 0) == 0
        )
        tests_attempted = sum(1 for r in results if r.get("score", {}).get("tests_run"))
        avg_cost = round(s.get("cumulative_cost_usd", 0) / n, 4) if n else 0.0
        avg_dur = round(
            sum(r.get("invoke_duration_sec", 0) for r in results) / n, 2
        ) if n else 0.0
        out["runs"].append({
            "file": p.name,
            "model": s.get("model"),
            "patch_mode": s.get("patch_mode"),
            "tasks_run": s.get("tasks_run"),
            "patch_generated": s.get("patch_generated_count"),
            "patch_applied": applied,
            "applied_rate": round(applied / n, 3) if n else 0.0,
            "resolved": resolved,
            "tests_attempted": tests_attempted,
            "resolved_rate": round(resolved / n, 3) if n else 0.0,
            "cumulative_cost_usd": s.get("cumulative_cost_usd"),
            "avg_cost_usd": avg_cost,
            "avg_invoke_duration_sec": avg_dur,
            "cost_cap_usd": s.get("cost_cap_usd"),
            "cost_cap_hit": s.get("cost_cap_hit"),
            "started_at": s.get("started_at"),
        })
    out["total_runs"] = len(out["runs"])
    return out


def fmt_swe_bench(sb: dict) -> str:
    """SWE-bench section markdown."""
    lines: list[str] = []
    lines.append("# SWE-bench Lite Audit")
    lines.append(f"_generated: {datetime.now().isoformat(timespec='seconds')}_")
    lines.append("")
    if sb["total_runs"] == 0:
        lines.append("(no runs found in .claude/skills/eval-harness/swe-bench/results/)")
        return "\n".join(lines)
    lines.append(f"- runs: **{sb['total_runs']}**")
    lines.append("")
    lines.append("| run | model | mode | n | applied | rate | resolved | resolved% | cum$ | avg$ | avg(s) | cap | hit |")
    lines.append("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|")
    for r in sb["runs"]:
        hit = "Y" if r.get("cost_cap_hit") else "-"
        mode = (r.get("patch_mode") or "?")[:11]
        lines.append(
            f"| {r['file']} | {r.get('model','?')} | {mode} | {r.get('tasks_run',0)} | "
            f"{r.get('patch_applied',0)} | {r.get('applied_rate',0):.0%} | "
            f"{r.get('resolved',0)} | {r.get('resolved_rate',0):.0%} | "
            f"${r.get('cumulative_cost_usd',0):.3f} | ${r.get('avg_cost_usd',0):.3f} | "
            f"{r.get('avg_invoke_duration_sec',0):.1f} | "
            f"${r.get('cost_cap_usd',0):.1f} | {hit} |"
        )
    return "\n".join(lines)


def router_breakdown(homunculus_root: Path | None = None, project_hash_override: str | None = None) -> dict:
    """Aggregate dispatch.jsonl rows from the homunculus tree.

    Strategy:
      - When an explicit `homunculus_root` is given (e.g. `--router-homunculus-root`),
        scan every projects/<hash>/dispatch.jsonl beneath it.
      - Otherwise resolve the current project's hash via `project_hash()` and read
        only that project's log; if absent, fall back to a global tree-wide scan.

    The aggregation is purposely tolerant: malformed rows are skipped, and a
    completely empty tree returns zeroed counters with `total: 0`.
    """
    root = Path(homunculus_root) if homunculus_root else HOMUNCULUS

    # Discover candidate logs.
    logs: list[Path] = []
    if homunculus_root:
        logs = sorted((root / "projects").glob("*/dispatch.jsonl")) if (root / "projects").is_dir() else []
    else:
        ph = project_hash_override or project_hash()
        if ph:
            cand = root / "projects" / ph / "dispatch.jsonl"
            if cand.exists():
                logs = [cand]
        if not logs and (root / "projects").is_dir():
            logs = sorted((root / "projects").glob("*/dispatch.jsonl"))

    rows: list[dict] = []
    for log in logs:
        try:
            for line in log.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
        except OSError:
            continue

    layer_counts: Counter[str] = Counter()
    agent_counts: Counter[str] = Counter()
    confidences: list[float] = []
    cumulative_cost = 0.0
    named_count = 0
    cycles = 0

    for r in rows:
        layer = str(r.get("fallback_layer") or "unknown")
        layer_counts[layer] += 1
        agent = str(r.get("dispatched_agent") or "unknown")
        agent_counts[agent] += 1
        if agent and agent != "general-purpose":
            named_count += 1
        try:
            confidences.append(float(r.get("confidence") or 0.0))
        except (TypeError, ValueError):
            pass
        try:
            cumulative_cost += float(r.get("cost_usd") or 0.0)
        except (TypeError, ValueError):
            pass
        if r.get("cycle_broken"):
            cycles += 1

    total = len(rows)
    avg_conf = round(sum(confidences) / len(confidences), 3) if confidences else 0.0
    named_rate = round(named_count / total, 3) if total else 0.0

    # Order layers in canonical fallback ladder; surface "unknown" last if present.
    canonical = ["keyword", "llm", "previous", "general-purpose"]
    layers_ordered = {l: layer_counts.get(l, 0) for l in canonical}
    for l, c in layer_counts.items():
        if l not in layers_ordered:
            layers_ordered[l] = c

    return {
        "logs_scanned": [str(p) for p in logs],
        "total": total,
        "by_layer": layers_ordered,
        "named_agent_count": named_count,
        "named_agent_rate": named_rate,
        "avg_confidence": avg_conf,
        "cumulative_cost_usd": round(cumulative_cost, 6),
        "cycle_broken": cycles,
        "top_agents": dict(agent_counts.most_common(10)),
    }


def fmt_router(r: dict) -> str:
    """Markdown leaderboard for the router section."""
    lines: list[str] = []
    lines.append("# Router Dispatch Audit")
    lines.append(f"_generated: {datetime.now().isoformat(timespec='seconds')}_")
    lines.append("")
    if r["total"] == 0:
        lines.append("- (no dispatch.jsonl rows found)")
        if r["logs_scanned"]:
            lines.append("")
            lines.append("## Scanned logs")
            for p in r["logs_scanned"]:
                lines.append(f"  - `{p}`")
        return "\n".join(lines)

    lines.append(f"- total dispatches: **{r['total']}**")
    lines.append(f"- named-agent rate: **{r['named_agent_rate']:.1%}** ({r['named_agent_count']}/{r['total']})")
    lines.append(f"- avg confidence: **{r['avg_confidence']:.3f}**")
    lines.append(f"- cumulative cost: **${r['cumulative_cost_usd']:.4f}**")
    lines.append(f"- cycle-broken events: {r['cycle_broken']}")
    lines.append("")

    lines.append("## Layer breakdown")
    lines.append("| layer | count | share |")
    lines.append("|---|---:|---:|")
    for layer, count in r["by_layer"].items():
        share = (count / r["total"]) if r["total"] else 0
        lines.append(f"| {layer} | {count} | {share:.1%} |")
    lines.append("")

    if r["top_agents"]:
        lines.append("## Top dispatched agents")
        lines.append("| agent | dispatches |")
        lines.append("|---|---:|")
        for agent, count in r["top_agents"].items():
            lines.append(f"| {agent} | {count} |")

    if r["logs_scanned"]:
        lines.append("")
        lines.append(f"_logs scanned: {len(r['logs_scanned'])}_")

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="出力を JSON にする")
    ap.add_argument("--window", type=int, default=100, help="観察ログの集計件数")
    ap.add_argument("--swe-bench", action="store_true", help="SWE-bench Lite leaderboard markdown のみ出力")
    ap.add_argument("--router", action="store_true", help="Agent-router dispatch.jsonl leaderboard markdown のみ出力")
    ap.add_argument("--router-homunculus-root", default=None, help="Override homunculus_root for the --router subcommand (mainly for tests)")
    args = ap.parse_args()

    if args.router:
        rr = router_breakdown(
            homunculus_root=Path(args.router_homunculus_root) if args.router_homunculus_root else None,
        )
        if args.json:
            print(json.dumps(rr, indent=2, ensure_ascii=False))
        else:
            print(fmt_router(rr))
        return 0

    if args.swe_bench:
        sb = swe_bench_breakdown()
        if args.json:
            print(json.dumps(sb, indent=2, ensure_ascii=False))
        else:
            print(fmt_swe_bench(sb))
        return 0

    obs_path = find_observations()
    records = tail_jsonl(obs_path, args.window) if obs_path else []
    report = {
        "generated": datetime.now().isoformat(timespec="seconds"),
        "project_hash": project_hash(),
        "observations_path": str(obs_path) if obs_path else None,
        "window": args.window,
        "observations": summarize_observations(records),
        "gateguard": gateguard_breakdown(),
        "taskguard": count_state_dir(ROOT / _cfg("taskguard_state_dir")),
        "failure_window": failure_window_summary(),
        "confidence_gate": confidence_gate_breakdown(),
        "swe_bench": swe_bench_breakdown(),
        "router": router_breakdown(),
    }

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(fmt_human(report))
        sb = report["swe_bench"]
        if sb["total_runs"] > 0:
            print("")
            print(fmt_swe_bench(sb))
        rr = report["router"]
        if rr["total"] > 0:
            print("")
            print(fmt_router(rr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
