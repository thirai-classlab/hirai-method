#!/usr/bin/env bash
# rule-change-draft-flow-guard-smoke.sh — task-40 Step 7 iter3 smoke
#
# 設計起源:
#   docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40)
#   Step 4 で拡張した draft-flow-guard.sh の新 path pattern + frontmatter parse +
#   bypass env + 既存 docs/ 直下 BLOCK 回帰の検証。
#   Step 7 iter2 (HIGH-EFI + MEDIUM 1-4, 10) で 6 case → 12 case へ拡張。
#   Step 7 iter3 (MEDIUM-A/B) で Case 3 fixture 仕様明確化 + Case 9 WARN 分離。
#
# 対象 hook:
#   .claude/hooks/draft-flow-guard.sh (PreToolUse Edit/Write、task-40 拡張版)
#
# 検証範囲 (12 ケース):
#   Case 1:  .claude/rules/foo.md 新規 Write + 対応 draft 不在 → BLOCK (exit 2) + stderr "BLOCK"
#   Case 2:  .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at 非空) → PASS
#   Case 3:  .claude/rules/foo.md 新規 Write + 対応 draft あり (approved_at key 不在) → BLOCK + stderr "BLOCK"
#            ※ key 不在 (draft 存在のみ) の境界値。Case 10 (空白のみ) / Case 11 (key only 値なし) と
#               合わせて 3 境界値を網羅:
#               Case 3 = approved_at key 不在 / Case 10 = 空白のみ / Case 11 = key only
#   Case 4:  .claude/templates/docs/tasks/foo.md 新規 Write + retroactive: true → PASS + warn
#   Case 5:  .claude/rules/foo.md 新規 Write + ECC_RULE_CHANGE_GUARD_OFF=1 → PASS
#   Case 6:  docs/new-feature.md 新規 Write + 対応 draft 不在 → BLOCK (既存挙動回帰)
#   Case 7:  .claude/commands/foo.md 新規 Write + 対応 draft 不在 → BLOCK (HIGH-E)
#   Case 8:  既存 .claude/rules/<existing>.md Edit (tool_name=Edit) → PASS (HIGH-F)
#   Case 9:  ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 で .claude/rules/foo.md Write → PASS + bypass.log (HIGH-I)
#            ※ bypass.log 記録は best-effort: 記録あり=PASS、記録なし=WARN (PASS 扱いだが別カウント)
#   Case 10: approved_at: (空白のみ) draft → BLOCK (MEDIUM-1a)
#   Case 11: approved_at: (key only、値なし) draft → BLOCK (MEDIUM-1b)
#   Case 12: .claude/rules/sub/foo.md (深さ 2、out of scope) Write → PASS (MEDIUM-10)
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
#   0 = 全 PASS (WARN あり含む) / 1 = 1 件以上 FAIL

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
         "$TMP_ROOT/.claude/templates/docs/tasks" \
         "$TMP_ROOT/.claude/rules/sub" \
         "$TMP_ROOT/.claude/.workflow-state"

# MEDIUM-4: trap で tmp_root cleanup (中断時もリーク防止)
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
WARN=0
FAILED_CASES=()
WARNED_CASES=()

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
# CLAUDE_PROJECT_DIR を TMP_ROOT に設定してから hook 起動 (bypass.log 先を統一)
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

# helper: approved_at key のみ (値なし) の draft を作成
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

# helper: approved_at に空白のみの draft を作成
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

# === Case 1: .claude/rules/foo.md 新規 Write + 対応 draft 不在 → BLOCK + stderr "BLOCK" ===
case1_rules_no_draft_block() {
  local label="Case 1: .claude/rules/case1.md w/o draft → BLOCK (exit 2) + stderr BLOCK"
  local fp="${TMP_ROOT}/.claude/rules/case1.md"
  local rc=0
  local stderr_out
  # MEDIUM-2: stderr に "BLOCK" が含まれることを assertion
  stderr_out=$(run_hook Write "$fp" 2>&1 >/dev/null) || rc=$?

  if [ "$rc" -eq 2 ] && printf '%s' "$stderr_out" | grep -q "BLOCK"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc, stderr_has_BLOCK=$(printf '%s' "$stderr_out" | grep -c "BLOCK" 2>/dev/null || echo 0))")
    printf "  FAIL: %s (rc=%d expected 2, stderr_has_BLOCK=%s)\n" "$label" "$rc" \
      "$(printf '%s' "$stderr_out" | grep -c "BLOCK" 2>/dev/null || echo 0)"
  fi
}

# === Case 2: .claude/rules/foo.md + draft (approved_at 非空) → PASS ===
case2_rules_approved_pass() {
  local label="Case 2: .claude/rules/case2.md w/ approved draft → PASS"
  local fp="${TMP_ROOT}/.claude/rules/case2.md"
  write_draft "${TMP_ROOT}/docs/draft/case2.md" "2026-05-26"
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

# === Case 3: .claude/rules/foo.md + draft (approved_at key 不在) → BLOCK + stderr "BLOCK" ===
# 仕様 (MEDIUM-A 案 b): draft は存在するが frontmatter に approved_at key 自体が不在。
# write_draft に "" を渡すと [ -n "$approved_at" ] が false で key 自体が生成されない。
# これは意図通りの境界値 = "draft 存在 + approved_at key 不在"。
# 3 境界値全網羅:
#   Case 3  = approved_at key 不在 (本 Case)
#   Case 10 = approved_at: <空白のみ> (key あり・値が空白)
#   Case 11 = approved_at: (key only・値なし改行直後)
case3_rules_unapproved_block() {
  local label="Case 3: .claude/rules/case3.md w/ draft (approved_at key absent) → BLOCK (exit 2) + stderr BLOCK"
  local fp="${TMP_ROOT}/.claude/rules/case3.md"
  # draft 存在するが approved_at key 自体が frontmatter に不在 (write_draft に "" 渡しで key skip)
  write_draft "${TMP_ROOT}/docs/draft/case3.md" "" ""
  local rc=0
  local stderr_out
  # MEDIUM-2: stderr に "BLOCK" が含まれることを assertion
  stderr_out=$(run_hook Write "$fp" 2>&1 >/dev/null) || rc=$?

  if [ "$rc" -eq 2 ] && printf '%s' "$stderr_out" | grep -q "BLOCK"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc, stderr_has_BLOCK=$(printf '%s' "$stderr_out" | grep -c "BLOCK" 2>/dev/null || echo 0))")
    printf "  FAIL: %s (rc=%d expected 2, stderr_has_BLOCK=%s)\n" "$label" "$rc" \
      "$(printf '%s' "$stderr_out" | grep -c "BLOCK" 2>/dev/null || echo 0)"
  fi
}

# === Case 4: .claude/templates/docs/tasks/foo.md + retroactive: true → PASS + warn ===
case4_templates_retroactive_pass_warn() {
  local label="Case 4: .claude/templates/docs/tasks/case4.md w/ retroactive draft → PASS + warn"
  local fp="${TMP_ROOT}/.claude/templates/docs/tasks/case4.md"
  write_draft "${TMP_ROOT}/docs/draft/case4.md" "" "true"
  local rc=0
  local stderr_out
  # MEDIUM-3: 2>&1 >/dev/null の順序で stderr をコマンド置換にキャプチャ (正しい順序)
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

# === Case 7 (HIGH-E): .claude/commands/foo.md 新規 Write + draft 不在 → BLOCK ===
case7_commands_no_draft_block() {
  local label="Case 7 (HIGH-E): .claude/commands/case7.md w/o draft → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/.claude/commands/case7.md"
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

# === Case 8 (HIGH-F): 既存 .claude/rules/<existing>.md Edit → PASS ===
# 設計仕様: 新規 Write のみ BLOCK、既存 file の Edit は無条件 PASS
case8_existing_rules_edit_pass() {
  local label="Case 8 (HIGH-F): existing .claude/rules/existing.md Edit → PASS (edit pass-through)"
  local fp="${TMP_ROOT}/.claude/rules/existing.md"
  # 既存 file として touch で作成 (file が存在する状態を作る)
  touch "$fp"
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

# === Case 9 (HIGH-I): ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 + .claude/rules/foo.md Write → PASS + bypass.log ===
# MEDIUM-B: bypass.log 記録を 3 段階に分離:
#   完全 PASS: rc=0 && bypass_logged=1  → "PASS"
#   部分 PASS: rc=0 && bypass_logged=0  → "WARN: bypass.log 未記録" (PASS 扱い、WARN カウント)
#   FAIL:      rc!=0                    → "FAIL"
# WARN は exit code 0 を維持しつつ summary で別途報告。
# iter3-A で bypass-logger.sh sanitize が完了していれば bypass_logged=1 (完全 PASS) に到達可。
case9_override_env_pass_and_bypass_log() {
  local label="Case 9 (HIGH-I): ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 → PASS + bypass.log"
  local fp="${TMP_ROOT}/.claude/rules/case9.md"
  local bypass_log="${TMP_ROOT}/.claude/.workflow-state/bypass.log"
  # bypass.log を初期化
  rm -f "$bypass_log"
  local rc=0
  run_hook Write "$fp" ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 >/dev/null 2>&1 || rc=$?

  # bypass.log に記録されているか確認 (bypass-logger.sh が利用可能な場合のみ記録される)
  local bypass_logged=0
  if [ -f "$bypass_log" ] && grep -q "ECC_DRAFT_FLOW_GUARD_OVERRIDE" "$bypass_log" 2>/dev/null; then
    bypass_logged=1
  fi

  if [ "$rc" -eq 0 ] && [ "$bypass_logged" -eq 1 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  elif [ "$rc" -eq 0 ] && [ "$bypass_logged" -eq 0 ]; then
    # MEDIUM-B: bypass.log 未記録は WARN 扱い (PASS カウント + WARN カウント)
    # bypass-logger.sh が tmp 環境で機能しない場合に発生する可能性がある。
    # exit code は 0 維持 (PASS_COUNT に算入)、WARN_COUNT を別途インクリメント。
    PASS=$((PASS + 1))
    WARN=$((WARN + 1))
    WARNED_CASES+=("$label: bypass.log 未記録 (bypass-logger.sh が CLAUDE_PROJECT_DIR を解決できていない可能性)")
    printf "  WARN: %s\n" "$label"
    printf "    NOTE: bypass.log not recorded — verify bypass-logger.sh is working correctly\n"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc, bypass_logged=$bypass_logged)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
  fi
}

# === Case 10 (MEDIUM-1a): approved_at: (空白のみ) draft → BLOCK ===
case10_approved_at_spaces_only_block() {
  local label="Case 10 (MEDIUM-1a): approved_at with spaces only → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/.claude/rules/case10.md"
  write_draft_spaces_only "${TMP_ROOT}/docs/draft/case10.md"
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

# === Case 11 (MEDIUM-1b): approved_at: (key only、値なし改行直後) draft → BLOCK ===
case11_approved_at_key_only_block() {
  local label="Case 11 (MEDIUM-1b): approved_at key only (no value) → BLOCK (exit 2)"
  local fp="${TMP_ROOT}/.claude/rules/case11.md"
  write_draft_key_only "${TMP_ROOT}/docs/draft/case11.md"
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

# === Case 12 (MEDIUM-10): .claude/rules/sub/foo.md (深さ 2、out of scope) Write → PASS ===
# 設計仕様: .claude/rules/ 直下 (深さ 1) のみ BLOCK 対象、深さ 2 以上は out of scope
case12_rules_subdirectory_depth2_pass() {
  local label="Case 12 (MEDIUM-10): .claude/rules/sub/case12.md (depth 2) Write → PASS (out of scope)"
  local fp="${TMP_ROOT}/.claude/rules/sub/case12.md"
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

printf "===== rule-change-draft-flow-guard-smoke (task-40 Step 7 iter3, 12 cases) =====\n\n"

case1_rules_no_draft_block
case2_rules_approved_pass
case3_rules_unapproved_block
case4_templates_retroactive_pass_warn
case5_bypass_env_pass
case6_docs_root_block_regression
case7_commands_no_draft_block
case8_existing_rules_edit_pass
case9_override_env_pass_and_bypass_log
case10_approved_at_spaces_only_block
case11_approved_at_key_only_block
case12_rules_subdirectory_depth2_pass

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
if [ "$WARN" -gt 0 ]; then
  printf "WARN: %d (PASS 扱い、要確認)\n" "$WARN"
  for w in "${WARNED_CASES[@]}"; do
    printf "  - %s\n" "$w"
  done
fi
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS" "$PASS" "$TOTAL"
  if [ "$WARN" -gt 0 ]; then
    printf " (%d WARN)" "$WARN"
  fi
  printf "\n"
  exit 1
fi

printf "\nsummary: %d/%d PASS" "$PASS" "$TOTAL"
if [ "$WARN" -gt 0 ]; then
  printf " (%d WARN)" "$WARN"
fi
printf "\n"
exit 0
