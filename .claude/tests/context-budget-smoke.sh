#!/usr/bin/env bash
# context-budget-smoke.sh — smoke tests for .claude/hooks/context-budget.sh
#
# 目的:
#   context-budget hook が 60 / 80 / 95% の各閾値で正しく発火し、
#   同一 tier の重複発火を抑制し、Normal モードでは no-op であることを検証する。
#
# 前提:
#   - jq が PATH にある
#   - tac は不要 (awk fallback でも通る)
#   - fixtures/transcript-*.jsonl を使用 (1M token = HC_CONTEXT_BUDGET_LIMIT 既定)
#
# 実行:
#   bash .claude/tests/context-budget-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1

HOOK=".claude/hooks/context-budget.sh"
FIXTURES=".claude/tests/fixtures"
STATE_BASE="/tmp/context-budget-smoke-$$"

PASS=0
FAIL=0

trap 'rm -rf "$STATE_BASE"' EXIT

mkdir -p "$STATE_BASE"

_make_input() {
  local transcript="$1"
  local session="$2"
  printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$session"
}

# usage: assert_case <label> <expect: fire|silent> <expected_tier> <env vars...> -- <transcript> <session>
run_case() {
  local label="$1" expect="$2" expected_tier="$3"
  shift 3
  local env_args=()
  while [ "$1" != "--" ]; do
    env_args+=("$1")
    shift
  done
  shift  # consume --
  local transcript="$1" session="$2"

  local state_dir="$STATE_BASE/$session"
  mkdir -p "$state_dir"

  local input
  input=$(_make_input "$transcript" "$session")

  # env 値で hook を起動
  local out
  out=$(echo "$input" \
    | env "${env_args[@]}" \
        HC_CONTEXT_BUDGET_STATE_DIR="$state_dir" \
        bash "$HOOK" 2>&1)
  local exit_code=$?

  local fired="silent"
  if printf '%s' "$out" | grep -q "system-reminder"; then
    fired="fire"
  fi

  # tier check
  local actual_tier="-"
  if [ -f "$state_dir/${session}.warned" ]; then
    # marker は "|TIER|" 形式で連結される
    actual_tier=$(cat "$state_dir/${session}.warned" | tr '|' '\n' | grep -E '^[0-9]+$' | tail -1)
    actual_tier="${actual_tier:--}"
  fi

  local ok=1
  [ "$fired" = "$expect" ] || ok=0
  [ "$exit_code" = "0" ] || ok=0
  if [ "$expect" = "fire" ] && [ -n "$expected_tier" ]; then
    [ "$actual_tier" = "$expected_tier" ] || ok=0
  fi

  if [ "$ok" = "1" ]; then
    printf "PASS: %s (fired=%s tier=%s exit=%s)\n" "$label" "$fired" "$actual_tier" "$exit_code"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s (expected=%s tier=%s; got fired=%s tier=%s exit=%s)\n" \
      "$label" "$expect" "$expected_tier" "$fired" "$actual_tier" "$exit_code"
    printf "  ---- output ----\n%s\n  ---- end ----\n" "$out"
    FAIL=$((FAIL + 1))
  fi
}

# 1. 60% tier: ratio 60.5% (605K / 1M) ≥ 0.60 → fire tier 60
# task-74: repo の context_budget_threshold=0.66 に依存せず HC_CONTEXT_BUDGET_THRESHOLD=0.60 を
# 明示 set して決定論化 (Case 10 の env override パターン踏襲、spec-drift 修正)。
run_case "60pct fires at threshold 0.60 (loop mode)" "fire" "60" \
  HC_MODE=loop HC_CONTEXT_BUDGET_THRESHOLD=0.60 -- "$FIXTURES/transcript-60pct.jsonl" "case-60"

# 2. 80% tier: ratio 81.0% (810K / 1M) ≥ 0.80 → fire tier 80
run_case "80pct fires (loop mode)" "fire" "80" \
  HC_MODE=loop -- "$FIXTURES/transcript-80pct.jsonl" "case-80"

# 3. 95% tier: ratio 96.0% (960K / 1M) ≥ 0.95 → fire tier 95
run_case "95pct fires (loop mode)" "fire" "95" \
  HC_MODE=loop -- "$FIXTURES/transcript-95pct.jsonl" "case-95"

# 4. 50% tier: ratio 50.0% (500K / 1M) < 0.60 → silent
run_case "50pct silent at default threshold" "silent" "" \
  HC_MODE=loop -- "$FIXTURES/transcript-50pct.jsonl" "case-50"

# 5. Normal モード: 95% transcript でも fire しない
run_case "Normal mode silent even at 95pct" "silent" "" \
  HC_MODE=normal -- "$FIXTURES/transcript-95pct.jsonl" "case-normal"

# 6. spam 防止: 同一 session で 60% を 2 回呼ぶ → 1 回目 fire / 2 回目 silent
# task-74: 60pct fixture (0.605) は repo threshold 0.66 未満で silent になるため、
# HC_CONTEXT_BUDGET_THRESHOLD=0.60 を明示 set して決定論化 (Case 1 と同じ spec-drift 修正)。
{
  STATE_DIR="$STATE_BASE/case-spam"
  mkdir -p "$STATE_DIR"
  INPUT=$(_make_input "$FIXTURES/transcript-60pct.jsonl" "case-spam")

  # 1st call: must fire
  out1=$(echo "$INPUT" | env HC_MODE=loop HC_CONTEXT_BUDGET_THRESHOLD=0.60 HC_CONTEXT_BUDGET_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)
  # 2nd call: must NOT fire (already warned for tier 60)
  out2=$(echo "$INPUT" | env HC_MODE=loop HC_CONTEXT_BUDGET_THRESHOLD=0.60 HC_CONTEXT_BUDGET_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)

  fire1="no"; fire2="no"
  printf '%s' "$out1" | grep -q "system-reminder" && fire1="yes"
  printf '%s' "$out2" | grep -q "system-reminder" && fire2="yes"

  if [ "$fire1" = "yes" ] && [ "$fire2" = "no" ]; then
    printf "PASS: spam prevention — 1st fires, 2nd silent\n"
    PASS=$((PASS + 1))
  else
    printf "FAIL: spam prevention (1st=%s 2nd=%s)\n" "$fire1" "$fire2"
    FAIL=$((FAIL + 1))
  fi
}

# 7. tier escalation: 60% 通知済 session で 80% transcript が来たら fire 80
{
  STATE_DIR="$STATE_BASE/case-escalate"
  mkdir -p "$STATE_DIR"

  # prime state with tier 60 already warned
  echo -n "|60|" > "$STATE_DIR/case-escalate.warned"

  INPUT=$(_make_input "$FIXTURES/transcript-80pct.jsonl" "case-escalate")
  out=$(echo "$INPUT" | env HC_MODE=loop HC_CONTEXT_BUDGET_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)

  fire="no"
  printf '%s' "$out" | grep -q "system-reminder" && fire="yes"

  marker=$(cat "$STATE_DIR/case-escalate.warned" 2>/dev/null)
  if [ "$fire" = "yes" ] && [ "$marker" = "|60||80|" ]; then
    printf "PASS: tier escalation — 60 warned, 80 fires and appends marker (marker=%s)\n" "$marker"
    PASS=$((PASS + 1))
  else
    printf "FAIL: tier escalation (fire=%s marker=%s)\n" "$fire" "$marker"
    FAIL=$((FAIL + 1))
  fi
}

# 8. HC_CONTEXT_BUDGET_ENABLED=false で no-op
run_case "disabled via env" "silent" "" \
  HC_MODE=loop HC_CONTEXT_BUDGET_ENABLED=false -- "$FIXTURES/transcript-95pct.jsonl" "case-disabled"

# 9. transcript_path 不在 → silent exit 0
{
  STATE_DIR="$STATE_BASE/case-nofile"
  mkdir -p "$STATE_DIR"
  INPUT=$(_make_input "$FIXTURES/does-not-exist.jsonl" "case-nofile")
  out=$(echo "$INPUT" | env HC_MODE=loop HC_CONTEXT_BUDGET_STATE_DIR="$STATE_DIR" bash "$HOOK" 2>&1)
  code=$?
  fire="no"
  printf '%s' "$out" | grep -q "system-reminder" && fire="yes"
  if [ "$fire" = "no" ] && [ "$code" = "0" ]; then
    printf "PASS: missing transcript_path silent exit 0\n"
    PASS=$((PASS + 1))
  else
    printf "FAIL: missing transcript_path (fire=%s code=%s)\n" "$fire" "$code"
    FAIL=$((FAIL + 1))
  fi
}

# 10. lower threshold env override: 50% transcript + threshold 0.40 → fire 60
run_case "env threshold override (0.40 over 50pct)" "fire" "60" \
  HC_MODE=loop HC_CONTEXT_BUDGET_THRESHOLD=0.40 -- "$FIXTURES/transcript-50pct.jsonl" "case-thr"

# 11. regression guard: mode-loader must not leak set -e / pipefail to caller
{
  out=$(
    env HC_MODE=loop bash -c '
      set -u
      source .claude/hooks/lib/mode-loader.sh
      m=$(load_mode)
      # report leaked options
      case "$-" in *e*) echo "errexit_leak"; ;; esac
      if shopt -po pipefail 2>/dev/null | grep -q "set -o pipefail"; then
        echo "pipefail_leak"
      fi
      echo "MODE=$m"
    '
  )
  if printf '%s' "$out" | grep -q "MODE=loop" \
     && ! printf '%s' "$out" | grep -q "errexit_leak" \
     && ! printf '%s' "$out" | grep -q "pipefail_leak"; then
    printf "PASS: mode-loader does not leak set -e / pipefail\n"
    PASS=$((PASS + 1))
  else
    printf "FAIL: mode-loader option leak detected\n%s\n" "$out"
    FAIL=$((FAIL + 1))
  fi
}

printf "\n=== context-budget smoke: %d passed, %d failed ===\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
