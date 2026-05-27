#!/usr/bin/env bash
# rule-change-draft-flow-guard-smoke.sh — task-40 拡張の緩和 (2026-05-28) smoke
#
# 設計起源:
#   docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40、2026-05-26)
#   2026-05-28 user 指示「既存 rules file の Edit は PASS (新規 Write のみ
#   BLOCK) → 書き込みも許容してください」で task-40 拡張部分を撤廃。
#
# 緩和内容:
#   旧 task-40 拡張は .claude/rules/*.md / .claude/commands/*.md /
#   .claude/templates/docs/**/*.md への新規 Write を draft 承認 (approved_at /
#   retroactive) 不在で BLOCK していた。本緩和で **これらは新規 Write / 既存
#   Edit とも PASS** になる (本 hook は一切監視しない)。
#   docs/ 直下の新規設計文書 BLOCK + 既存 Edit PASS は **完全維持** (回帰)。
#
# 対象 hook:
#   .claude/hooks/draft-flow-guard.sh (PreToolUse Edit/Write)
#
# 検証範囲 (13 active + 1 skip):
#   Case 1:  .claude/rules/foo.md 新規 Write + 対応 draft 不在 → PASS (緩和、旧 BLOCK)
#   Case 2:  .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at 非空) → PASS
#   Case 3:  .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at key 不在) → PASS (緩和、旧 BLOCK)
#   Case 4:  .claude/templates/docs/tasks/foo.md 新規 Write + retroactive draft → PASS (緩和、旧 PASS+warn)
#   Case 5:  .claude/rules/foo.md + ECC_RULE_CHANGE_GUARD_OFF=1 → PASS (env は dead path、緩和後も PASS)
#   Case 6:  docs/new-feature.md 新規 Write + 対応 draft 不在 → BLOCK (docs/ block 維持、回帰)
#   Case 7:  .claude/commands/foo.md 新規 Write + 対応 draft 不在 → PASS (緩和、旧 BLOCK)
#   Case 8:  既存 .claude/rules/<existing>.md Edit → PASS (緩和前後とも PASS)
#   Case 9:  ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 で .claude/rules/foo.md Write → PASS + bypass.log (override は hook 冒頭で維持)
#   Case 10: approved_at: (空白のみ) draft で .claude/rules/foo.md → PASS (緩和、旧 BLOCK)
#   Case 11: approved_at: (key only) draft で .claude/rules/foo.md → PASS (緩和、旧 BLOCK)
#   Case 12: .claude/rules/sub/foo.md (深さ 2) Write → PASS (緩和前後とも PASS)
#   Case 13: HC_RULE_CHANGE_GUARD_ENABLED=false で .claude/rules/foo.md Write → PASS (config は dead path、緩和後も PASS)
#   Case 14: docs/draft/ + docs/tasks/ 配下 → PASS [SKIP: 既存 draft-flow-guard-smoke.sh で網羅]
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
#   0 = 全 PASS / 1 = 1 件以上 FAIL

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
unset ECC_BYPASS_REASON

# tmp project root に .git/ を作って resolve_project_root が安定して解決するように
TMP_ROOT="$(mktemp -d /tmp/rule-change-draft-flow-guard-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" \
         "$TMP_ROOT/docs/draft" \
         "$TMP_ROOT/docs/tasks" \
         "$TMP_ROOT/.claude/rules" \
         "$TMP_ROOT/.claude/commands" \
         "$TMP_ROOT/.claude/templates/docs/tasks" \
         "$TMP_ROOT/.claude/rules/sub" \
         "$TMP_ROOT/.claude/.workflow-state"

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
      hook_input "$tool" "$fp" | env CLAUDE_PROJECT_DIR="$TMP_ROOT" "$@" bash "$HOOK"
    else
      hook_input "$tool" "$fp" | CLAUDE_PROJECT_DIR="$TMP_ROOT" bash "$HOOK"
    fi
  )
}

# helper: draft を frontmatter 付きで作成
write_draft() {
  local _path="$1"
  local _approved_at="$2"
  local _retroactive="${3:-}"
  local _approved_by="${4:-}"
  mkdir -p "$(dirname "$_path")"
  {
    echo '<!--'
    [ -n "$_approved_at" ] && echo "approved_at: $_approved_at"
    [ -n "$_retroactive" ] && echo "retroactive: $_retroactive"
    [ -n "$_approved_by" ] && echo "approved_by: $_approved_by"
    echo '-->'
    echo ''
    echo '# draft body'
  } > "$_path"
}

write_draft_key_only() {
  local path="$1"
  {
    echo '<!--'
    printf 'approved_at:\n'
    echo '-->'
    echo ''
    echo '# draft body'
  } > "$path"
}

write_draft_spaces_only() {
  local path="$1"
  {
    echo '<!--'
    printf 'approved_at:    \n'
    echo '-->'
    echo ''
    echo '# draft body'
  } > "$path"
}

# 汎用 PASS 期待 assertion (rc=0)
assert_pass() {
  local label="$1"; local rc="$2"
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("$label (rc=$rc expected 0)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# 汎用 BLOCK 期待 assertion (rc=2)
assert_block() {
  local label="$1"; local rc="$2"
  if [ "$rc" -eq 2 ]; then
    PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("$label (rc=$rc expected 2)")
    printf "  FAIL: %s (rc=%d expected 2)\n" "$label" "$rc"
  fi
}

# === Case 1 (緩和): .claude/rules/foo.md 新規 Write + 対応 draft 不在 → PASS ===
case1_rules_no_draft_pass() {
  local label="Case 1 (緩和): .claude/rules/case1.md w/o draft → PASS (旧 BLOCK)"
  local fp="${TMP_ROOT}/.claude/rules/case1.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 2: .claude/rules/foo.md + draft (approved_at 非空) → PASS ===
case2_rules_approved_pass() {
  local label="Case 2: .claude/rules/case2.md w/ approved draft → PASS"
  local fp="${TMP_ROOT}/.claude/rules/case2.md"
  write_draft "${TMP_ROOT}/docs/draft/case2.md" "2026-05-26"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 3 (緩和): .claude/rules/foo.md + draft (approved_at key 不在) → PASS ===
case3_rules_unapproved_pass() {
  local label="Case 3 (緩和): .claude/rules/case3.md w/ draft (approved_at key absent) → PASS (旧 BLOCK)"
  local fp="${TMP_ROOT}/.claude/rules/case3.md"
  write_draft "${TMP_ROOT}/docs/draft/case3.md" "" ""
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 4 (緩和): templates/docs retroactive draft → PASS (warn なし) ===
case4_templates_retroactive_pass() {
  local label="Case 4 (緩和): templates/docs retroactive draft → PASS (旧 PASS+warn、現 plain PASS)"
  local fp="${TMP_ROOT}/.claude/templates/docs/tasks/case4.md"
  write_draft "${TMP_ROOT}/docs/draft/case4.md" "" "true" "Hirai"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 5 (緩和): ECC_RULE_CHANGE_GUARD_OFF=1 → PASS (env は dead path だが結果 PASS) ===
case5_rule_guard_off_pass() {
  local label="Case 5 (緩和): ECC_RULE_CHANGE_GUARD_OFF=1 on rules → PASS (env dead path)"
  local fp="${TMP_ROOT}/.claude/rules/case5.md"
  local rc=0
  run_hook Write "$fp" ECC_RULE_CHANGE_GUARD_OFF=1 >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 6: docs/new-feature.md 新規 Write + draft 不在 → BLOCK (docs/ block 維持、回帰) ===
case6_docs_root_block_regression() {
  local label="Case 6 (回帰): docs/case6.md w/o draft → BLOCK (docs/ block 維持)"
  local fp="${TMP_ROOT}/docs/case6.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_block "$label" "$rc"
}

# === Case 7 (緩和): .claude/commands/foo.md 新規 Write + draft 不在 → PASS ===
case7_commands_no_draft_pass() {
  local label="Case 7 (緩和): .claude/commands/case7.md w/o draft → PASS (旧 BLOCK)"
  local fp="${TMP_ROOT}/.claude/commands/case7.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 8: 既存 .claude/rules/<existing>.md Edit → PASS (緩和前後とも) ===
case8_existing_rules_edit_pass() {
  local label="Case 8: existing .claude/rules/existing.md Edit → PASS (edit pass-through)"
  local fp="${TMP_ROOT}/.claude/rules/existing.md"
  touch "$fp"
  local rc=0
  run_hook Edit "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 9: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + .claude/rules/foo.md Write → PASS + bypass.log ===
# override は hook 冒頭 (docs/ block 含む全 path) で維持されるため bypass.log 記録も継続。
case9_override_env_pass_and_bypass_log() {
  local label="Case 9: ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 → PASS + bypass.log (override 維持)"
  local fp="${TMP_ROOT}/.claude/rules/case9.md"
  local bypass_log="${TMP_ROOT}/.claude/.workflow-state/bypass.log"
  rm -f "$bypass_log"
  local rc=0
  run_hook Write "$fp" ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 >/dev/null 2>&1 || rc=$?

  local bypass_logged=0
  if [ -f "$bypass_log" ] && grep -q "ECC_DRAFT_FLOW_GUARD_OVERRIDE" "$bypass_log" 2>/dev/null; then
    bypass_logged=1
  fi

  if [ "$rc" -eq 0 ] && [ "$bypass_logged" -eq 1 ]; then
    PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("$label (rc=$rc, bypass_logged=$bypass_logged)")
    printf "  FAIL: %s (rc=%d expected 0, bypass=%d)\n" "$label" "$rc" "$bypass_logged"
  fi
}

# === Case 10 (緩和): approved_at: (空白のみ) draft で rules → PASS ===
case10_approved_at_spaces_only_pass() {
  local label="Case 10 (緩和): approved_at spaces-only draft + rules → PASS (旧 BLOCK)"
  local fp="${TMP_ROOT}/.claude/rules/case10.md"
  write_draft_spaces_only "${TMP_ROOT}/docs/draft/case10.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 11 (緩和): approved_at: (key only) draft で rules → PASS ===
case11_approved_at_key_only_pass() {
  local label="Case 11 (緩和): approved_at key-only draft + rules → PASS (旧 BLOCK)"
  local fp="${TMP_ROOT}/.claude/rules/case11.md"
  write_draft_key_only "${TMP_ROOT}/docs/draft/case11.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 12: .claude/rules/sub/foo.md (深さ 2) Write → PASS (緩和前後とも) ===
case12_rules_subdirectory_depth2_pass() {
  local label="Case 12: .claude/rules/sub/case12.md (depth 2) Write → PASS"
  local fp="${TMP_ROOT}/.claude/rules/sub/case12.md"
  local rc=0
  run_hook Write "$fp" >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 13 (緩和): HC_RULE_CHANGE_GUARD_ENABLED=false → PASS (config dead path だが結果 PASS) ===
case13_config_guard_disabled_pass() {
  local label="Case 13 (緩和): HC_RULE_CHANGE_GUARD_ENABLED=false + rules → PASS (config dead path)"
  local fp="${TMP_ROOT}/.claude/rules/case13.md"
  local rc=0
  run_hook Write "$fp" HC_RULE_CHANGE_GUARD_ENABLED=false >/dev/null 2>&1 || rc=$?
  assert_pass "$label" "$rc"
}

# === Case 14: docs/draft/ + docs/tasks/ 配下は対象外 [SKIP] ===
case14_draft_tasks_exempt_skip() {
  local label="Case 14: docs/draft/ + docs/tasks/ 配下 exempt → PASS [SKIP: draft-flow-guard-smoke.sh で網羅]"
  printf "  NOTE: %s\n" "$label"
}

printf "===== rule-change-draft-flow-guard-smoke (2026-05-28 緩和、13 active + 1 skip) =====\n\n"

case1_rules_no_draft_pass
case2_rules_approved_pass
case3_rules_unapproved_pass
case4_templates_retroactive_pass
case5_rule_guard_off_pass
case6_docs_root_block_regression
case7_commands_no_draft_pass
case8_existing_rules_edit_pass
case9_override_env_pass_and_bypass_log
case10_approved_at_spaces_only_pass
case11_approved_at_key_only_pass
case12_rules_subdirectory_depth2_pass
case13_config_guard_disabled_pass
case14_draft_tasks_exempt_skip

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
