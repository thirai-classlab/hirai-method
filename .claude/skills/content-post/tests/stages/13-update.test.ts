/**
 * tests/stages/13-update.test.ts — Task #56 W3 (11.3d-C)
 *
 * Lightweight check: verify updateExisting writes summary + html + embedding,
 * and only calls version-manager hooks when snapshotNextVersion is provided.
 */
import { describe, it, expect, vi } from "vitest";

vi.mock("../../src/posting/summary.js", () => ({
  generateSummary: vi.fn(async () => "derived summary"),
}));

vi.mock("../../src/posting/version-manager.js", () => ({
  bumpVersion: vi.fn(async () => {}),
  saveSnapshotAfter: vi.fn(async () => {}),
}));

vi.mock("../../scripts/db/queries.js", () => ({
  updateMainContent: vi.fn(async () => {}),
  upsertEmbedding: vi.fn(async () => {}),
}));

import { updateExisting } from "../../scripts/stages/13-update.js";
import { updateMainContent, upsertEmbedding } from "../../scripts/db/queries.js";
import { saveSnapshotAfter, bumpVersion } from "../../src/posting/version-manager.js";
import type { PostDeps } from "../../scripts/post.js";

function makeDeps(): PostDeps {
  return {
    loadFile: vi.fn(),
    validate: vi.fn(),
    parseMarkdown: vi.fn(),
    renderToHtml: vi.fn(),
    renderToHtmlAsync: vi.fn(),
    generateSlug: vi.fn(),
    ensureUniqueSlug: vi.fn(),
    generateEmbedding: vi.fn(),
    checkDuplicate: vi.fn(),
    suggestCategory: vi.fn(),
    suggestTags: vi.fn(),
    resolveTagAgainstMasters: vi.fn(),
    confirmInteractively: vi.fn(),
    getSupabaseClient: vi.fn(),
    webSearch: { search: vi.fn() },
    reader: { question: vi.fn(), close: vi.fn() },
    streams: { out: [], err: [], write: vi.fn(), writeErr: vi.fn() },
    env: {},
  } as PostDeps;
}

describe("scripts/stages/13-update — Task #56 W3", () => {
  it("writes through updateMainContent + upsertEmbedding without version hooks when snapshotNextVersion is null", async () => {
    await updateExisting({
      client: {},
      tableName: "knowledge",
      contentId: "id1",
      title: "T",
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      embedding: [0.1],
      contentType: "knowledge",
      frontmatter: {},
      thumbnailCdnUrl: null,
      slug: "sl",
      snapshotNextVersion: null,
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(updateMainContent).toHaveBeenCalledOnce();
    expect(upsertEmbedding).toHaveBeenCalledOnce();
    expect(saveSnapshotAfter).not.toHaveBeenCalled();
    expect(bumpVersion).not.toHaveBeenCalled();
  });

  it("invokes saveSnapshotAfter + bumpVersion when snapshotNextVersion is provided", async () => {
    vi.clearAllMocks();
    await updateExisting({
      client: {},
      tableName: "knowledge",
      contentId: "id1",
      title: "T",
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      embedding: [0.1],
      contentType: "knowledge",
      frontmatter: {},
      thumbnailCdnUrl: null,
      slug: "sl",
      snapshotNextVersion: 3,
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(saveSnapshotAfter).toHaveBeenCalledOnce();
    expect(bumpVersion).toHaveBeenCalledOnce();
  });

  // -------------------------------------------------------------------------
  // M12: #58 round-2 — --update path does NOT write the knowledge.kind column.
  //
  // kind は新規作成時 (ingest payload) のみ確定し、--update では既存行の kind を
  // 保存する (上書きしない) のが意図的な設計。updateMainContent の row に kind /
  // knowledge_kind が含まれないことを pin し、将来 kind を update payload に
  // 混ぜ込む regression を検出可能にする。kind を更新したい場合は別タスクで
  // updateMainContent の拡張を設計する (本 round では scope 外)。
  // -------------------------------------------------------------------------
  it("M12: --update では updateMainContent row に kind を含めない (既存 kind を保存)", async () => {
    vi.clearAllMocks();
    await updateExisting({
      client: {},
      tableName: "knowledge",
      contentId: "id1",
      title: "T",
      parsedRaw: "B",
      renderedHtml: "<p>x</p>",
      embedding: [0.1],
      contentType: "knowledge",
      // frontmatter に kind を入れても update row には載らない (動作不変の保証)
      frontmatter: { kind: "operation" },
      thumbnailCdnUrl: null,
      slug: "sl",
      snapshotNextVersion: null,
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(updateMainContent).toHaveBeenCalledOnce();
    const updateMock = updateMainContent as unknown as {
      mock: { calls: unknown[][] };
    };
    const row = updateMock.mock.calls[0]![3] as Record<string, unknown>;
    expect(row).not.toHaveProperty("kind");
    expect(row).not.toHaveProperty("knowledge_kind");
  });
});
