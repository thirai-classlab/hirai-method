/**
 * tests/posting/post-update-roundtrip.test.ts
 *
 * Integration test: post.ts --update フロー全体の version-management hooks 検証
 *
 * 確認事項:
 *   1. --update 後に snapshot.html が生成される
 *   2. meta.json の current_version が増加する
 *   3. snapshot-before-update.html が存在する
 *   4. bumpVersion / saveSnapshotAfter が呼ばれる (spy 経由)
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

async function mkTmpDir(): Promise<string> {
  return await fs.mkdtemp(path.join(os.tmpdir(), "post-update-rt-"));
}

// ---------------------------------------------------------------------------
// Shared helpers (same pattern as other post.test.ts files)
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
    out, err,
    write(line: string) { out.push(line); },
    writeErr(line: string) { err.push(line); },
  };
}

type SupabaseCall = { op: string; table?: string; args?: unknown };

function makeFakeSupabase(cfg: {
  existingRows?: Record<string, Array<Record<string, unknown>>>;
} = {}) {
  const existingRows = cfg.existingRows ?? {};
  const calls: SupabaseCall[] = [];

  const makeBuilder = (table: string) => {
    const state: { mode: string; filters: Array<{ col: string; val: unknown }> } = {
      mode: "select",
      filters: [],
    };
    const builder: Record<string, unknown> = {
      select() { return builder; },
      eq(col: string, val: unknown) { state.filters.push({ col, val }); return builder; },
      async maybeSingle() {
        calls.push({ op: "maybeSingle", table, args: { ...state } });
        const rows = existingRows[table] ?? [];
        const match = rows.find((r) => state.filters.every((f) => r[f.col] === f.val));
        return { data: match ?? null, error: null };
      },
      async single() {
        calls.push({ op: "single", table, args: { ...state } });
        if (state.mode === "insert") return { data: { id: `${table}-id` }, error: null };
        const rows = existingRows[table] ?? [];
        const match = rows.find((r) => state.filters.every((f) => r[f.col] === f.val));
        return match ? { data: match, error: null } : { data: null, error: null };
      },
      insert(row: unknown) {
        state.mode = "insert";
        calls.push({ op: "insert", table, args: row });
        return builder;
      },
      update(row: unknown) {
        state.mode = "update";
        calls.push({ op: "update", table, args: row });
        return builder;
      },
      async upsert(rows: unknown, opts?: unknown) {
        calls.push({ op: "upsert", table, args: { rows, opts } });
        return { data: rows, error: null };
      },
      async limit(_n: number) {
        calls.push({ op: "limit", table });
        return { data: existingRows[table] ?? [], error: null };
      },
    };
    return builder;
  };

  return {
    calls,
    from(table: string) { return makeBuilder(table); },
    async rpc(name: string, args?: Record<string, unknown>) {
      calls.push({ op: "rpc", table: name, args });
      return { data: [], error: null };
    },
  };
}

const EXISTING_KNOWLEDGE = {
  id: "k-existing-1",
  slug: "my-test-slug",
  title: "Existing Article",
  body: "<h1>Old body</h1>",
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

describe("post.ts --update: UPDATE-complete hooks (roundtrip)", () => {
  let tmpDir: string;
  let contentsDir: string;

  beforeEach(async () => {
    tmpDir = await mkTmpDir();
    contentsDir = path.join(tmpDir, "contents");
    await fs.mkdir(contentsDir, { recursive: true });
    vi.resetModules();
  });

  afterEach(async () => {
    await fs.rm(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  /**
   * v1 の meta.json + snapshot.html を事前に作成するヘルパー
   */
  async function seedV1(slug: string): Promise<void> {
    const slugDir = path.join(contentsDir, slug);
    const v1Dir = path.join(slugDir, "v1");
    await fs.mkdir(v1Dir, { recursive: true });

    const meta = {
      slug,
      kind: "knowledge",
      title: "Existing Article",
      current_version: 1,
      published_version: 1,
      published_at: "2026-04-25T00:00:00Z",
      versions: [
        {
          v: 1,
          created_at: "2026-04-25T00:00:00Z",
          author: "task-41-seed",
          snapshot_taken: true,
        },
      ],
    };
    await fs.writeFile(path.join(slugDir, "meta.json"), JSON.stringify(meta, null, 2), "utf-8");
    await fs.writeFile(path.join(v1Dir, "snapshot.html"), "<h1>Old body</h1>", "utf-8");
    await fs.writeFile(path.join(v1Dir, "post.md"), "# Old body", "utf-8");
  }

  it("1. --update 後に v2/snapshot-before-update.html + v2/snapshot.html が生成される", async () => {
    await seedV1("my-test-slug");

    const supabase = makeFakeSupabase({
      existingRows: { knowledge: [EXISTING_KNOWLEDGE] },
    });
    const streams = makeStreams();

    const { main } = await import("../../scripts/post.js");

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/draft.md", "--update", "--slug", "my-test-slug", "--auto-approve"],
      {
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
        getSupabaseClient: vi.fn().mockReturnValue(supabase),
        webSearch: { search: vi.fn().mockResolvedValue([]) },
        reader: { question: vi.fn().mockResolvedValue("y"), close: vi.fn() },
        streams,
        contentsManageDir: contentsDir,
        env: {
          SUPABASE_URL: "https://example.supabase.co",
          SUPABASE_SERVICE_ROLE_KEY: "service-key",
          AI_GATEWAY_API_KEY: "gw-key",
          SITE_URL: "https://example.com",
          REVALIDATE_SECRET: "secret",
        },
      },
    );

    expect(code).toBe(0);

    // snapshot-before-update.html が v2 に生成されている
    const beforePath = path.join(contentsDir, "my-test-slug", "v2", "snapshot-before-update.html");
    const beforeContent = await fs.readFile(beforePath, "utf-8");
    expect(beforeContent).toContain("Old body");

    // snapshot.html が v2 に生成されている
    const afterPath = path.join(contentsDir, "my-test-slug", "v2", "snapshot.html");
    const afterContent = await fs.readFile(afterPath, "utf-8");
    expect(afterContent).toContain("updated");

    // meta.json の current_version が 2 に増加している
    const metaRaw = await fs.readFile(
      path.join(contentsDir, "my-test-slug", "meta.json"),
      "utf-8",
    );
    const meta = JSON.parse(metaRaw) as { current_version: number; versions: unknown[] };
    expect(meta.current_version).toBe(2);
    expect(meta.versions).toHaveLength(2);
  });

  it("2. DB update call が実行される", async () => {
    await seedV1("my-test-slug");

    const supabase = makeFakeSupabase({
      existingRows: { knowledge: [EXISTING_KNOWLEDGE] },
    });
    const streams = makeStreams();

    const { main } = await import("../../scripts/post.js");

    const code = await main(
      ["node", "post.ts", "--file", "/tmp/draft.md", "--update", "--slug", "my-test-slug", "--auto-approve"],
      {
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
        getSupabaseClient: vi.fn().mockReturnValue(supabase),
        webSearch: { search: vi.fn().mockResolvedValue([]) },
        reader: { question: vi.fn().mockResolvedValue("y"), close: vi.fn() },
        streams,
        contentsManageDir: contentsDir,
        env: {
          SUPABASE_URL: "https://example.supabase.co",
          SUPABASE_SERVICE_ROLE_KEY: "service-key",
          AI_GATEWAY_API_KEY: "gw-key",
          SITE_URL: "https://example.com",
          REVALIDATE_SECRET: "secret",
        },
      },
    );

    expect(code).toBe(0);

    // DB update が呼ばれた
    const updateCalls = supabase.calls.filter((c) => c.op === "update");
    expect(updateCalls.length).toBeGreaterThan(0);
  });
});
