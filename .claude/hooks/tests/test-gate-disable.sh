#!/usr/bin/env bash
# test-gate-disable.sh — smoke test for ECC_F{1,2,3}_OFF env var bypass
#
# Verifies that:
#   - F1 (gateguard.sh):        ECC_F1_OFF=1 → approve, unset → existing behavior
#   - F2 (task-rule-guard.sh):  ECC_F2_OFF=1 → approve, unset → existing behavior
#   - F3 (confidence-gate.sh):  ECC_F3_OFF=1 → approve, unset → existing behavior
#
# Test design:
#   - "OFF": invoke hook with ECC_F{n}_OFF=1, expect output containing
#            decision":"approve" (or {"decision":"approve",...}). No file
#            system mutation needed.
#   - "ON" (envvar unset): invoke hook with an input that the existing
#            logic would block. Expect output NOT containing the F{n}_OFF
#            marker reason — proves the early-exit branch is not hit and
#            existing logic still runs.

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

run_test() {
  local name="$1"
  local expected_substr="$2"
  local must_not_contain="$3"
  local actual="$4"

  # Strip whitespace so that pretty-printed jq output ({"decision": "approve"})
  # matches the same substring patterns as compact output ({"decision":"approve"}).
  local actual_compact
  actual_compact=$(printf '%s' "$actual" | tr -d '[:space:]')

  if [[ "$actual_compact" == *"$expected_substr"* ]]; then
    if [ -n "$must_not_contain" ] && [[ "$actual_compact" == *"$must_not_contain"* ]]; then
      printf "FAIL: %s\n  expected '%s', forbidden '%s' both present\n  got: %s\n" \
        "$name" "$expected_substr" "$must_not_contain" "$actual"
      FAIL=$((FAIL + 1))
      return
    fi
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected substring: %s\n  got: %s\n" \
      "$name" "$expected_substr" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# --- Sandbox: isolate state dirs so existing markers don't leak in ---
TMP_STATE=$(mktemp -d)
trap 'rm -rf "$TMP_STATE"' EXIT
export HC_GATEGUARD_STATE_DIR="$TMP_STATE/gateguard"
export HC_TASKGUARD_STATE_DIR="$TMP_STATE/taskguard"
export HC_CONFIDENCE_STATE_DIR="$TMP_STATE/confidence"
mkdir -p "$HC_GATEGUARD_STATE_DIR" "$HC_TASKGUARD_STATE_DIR" "$HC_CONFIDENCE_STATE_DIR"

# Make sure no stale agent markers / subagent env interferes.
unset CLAUDE_HARNESS_ROLE
export HC_AGENT_MARKER_DIR="$TMP_STATE/agent-markers"
mkdir -p "$HC_AGENT_MARKER_DIR"

# === F1 (gateguard) ===
F1_INPUT_BLOCK='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/some/protected/foo.ts"}}'

# Case 1: ECC_F1_OFF=1 → approve
out=$(printf '%s' "$F1_INPUT_BLOCK" | ECC_F1_OFF=1 bash "$HOOKS_DIR/gateguard.sh" Edit 2>/dev/null)
run_test "F1: ECC_F1_OFF=1 yields approve" \
  '"decision":"approve"' "" "$out"

# Case 2: ECC_F1_OFF unset → existing logic runs (block path triggers because
# this is a fresh state dir / first edit). We assert it did NOT take the
# OFF early-exit branch by checking the OFF reason string is absent.
unset ECC_F1_OFF
out=$(printf '%s' "$F1_INPUT_BLOCK" | bash "$HOOKS_DIR/gateguard.sh" Edit 2>/dev/null)
run_test "F1: unset preserves existing logic" \
  '' "ECC_F1_OFF" "$out"
# Also assert it actually emitted SOMETHING (block JSON or {} per existing logic):
if [ -z "$out" ]; then
  printf "FAIL: F1 unset case produced empty output\n"
  FAIL=$((FAIL + 1))
  PASS=$((PASS - 1))
fi

# === F2 (task-rule-guard) ===
F2_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/tmp/some/repo/docs/tasks/task-99-nodraft.md"}}'

# Case 3: ECC_F2_OFF=1 → approve
out=$(printf '%s' "$F2_INPUT" | ECC_F2_OFF=1 bash "$HOOKS_DIR/task-rule-guard.sh" Write 2>/dev/null)
run_test "F2: ECC_F2_OFF=1 yields approve" \
  '"decision":"approve"' "" "$out"

# Case 4: ECC_F2_OFF unset → OFF marker absent
unset ECC_F2_OFF
out=$(printf '%s' "$F2_INPUT" | bash "$HOOKS_DIR/task-rule-guard.sh" Write 2>/dev/null)
run_test "F2: unset preserves existing logic" \
  '' "ECC_F2_OFF" "$out"

# === F3 (confidence-gate) ===
# Use a transcript_path pointing at a non-existent file → existing logic
# fail-opens with `{}`. With ECC_F3_OFF=1 we should get an approve JSON instead.
F3_INPUT='{"transcript_path":"/nonexistent/file.jsonl"}'

# Case 5: ECC_F3_OFF=1 → approve
out=$(printf '%s' "$F3_INPUT" | ECC_F3_OFF=1 bash "$HOOKS_DIR/confidence-gate.sh" 2>/dev/null)
run_test "F3: ECC_F3_OFF=1 yields approve" \
  '"decision":"approve"' "" "$out"

# Case 6: ECC_F3_OFF unset → OFF marker absent (logic falls through to fail-open `{}`)
unset ECC_F3_OFF
out=$(printf '%s' "$F3_INPUT" | bash "$HOOKS_DIR/confidence-gate.sh" 2>/dev/null)
run_test "F3: unset preserves existing logic" \
  '' "ECC_F3_OFF" "$out"

# --- summary ---
printf "\n--- test-gate-disable.sh: %d pass / %d fail ---\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
