/**
 * Tests for scripts/post.ts — Task #33 W4 新フラグ
 *
 * テスト観点:
 *   1. --publish: INSERT 後に publishContent が呼ばれる
 *   2. --publish なし: publishContent は呼ばれない
 *   3. --dry-run + --publish: publishContent は呼ばれない
 *   4. frontmatter に published_at なし → INSERT payload に published_at が含まれない (NULL 相当)
 *   5. frontmatter に published_at あり → INSERT payload にその値が含まれる
 *   6,7. (Wave 11.3a で削除: --no-auto-knowledge / extractEntities は Augment 移管)
 *   8. publishContent 失敗時は非致命 (exit 0, error 出力)
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Shared helpers (copied from post.test.ts pattern)
// ---------------------------------------------------------------------------

function makeStreams() {
  const out: string[] = [];
  const err: string[] = [];
  return {
    out,
    err,
    write(line: string) { out.push(line); },
    writeErr(line: string) { err.push(line); },
  };
}

function makeFakeSupabase() {
  const calls: Array<{ op: string; table?: string; args?: unknown }> = [];
  const makeBuilder = (table: string) => {
    const state: { mode: string; pending?: unknown } = { mode: "select" };
    const builder = {
      select: () => builder,
      eq: () => builder,
      is: () => builder,
      order: () => builder,
      maybeSingle: async () => ({ data: null, error: null }),
      single: async () => {
        calls.push({ op: "single", table, args: state.pending });
        const idMap: Record<string, string> = {
          knowledge: "k-1",
          tech_articles: "a-1",
          weekly_issues: "i-1",
          content_embeddings: "e-1",
          content_generation_log: "log-1",
        };
        return { data: { id: idMap[table] ?? `${table}-id` }, error: null };
      },
      insert: (row: unknown) => {
        state.mode = "insert";
        state.pending = row;
        calls.push({ op: "insert", table, args: row });
        return builder;
      },
      update: (row: unknown) => {
        state.mode = "update";
        state.pending = row;
        calls.push({ op: "update", table, args: row });
        return builder;
      },
      upsert: async (rows: unknown, opts?: unknown) => {
        calls.push({ op: "upsert", table, args: { rows, opts } });
        return { data: rows, error: null };
      },
    };
    return builder;
  };
  return {
    calls,
    from: (table: string) => makeFakeSupabase_builder(table, calls),
    rpc: async (name: string) => {
      calls.push({ op: "rpc", table: name });
      return { data: [], error: null };
    },
  };
}

function makeFakeSupabase_builder(
  table: string,
  calls: Array<{ op: string; table?: string; args?: unknown }>,
) {
  const state: { mode: string; pending?: unknown } = { mode: "select" };
  const builder: Record<string, unknown> = {};
  builder["select"] = () => builder;
  builder["eq"] = () => builder;
  builder["is"] = () => builder;
  builder["order"] = () => builder;
  builder["maybeSingle"] = async () => ({ data: null, error: null });
  builder["single"] = async () => {
    calls.push({ op: "single", table, args: state.pending });
    const idMap: Record<string, string> = {
      knowledge: "k-1",
      tech_articles: "a-1",
      weekly_issues: "i-1",
      content_embeddings: "e-1",
      content_generation_log: "log-1",
    };
    return { data: { id: idMap[table] ?? `${table}-id` }, error: null };
  };
  builder["insert"] = (row: unknown) => {
    state.mode = "insert";
    state.pending = row;
    calls.push({ op: "insert", table, args: row });
    return builder;
  };
  builder["update"] = (row: unknown) => {
    state.mode = "update";
    state.pending = row;
    calls.push({ op: "update", table, args: row });
    return builder;
  };
  builder["upsert"] = async (rows: unknown, opts?: unknown) => {
    calls.push({ op: "upsert", table, args: { rows, opts } });
    return { data: rows, error: null };
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return builder as any;
}

const FRONTMATTER_NO_PUBLISHED_AT = [
  "---",
  'title: "Test Knowledge"',
  'type: "knowledge"',
  'author: "平井拓真"',
  "---",
  "",
  "本文".repeat(50),
].join("\n");

const FRONTMATTER_WITH_PUBLISHED_AT = [
  "---",
  'title: "Test Knowledge"',
  'type: "knowledge"',
  'author: "平井拓真"',
  'published_at: "2026-04-26T10:00:00.000Z"',
  "---",
  "",
  "本文".repeat(50),
].join("\n");

function makeDeps(overrides: Record<string, unknown> = {}) {
  const streams = makeStreams();
  const supabase = {
    calls: [] as Array<{ op: string; table?: string; args?: unknown }>,
    from(table: string) {
      return makeFakeSupabase_builder(table, this.calls);
    },
    async rpc(name: string) {
      this.calls.push({ op: "rpc", table: name });
      return { data: [], error: null };
    },
  };

  const publishContent = vi.fn().mockResolvedValue({
    success: true,
    published_at: "2026-04-26T10:00:00.000Z",
    revalidated: ["home"],
  });

  // Wave 11.3a: post.ts is default --via-api. ingestViaApi must be mocked
  // and the captured payload is what tests assert against (instead of the
  // legacy Supabase direct INSERT row).
  const ingestViaApi = vi.fn().mockResolvedValue({
    id: "k-1",
    slug: "test-knowledge",
    augment_job_id: null,
    trace_id: "trace-publish-flag",
  });

  const deps = {
    loadFile: vi.fn().mockResolvedValue(FRONTMATTER_NO_PUBLISHED_AT),
    loadTemplates: vi.fn().mockResolvedValue({}),
    validate: vi.fn().mockReturnValue({
      ok: true,
      errors: [],
      warnings: [],
      frontmatter: {
        title: "Test Knowledge",
        type: "knowledge",
        author: "平井拓真",
      },
      body: "本文".repeat(50),
    }),
    parseMarkdown: vi.fn().mockReturnValue({
      sections: [],
      raw: "本文",
    }),
    renderToHtml: vi.fn().mockReturnValue({ html: "<p>本文</p>", appliedClasses: [] }),
    renderToHtmlAsync: vi.fn().mockResolvedValue({
      html: "<p>本文</p>",
      appliedClasses: [],
      plantumlReplacements: [],
    }),
    generateSlug: vi.fn().mockResolvedValue("test-knowledge"),
    ensureUniqueSlug: vi.fn().mockResolvedValue("test-knowledge"),
    generateEmbedding: vi.fn().mockResolvedValue(new Array(1024).fill(0.01)),
    checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
    suggestCategory: vi.fn().mockResolvedValue({ slug: "tips", name: "Tips", confidence: 0.9, isNew: false }),
    suggestTags: vi.fn().mockResolvedValue([{ name: "nextjs", confidence: 0.9 }]),
    resolveTagAgainstMasters: vi.fn().mockResolvedValue([
      { kind: "existing", id: "t-1", name: "nextjs", usageCount: 3, confidence: 0.9 },
    ]),
    confirmInteractively: vi.fn().mockResolvedValue({
      committed: true,
      category: { slug: "tips", name: "Tips", isNew: false, id: "c-1" },
      tags: [{ name: "nextjs", id: "t-1", isNew: false }],
    }),
    getSupabaseClient: () => supabase,
    publishContent,
    ingestViaApi,
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
  return { deps, streams, supabase, publishContent, ingestViaApi };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scripts/post.ts — #33 publish flag and draft behavior", () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it("1. --publish: publishContent is called after INSERT with correct kind+slug", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, publishContent } = makeDeps();

    const code = await main(
      ["node", "post.ts", "--file", "./draft.md", "--auto-approve", "--publish"],
      deps,
    );

    expect(code).toBe(0);
    expect(publishContent).toHaveBeenCalledOnce();
    expect(publishContent).toHaveBeenCalledWith({ kind: "knowledge", slug: "test-knowledge" });
  });

  it("2. --publish not set: publishContent is NOT called", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, publishContent } = makeDeps();

    const code = await main(
      ["node", "post.ts", "--file", "./draft.md", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);
    expect(publishContent).not.toHaveBeenCalled();
  });

  it("3. --dry-run + --publish: publishContent is NOT called", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, publishContent } = makeDeps();

    const code = await main(
      ["node", "post.ts", "--file", "./draft.md", "--auto-approve", "--dry-run", "--publish"],
      deps,
    );

    expect(code).toBe(0);
    expect(publishContent).not.toHaveBeenCalled();
  });

  // Wave 11.3a: tests 4 & 5 (frontmatter.published_at → INSERT payload) removed.
  // /api/ingest payload は published_at を含まない設計のため、frontmatter
  // published_at は --publish フラグ経由でのみ反映される（test 1-3, 8 で担保）。

  // Wave 11.3a: --no-auto-knowledge / extractEntities tests removed —
  // NER/auto-knowledge-gen は Augment Edge Function に移管済み。

  it("8. publishContent failure is non-fatal (exit 0, error logged)", async () => {
    const { main } = await import("../../scripts/post.js");
    const { deps, streams } = makeDeps();
    deps.publishContent = vi.fn().mockRejectedValue(new Error("unauthorized"));

    const code = await main(
      ["node", "post.ts", "--file", "./draft.md", "--auto-approve", "--publish"],
      deps,
    );

    expect(code).toBe(0);
    expect(streams.err.join("\n")).toMatch(/publish failed/i);
  });
});
