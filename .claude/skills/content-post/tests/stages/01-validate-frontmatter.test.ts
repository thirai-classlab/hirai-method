/**
 * tests/stages/01-validate-frontmatter.test.ts — Task #56 W2 (11.3d-B)
 *
 * Validates that validateFrontmatter() preserves the post.ts inline semantics:
 *   - returns the frontmatter + title + contentType on success
 *   - returns the structured error list on validation failure
 *   - tolerates loadTemplates() throwing (best-effort fallback to {})
 */
import { describe, it, expect, vi } from "vitest";
import { validateFrontmatter } from "../../scripts/stages/01-validate-frontmatter.js";
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

describe("scripts/stages/01-validate-frontmatter — Task #56 W2", () => {
  it("returns ok with frontmatter / title / contentType on success", async () => {
    const deps = makeDeps({
      validate: vi.fn(() => ({
        ok: true,
        frontmatter: { title: "Hello", type: "knowledge", foo: 1 },
      })) as unknown as PostDeps["validate"],
    });
    const result = await validateFrontmatter("source-md", deps);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.title).toBe("Hello");
      expect(result.contentType).toBe("knowledge");
      expect(result.frontmatter.foo).toBe(1);
    }
  });

  it("returns errors array when validate() reports failure", async () => {
    const deps = makeDeps({
      validate: vi.fn(() => ({
        ok: false,
        errors: [{ field: "title", message: "required" }],
      })) as unknown as PostDeps["validate"],
    });
    const result = await validateFrontmatter("source-md", deps);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors).toEqual([
        { field: "title", message: "required" },
      ]);
    }
  });

  it("tolerates loadTemplates throwing — falls back to empty registry", async () => {
    const validateFn = vi.fn(() => ({
      ok: true,
      frontmatter: { title: "X", type: "tech_articles" },
    })) as unknown as PostDeps["validate"];
    const deps = makeDeps({
      loadTemplates: vi.fn(() => {
        throw new Error("registry boom");
      }) as unknown as PostDeps["loadTemplates"],
      validate: validateFn,
    });
    const result = await validateFrontmatter("source-md", deps);
    expect(result.ok).toBe(true);
    // validate was still called with an empty templates registry
    expect((validateFn as unknown as { mock: { calls: unknown[][] } }).mock.calls[0]?.[1])
      .toEqual({ templates: {} });
  });
});
