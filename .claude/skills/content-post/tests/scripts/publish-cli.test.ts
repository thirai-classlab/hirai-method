/**
 * Tests for scripts/publish.ts — Task #33 W4
 *
 * テスト観点:
 *   1. --slug + --type: publishContent を 1 回呼んで exit 0
 *   2. --slug + --type: publishContent がエラー → exit 1
 *   3. --slug のみ（--type なし）→ exit 1
 *   4. --pending のみ（--type なし）→ exit 1
 *   5. 引数なし → exit 1
 *   6. --pending --type knowledge --dry-run --confirm: publishContent を呼ばず exit 0
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// publish-client をモック（fetch を呼ばない）
vi.mock("../../src/posting/publish-client.js", () => ({
  publishContent: vi.fn(),
}));

// @supabase/supabase-js をモック（--pending モード用）
vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        is: vi.fn(() => ({
          order: vi.fn(async () => ({ data: [], error: null })),
        })),
      })),
    })),
  })),
}));

describe("scripts/publish.ts — CLI", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    process.env.BATCH_SECRET = "test-secret";
    process.env.SUPABASE_URL = "https://example.supabase.co";
    process.env.SUPABASE_SERVICE_ROLE_KEY = "service-key";
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("1. --slug + --type publishes and exits 0", async () => {
    const { publishContent } = await import("../../src/posting/publish-client.js");
    vi.mocked(publishContent).mockResolvedValueOnce({
      success: true,
      published_at: "2026-04-26T10:00:00.000Z",
      revalidated: [],
    });

    const { run } = await import("../../scripts/publish.js");
    const code = await run(["node", "publish.ts", "--slug", "test-slug", "--type", "knowledge"]);

    expect(code).toBe(0);
    expect(publishContent).toHaveBeenCalledWith({ kind: "knowledge", slug: "test-slug" });
  });

  it("2. publishContent error → exits 1", async () => {
    const { publishContent } = await import("../../src/posting/publish-client.js");
    vi.mocked(publishContent).mockRejectedValueOnce(new Error("unauthorized"));

    const { run } = await import("../../scripts/publish.js");
    const code = await run(["node", "publish.ts", "--slug", "bad-slug", "--type", "knowledge"]);

    expect(code).toBe(1);
  });

  it("3. --slug without --type → exits 1", async () => {
    const { run } = await import("../../scripts/publish.js");
    const code = await run(["node", "publish.ts", "--slug", "test-slug"]);
    expect(code).toBe(1);
  });

  it("4. --pending without --type → exits 1", async () => {
    const { run } = await import("../../scripts/publish.js");
    const code = await run(["node", "publish.ts", "--pending"]);
    expect(code).toBe(1);
  });

  it("5. no args → exits 1", async () => {
    const { run } = await import("../../scripts/publish.js");
    const code = await run(["node", "publish.ts"]);
    expect(code).toBe(1);
  });

  it("6. --pending --type knowledge --confirm --dry-run: publishContent not called, exits 0", async () => {
    // Override supabase mock to return one draft
    vi.doMock("@supabase/supabase-js", () => ({
      createClient: vi.fn(() => ({
        from: vi.fn(() => ({
          select: vi.fn(() => ({
            is: vi.fn(() => ({
              order: vi.fn(async () => ({
                data: [{ slug: "draft-item" }],
                error: null,
              })),
            })),
          })),
        })),
      })),
    }));

    const { publishContent } = await import("../../src/posting/publish-client.js");
    vi.mocked(publishContent).mockClear();

    const { run } = await import("../../scripts/publish.js");
    const code = await run([
      "node", "publish.ts",
      "--pending",
      "--type", "knowledge",
      "--confirm",
      "--dry-run",
    ]);

    expect(code).toBe(0);
    expect(publishContent).not.toHaveBeenCalled();
  });
});
