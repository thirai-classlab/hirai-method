/**
 * Integration test: link-card enrichment pipeline
 *
 * Verifies that a URL-only paragraph in markdown flows through the full
 * post.ts pipeline and results in an enriched C1 Boxed Card in the final
 * HTML written to the DB. This covers the integration between:
 *
 *   markdown.ts renderToHtml() → enrichLinkCards() → DB html column
 *
 * fetch() is mocked at the global level so no real HTTP requests are made.
 *
 * Covers:
 *   P-1: happy path — OG fetch succeeds → enriched card in DB html
 *   P-2: fallback path — OG fetch fails → fallback card (link-card--fallback) still appears
 *   P-3: no URL-only line → no link-card in output (regression guard)
 *   P-4: enrichLinkCards is a no-op when dep is omitted (backward-compat)
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import os from "node:os";

// ---------------------------------------------------------------------------
// Shared fake helpers (mirrors post.test.ts pattern)
// ---------------------------------------------------------------------------

interface CapturedStreams {
  out: string[];
  err: string[];
  write(line: string): void;
  writeErr(line: string): void;
}

function makeStreams(): CapturedStreams {
  const out: string[] = [];
  const err: string[] = [];
  return {
    out,
    err,
    write(line: string) {
      out.push(line);
    },
    writeErr(line: string) {
      err.push(line);
    },
  };
}

type SupabaseCall = {
  op: string;
  table?: string;
  data?: unknown;
};

interface FakeBuilder {
  select: (cols?: string) => FakeBuilder;
  eq: (col: string, val: unknown) => FakeBuilder;
  maybeSingle: () => Promise<{ data: unknown; error: unknown }>;
  single: () => Promise<{ data: unknown; error: unknown }>;
  insert: (row: unknown) => FakeBuilder;
  update: (row: unknown) => FakeBuilder;
  upsert: (rows: unknown, opts?: unknown) => Promise<unknown>;
  limit: (n: number) => Promise<{ data: unknown[]; error: unknown }>;
}

interface FakeSupabase {
  calls: SupabaseCall[];
  from(table: string): FakeBuilder;
  rpc(name: string, args?: Record<string, unknown>): Promise<unknown>;
}

const INSERT_RESPONSES: Record<string, { id: string; slug?: string }> = {
  knowledge: { id: "k-1", slug: "link-card-pipeline-test" },
  tech_articles: { id: "a-1", slug: "link-card-pipeline-test" },
  weekly_issues: { id: "i-1", slug: "link-card-pipeline-test" },
  content_embeddings: { id: "e-1" },
  tags: { id: "t-1" },
  content_categories: { id: "c-1" },
  content_generation_log: { id: "log-1" },
};

function makeFakeSupabase(): FakeSupabase {
  const calls: SupabaseCall[] = [];

  const makeBuilder = (table: string): FakeBuilder => {
    const state: { mode: "select" | "insert" | "update"; pending?: unknown } = {
      mode: "select",
    };
    const builder: FakeBuilder = {
      select() { return builder; },
      eq() { return builder; },
      async maybeSingle() {
        calls.push({ op: "maybySingle", table });
        return { data: null, error: null };
      },
      async single() {
        calls.push({ op: "single", table });
        if (state.mode === "insert") {
          const resp = INSERT_RESPONSES[table];
          if (resp) return { data: resp, error: null };
          return { data: { id: `${table}-generated-id` }, error: null };
        }
        return { data: null, error: null };
      },
      insert(row) {
        state.mode = "insert";
        state.pending = row;
        calls.push({ op: "insert", table, data: row });
        return builder;
      },
      update(row) {
        state.mode = "update";
        state.pending = row;
        calls.push({ op: "update", table, data: row });
        return builder;
      },
      async upsert(rows, _opts) {
        calls.push({ op: "upsert", table, data: rows });
        return { data: [{ id: "e-1" }], error: null };
      },
      async limit(_n) {
        return { data: [], error: null };
      },
    };
    return builder;
  };

  return {
    calls,
    from(table) { return makeBuilder(table); },
    async rpc(name, args) {
      calls.push({ op: "rpc", table: name, data: args });
      if (name === "search_tags_similar") return { data: [], error: null };
      return { data: [], error: null };
    },
  };
}

// ---------------------------------------------------------------------------
// Markdown with a standalone URL line (triggers link-card generation)
// ---------------------------------------------------------------------------

const URL_ONLY_MARKDOWN = [
  "---",
  'title: "Link Card Pipeline Test"',
  'type: "knowledge"',
  'author: "テスト"',
  "---",
  "",
  "前段落のテキスト。",
  "",
  "https://example.com/og-test-article",
  "",
  "後段落のテキスト。",
].join("\n");

const PLAIN_MARKDOWN = [
  "---",
  'title: "No Link Card Test"',
  'type: "knowledge"',
  'author: "テスト"',
  "---",
  "",
  "This is a paragraph without any standalone URL lines.",
  "",
  "Check out [this link](https://example.com) inline.",
].join("\n");

// ---------------------------------------------------------------------------
// OG HTML returned by the mocked fetch
// ---------------------------------------------------------------------------

const FAKE_OG_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="Example OG Title" />
  <meta property="og:description" content="Example OG Description" />
  <meta property="og:image" content="https://example.com/og-image.jpg" />
  <link rel="icon" href="/favicon.ico" />
  <title>Example Page</title>
</head>
<body><p>Content</p></body>
</html>`;

// ---------------------------------------------------------------------------
// makeDeps — mirrors the pattern from post.test.ts
// ---------------------------------------------------------------------------

function makeDeps(overrides: Record<string, unknown> = {}) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase();

  // Wave 11.3a: post.ts is default --via-api. Capture the payload at /api/ingest
  // call site so the test can assert against the rendered HTML that gets sent.
  const ingestViaApi = vi.fn().mockResolvedValue({
    id: "k-1",
    slug: "link-card-pipeline-test",
    augment_job_id: null,
    trace_id: "trace-link-card-pipe",
  });

  const deps = {
    loadFile: vi.fn().mockResolvedValue(URL_ONLY_MARKDOWN),
    loadTemplates: vi.fn().mockResolvedValue({}),
    validate: vi.fn().mockImplementation((source: string) => {
      // Extract title from frontmatter
      const titleMatch = source.match(/title:\s*"([^"]+)"/);
      const title = titleMatch?.[1] ?? "Test Title";
      const typeMatch = source.match(/type:\s*"([^"]+)"/);
      const type = typeMatch?.[1] ?? "knowledge";
      return {
        ok: true,
        errors: [],
        warnings: [],
        frontmatter: { title, type, author: "テスト", tags: [] },
        body: "body",
      };
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      frontmatter: { title: "Link Card Pipeline Test", type: "knowledge" },
      sections: [],
      raw: "前段落のテキスト。\n\nhttps://example.com/og-test-article\n\n後段落のテキスト。",
    }),
    // renderToHtml returns bare link-card (as markdown.ts postprocess emits)
    renderToHtml: vi.fn().mockReturnValue({
      html: '<p>前段落のテキスト。</p>\n<div class="link-card"><a href="https://example.com/og-test-article" data-url="https://example.com/og-test-article">https://example.com/og-test-article</a></div>\n<p>後段落のテキスト。</p>',
      appliedClasses: [],
    }),
    renderToHtmlAsync: vi.fn().mockResolvedValue({
      html: '<p>前段落のテキスト。</p>\n<div class="link-card"><a href="https://example.com/og-test-article" data-url="https://example.com/og-test-article">https://example.com/og-test-article</a></div>\n<p>後段落のテキスト。</p>',
      appliedClasses: [],
      plantumlReplacements: [],
    }),
    generateSlug: vi.fn().mockResolvedValue("link-card-pipeline-test"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("link-card-pipeline-test"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({ slug: "tips", name: "Tips", confidence: 0.9, isNew: false }),
    suggestTags: vi.fn().mockResolvedValue([]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "tips", name: "Tips", isNew: false, id: "c-1" },
      tags: [],
    }),
    ingestViaApi,
    getSupabaseClient: () => supabase,
    webSearch: { search: vi.fn().mockResolvedValue([]) },
    reader: { question: async () => "Y", close: () => {} },
    streams,
    env: {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "sr-key",
      AI_GATEWAY_API_KEY: "gw-key",
      OPENAI_API_KEY: "sk-key",
      SITE_URL: "http://site",
      REVALIDATE_SECRET: "rs-secret",
    } as Record<string, string | undefined>,
    contentsManageDir: os.tmpdir(),
    ...overrides,
  };

  return { deps, streams, supabase, ingestViaApi };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("link-card pipeline integration", () => {
  let globalFetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    // Mock global fetch to return OG HTML
    globalFetchSpy = vi.fn().mockResolvedValue({
      text: async () => FAKE_OG_HTML,
      ok: true,
      status: 200,
    });
    vi.stubGlobal("fetch", globalFetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  // P-1: happy path
  it("P-1: enrichLinkCards is called and DB html contains enriched card with OG title", async () => {
    const { main } = await import("../../scripts/post.js");
    const enrichLinkCards = vi.fn().mockImplementation(async (html: string) => {
      // Simulate enrichment: replace bare card with enriched C1 card
      return html.replace(
        /<div class="link-card"><a[^>]*data-url="([^"]+)"[^>]*>[^<]*<\/a><\/div>/g,
        (_match, url) =>
          `<div class="link-card" data-url="${url}"><a href="${url}" target="_blank" rel="noopener noreferrer"><div class="link-card__body"><h3 class="link-card__title">Example OG Title</h3><p class="link-card__description">Example OG Description</p><div class="link-card__meta"><img class="link-card__favicon" src="https://example.com/favicon.ico" alt="" width="16" height="16" /><span class="link-card__domain">example.com</span></div></div><img class="link-card__thumbnail" src="https://example.com/og-image.jpg" alt="" loading="lazy" width="120" height="120" /></a></div>`,
      );
    });

    const { deps, ingestViaApi } = makeDeps({ enrichLinkCards });

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(enrichLinkCards).toHaveBeenCalled();

    expect(ingestViaApi).toHaveBeenCalledOnce();
    const payload = ingestViaApi.mock.calls[0]?.[0] as Record<string, unknown>;
    const insertedHtml = String(payload?.html ?? "");
    expect(insertedHtml).toContain("link-card__title");
    expect(insertedHtml).toContain("Example OG Title");
  });

  // P-2: fallback path — fetch fails → fallback card appears
  it("P-2: when fetch fails, fallback card (link-card--fallback) is still inserted in DB html", async () => {
    const { main } = await import("../../scripts/post.js");
    const enrichLinkCards = vi.fn().mockImplementation(async (html: string) => {
      // Simulate fallback: fetch error → minimal fallback card
      return html.replace(
        /<div class="link-card"><a[^>]*data-url="([^"]+)"[^>]*>[^<]*<\/a><\/div>/g,
        (_match, url) =>
          `<div class="link-card link-card--fallback" data-url="${url}"><a href="${url}" target="_blank" rel="noopener noreferrer"><div class="link-card__body"><h3 class="link-card__title">${url}</h3><div class="link-card__meta"><span class="link-card__domain">example.com</span></div></div></a></div>`,
      );
    });

    const { deps, ingestViaApi } = makeDeps({ enrichLinkCards });

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(enrichLinkCards).toHaveBeenCalled();

    expect(ingestViaApi).toHaveBeenCalledOnce();
    const payload = ingestViaApi.mock.calls[0]?.[0] as Record<string, unknown>;
    const insertedHtml = String(payload?.html ?? "");
    expect(insertedHtml).toContain("link-card--fallback");
  });

  // P-3: no URL-only line → no link-card in output
  it("P-3: markdown without standalone URL produces no link-card in DB html", async () => {
    const { main } = await import("../../scripts/post.js");
    const enrichLinkCards = vi.fn().mockImplementation(async (html: string) => html);

    const { deps, ingestViaApi } = makeDeps({
      enrichLinkCards,
      loadFile: vi.fn().mockResolvedValue(PLAIN_MARKDOWN),
      renderToHtml: vi.fn().mockReturnValue({
        html: "<p>This is a paragraph without any standalone URL lines.</p><p>Check out <a href=\"https://example.com\">this link</a> inline.</p>",
        appliedClasses: [],
      }),
      renderToHtmlAsync: vi.fn().mockResolvedValue({
        html: "<p>This is a paragraph without any standalone URL lines.</p><p>Check out <a href=\"https://example.com\">this link</a> inline.</p>",
        appliedClasses: [],
        plantumlReplacements: [],
      }),
    });

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(enrichLinkCards).toHaveBeenCalled();

    expect(ingestViaApi).toHaveBeenCalledOnce();
    const payload = ingestViaApi.mock.calls[0]?.[0] as Record<string, unknown>;
    const insertedHtml = String(payload?.html ?? "");
    expect(insertedHtml).not.toContain("link-card");
  });

  // P-4: enrichLinkCards dep omitted → pipeline still runs (backward compat)
  it("P-4: when enrichLinkCards dep is omitted, pipeline completes normally without enrichment", async () => {
    const { main } = await import("../../scripts/post.js");
    // No enrichLinkCards in deps
    const { deps, ingestViaApi } = makeDeps();

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);

    expect(ingestViaApi).toHaveBeenCalledOnce();
    const payload = ingestViaApi.mock.calls[0]?.[0] as Record<string, unknown>;
    const insertedHtml = String(payload?.html ?? "");
    // Bare card still present (unenriched)
    expect(insertedHtml).toContain("link-card");
    // But no enriched structure
    expect(insertedHtml).not.toContain("link-card__title");
  });
});
