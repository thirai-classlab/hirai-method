/**
 * scripts/stages/07-render-async.ts — Task #56 W3 (11.3d-C)
 *
 * Stage 07: async render (PlantUML + final HTML re-render after image upload).
 *
 * Pure function:
 *   - renderAsync(args): invokes deps.renderToHtmlAsync when wired and not
 *     --dry-run. Returns the updated rendered object so the caller can decide
 *     how to splice it into context state.
 *
 * Stage descriptor:
 *   - stage07RenderAsync.run(ctx): mutates ctx.rendered with the async result.
 *
 * Design intent (動作保存):
 *   - Skip when dep未注入 or --dry-run (matches inline post.ts behaviour).
 *   - Template is re-resolved here via loadTemplates + getTemplate so the same
 *     {type, subtype} flowing through stage 02 is honoured. This is the same
 *     getTemplate lookup that ran in stage 02 but we re-run it because ctx
 *     intentionally does not memoise the template (cheap filesystem read).
 *   - Verbose logs the number of PlantUML blocks processed when > 0.
 *   - 元 post.ts runOne 586-595 行と動作完全一致。
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";
import { mapContentTypeToImagePrefix } from "../helpers/type-mapping.js";
import { getTemplate } from "../../src/lib/templates.js";

export interface RenderAsyncArgs {
  source: string;
  template: unknown;
  slug: string;
  contentType: string;
  opts: { dryRun: boolean };
  deps: PostDeps;
  verbose: (s: string) => void;
}

export interface RenderAsyncResult {
  rendered: {
    html: string;
    appliedClasses: string[];
    plantumlReplacements?: unknown[];
  } | null;
}

export async function renderAsync(args: RenderAsyncArgs): Promise<RenderAsyncResult> {
  const { source, template, slug, contentType, opts, deps, verbose } = args;
  if (!deps.renderToHtmlAsync || opts.dryRun) {
    return { rendered: null };
  }
  const imageType = mapContentTypeToImagePrefix(contentType);
  const rendered = await deps.renderToHtmlAsync(source, template, {
    slug,
    contentType: imageType,
  });
  if (rendered.plantumlReplacements && rendered.plantumlReplacements.length > 0) {
    verbose(`[post] plantuml: ${rendered.plantumlReplacements.length} block(s) processed`);
  }
  return { rendered };
}

/** Re-resolve the template the same way stage 02 did. Best-effort: errors → {}. */
async function resolveTemplate(
  contentType: string,
  frontmatter: Record<string, unknown>,
  deps: PostDeps,
): Promise<unknown> {
  if (!deps.loadTemplates) return {};
  try {
    const registry = (await deps.loadTemplates()) as unknown as Parameters<
      typeof getTemplate
    >[0];
    const templateType =
      contentType === "tech_articles"
        ? "tech_article"
        : contentType === "weekly_issues"
          ? "weekly_issue"
          : "knowledge";
    const t = getTemplate(
      registry,
      templateType,
      (frontmatter.subtype as string | undefined) || undefined,
    );
    return t ?? {};
  } catch {
    return {};
  }
}

export const stage07RenderAsync = {
  name: "render-async" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (typeof ctx.source !== "string" || !ctx.slug || !ctx.contentType || !ctx.frontmatter) {
      throw new Error("stage07: ctx.source / slug / contentType / frontmatter must be set");
    }
    const verbose = (s: string) => {
      if (ctx.opts.verbose) ctx.streams.write(s);
    };
    const template = await resolveTemplate(ctx.contentType, ctx.frontmatter, ctx.deps);
    const result = await renderAsync({
      source: ctx.source,
      template,
      slug: ctx.slug,
      contentType: ctx.contentType,
      opts: { dryRun: ctx.opts.dryRun },
      deps: ctx.deps,
      verbose,
    });
    if (result.rendered) {
      ctx.rendered = {
        html: result.rendered.html,
        appliedClasses: result.rendered.appliedClasses,
      };
    }
  },
};
