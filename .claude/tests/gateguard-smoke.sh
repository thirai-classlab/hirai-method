#!/usr/bin/env bash
# gateguard-smoke.sh — task-22 W3 smoke for gateguard.sh (F1 事前ゲート)
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#
# 対象 hook:
#   .claude/hooks/gateguard.sh
#
# 検証範囲 (5 ケース):
#   Case 1: 初回 Edit (cleared state 不在) → BLOCK + 事実材料要求 reason
#   Case 2: 同 file 2 回目 Edit (cleared marker 存在) → PASS
#   Case 3: 破壊的 Bash (rm -rf) 初回 → BLOCK + rollback/影響範囲/逐語要求
#   Case 4: ECC_GATEGUARD=off で初回 Edit → PASS (素通し)
#   Case 5: 除外 path (CLAUDE.md) への Edit → PASS (hook hardcoded exclusion)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 教訓)
#   - state_dir は独立した /tmp/ 配下に隔離して既存 state を汚染しない
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE をクリア
#
# 実行:
#   bash .claude/tests/gateguard-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/gateguard.sh"

# clean main agent context
unset CLAUDE_HARNESS_ROLE
unset ECC_GATEGUARD
unset ECC_F1_OFF

# 独立 state_dir (既存 .gateguard-state を触らない)
TMP_STATE_DIR="$(mktemp -d /tmp/gateguard-smoke-state.XXXXXX)"
trap 'rm -rf "$TMP_STATE_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# Edit JSON 入力を組み立てる
json_edit_input() {
  local fp="$1"
  FP="$fp" python3 -c '
import json, os
print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": os.environ["FP"]}}))
'
}

# Bash JSON 入力を組み立てる
json_bash_input() {
  local cmd="$1"
  CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))
'
}

# stdout (1 行 JSON) から decision フィールド抽出
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

# stdout から reason 文字列抽出
extract_reason() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("reason", ""))
except Exception:
    print("")
' 2>/dev/null
}

# === Case 1: 初回 Edit → BLOCK ===
case1_initial_edit_blocked() {
  local label="Case 1: initial Edit (no cleared state) → BLOCK"
  local fp="/tmp/gateguard-smoke-case1.ts"
  local out decision reason
  out=$(json_edit_input "$fp" | HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Edit 2>/dev/null)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q "GateGuard"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 2: 2 回目 Edit (cleared marker あり) → PASS ===
case2_cleared_edit_pass() {
  local label="Case 2: 2nd Edit (cleared marker exists) → PASS"
  local fp="/tmp/gateguard-smoke-case2.ts"
  local out decision

  # 1 回目で marker 作成 (BLOCK)
  json_edit_input "$fp" | HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Edit >/dev/null 2>&1

  # 2 回目 — marker 存在で PASS 期待
  out=$(json_edit_input "$fp" | HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Edit 2>/dev/null)
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

# === Case 3: 破壊的 Bash (rm -rf) 初回 → BLOCK ===
case3_destructive_bash_blocked() {
  local label="Case 3: initial 'rm -rf' destructive bash → BLOCK"
  local cmd="rm -rf /tmp/gateguard-smoke-fake-target-$$"
  local out decision reason
  out=$(json_bash_input "$cmd" | HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Bash 2>/dev/null)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q "destructive"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 4: ECC_GATEGUARD=off で初回 Edit → PASS ===
case4_bypass_env_pass() {
  local label="Case 4: ECC_GATEGUARD=off bypass on initial Edit → PASS"
  local fp="/tmp/gateguard-smoke-case4.ts"
  local out decision
  out=$(json_edit_input "$fp" | ECC_GATEGUARD=off HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Edit 2>/dev/null)
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

# === Case 5: 除外 path (CLAUDE.md) への Edit → PASS ===
# hook 内 hardcoded exclusion: */CLAUDE.md|*/README.md|*/.gitignore|*/.env.example etc.
case5_excluded_path_pass() {
  local label="Case 5: excluded path (CLAUDE.md) Edit → PASS"
  # hook が `*/CLAUDE.md` glob で除外判定するため、parent dir を実体として持たせる
  local tmpdir
  tmpdir=$(mktemp -d /tmp/gateguard-smoke-case5.XXXXXX)
  local fp="${tmpdir}/CLAUDE.md"
  local out decision
  out=$(json_edit_input "$fp" | HC_GATEGUARD_STATE_DIR="$TMP_STATE_DIR" bash "$HOOK" Edit 2>/dev/null)
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

printf "===== gateguard-smoke (task-22 W3.1, 5 cases) =====\n\n"

case1_initial_edit_blocked
case2_cleared_edit_pass
case3_destructive_bash_blocked
case4_bypass_env_pass
case5_excluded_path_pass

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
