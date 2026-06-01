#!/usr/bin/env bash
# mode-enforce.sh — SessionStart wrapper child (session-start-wrapper.sh DEFAULT_HOOKS)
#
# 役割: Loop モード稼働中、session 開始時に「停止指示まで AI 推奨で続行」ルールを
#       1 行 pointer の <system-reminder> として再宣言する。Normal モードでは no-op。
#       full 遵守事項は frontmatter-less 常時参照 rule (.claude/rules/modes.md) に委譲。
#       task-73 案 B: 4 項目箇条書きを 1 行 pointer へ短縮。
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

# task-73 案 B: 1 行 pointer (full 遵守事項は modes.md in-context)
cat <<'EOF'
<system-reminder>
Loop mode 稼働中: AI推奨を即採用 / 確認質問禁止 / 論理単位で commit / 停止=「stop」|完了|致命的error。詳細 .claude/rules/modes.md
</system-reminder>
EOF

exit 0
