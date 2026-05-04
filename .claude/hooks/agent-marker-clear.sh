#!/usr/bin/env bash
# PostToolUse(Agent): 該当 session のマーカーを削除 + 期限切れ marker を掃除。
#
# 1 セッションが複数 Agent を順次起動した場合は session_id が同じになるため、
# 当該 session の marker をすべて消す。さらに 60 分以上前の marker も削除する。
#
# Config keys consumed (.claude/harness-config.yml):
#   agent_marker_dir           # marker file root (agent-marker-set.sh と同じ値)
set -uo pipefail

# config 読み込み (HC_AGENT_MARKER_DIR)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty')"
now="$(date +%s)"
expire_seconds=3600

dir="$HC_AGENT_MARKER_DIR"
[ -d "$dir" ] || { echo "{}"; exit 0; }

# 1. 当該 session の marker を削除
if [ -n "$session_id" ]; then
  rm -f "$dir/${session_id}-"*.lock 2>/dev/null
fi

# 2. 期限切れ marker を掃除
for f in "$dir"/*.lock; do
  [ -e "$f" ] || continue
  ts="$(cat "$f" 2>/dev/null || echo 0)"
  if [ $((now - ts)) -gt $expire_seconds ]; then
    rm -f "$f"
  fi
done

echo "{}"
