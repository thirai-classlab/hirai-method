# Agent Router

Skill + optional hook that establishes a habit of choosing the right `subagent_type` at dispatch time. When the main agent is about to launch `Agent(subagent_type="general-purpose", ...)`, the router scores the prompt against ~100 active named agents and recommends the best fit.

## Justification

The original justification cited "138 of 144 named agents at zero invocations over 90 days" and "66% of historical flow went to general-purpose". Those numbers are **structurally unreliable** because the 144 agents were imported in a single commit on 2026-05-04 — the 90-day historical window mostly precedes their existence (see [`INVENTORY-stocktake-2026-05-04.md` §8](INVENTORY-stocktake-2026-05-04.md#8-指標解釈の注意2026-05-05-追記)).

The actual justification is:

1. **Habit formation**: prompt-to-specialist scoring at dispatch time builds a discipline of "name the right agent before launching", instead of defaulting to general-purpose.
2. **Newly-imported specialists must not sit idle**: 100 active named agents now exist; the router prevents them from being structurally invisible to the orchestrator.
3. **Auditable routing**: every recommendation reduces to a list of matched keywords from `dispatch-table.yml` — no hidden ML, no opaque heuristic.

The empirical 84.1% dispatch rate (1,178 historical `general-purpose` prompts, see [§How it works](#how-it-works)) remains a meaningful coverage indicator and will be re-measured against post-2026-05-04 transcripts in 30 / 90 days.

## Components

| File | Role |
|---|---|
| `.claude/skills/agent-router/SKILL.md` | Skill manifest (description / triggers) |
| `.claude/skills/agent-router/router.py` | Pure-stdlib dispatch implementation (Phase 1) + Claude CLI selector (Phase 2) |
| `.claude/skills/agent-router/dispatch-table.yml` | Single source of truth: keyword → agent |
| `.claude/skills/agent-router/tests/test_router.py` | 48 unit + integration tests (Phase 1: 19, Phase 2: 21, Phase 3+6: 8) |
| `.claude/skills/agent-router/samples/representative_prompts.txt` | Verification fixtures |
| `.claude/hooks/agent-router-suggest.sh` | `UserPromptSubmit` hint injector, wired via `dispatcher-manifest.tsv` (advisory channel) and gated by `feature_agent_router_suggest_enabled` (default ON). Forwards `AGENT_ROUTER_LLM_FALLBACK` to the router |

## How it works

1. **Tokenize** prompt → lowercase, alphanumeric + `-` `_` `.`, drop a small stop-word set.
2. **Match** against keywords in `dispatch-table.yml`:
   - Single-word: O(1) token-set lookup.
   - Multi-word phrases (`"app router"`, `"sql injection"`): word-boundary regex.
3. **Score** = sum of weights per agent + specialty boost when same agent matches multiple keywords.
4. **Confidence** = `min(score / saturation, 1.0)`. Below threshold → `general-purpose` keyword fallback.
5. **Phase 2 Hybrid (optional)**: when `--use-llm-fallback` is on AND keyword confidence < `--llm-threshold` (default 0.5), invoke a Claude CLI selector with the top 30 candidate agents. Up to 3 retries on parse / timeout / unknown-agent. The selector\'s recommendation overrides the keyword fallback when valid; otherwise the keyword result is preserved.
6. **Cycle detection**: same prompt hash dispatched to the same agent twice in a row triggers a forced switch to the next-best alternative. Persists to `~/.claude/agent-router-history.json` (last 100 entries).
7. **Name normalization**: LLM agent names (`Code Reviewer`, `code_reviewer`, etc.) are normalized to canonical names. Unknown names trigger a retry.

Validated against 1,178 real `general-purpose` prompts from the 90-day transcript history — **84.1% routed to a named specialist, 15.9% retained as fallback** (Phase 1, keyword only).

## Design rationale

### Why a skill (not a hook) does the routing

Claude Code does not currently expose a `SubagentStart` PreToolUse event that can rewrite a `subagent_type` argument transparently. PreToolUse can block tool calls but not transparently mutate them in a way the orchestrating model accepts. Consequently:

- **Routing logic** lives in the `agent-router` skill so the main agent can invoke it deterministically before launching `Agent(...)`.
- **A best-effort `UserPromptSubmit` hook** (`agent-router-suggest.sh`) is wired via `dispatcher-manifest.tsv` (gated by `feature_agent_router_suggest_enabled`, default ON) to inject an inline hint (`[agent-router suggestion] ...`) into freshly submitted user prompts. The main agent reads this hint and chooses whether to honor it.
- **No automatic routing** — the orchestrator is always the decision-maker. This preserves auditability and avoids surprising the user.

### Why scoring (not embeddings / ML) for Phase 1

- Stdlib only — runs anywhere Python 3 runs, no network or model dependencies.
- Auditable — each routing decision reduces to a list of matched keywords.
- Trivially extensible — add a YAML line to extend coverage. No retraining.
- Sufficient quality — the empirical 84% dispatch rate beats the 70% target without ML.

### Why a Claude CLI selector for Phase 2

Phase 2 closes the residual ~16% gap (low-confidence prompts that fall back to general-purpose). Inspired by AutoGen `SelectorGroupChat._select_speaker`:

- The selector receives prompt + 30 candidate agents and returns JSON `{"agent", "confidence", "reason"}`.
- We avoid sending all 100 agents (token waste) — top-N keyword candidates are surfaced first, padded with alphabetical samples for breadth.
- Per-call cost cap (`--max-budget-usd 0.05`) and 30s timeout prevent runaway spend.
- Cumulative cost is exposed in the routing result (`llm_cost_usd`) so the harness audit can graph spend.

### Tuning levers

`dispatch-table.yml` exposes three knobs (Phase 1):

| Field | Default | Effect when raised |
|---|---:|---|
| `threshold` | `0.25` | Fewer false-positive specialist routes; more fallback to general-purpose |
| `saturation` | `3.0` | Single keyword hits less confident; multi-keyword prompts more dominant |
| `specialty_boost` | `0.6` | Stronger reward for prompts hitting multiple keywords on the same agent |

`router.py` CLI / env (Phase 2):

| Flag / Env | Default | Effect |
|---|---|---|
| `--use-llm-fallback` / `AGENT_ROUTER_LLM_FALLBACK` | off | Master switch. Off keeps Phase 1 behavior. |
| `--llm-threshold` / `AGENT_ROUTER_LLM_THRESHOLD` | `0.5` | Confidence below which the selector kicks in |
| `--llm-model` / `AGENT_ROUTER_LLM_MODEL` | `claude-haiku-4-5` | Cheap by default; switch to `claude-sonnet-4-6` for harder routing |
| `--llm-timeout` / `AGENT_ROUTER_LLM_TIMEOUT` | `30` | Per-attempt timeout in seconds |
| `--llm-max-attempts` / `AGENT_ROUTER_LLM_MAX_ATTEMPTS` | `3` | Selector retries on parse / timeout / unknown agent |
| `--llm-budget-usd` / `AGENT_ROUTER_LLM_BUDGET_USD` | `0.05` | Per-call cost cap forwarded to `claude -p` |
| `--no-cycle-detection` | off | Disables history read + write |
| `--no-record` | off | Skip writing this dispatch to history (read still happens for cycle detection) |

The current values were chosen by sweeping against the 1,178 historical prompt sample and the 20-prompt representative fixture in `tests/test_router.py`.

## Coordination with the agent archive (144 → 100)

A parallel task archived 44 zero-invocation, low-fit-domain agents to `docs/archive/agents/` (see `docs/draft/agent-router-handoff-2026-05-05.md`). The dispatch table here:

- **Excludes** all 44 archived agents — their typical keywords route to general specialists instead. Examples:
  - `django` / `fastapi` → `python-pro` (django-developer / fastapi-developer archived)
  - `vue` / `angular` → fall back to `frontend-developer` / general-purpose
  - `kotlin` / `swift` / `rust` / `cpp` → no entries; truly unsupported in current ClassLab. stack
- **Anchors on the 100 active agents**. To regenerate the active list:

  ```bash
  find .claude/agents -name "*.md" -type f | sort       | sed \'s|.*/.claude/agents/||; s|\.md$||\'
  ```

When the active set changes, sync the dispatch table by:

1. Adding a keyword line for any new agent.
2. Removing every keyword pointing at any archived agent.
3. Running `python3 -m unittest discover tests -v` from the skill dir.

## Updating the dispatch table

```bash
cd .claude/skills/agent-router

# Inspect what\'s currently routed
python3 router.py --explain "<your-prompt>"

# Try Hybrid mode for low-confidence prompts
AGENT_ROUTER_LLM_FALLBACK=on python3 router.py --explain "<vague prompt>"

# Re-run tests after editing dispatch-table.yml
python3 -m unittest discover tests -v
```

If `python3 -m unittest discover tests -v` fails the `CoverageTests` floor (≥70% of representative prompts route correctly), the dispatch table change has weakened coverage and should be revisited before commit.

## Operational guidance for the main agent

Before launching `Agent(subagent_type="general-purpose", ...)`:

1. If the user explicitly chose `subagent_type`, honor it.
2. Otherwise consult the router:
   ```bash
   python3 .claude/skills/agent-router/router.py --explain "<prompt>"
   ```
3. If `fallback: false` and `confidence >= 0.5`, prefer the recommended agent.
4. If `fallback: true` or low confidence:
   - Phase 1: proceed with `general-purpose`.
   - Phase 2 (with `AGENT_ROUTER_LLM_FALLBACK=on`): the router has already invoked the LLM selector and surfaced the result. If `llm_used: true` and not falling back, prefer the recommended agent.

The `UserPromptSubmit` hook surfaces the same recommendation inline as `[agent-router suggestion] ...`. It is wired via `dispatcher-manifest.tsv` (gated by `feature_agent_router_suggest_enabled`, default ON), so the main agent sees the hint without an explicit CLI call. Disable per-repo with `hc-config.sh --feature agent_router_suggest=false`.

## Phase 2 status (2026-05-05)

**Done**:

- LLM selector implementation (`router.llm_select` + `_invoke_claude_selector`)
- Cycle detection via `~/.claude/agent-router-history.json` (lookback 3, max history 100)
- Name normalization (underscore / space / kebab / case-insensitive / substring fallback)
- 21 new tests covering: high-conf bypass, low-conf invocation, timeout fallback, parse error retries, unknown agent rejection, normalized name acceptance, default-off invariant, code-fence parsing, history persistence, history trim
- Hook (`agent-router-suggest.sh`) forwards `AGENT_ROUTER_LLM_FALLBACK` env to router
- All 40 tests pass; existing 19 keyword tests preserved unchanged in semantics

**Measured**:

| Sample | Mode | Dispatch rate | LLM calls | Cost |
|---|---|---:|---:|---:|
| 1,178 historical (Phase 1 baseline, prior measurement) | keyword | 84.1% | 0 | $0.00 |
| 20 representative prompts | keyword | 100% | 0 | $0.00 |
| 15 synthesized low-/subtle-signal prompts (mock selector) | Hybrid | 100% | 13 | ~$0.012 total |

The 1,178-prompt live re-measurement against the actual `claude -p` selector is gated on cost — once enabled in settings, run `harness-audit.py --router` to collect post-Phase-2 numbers and update this table.

**Known limits**:

- Mock-evaluation only for the historical 188 low-confidence sample. Live measurement requires `AGENT_ROUTER_LLM_FALLBACK=on` enabled in `.claude/settings.json` and at least an hour of actual usage to surface real cost / accuracy.
- `claude-haiku-4-5` is the default selector model; if accuracy is poor, escalate to `claude-sonnet-4-6` via env.
- Cycle detection is keyed on prompt SHA-256 prefix (16 chars). Near-duplicate prompts (different whitespace, single-word edits) are treated as distinct.

## 改善 backlog（残）

### Phase 3: AutoGen 三段 fallback の採用 — **Done (2026-05-05)**

AutoGen の `max_selector_attempts=3` → previous → first participant の三段 fallback を移植済:

- 1 段目: **keyword**（Phase 1）
- 2 段目: **llm** selector（Phase 2、`--use-llm-fallback` で有効）
- 3 段目: **previous** — 同一 prompt hash で直前に dispatch された named agent を継承（context 継承）
- 4 段目: **general-purpose**（最終 fallback）

実装上の決定:

- `RoutingResult.fallback_chain: list[str]` に通過した layer 名が順に積まれる。例: `["keyword", "llm", "previous"]` または `["keyword", "general-purpose"]`。
- `previous` layer は **「LLM が試行されて失敗、かつ keyword 結果も fallback」** のときだけ発火。LLM が成功して named agent を選んだケースでは `previous` は経由しない。
- 直前 dispatch が `general-purpose` だった場合は `previous` を skip して直接 4 段目へ進む（"signal" として無価値なため）。
- `previous` 経由で agent を継承したときは **cycle detection を意図的に skip** する。前回 dispatch をそのまま採用する layer なので、cycle 判定にかけると即座に `general-purpose` に押し戻されてしまう。
- 制御フラグ: `--no-previous-fallback` で 3 段目 layer を無効化可能（CLI / API 双方）。

### Phase 6: dispatch 履歴可観測化 — **Done (2026-05-05)**

#### Phase 6-A: dispatch.jsonl 永続化

router.py が dispatch ごとに 1 行を append（atomic write、temp file → `os.replace`）。出力先:

```
~/.claude/homunculus/projects/<git-remote-sha256[:12]>/dispatch.jsonl
```

各行のスキーマ:

| field | 型 | 説明 |
|---|---|---|
| `ts` | string (ISO8601 UTC) | 書き込み時刻、`Z` suffix |
| `prompt_hash` | string (16 hex) | prompt SHA-256 prefix |
| `dispatched_agent` | string | 最終的に選ばれた agent 名 |
| `fallback_layer` | string | `fallback_chain[-1]` の値（`keyword` / `llm` / `previous` / `general-purpose`） |
| `confidence` | float | 0.0–1.0、`fallback_chain` 末端 layer の confidence |
| `cost_usd` | float | LLM selector が呼ばれた場合の累積 cost、未呼出は 0 |
| `cycle_broken` | bool | cycle detection が発火した場合のみ true |

opt-out:

- `--no-dispatch-log` — append を skip（cycle detection 用 history は別系統で動く）
- `--no-record` — history も dispatch.jsonl も skip

#### Phase 6-B: harness-audit --router

```bash
python3 .claude/scripts/harness-audit.py --router
# あるいは集計のみ JSON で
python3 .claude/scripts/harness-audit.py --router --json
```

出力フィールド:

- total dispatches
- layer 別件数（`keyword` / `llm` / `previous` / `general-purpose`）と share %
- named-agent 起動率（`= 1 - general-purpose 率`）
- 平均 confidence
- 累計 cost (USD)
- cycle-broken events
- top-10 dispatched agents

`--router-homunculus-root <path>` で集計対象 root を上書き可能（テスト / 別 home スキャン用）。

#### Phase 2 で導入した `~/.claude/agent-router-history.json` との分離

- `agent-router-history.json` は cycle detection / previous-fallback 用の **直近 100 件**ローリング（global、project 横断）。
- `dispatch.jsonl` は **無圧縮の長期 telemetry**（project 別、`harness-audit.py` 集計対象）。retention は手動。

### 採用判断の SSoT

全 backlog 項目はまず GitHub Issues に登録し、user / contributor の優先順位投票で順次着手。
