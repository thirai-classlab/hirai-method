/**
 * Tests for src/posting/category-allowlist.ts — Wave 11.3e W2
 *
 * Fetches allowed categories from the site API
 * (GET /api/content-categories?type=...) and caches per-type results in-process.
 *
 * Cases:
 *   1. happy path returns categories
 *   2. memoizes per type (fetch called once across two calls)
 *   3. 404 throws + cache does not retain the failure
 *   4. 500 throws + cache does not retain the failure
 *   5. network error (reject) throws + cache does not retain the failure
 *   6. clearAllowlistCache() resets the cache
 *   7. invalid response shape throws
 *   8. missing apiBase throws
 */
import { describe, it, expect, beforeEach, vi } from "vitest";

import {
  fetchAllowedCategories,
  fetchAllowedCategoriesForKind,
  BUSINESS_AXIS_CATEGORIES,
  clearAllowlistCache,
  type CategoryAllowEntry,
} from "../../src/posting/category-allowlist.js";

const SAMPLE_KNOWLEDGE: CategoryAllowEntry[] = [
  { slug: "architecture", name: "Architecture", description: null },
  { slug: "devops", name: "DevOps", description: "Operations" },
  { slug: "reference", name: "Reference", description: null },
  { slug: "review", name: "Review", description: null },
  { slug: "tips", name: "Tips", description: null },
  { slug: "tutorial", name: "Tutorial", description: null },
];

function makeJsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

beforeEach(() => {
  clearAllowlistCache();
});

describe("fetchAllowedCategories — happy path", () => {
  it("returns parsed categories from the API", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
    ) as unknown as typeof fetch;

    const out = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(out).toEqual(SAMPLE_KNOWLEDGE);
    expect(fakeFetch).toHaveBeenCalledTimes(1);
    const url = (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock
      .calls[0]![0] as string;
    expect(url).toBe(
      "https://example.test/api/content-categories?type=knowledge",
    );
  });
});

describe("fetchAllowedCategories — memoization", () => {
  it("calls fetch only once for the same type across multiple calls", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
    ) as unknown as typeof fetch;

    const first = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    const second = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(first).toEqual(SAMPLE_KNOWLEDGE);
    expect(second).toEqual(SAMPLE_KNOWLEDGE);
    expect(fakeFetch).toHaveBeenCalledTimes(1);
  });
});

describe("fetchAllowedCategories — 404 propagates and resets cache", () => {
  it("throws and allows a subsequent retry to call fetch again", async () => {
    const fakeFetch = vi
      .fn()
      .mockResolvedValueOnce(makeJsonResponse({ error: "not found" }, 404))
      .mockResolvedValueOnce(
        makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
      ) as unknown as typeof fetch;

    await expect(
      fetchAllowedCategories("knowledge", {
        fetch: fakeFetch,
        apiBase: "https://example.test",
      }),
    ).rejects.toThrow(/HTTP 404/);

    const retry = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(retry).toEqual(SAMPLE_KNOWLEDGE);
    expect(
      (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock.calls.length,
    ).toBe(2);
  });
});

describe("fetchAllowedCategories — 500 propagates and resets cache", () => {
  it("throws and allows a subsequent retry to call fetch again", async () => {
    const fakeFetch = vi
      .fn()
      .mockResolvedValueOnce(makeJsonResponse({ error: "boom" }, 500))
      .mockResolvedValueOnce(
        makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
      ) as unknown as typeof fetch;

    await expect(
      fetchAllowedCategories("knowledge", {
        fetch: fakeFetch,
        apiBase: "https://example.test",
      }),
    ).rejects.toThrow(/HTTP 500/);

    const retry = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(retry).toEqual(SAMPLE_KNOWLEDGE);
    expect(
      (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock.calls.length,
    ).toBe(2);
  });
});

describe("fetchAllowedCategories — network error propagates and resets cache", () => {
  it("throws and allows a subsequent retry to call fetch again", async () => {
    const fakeFetch = vi
      .fn()
      .mockRejectedValueOnce(new Error("ECONNREFUSED"))
      .mockResolvedValueOnce(
        makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
      ) as unknown as typeof fetch;

    await expect(
      fetchAllowedCategories("knowledge", {
        fetch: fakeFetch,
        apiBase: "https://example.test",
      }),
    ).rejects.toThrow(/ECONNREFUSED/);

    const retry = await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(retry).toEqual(SAMPLE_KNOWLEDGE);
    expect(
      (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock.calls.length,
    ).toBe(2);
  });
});

describe("fetchAllowedCategories — clearAllowlistCache", () => {
  it("forces the next call to fetch again", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
    ) as unknown as typeof fetch;

    await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    clearAllowlistCache();
    await fetchAllowedCategories("knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(
      (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock.calls.length,
    ).toBe(2);
  });
});

describe("fetchAllowedCategories — invalid response shape", () => {
  it("throws when `categories` is missing or not an array", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: "nope" }),
    ) as unknown as typeof fetch;

    await expect(
      fetchAllowedCategories("knowledge", {
        fetch: fakeFetch,
        apiBase: "https://example.test",
      }),
    ).rejects.toThrow(/invalid response shape/);
  });
});

describe("fetchAllowedCategories — missing apiBase", () => {
  it("throws when neither deps.apiBase nor process.env.API_BASE_URL is set", async () => {
    const prev = process.env.API_BASE_URL;
    delete process.env.API_BASE_URL;
    try {
      const fakeFetch = vi.fn() as unknown as typeof fetch;
      await expect(
        fetchAllowedCategories("knowledge", { fetch: fakeFetch }),
      ).rejects.toThrow(/API_BASE_URL/);
    } finally {
      if (prev !== undefined) process.env.API_BASE_URL = prev;
    }
  });
});

// ---------------------------------------------------------------------------
// #58 Step 3: fetchAllowedCategoriesForKind — kind 別 fail-fast filter
// ---------------------------------------------------------------------------

describe("fetchAllowedCategoriesForKind — operation", () => {
  it("returns only the 2 business-axis categories without calling the API", async () => {
    const fakeFetch = vi.fn() as unknown as typeof fetch;
    const out = await fetchAllowedCategoriesForKind("operation", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(out).toEqual(BUSINESS_AXIS_CATEGORIES);
    expect(out.map((c) => c.slug).sort()).toEqual([
      "lifeline",
      "vacancy-energization",
    ]);
    // business-axis は seed 固定 (DB content_type=operation/domain_knowledge は
    // GET /api/content-categories の許可 type 外) なので fetch は呼ばれない。
    expect(fakeFetch).not.toHaveBeenCalled();
  });
});

describe("fetchAllowedCategoriesForKind — domain_knowledge", () => {
  it("returns the same 2 business-axis categories", async () => {
    const fakeFetch = vi.fn() as unknown as typeof fetch;
    const out = await fetchAllowedCategoriesForKind("domain_knowledge", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(out).toEqual(BUSINESS_AXIS_CATEGORIES);
    expect(fakeFetch).not.toHaveBeenCalled();
  });
});

describe("fetchAllowedCategoriesForKind — concept delegates to knowledge API", () => {
  it("calls fetchAllowedCategories('knowledge') unchanged", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
    ) as unknown as typeof fetch;
    const out = await fetchAllowedCategoriesForKind("concept", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(out).toEqual(SAMPLE_KNOWLEDGE);
    const url = (fakeFetch as unknown as ReturnType<typeof vi.fn>).mock
      .calls[0]![0] as string;
    expect(url).toBe(
      "https://example.test/api/content-categories?type=knowledge",
    );
  });
});

// #58 round-2 (M10): fetchAllowedCategoriesForKind は非 undefined の
// KnowledgeKind しか受け付けない (型で undefined を排除)。undefined→concept の
// default 解決は呼び出し元 (stage11CategoryTag.run) の責務へ移したため、ここでは
// concept を明示で渡したときに knowledge allowlist 経路へ委譲することのみ担保する
// (旧 "undefined delegates to knowledge" test は契約変更で repurpose)。
describe("fetchAllowedCategoriesForKind — concept (default-resolved) delegates to knowledge", () => {
  it("concept delegates to the knowledge allowlist (caller resolves undefined→concept)", async () => {
    const fakeFetch = vi.fn(async () =>
      makeJsonResponse({ type: "knowledge", categories: SAMPLE_KNOWLEDGE }),
    ) as unknown as typeof fetch;
    const out = await fetchAllowedCategoriesForKind("concept", {
      fetch: fakeFetch,
      apiBase: "https://example.test",
    });
    expect(out).toEqual(SAMPLE_KNOWLEDGE);
    expect(fakeFetch).toHaveBeenCalledTimes(1);
  });
});
