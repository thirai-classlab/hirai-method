#!/usr/bin/env bash
# failure-loop-detect.sh — 同種エラーの 3 連続発生を検出して /agent-introspect を提案
#
# Wired into PostToolUse matcher "*" via settings.json
# Tracks recent tool errors per session in .claude/.failure-window/<session>.log
# On 3+ consecutive same-signature errors, injects additionalContext suggesting
# /agent-introspect to break the blind-retry loop.
#
# Bypass:
#   ECC_FAILURE_LOOP=off                          # disable globally
#   rm ${failure_window_dir}/<session>.log        # reset one session
#   /agent-introspect                             # user explicit reset (after diagnosis)
#
# Subagent passthrough: matches delegation-guard / gateguard multi-stage detection.
#
# Config keys consumed (.claude/harness-config.yml):
#   failure_window_dir         # session log root
#   agent_marker_dir           # subagent passthrough detection

set -u

# config 読み込み (HC_* 変数 export)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled failure_loop_detect; then
  echo '{}'
  exit 0   # feature OFF で no-op (PostToolUse hook response 規約: empty JSON)
fi

# === Bypass ===
if [ "${ECC_FAILURE_LOOP:-}" = "off" ]; then
  echo '{}'
  exit 0
fi

input=$(cat)

# === jq required ===
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# === Subagent passthrough ===
is_subagent="false"
if [ "${CLAUDE_HARNESS_ROLE:-}" = "subagent" ]; then
  is_subagent="true"
fi
if [ "$is_subagent" = "false" ]; then
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
if [ "$is_subagent" = "true" ]; then
  echo '{}'
  exit 0
fi

# === State directory ===
window_dir="$HC_FAILURE_WINDOW_DIR"
mkdir -p "$window_dir" 2>/dev/null

session=$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)
[ -z "$session" ] || [ "$session" = "null" ] && session="default"

# Sanitize session ID (keep alnum + dash)
session=$(printf '%s' "$session" | tr -c '[:alnum:]-' '_' | head -c 64)

tool=$(printf '%s' "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null)
[ -z "$tool" ] || [ "$tool" = "null" ] && tool="unknown"

# === Detect failure ===
# tool_response shape varies — try multiple paths
is_error=$(printf '%s' "$input" | jq -r '
  (.tool_response.is_error // false)
  // (.tool_response.error // null | if . == null then false else true end)
  // false
' 2>/dev/null)

# Also check decision:block from upstream hooks (those preceded by Pre hooks may surface as error in chain)
hook_blocked=$(printf '%s' "$input" | jq -r '.tool_response.decision // empty' 2>/dev/null)
if [ "$hook_blocked" = "block" ]; then
  is_error="true"
fi

log="$window_dir/$session.log"

if [ "$is_error" != "true" ]; then
  # success → reset window for this session
  : > "$log" 2>/dev/null
  echo '{}'
  exit 0
fi

# === Build error signature ===
# Use tool name + first 80 chars of error message as signature
err_msg=$(printf '%s' "$input" | jq -r '
  (.tool_response.error // .tool_response.content // .tool_response.reason // "")
  | tostring
' 2>/dev/null | tr '\n' ' ' | head -c 80)

sig="$tool|$err_msg"

# Append + keep last 10
echo "$sig" >> "$log" 2>/dev/null
if [ -f "$log" ]; then
  tail -n 10 "$log" > "$log.tmp" 2>/dev/null && mv "$log.tmp" "$log" 2>/dev/null
fi

# === Detect 3+ consecutive same-signature errors ===
recent=$(tail -n 3 "$log" 2>/dev/null)
total=$(printf '%s\n' "$recent" | grep -c '^' 2>/dev/null || echo "0")
unique=$(printf '%s\n' "$recent" | sort -u | grep -c '^' 2>/dev/null || echo "0")

if [ "$total" -ge "3" ] && [ "$unique" = "1" ]; then
  msg="[failure-loop-detect] Same-signature error observed 3 times in a row (tool=$tool)."$'\n'
  msg="${msg}盲目リトライを停止し、根本原因を診断することを推奨:"$'\n\n'
  msg="${msg}  /agent-introspect    # L5 自己診断（4 phase: Capture / Diagnose / Recover / Report）"$'\n\n'
  msg="${msg}診断後にウィンドウをリセット:"$'\n'
  msg="${msg}  rm $log"$'\n\n'
  msg="${msg}Bypass (loop 自体を一時 OFF): ECC_FAILURE_LOOP=off"

  jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
  exit 0
fi

echo '{}'
exit 0
