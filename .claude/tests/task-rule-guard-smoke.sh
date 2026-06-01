#!/usr/bin/env bash
# task-rule-guard-smoke.sh — task-22 W3 smoke for task-rule-guard.sh
#                          + task-29 Phase 4 Step 1 で Phase/Step format 検証 case を追加
#                          + task-21 W3 仕様変更 (Phase 最終 Step 2 段 → 3 段) 追従 (Case 7 更新 + Case 11 追加)
#                          + task-36 Step 3 (Sub B) で plan-first warn 検証 case を追加 (Case 12/13)
#                          + task-36 Step 2 iter2 fix で採用 6 条 (Task=Phase=N Step、2026-05-25) 追従 (Case 6/7/9 更新 + Case 13 強化 + Case 14 追加)
#                          + task-36 Step 2 iter3 fix で F1 regression test (Case 15) + ヘッダ count 修正
#
# ※ smoke は `is_feature_enabled` を迂回し hook ロジックを直接検証する。
#    本番で `feature_task_rule_guard_enabled: false` の場合 hook 全体が no-op になる点に注意
#    (toggle 状態は next-actions #65 で追跡)。
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#   docs/tasks/task-29-phase-step-task-structure.md Phase 4
#   docs/tasks/task-21-system-reminder-attention-fix.md W3 (2026-05-23 user 仕様変更)
#   docs/tasks/task-36-list-md-plan-first-draft-warn.md Step 3 (task-36 Sub B)
#   docs/draft/task-equals-phase-step-status-list-normative.md (2026-05-25 採用 6 条、Phase 中間階層廃止)
#   task-36 Step 2 iter3: F7 (awk col 拡張) + F8 (Edit positive case) + F9 (ヘッダ count 修正)
#
# 対象 hook / template:
#   .claude/hooks/task-rule-guard.sh
#   .claude/templates/docs/tasks/_TASK_TEMPLATE.md
#
# 検証範囲 (17 ケース):
#   既存 5 case (task-22 W3):
#     Case 1: 新規 task Write、対応 draft 不在 → BLOCK
#     Case 2: 新規 task Write、対応 draft 存在 → PASS (additionalContext)
#     Case 3: 既存 list.md の Edit → PASS (exempt)
#     Case 4: ID 重複 (同 id-* file 既存) で別 slug の Write → BLOCK
#     Case 5: ECC_TASKGUARD=off で BLOCK ケース → PASS
#
#   採用 6 条追従 (task-36 Step 2 iter2 で更新):
#     Case 6: template に "## Step 計画" + "### Step 計画前の事前確認" 存在 (旧 "## Phase 計画" → 新 "## Step 計画")
#     Case 7: template の Step 計画以降に "テスト設計レビュー" + "テスト合格" + "リファクタリング" 3 段雛形存在
#     Case 8: template に "### 小タスクモード" sub-section + "skip:" 例示存在
#     Case 9: template frontmatter HTML comment に total_steps placeholder 存在 (採用 6 条で phase_count 廃止)
#     Case 10: template に旧 "## Wave 構成" section が残っていない (rename 済)
#
#   追加 1 case (task-21 W3 仕様変更追従):
#     Case 11: template にテスト設計レビューの動的選定方針 ("5+ reviewer" + "動的選定") が存在
#
#   追加 2 case (task-36 Step 3 Sub B — plan-first draft warn):
#     Case 12: docs/draft/<slug>.md Write、list.md に 📝 行不在 → additionalContext に "plan-first" keyword 含む (warn)
#     Case 13: docs/draft/<slug>.md Write、list.md に 📝 行存在 → additionalContext に "plan-first" keyword 含まない + warn 出典文字列 (task-management.md §plan-first) 不在 strict assert (iter2 F4)
#
#   追加 3 sub-case (task-36 Step 2 iter2 F6 — edge case 強化):
#     Case 14a: 空 basename (拡張子のみ ".md") → hook が異常終了せず silent pass
#     Case 14b: "-.md" (1 文字 slug "-") → hook が異常終了せず処理
#     Case 14c: 日本語 slug "日本語タスク.md" → ASCII slug regex 範囲外、hook 異常終了なし
#
#   追加 1 case (task-36 Step 2 iter3 F8 — F1 (Edit on draft 素通り) regression test):
#     Case 15: docs/draft/<existing-slug>.md への Edit tool 呼び出し → hook 素通り (additionalContext 不在)
#              iter2 F1 で実装した「Edit は draft warn 判定対象外」の logic を直接検証する positive case
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って docs/tasks docs/draft を配置
#   - hook は HC_TASK_DIR / HC_DRAFT_DIR / HC_TASKGUARD_STATE_DIR の env override に従う
#   - subagent 短絡防止: CLAUDE_HARNESS_ROLE をクリア + HC_AGENT_MARKER_DIR を空 dir に向ける
#   - 新規 case は実 template (_TASK_TEMPLATE.md) を読み、grep で検証する pure read-only
#   - 採用 6 条 (Task=Phase=N Step、2026-05-25) で template の `## Phase 計画` → `## Step 計画`、`phase_count` 廃止
#
# 実行:
#   bash .claude/tests/task-rule-guard-smoke.sh
#
# 終了コード:
#   0 = 17/17 PASS / 1 = 1 件以上 FAIL

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

# additionalContext を hookSpecificOutput から抽出
# 設計起源: task-36 task file Step 3 — top-level additionalContext は常時 null
extract_additional_context() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    hso = d.get("hookSpecificOutput", {}) or {}
    print(hso.get("additionalContext", "") or "")
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

# === Case 6 (採用 6 条追従、task-36 Step 2 iter2): template に Step 計画 + 事前確認 sub-section 存在 ===
# 採用 6 条 (2026-05-25): Task=Phase=N Step、Phase 中間階層廃止。
# 旧 "## Phase 計画" → 新 "## Step 計画"、旧 "### Phase 計画前の事前確認" → 新 "### Step 計画前の事前確認"
case6_template_phase_plan_section() {
  local label="Case 6: _TASK_TEMPLATE.md has '## Step 計画' + '### Step 計画前の事前確認' (採用 6 条)"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found: $TASK_TEMPLATE"
  else
    if ! grep -q '^## Step 計画$' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '^## Step 計画$' (採用 6 条で Phase → Step rename)"
    elif ! grep -q '### Step 計画前の事前確認' "$TASK_TEMPLATE"; then
      pass=0
      why="missing '### Step 計画前の事前確認'"
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

# === Case 7 (採用 6 条追従、task-36 Step 2 iter2): Step 計画以降に 3 段 (テスト設計レビュー + テスト合格 + リファクタリング) 雛形存在 ===
# 採用 6 条 4: Task 最終 = テスト設計レビュー → テスト合格 → リファクタリング (3 段必須)
case7_template_test_refactor_steps() {
  local label="Case 7: Step 計画 section has 'テスト設計レビュー' + 'テスト合格' + 'リファクタリング' Step 雛形 (3 段、採用 6 条 4)"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    # Step 計画 section 以降の slice を抽出して 3 keyword grep
    local slice
    slice=$(awk '/^## Step 計画$/{found=1} found' "$TASK_TEMPLATE")
    if [ -z "$slice" ]; then
      pass=0
      why="Step 計画 section not found by awk (採用 6 条で Phase → Step rename)"
    elif ! printf '%s' "$slice" | grep -q 'テスト設計レビュー'; then
      pass=0
      why="missing 'テスト設計レビュー' after Step 計画 section (3 段化 要求 by 採用 6 条 4)"
    elif ! printf '%s' "$slice" | grep -q 'テスト合格'; then
      pass=0
      why="missing 'テスト合格' after Step 計画 section"
    elif ! printf '%s' "$slice" | grep -q 'リファクタリング'; then
      pass=0
      why="missing 'リファクタリング' after Step 計画 section"
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

# === Case 9 (採用 6 条追従、task-36 Step 2 iter2): frontmatter HTML comment placeholder ===
# 採用 6 条 (2026-05-25): Phase 中間階層廃止に伴い phase_count 廃止、total_steps のみ存在
case9_template_metadata_placeholder() {
  local label="Case 9: template has total_steps placeholder (採用 6 条で phase_count 廃止)"
  local pass=1
  local why=""

  if [ ! -f "$TASK_TEMPLATE" ]; then
    pass=0
    why="template file not found"
  else
    if ! grep -q 'total_steps' "$TASK_TEMPLATE"; then
      pass=0
      why="missing 'total_steps' placeholder"
    elif grep -q 'phase_count' "$TASK_TEMPLATE"; then
      pass=0
      why="legacy 'phase_count' placeholder still present (採用 6 条で廃止)"
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

# === Case 12 (task-36 Sub B): docs/draft/<slug>.md Write、list.md に 📝 行不在 → warn (plan-first keyword) ===
#
# 設計起源: task-36 task file Step 3、jq path 注意: .hookSpecificOutput.additionalContext
# TDD RED phase: Sub A (hook 拡張) 完了後に PASS する想定。Sub A 並走中は FAIL 許容。
case12_draft_write_no_planned_row_warns() {
  local label="Case 12: docs/draft/<slug> Write, list.md has no 📝 row → warn with 'plan-first'"

  # fixture: list.md に対象 slug の 📝 行が無い状態
  local list_md="${TMP_ROOT}/docs/tasks/list.md"
  cat > "$list_md" <<'LISTEOF'
| # | ステータス | Phase | 概要 | 依存 | 詳細 |
|:---:|:---:|:---|:---|:---|:---|
| 1 | ✅ | some-other-task | ... | — | ... |
LISTEOF

  # fixture: 書き込み対象の draft file (内容は問わない)
  local draft_fp="${TMP_ROOT}/docs/draft/test-slug-not-planned.md"
  touch "$draft_fp"

  local out additional_ctx
  out=$(json_write_input "$draft_fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  additional_ctx=$(extract_additional_context "$out")

  if printf '%s' "$additional_ctx" | grep -q "plan-first"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (additionalContext did not contain 'plan-first')")
    printf "  FAIL: %s\n    additionalContext: %s\n    out: %s\n" "$label" "$additional_ctx" "$out"
  fi
}

# === Case 13 (task-36 Sub B + iter2 F4): docs/draft/<slug>.md Write、list.md に 📝 行存在 → 素通り (plan-first keyword + 出典文字列 共に不在) ===
#
# 設計起源: task-36 task file Step 3 + iter2 reviewer A HIGH (trivial-pass 解消)
# iter2 F4 強化: "plan-first" だけでなく、warn message 出典 "task-management.md" + "[task-rule-guard]" prefix も同時に不在 assert。
case13_draft_write_planned_row_exists_passthrough() {
  local label="Case 13: docs/draft/<slug> Write, list.md has 📝 row → no plan-first warn (strict: 3 keyword 全て不在)"

  # fixture: list.md に対象 slug の 📝 行が存在する状態
  local list_md="${TMP_ROOT}/docs/tasks/list.md"
  cat > "$list_md" <<'LISTEOF'
| # | ステータス | Phase | 概要 | 依存 | 詳細 |
|:---:|:---:|:---|:---|:---|:---|
| 99 | 📝 | test-slug-planned | ... | — | ... |
LISTEOF

  # fixture: 書き込み対象の draft file
  local draft_fp="${TMP_ROOT}/docs/draft/test-slug-planned.md"
  touch "$draft_fp"

  local out additional_ctx
  out=$(json_write_input "$draft_fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  additional_ctx=$(extract_additional_context "$out")

  # F4 strict assert: 3 keyword すべて不在を確認
  # 1. "plan-first" 不在 (warn message keyword)
  # 2. "task-management.md" 不在 (warn message 出典 link)
  # 3. "[task-rule-guard]" prefix 不在 (warn message header)
  local why=""
  local pass=1
  if printf '%s' "$additional_ctx" | grep -q "plan-first"; then
    pass=0
    why="'plan-first' keyword unexpectedly present"
  elif printf '%s' "$additional_ctx" | grep -q "task-management.md"; then
    pass=0
    why="warn 出典 'task-management.md' unexpectedly present"
  elif printf '%s' "$additional_ctx" | grep -q '\[task-rule-guard\]'; then
    pass=0
    why="warn prefix '[task-rule-guard]' unexpectedly present"
  fi

  if [ "$pass" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label ($why)")
    printf "  FAIL: %s\n    why: %s\n    additionalContext: %s\n    out: %s\n" "$label" "$why" "$additional_ctx" "$out"
  fi
}

# === Case 14a/b/c (task-36 Step 2 iter2 F6): edge case (空 / 1 文字 / 日本語 slug) ===
#
# 設計起源: task-36 task file Step 2 iter2 reviewer A/C MED
# 期待: 異常入力で hook は silent pass or 正常終了 (異常終了 / hang / parse_error なし)
case14a_empty_slug_silent_pass() {
  local label="Case 14a: empty basename '.md' (no slug) → hook silent pass (no crash)"
  local fp="${TMP_ROOT}/docs/draft/.md"
  # file は作らない (Write 前提、hook は file 存在 check しない)
  local out decision
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")

  # hook は異常終了せず JSON を返すか empty object を返す ("decision":"block" でも問題なし、crash しない事を確認)
  # parse_error は許容しない (json 不正)
  if [ "$decision" != "parse_error" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (hook output not valid JSON, decision=$decision)")
    printf "  FAIL: %s\n    out: %s\n" "$label" "$out"
  fi
}

case14b_single_dash_slug() {
  local label="Case 14b: '-.md' (1 char slug '-') → hook handles without crash"
  local fp="${TMP_ROOT}/docs/draft/-.md"
  local out decision
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "parse_error" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (hook output not valid JSON, decision=$decision)")
    printf "  FAIL: %s\n    out: %s\n" "$label" "$out"
  fi
}

case14c_japanese_slug_no_crash() {
  local label="Case 14c: '日本語タスク.md' (non-ASCII slug) → hook handles without crash"
  local fp="${TMP_ROOT}/docs/draft/日本語タスク.md"
  local out decision
  out=$(json_write_input "$fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Write 2>/dev/null)
  decision=$(extract_decision "$out")

  if [ "$decision" != "parse_error" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (hook output not valid JSON, decision=$decision)")
    printf "  FAIL: %s\n    out: %s\n" "$label" "$out"
  fi
}

# === Case 15 (task-36 Step 2 iter3 F8): docs/draft/<existing-slug>.md への Edit → 素通り (additionalContext 不在) ===
#
# 設計起源: task-36 Step 2 iter2 F1 で導入した「Edit は draft warn 判定対象外」logic を直接検証する positive case
# 期待: hook が Edit tool で呼ばれた場合、L121-124 の `if [ "$tool" != "Write" ]; then echo '{}'; exit 0; fi` 早期 return で素通り
# 検証: additionalContext が hookSpecificOutput.additionalContext path で 不在 (empty)
#        list.md に 📝 行が無い (本来 Write なら warn 注入されるべき条件) でも warn 不発火を確認
case15_edit_on_draft_no_warn() {
  local label="Case 15: Edit on docs/draft/<slug>.md → no warn (F1 regression test, iter3 F8)"

  # fixture: list.md に対象 slug の 📝 行が無い状態 (Write だったら warn 発火する条件)
  local list_md="${TMP_ROOT}/docs/tasks/list.md"
  cat > "$list_md" <<'LISTEOF'
| # | ステータス | Phase | 概要 | 依存 | 詳細 |
|:---:|:---:|:---|:---|:---|:---|
| 1 | ✅ | unrelated-task | ... | — | ... |
LISTEOF

  # fixture: Edit 対象の既存 draft file
  local draft_fp="${TMP_ROOT}/docs/draft/test-edit-slug.md"
  touch "$draft_fp"

  local out additional_ctx
  out=$(json_edit_input "$draft_fp" | env "${COMMON_ENV[@]}" bash "$HOOK" Edit 2>/dev/null)
  additional_ctx=$(extract_additional_context "$out")

  # Edit 素通り = additionalContext 不在 (empty) であること
  # F1 guard が機能していれば Edit tool では plan-first warn は注入されない
  if [ -z "$additional_ctx" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (Edit on draft で warn 注入された、F1 guard regression)")
    printf "  FAIL: %s\n    additionalContext: %s\n    out: %s\n" "$label" "$additional_ctx" "$out"
  fi
}

printf "===== task-rule-guard-smoke (task-22 W3.2 + task-29 Phase 4 Step 1 + task-21 W3 + task-36 Step 3 Sub B + task-36 Step 2 iter2 採用 6 条 + iter3 F7/F8/F9, 17 cases) =====\n\n"

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
case12_draft_write_no_planned_row_warns
case13_draft_write_planned_row_exists_passthrough
case14a_empty_slug_silent_pass
case14b_single_dash_slug
case14c_japanese_slug_no_crash
case15_edit_on_draft_no_warn

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
