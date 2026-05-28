/**
 * tests/stages/07-render-async.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import { renderAsync } from "../../scripts/stages/07-render-async.js";
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

describe("scripts/stages/07-render-async — Task #56 W3", () => {
  it("returns null when --dry-run is set", async () => {
    const result = await renderAsync({
      source: "x",
      template: {},
      slug: "s",
      contentType: "knowledge",
      opts: { dryRun: true },
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    expect(result.rendered).toBeNull();
  });

  it("invokes renderToHtmlAsync with mapped image-prefix contentType", async () => {
    const renderToHtmlAsync = vi.fn(async () => ({
      html: "<p>x</p>",
      appliedClasses: [],
      plantumlReplacements: [{}],
    }));
    const result = await renderAsync({
      source: "x",
      template: {},
      slug: "s",
      contentType: "tech_articles",
      opts: { dryRun: false },
      deps: makeDeps({ renderToHtmlAsync: renderToHtmlAsync as never }),
      verbose: vi.fn(),
    });
    expect(renderToHtmlAsync).toHaveBeenCalledWith(
      "x",
      {},
      { slug: "s", contentType: "tech_article" },
    );
    expect(result.rendered?.html).toBe("<p>x</p>");
  });
});
