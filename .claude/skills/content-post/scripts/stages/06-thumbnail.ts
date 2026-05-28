/**
 * scripts/stages/06-thumbnail.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 06: thumbnail hearing (#32) + thumbnail upload (#30).
 *
 * Pure functions:
 *   - runThumbnailHearingIfNeeded(args): conditionally invoke #32 hearing layer
 *     and write generated path back to frontmatter.thumbnail. No side effects
 *     unless deps.runThumbnailHearing + thumbnailHearingDeps are wired and
 *     opts.thumbnailHearing is true.
 *   - uploadThumbnailIfNeeded(args): translate frontmatter.thumbnail (path or
 *     external URL) into a CDN URL via deps.uploadThumbnail. External URLs
 *     pass through untouched.
 *
 * Stage descriptor:
 *   - stage06Thumbnail.run(ctx): runs the two helpers and stores the CDN URL
 *     on ctx.thumbnailCdnUrl. Mirrors post.ts runOne 5a+ / 5b+ behaviour 1:1.
 *
 * Design intent (動作保存):
 *   - #32 内部実装は触らない (runThumbnailHearing は deps 経由で呼び出すのみ).
 *   - Errors are logged and execution continues; ctx.thumbnailCdnUrl stays null.
 *   - 元 post.ts runOne 5a+/5b+ セクション (494-581 行) と動作完全一致。
 */
import path from "node:path";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps, ParsedOptions, KnowledgeKind } from "../post.js";
import { mapContentTypeToImagePrefix } from "../helpers/type-mapping.js";

export interface HearingArgs {
  contentType: string;
  title: string;
  body: string;
  frontmatter: Record<string, unknown>;
  /**
   * #58 Step 4: knowledge.kind。operation/domain_knowledge で kind 別パターン選択。
   * #58 round-2 (M7): `string` → KnowledgeKind に型安全化 (post-types.ts 単一真実源)。
   */
  knowledgeKind?: KnowledgeKind;
  opts: Pick<ParsedOptions, "thumbnailHearing" | "autoApprove" | "dryRun">;
  deps: PostDeps;
  logErr: (s: string) => void;
  verbose: (s: string) => void;
}

/** #32 thumbnail-hearing dispatcher. Mutates frontmatter.thumbnail on success. */
export async function runThumbnailHearingIfNeeded(args: HearingArgs): Promise<void> {
  const { contentType, title, body, frontmatter, knowledgeKind, opts, deps, logErr, verbose } = args;
  if (!deps.runThumbnailHearing || !deps.thumbnailHearingDeps || !opts.thumbnailHearing) {
    return;
  }
  try {
    const validContentType =
      contentType === "weekly_issues" ||
      contentType === "tech_articles" ||
      contentType === "knowledge"
        ? contentType
        : "knowledge";
    const hearingResult = await deps.runThumbnailHearing(
      {
        contentType: validContentType,
        title,
        body,
        tags: Array.isArray(frontmatter.tags)
          ? (frontmatter.tags as string[])
          : undefined,
        // #58 Step 4: knowledge のみ kind を渡す (concept/operation/domain_knowledge)。
        knowledgeKind:
          validContentType === "knowledge" ? knowledgeKind : undefined,
        frontmatterThumbnail: frontmatter.thumbnail
          ? String(frontmatter.thumbnail)
          : undefined,
        autoApprove: opts.autoApprove,
        dryRun: opts.dryRun,
      },
      deps.thumbnailHearingDeps,
    );
    if (
      hearingResult.generated &&
      hearingResult.thumbnailPath &&
      !frontmatter.thumbnail
    ) {
      frontmatter.thumbnail = hearingResult.thumbnailPath;
      verbose(
        `[post] thumbnail hearing: pattern=${hearingResult.pattern} → ${hearingResult.thumbnailPath}`,
      );
    } else if (hearingResult.hearingSkipped && !hearingResult.generated) {
      verbose(`[post] thumbnail hearing: skipped`);
    }
  } catch (err) {
    logErr(
      `[post] thumbnail hearing failed (continuing without thumbnail): ${(err as Error).message}`,
    );
  }
}

export interface UploadArgs {
  filePath: string;
  slug: string;
  contentType: string;
  frontmatter: Record<string, unknown>;
  opts: Pick<ParsedOptions, "dryRun">;
  deps: PostDeps;
  logErr: (s: string) => void;
  verbose: (s: string) => void;
}

/**
 * Upload local thumbnail file → CDN URL via deps.uploadThumbnail. External
 * URLs pass through as-is. Returns null when nothing is configured or on error.
 */
export async function uploadThumbnailIfNeeded(
  args: UploadArgs,
): Promise<string | null> {
  const { filePath, slug, contentType, frontmatter, opts, deps, logErr, verbose } = args;
  if (deps.uploadThumbnail && !opts.dryRun && frontmatter.thumbnail) {
    const thumbRaw = String(frontmatter.thumbnail);
    if (/^https?:\/\//.test(thumbRaw)) {
      return thumbRaw;
    }
    const baseDir = filePath ? path.dirname(filePath) : process.cwd();
    const thumbAbsPath = path.resolve(baseDir, thumbRaw);
    try {
      const imageType = mapContentTypeToImagePrefix(contentType);
      const uploaded = await deps.uploadThumbnail(thumbAbsPath, {
        slug,
        contentType: imageType,
      });
      verbose(`[post] thumbnail upload: ${thumbRaw} → ${uploaded.cloudfrontUrl}`);
      return uploaded.cloudfrontUrl;
    } catch (err) {
      logErr(`[post] thumbnail upload failed (continuing): ${(err as Error).message}`);
      return null;
    }
  }
  // uploadThumbnail dep not wired, but frontmatter.thumbnail is external URL —
  // pass through verbatim (matches inline post.ts behaviour).
  if (
    frontmatter.thumbnail &&
    /^https?:\/\//.test(String(frontmatter.thumbnail))
  ) {
    return String(frontmatter.thumbnail);
  }
  return null;
}

export const stage06Thumbnail = {
  name: "thumbnail" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (!ctx.frontmatter || !ctx.contentType || !ctx.slug) {
      throw new Error("stage06: frontmatter / contentType / slug must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const title = String(ctx.frontmatter.title ?? "");
    const body = (ctx.parsed?.raw as string | undefined) ?? ctx.source ?? "";
    await runThumbnailHearingIfNeeded({
      contentType: ctx.contentType,
      title,
      body,
      frontmatter: ctx.frontmatter,
      // #58 Step 4: knowledge.kind は ParsedOptions に常在 (default "concept")。
      knowledgeKind: ctx.opts.knowledgeKind,
      opts: {
        thumbnailHearing: ctx.opts.thumbnailHearing,
        autoApprove: ctx.opts.autoApprove,
        dryRun: ctx.opts.dryRun,
      },
      deps: ctx.deps,
      logErr,
      verbose,
    });
    const cdnUrl = await uploadThumbnailIfNeeded({
      filePath: ctx.filePath,
      slug: ctx.slug,
      contentType: ctx.contentType,
      frontmatter: ctx.frontmatter,
      opts: { dryRun: ctx.opts.dryRun },
      deps: ctx.deps,
      logErr,
      verbose,
    });
    ctx.thumbnailCdnUrl = cdnUrl;
  },
};
