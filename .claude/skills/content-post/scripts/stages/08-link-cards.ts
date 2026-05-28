/**
 * scripts/stages/08-link-cards.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 08: enrich bare link-card divs with OG metadata (#39).
 *
 * Pure function:
 *   - enrichLinkCardsIfNeeded(html, deps, opts, logErr, verbose): invokes
 *     deps.enrichLinkCards when wired and not --dry-run. Errors are logged
 *     and the original html is returned.
 *
 * Stage descriptor:
 *   - stage08LinkCards.run(ctx): replaces ctx.rendered.html with the enriched
 *     html when available.
 *
 * Design intent (動作保存):
 *   - 内部実装 (link-card-extractor.ts) は untouch、deps 経由のみ.
 *   - Errors fall back to original html (best-effort).
 *   - 元 post.ts runOne 597-609 行と動作完全一致。
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export async function enrichLinkCardsIfNeeded(
  html: string,
  deps: PostDeps,
  opts: { dryRun: boolean },
  logErr: (s: string) => void,
  verbose: (s: string) => void,
): Promise<string> {
  if (!deps.enrichLinkCards || opts.dryRun) {
    return html;
  }
  try {
    const enriched = await deps.enrichLinkCards(html);
    verbose(`[post] enrichLinkCards: html=${enriched.length} chars after enrichment`);
    return enriched;
  } catch (err) {
    logErr(`[post] enrichLinkCards failed (continuing): ${(err as Error).message}`);
    return html;
  }
}

export const stage08LinkCards = {
  name: "link-cards" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (!ctx.rendered) {
      throw new Error("stage08: ctx.rendered must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const logErr = (s: string) => ctx.streams.writeErr(s);
    const enriched = await enrichLinkCardsIfNeeded(
      ctx.rendered.html,
      ctx.deps,
      { dryRun: ctx.opts.dryRun },
      logErr,
      verbose,
    );
    ctx.rendered = { ...ctx.rendered, html: enriched };
  },
};
