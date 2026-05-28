/**
 * tests/stages/06-thumbnail.test.ts — Task #56 W3 (11.3d-C)
 *
 * Unit tests for runThumbnailHearingIfNeeded + uploadThumbnailIfNeeded.
 */
import { describe, it, expect, vi } from "vitest";
import {
  runThumbnailHearingIfNeeded,
  uploadThumbnailIfNeeded,
} from "../../scripts/stages/06-thumbnail.js";
import type { PostDeps } from "../../scripts/post.js";

function makeDeps(over: Partial<PostDeps> = {}): PostDeps {
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
    ...over,
  } as PostDeps;
}

describe("scripts/stages/06-thumbnail — Task #56 W3", () => {
  it("hearing skips when deps.runThumbnailHearing is omitted", async () => {
    const frontmatter: Record<string, unknown> = {};
    await runThumbnailHearingIfNeeded({
      contentType: "knowledge",
      title: "T",
      body: "B",
      frontmatter,
      opts: { thumbnailHearing: true, autoApprove: false, dryRun: false },
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(frontmatter.thumbnail).toBeUndefined();
  });

  it("hearing writes thumbnail path back to frontmatter when generated", async () => {
    const runThumbnailHearing = vi.fn(async () => ({
      generated: true,
      hearingSkipped: false,
      thumbnailPath: "/tmp/thumb.png",
      pattern: "T1",
    }));
    const thumbnailHearingDeps = {} as never;
    const frontmatter: Record<string, unknown> = {};
    await runThumbnailHearingIfNeeded({
      contentType: "knowledge",
      title: "T",
      body: "B",
      frontmatter,
      opts: { thumbnailHearing: true, autoApprove: false, dryRun: false },
      deps: makeDeps({
        runThumbnailHearing: runThumbnailHearing as never,
        thumbnailHearingDeps,
      }),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(frontmatter.thumbnail).toBe("/tmp/thumb.png");
  });

  // -------------------------------------------------------------------------
  // H5: #58 knowledgeKind 配線。stage06 → runThumbnailHearing へ kind を渡す。
  // -------------------------------------------------------------------------
  it("H5: knowledge + operation → runThumbnailHearing に knowledgeKind=operation を渡す", async () => {
    const runThumbnailHearing = vi.fn(async () => ({
      generated: true,
      hearingSkipped: false,
      thumbnailPath: "/tmp/op.png",
      pattern: "T403",
    }));
    const frontmatter: Record<string, unknown> = { tags: ["system"] };
    await runThumbnailHearingIfNeeded({
      contentType: "knowledge",
      title: "業務ナレッジ",
      body: "## 概要",
      frontmatter,
      knowledgeKind: "operation",
      opts: { thumbnailHearing: true, autoApprove: true, dryRun: false },
      deps: makeDeps({
        runThumbnailHearing: runThumbnailHearing as never,
        thumbnailHearingDeps: {} as never,
      }),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(runThumbnailHearing).toHaveBeenCalledTimes(1);
    const passedInput = (runThumbnailHearing.mock.calls[0] as unknown[])[0] as {
      contentType: string;
      knowledgeKind?: string;
      tags?: string[];
    };
    expect(passedInput.contentType).toBe("knowledge");
    expect(passedInput.knowledgeKind).toBe("operation");
    expect(passedInput.tags).toEqual(["system"]);
    expect(frontmatter.thumbnail).toBe("/tmp/op.png");
  });

  it("H5: knowledge 以外 (tech_articles) では knowledgeKind を渡さない (undefined)", async () => {
    const runThumbnailHearing = vi.fn(async () => ({
      generated: false,
      hearingSkipped: true,
      thumbnailPath: null,
      pattern: null,
    }));
    await runThumbnailHearingIfNeeded({
      contentType: "tech_articles",
      title: "T",
      body: "B",
      frontmatter: {},
      knowledgeKind: "operation", // 渡されても knowledge 以外なら無視される
      opts: { thumbnailHearing: true, autoApprove: true, dryRun: false },
      deps: makeDeps({
        runThumbnailHearing: runThumbnailHearing as never,
        thumbnailHearingDeps: {} as never,
      }),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    const passedInput = (runThumbnailHearing.mock.calls[0] as unknown[])[0] as {
      knowledgeKind?: string;
    };
    expect(passedInput.knowledgeKind).toBeUndefined();
  });

  it("upload passes external URL through unchanged", async () => {
    const url = await uploadThumbnailIfNeeded({
      filePath: "/tmp/x.md",
      slug: "s",
      contentType: "knowledge",
      frontmatter: { thumbnail: "https://example.com/t.png" },
      opts: { dryRun: false },
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(url).toBe("https://example.com/t.png");
  });

  it("upload returns null when no thumbnail configured", async () => {
    const url = await uploadThumbnailIfNeeded({
      filePath: "/tmp/x.md",
      slug: "s",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false },
      deps: makeDeps(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(url).toBeNull();
  });
});
