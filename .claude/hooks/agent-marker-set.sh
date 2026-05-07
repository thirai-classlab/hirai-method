#!/usr/bin/env bash
# PreToolUse(Agent): サブエージェント起動マーカーを書き出す。
# delegation-guard.sh はこのマーカーを見て「現在 Agent 経由のサブセッションが
# 動いている」と判定し、保護パスへの Read/Edit/Bash を許可する。
#
# concurrent Agent 起動に耐えるため、session_id + nanoseconds でユニーク化。
# 古い marker は 60 分で期限切れ扱い (cleanup は agent-marker-clear.sh で実施)。
#
# Config keys consumed (.claude/harness-config.yml):
#   agent_marker_dir           # marker file root
set -uo pipefail

# config 読み込み (HC_AGENT_MARKER_DIR)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
ts="$(date +%s)"
suffix="${session_id:-$$}-$(date +%N)"


# foreground subagent 起動を warn (block ではない)
# development-process.md "サブエージェント委譲の必須要件" §1 に基づき
# run_in_background != true の起動を stderr に通知する。
bg=$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // empty' 2>/dev/null)
if [ "$bg" != "true" ]; then
  printf '[agent-marker] WARNING: subagent launched without run_in_background=true. main エージェントが ブロックされ user 対話が中断します (rules/development-process.md §サブエージェント委譲の必須要件)。\n' >&2
fi

mkdir -p "$HC_AGENT_MARKER_DIR"
printf '%s\n' "$ts" > "${HC_AGENT_MARKER_DIR}/${suffix}.lock"

echo "{}"
