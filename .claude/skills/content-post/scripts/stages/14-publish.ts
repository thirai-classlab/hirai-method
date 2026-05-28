/**
 * scripts/stages/14-publish.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 14: publish content via POST /api/publish (#33).
 *
 * Pure function:
 *   - publishIfRequested(args): conditionally invokes deps.publishContent
 *     when --publish was set and we have a contentId.
 *
 * Stage descriptor:
 *   - stage14Publish.run(ctx): runs only when --publish && contentId && !dryRun.
 *
 * Design intent (動作保存):
 *   - 元 post.ts runOne 816-834 行と動作完全一致.
 *   - publishKind マッピング: tech_articles→tech_article / weekly_issues→issue / default knowledge.
 *   - Publish 失敗は non-fatal (logErr のみ).
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export interface PublishArgs {
  contentType: string;
  slug: string;
  deps: PostDeps;
  log: (s: string) => void;
  logErr: (s: string) => void;
  verbose: (s: string) => void;
}

export async function publishIfRequested(args: PublishArgs): Promise<void> {
  const { contentType, slug, deps, log, logErr, verbose } = args;
  if (!deps.publishContent) return;
  const publishKind = ((): "tech_article" | "issue" | "knowledge" => {
    if (contentType === "tech_articles") return "tech_article";
    if (contentType === "weekly_issues") return "issue";
    return "knowledge";
  })();
  try {
    const publishResult = await deps.publishContent({ kind: publishKind, slug });
    if (publishResult.already_published) {
      verbose(`[post] publish: already published (slug=${slug})`);
    } else {
      log(`[post] published: ${slug} at ${publishResult.published_at}`);
    }
  } catch (err) {
    logErr(`[post] publish failed (continuing): ${(err as Error).message}`);
  }
}

export const stage14Publish = {
  name: "publish" as const,
  async run(ctx: PipelineContext): Promise<void> {
    const log = (s: string) => ctx.streams.write(s);
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };

    // Publish only when --publish && contentId && !dryRun (動作保存: 元 publish ゲート).
    const shouldPublish = !ctx.opts.dryRun && ctx.opts.publish && !!ctx.contentId;
    if (shouldPublish) {
      if (!ctx.contentType || !ctx.slug) {
        throw new Error("stage14: contentType / slug must be set");
      }
      await publishIfRequested({
        contentType: ctx.contentType,
        slug: ctx.slug,
        deps: ctx.deps,
        log,
        logErr,
        verbose,
      });
    }

    // Final pipeline summary log — emitted on ALL paths (publish / --update / skip / dry-run)
    // so that "[post] ok:" always confirms pipeline completion (task-54 fix 1).
    // 元 post.ts runOne L837-839 は publish ゲート内に閉じていたため --update 経路で欠落していた。
    if (ctx.slug) {
      log(`[post] ok: ${ctx.opts.dryRun ? "(dry-run) " : ""}${ctx.tableName ?? "?"}.${ctx.slug}`);
    }
  },
};
