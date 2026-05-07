#!/usr/bin/env bash
# test-check-required-env.sh — smoke tests for check-required-env.sh
#
# 検証する仕様:
#   1. required_env: [] → 出力なし、exit 0
#   2. error severity の env が未設定 → stderr に MISSING 出力
#   3. error severity の env が設定済 → 出力なし
#   4. severity 混在 (error/warn/info) → 各々分類して出力
#   5. 不正フォーマット (`|` 不足) → skip して exit 0
#   6. fail-open: 必ず exit 0
#
# bash 3.2 互換 (macOS 標準) で動作する。

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/check-required-env.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Empty config so config-loader doesn't emit a "not found" WARN line that
# would interfere with stderr-based assertions.
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

# Helper: run hook with controlled HC_REQUIRED_ENV / additional env vars.
# Args: <required_env_value> [env-spec...]
# Captures stderr and exit code.
run_hook() {
  local required_env="$1"
  shift
  local env_setup=""
  for spec in "$@"; do
    env_setup="$env_setup export $spec;"
  done
  bash -c "
    set +u
    for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
    export HC_CONFIG_PATH='$TMP/empty.yml'
    export HC_REQUIRED_ENV=\$'$required_env'
    $env_setup
    bash '$HOOK' </dev/null 2>&1
    echo \"EXIT_CODE=\$?\"
  "
}

# === Case 1: required_env: [] (empty) → no output, exit 0 ===
out=$(run_hook "")
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case1a: empty required_env -> exit 0" "EXIT_CODE=0" "$exit_line"
assert_eq "Case1b: empty required_env -> no output" "" "$non_exit_lines"

# === Case 2: error severity unset → MISSING output ===
out=$(run_hook 'FOO_UNSET|error|critical resource')
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_contains "Case2a: error severity unset -> MISSING" \
  "MISSING required env: FOO_UNSET" "$out"
assert_contains "Case2b: error message has purpose" "critical resource" "$out"
assert_eq "Case2c: error severity still exits 0 (fail-open)" "EXIT_CODE=0" "$exit_line"

# === Case 3: error severity set → no warning ===
out=$(run_hook 'BAR|error|important' "BAR=somevalue")
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case3a: env set -> no output" "" "$non_exit_lines"
assert_eq "Case3b: env set -> exit 0" "EXIT_CODE=0" "$exit_line"

# === Case 4: severity mixed → each classified ===
# Use different names to avoid case-3 contamination
out=$(run_hook 'A_ERR|error|need-A\nB_WARN|warn|need-B\nC_INFO|info|need-C')
assert_contains "Case4a: error has MISSING marker" "MISSING required env: A_ERR" "$out"
assert_contains "Case4b: warn has Recommended marker" "Recommended env not set: B_WARN" "$out"
assert_contains "Case4c: info has Optional marker" "Optional env not set: C_INFO" "$out"
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case4d: mixed severity -> exit 0" "EXIT_CODE=0" "$exit_line"

# === Case 5: malformed entry (no `|`) → skip + exit 0 ===
out=$(run_hook 'NOT_A_PIPE_FORMAT')
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
non_exit_lines=$(printf '%s\n' "$out" | grep -v '^EXIT_CODE=')
assert_eq "Case5a: malformed entry skipped (no output)" "" "$non_exit_lines"
assert_eq "Case5b: malformed entry exit 0" "EXIT_CODE=0" "$exit_line"

# Combined malformed + valid (the malformed should be skipped, valid should fire)
out=$(run_hook 'NOT_PIPE\nVALID|error|valid one')
assert_contains "Case5c: valid entry still detected with malformed neighbor" \
  "MISSING required env: VALID" "$out"
assert_not_contains "Case5d: malformed entry not in output" "NOT_PIPE" "$out"

# === Case 6: fail-open guarantee ===
# Even with HC_REQUIRED_ENV containing many error severity entries, exit must be 0.
out=$(run_hook 'X|error|x\nY|error|y\nZ|error|z')
exit_line=$(printf '%s\n' "$out" | grep '^EXIT_CODE=' | tail -1)
assert_eq "Case6: many missing error envs -> still exit 0 (fail-open)" "EXIT_CODE=0" "$exit_line"

printf "\n--- test-check-required-env.sh: %d pass / %d fail ---\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
