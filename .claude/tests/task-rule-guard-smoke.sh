#!/usr/bin/env bash
# task-rule-guard-smoke.sh — task-22 W3 smoke for task-rule-guard.sh
#                          + task-29 Phase 4 Step 1 で Phase/Step format 検証 case を追加
#                          + task-21 W3 仕様変更 (Phase 最終 Step 2 段 → 3 段) 追従 (Case 7 更新 + Case 11 追加)
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#   docs/tasks/task-29-phase-step-task-structure.md Phase 4
#   docs/tasks/task-21-system-reminder-attention-fix.md W3 (2026-05-23 user 仕様変更)
#
# 対象 hook / template:
#   .claude/hooks/task-rule-guard.sh
#   .claude/templates/docs/tasks/_TASK_TEMPLATE.md
#
# 検証範囲 (11 ケース):
#   既存 5 case (task-22 W3):
#     Case 1: 新規 task Write、対応 draft 不在 → BLOCK
#     Case 2: 新規 task Write、対応 draft 存在 → PASS (additionalContext)
#     Case 3: 既存 list.md の Edit → PASS (exempt)
#     Case 4: ID 重複 (同 id-* file 既存) で別 slug の Write → BLOCK
#     Case 5: ECC_TASKGUARD=off で BLOCK ケース → PASS
#
#   新規 5 case (task-29 Phase 4 Step 1):
#     Case 6: template に "## Phase 計画" + "### Phase 計画前の事前確認" 存在
#     Case 7: template の Phase 計画以降に "テスト設計レビュー" + "テスト合格" + "リファクタリング" 3 段雛形存在 (2026-05-23 task-21 W3 仕様変更追従)
#     Case 8: template に "### 小タスクモード" sub-section + "skip:" 例示存在
#     Case 9: template frontmatter HTML comment に phase_count / total_steps placeholder 存在
#     Case 10: template に旧 "## Wave 構成" section が残っていない (rename 済)
#
#   追加 1 case (task-21 W3 仕様変更追従):
#     Case 11: template にテスト設計レビューの動的選定方針 ("5+ reviewer" + "動的選定") が存在
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って docs/tasks docs/draft を配置
#   - hook は HC_TASK_DIR / HC_DRAFT_DIR / HC_TASKGUARD_STATE_DIR の env override に従う
#   - subagent 短絡防止: CLAUDE_HARNESS_ROLE をクリア + HC_AGENT_MARKER_DIR を空 dir に向ける
#   - 新規 case は実 template (_TASK_TEMPLATE.md) を読み、grep で検証する pure read-only
#
# 実行:
#   bash .claude/tests/task-rule-guard-smoke.sh
#
# 終了コード:
#   0 = 11/11 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/task-rule-guard.sh"
TASK_TEMPLATE="$REPO_ROOT/.claude/templates/docs/tasks/_TASK_TEMPLATE.md"

# clean main agent context
unset CLAUDE_HARNESS_ROLE
unset ECC_TASKGUARD
unset ECC_F2_OFF

# tmp project root + state dir (live .taskguard-state を汚さない)
TMP_ROOT="$(mktemp -d /tmp/task-rule-guard-smoke.XXXXXX)"
TMP_STATE_DIR="${TMP_ROOT}/.taskguard-state"
TMP_MARKER_DIR="${TMP_ROOT}/.agent-markers"
mkdir -p "$TMP_ROOT/docs/tasks" "$TMP_ROOT/docs/draft" "$TMP_STATE_DIR" "$TMP_MARKER_DIR"

trap 'rm -rf "$TMP_ROOT"' EXIT

# task_dir/draft_dir は project root からの相対 path セグメントで指定。
# hook は file_path の "*/${HC_TASK_DIR}/*" glob match で判定するため
# task_dir="docs/tasks" のまま、file_path に "${TMP_ROOT}/docs/tasks/..." を渡す。
COMMON_ENV=(
  "HC_TASK_DIR=docs/tasks"
  "HC_DRAFT_DIR=docs/draft"
  "HC_TASKGUARD_STATE_DIR=${TMP_STATE_DIR}"
  "HC_AGENT_MARKER_DIR=${TMP_MARKER_DIR}"
)

PASS=0
FAIL=0
FAILED_CASES=()

# Write JSON input 組み立て
json_write_input() {
  local fp="$1"
  FP="$fp" python3 -c '
import json, os
print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": os.environ["FP"]}}))
'
}

# Edit JSON input
json_edit_input() {
  local fp="$1"
  FP="$fp" python3 -c '
import json, os
print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": os.environ["FP"]}}))
'
}

extract_decision() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("decision", "none"))
except Exception:
    print("parse_error")
' 2>/dev/null
}

extract_reason() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("reason", ""))
except Exception:
    print("")
' 2>/dev/null
}

# === Case 1: 新規 task Write、対応 draft 不在 → BLOCK ===
case1_no_draft_blocked() {
  local label="Case 1: new task Write w/o matching draft → BLOCK"
  local fp="${TMP_ROOT}/docs/tasks/task-99-case1-no-draft.md"
  local out decision reason
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q "対応する設計 draft"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 2: 新規 task Write、対応 draft 存在 → PASS ===
case2_draft_exists_pass() {
  local label="Case 2: new task Write w/ matching draft → PASS"
  local fp="${TMP_ROOT}/docs/tasks/task-98-case2-with-draft.md"
  # 対応 draft を先に作る
  touch "${TMP_ROOT}/docs/draft/case2-with-draft.md"
  local out decision
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 3: 既存 list.md の Edit → PASS (exempt) ===
case3_list_md_exempt() {
  local label="Case 3: list.md Edit → PASS (exempt)"
  local fp="${TMP_ROOT}/docs/tasks/list.md"
  touch "$fp"
  local out decision
  out=$(json_edit_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Edit 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 4: ID 重複で別 slug の Write → BLOCK ===
case4_id_duplicate_blocked() {
  local label="Case 4: ID duplicate (task-97-* exists) → BLOCK"
  # 同 id の既存 file (slug は異なる)
  touch "${TMP_ROOT}/docs/tasks/task-97-existing-slug.md"
  local fp="${TMP_ROOT}/docs/tasks/task-97-different-slug.md"
  # 別 slug は draft 一致が無くても ID 重複が先に判定される
  # draft も用意して draft missing と区別する
  touch "${TMP_ROOT}/docs/draft/different-slug.md"
  local out decision reason
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q "ID '97'"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 5: ECC_TASKGUARD=off で BLOCK ケース → PASS ===
case5_bypass_env_pass() {
  local label="Case 5: ECC_TASKGUARD=off bypass on no-draft case → PASS"
  local fp="${TMP_ROOT}/docs/tasks/task-96-case5-bypassed.md"
  # 対応 draft なし (本来 BLOCK だが bypass で PASS 期待)
  local out decision
  out=$(json_write_input "$fp" | ECC_TASKGUARD=off env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision: %s\n    out: %s\n" "$label" "$decision" "$out"
  fi
}

# === Case 6 (task-29 Phase 4): template に Phase 計画 + 事前確認 sub-section 存在 ===
case6_template_phase_plan_section() {
  local label="Case 6: _TASK_TEMPLATE.md has '## Phase 計画' + '### Phase 計画前の事前確認'"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found: $TASK_TEMPLATE"
  else
    if ! grep -q '^## Phase 計画$' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '^## Phase 計画$'"
    elif ! grep -q '### Phase 計画前の事前確認' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '### Phase 計画前の事前確認'"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

# === Case 7 (task-29 Phase 4 + task-21 W3 仕様変更追従): Phase 計画以降に 3 段 (テスト設計レビュー + テスト合格 + リファクタリング) 雛形存在 ===
case7_template_test_refactor_steps() {
  local label="Case 7: Phase 計画 section has 'テスト設計レビュー' + 'テスト合格' + 'リファクタリング' Step 雛形 (3 段)"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    # Phase 計画 section 以降の slice を抽出して 3 keyword grep
    local slice
    slice=$(awk '/^## Phase 計画$/{found=1} found' "$TASK_TEMPLATE")
    if [ -z "$slice" ]; then
      pass=0
      why="Phase 計画 section not found by awk"
    elif ! printf '%s' "$slice" | grep -q 'テスト設計レビュー'; then
      pass=0
      why="missing 'テスト設計レビュー' after Phase 計画 section (3 段化 要求 by task-21 W3)"
    elif ! printf '%s' "$slice" | grep -q 'テスト合格'; then
      pass=0
      why="missing 'テスト合格' after Phase 計画 section"
    elif ! printf '%s' "$slice" | grep -q 'リファクタリング'; then
      pass=0
      why="missing 'リファクタリング' after Phase 計画 section"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

# === Case 8 (task-29 Phase 4): 小タスクモード sub-section + skip: 例示 ===
case8_template_small_task_mode() {
  local label="Case 8: template has '### 小タスクモード' + 'skip:' example"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    if ! grep -q '### 小タスクモード' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '### 小タスクモード'"
    elif ! grep -q 'skip:' "$TASK_TEMPLATE"; then
      pass=0
      why="missing 'skip:' example"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

# === Case 9 (task-29 Phase 4): frontmatter HTML comment placeholder ===
case9_template_metadata_placeholder() {
  local label="Case 9: template has phase_count / total_steps placeholder"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    if ! grep -q 'phase_count' "$TASK_TEMPLATE"; then
      pass=0
      why="missing 'phase_count' placeholder"
    elif ! grep -q 'total_steps' "$TASK_TEMPLATE"; then
      pass=0
      why="missing 'total_steps' placeholder"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

# === Case 10 (task-29 Phase 4): 旧 Wave 構成 section が残っていない ===
case10_template_no_legacy_wave_section() {
  local label="Case 10: template has no legacy '## Wave 構成' section"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    if grep -q '^## Wave 構成$' "$TASK_TEMPLATE"; then
      pass=0
      why="legacy '## Wave 構成' section still present"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

# === Case 11 (task-21 W3 仕様変更追従): テスト設計レビューの動的選定方針 ===
case11_template_test_design_review_dynamic_selection() {
  local label="Case 11: template has '5+ reviewer' + '動的選定' for テスト設計レビュー Step"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    if ! grep -q '5+ reviewer' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '5+ reviewer' keyword (動的選定方針 not encoded)"
    elif ! grep -q '動的選定' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '動的選定' keyword"
    fi
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n" "$label" "$why"
  fi
}

printf "===== task-rule-guard-smoke (task-22 W3.2 + task-29 Phase 4 Step 1 + task-21 W3 仕様変更追従, 11 cases) =====\n\n"

case1_no_draft_blocked
case2_draft_exists_pass
case3_list_md_exempt
case4_id_duplicate_blocked
case5_bypass_env_pass
case6_template_phase_plan_section
case7_template_test_refactor_steps
case8_template_small_task_mode
case9_template_metadata_placeholder
case10_template_no_legacy_wave_section
case11_template_test_design_review_dynamic_selection

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
