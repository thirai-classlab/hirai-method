#!/usr/bin/env bash
# rule-change-draft-flow-guard-smoke.sh — task-40 Step 6 smoke
#
# 設計起源:
#   docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40)
#   Step 4 で拡張した draft-flow-guard.sh の新 path pattern + frontmatter parse +
#   bypass env + 既存 docs/ 直下 BLOCK 回帰の 6 case 検証。
#
# 対象 hook:
#   .claude/hooks/draft-flow-guard.sh (PreToolUse Edit/Write、task-40 拡張版)
#
# 検証範囲 (6 ケース):
#   Case 1: .claude/rules/foo.md 新規 Write + 対応 draft 不在 → BLOCK (exit 2)
#   Case 2: .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at 非空) → PASS
#   Case 3: .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at 空) → BLOCK
#   Case 4: .claude/templates/docs/tasks/foo.md 新規 Write + retroactive: true → PASS + warn
#   Case 5: .claude/rules/foo.md 新規 Write + ECC_RULE_CHANGE_GUARD_OFF=1 → PASS
#   Case 6: docs/new-feature.md 新規 Write + 対応 draft 不在 → BLOCK (既存挙動回帰)
#
# 重要制約:
#   - file-top の set -uo pipefail (errexit 外し、feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って独立 ツリーを配置
#   - hook は project-root.sh の resolve_project_root に依存するため、tmp_root に .git
#   - hook は exit 2 で BLOCK、exit 0 で PASS
#
# 実行:
#   bash .claude/tests/rule-change-draft-flow-guard-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/draft-flow-guard.sh"

# clean env (新旧両方 bypass を unset)
unset ECC_DRAFT_FLOW_GUARD_OVERRIDE
unset ECC_RULE_CHANGE_GUARD_OFF
unset HC_RULE_CHANGE_GUARD_ENABLED
unset HC_DRAFT_FLOW_GUARD_WHITELIST
unset HC_DOCS_APPROVED_DIR

# tmp project root に .git/ を作って resolve_project_root が安定して解決するように
TMP_ROOT="$(mktemp -d /tmp/rule-change-draft-flow-guard-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" \
         "$TMP_ROOT/docs/draft" \
         "$TMP_ROOT/docs/tasks" \
         "$TMP_ROOT/.claude/rules" \
         "$TMP_ROOT/.claude/commands" \
         "$TMP_ROOT/.claude/templates/docs/tasks"

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

# hook を tmp project root cwd で実行
run_hook() {
  local tool="$1"
  local fp="$2"
  shift 2
  (
    cd "$TMP_ROOT" || exit 99
    if [ $# -gt 0 ]; then
      hook_input "$tool" "$fp" | env "$@" bash "$HOOK"
    else
      hook_input "$tool" "$fp" | bash "$HOOK"
    fi
  )
}

# helper: draft を frontmatter 付きで作成
write_draft() {
  local path="$1"
  local approved_at="$2"  # 値 (空可)
  local retroactive="${3:-}"  # "true" or "" (省略可)
  {
    echo '<!--'
    [ -n "$approved_at" ] && echo "approved_at: $approved_at"
    [ -n "$retroactive" ] && echo "retroactive: $retroactive"
    echo '-->'
    echo ''
    echo '# draft body'
  } > "$path"
}

# === Case 1: .claude/rules/foo.md 新規 Write + 対応 draft 不在 → BLOCK ===
case1_rules_no_draft_block() {
  local label="Case 1: .claude/rules/case1.md w/o draft → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/.claude/rules/case1.md"
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

# === Case 2: .claude/rules/foo.md + draft (approved_at 非空) → PASS ===
case2_rules_approved_pass() {
  local label="Case 2: .claude/rules/case2.md w/ approved draft → PASS"
  local fp="${TMP_ROOT}/.claude/rules/case2.md"
  write_draft "${TMP_ROOT}/docs/draft/case2.md" "2026-05-26" ""
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

# === Case 3: .claude/rules/foo.md + draft (approved_at 空) → BLOCK ===
case3_rules_unapproved_block() {
  local label="Case 3: .claude/rules/case3.md w/ unapproved draft → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/.claude/rules/case3.md"
  # draft 存在するが approved_at 空 (frontmatter に key 自体なし)
  write_draft "${TMP_ROOT}/docs/draft/case3.md" "" ""
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

# === Case 4: .claude/templates/docs/tasks/foo.md + retroactive: true → PASS + warn ===
case4_templates_retroactive_pass_warn() {
  local label="Case 4: .claude/templates/docs/tasks/case4.md w/ retroactive draft → PASS + warn"
  local fp="${TMP_ROOT}/.claude/templates/docs/tasks/case4.md"
  write_draft "${TMP_ROOT}/docs/draft/case4.md" "" "true"
  local rc=0
  local stderr_out
  stderr_out=$(run_hook Write "$fp" 2>&1 >/dev/null) || rc=$?

  if [ "$rc" -eq 0 ] && printf '%s' "$stderr_out" | grep -q 'retroactive'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc, stderr=<<<$stderr_out>>>)")
    printf "  FAIL: %s (rc=%d expected 0+warn)\n" "$label" "$rc"
  fi
}

# === Case 5: .claude/rules/foo.md + ECC_RULE_CHANGE_GUARD_OFF=1 → PASS ===
case5_bypass_env_pass() {
  local label="Case 5: ECC_RULE_CHANGE_GUARD_OFF=1 on BLOCK case → PASS"
  local fp="${TMP_ROOT}/.claude/rules/case5.md"
  local rc=0
  run_hook Write "$fp" ECC_RULE_CHANGE_GUARD_OFF=1 >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 6: docs/new-feature.md 新規 Write + draft 不在 → BLOCK (回帰検証) ===
case6_docs_root_block_regression() {
  local label="Case 6: docs/case6.md w/o draft → BLOCK (regression check)"
  local fp="${TMP_ROOT}/docs/case6.md"
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

printf "===== rule-change-draft-flow-guard-smoke (task-40 Step 6, 6 cases) =====\n\n"

case1_rules_no_draft_block
case2_rules_approved_pass
case3_rules_unapproved_block
case4_templates_retroactive_pass_warn
case5_bypass_env_pass
case6_docs_root_block_regression

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
