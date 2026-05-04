#!/usr/bin/env bash
# Stop hook: セッション終了通知 (macOS)
#
# Config keys consumed (.claude/harness-config.yml):
#   stop_sound                 # afplay 対象 (macOS のみ。非 macOS / 不在ファイルなら静音)
set -uo pipefail

# config 読み込み (HC_STOP_SOUND)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

project=$(basename "$(pwd)")
afplay "$HC_STOP_SOUND" >/dev/null 2>&1 &
osascript -e "display notification \"応答が完了しました\" with title \"Claude Code: $project\" subtitle \"確認してください\"" >/dev/null 2>&1
