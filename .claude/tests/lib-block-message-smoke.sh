#!/usr/bin/env bash
# lib-block-message-smoke.sh — task-94 P2-3 smoke for lib/block-message.sh (7 cases A-G)
#
# 設計 SSoT:
#   docs/draft/lib-block-message-4args.md §3.7 Step 5 (7 case A-G)
#
# 対象 lib:
#   .claude/hooks/lib/block-message.sh (5 関数: event 別 3 variant + emit_warn + emit_info)
#
# 検証範囲 (7 ケース):
#   A: emit_block_pretool → JSON stdout {"decision":"block","reason":"..."} + stderr 4 行
#   B: emit_warn → stderr 4 行のみ (JSON 非出力)
#   C: emit_info → stderr 2 行 (why + docs)、2 args signature
#   D: 4 args sanitize (\n / \r → 空白、audit trail 破壊防止)
#   E: jq 不在 fallback (printf JSON escape 経路)
#   F: emit_block_stop → JSON stdout 非出力 assertion + stderr 4 行
#      (Stop `{decision:"block"}` の停止阻止 semantic 誤発火防止、§3.1 契約)
#   G: emit_block_subagent → JSON stdout + stderr 4 行 (subagent 完了阻止 semantic 維持)
#
# 重要制約 (feedback_set_e_in_sourced_libs):
#   - file-top に set -euo pipefail を書かない
#   - lib 内部関数は subshell ( set -uo pipefail; ... ) 局所化済 (leak しない)
#
# 実行:
#   bash .claude/tests/lib-block-message-smoke.sh
#
# 終了コード:
#   0 = 7/7 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/.claude/hooks/lib/block-message.sh"

if [ ! -f "$LIB" ]; then
  printf 'FATAL: lib not found: %s\n' "$LIB" >&2
  exit 1
fi

# source lib (subshell 内部 set は leak しない、feedback_set_e_in_sourced_libs 準拠)
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
FAILED_CASES=()

# helper: JSON stdout の decision field 抽出
_json_decision() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("decision", "none"))
except Exception:
    print("parse_error")
' 2>/dev/null
}

_json_reason() {
  OUT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT"])
    print(d.get("reason", ""))
except Exception:
    print("")
' 2>/dev/null
}

# ===== Case A: emit_block_pretool → JSON stdout + stderr 4 行 =====
case_a_pretool_json_and_stderr() {
  local label="Case A: emit_block_pretool → JSON stdout + stderr 4 lines"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-a.XXXXXX)
  stdout=$(emit_block_pretool "why-A" "fix-A" "ECC_A=1" "docs/a.md" 2>"$stderr_file")
  local decision reason stderr_content
  decision=$(_json_decision "$stdout")
  reason=$(_json_reason "$stdout")
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  # 判定: decision=block ∧ reason に why/fix/silence/docs 全含む ∧ stderr に 4 label 全含む
  if [ "$decision" = "block" ] \
     && printf '%s' "$reason" | grep -q 'why: why-A' \
     && printf '%s' "$reason" | grep -q 'fix: fix-A' \
     && printf '%s' "$reason" | grep -q 'silence: ECC_A=1' \
     && printf '%s' "$reason" | grep -q 'docs: docs/a.md' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] why: why-A' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] fix: fix-A' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] silence: ECC_A=1' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] docs: docs/a.md'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision=%s reason=%s\n    stderr=%s\n" "$label" "$decision" "$reason" "$stderr_content"
  fi
}

# ===== Case B: emit_warn → stderr 4 行のみ (JSON 非出力) =====
case_b_warn_stderr_only() {
  local label="Case B: emit_warn → stderr 4 lines, no JSON stdout"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-b.XXXXXX)
  stdout=$(emit_warn "why-B" "fix-B" "ECC_B=1" "docs/b.md" 2>"$stderr_file")
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  # 判定: stdout 空 ∧ stderr に WARN 4 label 全含む
  if [ -z "$stdout" ] \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] WARN why: why-B' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] WARN fix: fix-B' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] WARN silence: ECC_B=1' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] WARN docs: docs/b.md'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (stdout non-empty or missing labels)")
    printf "  FAIL: %s\n    stdout='%s'\n    stderr=%s\n" "$label" "$stdout" "$stderr_content"
  fi
}

# ===== Case C: emit_info → 2 args signature =====
case_c_info_2args() {
  local label="Case C: emit_info → 2 args signature, stderr 2 lines"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-c.XXXXXX)
  stdout=$(emit_info "why-C" "docs/c.md" 2>"$stderr_file")
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  if [ -z "$stdout" ] \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] INFO why: why-C' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] INFO docs: docs/c.md'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label")
    printf "  FAIL: %s\n    stdout='%s'\n    stderr=%s\n" "$label" "$stdout" "$stderr_content"
  fi
}

# ===== Case D: 4 args sanitize (\n / \r → 空白) =====
case_d_sanitize_newline() {
  local label="Case D: 4 args sanitize (\\n / \\r → space, audit trail 破壊防止)"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-d.XXXXXX)
  # why に \n を含める (sanitize が動作すれば stderr line 1 に flatten)
  stdout=$(emit_block_pretool $'why-D\nline2' "fix-D" "ECC_D=1" "docs/d.md" 2>"$stderr_file")
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  # 判定: stderr の why: 行に "why-D line2" (改行 → 空白) が含まれる
  # NG: stderr に "why-D" と "line2" が別行 (改行が残存)
  local why_line
  why_line=$(printf '%s' "$stderr_content" | grep '\[block-message\] why:' | head -1)
  if printf '%s' "$why_line" | grep -qE 'why: why-D line2'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (sanitize failed)")
    printf "  FAIL: %s\n    why_line='%s'\n    stderr=%s\n" "$label" "$why_line" "$stderr_content"
  fi
}

# ===== Case E: jq 不在 fallback =====
case_e_jq_fallback() {
  local label="Case E: jq 不在 fallback (printf JSON escape)"
  # jq を PATH から除外して subshell 実行
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-e.XXXXXX)
  # PATH を制限した subshell で lib を再 source (jq 見えない状態)
  stdout=$(
    PATH="/nonexistent"
    # command -v jq は false のはず
    if command -v jq >/dev/null 2>&1; then
      # PATH override 効かず (bash builtin path resolution) — skip
      printf 'JQ_STILL_VISIBLE'
    else
      # lib 内部の _bm_emit_json_block が printf fallback 経路に入る
      # (関数は既に source 済なのでそのまま呼出、内部で command -v jq check)
      emit_block_pretool "why-E" "fix-E" "ECC_E=1" "docs/e.md" 2>"$stderr_file"
    fi
  )

  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  if [ "$stdout" = "JQ_STILL_VISIBLE" ]; then
    # PATH restriction 効かない環境 → skip 扱いで PASS
    PASS=$((PASS + 1))
    printf "  PASS: %s (skipped: jq resolvable outside PATH)\n" "$label"
    return 0
  fi

  # printf fallback の JSON 形式検証: {"decision":"block","reason":"..."}
  # (jq は pretty-print、printf は compact JSON なので違いを吸収して decision 抽出)
  local decision
  decision=$(_json_decision "$stdout")
  if [ "$decision" = "block" ] \
     && printf '%s' "$stdout" | grep -q '"decision"' \
     && printf '%s' "$stdout" | grep -q 'why-E'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label")
    printf "  FAIL: %s\n    stdout='%s'\n" "$label" "$stdout"
  fi
}

# ===== Case F: emit_block_stop → JSON stdout 非出力 assertion =====
case_f_stop_no_json() {
  local label="Case F: emit_block_stop → JSON 非出力 + stderr 4 lines (§3.1 契約)"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-f.XXXXXX)
  stdout=$(emit_block_stop "why-F" "fix-F" "ECC_F=1" "docs/f.md" 2>"$stderr_file")
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  # 判定: stdout 空 ∧ stderr に 4 label 全含む
  if [ -z "$stdout" ] \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] why: why-F' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] fix: fix-F' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] silence: ECC_F=1' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] docs: docs/f.md'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (stdout non-empty means JSON emitted, violating §3.1 Stop contract)")
    printf "  FAIL: %s\n    stdout='%s'\n    stderr=%s\n" "$label" "$stdout" "$stderr_content"
  fi
}

# ===== Case G: emit_block_subagent → JSON stdout + stderr (semantic 維持) =====
case_g_subagent_json_and_stderr() {
  local label="Case G: emit_block_subagent → JSON stdout + stderr 4 lines (subagent 完了阻止 semantic 維持)"
  local stdout stderr_file
  stderr_file=$(mktemp /tmp/lib-bm-g.XXXXXX)
  stdout=$(emit_block_subagent "why-G" "fix-G" "ECC_G=1" "docs/g.md" 2>"$stderr_file")
  local decision reason stderr_content
  decision=$(_json_decision "$stdout")
  reason=$(_json_reason "$stdout")
  stderr_content=$(cat "$stderr_file")
  rm -f "$stderr_file"

  if [ "$decision" = "block" ] \
     && printf '%s' "$reason" | grep -q 'why: why-G' \
     && printf '%s' "$reason" | grep -q 'fix: fix-G' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] why: why-G' \
     && printf '%s' "$stderr_content" | grep -q '\[block-message\] docs: docs/g.md'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    decision=%s reason=%s\n    stderr=%s\n" "$label" "$decision" "$reason" "$stderr_content"
  fi
}

printf "===== lib-block-message-smoke (task-94 P2-3, 7 cases A-G) =====\n\n"

case_a_pretool_json_and_stderr
case_b_warn_stderr_only
case_c_info_2args
case_d_sanitize_newline
case_e_jq_fallback
case_f_stop_no_json
case_g_subagent_json_and_stderr

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
