---
name: agent-router
description: Route ambiguous "general-purpose" subagent prompts to the most relevant named agent. Use when about to launch Agent/Task with subagent_type=general-purpose and unsure which named agent fits, when reviewing past general-purpose flows for downgrade to a specialist, or when the user asks "which agent should handle X?". Inputs a prompt string, scores against the dispatch table (~100 active agents under .claude/agents/), and returns the best-matching agent + confidence + reason. Hybrid mode (--use-llm-fallback / AGENT_ROUTER_LLM_FALLBACK=on) invokes a Claude CLI selector for low-confidence prompts to lift dispatch rate further. Three-stage fallback (keyword → LLM → previous → general-purpose) inherits the prior dispatch on the same prompt before falling back to general-purpose.
---

# Agent Router

Establishes a hook-driven habit for the main agent to choose the right `subagent_type` at dispatch time. Recommends a specialist named agent based on prompt keywords so newly-imported specialists do not sit structurally idle.

> **Note on justification**: The original framing cited "66% of historical flow went to general-purpose" as the activation rationale. That figure was measured before the 100 named agents existed in their current form — they were imported on 2026-05-04 in a single commit, so the 90-day pre-import window contains structurally unreliable dormant percentages (see `docs/INVENTORY-stocktake-2026-05-04.md` §8). The router\'s primary justification is **habit formation**: making "name the right specialist" the default behaviour at dispatch time. Dormant numbers are at best a secondary indicator and will be re-measured against post-import transcripts in 30 / 90 days. The empirical 84.1% dispatch rate against the historical prompt sample remains a meaningful coverage signal.

## When to invoke

The main agent (or another skill) should consult agent-router **before** launching `Agent(subagent_type="general-purpose", ...)` when:

1. The prompt mentions a specific domain (review / debug / docs / infra / data / etc.).
2. The user explicitly asks "which agent should handle this?".
3. A previous general-purpose run produced low-confidence output and a re-run with a specialist might do better.

Skip when:

- The prompt is genuinely cross-cutting research with no dominant domain (router will return `general-purpose` as fallback).
- A `subagent_type` is already explicitly specified by the user.

## How to use

```bash
# CLI form (returns JSON)
python3 .claude/skills/agent-router/router.py "review the auth module for SQL injection"
# → {"agent": "security-auditor", "confidence": 0.71, "reason": "matched: security, auth, injection, review", "fallback": false}

# Hybrid mode — invokes the Claude CLI selector when keyword confidence < 0.5
AGENT_ROUTER_LLM_FALLBACK=on python3 .claude/skills/agent-router/router.py "investigate the supply chain dependencies"
# → {"agent": "security-auditor", "confidence": 0.75, "reason": "llm-selector: ...", "llm_used": true, "llm_attempts": 1, "llm_cost_usd": 0.0009}
```

The CLI exits 0 with the JSON result on stdout. Exit 2 means the router itself errored (file missing, table unparseable). On exit 2 the caller should fall back to `general-purpose` and continue.

## Dispatch table

`dispatch-table.yml` is the single source of truth. Each entry maps a keyword (case-insensitive, word-boundary match) to the preferred named agent under `.claude/agents/<category>/<name>.md`. Multiple keywords can point at the same agent. Specialty boost is applied when several keywords from the same agent fire together.

Routing model:

1. Tokenize prompt (lowercase, alphanumeric / `-` / `_`, stop-word filtered).
2. For every keyword in the table, look for a word-boundary match. Each hit contributes `weight` (default 1.0) to the target agent\'s score.
3. Apply specialty boost: when two or more keywords resolve to the same agent, add `0.5` per extra hit.
4. Normalize against a saturation cap (`6.0`) to produce a confidence in `[0, 1]`.
5. If best confidence < `0.30`, return the fallback `general-purpose` with the original tokens as reason.
6. **Hybrid mode (Phase 2)**: when `--use-llm-fallback` (or `AGENT_ROUTER_LLM_FALLBACK=on`) is set and best confidence is below `--llm-threshold` (default `0.5`), invoke a Claude CLI selector with the top 30 candidate agents. Up to 3 retries on parse / timeout / unknown-agent errors. The selector\'s recommendation overrides the keyword fallback when valid; otherwise keyword result is preserved.
7. **Cycle detection (Phase 2)**: same prompt hash dispatched to the same agent twice in a row triggers a forced switch to the next-best agent (or `general-purpose`).
8. **Name normalization (Phase 2)**: LLM agent names get normalized — `Code Reviewer`, `code_reviewer`, `code-reviewer` all map to the canonical `code-reviewer`.

The threshold is conservative on purpose — false-positive routing wastes tokens reframing the prompt for an unsuitable specialist.

## Updating the dispatch table

When a new agent is added under `.claude/agents/`, update `dispatch-table.yml` with at least one keyword. When an agent is archived to `docs/archive/agents/`, **remove** its keywords from the table — routing to an archived agent fails silently and degrades to general-purpose.

Validation:

```bash
python3 -m unittest discover .claude/skills/agent-router/tests -v
```

## Why a skill rather than a hook (today)

Subagent dispatch happens at `Agent(subagent_type=...)` invocation time. There is no native `SubagentStart` PreToolUse hook that can rewrite `subagent_type` (PreToolUse can block but cannot transparently rewrite tool inputs in a way the calling model accepts). Until that lands, the router is invoked manually by the orchestrator (main agent) via this skill or via the optional `agent-router-suggest.sh` `UserPromptSubmit` hook, which injects routing hints into freshly submitted prompts.

## Related

- Inventory & rationale: `docs/INVENTORY-stocktake-2026-05-04.md`
- Handoff context: `docs/draft/agent-router-handoff-2026-05-05.md`
- Router architecture doc: `docs/AGENT-ROUTER.md`
