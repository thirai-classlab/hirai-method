/**
 * scripts/stages/04-slug-resolve.ts — Task #56 W2 (11.3d-B)
 *
 * Stage 04: resolve target slug + update-mode existing fetch + snapshot.
 *
 * Pure functions:
 *   - resolveSlug(args): resolve slug for new / update modes.
 *     - new: explicit frontmatter.slug or generated from title, then
 *       fail-loud via assertSlugAvailable (preferred) or back-compat
 *       ensureUniqueSlug fallback.
 *     - update: returns existing.slug verbatim (no collision check).
 *   - kindForSnapshot(contentType): translate to ContentKind enum.
 *
 * Stage descriptor:
 *   - stage04SlugResolve.run(ctx): runs fetchBySlug for --update, applies
 *     snapshotBeforeUpdate (writes ctx.snapshotNextVersion), and resolves
 *     ctx.slug. Throws SlugConflictError up to main() unchanged.
 *
 * Design intent (動作保存):
 *   - Update path: fetchBySlug → error when not found (exit 1) → snapshot
 *     (only when !dryRun) → use existing.slug.
 *   - New path: assertSlugAvailable preferred (fail-loud), back-compat
 *     fallback to ensureUniqueSlug when assertSlugAvailable not injected.
 *   - SlugConflictError is intentionally re-thrown — main() converts it.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W2.
 */
import {
  snapshotBeforeUpdate as snapshotBeforeUpdateImpl,
  type ContentKind,
} from "../../src/posting/version-manager.js";
import { fetchBySlug } from "../db/queries.js";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps, ParsedOptions } from "../post.js";

/** Translate the internal contentType to the ContentKind used by version-manager. */
export function kindForSnapshot(contentType: string): ContentKind {
  switch (contentType) {
    case "tech_articles":
      return "tech_article";
    case "weekly_issues":
      return "weekly_issue";
    default:
      return "knowledge";
  }
}

export interface ResolveSlugArgs {
  title: string;
  contentType: string;
  frontmatter: Record<string, unknown>;
  opts: ParsedOptions;
  existing: Record<string, unknown> | null;
  client: unknown;
  deps: PostDeps;
}

/**
 * Resolve the target slug. For --update we accept the existing slug as-is.
 * For new posts we prefer assertSlugAvailable (fail-loud) and fall back to
 * ensureUniqueSlug for older injected dep maps used in some tests.
 */
export async function resolveSlug(args: ResolveSlugArgs): Promise<string> {
  const { title, contentType, frontmatter, opts, existing, client, deps } = args;
  if (opts.update && existing) {
    return String(existing.slug);
  }
  if (frontmatter.slug) {
    const slug = String(frontmatter.slug);
    if (deps.assertSlugAvailable) {
      await deps.assertSlugAvailable(slug, contentType, client);
      return slug;
    }
    return await deps.ensureUniqueSlug(slug, contentType, client);
  }
  const base = await deps.generateSlug(title, contentType, client);
  if (deps.assertSlugAvailable) {
    await deps.assertSlugAvailable(base, contentType, client);
    return base;
  }
  return await deps.ensureUniqueSlug(base, contentType, client);
}

export const stage04SlugResolve = {
  name: "slug-resolve" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (!ctx.frontmatter || !ctx.contentType) {
      throw new Error("stage04: frontmatter / contentType must be set");
    }
    const client = ctx.deps.getSupabaseClient();
    const tableName =
      ctx.contentType === "knowledge"
        ? "knowledge"
        : ctx.contentType === "tech_articles"
          ? "tech_articles"
          : ctx.contentType === "weekly_issues"
            ? "weekly_issues"
            : "knowledge";
    let existing: Record<string, unknown> | null = null;
    if (ctx.opts.update) {
      if (!ctx.opts.slug) {
        ctx.outcome = {
          kind: "error",
          exitCode: 1,
          message: "--update requires --slug",
        };
        throw new Error("update-missing-slug");
      }
      const row = await fetchBySlug(client, tableName, ctx.opts.slug);
      if (!row) {
        ctx.outcome = {
          kind: "error",
          exitCode: 1,
          message: `update target slug not found: ${ctx.opts.slug}`,
        };
        throw new Error("update-target-not-found");
      }
      existing = row;
      ctx.existing = row;
      if (!ctx.opts.dryRun) {
        const snapshotResult = await snapshotBeforeUpdateImpl(
          ctx.opts.slug,
          kindForSnapshot(ctx.contentType),
          {
            contentsDir: ctx.deps.contentsManageDir,
            fetchCurrentContent: async (fetchSlug, _kind) => {
              const r = await fetchBySlug(client, tableName, fetchSlug);
              if (!r) return null;
              return {
                body:
                  typeof r["body"] === "string"
                    ? (r["body"] as string)
                    : typeof r["html"] === "string"
                      ? (r["html"] as string)
                      : "",
                raw_markdown:
                  typeof r["raw_markdown"] === "string"
                    ? (r["raw_markdown"] as string)
                    : null,
              };
            },
          },
        );
        ctx.snapshotNextVersion = snapshotResult.nextVersion;
      }
    }
    const title = String(ctx.frontmatter.title ?? "");
    const slug = await resolveSlug({
      title,
      contentType: ctx.contentType,
      frontmatter: ctx.frontmatter,
      opts: ctx.opts,
      existing,
      client,
      deps: ctx.deps,
    });
    ctx.slug = slug;
    ctx.tableName = tableName;
  },
};
