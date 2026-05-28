/**
 * Tests for scripts/feedback-learn.ts — Phase 8 Wave F (8.F.2)
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-f/plan.md §8.F.2 テスト観点 (10)
 *
 *   1. collectEdits returns records since given date
 *   2. classifyEdits sorts into 4 kinds (tag_added / tag_removed / body_revised / category_changed)
 *   3. empty edits → empty fewShots
 *   4. Haiku returns valid JSON → parsed FewShot[]
 *   5. Haiku returns invalid JSON → 1 retry → throws
 *   6. upsertFewShots upserts by task_type
 *   7. upsertFewShots inserts fresh row
 *   8. --dry-run suppresses upsert
 *   9. missing env → exit 1
 *   10. main end-to-end invokes every stage
 */
import { describe, it, expect, vi } from "vitest";

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

interface FakeSupabase {
  calls: SupabaseCall[];
  editsRows: Array<Record<string, unknown>>;
  from(table: string): FakeBuilder;
}

interface FakeBuilder {
  select: (cols?: string) => FakeBuilder;
  eq: (col: string, val: unknown) => FakeBuilder;
  gte: (col: string, val: unknown) => FakeBuilder;
  order: (col: string, opts?: unknown) => FakeBuilder;
  // Data terminates (awaitable): select chain → thenable
  then: <T>(res: (v: { data: unknown[]; error: unknown }) => T) => Promise<T>;
  insert: (row: unknown) => FakeBuilder;
  upsert: (rows: unknown, opts?: unknown) => Promise<{ data: unknown; error: unknown }>;
}

function makeFakeSupabase(cfg: {
  editsRows?: Array<Record<string, unknown>>;
  existingFewShots?: Array<Record<string, unknown>>;
} = {}): FakeSupabase {
  const editsRows = cfg.editsRows ?? [];
  const calls: SupabaseCall[] = [];

  const makeBuilder = (table: string): FakeBuilder => {
    const state: {
      filters: Array<{ op: string; col: string; val: unknown }>;
    } = { filters: [] };
    const builder: FakeBuilder = {
      select(cols) {
        calls.push({ op: "select", table, args: cols });
        return builder;
      },
      eq(col, val) {
        state.filters.push({ op: "eq", col, val });
        return builder;
      },
      gte(col, val) {
        state.filters.push({ op: "gte", col, val });
        return builder;
      },
      order(col, opts) {
        calls.push({ op: "order", table, args: { col, opts } });
        return builder;
      },
      then(resolve) {
        // Awaiting the chain yields the filtered rows
        const rows = table === "content_edits_log" ? editsRows : [];
        const filtered = rows.filter((r) =>
          state.filters.every((f) => {
            const cell = r[f.col];
            if (f.op === "eq") return cell === f.val;
            if (f.op === "gte") {
              const a = new Date(String(cell)).getTime();
              const b = new Date(String(f.val)).getTime();
              return a >= b;
            }
            return true;
          }),
        );
        calls.push({ op: "await", table, args: { filters: state.filters } });
        return Promise.resolve(resolve({ data: filtered, error: null }));
      },
      insert(row) {
        calls.push({ op: "insert", table, args: row });
        return builder;
      },
      async upsert(rows, opts) {
        calls.push({ op: "upsert", table, args: { rows, opts } });
        return { data: rows, error: null };
      },
    };
    return builder;
  };

  return {
    calls,
    editsRows,
    from(table) {
      return makeBuilder(table);
    },
  };
}

function makeDeps(overrides: Record<string, unknown> = {}) {
  const streams = makeStreams();
  const supabase = makeFakeSupabase({
    editsRows: [
      {
        id: "e1",
        content_type: "knowledge",
        content_id: "k1",
        admin_user: "a@x",
        before: { tags: ["nextjs"] },
        after: { tags: ["nextjs", "cache"] },
        edit_type: "tag",
        created_at: "2026-04-10T00:00:00Z",
      },
      {
        id: "e2",
        content_type: "knowledge",
        content_id: "k2",
        admin_user: "a@x",
        before: { tags: ["nextjs", "cache"] },
        after: { tags: ["nextjs"] },
        edit_type: "tag",
        created_at: "2026-04-11T00:00:00Z",
      },
      {
        id: "e3",
        content_type: "article",
        content_id: "a1",
        admin_user: "a@x",
        before: { body: "old body" },
        after: { body: "improved body with more detail" },
        edit_type: "body",
        created_at: "2026-04-12T00:00:00Z",
      },
      {
        id: "e4",
        content_type: "knowledge",
        content_id: "k3",
        admin_user: "a@x",
        before: { category: "tips" },
        after: { category: "tutorial" },
        edit_type: "category",
        created_at: "2026-04-13T00:00:00Z",
      },
    ],
  });
  const deps = {
    getSupabaseClient: () => supabase,
    runLLM: vi.fn().mockResolvedValue({
      text: JSON.stringify({
        fewShots: [
          {
            task_type: "auto_tag",
            example_input: { title: "Next.js cache" },
            example_output: { tags: ["nextjs", "cache"] },
            quality_score: 0.9,
          },
        ],
      }),
      model: "anthropic/claude-haiku-4.5",
      tokens: { input: 100, output: 50, total: 150 },
    }),
    streams,
    env: {
      SUPABASE_URL: "http://localhost",
      SUPABASE_SERVICE_ROLE_KEY: "sr",
      AI_GATEWAY_API_KEY: "gw",
    } as Record<string, string | undefined>,
    ...overrides,
  };
  return { deps, streams, supabase };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("scripts/feedback-learn.ts — collectEdits", () => {
  it("returns records since the given date (gte + order)", async () => {
    const { collectEdits } = await import("../../scripts/feedback-learn.js");
    const { supabase } = makeDeps();
    const rows = await collectEdits(new Date("2026-04-11"), supabase as never);
    // e1 is 2026-04-10 and should be excluded
    expect(rows.map((r) => r.id).sort()).toEqual(["e2", "e3", "e4"]);
    const gteCall = supabase.calls.find(
      (c) => c.op === "await" && c.table === "content_edits_log",
    );
    expect(gteCall).toBeTruthy();
  });
});

describe("scripts/feedback-learn.ts — classifyEdits", () => {
  it("sorts into tag_added / tag_removed / body_revised / category_changed", async () => {
    const { classifyEdits } = await import("../../scripts/feedback-learn.js");
    const { supabase } = makeDeps();
    const edits = await (
      await import("../../scripts/feedback-learn.js")
    ).collectEdits(new Date("2020-01-01"), supabase as never);
    const classified = classifyEdits(edits);
    expect(classified.tag_added.length).toBe(1);
    expect(classified.tag_removed.length).toBe(1);
    expect(classified.body_revised.length).toBe(1);
    expect(classified.category_changed.length).toBe(1);
  });
});

describe("scripts/feedback-learn.ts — synthesizeFewShots", () => {
  it("returns empty array when edits are empty", async () => {
    const { synthesizeFewShots } = await import(
      "../../scripts/feedback-learn.js"
    );
    const { deps } = makeDeps();
    const shots = await synthesizeFewShots(
      {
        tag_added: [],
        tag_removed: [],
        body_revised: [],
        category_changed: [],
      },
      { runLLM: deps.runLLM as never },
    );
    expect(shots).toEqual([]);
    expect(deps.runLLM).not.toHaveBeenCalled();
  });

  it("parses Haiku JSON response into FewShot[]", async () => {
    const { synthesizeFewShots } = await import(
      "../../scripts/feedback-learn.js"
    );
    const { deps } = makeDeps();
    const shots = await synthesizeFewShots(
      {
        tag_added: [
          {
            id: "e1",
            content_type: "knowledge",
            content_id: "k1",
            before: { tags: ["nextjs"] },
            after: { tags: ["nextjs", "cache"] },
            edit_type: "tag",
          } as never,
        ],
        tag_removed: [],
        body_revised: [],
        category_changed: [],
      },
      { runLLM: deps.runLLM as never },
    );
    expect(shots.length).toBeGreaterThan(0);
    expect(shots[0]?.task_type).toBe("auto_tag");
    expect(shots[0]?.example_output).toEqual({ tags: ["nextjs", "cache"] });
  });

  it("retries once on invalid JSON then throws", async () => {
    const { synthesizeFewShots } = await import(
      "../../scripts/feedback-learn.js"
    );
    const runLLM = vi
      .fn()
      .mockResolvedValueOnce({
        text: "not-json{{{",
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 1, output: 1, total: 2 },
      })
      .mockResolvedValueOnce({
        text: "still-broken",
        model: "anthropic/claude-haiku-4.5",
        tokens: { input: 1, output: 1, total: 2 },
      });
    await expect(
      synthesizeFewShots(
        {
          tag_added: [
            {
              id: "e1",
              content_type: "knowledge",
              content_id: "k1",
              before: { tags: [] },
              after: { tags: ["x"] },
              edit_type: "tag",
            } as never,
          ],
          tag_removed: [],
          body_revised: [],
          category_changed: [],
        },
        { runLLM: runLLM as never },
      ),
    ).rejects.toThrow(/invalid JSON|parse/i);
    expect(runLLM).toHaveBeenCalledTimes(2);
  });
});

describe("scripts/feedback-learn.ts — upsertFewShots", () => {
  it("upserts rows into prompt_few_shots with onConflict=task_type+example_input", async () => {
    const { upsertFewShots } = await import("../../scripts/feedback-learn.js");
    const { supabase } = makeDeps();
    await upsertFewShots(
      [
        {
          task_type: "auto_tag",
          example_input: { title: "x" },
          example_output: { tags: ["y"] },
          quality_score: 0.8,
        },
      ],
      supabase as never,
    );
    const up = supabase.calls.find((c) => c.op === "upsert");
    expect(up?.table).toBe("prompt_few_shots");
  });

  it("inserts multiple rows in a single upsert call", async () => {
    const { upsertFewShots } = await import("../../scripts/feedback-learn.js");
    const { supabase } = makeDeps();
    await upsertFewShots(
      [
        {
          task_type: "auto_tag",
          example_input: { title: "a" },
          example_output: { tags: ["x"] },
          quality_score: 0.9,
        },
        {
          task_type: "category",
          example_input: { title: "b" },
          example_output: { slug: "tips" },
          quality_score: 0.7,
        },
      ],
      supabase as never,
    );
    const up = supabase.calls.find((c) => c.op === "upsert");
    expect(up).toBeTruthy();
    const arr = (up?.args as { rows: unknown[] }).rows;
    expect(Array.isArray(arr)).toBe(true);
    expect(arr.length).toBe(2);
  });
});

describe("scripts/feedback-learn.ts — main()", () => {
  it("--dry-run does not call upsert", async () => {
    const { main } = await import("../../scripts/feedback-learn.js");
    const { deps, supabase } = makeDeps();
    const code = await main(
      ["node", "feedback-learn.ts", "--since", "2020-01-01", "--dry-run"],
      deps as never,
    );
    expect(code).toBe(0);
    expect(supabase.calls.find((c) => c.op === "upsert")).toBeUndefined();
  });

  it("exits 1 when required env vars are missing", async () => {
    const { main } = await import("../../scripts/feedback-learn.js");
    const { deps, streams } = makeDeps({
      env: {
        SUPABASE_URL: undefined,
        SUPABASE_SERVICE_ROLE_KEY: undefined,
        AI_GATEWAY_API_KEY: undefined,
      } as Record<string, string | undefined>,
    });
    const code = await main(
      ["node", "feedback-learn.ts", "--since", "2020-01-01"],
      deps as never,
    );
    expect(code).toBe(1);
    expect(streams.err.join("\n")).toMatch(/env|SUPABASE|required/i);
  });

  it("happy path runs collect → classify → synthesize → upsert in order", async () => {
    const { main } = await import("../../scripts/feedback-learn.js");
    const { deps, supabase } = makeDeps();
    const code = await main(
      ["node", "feedback-learn.ts", "--since", "2020-01-01"],
      deps as never,
    );
    expect(code).toBe(0);
    // LLM was invoked at least once
    expect(deps.runLLM).toHaveBeenCalled();
    // upsert happened
    expect(supabase.calls.find((c) => c.op === "upsert")).toBeTruthy();
  });
});
