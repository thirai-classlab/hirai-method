/**
 * tests/posting/category-admin.test.ts — Wave 11.3e W3
 *
 * postNewCategory() の動作検証:
 *   - 201 success → CategoryAllowEntry を返す
 *   - 401 unauthorized → throw
 *   - 409 duplicate (race) → existing を返す (冪等継続)
 *   - 400 invalid → throw with detail
 *   - network error → throw
 *   - missing env → throw
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { postNewCategory } from "../../src/posting/category-admin.js";

const BASE = "https://example.test";
const SECRET = "test-secret-token";

describe("postNewCategory — happy path", () => {
  it("returns CategoryAllowEntry on 201", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: true,
      status: 201,
      statusText: "Created",
      json: async () => ({
        category: {
          id: "abc",
          content_type: "knowledge",
          slug: "reference",
          name: "リファレンス",
          description: "カタログ系",
          usage_count: 0,
          created_at: "2026-05-21T00:00:00Z",
        },
      }),
    });

    const result = await postNewCategory(
      {
        type: "knowledge",
        slug: "reference",
        name: "リファレンス",
        description: "カタログ系",
      },
      { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
    );

    expect(result).toEqual({
      slug: "reference",
      name: "リファレンス",
      description: "カタログ系",
    });

    const callArgs = fetchMock.mock.calls[0]!;
    expect(callArgs[0]).toBe(`${BASE}/api/content-categories`);
    const init = callArgs[1] as RequestInit;
    expect(init.method).toBe("POST");
    expect((init.headers as Record<string, string>)["Authorization"]).toBe(
      `Bearer ${SECRET}`,
    );
    expect(JSON.parse(init.body as string)).toEqual({
      type: "knowledge",
      slug: "reference",
      name: "リファレンス",
      description: "カタログ系",
    });
  });

  it("defaults description to null when omitted", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        category: { slug: "newcat", name: "新", description: null },
      }),
    });
    await postNewCategory(
      { type: "article", slug: "newcat", name: "新" },
      { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
    );
    const body = JSON.parse(
      (fetchMock.mock.calls[0]![1] as RequestInit).body as string,
    );
    expect(body.description).toBeNull();
  });
});

describe("postNewCategory — error paths", () => {
  it("throws on 401 unauthorized", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: false,
      status: 401,
      statusText: "Unauthorized",
      json: async () => ({ error: "unauthorized", trace_id: "t-1" }),
      text: async () => "",
    });
    await expect(
      postNewCategory(
        { type: "knowledge", slug: "x", name: "x" },
        {
          fetch: fetchMock as unknown as typeof fetch,
          apiBase: BASE,
          secret: "wrong",
        },
      ),
    ).rejects.toThrow(/HTTP 401/);
  });

  it("returns existing entry on 409 (idempotent race)", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: false,
      status: 409,
      statusText: "Conflict",
      json: async () => ({
        error: "duplicate",
        trace_id: "t-2",
        existing: {
          id: "existing-id",
          slug: "reference",
          name: "Reference",
          description: null,
        },
      }),
    });
    const result = await postNewCategory(
      { type: "knowledge", slug: "reference", name: "リファレンス" },
      { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
    );
    expect(result).toEqual({
      slug: "reference",
      name: "Reference",
      description: null,
    });
  });

  it("throws on 409 without existing field", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: false,
      status: 409,
      json: async () => ({ error: "duplicate" }),
    });
    await expect(
      postNewCategory(
        { type: "knowledge", slug: "x", name: "x" },
        { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
      ),
    ).rejects.toThrow(/lacks valid 'existing'/);
  });

  it("throws on 400 invalid_input", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce({
      ok: false,
      status: 400,
      statusText: "Bad Request",
      json: async () => ({
        error: "invalid_input",
        trace_id: "t-3",
        details: "slug must match /^[a-z]...",
      }),
      text: async () => "",
    });
    await expect(
      postNewCategory(
        { type: "knowledge", slug: "INVALID", name: "x" },
        { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
      ),
    ).rejects.toThrow(/HTTP 400/);
  });

  it("throws on network error", async () => {
    const fetchMock = vi.fn().mockRejectedValueOnce(new Error("ECONNREFUSED"));
    await expect(
      postNewCategory(
        { type: "knowledge", slug: "x", name: "x" },
        { fetch: fetchMock as unknown as typeof fetch, apiBase: BASE, secret: SECRET },
      ),
    ).rejects.toThrow(/ECONNREFUSED/);
  });
});

describe("postNewCategory — env defaults", () => {
  let savedBase: string | undefined;
  let savedSecret: string | undefined;

  beforeEach(() => {
    savedBase = process.env.API_BASE_URL;
    savedSecret = process.env.CATEGORY_ADMIN_SECRET;
  });

  afterEach(() => {
    if (savedBase === undefined) delete process.env.API_BASE_URL;
    else process.env.API_BASE_URL = savedBase;
    if (savedSecret === undefined) delete process.env.CATEGORY_ADMIN_SECRET;
    else process.env.CATEGORY_ADMIN_SECRET = savedSecret;
  });

  it("throws when API_BASE_URL is not set", async () => {
    delete process.env.API_BASE_URL;
    process.env.CATEGORY_ADMIN_SECRET = SECRET;
    await expect(
      postNewCategory({ type: "knowledge", slug: "x", name: "x" }),
    ).rejects.toThrow(/API_BASE_URL/);
  });

  it("throws when CATEGORY_ADMIN_SECRET is not set", async () => {
    process.env.API_BASE_URL = BASE;
    delete process.env.CATEGORY_ADMIN_SECRET;
    await expect(
      postNewCategory({ type: "knowledge", slug: "x", name: "x" }),
    ).rejects.toThrow(/CATEGORY_ADMIN_SECRET/);
  });
});
