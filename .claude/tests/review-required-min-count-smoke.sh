#!/usr/bin/env bash
# .claude/tests/review-required-min-count-smoke.sh — task-45 Step 3 (iter 2)
#
# 起源:
#   docs/draft/config-yml-phase2-hook-review-command.md §4 TDD 戦略 (4 cases)
#   task-45 Step 2 (commit 1521d74) で 4 review command (design-review /
#   test-design / module-review / system-review) に Phase 0 (yml 参照) が
#   追加された。本 smoke で Phase 0 仕様遵守と 4 env 参照を機械検証する。
#
# iter 2 変更点 (task-45 iter 1 reviewer findings):
#   - Case 2/3: 複合 regex を 3 grep 分割 (MEDIUM-1 解消)
#   - Case 5-7: feature OFF → no-op exit 0 の behavioral smoke 追加 (MEDIUM-3 / F-02 解消)
#   - Case 5/7: hook の stderr (WARN) を stdout に混入させないよう 2>/dev/null を使用
#
# 検証範囲 (7 cases):
#   Case 1: design-review.md が HC_REVIEW_REQUIRED_DESIGN / review_required_design
#           / no-op skip を参照していること
#   Case 2: test-design.md が HC_REVIEW_MIN_COUNT_TEST / review_min_count_test
#           / default 5 を参照していること (3 grep 分割、複合 regex 廃止)
#   Case 3: module-review.md が HC_REVIEW_MAX_COUNT_MODULE / review_max_count_module
#           / 上限 を参照していること (3 grep 分割、複合 regex 廃止)
#   Case 4: 4 review command 全てが HC_REVIEW_ITERATION_MAX / review_iteration_max
#           / 反復上限 or 反復ループ上限 を参照していること
#   Case 5: delegation-guard.sh が HC_FEATURE_DELEGATION_GUARD_ENABLED=false で exit 0
#   Case 6: loop-confirmation-detector.sh が HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false
#           かつ HC_MODE=loop で exit 0
#   Case 7: context-budget.sh が HC_FEATURE_CONTEXT_BUDGET_ENABLED=false
#           かつ HC_MODE=loop で exit 0
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
#   - Case 1-4: 検証対象 4 review command を grep するのみ (file 編集なし)
#   - Case 5-7: hook を実 bash 実行して exit code + stdout を検証 (file 編集なし)
#   - Case 5/7: stdout のみキャプチャ (stderr = config-loader WARN は 2>/dev/null で捨てる)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DESIGN_REVIEW="${REPO_ROOT}/.claude/commands/design-review.md"
TEST_DESIGN="${REPO_ROOT}/.claude/commands/test-design.md"
MODULE_REVIEW="${REPO_ROOT}/.claude/commands/module-review.md"
SYSTEM_REVIEW="${REPO_ROOT}/.claude/commands/system-review.md"

DELEGATION_GUARD="${REPO_ROOT}/.claude/hooks/delegation-guard.sh"
LOOP_CONFIRMATION="${REPO_ROOT}/.claude/hooks/loop-confirmation-detector.sh"
CONTEXT_BUDGET="${REPO_ROOT}/.claude/hooks/context-budget.sh"

# 必須 file の存在確認 (review commands)
for f in "$DESIGN_REVIEW" "$TEST_DESIGN" "$MODULE_REVIEW" "$SYSTEM_REVIEW"; do
  if [ ! -f "$f" ]; then
    printf 'ERROR: required file not found: %s\n' "$f" >&2
    exit 1
  fi
done

# 必須 file の存在確認 (hooks for behavioral cases)
for f in "$DELEGATION_GUARD" "$LOOP_CONFIRMATION" "$CONTEXT_BUDGET"; do
  if [ ! -f "$f" ]; then
    printf 'ERROR: required hook not found: %s\n' "$f" >&2
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
# 旧複合 regex を 3 grep 分割 (MEDIUM-1 解消)
# ============================================================
_case_2() (
  set -uo pipefail
  grep -q 'HC_REVIEW_MIN_COUNT_TEST' "$TEST_DESIGN" || return 1
  grep -q 'review_min_count_test' "$TEST_DESIGN" || return 1
  # default 値 `5` の参照確認 (独立 grep、複合 regex 廃止)
  grep -q '`5`' "$TEST_DESIGN" || return 1
  return 0
)

# ============================================================
# Case 3: module-review.md が review_max_count_module (上限) を参照
# 旧複合 regex を 3 grep 分割 (MEDIUM-1 解消)
# ============================================================
_case_3() (
  set -uo pipefail
  grep -q 'HC_REVIEW_MAX_COUNT_MODULE' "$MODULE_REVIEW" || return 1
  grep -q 'review_max_count_module' "$MODULE_REVIEW" || return 1
  # 「上限」表記の参照確認 (独立 grep、複合 regex 廃止)
  grep -q '上限' "$MODULE_REVIEW" || return 1
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
# Case 5: delegation-guard.sh が feature OFF で exit 0 (behavioral)
# HC_FEATURE_DELEGATION_GUARD_ENABLED=false → is_feature_enabled delegation_guard が false
# → hook 冒頭 `if ! is_feature_enabled delegation_guard; then exit 0` が発火
# 期待: exit_code == 0 AND stdout (空文字列 or "{}")
# 注意: config-loader の WARN は stderr 経由のため 2>/dev/null で捨て、stdout のみ検証
# ============================================================
_case_5() (
  set -uo pipefail
  local output exit_code
  output=$(
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_CONFIG_PATH=/dev/null \
    bash "$DELEGATION_GUARD" </dev/null 2>/dev/null
  ) || true
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    printf 'exit_code=%d (expected 0)\n' "$exit_code" >&2
    return 1
  fi
  # stdout は空文字列 or "{}" のみ許容
  local trimmed
  trimmed=$(printf '%s' "$output" | tr -d '[:space:]')
  if [ -n "$trimmed" ] && [ "$trimmed" != "{}" ]; then
    printf 'unexpected stdout: %s\n' "$output" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 6: loop-confirmation-detector.sh が feature OFF で exit 0 (behavioral)
# Stop hook のため transcript_path が必要だが、feature check は Loop モード確認後の
# 冒頭で評価される。HC_MODE=loop で Loop モード check を通過させ、
# HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false で feature check を発火させる。
# 期待: exit_code == 0
# ============================================================
_case_6() (
  set -uo pipefail
  local exit_code
  HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false \
  HC_MODE=loop \
  HC_CONFIG_PATH=/dev/null \
  bash "$LOOP_CONFIRMATION" \
    <<< '{"transcript_path":"/tmp/nonexistent_smoke_test"}' \
    >/dev/null 2>/dev/null || true
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    printf 'exit_code=%d (expected 0)\n' "$exit_code" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 7: context-budget.sh が feature OFF で exit 0 (behavioral)
# UserPromptSubmit hook。HC_MODE=loop で Loop モード check を通過させ、
# HC_FEATURE_CONTEXT_BUDGET_ENABLED=false で feature check を発火させる。
# 期待: exit_code == 0 AND stdout == ""
# 注意: config-loader の WARN は stderr 経由のため 2>/dev/null で捨て、stdout のみ検証
# ============================================================
_case_7() (
  set -uo pipefail
  local output exit_code
  output=$(
    HC_FEATURE_CONTEXT_BUDGET_ENABLED=false \
    HC_MODE=loop \
    HC_CONFIG_PATH=/dev/null \
    bash "$CONTEXT_BUDGET" </dev/null 2>/dev/null
  ) || true
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    printf 'exit_code=%d (expected 0)\n' "$exit_code" >&2
    return 1
  fi
  if [ -n "$output" ]; then
    printf 'unexpected stdout: %s\n' "$output" >&2
    return 1
  fi
  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== review-required-min-count-smoke (task-45 iter 2, 7 cases) ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "design-review.md: review_required_design + no-op skip 参照"
else                         _record FAIL 1 "design-review.md: review_required_design + no-op skip 参照"
fi

if _case_2 2>/dev/null; then _record PASS 2 "test-design.md: review_min_count_test + default 5 参照 (3 grep 分割)"
else                         _record FAIL 2 "test-design.md: review_min_count_test + default 5 参照 (3 grep 分割)"
fi

if _case_3 2>/dev/null; then _record PASS 3 "module-review.md: review_max_count_module + 上限 参照 (3 grep 分割)"
else                         _record FAIL 3 "module-review.md: review_max_count_module + 上限 参照 (3 grep 分割)"
fi

if _case_4 2>/dev/null; then _record PASS 4 "review_iteration_max + 反復上限 4 commands 全て参照"
else                         _record FAIL 4 "review_iteration_max + 反復上限 4 commands 全て参照"
fi

if _case_5 2>/dev/null; then _record PASS 5 "delegation-guard.sh: HC_FEATURE_DELEGATION_GUARD_ENABLED=false → exit 0"
else                         _record FAIL 5 "delegation-guard.sh: HC_FEATURE_DELEGATION_GUARD_ENABLED=false → exit 0"
fi

if _case_6 2>/dev/null; then _record PASS 6 "loop-confirmation-detector.sh: HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false + HC_MODE=loop → exit 0"
else                         _record FAIL 6 "loop-confirmation-detector.sh: HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false + HC_MODE=loop → exit 0"
fi

if _case_7 2>/dev/null; then _record PASS 7 "context-budget.sh: HC_FEATURE_CONTEXT_BUDGET_ENABLED=false + HC_MODE=loop → exit 0"
else                         _record FAIL 7 "context-budget.sh: HC_FEATURE_CONTEXT_BUDGET_ENABLED=false + HC_MODE=loop → exit 0"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  printf '\nHINT (Case 1-4): Phase 0 (yml 参照 section) が以下 4 file に正しく記載されているか確認:\n'
  printf '  - %s\n' "$DESIGN_REVIEW"
  printf '  - %s\n' "$TEST_DESIGN"
  printf '  - %s\n' "$MODULE_REVIEW"
  printf '  - %s\n' "$SYSTEM_REVIEW"
  printf '\nHINT (Case 5-7): 対象 hook の feature check section (task-45 Phase 2) が正しく実装されているか確認:\n'
  printf '  - %s\n' "$DELEGATION_GUARD"
  printf '  - %s\n' "$LOOP_CONFIRMATION"
  printf '  - %s\n' "$CONTEXT_BUDGET"
  exit 1
fi

exit 0
