#!/usr/bin/env bash
# shellcheck disable=SC2329  # functions invoked indirectly via "$test_fn"
# .claude/tests/iter-min-3-smoke.sh — task-101 Step 4
#
# reviewer-count-guard.sh の iter_min:3 拡張 smoke test。
#
# 設計起源:
#   docs/tasks/task-101-iter-min-reviewer-count-guard.md Step 3-4
#   docs/draft/install-immediately-usable-redesign-20260618.md §3 I8 / §5 P3-4
#
# Cases:
#   Case A:  iter_count=1 (< min:3) → warn 注入
#            state file: .claude/.review-state/<slug>-iter.count に "1"
#            期待: message に "review_iteration_min = 3" 明示
#   Case B:  iter_count=2 (< min:3) → warn 注入
#   Case C:  iter_count=3 (== min:3) → silent (iter warn 出ない)
#
# 検証スコープ:
#   - iter state file 読み込み + 数値比較の機械強制部分のみ検証
#   - main agent が state file を inc するかは honor-system (本 smoke の対象外)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップ
#   - CLAUDE_PROJECT_DIR + HC_REVIEWER_COUNT_STATE_DIR + HC_REVIEW_STATE_DIR を必ず設定
#     (production state 汚染回避)
#   - HC_REVIEW_ITERATION_MIN=3 を明示 (default 3 に依存しない robust)
#
# 実行:  bash .claude/tests/iter-min-3-smoke.sh
# 終了:  0 = 全 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/reviewer-count-guard.sh"

TMP_BASE="$(mktemp -d /tmp/iter-min-3-smoke.XXXXXX)"
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

# Seed iter state file for a given slug.
#   $1 = root dir, $2 = slug, $3 = iter count
_seed_iter_state() {
  local root="$1" slug="$2" count="$3"
  local iter_dir="${root}/.claude/.review-state"
  mkdir -p "$iter_dir"
  printf '%s\n' "$count" > "${iter_dir}/${slug}-iter.count"
}

# invoke hook with a review-agent tool input.
#   $1 = root, $2 = session_id, $3 = json input
_invoke() {
  local root="$1" sid="$2" json="$3"
  CLAUDE_PROJECT_DIR="$root" \
  CLAUDE_SESSION_ID="$sid" \
  HC_REVIEWER_COUNT_STATE_DIR="${root}/.claude/.reviewer-count-state" \
  HC_REVIEW_STATE_DIR="${root}/.claude/.review-state" \
  HC_REVIEW_ITERATION_MIN=3 \
  bash "$HOOK" <<< "$json" 2>&1
}

_review_input() {
  # $1 = description text
  printf '{"tool_name":"Agent","tool_input":{"description":"%s","run_in_background":true,"subagent_type":"general-purpose"}}' "$1"
}

# -------------------------------------------------------------------
# Case A: iter_count=1 (< min:3) → warn 注入
# -------------------------------------------------------------------
case_A_iter_1_warns() {
  local root sid slug
  root=$(_root_for A); sid="sessA"; slug="task-101"
  mkdir -p "${root}/.claude"
  _seed_iter_state "$root" "$slug" 1

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'テスト設計レビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }

  # warn message に "review_iteration_min" と slug 名が含まれること
  if ! printf '%s' "$out" | grep -q "review_iteration_min"; then
    printf 'expected iter_min warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -q "$slug"; then
    printf 'expected slug name %s in warn, got: [%s]\n' "$slug" "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  # BLOCK していないこと (JSON 出力に decision:"block" が出ない)
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    printf 'expected advisory (no block), got block: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case B: iter_count=2 (< min:3) → warn 注入
# -------------------------------------------------------------------
case_B_iter_2_warns() {
  local root sid slug
  root=$(_root_for B); sid="sessB"; slug="task-101"
  mkdir -p "${root}/.claude"
  _seed_iter_state "$root" "$slug" 2

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'テスト設計レビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }

  if ! printf '%s' "$out" | grep -q "review_iteration_min"; then
    printf 'expected iter_min warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  # warn message に iter_count=2 が展開されていること
  if ! printf '%s' "$out" | grep -q "iter_count=2"; then
    printf 'expected iter_count=2 in warn, got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    printf 'expected advisory (no block), got block: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  return 0
}

# -------------------------------------------------------------------
# Case C: iter_count=3 (== min:3) → silent (境界、iter warn 出ない)
#   count <= max (default test max=10) なので max warn も出ない → 完全 silent。
# -------------------------------------------------------------------
case_C_iter_3_silent() {
  local root sid slug
  root=$(_root_for C); sid="sessC"; slug="task-101"
  mkdir -p "${root}/.claude"
  _seed_iter_state "$root" "$slug" 3

  local out code
  out=$(_invoke "$root" "$sid" "$(_review_input 'テスト設計レビューを実施')")
  code=$?

  [ "$code" -eq 0 ] || { printf 'expected exit 0, got %d\n' "$code" >&2; return 1; }

  # iter warn が出ていないこと (境界: 3 >= 3)
  if printf '%s' "$out" | grep -q "review_iteration_min 未達"; then
    printf 'expected silent at boundary (iter=3 >= min=3), got iter warn: [%s]\n' \
      "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  # max warn も出ないこと (1 体目 <= max)
  if printf '%s' "$out" | grep -q "reviewer 数上限"; then
    printf 'expected no max warn (1st review), got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  # JSON 形式 (空 JSON `{}` or hookSpecificOutput 無し) であること
  printf '%s' "$out" | python3 -c "import sys,json;json.load(sys.stdin)" 2>/dev/null \
    || { printf 'expected valid JSON, got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2; return 1; }
  return 0
}

# ===================================================================
TOTAL_CASES=3

printf '===== task-101 Step 4 iter-min-3 smoke =====\n'
printf 'HOOK: %s\n' "$HOOK"
[ ! -f "$HOOK" ] && printf '[INFO] hook not found — all cases SKIP\n'
printf '\n'

run_case_verbose A 'iter_count=1 (< min:3) -> warn' case_A_iter_1_warns
run_case_verbose B 'iter_count=2 (< min:3) -> warn' case_B_iter_2_warns
run_case_verbose C 'iter_count=3 (== min:3) -> silent' case_C_iter_3_silent

printf '\n===== Result =====\n'
printf 'PASS: %d / %d\n' "$PASS" "$TOTAL_CASES"
printf 'SKIP: %d / %d\n' "$SKIP" "$TOTAL_CASES"
printf 'FAIL: %d / %d\n' "$FAIL" "$TOTAL_CASES"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
