#!/usr/bin/env bash
# delegation-guard-code-smoke.sh — task-26 W3 smoke for code-protection (W2 拡張) 検証
#
# 設計起源:
#   docs/draft/delegation-code-enforcement.md W2+W3
#   2026-05-23 user 指摘「なぜ基本原則に従ってサブエージェントに移譲しないのですか?」
#
# 対象 hook:
#   .claude/hooks/delegation-guard.sh の "task-26 W2: コード実装の保護パス" ブロック
#   (Edit|Write 分岐内、protected_paths block 直後)
#
# 検証範囲 (7 ケース):
#   Case 1: メイン .claude/hooks/foo.sh Write → block (sh 拡張子 + hooks 配下)
#   Case 2: メイン .claude/skills/foo/bar.py Write → block (py 拡張子 + skills 配下)
#   Case 3: メイン .claude/scripts/baz.mjs Write → block (mjs 拡張子 + scripts 配下)
#   Case 4: subagent (CLAUDE_HARNESS_ROLE=subagent) .claude/hooks/foo.sh Write → pass
#   Case 5: メイン .claude/rules/foo.md Write → pass (.md 拡張子対象外)
#   Case 6: メイン .claude/harness-config.yml Edit → pass (.yml 拡張子対象外)
#   Case 7: bypass env ECC_ALLOW_MAIN_CODE_EDIT=1 メイン .claude/hooks/foo.sh Write → pass + bypass.log 記録
#
# 重要制約:
#   - file-top に `set -euo pipefail` を書かない (caller leak 防止教訓
#     `feedback_set_e_in_sourced_libs`)
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE / ECC_ALLOW_MAIN_CODE_EDIT を unset
#   - marker dir に lock を作らない (clean main agent context で起動)
#
# 実行:
#   bash .claude/tests/delegation-guard-code-smoke.sh
#
# 終了コード:
#   0 = 7/7 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/delegation-guard.sh"

# clean main agent context を確保
unset CLAUDE_HARNESS_ROLE
unset ECC_ALLOW_MAIN_CODE_EDIT

PASS=0
FAIL=0
FAILED_CASES=()

# tool_input.file_path を含む PreToolUse JSON を python3 で安全に組み立てる
json_input() {
  local fp="$1"
  FP="$fp" python3 -c '
import json, os
print(json.dumps({"tool_input": {"file_path": os.environ["FP"]}}))
'
}

# stdout から decision を抽出
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

# stdout から reason を抽出 (block 確認用)
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

# stdout に code 保護 bypass context が含まれるか確認
contains_bypass_context() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    ctx = d.get("hookSpecificOutput", {}).get("additionalContext", "")
    print("yes" if "code 保護 bypass" in ctx else "no")
except Exception:
    print("no")
' 2>/dev/null
}

# block 期待: decision="block"
# reason 内訳:
#   - "code 保護" → W2 code-protection 由来 (期待される正経路)
#   - "サブエージェント委譲ルール" + "src/ tests/ scripts/" → 既存 protected_paths が先に発火
#     (例: .claude/scripts/baz.mjs は path に "scripts" を含むため既存 protected_paths でも match。
#      どちらでも「メイン編集を block」という規範的目的は達成されているので両方を許容)
# 引数:
#   $5 = expected_reason_type ("code" or "any") — "code" は code 保護必須、
#        "any" は code 保護 / 既存 protected_paths のいずれでも OK
expect_block_code() {
  local label="$1"
  local tool="$2"
  local fp="$3"
  local extra_env="${4:-}"
  local expected_type="${5:-code}"
  local out decision reason

  if [ -n "$extra_env" ]; then
    out=$(json_input "$fp" | env $extra_env bash "$HOOK" "$tool" 2>&1)
  else
    out=$(json_input "$fp" | bash "$HOOK" "$tool" 2>&1)
  fi
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  local reason_ok="false"
  if [ "$expected_type" = "code" ]; then
    if printf '%s' "$reason" | grep -q 'code 保護'; then
      reason_ok="true"
    fi
  else
    # "any": code 保護 / 既存 protected_paths のいずれでも OK
    if printf '%s' "$reason" | grep -qE 'code 保護|サブエージェント委譲ルール'; then
      reason_ok="true"
    fi
  fi

  if [ "$decision" = "block" ] && [ "$reason_ok" = "true" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision reason_ok=$reason_ok)")
    printf "  FAIL: %s\n    fp: %s\n    decision: %s\n    out: %s\n" "$label" "$fp" "$decision" "$out"
  fi
}

# pass 期待: decision != "block"
expect_pass() {
  local label="$1"
  local tool="$2"
  local fp="$3"
  local extra_env="${4:-}"
  local out decision

  if [ -n "$extra_env" ]; then
    out=$(json_input "$fp" | env $extra_env bash "$HOOK" "$tool" 2>&1)
  else
    out=$(json_input "$fp" | bash "$HOOK" "$tool" 2>&1)
  fi
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    fp: %s\n    out: %s\n" "$label" "$fp" "$out"
  fi
}

# bypass pass 期待: decision != "block" + additionalContext に "code 保護 bypass" + bypass.log に entry 追加
expect_bypass_pass() {
  local label="$1"
  local tool="$2"
  local fp="$3"
  local log_file="$REPO_ROOT/.claude/.workflow-state/bypass.log"
  local log_before_lines=0
  if [ -f "$log_file" ]; then
    log_before_lines=$(wc -l < "$log_file" | tr -d ' ')
  fi

  local out decision ctx_present
  out=$(json_input "$fp" | ECC_ALLOW_MAIN_CODE_EDIT=1 bash "$HOOK" "$tool" 2>&1)
  decision=$(extract_decision "$out")
  ctx_present=$(contains_bypass_context "$out")

  local log_after_lines=0
  if [ -f "$log_file" ]; then
    log_after_lines=$(wc -l < "$log_file" | tr -d ' ')
  fi
  local log_delta=$((log_after_lines - log_before_lines))

  # 条件: decision != block, ctx_present == yes, log_delta >= 1
  if [ "$decision" != "block" ] && [ "$ctx_present" = "yes" ] && [ "$log_delta" -ge 1 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s (log_delta=%d)\n" "$label" "$log_delta"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision ctx=$ctx_present log_delta=$log_delta)")
    printf "  FAIL: %s\n    fp: %s\n    decision: %s\n    ctx: %s\n    log_delta: %d\n    out: %s\n" \
      "$label" "$fp" "$decision" "$ctx_present" "$log_delta" "$out"
  fi
}

printf "===== delegation-guard-code-smoke (task-26 W3, 7 cases) =====\n\n"

# Case 1-3: メインからの code 編集 → block
printf "Block cases (3, main agent, code-extension under protected_paths_code):\n"
expect_block_code "Case 1: main Write .claude/hooks/foo.sh" \
  "Write" "$REPO_ROOT/.claude/hooks/foo.sh"
expect_block_code "Case 2: main Write .claude/skills/foo/bar.py" \
  "Write" "$REPO_ROOT/.claude/skills/foo/bar.py"
# Case 3: .claude/scripts/ は path に "scripts" を含むため既存 protected_paths も match。
# どちらの経路で block されても「メイン直接編集を block」という規範的目的は達成。
expect_block_code "Case 3: main Write .claude/scripts/baz.mjs" \
  "Write" "$REPO_ROOT/.claude/scripts/baz.mjs" "" "any"

# Case 4: subagent → pass
printf "\nSubagent context pass (1):\n"
expect_pass "Case 4: subagent Write .claude/hooks/foo.sh" \
  "Write" "$REPO_ROOT/.claude/hooks/foo.sh" "CLAUDE_HARNESS_ROLE=subagent"

# Case 5-6: 拡張子対象外 → pass
printf "\nNon-code extension pass (2):\n"
expect_pass "Case 5: main Write .claude/rules/foo.md (.md)" \
  "Write" "$REPO_ROOT/.claude/rules/foo.md"
expect_pass "Case 6: main Edit .claude/harness-config.yml (.yml)" \
  "Edit" "$REPO_ROOT/.claude/harness-config.yml"

# Case 7: bypass env → pass + log 記録
printf "\nBypass pass (1, ECC_ALLOW_MAIN_CODE_EDIT=1):\n"
expect_bypass_pass "Case 7: bypass main Write .claude/hooks/foo.sh" \
  "Write" "$REPO_ROOT/.claude/hooks/foo.sh"

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
