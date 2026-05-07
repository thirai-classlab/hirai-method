#!/usr/bin/env bash
# test-agent-marker-warn.sh — smoke tests for agent-marker-set.sh foreground warning
#
# Verifies development-process.md "サブエージェント委譲の必須要件" §1:
#   1. run_in_background=false → stderr に WARNING を出す
#   2. run_in_background=true  → WARNING を出さない
#   3. run_in_background 未指定  → WARNING を出す (default false 扱い)
#   4. どのケースでも stdout は "{}" を返し marker file は作成される

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/agent-marker-set.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HC_AGENT_MARKER_DIR="$TMP/markers"

assert_warn() {
  local name="$1"
  local stderr="$2"
  if printf '%s' "$stderr" | grep -q 'WARNING: subagent launched without run_in_background'; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected WARNING in stderr, got: %s\n" "$name" "$stderr"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_warn() {
  local name="$1"
  local stderr="$2"
  if printf '%s' "$stderr" | grep -q 'WARNING: subagent launched without run_in_background'; then
    printf "FAIL: %s\n  expected no warning, got: %s\n" "$name" "$stderr"
    FAIL=$((FAIL + 1))
  else
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  fi
}

assert_marker_created() {
  local name="$1"
  if ls "$HC_AGENT_MARKER_DIR"/*.lock >/dev/null 2>&1; then
    printf "PASS: %s (marker created)\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s (no marker)\n" "$name"
    FAIL=$((FAIL + 1))
  fi
}

# --- case 1: run_in_background=false ---
rm -rf "$HC_AGENT_MARKER_DIR"
out=$(echo '{"session_id":"s1","tool_input":{"run_in_background":false}}' \
      | bash "$HOOK" 2>/tmp/_amw_err.log)
err=$(cat /tmp/_amw_err.log)
assert_warn "foreground (run_in_background=false) emits WARNING" "$err"
assert_marker_created "foreground still creates marker"
[ "$(printf '%s' "$out" | tr -d '[:space:]')" = "{}" ] \
  && { echo "PASS: stdout is {}"; PASS=$((PASS+1)); } \
  || { echo "FAIL: stdout != {} got=$out"; FAIL=$((FAIL+1)); }

# --- case 2: run_in_background=true ---
rm -rf "$HC_AGENT_MARKER_DIR"
out=$(echo '{"session_id":"s2","tool_input":{"run_in_background":true}}' \
      | bash "$HOOK" 2>/tmp/_amw_err.log)
err=$(cat /tmp/_amw_err.log)
assert_no_warn "background (run_in_background=true) no WARNING" "$err"
assert_marker_created "background creates marker"

# --- case 3: run_in_background absent ---
rm -rf "$HC_AGENT_MARKER_DIR"
out=$(echo '{"session_id":"s3","tool_input":{}}' \
      | bash "$HOOK" 2>/tmp/_amw_err.log)
err=$(cat /tmp/_amw_err.log)
assert_warn "absent run_in_background emits WARNING" "$err"
assert_marker_created "absent still creates marker"

rm -f /tmp/_amw_err.log

printf "\n=== test-agent-marker-warn.sh: %d PASS / %d FAIL ===\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
