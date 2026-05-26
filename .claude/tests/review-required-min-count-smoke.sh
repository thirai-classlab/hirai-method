#!/usr/bin/env bash
# .claude/tests/review-required-min-count-smoke.sh — task-45 Step 3
#
# 起源:
#   docs/draft/config-yml-phase2-hook-review-command.md §4 TDD 戦略 (4 cases)
#   task-45 Step 2 (commit 1521d74) で 4 review command (design-review /
#   test-design / module-review / system-review) に Phase 0 (yml 参照) が
#   追加された。本 smoke で Phase 0 仕様遵守と 4 env 参照を機械検証する。
#
# 検証範囲 (4 cases):
#   Case 1: design-review.md が HC_REVIEW_REQUIRED_DESIGN / review_required_design
#           / no-op skip を参照していること
#   Case 2: test-design.md が HC_REVIEW_MIN_COUNT_TEST / review_min_count_test
#           / default 5 を参照していること
#   Case 3: module-review.md が HC_REVIEW_MAX_COUNT_MODULE / review_max_count_module
#           / 上限 を参照していること
#   Case 4: 4 review command 全てが HC_REVIEW_ITERATION_MAX / review_iteration_max
#           / 反復上限 or 反復ループ上限 を参照していること
#
# 実行:
#   bash .claude/tests/review-required-min-count-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 検証対象 4 review command を grep するのみ (file 編集なし)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DESIGN_REVIEW="${REPO_ROOT}/.claude/commands/design-review.md"
TEST_DESIGN="${REPO_ROOT}/.claude/commands/test-design.md"
MODULE_REVIEW="${REPO_ROOT}/.claude/commands/module-review.md"
SYSTEM_REVIEW="${REPO_ROOT}/.claude/commands/system-review.md"

# 必須 file の存在確認
for f in "$DESIGN_REVIEW" "$TEST_DESIGN" "$MODULE_REVIEW" "$SYSTEM_REVIEW"; do
  if [ ! -f "$f" ]; then
    printf 'ERROR: required file not found: %s\n' "$f" >&2
    exit 1
  fi
done

PASS=0
FAIL=0
FAILED_CASES=""

# PASS/FAIL を記録して結果行を出力
_record() {
  local result="$1"
  local case_id="$2"
  local desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# ============================================================
# Case 1: design-review.md が review_required_design (no-op skip) を参照
# ============================================================
_case_1() (
  set -uo pipefail
  # 3 grep 全 PASS 必須
  grep -q 'HC_REVIEW_REQUIRED_DESIGN' "$DESIGN_REVIEW" || return 1
  grep -q 'review_required_design' "$DESIGN_REVIEW" || return 1
  grep -q 'no-op skip' "$DESIGN_REVIEW" || return 1
  return 0
)

# ============================================================
# Case 2: test-design.md が review_min_count_test (default 5) を参照
# ============================================================
_case_2() (
  set -uo pipefail
  grep -q 'HC_REVIEW_MIN_COUNT_TEST' "$TEST_DESIGN" || return 1
  grep -q 'review_min_count_test' "$TEST_DESIGN" || return 1
  # Phase 0 table 内に `5` default 表記 (review_min_count_test 行に `5` cell)
  # row format: | `HC_REVIEW_MIN_COUNT_TEST` | `review_min_count_test` | `5` | ...
  grep -E 'HC_REVIEW_MIN_COUNT_TEST.*review_min_count_test.*`5`' "$TEST_DESIGN" >/dev/null || return 1
  return 0
)

# ============================================================
# Case 3: module-review.md が review_max_count_module (上限) を参照
# ============================================================
_case_3() (
  set -uo pipefail
  grep -q 'HC_REVIEW_MAX_COUNT_MODULE' "$MODULE_REVIEW" || return 1
  grep -q 'review_max_count_module' "$MODULE_REVIEW" || return 1
  # Phase 0 table の review_max_count_module 行に「上限」表記
  grep -E 'HC_REVIEW_MAX_COUNT_MODULE.*review_max_count_module.*上限' "$MODULE_REVIEW" >/dev/null || return 1
  return 0
)

# ============================================================
# Case 4: 4 review command 全てが HC_REVIEW_ITERATION_MAX を参照
# 各 file × 3 grep (env / yml key / 反復上限 or 反復ループ上限) = 12 grep
# ============================================================
_case_4() (
  set -uo pipefail
  local files=("$DESIGN_REVIEW" "$TEST_DESIGN" "$MODULE_REVIEW" "$SYSTEM_REVIEW")
  local f
  for f in "${files[@]}"; do
    grep -q 'HC_REVIEW_ITERATION_MAX' "$f" || return 1
    grep -q 'review_iteration_max' "$f" || return 1
    # 反復上限 / 反復ループ上限 のいずれか
    if ! grep -qE '反復上限|反復ループ上限' "$f"; then
      return 1
    fi
  done
  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== review-required-min-count-smoke (task-45 Step 3, 4 cases) ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "design-review.md: review_required_design + no-op skip 参照"
else                         _record FAIL 1 "design-review.md: review_required_design + no-op skip 参照"
fi

if _case_2 2>/dev/null; then _record PASS 2 "test-design.md: review_min_count_test + default 5 参照"
else                         _record FAIL 2 "test-design.md: review_min_count_test + default 5 参照"
fi

if _case_3 2>/dev/null; then _record PASS 3 "module-review.md: review_max_count_module + 上限 参照"
else                         _record FAIL 3 "module-review.md: review_max_count_module + 上限 参照"
fi

if _case_4 2>/dev/null; then _record PASS 4 "review_iteration_max + 反復上限 4 commands 全て参照"
else                         _record FAIL 4 "review_iteration_max + 反復上限 4 commands 全て参照"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  printf '\nHINT: Phase 0 (yml 参照 section) が以下 4 file に正しく記載されているか確認:\n'
  printf '  - %s\n' "$DESIGN_REVIEW"
  printf '  - %s\n' "$TEST_DESIGN"
  printf '  - %s\n' "$MODULE_REVIEW"
  printf '  - %s\n' "$SYSTEM_REVIEW"
  exit 1
fi

exit 0
