/**
 * tests/stages/05-image-upload.test.ts — Task #56 W3 (11.3d-C)
 *
 * Unit tests for processImagesIfNeeded() — verifies dep-omission skip,
 * dry-run skip, replacement detection, and basic invalidation wiring.
 */
import { describe, it, expect, vi } from "vitest";
import { processImagesIfNeeded } from "../../scripts/stages/05-image-upload.js";
import type { PostDeps } from "../../scripts/post.js";

function makeDeps(over: Partial<PostDeps> = {}): PostDeps {
  return {
    loadFile: vi.fn(),
    validate: vi.fn(),
    parseMarkdown: vi.fn((s: string) => ({ raw: s, sections: [] } as never)),
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

describe("scripts/stages/05-image-upload — Task #56 W3", () => {
  it("skips when processMarkdownImages dep is omitted", async () => {
    const result = await processImagesIfNeeded({
      source: "hello",
      filePath: "/tmp/x.md",
      slug: "s",
      contentType: "knowledge",
      opts: { dryRun: false, update: false },
      existing: null,
      env: {},
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(result).toEqual({ source: "hello", reparsed: null });
  });

  it("skips when --dry-run is set even if dep is wired", async () => {
    const processMarkdownImages = vi.fn();
    const result = await processImagesIfNeeded({
      source: "hello",
      filePath: "/tmp/x.md",
      slug: "s",
      contentType: "knowledge",
      opts: { dryRun: true, update: false },
      existing: null,
      env: {},
      deps: makeDeps({ processMarkdownImages }),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(processMarkdownImages).not.toHaveBeenCalled();
    expect(result.source).toBe("hello");
  });

  it("returns rewritten source + re-parsed result when replacements happen", async () => {
    const processMarkdownImages = vi.fn(async () => ({
      markdown: "rewritten",
      replacements: [{ original: "a", cdnUrl: "b" }],
    }));
    const result = await processImagesIfNeeded({
      source: "hello",
      filePath: "/tmp/x.md",
      slug: "s",
      contentType: "knowledge",
      opts: { dryRun: false, update: false },
      existing: null,
      env: {},
      deps: makeDeps({ processMarkdownImages: processMarkdownImages as never }),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(result.source).toBe("rewritten");
    expect(result.reparsed).not.toBeNull();
  });
});
