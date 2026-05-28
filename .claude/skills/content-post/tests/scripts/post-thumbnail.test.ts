/**
 * Tests for scripts/post.ts — #30 frontmatter thumbnail → S3 → /api/ingest
 *
 * テスト観点:
 *   1. frontmatter に thumbnail: ./cover.png → S3 upload → CDN URL が payload にセット
 *   2. frontmatter に thumbnail: https://d2f75plg0t6qwk.cloudfront.net/foo.jpg → そのまま payload にセット
 *   3. frontmatter 省略 → thumbnail_url: null / thumbnail_alt: null
 *   4. thumbnail_alt の optional 挙動（frontmatter に thumbnail のみ、alt なし）
 *   5. S3 upload エラー時のフォールバック（thumbnail_url: null で継続）
 *   6. thumbnail があっても --dry-run 時は upload しない
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Shared fakes (mirrored from post-via-api.test.ts)
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
    write(line: string) { out.push(line); },
    writeErr(line: string) { err.push(line); },
  };
}

type SupabaseCall = { op: string; table?: string; args?: unknown };

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

function makeFakeSupabase(cfg: {
  existingRows?: Record<string, Array<Record<string, unknown>>>;
  insertResponses?: Record<string, { id: string; slug?: string }>;
} = {}) {
  const existingRows = cfg.existingRows ?? {};
  const insertResponses = cfg.insertResponses ?? {};
  const calls: SupabaseCall[] = [];

  const makeBuilder = (table: string): FakeBuilder => {
    const state: {
      mode: "select" | "insert" | "update" | "upsert";
      filters: Array<{ col: string; val: unknown }>;
      pending?: unknown;
    } = { mode: "select", filters: [] };
    const builder: FakeBuilder = {
      select() { return builder; },
      eq(col, val) {
        state.filters.push({ col, val });
        return builder;
      },
      async maybeSingle() {
        const rows = existingRows[table] ?? [];
        const match = rows.find((r) => state.filters.every((f) => r[f.col] === f.val));
        calls.push({ op: "maybeSingle", table, args: { ...state } });
        return { data: match ?? null, error: null };
      },
      async single() {
        calls.push({ op: "single", table, args: { ...state } });
        if (state.mode === "insert") {
          const resp = insertResponses[table];
          if (resp) return { data: resp, error: null };
          return { data: { id: `${table}-generated-id` }, error: null };
        }
        const rows = existingRows[table] ?? [];
        const match = rows.find((r) => state.filters.every((f) => r[f.col] === f.val));
        return match ? { data: match, error: null } : { data: null, error: null };
      },
      insert(row) {
        state.mode = "insert";
        state.pending = row;
        calls.push({ op: "insert", table, args: row });
        return builder;
      },
      update(row) {
        state.mode = "update";
        state.pending = row;
        calls.push({ op: "update", table, args: row });
        return builder;
      },
      async upsert(rows, opts) {
        calls.push({ op: "upsert", table, args: { rows, opts } });
        return { data: rows, error: null };
      },
      async limit(_n) {
        calls.push({ op: "limit", table });
        return { data: existingRows[table] ?? [], error: null };
      },
    };
    return builder;
  };

  return {
    calls,
    insertResponses,
    from(table: string) { return makeBuilder(table); },
    async rpc(name: string, args?: Record<string, unknown>) {
      calls.push({ op: "rpc", table: name, args });
      return { data: [], error: null };
    },
  };
}

const MOCK_INGEST_RESULT = {
  id: "api-k-1",
  slug: "test-article",
  augment_job_id: null,
  trace_id: "trace-abc-123",
};

function makeBaseFrontmatter(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: "Test Article",
    type: "knowledge",
    author: "テスト",
    tags: ["tag1"],
    ...extra,
  };
}

function makeDeps(
  frontmatterExtra: Record<string, unknown> = {},
  overrides: Record<string, unknown> = {},
) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    insertResponses: {
      knowledge: { id: "k-1", slug: "test-article" },
      tech_articles: { id: "a-1", slug: "test-article" },
      weekly_issues: { id: "i-1", slug: "test-article" },
      content_embeddings: { id: "e-1" },
      tags: { id: "t-1" },
      content_categories: { id: "c-1" },
      content_generation_log: { id: "log-1" },
    },
  });

  const fm = makeBaseFrontmatter(frontmatterExtra);

  const deps = {
    loadFile: vi.fn().mockResolvedValue("---\ntitle: Test Article\n---\nbody"),
    loadTemplates: vi.fn().mockResolvedValue({}),
    validate: vi.fn().mockReturnValue({
      ok: true,
      errors: [],
      warnings: [],
      frontmatter: fm,
      body: "body",
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      frontmatter: fm,
      sections: [],
      raw: "body",
    }),
    renderToHtml: vi.fn().mockReturnValue({ html: "<p>body</p>", appliedClasses: [] }),
    renderToHtmlAsync: vi.fn().mockResolvedValue({
      html: "<p>body</p>",
      appliedClasses: [],
      plantumlReplacements: [],
    }),
    generateSlug: vi.fn().mockResolvedValue("test-article"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("test-article"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({ slug: "tips", name: "Tips", confidence: 0.9, isNew: false }),
    suggestTags: vi.fn().mockResolvedValue([{ name: "tag1", confidence: 0.9 }]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([
      { kind: "existing", id: "t-1", name: "tag1", usageCount: 1, confidence: 0.9 },
    ]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "tips", name: "Tips", isNew: false, id: "c-1" },
      tags: [{ name: "tag1", id: "t-1", isNew: false }],
    }),
    // Wave 11.3a: post.ts is default --via-api. Mock ingestViaApi by default.
    ingestViaApi: vi.fn().mockResolvedValue({
      id: "k-1",
      slug: "test-article",
      augment_job_id: null,
      trace_id: "trace-thumb-test",
    }),
    getSupabaseClient: () => supabase,
    webSearch: { search: vi.fn().mockResolvedValue([]) },
    reader: { question: async () => "Y", close: () => {} },
    streams,
    env: {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "sr-key",
      AI_GATEWAY_API_KEY: "gw-key",
      SITE_URL: "http://site",
      REVALIDATE_SECRET: "rs-secret",
    } as Record<string, string | undefined>,
    ...overrides,
  };
  return { deps, streams, supabase };
}

// ---------------------------------------------------------------------------
// Helper: build deps with a specific content type
// ---------------------------------------------------------------------------

function makeDepsForType(
  contentType: "knowledge" | "tech_articles" | "weekly_issues",
  frontmatterExtra: Record<string, unknown> = {},
  overrides: Record<string, unknown> = {},
) {
  // Build type-appropriate base frontmatter
  const baseFm: Record<string, unknown> = {
    title: "Test Article",
    type: contentType,
    author: "テスト",
    tags: ["tag1"],
    ...(contentType === "tech_articles" ? { subtype: "deepdive" } : {}),
    ...(contentType === "weekly_issues"
      ? {
          period_start: "2026-04-01T00:00:00Z",
          period_end: "2026-04-07T00:00:00Z",
        }
      : {}),
    ...frontmatterExtra,
  };

  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    insertResponses: {
      knowledge: { id: "k-1", slug: "test-article" },
      tech_articles: { id: "a-1", slug: "test-article" },
      weekly_issues: { id: "i-1", slug: "test-article" },
      content_embeddings: { id: "e-1" },
      tags: { id: "t-1" },
      content_categories: { id: "c-1" },
      content_generation_log: { id: "log-1" },
    },
  });

  const deps = {
    loadFile: vi.fn().mockResolvedValue("---\ntitle: Test Article\n---\nbody"),
    loadTemplates: vi.fn().mockResolvedValue({}),
    validate: vi.fn().mockReturnValue({
      ok: true,
      errors: [],
      warnings: [],
      frontmatter: baseFm,
      body: "body",
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      frontmatter: baseFm,
      sections: [],
      raw: "body",
    }),
    renderToHtml: vi.fn().mockReturnValue({ html: "<p>body</p>", appliedClasses: [] }),
    renderToHtmlAsync: vi.fn().mockResolvedValue({
      html: "<p>body</p>",
      appliedClasses: [],
      plantumlReplacements: [],
    }),
    generateSlug: vi.fn().mockResolvedValue("test-article"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("test-article"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({ slug: "tips", name: "Tips", confidence: 0.9, isNew: false }),
    suggestTags: vi.fn().mockResolvedValue([{ name: "tag1", confidence: 0.9 }]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([
      { kind: "existing", id: "t-1", name: "tag1", usageCount: 1, confidence: 0.9 },
    ]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "tips", name: "Tips", isNew: false, id: "c-1" },
      tags: [{ name: "tag1", id: "t-1", isNew: false }],
    }),
    // Wave 11.3a: post.ts is default --via-api. Mock ingestViaApi by default.
    ingestViaApi: vi.fn().mockResolvedValue({
      id: "k-1",
      slug: "test-article",
      augment_job_id: null,
      trace_id: "trace-thumb-test",
    }),
    getSupabaseClient: () => supabase,
    webSearch: { search: vi.fn().mockResolvedValue([]) },
    reader: { question: async () => "Y", close: () => {} },
    streams,
    env: {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "sr-key",
      AI_GATEWAY_API_KEY: "gw-key",
      SITE_URL: "http://site",
      REVALIDATE_SECRET: "rs-secret",
    } as Record<string, string | undefined>,
    ...overrides,
  };
  return { deps, streams, supabase };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scripts/post.ts — #30 thumbnail frontmatter support", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("1. local thumbnail path → uploadThumbnail called → CDN URL in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const cdnUrl = "https://d2f75plg0t6qwk.cloudfront.net/issue/test-article/cover.png";
    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: cdnUrl });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      { thumbnail: "./cover.png", thumbnail_alt: "カバー画像" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(mockUploadThumbnail).toHaveBeenCalledOnce();
    expect(capturedPayload).toBeDefined();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(cdnUrl);
    expect(p.thumbnail_alt).toBe("カバー画像");
  });

  it("2. remote URL thumbnail → passed through directly, no upload", async () => {
    const { main } = await import("../../scripts/post.js");

    const remoteUrl = "https://d2f75plg0t6qwk.cloudfront.net/foo.jpg";
    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: "should-not-be-called" });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      { thumbnail: remoteUrl, thumbnail_alt: "Remote image" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(mockUploadThumbnail).not.toHaveBeenCalled();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(remoteUrl);
    expect(p.thumbnail_alt).toBe("Remote image");
  });

  it("3. no thumbnail in frontmatter → thumbnail_url: null, thumbnail_alt: null in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { deps } = makeDeps({}, { ingestViaApi: mockIngestViaApi });

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBeNull();
    expect(p.thumbnail_alt).toBeNull();
  });

  it("4. thumbnail set but thumbnail_alt omitted → thumbnail_alt: null", async () => {
    const { main } = await import("../../scripts/post.js");

    const cdnUrl = "https://d2f75plg0t6qwk.cloudfront.net/foo.jpg";
    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: "x" });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      { thumbnail: cdnUrl },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(cdnUrl);
    expect(p.thumbnail_alt).toBeNull();
  });

  it("5. S3 upload error → thumbnail_url: null, pipeline continues (exit 0)", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockUploadThumbnail = vi.fn().mockRejectedValue(new Error("S3 upload failed"));
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      { thumbnail: "./cover.png" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBeNull();
  });

  it("6. --dry-run with thumbnail → uploadThumbnail not called, ingestViaApi not called", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: "x" });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      { thumbnail: "./cover.png" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve", "--dry-run"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockUploadThumbnail).not.toHaveBeenCalled();
    expect(mockIngestViaApi).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// tech_articles thumbnail support
// ---------------------------------------------------------------------------

describe("scripts/post.ts — #30 thumbnail support for tech_articles", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("7. tech_articles: local thumbnail → uploadThumbnail called with contentType=tech_article → CDN URL in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const cdnUrl = "https://d2f75plg0t6qwk.cloudfront.net/tech_article/test-article/thumbnail-abc-cover.png";
    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: cdnUrl });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDepsForType(
      "tech_articles",
      { thumbnail: "./cover.png", thumbnail_alt: "技術記事カバー" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockUploadThumbnail).toHaveBeenCalledOnce();
    // contentType should be mapped to "tech_article" (singular)
    const uploadCall = mockUploadThumbnail.mock.calls[0] as [string, { slug: string; contentType: string }];
    expect(uploadCall[1].contentType).toBe("tech_article");
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(cdnUrl);
    expect(p.thumbnail_alt).toBe("技術記事カバー");
    // ingest payload type should be "article"
    expect(p.type).toBe("article");
  });

  it("8. tech_articles: no thumbnail → thumbnail_url: null, thumbnail_alt: null in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { deps } = makeDepsForType("tech_articles", {}, { ingestViaApi: mockIngestViaApi });

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBeNull();
    expect(p.thumbnail_alt).toBeNull();
    expect(p.type).toBe("article");
  });

  it("9. tech_articles: remote URL thumbnail → passed through directly, no upload", async () => {
    const { main } = await import("../../scripts/post.js");

    const remoteUrl = "https://d2f75plg0t6qwk.cloudfront.net/tech_article/foo.jpg";
    const mockUploadThumbnail = vi.fn();
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDepsForType(
      "tech_articles",
      { thumbnail: remoteUrl, thumbnail_alt: "Remote" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(mockUploadThumbnail).not.toHaveBeenCalled();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(remoteUrl);
    expect(p.thumbnail_alt).toBe("Remote");
  });
});

// ---------------------------------------------------------------------------
// weekly_issues thumbnail support
// ---------------------------------------------------------------------------

describe("scripts/post.ts — #30 thumbnail support for weekly_issues", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("10. weekly_issues: local thumbnail → uploadThumbnail called with contentType=issue → CDN URL in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const cdnUrl = "https://d2f75plg0t6qwk.cloudfront.net/issue/test-article/thumbnail-abc-cover.png";
    const mockUploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: cdnUrl });
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDepsForType(
      "weekly_issues",
      { thumbnail: "./cover.png", thumbnail_alt: "号表紙" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockUploadThumbnail).toHaveBeenCalledOnce();
    // contentType should be mapped to "issue" (singular)
    const uploadCall = mockUploadThumbnail.mock.calls[0] as [string, { slug: string; contentType: string }];
    expect(uploadCall[1].contentType).toBe("issue");
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBe(cdnUrl);
    expect(p.thumbnail_alt).toBe("号表紙");
    // ingest payload type should be "issue"
    expect(p.type).toBe("issue");
  });

  it("11. weekly_issues: no thumbnail → thumbnail_url: null, thumbnail_alt: null in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { deps } = makeDepsForType("weekly_issues", {}, { ingestViaApi: mockIngestViaApi });

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBeNull();
    expect(p.thumbnail_alt).toBeNull();
    expect(p.type).toBe("issue");
  });

  it("12. weekly_issues: S3 upload error → thumbnail_url: null, pipeline continues (exit 0)", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockUploadThumbnail = vi.fn().mockRejectedValue(new Error("S3 upload failed"));
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDepsForType(
      "weekly_issues",
      { thumbnail: "./cover.png" },
      { uploadThumbnail: mockUploadThumbnail, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/article/index.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    const p = capturedPayload as Record<string, unknown>;
    expect(p.thumbnail_url).toBeNull();
  });
});
