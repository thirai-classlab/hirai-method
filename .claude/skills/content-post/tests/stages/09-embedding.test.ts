/**
 * tests/stages/09-embedding.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import {
  generateEmbeddingForPipeline,
  findRelatedKnowledge,
} from "../../scripts/stages/09-embedding.js";
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
    generateEmbedding: vi.fn(async () => [0.1, 0.2, 0.3]),
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

describe("scripts/stages/09-embedding — Task #56 W3", () => {
  it("generates embedding from title + parsedRaw, truncated to 8000 chars", async () => {
    const generateEmbedding = vi.fn(async (text: string) => {
      expect(text.length).toBeLessThanOrEqual(8000);
      return [1, 2, 3];
    });
    const out = await generateEmbeddingForPipeline(
      "Title",
      "Body".repeat(3000),
      makeDeps({ generateEmbedding }),
    );
    expect(out).toEqual([1, 2, 3]);
    expect(generateEmbedding).toHaveBeenCalledOnce();
  });

  it("findRelatedKnowledge returns empty when contentType != weekly_issues", async () => {
    const searchSimilar = vi.fn();
    const ids = await findRelatedKnowledge(
      [0.1],
      "knowledge",
      makeDeps({ searchSimilar: searchSimilar as never }),
      vi.fn(),
      vi.fn(),
    );
    expect(ids).toEqual([]);
    expect(searchSimilar).not.toHaveBeenCalled();
  });

  it("findRelatedKnowledge picks top-3 knowledge matches for weekly_issues", async () => {
    const searchSimilar = vi.fn(async () => [
      { content_type: "knowledge", content_id: "k1", similarity: 0.9 },
      { content_type: "knowledge", content_id: "k2", similarity: 0.85 },
      { content_type: "tech_articles", content_id: "a1", similarity: 0.83 },
      { content_type: "knowledge", content_id: "k3", similarity: 0.8 },
      { content_type: "knowledge", content_id: "k4", similarity: 0.79 },
    ]);
    const ids = await findRelatedKnowledge(
      [0.1],
      "weekly_issues",
      makeDeps({ searchSimilar: searchSimilar as never }),
      vi.fn(),
      vi.fn(),
    );
    expect(ids).toEqual(["k1", "k2", "k3"]);
  });
});
