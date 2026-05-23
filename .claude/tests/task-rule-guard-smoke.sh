#!/usr/bin/env bash
# task-rule-guard-smoke.sh — task-22 W3 smoke for task-rule-guard.sh
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#
# 対象 hook:
#   .claude/hooks/task-rule-guard.sh
#
# 検証範囲 (5 ケース):
#   Case 1: 新規 task Write、対応 draft 不在 → BLOCK
#   Case 2: 新規 task Write、対応 draft 存在 → PASS (additionalContext)
#   Case 3: 既存 list.md の Edit → PASS (exempt)
#   Case 4: ID 重複 (同 id-* file 既存) で別 slug の Write → BLOCK
#   Case 5: ECC_TASKGUARD=off で BLOCK ケース → PASS
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って docs/tasks docs/draft を配置
#   - hook は HC_TASK_DIR / HC_DRAFT_DIR / HC_TASKGUARD_STATE_DIR の env override に従う
#   - subagent 短絡防止: CLAUDE_HARNESS_ROLE をクリア + HC_AGENT_MARKER_DIR を空 dir に向ける
#
# 実行:
#   bash .claude/tests/task-rule-guard-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/task-rule-guard.sh"

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

printf "===== task-rule-guard-smoke (task-22 W3.2, 5 cases) =====\n\n"

case1_no_draft_blocked
case2_draft_exists_pass
case3_list_md_exempt
case4_id_duplicate_blocked
case5_bypass_env_pass

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
