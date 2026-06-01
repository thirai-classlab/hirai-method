#!/usr/bin/env bash
# tool-call-slip-detector.sh — Stop hook
#
# 役割:
#   AI 最終 assistant message の本文 (.text) に「tool-call markup slip の痕跡」
#   が残っている場合、tool 呼び出しが serialize 失敗し本文 text 化したと判定し、
#   top-level `{"decision":"block","reason":"..."}` を出力して AI を停止させず
#   次 turn に是正 context を注入する。
#
#   markup slip とは: `antml:invoke` の構造化出力が生成中に部分破綻し、囲みタグ
#   (`<invoke>`) が落ちて中身 (`call` トークン / bare command / `<parameter ...>`
#   断片) が assistant message の .text に流れ込む現象。tool は実行されないまま
#   turn 終了 → 気づかず同じ batch を再 emit → 無限ループに見える
#   (user には「途中で止まった / 動いていない」)。
#   実証: transcript dc60eacc (2026-06-01 task-69 session) で直近 400 行に
#   standalone `call` 12+ 回 + `<parameter name="description">...` の text 漏れを観測。
#
# 検出の根拠 (なぜ .text を見れば分かるか):
#   成功した tool_use ブロックは `.type=="tool_use"` の構造化要素で .text を持たない
#   ため last_assistant (= .text の join) には混入しない。slip した残骸のみが .text
#   に現れる。よって .text に slip 痕跡があれば「直前 tool 呼び出しが失敗」と確定できる。
#
# 設計起源:
#   docs/draft/tool-call-slip-detector-hook.md (approved_by: user, 2026-06-01)
#   memory feedback_multi_tool_block_serialization_failure (arity × payload 複雑度
#   閾値超過で構造化出力が壊れる) の機械的セーフティネット。
#   PreToolUse では捕捉不能 (slip は生成中 = parse 前に起きるため hook が発火しない)。
#   唯一効くレバー = 「user が気づいて指摘」を「Stop hook が自動検出し次 turn 自己是正」
#   に置換する。同型先例 loop-confirmation-detector.sh (task-41) の構造を踏襲。
#
# 発火 timing:
#   Stop hook (AI 最終 assistant message 完了時)
#
# 動作概要:
#   1. stdin JSON から transcript_path 抽出 (jq 不在 / 不在 path で fail-open)
#   2. bypass env 判定
#   3. transcript 末尾から最後の assistant .text を抽出
#   4. fenced code block (``` 囲み) を除去 (bug の meta 議論で markup を引用しても
#      誤検出しないため — slip は fence の外、引用は fence の中)
#   5. slip 痕跡 regex で照合:
#      - standalone `call` 行 (broken invoke wrapper の残渣、最高 signal)
#      - leaked markup 断片 (`<parameter name=` / `<invoke name=` / `</invoke>`
#        / `function_calls>`)
#   6. 検出時: bypass.log に VIOLATION 記録 + `{"decision":"block","reason":"..."}`
#   7. 検出なしなら silent exit 0
#
# mode について:
#   markup slip は Normal / Loop 両モードで起きる (mode 非依存) ため、
#   loop-confirmation-detector と異なり mode gate しない (常時作動)。
#
# 環境変数:
#   HC_FEATURE_TOOL_CALL_SLIP_DETECT_ENABLED=false  ... feature toggle OFF (yml 経由集中管理)
#   ECC_TOOL_CALL_SLIP_OFF=1                        ... 一時 OFF (1 セッション)
#   HC_TOOL_CALL_SLIP_DETECTION_ENABLED=false       ... config レベル無効化
#
# 失敗時の挙動:
#   - exit 0 のみ (fail-open)。jq 不在 / transcript 不在 / parse 失敗 → silent skip。
#   - Stop hook の `decision:"block"` は「AI を停止させず reason を次 turn に注入」の
#     意味 (通常の PreToolUse block と semantics 反転)。
#
# bash flags の方針 (CLAUDE.md Critical Lessons HIGH 準拠):
#   file-top に `set -euo pipefail` を **書かない** (caller への leak / SIGPIPE 死防止)。

set -uo pipefail  # errexit は外し、unset + pipefail のみ

# stdin を必ず保持 (pipeline 詰まり防止)
input=$(cat 2>/dev/null || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# --- feature toggle (paired 実装、yml feature_tool_call_slip_detect_enabled) ---
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled tool_call_slip_detect; then
  exit 0
fi

# --- bypass 判定 ---
if [ "${ECC_TOOL_CALL_SLIP_OFF:-0}" = "1" ]; then
  if command -v log_bypass >/dev/null 2>&1; then
    log_bypass "tool-call-slip-detector" "ECC_TOOL_CALL_SLIP_OFF" "${ECC_BYPASS_REASON:-(not provided)}"
  fi
  exit 0
fi

if [ "${HC_TOOL_CALL_SLIP_DETECTION_ENABLED:-true}" = "false" ]; then
  if command -v log_bypass >/dev/null 2>&1; then
    log_bypass "tool-call-slip-detector" "HC_TOOL_CALL_SLIP_DETECTION_ENABLED" "config-disabled"
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

# システム機密 path への traversal を拒否
case "$transcript_path" in
  /etc/*|/usr/*|/bin/*|/sbin/*|/sys/*|/proc/*|/var/log/*|/dev/*)
    exit 0 ;;
esac

# --- 直前 assistant text 抽出 (末尾 50 行、loop-confirmation-detector と同戦略) ---
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

# --- fenced code block (``` 囲み) を除去 ---
# bug の meta 議論で markup を引用 (常に fence 内) しても誤検出しないため。
# slip 残渣は prose 中 = fence の外に出るので、fence 内を捨てても検出は失われない。
stripped=$(printf '%s\n' "$last_assistant" | awk '
  /^[[:space:]]*```/ { infence = !infence; next }
  infence { next }
  { print }
')

# --- slip 痕跡 regex ---
# (1) standalone `call` 行: broken invoke wrapper の最高 signal。
#     前後 whitespace のみ許容、それ単独行のみ (文中の "call" 単語は match しない)。
# (2) leaked markup 断片: invoke 囲みが落ちて parameter / invoke タグだけ漏れた形。
SLIP_REGEX='(^[[:space:]]*call[[:space:]]*$)|(<parameter[[:space:]]+name=)|(<invoke[[:space:]]+name=)|(</invoke>)|(function_calls>)'

if ! printf '%s' "$stripped" | grep -Eq "$SLIP_REGEX" 2>/dev/null; then
  # slip 痕跡なし → silent exit 0
  exit 0
fi

# --- 検出: bypass.log 記録 + reason 注入 ---
if command -v log_bypass >/dev/null 2>&1; then
  log_bypass "tool-call-slip-detector" "VIOLATION" "markup-slip-detected"
fi

warn_message=$(cat <<'EOF'
[tool-call-slip-detector] 直前の tool 呼び出しが serialize 失敗 (markup slip) し、command が本文 text 化して実行されませんでした。同じ batch を retry してはいけません (同じく失敗しループします)。次の手順で出し直してください: (1) tool 呼び出しは 1 ターンに 1 件のシンプルな形で再発行する。(2) 検証用の複雑な複合 command (複数 echo/grep の連結・grep の alternation・多数 quote/pipe/日本語混在) を inline で組まない — 既存/専用の smoke script を 1 コマンドで実行するか、目的ごとに 1 command へ分割する。(3) subagent fan-out が 3 件以上なら Workflow ツールを使う。手書きは 1 ターン 1-2 件まで、長 prompt は file 経由。(4) tool 呼び出しの前に `call` 等の前置き語を書かない。詳細: memory feedback_multi_tool_block_serialization_failure + .claude/rules/development-process.md §「多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限」。
EOF
)

if printf '%s' "$warn_message" | jq -Rsc '{
  decision: "block",
  reason: .
}' 2>/dev/null; then
  :
else
  cat <<'FALLBACK'
{"decision":"block","reason":"[tool-call-slip-detector] 直前の tool 呼び出しが serialize 失敗 (markup slip) し本文 text 化しました。同 batch を retry せず、1 ターン 1 件のシンプルな tool 呼び出しで出し直してください。複雑な検証 command は分割 or 専用 smoke script を実行。詳細: .claude/rules/development-process.md §多数 fan-out。"}
FALLBACK
fi

exit 0
