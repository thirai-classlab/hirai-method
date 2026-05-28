/**
 * tests/stages/02-parse-markdown.test.ts — Task #56 W2 (11.3d-B)
 *
 * Unit tests for parseAndRender() — the pure stage 02 helper extracted from
 * scripts/post.ts. Verifies it threads the source through deps.parseMarkdown
 * and deps.renderToHtml, and that template lookup failures are caught into
 * templateError without bubbling up (matching the original post.ts inline
 * best-effort semantics).
 */
import { describe, it, expect, vi } from "vitest";
import { parseAndRender } from "../../scripts/stages/02-parse-markdown.js";
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

describe("scripts/stages/02-parse-markdown — Task #56 W2", () => {
  it("returns parsed / rendered / template via deps and forwards renderToHtml result", () => {
    const deps = makeDeps({
      parseMarkdown: vi.fn(() => ({ raw: "raw-md" })) as unknown as PostDeps["parseMarkdown"],
      renderToHtml: vi.fn(() => ({
        html: "<p>x</p>",
        appliedClasses: ["foo"],
      })) as unknown as PostDeps["renderToHtml"],
    });
    const result = parseAndRender(
      "source-md",
      "knowledge",
      { subtype: undefined },
      // Empty registry → getTemplate throws "Template not found" but we catch
      // that into templateError (non-fatal — same as original inline code).
      {},
      deps,
    );
    expect(result.rendered.html).toBe("<p>x</p>");
    expect(result.rendered.appliedClasses).toEqual(["foo"]);
    expect((result.parsed as { raw?: string }).raw).toBe("raw-md");
    // Template lookup against an empty registry currently throws — confirm
    // the error is captured as a non-fatal templateError string and never
    // re-thrown. Template falls back to {} so downstream stages still work.
    expect(result.template).toEqual({});
    expect(typeof result.templateError).toBe("string");
  });

  it("threads contentType=tech_articles through without raising", () => {
    const renderToHtml = vi.fn(() => ({ html: "<p/>", appliedClasses: [] }));
    const deps = makeDeps({
      parseMarkdown: vi.fn(() => ({ raw: "raw" })) as unknown as PostDeps["parseMarkdown"],
      renderToHtml: renderToHtml as unknown as PostDeps["renderToHtml"],
    });
    const result = parseAndRender(
      "source-md",
      "tech_articles",
      {},
      {},
      deps,
    );
    // Stage must not throw even when template lookup fails — that is the
    // contract preserved from the original post.ts inline try/catch.
    expect(result.rendered.html).toBe("<p/>");
    expect(result.template).toEqual({});
    // renderToHtml is invoked with the fallback {} template.
    expect(renderToHtml).toHaveBeenCalledWith("source-md", {});
  });
});
