#!/usr/bin/env bash
# session-help-surface-smoke.sh — task #11 smoke test
#
# 4 cases:
#   Case 1: default (HC_SESSION_HELP_* unset) → 簡潔版が出力される
#   Case 2: HC_SESSION_HELP_ENABLED=false → silent (出力なし)
#   Case 3: HC_SESSION_HELP_VERBOSE=true → 詳細版が追加出力
#   Case 4: 簡潔版に主要 command (`/save-state`, `/new-task`, `/mode`) が含まれる
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#
# 実行:
#   bash .claude/tests/session-help-surface-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/session-help-surface.sh"

PASS=0
FAIL=0
FAILED_CASES=()

# run_case <id> <desc> <test_fn>
run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

# === Case 1: default → 簡潔版出力 ===
case_1() {
  local output
  # 既存 env を unset して default 動作を再現
  output=$(unset HC_SESSION_HELP_ENABLED HC_SESSION_HELP_VERBOSE; bash "$HOOK" </dev/null 2>/dev/null)
  if [ -z "$output" ]; then
    printf 'expected non-empty output, got empty\n' >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q '主要 slash commands'; then
    printf 'expected "主要 slash commands" header, got: %s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'system-reminder'; then
    return 1
  fi
  return 0
}

# === Case 2: HC_SESSION_HELP_ENABLED=false → silent ===
case_2() {
  local output
  output=$(HC_SESSION_HELP_ENABLED=false bash "$HOOK" </dev/null 2>/dev/null)
  if [ -n "$output" ]; then
    printf 'expected silent, got: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

# === Case 3: HC_SESSION_HELP_VERBOSE=true → 詳細版追加 ===
case_3() {
  local output
  output=$(HC_SESSION_HELP_VERBOSE=true bash "$HOOK" </dev/null 2>/dev/null)
  if ! printf '%s' "$output" | grep -q '詳細 commands'; then
    printf 'expected "詳細 commands" verbose section, got: %s\n' "$output" >&2
    return 1
  fi
  # 簡潔版 + 詳細版の 2 つの system-reminder が出るはず
  local reminder_count
  reminder_count=$(printf '%s' "$output" | grep -c 'system-reminder' || true)
  if [ "$reminder_count" -lt 2 ]; then
    printf 'expected >=2 system-reminder occurrences (open+close tags x2 sections), got: %s\n' "$reminder_count" >&2
    return 1
  fi
  return 0
}

# === Case 4: 簡潔版に主要 command 含む ===
case_4() {
  local output
  output=$(unset HC_SESSION_HELP_ENABLED HC_SESSION_HELP_VERBOSE; bash "$HOOK" </dev/null 2>/dev/null)
  if ! printf '%s' "$output" | grep -q '/save-state'; then
    printf 'missing /save-state\n' >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q '/new-task'; then
    printf 'missing /new-task\n' >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q '/mode'; then
    printf 'missing /mode\n' >&2
    return 1
  fi
  return 0
}

printf '===== task #11 session-help-surface smoke =====\n'
run_case 1 'default -> 簡潔版出力' case_1
run_case 2 'ENABLED=false -> silent' case_2
run_case 3 'VERBOSE=true -> 詳細版追加' case_3
run_case 4 '簡潔版に /save-state /new-task /mode 含む' case_4

printf '\n===== Result =====\n'
printf 'PASS: %d / 4\n' "$PASS"
printf 'FAIL: %d / 4\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
