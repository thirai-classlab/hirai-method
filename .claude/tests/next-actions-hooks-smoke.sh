#!/usr/bin/env bash
# .claude/tests/next-actions-hooks-smoke.sh — smoke tests for next-actions hooks
#
# 目的:
#   next-actions-surface.sh (SessionStart) と byproduct-discharge-guard.sh (Stop)
#   の end-to-end 挙動を 5 ケースで検証する。
#
# テストケース:
#   1. case-clean        : 全 entry 処理済    → surface silent / discharge exit 0
#   2. case-with-red     : 🔴 未処理 2 件     → surface に "🔴 2 件" 文言 / discharge exit 2
#   3. case-with-yellow-only : 🟡 未処理 1 件 → surface WARN / discharge exit 0 (WARN)
#   4. case-bypass       : 🔴 残存 + bypass env → discharge exit 0 + bypass.log 確認
#   5. case-missing-file : next-actions.md 不在 → 両 hook exit 0 silent
#
# 設計:
#   - per-test tmp harness root に hooks / lib を symlink
#   - tmp に docs/tasks/next-actions.md を fixture から配置
#   - .workflow-state は per-test 隔離 → 本物の bypass.log を汚さない
#
# 実行:
#   bash .claude/tests/next-actions-hooks-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)

set -uo pipefail

cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
REPO_ROOT="$(pwd)"

SURFACE_HOOK="${REPO_ROOT}/.claude/hooks/next-actions-surface.sh"
DISCHARGE_HOOK="${REPO_ROOT}/.claude/hooks/byproduct-discharge-guard.sh"
FIXTURES="${REPO_ROOT}/.claude/tests/fixtures/next-actions"

# tmp harness root (per-run)
TMP_ROOT="$(mktemp -d "/tmp/next-actions-hooks-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

# tmp .claude/ 構築
mkdir -p "${TMP_ROOT}/.claude"
ln -s "${REPO_ROOT}/.claude/hooks" "${TMP_ROOT}/.claude/hooks"
mkdir -p "${TMP_ROOT}/docs/tasks"

PASS=0
FAIL=0
FAIL_CASES=""
RESULTS=""

# helpers ----------------------------------------------------------------------

# fixture を tmp の docs/tasks/next-actions.md に配置
# $1 = fixture filename (空文字列なら file を削除 = 不在ケース)
_place_md() {
  local fixture="${1:-}"
  rm -f "${TMP_ROOT}/docs/tasks/next-actions.md"
  if [ -n "$fixture" ]; then
    cp "${FIXTURES}/${fixture}" "${TMP_ROOT}/docs/tasks/next-actions.md"
  fi
}

_reset_state_dir() {
  rm -rf "${TMP_ROOT}/.claude/.workflow-state"
  mkdir -p "${TMP_ROOT}/.claude/.workflow-state"
}

# run hook (next-actions-surface or byproduct-discharge-guard)
# sets LAST_OUT / LAST_ERR / LAST_CODE
_run_hook() {
  local hook_path="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$TMP_ROOT" \
    "$@" \
    bash "$hook_path" \
    < /dev/null \
    > "$out_file" \
    2> "$err_file"
  LAST_CODE=$?
  LAST_OUT=$(cat "$out_file")
  LAST_ERR=$(cat "$err_file")
  rm -f "$out_file" "$err_file"
}

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

# Case 1: clean → surface silent / discharge silent
case_clean() {
  _reset_state_dir
  _place_md "case-clean.md"

  _run_hook "$SURFACE_HOOK"
  local s_code=$LAST_CODE
  local s_err_len=${#LAST_ERR}
  if [ "$s_code" = "0" ] && [ "$s_err_len" = "0" ]; then
    _record "Case 1a [clean]: surface silent" "PASS" "exit=0, stderr empty" \
      "exit=${s_code} stderr_len=${s_err_len}"
  else
    _record "Case 1a [clean]: surface silent" "FAIL" "exit=0, stderr empty" \
      "exit=${s_code} stderr_len=${s_err_len}"
  fi

  _run_hook "$DISCHARGE_HOOK"
  local d_code=$LAST_CODE
  if [ "$d_code" = "0" ]; then
    _record "Case 1b [clean]: discharge exit 0" "PASS" "exit=0" "exit=${d_code}"
  else
    _record "Case 1b [clean]: discharge exit 0" "FAIL" "exit=0" "exit=${d_code}"
  fi
}

# Case 2: with-red → surface に「🔴 2 件」/ discharge exit 2
case_with_red() {
  _reset_state_dir
  _place_md "case-with-red.md"

  _run_hook "$SURFACE_HOOK"
  local s_code=$LAST_CODE
  # stderr に「🔴 2」と「未処理副産物」が出ること
  if [ "$s_code" = "0" ] \
     && printf '%s' "$LAST_ERR" | grep -q "🔴 2" \
     && printf '%s' "$LAST_ERR" | grep -q "未処理副産物"; then
    _record "Case 2a [red]: surface reports 🔴 2件" "PASS" \
      "exit=0 stderr~'🔴 2 件'" "exit=${s_code} stderr_match=yes"
  else
    _record "Case 2a [red]: surface reports 🔴 2件" "FAIL" \
      "exit=0 stderr~'🔴 2 件'" "exit=${s_code} stderr='$(printf '%s' "$LAST_ERR" | head -c 80)'"
  fi

  _run_hook "$DISCHARGE_HOOK"
  local d_code=$LAST_CODE
  if [ "$d_code" = "2" ] && printf '%s' "$LAST_ERR" | grep -q "BLOCK"; then
    _record "Case 2b [red]: discharge BLOCK exit 2" "PASS" \
      "exit=2 stderr~BLOCK" "exit=${d_code} BLOCK=yes"
  else
    _record "Case 2b [red]: discharge BLOCK exit 2" "FAIL" \
      "exit=2 stderr~BLOCK" "exit=${d_code} stderr='$(printf '%s' "$LAST_ERR" | head -c 80)'"
  fi
}

# Case 3: yellow only → surface WARN(stderr 出力) / discharge exit 0 (WARN)
case_with_yellow_only() {
  _reset_state_dir
  _place_md "case-with-yellow-only.md"

  _run_hook "$SURFACE_HOOK"
  local s_code=$LAST_CODE
  if [ "$s_code" = "0" ] \
     && printf '%s' "$LAST_ERR" | grep -q "🟡 1" \
     && printf '%s' "$LAST_ERR" | grep -q "🔴 0"; then
    _record "Case 3a [yellow]: surface reports 🟡 1件" "PASS" \
      "exit=0 stderr~'🟡 1 件' 🔴 0 件" "exit=${s_code} stderr_match=yes"
  else
    _record "Case 3a [yellow]: surface reports 🟡 1件" "FAIL" \
      "exit=0 stderr~'🟡 1 件' 🔴 0 件" "exit=${s_code} stderr='$(printf '%s' "$LAST_ERR" | head -c 80)'"
  fi

  _run_hook "$DISCHARGE_HOOK"
  local d_code=$LAST_CODE
  if [ "$d_code" = "0" ] && printf '%s' "$LAST_ERR" | grep -q "WARN"; then
    _record "Case 3b [yellow]: discharge WARN exit 0" "PASS" \
      "exit=0 stderr~WARN" "exit=${d_code} WARN=yes"
  else
    _record "Case 3b [yellow]: discharge WARN exit 0" "FAIL" \
      "exit=0 stderr~WARN" "exit=${d_code} stderr='$(printf '%s' "$LAST_ERR" | head -c 80)'"
  fi
}

# Case 4: red + bypass env → discharge exit 0 + bypass.log append
case_bypass() {
  _reset_state_dir
  _place_md "case-with-red.md"

  local log_file="${TMP_ROOT}/.claude/.workflow-state/bypass.log"
  : > "$log_file"

  _run_hook "$DISCHARGE_HOOK" \
    ECC_BYPASS_DISCHARGE_GUARD=1 \
    ECC_BYPASS_REASON="smoke test discharge bypass" \
    CLAUDE_SESSION_ID="smoke-session-bypass-001"

  local d_code=$LAST_CODE
  local log_last
  log_last=$(tail -n1 "$log_file" 2>/dev/null)

  if [ "$d_code" = "0" ] \
     && printf '%s' "$log_last" | grep -q "byproduct-discharge-guard" \
     && printf '%s' "$log_last" | grep -q "ECC_BYPASS_DISCHARGE_GUARD" \
     && printf '%s' "$log_last" | grep -q "smoke-session-bypass-001" \
     && printf '%s' "$log_last" | grep -q "discharge-guard bypass"; then
    _record "Case 4 [bypass]: env bypass → exit 0 + log append" "PASS" \
      "exit=0 log~session_id+bypass" "exit=${d_code} log='$(printf '%s' "$log_last" | head -c 100)'"
  else
    _record "Case 4 [bypass]: env bypass → exit 0 + log append" "FAIL" \
      "exit=0 log~session_id+bypass" "exit=${d_code} log='$(printf '%s' "$log_last" | head -c 100)'"
  fi
}

# Case 5: missing file → 両 hook exit 0 silent
case_missing_file() {
  _reset_state_dir
  _place_md ""  # md 不在

  _run_hook "$SURFACE_HOOK"
  local s_code=$LAST_CODE
  local s_err_len=${#LAST_ERR}
  if [ "$s_code" = "0" ] && [ "$s_err_len" = "0" ]; then
    _record "Case 5a [missing]: surface silent" "PASS" "exit=0, stderr empty" \
      "exit=${s_code} stderr_len=${s_err_len}"
  else
    _record "Case 5a [missing]: surface silent" "FAIL" "exit=0, stderr empty" \
      "exit=${s_code} stderr_len=${s_err_len}"
  fi

  _run_hook "$DISCHARGE_HOOK"
  local d_code=$LAST_CODE
  local d_err_len=${#LAST_ERR}
  if [ "$d_code" = "0" ] && [ "$d_err_len" = "0" ]; then
    _record "Case 5b [missing]: discharge silent" "PASS" "exit=0, stderr empty" \
      "exit=${d_code} stderr_len=${d_err_len}"
  else
    _record "Case 5b [missing]: discharge silent" "FAIL" "exit=0, stderr empty" \
      "exit=${d_code} stderr_len=${d_err_len}"
  fi
}

# === run all ===
case_clean
case_with_red
case_with_yellow_only
case_bypass
case_missing_file

# === report ===
printf '\n=== next-actions-hooks smoke results ===\n'
printf 'Status | Case | Expected | Actual\n'
printf -- '-------+------+----------+-------\n'
printf '%s' "$RESULTS"
printf '\n=== summary: %d passed, %d failed ===\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  printf 'FAIL cases:%s\n' "$FAIL_CASES" >&2
  exit 1
fi
exit 0
