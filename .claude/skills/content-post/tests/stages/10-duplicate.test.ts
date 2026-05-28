/**
 * tests/stages/10-duplicate.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import { checkDuplicateForPipeline } from "../../scripts/stages/10-duplicate.js";
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

describe("scripts/stages/10-duplicate — Task #56 W3", () => {
  it("passes selfId from existing.id to deps.checkDuplicate", async () => {
    const checkDuplicate = vi.fn(async () => ({ level: "ok", matches: [], reason: null }));
    await checkDuplicateForPipeline(
      [0.1],
      "knowledge",
      { id: "abc-123" },
      { c: 1 },
      makeDeps({ checkDuplicate: checkDuplicate as never }),
    );
    expect(checkDuplicate).toHaveBeenCalledWith({
      client: { c: 1 },
      embedding: [0.1],
      contentType: "knowledge",
      selfId: "abc-123",
    });
  });

  it("omits selfId when no existing row", async () => {
    const checkDuplicate = vi.fn(async () => ({ level: "ok", matches: [], reason: null }));
    await checkDuplicateForPipeline(
      [0.1],
      "knowledge",
      null,
      { c: 1 },
      makeDeps({ checkDuplicate: checkDuplicate as never }),
    );
    expect(checkDuplicate).toHaveBeenCalledWith({
      client: { c: 1 },
      embedding: [0.1],
      contentType: "knowledge",
      selfId: undefined,
    });
  });
});
