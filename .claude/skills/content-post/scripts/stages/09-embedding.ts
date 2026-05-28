/**
 * scripts/stages/09-embedding.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 09: generate embedding + (for weekly_issues) similar knowledge search.
 *
 * Pure functions:
 *   - generateEmbeddingForPipeline(title, parsedRaw, deps): truncates to 8000
 *     chars and calls deps.generateEmbedding.
 *   - findRelatedKnowledge(embedding, contentType, deps, logErr, verbose):
 *     returns top-3 related knowledge IDs for weekly_issues; empty otherwise.
 *
 * Stage descriptor:
 *   - stage09Embedding.run(ctx): populates ctx.embedding and ctx.relatedKnowledgeIds.
 *
 * Design intent (動作保存):
 *   - Embedding text = `${title}\n${parsed.raw ?? ""}`.slice(0, 8000).
 *   - searchSimilar only invoked for weekly_issues with non-empty embedding.
 *   - 元 post.ts runOne 611-637 行と動作完全一致。
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export async function generateEmbeddingForPipeline(
  title: string,
  parsedRaw: string,
  deps: PostDeps,
): Promise<number[]> {
  const embeddingText = `${title}\n${parsedRaw}`.slice(0, 8000);
  return await deps.generateEmbedding(embeddingText);
}

export async function findRelatedKnowledge(
  embedding: number[],
  contentType: string,
  deps: PostDeps,
  logErr: (s: string) => void,
  verbose: (s: string) => void,
): Promise<string[]> {
  if (!deps.searchSimilar || contentType !== "weekly_issues" || embedding.length === 0) {
    return [];
  }
  try {
    const similar = await deps.searchSimilar(embedding, {
      limit: 10,
      threshold: 0.7,
    });
    const ids = similar
      .filter((r) => r.content_type === "knowledge")
      .slice(0, 3)
      .map((r) => r.content_id);
    verbose(`[post] related knowledge: ${ids.length} item(s)`);
    return ids;
  } catch (err) {
    logErr(
      `[post] knowledge similarity search failed (continuing): ${(err as Error).message}`,
    );
    return [];
  }
}

export const stage09Embedding = {
  name: "embedding" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (!ctx.frontmatter || !ctx.contentType) {
      throw new Error("stage09: frontmatter / contentType must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const title = String(ctx.frontmatter.title ?? "");
    const parsedRaw = (ctx.parsed?.raw as string | undefined) ?? "";
    const embedding = await generateEmbeddingForPipeline(title, parsedRaw, ctx.deps);
    verbose(`[post] embedding dims: ${embedding.length}`);
    ctx.embedding = embedding;
    const related = await findRelatedKnowledge(
      embedding,
      ctx.contentType,
      ctx.deps,
      logErr,
      verbose,
    );
    ctx.relatedKnowledgeIds = related;
  },
};
