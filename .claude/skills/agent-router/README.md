# agent-router

Skill that recommends a specialist subagent for ambiguous prompts that would otherwise default to `general-purpose`. The skill establishes a habit of naming the right specialist at dispatch time, instead of falling back to general-purpose by default.

> **Note on justification**: An earlier draft cited "66% (1,178/1,749) of historical subagent invocations went to general-purpose while named specialists sat dormant" as the activation rationale. That figure was measured before the 100 named agents existed in their current form — they were imported on 2026-05-04 in a single commit, so the 90-day pre-import window contains structurally unreliable dormant percentages (see `docs/INVENTORY-stocktake-2026-05-04.md` §8). The router is justified primarily by **habit formation** at dispatch time, not by the dormant figure. The empirical 84.1% dispatch rate against the 1,178 historical `general-purpose` prompts remains a meaningful coverage indicator and will be re-measured against post-import transcripts in 30 / 90 days.

## Files

| Path | Purpose |
|---|---|
| `SKILL.md` | Skill manifest (name, description, when-to-use) |
| `router.py` | Dispatch implementation (stdlib only) |
| `dispatch-table.yml` | Single source of truth: keyword → agent map |
| `tests/test_router.py` | 40 unit + integration tests (19 keyword + 21 Phase 2) |
| `samples/representative_prompts.txt` | Verification fixtures sampled from real history |
| `README.md` | This file (design notes & extension guide) |

## Design

### Why scoring rather than ML?

- Stdlib only, zero dependencies — runs anywhere Python 3 runs.
- Auditable: every routing decision is reproducible from the dispatch table.
- Easy to extend: add a keyword line, no retraining.
- Threshold-controlled fallback prevents false-positive specialist routing.

### Algorithm (Phase 1: keyword)

1. **Tokenize** the prompt: lowercase, alphanumeric + `-` + `_` + `.`, drop a small stop-word set (~50 entries — small to avoid filtering domain terms).
2. **Match keywords**:
   - Single-word keywords: O(1) lookup against the token set.
   - Multi-word phrases (`"app router"`, `"sql injection"`): word-boundary regex search.
3. **Score**: each keyword hit contributes `weight` (default 1.0) to its target agent.
4. **Specialty boost**: when the same agent matches N>1 distinct keywords, add `(N-1) * specialty_boost` (default 0.6). This rewards prompts with strong domain signal.
5. **Confidence** = `min(score / saturation, 1.0)`. Saturation 3.0 means a single hit yields ~0.33 confidence; two hits ~0.87.
6. **Threshold**: if best confidence < 0.25, return `general-purpose` fallback.

### Phase 2: Hybrid (LLM fallback)

When `--use-llm-fallback` is on AND keyword confidence < `--llm-threshold` (default `0.5`):

1. Build a candidate list: top-N keyword candidates first, padded to 30 agents from the active set for breadth.
2. Invoke the Claude CLI selector via subprocess (`claude -p --model claude-haiku-4-5 ...`) with timeout `30s` and per-call budget cap `$0.05`.
3. Parse the JSON output `{"agent": "...", "confidence": 0.0-1.0, "reason": "..."}`. The model may wrap in `\\\`\\\`\\\`json` fences — those are stripped.
4. **Name normalization** maps loose responses (`Code Reviewer`, `code_reviewer`) to canonical agent names. Unknown agents trigger a retry.
5. Up to **3 retries** on timeout / parse failure / unknown agent. After 3 failures, the keyword result is kept and the failure is surfaced in `reason`.
6. **Cycle detection** reads `~/.claude/agent-router-history.json` (last 100 entries). When the same prompt hash dispatched to the same agent twice in a row, the router forces a switch to the next-best alternative.

### Tuning levers

| Field | Default | Effect |
|---|---:|---|
| `threshold` (table) | 0.25 | Lower = route more aggressively to specialists |
| `saturation` (table) | 3.0 | Lower = single keyword hits more confident |
| `specialty_boost` (table) | 0.6 | Higher = stack-rank prompts that hit multiple kw on same agent |
| `--llm-threshold` | 0.5 | Confidence under this triggers LLM selector (Hybrid mode) |
| `--llm-max-attempts` | 3 | Selector retries before keyword fallback |
| `--llm-budget-usd` | 0.05 | Per-call cost cap (forwarded to `claude -p --max-budget-usd`) |

Empirical tuning on 1,178 historical `general-purpose` prompts achieves **~84% routing to named agents** at the current keyword settings. Phase 2 Hybrid mode (mock-evaluated) routes the residual ~16% low-confidence prompts to a named agent in the majority of cases — see [`docs/AGENT-ROUTER.md`](../../../docs/AGENT-ROUTER.md) for the measured uplift.

## Adding / removing agents

When a new agent is added under `.claude/agents/<category>/<name>.md`:

```yaml
# dispatch-table.yml
keywords:
  ...
  <new-keyword>: <new-agent-name>
```

When an agent is **archived** (moved to `docs/archive/agents/`):

1. Open `dispatch-table.yml`.
2. Search for the archived agent name and **delete every keyword** pointing at it.
3. Run `python3 -m unittest discover tests -v` to confirm nothing breaks.

If an archived agent is left in the table, the router will return its name and the caller will fail at `Agent(subagent_type=...)` invocation. The skill never validates that recommended agents still exist on disk — keep the table clean.

## Coordinating with the archive subagent

The agent inventory was reduced from 144 → 100 active agents in a parallel task (see `docs/draft/agent-router-handoff-2026-05-05.md`). The dispatch table here was authored against that final 100-agent active set:

- Archived language specialists (PowerShell, .NET, Rails, Java, Kotlin, Swift, C++, Vue, Angular, FastAPI, Django, Elixir, Flutter, PHP, Rust, etc.) have **no entries** in the table; their typical keywords route to general specialists (e.g. `django` → `python-pro`, `vue` → `frontend-developer`).
- Archived infra/security/data agents (`azure-infra-engineer`, `chaos-engineer`, `ai-engineer`, `reinforcement-learning-engineer`, etc.) have no entries either.
- The `09-meta-orchestration/agent-router.md` agent itself (if added) is not currently in the dispatch table — the router skill is meant to be invoked, not subagented.

## Tests

```bash
cd .claude/skills/agent-router
python3 -m unittest discover tests -v
# 40 tests: parse + tokenize + dispatch + coverage + LLM fallback + cycle detection + name normalization + history recording
```

The `CoverageTests` suite verifies that ≥70% of representative prompts route correctly. The implementation currently achieves 100% on the 20-prompt fixture (keyword-only) and ~84% on the unfiltered 1,178-prompt 90-day historical sample. Phase 2 Hybrid mode further lifts low-confidence prompts; see the benchmark table below.

## Benchmark

| Mode | Sample | Dispatch rate | LLM calls | Cost / prompt |
|---|---|---:|---:|---:|
| Phase 1 (keyword only) | 1,178 historical prompts | 84.1% | 0 | $0.00 |
| Phase 1 (keyword only) | 20 representative prompts | 100% | 0 | $0.00 |
| Phase 2 (Hybrid mock) | 15 low-/subtle-signal prompts | 100% | 13 | ~$0.0009 |

The Phase 2 row uses a deterministic mock selector to validate the wiring; live measurement against the historical 188 low-confidence sample is gated on cost — set `AGENT_ROUTER_LLM_FALLBACK=on` and re-run the harness audit to collect live numbers.

## CLI examples

```bash
# Basic
python3 router.py "review the auth module"
# → {"agent": "security-auditor", "confidence": 1.0, "reason": "matched: auth, review", ...}

# With per-candidate breakdown
python3 router.py --explain "set up kubernetes ingress with helm"

# From stdin
echo "write tdd unit tests with pytest" | python3 router.py --stdin

# With alternative table
python3 router.py --table /tmp/experimental-table.yml "<prompt>"

# Hybrid mode (LLM selector for low-confidence prompts)
python3 router.py --use-llm-fallback --llm-threshold 0.5 "<vague prompt>"

# Hybrid via env (recommended for hooks)
AGENT_ROUTER_LLM_FALLBACK=on python3 router.py "<vague prompt>"
```

## Limitations & future work

- **No semantic understanding** in keyword mode: a prompt like "I need help with Python\'s payment processing" routes on `payment` (→ payment-integration), not on `python` (→ python-pro). Specialty boost mitigates this when both keywords appear, but truly ambiguous prompts may pick the wrong specialist. Hybrid mode addresses this when enabled.
- **No `SubagentStart` hook**: see `SKILL.md#why-a-skill-rather-than-a-hook-today`. The optional `agent-router-suggest.sh` `UserPromptSubmit` hook offers a workaround by injecting routing hints, but the main agent must still consult the result.
- **No invocation feedback loop**: if an agent recommendation produces poor downstream results, the table doesn\'t learn. Periodically re-run the keyword-frequency analysis (see `docs/AGENT-ROUTER.md`) and tune.
- **Hybrid cost discipline**: each LLM selector call is bounded by `--llm-budget-usd` (default $0.05) and timeout 30s. Aggregate cost still scales with the rate of low-confidence prompts; monitor `~/.claude/agent-router-history.json` and the `llm_cost_usd` field for runaway usage.
