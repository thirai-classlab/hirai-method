/**
 * Tests for scripts/post.ts — Phase 8 Wave E4 (8.E.10)
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e4/plan.md §8.E.10 テスト観点 (15)
 *
 *   1. 必須 env 欠損で early fail (exit 1)
 *   2. `--file` 欠損で usage error (exit 1)
 *   3. 正常系 dry-run → INSERT 呼ばれない
 *   4. 正常系 auto-approve → INSERT 呼ばれる
 *   5. `--force` で duplicate block を貫通
 *   6. duplicate block + `--force` なし → exit 3
 *   7. validate error → exit 1
 *   8. update モードで既存 fetch → title 書き換え
 *   9. update で対象 slug 存在しない → exit 1
 *   10. batch モードで 3 ファイル順次処理
 *   11. batch で 2 件目失敗 → 3 件目も実行
 *   12. revalidate 失敗でも INSERT は rollback しない（exit 0、warning のみ）
 *   13. `--no-revalidate` で revalidate スキップ
 *   14. `--verbose` で詳細ログ
 *   15. 監査ログ `content_generation_log` への INSERT
 *
 * モック戦略:
 *   scripts/post.ts は `main(argv, deps)` を export し、全ての外部境界 (LLM / embedding /
 *   supabase / webSearch / revalidate / fs / stdout) を deps で差し替え可能にする。
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import os from "node:os";

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

type SupabaseCall = {
  op: string;
  table?: string;
  args?: unknown;
};

interface FakeSupabase {
  calls: SupabaseCall[];
  insertResponses: Record<string, { id: string; slug?: string }>;
  from(table: string): FakeBuilder;
  rpc(name: string, args?: Record<string, unknown>): Promise<unknown>;
}

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
} = {}): FakeSupabase {
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
    from(table) {
      return makeBuilder(table);
    },
    async rpc(name, args) {
      calls.push({ op: "rpc", table: name, args });
      // Return empty-array default; tests override via vi.mock on rag module when needed.
      if (name === "search_tags_similar") return { data: [], error: null };
      return { data: [], error: null };
    },
  };
}

// ---------------------------------------------------------------------------
// Default frontmatter + markdown body used across happy-path tests.
// ---------------------------------------------------------------------------

const GOOD_FRONTMATTER = [
  "---",
  'title: "Test Article Title"',
  'type: "knowledge"',
  'author: "平井拓真"',
  'tags:',
  '  - "nextjs"',
  '  - "cache"',
  "---",
  "",
  "本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文",
].join("\n");

function makeDeps(overrides: Record<string, unknown> = {}) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    insertResponses: {
      knowledge: { id: "k-1", slug: "test-article-title" },
      tech_articles: { id: "a-1", slug: "test-article-title" },
      weekly_issues: { id: "i-1", slug: "test-article-title" },
      content_embeddings: { id: "e-1" },
      tags: { id: "t-1" },
      content_categories: { id: "c-1" },
      content_generation_log: { id: "log-1" },
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
        title: "Test Article Title",
        type: "knowledge",
        author: "平井拓真",
        tags: ["nextjs", "cache"],
      },
      body: "本文".repeat(100),
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      frontmatter: {
        title: "Test Article Title",
        type: "knowledge",
      },
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
    generateSlug: vi.fn().mockResolvedValue("test-article-title"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("test-article-title"),
    generateEmbedding: vi
      .fn()
      .mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({
      level: "ok",
      matches: [],
      reason: null,
    }),
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
      { kind: "existing", id: "t-1", name: "nextjs", usageCount: 3, confidence: 0.9 },
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
    // Wave 11.3a: post.ts is default --via-api. Mock ingestViaApi by default
    // so tests don't accidentally hit network / fail at exit code 2.
    ingestViaApi: vi.fn().mockResolvedValue({
      id: "k-1",
      slug: "test-post",
      augment_job_id: null,
      trace_id: "trace-post-test",
    }),
    getSupabaseClient: () => supabase,
    webSearch: {
      search: vi.fn().mockResolvedValue([]),
    },
    reader: {
      question: async () => "Y",
      close: () => {},
    },
    streams,
    env: {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "sr-key",
      AI_GATEWAY_API_KEY: "gw-key",
      OPENAI_API_KEY: "sk-key",
      SITE_URL: "http://site",
      REVALIDATE_SECRET: "rs-secret",
    } as Record<string, string | undefined>,
    // Redirect snapshot writes to os.tmpdir() so tests don't pollute contents_manage/
    contentsManageDir: os.tmpdir(),
    ...overrides,
  };
  return { deps, streams, supabase };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scripts/post.ts — main()", () => {
  let originalEnv: NodeJS.ProcessEnv;
  beforeEach(() => {
    originalEnv = { ...process.env };
  });

  it("exits 1 when required env vars are missing (early fail)", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, streams } = makeDeps({
      env: {
        SUPABASE_URL: undefined,
        SUPABASE_SERVICE_ROLE_KEY: undefined,
        AI_GATEWAY_API_KEY: undefined,
        OPENAI_API_KEY: undefined,
        SITE_URL: undefined,
        REVALIDATE_SECRET: undefined,
      } as Record<string, string | undefined>,
    });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );
    expect(code).toBe(1);
    expect(streams.err.join("\n")).toMatch(/env|SUPABASE|required/i);
  });

  it("exits 1 when --file is missing (and not batch)", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, streams } = makeDeps();
    const code = await main(["node", "post.ts", "--auto-approve"], deps);
    expect(code).toBe(1);
    expect(streams.err.join("\n")).toMatch(/--file|--batch|required/i);
  });

  it("dry-run does not call any INSERT and does not call ingestViaApi", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, supabase } = makeDeps();
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--dry-run"],
      deps,
    );
    expect(code).toBe(0);
    const inserts = supabase.calls.filter((c) => c.op === "insert");
    expect(inserts.length).toBe(0);
    expect(deps.ingestViaApi).not.toHaveBeenCalled();
  });

  it("auto-approve happy path posts to /api/ingest with the rendered payload", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps } = makeDeps();
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );
    expect(code).toBe(0);
    expect(deps.ingestViaApi).toHaveBeenCalledOnce();
    const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
    const payload = ingestMock.mock.calls[0]?.[0] as Record<string, unknown>;
    // Wave 11.3a: server-side /api/ingest handles category, tags, embedding,
    // related linking, link insertion, and revalidate. The post.ts contract
    // here is reduced to: shape the payload correctly and dispatch it.
    expect(payload.type).toBe("knowledge");
    expect(typeof payload.title).toBe("string");
    expect(typeof payload.html).toBe("string");
  });

  it("--force bypasses duplicate=block", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, supabase } = makeDeps({
      checkDuplicate: vi.fn().mockResolvedValue({
        level: "block",
        matches: [{ content_id: "k-0", similarity: 0.95 }],
        reason: "high similarity",
      }),
    });
    const code = await main(
      [
        "node",
        "post.ts",
        "--file",
        "./x.md",
        "--auto-approve",
        "--force",
      ],
      deps,
    );
    expect(code).toBe(0);
    expect(deps.ingestViaApi).toHaveBeenCalledOnce();
  });

  it("exits 3 on duplicate=block without --force", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, streams } = makeDeps({
      checkDuplicate: vi.fn().mockResolvedValue({
        level: "block",
        matches: [{ content_id: "k-0", similarity: 0.95 }],
        reason: "high similarity",
      }),
    });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );
    expect(code).toBe(3);
    expect(deps.ingestViaApi).not.toHaveBeenCalled();
    expect(streams.err.join("\n")).toMatch(/dup|block|--force/i);
  });

  it("--update bypasses duplicate=block (self-similarity guard)", async () => {
    const { main } = await import("../../scripts/post.js");
    const supabase = makeFakeSupabase({
      existingRows: {
        knowledge: [
          { id: "existing-1", slug: "old-title", title: "Old Title", author: "平井拓真", body: "old body" },
        ],
      },
    });
    const { deps } = makeDeps({
      checkDuplicate: vi.fn().mockResolvedValue({
        level: "block",
        matches: [{ content_id: "existing-1", similarity: 0.999 }],
        reason: "top similarity 0.999 (block threshold)",
      }),
      getSupabaseClient: () => supabase,
    });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--update", "--slug", "old-title", "--auto-approve"],
      deps,
    );
    // --update should bypass block-level duplicate guard and succeed
    expect(code).toBe(0);
    const updates = supabase.calls.filter((c) => c.op === "update");
    expect(updates.length).toBeGreaterThan(0);
  });

  it("exits 1 on validate error", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, streams } = makeDeps({
      validate: vi.fn().mockReturnValue({
        ok: false,
        errors: [{ field: "title", message: "title is required" }],
        warnings: [],
        frontmatter: {},
        body: "",
      }),
    });
    const code = await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      deps,
    );
    expect(code).toBe(1);
    expect(streams.err.join("\n")).toMatch(/title/i);
  });

  it("update mode fetches existing by slug and replaces title", async () => {
    const { main } = await import("../../scripts/post.js");
    const supabase = makeFakeSupabase({
      existingRows: {
        knowledge: [
          {
            id: "existing-1",
            slug: "old-title",
            title: "Old Title",
            author: "平井拓真",
            body: "old body",
          },
        ],
      },
    });
    const deps = {
      ...makeDeps().deps,
      getSupabaseClient: () => supabase,
    };
    const code = await main(
      [
        "node",
        "post.ts",
        "--file",
        "./x.md",
        "--update",
        "--slug",
        "old-title",
        "--auto-approve",
      ],
      deps,
    );
    expect(code).toBe(0);
    const updates = supabase.calls.filter((c) => c.op === "update");
    expect(updates.length).toBeGreaterThan(0);
    expect(JSON.stringify(updates[0])).toContain("Test Article Title");
  });

  it("exits 1 when update target slug does not exist", async () => {
    const { main } = await import("../../scripts/post.js");
    const supabase = makeFakeSupabase({ existingRows: { knowledge: [] } });
    const { deps, streams } = makeDeps({
      getSupabaseClient: () => supabase,
    });
    const code = await main(
      [
        "node",
        "post.ts",
        "--file",
        "./x.md",
        "--update",
        "--slug",
        "missing-slug",
        "--auto-approve",
      ],
      deps,
    );
    expect(code).toBe(1);
    expect(streams.err.join("\n")).toMatch(/slug|not.*found|missing/i);
  });

  it("batch mode processes 3 files sequentially", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps } = makeDeps({
      expandGlob: vi.fn().mockResolvedValue(["./a.md", "./b.md", "./c.md"]),
    });
    const code = await main(
      [
        "node",
        "post.ts",
        "--batch",
        "./*.md",
        "--auto-approve",
      ],
      deps,
    );
    expect(code).toBe(0);
    // loadFile 呼び出しが 3 回
    expect(deps.loadFile).toHaveBeenCalledTimes(3);
  });

  it("batch continues after a file fails (2nd fails, 3rd still runs)", async () => {
    const { main } = await import("../../scripts/post.js");
    // 2nd の validate で ok:false を返すよう切替
    let callCount = 0;
    const validate = vi.fn().mockImplementation(() => {
      callCount += 1;
      if (callCount === 2) {
        return {
          ok: false,
          errors: [{ field: "title", message: "nope" }],
          warnings: [],
          frontmatter: {},
          body: "",
        };
      }
      return {
        ok: true,
        errors: [],
        warnings: [],
        frontmatter: {
          title: "Ok",
          type: "knowledge",
        },
        body: "本文".repeat(100),
      };
    });
    const { deps } = makeDeps({
      validate,
      expandGlob: vi.fn().mockResolvedValue(["./a.md", "./b.md", "./c.md"]),
    });
    const code = await main(
      [
        "node",
        "post.ts",
        "--batch",
        "./*.md",
        "--auto-approve",
      ],
      deps,
    );
    // batch は部分失敗を許容 → exit 0 (失敗件数は stdout に出すのみ)
    expect(code).toBe(0);
    expect(deps.loadFile).toHaveBeenCalledTimes(3);
    expect(validate).toHaveBeenCalledTimes(3);
  });

  // Wave 11.3a: revalidate / --no-revalidate tests removed —
  // revalidate は Augment Edge Function に移管。post.ts から呼び出さない。

  it("--verbose produces extra stdout detail", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps: depsQuiet, streams: streamsQuiet } = makeDeps();
    await main(
      ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
      depsQuiet,
    );
    const { deps: depsVerbose, streams: streamsVerbose } = makeDeps();
    await main(
      [
        "node",
        "post.ts",
        "--file",
        "./x.md",
        "--auto-approve",
        "--verbose",
      ],
      depsVerbose,
    );
    expect(streamsVerbose.out.length).toBeGreaterThan(streamsQuiet.out.length);
  });

  // Wave 11.3a: content_generation_log audit row test removed —
  // post.ts から audit log INSERT は撤去（Augment Edge Function 側で記録）。

  // ---------------------------------------------------------------------------
  // Regression block 1: upsertEmbedding onConflict MUST be 3-column
  // Bug: previously used onConflict:"content_id" (single column), which does
  // not match the DB UNIQUE(content_type, content_id, model) constraint and
  // causes silent double-inserts on re-post.
  // ---------------------------------------------------------------------------
  describe("regression: upsertEmbedding onConflict is 3-column (content_type,content_id,model)", () => {
    it("passes the 3-column onConflict string to supabase.upsert in --update mode", async () => {
      const { main } = await import("../../scripts/post.js");
      const supabase = makeFakeSupabase({
        existingRows: {
          knowledge: [
            {
              id: "existing-1",
              slug: "my-slug",
              title: "Old Title",
              author: "平井拓真",
              body: "old body",
            },
          ],
        },
      });
      const deps = {
        ...makeDeps().deps,
        getSupabaseClient: () => supabase,
      };
      const code = await main(
        [
          "node", "post.ts",
          "--file", "./x.md",
          "--update", "--slug", "my-slug",
          "--auto-approve",
        ],
        deps,
      );
      expect(code).toBe(0);

      // Find the upsert call on content_embeddings and inspect its onConflict.
      const upsertCall = supabase.calls.find(
        (c) => c.op === "upsert" && c.table === "content_embeddings",
      );
      expect(upsertCall).toBeDefined();
      const opts = (upsertCall!.args as { opts: { onConflict: string } }).opts;
      // MUST be the 3-column conflict target matching DB UNIQUE constraint.
      // Regression: if this regresses to "content_id" the assertion below fails.
      expect(opts.onConflict).toBe("content_type,content_id,model");
      expect(opts.onConflict).not.toBe("content_id");
      expect(opts.onConflict.split(",").map((s: string) => s.trim())).toEqual(
        expect.arrayContaining(["content_type", "content_id", "model"]),
      );
    });

    it("includes the model field in the upserted row", async () => {
      const { main } = await import("../../scripts/post.js");
      const supabase = makeFakeSupabase({
        existingRows: {
          knowledge: [
            {
              id: "existing-2",
              slug: "another-slug",
              title: "Title",
              author: "平井拓真",
              body: "body",
            },
          ],
        },
      });
      const deps = {
        ...makeDeps().deps,
        getSupabaseClient: () => supabase,
      };
      await main(
        [
          "node", "post.ts",
          "--file", "./x.md",
          "--update", "--slug", "another-slug",
          "--auto-approve",
        ],
        deps,
      );

      const upsertCall = supabase.calls.find(
        (c) => c.op === "upsert" && c.table === "content_embeddings",
      );
      expect(upsertCall).toBeDefined();
      const rows = (upsertCall!.args as { rows: Record<string, unknown> }).rows;
      const row = Array.isArray(rows) ? rows[0] : rows;
      // model must be present so the 3-column UNIQUE target is satisfied.
      expect(row).toHaveProperty("model");
      expect(typeof row!.model).toBe("string");
      expect((row!.model as string).length).toBeGreaterThan(0);
    });
  });

  // ---------------------------------------------------------------------------
  // Regression block 2: audit log status must be "done", not "success"
  // Bug: Phase 11 W2.A renamed the lifecycle — old code wrote "success" which
  // the DB CHECK constraint rejects. Regression guard: assert exact value.
  // ---------------------------------------------------------------------------
  // Wave 11.3a: 'done' lifecycle audit-log regression test removed —
  // post.ts は audit log を書かなくなった (Augment 側で記録)。

  // ---------------------------------------------------------------------------
  // Regression block 3: --update on weekly_issues writes period_start / period_end
  // Bug: updateMainContent only wrote title/body/html; period columns were lost
  // on re-post, breaking the NOT NULL constraint on weekly_issues.
  // ---------------------------------------------------------------------------
  describe("regression: --update on weekly_issues writes period_start/period_end", () => {
    const ISSUE_FRONTMATTER = [
      "---",
      'title: "Weekly News 2026-04-21"',
      'type: "weekly_issues"',
      'period_start: "2026-04-14"',
      'period_end: "2026-04-21"',
      "---",
      "",
      "本文".repeat(100),
    ].join("\n");

    it("includes period_start and period_end in the UPDATE payload for weekly_issues", async () => {
      const { main } = await import("../../scripts/post.js");
      const supabase = makeFakeSupabase({
        existingRows: {
          weekly_issues: [
            {
              id: "issue-1",
              slug: "weekly-2026-04-14",
              title: "Old Issue",
              body: "old body",
              period_start: "2026-04-07",
              period_end: "2026-04-13",
            },
          ],
        },
      });
      const deps = {
        ...makeDeps().deps,
        loadFile: vi.fn().mockResolvedValue(ISSUE_FRONTMATTER),
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Weekly News 2026-04-21",
            type: "weekly_issues",
            period_start: "2026-04-14",
            period_end: "2026-04-21",
          },
          body: "本文".repeat(100),
        }),
        parseMarkdown: vi.fn().mockReturnValue({
          frontmatter: { title: "Weekly News 2026-04-21", type: "weekly_issues" },
          sections: [],
          raw: "本文".repeat(100),
        }),
        renderToHtml: vi.fn().mockReturnValue({ html: "<p>新本文</p>", appliedClasses: [] }),
        renderToHtmlAsync: vi.fn().mockResolvedValue({ html: "<p>新本文</p>", appliedClasses: [], plantumlReplacements: [] }),
        getSupabaseClient: () => supabase,
      };
      const code = await main(
        [
          "node", "post.ts",
          "--file", "./issue.md",
          "--update", "--slug", "weekly-2026-04-14",
          "--auto-approve",
        ],
        deps,
      );
      expect(code).toBe(0);

      // The UPDATE call must contain period_start and period_end.
      const updateCall = supabase.calls.find(
        (c) => c.op === "update" && c.table === "weekly_issues",
      );
      expect(updateCall).toBeDefined();
      const payload = updateCall!.args as Record<string, unknown>;
      expect(payload.period_start).toBe("2026-04-14");
      expect(payload.period_end).toBe("2026-04-21");
    });

    it("does NOT write period_start/period_end in the UPDATE payload for knowledge", async () => {
      const { main } = await import("../../scripts/post.js");
      const supabase = makeFakeSupabase({
        existingRows: {
          knowledge: [
            {
              id: "k-upd",
              slug: "knowledge-slug",
              title: "Old Knowledge",
              author: "平井拓真",
              body: "old body",
            },
          ],
        },
      });
      // validate returns period_start / period_end in frontmatter (caller may
      // inadvertently include them), but knowledge UPDATE must ignore them.
      const deps = {
        ...makeDeps().deps,
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Updated Knowledge",
            type: "knowledge",
            author: "平井拓真",
            period_start: "2026-04-14",
            period_end: "2026-04-21",
          },
          body: "本文".repeat(100),
        }),
        parseMarkdown: vi.fn().mockReturnValue({
          frontmatter: { title: "Updated Knowledge", type: "knowledge" },
          sections: [],
          raw: "本文".repeat(100),
        }),
        getSupabaseClient: () => supabase,
      };
      const code = await main(
        [
          "node", "post.ts",
          "--file", "./x.md",
          "--update", "--slug", "knowledge-slug",
          "--auto-approve",
        ],
        deps,
      );
      expect(code).toBe(0);

      const updateCall = supabase.calls.find(
        (c) => c.op === "update" && c.table === "knowledge",
      );
      expect(updateCall).toBeDefined();
      const payload = updateCall!.args as Record<string, unknown>;
      // knowledge has no period columns — they must not appear in the UPDATE.
      expect(payload.period_start).toBeUndefined();
      expect(payload.period_end).toBeUndefined();
    });

    it("does NOT write period_start/period_end in the UPDATE payload for tech_articles", async () => {
      const { main } = await import("../../scripts/post.js");
      const supabase = makeFakeSupabase({
        existingRows: {
          tech_articles: [
            {
              id: "ta-upd",
              slug: "article-slug",
              title: "Old Article",
              author: "平井拓真",
              body: "old body",
            },
          ],
        },
      });
      const deps = {
        ...makeDeps().deps,
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Updated Article",
            type: "tech_articles",
            author: "平井拓真",
          },
          body: "本文".repeat(100),
        }),
        parseMarkdown: vi.fn().mockReturnValue({
          frontmatter: { title: "Updated Article", type: "tech_articles" },
          sections: [],
          raw: "本文".repeat(100),
        }),
        getSupabaseClient: () => supabase,
      };
      const code = await main(
        [
          "node", "post.ts",
          "--file", "./x.md",
          "--update", "--slug", "article-slug",
          "--auto-approve",
        ],
        deps,
      );
      expect(code).toBe(0);

      const updateCall = supabase.calls.find(
        (c) => c.op === "update" && c.table === "tech_articles",
      );
      expect(updateCall).toBeDefined();
      const payload = updateCall!.args as Record<string, unknown>;
      expect(payload.period_start).toBeUndefined();
      expect(payload.period_end).toBeUndefined();
    });
  });

  // ---------------------------------------------------------------------------
  // Sub-4: renderToHtmlAsync integration in post pipeline
  // ---------------------------------------------------------------------------
  describe("Sub-4: renderToHtmlAsync called with {slug, contentType} after image rewrite", () => {
    it("calls renderToHtmlAsync with slug and contentType after processMarkdownImages", async () => {
      const { main } = await import("../../scripts/post.js");
      const processMarkdownImages = vi.fn().mockResolvedValue({
        markdown: "# Updated",
        replacements: [{ localPath: "./img.png", cdnUrl: "https://cdn/img.png" }],
      });
      const renderToHtmlAsync = vi.fn().mockResolvedValue({
        html: "<p>after rewrite</p>",
        appliedClasses: [],
        plantumlReplacements: [],
      });
      const { deps } = makeDeps({
        processMarkdownImages,
        renderToHtmlAsync,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(renderToHtmlAsync).toHaveBeenCalled();
      const callArgs = renderToHtmlAsync.mock.calls[0]!;
      // Third argument must have slug and contentType
      expect(callArgs[2]).toMatchObject({
        slug: expect.any(String),
        contentType: expect.stringMatching(/^(knowledge|tech_article|issue)$/),
      });
    });

    it("logs plantumlReplacements count when blocks are processed", async () => {
      const { main } = await import("../../scripts/post.js");
      const processMarkdownImages = vi.fn().mockResolvedValue({
        markdown: "# Updated",
        replacements: [{ localPath: "./img.png", cdnUrl: "https://cdn/img.png" }],
      });
      const renderToHtmlAsync = vi.fn().mockResolvedValue({
        html: "<p>with plantuml</p>",
        appliedClasses: [],
        plantumlReplacements: [
          { source: "@startuml\nA --> B\n@enduml", cdnUrl: "https://cdn/plantuml/x.svg" },
          { source: "@startuml\nC --> D\n@enduml", cdnUrl: "https://cdn/plantuml/y.svg" },
        ],
      });
      const { deps, streams } = makeDeps({
        processMarkdownImages,
        renderToHtmlAsync,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve", "--verbose"],
        deps,
      );
      expect(code).toBe(0);
      const allOutput = streams.out.join("\n");
      expect(allOutput).toMatch(/plantuml.*2|2.*plantuml/i);
    });

    it("completes normally when plantumlReplacements is empty array", async () => {
      const { main } = await import("../../scripts/post.js");
      const processMarkdownImages = vi.fn().mockResolvedValue({
        markdown: "# Updated",
        replacements: [{ localPath: "./img.png", cdnUrl: "https://cdn/img.png" }],
      });
      const renderToHtmlAsync = vi.fn().mockResolvedValue({
        html: "<p>no plantuml</p>",
        appliedClasses: [],
        plantumlReplacements: [],
      });
      const { deps } = makeDeps({
        processMarkdownImages,
        renderToHtmlAsync,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
    });
  });

  // ---------------------------------------------------------------------------
  // Sub-5 Bug 1: PlantUML pipeline must run regardless of image upload results
  // ---------------------------------------------------------------------------
  describe("Sub-5 Bug 1: renderToHtmlAsync runs even when no images are found", () => {
    it("PlantUML-only draft (no images): calls renderToHtmlAsync and writes <img> to DB", async () => {
      const { main } = await import("../../scripts/post.js");
      const plantumlHtml =
        '<p>diagram: <img src="https://cdn/plantuml/x.svg" loading="lazy" decoding="async" /></p>';
      const processMarkdownImages = vi.fn().mockResolvedValue({
        markdown: GOOD_FRONTMATTER,
        replacements: [],
      });
      const renderToHtmlAsync = vi.fn().mockResolvedValue({
        html: plantumlHtml,
        appliedClasses: [],
        plantumlReplacements: [
          { source: "@startuml\nA --> B\n@enduml", cdnUrl: "https://cdn/plantuml/x.svg" },
        ],
      });
      const { deps } = makeDeps({
        processMarkdownImages,
        renderToHtmlAsync,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      // renderToHtmlAsync must be called even though replacements.length === 0
      expect(renderToHtmlAsync).toHaveBeenCalled();
      // The /api/ingest payload must carry the CDN <img> for the PlantUML diagram
      const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
      expect(ingestMock).toHaveBeenCalledOnce();
      const payload = ingestMock.mock.calls[0]?.[0] as Record<string, unknown>;
      const html = String(payload.html ?? "");
      expect(html).toContain("<img");
      // The raw plantuml fence must NOT appear in the stored html
      expect(html).not.toContain('data-lang="plantuml"');
    });

    it("PlantUML + images draft: both pipelines run, html has CDN urls and PlantUML imgs", async () => {
      const { main } = await import("../../scripts/post.js");
      const rewrittenMarkdown = GOOD_FRONTMATTER.replace(
        "本文本文",
        "![img](https://cdn/images/img.png)本文",
      );
      const processMarkdownImages = vi.fn().mockResolvedValue({
        markdown: rewrittenMarkdown,
        replacements: [{ localPath: "./img.png", cdnUrl: "https://cdn/images/img.png" }],
      });
      const combinedHtml =
        '<p><img src="https://cdn/images/img.png" /></p>' +
        '<p><img src="https://cdn/plantuml/y.svg" loading="lazy" decoding="async" /></p>';
      const renderToHtmlAsync = vi.fn().mockResolvedValue({
        html: combinedHtml,
        appliedClasses: [],
        plantumlReplacements: [
          { source: "@startuml\nC --> D\n@enduml", cdnUrl: "https://cdn/plantuml/y.svg" },
        ],
      });
      const { deps } = makeDeps({
        processMarkdownImages,
        renderToHtmlAsync,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(processMarkdownImages).toHaveBeenCalled();
      expect(renderToHtmlAsync).toHaveBeenCalled();
      const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
      expect(ingestMock).toHaveBeenCalledOnce();
      const payload = ingestMock.mock.calls[0]?.[0] as Record<string, unknown>;
      const html = String(payload.html ?? "");
      // Both image CDN URL and PlantUML img must be present in final html
      expect(html).toContain("cdn/images/img.png");
      expect(html).toContain("cdn/plantuml/y.svg");
    });
  });

  // ---------------------------------------------------------------------------
  // Sub-5 Bug 2: frontmatter slug must be respected over auto-generated slug
  // ---------------------------------------------------------------------------
  describe("Sub-5 Bug 2: frontmatter slug takes priority over generateSlug", () => {
    const FRONTMATTER_WITH_SLUG = [
      "---",
      'title: "Test Article Title"',
      'type: "knowledge"',
      'author: "平井拓真"',
      'slug: "my-explicit-slug"',
      'tags:',
      '  - "nextjs"',
      "---",
      "",
      "本文".repeat(100),
    ].join("\n");

    it("frontmatter slug specified: uses frontmatter slug, generateSlug not called", async () => {
      const { main } = await import("../../scripts/post.js");
      const generateSlug = vi.fn().mockResolvedValue("auto-generated-slug");
      const ensureUniqueSlug = vi.fn().mockResolvedValue("my-explicit-slug");
      const { deps } = makeDeps({
        loadFile: vi.fn().mockResolvedValue(FRONTMATTER_WITH_SLUG),
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Test Article Title",
            type: "knowledge",
            author: "平井拓真",
            slug: "my-explicit-slug",
            tags: ["nextjs"],
          },
          body: "本文".repeat(100),
        }),
        generateSlug,
        ensureUniqueSlug,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      // generateSlug must NOT be called when frontmatter.slug is present
      expect(generateSlug).not.toHaveBeenCalled();
      // ensureUniqueSlug IS called to resolve collisions
      expect(ensureUniqueSlug).toHaveBeenCalledWith(
        "my-explicit-slug",
        expect.any(String),
        expect.anything(),
      );
      // Wave 11.3a: payload sent to /api/ingest must use the frontmatter slug
      const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
      expect(ingestMock).toHaveBeenCalledOnce();
      const payload = ingestMock.mock.calls[0]?.[0] as Record<string, unknown>;
      expect(payload.slug).toBe("my-explicit-slug");
    });

    it("no frontmatter slug: generateSlug called as before (regression)", async () => {
      const { main } = await import("../../scripts/post.js");
      const generateSlug = vi.fn().mockResolvedValue("auto-generated-slug");
      const ensureUniqueSlug = vi.fn().mockResolvedValue("auto-generated-slug");
      const { deps } = makeDeps({
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Test Article Title",
            type: "knowledge",
            author: "平井拓真",
            tags: ["nextjs"],
          },
          body: "本文".repeat(100),
        }),
        generateSlug,
        ensureUniqueSlug,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      // generateSlug must be called when frontmatter.slug is absent
      expect(generateSlug).toHaveBeenCalled();
      // Wave 11.3a: payload sent to /api/ingest carries the auto-generated slug
      const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
      expect(ingestMock).toHaveBeenCalledOnce();
      const payload = ingestMock.mock.calls[0]?.[0] as Record<string, unknown>;
      expect(payload.slug).toBe("auto-generated-slug");
    });
  });

  // ---------------------------------------------------------------------------
  // Slug fail-loud: assertSlugAvailable → SlugConflictError → exit 2 + guidance
  // ---------------------------------------------------------------------------
  describe("slug fail-loud: SlugConflictError causes exit 2 with --update guidance", () => {
    it("normal-mode collision: assertSlugAvailable throws → exit 2 + 対処方法 lines on stderr", async () => {
      const { main } = await import("../../scripts/post.js");
      const { SlugConflictError } = await import("../../src/posting/slug-errors.js");

      const assertSlugAvailable = vi.fn().mockImplementation(async () => {
        throw new SlugConflictError(
          "already-taken",
          "knowledge",
          "k-existing-7",
        );
      });
      const generateSlug = vi.fn().mockResolvedValue("already-taken");
      const ensureUniqueSlug = vi.fn(); // must NOT be called

      const { deps, streams } = makeDeps({
        generateSlug,
        ensureUniqueSlug,
        assertSlugAvailable,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(2);
      expect(assertSlugAvailable).toHaveBeenCalled();
      expect(ensureUniqueSlug).not.toHaveBeenCalled();

      const stderr = streams.err.join("\n");
      expect(stderr).toMatch(/already-taken/);
      expect(stderr).toMatch(/knowledge/);
      expect(stderr).toMatch(/k-existing-7/);
      expect(stderr).toMatch(/対処方法/);
      expect(stderr).toMatch(/--update --slug already-taken/);
      expect(stderr).toMatch(/slug: "<別名>"/);

      // Pipeline must not have reached ingestViaApi after a collision.
      const ingestMock = deps.ingestViaApi as ReturnType<typeof vi.fn>;
      expect(ingestMock).not.toHaveBeenCalled();
    });

    it("update mode bypasses assertSlugAvailable (既存 slug をそのまま使う)", async () => {
      // Set up a fake supabase where the slug already exists (so any guard
      // would normally throw). With --update, the pipeline must skip the
      // collision check and continue.
      const { main } = await import("../../scripts/post.js");
      const assertSlugAvailable = vi.fn().mockImplementation(async () => {
        throw new Error("assertSlugAvailable must NOT be called in --update mode");
      });

      const existingRow = {
        id: "k-1",
        slug: "existing-slug",
        title: "Old",
        body: "<p>old</p>",
        html: "<p>old</p>",
        raw_markdown: "old",
      };
      const fakeClient = {
        from: (_t: string) => ({
          select: (_c?: string) => ({
            eq: (_col: string, _val: unknown) => ({
              maybeSingle: async () => ({ data: existingRow, error: null }),
              single: async () => ({ data: existingRow, error: null }),
              limit: (_n: number) => ({
                maybeSingle: async () => ({ data: existingRow, error: null }),
              }),
            }),
          }),
          update: (_v: unknown) => ({
            eq: (_col: string, _val: unknown) => ({
              select: () => ({ single: async () => ({ data: existingRow, error: null }) }),
            }),
          }),
        }),
        rpc: async () => ({ data: [], error: null }),
      };

      const { deps } = makeDeps({
        getSupabaseClient: () => fakeClient,
        assertSlugAvailable,
        // makeDeps() already sets contentsManageDir to os.tmpdir() so snapshot
        // writes don't pollute the real contents_manage/ directory.
      });
      const code = await main(
        [
          "node",
          "post.ts",
          "--file",
          "./x.md",
          "--update",
          "--slug",
          "existing-slug",
          "--auto-approve",
        ],
        deps,
      );
      // We don't assert success (the path has many side-effects unmocked
      // here) — the only invariant we care about is the guard NEVER fires
      // in --update mode regardless of how the rest of the pipeline behaves.
      expect(assertSlugAvailable).not.toHaveBeenCalled();
      // Code can be 0 or 2 depending on downstream stubs; the important
      // contract is: no SlugConflictError was thrown by the guard.
      expect(typeof code).toBe("number");
    });

    it("ingestViaApi 409 (server-side conflict) also produces exit 2 + guidance", async () => {
      const { main } = await import("../../scripts/post.js");
      const { SlugConflictError } = await import("../../src/posting/slug-errors.js");

      // Local guard passes (no collision detected locally).
      const assertSlugAvailable = vi.fn().mockResolvedValue(undefined);
      // Server returns 409 → api-client converts to SlugConflictError.
      const ingestViaApi = vi.fn().mockRejectedValue(
        new SlugConflictError(
          "raced-slug",
          "tech_articles",
          "ta-server-1",
        ),
      );

      const { deps, streams } = makeDeps({
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Race Article",
            type: "tech_articles",
            author: "平井拓真",
            tags: ["nextjs"],
          },
          body: "本文".repeat(100),
        }),
        assertSlugAvailable,
        ingestViaApi,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(2);

      const stderr = streams.err.join("\n");
      expect(stderr).toMatch(/raced-slug/);
      expect(stderr).toMatch(/tech_articles/);
      expect(stderr).toMatch(/ta-server-1/);
      expect(stderr).toMatch(/--update --slug raced-slug/);
    });
  });

  // ---------------------------------------------------------------------------
  // #32: Thumbnail hearing layer integration (Task #32 セッション 2)
  // ---------------------------------------------------------------------------
  describe("#32 thumbnail hearing integration (Stage 5a+)", () => {
    it("calls runThumbnailHearing when dep is wired and writes generated path back to frontmatter.thumbnail", async () => {
      const { main } = await import("../../scripts/post.js");
      const hearingFn = vi.fn().mockResolvedValue({
        generated: true,
        thumbnailPath: "/tmp/generated-thumb.png",
        candidates: ["/tmp/generated-thumb.png"],
        pattern: "T363",
        hearingSkipped: true,
      });
      const uploadThumbnail = vi
        .fn()
        .mockResolvedValue({ cloudfrontUrl: "https://cdn.example.com/x.png" });
      const { deps } = makeDeps({
        runThumbnailHearing: hearingFn,
        thumbnailHearingDeps: {
          readPatternsConfig: vi.fn(),
          promptUser: vi.fn(),
          spawnGenerator: vi.fn(),
        },
        uploadThumbnail,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(hearingFn).toHaveBeenCalledTimes(1);
      // hearing's generated thumbnail path should have been routed through
      // the existing uploadThumbnail (Stage 5b+) path.
      expect(uploadThumbnail).toHaveBeenCalledWith(
        "/tmp/generated-thumb.png",
        expect.objectContaining({ contentType: "knowledge" }),
      );
    });

    it("skips hearing when --no-thumbnail-hearing is passed", async () => {
      const { main } = await import("../../scripts/post.js");
      const hearingFn = vi.fn();
      const { deps } = makeDeps({
        runThumbnailHearing: hearingFn,
        thumbnailHearingDeps: {
          readPatternsConfig: vi.fn(),
          promptUser: vi.fn(),
          spawnGenerator: vi.fn(),
        },
      });
      const code = await main(
        [
          "node",
          "post.ts",
          "--file",
          "./x.md",
          "--auto-approve",
          "--no-thumbnail-hearing",
        ],
        deps,
      );
      expect(code).toBe(0);
      expect(hearingFn).not.toHaveBeenCalled();
    });

    it("does not call uploadThumbnail when hearing returns generated=false (skip)", async () => {
      const { main } = await import("../../scripts/post.js");
      const hearingFn = vi.fn().mockResolvedValue({
        generated: false,
        thumbnailPath: null,
        candidates: [],
        pattern: null,
        hearingSkipped: true,
      });
      const uploadThumbnail = vi.fn().mockResolvedValue({ cloudfrontUrl: "x" });
      const { deps } = makeDeps({
        runThumbnailHearing: hearingFn,
        thumbnailHearingDeps: {
          readPatternsConfig: vi.fn(),
          promptUser: vi.fn(),
          spawnGenerator: vi.fn(),
        },
        uploadThumbnail,
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(hearingFn).toHaveBeenCalledTimes(1);
      expect(uploadThumbnail).not.toHaveBeenCalled();
    });

    it("hearing failure does not abort the pipeline (logs warning, continues)", async () => {
      const { main } = await import("../../scripts/post.js");
      const hearingFn = vi
        .fn()
        .mockRejectedValue(new Error("hearing simulation error"));
      const { deps, streams } = makeDeps({
        runThumbnailHearing: hearingFn,
        thumbnailHearingDeps: {
          readPatternsConfig: vi.fn(),
          promptUser: vi.fn(),
          spawnGenerator: vi.fn(),
        },
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(streams.err.join("\n")).toMatch(/thumbnail hearing failed/);
    });

    it("does not invoke hearing when frontmatter.thumbnail is already set (early-return path inside hearing)", async () => {
      const { main } = await import("../../scripts/post.js");
      // Even if the hearing dep is wired, runOne still calls it; the hearing
      // implementation itself short-circuits via the frontmatterThumbnail
      // arg. We verify by asserting the input passed to runThumbnailHearing
      // includes the frontmatterThumbnail value.
      const hearingFn = vi.fn().mockResolvedValue({
        generated: false,
        thumbnailPath: null,
        candidates: [],
        pattern: null,
        hearingSkipped: true,
      });
      const { deps } = makeDeps({
        runThumbnailHearing: hearingFn,
        thumbnailHearingDeps: {
          readPatternsConfig: vi.fn(),
          promptUser: vi.fn(),
          spawnGenerator: vi.fn(),
        },
        validate: vi.fn().mockReturnValue({
          ok: true,
          errors: [],
          warnings: [],
          frontmatter: {
            title: "Test Article Title",
            type: "knowledge",
            author: "平井拓真",
            tags: ["nextjs"],
            thumbnail: "./already-set.png",
          },
          body: "本文".repeat(100),
        }),
      });
      const code = await main(
        ["node", "post.ts", "--file", "./x.md", "--auto-approve"],
        deps,
      );
      expect(code).toBe(0);
      expect(hearingFn).toHaveBeenCalledTimes(1);
      const args = hearingFn.mock.calls[0]![0] as { frontmatterThumbnail?: string };
      expect(args.frontmatterThumbnail).toBe("./already-set.png");
    });
  });
});
