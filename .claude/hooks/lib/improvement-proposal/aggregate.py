#!/usr/bin/env python3
# aggregate.py — improvement-proposal の集計 + heuristics + dedup ロジック
#
# 役割:
#   observations.jsonl / hook state を集計し、heuristics に基づき
#   改善提案を生成、dedup state を考慮して stderr に出力する。
#
# 呼び出し方法:
#   python3 .claude/hooks/lib/improvement-proposal/aggregate.py
#
# 環境変数で設定を受け取る (improvement-proposal.sh orchestrator が export):
#   HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS
#   HC_IMPROVEMENT_PROPOSAL_MAX_COUNT
#   HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS
#   HC_GATEGUARD_STATE_DIR
#   HC_TASKGUARD_STATE_DIR
#   HC_FAILURE_WINDOW_DIR
#   HC_CONFIDENCE_STATE_DIR
#   HC_HOMUNCULUS_ROOT
#   ECC_IMPROVEMENT_PROPOSAL_TEST_NOW
#   ABS_STATE_DIR
#   PROJ_ROOT
#   HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE
#   HC_OBSERVE_PATH (test override)
#
# 出力: 集計結果を stderr に流す (caller は CACHE_TMP に capture して cache 書き込み)

import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

# === 設定読み込み ===
def env_int(name, default):
    try:
        return int(os.environ.get(name, "") or default)
    except (TypeError, ValueError):
        return default

LOOKBACK_DAYS = env_int("HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS", 7)
MAX_COUNT = env_int("HC_IMPROVEMENT_PROPOSAL_MAX_COUNT", 3)
DEDUP_HOURS = env_int("HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS", 24)

PROJ_ROOT = Path(os.environ.get("PROJ_ROOT", os.getcwd()))
STATE_DIR = Path(os.environ.get("ABS_STATE_DIR", str(PROJ_ROOT / ".claude" / ".improvement-proposal-state")))

def _abs(rel_or_abs):
    p = Path(rel_or_abs)
    if p.is_absolute():
        return p
    return PROJ_ROOT / p

GATEGUARD_DIR = _abs(os.environ.get("HC_GATEGUARD_STATE_DIR", ".claude/.gateguard-state"))
TASKGUARD_DIR = _abs(os.environ.get("HC_TASKGUARD_STATE_DIR", ".claude/.taskguard-state"))
FAILURE_DIR   = _abs(os.environ.get("HC_FAILURE_WINDOW_DIR", ".claude/.failure-window"))
CONFIDENCE_DIR = _abs(os.environ.get("HC_CONFIDENCE_STATE_DIR", ".claude/.confidence-gate-state"))

homu_raw = os.environ.get("HC_HOMUNCULUS_ROOT") or "~/.claude/homunculus"
HOMUNCULUS = Path(os.path.expanduser(homu_raw))

# === time ref（テスト用に固定可） ===
_now_override = os.environ.get("ECC_IMPROVEMENT_PROPOSAL_TEST_NOW")
if _now_override:
    try:
        NOW = datetime.fromisoformat(_now_override.replace("Z", "+00:00"))
        if NOW.tzinfo is None:
            NOW = NOW.replace(tzinfo=timezone.utc)
    except Exception:
        NOW = datetime.now(timezone.utc)
else:
    NOW = datetime.now(timezone.utc)

CUTOFF = NOW - timedelta(days=LOOKBACK_DAYS)

# === observations.jsonl 探索 ===
def _normalize_remote_url(url):
    s = url.strip()
    m = re.match(r"^git@([^:]+):(.*)$", s)
    if m:
        s = f"https://{m.group(1)}/{m.group(2)}"
    if s.endswith(".git"):
        s = s[:-4]
    return s

def project_hash():
    try:
        out = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            stderr=subprocess.DEVNULL, text=True, cwd=str(PROJ_ROOT),
        ).strip()
        if not out:
            return None
        return hashlib.sha256(_normalize_remote_url(out).encode()).hexdigest()[:12]
    except Exception:
        return None

def find_observations():
    # test override: HC_OBSERVE_PATH で直接指定可能 (smoke test 用)
    override = os.environ.get("HC_OBSERVE_PATH")
    if override:
        p = Path(override)
        if p.exists() and p.stat().st_size > 0:
            return p
        return None
    ph = project_hash()
    candidates = []
    if ph:
        candidates.append(HOMUNCULUS / "projects" / ph / "observations.jsonl")
    candidates.append(HOMUNCULUS / "observations.jsonl")
    for p in candidates:
        if p.exists() and p.stat().st_size > 0:
            return p
    return None

def parse_ts(s):
    if not s:
        return None
    try:
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None

def load_recent_observations(path, cutoff):
    """末尾から逆向きに読み、cutoff より古くなったら停止。tail-like 動作。"""
    if not path or not path.exists():
        return []
    out = []
    try:
        # ファイルが大きいときは末尾チャンクのみ読む
        size = path.stat().st_size
        chunk = min(size, 4 * 1024 * 1024)  # max 4MB
        with path.open("rb") as f:
            f.seek(size - chunk)
            data = f.read().decode("utf-8", errors="replace")
        lines = data.splitlines()
        if chunk < size and lines:
            # 最初の行は途中で切れている可能性があるので捨てる
            lines = lines[1:]
        for line in lines:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            ts = parse_ts(rec.get("ts") or rec.get("timestamp"))
            if ts and ts < cutoff:
                continue
            out.append(rec)
    except Exception:
        return []
    return out

# === 集計関数群 ===
def aggregate_observations(records):
    bash_deny = 0
    edit_deny = 0
    block_count = 0
    error_count = 0
    tool_errors = Counter()
    tools = Counter()
    timeouts = 0
    sessions = set()

    for r in records:
        tool = r.get("tool") or r.get("tool_name") or "unknown"
        tools[tool] += 1

        raw = r.get("raw") or {}
        if isinstance(raw, dict):
            sid = raw.get("session_id")
            if sid:
                sessions.add(sid)

        resp = r.get("tool_response") or (raw.get("tool_response") if isinstance(raw, dict) else None) or {}
        if isinstance(resp, dict):
            text_blob = json.dumps(resp).lower()
            if resp.get("is_error") or resp.get("decision") == "block":
                error_count += 1
                tool_errors[tool] += 1
                if resp.get("decision") == "block":
                    block_count += 1
            if "permission" in text_blob and ("denied" in text_blob or "deny" in text_blob):
                if tool == "Bash":
                    bash_deny += 1
                elif tool in ("Edit", "Write"):
                    edit_deny += 1
            if "timed out" in text_blob or "timeout" in text_blob:
                timeouts += 1

    return {
        "total": len(records),
        "tools": dict(tools),
        "tool_errors": dict(tool_errors),
        "bash_deny": bash_deny,
        "edit_deny": edit_deny,
        "blocks": block_count,
        "errors": error_count,
        "timeouts": timeouts,
        "sessions": len(sessions),
    }

def count_cleared(d):
    if not d.is_dir():
        return 0
    return sum(1 for p in d.iterdir() if p.is_file() and p.name.endswith(".cleared"))

def gateguard_recent_count(d, cutoff):
    """直近 cutoff 以降に作成 / 更新された .cleared 数（mtime ベース）。"""
    if not d.is_dir():
        return 0
    n = 0
    cutoff_ts = cutoff.timestamp()
    for p in d.iterdir():
        if not p.is_file() or not p.name.endswith(".cleared"):
            continue
        try:
            if p.stat().st_mtime >= cutoff_ts:
                n += 1
        except Exception:
            continue
    return n

def confidence_breakdown(d, cutoff):
    out = {"bypasses": 0, "recent_reasons": []}
    if not d.is_dir():
        return out
    log = d / "bypass.log"
    if not log.exists():
        return out
    try:
        lines = [ln.strip() for ln in log.read_text().splitlines() if ln.strip()]
    except Exception:
        return out
    recent = []
    for ln in lines:
        # format: "<ts>\t<reason>"
        parts = ln.split("\t", 1)
        if len(parts) != 2:
            continue
        ts = parse_ts(parts[0])
        if ts and ts >= cutoff:
            recent.append((parts[0], parts[1]))
    out["bypasses"] = len(recent)
    out["recent_reasons"] = recent[-3:]
    return out

def failure_window_active(d):
    if not d.is_dir():
        return 0
    active = 0
    for log in d.glob("*.log"):
        try:
            lines = [ln.strip() for ln in log.read_text().splitlines() if ln.strip()]
        except Exception:
            continue
        if len(lines) >= 3 and len(set(lines[-3:])) == 1:
            active += 1
    return active

def router_dispatch_breakdown(cutoff):
    """global agent-router-history.json から fallback rate を計算。"""
    p = Path.home() / ".claude" / "agent-router-history.json"
    out = {"total": 0, "general_purpose": 0, "general_rate": 0.0}
    if not p.exists():
        return out
    try:
        data = json.loads(p.read_text())
    except Exception:
        return out
    if not isinstance(data, list):
        return out
    total = 0
    general = 0
    for e in data:
        ts = parse_ts(e.get("ts"))
        if ts and ts < cutoff:
            continue
        total += 1
        if (e.get("dispatched") or "").strip() == "general-purpose":
            general += 1
    out["total"] = total
    out["general_purpose"] = general
    out["general_rate"] = round(general / total, 3) if total else 0.0
    return out

# === heuristics: 提案生成 ===
# 各エントリは (id, severity_priority, message)。priority 高い順に最大 MAX_COUNT 件採用。
def generate_proposals():
    obs_path = find_observations()
    records = load_recent_observations(obs_path, CUTOFF) if obs_path else []
    agg = aggregate_observations(records)

    gg_recent = gateguard_recent_count(GATEGUARD_DIR, CUTOFF)
    tg_total = count_cleared(TASKGUARD_DIR)
    cg = confidence_breakdown(CONFIDENCE_DIR, CUTOFF)
    fw_active = failure_window_active(FAILURE_DIR)
    rt = router_dispatch_breakdown(CUTOFF)

    proposals = []

    # 1. Bash deny 多 → Agent 委譲が漏れている
    if agg["bash_deny"] >= 5:
        proposals.append((
            "bash-deny", 90,
            f"Bash deny {agg['bash_deny']} 件 → Agent tool 経由の委譲が漏れている可能性。"
            "次回は run_in_background:true で必ず Agent 起動を。"
        ))
    # 2. Edit/Write deny 多 → delegation-guard で弾かれている
    if agg["edit_deny"] >= 3:
        proposals.append((
            "edit-deny", 85,
            f"Edit/Write deny {agg['edit_deny']} 件 → メイン直接編集禁止域。"
            "Agent tool 経由で委譲するか、保護パスを再確認。"
        ))
    # 3. GateGuard cleared が多い → 事実材料未提示で block を多く受けた可能性
    if gg_recent >= 5:
        proposals.append((
            "gateguard-block", 80,
            f"GateGuard cleared {gg_recent} 件 → Edit/Write 直前の事実材料提示忘れ。"
            "importer/caller/data/quote の 4 点を summary に。"
        ))
    # 4. Confidence bypass 多 → 抽出 or 自信付与の問題
    if cg["bypasses"] >= 5:
        proposals.append((
            "confidence-bypass", 75,
            f"Confidence bypass {cg['bypasses']} 件 → 抽出ロジック改善の余地。"
            "docs/CONFIDENCE-GATE.md 参照、subagent prompt に confidence:0.X 明記を。"
        ))
    # 5. failure-loop active → 同種エラーで止まっている
    if fw_active >= 1:
        proposals.append((
            "failure-loop", 95,
            f"Failure loop {fw_active} session 検出 → 同種エラーで止まっている。"
            "/agent-introspect で 4-phase Capture-Audit-Diff-Fix を実行を。"
        ))
    # 6. Router fallback rate 高 → dispatch table 拡張余地
    if rt["total"] >= 5 and rt["general_rate"] >= 0.6:
        proposals.append((
            "router-fallback", 60,
            f"Agent router で general-purpose 比率 {int(rt['general_rate']*100)}% "
            f"({rt['general_purpose']}/{rt['total']}) → dispatch-table 拡張、"
            "または LLM fallback を検討。"
        ))
    # 7. TaskGuard bypass 多 → bypass 常用化
    if tg_total >= 5:
        proposals.append((
            "taskguard-bypass", 55,
            f"TaskGuard bypass {tg_total} 件 → bypass の常用化。"
            "draft/task の同期ルールを再確認。"
        ))
    # 8. timeouts 多 → hook が重い
    if agg["timeouts"] >= 3:
        proposals.append((
            "hook-timeouts", 50,
            f"Hook timeouts {agg['timeouts']} 件 → hook 内処理が重い可能性。"
            "harness-config.yml の timeout か hook ロジックを見直し。"
        ))
    # 9. errors 多 → 一般的な失敗多
    if agg["errors"] >= 10 and agg["total"] >= 50:
        rate = agg["errors"] / agg["total"]
        if rate >= 0.10:
            proposals.append((
                "error-rate-high", 40,
                f"Tool error rate {int(rate*100)}% ({agg['errors']}/{agg['total']}) → "
                "tool 利用の前提誤りが多い可能性。/harness-audit で詳細確認を。"
            ))

    # priority 高い順、ID 重複排除
    seen = set()
    proposals.sort(key=lambda x: -x[1])
    selected = []
    for pid, prio, msg in proposals:
        if pid in seen:
            continue
        seen.add(pid)
        selected.append((pid, msg))
        if len(selected) >= MAX_COUNT:
            break
    return selected, len(records)

# === dedup state ===
DEDUP_PATH = STATE_DIR / "last_shown.json"

def load_dedup():
    if not DEDUP_PATH.exists():
        return {}
    try:
        return json.loads(DEDUP_PATH.read_text())
    except Exception:
        return {}

def save_dedup(state):
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = DEDUP_PATH.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state, ensure_ascii=False, sort_keys=True))
        tmp.replace(DEDUP_PATH)
    except Exception:
        pass

def filter_dedup(props, dedup_state):
    cutoff = NOW - timedelta(hours=DEDUP_HOURS)
    keep = []
    new_state = dict(dedup_state)
    for pid, msg in props:
        last = parse_ts(dedup_state.get(pid))
        if last and last >= cutoff:
            continue
        keep.append((pid, msg))
        new_state[pid] = NOW.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return keep, new_state

# observations count を保存先 file に書き出し (cache metadata 用)
def _emit_obs_count(n):
    p = os.environ.get("HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE")
    if not p:
        return
    try:
        Path(p).write_text(str(n))
    except Exception:
        pass

# === main ===
def main():
    try:
        proposals, obs_count = generate_proposals()
        _emit_obs_count(obs_count)
        if not proposals:
            sys.exit(0)

        dedup_state = load_dedup()
        proposals, new_state = filter_dedup(proposals, dedup_state)
        if not proposals:
            sys.exit(0)

        # 提案 1+ 件 → stderr に出力
        print(f"[harness] \U0001f4a1 Improvement proposals (last {LOOKBACK_DAYS} days):", file=sys.stderr)
        for i, (pid, msg) in enumerate(proposals, start=1):
            print(f"[harness]   {i}. {msg}", file=sys.stderr)
        print(
            "[harness] (これらは提案であり block しません。無視して進めて構いません。"
            "/harness-audit で詳細確認可)",
            file=sys.stderr,
        )

        save_dedup(new_state)
    except SystemExit:
        raise
    except Exception:
        # fail-open: traceback は出さずに静かに終わる
        pass

if __name__ == "__main__":
    main()
