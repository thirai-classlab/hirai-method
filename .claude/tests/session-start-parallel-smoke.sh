#!/usr/bin/env bash
# session-start-parallel-smoke.sh — task-25 Sub-epic A2 smoke test
#
# 5 cases:
#   1. all hooks normal → wrapper rc=0, stdout populated
#   2. one hook fail → wrapper rc=0, tagged warn in stderr
#   3. all hooks timeout → wrapper rc=0, TIMEOUT warns
#   4. parallel mode wall time < serial sum (短縮確認)
#   5. regression: real hooks (mode-session-start / why-x5-reminder /
#                  session-help-surface / check-serena-mcp /
#                  next-actions-surface / mode-asana-prompt) work through wrapper

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WRAPPER="$REPO_ROOT/hooks/session-start-wrapper.sh"

PASS=0
FAIL=0
FAILED_CASES=()

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name (expected: '$expected', actual: '$actual')"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name")
  fi
}

assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  # -F: fixed string match (角括弧等の regex metachar を literal 扱い)
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name (missing '$needle' in haystack)"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name")
  fi
}

assert_le() {
  local name="$1" threshold="$2" actual="$3"
  if [ "$actual" -le "$threshold" ]; then
    echo "  PASS: $name ($actual <= $threshold)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name ($actual > $threshold)"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$name")
  fi
}

# Create fake hooks workspace for cases 1-4
FAKE_HOOK_DIR=$(mktemp -d -t "session-start-fake-hooks.XXXXXX")
trap 'rm -rf "$FAKE_HOOK_DIR"' EXIT

# Helper: build wrapper with custom HOOK_DIR by overriding hook list
make_fake_hook() {
  local name="$1" body="$2"
  cat > "$FAKE_HOOK_DIR/${name}.sh" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$FAKE_HOOK_DIR/${name}.sh"
}

# Run wrapper with custom SCRIPT_DIR (override hook locations via fake wrapper)
# We re-implement minimal wrapper logic by sourcing the wrapper with overridden SCRIPT_DIR
# Strategy: copy wrapper to FAKE_HOOK_DIR, then it picks up FAKE_HOOK_DIR/*.sh
# task-104 W1-8: wrapper が shim mode 化されたため、legacy 並列実行 path を強制的に有効化する env
# HC_SESSION_START_USE_WRAPPER=true を追加。これにより既存 smoke Case 1-5 は wrapper legacy 動作を検証。
run_fake_wrapper() {
  cp "$WRAPPER" "$FAKE_HOOK_DIR/wrapper.sh"
  chmod +x "$FAKE_HOOK_DIR/wrapper.sh"
  HC_SESSION_START_USE_WRAPPER=true "$@" bash "$FAKE_HOOK_DIR/wrapper.sh" </dev/null 2>"$FAKE_HOOK_DIR/stderr" >"$FAKE_HOOK_DIR/stdout"
  echo "$?"
}

echo "=== Case 1: all hooks normal → rc=0 + stdout populated ==="
make_fake_hook "hook-a" 'echo "HOOK_A_OUTPUT"; exit 0'
make_fake_hook "hook-b" 'echo "HOOK_B_OUTPUT"; exit 0'
make_fake_hook "hook-c" 'echo "HOOK_C_OUTPUT"; exit 0'
rc=$(HC_SESSION_START_PARALLEL_HOOKS="hook-a:hook-b:hook-c" run_fake_wrapper env)
assert_eq "case1.rc" "0" "$rc"
assert_contains "case1.stdout has HOOK_A_OUTPUT" "HOOK_A_OUTPUT" "$(cat "$FAKE_HOOK_DIR/stdout")"
assert_contains "case1.stdout has HOOK_B_OUTPUT" "HOOK_B_OUTPUT" "$(cat "$FAKE_HOOK_DIR/stdout")"
assert_contains "case1.stdout has HOOK_C_OUTPUT" "HOOK_C_OUTPUT" "$(cat "$FAKE_HOOK_DIR/stdout")"
# verify stable order (alphabetical by hook name)
first_hook=$(grep -E "^HOOK_[A-Z]_OUTPUT$" "$FAKE_HOOK_DIR/stdout" | head -1)
assert_eq "case1.stdout stable order (hook-a first)" "HOOK_A_OUTPUT" "$first_hook"

echo ""
echo "=== Case 2: one hook fail → rc=0 (fail-open) + tagged stderr ==="
make_fake_hook "hook-ok" 'echo "OK_OUTPUT"; exit 0'
make_fake_hook "hook-fail" 'echo "ERR_MSG" >&2; exit 1'
rc=$(HC_SESSION_START_PARALLEL_HOOKS="hook-ok:hook-fail" run_fake_wrapper env)
assert_eq "case2.rc" "0" "$rc"
assert_contains "case2.stdout has OK_OUTPUT" "OK_OUTPUT" "$(cat "$FAKE_HOOK_DIR/stdout")"
assert_contains "case2.stderr has tag prefix" "[hook-fail] ERR_MSG" "$(cat "$FAKE_HOOK_DIR/stderr")"

echo ""
echo "=== Case 3: all hooks timeout → rc=0 + TIMEOUT warns ==="
# Skip case3 if timeout/gtimeout not available
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  make_fake_hook "hook-slow" 'sleep 10; echo "SLOW_OUTPUT"'
  rc=$(HC_SESSION_START_PARALLEL_HOOKS="hook-slow" HC_SESSION_START_PARALLEL_TIMEOUT_SEC=1 run_fake_wrapper env)
  assert_eq "case3.rc" "0" "$rc"
  assert_contains "case3.stderr has TIMEOUT warn" "TIMEOUT" "$(cat "$FAKE_HOOK_DIR/stderr")"
else
  echo "  SKIP: timeout/gtimeout not available"
fi

echo ""
echo "=== Case 4: parallel wall time < serial sum ==="
make_fake_hook "hook-p1" 'sleep 0.2; echo "P1"'
make_fake_hook "hook-p2" 'sleep 0.2; echo "P2"'
make_fake_hook "hook-p3" 'sleep 0.2; echo "P3"'

now_ms() { python3 -c "import time; print(int(time.time()*1000))"; }

# Parallel
start=$(now_ms)
HC_SESSION_START_PARALLEL_HOOKS="hook-p1:hook-p2:hook-p3" HC_SESSION_START_PARALLEL_ENABLED=true \
  run_fake_wrapper env > /dev/null
end=$(now_ms)
parallel_ms=$((end-start))

# Serial
start=$(now_ms)
HC_SESSION_START_PARALLEL_HOOKS="hook-p1:hook-p2:hook-p3" HC_SESSION_START_PARALLEL_ENABLED=false \
  run_fake_wrapper env > /dev/null
end=$(now_ms)
serial_ms=$((end-start))

echo "  parallel: ${parallel_ms}ms / serial: ${serial_ms}ms"
# Parallel should be < serial / 2 (3 hooks sleeping 200ms each)
threshold=$((serial_ms / 2))
assert_le "case4.parallel < serial/2" "$threshold" "$parallel_ms"

echo ""
echo "=== Case 5: regression — real SessionStart hooks via wrapper ==="
# Use actual wrapper with default hooks (the production one)
# task-104 W1-8: wrapper が shim mode 化されたため HC_SESSION_START_USE_WRAPPER=true で legacy path 強制
real_rc=$(HC_SESSION_START_USE_WRAPPER=true bash "$WRAPPER" </dev/null 1>"$FAKE_HOOK_DIR/real-stdout" 2>"$FAKE_HOOK_DIR/real-stderr"; echo $?)
assert_eq "case5.rc" "0" "$real_rc"
# mode-session-start emits Serena resume reminder when .serena/memories/session/context.md exists
# why-x5-reminder emits a system-reminder unconditionally
real_stdout=$(cat "$FAKE_HOOK_DIR/real-stdout")
# At least one system-reminder block should appear
assert_contains "case5.real stdout has system-reminder block" "system-reminder" "$real_stdout"

echo ""
echo "================================"
echo "Summary: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed cases:"
  printf '  - %s\n' "${FAILED_CASES[@]}"
  exit 1
fi
echo "All cases passed."
exit 0
