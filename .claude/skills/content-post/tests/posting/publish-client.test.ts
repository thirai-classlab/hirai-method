/**
 * Tests for src/posting/publish-client.ts — Task #33 W4
 *
 * テスト観点:
 *   1. BATCH_SECRET 未設定 → fetch を呼ばずに即座に throw
 *   2. 200 + {success: true, published_at, revalidated} → 成功オブジェクト返却
 *   3. 200 + {already_published: true} → already_published フラグ付き返却
 *   4. 401 → throw "unauthorized" 含むエラー
 *   5. 404 → throw "not_found" + slug 含むエラー
 *   6. 500 → throw with detail 含むエラー
 *   7. CLASSLAB_WEEKLY_NEWS_API_URL 設定 → カスタム URL 優先
 *   8. デフォルト URL = https://classlab-weekly-news.vercel.app
 *   9. POST /api/publish に正しい body (kind, slug) を送信
 *   10. x-batch-secret ヘッダに BATCH_SECRET を設定
 */
import { describe, it, expect, vi, beforeEach, afterEach, type MockInstance } from "vitest";

function makeResponse(body: object, status: number, headers: Record<string, string> = {}) {
  const allHeaders: Record<string, string> = {
    "content-type": "application/json",
    ...headers,
  };
  return {
    ok: status >= 200 && status < 400,
    status,
    headers: {
      get: (name: string) => allHeaders[name.toLowerCase()] ?? null,
    },
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}

describe("src/posting/publish-client.ts — publishContent()", () => {
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

  it("1. throws immediately without calling fetch when BATCH_SECRET is not set", async () => {
    delete process.env.BATCH_SECRET;
    fetchSpy.mockResolvedValueOnce(makeResponse({}, 200) as unknown as Response);

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await expect(
      publishContent({ kind: "knowledge", slug: "test-slug" }),
    ).rejects.toThrow(/BATCH_SECRET/);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("2. returns success object with published_at and revalidated on 200", async () => {
    process.env.BATCH_SECRET = "test-secret";
    delete process.env.CLASSLAB_WEEKLY_NEWS_API_URL;

    const publishedAt = "2026-04-26T10:00:00.000Z";
    fetchSpy.mockResolvedValueOnce(
      makeResponse(
        { success: true, published_at: publishedAt, revalidated: ["home", "knowledge-list"] },
        200,
      ) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    const result = await publishContent({ kind: "knowledge", slug: "test-knowledge" });

    expect(result.success).toBe(true);
    expect(result.published_at).toBe(publishedAt);
    expect(result.revalidated).toEqual(["home", "knowledge-list"]);
  });

  it("3. returns already_published flag when content was already published", async () => {
    process.env.BATCH_SECRET = "test-secret";

    fetchSpy.mockResolvedValueOnce(
      makeResponse(
        { success: true, already_published: true, published_at: "2026-04-25T00:00:00.000Z", revalidated: [] },
        200,
      ) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    const result = await publishContent({ kind: "tech_article", slug: "some-article" });

    expect(result.already_published).toBe(true);
  });

  it("4. throws with 'unauthorized' on 401 response", async () => {
    process.env.BATCH_SECRET = "wrong-secret";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ error: "unauthorized" }, 401) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await expect(
      publishContent({ kind: "knowledge", slug: "test-slug" }),
    ).rejects.toThrow(/unauthorized|401/i);
  });

  it("5. throws with 'not_found' and slug on 404 response", async () => {
    process.env.BATCH_SECRET = "test-secret";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ error: "not_found" }, 404) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    let caught: unknown;
    try {
      await publishContent({ kind: "knowledge", slug: "missing-slug" });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeDefined();
    const msg = (caught as Error).message;
    expect(msg).toMatch(/not_found|404/i);
    expect(msg).toContain("missing-slug");
  });

  it("6. throws with detail on 500 response", async () => {
    process.env.BATCH_SECRET = "test-secret";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ error: "internal_server_error", detail: "DB timeout" }, 500) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await expect(
      publishContent({ kind: "issue", slug: "weekly-2026-04-26" }),
    ).rejects.toThrow(/500|internal_server_error|DB timeout/);
  });

  it("7. uses CLASSLAB_WEEKLY_NEWS_API_URL when set", async () => {
    process.env.BATCH_SECRET = "test-secret";
    process.env.CLASSLAB_WEEKLY_NEWS_API_URL = "https://custom.example.com";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ success: true, published_at: "2026-04-26T10:00:00.000Z", revalidated: [] }, 200) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await publishContent({ kind: "knowledge", slug: "test-slug" });

    const [url] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toContain("custom.example.com");
    expect(String(url)).toContain("/api/publish");
  });

  it("8. uses default production URL when CLASSLAB_WEEKLY_NEWS_API_URL is not set", async () => {
    process.env.BATCH_SECRET = "test-secret";
    delete process.env.CLASSLAB_WEEKLY_NEWS_API_URL;

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ success: true, published_at: "2026-04-26T10:00:00.000Z", revalidated: [] }, 200) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await publishContent({ kind: "knowledge", slug: "test-slug" });

    const [url] = fetchSpy.mock.calls[0]!;
    expect(String(url)).toContain("classlab-weekly-news.vercel.app");
    expect(String(url)).toContain("/api/publish");
  });

  it("9. sends POST with correct body (kind and slug)", async () => {
    process.env.BATCH_SECRET = "test-secret";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ success: true, published_at: "2026-04-26T10:00:00.000Z", revalidated: [] }, 200) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await publishContent({ kind: "tech_article", slug: "my-article" });

    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    expect(init.method).toBe("POST");
    const body = JSON.parse(init.body as string);
    expect(body.kind).toBe("tech_article");
    expect(body.slug).toBe("my-article");
  });

  it("10. sends x-batch-secret header with BATCH_SECRET value", async () => {
    process.env.BATCH_SECRET = "super-secret-batch";

    fetchSpy.mockResolvedValueOnce(
      makeResponse({ success: true, published_at: "2026-04-26T10:00:00.000Z", revalidated: [] }, 200) as unknown as Response,
    );

    const { publishContent } = await import("../../src/posting/publish-client.js");
    await publishContent({ kind: "issue", slug: "weekly-issue-1" });

    const [_url, init] = fetchSpy.mock.calls[0]! as [unknown, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers["x-batch-secret"]).toBe("super-secret-batch");
  });
});
