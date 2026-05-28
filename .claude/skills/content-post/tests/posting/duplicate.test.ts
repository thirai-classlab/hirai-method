/**
 * Tests for src/posting/duplicate.ts — Phase 8 Wave E1
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e1/plan.md §テスト観点 (duplicate.test.ts)
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createMockSupabase } from "../__helpers__/supabase-mock.js";

// Mock embedding + rag. We mock rag to avoid pulling in the real Supabase
// singleton inside rag.ts (which would require env vars). Our checkDuplicate
// receives the client via options, but rag.searchSimilar uses getSupabaseClient.
vi.mock("../../src/lib/embedding.js", () => ({
  generateEmbedding: vi.fn(),
}));
vi.mock("../../src/lib/rag.js", () => ({
  searchSimilar: vi.fn(),
}));

import { generateEmbedding } from "../../src/lib/embedding.js";
import { searchSimilar } from "../../src/lib/rag.js";
import { checkDuplicate } from "../../src/posting/duplicate.js";

const embedMock = generateEmbedding as unknown as ReturnType<typeof vi.fn>;
const searchMock = searchSimilar as unknown as ReturnType<typeof vi.fn>;

beforeEach(() => {
  embedMock.mockReset();
  searchMock.mockReset();
});

const DUMMY_EMBEDDING = Array.from({ length: 1024 }, () => 0.001);

describe("checkDuplicate — threshold classification", () => {
  it("returns level=block when similarity ≥ 0.90", async () => {
    embedMock.mockResolvedValue(DUMMY_EMBEDDING);
    searchMock.mockResolvedValue([
      {
        id: "a",
        content_type: "knowledge",
        content_id: "k1",
        similarity: 0.95,
      },
    ]);
    const client = createMockSupabase();
    const res = await checkDuplicate("body text", "knowledge", { client });
    expect(res.level).toBe("block");
    expect(res.matches.length).toBe(1);
    expect(res.reason).toMatch(/block|0\.95|similar/i);
  });

  it("returns level=warn for 0.80 ≤ similarity < 0.90", async () => {
    embedMock.mockResolvedValue(DUMMY_EMBEDDING);
    searchMock.mockResolvedValue([
      {
        id: "a",
        content_type: "knowledge",
        content_id: "k1",
        similarity: 0.85,
      },
    ]);
    const client = createMockSupabase();
    const res = await checkDuplicate("body text", "knowledge", { client });
    expect(res.level).toBe("warn");
    expect(res.reason).toMatch(/warn|0\.85|similar/i);
  });

  it("returns level=ok for similarity < 0.80", async () => {
    embedMock.mockResolvedValue(DUMMY_EMBEDDING);
    searchMock.mockResolvedValue([
      {
        id: "a",
        content_type: "knowledge",
        content_id: "k1",
        similarity: 0.7,
      },
    ]);
    const client = createMockSupabase();
    const res = await checkDuplicate("body text", "knowledge", { client });
    expect(res.level).toBe("ok");
  });
});

describe("checkDuplicate — empty match list", () => {
  it("returns level=ok with reason=null when no matches", async () => {
    embedMock.mockResolvedValue(DUMMY_EMBEDDING);
    searchMock.mockResolvedValue([]);
    const client = createMockSupabase();
    const res = await checkDuplicate("body text", "knowledge", { client });
    expect(res.level).toBe("ok");
    expect(res.matches).toEqual([]);
    expect(res.reason).toBeNull();
  });
});

describe("checkDuplicate — embedding failure propagates", () => {
  it("throws when generateEmbedding rejects", async () => {
    embedMock.mockRejectedValue(new Error("upstream failure"));
    const client = createMockSupabase();
    await expect(
      checkDuplicate("body text", "knowledge", { client }),
    ).rejects.toThrow(/upstream/);
  });
});

describe("checkDuplicate — max similarity chosen regardless of order", () => {
  it("picks the highest similarity from multiple matches", async () => {
    embedMock.mockResolvedValue(DUMMY_EMBEDDING);
    searchMock.mockResolvedValue([
      {
        id: "a",
        content_type: "knowledge",
        content_id: "k1",
        similarity: 0.5,
      },
      {
        id: "b",
        content_type: "knowledge",
        content_id: "k2",
        similarity: 0.92,
      },
      {
        id: "c",
        content_type: "knowledge",
        content_id: "k3",
        similarity: 0.81,
      },
    ]);
    const client = createMockSupabase();
    const res = await checkDuplicate("body text", "knowledge", { client });
    expect(res.level).toBe("block");
    // matches are returned sorted high → low so consumers can show top-N
    expect(res.matches[0]!.similarity).toBeGreaterThanOrEqual(0.92);
  });
});
