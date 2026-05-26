#!/usr/bin/env bash
# loop-confirmation-detector.sh — Stop hook
#
# 役割:
#   Loop モード稼働中、AI 最終 assistant message に「確認質問パターン」
#   (例: 「進めてよいですか?」「OK ですか?」「お待ちします」) または
#   「予防的自主ターン区切りパターン」(例: 「本 turn 完遂」「ターン区切り」
#   「次 turn で <X> 着手」「次回 fresh prompt」「context budget 警戒」
#   「ここで一旦」) が含まれていた場合、
#   top-level `{"decision":"block","reason":"..."}` を出力して AI を停止させず
#   次 turn に warn context を注入する。
#   「Loop モード遵守事項 2 (中間確認の停止) / 遵守事項 9 (list.md 全 task 連続自律実行)
#   違反 → 自律実行に切替えよ」と是正を促す。
#   Normal モードでは no-op。
#
# 設計起源:
#   docs/draft/loop-confirmation-detector-hook.md (frontmatter retroactive: true,
#   approved_by: user, 2026-05-26)
#   task-41 Step 2
#   2026-05-27 拡張: 自主ターン区切り keyword 6 件追加 + warn_message に遵守事項 9 言及
#     (user 直接指示「続行可能なのに勝手に止まらないようにハーネス側で修正」)
#   2026-05-27 hot fix: Stop hook JSON output schema 違反修正
#     (hookSpecificOutput.additionalContext → top-level decision/reason)
#
# 発火 timing:
#   Stop hook (AI 最終 assistant message 完了時、PostToolUse の後段)
#
# 動作概要:
#   1. mode-loader.sh で current mode 取得、Loop モード以外は早期 exit 0
#   2. bypass env 判定 (ECC_LOOP_CONFIRMATION_OFF=1 / HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false)
#   3. stdin JSON から transcript_path を抽出 (jq 不在で fail-open)
#   4. transcript 末尾から最後の assistant text を抽出
#   5. 確認質問 regex + 自主ターン区切り regex
#      (default 19 パターン or HC_LOOP_CONFIRMATION_PATTERNS で override)
#      に対し grep -E で照合
#   6. 検出時:
#      - bypass.log に VIOLATION 記録
#      - stdout に JSON `{"decision":"block","reason":"..."}` を出力
#   7. 検出なしなら silent exit 0
#
# 環境変数:
#   ECC_LOOP_CONFIRMATION_OFF=1                       ... 一時 OFF (1 セッション)
#   HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false      ... config レベル無効化
#   HC_LOOP_CONFIRMATION_PATTERNS=<改行区切り>        ... regex 上書き
#                                                       (空 / whitespace のみは無視し default に戻す)
#
# 失敗時の挙動:
#   - exit 0 のみ (fail-open)。block しない (decision:block で AI を停止させず reason 注入)。
#     Stop hook の `decision:"block"` は「停止させない (AI が続行)」意味、通常の
#     PreToolUse block と意味反転している点に注意。
#   - jq 不在 / transcript 不在 / parse 失敗 → silent skip。
#
# bash flags の方針 (重要、CLAUDE.md Critical Lessons HIGH 準拠):
#   file-top に `set -euo pipefail` を **書かない**。
#   caller の shell flags への leak と SIGPIPE → exit 141 サイレント死を防ぐ。
#   strict mode が必要な箇所は subshell `( set -euo pipefail; ... )` で局所化する。

set -uo pipefail  # errexit は外し、unset + pipefail のみ

# stdin を必ず保持 (pipeline 詰まり防止)
input=$(cat 2>/dev/null || true)

# --- モード解決 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mode-loader.sh
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  MODE=$(load_mode)
else
  MODE="normal"
fi

# Loop モード以外は no-op
if [ "$MODE" != "loop" ]; then
  exit 0
fi

# --- bypass-logger.sh (best-effort) ---
# shellcheck source=lib/bypass-logger.sh
if [ -f "$SCRIPT_DIR/lib/bypass-logger.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/bypass-logger.sh" 2>/dev/null || true
fi

# --- config-loader.sh (best-effort、HC_* env 解決) ---
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled loop_mode_enforcement; then
  exit 0
fi

# --- bypass 判定 ---
# ECC_LOOP_CONFIRMATION_OFF=1 — 1 セッション一時 OFF
if [ "${ECC_LOOP_CONFIRMATION_OFF:-0}" = "1" ]; then
  if command -v log_bypass >/dev/null 2>&1; then
    log_bypass "loop-confirmation-detector" "ECC_LOOP_CONFIRMATION_OFF" "${ECC_BYPASS_REASON:-(not provided)}"
  fi
  exit 0
fi

# HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false — config レベル無効化
if [ "${HC_LOOP_CONFIRMATION_DETECTION_ENABLED:-true}" = "false" ]; then
  if command -v log_bypass >/dev/null 2>&1; then
    log_bypass "loop-confirmation-detector" "HC_LOOP_CONFIRMATION_DETECTION_ENABLED" "config-disabled"
  fi
  exit 0
fi

# --- 依存チェック (jq 不在で fail-open) ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- transcript_path 抽出 ---
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# システム機密 path への traversal を拒否 (security-M1 + sec-H2 拡張)
# writable system path (/dev/*) も追加して traversal を構造的に防止
case "$transcript_path" in
  /etc/*|/usr/*|/bin/*|/sbin/*|/sys/*|/proc/*|/var/log/*|/dev/*)
    exit 0 ;;
esac

# --- 直前 assistant text 抽出 (末尾 50 行) ---
# why-x5-violation-detect.sh と同じ抽出戦略 (transcript 形式変動への耐性確保)
last_assistant=$(tail -n 50 "$transcript_path" 2>/dev/null | jq -rs '
  [
    .[]
    | select(
        ((.type // "") == "assistant")
        or ((.role // "") == "assistant")
        or (((.message // {}).role // "") == "assistant")
      )
    | (
        ((.message // .).content)
        | if type == "array" then
            [ .[] | (.text // "") ] | join("\n")
          elif type == "string" then .
          else "" end
      )
  ]
  | last // ""
' 2>/dev/null)

if [ -z "$last_assistant" ]; then
  exit 0
fi

# --- 検出 regex (default 19 パターン、env override 可) ---
# 改行区切り。Bash 連想配列等は使わず、while read で 1 行ずつ照合する。
# Pattern 1 (進めて...): 「進めて」「進めてよ」「進めても」「進めてもよ」
#   「進めてもよろ」「進めてよろ」「進めてもよろし」全パターンを cover (tdd-H2 fix)
# Pattern 7 (お待ちし...): BSD grep で empty alternation (て|) 不可、(て)? に修正 (tdd-H1 fix)
# Pattern 2 (OK...): \s は POSIX 非 portable、[[:space:]] に修正 (architect-M2 fix)
# Pattern 14-19 (2026-05-27 拡張): 予防的自主ターン区切りパターン
#   遵守事項 9 (list.md 全 task 連続自律実行) 違反検出のため追加
DEFAULT_PATTERNS='進めて((も)?よろ|よ|も)?(し)?い(い)?(ですか|でしょうか)
OK[[:space:]]?(ですか|でしょうか)
どちら(に|を)?します?か?
どうします?か?
実行(し|して)も(よろし|よ)い?(ですか|でしょうか)
次の指示をお待ちします
お待ちし(て)?(い|お)?ます
user 判断待ち
user 確認待ち
進めますか
続行しますか
停止しますか
よろしいですか
本[[:space:]]?turn[[:space:]]?完遂
ターン区切り
次[[:space:]]?turn[[:space:]]+で.*着手
次回[[:space:]]+fresh[[:space:]]+prompt
context[[:space:]]+budget[[:space:]]+警戒
ここで一旦'

# PATTERNS env override は空 / whitespace のみなら default に戻す (sec-H1 fix)
PATTERNS="${HC_LOOP_CONFIRMATION_PATTERNS:-}"
if ! printf '%s' "$PATTERNS" | grep -qE '[^[:space:]]'; then
  PATTERNS="$DEFAULT_PATTERNS"
fi

matched=""
while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  if printf '%s' "$last_assistant" | grep -Eq "$pat" 2>/dev/null; then
    matched="$pat"
    break
  fi
done <<< "$PATTERNS"

if [ -z "$matched" ]; then
  # 違反なし → silent exit 0
  exit 0
fi

# matched 制御文字 + regex metachar escape (security-M2 fix + sec-M4 拡張)
# 改行 / CR / null + single quote / backslash / dollar / backtick を除去 — warn_message 埋め込み前
matched_safe=$(printf '%s' "$matched" | tr -d '\n\r\0\\`$' | tr -d "'")

# --- 検出: bypass.log 記録 + reason 注入 ---
# env_var label を VIOLATION に変更し filter で bypass と区別可能化 (security-M3 fix)
if command -v log_bypass >/dev/null 2>&1; then
  log_bypass "loop-confirmation-detector" "VIOLATION" "pattern=${matched_safe}"
fi

# reason を jq で安全に JSON エンコード (改行 / 引用符 / 特殊文字を escape)
# 2026-05-27 拡張: 遵守事項 9 (list.md 全 task 連続自律実行) 言及追加、
# context tier 警告 (60/80/95) 未発火下での予防的自主ターン区切り禁止を明示
warn_message=$(cat <<EOF
[loop-confirmation-detector] Loop モード違反検出: パターン '${matched_safe}' を検出。 Loop モード遵守事項 2 (中間確認の停止) / 遵守事項 9 (list.md 全 task 連続自律実行) 違反の可能性。 context tier 警告 (60/80/95) 未発火下での予防的自主ターン区切りは禁止。 context tier 80 到達まで自律実行を継続し、tier 80 以上で自動 /save-state してください。 詳細: \`.claude/rules/modes.md\` 遵守事項 2 + 遵守事項 9 + \`.claude/commands/resume-state.md\` Phase 6 step 6/7。
EOF
)

# JSON 出力 (top-level decision:"block" + reason)
# Stop hook の decision:"block" は「AI を停止させず reason を次 turn に注入」の意味。
# 通常の PreToolUse block (実行阻止) とは semantics が反転している。
# jq でエンコードし control 文字等を安全に embed する。
if printf '%s' "$warn_message" | jq -Rsc '{
  decision: "block",
  reason: .
}' 2>/dev/null; then
  :
else
  # jq fail 時は top-level JSON fallback (fail-open)
  cat <<'FALLBACK'
{"decision":"block","reason":"[loop-confirmation-detector] Loop モード違反検出: 確認質問 / 予防的自主ターン区切りパターンを検出。Loop モード遵守事項 2 (中間確認の停止) / 遵守事項 9 (list.md 全 task 連続自律実行) 違反の可能性。次 turn で確認質問せず自律実行に切替えてください。詳細: .claude/rules/modes.md 遵守事項 2 + 遵守事項 9。"}
FALLBACK
fi

exit 0
