/**
 * tests/stages/12-ingest.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import { ingestNew } from "../../scripts/stages/12-ingest.js";
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

describe("scripts/stages/12-ingest — Task #56 W3", () => {
  it("maps contentType to apiType (knowledge → knowledge / tech_articles → article / weekly_issues → issue)", async () => {
    const calls: string[] = [];
    const ingestViaApi = vi.fn(async (payload: { type: string }) => {
      calls.push(payload.type);
      return { id: "id1", slug: "sl", trace_id: "tr" };
    });
    const log = vi.fn();
    for (const ct of ["knowledge", "tech_articles", "weekly_issues"]) {
      await ingestNew({
        title: "T",
        slug: "sl",
        contentType: ct,
        frontmatter: {},
        parsedRaw: "B",
        renderedHtml: "<p>x</p>",
        confirmedMeta: null,
        thumbnailCdnUrl: null,
        relatedKnowledgeIds: [],
        deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
        log,
      });
    }
    expect(calls).toEqual(["knowledge", "article", "issue"]);
  });

  it("splits confirmedMeta.tags into existing tag_ids vs new tag_names_new", async () => {
    let captured: { tag_ids: string[]; tag_names_new: string[] } | null = null;
    const ingestViaApi = vi.fn(
      async (payload: { tag_ids: string[]; tag_names_new: string[] }) => {
        captured = {
          tag_ids: payload.tag_ids,
          tag_names_new: payload.tag_names_new,
        };
        return { id: "id1", slug: "sl", trace_id: "tr" };
      },
    );
    await ingestNew({
      title: "T",
      slug: "sl",
      contentType: "knowledge",
      frontmatter: {},
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      confirmedMeta: {
        category: { slug: "c" },
        tags: [
          { name: "existing-1", id: "t1", isNew: false },
          { name: "new-1", isNew: true },
          { name: "existing-2", id: "t2", isNew: false },
        ],
      },
      thumbnailCdnUrl: null,
      relatedKnowledgeIds: [],
      deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
      log: vi.fn(),
    });
    expect(captured!.tag_ids).toEqual(["t1", "t2"]);
    expect(captured!.tag_names_new).toEqual(["new-1"]);
  });

  // --- #58 Step 1: knowledge.kind in ingest payload ---
  it("includes kind in payload for knowledge (--kind operation)", async () => {
    let capturedKind: unknown;
    const ingestViaApi = vi.fn(async (payload: { kind?: unknown }) => {
      capturedKind = payload.kind;
      return { id: "id1", slug: "sl", trace_id: "tr" };
    });
    await ingestNew({
      title: "T",
      slug: "sl",
      contentType: "knowledge",
      knowledgeKind: "operation",
      frontmatter: {},
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      confirmedMeta: null,
      thumbnailCdnUrl: null,
      relatedKnowledgeIds: [],
      deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
      log: vi.fn(),
    });
    expect(capturedKind).toBe("operation");
  });

  it("includes kind=domain_knowledge in payload for knowledge", async () => {
    let capturedKind: unknown;
    const ingestViaApi = vi.fn(async (payload: { kind?: unknown }) => {
      capturedKind = payload.kind;
      return { id: "id1", slug: "sl", trace_id: "tr" };
    });
    await ingestNew({
      title: "T",
      slug: "sl",
      contentType: "knowledge",
      knowledgeKind: "domain_knowledge",
      frontmatter: {},
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      confirmedMeta: null,
      thumbnailCdnUrl: null,
      relatedKnowledgeIds: [],
      deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
      log: vi.fn(),
    });
    expect(capturedKind).toBe("domain_knowledge");
  });

  it("defaults kind to 'concept' for knowledge when knowledgeKind is omitted (backward compat)", async () => {
    let capturedKind: unknown;
    const ingestViaApi = vi.fn(async (payload: { kind?: unknown }) => {
      capturedKind = payload.kind;
      return { id: "id1", slug: "sl", trace_id: "tr" };
    });
    await ingestNew({
      title: "T",
      slug: "sl",
      contentType: "knowledge",
      frontmatter: {},
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      confirmedMeta: null,
      thumbnailCdnUrl: null,
      relatedKnowledgeIds: [],
      deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
      log: vi.fn(),
    });
    expect(capturedKind).toBe("concept");
  });

  it("does NOT set kind for non-knowledge content (tech_articles / weekly_issues)", async () => {
    const captured: Array<{ type: string; kind?: unknown }> = [];
    const ingestViaApi = vi.fn(async (payload: { type: string; kind?: unknown }) => {
      captured.push({ type: payload.type, kind: payload.kind });
      return { id: "id1", slug: "sl", trace_id: "tr" };
    });
    for (const ct of ["tech_articles", "weekly_issues"]) {
      await ingestNew({
        title: "T",
        slug: "sl",
        contentType: ct,
        // pass a non-default kind to prove it is ignored for non-knowledge
        knowledgeKind: "operation",
        frontmatter: {},
        parsedRaw: "B",
        renderedHtml: "<p>x</p>",
        confirmedMeta: null,
        thumbnailCdnUrl: null,
        relatedKnowledgeIds: [],
        deps: makeDeps({ ingestViaApi: ingestViaApi as never }),
        log: vi.fn(),
      });
    }
    expect(captured.map((c) => c.kind)).toEqual([undefined, undefined]);
  });
});
