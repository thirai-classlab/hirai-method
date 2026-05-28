/**
 * scripts/defaultDeps.ts — Task #56 W3 (11.3d-C)
 *
 * Default DI wiring for the CLI entry point. Extracted from post.ts so the
 * orchestrator file can fit inside the W3 size budget (post.ts ≤ 150 行).
 *
 * Tests still inject their own PostDeps; this module is consumed only by
 * the CLI entry block in post.ts.
 */
import "dotenv/config";
import path from "node:path";
import fs from "node:fs/promises";

import { validateInput } from "../src/posting/validate.js";
import {
  parseMarkdown,
  renderToHtml,
  renderToHtmlAsync as renderToHtmlAsyncImpl,
} from "../src/lib/markdown.js";
import { loadTemplates } from "../src/lib/templates.js";
import {
  generateSlug as generateSlugImpl,
  ensureUniqueSlug as ensureUniqueSlugImpl,
  assertSlugAvailable as assertSlugAvailableImpl,
} from "../src/posting/slug.js";
import { generateEmbedding as generateEmbeddingImpl } from "../src/lib/embedding.js";
import {
  suggestCategory as suggestCategoryImpl,
  suggestTags as suggestTagsImpl,
  resolveTagAgainstMasters as resolveTagAgainstMastersImpl,
  confirmInteractively as confirmInteractivelyImpl,
  createDefaultReader,
} from "../src/posting/category-tag.js";
import { getSupabaseClient as getSupabaseClientImpl } from "../src/lib/supabase.js";
import { ingestViaApi as ingestViaApiImpl } from "../src/posting/api-client.js";
import { publishContent as publishContentImpl } from "../src/posting/publish-client.js";
import {
  runThumbnailHearing as runThumbnailHearingImpl,
  defaultReadPatternsConfig,
  makeDefaultSpawnGenerator,
  makeDefaultPromptUser,
  makeDefaultPatternSelector,
} from "../src/posting/thumbnail-hearing.js";
import { processMarkdownImages as processMarkdownImagesImpl } from "../src/lib/image-processor.js";
import { invalidateCloudFront as invalidateCloudFrontImpl } from "../src/lib/cloudfront.js";
import { enrichLinkCards as enrichLinkCardsImpl } from "../src/posting/link-card-extractor.js";
import type { PostDeps, Streams } from "./post.js";

const posting2Posting = (
  t: string,
): "knowledge" | "tech_articles" | "weekly_issues" =>
  t === "tech_articles"
    ? "tech_articles"
    : t === "weekly_issues"
      ? "weekly_issues"
      : "knowledge";

/**
 * Construct the default PostDeps bag used by the CLI. `reader` is a no-op
 * stub here; the caller is expected to overwrite it via createDefaultReader()
 * after import (see post.ts CLI block).
 */
export function buildDefaultDeps(streams: Streams): PostDeps {
  return {
    loadFile: (p) => fs.readFile(p, "utf-8"),
    loadTemplates,
    validate: validateInput,
    parseMarkdown,
    renderToHtml: renderToHtml as unknown as PostDeps["renderToHtml"],
    renderToHtmlAsync:
      renderToHtmlAsyncImpl as unknown as PostDeps["renderToHtmlAsync"],
    generateSlug: ((title: string, type: string, _client: unknown) =>
      generateSlugImpl(
        title,
        posting2Posting(type),
      )) as unknown as PostDeps["generateSlug"],
    ensureUniqueSlug: ((base: string, type: string, client: unknown) =>
      ensureUniqueSlugImpl(
        base,
        posting2Posting(type),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        client as any,
      )) as unknown as PostDeps["ensureUniqueSlug"],
    assertSlugAvailable: ((slug: string, type: string, client: unknown) =>
      assertSlugAvailableImpl(
        slug,
        posting2Posting(type),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        client as any,
      )) as unknown as NonNullable<PostDeps["assertSlugAvailable"]>,
    generateEmbedding: generateEmbeddingImpl,
    checkDuplicate: (async (o: {
      client: unknown;
      embedding: number[];
      contentType: string;
      selfId?: string;
    }) => {
      const { searchSimilar } = await import("../src/lib/rag.js");
      const rawMatches = await searchSimilar(o.embedding, { limit: 5 });
      const filtered = o.selfId
        ? rawMatches.filter((m) => m.content_id !== o.selfId)
        : rawMatches;
      const matches = [...filtered].sort((a, b) => b.similarity - a.similarity);
      if (matches.length === 0)
        return { level: "ok" as const, matches: [], reason: null };
      const top = matches[0]!;
      const sim = top.similarity;
      const level = sim >= 0.9 ? "block" : sim >= 0.8 ? "warn" : "ok";
      const reason =
        level === "ok"
          ? null
          : `top similarity ${sim.toFixed(3)} (${level} threshold)`;
      return { level, matches, reason };
    }) as unknown as PostDeps["checkDuplicate"],
    suggestCategory:
      suggestCategoryImpl as unknown as PostDeps["suggestCategory"],
    suggestTags: suggestTagsImpl as unknown as PostDeps["suggestTags"],
    resolveTagAgainstMasters:
      resolveTagAgainstMastersImpl as unknown as PostDeps["resolveTagAgainstMasters"],
    confirmInteractively:
      confirmInteractivelyImpl as unknown as PostDeps["confirmInteractively"],
    ingestViaApi: ingestViaApiImpl,
    publishContent: publishContentImpl,
    getSupabaseClient: () => getSupabaseClientImpl(),
    processMarkdownImages: processMarkdownImagesImpl,
    invalidateCloudFront: invalidateCloudFrontImpl,
    searchSimilar: async (
      embedding: number[],
      opts: { limit?: number; threshold?: number },
    ) => {
      const { searchSimilar: searchSimilarImpl } = await import(
        "../src/lib/rag.js"
      );
      return searchSimilarImpl(embedding, opts);
    },
    runThumbnailHearing: runThumbnailHearingImpl,
    thumbnailHearingDeps: {
      readPatternsConfig: defaultReadPatternsConfig,
      promptUser: makeDefaultPromptUser(),
      spawnGenerator: makeDefaultSpawnGenerator(),
      selectPattern: makeDefaultPatternSelector(),
      logger: (m: string) => streams.write(m),
    },
    uploadThumbnail: async (
      absPath: string,
      opts: {
        slug: string;
        contentType: "knowledge" | "tech_article" | "issue";
      },
    ) => {
      const { uploadToS3, cloudFrontUrl } = await import("../src/lib/s3.js");
      const crypto = await import("node:crypto");
      const fileBuffer = await fs.readFile(absPath);
      const hash = crypto
        .createHash("sha256")
        .update(fileBuffer)
        .digest("hex")
        .slice(0, 8);
      const filename = path.basename(absPath);
      const ext = path.extname(filename).toLowerCase();
      const CONTENT_TYPES: Record<string, string> = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".gif": "image/gif",
        ".svg": "image/svg+xml",
        ".webp": "image/webp",
      };
      const ct = CONTENT_TYPES[ext] ?? "application/octet-stream";
      const s3Key = `${opts.contentType}/${opts.slug}/thumbnail-${hash}-${filename}`;
      await uploadToS3(s3Key, fileBuffer, ct);
      return { cloudfrontUrl: cloudFrontUrl(s3Key) };
    },
    enrichLinkCards: enrichLinkCardsImpl,
    webSearch: {
      async search() {
        return [];
      },
    },
    reader: { question: async () => "", close: () => {} },
    streams,
    env: process.env,
  };
}

export { createDefaultReader };
