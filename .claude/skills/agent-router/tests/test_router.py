"""Unit tests for agent-router. Standard library only."""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# Make the parent directory importable.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import router  # type: ignore  # noqa: E402

TABLE_PATH = Path(__file__).resolve().parent.parent / "dispatch-table.yml"


def _isolated_history_path() -> Path:
    """Return a per-test history path that lives under a tmp dir so tests
    never touch the user\'s real ~/.claude/agent-router-history.json."""
    tmpdir = Path(tempfile.mkdtemp(prefix="agent-router-test-"))
    return tmpdir / "history.json"


class IsolatedRouteMixin:
    """Mixin that swaps DEFAULT_HISTORY_PATH and disables history recording
    by default for tests that do not explicitly opt in."""

    def setUp(self) -> None:  # type: ignore[override]
        self._history_path = _isolated_history_path()
        # Patch DEFAULT_HISTORY_PATH so any code path that reads it picks up
        # the temp path.
        self._patch = mock.patch.object(router, "DEFAULT_HISTORY_PATH", self._history_path)
        self._patch.start()
        # Phase 6: redirect dispatch.jsonl telemetry away from the real
        # ~/.claude/homunculus tree.
        self._homunculus_root = self._history_path.parent / "homunculus"
        self._homunculus_patch = mock.patch.object(
            router, "DEFAULT_HOMUNCULUS_ROOT", self._homunculus_root
        )
        self._homunculus_patch.start()

    def tearDown(self) -> None:  # type: ignore[override]
        self._homunculus_patch.stop()
        self._patch.stop()
        try:
            self._history_path.unlink(missing_ok=True)
            # Recursive cleanup for the homunculus tree if present.
            import shutil
            if self._homunculus_root.exists():
                shutil.rmtree(self._homunculus_root, ignore_errors=True)
            self._history_path.parent.rmdir()
        except OSError:
            pass


class ParseTableTests(unittest.TestCase):
    def test_parses_real_table(self):
        table = router.load_table(TABLE_PATH)
        self.assertEqual(table.fallback, "general-purpose")
        self.assertGreater(len(table.keywords), 100)
        self.assertGreaterEqual(table.threshold, 0.0)
        self.assertLessEqual(table.threshold, 1.0)
        self.assertGreater(table.saturation, 0.0)

    def test_parses_minimal_inline_yaml(self):
        text = (
            "threshold: 0.5\n"
            "saturation: 4.0\n"
            "specialty_boost: 0.25\n"
            "fallback: general-purpose\n"
            "keywords:\n"
            "  review: code-reviewer\n"
            "  \"code review\": code-reviewer\n"
            "  audit: { agent: security-auditor, weight: 1.5 }\n"
        )
        table = router.parse_dispatch_table(text)
        self.assertEqual(table.threshold, 0.5)
        self.assertEqual(table.saturation, 4.0)
        self.assertEqual(table.specialty_boost, 0.25)
        self.assertEqual(table.fallback, "general-purpose")
        self.assertEqual(table.keywords["review"], ("code-reviewer", 1.0))
        self.assertEqual(table.keywords["code review"], ("code-reviewer", 1.0))
        self.assertEqual(table.keywords["audit"], ("security-auditor", 1.5))

    def test_parser_strips_inline_comments(self):
        text = (
            "fallback: general-purpose  # default fallback\n"
            "keywords:\n"
            "  review: code-reviewer  # quality\n"
        )
        table = router.parse_dispatch_table(text)
        self.assertEqual(table.fallback, "general-purpose")
        self.assertEqual(table.keywords["review"], ("code-reviewer", 1.0))


class TokenizeTests(unittest.TestCase):
    def test_lowercases_and_filters_stop_words(self):
        tokens = router.tokenize("Please REVIEW the API for security issues")
        self.assertIn("review", tokens)
        self.assertIn("api", tokens)
        self.assertIn("security", tokens)
        self.assertNotIn("the", tokens)
        self.assertNotIn("for", tokens)

    def test_keeps_hyphenated_tokens(self):
        tokens = router.tokenize("setup ci-cd via github-actions and run e2e")
        self.assertIn("ci-cd", tokens)
        self.assertIn("github-actions", tokens)
        self.assertIn("e2e", tokens)


class RoutingDispatchTests(IsolatedRouteMixin, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = router.load_table(TABLE_PATH)

    def _route(self, prompt, **kwargs):
        kwargs.setdefault("record_history", False)
        kwargs.setdefault("history_path", self._history_path)
        return router.route(prompt, table=self.table, **kwargs)

    def test_security_review_routes_to_security_auditor(self):
        r = self._route("review the auth module for SQL injection vulnerabilities")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "security-auditor")
        self.assertGreaterEqual(r.confidence, 0.30)

    def test_debug_prompt_routes_to_debugger(self):
        r = self._route("debug the failing payment webhook and trace the exception")
        self.assertFalse(r.fallback)
        # debugger or error-detective both acceptable; debugger should win
        self.assertIn(r.agent, {"debugger", "error-detective"})

    def test_react_component_routes_to_react_specialist(self):
        r = self._route("write a react component with hooks and tsx for the dashboard")
        self.assertFalse(r.fallback)
        self.assertIn(r.agent, {"react-specialist", "frontend-developer", "typescript-pro"})

    def test_terraform_routes_to_terraform_engineer(self):
        r = self._route("write terraform hcl for our aws infrastructure with iac best practices")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "terraform-engineer")

    def test_kubernetes_prompt_routes_to_kubernetes_specialist(self):
        r = self._route("kubectl apply the helm chart and inspect the failing pod logs")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "kubernetes-specialist")

    def test_postgres_query_routes_to_postgres_pro(self):
        r = self._route("optimize this postgres query and add the right index")
        self.assertFalse(r.fallback)
        self.assertIn(r.agent, {"postgres-pro", "database-optimizer", "sql-pro"})

    def test_documentation_prompt_routes_to_docs_engineer(self):
        r = self._route("write a tutorial guide and update the documentation")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "documentation-engineer")

    def test_test_automation_routes_to_test_automator(self):
        r = self._route("add pytest tests with TDD and verify coverage")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "test-automator")

    def test_empty_prompt_returns_fallback(self):
        r = self._route("")
        self.assertTrue(r.fallback)
        self.assertEqual(r.agent, self.table.fallback)

    def test_no_keyword_match_returns_fallback(self):
        r = self._route("zzzzz qqqqq xxxx kkkkk wwwww gibberish yyyyy zzzzz")
        self.assertTrue(r.fallback)
        self.assertEqual(r.agent, self.table.fallback)

    def test_low_confidence_returns_fallback_with_low_threshold_table(self):
        # Build an isolated table with a stricter threshold to verify the
        # fallback path triggers when the top candidate is below it.
        text = (
            "threshold: 0.9\n"
            "saturation: 6.0\n"
            "specialty_boost: 0.5\n"
            "fallback: general-purpose\n"
            "keywords:\n"
            "  slack: slack-expert\n"
        )
        strict_table = router.parse_dispatch_table(text)
        r = router.route(
            "just a quick mention of slack in passing",
            table=strict_table,
            record_history=False,
            history_path=self._history_path,
        )
        self.assertTrue(r.fallback)
        self.assertEqual(r.agent, "general-purpose")

    def test_specialty_boost_applies_when_multiple_keywords_hit(self):
        # "review", "code review" both target code-reviewer → specialty boost
        r = self._route("please do a code review of this PR")
        self.assertFalse(r.fallback)
        self.assertEqual(r.agent, "code-reviewer")
        self.assertGreater(len(r.matched_keywords), 1)

    def test_explain_includes_candidates(self):
        r = self._route("review the code and run tests", explain=True)
        self.assertTrue(r.candidates)
        # Top candidate should match top-level agent
        self.assertEqual(r.candidates[0]["agent"], r.agent)


class CoverageTests(IsolatedRouteMixin, unittest.TestCase):
    """Sanity-check that representative prompts route somewhere reasonable."""

    REPRESENTATIVE = [
        ("review the auth module for security issues", {"security-auditor", "code-reviewer"}),
        ("debug the failing test", {"debugger", "test-automator", "error-detective"}),
        ("dockerize this node service", {"docker-expert", "node-specialist"}),
        ("write a next.js app router page with server components", {"nextjs-developer"}),
        ("optimize the slow postgres query plan", {"postgres-pro", "database-optimizer", "sql-pro"}),
        ("add a stripe payment endpoint", {"payment-integration", "api-designer"}),
        ("write a prd for the new feature", {"product-manager"}),
        ("research competitor pricing pages", {"competitive-analyst", "research-analyst", "market-researcher"}),
        ("set up kubernetes ingress with helm", {"kubernetes-specialist"}),
        ("write tdd unit tests with pytest", {"test-automator"}),
    ]

    @classmethod
    def setUpClass(cls):
        cls.table = router.load_table(TABLE_PATH)

    def test_coverage_routes_at_least_70_percent(self):
        hits = 0
        misses: list[str] = []
        for prompt, expected in self.REPRESENTATIVE:
            r = router.route(
                prompt,
                table=self.table,
                record_history=False,
                history_path=self._history_path,
            )
            if not r.fallback and r.agent in expected:
                hits += 1
            else:
                misses.append(f"{prompt!r} → {r.agent} (fallback={r.fallback})")
        ratio = hits / len(self.REPRESENTATIVE)
        self.assertGreaterEqual(
            ratio,
            0.7,
            msg=f"Only {hits}/{len(self.REPRESENTATIVE)} routed correctly. Misses: {misses}",
        )


# ---------------------------------------------------------------------------
# Phase 2 tests
# ---------------------------------------------------------------------------


class NameNormalizationTests(unittest.TestCase):
    def setUp(self):
        self.known = {
            "code-reviewer", "security-auditor", "test-automator",
            "react-specialist", "general-purpose", "qa-expert",
        }

    def test_exact_match_passes_through(self):
        self.assertEqual(router.normalize_agent_name("code-reviewer", self.known), "code-reviewer")

    def test_underscore_to_hyphen(self):
        self.assertEqual(router.normalize_agent_name("code_reviewer", self.known), "code-reviewer")

    def test_space_to_hyphen(self):
        self.assertEqual(router.normalize_agent_name("Code Reviewer", self.known), "code-reviewer")

    def test_case_insensitive(self):
        self.assertEqual(router.normalize_agent_name("SECURITY-AUDITOR", self.known), "security-auditor")

    def test_quotes_stripped(self):
        self.assertEqual(router.normalize_agent_name('"react-specialist"', self.known), "react-specialist")

    def test_unknown_returns_none(self):
        self.assertIsNone(router.normalize_agent_name("nonexistent-agent", self.known))

    def test_empty_returns_none(self):
        self.assertIsNone(router.normalize_agent_name("", self.known))
        self.assertIsNone(router.normalize_agent_name("   ", self.known))


class CycleDetectionTests(IsolatedRouteMixin, unittest.TestCase):
    def test_cycle_detection_blocks_repeat(self):
        prompt = "review the auth module"
        # Seed history with the same agent
        router.record_dispatch(prompt, "code-reviewer", self._history_path)
        self.assertTrue(
            router.detect_cycle(prompt, "code-reviewer", self._history_path)
        )

    def test_cycle_detection_allows_different_agent(self):
        prompt = "review the auth module"
        router.record_dispatch(prompt, "code-reviewer", self._history_path)
        self.assertFalse(
            router.detect_cycle(prompt, "security-auditor", self._history_path)
        )

    def test_cycle_detection_no_history_returns_false(self):
        self.assertFalse(
            router.detect_cycle("anything", "code-reviewer", self._history_path)
        )

    def test_route_breaks_cycle_to_alternative(self):
        # Pre-populate history with a same-prompt dispatch to security-auditor.
        prompt = "review the auth module for SQL injection"
        router.record_dispatch(prompt, "security-auditor", self._history_path)
        table = router.load_table(TABLE_PATH)
        result = router.route(
            prompt,
            table=table,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertTrue(result.cycle_broken)
        self.assertNotEqual(result.agent, "security-auditor")


class LLMFallbackTests(IsolatedRouteMixin, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.table = router.load_table(TABLE_PATH)

    def test_high_confidence_does_not_call_llm(self):
        """Score 0.6+ → keyword result, LLM not invoked."""
        called = []

        def fake_runner(candidates, prompt_text, timeout):
            called.append(prompt_text)
            return ('{"agent": "test-automator", "confidence": 0.9, "reason": "x"}',
                    {"cost_usd": 0.001})

        # "review the code and audit for security" generates a strong keyword
        # signal — confidence should easily exceed 0.5.
        r = router.route(
            "review the auth module for SQL injection vulnerabilities and security issues",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.5,
            llm_runner=fake_runner,
            history_path=self._history_path,
            record_history=False,
        )
        # If keyword confidence is already high, llm_used must be False.
        if r.confidence >= 0.5:
            self.assertFalse(r.llm_used, msg=f"LLM unexpectedly called: {called!r}")
            self.assertEqual(called, [])

    def test_low_confidence_calls_llm(self):
        """Score < 0.5 → LLM selector is invoked and result honored."""
        invocations = []

        def fake_runner(candidates, prompt_text, timeout):
            invocations.append(prompt_text)
            return ('{"agent": "code-reviewer", "confidence": 0.85, "reason": "matched"}',
                    {"cost_usd": 0.002})

        # A prompt with weak keyword signal: only one matching keyword.
        r = router.route(
            "I would like assistance with my mobile work",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,  # force LLM path
            llm_runner=fake_runner,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertTrue(r.llm_used)
        self.assertEqual(len(invocations), 1)
        self.assertEqual(r.agent, "code-reviewer")
        self.assertGreaterEqual(r.llm_cost_usd, 0.001)

    def test_llm_timeout_falls_back_to_keyword(self):
        def fake_runner(candidates, prompt_text, timeout):
            return (None, {"error": "timeout", "cost_usd": 0.0})

        r = router.route(
            "review the code carefully",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=fake_runner,
            llm_max_attempts=3,
            history_path=self._history_path,
            record_history=False,
        )
        # LLM was tried but failed; result keeps keyword agent and surfaces error.
        self.assertTrue(r.llm_used)
        self.assertEqual(r.llm_attempts, 3)
        self.assertIn("timeout", r.reason)

    def test_llm_invalid_json_retries_then_falls_back(self):
        attempts = {"n": 0}

        def fake_runner(candidates, prompt_text, timeout):
            attempts["n"] += 1
            return ("not-a-json output ¯\\_(ツ)_/¯", {"cost_usd": 0.001})

        r = router.route(
            "build something",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=fake_runner,
            llm_max_attempts=3,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertEqual(attempts["n"], 3)
        self.assertTrue(r.llm_used)
        self.assertEqual(r.llm_attempts, 3)

    def test_llm_unknown_agent_falls_back(self):
        def fake_runner(candidates, prompt_text, timeout):
            return ('{"agent": "made-up-agent-9999", "confidence": 0.9, "reason": "x"}',
                    {"cost_usd": 0.001})

        r = router.route(
            "build something",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=fake_runner,
            llm_max_attempts=3,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertTrue(r.llm_used)
        self.assertEqual(r.llm_attempts, 3)
        self.assertIn("unknown agent", r.reason)

    def test_llm_normalized_agent_name(self):
        """LLM returning 'Code Reviewer' (with spaces) maps to 'code-reviewer'."""
        def fake_runner(candidates, prompt_text, timeout):
            return ('{"agent": "Code Reviewer", "confidence": 0.7, "reason": "x"}',
                    {"cost_usd": 0.001})

        r = router.route(
            "build something",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=fake_runner,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertTrue(r.llm_used)
        self.assertEqual(r.agent, "code-reviewer")

    def test_llm_disabled_by_default(self):
        called = []

        def fake_runner(candidates, prompt_text, timeout):
            called.append(prompt_text)
            return ('{"agent": "code-reviewer", "confidence": 0.9, "reason": "x"}',
                    {"cost_usd": 0.001})

        # use_llm_fallback NOT passed → defaults to False → never invoked.
        router.route(
            "vague prompt with no keyword",
            table=self.table,
            llm_runner=fake_runner,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertEqual(called, [])

    def test_llm_response_with_code_fences_parsed(self):
        def fake_runner(candidates, prompt_text, timeout):
            return ("```json\n" + '{"agent": "code-reviewer", "confidence": 0.8, "reason": "x"}' + "\n```",
                    {"cost_usd": 0.001})

        r = router.route(
            "build something",
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=fake_runner,
            history_path=self._history_path,
            record_history=False,
        )
        self.assertTrue(r.llm_used)
        self.assertEqual(r.agent, "code-reviewer")


class HistoryRecordingTests(IsolatedRouteMixin, unittest.TestCase):
    def test_record_dispatch_persists(self):
        router.record_dispatch("hello", "code-reviewer", self._history_path)
        history = router._load_history(self._history_path)
        self.assertEqual(len(history), 1)
        self.assertEqual(history[0]["dispatched"], "code-reviewer")
        self.assertIn("ts", history[0])
        self.assertIn("prompt_hash", history[0])

    def test_history_trims_at_100(self):
        for i in range(150):
            router.record_dispatch(f"prompt-{i}", "code-reviewer", self._history_path)
        history = router._load_history(self._history_path)
        self.assertEqual(len(history), 100)


# ---------------------------------------------------------------------------
# Phase 3 + Phase 6 tests
# ---------------------------------------------------------------------------


class ThreeStageFallbackTests(IsolatedRouteMixin, unittest.TestCase):
    """Phase 3 — keyword → llm → previous → general-purpose ladder."""

    @classmethod
    def setUpClass(cls):
        cls.table = router.load_table(TABLE_PATH)

    def test_three_stage_fallback_to_previous(self):
        """LLM fails → previous-agent layer kicks in with the prior dispatch."""
        prompt = "totally vague help me out please friend"

        # Seed history: this same prompt previously routed to react-specialist.
        router.record_dispatch(prompt, "react-specialist", self._history_path)

        def failing_runner(_candidates, _prompt_text, _timeout):
            return (None, {"error": "timeout", "cost_usd": 0.0})

        r = router.route(
            prompt,
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=failing_runner,
            llm_max_attempts=2,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=False,
        )
        self.assertEqual(r.agent, "react-specialist")
        self.assertFalse(r.fallback)
        self.assertIn("previous", r.fallback_chain)
        # Order: keyword → llm → previous
        self.assertEqual(r.fallback_chain[:3], ["keyword", "llm", "previous"])
        self.assertNotIn("general-purpose", r.fallback_chain)

    def test_previous_skipped_if_general(self):
        """Previous dispatch == general-purpose ⇒ skip 3rd layer, land at 4th."""
        prompt = "vague question with no keyword signal at all qqxx"

        # Seed history with general-purpose itself — the previous-layer should
        # treat that as "no signal" and skip directly to general-purpose.
        router.record_dispatch(prompt, self.table.fallback, self._history_path)

        def failing_runner(_candidates, _prompt_text, _timeout):
            return (None, {"error": "no candidate", "cost_usd": 0.0})

        r = router.route(
            prompt,
            table=self.table,
            use_llm_fallback=True,
            llm_threshold=0.99,
            llm_runner=failing_runner,
            llm_max_attempts=2,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=False,
        )
        self.assertEqual(r.agent, self.table.fallback)
        self.assertTrue(r.fallback)
        # previous layer must NOT appear; chain ends at general-purpose.
        self.assertNotIn("previous", r.fallback_chain)
        self.assertEqual(r.fallback_chain[-1], "general-purpose")

    def test_fallback_chain_keyword_only_for_high_conf(self):
        """High-confidence keyword route must report only the keyword layer."""
        r = router.route(
            "review the auth module for SQL injection vulnerabilities and security",
            table=self.table,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=False,
        )
        self.assertFalse(r.fallback)
        self.assertEqual(r.fallback_chain, ["keyword"])

    def test_fallback_chain_includes_general_when_no_keyword(self):
        """No keyword + LLM disabled → chain is keyword → general-purpose."""
        r = router.route(
            "zzzzz qqqqq xxxx kkkkk wwwww gibberish yyyyy zzzzz",
            table=self.table,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=False,
        )
        self.assertTrue(r.fallback)
        self.assertEqual(r.fallback_chain, ["keyword", "general-purpose"])


class DispatchLogTests(IsolatedRouteMixin, unittest.TestCase):
    """Phase 6-A — dispatch.jsonl telemetry."""

    @classmethod
    def setUpClass(cls):
        cls.table = router.load_table(TABLE_PATH)

    def _read_log(self):
        log_path = router.dispatch_log_path(self._homunculus_root)
        if not log_path.exists():
            return []
        out = []
        for line in log_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            out.append(json.loads(line))
        return out

    def test_dispatch_jsonl_appended(self):
        router.route(
            "review the auth module for SQL injection",
            table=self.table,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=True,
            homunculus_root=self._homunculus_root,
        )
        rows = self._read_log()
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertIn("ts", row)
        self.assertIn("prompt_hash", row)
        self.assertIn("dispatched_agent", row)
        self.assertIn("fallback_layer", row)
        self.assertIn("confidence", row)
        self.assertIn("cost_usd", row)
        self.assertIn("cycle_broken", row)
        self.assertEqual(row["dispatched_agent"], "security-auditor")
        # Fallback layer for a clean keyword hit must be "keyword".
        self.assertEqual(row["fallback_layer"], "keyword")

    def test_dispatch_jsonl_atomic(self):
        """Atomic append: even if the existing file is partially written, the
        next call must produce a clean, fully-parseable JSONL."""
        log_path = router.dispatch_log_path(self._homunculus_root)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        # Simulate a corrupted partial-write from a crashed process.
        log_path.write_text("{\"partial\": tru", encoding="utf-8")

        router.append_dispatch_log(
            log_path,
            prompt="hello",
            dispatched_agent="code-reviewer",
            fallback_layer="keyword",
            confidence=0.7,
            cost_usd=0.0,
        )
        # Final file must end with a newline and last line must parse.
        text = log_path.read_text(encoding="utf-8")
        self.assertTrue(text.endswith("\n"))
        last_line = [ln for ln in text.splitlines() if ln.strip()][-1]
        record = json.loads(last_line)
        self.assertEqual(record["dispatched_agent"], "code-reviewer")
        self.assertEqual(record["fallback_layer"], "keyword")
        # No partial temp files left around.
        leftovers = list(log_path.parent.glob("dispatch.jsonl.tmp.*"))
        self.assertEqual(leftovers, [])

    def test_dispatch_jsonl_skipped_when_no_record(self):
        router.route(
            "review the auth module for security",
            table=self.table,
            history_path=self._history_path,
            record_history=False,
            record_dispatch_log=False,
            homunculus_root=self._homunculus_root,
        )
        log_path = router.dispatch_log_path(self._homunculus_root)
        self.assertFalse(log_path.exists())


class HarnessAuditRouterIntegrationTests(unittest.TestCase):
    """Phase 6-B — `harness-audit.py --router` output schema."""

    def test_router_subcommand_runs_against_temp_log(self):
        import subprocess
        import tempfile

        scripts = (
            Path(__file__).resolve().parents[3]
            / "scripts" / "harness-audit.py"
        )
        if not scripts.exists():
            self.skipTest(f"harness-audit.py not found at {scripts}")

        # Build a synthetic dispatch.jsonl under a tmp homunculus root.
        with tempfile.TemporaryDirectory() as td:
            home = Path(td)
            project_dir = home / "projects" / "synthetic-test"
            project_dir.mkdir(parents=True)
            log = project_dir / "dispatch.jsonl"
            rows = [
                {
                    "ts": "2026-05-05T01:02:03Z",
                    "prompt_hash": "abc",
                    "dispatched_agent": "code-reviewer",
                    "fallback_layer": "keyword",
                    "confidence": 0.71,
                    "cost_usd": 0.0,
                    "cycle_broken": False,
                },
                {
                    "ts": "2026-05-05T01:02:04Z",
                    "prompt_hash": "def",
                    "dispatched_agent": "security-auditor",
                    "fallback_layer": "llm",
                    "confidence": 0.65,
                    "cost_usd": 0.002,
                    "cycle_broken": False,
                },
                {
                    "ts": "2026-05-05T01:02:05Z",
                    "prompt_hash": "ghi",
                    "dispatched_agent": "general-purpose",
                    "fallback_layer": "general-purpose",
                    "confidence": 0.0,
                    "cost_usd": 0.0,
                    "cycle_broken": False,
                },
            ]
            log.write_text(
                "\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n",
                encoding="utf-8",
            )

            # Invoke the subcommand with the synthetic root.
            proc = subprocess.run(
                [
                    sys.executable, str(scripts),
                    "--router",
                    "--router-homunculus-root", str(home),
                ],
                capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            out = proc.stdout

            # Schema spot-checks.
            self.assertIn("Router Dispatch Audit", out)
            self.assertIn("total dispatches", out.lower())
            self.assertIn("keyword", out)
            self.assertIn("llm", out)
            self.assertIn("general-purpose", out)
            self.assertIn("named-agent rate", out.lower())



if __name__ == "__main__":
    unittest.main()
