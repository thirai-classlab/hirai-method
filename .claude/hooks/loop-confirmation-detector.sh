#!/usr/bin/env bash
# loop-confirmation-detector.sh — Stop hook
#
# 役割:
#   Loop モード稼働中、AI 最終 assistant message に「確認質問パターン」
#   (例: 「進めてよいですか?」「OK ですか?」「お待ちします」) が含まれていた場合、
#   `<system-reminder>` (hookSpecificOutput.additionalContext) を次 turn に注入し、
#   「Loop モード遵守事項 2 (中間確認の停止) 違反 → 自律実行に切替えよ」と是正を促す。
#   Normal モードでは no-op。
#
# 設計起源:
#   docs/draft/loop-confirmation-detector-hook.md (frontmatter retroactive: true,
#   approved_by: user, 2026-05-26)
#   task-41 Step 2
#
# 発火 timing:
#   Stop hook (AI 最終 assistant message 完了時、PostToolUse の後段)
#
# 動作概要:
#   1. mode-loader.sh で current mode 取得、Loop モード以外は早期 exit 0
#   2. bypass env 判定 (ECC_LOOP_CONFIRMATION_OFF=1 / HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false)
#   3. stdin JSON から transcript_path を抽出 (jq 不在で fail-open)
#   4. transcript 末尾から最後の assistant text を抽出
#   5. 確認質問 regex (default 13 パターン or HC_LOOP_CONFIRMATION_PATTERNS で override)
#      に対し grep -E で照合
#   6. 検出時:
#      - bypass.log に violation-detected 記録
#      - stdout に JSON `{"hookSpecificOutput":{"hookEventName":"Stop",
#        "additionalContext":"..."}}` を出力
#   7. 検出なしなら silent exit 0
#
# 環境変数:
#   ECC_LOOP_CONFIRMATION_OFF=1                       ... 一時 OFF (1 セッション)
#   HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false      ... config レベル無効化
#   HC_LOOP_CONFIRMATION_PATTERNS=<改行区切り>        ... regex 上書き
#
# 失敗時の挙動:
#   - exit 0 のみ (fail-open)。block しない (additionalContext 注入のみ)。
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

# --- 検出 regex (default 13 パターン、env override 可) ---
# 改行区切り。Bash 連想配列等は使わず、while read で 1 行ずつ照合する。
DEFAULT_PATTERNS='進めて(も|よろ)?(し)?い(い)?(ですか|でしょうか)
OK\s?(ですか|でしょうか)
どちら(に|を)?します?か?
どうします?か?
実行(し|して)も(よろし|よ)い?(ですか|でしょうか)
次の指示をお待ちします
お待ちし(て|)(い|お)?ます
user 判断待ち
user 確認待ち
進めますか
続行しますか
停止しますか
よろしいですか'

PATTERNS="${HC_LOOP_CONFIRMATION_PATTERNS:-$DEFAULT_PATTERNS}"

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

# --- 検出: bypass.log 記録 + additionalContext 注入 ---
if command -v log_bypass >/dev/null 2>&1; then
  log_bypass "loop-confirmation-detector" "violation-detected" "pattern=${matched}"
fi

# additionalContext を jq で安全に JSON エンコード (改行 / 引用符 / 特殊文字を escape)
warn_message=$(cat <<EOF
[loop-confirmation-detector] Loop モード違反検出: 確認質問パターン '${matched}' を検出。Loop モード遵守事項 2 (中間確認の停止) 違反。次 turn で確認質問せず自律実行に切替えてください。詳細: \`.claude/rules/modes.md\` 遵守事項 2。
EOF
)

# JSON 出力 (hookSpecificOutput.additionalContext)
# jq でエンコードし control 文字等を安全に embed する
if printf '%s' "$warn_message" | jq -Rsc '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: .
  }
}' 2>/dev/null; then
  :
else
  # jq fail 時は plain text fallback (fail-open)
  cat <<'FALLBACK'
<system-reminder>
[loop-confirmation-detector] Loop モード違反検出: 確認質問パターンを検出。
Loop モード遵守事項 2 (中間確認の停止) 違反。次 turn で確認質問せず自律実行に切替えてください。
詳細: `.claude/rules/modes.md` 遵守事項 2。
</system-reminder>
FALLBACK
fi

exit 0
