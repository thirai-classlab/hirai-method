#!/usr/bin/env bash
# .claude/tests/wave-precheck-template-smoke.sh — smoke for Wave Pre-check template/rule/command wiring (W4)
#
# 目的:
#   docs/draft/wave-precheck-git-log-grep.md W1-W3 で導入された artifact が
#   実体として存在し、所定の keyword が含まれていることを静的に検証する。
#   さらに既存 smoke file の存在 (回帰安全) を確認する。
#
# 検証ケース:
#   Case 1: _TASK_TEMPLATE.md に「事前確認」 keyword が含まれる (W1)
#   Case 2: workflow.md Stage 8 / 7 周辺に "git log --grep" が最低 2 hit (W2)
#   Case 3: new-feature.md / modify-feature.md 両方に "Wave Pre-check" 存在 (W3)
#   Case 4: 既存 smoke (workflow-guard / next-actions-hooks / loop-auto-progress) が存在 (regression safety)
#
# 実行:
#   bash .claude/tests/wave-precheck-template-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail は書かない
#     (.claude/rules/development-process.md Critical Operational Lessons HIGH 参照 /
#      mode-loader.sh の CB-verify 教訓 commit 5846925)
#   - 厳格 mode は subshell 関数で局所化する

set -uo pipefail

# repo root に移動
cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
REPO_ROOT="$(pwd)"

TEMPLATE_FILE="${REPO_ROOT}/.claude/templates/docs/tasks/_TASK_TEMPLATE.md"
WORKFLOW_RULE="${REPO_ROOT}/.claude/rules/workflow.md"
# task-74: task-51 Layer A/B 再構造で "git log --grep" 記述が workflow.md (Layer A) から
# rules-details/workflow/14-stage.md (Stage 8) + 10-stage.md (Stage 7) (Layer B) へ移動。
WORKFLOW_LAYERB_NEW="${REPO_ROOT}/.claude/rules-details/workflow/14-stage.md"
WORKFLOW_LAYERB_MODIFY="${REPO_ROOT}/.claude/rules-details/workflow/10-stage.md"
NEW_FEATURE_CMD="${REPO_ROOT}/.claude/commands/new-feature.md"
MODIFY_FEATURE_CMD="${REPO_ROOT}/.claude/commands/modify-feature.md"

EXISTING_SMOKES=(
  "${REPO_ROOT}/.claude/tests/workflow-guard-smoke.sh"
  "${REPO_ROOT}/.claude/tests/next-actions-hooks-smoke.sh"
  "${REPO_ROOT}/.claude/tests/loop-auto-progress-smoke.sh"
)

PASS=0
FAIL=0
FAIL_CASES=""
RESULTS=""

_record() {
  local label="$1" status="$2" detail="$3"
  RESULTS="${RESULTS}${status}|${label}|${detail}"$'\n'
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_CASES="${FAIL_CASES} ${label}"
  fi
}

# Case 1: _TASK_TEMPLATE.md に「事前確認」 keyword 存在 (W1)
case1() {
  local label="Case 1: _TASK_TEMPLATE.md 'Wave 計画前の事前確認' subsection"
  if [ ! -f "$TEMPLATE_FILE" ]; then
    _record "$label" "FAIL" "file missing: $TEMPLATE_FILE"
    return
  fi
  if grep -q "事前確認" "$TEMPLATE_FILE"; then
    local detail
    detail="hit count: $(grep -c "事前確認" "$TEMPLATE_FILE")"
    _record "$label" "PASS" "$detail"
  else
    _record "$label" "FAIL" "keyword '事前確認' not found"
  fi
}

# Case 2: Layer B (14-stage Stage 8 / 10-stage Stage 7) に "git log --grep" が各 1 hit 以上、
#         かつ Layer A workflow.md が両 Layer B file への pointer を保持 (W2、task-74 spec-drift 修正)
case2() {
  local label="Case 2: Layer B 14-stage(Stage 8)/10-stage(Stage 7) reference 'git log --grep' + Layer A pointer"
  if [ ! -f "$WORKFLOW_LAYERB_NEW" ] || [ ! -f "$WORKFLOW_LAYERB_MODIFY" ]; then
    _record "$label" "FAIL" "Layer B file missing (14-stage or 10-stage)"
    return
  fi
  if [ ! -f "$WORKFLOW_RULE" ]; then
    _record "$label" "FAIL" "Layer A file missing: $WORKFLOW_RULE"
    return
  fi
  local new_hit modify_hit
  new_hit=$(grep -E "git log.*--grep" "$WORKFLOW_LAYERB_NEW" | wc -l | tr -d ' ')
  modify_hit=$(grep -E "git log.*--grep" "$WORKFLOW_LAYERB_MODIFY" | wc -l | tr -d ' ')
  # Layer A pointer: workflow.md が両 Layer B file への参照を保持
  local ptr_new ptr_modify
  if grep -q "workflow/14-stage.md" "$WORKFLOW_RULE"; then ptr_new=1; else ptr_new=0; fi
  if grep -q "workflow/10-stage.md" "$WORKFLOW_RULE"; then ptr_modify=1; else ptr_modify=0; fi
  if [ "$new_hit" -ge 1 ] && [ "$modify_hit" -ge 1 ] && [ "$ptr_new" = "1" ] && [ "$ptr_modify" = "1" ]; then
    _record "$label" "PASS" "14-stage=$new_hit 10-stage=$modify_hit ptr(new=$ptr_new,modify=$ptr_modify)"
  else
    _record "$label" "FAIL" "14-stage=$new_hit 10-stage=$modify_hit ptr(new=$ptr_new,modify=$ptr_modify)"
  fi
}

# Case 3: new-feature.md / modify-feature.md 両方に "Wave Pre-check" 存在 (W3)
case3() {
  local label="Case 3: new-feature.md AND modify-feature.md contain 'Wave Pre-check'"
  if [ ! -f "$NEW_FEATURE_CMD" ] || [ ! -f "$MODIFY_FEATURE_CMD" ]; then
    _record "$label" "FAIL" "command file missing"
    return
  fi
  local n_hit m_hit
  if grep -q "Wave Pre-check" "$NEW_FEATURE_CMD"; then n_hit=1; else n_hit=0; fi
  if grep -q "Wave Pre-check" "$MODIFY_FEATURE_CMD"; then m_hit=1; else m_hit=0; fi
  if [ "$n_hit" = "1" ] && [ "$m_hit" = "1" ]; then
    _record "$label" "PASS" "new-feature=$n_hit modify-feature=$m_hit"
  else
    _record "$label" "FAIL" "new-feature=$n_hit modify-feature=$m_hit"
  fi
}

# Case 4: 既存 smoke (workflow-guard / next-actions-hooks / loop-auto-progress) が存在
case4() {
  local label="Case 4: pre-existing smoke files exist (regression safety)"
  local missing=""
  local f
  for f in "${EXISTING_SMOKES[@]}"; do
    if [ ! -f "$f" ]; then
      missing="${missing} $(basename "$f")"
    fi
  done
  if [ -z "$missing" ]; then
    _record "$label" "PASS" "all ${#EXISTING_SMOKES[@]} smoke files present"
  else
    _record "$label" "FAIL" "missing:${missing}"
  fi
}

# run all
case1
case2
case3
case4

# report
printf '\n=== wave-precheck-template smoke results ===\n'
printf 'Status | Case | Detail\n'
printf -- '------+------+-------\n'
printf '%s' "$RESULTS"
printf '\n=== summary: %d/%d PASS ===\n' "$PASS" "$((PASS + FAIL))"

if [ "$FAIL" -ne 0 ]; then
  printf 'FAIL cases:%s\n' "$FAIL_CASES" >&2
  exit 1
fi

printf 'wave-precheck-template-smoke: %d/%d PASS\n' "$PASS" "$((PASS + FAIL))"
exit 0
