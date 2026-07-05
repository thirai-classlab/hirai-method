#!/usr/bin/env bash
# list-md-plan-first-reminder-smoke.sh — task #35 smoke test (task #91 Step 3 で 13 case 化)
#
# Cases:
#   Case 1:  tier A 条件成立 (draft 3 + list.md task 行 0) → stderr に keyword 出力
#   Case 2:  draft 2 + task 0 (bootstrap 期) → tier B 発火 (task #91 期待値反転: 旧 silent)
#   Case 3:  bypass env (HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false) → stderr 空
#   Case 4:  fail-open guard (list.md 不在) → exit 0 + stderr 空
#   Case 5:  list.md に task 行有り (roadmap 進行済) → 誤発火しない
#   Case 6:  draft template (_*.md) カウント除外 → 実 draft 2 は tier B 発火
#            (tier A に昇格しないことを assert、task #91 期待値反転: 旧 silent)
#   Case 7:  N=3 exact boundary (draft 3 + list.md 空) → tier A 発火 (PR-H1)
#   Case 8:  条件成立時 exit code 0 を assert (PR-H2)
#   Case 9:  draft_dir 不在 fail-open (list.md 存在 / draft 不在) → exit 0 + silent (QA-M1)
#   Case 10: draft 0 + task 0 (bootstrap 期そのもの、stdin 空 = 抽出失敗 fallback) → tier B 発火 (task #91)
#   Case 11: draft 0 + task 0 + stdin {"source":"resume"} → silent + exit 0 (tier B source gating、task #91)
#   Case 12: draft 0 + task 0 + stdin {"source":"startup"} / {"source":"clear"} → tier B 発火 (明示 source、task #91)
#   Case 13: draft 3 + task 0 + stdin {"source":"resume"} → tier A 発火 (非 gating regression)
#            + golden diff で tier A message 不変 (1 文字も変更しない規約) を assert (task #91)
#
# feature toggle 注入 (task #91 Step 3、draft §3 Step 3):
#   本 repo (harness-dev preset) は harness-config.yml の feature_task_rule_guard_enabled: false
#   により hook が feature check で no-op になるため、全 13 case で per-case
#   HC_FEATURE_TASK_RULE_GUARD_ENABLED=true を注入する (env preset は yml false に勝つ、
#   config-loader Step 1b)。発火系 case (1/2/6/7/8/10/12/13) は注入なしでは silent FAIL、
#   silent 系 case (3/4/5/9/11) も注入なしでは feature no-op による trivially-pass
#   (vacuous test) になるため、全 case 注入で実 logic 経路を検証する。
#   これにより harness-dev でも 13/13 PASS が成立し、run-all-smokes.sh の
#   expected-fail manifest から本 smoke は削除済 (task #91 Step 3)。
#
# tier 判別 keyword (hook の 2-tier 化、task #91 Step 2):
#   tier A 固有: 「経路 B」 (batch planning full message、draft >= 3)
#   tier B 固有: 「台帳が空」 (bootstrap 短文 message、draft < 3)
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

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/list-md-plan-first-reminder-smoke.XXXXXX" 2>/dev/null || true)"
if [ -z "$TMP_BASE" ] || [ ! -d "$TMP_BASE" ]; then
  printf 'FATAL: mktemp -d failed\n' >&2
  exit 1
fi
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

# assert helper: tier B 発火 (keyword + tier B 固有文言あり ∧ tier A 固有文言なし)
_assert_tier_b() {
  local err="$1"
  local ctx="$2"
  if [ -z "$err" ]; then
    printf 'expected tier B stderr output (%s), got empty\n' "$ctx" >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'list.md plan-first'; then
    printf 'missing "list.md plan-first" keyword (%s). stderr:\n%s\n' "$ctx" "$err" >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q 'system-reminder'; then
    printf 'missing system-reminder tag (%s). stderr:\n%s\n' "$ctx" "$err" >&2
    return 1
  fi
  if ! printf '%s' "$err" | grep -q '台帳が空'; then
    printf 'missing tier B marker "台帳が空" (%s). stderr:\n%s\n' "$ctx" "$err" >&2
    return 1
  fi
  if printf '%s' "$err" | grep -q '経路 B'; then
    printf 'unexpected tier A marker "経路 B" — tier A に昇格 (%s). stderr:\n%s\n' "$ctx" "$err" >&2
    return 1
  fi
  return 0
}

# === Case 1: tier A 条件成立 (draft 3 + list.md 空) ===
case_1_condition_met() {
  local root
  root=$(_root_for 1)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
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

# === Case 2: draft 2 + task 0 → tier B 発火 (task #91 期待値反転: 旧 silent) ===
# 発火条件緩和の本体。draft < 3 の bootstrap 期でも task 行 0 なら tier B 短文が出る。
case_2_boundary_n2() {
  local root
  root=$(_root_for 2)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  _assert_tier_b "$err" 'Case 2 draft 2 + task 0'
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
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
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
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
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
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  if [ -n "$err" ]; then
    printf 'expected silent (list.md has entries), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 6: draft template (_TEMPLATE.md / _DRAFT_TEMPLATE.md) はカウントしない ===
# task #91 期待値反転: 旧 silent → 実 draft 2 (template 除外後) は tier B 発火。
# 検証意図を「tier A に昇格しない」に変更 (template が count されると draft 4 = tier A になる)。
case_6_template_excluded() {
  local root
  root=$(_root_for 6)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  # template 2 件 + 通常 draft 2 件 = 通常カウント 2 (template 除外で 3 未満 → tier B)
  touch "$root/docs/draft/_TEMPLATE.md" "$root/docs/draft/_DRAFT_TEMPLATE.md"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  _assert_tier_b "$err" 'Case 6 templates excluded, 2 real drafts'
}

# === Case 7: N=3 exact boundary (発火境界、PR-H1 finding 解消) ===
# Case 2 (N=2、境界 -1) は tier B。本 case は N=3 (境界そのもの = tier A 閾値) で
# tier A が発火することを assert。閾値変更 PR で regression が素通りするのを防ぐ。
case_7_n3_exact_boundary() {
  local root
  root=$(_root_for 7)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  # N=3 exact (tier A 発火境界)
  touch "$root/docs/draft/a.md" "$root/docs/draft/b.md" "$root/docs/draft/c.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
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
  # (task #91: feature env 注入で発火経路を実際に通す — 注入なしだと no-op exit 0 の vacuous test)
  (
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null >/dev/null 2>&1
  )
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 on trigger condition, got %d\n' "$rc" >&2
    return 1
  fi
  return 0
}

# === Case 9: draft_dir 不在 fail-open (QA-M1 finding 解消) ===
# Case 4 は list.md 不在のみ検証、draft_dir 不在の別 fail-open 分岐は未テスト。
# hook `[ -d "$draft_dir" ] || exit 0` の動作を独立検証する (task #91 でも保守的に維持、draft §「open questions」3)。
case_9_no_draft_dir_failopen() {
  local root
  root=$(_root_for 9)
  mkdir -p "$root/docs/tasks"
  # docs/draft/ は意図的に不在
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err rc
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
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

# === Case 10 (task #91): draft 0 + task 0 (bootstrap 期そのもの) → tier B 発火 ===
# stdin は </dev/null (空) = source 抽出失敗 → startup 扱い fallback で発火 (fail 方向設計)。
case_10_bootstrap_tier_b() {
  local root
  root=$(_root_for 10)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  # draft 0 件 (install 直後の bootstrap 期)
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
      bash "$HOOK" </dev/null 2>&1 >/dev/null
  )
  _assert_tier_b "$err" 'Case 10 draft 0 + task 0, empty stdin fallback'
}

# === Case 11 (task #91): stdin {"source":"resume"} → silent + exit 0 (tier B source gating) ===
case_11_resume_gated_silent() {
  local root
  root=$(_root_for 11)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err rc
  err=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    printf '%s' '{"source":"resume"}' \
      | CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
        bash "$HOOK" 2>&1 >/dev/null
  )
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 (resume gated skip), got %d\n' "$rc" >&2
    return 1
  fi
  if [ -n "$err" ]; then
    printf 'expected silent (source=resume gated), got:\n%s\n' "$err" >&2
    return 1
  fi
  return 0
}

# === Case 12 (task #91): stdin {"source":"startup"} / {"source":"clear"} → tier B 発火 ===
# source gating whitelist の明示 2 値 (startup / clear) を両方 assert。
case_12_startup_clear_fire() {
  local root
  root=$(_root_for 12)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local err_startup err_clear
  err_startup=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    printf '%s' '{"source":"startup"}' \
      | CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
        bash "$HOOK" 2>&1 >/dev/null
  )
  _assert_tier_b "$err_startup" 'Case 12 source=startup' || return 1

  err_clear=$(
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    printf '%s' '{"source":"clear"}' \
      | CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
        bash "$HOOK" 2>&1 >/dev/null
  )
  _assert_tier_b "$err_clear" 'Case 12 source=clear' || return 1
  return 0
}

# === Case 13 (task #91): draft 3 + task 0 + stdin {"source":"resume"} → tier A 発火 + golden diff ===
# tier A は非 gating (全 source で発火、現行互換) の regression 検証。
# 併せて tier A message の golden diff で「1 文字も変更しない」規約 (draft §4 リスク表) を byte assert。
case_13_tier_a_resume_golden() {
  local root
  root=$(_root_for 13)
  mkdir -p "$root/docs/draft" "$root/docs/tasks"
  touch "$root/docs/draft/foo.md" "$root/docs/draft/bar.md" "$root/docs/draft/baz.md"
  _make_empty_list_md "$root/docs/tasks/list.md"

  local actual="$root/actual-stderr.txt"
  local golden="$root/golden-tier-a.txt"

  (
    unset HC_LIST_PLAN_FIRST_REMINDER_ENABLED
    printf '%s' '{"source":"resume"}' \
      | CLAUDE_PROJECT_DIR="$root" HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
        bash "$HOOK" >/dev/null 2>"$actual"
  )
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'expected exit 0 (tier A on resume), got %d\n' "$rc" >&2
    return 1
  fi

  # tier A keyword (非 gating で resume でも発火)
  if ! grep -q '経路 B' "$actual"; then
    printf 'missing tier A marker "経路 B" on source=resume (tier A must not be gated). stderr:\n' >&2
    cat "$actual" >&2
    return 1
  fi

  # golden diff: 現行 tier A full message (hook heredoc 展開後、draft_count=3) と byte 一致
  cat > "$golden" <<'GOLDEN'

<system-reminder>
[list.md plan-first] batch planning 経路 B 不在を検出しました:
- `docs/draft/*.md` が 3 件存在し、かつ `docs/tasks/list.md` に task エントリ行 (📝/🔲/🔄/✅) が 0 件です。
- master roadmap で N ≥ 3 task を一括計画する場合、`.claude/rules/task-management.md` §plan-first 経路 B に従い list.md に N 行 **📝 設計（未承認）** で先置きしてください (main 直接 Edit、task-rule-guard.sh 既存 exempt 通過)。
- 規範: `.claude/rules/task-management.md` §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」
- bypass: `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false` または harness-config.yml `list_plan_first_reminder_enabled: false`
</system-reminder>
GOLDEN

  if ! diff -u "$golden" "$actual" >&2; then
    printf 'tier A message drifted from golden (規約: tier A は 1 文字も変更しない — draft §4 リスク表)\n' >&2
    return 1
  fi
  return 0
}

printf '===== task #35 list-md-plan-first-reminder smoke (task #91: 13 case) =====\n'
run_case 1 'tier A condition met (draft 3 + list empty) -> stderr has keyword' case_1_condition_met
run_case 2 'draft 2 + task 0 -> tier B fires (task #91: was silent)' case_2_boundary_n2
run_case 3 'bypass env (HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false) -> silent' case_3_bypass_env
run_case 4 'fail-open (list.md absent) -> exit 0 + silent' case_4_fail_open_no_list_md
run_case 5 'list.md has task entries -> silent (no false-positive)' case_5_list_has_entries
run_case 6 'draft templates (_*.md) excluded -> tier B (no tier A promotion)' case_6_template_excluded
run_case 7 'N=3 exact boundary -> tier A fires (PR-H1)' case_7_n3_exact_boundary
run_case 8 'exit code 0 on trigger condition (PR-H2)' case_8_exit_code_zero_on_trigger
run_case 9 'draft_dir absent -> exit 0 + silent (QA-M1)' case_9_no_draft_dir_failopen
run_case 10 'bootstrap (draft 0 + task 0, empty stdin fallback) -> tier B fires' case_10_bootstrap_tier_b
run_case 11 'source gating: {"source":"resume"} -> silent + exit 0' case_11_resume_gated_silent
run_case 12 'source gating: startup / clear -> tier B fires' case_12_startup_clear_fire
run_case 13 'tier A non-gating on resume + golden diff unchanged' case_13_tier_a_resume_golden

printf '\n===== Result =====\n'
printf 'PASS: %d / 13\n' "$PASS"
printf 'FAIL: %d / 13\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
