#!/usr/bin/env bash
# shellcheck disable=SC2329  # functions invoked indirectly via "$test_fn"
# .claude/tests/reviewer-count-guard-smoke.sh — task-64 Step 5
#
# reviewer-count-guard.sh hook の smoke test。
#
# 設計起源:
#   docs/draft/reviewer-count-enforcement.md §3.3 (P2 強制 hook)
#
# Cases:
#   Case 1:  review subagent 1 体目 (count <= max) → silent (warn なし)
#   Case 2:  max+1 体目 → warn 注入 (review_max_count_<cat> 超過)
#   Case 3:  feature toggle false → no-op (silent)
#   Case 4:  bypass env (HC_REVIEWER_COUNT_GUARD_ENABLED=false) → no-op
#   Case 4b: bypass env (ECC_REVIEWER_COUNT_OFF=1) → no-op
#   Case 5:  review でない Agent 起動 (実装 keyword のみ) → count せず pass (silent)
#   Case 6:  category 推定 — test / design / module / system 別に正しい max を使う
#   Case 7:  unknown category (reviewer 一般) → max(全 cat) を緩い上限に
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - CLAUDE_PROJECT_DIR + HC_REVIEWER_COUNT_STATE_DIR を必ず設定 (production state 汚染回避)
#   - 各 case は独立 tmp dir + 独立 session_id で state リーク防止
#
# 実行:  bash .claude/tests/reviewer-count-guard-smoke.sh
# 終了:  0 = 全 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/reviewer-count-guard.sh"

TMP_BASE="$(mktemp -d /tmp/reviewer-count-guard-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=()

_root_for() {
  printf '%s/root-%s' "$TMP_BASE" "$1"
}

run_case_verbose() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"

  if [ ! -f "$HOOK" ]; then
    printf '  SKIP  Case %s: %s  [hook not found]\n' "$case_id" "$desc"
    SKIP=$((SKIP+1))
    return
  fi

  local diag_file
  diag_file="$(mktemp "${TMP_BASE}/diag.XXXXXX")"

  if ( set -uo pipefail; "$test_fn" ) >"$diag_file" 2>&1; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    printf '        --- diagnostic ---\n'
    sed 's/^/        /' "$diag_file"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
  rm -f "$diag_file"
}

# Seed state file with an existing count for category <cat>.
#   $1 = root dir, $2 = session_id, $3 = cat, $4 = count
_seed_state() {
  local root="$1" sid="$2" cat="$3" count="$4"
  local state_dir="${root}/.claude/.reviewer-count-state"
  mkdir -p "$state_dir"
  printf '{"%s":%s}\n' "$cat" "$count" > "${state_dir}/${sid}.json"
}

# invoke hook. Args via env: caller exports HC_*/ECC_*/CLAUDE_*.
#   $1 = root, $2 = session_id, $3 = json input
_invoke() {
  local root="$1" sid="$2" json="$3"
  CLAUDE_PROJECT_DIR="$root" \
  CLAUDE_SESSION_ID="$sid" \
  HC_REVIEWER_COUNT_STATE_DIR="${root}/.claude/.reviewer-count-state" \
  bash "$HOOK" <<< "$json" 2>&1
}

_review_input() {
  # $1 = description text
  printf '{"tool_name":"Agent","tool_input":{"description":"%s","run_in_background":true,"subagent_type":"general-purpose"}}' "$1"
}

# -------------------------------------------------------------------
# Case 1: 1 体目 (count=1 <= max) → silent
# -------------------------------------------------------------------
case_1_first_review_silent() {
  local root sid
  root=$(_root_for 1); sid="sess1"
  mkdir -p "${root}/.claude"

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'テスト設計レビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected silent for 1st review, got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  printf '%s' "$out" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null \
    || { printf 'expected valid JSON, got: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2; return 1; }
  return 0
}

# -------------------------------------------------------------------
# Case 2: max+1 体目 → warn 注入
#   test max = 10 (default)。state に 10 件 seed → 本起動が 11 → warn。
# -------------------------------------------------------------------
case_2_over_max_warns() {
  local root sid
  root=$(_root_for 2); sid="sess2"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "test" 10

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'テスト設計レビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if ! printf '%s' "$out" | grep -q "reviewer 数上限\|超過\|review_max_count_test"; then
    printf 'expected warn for over-max, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 3: feature toggle false → no-op
# -------------------------------------------------------------------
case_3_feature_off_noop() {
  local root sid
  root=$(_root_for 3); sid="sess3"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "test" 10

  local out code
  out=$(
    CLAUDE_PROJECT_DIR="$root" \
    CLAUDE_SESSION_ID="$sid" \
    HC_REVIEWER_COUNT_STATE_DIR="${root}/.claude/.reviewer-count-state" \
    HC_FEATURE_REVIEWER_COUNT_GUARD_ENABLED=false \
    bash "$HOOK" <<< "$(_review_input 'テスト設計レビューを実施')" 2>&1
  )
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected no-op when feature OFF, got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 4: bypass env HC_REVIEWER_COUNT_GUARD_ENABLED=false → no-op
# -------------------------------------------------------------------
case_4_bypass_hc_env_noop() {
  local root sid
  root=$(_root_for 4); sid="sess4"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "test" 10

  local out code
  out=$(
    CLAUDE_PROJECT_DIR="$root" \
    CLAUDE_SESSION_ID="$sid" \
    HC_REVIEWER_COUNT_STATE_DIR="${root}/.claude/.reviewer-count-state" \
    HC_REVIEWER_COUNT_GUARD_ENABLED=false \
    bash "$HOOK" <<< "$(_review_input 'テスト設計レビューを実施')" 2>&1
  )
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected no-op when bypass env, got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 4b: bypass env ECC_REVIEWER_COUNT_OFF=1 → no-op
# -------------------------------------------------------------------
case_4b_bypass_ecc_env_noop() {
  local root sid
  root=$(_root_for 4b); sid="sess4b"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "test" 10

  local out code
  out=$(
    CLAUDE_PROJECT_DIR="$root" \
    CLAUDE_SESSION_ID="$sid" \
    HC_REVIEWER_COUNT_STATE_DIR="${root}/.claude/.reviewer-count-state" \
    ECC_REVIEWER_COUNT_OFF=1 \
    bash "$HOOK" <<< "$(_review_input 'テスト設計レビューを実施')" 2>&1
  )
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected no-op when ECC bypass, got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 5: review でない Agent 起動 → count せず pass (silent)
#   実装 keyword のみ、review keyword 不在。max seed 済でも warn しない。
# -------------------------------------------------------------------
case_5_non_review_not_counted() {
  local root sid
  root=$(_root_for 5); sid="sess5"
  mkdir -p "${root}/.claude"
  # 別 cat (test) に 10 seed しても、本 Agent は review でないので無関係 + 増分されない
  _seed_state "$root" "$sid" "test" 10

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input '新 hook の実装と関数分割を行う')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected no-op for non-review agent, got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  # state file の test count が 10 のまま (増分されていない) ことを確認
  local cnt
  cnt=$(jq -r '.test // 0' "${root}/.claude/.reviewer-count-state/${sid}.json" 2>/dev/null || echo "?")
  if [ "$cnt" != "10" ]; then
    printf 'expected test count unchanged (10), got: %s\n' "$cnt" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 6: category 推定 — 各 cat で正しい max を使う
#   design max=7。state design 7 seed → 本起動 8 → warn (8 > 7)。
#   同 input で max=10 の test 解釈なら warn 出ないはず → design 正解検証。
# -------------------------------------------------------------------
case_6_category_design_uses_design_max() {
  local root sid
  root=$(_root_for 6); sid="sess6"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "design" 7

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'design-review を実施し設計レビュー findings を集約')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  # 8 > design max(7) → warn、かつ review_max_count_design が文中に出る
  if ! printf '%s' "$out" | grep -q "review_max_count_design"; then
    printf 'expected design-category warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

case_6b_category_module_uses_module_max() {
  local root sid
  root=$(_root_for 6b); sid="sess6b"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "module" 5

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'module-review モジュールレビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  # 6 > module max(5) → warn module
  if ! printf '%s' "$out" | grep -q "review_max_count_module"; then
    printf 'expected module-category warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

case_6c_category_system_uses_system_max() {
  local root sid
  root=$(_root_for 6c); sid="sess6c"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "system" 5

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'system-review システムレビューで整合性検証')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  if ! printf '%s' "$out" | grep -q "review_max_count_system"; then
    printf 'expected system-category warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case 7: unknown category (reviewer 一般) → max(全 cat) 緩い上限
#   reviewer 一般 keyword のみ。max(10,7,5,5)=10 を上限に。
#   state unknown に 10 seed → 11 → warn。
# -------------------------------------------------------------------
case_7_unknown_uses_loose_max() {
  local root sid
  root=$(_root_for 7); sid="sess7"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "unknown" 10

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'reviewer として一般的なレビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  # 11 > 10 (loose max) → warn (unknown category)
  if ! printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected unknown-category warn at loose max, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

# Case 7b: unknown category 10 体目 (= loose max 10) → silent (境界、<=)
case_7b_unknown_at_max_silent() {
  local root sid
  root=$(_root_for 7b); sid="sess7b"
  mkdir -p "${root}/.claude"
  _seed_state "$root" "$sid" "unknown" 9

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'reviewer として一般的なレビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }
  # 10 <= 10 → silent
  if printf '%s' "$out" | grep -q "reviewer 数上限\|超過"; then
    printf 'expected silent at boundary (count=10 == max), got warn: [%s]\n' "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi
  return 0
}

# ===================================================================
TOTAL_CASES=11

printf '===== task-64 Step 5 reviewer-count-guard smoke =====\n'
printf 'HOOK: %s\n' "$HOOK"
[ ! -f "$HOOK" ] && printf '[INFO] hook not found — all cases SKIP\n'
printf '\n'

run_case_verbose 1   'first review (count<=max) -> silent' case_1_first_review_silent
run_case_verbose 2   'max+1 review -> warn' case_2_over_max_warns
run_case_verbose 3   'feature toggle false -> no-op' case_3_feature_off_noop
run_case_verbose 4   'bypass HC env -> no-op' case_4_bypass_hc_env_noop
run_case_verbose '4b' 'bypass ECC env -> no-op' case_4b_bypass_ecc_env_noop
run_case_verbose 5   'non-review Agent -> not counted, silent' case_5_non_review_not_counted
run_case_verbose 6   'category design -> uses design max' case_6_category_design_uses_design_max
run_case_verbose '6b' 'category module -> uses module max' case_6b_category_module_uses_module_max
run_case_verbose '6c' 'category system -> uses system max' case_6c_category_system_uses_system_max
run_case_verbose 7   'unknown category -> loose max(all)' case_7_unknown_uses_loose_max
run_case_verbose '7b' 'unknown category boundary (==max) -> silent' case_7b_unknown_at_max_silent

printf '\n===== Result =====\n'
printf 'PASS: %d / %d\n' "$PASS" "$TOTAL_CASES"
printf 'SKIP: %d / %d\n' "$SKIP" "$TOTAL_CASES"
printf 'FAIL: %d / %d\n' "$FAIL" "$TOTAL_CASES"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
