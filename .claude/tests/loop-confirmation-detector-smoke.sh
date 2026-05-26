#!/usr/bin/env bash
# .claude/tests/loop-confirmation-detector-smoke.sh — task-41 Step 6 iter3 + 2026-05-27 拡張
#
# 設計起源:
#   docs/draft/loop-confirmation-detector-hook.md §4 TDD 戦略
#   2026-05-27 拡張: 自主ターン区切り keyword 6 件追加 (user 直接指示
#     「続行可能なのに勝手に止まらないようにハーネス側で修正」)
#
# 対象 hook:
#   .claude/hooks/loop-confirmation-detector.sh (Stop hook)
#
# 検証範囲 (18 ケース、既存 12 + 新 6):
#   Case 1: Loop モード、AI message に「進めてよいですか」→ additionalContext 注入確認
#   Case 2: Loop モード、AI message に「OK ですか」→ additionalContext 注入確認
#   Case 3: Loop モード、AI message に「次の指示をお待ちします」→ additionalContext 注入確認
#   Case 4: Normal モード、AI message に「進めてよいですか」→ silent pass (additionalContext 不在)
#   Case 5: Loop モード、AI message に確認質問なし ("task 完遂しました") → silent pass
#   Case 6: bypass env HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false → silent pass
#   Case 7: bypass env ECC_LOOP_CONFIRMATION_OFF=1 → silent pass + bypass.log 記録確認
#   Case 8: pattern override HC_LOOP_CONFIRMATION_PATTERNS="custom" + AI message に "custom" → 注入確認
#   Case 9: Loop モード、AI message に「お待ちしています」(Pattern 7 単独) → 注入確認
#   Case 10: Loop モード、AI message に「進めてよいですか」(Pattern 1 短形) → 注入確認
#   Case 11: HC_LOOP_CONFIRMATION_PATTERNS=$'\n' (空行のみ) → default fallback → 確認質問検出 → 注入確認
#   Case 12: jq 不在環境 → fail-open (exit 0、additionalContext 不在)
#   Case 13: Loop + 「本 turn 完遂」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#   Case 14: Loop + 「ターン区切り」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#   Case 15: Loop + 「次 turn で Step 2 着手予定」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#   Case 16: Loop + 「次回 fresh prompt」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#   Case 17: Loop + 「context budget 警戒」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#   Case 18: Loop + 「ここで一旦」 → 新 keyword で additionalContext 注入 (2026-05-27 拡張)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - mock transcript file は tmp dir に作成 (cleanup trap)
#   - CLAUDE_PROJECT_DIR="$TMP_ROOT" で hook 環境を isolate
#   - mode は .claude/mode.yml を tmp dir 内に作成して制御 (loop / normal)
#   - env -i PATH 固定化 (SAFE_PATH) で呼び出し元 PATH injection を防止 (iter3 sec-M5 fix)
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

# hook を実行 (iter3 sec-M5 fix: SAFE_PATH 固定で injection 防止)
# $1 = transcript path (空文字可)
# $2... = 追加環境変数 KEY=VAL
_run_hook() {
  local tp="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  # SAFE_PATH 固定 (呼び出し元 PATH 継承を回避、PATH injection を構造的に防止)
  local SAFE_PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"

  env -i \
    PATH="$SAFE_PATH" \
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

# hook を jq 不在 PATH で実行 (Case 12 用)
# $1 = transcript path (空文字可)
_run_hook_no_jq() {
  local tp="$1"
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  # jq が通常インストールされる場所 (/opt/homebrew/bin, /usr/local/bin) を除いた PATH を構築
  local stripped_path
  stripped_path=$(printf '%s' "$PATH" | tr ':' '\n' \
    | grep -v '/opt/homebrew/bin' \
    | grep -v '/usr/local/bin' \
    | grep -v '/home/linuxbrew/.linuxbrew/bin' \
    | tr '\n' ':' \
    | sed 's/:$//')

  env -i \
    PATH="$stripped_path" \
    HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$TMP_ROOT" \
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
# Case 9: Loop モード、「お待ちしています」(Pattern 7 単独 hit) → additionalContext 注入
# HIGH-1: Pattern 7 が BSD grep -P 非対応環境でも動作することを確認。
# hook は grep -E を使用しており、Pattern 7 は 'お待ちし(て)?(い|お)?ます' (POSIX ERE)。
# 「お待ちしています」は Pattern 6「次の指示をお待ちします」とは別 hit。
# --------------------------------------------------------------------------
case9_pattern7_alone() {
  local label="Case 9: Loop + 'お待ちしています' (Pattern 7 単独) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case9.jsonl"
  # Pattern 6「次の指示をお待ちします」は含まない、Pattern 7「お待ちし(て)?(い|お)?ます」のみ
  _make_transcript "$tp" "全件確認しました。お待ちしています。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 10: Loop モード、「進めてよいですか」(Pattern 1 短形) → additionalContext 注入
# HIGH-2: iter1 reviewer 指摘「進めてよいですか が Pattern 1 regex で未検出の可能性」を確認。
# Pattern 1: '進めて((も)?よろ|よ|も)?(し)?い(い)?(ですか|でしょうか)'
# 「進めてよいですか」は「進めて + よ + い + ですか」で Pattern 1 に該当する。
# --------------------------------------------------------------------------
case10_pattern1_susumete_yoi() {
  local label="Case 10: Loop + '進めてよいですか' (Pattern 1 短形) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case10.jsonl"
  _make_transcript "$tp" "次のフェーズに進めてよいですか？"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 11: HC_LOOP_CONFIRMATION_PATTERNS=$'\n' (空行のみ) → default fallback → 注入確認
# HIGH-3 + iter2 sec-H1 fix: pattern 全無効化 edge case の動作確認。
#
# hook iter2 fix の動作:
#   PATTERNS="${HC_LOOP_CONFIRMATION_PATTERNS:-}"  # 改行のみの値は ":-" 展開で fallback しない
#   if ! printf '%s' "$PATTERNS" | grep -qE '[^[:space:]]'; then  # whitespace-only 判定で default 復元
#     PATTERNS="$DEFAULT_PATTERNS"
#   fi
#
# 期待動作: HC_LOOP_CONFIRMATION_PATTERNS が改行 / whitespace のみなら default に fallback、
# AI message に default pattern (例「進めてもいいですか」) が含まれれば確認質問検出 → 注入。
# --------------------------------------------------------------------------
case11_pattern_empty_fallback_to_default() {
  local label="Case 11: HC_LOOP_CONFIRMATION_PATTERNS=\$'\n' → default fallback → 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case11.jsonl"
  # デフォルト pattern にマッチする text を使用
  _make_transcript "$tp" "次のフェーズに進めてもいいですか？"

  # 空行のみ (改行文字のみの値) を設定 — hook iter2 fix で default 復元される
  # 注: double-quote 内で $'\n' は ANSI-C quoting 展開されない (literal 文字列扱い)
  # local NL=$'\n' で改行文字に展開してから env arg に埋め込む必要がある
  local NL=$'\n'
  _run_hook "$tp" \
    "HC_LOOP_CONFIRMATION_PATTERNS=${NL}"

  # hook iter2 fix の挙動: default fallback → 確認質問検出 → additionalContext 注入
  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) (expected default fallback should detect 進めてもいいですか)"
  fi
}

# --------------------------------------------------------------------------
# Case 12: jq 不在環境 → fail-open (exit 0、additionalContext 不在)
# MEDIUM: hook L99「if ! command -v jq; then exit 0; fi」の fail-open 動作確認。
# _run_hook_no_jq() で /opt/homebrew/bin と /usr/local/bin を除いた PATH を使用。
# macOS では jq は homebrew か /usr/local/bin にあることが多い。
# もし system PATH (例 /usr/bin) に jq が存在する場合は WARN として処理。
# --------------------------------------------------------------------------
case12_jq_missing_fail_open() {
  local label="Case 12: jq 不在 PATH → fail-open (exit 0、additionalContext 不在)"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case12.jsonl"
  _make_transcript "$tp" "進めてもいいですか？"

  _run_hook_no_jq "$tp"

  if [ "$LAST_CODE" -eq 0 ] && ! _has_additional_context "$LAST_OUT"; then
    # jq が stripped PATH に存在しない場合: fail-open で exit 0 + 注入なし → PASS
    _record_pass "$label"
  elif [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    # jq が /usr/bin 等 stripped 後も残る PATH に存在した場合: 通常動作で注入 → WARN (環境依存)
    WARN=$((WARN + 1))
    WARNED_CASES+=("${label} (jq が stripped PATH に残存、環境依存 WARN)")
    printf "  WARN: %s (jq が stripped PATH に残存、jq 不在テスト無効、環境依存)\n" "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} (expected 0/fail-open)"
  fi
}

# --------------------------------------------------------------------------
# Case 13 (2026-05-27 拡張): Loop モード、「本 turn 完遂」→ 新 keyword で注入
# 起源: 2026-05-27 user 提示 transcript「本 turn 完遂: ...」予防的自主停止
# --------------------------------------------------------------------------
case13_loop_honturn_kanzui_inject() {
  local label="Case 13: Loop + '本 turn 完遂' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case13.jsonl"
  _make_transcript "$tp" "本 turn 完遂: hook 実装 + smoke PASS。次 turn 開始時に Step 2 を予定。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 14 (2026-05-27 拡張): Loop モード、「ターン区切り」→ 新 keyword で注入
# 起源: 2026-05-27 user 提示 transcript「context budget 警戒のため本 turn ターン区切り」
# --------------------------------------------------------------------------
case14_loop_turn_kugiri_inject() {
  local label="Case 14: Loop + 'ターン区切り' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case14.jsonl"
  _make_transcript "$tp" "本 task 主要部完了のためここで一区切り。ターン区切りとし新 session で継続。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 15 (2026-05-27 拡張): Loop モード、「次 turn で Step 2 着手予定」→ 新 keyword で注入
# 起源: 2026-05-27 user 提示 transcript「次 turn で Step 2 着手予定」予防的自主停止
# --------------------------------------------------------------------------
case15_loop_next_turn_chakushu_inject() {
  local label="Case 15: Loop + '次 turn で Step 2 着手' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case15.jsonl"
  _make_transcript "$tp" "Step 1 完了。次 turn で Step 2 着手予定。本 session ここで停止。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 16 (2026-05-27 拡張): Loop モード、「次回 fresh prompt」→ 新 keyword で注入
# 起源: 2026-05-27 user 提示 transcript「次回 fresh prompt で...」予防的自主停止
# --------------------------------------------------------------------------
case16_loop_fresh_prompt_inject() {
  local label="Case 16: Loop + '次回 fresh prompt' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case16.jsonl"
  _make_transcript "$tp" "本 turn 主要 work 完了。次回 fresh prompt で残り作業を進めます。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 17 (2026-05-27 拡張): Loop モード、「context budget 警戒」→ 新 keyword で注入
# 起源: 2026-05-27 user 提示 transcript「context budget 警戒のため本 turn ターン区切り」
# --------------------------------------------------------------------------
case17_loop_context_budget_keikai_inject() {
  local label="Case 17: Loop + 'context budget 警戒' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case17.jsonl"
  # tier 警告未発火下での予防的自主停止 keyword
  _make_transcript "$tp" "context budget 警戒のため一旦停止します。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# Case 18 (2026-05-27 拡張): Loop モード、「ここで一旦」→ 新 keyword で注入
# 起源: 2026-05-27 自主ターン区切り発話の代表 phrase
# --------------------------------------------------------------------------
case18_loop_kokode_ittan_inject() {
  local label="Case 18: Loop + 'ここで一旦' (新 keyword) → additionalContext 注入"
  _set_mode "loop"
  local tp="${TMP_ROOT}/case18.jsonl"
  _make_transcript "$tp" "Step 完了報告。ここで一旦停止します。"

  _run_hook "$tp"

  if [ "$LAST_CODE" -eq 0 ] && _has_additional_context "$LAST_OUT"; then
    _record_pass "$label"
  else
    _record_fail "$label" "rc=${LAST_CODE} has_ctx=$(_has_additional_context "$LAST_OUT" && echo 1 || echo 0) out=$(printf '%s' "$LAST_OUT" | head -c 80)"
  fi
}

# --------------------------------------------------------------------------
# run all cases
# --------------------------------------------------------------------------
printf "===== loop-confirmation-detector-smoke (task-41 + 2026-05-27 拡張, 18 cases) =====\n\n"

case1_loop_shimete_yoidesuka_inject
case2_loop_ok_desuka_inject
case3_loop_machi_shimasu_inject
case4_normal_mode_no_inject
case5_loop_no_question_silent
case6_config_disabled_silent
case7_ecc_off_bypass_log
case8_pattern_override_inject
case9_pattern7_alone
case10_pattern1_susumete_yoi
case11_pattern_empty_fallback_to_default
case12_jq_missing_fail_open
case13_loop_honturn_kanzui_inject
case14_loop_turn_kugiri_inject
case15_loop_next_turn_chakushu_inject
case16_loop_fresh_prompt_inject
case17_loop_context_budget_keikai_inject
case18_loop_kokode_ittan_inject

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
