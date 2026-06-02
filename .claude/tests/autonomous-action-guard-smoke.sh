#!/usr/bin/env bash
# autonomous-action-guard-smoke.sh — task-22 W3 smoke for autonomous-action-guard.sh
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#   docs/draft/loop-auto-progress-enforcement.md §3 W3
#
# 対象 hook:
#   .claude/hooks/autonomous-action-guard.sh (PreToolUse Bash)
#
# 検証範囲 (5 ケース):
#   Case 1: Loop モード + git push origin main → BLOCK (decision=block)
#   Case 2: Loop モード + gh pr create → BLOCK
#   Case 3: Loop モード + vercel --prod → BLOCK
#   Case 4: Normal モード + git push origin main → PASS + additionalContext warning
#   Case 5: Loop モード + ECC_AUTONOMOUS_ACTION_OVERRIDE=1 + git push → PASS + bypass.log 記録
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - HC_MODE env で mode 切替 (.claude/mode.yml に依存しない)
#   - HC_AGENT_MARKER_DIR を空 tmp に向けて subagent 短絡を避ける
#   - bypass.log は live .workflow-state/bypass.log を汚さない方法で検証する
#     (Case 5 では line delta を測る — config-level ON のまま env bypass を発火)
#
# 実行:
#   bash .claude/tests/autonomous-action-guard-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/autonomous-action-guard.sh"

# clean env
unset CLAUDE_HARNESS_ROLE
unset ECC_AUTONOMOUS_ACTION_OVERRIDE
unset HC_AUTONOMOUS_ACTION_ENABLED

TMP_MARKER_DIR="$(mktemp -d /tmp/aag-smoke-marker.XXXXXX)"
trap 'rm -rf "$TMP_MARKER_DIR"' EXIT

COMMON_ENV=(
  "HC_AGENT_MARKER_DIR=${TMP_MARKER_DIR}"
)

# bypass.log は REPO_ROOT/.claude/.workflow-state/bypass.log に集約される設計。
# Case 5 では line delta を測ることで「新規 entry 追加」を検証する。
BYPASS_LOG="$REPO_ROOT/.claude/.workflow-state/bypass.log"

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=()

# Bash JSON input
json_bash_input() {
  local cmd="$1"
  CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))
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

extract_additional_context() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("hookSpecificOutput", {}).get("additionalContext", ""))
except Exception:
    print("")
' 2>/dev/null
}

# === Case 1: Loop + git push origin main → BLOCK ===
# [OBSOLETE: task-39 2026-05-25] git push origin main は自律実行可となり BLOCK されなくなった
# (modes.md 遵守事項 8 緩和)。旧 BLOCK 期待は stale につき skip。
case1_loop_git_push_block() {
  local label="Case 1: Loop + 'git push origin main' → BLOCK [OBSOLETE: task-39]"
  SKIP=$((SKIP + 1))
  printf "  SKIP (obsolete): %s\n" "$label"
}

# === Case 2: Loop + gh pr create → BLOCK ===
# [OBSOLETE: task-39 2026-05-25] gh pr create は自律実行可となり BLOCK されなくなった
# (modes.md 遵守事項 8 緩和)。旧 BLOCK 期待は stale につき skip。
case2_loop_gh_pr_create_block() {
  local label="Case 2: Loop + 'gh pr create' → BLOCK [OBSOLETE: task-39]"
  SKIP=$((SKIP + 1))
  printf "  SKIP (obsolete): %s\n" "$label"
}

# === Case 3: Loop + vercel --prod → BLOCK ===
case3_loop_vercel_prod_block() {
  local label="Case 3: Loop + 'vercel --prod' → BLOCK"
  local cmd="vercel --prod"
  local out decision
  out=$(json_bash_input "$cmd" | HC_MODE=loop env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
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

# === Case 4: Normal + git push origin main → PASS + additionalContext warning ===
# [OBSOLETE: task-39 2026-05-25] git push origin main が緩和され、Normal モードでも
# autonomous-action-guard が当該コマンドに warning context を出さなくなった。
# 旧「Normal で warning context 付与」期待は stale につき skip。
case4_normal_git_push_context_warning() {
  local label="Case 4: Normal + 'git push origin main' → PASS w/ additionalContext [OBSOLETE: task-39]"
  SKIP=$((SKIP + 1))
  printf "  SKIP (obsolete): %s\n" "$label"
}

# === Case 5: Loop + ECC_AUTONOMOUS_ACTION_OVERRIDE=1 → PASS + bypass.log 記録 ===
case5_loop_bypass_env_with_log() {
  local label="Case 5: Loop + ECC_AUTONOMOUS_ACTION_OVERRIDE=1 → PASS + bypass.log entry"
  local cmd="git push origin main"
  local log_before=0
  if [ -f "$BYPASS_LOG" ]; then
    log_before=$(wc -l < "$BYPASS_LOG" | tr -d ' ')
  fi
  local out decision
  out=$(json_bash_input "$cmd" | HC_MODE=loop ECC_AUTONOMOUS_ACTION_OVERRIDE=1 ECC_BYPASS_REASON="smoke test" env "${COMMON_ENV[@]}" bash "$HOOK" 2>/dev/null)
  decision=$(extract_decision "$out")

  local log_after=0
  if [ -f "$BYPASS_LOG" ]; then
    log_after=$(wc -l < "$BYPASS_LOG" | tr -d ' ')
  fi
  local delta=$((log_after - log_before))

  if [ "$decision" != "block" ] && [ "$delta" -ge 1 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s (bypass.log delta=%d)\n" "$label" "$delta"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision log_delta=$delta)")
    printf "  FAIL: %s\n    decision: %s\n    log_delta: %d\n    out: %s\n" "$label" "$decision" "$delta" "$out"
  fi
}

printf "===== autonomous-action-guard-smoke (task-22 W3.4, 5 cases) =====\n\n"

case1_loop_git_push_block
case2_loop_gh_pr_create_block
case3_loop_vercel_prod_block
case4_normal_git_push_context_warning
case5_loop_bypass_env_with_log

TOTAL=$((PASS + FAIL + SKIP))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
printf "SKIP: %d / %d (obsolete: task-39)\n" "$SKIP" "$TOTAL"

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
