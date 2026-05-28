/**
 * Tests for src/posting/auto-tag.ts — Phase 8 Wave E2
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e2/plan.md §テスト観点 (auto-tag.test.ts) (10 cases)
 *
 * Scope: pure prompt builder + JSON parser + Haiku extraction (mocked).
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

// Haiku I/O lives in llm.ts — mock it so no network calls happen.
vi.mock("../../src/lib/llm.js", () => ({
  runLLM: vi.fn(),
}));

import { runLLM } from "../../src/lib/llm.js";
import {
  buildAutoTagPrompt,
  parseAutoTagResponse,
  extractCandidatesFromContent,
} from "../../src/posting/auto-tag.js";

const runLLMMock = runLLM as unknown as ReturnType<typeof vi.fn>;

beforeEach(() => {
  runLLMMock.mockReset();
});

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const SAMPLE_INPUT = {
  title: "pgvector でハイブリッド検索を実装する",
  body: "PostgreSQL の pgvector 拡張と tsvector を組み合わせて全文検索とセマンティック検索を統合する方法を解説する。",
  type: "tech_articles" as const,
};

const validJson = JSON.stringify({
  category: { slug: "deepdive", name: "Deep Dive", confidence: 0.92 },
  tags: [
    { name: "Supabase", confidence: 0.9 },
    { name: "PostgreSQL", confidence: 0.88 },
    { name: "pgvector", confidence: 0.8 },
  ],
});

// ---------------------------------------------------------------------------
// 1–2. buildAutoTagPrompt
// ---------------------------------------------------------------------------

describe("buildAutoTagPrompt — embeds inputs", () => {
  it("includes title, body excerpt, and type in the prompt", () => {
    const prompt = buildAutoTagPrompt(SAMPLE_INPUT);
    expect(prompt).toContain(SAMPLE_INPUT.title);
    // Body may be truncated but the leading phrase should survive.
    expect(prompt).toContain("pgvector");
    expect(prompt).toContain(SAMPLE_INPUT.type);
  });
});

describe("buildAutoTagPrompt — few-shot examples", () => {
  it("contains at least 3 few-shot examples", () => {
    const prompt = buildAutoTagPrompt(SAMPLE_INPUT);
    // Few-shot blocks are emitted as `例1:`, `例2:`, ...; count >=3
    const count = (prompt.match(/例[0-9]+:/g) ?? []).length;
    expect(count).toBeGreaterThanOrEqual(3);
  });
});

// ---------------------------------------------------------------------------
// 3–4. parseAutoTagResponse — success paths
// ---------------------------------------------------------------------------

describe("parseAutoTagResponse — plain JSON", () => {
  it("parses a valid response body", () => {
    const out = parseAutoTagResponse(validJson);
    expect(out.category.slug).toBe("deepdive");
    expect(out.category.name).toBe("Deep Dive");
    expect(out.category.confidence).toBeCloseTo(0.92);
    expect(out.tags).toHaveLength(3);
    expect(out.tags[0]!.name).toBe("Supabase");
  });
});

describe("parseAutoTagResponse — fenced code block", () => {
  it("strips ```json ... ``` wrapping before parsing", () => {
    const fenced = "```json\n" + validJson + "\n```";
    const out = parseAutoTagResponse(fenced);
    expect(out.category.slug).toBe("deepdive");
    expect(out.tags).toHaveLength(3);
  });

  it("strips plain ``` fences without json hint", () => {
    const fenced = "```\n" + validJson + "\n```";
    const out = parseAutoTagResponse(fenced);
    expect(out.category.slug).toBe("deepdive");
  });
});

// ---------------------------------------------------------------------------
// 5. confidence out of range
// ---------------------------------------------------------------------------

describe("parseAutoTagResponse — confidence range validation", () => {
  it("throws when category.confidence is outside [0,1]", () => {
    const bad = JSON.stringify({
      category: { slug: "x", name: "X", confidence: 1.3 },
      tags: [],
    });
    expect(() => parseAutoTagResponse(bad)).toThrow(/confidence/i);
  });
});

// ---------------------------------------------------------------------------
// 6. tags truncation
// ---------------------------------------------------------------------------

describe("parseAutoTagResponse — tags length cap", () => {
  it("truncates tags to the configured limit (default 5)", () => {
    const tags = Array.from({ length: 9 }, (_, i) => ({
      name: `t${i}`,
      confidence: 0.7,
    }));
    const raw = JSON.stringify({
      category: { slug: "deepdive", name: "Deep Dive", confidence: 0.9 },
      tags,
    });
    const out = parseAutoTagResponse(raw);
    expect(out.tags).toHaveLength(5);
  });
});

// ---------------------------------------------------------------------------
// 7. extractCandidatesFromContent — happy path
// ---------------------------------------------------------------------------

describe("extractCandidatesFromContent — invokes Haiku and returns parsed payload", () => {
  it("calls runLLM once and returns parsed category/tags", async () => {
    runLLMMock.mockResolvedValueOnce({
      text: validJson,
      model: "anthropic/claude-haiku-4.5",
      tokens: { input: 20, output: 40, total: 60 },
    });
    const out = await extractCandidatesFromContent(SAMPLE_INPUT);
    expect(runLLMMock).toHaveBeenCalledTimes(1);
    const call = runLLMMock.mock.calls[0]![0];
    expect(call.kind).toBe("auto-tag");
    expect(out.category.slug).toBe("deepdive");
    expect(out.tags).toHaveLength(3);
  });
});

// ---------------------------------------------------------------------------
// 8–9. retry on invalid JSON then final failure
// ---------------------------------------------------------------------------

describe("extractCandidatesFromContent — one-shot retry on invalid JSON", () => {
  it("retries once then succeeds on second valid output", async () => {
    runLLMMock
      .mockResolvedValueOnce({
        text: "not valid json at all",
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 20, output: 5, total: 25 },
      })
      .mockResolvedValueOnce({
        text: validJson,
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 20, output: 40, total: 60 },
      });
    const out = await extractCandidatesFromContent(SAMPLE_INPUT);
    expect(runLLMMock).toHaveBeenCalledTimes(2);
    expect(out.category.slug).toBe("deepdive");
  });

  it("throws when the retry is also invalid", async () => {
    runLLMMock
      .mockResolvedValueOnce({
        text: "still not json",
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 20, output: 5, total: 25 },
      })
      .mockResolvedValueOnce({
        text: "still garbage",
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 20, output: 5, total: 25 },
      });
    await expect(
      extractCandidatesFromContent(SAMPLE_INPUT),
    ).rejects.toThrow(/parse/i);
    expect(runLLMMock).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// 10. confidence must be numeric
// ---------------------------------------------------------------------------

describe("parseAutoTagResponse — confidence must be numeric", () => {
  it("throws when category.confidence is not a number", () => {
    const bad = JSON.stringify({
      category: { slug: "x", name: "X", confidence: "high" },
      tags: [],
    });
    expect(() => parseAutoTagResponse(bad)).toThrow(/confidence/i);
  });
});

// ---------------------------------------------------------------------------
// 11–13. buildAutoTagPrompt — allowlist injection (Wave 11.3e W2)
// ---------------------------------------------------------------------------

import type { CategoryAllowEntry } from "../../src/posting/category-allowlist.js";

const ALLOWLIST_SAMPLE: CategoryAllowEntry[] = [
  { slug: "architecture", name: "Architecture", description: null },
  { slug: "tips", name: "Tips", description: "Quick how-to" },
];

describe("buildAutoTagPrompt — empty allowList is a no-op", () => {
  it("returns the same prompt whether opts is omitted or has empty allowList", () => {
    const a = buildAutoTagPrompt(SAMPLE_INPUT);
    const b = buildAutoTagPrompt(SAMPLE_INPUT, { allowedCategories: [] });
    expect(b).toBe(a);
  });
});

describe("buildAutoTagPrompt — allowList injection", () => {
  it("includes a strict-allowlist section when allowedCategories is provided", () => {
    const p = buildAutoTagPrompt(SAMPLE_INPUT, {
      allowedCategories: ALLOWLIST_SAMPLE,
    });
    expect(p).toMatch(/厳格な制約/);
    expect(p).toContain("- architecture: Architecture");
    expect(p).toContain("- tips: Tips — Quick how-to");
    expect(p).toMatch(/新規 slug/);
  });
});

describe("buildAutoTagPrompt — allowList placement", () => {
  it("places the allowlist section immediately before the trailing '出力:' line", () => {
    const p = buildAutoTagPrompt(SAMPLE_INPUT, {
      allowedCategories: ALLOWLIST_SAMPLE,
    });
    const idxAllow = p.indexOf("厳格な制約");
    // 末尾の単独 "出力:" を見る (few-shot の "出力: <json>" には改行が続くため lastIndexOf で末尾を取る)
    const idxTrailingOutput = p.lastIndexOf("出力:");
    expect(idxAllow).toBeGreaterThan(-1);
    expect(idxTrailingOutput).toBeGreaterThan(-1);
    expect(idxAllow).toBeLessThan(idxTrailingOutput);
    // 単独行 "出力:" は最終出力指示の 1 箇所のみ (few-shot は "出力: <payload>" で行頭マッチしない)
    const trailingMatches = p.match(/^出力:$/gm) ?? [];
    expect(trailingMatches.length).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// 14. extractCandidatesFromContent — passes allowedCategories through
// ---------------------------------------------------------------------------

describe("extractCandidatesFromContent — forwards allowedCategories into the prompt", () => {
  it("invokes runLLM with a prompt that includes the allowlist", async () => {
    runLLMMock.mockResolvedValueOnce({
      text: validJson,
      model: "anthropic/claude-haiku-4.5",
      tokens: { input: 20, output: 40, total: 60 },
    });
    await extractCandidatesFromContent(SAMPLE_INPUT, {
      allowedCategories: ALLOWLIST_SAMPLE,
    });
    const call = runLLMMock.mock.calls[0]![0];
    expect(call.prompt).toMatch(/厳格な制約/);
    expect(call.prompt).toContain("- tips: Tips — Quick how-to");
  });
});
