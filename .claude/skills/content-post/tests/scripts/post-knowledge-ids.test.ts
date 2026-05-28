/**
 * Tests for scripts/post.ts — #29 weekly_issue → knowledge_ids auto-link
 *
 * テスト観点:
 *   1. contentType="weekly_issues" で embedding あり → searchSimilar 呼ばれる → knowledge フィルタ → Top3 取得 → payload に knowledge_ids
 *   2. contentType="knowledge" → searchSimilar 呼ばれない、payload の knowledge_ids は undefined
 *   3. contentType="tech_articles" → searchSimilar 呼ばれない、payload の knowledge_ids は undefined
 *   4. searchSimilar が 0 件 → knowledge_ids は undefined
 *   5. knowledge が 2 件のみ → Top2 取得
 *   6. threshold 未達の結果は除外される（similarity < 0.7）
 *   7. knowledge 以外の content_type はフィルタされる（issue/article は除外）
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Shared fakes
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
  id: "api-i-1",
  slug: "weekly-issue-2026-04-21",
  augment_job_id: null,
  trace_id: "trace-xyz",
};

function makeDeps(
  contentTypeOverride: string = "weekly_issues",
  extraFrontmatter: Record<string, unknown> = {},
  overrides: Record<string, unknown> = {},
) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    insertResponses: {
      knowledge: { id: "k-1", slug: "test" },
      tech_articles: { id: "a-1", slug: "test" },
      weekly_issues: { id: "i-1", slug: "test" },
      content_embeddings: { id: "e-1" },
      tags: { id: "t-1" },
      content_categories: { id: "c-1" },
      content_generation_log: { id: "log-1" },
    },
  });

  const fm: Record<string, unknown> = {
    title: "Weekly Tech News 2026-04-21",
    type: contentTypeOverride,
    author: "テスト",
    tags: ["weekly"],
    ...extraFrontmatter,
  };

  const deps = {
    loadFile: vi.fn().mockResolvedValue("---\ntitle: Weekly Tech News\n---\nbody"),
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
    generateSlug: vi.fn().mockResolvedValue("weekly-issue-2026-04-21"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("weekly-issue-2026-04-21"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({ slug: "weekly", name: "Weekly", confidence: 0.9, isNew: false }),
    suggestTags: vi.fn().mockResolvedValue([{ name: "weekly", confidence: 0.9 }]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([
      { kind: "existing", id: "t-1", name: "weekly", usageCount: 5, confidence: 0.9 },
    ]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "weekly", name: "Weekly", isNew: false, id: "c-1" },
      tags: [{ name: "weekly", id: "t-1", isNew: false }],
    }),
    // Wave 11.3a: post.ts is default --via-api. Mock ingestViaApi by default
    // so tests don't accidentally hit network / fail at exit code 2.
    ingestViaApi: vi.fn().mockResolvedValue(MOCK_INGEST_RESULT),
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

describe("scripts/post.ts — #29 weekly_issue → knowledge_ids auto-link", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("1. weekly_issues + embedding → searchSimilar called → knowledge Top3 in payload", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([
      { content_type: "knowledge", content_id: "k-uuid-1", similarity: 0.95 },
      { content_type: "knowledge", content_id: "k-uuid-2", similarity: 0.90 },
      { content_type: "knowledge", content_id: "k-uuid-3", similarity: 0.85 },
      { content_type: "knowledge", content_id: "k-uuid-4", similarity: 0.80 },
    ]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "weekly_issues",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/issue.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockSearchSimilar).toHaveBeenCalledOnce();
    const p = capturedPayload as Record<string, unknown>;
    expect(Array.isArray(p.knowledge_ids)).toBe(true);
    const ids = p.knowledge_ids as string[];
    // Top 3 only (not all 4)
    expect(ids.length).toBe(3);
    expect(ids).toContain("k-uuid-1");
    expect(ids).toContain("k-uuid-2");
    expect(ids).toContain("k-uuid-3");
    expect(ids).not.toContain("k-uuid-4");
  });

  it("2. contentType=knowledge → searchSimilar NOT called, knowledge_ids undefined", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "knowledge",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/k.md", "--auto-approve"],
      deps,
    );

    expect(mockSearchSimilar).not.toHaveBeenCalled();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.knowledge_ids).toBeUndefined();
  });

  it("3. contentType=tech_articles → searchSimilar NOT called, knowledge_ids undefined", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "tech_articles",
      { subtype: "deepdive" },
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/a.md", "--auto-approve"],
      deps,
    );

    expect(mockSearchSimilar).not.toHaveBeenCalled();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.knowledge_ids).toBeUndefined();
  });

  it("4. searchSimilar returns 0 results → knowledge_ids undefined", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "weekly_issues",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/issue.md", "--auto-approve"],
      deps,
    );

    expect(mockSearchSimilar).toHaveBeenCalledOnce();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.knowledge_ids).toBeUndefined();
  });

  it("5. only 2 knowledge results → knowledge_ids has 2 items", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([
      { content_type: "knowledge", content_id: "k-a", similarity: 0.92 },
      { content_type: "knowledge", content_id: "k-b", similarity: 0.88 },
    ]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "weekly_issues",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/issue.md", "--auto-approve"],
      deps,
    );

    const p = capturedPayload as Record<string, unknown>;
    expect(Array.isArray(p.knowledge_ids)).toBe(true);
    expect((p.knowledge_ids as string[]).length).toBe(2);
    expect(p.knowledge_ids).toContain("k-a");
    expect(p.knowledge_ids).toContain("k-b");
  });

  it("6. similarity below threshold (0.7) → excluded from knowledge_ids", async () => {
    const { main } = await import("../../scripts/post.js");

    // searchSimilar is called with threshold option; the dep implementation
    // itself filters. We return results that should have been filtered by the
    // caller passing threshold=0.7. Verify the pipeline passes threshold correctly.
    const mockSearchSimilar = vi.fn().mockImplementation(
      (_embedding: number[], opts: { threshold?: number }) => {
        // Simulate the threshold filtering that rag.searchSimilar does
        const allResults = [
          { content_type: "knowledge", content_id: "k-high", similarity: 0.85 },
          { content_type: "knowledge", content_id: "k-low", similarity: 0.65 },
        ];
        const threshold = opts.threshold ?? 0;
        return Promise.resolve(allResults.filter((r) => r.similarity >= threshold));
      },
    );
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "weekly_issues",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/issue.md", "--auto-approve"],
      deps,
    );

    // Verify searchSimilar was called with threshold: 0.7
    expect(mockSearchSimilar).toHaveBeenCalledWith(
      expect.any(Array),
      expect.objectContaining({ threshold: 0.7 }),
    );

    const p = capturedPayload as Record<string, unknown>;
    const ids = p.knowledge_ids as string[];
    expect(ids).toContain("k-high");
    expect(ids).not.toContain("k-low");
  });

  it("7. non-knowledge content_types filtered out (issue/article excluded)", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockSearchSimilar = vi.fn().mockResolvedValue([
      { content_type: "issue", content_id: "i-1", similarity: 0.95 },
      { content_type: "article", content_id: "a-1", similarity: 0.90 },
      { content_type: "knowledge", content_id: "k-1", similarity: 0.85 },
    ]);
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);

    const { deps } = makeDeps(
      "weekly_issues",
      {},
      { searchSimilar: mockSearchSimilar, ingestViaApi: mockIngestViaApi },
    );

    let capturedPayload: unknown = null;
    (deps.ingestViaApi as ReturnType<typeof vi.fn>).mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    await main(
      ["node", "post.ts", "--file", "/tmp/issue.md", "--auto-approve"],
      deps,
    );

    const p = capturedPayload as Record<string, unknown>;
    const ids = p.knowledge_ids as string[];
    expect(ids).toHaveLength(1);
    expect(ids).toContain("k-1");
    expect(ids).not.toContain("i-1");
    expect(ids).not.toContain("a-1");
  });
});
