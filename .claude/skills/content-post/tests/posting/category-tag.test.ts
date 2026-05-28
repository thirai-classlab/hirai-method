/**
 * Tests for src/posting/category-tag.ts — Phase 8 Wave E2
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e2/plan.md §テスト観点 (category-tag.test.ts) (19 cases)
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";

// Mock auto-tag so we don't hit the real Haiku pipeline.
vi.mock("../../src/posting/auto-tag.js", async () => {
  const actual = await vi.importActual<
    typeof import("../../src/posting/auto-tag.js")
  >("../../src/posting/auto-tag.js");
  return {
    ...actual,
    extractCandidatesFromContent: vi.fn(),
  };
});

import { extractCandidatesFromContent } from "../../src/posting/auto-tag.js";
import {
  suggestCategory,
  suggestTags,
  resolveTagAgainstMasters,
  confirmInteractively,
  type InteractiveReader,
  type ResolvedTag,
  type ConfirmedMeta,
} from "../../src/posting/category-tag.js";

const extractMock = extractCandidatesFromContent as unknown as ReturnType<
  typeof vi.fn
>;

beforeEach(() => {
  extractMock.mockReset();
});

// ---------------------------------------------------------------------------
// Supabase stub builder — minimal for this module's calls.
// ---------------------------------------------------------------------------

interface ContentCategoryRow {
  id?: string;
  content_type: string;
  slug: string;
  name: string;
}
interface TagRow {
  id: string;
  name: string;
  usage_count?: number;
}
interface TermAliasRow {
  term: string;
  canonical: string;
  canonical_tag_id: string;
  scope: string;
}

interface StubConfig {
  categories?: ContentCategoryRow[];
  tags?: TagRow[];
  aliases?: TermAliasRow[];
  /** pg_trgm 類似度 RPC シミュレータ。入力名→[{tag_id, name, similarity}] */
  similarityMap?: Record<
    string,
    Array<{ id: string; name: string; similarity: number }>
  >;
  /** INSERT 呼び出しを観測するためのスパイ */
  inserts?: {
    categories: Array<Record<string, unknown>>;
    tags: Array<Record<string, unknown>>;
  };
}

function createStubClient(cfg: StubConfig = {}): SupabaseClient {
  const categories = cfg.categories ?? [];
  const tags = cfg.tags ?? [];
  const aliases = cfg.aliases ?? [];
  const similarityMap = cfg.similarityMap ?? {};
  const inserts =
    cfg.inserts ?? { categories: [], tags: [] };

  // Generic chain supporting .select().eq()[.eq()][.maybeSingle()|.single()]
  const queryBuilder = (table: string) => {
    let filters: Array<{ col: string; val: unknown }> = [];
    let insertPayload: Record<string, unknown> | null = null;
    const rowsFor = (): Record<string, unknown>[] => {
      if (table === "content_categories") return categories as unknown as Record<string, unknown>[];
      if (table === "tags") return tags as unknown as Record<string, unknown>[];
      if (table === "term_aliases") return aliases as unknown as Record<string, unknown>[];
      return [];
    };

    const filterRow = (r: Record<string, unknown>) =>
      filters.every((f) => r[f.col] === f.val);

    const afterInsert = {
      select: () => afterInsert,
      single: async () => {
        if (!insertPayload) return { data: null, error: { message: "no insert" } };
        const id =
          (insertPayload.id as string | undefined) ??
          `${table}-${Math.random().toString(36).slice(2, 8)}`;
        const row = { ...insertPayload, id };
        if (table === "content_categories") inserts.categories.push(row);
        if (table === "tags") inserts.tags.push(row);
        return { data: row, error: null };
      },
    };

    const chain = {
      select: (_cols?: string) => chain,
      eq: (col: string, val: unknown) => {
        filters.push({ col, val });
        return chain;
      },
      maybeSingle: async () => {
        const match = rowsFor().find(filterRow);
        return { data: match ?? null, error: null };
      },
      single: async () => {
        const match = rowsFor().find(filterRow);
        return match
          ? { data: match, error: null }
          : { data: null, error: { code: "PGRST116", message: "no rows" } };
      },
      insert: (row: Record<string, unknown>) => {
        insertPayload = row;
        return afterInsert;
      },
    };
    return chain;
  };

  return {
    from: (table: string) => queryBuilder(table),
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === "search_tags_similar") {
        const q = (args.query as string | undefined) ?? "";
        return { data: similarityMap[q] ?? [], error: null };
      }
      return { data: [], error: null };
    },
  } as unknown as SupabaseClient;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SAMPLE_INPUT = {
  title: "pgvector でハイブリッド検索を実装する",
  body: "本文本文本文",
  type: "tech_articles" as const,
};

function mockHaiku(category: {
  slug: string;
  name: string;
  confidence: number;
}, tags: Array<{ name: string; confidence: number }>) {
  extractMock.mockResolvedValue({ category, tags });
}

// ---------------------------------------------------------------------------
// 1–3. suggestCategory
// ---------------------------------------------------------------------------

describe("suggestCategory", () => {
  it("returns a single category suggestion derived from Haiku", async () => {
    mockHaiku(
      { slug: "deepdive", name: "Deep Dive", confidence: 0.9 },
      [],
    );
    const client = createStubClient({
      categories: [
        {
          id: "cat-1",
          content_type: "tech_articles",
          slug: "deepdive",
          name: "Deep Dive",
        },
      ],
    });
    const out = await suggestCategory(SAMPLE_INPUT, { client });
    expect(out.slug).toBe("deepdive");
    expect(out.confidence).toBeCloseTo(0.9);
  });

  it("marks isNew=false when an existing category matches", async () => {
    mockHaiku(
      { slug: "deepdive", name: "Deep Dive", confidence: 0.9 },
      [],
    );
    const client = createStubClient({
      categories: [
        {
          id: "cat-1",
          content_type: "tech_articles",
          slug: "deepdive",
          name: "Deep Dive",
        },
      ],
    });
    const out = await suggestCategory(SAMPLE_INPUT, { client });
    expect(out.isNew).toBe(false);
  });

  it("marks isNew=true when no existing category matches the slug", async () => {
    mockHaiku(
      { slug: "brand-new", name: "Brand New", confidence: 0.7 },
      [],
    );
    const client = createStubClient({ categories: [] });
    const out = await suggestCategory(SAMPLE_INPUT, { client });
    expect(out.isNew).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// 4. suggestTags — limit
// ---------------------------------------------------------------------------

describe("suggestTags", () => {
  it("returns at most 5 suggestions", async () => {
    const tags = Array.from({ length: 9 }, (_, i) => ({
      name: `t${i}`,
      confidence: 0.6,
    }));
    mockHaiku({ slug: "deepdive", name: "Deep Dive", confidence: 0.9 }, tags);
    const client = createStubClient();
    const out = await suggestTags(SAMPLE_INPUT, { client });
    expect(out).toHaveLength(5);
  });
});

// ---------------------------------------------------------------------------
// 5–8. resolveTagAgainstMasters
// ---------------------------------------------------------------------------

describe("resolveTagAgainstMasters", () => {
  it("returns kind=existing when name exactly matches an existing tag", async () => {
    const client = createStubClient({
      tags: [{ id: "t-1", name: "Supabase", usage_count: 10 }],
    });
    const resolved = await resolveTagAgainstMasters(
      [{ name: "Supabase", confidence: 0.9 }],
      client,
    );
    expect(resolved).toHaveLength(1);
    expect(resolved[0]!.kind).toBe("existing");
    if (resolved[0]!.kind === "existing") {
      expect(resolved[0]!.id).toBe("t-1");
      expect(resolved[0]!.usageCount).toBe(10);
    }
  });

  it("returns kind=alias when a term_aliases row (scope=tag) points to a canonical tag", async () => {
    const client = createStubClient({
      tags: [{ id: "t-1", name: "React", usage_count: 3 }],
      aliases: [
        {
          term: "ReactJS",
          canonical: "React",
          canonical_tag_id: "t-1",
          scope: "tag",
        },
      ],
    });
    const resolved = await resolveTagAgainstMasters(
      [{ name: "ReactJS", confidence: 0.88 }],
      client,
    );
    expect(resolved[0]!.kind).toBe("alias");
    if (resolved[0]!.kind === "alias") {
      expect(resolved[0]!.alias).toBe("ReactJS");
      expect(resolved[0]!.canonicalName).toBe("React");
      expect(resolved[0]!.canonicalId).toBe("t-1");
    }
  });

  it("ignores term_aliases rows whose scope is not 'tag'", async () => {
    // search-only synonyms must not be treated as tag aliases.
    const client = createStubClient({
      tags: [{ id: "t-1", name: "React", usage_count: 3 }],
      aliases: [
        {
          term: "ReactJS",
          canonical: "React",
          canonical_tag_id: "t-1",
          scope: "search",
        },
      ],
    });
    const resolved = await resolveTagAgainstMasters(
      [{ name: "ReactJS", confidence: 0.6 }],
      client,
    );
    // Falls through to "new" because the tag-scoped lookup misses.
    expect(resolved[0]!.kind).toBe("new");
  });

  it("returns kind=similar when pg_trgm similarity > 0.75", async () => {
    const client = createStubClient({
      tags: [{ id: "t-pg", name: "PostgreSQL", usage_count: 5 }],
      similarityMap: {
        pgvector: [
          { id: "t-pg", name: "PostgreSQL", similarity: 0.82 },
        ],
      },
    });
    const resolved = await resolveTagAgainstMasters(
      [{ name: "pgvector", confidence: 0.8 }],
      client,
    );
    expect(resolved[0]!.kind).toBe("similar");
    if (resolved[0]!.kind === "similar") {
      expect(resolved[0]!.existingId).toBe("t-pg");
      expect(resolved[0]!.similarity).toBeCloseTo(0.82);
    }
  });

  it("returns kind=new when no match/alias/similar is found", async () => {
    const client = createStubClient({ tags: [] });
    const resolved = await resolveTagAgainstMasters(
      [{ name: "まったく新規", confidence: 0.6 }],
      client,
    );
    expect(resolved[0]!.kind).toBe("new");
    if (resolved[0]!.kind === "new") {
      expect(resolved[0]!.name).toBe("まったく新規");
    }
  });
});

// ---------------------------------------------------------------------------
// 9–16. confirmInteractively
// ---------------------------------------------------------------------------

function makeReader(lines: string[]): InteractiveReader {
  let idx = 0;
  return {
    question: async (_q: string) => {
      return lines[idx++] ?? "";
    },
    close: () => {},
  };
}

const SAMPLE_CATEGORY = {
  slug: "deepdive",
  name: "Deep Dive",
  confidence: 0.9,
  isNew: false,
};

function sampleResolved(): ResolvedTag[] {
  return [
    {
      kind: "existing",
      id: "t-1",
      name: "Supabase",
      usageCount: 10,
      confidence: 0.9,
    },
    {
      kind: "new",
      name: "ハイブリッド検索",
      confidence: 0.88,
    },
    {
      kind: "similar",
      suggested: "pgvector",
      existingName: "PostgreSQL",
      existingId: "t-pg",
      similarity: 0.82,
      confidence: 0.8,
    },
  ];
}

describe("confirmInteractively — dry-run", () => {
  it("returns committed=false and does not consult stdin", async () => {
    const reader = makeReader([]);
    const spy = vi.spyOn(reader, "question");
    const meta = await confirmInteractively(
      {
        category: {
          slug: "deepdive",
          name: "Deep Dive",
          confidence: 0.9,
          isNew: false,
        },
        resolved: sampleResolved(),
        mode: "dry-run",
      },
      { reader },
    );
    expect(meta.committed).toBe(false);
    expect(spy).not.toHaveBeenCalled();
  });
});

describe("confirmInteractively — auto-approve", () => {
  it("auto-approves an existing tag when confidence > 0.8", async () => {
    const meta = await confirmInteractively(
      {
        category: {
          slug: "deepdive",
          name: "Deep Dive",
          confidence: 0.9,
          isNew: false,
        },
        resolved: [
          {
            kind: "existing",
            id: "t-1",
            name: "Supabase",
            usageCount: 10,
            confidence: 0.85,
          },
        ],
        mode: "auto-approve",
      },
      { reader: makeReader([]) },
    );
    expect(meta.committed).toBe(true);
    expect(meta.tags.map((t) => t.name)).toContain("Supabase");
  });

  it("auto-approves a new tag when confidence > 0.85", async () => {
    const meta = await confirmInteractively(
      {
        category: SAMPLE_CATEGORY,
        resolved: [
          {
            kind: "new",
            name: "新規A",
            confidence: 0.9,
          },
          {
            kind: "new",
            name: "新規B",
            confidence: 0.5, // low → skip
          },
        ],
        mode: "auto-approve",
      },
      { reader: makeReader([]) },
    );
    expect(meta.tags.map((t) => t.name)).toContain("新規A");
    expect(meta.tags.map((t) => t.name)).not.toContain("新規B");
  });

  it("skips low-confidence suggestions in auto-approve", async () => {
    const meta = await confirmInteractively(
      {
        category: SAMPLE_CATEGORY,
        resolved: [
          {
            kind: "existing",
            id: "t-2",
            name: "Low",
            usageCount: 1,
            confidence: 0.4,
          },
        ],
        mode: "auto-approve",
      },
      { reader: makeReader([]) },
    );
    expect(meta.tags).toHaveLength(0);
  });
});

describe("confirmInteractively — interactive Y / N / S / E", () => {
  it("[Y] approves every suggestion", async () => {
    const meta = await confirmInteractively(
      {
        category: {
          slug: "deepdive",
          name: "Deep Dive",
          confidence: 0.9,
          isNew: false,
        },
        resolved: sampleResolved(),
        mode: "interactive",
      },
      { reader: makeReader(["Y"]) },
    );
    expect(meta.committed).toBe(true);
    // all 3 tags adopted
    expect(meta.tags).toHaveLength(3);
  });

  it("[N] cancels — returns committed=false with cancelled flag", async () => {
    const meta = await confirmInteractively(
      {
        category: SAMPLE_CATEGORY,
        resolved: sampleResolved(),
        mode: "interactive",
      },
      { reader: makeReader(["N"]) },
    );
    expect(meta.committed).toBe(false);
    expect(meta.cancelled).toBe(true);
  });

  it("[S] keeps only existing / alias resolutions", async () => {
    const resolved: ResolvedTag[] = [
      {
        kind: "existing",
        id: "t-1",
        name: "Supabase",
        usageCount: 10,
        confidence: 0.9,
      },
      { kind: "new", name: "New Tag", confidence: 0.9 },
      {
        kind: "similar",
        suggested: "pgvector",
        existingName: "PostgreSQL",
        existingId: "t-pg",
        similarity: 0.82,
        confidence: 0.8,
      },
    ];
    const meta = await confirmInteractively(
      {
        category: SAMPLE_CATEGORY,
        resolved,
        mode: "interactive",
      },
      { reader: makeReader(["S"]) },
    );
    const names = meta.tags.map((t) => t.name);
    expect(names).toContain("Supabase");
    // "similar" (PostgreSQL via寄せ) counts as existing adoption
    expect(names).toContain("PostgreSQL");
    expect(names).not.toContain("New Tag");
  });

  it("[E] asks per-suggestion and takes y/n decisions", async () => {
    // 3 suggestions: y, n, y  →  keep #1 and #3
    const meta = await confirmInteractively(
      {
        category: SAMPLE_CATEGORY,
        resolved: sampleResolved(),
        mode: "interactive",
      },
      { reader: makeReader(["E", "y", "n", "y"]) },
    );
    expect(meta.committed).toBe(true);
    expect(meta.tags).toHaveLength(2);
    expect(meta.tags.map((t) => t.name)).toEqual([
      "Supabase",
      "PostgreSQL",
    ]);
  });
});

// Phase 11 W11.3a: commitCategoryAndTags は削除された (POST /api/ingest 経由)。
// 旧 17-19 ケースの test も同時に削除。タグ正規化 (slugifyTagName) は今後
// サーバ側 (/api/ingest) でカバー。

// ---------------------------------------------------------------------------
// Wave 11.3e W3 — allowlist fail-fast + three-choice interactive fallback
// ---------------------------------------------------------------------------

describe("suggestCategory — Wave 11.3e W3 allowlist fail-fast", () => {
  const ALLOW = [
    { slug: "tips", name: "Tips", description: null },
    { slug: "architecture", name: "Architecture", description: null },
    { slug: "reference", name: "Reference", description: "Catalog" },
  ];

  function makeReader(answers: string[]): InteractiveReader {
    const queue = [...answers];
    return {
      question: vi.fn().mockImplementation(async () => {
        const a = queue.shift();
        if (a === undefined) throw new Error("reader: no more queued answers");
        return a;
      }),
      close: vi.fn(),
    };
  }

  it("returns 1st-pass slug as-is when within allowlist (fallbackUsed='none')", async () => {
    extractMock.mockResolvedValueOnce({
      category: { slug: "tips", name: "Tips", confidence: 0.9 },
      tags: [],
    });
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      { client: createStubClient(), allowedCategories: ALLOW },
    );
    expect(result.slug).toBe("tips");
    expect(result.fallbackUsed).toBe("none");
    expect(result.isNew).toBe(false);
    expect(extractMock).toHaveBeenCalledTimes(1);
  });

  it("retries on 2nd pass when 1st miss and 2nd is within allow (fallbackUsed='second-pass')", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "unknown", name: "Unknown", confidence: 0.7 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "architecture", name: "Architecture", confidence: 0.6 },
        tags: [],
      });
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      { client: createStubClient(), allowedCategories: ALLOW },
    );
    expect(result.slug).toBe("architecture");
    expect(result.fallbackUsed).toBe("second-pass");
    expect(extractMock).toHaveBeenCalledTimes(2);
  });

  it("throws in auto-approve mode when both passes miss", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "alpha", name: "Alpha", confidence: 0.8 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "beta", name: "Beta", confidence: 0.7 },
        tags: [],
      });
    await expect(
      suggestCategory(
        { title: "t", body: "b", type: "knowledge" },
        {
          client: createStubClient(),
          allowedCategories: ALLOW,
          mode: "auto-approve",
        },
      ),
    ).rejects.toThrow(/non-allowlist slugs 'alpha' and 'beta'/);
  });

  it("throws in dry-run mode when both passes miss", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "alpha", name: "A", confidence: 0.8 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "beta", name: "B", confidence: 0.7 },
        tags: [],
      });
    await expect(
      suggestCategory(
        { title: "t", body: "b", type: "knowledge" },
        {
          client: createStubClient(),
          allowedCategories: ALLOW,
          mode: "dry-run",
        },
      ),
    ).rejects.toThrow(/dry-run mode/);
  });

  it("interactive choice=3 aborts with throw", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "alpha", name: "A", confidence: 0.8 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "beta", name: "B", confidence: 0.7 },
        tags: [],
      });
    const reader = makeReader(["3"]);
    await expect(
      suggestCategory(
        { title: "t", body: "b", type: "knowledge" },
        {
          client: createStubClient(),
          allowedCategories: ALLOW,
          mode: "interactive",
          reader,
        },
      ),
    ).rejects.toThrow(/aborted by user/);
  });

  it("interactive choice=1 picks an existing category (fallbackUsed='user-confirm')", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "alpha", name: "A", confidence: 0.8 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "beta", name: "B", confidence: 0.7 },
        tags: [],
      });
    // choice=1 then pick index 2 (architecture)
    const reader = makeReader(["1", "2"]);
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      {
        client: createStubClient(),
        allowedCategories: ALLOW,
        mode: "interactive",
        reader,
      },
    );
    expect(result.slug).toBe("architecture");
    expect(result.name).toBe("Architecture");
    expect(result.fallbackUsed).toBe("user-confirm");
    expect(result.isNew).toBe(false);
  });

  it("interactive choice=2 adds new category via postNewCategory (fallbackUsed='user-added')", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "newslug", name: "新カテゴリ", confidence: 0.9 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "newslug", name: "新カテゴリ", confidence: 0.85 },
        tags: [],
      });
    const reader = makeReader(["2"]);
    const postMock = vi.fn().mockResolvedValue({
      slug: "newslug",
      name: "新カテゴリ",
      description: null,
    });
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      {
        client: createStubClient(),
        allowedCategories: ALLOW,
        mode: "interactive",
        reader,
        postNewCategory: postMock,
      },
    );
    expect(result.slug).toBe("newslug");
    expect(result.fallbackUsed).toBe("user-added");
    expect(result.isNew).toBe(false);
    expect(postMock).toHaveBeenCalledWith({
      type: "knowledge",
      slug: "newslug",
      name: "新カテゴリ",
      description: null,
    });
  });

  it("interactive choice=2 handles 409 race by returning existing entry", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "racy", name: "レースカテゴリ", confidence: 0.9 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "racy", name: "レースカテゴリ", confidence: 0.85 },
        tags: [],
      });
    const reader = makeReader(["2"]);
    // postNewCategory mock simulates 409 → returns existing entry
    const postMock = vi.fn().mockResolvedValue({
      slug: "racy",
      name: "Racy (existing)",
      description: "already there",
    });
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      {
        client: createStubClient(),
        allowedCategories: ALLOW,
        mode: "interactive",
        reader,
        postNewCategory: postMock,
      },
    );
    expect(result.slug).toBe("racy");
    expect(result.name).toBe("Racy (existing)");
    expect(result.fallbackUsed).toBe("user-added");
  });

  it("interactive choice=1 with invalid pick index throws", async () => {
    extractMock
      .mockResolvedValueOnce({
        category: { slug: "alpha", name: "A", confidence: 0.8 },
        tags: [],
      })
      .mockResolvedValueOnce({
        category: { slug: "beta", name: "B", confidence: 0.7 },
        tags: [],
      });
    const reader = makeReader(["1", "99"]);
    await expect(
      suggestCategory(
        { title: "t", body: "b", type: "knowledge" },
        {
          client: createStubClient(),
          allowedCategories: ALLOW,
          mode: "interactive",
          reader,
        },
      ),
    ).rejects.toThrow(/invalid pick index/);
  });

  it("falls back to legacy DB match when allowedCategories is empty (compat)", async () => {
    extractMock.mockResolvedValueOnce({
      category: { slug: "legacy", name: "Legacy", confidence: 0.9 },
      tags: [],
    });
    const result = await suggestCategory(
      { title: "t", body: "b", type: "knowledge" },
      {
        client: createStubClient({
          categories: [
            { content_type: "knowledge", slug: "legacy", name: "Legacy" },
          ],
        }),
        // allowedCategories omitted → legacy path
      },
    );
    expect(result.slug).toBe("legacy");
    expect(result.isNew).toBe(false);
    expect(result.fallbackUsed).toBeUndefined();
  });
});
