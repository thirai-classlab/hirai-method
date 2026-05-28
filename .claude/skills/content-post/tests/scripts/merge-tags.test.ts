/**
 * Tests for scripts/merge-tags.ts — Phase 8 Wave F (8.F.4)
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-f/plan.md §8.F.4 テスト観点 (7)
 *
 *   1. fetchAllTags returns every tag
 *   2. findSimilarTagPairs filters by threshold
 *   3. normalizes lowercase + whitespace
 *   4. higher usage_count becomes canonical
 *   5. self-pairs excluded
 *   6. --auto invokes INSERT on term_aliases (scope='tag')
 *   7. default mode: no INSERT
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
  tagsRows?: Array<{ id: string; name: string; usage_count: number }>;
} = {}): {
  calls: SupabaseCall[];
  from(table: string): unknown;
} {
  const calls: SupabaseCall[] = [];
  const tagsRows = cfg.tagsRows ?? [];
  return {
    calls,
    from(table: string) {
      const builder: {
        select: (cols?: string) => typeof builder;
        then: <T>(
          r: (v: { data: unknown[]; error: unknown }) => T,
        ) => Promise<T>;
        upsert: (
          rows: unknown,
          opts?: unknown,
        ) => Promise<{ data: unknown; error: unknown }>;
      } = {
        select(cols) {
          calls.push({ op: "select", table, args: cols });
          return builder;
        },
        then(resolve) {
          const rows = table === "tags" ? tagsRows : [];
          calls.push({ op: "await", table });
          return Promise.resolve(resolve({ data: rows, error: null }));
        },
        async upsert(rows, opts) {
          calls.push({ op: "upsert", table, args: { rows, opts } });
          return { data: rows, error: null };
        },
      };
      return builder;
    },
  };
}

describe("scripts/merge-tags.ts — fetchAllTags", () => {
  it("returns every tag row from tags table", async () => {
    const { fetchAllTags } = await import("../../scripts/merge-tags.js");
    const supabase = makeFakeSupabase({
      tagsRows: [
        { id: "t1", name: "Next.js", usage_count: 10 },
        { id: "t2", name: "nextjs", usage_count: 3 },
        { id: "t3", name: "react", usage_count: 7 },
      ],
    });
    const tags = await fetchAllTags(supabase as never);
    expect(tags.length).toBe(3);
    expect(tags.map((t) => t.name).sort()).toEqual(["Next.js", "nextjs", "react"]);
  });
});

describe("scripts/merge-tags.ts — findSimilarTagPairs", () => {
  it("returns only pairs above threshold", async () => {
    const { findSimilarTagPairs } = await import("../../scripts/merge-tags.js");
    // "Next.js" vs "nextjs" differs in the "." so naive 3-gram Jaccard is ~0.54.
    // Use a threshold that reflects realistic trigram similarity for that pair.
    const pairs = await findSimilarTagPairs(
      [
        { id: "t1", name: "Next.js", usage_count: 10 },
        { id: "t2", name: "nextjs", usage_count: 3 },
        { id: "t3", name: "react", usage_count: 7 },
      ],
      0.5,
    );
    expect(pairs.length).toBeGreaterThanOrEqual(1);
    expect(
      pairs.some(
        (p) =>
          (p.alias === "nextjs" || p.alias === "Next.js") &&
          (p.canonicalName === "Next.js" || p.canonicalName === "nextjs"),
      ),
    ).toBe(true);
    // "react" shouldn't match either of the others
    expect(pairs.every((p) => p.alias !== "react" && p.canonicalName !== "react")).toBe(true);
  });

  it("normalizes case + whitespace before comparing", async () => {
    const { findSimilarTagPairs } = await import("../../scripts/merge-tags.js");
    const pairs = await findSimilarTagPairs(
      [
        { id: "t1", name: "Tail wind CSS", usage_count: 20 },
        { id: "t2", name: "tailwind css", usage_count: 5 },
      ],
      0.5,
    );
    expect(pairs.length).toBe(1);
  });

  it("picks the higher-usage tag as canonical", async () => {
    const { findSimilarTagPairs } = await import("../../scripts/merge-tags.js");
    const pairs = await findSimilarTagPairs(
      [
        { id: "t1", name: "Next.js", usage_count: 100 },
        { id: "t2", name: "nextjs", usage_count: 1 },
      ],
      0.5,
    );
    expect(pairs.length).toBe(1);
    expect(pairs[0]?.canonicalId).toBe("t1");
    expect(pairs[0]?.canonicalName).toBe("Next.js");
    expect(pairs[0]?.alias).toBe("nextjs");
  });

  it("excludes self-pairs", async () => {
    const { findSimilarTagPairs } = await import("../../scripts/merge-tags.js");
    const pairs = await findSimilarTagPairs(
      [{ id: "t1", name: "nextjs", usage_count: 5 }],
      0.1,
    );
    expect(pairs.length).toBe(0);
  });
});

describe("scripts/merge-tags.ts — main()", () => {
  it("default run does NOT call upsert on term_aliases", async () => {
    const { main } = await import("../../scripts/merge-tags.js");
    const supabase = makeFakeSupabase({
      tagsRows: [
        { id: "t1", name: "Next.js", usage_count: 10 },
        { id: "t2", name: "nextjs", usage_count: 3 },
      ],
    });
    const streams = makeStreams();
    const code = await main(
      ["node", "merge-tags.ts", "--threshold", "0.5"],
      {
        getSupabaseClient: () => supabase,
        writeFile: vi.fn().mockResolvedValue(undefined),
        streams,
        env: {
          SUPABASE_URL: "http://localhost",
          SUPABASE_SERVICE_ROLE_KEY: "sr",
        } as Record<string, string | undefined>,
      } as never,
    );
    expect(code).toBe(0);
    expect(
      supabase.calls.find(
        (c) => c.op === "upsert" && c.table === "term_aliases",
      ),
    ).toBeUndefined();
    // The legacy table must no longer be touched.
    expect(
      supabase.calls.find(
        (c) => c.op === "upsert" && c.table === "tag_aliases",
      ),
    ).toBeUndefined();
  });

  it("--auto upserts candidates into term_aliases with scope='tag'", async () => {
    const { main } = await import("../../scripts/merge-tags.js");
    const supabase = makeFakeSupabase({
      tagsRows: [
        { id: "t1", name: "Next.js", usage_count: 100 },
        { id: "t2", name: "nextjs", usage_count: 1 },
      ],
    });
    const streams = makeStreams();
    const code = await main(
      ["node", "merge-tags.ts", "--threshold", "0.5", "--auto"],
      {
        getSupabaseClient: () => supabase,
        writeFile: vi.fn().mockResolvedValue(undefined),
        streams,
        env: {
          SUPABASE_URL: "http://localhost",
          SUPABASE_SERVICE_ROLE_KEY: "sr",
        } as Record<string, string | undefined>,
      } as never,
    );
    expect(code).toBe(0);
    const upsert = supabase.calls.find(
      (c) => c.op === "upsert" && c.table === "term_aliases",
    );
    expect(upsert).toBeTruthy();
    const rows = (upsert?.args as { rows: unknown[] }).rows as Array<{
      term: string;
      canonical: string;
      canonical_tag_id: string;
      scope: string;
    }>;
    expect(rows.length).toBe(1);
    expect(rows[0]?.term).toBe("nextjs");
    expect(rows[0]?.canonical).toBe("Next.js");
    expect(rows[0]?.canonical_tag_id).toBe("t1");
    expect(rows[0]?.scope).toBe("tag");
    // onConflict must target the new composite UNIQUE (term, scope).
    const opts = (upsert?.args as { opts?: { onConflict?: string } }).opts;
    expect(opts?.onConflict).toBe("term,scope");
    // The legacy table must no longer be touched.
    expect(
      supabase.calls.find(
        (c) => c.op === "upsert" && c.table === "tag_aliases",
      ),
    ).toBeUndefined();
  });
});
