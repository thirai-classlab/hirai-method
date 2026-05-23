#!/usr/bin/env bash
# subagent-detect.sh — サブエージェント検出 (多段フォールバック)
#
# Claude Code のバージョンにより subagent 識別フィールドが異なる/未提供のため、
# 以下を順に評価し、いずれかが立っていれば「サブエージェント実行中」と判定する。
#
# 1. 環境変数 CLAUDE_HARNESS_ROLE=subagent (user / Agent tool が明示)
# 2. 入力 JSON のいずれか: agent_type / subagent_type / parent_tool_use_id / agent_id
# 3. ${HC_AGENT_MARKER_DIR}/*.lock の存在 (PreToolUse:Agent hook が書き出す)
#
# 引数: $1 = input JSON
# 出力: stdout に "true" / "false"

detect_subagent() {
  local input="$1"
  local is_subagent="false"

  if [ "${CLAUDE_HARNESS_ROLE:-}" = "subagent" ]; then
    is_subagent="true"
  fi

  if [ "$is_subagent" = "false" ]; then
    local field v
    for field in agent_type subagent_type parent_tool_use_id agent_id; do
      v=$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)
      if [ -n "$v" ] && [ "$v" != "null" ]; then
        is_subagent="true"
        break
      fi
    done
  fi

  if [ "$is_subagent" = "false" ] && [ -d "$HC_AGENT_MARKER_DIR" ]; then
    if ls "$HC_AGENT_MARKER_DIR"/*.lock >/dev/null 2>&1; then
      is_subagent="true"
    fi
  fi

  printf '%s' "$is_subagent"
}
