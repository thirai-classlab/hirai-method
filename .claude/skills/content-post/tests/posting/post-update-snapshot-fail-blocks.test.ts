/**
 * tests/posting/post-update-snapshot-fail-blocks.test.ts
 *
 * Validates that when snapshotBeforeUpdate throws, the post.ts --update
 * pipeline does NOT proceed to DB UPDATE.
 *
 * This structurally guarantees the fail-safe property:
 *   "snapshot failure → DB never overwritten"
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
// os used by mkTmpDir

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "snap-fail-test-"));
}

// ---------------------------------------------------------------------------
// Shared helpers (same pattern as tests/scripts/post.test.ts)
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

interface FakeSupabase {
  calls: SupabaseCall[];
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
    } = { mode: "select", filters: [] };
    const builder: FakeBuilder = {
      select() { return builder; },
      eq(col, val) { state.filters.push({ col, val }); return builder; },
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
        calls.push({ op: "insert", table, args: row });
        return builder;
      },
      update(row) {
        state.mode = "update";
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
    from(table) { return makeBuilder(table); },
    async rpc(name, args) {
      calls.push({ op: "rpc", table: name, args });
      return { data: [], error: null };
    },
  };
}

const EXISTING_KNOWLEDGE = {
  id: "k-existing-1",
  slug: "my-test-slug",
  title: "Existing Article",
  body: "# Old body",
  html: "<h1>Old body</h1>",
  raw_markdown: "# Old body",
  published_at: "2026-04-25T00:00:00Z",
};

const GOOD_FRONTMATTER = [
  "---",
  'title: "Updated Article Title"',
  'type: "knowledge"',
  'author: "平井"',
  "---",
  "",
  "本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文本文",
].join("\n");

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("post.ts --update: snapshot fail-safe", () => {
  let tmpDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
    // Reset module cache so version-manager mock takes effect
    vi.resetModules();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("does NOT call DB update when snapshotBeforeUpdate throws", async () => {
    // Mock version-manager BEFORE importing post.ts
    vi.doMock("../../src/posting/version-manager.js", () => ({
      snapshotBeforeUpdate: vi.fn().mockRejectedValue(
        new Error("Snapshot failed: DB fetch error"),
      ),
      bumpVersion: vi.fn().mockResolvedValue(undefined),
      loadCurrentMarkdown: vi.fn().mockResolvedValue(null),
      saveSnapshotAfter: vi.fn().mockResolvedValue(undefined),
      validateMetaSchema: vi.fn(),
    }));

    const { main } = await import("../../scripts/post.js");

    const supabase = makeFakeSupabase({
      existingRows: {
        knowledge: [EXISTING_KNOWLEDGE],
      },
      insertResponses: {
        knowledge: { id: "k-1" },
        content_embeddings: { id: "e-1" },
        content_generation_log: { id: "log-1" },
      },
    });

    const streams = makeStreams();
    const deps = {
      loadFile: vi.fn().mockResolvedValue(GOOD_FRONTMATTER),
      loadTemplates: vi.fn().mockResolvedValue({}),
      validate: vi.fn().mockReturnValue({
        ok: true, errors: [], warnings: [],
        frontmatter: { title: "Updated Article Title", type: "knowledge", author: "平井" },
        body: "本文...",
      }),
      parseMarkdown: vi.fn().mockReturnValue({
        frontmatter: { title: "Updated Article Title", type: "knowledge" },
        sections: [],
        raw: "本文...",
      }),
      renderToHtml: vi.fn().mockReturnValue({ html: "<p>updated</p>", appliedClasses: [] }),
      renderToHtmlAsync: vi.fn().mockResolvedValue({ html: "<p>updated</p>", appliedClasses: [] }),
      generateSlug: vi.fn().mockResolvedValue("my-test-slug"),
      ensureUniqueSlug: vi.fn().mockResolvedValue("my-test-slug"),
      generateEmbedding: vi.fn().mockResolvedValue(new Array(1536).fill(0.1)),
      checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
      suggestCategory: vi.fn().mockResolvedValue({ slug: "general", name: "General", confidence: 0.9, isNew: false }),
      suggestTags: vi.fn().mockResolvedValue([]),
      resolveTagAgainstMasters: vi.fn().mockResolvedValue([]),
      confirmInteractively: vi.fn().mockResolvedValue({
        committed: true,
        category: { slug: "general", name: "General", isNew: false },
        tags: [],
      }),
      commitCategoryAndTags: vi.fn().mockResolvedValue({ categoryId: "cat-1", tagIds: [] }),
      extractEntities: vi.fn().mockResolvedValue([]),
      processEntities: vi.fn().mockResolvedValue([]),
      findRelated: vi.fn().mockResolvedValue([]),
      linkRelated: vi.fn().mockResolvedValue([]),
      insertLinks: vi.fn().mockResolvedValue({ html: "<p>updated</p>", inserted: [] }),
      revalidateSite: vi.fn().mockResolvedValue({ ok: true, revalidated: [], status: 200 }),
      getSupabaseClient: vi.fn().mockReturnValue(supabase),
      webSearch: { search: vi.fn().mockResolvedValue([]) },
      reader: { question: vi.fn().mockResolvedValue("y"), close: vi.fn() },
      streams,
      env: {
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "service-key",
        AI_GATEWAY_API_KEY: "gw-key",
        SITE_URL: "https://example.com",
        REVALIDATE_SECRET: "secret",
      },
    };

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/draft.md", "--update", "--slug", "my-test-slug", "--auto-approve"],
      deps,
    );

    // Should exit with error (not 0)
    expect(code).not.toBe(0);

    // Critical assertion: DB update must NOT have been called
    const updateCalls = supabase.calls.filter((c) => c.op === "update");
    expect(updateCalls).toHaveLength(0);

    // Error should be logged
    expect(streams.err.some((e) => /snapshot/i.test(e) || /unexpected/i.test(e))).toBe(true);
  });

  it("proceeds to DB update when snapshotBeforeUpdate succeeds", async () => {
    vi.doMock("../../src/posting/version-manager.js", () => ({
      snapshotBeforeUpdate: vi.fn().mockResolvedValue({ nextVersion: 2 }),
      bumpVersion: vi.fn().mockResolvedValue(undefined),
      loadCurrentMarkdown: vi.fn().mockResolvedValue(null),
      saveSnapshotAfter: vi.fn().mockResolvedValue(undefined),
      validateMetaSchema: vi.fn(),
    }));

    const { main } = await import("../../scripts/post.js");

    const supabase = makeFakeSupabase({
      existingRows: {
        knowledge: [EXISTING_KNOWLEDGE],
      },
      insertResponses: {
        knowledge: { id: "k-1" },
        content_embeddings: { id: "e-1" },
        content_generation_log: { id: "log-1" },
      },
    });

    const streams = makeStreams();
    const deps = {
      loadFile: vi.fn().mockResolvedValue(GOOD_FRONTMATTER),
      loadTemplates: vi.fn().mockResolvedValue({}),
      validate: vi.fn().mockReturnValue({
        ok: true, errors: [], warnings: [],
        frontmatter: { title: "Updated Article Title", type: "knowledge", author: "平井" },
        body: "本文...",
      }),
      parseMarkdown: vi.fn().mockReturnValue({
        frontmatter: { title: "Updated Article Title", type: "knowledge" },
        sections: [],
        raw: "本文...",
      }),
      renderToHtml: vi.fn().mockReturnValue({ html: "<p>updated</p>", appliedClasses: [] }),
      renderToHtmlAsync: vi.fn().mockResolvedValue({ html: "<p>updated</p>", appliedClasses: [] }),
      generateSlug: vi.fn().mockResolvedValue("my-test-slug"),
      ensureUniqueSlug: vi.fn().mockResolvedValue("my-test-slug"),
      generateEmbedding: vi.fn().mockResolvedValue(new Array(1536).fill(0.1)),
      checkDuplicate: vi.fn().mockResolvedValue({ level: "ok", matches: [], reason: null }),
      suggestCategory: vi.fn().mockResolvedValue({ slug: "general", name: "General", confidence: 0.9, isNew: false }),
      suggestTags: vi.fn().mockResolvedValue([]),
      resolveTagAgainstMasters: vi.fn().mockResolvedValue([]),
      confirmInteractively: vi.fn().mockResolvedValue({
        committed: true,
        category: { slug: "general", name: "General", isNew: false },
        tags: [],
      }),
      commitCategoryAndTags: vi.fn().mockResolvedValue({ categoryId: "cat-1", tagIds: [] }),
      extractEntities: vi.fn().mockResolvedValue([]),
      processEntities: vi.fn().mockResolvedValue([]),
      findRelated: vi.fn().mockResolvedValue([]),
      linkRelated: vi.fn().mockResolvedValue([]),
      insertLinks: vi.fn().mockResolvedValue({ html: "<p>updated</p>", inserted: [] }),
      revalidateSite: vi.fn().mockResolvedValue({ ok: true, revalidated: [], status: 200 }),
      getSupabaseClient: vi.fn().mockReturnValue(supabase),
      webSearch: { search: vi.fn().mockResolvedValue([]) },
      reader: { question: vi.fn().mockResolvedValue("y"), close: vi.fn() },
      streams,
      env: {
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "service-key",
        AI_GATEWAY_API_KEY: "gw-key",
        SITE_URL: "https://example.com",
        REVALIDATE_SECRET: "secret",
      },
    };

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/draft.md", "--update", "--slug", "my-test-slug", "--auto-approve"],
      deps,
    );

    expect(code).toBe(0);

    // DB update MUST have been called
    const updateCalls = supabase.calls.filter((c) => c.op === "update");
    expect(updateCalls.length).toBeGreaterThan(0);
  });
});
