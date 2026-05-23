#!/usr/bin/env bash
# draft-flow-guard-approved-dir-smoke.sh — task-24 W3 smoke for HC_DOCS_APPROVED_DIR
#
# 設計起源:
#   docs/draft/taskmanagesystem-recovery.md Q2 (2026-05-23)
#
# 対象 hook:
#   .claude/hooks/draft-flow-guard.sh (PreToolUse Edit/Write)
#
# 検証範囲 (7 ケース):
#   Case 1: HC_DOCS_APPROVED_DIR 未設定で docs/foo.md Write → BLOCK (regression)
#   Case 2: HC_DOCS_APPROVED_DIR=design で docs/design/foo.md Write → PASS
#   Case 3: HC_DOCS_APPROVED_DIR=design で docs/foo.md Write → BLOCK (approved_dir 外)
#   Case 4: HC_DOCS_APPROVED_DIR=design で docs/draft/foo.md Write → PASS (既存 draft 経路温存)
#   Case 5: HC_DOCS_APPROVED_DIR=design で docs/design/sub/nested.md Write → PASS (深さ 3、対象外)
#   Case 6: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 で docs/foo.md Write → PASS (bypass)
#   Case 7: HC_DOCS_APPROVED_DIR=design,research (CSV) で docs/research/foo.md Write → PASS
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root に .git/ を作って resolve_project_root を安定化
#   - hook は exit 2 で BLOCK、exit 0 で PASS
#
# 実行:
#   bash .claude/tests/draft-flow-guard-approved-dir-smoke.sh
#
# 終了コード:
#   0 = 7/7 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/draft-flow-guard.sh"

# clean env
unset ECC_DRAFT_FLOW_GUARD_OVERRIDE
unset HC_DRAFT_FLOW_GUARD_WHITELIST
unset HC_DOCS_APPROVED_DIR

# tmp project root に .git/ を作って resolve_project_root が安定して解決するように
TMP_ROOT="$(mktemp -d /tmp/draft-flow-guard-approved-dir-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" \
         "$TMP_ROOT/docs/draft" \
         "$TMP_ROOT/docs/tasks" \
         "$TMP_ROOT/docs/design" \
         "$TMP_ROOT/docs/design/sub" \
         "$TMP_ROOT/docs/research"

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

# === Case 1: HC_DOCS_APPROVED_DIR 未設定 + docs/foo.md → BLOCK (regression) ===
case1_unset_block_regression() {
  local label="Case 1: HC_DOCS_APPROVED_DIR unset + docs/foo.md → BLOCK (regression)"
  local fp="${TMP_ROOT}/docs/case1-unset.md"
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

# === Case 2: HC_DOCS_APPROVED_DIR=design + docs/design/foo.md → PASS ===
case2_approved_dir_design_pass() {
  local label="Case 2: HC_DOCS_APPROVED_DIR=design + docs/design/foo.md → PASS"
  local fp="${TMP_ROOT}/docs/design/case2-design.md"
  local rc=0
  run_hook Write "$fp" HC_DOCS_APPROVED_DIR=design >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 3: HC_DOCS_APPROVED_DIR=design + docs/foo.md → BLOCK (approved_dir 外) ===
case3_approved_dir_outside_block() {
  local label="Case 3: HC_DOCS_APPROVED_DIR=design + docs/foo.md → BLOCK (outside)"
  local fp="${TMP_ROOT}/docs/case3-outside.md"
  local rc=0
  run_hook Write "$fp" HC_DOCS_APPROVED_DIR=design >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 2 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 2)\n" "$label" "$rc"
  fi
}

# === Case 4: HC_DOCS_APPROVED_DIR=design + docs/draft/foo.md → PASS (既存 draft 経路温存) ===
case4_draft_path_preserved() {
  local label="Case 4: HC_DOCS_APPROVED_DIR=design + docs/draft/foo.md → PASS (preserved)"
  local fp="${TMP_ROOT}/docs/draft/case4-draft.md"
  local rc=0
  run_hook Write "$fp" HC_DOCS_APPROVED_DIR=design >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 5: HC_DOCS_APPROVED_DIR=design + docs/design/sub/nested.md → PASS (深さ 3、対象外) ===
# 現 hook は docs/ 直下深さ 1 のみ block。深さ 3 (docs/design/sub/nested.md) は元々対象外で PASS。
# 「approved_dir 配下も深さ 1 のみ approved とするのが整合的」= 深さ 1 (=docs 全体で深さ 2) のみ
# approved として PASS、深さ 2+ (=docs 全体で深さ 3+) は元の対象外挙動で PASS。
# 結果: 深さ 3 は PASS (block されない、approved 範囲外でもあるが block 対象でもない)。
case5_deeper_nested_pass() {
  local label="Case 5: HC_DOCS_APPROVED_DIR=design + docs/design/sub/nested.md → PASS (depth 3, out of scope)"
  local fp="${TMP_ROOT}/docs/design/sub/case5-nested.md"
  local rc=0
  run_hook Write "$fp" HC_DOCS_APPROVED_DIR=design >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 6: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + docs/foo.md → PASS (bypass) ===
case6_bypass_env_pass() {
  local label="Case 6: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + docs/foo.md → PASS (bypass)"
  local fp="${TMP_ROOT}/docs/case6-bypass.md"
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

# === Case 7: HC_DOCS_APPROVED_DIR=design,research (CSV) + docs/research/foo.md → PASS ===
case7_csv_multi_value_pass() {
  local label="Case 7: HC_DOCS_APPROVED_DIR=design,research (CSV) + docs/research/foo.md → PASS"
  local fp="${TMP_ROOT}/docs/research/case7-csv.md"
  local rc=0
  run_hook Write "$fp" HC_DOCS_APPROVED_DIR=design,research >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

printf "===== draft-flow-guard-approved-dir-smoke (task-24 W3, 7 cases) =====\n\n"

case1_unset_block_regression
case2_approved_dir_design_pass
case3_approved_dir_outside_block
case4_draft_path_preserved
case5_deeper_nested_pass
case6_bypass_env_pass
case7_csv_multi_value_pass

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
