/**
 * tests/stages/08-link-cards.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import { enrichLinkCardsIfNeeded } from "../../scripts/stages/08-link-cards.js";
import type { PostDeps } from "../../scripts/post.js";

function makeDeps(over: Partial<PostDeps> = {}): PostDeps {
  return {
    loadFile: vi.fn(),
    validate: vi.fn(),
    parseMarkdown: vi.fn(),
    renderToHtml: vi.fn(),
    renderToHtmlAsync: vi.fn(),
    generateSlug: vi.fn(),
    ensureUniqueSlug: vi.fn(),
    generateEmbedding: vi.fn(),
    checkDuplicate: vi.fn(),
    suggestCategory: vi.fn(),
    suggestTags: vi.fn(),
    resolveTagAgainstMasters: vi.fn(),
    confirmInteractively: vi.fn(),
    getSupabaseClient: vi.fn(),
    webSearch: { search: vi.fn() },
    reader: { question: vi.fn(), close: vi.fn() },
    streams: { out: [], err: [], write: vi.fn(), writeErr: vi.fn() },
    env: {},
    ...over,
  } as PostDeps;
}

describe("scripts/stages/08-link-cards — Task #56 W3", () => {
  it("returns original html when dep is omitted", async () => {
    const result = await enrichLinkCardsIfNeeded(
      "<p>x</p>",
      makeDeps(),
      { dryRun: false },
      vi.fn(),
      vi.fn(),
    );
    expect(result).toBe("<p>x</p>");
  });

  it("falls back to original html when enrichment throws", async () => {
    const enrichLinkCards = vi.fn(async () => {
      throw new Error("OG fetch failed");
    });
    const logErr = vi.fn();
    const result = await enrichLinkCardsIfNeeded(
      "<p>x</p>",
      makeDeps({ enrichLinkCards }),
      { dryRun: false },
      logErr,
      vi.fn(),
    );
    expect(result).toBe("<p>x</p>");
    expect(logErr).toHaveBeenCalledOnce();
  });

  it("returns enriched html when dep succeeds", async () => {
    const enrichLinkCards = vi.fn(async () => "<p>enriched</p>");
    const result = await enrichLinkCardsIfNeeded(
      "<p>x</p>",
      makeDeps({ enrichLinkCards }),
      { dryRun: false },
      vi.fn(),
      vi.fn(),
    );
    expect(result).toBe("<p>enriched</p>");
  });
});
