#!/usr/bin/env bash
# loop-auto-progress-reminder.sh — SubagentStop + Stop hook
#
# 役割:
#   Loop モード稼働中、subagent 完了直後 (SubagentStop) と ターン終了時 (Stop)
#   に発火し、「subagent 完了通知後の自動次タスク起動 を default 動作とする」を
#   <system-reminder> で再注入する。
#   Normal モードでは no-op。
#
# 設計の根本変更 (task-21 W0.1, 2026-05-23):
#   旧: UserPromptSubmit (= user 次入力時) で「待ち中報告」キーワード検出 → fail-late
#   新: SubagentStop (subagent 完了直後) + Stop (ターン終了時) → fail-early
#       - SubagentStop: subagent 完了直後にメインへ「即次タスク継続」hint
#       - Stop: ターン終了時の最終検出 (メインが受動待ちで停止しようとした際)
#
# 簡略実装 (初期版):
#   event 受信時、Loop モードなら常に `<system-reminder>` を出力する。
#   過去 N ターン transcript の「待ち中キーワード grep」は将来精度向上の余地。
#   fail-early 設計を優先し、誤注入 (Loop モード稼働中の全 SubagentStop / Stop)
#   は under-warn より許容可能と判断。
#
# 環境変数:
#   HC_LOOP_AUTO_PROGRESS_ENABLED=false   ... 無効化 (Normal モードと等価)
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもメインターンをブロックしない (fail-open)。
#
# 設計起源:
#   docs/draft/system-reminder-attention-fix.md §2 W0.1
#   docs/tasks/task-21-system-reminder-attention-fix.md W0.1

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

# Loop モード以外は no-op
if [ "$MODE" != "loop" ]; then
  exit 0
fi

# --- 早期 bypass ---
if [ "${HC_LOOP_AUTO_PROGRESS_ENABLED:-true}" = "false" ]; then
  exit 0
fi

# --- event 種別判定 (SubagentStop / Stop) ---
# stdin JSON の hook_event_name を抽出 (jq 不在時は "unknown")
EVENT_NAME="unknown"
if command -v jq >/dev/null 2>&1; then
  EVENT_NAME=$(printf '%s' "$input" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
fi

# --- system-reminder 注入 ---
cat <<EOF
<system-reminder>
**Loop モード自律進行 — ${EVENT_NAME} event 検出 (loop-auto-progress-reminder)**

Loop モード稼働中、以下を default 動作として遵守すること
(\`.claude/rules/modes.md\` 遵守事項 7、設計起源 \`docs/draft/system-reminder-attention-fix.md\` W0.1):

**メインへの指示**:

1. **subagent 完了通知後の次タスク自動起動は default 動作**。user 指示を待たない。
2. subagent 完了を待つ間、以下のいずれかを **必ず並行進行** すること:
   - 別の独立 task (\`docs/tasks/list.md\` の \`🔲 未着手\` 行) を着手
   - メイン専任作業 (タスク管理 / list.md sync / draft 起こし / next-actions 整理)
   - 規範文書化 (\`.claude/rules/\` / CLAUDE.md 編集)
   - memory 整理 / 進捗 commit
3. 並行作業が物理的に無い場合 (依存関係 / 全 task 着手済) のみ、その旨を明示報告
   して停止可。「完了通知を待つだけ」「次セッションで対応」では停止しない。

**bypass**:
- \`HC_LOOP_AUTO_PROGRESS_ENABLED=false\` でセッション全体 OFF
- Loop モード自体の解除: \`/mode normal\`
</system-reminder>
EOF

exit 0
