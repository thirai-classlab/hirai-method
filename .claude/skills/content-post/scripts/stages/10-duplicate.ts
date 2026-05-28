/**
 * scripts/stages/10-duplicate.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 10: duplicate detection via embedding similarity.
 *
 * Pure function:
 *   - checkDuplicate(embedding, contentType, existing, deps): wraps
 *     deps.checkDuplicate with selfId so --update doesn\'t self-trigger
 *     the block threshold.
 *
 * Stage descriptor:
 *   - stage10Duplicate.run(ctx): sets ctx.outcome to exit 3 when level=block
 *     without --force or --update. Otherwise leaves ctx unchanged.
 *
 * Design intent (動作保存):
 *   - --update skips block check (high self-similarity to old embedding is OK).
 *   - --force overrides block. warn level is logged but never blocks.
 *   - 元 post.ts runOne 639-655 行と動作完全一致。
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export interface DupResult {
  level: "ok" | "warn" | "block";
  matches: Array<{ content_id: string; similarity: number }>;
  reason: string | null;
}

export async function checkDuplicateForPipeline(
  embedding: number[],
  contentType: string,
  existing: Record<string, unknown> | null,
  client: unknown,
  deps: PostDeps,
): Promise<DupResult> {
  return (await deps.checkDuplicate({
    client,
    embedding,
    contentType,
    selfId: existing?.id as string | undefined,
  })) as DupResult;
}

export const stage10Duplicate = {
  name: "duplicate" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (!ctx.contentType || !ctx.embedding) {
      throw new Error("stage10: contentType / embedding must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const client = ctx.deps.getSupabaseClient();
    const dup = await checkDuplicateForPipeline(
      ctx.embedding,
      ctx.contentType,
      ctx.existing ?? null,
      client,
      ctx.deps,
    );
    verbose(`[post] duplicate: level=${dup.level} matches=${dup.matches.length}`);
    if (dup.level === "block" && !ctx.opts.force && !ctx.opts.update) {
      logErr(
        `[post] duplicate block (use --force to override): ${dup.reason ?? "high similarity"}`,
      );
      ctx.outcome = {
        kind: "error",
        exitCode: 3,
        message: dup.reason ?? "duplicate-block",
      };
      throw new Error("duplicate-block");
    }
  },
};
