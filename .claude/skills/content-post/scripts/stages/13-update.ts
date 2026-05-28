/**
 * scripts/stages/13-update.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 13: UPDATE path (Supabase direct UPDATE + version-manager hooks).
 *
 * Pure function:
 *   - updateExisting(args): updates content row + upserts embedding + invokes
 *     #41 version-manager post-update hooks (saveSnapshotAfter + bumpVersion).
 *
 * Stage descriptor:
 *   - stage13Update.run(ctx): runs only when !dryRun && update && existing.
 *     Populates ctx.contentId from existing.id.
 *
 * Design intent (動作保存):
 *   - 元 post.ts runOne 761-809 行と動作完全一致.
 *   - #41 version-manager (snapshotBeforeUpdate / saveSnapshotAfter / bumpVersion)
 *     は内部実装 untouch、deps 経由でなく直 import で呼び出し (元 post.ts と同じ).
 *   - summary は generateSummary で再導出 (古い HTML/img を引き継がない).
 *   - version-manager post-update hooks 失敗は non-fatal (logErr のみ).
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";
import { generateSummary as generateSummaryImpl } from "../../src/posting/summary.js";
import {
  bumpVersion as bumpVersionImpl,
  saveSnapshotAfter as saveSnapshotAfterImpl,
} from "../../src/posting/version-manager.js";
import { updateMainContent, upsertEmbedding } from "../db/queries.js";

export interface UpdateArgs {
  client: unknown;
  tableName: string;
  contentId: string;
  title: string;
  parsedRaw: string;
  renderedHtml: string;
  embedding: number[];
  contentType: string;
  frontmatter: Record<string, unknown>;
  thumbnailCdnUrl: string | null;
  slug: string;
  snapshotNextVersion: number | null;
  deps: PostDeps;
  logErr: (s: string) => void;
  verbose: (s: string) => void;
}

export async function updateExisting(args: UpdateArgs): Promise<void> {
  const {
    client,
    tableName,
    contentId,
    title,
    parsedRaw,
    renderedHtml,
    embedding,
    contentType,
    frontmatter,
    thumbnailCdnUrl,
    slug,
    snapshotNextVersion,
    deps,
    logErr,
    verbose,
  } = args;
  const updatedSummary = await generateSummaryImpl({
    title,
    rawMarkdown: parsedRaw,
    explicit:
      typeof frontmatter.summary === "string"
        ? (frontmatter.summary as string)
        : undefined,
  });
  verbose(
    `[post] summary (update): ${updatedSummary.slice(0, 80)}${updatedSummary.length > 80 ? "..." : ""}`,
  );
  await updateMainContent(client, tableName, contentId, {
    title,
    body: parsedRaw,
    html: renderedHtml,
    summary: updatedSummary,
    periodStart: (frontmatter.period_start as string | undefined) ?? undefined,
    periodEnd: (frontmatter.period_end as string | undefined) ?? undefined,
    thumbnailUrl: thumbnailCdnUrl,
    thumbnailAlt: (frontmatter.thumbnail_alt as string | undefined) ?? null,
  });
  await upsertEmbedding(client, {
    contentType,
    contentId,
    embedding,
  });
  verbose(`[post] updated ${tableName}.${contentId}`);

  if (snapshotNextVersion !== null) {
    try {
      await saveSnapshotAfterImpl(slug, snapshotNextVersion, renderedHtml, {
        contentsDir: deps.contentsManageDir,
      });
      // task-54 fix 2: pass raw markdown so bumpVersion can content-hash dedupe.
      // 同一内容で --update を再実行しても version が増殖しない (冪等)。
      const bumped = await bumpVersionImpl(slug, {
        author: "post.ts --update",
        note: `auto-created by post.ts --update (title: ${title})`,
        contentsDir: deps.contentsManageDir,
        refreshIndex: true,
        content: parsedRaw,
      });
      if (bumped) {
        verbose(`[post] version bumped to v${snapshotNextVersion} + snapshot.html saved`);
      } else {
        verbose(`[post] content unchanged — version bump skipped (idempotent)`);
      }
    } catch (vErr) {
      logErr(
        `[post] version-manager post-update hook failed (non-fatal): ${(vErr as Error).message}`,
      );
    }
  }
}

export const stage13Update = {
  name: "update" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (ctx.opts.dryRun || !ctx.opts.update) return;
    if (!ctx.existing) return; // existing fetch happens in stage 04
    if (!ctx.frontmatter || !ctx.contentType || !ctx.slug || !ctx.rendered || !ctx.embedding) {
      throw new Error("stage13: frontmatter / contentType / slug / rendered / embedding must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const client = ctx.deps.getSupabaseClient();
    const tableName = ctx.tableName ?? "knowledge";
    const contentId = String(ctx.existing.id);
    const title = String(ctx.frontmatter.title ?? "");
    const parsedRaw = (ctx.parsed?.raw as string | undefined) ?? "";
    await updateExisting({
      client,
      tableName,
      contentId,
      title,
      parsedRaw,
      renderedHtml: ctx.rendered.html,
      embedding: ctx.embedding,
      contentType: ctx.contentType,
      frontmatter: ctx.frontmatter,
      thumbnailCdnUrl: ctx.thumbnailCdnUrl ?? null,
      slug: ctx.slug,
      snapshotNextVersion: ctx.snapshotNextVersion ?? null,
      deps: ctx.deps,
      logErr,
      verbose,
    });
    ctx.contentId = contentId;
  },
};
