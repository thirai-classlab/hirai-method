/**
 * Tests for scripts/merge-duplicates.ts — Phase 8 Wave F (8.F.3)
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-f/plan.md §8.F.3 テスト観点 (7)
 *
 *   1. fetchAllEmbeddings filters by --type
 *   2. findDuplicatePairs returns pairs above threshold
 *   3. self-pairs (a=a) are excluded
 *   4. symmetric pairs: only (a,b) once — never both (a,b) and (b,a)
 *   5. formatReport produces markdown
 *   6. empty list → "マージ候補なし" message
 *   7. --output writes file via fs dep
 */
import { describe, it, expect, vi } from "vitest";

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
    write: (l) => out.push(l),
    writeErr: (l) => err.push(l),
  };
}

type SupabaseCall = { op: string; table?: string; args?: unknown };

function makeFakeSupabase(cfg: {
  embeddingsRows?: Array<Record<string, unknown>>;
  contentByType?: Record<string, Array<Record<string, unknown>>>;
} = {}): {
  calls: SupabaseCall[];
  from(table: string): unknown;
} {
  const calls: SupabaseCall[] = [];
  const embRows = cfg.embeddingsRows ?? [];
  const contentByType = cfg.contentByType ?? {};
  return {
    calls,
    from(table: string) {
      const state: { filters: Array<{ col: string; val: unknown }> } = {
        filters: [],
      };
      const builder: {
        select: (cols?: string) => typeof builder;
        eq: (col: string, val: unknown) => typeof builder;
        in: (col: string, vals: unknown[]) => typeof builder;
        then: <T>(
          r: (v: { data: unknown[]; error: unknown }) => T,
        ) => Promise<T>;
      } = {
        select(cols) {
          calls.push({ op: "select", table, args: cols });
          return builder;
        },
        eq(col, val) {
          state.filters.push({ col, val });
          return builder;
        },
        in(col, vals) {
          state.filters.push({ col, val: vals });
          return builder;
        },
        then(resolve) {
          let rows: Array<Record<string, unknown>> = [];
          if (table === "content_embeddings") {
            rows = embRows.filter((r) =>
              state.filters.every((f) => {
                const cell = r[f.col];
                if (Array.isArray(f.val)) return (f.val as unknown[]).includes(cell);
                return cell === f.val;
              }),
            );
          } else if (table === "knowledge" || table === "tech_articles" || table === "weekly_issues") {
            rows = contentByType[table] ?? [];
            // handle `.in("id", [ids])` filter
            rows = rows.filter((r) =>
              state.filters.every((f) => {
                const cell = r[f.col];
                if (Array.isArray(f.val)) return (f.val as unknown[]).includes(cell);
                return cell === f.val;
              }),
            );
          }
          calls.push({ op: "await", table, args: { filters: state.filters } });
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
      };
      return builder;
    },
  };
}

// Helpers
const dim = (i: number): number[] => {
  const v = new Array(8).fill(0);
  v[i % 8] = 1;
  return v;
};

// Two vectors with cosine similarity = 1
const v1 = [1, 0, 0, 0, 0, 0, 0, 0];
const v1copy = [1, 0, 0, 0, 0, 0, 0, 0];
// Orthogonal to v1
const v2 = [0, 1, 0, 0, 0, 0, 0, 0];

describe("scripts/merge-duplicates.ts — fetchAllEmbeddings", () => {
  it("fetches only the rows matching --type filter", async () => {
    const { fetchAllEmbeddings } = await import(
      "../../scripts/merge-duplicates.js"
    );
    const supabase = makeFakeSupabase({
      embeddingsRows: [
        { content_type: "knowledge", content_id: "k1", embedding: dim(0) },
        { content_type: "knowledge", content_id: "k2", embedding: dim(1) },
        { content_type: "article", content_id: "a1", embedding: dim(2) },
      ],
    });
    const rows = await fetchAllEmbeddings(supabase as never, {
      type: "knowledge",
    });
    expect(rows.length).toBe(2);
    expect(rows.every((r) => r.content_type === "knowledge")).toBe(true);
  });
});

describe("scripts/merge-duplicates.ts — findDuplicatePairs", () => {
  it("returns only pairs whose cosine similarity is >= threshold", async () => {
    const { findDuplicatePairs } = await import(
      "../../scripts/merge-duplicates.js"
    );
    const pairs = await findDuplicatePairs(
      [
        { content_type: "knowledge", content_id: "k1", embedding: v1 },
        { content_type: "knowledge", content_id: "k2", embedding: v1copy },
        { content_type: "knowledge", content_id: "k3", embedding: v2 },
      ],
      0.9,
    );
    expect(pairs.length).toBe(1);
    expect(pairs[0]?.similarity).toBeGreaterThan(0.99);
  });

  it("excludes self-pairs (a=a)", async () => {
    const { findDuplicatePairs } = await import(
      "../../scripts/merge-duplicates.js"
    );
    const pairs = await findDuplicatePairs(
      [
        { content_type: "knowledge", content_id: "k1", embedding: v1 },
      ],
      0.5,
    );
    expect(pairs.length).toBe(0);
  });

  it("emits each symmetric pair once (a,b) not both (a,b) and (b,a)", async () => {
    const { findDuplicatePairs } = await import(
      "../../scripts/merge-duplicates.js"
    );
    const pairs = await findDuplicatePairs(
      [
        { content_type: "knowledge", content_id: "k1", embedding: v1 },
        { content_type: "knowledge", content_id: "k2", embedding: v1copy },
      ],
      0.5,
    );
    expect(pairs.length).toBe(1);
    // Stable ordering: we only get one direction
    const pair = pairs[0]!;
    const ids = [pair.aId, pair.bId].sort();
    expect(ids).toEqual(["k1", "k2"]);
  });
});

describe("scripts/merge-duplicates.ts — formatReport", () => {
  it("produces markdown with similarity for each pair", async () => {
    const { formatReport } = await import("../../scripts/merge-duplicates.js");
    const md = formatReport([
      {
        aType: "knowledge",
        aId: "k1",
        aSlug: "alpha",
        aTitle: "Alpha",
        bType: "knowledge",
        bId: "k2",
        bSlug: "beta",
        bTitle: "Beta",
        similarity: 0.95,
      },
    ]);
    expect(md).toMatch(/#.*マージ候補/);
    expect(md).toMatch(/alpha/);
    expect(md).toMatch(/beta/);
    expect(md).toMatch(/0\.95/);
  });

  it("returns a 'マージ候補なし' message for empty input", async () => {
    const { formatReport } = await import("../../scripts/merge-duplicates.js");
    const md = formatReport([]);
    expect(md).toMatch(/マージ候補なし/);
  });
});

describe("scripts/merge-duplicates.ts — main()", () => {
  it("writes to --output path when provided", async () => {
    const { main } = await import("../../scripts/merge-duplicates.js");
    const supabase = makeFakeSupabase({
      embeddingsRows: [
        { content_type: "knowledge", content_id: "k1", embedding: v1 },
        { content_type: "knowledge", content_id: "k2", embedding: v1copy },
      ],
      contentByType: {
        knowledge: [
          { id: "k1", slug: "alpha", title: "Alpha" },
          { id: "k2", slug: "beta", title: "Beta" },
        ],
      },
    });
    const writeFile = vi.fn().mockResolvedValue(undefined);
    const streams = makeStreams();
    const code = await main(
      [
        "node",
        "merge-duplicates.ts",
        "--threshold",
        "0.5",
        "--output",
        "/tmp/out.md",
        "--type",
        "knowledge",
      ],
      {
        getSupabaseClient: () => supabase,
        writeFile,
        streams,
        env: {
          SUPABASE_URL: "http://localhost",
          SUPABASE_SERVICE_ROLE_KEY: "sr",
        } as Record<string, string | undefined>,
      } as never,
    );
    expect(code).toBe(0);
    expect(writeFile).toHaveBeenCalledTimes(1);
    const [path, body] = writeFile.mock.calls[0]!;
    expect(path).toBe("/tmp/out.md");
    expect(String(body)).toMatch(/alpha|beta/);
  });
});
