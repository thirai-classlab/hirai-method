#!/usr/bin/env bash
# mode-enforce.sh — UserPromptSubmit hook
#
# 役割: Loop モード稼働中、毎ターンの応答に「停止指示まで AI 推奨で続行」ルールを
#       <system-reminder> として注入する。Normal モードでは no-op。
#       task-68 §3.2: 冗長 reminder を「遵守事項見出し + 事実文 (簡潔な箇条書き)」へ圧縮し、
#       詳細は modes.md pointer 参照に置換。
#
# 失敗時の挙動: exit 0 のみ。失敗してもユーザターンをブロックしない。
#
# 共有 feature toggle group:
#   - グループ制御 toggle: `feature_loop_mode_enforcement_enabled` (default: true)
#   - OFF にすると本 hook を含む同 group の全 hook が no-op
#   - 編集: `bash .claude/scripts/hc-config.sh --feature loop_mode_enforcement=false`
#   - 同 group の他 hook: loop-confirmation-detector.sh, loop-auto-progress-reminder.sh

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

# stdin を消費（pipeline block を避ける）
cat > /dev/null 2>&1 || true

# モードローダーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mode-loader.sh
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  MODE=$(load_mode)
else
  MODE="normal"
fi

if [ "$MODE" != "loop" ]; then
  # Normal モード: 何もしない
  exit 0
fi

# --- config-loader.sh (best-effort、HC_* env 解決 + is_feature_enabled) ---
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled loop_mode_enforcement; then
  exit 0
fi

# task-68 §3.2: 事実文 (簡潔な箇条書き) + pointer 短縮
cat <<'EOF'
<system-reminder>
**Loop モード稼働中** (遵守事項、詳細は `.claude/rules/modes.md`):
- ユーザ確認質問は禁止 (設計新規追加 / 仕様変更 / 戦略判断 / 規範変更は例外で要確認)
- AI 推奨方法を即採用、大タスクは自律分解し最後まで通す
- Why × 5 (1 行) 表示は維持、論理単位ごとに git commit
- 停止条件は 3 つのみ: 明示停止指示 / タスク完了 / 致命的エラー
解除: `/mode normal`
</system-reminder>
EOF

exit 0
