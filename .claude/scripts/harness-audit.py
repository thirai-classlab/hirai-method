#!/usr/bin/env python3
"""harness-audit.py — Claude Code ハーネスの健全性を実測値で出力。

Read-only 集計。観察ログ・GateGuard state・TaskGuard state・failure-window から
完成率 / リトライ率 / ブロック頻度 / failure-loop 件数 / hook timeout 件数を抽出。

Usage:
    python3 .claude/scripts/harness-audit.py            # default: human-readable
    python3 .claude/scripts/harness-audit.py --json     # machine-readable
    python3 .claude/scripts/harness-audit.py --window=N # 直近 N 件のみ集計（default 100）
    python3 .claude/scripts/harness-audit.py --compare /path/to/other-repo
                                                        # 他リポの .claude/ と structural diff (task-25 B3)

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
from datetime import datetime, timedelta, timezone
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

# === task-32: observation pipeline 健全性指標 ===
# cascade fail 検出の閾値: N 連続 JSONDecodeError で cascade_suspected: True
# env `HC_CASCADE_THRESHOLD` で override 可、default 5
_CASCADE_THRESHOLD_DEFAULT = 5


def _cascade_threshold() -> int:
    """Resolve cascade fail 検出閾値 from env `HC_CASCADE_THRESHOLD` with safe fallback.

    Parsing 規約 (default `_CASCADE_THRESHOLD_DEFAULT` = 5):
      - env 未設定 → default
      - 正整数 (`"3"`, `"10"`) → そのまま採用
      - 非正整数 (`"0"`, `"-1"`) → default fallback (threshold は >=1 必須)
      - 非数値 (`"abc"`) → `int()` が `ValueError` → default fallback
      - float 文字列 (`"3.5"`) → `int("3.5")` は `ValueError` で default fallback
        (Python の `int()` は `"3.5"` を直接 parse できない、`float()` 経由を意図的に行わない)
      - `None` を str に変換した形 → `TypeError` 防御で fallback
    """
    raw = os.environ.get("HC_CASCADE_THRESHOLD")
    if raw is None:
        return _CASCADE_THRESHOLD_DEFAULT
    try:
        v = int(raw)
        return v if v > 0 else _CASCADE_THRESHOLD_DEFAULT
    except (TypeError, ValueError):
        return _CASCADE_THRESHOLD_DEFAULT


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


def _read_tail_chunk(path: Path, n: int) -> bytes:
    """末尾 N 行を含むのに十分な chunk を読み込む (近似 heuristic)。

    n*4096 と 65536 の大きい方を上限 chunk として末尾を seek。
    file が chunk より小さければ全 byte を返す。OSError / IOError は呼び出し側へ伝播。
    """
    with path.open("rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        chunk = min(size, max(n * 4096, 65536))
        f.seek(size - chunk)
        return f.read()


def tail_jsonl(path: Path, n: int) -> dict:
    """末尾 N 行 JSON parse + observation pipeline 健全性指標 (task-32)。

    返り値 key:
      - records: list[dict]
      - skipped_lines: int (JSONDecodeError 件数)
      - total_lines: int (空行除外後の line count)
      - cascade_suspected: bool (連続 JSONDecodeError が cascade threshold 以上)
      - max_consecutive_skips: int (window 内の最長連続 skip 数)

    iter4 PY-9 fix: 旧 `_EMPTY_TAIL_RESULT` const は inline literal return に置換 (shallow
    copy mutable share 防止)。`dict(const)` は内部の `records: []` mutable list が share される
    バグを生み、別 invocation が前回の result を mutate する事故を起こすため。
    """
    threshold = _cascade_threshold()
    if not path.exists():
        return {"records": [], "skipped_lines": 0, "total_lines": 0,
                "cascade_suspected": False, "max_consecutive_skips": 0}
    try:
        raw_bytes = _read_tail_chunk(path, n)
    except (OSError, MemoryError):
        return {"records": [], "skipped_lines": 0, "total_lines": 0,
                "cascade_suspected": False, "max_consecutive_skips": 0}
    data = raw_bytes.decode("utf-8", errors="replace")
    out: list[dict] = []
    skipped = total = consecutive_skips = max_consecutive = 0
    cascade = False
    for line in data.splitlines()[-n:]:
        line = line.strip()
        if not line:
            continue
        total += 1
        try:
            out.append(json.loads(line))
            consecutive_skips = 0
        except json.JSONDecodeError:
            skipped += 1
            consecutive_skips += 1
            if consecutive_skips > max_consecutive:
                max_consecutive = consecutive_skips
            if consecutive_skips >= threshold:
                cascade = True
    return {
        "records": out,
        "skipped_lines": skipped,
        "total_lines": total,
        "cascade_suspected": cascade,
        "max_consecutive_skips": max_consecutive,
    }


def _classify_raw_field(raw_val: object) -> str:
    """observation record の `raw` field を schema 種別に分類 (task-32)。

    返り値: `"object"` (dict) / `"string"` (str) / `"other"` (それ以外、list / None / 数値等)。
    task-27 W1 (`c25f3ee`) で観察 schema は raw=object に統一済、本判定は実測継続のため。
    """
    if isinstance(raw_val, dict):
        return "object"
    if isinstance(raw_val, str):
        return "string"
    return "other"


def summarize_observations(records: list[dict]) -> dict:
    """observations から指標を抽出 (task-32: raw object rate も併記、schema 統一の実測継続)。

    raw_object_rate semantics: `raw_present_count: 0` のとき `raw_object_rate: 0.0` は
    rate 計算不能 (no data) を意味する。`raw_present_count > 0` のときは
    `raw_object_count / raw_present_count` (object 比率) を 3 桁丸めで返す。

    iter4 PY-9 / PY-4 fix: 旧 `_EMPTY_SUMMARY` const は inline literal return に置換 + `tool_errors: {}`
    を schema に追加。`dict(const)` は内部 dict (`tools: {}` / `tool_errors: {}`) が shallow share
    されるバグを生むため、empty 時も inline literal で完全独立の dict を返す。
    """
    if not records:
        return {
            "total": 0,
            "tools": {},
            "tool_errors": {},
            "errors": 0,
            "error_rate": 0.0,
            "timeouts": 0,
            "first_ts": None,
            "last_ts": None,
            "raw_object_count": 0,
            "raw_string_count": 0,
            "raw_other_count": 0,
            "raw_present_count": 0,
            "raw_object_rate": 0.0,
        }
    total = len(records)
    tool_counts: Counter[str] = Counter()
    tool_errors: Counter[str] = Counter()
    timestamps: list[str] = []
    raw_counts: Counter[str] = Counter()
    timeouts = errors = raw_present = 0

    for r in records:
        tool = r.get("tool_name") or r.get("tool") or "unknown"
        tool_counts[tool] += 1
        ts = r.get("timestamp") or r.get("ts")
        if ts:
            timestamps.append(str(ts))
        resp = r.get("tool_response") or {}
        if isinstance(resp, dict):
            if resp.get("is_error") or resp.get("decision") == "block":
                errors += 1
                tool_errors[tool] += 1
            err_str = json.dumps(resp).lower() if resp else ""
            if "timeout" in err_str or "timed out" in err_str:
                timeouts += 1
        if "raw" in r:
            raw_present += 1
            raw_counts[_classify_raw_field(r.get("raw"))] += 1

    raw_object = raw_counts.get("object", 0)
    # rate は raw field 存在 record を分母とする (raw 欠如 record は分母から除外)
    raw_rate = round(raw_object / raw_present, 3) if raw_present else 0.0
    return {
        "total": total,
        "tools": dict(tool_counts.most_common()),
        "tool_errors": dict(tool_errors.most_common()),
        "errors": errors,
        "error_rate": round(errors / total, 3) if total else 0.0,
        "timeouts": timeouts,
        "first_ts": min(timestamps) if timestamps else None,
        "last_ts": max(timestamps) if timestamps else None,
        "raw_object_count": raw_object,
        "raw_string_count": raw_counts.get("string", 0),
        "raw_other_count": raw_counts.get("other", 0),
        "raw_present_count": raw_present,
        "raw_object_rate": raw_rate,
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


def bypass_log_summary(days: int = 7) -> dict:
    """`.claude/.workflow-state/bypass.log` を集計。

    形式: `<ISO-8601> | <session_id> | <hook_name> | <env_var> | <reason>`
    （lib/bypass-logger.sh が append する統一フォーマット）

    出力:
      - total_entries: 直近 N 日 の bypass 件数
      - window_days:   集計対象期間 (既定 7 日)
      - by_session:    session_id ごとの bypass 回数 (上位 10)
      - by_hook:       hook_name ごとの bypass 回数
      - top_env_vars:  最頻出 env_var top 3
      - log_path:      実 path (デバッグ用)
      - missing_or_empty: ログ不在 / 空なら True
    """
    log_path = ROOT / ".claude" / ".workflow-state" / "bypass.log"
    out: dict = {
        "log_path": str(log_path),
        "window_days": days,
        "total_entries": 0,
        "by_session": {},
        "by_hook": {},
        "top_env_vars": [],
        "missing_or_empty": True,
    }
    if not log_path.is_file():
        return out

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    session_counts: Counter[str] = Counter()
    hook_counts: Counter[str] = Counter()
    env_var_counts: Counter[str] = Counter()
    total = 0

    try:
        raw_lines = log_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return out

    for raw in raw_lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        # 期待フィールド数: 5
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 5:
            continue
        ts_str, session_id, hook_name, env_var, _reason = parts[0], parts[1], parts[2], parts[3], "|".join(parts[4:])
        # ISO-8601 (Z suffix) parse → tz-aware UTC
        try:
            ts = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if ts < cutoff:
            continue
        total += 1
        session_counts[session_id] += 1
        hook_counts[hook_name] += 1
        env_var_counts[env_var] += 1

    out["total_entries"] = total
    out["by_session"] = dict(session_counts.most_common(10))
    out["by_hook"] = dict(hook_counts.most_common())
    out["top_env_vars"] = [
        {"env_var": v, "count": c} for v, c in env_var_counts.most_common(3)
    ]
    out["missing_or_empty"] = total == 0
    return out


def fmt_bypass_log(b: dict) -> str:
    """Bypass log section markdown (human-readable)."""
    lines: list[str] = []
    lines.append("## Bypass Log Summary")
    lines.append(f"- source: `{b['log_path']}`")
    lines.append(f"- window: 直近 {b['window_days']} 日")
    if b["missing_or_empty"]:
        lines.append(f"- No bypass entries in last {b['window_days']} days")
        return "\n".join(lines)
    lines.append(f"- total entries: **{b['total_entries']}**")
    if b["by_session"]:
        lines.append("")
        lines.append("### Bypasses by session (top 10)")
        for sid, c in b["by_session"].items():
            lines.append(f"  - `{sid}`: {c}")
    if b["by_hook"]:
        lines.append("")
        lines.append("### Bypasses by hook")
        for hk, c in b["by_hook"].items():
            lines.append(f"  - `{hk}`: {c}")
    if b["top_env_vars"]:
        lines.append("")
        lines.append("### Top env vars (top 3)")
        for e in b["top_env_vars"]:
            lines.append(f"  - `{e['env_var']}`: {e['count']}")
    return "\n".join(lines)


def stale_drafts_summary(threshold_days: int = 90, root: Path | None = None) -> dict:
    """`docs/draft/*.md` を走査し、未承認 + mtime > threshold_days の draft を返す (task-25 C2)。

    判定基準:
      - frontmatter (HTML comment 内 `key: value`) で `approval_required: true`
      - `approved_at:` が空 (key 不在 or 値が空文字)
      - file mtime が threshold_days 日より古い
      - `_DRAFT_TEMPLATE.md` のような template / underscore prefix は除外

    出力:
      - threshold_days: 閾値 (default 90)
      - total: 該当件数
      - drafts: [{path, mtime_iso, days_old}] (days_old 降順)
      - draft_dir_present: ディレクトリ存在判定
    """
    base = root if root is not None else ROOT
    draft_dir = base / "docs" / "draft"
    out: dict = {
        "threshold_days": threshold_days,
        "total": 0,
        "drafts": [],
        "draft_dir_present": draft_dir.is_dir(),
    }
    if not draft_dir.is_dir():
        return out

    now = datetime.now()
    cutoff_sec = now.timestamp() - threshold_days * 86400
    findings: list[dict] = []

    for p in sorted(draft_dir.glob("*.md")):
        name = p.name
        # template / underscore prefix は対象外
        if name.startswith("_"):
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        if st.st_mtime > cutoff_sec:
            continue
        # frontmatter parse (HTML comment block の先頭 30 行のみ)
        try:
            head_lines = []
            with p.open("r", encoding="utf-8", errors="replace") as f:
                for i, line in enumerate(f):
                    if i >= 30:
                        break
                    head_lines.append(line)
        except OSError:
            continue
        head = "".join(head_lines)
        # `approval_required: true` で承認必須を判定 (default true、key 不在も承認必須として扱う)
        # `\s` は改行を含むため `[ \t]` に限定 (改行跨ぎマッチを防止)
        m_req = re.search(r"^[ \t]*approval_required[ \t]*:[ \t]*(\S+)", head, re.MULTILINE)
        approval_required = True
        if m_req:
            approval_required = m_req.group(1).lower() == "true"
        if not approval_required:
            continue
        # `approved_at: <value>` を抽出 — 値が空なら未承認
        m_app = re.search(r"^[ \t]*approved_at[ \t]*:[ \t]*(.*)$", head, re.MULTILINE)
        approved_value = ""
        if m_app:
            approved_value = m_app.group(1).strip()
        if approved_value:
            continue

        days_old = int((now.timestamp() - st.st_mtime) // 86400)
        try:
            rel = str(p.relative_to(base))
        except ValueError:
            rel = str(p)
        findings.append({
            "path": rel,
            "mtime_iso": datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d"),
            "days_old": days_old,
        })

    findings.sort(key=lambda d: d["days_old"], reverse=True)
    out["total"] = len(findings)
    out["drafts"] = findings
    return out


def fmt_stale_drafts(sd: dict) -> str:
    """Stale draft section markdown (task-25 C2)."""
    lines: list[str] = []
    lines.append(f"## Stale Drafts (≥{sd['threshold_days']} days, unapproved)")
    if not sd["draft_dir_present"]:
        lines.append("- (docs/draft/ 不在)")
        return "\n".join(lines)
    if sd["total"] == 0:
        lines.append(f"- 0 drafts (no unapproved drafts older than {sd['threshold_days']} days)")
        return "\n".join(lines)
    lines.append(f"{sd['total']} drafts found:")
    for d in sd["drafts"]:
        lines.append(f"  - {d['path']} (起案: {d['mtime_iso']}, {d['days_old']}日経過)")
    return "\n".join(lines)


def settings_drift_check(root: Path | None = None) -> dict:
    """`.claude/settings.json` と `settings.local.json` を比較 (task-25 C3)。

    判定:
      - settings.local.json 不在 → drift なし (silent skip)
      - 両 file の top-level key を再帰比較
        - local のみに存在 → "local_only"
        - main のみに存在 → "main_only"
        - 値が違う → "modified" (path + before/after の文字列化)

    出力:
      - local_present: bool
      - drift_count: int (発見 diff 件数)
      - local_only: list[{path, value}]
      - main_only: list[{path, value}]
      - modified: list[{path, main, local}]
    """
    base = root if root is not None else ROOT
    main_path = base / ".claude" / "settings.json"
    local_path = base / ".claude" / "settings.local.json"
    out: dict = {
        "main_present": main_path.is_file(),
        "local_present": local_path.is_file(),
        "drift_count": 0,
        "local_only": [],
        "main_only": [],
        "modified": [],
    }
    if not local_path.is_file():
        return out
    if not main_path.is_file():
        # local だけある状態は drift 報告対象だが main を読めないので skip
        return out
    try:
        main_data = json.loads(main_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return out
    try:
        local_data = json.loads(local_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return out

    local_only: list[dict] = []
    main_only: list[dict] = []
    modified: list[dict] = []

    def _walk(prefix: str, m: object, l: object) -> None:
        # 両側が dict なら key 単位再帰
        if isinstance(m, dict) and isinstance(l, dict):
            for k in sorted(set(m.keys()) | set(l.keys())):
                child_path = f"{prefix}.{k}" if prefix else k
                if k in m and k not in l:
                    main_only.append({"path": child_path, "value": _short(m[k])})
                elif k in l and k not in m:
                    local_only.append({"path": child_path, "value": _short(l[k])})
                else:
                    _walk(child_path, m[k], l[k])
            return
        # それ以外 (list / scalar) は eq 比較
        if m != l:
            modified.append({
                "path": prefix or "(root)",
                "main": _short(m),
                "local": _short(l),
            })

    _walk("", main_data, local_data)

    out["local_only"] = local_only
    out["main_only"] = main_only
    out["modified"] = modified
    out["drift_count"] = len(local_only) + len(main_only) + len(modified)
    return out


def _short(v: object, limit: int = 80) -> str:
    """値を 1 行 string に圧縮 (drift 出力用)。"""
    try:
        s = json.dumps(v, ensure_ascii=False)
    except (TypeError, ValueError):
        s = str(v)
    if len(s) > limit:
        s = s[: limit - 3] + "..."
    return s


def fmt_settings_drift(sd: dict) -> str:
    """Settings drift section markdown (task-25 C3)."""
    lines: list[str] = []
    lines.append("## Settings Drift")
    if not sd["local_present"]:
        lines.append("- settings.local.json 不在 → drift 検証 skip")
        return "\n".join(lines)
    if not sd["main_present"]:
        lines.append("- settings.json 不在 → drift 検証 skip")
        return "\n".join(lines)
    if sd["drift_count"] == 0:
        lines.append("- settings.json vs settings.local.json: identical (0 diff)")
        return "\n".join(lines)
    lines.append("settings.json vs settings.local.json:")
    for e in sd["local_only"]:
        lines.append(f"  + {e['path']}: {e['value']}  (local only)")
    for e in sd["main_only"]:
        lines.append(f"  - {e['path']}: <missing in local but present in main>")
    for e in sd["modified"]:
        lines.append(f"  ~ {e['path']}: {e['main']} -> {e['local']}")
    return "\n".join(lines)


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


def fmt_observation_health(report: dict) -> str:
    """task-32: Observation Pipeline 健全性セクション markdown。

    Phase 1: parse-skipped 行数 / raw object rate
    Phase 2: cascade fail 検出時 🔴 warning
    """
    obs = report.get("observations") or {}
    health = report.get("observation_health") or {}
    threshold = health.get("cascade_threshold", _cascade_threshold())
    total_lines = health.get("total_lines", 0)
    skipped_lines = health.get("skipped_lines", 0)
    cascade = bool(health.get("cascade_suspected", False))
    max_consec = health.get("max_consecutive_skips", 0)

    lines: list[str] = []
    lines.append("## Observation Pipeline 健全性")
    if total_lines == 0:
        lines.append("- (集計対象 line なし、observation 未発生 or window 外)")
        return "\n".join(lines)

    jq_valid = total_lines - skipped_lines
    parse_rate_pct = (jq_valid / total_lines * 100) if total_lines else 0.0
    skip_rate_pct = (skipped_lines / total_lines * 100) if total_lines else 0.0
    lines.append(
        f"- parse-skipped: **{skipped_lines}** / {total_lines} lines "
        f"({skip_rate_pct:.2f}% skipped, jq-valid {parse_rate_pct:.2f}%)"
    )

    raw_present = obs.get("raw_present_count", 0)
    raw_object = obs.get("raw_object_count", 0)
    raw_string = obs.get("raw_string_count", 0)
    raw_other = obs.get("raw_other_count", 0)
    raw_rate_pct = (obs.get("raw_object_rate", 0.0) * 100)
    if raw_present > 0:
        lines.append(
            f"- raw object rate: **{raw_rate_pct:.2f}%** "
            f"(object {raw_object} / string {raw_string} / other {raw_other} / "
            f"present {raw_present})"
        )
    else:
        lines.append("- raw object rate: (no `raw` field observed in window)")

    lines.append(f"- cascade threshold: {threshold} (env `HC_CASCADE_THRESHOLD` で override)")
    lines.append(f"- max consecutive skips observed: {max_consec}")

    if cascade:
        lines.append("")
        lines.append(
            f"🔴 **CASCADE FAIL SUSPECTED**: {max_consec} 連続行で JSONDecodeError 発生。"
            "observe.sh write 経路 regression の可能性 (`.claude/skills/continuous-learning-v2/hooks/observe.sh` "
            "の `--rawfile` + `fromjson?` 経路確認)。"
        )

    return "\n".join(lines)


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

    # task-32: Observation Pipeline 健全性 (observations セクション直後)
    if "observation_health" in report:
        lines.append(fmt_observation_health(report))
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

    # Workflow bypass log (W4)
    if "bypass_log" in report:
        lines.append(fmt_bypass_log(report["bypass_log"]))
        lines.append("")

    # Stale drafts (task-25 C2)
    if "stale_drafts" in report:
        lines.append(fmt_stale_drafts(report["stale_drafts"]))
        lines.append("")

    # Settings drift (task-25 C3)
    if "settings_drift" in report:
        lines.append(fmt_settings_drift(report["settings_drift"]))
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
    # task-32: cascade fail を Health に昇格
    oh = report.get("observation_health") or {}
    if oh.get("cascade_suspected"):
        health.append(
            f"🔴 cascade fail suspected ({oh.get('max_consecutive_skips', 0)} consecutive parse errors)"
        )
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
            "by_gate_combo": s.get("by_gate_combo") or {},
            "official_harness": data.get("official_harness") or {},
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

    # F1/F2 gate-combo breakdown (only emitted for runs that used --gates-grid).
    grid_runs = [r for r in sb["runs"] if r.get("by_gate_combo")]
    if grid_runs:
        lines.append("")
        lines.append("## F1/F2 Gate Grid")
        for r in grid_runs:
            lines.append(f"### {r['file']}")
            lines.append("")
            lines.append("| combo | selected | applied | rate | resolved | resolved% | cost$ | wall(s) |")
            lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
            for combo, slot in sorted(r["by_gate_combo"].items()):
                lines.append(
                    f"| {combo} | {slot.get('selected',0)} | {slot.get('applied',0)} | "
                    f"{slot.get('applied_rate',0):.0%} | {slot.get('resolved',0)} | "
                    f"{slot.get('resolved_rate',0):.0%} | "
                    f"${slot.get('cost_usd',0):.3f} | {slot.get('wall_time_sec',0):.1f} |"
                )
            # defensive impact: F1 on vs F1 off, F2 on vs F2 off
            bgc = r["by_gate_combo"]
            def _avg(keys: list[str], field: str) -> float:
                vals = [bgc[k].get(field, 0) for k in keys if k in bgc]
                return round(sum(vals) / len(vals), 3) if vals else 0.0

            f1_on_rate = _avg(["f1_on_f2_on", "f1_on_f2_off"], "applied_rate")
            f1_off_rate = _avg(["f1_off_f2_on", "f1_off_f2_off"], "applied_rate")
            f2_on_rate = _avg(["f1_on_f2_on", "f1_off_f2_on"], "applied_rate")
            f2_off_rate = _avg(["f1_on_f2_off", "f1_off_f2_off"], "applied_rate")
            if any(k in bgc for k in ("f1_on_f2_on", "f1_off_f2_on", "f1_on_f2_off", "f1_off_f2_off")):
                lines.append("")
                lines.append("#### Defensive impact (applied rate)")
                lines.append(f"- F1 on→off: {f1_on_rate:.0%} → {f1_off_rate:.0%} (delta {f1_on_rate - f1_off_rate:+.0%})")
                lines.append(f"- F2 on→off: {f2_on_rate:.0%} → {f2_off_rate:.0%} (delta {f2_on_rate - f2_off_rate:+.0%})")

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


# === task-25 B3: cross-repo harness diff =====================================
#
# `--compare <other-repo>` で他リポの `.claude/` と structural diff を取る。
# 設計の前提:
#   - read-only (両 repo を absolute に書き換えない)
#   - 標準 library のみ (hashlib / os / pathlib)
#   - default で runtime-only file (state / cache / .gitignore'd marker) を除外
#
# 出力 mode:
#   summary (default): 件数 + 代表 file 列挙 (top 20)
#   detail:           全 file path を列挙 (大規模 diff 用)
#   json:             machine-readable
#
# include filter:
#   {hooks,rules,skills,commands,templates,settings,all} default=all
#   all 以外を選んだ場合は `.claude/<category>/...` 配下のみ比較

# 比較対象から外す path pattern (runtime-only / state / cache)。
# `.claude/<root>` からの相対 path で match する。
_IGNORE_PATTERNS: tuple[str, ...] = (
    ".session-help-shown",  # SessionStart marker
    ".workflow-state/",     # workflow_guard state (SCHEMA.md 除く全 json/cleared)
    ".gateguard-state/",
    ".taskguard-state/",
    ".failure-window/",
    ".confidence-gate-state/",
    ".compaction-state/",
    "logs/",                # session logs
    ".DS_Store",            # macOS
)

# `--compare-include` で許可される category と `.claude/` 配下 path の対応。
_INCLUDE_MAP: dict[str, tuple[str, ...]] = {
    "hooks": ("hooks/",),
    "rules": ("rules/",),
    "skills": ("skills/",),
    "commands": ("commands/",),
    "templates": ("templates/",),
    "settings": ("settings.json", "settings.local.json", "harness-config.yml", "mode.yml"),
    "all": (),  # 全 path
}


def _is_ignored_relpath(rel: str) -> bool:
    """`.claude/` 相対 path が runtime-only path か判定。"""
    for pat in _IGNORE_PATTERNS:
        if pat.endswith("/"):
            if rel.startswith(pat):
                # SCHEMA.md / bypass.log.template / .gitignore は track 対象なので残す
                if rel.endswith("/SCHEMA.md") or rel.endswith("/bypass.log.template") or rel.endswith("/.gitignore"):
                    return False
                return True
        else:
            if rel == pat or rel.endswith("/" + pat):
                return True
    return False


def _is_included(rel: str, includes: set[str]) -> bool:
    """`--compare-include` 指定された category に rel path が該当するか。"""
    if "all" in includes or not includes:
        return True
    for cat in includes:
        prefixes = _INCLUDE_MAP.get(cat, ())
        for pre in prefixes:
            if pre.endswith("/"):
                if rel.startswith(pre):
                    return True
            else:
                if rel == pre:
                    return True
    return False


def _scan_claude_tree(claude_root: Path, includes: set[str]) -> dict[str, dict]:
    """`<claude_root>/.claude/` 配下を再帰探索し file metadata dict を返す。

    返り値: {rel_path: {sha256, size, mtime}}
      rel_path は `.claude/` を含まない (例: `hooks/observe.sh`)。
    """
    out: dict[str, dict] = {}
    base = claude_root / ".claude"
    if not base.is_dir():
        return out
    for dirpath, dirnames, filenames in os.walk(base):
        # symlink loops / .git 系を念のため除外
        dirnames[:] = [d for d in dirnames if not d.startswith(".git")]
        for fn in filenames:
            full = Path(dirpath) / fn
            try:
                rel = str(full.relative_to(base))
            except ValueError:
                continue
            if _is_ignored_relpath(rel):
                continue
            if not _is_included(rel, includes):
                continue
            try:
                st = full.stat()
                # 大きすぎる file (>5MB) は size/mtime のみ、hash は skip
                if st.st_size > 5 * 1024 * 1024:
                    h = "(skipped: large file)"
                else:
                    h = hashlib.sha256(full.read_bytes()).hexdigest()
            except OSError:
                continue
            out[rel] = {
                "sha256": h,
                "size": st.st_size,
                "mtime": st.st_mtime,
            }
    return out


def compare_harness(
    source_root: Path,
    target_root: Path,
    includes: set[str],
) -> dict:
    """source / target の `.claude/` を比較し structural diff dict を返す。

    出力 key:
      source_path / target_path: 実 path (絶対)
      source_count / target_count / source_kb / target_kb
      missing_in_target: source のみに存在する file list
      missing_in_source: target のみに存在する file list
      content_drift: 両方に存在するが hash 不一致 (size / mtime delta 付き)
      clean: 両方に存在し hash 一致
      total_clean / total_drift / total_missing_target / total_missing_source
    """
    src_files = _scan_claude_tree(source_root, includes)
    tgt_files = _scan_claude_tree(target_root, includes)

    src_keys = set(src_files.keys())
    tgt_keys = set(tgt_files.keys())

    missing_in_target = sorted(src_keys - tgt_keys)
    missing_in_source = sorted(tgt_keys - src_keys)
    common = sorted(src_keys & tgt_keys)

    drift: list[dict] = []
    clean: list[str] = []
    for rel in common:
        s = src_files[rel]
        t = tgt_files[rel]
        if s["sha256"] != t["sha256"]:
            mtime_delta_sec = abs(s["mtime"] - t["mtime"])
            mtime_delta_days = round(mtime_delta_sec / 86400, 2)
            drift.append({
                "path": rel,
                "source_size": s["size"],
                "target_size": t["size"],
                "size_delta": t["size"] - s["size"],
                "mtime_delta_days": mtime_delta_days,
            })
        else:
            clean.append(rel)

    src_kb = round(sum(f["size"] for f in src_files.values()) / 1024, 1)
    tgt_kb = round(sum(f["size"] for f in tgt_files.values()) / 1024, 1)

    return {
        "source_path": str((source_root / ".claude").resolve()),
        "target_path": str((target_root / ".claude").resolve()),
        "source_count": len(src_files),
        "target_count": len(tgt_files),
        "source_kb": src_kb,
        "target_kb": tgt_kb,
        "includes": sorted(includes),
        "missing_in_target": missing_in_target,
        "missing_in_source": missing_in_source,
        "content_drift": drift,
        "clean": clean,
        "total_clean": len(clean),
        "total_drift": len(drift),
        "total_missing_target": len(missing_in_target),
        "total_missing_source": len(missing_in_source),
    }


def fmt_compare(result: dict, fmt: str = "summary") -> str:
    """compare_harness の result を human-readable markdown に format。"""
    lines: list[str] = []
    lines.append("[harness-audit --compare]")
    lines.append(
        f"Source: {result['source_path']} "
        f"({result['source_count']} files, {result['source_kb']} KB)"
    )
    lines.append(
        f"Target: {result['target_path']} "
        f"({result['target_count']} files, {result['target_kb']} KB)"
    )
    if result["includes"]:
        lines.append(f"Includes: {', '.join(result['includes'])}")
    lines.append("")

    # default top 20、detail mode で全件表示
    list_limit = None if fmt == "detail" else 20

    # Missing in target
    lines.append(f"## Missing in target (source only): {result['total_missing_target']} files")
    missing_t = result["missing_in_target"]
    shown = missing_t if list_limit is None else missing_t[:list_limit]
    for p in shown:
        lines.append(f"  - .claude/{p}")
    if list_limit is not None and len(missing_t) > list_limit:
        lines.append(f"  ... and {len(missing_t) - list_limit} more (use --compare-format detail)")
    lines.append("")

    # Missing in source
    lines.append(f"## Missing in source (target only): {result['total_missing_source']} files")
    missing_s = result["missing_in_source"]
    shown = missing_s if list_limit is None else missing_s[:list_limit]
    for p in shown:
        lines.append(f"  - .claude/{p}")
    if list_limit is not None and len(missing_s) > list_limit:
        lines.append(f"  ... and {len(missing_s) - list_limit} more (use --compare-format detail)")
    lines.append("")

    # Content drift
    lines.append(f"## Content drift (same path, different hash): {result['total_drift']} files")
    drift = result["content_drift"]
    shown_drift = drift if list_limit is None else drift[:list_limit]
    for d in shown_drift:
        delta = d["size_delta"]
        sign = "+" if delta >= 0 else ""
        lines.append(
            f"  - .claude/{d['path']} "
            f"(source: {d['source_size']}B / target: {d['target_size']}B / "
            f"size delta: {sign}{delta}B / mtime delta: {d['mtime_delta_days']}d)"
        )
    if list_limit is not None and len(drift) > list_limit:
        lines.append(f"  ... and {len(drift) - list_limit} more (use --compare-format detail)")
    lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append(f"  - install.sh --update sync 推奨 file 数: {result['total_missing_target']} "
                 "(missing in target が新規追加対象)")
    lines.append(f"  - 真の drift (両 repo で独立進化): {result['total_drift']} (要 manual review)")
    lines.append(f"  - clean: {result['total_clean']} files (両 repo identical)")

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="出力を JSON にする")
    ap.add_argument("--window", type=int, default=100, help="観察ログの集計件数")
    ap.add_argument("--swe-bench", action="store_true", help="SWE-bench Lite leaderboard markdown のみ出力")
    ap.add_argument("--router", action="store_true", help="Agent-router dispatch.jsonl leaderboard markdown のみ出力")
    ap.add_argument("--router-homunculus-root", default=None, help="Override homunculus_root for the --router subcommand (mainly for tests)")
    # task-25 B3: cross-repo compare
    ap.add_argument(
        "--compare",
        action="append",
        default=None,
        help="他リポの .claude/ root と structural diff を取る (task-25 B3、複数指定可)",
    )
    ap.add_argument(
        "--compare-format",
        choices=["summary", "detail", "json"],
        default="summary",
        help="--compare の出力 format (default: summary)",
    )
    ap.add_argument(
        "--compare-include",
        action="append",
        choices=list(_INCLUDE_MAP.keys()),
        default=None,
        help="--compare の比較対象 category (default: all、複数指定可)",
    )
    ap.add_argument(
        "--compare-source",
        default=None,
        help="--compare の source root (default: cwd)",
    )
    # task-25 C2 / C3 toggles
    ap.add_argument(
        "--no-stale-drafts",
        action="store_true",
        help="stale draft (>=90 days unapproved) section を skip (task-25 C2)",
    )
    ap.add_argument(
        "--stale-drafts-threshold",
        type=int,
        default=90,
        help="stale draft 判定の閾値日数 (default: 90)",
    )
    ap.add_argument(
        "--no-settings-drift",
        action="store_true",
        help="settings.local.json drift section を skip (task-25 C3)",
    )
    args = ap.parse_args()

    # --compare branch (task-25 B3)
    if args.compare:
        source_root = Path(args.compare_source).resolve() if args.compare_source else ROOT
        if not (source_root / ".claude").is_dir():
            print(
                f"error: source .claude/ not found at {source_root}/.claude",
                file=sys.stderr,
            )
            return 2

        includes = set(args.compare_include) if args.compare_include else {"all"}
        results: list[dict] = []
        had_error = False
        for tgt_arg in args.compare:
            target_root = Path(tgt_arg).expanduser().resolve()
            if not target_root.exists():
                print(f"error: target path does not exist: {tgt_arg}", file=sys.stderr)
                had_error = True
                continue
            if not (target_root / ".claude").is_dir():
                print(
                    f"error: target .claude/ not found at {target_root}/.claude",
                    file=sys.stderr,
                )
                had_error = True
                continue
            results.append(compare_harness(source_root, target_root, includes))

        if had_error and not results:
            return 2

        # output
        if args.compare_format == "json" or args.json:
            payload = results[0] if len(results) == 1 else {"comparisons": results}
            print(json.dumps(payload, indent=2, ensure_ascii=False))
        else:
            for i, r in enumerate(results):
                if i > 0:
                    print("")
                    print("---")
                    print("")
                print(fmt_compare(r, fmt=args.compare_format))
        return 0 if not had_error else 2

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
    # task-32: tail_jsonl 返り値 dict 化に対応 (caller 1 箇所のみ修正)
    tj = tail_jsonl(obs_path, args.window) if obs_path else {
        "records": [],
        "skipped_lines": 0,
        "total_lines": 0,
        "cascade_suspected": False,
        "max_consecutive_skips": 0,
    }
    records = tj["records"]
    report = {
        "generated": datetime.now().isoformat(timespec="seconds"),
        "project_hash": project_hash(),
        "observations_path": str(obs_path) if obs_path else None,
        "window": args.window,
        "observations": summarize_observations(records),
        # task-32: observation pipeline 健全性指標
        "observation_health": {
            "skipped_lines": tj["skipped_lines"],
            "total_lines": tj["total_lines"],
            "cascade_suspected": tj["cascade_suspected"],
            "max_consecutive_skips": tj["max_consecutive_skips"],
            "cascade_threshold": _cascade_threshold(),
        },
        "gateguard": gateguard_breakdown(),
        "taskguard": count_state_dir(ROOT / _cfg("taskguard_state_dir")),
        "failure_window": failure_window_summary(),
        "confidence_gate": confidence_gate_breakdown(),
        "bypass_log": bypass_log_summary(),
        "swe_bench": swe_bench_breakdown(),
        "router": router_breakdown(),
    }
    # task-25 C2 / C3: opt-out flags
    if not args.no_stale_drafts:
        report["stale_drafts"] = stale_drafts_summary(threshold_days=args.stale_drafts_threshold)
    if not args.no_settings_drift:
        report["settings_drift"] = settings_drift_check()

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
