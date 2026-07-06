#!/usr/bin/env bash
# gateguard.sh — Fact-forcing PreToolUse gate (ECC GateGuard)
#
# Args: $1 = tool name (Edit|Write|Bash) used as fallback if JSON tool_name absent
# Stdin: PreToolUse JSON
#
# Bypass:
#   ECC_GATEGUARD=off          # disable globally
#   /gate-clear                # reset state
#   /gate-bypass <file>        # pre-clear one file
#
# Config keys consumed (.claude/harness-config.yml):
#   gateguard_state_dir        # state file root (cleared markers)
#   agent_marker_dir           # for subagent passthrough detection

set -u

# config 読み込み (HC_* 変数 export)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

# BLOCK message 統一 API (task-94 P2-3、docs/draft/lib-block-message-4args.md §3.1)
# shellcheck source=lib/block-message.sh
source "$(dirname "$0")/lib/block-message.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled gateguard; then
  echo '{}'
  exit 0   # feature OFF で no-op
fi

# Phase β: F1 disable for SWE-bench grid evaluation (fail-open)
# ECC_F{1,2,3}_OFF env vars allow runner.py to bypass gates per-task
# while measuring gate effectiveness. Production usage MUST NOT set these.
if [ "${ECC_F1_OFF:-0}" = "1" ] || [ "${ECC_F1_OFF:-}" = "true" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{decision:"approve", reason:"F1 (gateguard) disabled via ECC_F1_OFF"}'
  else
    printf '{"decision":"approve","reason":"F1 (gateguard) disabled via ECC_F1_OFF"}\n'
  fi
  exit 0
fi

# Bypass
if [ "${ECC_GATEGUARD:-}" = "off" ]; then
  echo '{}'
  exit 0
fi

input=$(cat)

# Need jq
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# Detect tool from JSON, fallback to $1
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$tool" ] || [ "$tool" = "null" ]; then
  tool="${1:-}"
fi

# Subagent passthrough (same multi-stage detection as delegation-guard)
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

state_dir="$HC_GATEGUARD_STATE_DIR"
mkdir -p "$state_dir" 2>/dev/null

hash_str() {
  printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-12
}

# emit_block: task-94 migration wrapper
#   PreToolUse event 用に emit_block_pretool へ委譲 (lib SSoT)。
#   既存 caller (Edit / Write / Bash gate) の 1-arg 呼出 semantic を保持するため、
#   full message を why arg として渡し、他 3 arg は空 (msg 内に 3 点提示が inline 済)。
emit_block() {
  emit_block_pretool "$1" "" "" ""
}

# === Edit gate ===
if [ "$tool" = "Edit" ]; then
  file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
  if [ -z "$file" ]; then echo '{}'; exit 0; fi

  # Excluded paths
  case "$file" in
    */CLAUDE.md|*/README.md|*/.gitignore|*/.dockerignore|*/.env.example|*/.gitmessage|*/.claude/.agent-markers/*|*/.claude/.gateguard-state/*|*.lock)
      echo '{}'; exit 0;;
  esac

  fhash=$(hash_str "$file")
  state="$state_dir/edit-$fhash.cleared"

  if [ -f "$state" ]; then
    echo '{}'; exit 0
  fi

  touch "$state" 2>/dev/null

  msg="[GateGuard] First Edit to: $file"
  msg="$msg"$'\n\n'"Before retrying, gather and present these facts:"
  msg="$msg"$'\n\n'"  1. Run Grep to list ALL files importing/requiring this file"
  msg="$msg"$'\n'"     -> which downstream code is affected by this edit?"
  msg="$msg"$'\n'"  2. Identify public functions / classes / exports affected"
  msg="$msg"$'\n'"     -> API surface that callers depend on"
  msg="$msg"$'\n'"  3. Describe data structure (field names, types, date formats)"
  msg="$msg"$'\n'"     -> values may be redacted"
  msg="$msg"$'\n'"  4. Quote the user's verbatim instruction authorizing this change"
  msg="$msg"$'\n\n'"After presenting these facts, retry the Edit — the gate is now cleared"
  msg="$msg"$'\n'"for this file in this session ($state created)."
  msg="$msg"$'\n\n'"Bypass: ECC_GATEGUARD=off  /  /gate-clear  /  /gate-bypass $file"

  emit_block "$msg"
  exit 0
fi

# === Write gate ===
if [ "$tool" = "Write" ]; then
  file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
  if [ -z "$file" ]; then echo '{}'; exit 0; fi

  case "$file" in
    */CLAUDE.md|*/README.md|*/.gitignore|*/.dockerignore|*/.env.example|*/.gitmessage|*/.claude/.agent-markers/*|*/.claude/.gateguard-state/*|*.lock)
      echo '{}'; exit 0;;
  esac

  fhash=$(hash_str "$file")
  state="$state_dir/write-$fhash.cleared"

  if [ -f "$state" ]; then
    echo '{}'; exit 0
  fi

  touch "$state" 2>/dev/null

  msg="[GateGuard] First Write of new file: $file"
  msg="$msg"$'\n\n'"Before retrying, gather and present these facts:"
  msg="$msg"$'\n\n'"  1. Which files / lines will call or import this new file?"
  msg="$msg"$'\n'"     -> if none yet, name the caller you'll add next"
  msg="$msg"$'\n'"  2. Confirm via Glob that no existing file duplicates this purpose"
  msg="$msg"$'\n'"  3. Describe data structure (if applicable)"
  msg="$msg"$'\n'"  4. Quote the user's verbatim instruction authorizing creation"
  msg="$msg"$'\n\n'"After presenting these facts, retry the Write — the gate is now cleared"
  msg="$msg"$'\n'"for this file in this session ($state created)."
  msg="$msg"$'\n\n'"Bypass: ECC_GATEGUARD=off  /  /gate-clear  /  /gate-bypass $file"

  emit_block "$msg"
  exit 0
fi

# === Bash gate ===
if [ "$tool" = "Bash" ]; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  if [ -z "$cmd" ]; then echo '{}'; exit 0; fi

  is_destructive="false"
  if printf '%s' "$cmd" | grep -qE '(rm -rf|rm -fr|git reset --hard|git push --force|git push -f|git branch -D|drop table|DROP TABLE|truncate table|TRUNCATE TABLE|supabase db reset)'; then
    is_destructive="true"
  fi

  if [ "$is_destructive" = "false" ]; then
    echo '{}'; exit 0
  fi

  chash=$(hash_str "$cmd")
  state="$state_dir/bash-$chash.cleared"

  if [ -f "$state" ]; then
    echo '{}'; exit 0
  fi

  touch "$state" 2>/dev/null

  cmd_short=$(printf '%s' "$cmd" | head -c 200)

  msg="[GateGuard] First destructive Bash command:"
  msg="$msg"$'\n'"  \$ $cmd_short"
  msg="$msg"$'\n\n'"Before retrying, gather and present these facts:"
  msg="$msg"$'\n\n'"  1. List ALL files / data this command modifies or deletes"
  msg="$msg"$'\n'"     -> enumerate explicitly, not 'various files'"
  msg="$msg"$'\n'"  2. Provide a one-line rollback procedure"
  msg="$msg"$'\n'"     -> e.g. git reflog / DB snapshot restore"
  msg="$msg"$'\n'"  3. Quote the user's verbatim instruction authorizing this destructive action"
  msg="$msg"$'\n\n'"After presenting these facts, retry — the gate is cleared for this exact"
  msg="$msg"$'\n'"command in this session ($state created)."
  msg="$msg"$'\n\n'"Bypass: ECC_GATEGUARD=off  /  /gate-clear"

  emit_block "$msg"
  exit 0
fi

# Default: allow
echo '{}'
exit 0
