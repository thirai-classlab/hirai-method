/**
 * scripts/stages/05-image-upload.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 05: upload local markdown images to S3 + CloudFront, rewrite markdown
 * with CDN URLs, and (in --update mode) invalidate stale CloudFront paths.
 *
 * Pure function:
 *   - processImagesIfNeeded(args): runs deps.processMarkdownImages when wired
 *     and not --dry-run. Returns the rewritten source + parsed result + any
 *     stale-CDN invalidation paths so the stage descriptor can mutate ctx.
 *
 * Stage descriptor:
 *   - stage05ImageUpload.run(ctx): mutates ctx.source / ctx.parsed and emits
 *     CloudFront invalidation when applicable. Failures are logged and skipped
 *     (best-effort; never throws — matches inline post.ts behaviour).
 *
 * Design intent (動作保存):
 *   - dep未注入 / dryRun は全 skip。失敗時は logErr で継続。
 *   - --update + existing.body + invalidateCloudFront 揃った時のみ invalidation
 *     を実行 (旧 CDN パスを抽出して purge)。
 *   - 元 post.ts runOne の 5b セクション (438-492 行) と動作完全一致。
 */
import path from "node:path";
import {
  extractCdnPathsForInvalidation,
  type ProcessImagesOptions,
} from "../../src/lib/image-processor.js";
import { mapContentTypeToImagePrefix } from "../helpers/type-mapping.js";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export interface ImageUploadArgs {
  source: string;
  filePath: string;
  slug: string;
  contentType: string;
  opts: { dryRun: boolean; update: boolean };
  existing: Record<string, unknown> | null;
  env: Record<string, string | undefined>;
  deps: PostDeps;
  logErr: (s: string) => void;
  verbose: (s: string) => void;
}

export interface ImageUploadOutcome {
  /** Rewritten source markdown (CDN URLs substituted). Same string if no upload happened. */
  source: string;
  /** Re-parsed markdown when upload happened, else null (caller retains existing parsed). */
  reparsed: unknown | null;
}

export async function processImagesIfNeeded(
  args: ImageUploadArgs,
): Promise<ImageUploadOutcome> {
  const { source, filePath, slug, contentType, opts, existing, env, deps, logErr, verbose } = args;
  if (!deps.processMarkdownImages || opts.dryRun) {
    return { source, reparsed: null };
  }
  const imageType = mapContentTypeToImagePrefix(contentType);
  const baseDir = filePath ? path.dirname(filePath) : process.cwd();
  try {
    const procOpts: ProcessImagesOptions = {
      slug,
      contentType: imageType,
      baseDir,
    };
    const { markdown: rewritten, replacements } =
      await deps.processMarkdownImages(source, procOpts);
    if (replacements.length === 0) {
      return { source, reparsed: null };
    }
    verbose(`[post] image upload: ${replacements.length} file(s) → CloudFront`);
    const reparsed = deps.parseMarkdown(rewritten);
    // --update: invalidate stale CDN paths from the existing body.
    if (
      opts.update &&
      existing &&
      deps.invalidateCloudFront &&
      typeof existing.body === "string"
    ) {
      const cdnDomain = env.CLOUDFRONT_DOMAIN ?? "d2f75plg0t6qwk.cloudfront.net";
      const stalePaths = extractCdnPathsForInvalidation(
        existing.body as string,
        cdnDomain,
      );
      if (stalePaths.length > 0) {
        try {
          const res = await deps.invalidateCloudFront(stalePaths);
          verbose(
            `[post] cloudfront invalidation: ${stalePaths.length} path(s), id=${res.id}`,
          );
        } catch (err) {
          logErr(
            `[post] cloudfront invalidation failed (continuing): ${(err as Error).message}`,
          );
        }
      }
    }
    return { source: rewritten, reparsed };
  } catch (err) {
    logErr(`[post] image upload failed (continuing): ${(err as Error).message}`);
    return { source, reparsed: null };
  }
}

export const stage05ImageUpload = {
  name: "image-upload" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (typeof ctx.source !== "string" || !ctx.slug || !ctx.contentType) {
      throw new Error("stage05: ctx.source / slug / contentType must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const result = await processImagesIfNeeded({
      source: ctx.source,
      filePath: ctx.filePath,
      slug: ctx.slug,
      contentType: ctx.contentType,
      opts: { dryRun: ctx.opts.dryRun, update: ctx.opts.update },
      existing: ctx.existing ?? null,
      env: ctx.env,
      deps: ctx.deps,
      logErr,
      verbose,
    });
    ctx.source = result.source;
    if (result.reparsed !== null) {
      ctx.parsed = result.reparsed as PipelineContext["parsed"];
    }
  },
};
