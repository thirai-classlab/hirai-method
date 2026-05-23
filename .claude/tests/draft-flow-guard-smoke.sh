#!/usr/bin/env bash
# draft-flow-guard-smoke.sh — task-22 W3 smoke for draft-flow-guard.sh
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md W3
#   docs/draft/system-reminder-attention-fix.md Wave 2.3
#
# 対象 hook:
#   .claude/hooks/draft-flow-guard.sh (PreToolUse Edit/Write)
#
# 検証範囲 (5 ケース):
#   Case 1: docs/foo.md 新規 Write、対応 draft 不在 → BLOCK (exit 2)
#   Case 2: docs/foo.md 新規 Write、対応 docs/draft/foo.md 存在 → PASS (exit 0)
#   Case 3: 既存 docs/foo.md の Edit → PASS (既存 file は素通し)
#   Case 4: docs/sub/foo.md (深さ 2) → PASS (docs 直下のみが対象)
#   Case 5: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + 新規 BLOCK ケース → PASS (bypass env)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って独立 docs ツリーを配置
#   - hook は project-root.sh の resolve_project_root に依存するため、tmp_root に .git を作る
#   - hook は exit 2 で BLOCK、exit 0 で PASS (decision JSON ではない点が他 hook と異なる)
#
# 実行:
#   bash .claude/tests/draft-flow-guard-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/draft-flow-guard.sh"

# clean env
unset ECC_DRAFT_FLOW_GUARD_OVERRIDE
unset HC_DRAFT_FLOW_GUARD_WHITELIST

# tmp project root に .git/ を作って resolve_project_root が安定して解決するように
TMP_ROOT="$(mktemp -d /tmp/draft-flow-guard-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" "$TMP_ROOT/docs/draft" "$TMP_ROOT/docs/tasks" "$TMP_ROOT/docs/sub"

trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# hook input JSON (PreToolUse Edit/Write)
hook_input() {
  local tool="$1"
  local fp="$2"
  TOOL="$tool" FP="$fp" python3 -c '
import json, os
print(json.dumps({
    "tool_name": os.environ["TOOL"],
    "tool_input": {"file_path": os.environ["FP"]}
}))
'
}

# hook を tmp project root cwd で実行 (resolve_project_root が pwd fallback)
# exit code を捕捉する (set -e なし)。
run_hook() {
  local tool="$1"
  local fp="$2"
  shift 2
  # 残りの引数は env 設定 (KEY=VALUE 形式)
  (
    cd "$TMP_ROOT" || exit 99
    if [ $# -gt 0 ]; then
      hook_input "$tool" "$fp" | env "$@" bash "$HOOK"
    else
      hook_input "$tool" "$fp" | bash "$HOOK"
    fi
  )
}

# === Case 1: 新規 Write w/o draft → BLOCK (exit 2) ===
case1_no_draft_block() {
  local label="Case 1: new docs/foo.md Write w/o draft → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/docs/case1-no-draft.md"
  # file は実体不在のままで Write を試みる
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 2 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 2)\n" "$label" "$rc"
  fi
}

# === Case 2: 新規 Write w/ matching draft → PASS (exit 0) ===
case2_with_draft_pass() {
  local label="Case 2: new docs/foo.md Write w/ matching draft → PASS"
  local fp="${TMP_ROOT}/docs/case2-with-draft.md"
  # 対応 draft を先に作る
  touch "${TMP_ROOT}/docs/draft/case2-with-draft.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 3: 既存 docs/foo.md の Edit → PASS ===
case3_existing_file_edit_pass() {
  local label="Case 3: existing docs/foo.md Edit → PASS"
  local fp="${TMP_ROOT}/docs/case3-existing.md"
  # 既存 file (draft なくても OK)
  echo "existing content" > "$fp"
  local rc=0
  run_hook Edit "$fp" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 4: docs/sub/foo.md (深さ 2) → PASS ===
# hook は深さ 1 (docs 直下) のみが対象、それより深い path は対象外
case4_deeper_path_pass() {
  local label="Case 4: docs/sub/foo.md (depth 2) → PASS (out of scope)"
  local fp="${TMP_ROOT}/docs/sub/case4-deep.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 5: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + 本来 BLOCK case → PASS ===
case5_bypass_env_pass() {
  local label="Case 5: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 on BLOCK case → PASS"
  local fp="${TMP_ROOT}/docs/case5-bypassed.md"
  local rc=0
  run_hook Write "$fp" ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

printf "===== draft-flow-guard-smoke (task-22 W3.5, 5 cases) =====\n\n"

case1_no_draft_block
case2_with_draft_pass
case3_existing_file_edit_pass
case4_deeper_path_pass
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
