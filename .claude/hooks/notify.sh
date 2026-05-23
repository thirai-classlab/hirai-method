#!/usr/bin/env bash
# Notification: 操作待ち通知 (macOS)
#
# Config keys consumed (.claude/harness-config.yml):
#   notify_sound               # afplay 対象 (macOS のみ。非 macOS / 不在ファイルなら静音)
set -u

# config 読み込み (HC_NOTIFY_SOUND)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

input=$(cat)

# task-22 W2: jq 不在環境では fail-open (msg = default、通知音のみ鳴らす)
if command -v jq >/dev/null 2>&1; then
  msg=$(echo "$input" | jq -r '.message // "承認/入力が必要です"')
else
  msg="承認/入力が必要です"
fi
project=$(basename "$(pwd)")
afplay "$HC_NOTIFY_SOUND" >/dev/null 2>&1 &
osascript -e "display notification \"$msg\" with title \"Claude Code: $project\" subtitle \"操作が必要です\"" >/dev/null 2>&1
