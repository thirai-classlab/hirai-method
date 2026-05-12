#!/usr/bin/env bash
# .claude/tests/workflow-guard-smoke.sh — smoke tests for workflow-guard.sh
#
# 目的:
#   workflow-guard.sh + bypass-logger.sh + .workflow-state JSON の end-to-end
#   挙動を 8 ケースで検証する。
#
#   - state JSON 不在の旧 task 互換: silent pass
#   - workflow_type=new / current_stage 未達 + findings 空 → BLOCK
#   - workflow_type=new / current_stage=finish + CRITICAL finding → BLOCK
#   - workflow_type=new / current_stage=finish + findings 空 → PASS
#   - bypass (ECC_WORKFLOW_GUARD_OFF=1) → PASS + bypass.log に 1 行 append
#   - tool_name != Bash → silent pass
#   - Bash だが /finish-task 以外 → silent pass
#   - workflow_type=modify / current_stage=system-review + findings 空 → PASS
#
# 設計:
#   - per-test tmp harness root に config-loader / bypass-logger を symlink
#   - .workflow-state は per-test tmpdir で隔離 → 本物の bypass.log を汚さない
#   - harness-config.yml も symlink で本物の stage 定義を再利用
#
# 実行:
#   bash .claude/tests/workflow-guard-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)

set -uo pipefail

# repo root に移動
cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1

REPO_ROOT="$(pwd)"
HOOK_REAL="${REPO_ROOT}/.claude/hooks/workflow-guard.sh"
FIXTURES="${REPO_ROOT}/.claude/tests/fixtures/workflow-guard"
INPUTS="${FIXTURES}/inputs"

# tmp harness root (per-run) — bypass.log を本物の場所に書かせない
TMP_ROOT="$(mktemp -d "/tmp/workflow-guard-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# tmp harness root に .claude/ を組み立てる
# - hooks / harness-config.yml は real を symlink (再利用)
# - .workflow-state は per-test 隔離 (real .workflow-state/bypass.log を汚さない)
mkdir -p "${TMP_ROOT}/.claude"
ln -s "${REPO_ROOT}/.claude/hooks" "${TMP_ROOT}/.claude/hooks"
ln -s "${REPO_ROOT}/.claude/harness-config.yml" "${TMP_ROOT}/.claude/harness-config.yml"

PASS=0
FAIL=0
FAIL_CASES=""

# === 結果テーブル (実装末尾で表示) ===
RESULTS=""

# helpers ----------------------------------------------------------------------

# reset per-test state dir (空 bypass.log + 0 state json)
_reset_state_dir() {
  rm -rf "${TMP_ROOT}/.claude/.workflow-state"
  mkdir -p "${TMP_ROOT}/.claude/.workflow-state"
}

# place a fixture state JSON in tmp state dir
# $1 = fixture filename (e.g. case-2-mid.json)
# $2 = target slug (filename without .json)
_place_state() {
  local fixture="$1"
  local slug="$2"
  cp "${FIXTURES}/${fixture}" "${TMP_ROOT}/.claude/.workflow-state/${slug}.json"
}

# run hook against an input fixture; returns nothing — sets globals
#   LAST_OUT (stdout)
#   LAST_ERR (stderr)
#   LAST_CODE (exit code)
# $1 = input fixture filename
# remaining = env KEY=VAL pairs
_run_hook() {
  local input="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$TMP_ROOT" \
    "$@" \
    bash "$HOOK_REAL" \
    < "${INPUTS}/${input}" \
    > "$out_file" \
    2> "$err_file"
  LAST_CODE=$?
  LAST_OUT=$(cat "$out_file")
  LAST_ERR=$(cat "$err_file")
  rm -f "$out_file" "$err_file"
}

# record case result
# $1 = label, $2 = pass|fail, $3 = expected, $4 = actual
_record() {
  local label="$1" status="$2" expected="$3" actual="$4"
  RESULTS="${RESULTS}${status}|${label}|${expected}|${actual}"$'\n'
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_CASES="${FAIL_CASES} ${label}"
  fi
}

# tests ------------------------------------------------------------------------

# Case 1: state JSON 不在 + /finish-task → silent pass (exit 0)
case1() {
  _reset_state_dir
  _run_hook "case-1.json"
  local expected="exit=0 silent" actual="exit=${LAST_CODE} stderr=$(printf '%s' "$LAST_ERR" | head -c 40)"
  if [ "$LAST_CODE" = "0" ] && [ -z "$LAST_ERR" ]; then
    _record "Case 1: missing state JSON → silent pass" "PASS" "$expected" "$actual"
  else
    _record "Case 1: missing state JSON → silent pass" "FAIL" "$expected" "$actual"
  fi
}

# Case 2: workflow_type=new, current_stage=tdd (not final), findings 空 → BLOCK exit 2
case2() {
  _reset_state_dir
  _place_state "case-2-mid.json" "smoke-mid"
  _run_hook "case-2.json"
  local expected="exit=2 stderr~'not at final'"
  local actual="exit=${LAST_CODE}"
  # stderr should mention current_stage 未達 (we check the Japanese stem "最終 stage")
  if [ "$LAST_CODE" = "2" ] && printf '%s' "$LAST_ERR" | grep -q "current_stage" \
     && printf '%s' "$LAST_ERR" | grep -q "最終 stage"; then
    _record "Case 2: stage not final → BLOCK" "PASS" "$expected" "$actual"
  else
    _record "Case 2: stage not final → BLOCK" "FAIL" "$expected" "$actual"
  fi
}

# Case 3: workflow_type=new, current_stage=finish, CRITICAL finding → BLOCK exit 2
case3() {
  _reset_state_dir
  _place_state "case-3-blocked.json" "smoke-blocked"
  _run_hook "case-3.json"
  local expected="exit=2 stderr~'pending_findings'"
  local actual="exit=${LAST_CODE}"
  if [ "$LAST_CODE" = "2" ] && printf '%s' "$LAST_ERR" | grep -q "pending_findings"; then
    _record "Case 3: pending finding → BLOCK" "PASS" "$expected" "$actual"
  else
    _record "Case 3: pending finding → BLOCK" "FAIL" "$expected" "$actual"
  fi
}

# Case 4: workflow_type=new, current_stage=finish, findings 空 → PASS exit 0
case4() {
  _reset_state_dir
  _place_state "case-4-clean.json" "smoke-clean"
  _run_hook "case-4.json"
  local expected="exit=0 stdout='{}'"
  local actual="exit=${LAST_CODE} stdout=${LAST_OUT}"
  if [ "$LAST_CODE" = "0" ] && [ "$LAST_OUT" = "{}" ]; then
    _record "Case 4: clean finish → PASS" "PASS" "$expected" "$actual"
  else
    _record "Case 4: clean finish → PASS" "FAIL" "$expected" "$actual"
  fi
}

# Case 5: bypass via ECC_WORKFLOW_GUARD_OFF=1 on Case-3 input → PASS + bypass.log append
case5() {
  _reset_state_dir
  _place_state "case-3-blocked.json" "smoke-blocked"
  local log_file="${TMP_ROOT}/.claude/.workflow-state/bypass.log"
  # ensure empty
  : > "$log_file"

  _run_hook "case-5.json" \
    ECC_WORKFLOW_GUARD_OFF=1 \
    ECC_BYPASS_REASON="smoke test bypass" \
    CLAUDE_SESSION_ID="smoke-session-c5"

  local expected="exit=0, log line with 'workflow-guard' + 'ECC_WORKFLOW_GUARD_OFF'"
  local actual="exit=${LAST_CODE}"
  local log_last
  log_last=$(tail -n1 "$log_file" 2>/dev/null)
  actual="${actual} log_last='${log_last}'"

  if [ "$LAST_CODE" = "0" ] \
     && printf '%s' "$log_last" | grep -q "workflow-guard" \
     && printf '%s' "$log_last" | grep -q "ECC_WORKFLOW_GUARD_OFF" \
     && printf '%s' "$log_last" | grep -q "smoke test bypass" \
     && printf '%s' "$log_last" | grep -q "smoke-session-c5"; then
    _record "Case 5: ECC_WORKFLOW_GUARD_OFF bypass → PASS + log append" "PASS" "$expected" "$actual"
  else
    _record "Case 5: ECC_WORKFLOW_GUARD_OFF bypass → PASS + log append" "FAIL" "$expected" "$actual"
  fi
}

# Case 6: tool_name=Edit (非 Bash) → silent pass
case6() {
  _reset_state_dir
  _run_hook "case-6.json"
  local expected="exit=0 silent"
  local actual="exit=${LAST_CODE} stderr_len=${#LAST_ERR}"
  if [ "$LAST_CODE" = "0" ] && [ -z "$LAST_ERR" ]; then
    _record "Case 6: tool_name=Edit → silent pass" "PASS" "$expected" "$actual"
  else
    _record "Case 6: tool_name=Edit → silent pass" "FAIL" "$expected" "$actual"
  fi
}

# Case 7: Bash command but not /finish-task → silent pass
case7() {
  _reset_state_dir
  _run_hook "case-7.json"
  local expected="exit=0 silent"
  local actual="exit=${LAST_CODE} stderr_len=${#LAST_ERR}"
  if [ "$LAST_CODE" = "0" ] && [ -z "$LAST_ERR" ]; then
    _record "Case 7: Bash non-finish-task → silent pass" "PASS" "$expected" "$actual"
  else
    _record "Case 7: Bash non-finish-task → silent pass" "FAIL" "$expected" "$actual"
  fi
}

# Case 8: workflow_type=modify, current_stage=system-review (final), findings 空 → PASS
case8() {
  _reset_state_dir
  _place_state "case-8-modify.json" "smoke-modify"
  _run_hook "case-8.json"
  local expected="exit=0 stdout='{}'"
  local actual="exit=${LAST_CODE} stdout=${LAST_OUT}"
  if [ "$LAST_CODE" = "0" ] && [ "$LAST_OUT" = "{}" ]; then
    _record "Case 8: modify clean final → PASS" "PASS" "$expected" "$actual"
  else
    _record "Case 8: modify clean final → PASS" "FAIL" "$expected" "$actual"
  fi
}

# === run all ===
case1
case2
case3
case4
case5
case6
case7
case8

# === report ===
printf '\n=== workflow-guard smoke results ===\n'
printf 'Status | Case | Expected | Actual\n'
printf -- '------+------+----------+-------\n'
printf '%s' "$RESULTS"
printf '\n=== summary: %d passed, %d failed ===\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  printf 'FAIL cases:%s\n' "$FAIL_CASES" >&2
  exit 1
fi
exit 0
