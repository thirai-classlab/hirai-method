#!/usr/bin/env bash
# loop-auto-progress-reminder.sh — UserPromptSubmit hook
#
# 役割:
#   Loop モード稼働中、メインが「subagent 完了待ちで停止」状態を検出し、
#   <system-reminder> で「独立作業を継続せよ」を強制注入する。
#   Normal モードでは no-op。
#
# 検出条件 (AND):
#   1. 現モードが loop
#   2. 直前 assistant 応答に「待ち中報告 / 完了通知待ち / 次セッションで対応」
#      キーワードが含まれる (default 9 個、env override 可)
#   3. (補助) 直近に Agent tool_use が起動され、対応する tool_result がまだ
#      返っていない (= in_progress subagent あり)。検出失敗時もキーワード単独
#      で warn する (誤検出より under-warn が悪いという思想)。
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもユーザターンをブロックしない (fail-open)。
#   - jq 不在 / transcript 不在 / parse 失敗 → silent skip。
#
# 環境変数:
#   HC_LOOP_AUTO_PROGRESS_ENABLED=false   ... 無効化 (Normal モードと等価)
#   HC_LOOP_AUTO_PROGRESS_KEYWORDS=...    ... 検出 regex 上書き (改行区切り)
#
# 設計起源:
#   docs/draft/loop-auto-progress-enforcement.md §3 W2
#   docs/tasks/task-6-loop-auto-progress-enforcement.md W2 詳細

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

# Loop モード以外は no-op (Normal では waiting check しない)
if [ "$MODE" != "loop" ]; then
  exit 0
fi

# --- 早期 bypass ---
if [ "${HC_LOOP_AUTO_PROGRESS_ENABLED:-true}" = "false" ]; then
  exit 0
fi

# --- 依存チェック ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- stdin parse ---
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# --- 直前 assistant text の抽出 (transcript 末尾 200 行) ---
# confidence-gate.sh と同じ schema 両対応:
#   旧: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
#   新: {"role":"assistant","content":[{"type":"text","text":"..."}]}
last_assistant=$(tail -n 200 "$transcript_path" 2>/dev/null | jq -rs '
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

# --- 待ち中キーワード判定 ---
# 改行区切りで env override 可。default 9 個。
DEFAULT_KEYWORDS='subagent.*完了.*待
subagent.*待機
完了通知.*待
ターン区切り報告
完了次第
完了を待
進捗確認のみ
次セッションで対応
バックグラウンド.*完了.*待'

KEYWORDS="${HC_LOOP_AUTO_PROGRESS_KEYWORDS:-$DEFAULT_KEYWORDS}"

matched=""
while IFS= read -r kw; do
  if [ -n "$kw" ] && printf '%s' "$last_assistant" | grep -qE "$kw"; then
    matched="$kw"
    break
  fi
done <<< "$KEYWORDS"

if [ -z "$matched" ]; then
  exit 0
fi

# --- in_progress subagent 検出 (補助シグナル) ---
# transcript 末尾 500 行から Agent tool_use を集め、対応する tool_result が
# あるか確認。tool_use_id が tool_result.tool_use_id と一致しない (= in_progress)
# なら counted。検出失敗時は 0 として扱い、キーワード単独で warn する。
pending_agents=$(tail -n 500 "$transcript_path" 2>/dev/null | jq -rs '
  ([ .[]
     | (.message.content // .content // [])
     | if type == "array" then .[] else empty end
     | select((.type // "") == "tool_use")
     | select((.name // "") == "Agent" or (.name // "") == "Task")
     | (.id // "")
   ] | map(select(. != ""))) as $tu

  | ([ .[]
       | (.message.content // .content // [])
       | if type == "array" then .[] else empty end
       | select((.type // "") == "tool_result")
       | (.tool_use_id // "")
     ] | map(select(. != ""))) as $tr

  | ($tu | map(select(. as $x | $tr | index($x) == null))) | length
' 2>/dev/null)

pending_agents="${pending_agents:-0}"

# --- system-reminder 注入 ---
cat <<EOF
<system-reminder>
**Loop モード自律進行違反検出 (loop-auto-progress-reminder)**

直前応答に「待ち中 / 完了通知待ち / 次セッションで対応」キーワードが含まれています:
  matched keyword regex: \`${matched}\`
  pending subagent count (補助): ${pending_agents}

Loop モード稼働中は **subagent 完了通知を受動的に待つ停止は禁止** です
(\`.claude/rules/modes.md\` 遵守事項 7、設計起源 \`docs/draft/loop-auto-progress-enforcement.md\`)。

**メインへの指示** (このターン内で必ず実行):

1. subagent 完了を待つ間、以下のいずれかを **必ず並行進行** すること:
   - 別の独立 task (\`docs/tasks/list.md\` の \`🔲 未着手\` 行) を着手
   - メイン専任作業 (タスク管理 / list.md sync / draft 起こし / next-actions 整理)
   - 規範文書化 (\`.claude/rules/\` / CLAUDE.md 編集)
   - memory 整理 / 進捗 commit

2. 並行作業が物理的に無い場合 (依存関係 / 全 task 着手済) のみ、その旨を明示報告
   して停止可。「完了通知を待つだけ」「次セッションで対応」では停止しない。

3. subagent 完了通知後の次タスク自動起動は default 動作。user 指示を待たない。

**bypass**:
- \`HC_LOOP_AUTO_PROGRESS_ENABLED=false\` でセッション全体 OFF
- \`HC_LOOP_AUTO_PROGRESS_KEYWORDS\` で検出 regex 上書き
- Loop モード自体の解除: \`/mode normal\`
</system-reminder>
EOF

exit 0
