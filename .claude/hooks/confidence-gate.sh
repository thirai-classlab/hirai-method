#!/usr/bin/env bash
# confidence-gate.sh — SubagentStop hook (F3) — confidence threshold gate
#
# Orchestrator: env load + bypass / disable check + tool_response/transcript fallback + threshold compare。
# 個別 logic は lib/confidence-gate/ に分割:
#   - bypass.sh             — bypass marker + log_failure helper
#   - extract.sh            — confidence regex / tool_response text / transcript text 抽出
#   - major-agent-filter.sh — F3 major subagent only judgment
#   - messages.sh           — block reason text 生成
#
# Hook event: SubagentStop
# Output:
#   pass  → exit 0 + `{}` （素通し）
#   block → exit 0 + `{"decision":"block","reason":"..."}` （SubagentStop block JSON）
# Bypass:
#   ECC_CONFIDENCE_GATE=off / HC_CONFIDENCE_REQUIRED=false / /gate-bypass confidence

set -u

SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/lib/config-loader.sh"
# shellcheck source=lib/confidence-gate/bypass.sh
source "$SCRIPT_DIR/lib/confidence-gate/bypass.sh"
# shellcheck source=lib/confidence-gate/extract.sh
source "$SCRIPT_DIR/lib/confidence-gate/extract.sh"
# shellcheck source=lib/confidence-gate/major-agent-filter.sh
source "$SCRIPT_DIR/lib/confidence-gate/major-agent-filter.sh"
# shellcheck source=lib/confidence-gate/messages.sh
source "$SCRIPT_DIR/lib/confidence-gate/messages.sh"

# Phase β: F3 disable for SWE-bench grid evaluation (fail-open)
if [ "${ECC_F3_OFF:-0}" = "1" ] || [ "${ECC_F3_OFF:-}" = "true" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{decision:"approve", reason:"F3 (confidence-gate) disabled via ECC_F3_OFF"}'
  else
    printf '{"decision":"approve","reason":"F3 (confidence-gate) disabled via ECC_F3_OFF"}\n'
  fi
  exit 0
fi

# === bypass / disable check ===
if [ "${ECC_CONFIDENCE_GATE:-}" = "off" ]; then echo '{}'; exit 0; fi
if [ "${HC_CONFIDENCE_REQUIRED:-true}" = "false" ]; then echo '{}'; exit 0; fi

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then echo '{}'; exit 0; fi

init_bypass_paths
handle_bypass_marker

emit_block() { jq -n --arg r "$1" '{decision:"block", reason:$r}'; }

agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
_cg_agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
transcript=$(resolve_subagent_transcript "$transcript" "$_cg_agent_id")
unset _cg_agent_id

is_sidechain=$(classify_sidechain "$transcript")
is_major=$(is_major_subagent "$agent_type" "$is_sidechain")

threshold="${HC_CONFIDENCE_THRESHOLD:-0.6}"

compare_and_emit() {
  local score="$1"
  local fail_phase="$2"
  local ok
  ok=$(awk -v s="$score" -v t="$threshold" 'BEGIN { print (s+0 >= t+0) ? "1" : "0" }')
  if [ "$ok" = "1" ]; then echo '{}'; exit 0; fi
  log_failure "$fail_phase" "score=${score} threshold=${threshold} sidechain=${is_sidechain}"
  if [ "$fail_phase" = "below_threshold_via_tool_response" ]; then
    emit_block "[confidence-gate] tool_response 経由で抽出した confidence ${score} が閾値 ${threshold} 未満です。"
  else
    emit_block "$(build_below_threshold_reason "$score" "$threshold")"
  fi
  exit 0
}

extract_score_from_match() {
  printf '%s' "$1" | sed -E 's/.*[:：][[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/'
}

# transcript 不在 / null / 不存在 → tool_response fallback
if [ -z "$transcript" ] || [ "$transcript" = "null" ] || [ ! -f "$transcript" ]; then
  fallback_text=$(extract_tool_response_text "$input")
  if [ -n "$fallback_text" ]; then
    fb_match=$(extract_confidence "$fallback_text")
    if [ -n "$fb_match" ]; then
      score=$(extract_score_from_match "$fb_match")
      compare_and_emit "$score" "below_threshold_via_tool_response"
    fi
  fi
  if [ -z "$transcript" ] || [ "$transcript" = "null" ]; then
    log_failure "no_transcript" "transcript_path missing or null"
  else
    log_failure "file_not_found" "path=${transcript}"
  fi
  echo '{}'; exit 0
fi

final_text=$(extract_final_assistant_text "$transcript")
is_sidechain=$(refine_sidechain_from_records "$is_sidechain" "$transcript")

if [ -z "$final_text" ]; then
  log_failure "extract_failed" "transcript=${transcript} sidechain=${is_sidechain}"
  echo '{}'; exit 0
fi

match=$(extract_confidence "$final_text")
if [ -z "$match" ]; then
  fallback_text=$(extract_tool_response_text "$input")
  if [ -n "$fallback_text" ]; then
    match=$(extract_confidence "$fallback_text")
  fi
fi

if [ -z "$match" ]; then
  # major subagent でなければ fail-open
  if [ "$is_major" = "false" ] && [ "${HC_CONFIDENCE_MAJOR_AGENT_ONLY:-true}" != "false" ]; then
    log_failure "skipped_minor_sidechain" "agent_type=${agent_type} sidechain=${is_sidechain} transcript_chars=${#final_text}"
    echo '{}'; exit 0
  fi
  log_failure "regex_no_match" "transcript_chars=${#final_text} sidechain=${is_sidechain}"
  emit_block "$(build_no_match_reason "$threshold")"
  exit 0
fi

# 数値抽出 + 閾値比較
score=$(extract_score_from_match "$match")
compare_and_emit "$score" "below_threshold"
