#!/usr/bin/env bash
# .claude/tests/loop-confirmation-detector-smoke.sh — task-41 Step 4 smoke
#
# 設計起源:
#   docs/draft/loop-confirmation-detector-hook.md §4 TDD 戦略
#
# 対象 hook:
#   .claude/hooks/loop-confirmation-detector.sh (Stop hook)
#
# 検証範囲 (8 ケース):
#   Case 1: Loop モード、AI message に「進めてよいですか」→ additionalContext 注入確認
#   Case 2: Loop モード、AI message に「OK ですか」→ additionalContext 注入確認
#   Case 3: Loop モード、AI message に「次の指示をお待ちします」→ additionalContext 注入確認
#   Case 4: Normal モード、AI message に「進めてよいですか」→ silent pass (additionalContext 不在)
#   Case 5: Loop モード、AI message に確認質問なし ("task 完遂しました") → silent pass
#   Case 6: bypass env HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false → silent pass
#   Case 7: bypass env ECC_LOOP_CONFIRMATION_OFF=1 → silent pass + bypass.log 記録確認
#   Case 8: pattern override HC_LOOP_CONFIRMATION_PATTERNS="custom" + AI message に "custom" → 注入確認
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - mock transcript file は tmp dir に作成 (cleanup trap)
#   - CLAUDE_PROJECT_DIR="$TMP_ROOT" で hook 環境を isolate
#   - mode は .claude/mode.yml を tmp dir 内に作成して制御 (loop / normal)
#
# 実行:
#   bash .claude/tests/loop-confirmation-detector-smoke.sh
#
# 終了コード:
#   0 = 全 PASS (WARN あり含む) / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/loop-confirmation-detector.sh"

# clean env
unset HC_LOOP_CONFIRMATION_DETECTION_ENABLED
unset ECC_LOOP_CONFIRMATION_OFF
unset HC_LOOP_CONFIRMATION_PATTERNS
unset HC_MODE

# tmp project root を /tmp/ に作成して独立ツリーを配置
TMP_ROOT="$(mktemp -d /tmp/loop-confirmation-detector-smoke.XXXXXX)"
mkdir -p \
  "${TMP_ROOT}/.git" \
  "${TMP_ROOT}/.claude/hooks/lib" \
  "${TMP_ROOT}/.claude/.workflow-state"

# real hooks/lib を symlink (mode-loader.sh / config-loader.sh / bypass-logger.sh に依存)
if [ -d "${REPO_ROOT}/.claude/hooks/lib" ]; then
  rm -rf "${TMP_ROOT}/.claude/hooks/lib"
  ln -s "${REPO_ROOT}/.claude/hooks/lib" "${TMP_ROOT}/.claude/hooks/lib"
fi
if [ -f "${REPO_ROOT}/.claude/harness-config.yml" ]; then
  ln -s "${REPO_ROOT}/.claude/harness-config.yml" "${TMP_ROOT}/.claude/harness-config.yml"
fi

# .claude/mode.yml backup & restore on exit
MODE_FILE="${REPO_ROOT}/.claude/mode.yml"
MODE_BACKUP="${TMP_ROOT}/mode.yml.bak"
if [ -f "$MODE_FILE" ]; then
  cp "$MODE_FILE" "$MODE_BACKUP"
fi

_cleanup() {
  if [ -f "$MODE_BACKUP" ]; then
    cp "$MODE_BACKUP" "$MODE_FILE"
  fi
  rm -rf "$TMP_ROOT"
}
trap _cleanup EXIT

PASS=0
FAIL=0
WARN=0
FAILED_CASES=()
WARNED_CASES=()

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

# mode.yml を一時的に書き換え
# $1 = "loop" | "normal"
_set_mode() {
  local m="$1"
  cat > "$MODE_FILE" <<EOF
mode: ${m}
asana_enabled: false
EOF
}

# transcript JSONL を tmp に作成 (最終 assistant message のみ)
# $1 = output path
# $2 = AI text content
_make_transcript() {
  local out="$1"
  local txt="$2"
  SMOKE_TEXT="$txt" python3 -c '
import json, os
text = os.environ["SMOKE_TEXT"]
rec = {
    "type": "assistant",
    "message": {
        "role": "assistant",
        "content": [{"type": "text", "text": text}]
    },
    "uuid": "smoke-a1"
}
print(json.dumps(rec))
' > "$out"
}

# Stop hook 用の JSON payload を生成
# $1 = transcript path (必要なければ空文字でも可)
_hook_input() {
  local tp="$1"
  SMOKE_TP="$tp" python3 -c '
import json, os
tp = os.environ.get("SMOKE_TP", "")
payload = {"session_id": "smoke", "stop_hook_active": True}
if tp:
    payload["transcript_path"] = tp
print(json.dumps(payload))
'
}

# hook を実行
# $1 = transcript path (空文字可)
# $2... = 追加環境変数 KEY=VAL
_run_hook() {
  local tp="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$TMP_ROOT" \
    "$@" \
    bash "$HOOK" \
    <<< "$(_hook_input "$tp")" \
    > "$out_file" \
    2> "$err_file"
  LAST_CODE=$?
  LAST_OUT=$(cat "$out_file")
  LAST_ERR=$(cat "$err_file")
  rm -f "$out_file" "$err_file"
}

# additionalContext が stdout JSON に含まれるか確認
_has_additional_context() {
  local out="$1"
  if printf '%s' "$out" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
    val = d.get("hookSpecificOutput", {}).get("additionalContext", "")
    sys.exit(0 if val else 1)
except Exception:
    sys.exit(1)
' 2>/dev/null; then
    return 0
  fi
  return 1
}

_record_pass() {
  local label="$1"
  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

_record_fail() {
  local label="$1"
  local detail="$2"
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("${label} (${detail})")
  printf "  FAIL: %s (%s)\n" "$label" "$detail"
}

# --------------------------------------------------------------------------
# Case 1: Loop モード、「進めてよいですか」→ additionalContext 注入
# --------------------------------------------------------------------------
case1_loop_shimete_yoidesuka_inject() {
  local label="Case 1: Loop + '進めてもいいですか' → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case1.jsonl"
  _make_transcript "$tp" "実装完了しました。進めてもいいですか？"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 2: Loop モード、「OK ですか」→ additionalContext 注入
# --------------------------------------------------------------------------
case2_loop_ok_desuka_inject() {
  local label="Case 2: Loop + 'OK ですか' → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case2.jsonl"
  _make_transcript "$tp" "次のステップに進みます。OK ですか？"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 3: Loop モード、「次の指示をお待ちします」→ additionalContext 注入
# --------------------------------------------------------------------------
case3_loop_machi_shimasu_inject() {
  local label="Case 3: Loop + '次の指示をお待ちします' → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case3.jsonl"
  _make_transcript "$tp" "hook の実装が完了しました。次の指示をお待ちします。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 4: Normal モード、「進めてよいですか」→ silent pass (additionalContext 不在)
# --------------------------------------------------------------------------
case4_normal_mode_no_inject() {
  local label="Case 4: Normal + '進めてもいいですか' → silent pass (additionalContext 不在)"
  _set_mode "normal"
  local tp="${TMP_ROOT}/case4.jsonl"
  _make_transcript "$tp" "実装完了しました。進めてもいいですか？"

  _run_hook "$tp"

  # Normal モードでは additionalContext なし、かつ exit 0
  if [ "$LAST_CODE" -eq 0 ] && ! _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0)"
  fi
}

# --------------------------------------------------------------------------
# Case 5: Loop モード、確認質問なし ("task 完遂しました") → silent pass
# --------------------------------------------------------------------------
case5_loop_no_question_silent() {
  local label="Case 5: Loop + 確認質問なし ('task 完遂しました') → silent pass"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case5.jsonl"
  _make_transcript "$tp" "task 完遂しました。全テスト PASS、confidence: 0.9"

  _run_hook "$tp"

  # 確認質問なし → additionalContext 不在
  if [ "$LAST_CODE" -eq 0 ] && ! _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0)"
  fi
}

# --------------------------------------------------------------------------
# Case 6: HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false → silent pass
# --------------------------------------------------------------------------
case6_config_disabled_silent() {
  local label="Case 6: HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false → silent pass"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case6.jsonl"
  _make_transcript "$tp" "進めてよいですか？よろしいですか？"

  _run_hook "$tp" HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false

  # bypass → additionalContext 不在
  if [ "$LAST_CODE" -eq 0 ] && ! _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0)"
  fi
}

# --------------------------------------------------------------------------
# Case 7: ECC_LOOP_CONFIRMATION_OFF=1 → silent pass + bypass.log 記録
# --------------------------------------------------------------------------
case7_ecc_off_bypass_log() {
  local label="Case 7: ECC_LOOP_CONFIRMATION_OFF=1 → silent pass + bypass.log 記録"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case7.jsonl"
  _make_transcript "$tp" "OK ですか？どちらにしますか？"

  local bypass_log="${TMP_ROOT}/.claude/.workflow-state/bypass.log"
  rm -f "$bypass_log"

  _run_hook "$tp" \
    ECC_LOOP_CONFIRMATION_OFF=1 \
    ECC_BYPASS_REASON="smoke test bypass" \
    CLAUDE_SESSION_ID="smoke-c7"

  # bypass.log に ECC_LOOP_CONFIRMATION_OFF が記録されているか確認
  local bypass_logged=0
  if [ -f "$bypass_log" ] && grep -q "ECC_LOOP_CONFIRMATION_OFF" "$bypass_log" 2>/dev/null; then
    bypass_logged=1
  fi

  if [ "$LAST_CODE" -eq 0 ] && ! _has_additional_context "$LAST_OUT" && [ "$bypass_logged" -eq 1 ]; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) bypass_logged=${bypass_logged}"
  fi
}

# --------------------------------------------------------------------------
# Case 8: HC_LOOP_CONFIRMATION_PATTERNS override → custom パターンで注入確認
# --------------------------------------------------------------------------
case8_pattern_override_inject() {
  local label="Case 8: HC_LOOP_CONFIRMATION_PATTERNS='custom' override → 'custom' 検出で注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case8.jsonl"
  _make_transcript "$tp" "処理が完了しました。custom な確認が必要かもしれません。"

  _run_hook "$tp" \
    "HC_LOOP_CONFIRMATION_PATTERNS=custom"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# run all cases
# --------------------------------------------------------------------------
printf "===== loop-confirmation-detector-smoke (task-41 Step 4, 8 cases) =====\n\n"

case1_loop_shimete_yoidesuka_inject
case2_loop_ok_desuka_inject
case3_loop_machi_shimasu_inject
case4_normal_mode_no_inject
case5_loop_no_question_silent
case6_config_disabled_silent
case7_ecc_off_bypass_log
case8_pattern_override_inject

# --------------------------------------------------------------------------
# result summary
# --------------------------------------------------------------------------
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
