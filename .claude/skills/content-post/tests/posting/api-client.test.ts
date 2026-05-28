/**
 * Tests for src/posting/api-client.ts — Phase 11 W1.D-2 (11.1.9)
 *
 * テスト観点:
 *   1. INGEST_SECRET 設定 + URL 既定 → 正しい x-ingest-secret ヘッダ
 *   2. traceId 引数あり → x-trace-id ヘッダに含む
 *   3. traceId 引数なし → crypto.randomUUID で自動生成
 *   4. レスポンス 201 → IngestResult に id/slug 反映
 *   5. レスポンス 200 + mode='mock' → IngestResult.mode='mock'
 *   6. 401 → throw Error (status + body)
 *   7. 409 slug_conflict → throw with code='slug_conflict'
 *   8. 500 → throw with body.trace_id 含む
 *   9. ネットワークエラー → throw (fetch reject)
 *   10. INGEST_SECRET 未設定 → 即座に throw（fetch を呼ばない）
 *   11. CLASSLAB_WEEKLY_NEWS_API_URL 設定 → そっちを優先
 */
import { describe, it, expect, vi, beforeEach, afterEach, type MockInstance } from "vitest";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const VALID_PAYLOAD = {
  type: "knowledge" as const,
  title: "Test Knowledge",
  slug: "test-knowledge",
  html: "<p>Hello</p>",
  raw_markdown: "Hello",
  category_slug: "tips",
  summary: "A summary",
  author: "平井拓真",
  tag_ids: ["t-1", "t-2"],
  tag_names_new: ["new-tag"],
  related_content_ids: ["k-10"],
  related_content_types: ["knowledge"],
  depth: 0,
};

function makeOkResponse(body: object, status = 201, headers: Record<string, string> = {}) {
  const defaultHeaders: Record<string, string> = {
    "content-type": "application/json",
    "x-trace-id": "server-trace-id",
    ...headers,
  };
  return {
    ok: status < 400,
    status,
    headers: {
      get: (name: string) => defaultHeaders[name.toLowerCase()] ?? null,
    },
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("src/posting/api-client.ts — ingestViaApi()", () => {
  let originalEnv: NodeJS.ProcessEnv;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: MockInstance<(...args: any[]) => any>;

  beforeEach(() => {
    originalEnv = { ...process.env };
    fetchSpy = vi.spyOn(global, "fetch");
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("1. sends x-ingest-secret header with INGEST_SECRET value", async () => {
    process.env.INGEST_SECRET = "my-secret";
    delete process.env.CLASSLAB_WEEKLY_NEWS_API_URL;

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    expect(fetchSpy).toHaveBeenCalledOnce();
    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers["x-ingest-secret"]).toBe("my-secret");
  });

  it("2. uses custom traceId in x-trace-id header when provided", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD, { traceId: "custom-trace-123" });

    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers["x-trace-id"]).toBe("custom-trace-123");
  });

  it("3. generates a UUID for x-trace-id when traceId is not provided", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    const headers = init.headers as Record<string, string>;
    // UUID v4 format
    expect(headers["x-trace-id"]).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });

  it("4. returns IngestResult with id, slug, augment_job_id on 201 response", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse(
        { id: "k-abc", slug: "test-knowledge", augment_job_id: null },
        201,
        { "x-trace-id": "trace-xyz" },
      ) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    const result = await ingestViaApi(VALID_PAYLOAD);

    expect(result.id).toBe("k-abc");
    expect(result.slug).toBe("test-knowledge");
    expect(result.augment_job_id).toBeNull();
    expect(result.trace_id).toBe("trace-xyz");
  });

  it("5. returns IngestResult with mode='mock' on 200 mock response", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse(
        { id: "mock-trace-xyz", slug: "test-knowledge", augment_job_id: null, mode: "mock" },
        200,
      ) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    const result = await ingestViaApi(VALID_PAYLOAD);

    expect(result.mode).toBe("mock");
    expect(result.id).toBe("mock-trace-xyz");
  });

  it("6. throws on 401 with status and error in message", async () => {
    process.env.INGEST_SECRET = "wrong-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ error: "unauthorized" }, 401) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await expect(ingestViaApi(VALID_PAYLOAD)).rejects.toThrow(/401/);
  });

  it("7. throws SlugConflictError on 409 with existing_slug / existing_id from server payload", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse(
        {
          error: "slug_conflict",
          existing_slug: "test-knowledge",
          existing_id: "k-existing-99",
          content_type: "knowledge",
        },
        409,
      ) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    const { SlugConflictError } = await import("../../src/posting/slug-errors.js");
    let caughtError: unknown;
    try {
      await ingestViaApi(VALID_PAYLOAD);
    } catch (e) {
      caughtError = e;
    }
    expect(caughtError).toBeInstanceOf(SlugConflictError);
    const err = caughtError as InstanceType<typeof SlugConflictError>;
    expect(err.slug).toBe("test-knowledge");
    expect(err.existingId).toBe("k-existing-99");
    expect(err.contentType).toBe("knowledge");
  });

  it("7b. 409 falls back to payload.slug / payload.type when server omits existing_slug", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ error: "slug_conflict" }, 409) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    const { SlugConflictError } = await import("../../src/posting/slug-errors.js");
    let caughtError: unknown;
    try {
      await ingestViaApi(VALID_PAYLOAD);
    } catch (e) {
      caughtError = e;
    }
    expect(caughtError).toBeInstanceOf(SlugConflictError);
    const err = caughtError as InstanceType<typeof SlugConflictError>;
    expect(err.slug).toBe(VALID_PAYLOAD.slug);
    expect(err.contentType).toBe(VALID_PAYLOAD.type);
    expect(err.existingId).toBeUndefined();
  });

  it("8. throws on 500 and includes server trace_id in error", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse(
        { error: "database_error", trace_id: "server-trace-500" },
        500,
      ) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await expect(ingestViaApi(VALID_PAYLOAD)).rejects.toSatisfy(
      (e: unknown) => JSON.stringify(e).includes("server-trace-500") || (e as Error).message.includes("server-trace-500"),
    );
  });

  it("9. rethrows network errors when fetch rejects", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockRejectedValueOnce(new TypeError("Failed to fetch"));

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await expect(ingestViaApi(VALID_PAYLOAD)).rejects.toThrow("Failed to fetch");
  });

  it("10. throws immediately without calling fetch when INGEST_SECRET is not set", async () => {
    delete process.env.INGEST_SECRET;
    fetchSpy.mockResolvedValueOnce(makeOkResponse({}) as unknown as Response);

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await expect(ingestViaApi(VALID_PAYLOAD)).rejects.toThrow(/INGEST_SECRET/);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("11. uses CLASSLAB_WEEKLY_NEWS_API_URL when set instead of default", async () => {
    process.env.INGEST_SECRET = "my-secret";
    process.env.CLASSLAB_WEEKLY_NEWS_API_URL = "https://custom.example.com";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    const [url] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toContain("custom.example.com");
  });

  it("uses default production URL when CLASSLAB_WEEKLY_NEWS_API_URL is not set", async () => {
    process.env.INGEST_SECRET = "my-secret";
    delete process.env.CLASSLAB_WEEKLY_NEWS_API_URL;

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    const [url] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toContain("classlab-weekly-news.vercel.app");
  });

  it("sends correct request body including type, title, slug, html, tag_ids, tag_names_new", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    const body = JSON.parse(init.body as string);
    expect(body.type).toBe("knowledge");
    expect(body.title).toBe("Test Knowledge");
    expect(body.slug).toBe("test-knowledge");
    expect(body.html).toBe("<p>Hello</p>");
    expect(body.tag_ids).toEqual(["t-1", "t-2"]);
    expect(body.tag_names_new).toEqual(["new-tag"]);
    expect(body.related_content_ids).toEqual(["k-10"]);
    expect(body.related_content_types).toEqual(["knowledge"]);
  });

  it("sends POST method with correct Content-Type", async () => {
    process.env.INGEST_SECRET = "my-secret";

    fetchSpy.mockResolvedValueOnce(
      makeOkResponse({ id: "k-1", slug: "test-knowledge", augment_job_id: null }) as unknown as Response,
    );

    const { ingestViaApi } = await import("../../src/posting/api-client.js");
    await ingestViaApi(VALID_PAYLOAD);

    const [url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    expect(String(url)).toContain("/api/ingest");
    expect(init.method).toBe("POST");
    const headers = init.headers as Record<string, string>;
    expect(headers["content-type"]).toBe("application/json");
  });
});
