/**
 * tests/stages/04-slug-resolve.test.ts — Task #56 W2 (11.3d-B)
 *
 * Unit tests for the pure resolveSlug() helper and kindForSnapshot() mapping.
 * Update-mode snapshot side-effects are exercised by the existing post.test.ts
 * roundtrip suite; here we pin the slug-derivation rules.
 */
import { describe, it, expect, vi } from "vitest";
import {
  resolveSlug,
  kindForSnapshot,
} from "../../scripts/stages/04-slug-resolve.js";
import type { PostDeps, ParsedOptions } from "../../scripts/post.js";

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

function makeOpts(over: Partial<ParsedOptions> = {}): ParsedOptions {
  return {
    file: undefined,
    batch: undefined,
    dryRun: false,
    autoApprove: false,
    update: false,
    slug: undefined,
    force: false,
    verbose: false,
    thumbnailHearing: true,
    publish: false,
    linkCheck: true,
    linkCheckStrict: false,
    knowledgeKind: "concept",
    ...over,
  };
}

describe("scripts/stages/04-slug-resolve — Task #56 W2", () => {
  describe("kindForSnapshot", () => {
    it("maps post.ts contentType to the version-manager ContentKind enum", () => {
      expect(kindForSnapshot("tech_articles")).toBe("tech_article");
      expect(kindForSnapshot("weekly_issues")).toBe("weekly_issue");
      expect(kindForSnapshot("knowledge")).toBe("knowledge");
      expect(kindForSnapshot("unknown")).toBe("knowledge");
    });
  });

  describe("resolveSlug", () => {
    it("returns existing.slug when update=true and existing row is present", async () => {
      const slug = await resolveSlug({
        title: "ignored",
        contentType: "knowledge",
        frontmatter: {},
        opts: makeOpts({ update: true }),
        existing: { slug: "from-existing" },
        client: {},
        deps: makeDeps(),
      });
      expect(slug).toBe("from-existing");
    });

    it("uses assertSlugAvailable when frontmatter.slug is explicit (fail-loud)", async () => {
      const assertSlugAvailable = vi.fn(async () => {});
      const slug = await resolveSlug({
        title: "T",
        contentType: "knowledge",
        frontmatter: { slug: "explicit-slug" },
        opts: makeOpts(),
        existing: null,
        client: { c: 1 },
        deps: makeDeps({
          assertSlugAvailable: assertSlugAvailable as unknown as PostDeps["assertSlugAvailable"],
        }),
      });
      expect(slug).toBe("explicit-slug");
      expect(assertSlugAvailable).toHaveBeenCalledWith(
        "explicit-slug",
        "knowledge",
        { c: 1 },
      );
    });

    it("falls back to ensureUniqueSlug when assertSlugAvailable not injected (back-compat)", async () => {
      const ensureUniqueSlug = vi.fn(async () => "unique-suffix");
      const generateSlug = vi.fn(async () => "from-title");
      const slug = await resolveSlug({
        title: "Some Title",
        contentType: "tech_articles",
        frontmatter: {},
        opts: makeOpts(),
        existing: null,
        client: {},
        deps: makeDeps({
          generateSlug: generateSlug as unknown as PostDeps["generateSlug"],
          ensureUniqueSlug: ensureUniqueSlug as unknown as PostDeps["ensureUniqueSlug"],
        }),
      });
      expect(slug).toBe("unique-suffix");
      expect(generateSlug).toHaveBeenCalledWith("Some Title", "tech_articles", {});
      expect(ensureUniqueSlug).toHaveBeenCalledWith("from-title", "tech_articles", {});
    });
  });
});
