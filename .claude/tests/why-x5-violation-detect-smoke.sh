#!/usr/bin/env bash
# why-x5-violation-detect-smoke.sh — smoke tests for task-21 W0.3 new hook
#
# 目的: why-x5-violation-detect.sh (PostToolUse) の挙動を 4 ケースで検証する。
#
# テストケース:
#   1. v9 残骸「【システムの存在意義】」を含む直前 assistant
#      → exit 0, stdout に <system-reminder> + matched pattern
#   2. v9 残骸「【whyN】」を含む直前 assistant
#      → exit 0, stdout に <system-reminder>
#   3. v10 1 行 format のみの直前 assistant (違反なし)
#      → exit 0, stdout empty (silent)
#   4. HC_WHY_X5_VIOLATION_ENABLED=false + 違反あり
#      → exit 0, stdout empty (bypass)
#
# 実行: bash .claude/tests/why-x5-violation-detect-smoke.sh
# 終了コード: 0 = 全 case PASS / 1 = 1 件以上 FAIL

set -uo pipefail

cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
REPO_ROOT="$(pwd)"
HOOK="${REPO_ROOT}/.claude/hooks/why-x5-violation-detect.sh"

TMP_ROOT="$(mktemp -d "/tmp/why-x5-violation-smoke.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
FAIL_CASES=""
RESULTS=""

_make_transcript() {
  local out="$1"
  local txt="$2"
  : > "$out"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hello"},"uuid":"u1"}' >> "$out"
  local line
  line=$(jq -nc --arg t "$txt" '{
    type: "assistant",
    message: {role: "assistant", content: [{type: "text", text: $t}]},
    uuid: "a1"
  }')
  printf '%s\n' "$line" >> "$out"
}

_run() {
  local stdin_json="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"
  env -i PATH="$PATH" HOME="$HOME" "$@" \
    bash "$HOOK" <<< "$stdin_json" > "$out_file" 2> "$err_file"
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

# Case 1: v9 残骸「【システムの存在意義】」を含む → reminder fires
case1() {
  local tr="${TMP_ROOT}/tr-c1.jsonl"
  _make_transcript "$tr" "【システムの存在意義】hirai-method を強化するため【whyN】規範統一が必要"
  local stdin_json
  stdin_json=$(jq -nc --arg p "$tr" '{transcript_path: $p}')
  _run "$stdin_json"

  local expected="exit=0, stdout~'<system-reminder>'+'matched pattern'"
  local actual="exit=${LAST_CODE} stdout_head='$(printf '%s' "$LAST_OUT" | head -c 80)'"
  if [ "$LAST_CODE" = "0" ] \
     && printf '%s' "$LAST_OUT" | grep -q "<system-reminder>" \
     && printf '%s' "$LAST_OUT" | grep -q "matched pattern"; then
    _record "Case 1: v9 [システムの存在意義] → reminder fires" "PASS" "$expected" "$actual"
  else
    _record "Case 1: v9 [システムの存在意義] → reminder fires" "FAIL" "$expected" "$actual"
  fi
}

# Case 2: v9 残骸「【whyN】」のみを含む → reminder fires
case2() {
  local tr="${TMP_ROOT}/tr-c2.jsonl"
  _make_transcript "$tr" "通常作業中【whyN】規範統一が必要"
  local stdin_json
  stdin_json=$(jq -nc --arg p "$tr" '{transcript_path: $p}')
  _run "$stdin_json"

  local expected="exit=0, stdout~'<system-reminder>'"
  local actual="exit=${LAST_CODE} stdout_head='$(printf '%s' "$LAST_OUT" | head -c 80)'"
  if [ "$LAST_CODE" = "0" ] && printf '%s' "$LAST_OUT" | grep -q "<system-reminder>"; then
    _record "Case 2: v9 [whyN] → reminder fires" "PASS" "$expected" "$actual"
  else
    _record "Case 2: v9 [whyN] → reminder fires" "FAIL" "$expected" "$actual"
  fi
}

# Case 3: v10 1 行 format のみ → silent
case3() {
  local tr="${TMP_ROOT}/tr-c3.jsonl"
  _make_transcript "$tr" "smoke test を実行するため、bash .claude/tests/loop-auto-progress-smoke.sh を行う"
  local stdin_json
  stdin_json=$(jq -nc --arg p "$tr" '{transcript_path: $p}')
  _run "$stdin_json"

  local expected="exit=0, stdout empty (no violation)"
  local actual="exit=${LAST_CODE} stdout_len=${#LAST_OUT}"
  if [ "$LAST_CODE" = "0" ] && [ -z "$LAST_OUT" ]; then
    _record "Case 3: v10 1 行 format → silent" "PASS" "$expected" "$actual"
  else
    _record "Case 3: v10 1 行 format → silent" "FAIL" "$expected" "$actual"
  fi
}

# Case 4: HC_WHY_X5_VIOLATION_ENABLED=false + 違反あり → silent (bypass)
case4() {
  local tr="${TMP_ROOT}/tr-c4.jsonl"
  _make_transcript "$tr" "【システムの存在意義】テスト中"
  local stdin_json
  stdin_json=$(jq -nc --arg p "$tr" '{transcript_path: $p}')
  _run "$stdin_json" HC_WHY_X5_VIOLATION_ENABLED=false

  local expected="exit=0, stdout empty (bypass)"
  local actual="exit=${LAST_CODE} stdout_len=${#LAST_OUT}"
  if [ "$LAST_CODE" = "0" ] && [ -z "$LAST_OUT" ]; then
    _record "Case 4: HC_WHY_X5_VIOLATION_ENABLED=false → silent" "PASS" "$expected" "$actual"
  else
    _record "Case 4: HC_WHY_X5_VIOLATION_ENABLED=false → silent" "FAIL" "$expected" "$actual"
  fi
}

case1
case2
case3
case4

printf '\n=== why-x5-violation-detect smoke results ===\n'
printf 'Status | Case | Expected | Actual\n'
printf -- '-------+------+----------+-------\n'
printf '%s' "$RESULTS"
printf '\n=== summary: %d passed, %d failed ===\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  printf 'FAIL cases:%s\n' "$FAIL_CASES" >&2
  exit 1
fi
exit 0
