#!/usr/bin/env bash
# extract.sh — confidence-gate の text 抽出 helper
#
# 提供関数:
#   extract_confidence <text>           — text から `confidence: 0.X` を抽出 (variant 対応)
#   extract_tool_response_text <input>  — SubagentStop JSON の tool_response から最終 reply text 抽出
#   resolve_subagent_transcript <transcript> <agent_id>
#                                       — subagent transcript path 解決 (agent_id 付きなら subagents/ 優先)
#   extract_final_assistant_text <transcript>
#                                       — transcript 末尾 500 行から assistant message text を join

# === 抽出ヘルパー: confidence 数値を文字列から抜く ===
# 対応 variant:
#   confidence: 0.85
#   Confidence: 0.85
#   confidence_score: 0.85
#   confidence score: 0.85
#   信頼度: 0.85
#   信頼度 0.85
# 数値レンジ: 0(.0..) / 1(.0..)
# 区切り: 半角 ":" / 全角 "："（記号のみ env-portable な POSIX class で）
extract_confidence() {
  local text="$1"
  local m
  # 英語 variant — confidence / confidence_score / confidence score
  m=$(printf '%s' "$text" | grep -ioE '(confidence([_[:space:]]*score)?)[[:space:]]*[:：][[:space:]]*(0(\.[0-9]+)?|1(\.0+)?)' | tail -n 1)
  if [ -z "$m" ]; then
    # 日本語 variant — 信頼度: 0.X / 信頼度 0.X
    m=$(printf '%s' "$text" | grep -ioE '信頼度[[:space:]]*[:：]?[[:space:]]*(0(\.[0-9]+)?|1(\.0+)?)' | tail -n 1)
  fi
  printf '%s' "$m"
}

# === fallback: hook input の tool_response から最終 reply text を構築 ===
extract_tool_response_text() {
  printf '%s' "$1" | jq -r '
    (.tool_response // {})
    | if type == "string" then .
      elif type == "object" then
        (.content // .text // "")
        | if type == "array" then
            [ .[] | (.text // (if type == "string" then . else "" end)) ] | join("\n")
          elif type == "string" then .
          else "" end
      else "" end
  ' 2>/dev/null
}

# === subagent transcript 解決 ===
# SubagentStop hook に渡される transcript_path は親セッションの JSONL を指すことがある。
# 実際のサブエージェント応答は <parent_stem>/subagents/agent-<id>.jsonl に書かれる。
# agent_id が SubagentStop JSON に含まれる場合は subagent ファイルを優先して読む。
# stdout に解決後 transcript path を返す
resolve_subagent_transcript() {
  local transcript="$1"
  local agent_id="$2"
  if [ -n "$agent_id" ] && [ -n "$transcript" ] && [ "$transcript" != "null" ]; then
    local stem subagent_file
    stem="${transcript%.jsonl}"
    subagent_file="${stem}/subagents/agent-${agent_id}.jsonl"
    if [ -f "$subagent_file" ]; then
      printf '%s' "$subagent_file"
      return
    fi
  fi
  printf '%s' "$transcript"
}

# === 最終 assistant text を抽出 ===
# transcript は JSONL。末尾 500 行から assistant role のメッセージを集める
# (元 200 行では subagent の長い summary が境界をまたぎ confidence を見落とす
# ケースが頻発したため拡大)。
# Claude Code transcript schema 新旧両対応:
#   旧: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
#   新: {"role":"assistant","content":[{"type":"text","text":"..."}]} 等
extract_final_assistant_text() {
  local transcript="$1"
  tail -n 500 "$transcript" 2>/dev/null | jq -rs '
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
            elif type == "string" then
              .
            else
              ""
            end
        )
    ]
    | join("\n")
  ' 2>/dev/null
}
