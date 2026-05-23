#!/usr/bin/env bash
# confidence-gate-smoke.sh — task-22 W3 smoke for confidence-gate.sh (F3)
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#
# 対象 hook:
#   .claude/hooks/confidence-gate.sh (SubagentStop)
#
# 検証範囲 (5 ケース):
#   Case 1: transcript final assistant text に "confidence: 0.9" → PASS
#   Case 2: "confidence: 0.3" (閾値 0.6 未満) → BLOCK
#   Case 3: confidence 未記載 + major subagent (agent_type=general-purpose) → BLOCK
#   Case 4: confidence 未記載 + minor sidechain (allowlist 外) → PASS (fail-open)
#   Case 5: ECC_CONFIDENCE_GATE=off + 未記載 → PASS (bypass)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - 各ケースで mock transcript JSONL を tmp に作成
#   - bypass marker / log は HC_CONFIDENCE_STATE_DIR で隔離
#   - HC_CONFIDENCE_THRESHOLD=0.6 (default) を前提
#
# 実行:
#   bash .claude/tests/confidence-gate-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/confidence-gate.sh"

# clean env
unset ECC_CONFIDENCE_GATE
unset ECC_F3_OFF
unset HC_CONFIDENCE_REQUIRED

# tmp transcript + state dir (live state を汚さない)
TMP_DIR="$(mktemp -d /tmp/confidence-gate-smoke.XXXXXX)"
TMP_STATE_DIR="${TMP_DIR}/state"
mkdir -p "$TMP_STATE_DIR"

trap 'rm -rf "$TMP_DIR"' EXIT

COMMON_ENV=(
  "HC_CONFIDENCE_STATE_DIR=${TMP_STATE_DIR}"
  "HC_CONFIDENCE_THRESHOLD=0.6"
  "HC_CONFIDENCE_REQUIRED=true"
)

PASS=0
FAIL=0
FAILED_CASES=()

# transcript JSONL に assistant text を 1 件書く
make_transcript() {
  local path="$1"
  local text="$2"
  TEXT="$text" python3 -c '
import json, os, sys
rec = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [{"type": "text", "text": os.environ["TEXT"]}]
    },
    "uuid": "a-smoke"
}
print(json.dumps(rec))
' > "$path"
}

# hook input JSON 組み立て (SubagentStop)
hook_input() {
  local transcript="$1"
  local agent_type="$2"
  TP="$transcript" AT="$agent_type" python3 -c '
import json, os
print(json.dumps({
    "session_id": "smoke",
    "transcript_path": os.environ["TP"],
    "agent_type": os.environ["AT"]
}))
'
}

extract_decision() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("decision", "none"))
except Exception:
    print("parse_error")
' 2>/dev/null
}

# === Case 1: confidence 0.9 → PASS ===
case1_high_confidence_pass() {
  local label="Case 1: confidence: 0.9 (>= 0.6) → PASS"
  local tp="${TMP_DIR}/case1.jsonl"
  make_transcript "$tp" "実装完了。全 build/test PASS。confidence: 0.9"
  local out decision
  out=$(hook_input "$tp" "general-purpose" | env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 2: confidence 0.3 → BLOCK ===
case2_low_confidence_block() {
  local label="Case 2: confidence: 0.3 (< 0.6) → BLOCK"
  local tp="${TMP_DIR}/case2.jsonl"
  make_transcript "$tp" "途中まで完了。一部 test 未確認。confidence: 0.3"
  local out decision
  out=$(hook_input "$tp" "general-purpose" | env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" = "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 3: confidence 未記載 + major subagent (general-purpose) → BLOCK ===
case3_missing_major_subagent_block() {
  local label="Case 3: confidence missing, agent_type=general-purpose → BLOCK"
  local tp="${TMP_DIR}/case3.jsonl"
  make_transcript "$tp" "実装完了したけど自己評価なし"
  local out decision
  out=$(hook_input "$tp" "general-purpose" | env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" = "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 4: confidence 未記載 + minor sidechain (allowlist 外) → PASS (fail-open) ===
# agent_type が general-purpose / Explore / Task 以外、かつ transcript_path に /subagents/ を
# 含まない場合、HC_CONFIDENCE_MAJOR_AGENT_ONLY=true (default) で fail-open
case4_missing_minor_sidechain_pass() {
  local label="Case 4: confidence missing, agent_type=other (minor sidechain) → PASS"
  local tp="${TMP_DIR}/case4.jsonl"
  make_transcript "$tp" "短い tool-use only sidechain reply"
  local out decision
  out=$(hook_input "$tp" "some-other-light-agent" | env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 5: ECC_CONFIDENCE_GATE=off + 未記載 → PASS ===
case5_bypass_env_pass() {
  local label="Case 5: ECC_CONFIDENCE_GATE=off + confidence missing → PASS"
  local tp="${TMP_DIR}/case5.jsonl"
  make_transcript "$tp" "bypass test - no confidence here"
  local out decision
  out=$(hook_input "$tp" "general-purpose" | ECC_CONFIDENCE_GATE=off env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

printf "===== confidence-gate-smoke (task-22 W3.3, 5 cases) =====\n\n"

case1_high_confidence_pass
case2_low_confidence_block
case3_missing_major_subagent_block
case4_missing_minor_sidechain_pass
case5_bypass_env_pass

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
