#!/usr/bin/env bash
# Stop hook: セッション終了通知 (macOS)
#
# Config keys consumed (.claude/harness-config.yml):
#   stop_sound                 # afplay 対象 (macOS のみ。非 macOS / 不在ファイルなら静音)
#
# 共有 feature toggle group:
#   - グループ制御 toggle: `feature_notify_enabled` (default: true)
#   - OFF にすると本 hook を含む同 group の全 hook が no-op
#   - 編集: `bash .claude/scripts/hc-config.sh --feature notify=false`
#   - 同 group の他 hook: notify.sh
set -uo pipefail

# config 読み込み (HC_STOP_SOUND)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled notify; then
  exit 0   # feature OFF で no-op
fi

project=$(basename "$(pwd)")
afplay "$HC_STOP_SOUND" >/dev/null 2>&1 &
osascript -e "display notification \"応答が完了しました\" with title \"Claude Code: $project\" subtitle \"確認してください\"" >/dev/null 2>&1
