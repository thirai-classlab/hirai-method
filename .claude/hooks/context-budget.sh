#!/usr/bin/env bash
# context-budget.sh — UserPromptSubmit hook
#
# 役割:
#   Loop モード稼働中、context 使用率が閾値 (default 60%) を超えた時点で
#   <system-reminder> を注入してメインに `/save-state` 実行 + セッション再開
#   提案を強制する。Normal モードでは no-op。
#
# 仕組み:
#   1. mode-loader.sh で現モード解決。loop でなければ exit 0。
#   2. stdin JSON から transcript_path / session_id を取得。
#   3. transcript JSONL を末尾から逆走し、最後の assistant メッセージの
#      `message.usage` を抽出。
#   4. context_used = input_tokens + cache_creation_input_tokens
#                   + cache_read_input_tokens + output_tokens
#   5. ratio = context_used / context_limit (HC_CONTEXT_BUDGET_LIMIT, default 1M)
#   6. ratio >= threshold かつ未警告セッションなら system-reminder を注入。
#   7. state file (.claude/.context-budget-state/<session>.warned) に
#      警告済み tier (60/80/95) を記録し、tier ごとに 1 度だけ警告。
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもユーザターンをブロックしない。
#   - jq 不在 / transcript 不在 / parse 失敗 → silent skip。
#
# 環境変数 (env override):
#   HC_CONTEXT_BUDGET_ENABLED=false  ... 無効化 (Normal モードと等価)
#   HC_CONTEXT_BUDGET_LIMIT=200000   ... context window サイズ (tokens)
#   HC_CONTEXT_BUDGET_THRESHOLD=0.60 ... 警告開始 ratio (0.0〜1.0)
#   HC_CONTEXT_BUDGET_STATE_DIR=...  ... 警告済み marker 保管先

set -u

# stdin を必ず消費して保持
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

# Loop モード以外は no-op (Normal では context 警告しない)
if [ "$MODE" != "loop" ]; then
  exit 0
fi

# --- config 読み込み ---
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/config-loader.sh"
fi

# --- 早期 bypass ---
if [ "${HC_CONTEXT_BUDGET_ENABLED:-true}" = "false" ]; then
  exit 0
fi

# --- 依存チェック ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- 設定値解決 (defaults) ---
context_limit="${HC_CONTEXT_BUDGET_LIMIT:-1000000}"
threshold="${HC_CONTEXT_BUDGET_THRESHOLD:-0.60}"
state_dir="${HC_CONTEXT_BUDGET_STATE_DIR:-.claude/.context-budget-state}"

# --- stdin parse ---
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# session_id sanitize (alnum + dash)
session_safe=$(printf '%s' "$session_id" | tr -c '[:alnum:]-' '_' | head -c 64)

# --- transcript から最新 assistant usage を取得 ---
# JSONL を逆順に読み、最初に見つかった message.usage を採用。
# 形式変動に備え、複数 path を試す。
# tac 不在環境 (macOS) のための fallback: awk で逆順化
if command -v tac >/dev/null 2>&1; then
  reverse_cmd="tac"
else
  reverse_cmd="awk '{a[NR]=\$0} END {for(i=NR;i>0;i--) print a[i]}'"
fi

last_usage=$(eval "$reverse_cmd" < "$transcript_path" 2>/dev/null \
  | jq -c 'select((.message.usage // .usage // null) != null) | (.message.usage // .usage)' 2>/dev/null \
  | head -1)

if [ -z "$last_usage" ]; then
  exit 0
fi

# context_used = input + cache_creation + cache_read + output
context_used=$(printf '%s' "$last_usage" | jq -r '
  ((.input_tokens // 0)
   + (.cache_creation_input_tokens // 0)
   + (.cache_read_input_tokens // 0)
   + (.output_tokens // 0)) | floor
' 2>/dev/null)

if [ -z "$context_used" ] || [ "$context_used" = "null" ] || [ "$context_used" = "0" ]; then
  exit 0
fi

# --- ratio 計算 (awk で float 演算) ---
ratio=$(awk -v u="$context_used" -v l="$context_limit" 'BEGIN { if (l > 0) printf "%.4f", u / l; else print "0" }')
ratio_pct=$(awk -v r="$ratio" 'BEGIN { printf "%.1f", r * 100 }')

# 閾値判定 (awk で比較)
crossed=$(awk -v r="$ratio" -v t="$threshold" 'BEGIN { print (r >= t) ? 1 : 0 }')
if [ "$crossed" != "1" ]; then
  exit 0
fi

# --- tier 判定 (60/80/95) ---
tier="60"
if awk -v r="$ratio" 'BEGIN { exit !(r >= 0.95) }'; then
  tier="95"
elif awk -v r="$ratio" 'BEGIN { exit !(r >= 0.80) }'; then
  tier="80"
fi

# --- state ファイルで重複抑制 ---
mkdir -p "$state_dir" 2>/dev/null
state_file="$state_dir/${session_safe}.warned"
already_warned=""
if [ -f "$state_file" ]; then
  already_warned=$(cat "$state_file" 2>/dev/null)
fi

# 同 tier を既に警告済みなら skip
case "$already_warned" in
  *"|${tier}|"*) exit 0 ;;
esac

# 上位 tier の警告が既に出ているなら、下位 tier の再警告は不要
if [ "$tier" = "60" ]; then
  case "$already_warned" in
    *"|80|"*|*"|95|"*) exit 0 ;;
  esac
elif [ "$tier" = "80" ]; then
  case "$already_warned" in
    *"|95|"*) exit 0 ;;
  esac
fi

# tier を marker に書き出し
# `already_warned` 末尾の `|` を保ち、`<existing>|<tier>|` 形式で **上書き** する。
# `>>` (append) ではなく `>` (write) を使うのは、`already_warned` を再度
# 書き出すので append すると `|60||60||80|` のように重複するため。
printf '%s|%s|' "$already_warned" "$tier" > "$state_file" 2>/dev/null

# --- 警告メッセージ生成 ---
limit_k=$(awk -v l="$context_limit" 'BEGIN { printf "%.0f", l / 1000 }')
used_k=$(awk -v u="$context_used" 'BEGIN { printf "%.0f", u / 1000 }')

case "$tier" in
  "95")
    urgency="CRITICAL"
    action_verb="**即座に** \`/save-state\` を実行"
    ;;
  "80")
    urgency="URGENT"
    action_verb="**この応答内で** \`/save-state\` を実行"
    ;;
  *)
    urgency="NOTICE"
    action_verb="\`/save-state\` を実行"
    ;;
esac

cat <<EOF
<system-reminder>
**[${urgency}] Loop モード Context 使用率 ${ratio_pct}% (${used_k}K / ${limit_k}K tokens, tier=${tier}%)**

Loop モード稼働中に context limit の ${tier}% を超過しました。残り context が枯渇する前に
セッション状態を保存し、ユーザに再開を提案してください。

**メインエージェントへの指示** (このターン内で必ず実行):

1. ${action_verb} してセッション状態を永続化する
2. 完了後、以下のフォーマットでユーザに **明示的に** 再開を提案する:

   > Context 使用率が ${ratio_pct}% に到達しました。Loop モード継続のため
   > \`/save-state\` でセッション状態を保存しました。
   >
   > **推奨**: 新しいセッションを開始して \`/resume-state\` で復元するか、
   > このまま継続する場合は context limit 到達まで残りわずかな点に留意してください。
   >
   > 続行 / 新セッション開始 のいずれを希望しますか?

3. ユーザの応答を待つ間も Why × 5 出力ルールは継続

**重要**:
- この警告は同一 tier では 1 セッションあたり 1 度のみ発火
- 60% → 80% → 95% の 3 段階で段階的にエスカレート
- 一時的に無効化したい場合: \`HC_CONTEXT_BUDGET_ENABLED=false\`
- 閾値変更: \`.claude/harness-config.yml\` の \`context_budget_threshold\`
</system-reminder>
EOF

exit 0
