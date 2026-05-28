/**
 * tests/stages/14-publish.test.ts — Task #56 W3 (11.3d-C)
 */
import { describe, it, expect, vi } from "vitest";
import { publishIfRequested } from "../../scripts/stages/14-publish.js";
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

describe("scripts/stages/14-publish — Task #56 W3", () => {
  it("skips when publishContent dep is omitted", async () => {
    const log = vi.fn();
    await publishIfRequested({
      contentType: "knowledge",
      slug: "s",
      deps: makeDeps(),
      log,
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(log).not.toHaveBeenCalled();
  });

  it("logs published timestamp when not already published", async () => {
    const publishContent = vi.fn(async () => ({
      success: true,
      published_at: "2026-05-23T10:00:00Z",
      revalidated: [],
      already_published: false,
    }));
    const log = vi.fn();
    await publishIfRequested({
      contentType: "knowledge",
      slug: "s1",
      deps: makeDeps({ publishContent: publishContent as never }),
      log,
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(publishContent).toHaveBeenCalledWith({ kind: "knowledge", slug: "s1" });
    expect(log).toHaveBeenCalledWith("[post] published: s1 at 2026-05-23T10:00:00Z");
  });

  it("maps tech_articles → tech_article kind", async () => {
    const publishContent = vi.fn(async () => ({
      success: true,
      published_at: "x",
      revalidated: [],
      already_published: true,
    }));
    await publishIfRequested({
      contentType: "tech_articles",
      slug: "s2",
      deps: makeDeps({ publishContent: publishContent as never }),
      log: vi.fn(),
      logErr: vi.fn(),
      verbose: vi.fn(),
    });
    expect(publishContent).toHaveBeenCalledWith({ kind: "tech_article", slug: "s2" });
  });

  it("logErr on failure but does not throw", async () => {
    const publishContent = vi.fn(async () => {
      throw new Error("network");
    });
    const logErr = vi.fn();
    await publishIfRequested({
      contentType: "knowledge",
      slug: "s3",
      deps: makeDeps({ publishContent: publishContent as never }),
      log: vi.fn(),
      logErr,
      verbose: vi.fn(),
    });
    expect(logErr).toHaveBeenCalledOnce();
  });
});
