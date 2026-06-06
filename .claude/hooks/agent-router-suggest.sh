#!/usr/bin/env bash
# agent-router-suggest.sh — UserPromptSubmit hook.
#
# Reads the freshly submitted user prompt from stdin (Claude Code passes
# {"prompt": "..."} as JSON), runs the agent-router skill, and emits an
# additionalContext suggestion when the router has high confidence in a
# named specialist. Fail-open: any error returns 0 with no context injection
# so the user prompt continues unchanged.
#
# Activation:
#   Wired via .claude/hooks/dispatcher-manifest.tsv (UserPromptSubmit, advisory
#   channel), gated by feature toggle feature_agent_router_suggest_enabled
#   (default ON). Disable per-repo with `hc-config.sh --feature
#   agent_router_suggest=false` or env HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false.
#   Confidence threshold (suggest vs stay quiet) defaults to 0.5; set
#   AGENT_ROUTER_SUGGEST_THRESHOLD in env to override.
#
# Phase 2 — Hybrid mode:
#   Set AGENT_ROUTER_LLM_FALLBACK=on (or 1/true/yes) to enable the LLM
#   selector for low-confidence prompts. Optional knobs:
#     AGENT_ROUTER_LLM_THRESHOLD   (default 0.5)
#     AGENT_ROUTER_LLM_MODEL       (default claude-haiku-4-5)
#     AGENT_ROUTER_LLM_TIMEOUT     (default 30 seconds)
#     AGENT_ROUTER_LLM_MAX_ATTEMPTS (default 3)
#     AGENT_ROUTER_LLM_BUDGET_USD  (default 0.05)
#   The router itself respects these env vars, so this hook just forwards
#   the env to it via subprocess. No code changes needed when toggling.
#
# Notes:
#   - This hook is OPTIONAL. The router skill works without it; the hook
#     just removes one round-trip for the main agent.
#   - The hook does NOT rewrite tool inputs — that requires a SubagentStart
#     hook which Claude Code does not currently expose. The hook only adds
#     a contextual hint.

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- feature gate (task-81、3 点セット規範) ---
# config-loader.sh は is_feature_enabled / HC_* を提供 (fail-open 設計)。
# dispatcher も manifest feature_key で gate するが、直接起動経路でも OFF を保証するため
# hook 冒頭でも gate する。OFF なら stdin を消費せず即 no-op exit 0。
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh"
fi
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled agent_router_suggest; then
    exit 0   # feature OFF で no-op
fi

THRESHOLD="${AGENT_ROUTER_SUGGEST_THRESHOLD:-0.5}"
ROUTER_PY="${SCRIPT_DIR}/../skills/agent-router/router.py"

if [[ ! -f "${ROUTER_PY}" ]]; then
    # Skill not installed — silently no-op.
    exit 0
fi

# Read stdin (Claude Code JSON payload). If python isn\'t available, no-op.
if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

PAYLOAD="$(cat)"

PROMPT="$(printf '''%s''' "${PAYLOAD}" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('''prompt''', ''''''), end='''''')
except Exception:
    pass
")"

if [[ -z "${PROMPT}" ]]; then
    exit 0
fi

# Build router args. The router itself reads AGENT_ROUTER_LLM_FALLBACK and
# friends from env, so we only need to pass --no-record so the hook does
# not pollute history (the main agent\'s actual dispatch is what should
# count, not the hook\'s preview).
ROUTER_ARGS=(--stdin --no-record)

# Route the prompt; the router itself fails open (exit 2 on error).
ROUTING="$(printf '''%s''' "${PROMPT}" | python3 "${ROUTER_PY}" "${ROUTER_ARGS[@]}" 2>/dev/null || echo '''{"fallback": true}''')"

# Decide whether to suggest. Stay quiet on fallback or low confidence.
SUGGESTION="$(printf '''%s''' "${ROUTING}" | python3 -c "
import json, sys, os
threshold = float(os.environ.get('''AGENT_ROUTER_SUGGEST_THRESHOLD''', '''0.5'''))
try:
    r = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if r.get('''fallback'''):
    sys.exit(0)
conf = float(r.get('''confidence''', 0.0))
if conf < threshold:
    sys.exit(0)
agent = r.get('''agent''', '''''')
matched = ''', '''.join(r.get('''matched_keywords''', [])) or r.get('''reason''', '''''')
extra = ''''''
if r.get('''llm_used'''):
    extra = f''' [hybrid: llm-selector confirmed]'''
if r.get('''cycle_broken'''):
    extra += ''' [cycle-broken]'''
print(
    f'''[agent-router suggestion] This prompt looks like a job for the '''
    f'''"{agent}" subagent (confidence={conf:.2f}, matched: {matched}){extra}. '''
    f'''Consider Agent(subagent_type="{agent}", ...) instead of general-purpose.'''
)
")"

if [[ -n "${SUGGESTION}" ]]; then
    # additionalContext is the canonical channel for UserPromptSubmit hooks
    # to inject context into the model\'s working set.
    printf '''%s\n''' "${SUGGESTION}"
fi

exit 0
