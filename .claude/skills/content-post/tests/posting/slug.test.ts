/**
 * Tests for src/posting/slug.ts — Phase 8 Wave E1
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e1/plan.md §テスト観点 (slug.test.ts)
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createMockSupabase } from "../__helpers__/supabase-mock.js";

// --- Mock llm.ts's `runLLM` so Haiku fallback is deterministic ---
vi.mock("../../src/lib/llm.js", () => ({
  runLLM: vi.fn(),
}));

import { runLLM } from "../../src/lib/llm.js";
import {
  generateSlug,
  checkSlugCollision,
  ensureUniqueSlug,
  normalizeSlug,
  assertSlugAvailable,
  SlugConflictError,
} from "../../src/posting/slug.js";

const runLLMMock = runLLM as unknown as ReturnType<typeof vi.fn>;

beforeEach(() => {
  runLLMMock.mockReset();
});

describe("generateSlug — ASCII title", () => {
  it("slugifies 'Hello World' to 'hello-world'", async () => {
    const out = await generateSlug("Hello World", "knowledge");
    expect(out).toBe("hello-world");
    // No LLM call needed for plain ASCII
    expect(runLLMMock).not.toHaveBeenCalled();
  });
});

describe("generateSlug — Japanese title → Haiku fallback", () => {
  it("uses runLLM when slugify output is empty", async () => {
    runLLMMock.mockResolvedValue({
      text: "nextjs-cache-components",
      model: "anthropic/claude-haiku-4.5",
      tokens: { input: 10, output: 5, total: 15 },
    });
    const out = await generateSlug(
      "Next.js 16 のキャッシュコンポーネント入門",
      "tech_articles",
    );
    expect(out).toBe("nextjs-cache-components");
    expect(runLLMMock).toHaveBeenCalledOnce();
    const call = runLLMMock.mock.calls[0]![0];
    expect(call.kind).toBe("slug");
  });
});

describe("ensureUniqueSlug — collision handling", () => {
  it("appends -2 when base slug already exists once", async () => {
    const client = createMockSupabase({
      tables: {
        knowledge: [{ slug: "my-slug" }],
      },
    });
    const out = await ensureUniqueSlug("my-slug", "knowledge", client);
    expect(out).toBe("my-slug-2");
  });

  it("throws when collision exceeds 20 attempts", async () => {
    const existing: { slug: string }[] = [{ slug: "busy-slug" }];
    for (let i = 2; i <= 21; i++) existing.push({ slug: `busy-slug-${i}` });
    const client = createMockSupabase({
      tables: { knowledge: existing },
    });
    await expect(
      ensureUniqueSlug("busy-slug", "knowledge", client),
    ).rejects.toThrow(/exceeded.*20/i);
  });
});

describe("checkSlugCollision", () => {
  it("returns true when row with slug exists", async () => {
    const client = createMockSupabase({
      tables: { tech_articles: [{ slug: "foo" }] },
    });
    const hit = await checkSlugCollision("foo", "tech_articles", client);
    expect(hit).toBe(true);
  });

  it("returns false when row with slug not found", async () => {
    const client = createMockSupabase({ tables: { knowledge: [] } });
    const hit = await checkSlugCollision("nope", "knowledge", client);
    expect(hit).toBe(false);
  });
});

describe("normalizeSlug — formatting", () => {
  it("lowercases, strips symbols, collapses double hyphens", () => {
    expect(normalizeSlug("Hello--World!!")).toBe("hello-world");
  });

  it("trims leading and trailing hyphens", () => {
    expect(normalizeSlug("--abc-def--")).toBe("abc-def");
  });

  it("truncates results longer than 80 chars", () => {
    const long = "a".repeat(100);
    const out = normalizeSlug(long);
    expect(out.length).toBeLessThanOrEqual(80);
  });
});

describe("assertSlugAvailable — fail-loud on collision", () => {
  it("resolves without throwing when slug is not taken", async () => {
    const client = createMockSupabase({ tables: { knowledge: [] } });
    await expect(
      assertSlugAvailable("brand-new-slug", "knowledge", client),
    ).resolves.toBeUndefined();
  });

  it("throws SlugConflictError when slug is already taken", async () => {
    const client = createMockSupabase({
      tables: { knowledge: [{ slug: "taken", id: "k-existing-1" }] },
    });
    await expect(
      assertSlugAvailable("taken", "knowledge", client),
    ).rejects.toBeInstanceOf(SlugConflictError);
  });

  it("SlugConflictError carries slug, contentType, existingId", async () => {
    const client = createMockSupabase({
      tables: { tech_articles: [{ slug: "dup", id: "ta-42" }] },
    });
    let caught: unknown = null;
    try {
      await assertSlugAvailable("dup", "tech_articles", client);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(SlugConflictError);
    const err = caught as SlugConflictError;
    expect(err.slug).toBe("dup");
    expect(err.contentType).toBe("tech_articles");
    expect(err.existingId).toBe("ta-42");
    expect(err.name).toBe("SlugConflictError");
    expect(err.message).toMatch(/dup/);
    expect(err.message).toMatch(/tech_articles/);
  });

  it("existingId is undefined when the matched row has no id column", async () => {
    // maybeSingle returns the row matched by slug; if no id is seeded, existingId is undefined.
    const client = createMockSupabase({
      tables: { knowledge: [{ slug: "no-id-row" }] },
    });
    let caught: unknown = null;
    try {
      await assertSlugAvailable("no-id-row", "knowledge", client);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(SlugConflictError);
    expect((caught as SlugConflictError).existingId).toBeUndefined();
  });

  it("resolves when maybeSingle returns null (no row)", async () => {
    // Empty table — maybeSingle yields { data: null }.
    const client = createMockSupabase({ tables: { weekly_issues: [] } });
    await expect(
      assertSlugAvailable("fresh", "weekly_issues", client),
    ).resolves.toBeUndefined();
  });
});
