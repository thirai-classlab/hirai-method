#!/usr/bin/env python3
"""agent-router/router.py — Route a prompt to the most relevant named subagent.

Reads dispatch-table.yml (single source of truth, alongside this script) and
returns a JSON blob describing the recommended agent, its confidence score,
matched keywords, and whether the recommendation is a fallback.

Standard library only. No external YAML parser dependency — uses a small
purpose-built parser for the constrained subset of YAML the table uses.

Phase 2 (Hybrid mode):
  When --use-llm-fallback is on AND keyword confidence < --llm-threshold,
  the router invokes a Claude CLI selector to score candidate agents in
  natural language. Failure modes (timeout / parse / unknown agent) fall
  back to the keyword result. Cycle detection prevents A→A→A loops.

Usage:
    python3 router.py "review the auth module for SQL injection"
    python3 router.py --explain "<prompt>"           # include per-agent breakdown
    python3 router.py --use-llm-fallback "<prompt>"  # Hybrid mode
    python3 router.py --use-llm-fallback --llm-threshold 0.6 "<prompt>"

Exit codes:
    0  — JSON result on stdout (always emitted)
    2  — internal error (table missing / unparseable). JSON err on stdout
         and human message on stderr. Caller should fall back to
         general-purpose.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

DEFAULT_TABLE = Path(__file__).resolve().parent / "dispatch-table.yml"

# Lightweight stop-word list — keep small to avoid filtering domain terms.
STOP_WORDS = {
    "the", "a", "an", "and", "or", "but", "if", "then", "for", "to", "of",
    "in", "on", "with", "by", "at", "from", "as", "is", "are", "was", "were",
    "be", "been", "being", "have", "has", "had", "do", "does", "did",
    "will", "would", "shall", "should", "can", "could", "may", "might",
    "must", "this", "that", "these", "those", "it", "its", "i", "you",
    "we", "they", "me", "my", "our", "your", "their", "what", "which",
    "who", "when", "where", "why", "how", "please", "pls", "thanks",
    "thank", "ok", "now", "also",
}

# Token regex: lowercase alnum + - + _ + .
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9._\-]*")

# Phase 2 constants
DEFAULT_LLM_THRESHOLD = 0.5
DEFAULT_LLM_MODEL = "claude-haiku-4-5"
DEFAULT_LLM_TIMEOUT = 30  # seconds
DEFAULT_LLM_MAX_ATTEMPTS = 3
DEFAULT_LLM_BUDGET_USD = 0.05
DEFAULT_HISTORY_PATH = Path.home() / ".claude" / "agent-router-history.json"
DEFAULT_HISTORY_LOOKBACK = 3


@dataclass
class RoutingResult:
    agent: str
    confidence: float
    reason: str
    fallback: bool
    matched_keywords: list[str] = field(default_factory=list)
    candidates: list[dict] = field(default_factory=list)
    # Phase 2 fields — present only when LLM selector is used.
    llm_used: bool = False
    llm_attempts: int = 0
    llm_cost_usd: float = 0.0
    cycle_broken: bool = False

    def to_json(self) -> str:
        d = asdict(self)
        # Always include core fields; strip empty / default optional fields.
        if not d["candidates"]:
            d.pop("candidates", None)
        if not d["llm_used"]:
            d.pop("llm_used", None)
            d.pop("llm_attempts", None)
            d.pop("llm_cost_usd", None)
        if not d["cycle_broken"]:
            d.pop("cycle_broken", None)
        return json.dumps(d, ensure_ascii=False)


@dataclass
class DispatchTable:
    threshold: float
    saturation: float
    specialty_boost: float
    fallback: str
    # keyword -> (agent_name, weight). Multi-word phrases also live here.
    keywords: dict[str, tuple[str, float]]

    @property
    def single_word_keywords(self) -> dict[str, tuple[str, float]]:
        return {k: v for k, v in self.keywords.items() if " " not in k}

    @property
    def phrase_keywords(self) -> dict[str, tuple[str, float]]:
        return {k: v for k, v in self.keywords.items() if " " in k}

    @property
    def known_agents(self) -> set[str]:
        return {agent for agent, _ in self.keywords.values()} | {self.fallback}


def _strip_inline_comment(value: str) -> str:
    """Strip ' # ...' inline comments while respecting quoted strings."""
    in_str = False
    quote = ""
    out_chars = []
    i = 0
    while i < len(value):
        ch = value[i]
        if in_str:
            if ch == quote:
                in_str = False
            out_chars.append(ch)
        else:
            if ch in ("\"", "\'"):
                in_str = True
                quote = ch
                out_chars.append(ch)
            elif ch == "#" and (i == 0 or value[i - 1].isspace()):
                break
            else:
                out_chars.append(ch)
        i += 1
    return "".join(out_chars).rstrip()


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("\"", "\'"):
        return value[1:-1]
    return value


def parse_dispatch_table(text: str) -> DispatchTable:
    """Parse the constrained YAML subset used by dispatch-table.yml.

    Supports:
      - top-level scalar fields: threshold, saturation, specialty_boost, fallback
      - top-level "keywords:" mapping with two value forms:
          <keyword>: <agent_name>
          <keyword>: { agent: <name>, weight: <float> }
      - quoted keys ("multi word"), single or double
      - "# ..." comments (full line or trailing)
    """
    threshold = 0.30
    saturation = 6.0
    specialty_boost = 0.5
    fallback = "general-purpose"
    keywords: dict[str, tuple[str, float]] = {}

    in_keywords = False
    for raw_line in text.splitlines():
        line = _strip_inline_comment(raw_line)
        stripped = line.strip()
        if not stripped:
            continue
        if not raw_line.startswith((" ", "\t")):
            # top-level
            in_keywords = False
            if ":" not in stripped:
                continue
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if key == "keywords":
                in_keywords = True
                continue
            if key == "threshold":
                threshold = float(value)
            elif key == "saturation":
                saturation = float(value)
            elif key == "specialty_boost":
                specialty_boost = float(value)
            elif key == "fallback":
                fallback = _unquote(value)
        elif in_keywords:
            if ":" not in stripped:
                continue
            key_raw, _, value = stripped.partition(":")
            key = _unquote(key_raw.strip()).lower()
            value = value.strip()
            if value.startswith("{") and value.endswith("}"):
                inner = value[1:-1]
                agent_name = ""
                weight = 1.0
                for part in inner.split(","):
                    if ":" not in part:
                        continue
                    k2, _, v2 = part.partition(":")
                    k2 = k2.strip()
                    v2 = _unquote(v2.strip())
                    if k2 == "agent":
                        agent_name = v2
                    elif k2 == "weight":
                        try:
                            weight = float(v2)
                        except ValueError:
                            weight = 1.0
                if agent_name:
                    keywords[key] = (agent_name, weight)
            else:
                agent_name = _unquote(value)
                if agent_name:
                    keywords[key] = (agent_name, 1.0)

    return DispatchTable(
        threshold=threshold,
        saturation=saturation,
        specialty_boost=specialty_boost,
        fallback=fallback,
        keywords=keywords,
    )


def load_table(path: Path | None = None) -> DispatchTable:
    p = Path(path) if path else DEFAULT_TABLE
    if not p.exists():
        raise FileNotFoundError(f"dispatch table not found: {p}")
    return parse_dispatch_table(p.read_text(encoding="utf-8"))


def tokenize(prompt: str) -> list[str]:
    lowered = prompt.lower()
    return [t for t in TOKEN_RE.findall(lowered) if t not in STOP_WORDS and len(t) >= 2]


def _word_boundary_phrase_search(prompt_lower: str, phrase: str) -> bool:
    """Match a multi-word phrase on word boundaries (case-insensitive)."""
    pattern = r"\b" + re.escape(phrase) + r"\b"
    return re.search(pattern, prompt_lower) is not None


def score_prompt(prompt: str, table: DispatchTable) -> tuple[dict[str, float], dict[str, list[str]]]:
    """Return (agent -> raw score, agent -> matched keywords)."""
    tokens = set(tokenize(prompt))
    prompt_lower = prompt.lower()

    scores: dict[str, float] = defaultdict(float)
    matches: dict[str, list[str]] = defaultdict(list)
    hit_counts: dict[str, int] = defaultdict(int)

    # Single-word keywords: token-set lookup.
    for kw, (agent, weight) in table.single_word_keywords.items():
        if kw in tokens:
            scores[agent] += weight
            matches[agent].append(kw)
            hit_counts[agent] += 1

    # Multi-word phrases: regex word-boundary search.
    for kw, (agent, weight) in table.phrase_keywords.items():
        if _word_boundary_phrase_search(prompt_lower, kw):
            scores[agent] += weight
            matches[agent].append(kw)
            hit_counts[agent] += 1

    # Specialty boost — adds (hits-1) * specialty_boost to encourage agents
    # that match multiple distinct keywords (signal > noise).
    for agent, hits in hit_counts.items():
        if hits > 1:
            scores[agent] += (hits - 1) * table.specialty_boost

    return dict(scores), {a: sorted(set(m)) for a, m in matches.items()}


# ---------------------------------------------------------------------------
# Phase 2: Name normalization (CrewAI #1823 mitigation)
# ---------------------------------------------------------------------------

def normalize_agent_name(raw: str, known_agents: set[str]) -> str | None:
    """Map a free-form agent name returned by the LLM to a known agent.

    Tries, in order:
      1. Exact match (case-insensitive).
      2. Normalized form: lowercase, hyphens / spaces / underscores collapsed
         to a single hyphen.
      3. Substring match against known agents (longest first).

    Returns None when no candidate matches.
    """
    if not raw:
        return None
    raw_clean = raw.strip().strip("\"\'")
    if not raw_clean:
        return None

    def _norm(s: str) -> str:
        s = s.strip().lower()
        s = re.sub(r"[\s_]+", "-", s)
        s = re.sub(r"-+", "-", s)
        return s.strip("-")

    target = _norm(raw_clean)

    # 1. Build normalized → canonical map for known agents.
    canon_map: dict[str, str] = {}
    for agent in known_agents:
        canon_map[_norm(agent)] = agent

    if target in canon_map:
        return canon_map[target]

    # 2. Substring containment (prefer longest known agent name first).
    sorted_known = sorted(known_agents, key=lambda a: -len(a))
    for agent in sorted_known:
        agent_norm = _norm(agent)
        if not agent_norm:
            continue
        if agent_norm in target or target in agent_norm:
            # Avoid unintentionally matching extremely short normalized names
            # (e.g. "qa" inside "qa-expert"); require ≥4 chars on the matched
            # side.
            shorter = min(len(agent_norm), len(target))
            if shorter >= 4:
                return agent

    return None


# ---------------------------------------------------------------------------
# Phase 2: LLM selector
# ---------------------------------------------------------------------------

SELECTOR_PROMPT_TEMPLATE = """\
あなたは agent dispatcher です。以下の user prompt に対し、最適な named agent を 1 つ選択してください。

# user prompt
{prompt}

# 候補 agents（最大 30 件）
{candidate_list}

# 出力フォーマット（JSON のみ、他テキスト禁止）
{{"agent": "<agent_name>", "confidence": 0.0-1.0, "reason": "<200 字以内の理由>"}}

候補に該当なしなら: {{"agent": "general-purpose", "confidence": 0.3, "reason": "no specialty match"}}
"""


def build_candidate_list(
    table: DispatchTable,
    keyword_scores: dict[str, float],
    max_candidates: int = 30,
) -> list[str]:
    """Return up to max_candidates agent names to surface to the LLM selector.

    Strategy: top-N keyword candidates first, then a sample of other known
    agents to give the selector breadth without blowing token budget.
    """
    seen: list[str] = []
    seen_set: set[str] = set()

    # Keyword-ranked candidates first.
    ranked = sorted(keyword_scores.items(), key=lambda kv: kv[1], reverse=True)
    for agent, _score in ranked:
        if agent not in seen_set:
            seen.append(agent)
            seen_set.add(agent)
        if len(seen) >= max_candidates:
            return seen

    # Fill with other known agents (sorted alphabetically for determinism).
    for agent in sorted(table.known_agents):
        if agent not in seen_set:
            seen.append(agent)
            seen_set.add(agent)
        if len(seen) >= max_candidates:
            break

    return seen


def _invoke_claude_selector(
    prompt: str,
    candidate_list: list[str],
    *,
    model: str,
    timeout: int,
    max_budget_usd: float,
    runner=None,
) -> tuple[str | None, dict]:
    """Run the Claude CLI selector once. Returns (raw_response_text, meta).

    `runner` is an optional injection point for unit tests. When supplied it
    is called as runner(candidate_list, selector_prompt, timeout) and must
    return (text, meta).
    """
    selector_prompt = SELECTOR_PROMPT_TEMPLATE.format(
        prompt=prompt.strip(),
        candidate_list="\n".join(f"- {name}" for name in candidate_list),
    )

    if runner is not None:
        return runner(candidate_list, selector_prompt, timeout)

    cmd = [
        "claude", "-p",
        "--model", model,
        "--output-format", "json",
        "--input-format", "text",
        "--max-budget-usd", str(max_budget_usd),
        "--no-session-persistence",
        "--permission-mode", "bypassPermissions",
        "--disallowedTools", "Bash,Edit,Write,Read,Grep,Glob,WebSearch,WebFetch,Task",
    ]

    try:
        proc = subprocess.run(
            cmd,
            input=selector_prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired:
        return None, {"error": "timeout", "cost_usd": 0.0}
    except FileNotFoundError:
        return None, {"error": "claude CLI not found", "cost_usd": 0.0}

    raw = proc.stdout or ""
    meta: dict = {"cost_usd": 0.0, "duration_ms": 0, "rc": proc.returncode}
    text_response: str | None = raw

    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            text_response = parsed.get("result") or parsed.get("text") or raw
            usage = parsed.get("usage") or {}
            meta["cost_usd"] = float(parsed.get("total_cost_usd") or usage.get("total_cost_usd") or 0.0)
            meta["duration_ms"] = int(parsed.get("duration_ms") or 0)
    except json.JSONDecodeError:
        pass

    if proc.returncode != 0:
        meta["error"] = (proc.stderr or "")[:500]
        return None, meta
    return text_response, meta


def _parse_selector_response(text: str | None) -> dict | None:
    """Parse the selector's JSON output. Returns None on any failure."""
    if not text:
        return None
    s = text.strip()
    # The model may wrap in ```json fences; strip them.
    if s.startswith("```"):
        s = re.sub(r"^```(?:json)?\s*", "", s)
        s = re.sub(r"\s*```\s*$", "", s)
    # Take the first {...} JSON object encountered.
    match = re.search(r"\{.*?\}", s, re.DOTALL)
    if not match:
        return None
    try:
        obj = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    return obj


def llm_select(
    prompt: str,
    table: DispatchTable,
    keyword_scores: dict[str, float],
    *,
    model: str = DEFAULT_LLM_MODEL,
    timeout: int = DEFAULT_LLM_TIMEOUT,
    max_attempts: int = DEFAULT_LLM_MAX_ATTEMPTS,
    max_budget_usd: float = DEFAULT_LLM_BUDGET_USD,
    runner=None,
) -> tuple[dict | None, dict]:
    """Invoke the selector with up to max_attempts retries.

    Returns (parsed_dict_or_None, meta) where meta carries:
      - attempts: int
      - cost_usd: float (cumulative)
      - error: str | None (last error)
    """
    candidates = build_candidate_list(table, keyword_scores)
    cumulative_cost = 0.0
    last_error: str | None = None
    attempts = 0

    for attempt in range(1, max_attempts + 1):
        attempts = attempt
        text, meta = _invoke_claude_selector(
            prompt,
            candidates,
            model=model,
            timeout=timeout,
            max_budget_usd=max_budget_usd,
            runner=runner,
        )
        cumulative_cost += float(meta.get("cost_usd", 0.0) or 0.0)
        if "error" in meta and meta["error"]:
            last_error = str(meta["error"])
        parsed = _parse_selector_response(text)
        if parsed is None:
            continue

        raw_agent = parsed.get("agent", "")
        normalized = normalize_agent_name(raw_agent, table.known_agents)
        if not normalized:
            last_error = f"unknown agent in selector output: {raw_agent!r}"
            continue

        try:
            confidence = float(parsed.get("confidence", 0.0))
        except (TypeError, ValueError):
            confidence = 0.0
        confidence = max(0.0, min(1.0, confidence))

        reason = str(parsed.get("reason") or "selector recommendation")[:200]

        return (
            {
                "agent": normalized,
                "confidence": confidence,
                "reason": reason,
                "raw_agent": raw_agent,
            },
            {"attempts": attempts, "cost_usd": cumulative_cost, "error": None},
        )

    return None, {"attempts": attempts, "cost_usd": cumulative_cost, "error": last_error}


# ---------------------------------------------------------------------------
# Phase 2: Cycle detection
# ---------------------------------------------------------------------------

def _hash_prompt(prompt: str) -> str:
    return hashlib.sha256(prompt.strip().encode("utf-8")).hexdigest()[:16]


def _load_history(path: Path) -> list[dict]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return data
    except (json.JSONDecodeError, OSError):
        pass
    return []


def _save_history(path: Path, entries: list[dict]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        # Trim to a reasonable size (last 100 entries).
        path.write_text(json.dumps(entries[-100:], ensure_ascii=False), encoding="utf-8")
    except OSError:
        # History persistence is best-effort; never fail routing because of it.
        pass


def detect_cycle(
    prompt: str,
    candidate_agent: str,
    history_path: Path,
    lookback: int = DEFAULT_HISTORY_LOOKBACK,
) -> bool:
    """Return True when dispatching candidate_agent for this prompt would
    repeat the most recent dispatch on the same prompt hash.
    """
    history = _load_history(history_path)
    if not history:
        return False
    prompt_hash = _hash_prompt(prompt)
    recent = [e for e in history[-lookback:] if e.get("prompt_hash") == prompt_hash]
    if not recent:
        return False
    last_same_prompt = recent[-1]
    return last_same_prompt.get("dispatched") == candidate_agent


def record_dispatch(
    prompt: str,
    dispatched_agent: str,
    history_path: Path,
) -> None:
    history = _load_history(history_path)
    history.append({
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "prompt_hash": _hash_prompt(prompt),
        "dispatched": dispatched_agent,
    })
    _save_history(history_path, history)


def pick_alternative_agent(
    blocked_agent: str,
    keyword_scores: dict[str, float],
    fallback: str,
) -> str:
    """Return the next-best agent that is not blocked_agent."""
    ranked = sorted(keyword_scores.items(), key=lambda kv: kv[1], reverse=True)
    for agent, _score in ranked:
        if agent != blocked_agent:
            return agent
    return fallback


# ---------------------------------------------------------------------------
# Routing entry point
# ---------------------------------------------------------------------------

def route(
    prompt: str,
    table: DispatchTable | None = None,
    table_path: Path | None = None,
    explain: bool = False,
    *,
    use_llm_fallback: bool = False,
    llm_threshold: float = DEFAULT_LLM_THRESHOLD,
    llm_model: str = DEFAULT_LLM_MODEL,
    llm_timeout: int = DEFAULT_LLM_TIMEOUT,
    llm_max_attempts: int = DEFAULT_LLM_MAX_ATTEMPTS,
    llm_budget_usd: float = DEFAULT_LLM_BUDGET_USD,
    llm_runner=None,
    enable_cycle_detection: bool = True,
    history_path: Path | None = None,
    record_history: bool = True,
) -> RoutingResult:
    if table is None:
        table = load_table(table_path)

    if not prompt or not prompt.strip():
        return RoutingResult(
            agent=table.fallback,
            confidence=0.0,
            reason="empty prompt",
            fallback=True,
        )

    history_path = history_path or DEFAULT_HISTORY_PATH

    scores, matches = score_prompt(prompt, table)

    if not scores:
        # No keyword hit at all. LLM fallback (if on) is our only chance.
        keyword_result = RoutingResult(
            agent=table.fallback,
            confidence=0.0,
            reason="no keyword matched",
            fallback=True,
        )
    else:
        ranked = sorted(
            scores.items(),
            key=lambda kv: (kv[1], len(matches.get(kv[0], []))),
            reverse=True,
        )
        top_agent, top_score = ranked[0]
        confidence = min(top_score / table.saturation, 1.0)
        if confidence < table.threshold:
            keyword_result = RoutingResult(
                agent=table.fallback,
                confidence=round(confidence, 3),
                reason=(
                    f"top candidate {top_agent} (score {round(top_score, 2)}) "
                    f"under threshold {table.threshold}"
                ),
                fallback=True,
                matched_keywords=matches.get(top_agent, []),
                candidates=_explain_candidates(ranked, matches, table) if explain else [],
            )
        else:
            keyword_result = RoutingResult(
                agent=top_agent,
                confidence=round(confidence, 3),
                reason="matched: " + ", ".join(matches.get(top_agent, [])),
                fallback=False,
                matched_keywords=matches.get(top_agent, []),
                candidates=_explain_candidates(ranked, matches, table) if explain else [],
            )

    # ---- Decide whether to invoke LLM selector ----------------------------
    final = keyword_result

    if use_llm_fallback and keyword_result.confidence < llm_threshold:
        parsed, meta = llm_select(
            prompt,
            table,
            scores,
            model=llm_model,
            timeout=llm_timeout,
            max_attempts=llm_max_attempts,
            max_budget_usd=llm_budget_usd,
            runner=llm_runner,
        )
        attempts = int(meta.get("attempts", 0))
        cost_usd = float(meta.get("cost_usd", 0.0))
        if parsed is not None:
            final = RoutingResult(
                agent=parsed["agent"],
                confidence=round(parsed["confidence"], 3),
                reason=f"llm-selector: {parsed['reason']}",
                fallback=parsed["agent"] == table.fallback,
                matched_keywords=keyword_result.matched_keywords,
                candidates=keyword_result.candidates,
                llm_used=True,
                llm_attempts=attempts,
                llm_cost_usd=round(cost_usd, 6),
            )
        else:
            # All LLM attempts failed; keep keyword result but record the
            # attempt count + cost so callers can audit.
            final = RoutingResult(
                agent=keyword_result.agent,
                confidence=keyword_result.confidence,
                reason=(
                    keyword_result.reason
                    + f" | llm-selector failed after {attempts} attempts: "
                    + str(meta.get("error") or "unknown error")
                ),
                fallback=keyword_result.fallback,
                matched_keywords=keyword_result.matched_keywords,
                candidates=keyword_result.candidates,
                llm_used=True,
                llm_attempts=attempts,
                llm_cost_usd=round(cost_usd, 6),
            )

    # ---- Cycle detection --------------------------------------------------
    if enable_cycle_detection and not final.fallback:
        if detect_cycle(prompt, final.agent, history_path):
            alt = pick_alternative_agent(final.agent, scores, table.fallback)
            if alt != final.agent:
                final = RoutingResult(
                    agent=alt,
                    confidence=final.confidence,
                    reason=f"cycle-broken: {final.agent} repeated; routed to {alt}. {final.reason}",
                    fallback=alt == table.fallback,
                    matched_keywords=final.matched_keywords,
                    candidates=final.candidates,
                    llm_used=final.llm_used,
                    llm_attempts=final.llm_attempts,
                    llm_cost_usd=final.llm_cost_usd,
                    cycle_broken=True,
                )

    if record_history:
        record_dispatch(prompt, final.agent, history_path)

    return final


def _explain_candidates(
    ranked: Iterable[tuple[str, float]],
    matches: dict[str, list[str]],
    table: DispatchTable,
) -> list[dict]:
    out = []
    for agent, score in list(ranked)[:5]:
        out.append({
            "agent": agent,
            "score": round(score, 3),
            "confidence": round(min(score / table.saturation, 1.0), 3),
            "matched": matches.get(agent, []),
        })
    return out


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _env_truthy(name: str) -> bool:
    val = os.environ.get(name, "").strip().lower()
    return val in {"1", "true", "yes", "on"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Route a prompt to a named agent")
    parser.add_argument("prompt", nargs="*", help="Prompt text (joined with spaces)")
    parser.add_argument("--table", default=None, help="Override dispatch table path")
    parser.add_argument("--explain", action="store_true", help="Include candidate breakdown")
    parser.add_argument("--stdin", action="store_true", help="Read prompt from stdin")
    parser.add_argument(
        "--use-llm-fallback",
        action="store_true",
        default=_env_truthy("AGENT_ROUTER_LLM_FALLBACK"),
        help=(
            "Invoke a Claude CLI selector when keyword confidence < --llm-threshold. "
            "Default: off (env AGENT_ROUTER_LLM_FALLBACK=on enables)."
        ),
    )
    parser.add_argument(
        "--llm-threshold",
        type=float,
        default=float(os.environ.get("AGENT_ROUTER_LLM_THRESHOLD", DEFAULT_LLM_THRESHOLD)),
        help="Confidence below which the LLM selector kicks in (default: 0.5)",
    )
    parser.add_argument(
        "--llm-model",
        default=os.environ.get("AGENT_ROUTER_LLM_MODEL", DEFAULT_LLM_MODEL),
        help=f"Claude model used by the selector (default: {DEFAULT_LLM_MODEL})",
    )
    parser.add_argument(
        "--llm-timeout",
        type=int,
        default=int(os.environ.get("AGENT_ROUTER_LLM_TIMEOUT", DEFAULT_LLM_TIMEOUT)),
        help="Per-attempt timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "--llm-max-attempts",
        type=int,
        default=int(os.environ.get("AGENT_ROUTER_LLM_MAX_ATTEMPTS", DEFAULT_LLM_MAX_ATTEMPTS)),
        help="Max selector retries on parse / timeout / unknown agent (default: 3)",
    )
    parser.add_argument(
        "--llm-budget-usd",
        type=float,
        default=float(os.environ.get("AGENT_ROUTER_LLM_BUDGET_USD", DEFAULT_LLM_BUDGET_USD)),
        help="Per-call cost cap for the selector (default: 0.05 USD)",
    )
    parser.add_argument(
        "--no-cycle-detection",
        action="store_true",
        help="Disable cycle detection / history recording",
    )
    parser.add_argument(
        "--no-record",
        action="store_true",
        help="Skip writing the dispatch result to history (cycle detection still reads)",
    )
    args = parser.parse_args(argv)

    if args.stdin:
        prompt = sys.stdin.read()
    else:
        prompt = " ".join(args.prompt)

    try:
        result = route(
            prompt,
            table_path=Path(args.table) if args.table else None,
            explain=args.explain,
            use_llm_fallback=args.use_llm_fallback,
            llm_threshold=args.llm_threshold,
            llm_model=args.llm_model,
            llm_timeout=args.llm_timeout,
            llm_max_attempts=args.llm_max_attempts,
            llm_budget_usd=args.llm_budget_usd,
            enable_cycle_detection=not args.no_cycle_detection,
            record_history=not (args.no_record or args.no_cycle_detection),
        )
    except FileNotFoundError as exc:
        print(json.dumps({"error": str(exc), "agent": "general-purpose", "fallback": True}), flush=True)
        print(f"agent-router: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # pragma: no cover - defensive
        print(json.dumps({"error": repr(exc), "agent": "general-purpose", "fallback": True}), flush=True)
        print(f"agent-router internal error: {exc}", file=sys.stderr)
        return 2

    print(result.to_json(), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
