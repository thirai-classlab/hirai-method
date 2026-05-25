#!/usr/bin/env bash
# list-md-plan-first-reminder-smoke.sh — task #35 smoke test
#
# Cases:
#   Case 1: 条件成立 (draft 3 + list.md task 行 0) → stderr に keyword 出力
#   Case 2: 不成立 N=2 境界 (draft 2 + list.md task 行 0) → stderr 空
#   Case 3: bypass env (HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false) → stderr 空
#   Case 4: fail-open guard (list.md 不在) → exit 0 + stderr 空
#   Case 5: list.md に task 行有り (roadmap 進行済) → 誤発火しない
#   Case 6: draft template (_*.md) はカウント除外
#   Case 7: N=3 exact boundary (draft 3 + list.md 空) → 発火 (PR-H1)
#   Case 8: 条件成立時 exit code 0 を assert (PR-H2)
#   Case 9: draft_dir 不在 fail-open (list.md 存在 / draft 不在) → exit 0 + silent (QA-M1)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH 遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - 各 case は tmp dir を per-case 隔離して順序依存を排除
#
# 実行:
#   bash .claude/tests/list-md-plan-first-reminder-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/list-md-plan-first-reminder.sh"

TMP_BASE="$(mktemp -d /tmp/list-md-plan-first-reminder-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# tmp root per-case (隔離して順序依存排除)
_root_for() {
  local case_id="$1"
  printf '%s/root-%s' "$TMP_BASE" "$case_id"
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

# fixture: list.md (task エントリ行 0、コメント・凡例・header のみ)
_make_empty_list_md() {
  local path="$1"
  cat > "$path" <<'EOF'
# Task List

> 凡例: 📝 設計（未承認）/ 🔲 未着手 / 🔄 進行中 / ✅ 完了 / ⏸️ 保留

| # | Status | Task | 概要 | 詳細 |
|---|---|---|---|---|
EOF
}

# === Case 1: 条件成立 (draft 3 + list.md 空) ===
case_1_condition_met() {
  local root
  root=$(_root_for 1)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -z "$err" ]; then
    printf 'expected stderr output, got empty\n' >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'list.md plan-first'; then
    printf 'missing "list.md plan-first" keyword. stderr was:\n%s\n' "$err" >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'system-reminder'; then
    printf 'missing system-reminder tag. stderr was:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 2: 不成立 N=2 境界 (draft 2 のみ) ===
case_2_boundary_n2() {
  local root
  root=$(_root_for 2)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -n "$err" ]; then
    printf 'expected silent (N=2 boundary), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 3: bypass env ===
case_3_bypass_env() {
  local root
  root=$(_root_for 3)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false \
    CLAUDE_PROJECT_DIR="$root" \
    bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -n "$err" ]; then
    printf 'expected silent (bypass env), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 4: fail-open guard (list.md 不在) ===
case_4_fail_open_no_list_md() {
  local root
  root=$(_root_for 4)
  mkdir -p "$root/docs/draft"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  # docs/tasks/list.md は意図的に不在

  local err rc
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 (fail-open), got %d\n' "$rc" >&2
    return 1
  fi
  if [ -n "$err" ]; then
    printf 'expected silent (list.md absent fail-open), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 5: 条件成立だが list.md に task 行有り (= roadmap 進行済) ===
# (任意拡張: 既存 plan-first 適用済 session で誤発火しないこと)
case_5_list_has_entries() {
  local root
  root=$(_root_for 5)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  cat > "$root/docs/tasks/list.md" <<'EOF'
# Task List

| # | Status | Task | 概要 | 詳細 |
|---|---|---|---|---|
| 1 | 📝 | Task: foo | foo の plan-first row | task-1-foo.md |
EOF

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -n "$err" ]; then
    printf 'expected silent (list.md has entries), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 6: draft template (_TEMPLATE.md / _DRAFT_TEMPLATE.md) はカウントしない ===
case_6_template_excluded() {
  local root
  root=$(_root_for 6)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  # template 2 件 + 通常 draft 2 件 = 通常カウント 2 (template 除外で 3 未満)
  touch "$root/docs/draft/_TEMPLATE.md" "$root/docs/draft/_DRAFT_TEMPLATE.md"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -n "$err" ]; then
    printf 'expected silent (templates excluded, 2 real drafts), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 7: N=3 exact boundary (発火境界、PR-H1 finding 解消) ===
# Case 2 (N=2、境界 -1) では発火しないことを確認済。
# 本 case は N=3 (境界そのもの = 発火閾値) で発火することを assert。
# 閾値変更 PR で regression が素通りするのを防ぐ。
case_7_n3_exact_boundary() {
  local root
  root=$(_root_for 7)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  # N=3 exact (発火境界)
  touch "$root/docs/draft/a.md" "$root/docs/draft/b.md" "$root/docs/draft/c.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -z "$err" ]; then
    printf 'expected stderr output at N=3 exact boundary, got empty\n' >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'list.md plan-first'; then
    printf 'missing "list.md plan-first" keyword at N=3 boundary. stderr:\n%s\n' "$err" >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'system-reminder'; then
    printf 'missing system-reminder tag at N=3 boundary. stderr:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 8: 条件成立時 exit code 0 を assert (PR-H2 finding 解消) ===
# Case 1 は stderr keyword のみ検証、exit code を assert していなかった。
# hook が warn 出しつつ非 0 で終了する実装 bug を本 case で独立検証する。
case_8_exit_code_zero_on_trigger() {
  local root
  root=$(_root_for 8)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/a.md" "$root/docs/draft/b.md" "$root/docs/draft/c.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  # stderr/stdout は捨て、exit code のみ assert
  CLAUDE_PROJECT_DIR="$root" \
    bash "$HOOK" </dev/null >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 on trigger condition, got %d\n' "$rc" >&2
    return 1
  fi
  return 0
}

# === Case 9: draft_dir 不在 fail-open (QA-M1 finding 解消) ===
# Case 4 は list.md 不在のみ検証、draft_dir 不在の別 fail-open 分岐は未テスト。
# hook L72 `[ -d "$draft_dir" ] || exit 0` の動作を独立検証する。
case_9_no_draft_dir_failopen() {
  local root
  root=$(_root_for 9)
  mkdir -p "$root/docs/tasks"
  # docs/draft/ は意図的に不在
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err rc
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 (draft_dir absent fail-open), got %d\n' "$rc" >&2
    return 1
  fi
  if [ -n "$err" ]; then
    printf 'expected silent (draft_dir absent fail-open), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

printf '===== task #35 list-md-plan-first-reminder smoke =====\n'
run_case 1 'condition met (draft 3 + list empty) -> stderr has keyword' case_1_condition_met
run_case 2 'N=2 boundary (draft 2) -> silent' case_2_boundary_n2
run_case 3 'bypass env (HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false) -> silent' case_3_bypass_env
run_case 4 'fail-open (list.md absent) -> exit 0 + silent' case_4_fail_open_no_list_md
run_case 5 'list.md has task entries -> silent (no false-positive)' case_5_list_has_entries
run_case 6 'draft templates (_*.md) excluded from count' case_6_template_excluded
run_case 7 'N=3 exact boundary -> fires (PR-H1)' case_7_n3_exact_boundary
run_case 8 'exit code 0 on trigger condition (PR-H2)' case_8_exit_code_zero_on_trigger
run_case 9 'draft_dir absent -> exit 0 + silent (QA-M1)' case_9_no_draft_dir_failopen

printf '\n===== Result =====\n'
printf 'PASS: %d / 9\n' "$PASS"
printf 'FAIL: %d / 9\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
