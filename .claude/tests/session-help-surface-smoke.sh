#!/usr/bin/env bash
# session-help-surface-smoke.sh — task #11 + Wave 1.6 smoke test
#
# Cases:
#   Case 1: default (HC_SESSION_HELP_* unset) → 1 行 pointer が出力される (marker 作成、task-68 §3.2 opt-in 化)
#   Case 2: HC_SESSION_HELP_ENABLED=false → silent (出力なし)
#   Case 3: HC_SESSION_HELP_FORCE=true + VERBOSE=true → 詳細版が追加出力
#   Case 4: FORCE=true の詳細 help に主要 command (`/save-state`, `/new-task`, `/mode`) が含まれる (task-68 §3.2)
#
# Wave 1.6 (2026-05-23) で追加された first-only 動作 + marker:
#   Case 5: HC_SESSION_HELP_FIRST_ONLY=true (default) + marker 既存 → silent
#   Case 6: HC_SESSION_HELP_FORCE=1 → marker 無視で詳細 help 強制表示
#   Case 7: HC_SESSION_HELP_FIRST_ONLY=false (旧挙動) + marker 既存 → 1 行 pointer 表示
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - 各 case は marker file を per-case 隔離 (TMP) して順序依存を排除
#
# 実行:
#   bash .claude/tests/session-help-surface-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/session-help-surface.sh"

TMP_BASE="$(mktemp -d /tmp/session-help-surface-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# marker path を case 毎に隔離 (env override `HC_SESSION_HELP_MARKER_PATH`)
# 各 case で uniq marker を使い、test 順序依存を排除
_marker_for() {
  local case_id="$1"
  printf '%s/marker-%s' "$TMP_BASE" "$case_id"
}

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

# === Case 1: default → 1 行 pointer 出力 (task-68 §3.2 opt-in 化) ===
case_1() {
  local marker
  marker=$(_marker_for 1)
  rm -f "$marker"
  local output
  # marker 未存在 + first-only default → 1 行 pointer が表示される
  output=$(unset HC_SESSION_HELP_ENABLED HC_SESSION_HELP_VERBOSE HC_SESSION_HELP_FORCE HC_SESSION_HELP_FIRST_ONLY; \
    HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
  if [ -z "$output" ]; then
    printf 'expected non-empty pointer output, got empty\n' >&2
    return 1
  fi
  # default は詳細 help 全文 (主要 slash commands header) を含まず、pointer (HC_SESSION_HELP_FORCE 案内) を含む
  if printf '%s' "$output" | grep -q '主要 slash commands'; then
    printf 'expected pointer-only default (no 主要 slash commands header), got full help: %s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'HC_SESSION_HELP_FORCE'; then
    printf 'expected pointer mentioning HC_SESSION_HELP_FORCE, got: %s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'system-reminder'; then
    return 1
  fi
  # marker が作成されているはず
  if [ ! -f "$marker" ]; then
    printf 'expected marker created at %s\n' "$marker" >&2
    return 1
  fi
  return 0
}

# === Case 2: HC_SESSION_HELP_ENABLED=false → silent ===
case_2() {
  local marker
  marker=$(_marker_for 2)
  rm -f "$marker"
  local output
  output=$(HC_SESSION_HELP_ENABLED=false HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
  if [ -n "$output" ]; then
    printf 'expected silent, got: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

# === Case 3: HC_SESSION_HELP_FORCE=true + VERBOSE=true → 詳細版追加 (task-68 §3.2: VERBOSE は FORCE 配下) ===
case_3() {
  local marker
  marker=$(_marker_for 3)
  rm -f "$marker"
  local output
  output=$(HC_SESSION_HELP_FORCE=true HC_SESSION_HELP_VERBOSE=true HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
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

# === Case 4: FORCE=true 詳細 help に主要 command 含む (task-68 §3.2) ===
case_4() {
  local marker
  marker=$(_marker_for 4)
  rm -f "$marker"
  local output
  output=$(HC_SESSION_HELP_FORCE=true HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
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

# === Case 5 (W1.6): marker 既存 + first-only default → silent ===
case_5_marker_exists_silent() {
  local marker
  marker=$(_marker_for 5)
  # marker を事前に作成 (初回 session help 完了済の状態)
  : > "$marker"
  local output
  output=$(unset HC_SESSION_HELP_ENABLED HC_SESSION_HELP_VERBOSE HC_SESSION_HELP_FORCE HC_SESSION_HELP_FIRST_ONLY; \
    HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
  if [ -n "$output" ]; then
    printf 'expected silent (marker exists, first-only default), got: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

# === Case 6 (W1.6): HC_SESSION_HELP_FORCE=1 → marker 無視で強制表示 ===
case_6_force_overrides_marker() {
  local marker
  marker=$(_marker_for 6)
  # marker 既存
  : > "$marker"
  local output
  output=$(HC_SESSION_HELP_FORCE=1 HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
  if [ -z "$output" ]; then
    printf 'expected force display (marker ignored), got empty\n' >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q '主要 slash commands'; then
    printf 'expected force display content, got: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

# === Case 7 (W1.6): HC_SESSION_HELP_FIRST_ONLY=false → 旧挙動 (marker 既存でも毎回表示) ===
# task-68 §3.2: FORCE 未指定なので表示されるのは 1 行 pointer (詳細 help は opt-in)。
case_7_first_only_false_always_show() {
  local marker
  marker=$(_marker_for 7)
  # marker 既存
  : > "$marker"
  local output
  output=$(HC_SESSION_HELP_FIRST_ONLY=false HC_SESSION_HELP_MARKER_PATH="$marker" bash "$HOOK" </dev/null 2>/dev/null)
  if [ -z "$output" ]; then
    printf 'expected display (FIRST_ONLY=false), got empty\n' >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'HC_SESSION_HELP_FORCE'; then
    printf 'expected pointer content (HC_SESSION_HELP_FORCE), got: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

printf '===== task #11 + Wave 1.6 session-help-surface smoke =====\n'
run_case 1 'default -> 1 行 pointer 出力 + marker 作成 (§3.2 opt-in)' case_1
run_case 2 'ENABLED=false -> silent' case_2
run_case 3 'FORCE+VERBOSE -> 詳細版追加' case_3
run_case 4 'FORCE 詳細 help に /save-state /new-task /mode 含む' case_4
run_case 5 'W1.6: marker 既存 + first-only default -> silent' case_5_marker_exists_silent
run_case 6 'W1.6: FORCE=1 -> marker 無視で詳細 help 表示' case_6_force_overrides_marker
run_case 7 'W1.6: FIRST_ONLY=false -> pointer 表示' case_7_first_only_false_always_show

printf '\n===== Result =====\n'
printf 'PASS: %d / 7\n' "$PASS"
printf 'FAIL: %d / 7\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
