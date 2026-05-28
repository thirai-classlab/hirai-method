/**
 * Tests for scripts/post.ts — Wave 11.3a: --via-api default ON + Augment 4 ステップ削除
 *
 * 設計 v2: post.ts は POST /api/ingest 経由を default 動作とし、
 *           runOne 内の NER/auto-knowledge / findRelated+linkRelated /
 *           insertLinks / revalidateSite を runtime から外す。
 *
 * テスト観点:
 *   1. --via-api フラグなし → POST /api/ingest が呼ばれる (default true)
 *   2. --via-api フラグなし + payload mapping (type / title / slug / html / tags / category_slug / depth)
 *   3. --via-api フラグなし + ingestViaApi が失敗 → exit 2
 *   4. --dry-run → ingestViaApi も Supabase direct INSERT も呼ばれない
 *   5. PostDeps から削除されたモジュールが import されていないこと
 *      (extractEntities / processEntities / findRelated / linkRelated /
 *       insertLinks / revalidateSite / commitCategoryAndTags は deps に存在しない)
 *   6. 保護対象モジュール (#41 version-manager / #32 thumbnail-hearing /
 *      #39 link-card-extractor) は deps に維持されている
 *   7. 旧 Augment 系 mock が deps に渡されていなくても run できる
 *      (= post.ts 側で参照されていない)
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
    write(line: string) {
      out.push(line);
    },
    writeErr(line: string) {
      err.push(line);
    },
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
      select() {
        return builder;
      },
      eq(col, val) {
        state.filters.push({ col, val });
        return builder;
      },
      async maybeSingle() {
        const rows = existingRows[table] ?? [];
        const match = rows.find((r) =>
          state.filters.every((f) => r[f.col] === f.val),
        );
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
        const match = rows.find((r) =>
          state.filters.every((f) => r[f.col] === f.val),
        );
        return match
          ? { data: match, error: null }
          : { data: null, error: null };
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
    from(table: string) {
      return makeBuilder(table);
    },
    async rpc(name: string, args?: Record<string, unknown>) {
      calls.push({ op: "rpc", table: name, args });
      return { data: [], error: null };
    },
  };
}

const GOOD_FRONTMATTER = [
  "---",
  'title: "Default Via API Article"',
  'type: "knowledge"',
  'author: "平井拓真"',
  'tags:',
  '  - "nextjs"',
  '  - "cache"',
  "---",
  "",
  "本文".repeat(200),
].join("\n");

const MOCK_INGEST_RESULT = {
  id: "api-k-1",
  slug: "default-via-api-article",
  augment_job_id: null,
  trace_id: "trace-default-001",
};

function makeDeps(overrides: Record<string, unknown> = {}) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    insertResponses: {
      knowledge: { id: "k-1", slug: "default-via-api-article" },
      tech_articles: { id: "a-1", slug: "default-via-api-article" },
      weekly_issues: { id: "i-1", slug: "default-via-api-article" },
      tags: { id: "t-1" },
      content_categories: { id: "c-1" },
    },
  });

  const deps = {
    loadFile: vi.fn().mockResolvedValue(GOOD_FRONTMATTER),
    loadTemplates: vi.fn().mockResolvedValue({}),
    validate: vi.fn().mockReturnValue({
      ok: true,
      errors: [],
      warnings: [],
      frontmatter: {
        title: "Default Via API Article",
        type: "knowledge",
        author: "平井拓真",
        tags: ["nextjs", "cache"],
      },
      body: "本文".repeat(200),
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      frontmatter: { title: "Default Via API Article", type: "knowledge" },
      sections: [],
      raw: "本文",
    }),
    renderToHtml: vi
      .fn()
      .mockReturnValue({ html: "<p>本文</p>", appliedClasses: [] }),
    renderToHtmlAsync: vi.fn().mockResolvedValue({
      html: "<p>本文</p>",
      appliedClasses: [],
      plantumlReplacements: [],
    }),
    generateSlug: vi.fn().mockResolvedValue("default-via-api-article"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("default-via-api-article"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi
      .fn()
      .mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({
      slug: "tips",
      name: "Tips",
      confidence: 0.9,
      isNew: false,
    }),
    suggestTags: vi.fn().mockResolvedValue([
      { name: "nextjs", confidence: 0.9 },
      { name: "cache", confidence: 0.85 },
    ]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([
      {
        kind: "existing",
        id: "t-1",
        name: "nextjs",
        usageCount: 3,
        confidence: 0.9,
      },
      { kind: "new", name: "cache", confidence: 0.85 },
    ]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "tips", name: "Tips", isNew: false, id: "c-1" },
      tags: [
        { name: "nextjs", id: "t-1", isNew: false },
        { name: "cache", isNew: true },
      ],
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

describe("scripts/post.ts — Wave 11.3a: --via-api default + Augment removed", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("1. without any flag (default): calls ingestViaApi and skips Supabase direct INSERT", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { deps, supabase } = makeDeps({ ingestViaApi: mockIngestViaApi });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockIngestViaApi).toHaveBeenCalledOnce();
    // Direct INSERT into knowledge / tech_articles / weekly_issues must NOT happen.
    const directInserts = supabase.calls.filter(
      (c) =>
        c.op === "insert" &&
        (c.table === "knowledge" ||
          c.table === "tech_articles" ||
          c.table === "weekly_issues"),
    );
    expect(directInserts.length).toBe(0);
    // content_embeddings INSERT must NOT happen — Augment handles it.
    const embeddingInserts = supabase.calls.filter(
      (c) => c.op === "insert" && c.table === "content_embeddings",
    );
    expect(embeddingInserts.length).toBe(0);
  });

  it("2. default path: payload is correctly mapped (type, title, slug, html, tags, category_slug, depth)", async () => {
    const { main } = await import("../../scripts/post.js");

    let capturedPayload: unknown = null;
    const mockIngestViaApi = vi.fn().mockImplementation((payload: unknown) => {
      capturedPayload = payload;
      return Promise.resolve(MOCK_INGEST_RESULT);
    });

    const { deps } = makeDeps({ ingestViaApi: mockIngestViaApi });

    await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(capturedPayload).toBeDefined();
    const p = capturedPayload as Record<string, unknown>;
    expect(p.type).toBe("knowledge");
    expect(p.title).toBe("Default Via API Article");
    expect(p.slug).toBe("default-via-api-article");
    expect(p.html).toBe("<p>本文</p>");
    expect(Array.isArray(p.tag_ids)).toBe(true);
    expect((p.tag_ids as string[]).includes("t-1")).toBe(true);
    expect(Array.isArray(p.tag_names_new)).toBe(true);
    expect((p.tag_names_new as string[]).includes("cache")).toBe(true);
    expect(p.category_slug).toBe("tips");
    expect(p.depth).toBe(0);
  });

  it("3. default path: returns exit 2 when ingestViaApi throws", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi
      .fn()
      .mockRejectedValue(new Error("API 500: database_error"));
    const { deps } = makeDeps({ ingestViaApi: mockIngestViaApi });

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(2);
  });

  it("4. with --dry-run: neither direct INSERT nor ingestViaApi is called", async () => {
    const { main } = await import("../../scripts/post.js");

    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { deps, supabase } = makeDeps({ ingestViaApi: mockIngestViaApi });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve", "--dry-run"],
      deps,
    );

    expect(code).toBe(0);
    expect(mockIngestViaApi).not.toHaveBeenCalled();
    const inserts = supabase.calls.filter((c) => c.op === "insert");
    expect(inserts.length).toBe(0);
  });

  it("5. dropped Augment modules are NOT imported by post.ts", async () => {
    // Ensure source file does not contain stale imports that would pull in
    // the deleted modules.
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    const src = await fs.readFile(
      path.resolve(process.cwd(), "scripts/post.ts"),
      "utf-8",
    );
    expect(src).not.toMatch(/from ["'].*posting\/auto-knowledge-gen/);
    expect(src).not.toMatch(/from ["'].*posting\/auto-relate/);
    expect(src).not.toMatch(/from ["'].*posting\/auto-link/);
    expect(src).not.toMatch(/from ["'].*posting\/revalidate/);
    expect(src).not.toMatch(/from ["'].*posting\/ner/);
    // commitCategoryAndTags is dropped — it must not appear on the import line.
    // (suggestCategory/suggestTags/resolveTagAgainstMasters/confirmInteractively
    //  are kept, so we only check the specific symbol.)
    expect(src).not.toMatch(/\bcommitCategoryAndTags\b/);
  });

  it("6. protected modules (#32 #39 #41) remain wired into the post pipeline", async () => {
    const fs = await import("node:fs/promises");
    const path = await import("node:path");
    // Task #56 W3: protected modules now live in scripts/stages/ (extracted
    // from post.ts) — grep across the whole scripts/ tree so we still detect
    // any accidental removal of the #32/#39/#41 hooks.
    const scriptsDir = path.resolve(process.cwd(), "scripts");
    const collect = async (dir: string): Promise<string[]> => {
      const out: string[] = [];
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const ent of entries) {
        const full = path.join(dir, ent.name);
        if (ent.isDirectory()) {
          out.push(...(await collect(full)));
        } else if (ent.isFile() && ent.name.endsWith(".ts")) {
          out.push(await fs.readFile(full, "utf-8"));
        }
      }
      return out;
    };
    const allSrc = (await collect(scriptsDir)).join("\n");
    // #41 snapshot-before-update / version manager
    expect(allSrc).toMatch(/version-manager/);
    expect(allSrc).toMatch(/snapshotBeforeUpdate/);
    // #32 thumbnail hearing
    expect(allSrc).toMatch(/thumbnail-hearing/);
    expect(allSrc).toMatch(/runThumbnailHearing/);
    // #39 link-card extractor
    expect(allSrc).toMatch(/link-card-extractor/);
    expect(allSrc).toMatch(/enrichLinkCards/);
  });

  it("7. PostDeps no longer requires removed Augment hooks (deps without them still works)", async () => {
    // Build deps WITHOUT extractEntities/processEntities/findRelated/linkRelated/
    // insertLinks/revalidateSite/commitCategoryAndTags. If post.ts still
    // references these, it will throw "X is not a function".
    const mockIngestViaApi = vi.fn().mockResolvedValue(MOCK_INGEST_RESULT);
    const { main } = await import("../../scripts/post.js");
    const { deps } = makeDeps({ ingestViaApi: mockIngestViaApi });
    // Sanity: makeDeps does not include the removed ones at all.
    expect((deps as Record<string, unknown>).extractEntities).toBeUndefined();
    expect((deps as Record<string, unknown>).processEntities).toBeUndefined();
    expect((deps as Record<string, unknown>).findRelated).toBeUndefined();
    expect((deps as Record<string, unknown>).linkRelated).toBeUndefined();
    expect((deps as Record<string, unknown>).insertLinks).toBeUndefined();
    expect((deps as Record<string, unknown>).revalidateSite).toBeUndefined();
    expect(
      (deps as Record<string, unknown>).commitCategoryAndTags,
    ).toBeUndefined();

    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );
    expect(code).toBe(0);
  });
});
