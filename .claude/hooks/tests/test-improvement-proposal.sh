#!/usr/bin/env bash
# test-improvement-proposal.sh — smoke tests for improvement-proposal.sh
#
# 検証する仕様:
#   1. observations 0 件 + state 空 → 何も出力しない、exit 0
#   2. mock observations: Bash deny 多数 → "Agent 委譲" 系の提案出力
#   3. mock GateGuard cleared 多数 → "事実材料" 系の提案出力
#   4. dedup: 24h 以内に同提案出ていたら抑制
#   5. ECC_IMPROVEMENT_PROPOSAL=off → 全 skip
#   6. HC_IMPROVEMENT_PROPOSAL_ENABLED=false → 全 skip
#   7. fail-open: python3 不在等の障害でも exit 0
#   8. failure-loop active session 検出 → "agent-introspect" 提案出力
#
# bash 3.2 互換 (macOS 標準) で動作する。

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/improvement-proposal.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Empty config so config-loader doesn't WARN
: > "$TMP/empty.yml"

assert_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected substring: %s\n  got: %s\n" "$name" "$needle" "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  unexpected substring: %s\n  got: %s\n" "$name" "$needle" "$haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n" "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: run the hook in an isolated PROJECT_DIR with controlled HC_*
# Args:
#   $1 = scenario name (used for tmpdir)
#   $2 = obs records jsonl content (multiline string)
#   $3 = number of GateGuard .cleared files to drop into HC_GATEGUARD_STATE_DIR
#   $4 = number of confidence bypass.log lines
#   $5 = number of failure-window logs with active loop signature
#   $@ from $6 onward = extra "VAR=val" exports
run_hook() {
  local scenario="$1"
  local obs_content="$2"
  local gg_count="$3"
  local cg_count="$4"
  local fw_count="$5"
  shift 5

  local proj="$TMP/$scenario"
  rm -rf "$proj"
  mkdir -p "$proj/.claude/.gateguard-state"
  mkdir -p "$proj/.claude/.taskguard-state"
  mkdir -p "$proj/.claude/.failure-window"
  mkdir -p "$proj/.claude/.confidence-gate-state"
  mkdir -p "$proj/.claude/.improvement-proposal-state"
  mkdir -p "$proj/homunculus"

  # observations.jsonl drop
  if [ -n "$obs_content" ]; then
    printf '%s\n' "$obs_content" > "$proj/homunculus/observations.jsonl"
  fi

  # GateGuard cleared files
  local i=0
  while [ "$i" -lt "$gg_count" ]; do
    : > "$proj/.claude/.gateguard-state/edit-mock${i}.cleared"
    i=$((i + 1))
  done

  # confidence bypass.log
  if [ "$cg_count" -gt 0 ]; then
    local j=0
    : > "$proj/.claude/.confidence-gate-state/bypass.log"
    while [ "$j" -lt "$cg_count" ]; do
      printf '%s\tbypassed: mock-reason-%d\n' \
        "${ECC_IMPROVEMENT_PROPOSAL_TEST_NOW:-2026-05-07T00:00:00Z}" "$j" \
        >> "$proj/.claude/.confidence-gate-state/bypass.log"
      j=$((j + 1))
    done
  fi

  # failure-window active loops
  local k=0
  while [ "$k" -lt "$fw_count" ]; do
    {
      echo "Bash:fooerror"
      echo "Bash:fooerror"
      echo "Bash:fooerror"
    } > "$proj/.claude/.failure-window/session${k}.log"
    k=$((k + 1))
  done

  local extra_env=""
  for spec in "$@"; do
    extra_env="$extra_env export $spec;"
  done

  bash -c "
    set +u
    for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
    unset ECC_IMPROVEMENT_PROPOSAL
    export HC_CONFIG_PATH='$TMP/empty.yml'
    export CLAUDE_PROJECT_DIR='$proj'
    export HC_HOMUNCULUS_ROOT='$proj/homunculus'
    export HC_GATEGUARD_STATE_DIR='.claude/.gateguard-state'
    export HC_TASKGUARD_STATE_DIR='.claude/.taskguard-state'
    export HC_FAILURE_WINDOW_DIR='.claude/.failure-window'
    export HC_CONFIDENCE_STATE_DIR='.claude/.confidence-gate-state'
    export HC_IMPROVEMENT_PROPOSAL_STATE_DIR='.claude/.improvement-proposal-state'
    export HC_IMPROVEMENT_PROPOSAL_ENABLED=true
    export HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS=7
    export HC_IMPROVEMENT_PROPOSAL_MAX_COUNT=3
    export HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS=24
    export ECC_IMPROVEMENT_PROPOSAL_TEST_NOW='${ECC_IMPROVEMENT_PROPOSAL_TEST_NOW:-2026-05-07T12:00:00Z}'
    $extra_env
    bash '$HOOK' </dev/null 2>&1
    echo \"EXIT_CODE=\$?\"
  "
}

# === Helper to generate mock observations records ===
# Args: count, tool, with_perm_deny (1 or 0)
gen_obs_records() {
  local count="$1"
  local tool="$2"
  local perm_deny="$3"
  local i=0
  local out=""
  while [ "$i" -lt "$count" ]; do
    local line='{"ts":"2026-05-07T10:00:00Z","event":"PostToolUse","tool":"'"$tool"'","raw":{"hook_event_name":"PostToolUse","tool_name":"'"$tool"'"'
    if [ "$perm_deny" = "1" ]; then
      line="$line"',"tool_response":{"is_error":true,"content":"Permission denied: please use Agent","decision":"block"}}}'
    else
      line="$line"',"tool_response":{"is_error":false}}}'
    fi
    if [ -z "$out" ]; then
      out="$line"
    else
      out="$out"$'\n'"$line"
    fi
    i=$((i + 1))
  done
  printf '%s' "$out"
}

# === Case 1: empty obs + empty state -> no output, exit 0 ===
out=$(run_hook "case1" "" 0 0 0)
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case1a: empty -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_eq "Case1b: empty -> no output" "" "$non_exit_lines"

# === Case 2: many Bash perm denials -> Agent 委譲 proposal ===
obs=$(gen_obs_records 10 "Bash" 1)
out=$(run_hook "case2" "$obs" 0 0 0)
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case2a: bash deny -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_contains "Case2b: bash deny -> proposal header" "Improvement proposals" "$out"
assert_contains "Case2c: bash deny -> Agent 委譲 hint" "Agent tool 経由" "$out"
assert_contains "Case2d: footer present" "block しません" "$out"

# === Case 3: many GateGuard .cleared -> 事実材料 proposal ===
out=$(run_hook "case3" "" 8 0 0)
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case3a: gateguard -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_contains "Case3b: gateguard -> 事実材料 hint" "事実材料" "$out"

# === Case 4: dedup within DEDUP_HOURS suppresses repeat ===
# 1st run: produce proposal (uses dedup_state inside the project's .claude)
out1=$(run_hook "case4" "" 8 0 0)
# 2nd run with same project dir: should be suppressed
out2=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  unset ECC_IMPROVEMENT_PROPOSAL
  export HC_CONFIG_PATH='$TMP/empty.yml'
  export CLAUDE_PROJECT_DIR='$TMP/case4'
  export HC_HOMUNCULUS_ROOT='$TMP/case4/homunculus'
  export HC_GATEGUARD_STATE_DIR='.claude/.gateguard-state'
  export HC_TASKGUARD_STATE_DIR='.claude/.taskguard-state'
  export HC_FAILURE_WINDOW_DIR='.claude/.failure-window'
  export HC_CONFIDENCE_STATE_DIR='.claude/.confidence-gate-state'
  export HC_IMPROVEMENT_PROPOSAL_STATE_DIR='.claude/.improvement-proposal-state'
  export HC_IMPROVEMENT_PROPOSAL_ENABLED=true
  export HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS=7
  export HC_IMPROVEMENT_PROPOSAL_MAX_COUNT=3
  export HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS=24
  export ECC_IMPROVEMENT_PROPOSAL_TEST_NOW='2026-05-07T13:00:00Z'
  bash '$HOOK' </dev/null 2>&1
  echo \"EXIT_CODE=\$?\"
")
exit_line=$(printf '%s\n' "$out2" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out2" | grep -v '^EXIT_CODE=')
assert_contains "Case4a: 1st run shows proposal" "Improvement proposals" "$out1"
assert_eq "Case4b: 2nd run within dedup -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_eq "Case4c: 2nd run within dedup -> no output" "" "$non_exit_lines"

# === Case 5: ECC_IMPROVEMENT_PROPOSAL=off -> all skip ===
out=$(run_hook "case5" "$(gen_obs_records 10 Bash 1)" 8 0 0 "ECC_IMPROVEMENT_PROPOSAL=off")
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case5a: ECC kill switch -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_eq "Case5b: ECC kill switch -> no output" "" "$non_exit_lines"

# === Case 6: HC_IMPROVEMENT_PROPOSAL_ENABLED=false -> all skip ===
out=$(run_hook "case6" "$(gen_obs_records 10 Bash 1)" 8 0 0 "HC_IMPROVEMENT_PROPOSAL_ENABLED=false")
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case6a: HC kill switch -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_eq "Case6b: HC kill switch -> no output" "" "$non_exit_lines"

# === Case 7: fail-open without python3 -> exit 0 silently ===
# Strip dirs containing python3 from PATH so `command -v python3` fails.
# We DO keep system bins (/bin /usr/bin) so bash/grep/cat work.
strip_python_path() {
  local p clean=""
  local OLDIFS="$IFS"
  IFS=':'
  for p in $PATH; do
    [ -z "$p" ] && continue
    [ -x "$p/python3" ] && continue
    if [ -z "$clean" ]; then clean="$p"; else clean="$clean:$p"; fi
  done
  IFS="$OLDIFS"
  printf '%s' "$clean"
}
clean_path=$(strip_python_path)
proj7="$TMP/case7"
mkdir -p "$proj7"
out=$(PATH="$clean_path" bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' 2>/dev/null || true); do unset \"\$v\"; done
  unset ECC_IMPROVEMENT_PROPOSAL
  export HC_CONFIG_PATH='$TMP/empty.yml'
  export CLAUDE_PROJECT_DIR='$proj7'
  bash '$HOOK' </dev/null 2>&1
  echo \"EXIT_CODE=\$?\"
")
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case7: no python3 -> exit 0 (fail-open)" "EXIT_CODE=0" "$exit_line"

# === Case 8: failure-window active loop -> agent-introspect proposal ===
out=$(run_hook "case8" "" 0 0 1)
assert_contains "Case8a: failure-loop -> agent-introspect hint" "agent-introspect" "$out"
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case8b: failure-loop -> exit 0" "EXIT_CODE=0" "$exit_line"

printf "\n--- test-improvement-proposal.sh: %d pass / %d fail ---\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
