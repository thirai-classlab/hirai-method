/**
 * scripts/stages/02-parse-markdown.ts — Task #56 W2 (11.3d-B)
 *
 * Stage 02: parse markdown source and render initial HTML (pre-image-upload).
 *
 * Pure function:
 *   - parseAndRender(source, contentType, frontmatter, validateTemplates, deps)
 *     - returns { parsed, rendered, template }
 *
 * Stage descriptor:
 *   - stage02ParseMarkdown.run(ctx): populates ctx.parsed / ctx.rendered.
 *
 * Design intent (動作保存):
 *   - Template lookup mirrors post.ts inline behaviour exactly: best-effort,
 *     errors log but never throw. Falls back to `{}` when getTemplate returns
 *     null/undefined.
 *   - Returns the initial sync render result (renderToHtml). Async PlantUML
 *     re-render still happens later in stage 5b+ — by design, since image
 *     rewrites can change the source between parse and async-render.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W2.
 */
import { getTemplate } from "../../src/lib/templates.js";
import type { ParsedMarkdown } from "../../src/lib/markdown.js";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export interface ParseRenderResult {
  parsed: ParsedMarkdown;
  rendered: { html: string; appliedClasses: string[]; plantumlReplacements?: unknown[] };
  template: unknown;
  /** Diagnostic note when template lookup throws (non-fatal). */
  templateError?: string;
}

/**
 * Parse markdown via deps.parseMarkdown and render the initial sync HTML via
 * deps.renderToHtml. Template lookup is best-effort.
 */
export function parseAndRender(
  source: string,
  contentType: string,
  frontmatter: Record<string, unknown>,
  validateTemplates: Record<string, unknown>,
  deps: PostDeps,
): ParseRenderResult {
  const parsed = deps.parseMarkdown(source);
  let template: unknown = {};
  let templateError: string | undefined;
  try {
    const registry = validateTemplates;
    const templateType =
      contentType === "tech_articles"
        ? "tech_article"
        : contentType === "weekly_issues"
          ? "weekly_issue"
          : "knowledge";
    const t = getTemplate(
      registry as unknown as Parameters<typeof getTemplate>[0],
      templateType,
      (frontmatter.subtype as string | undefined) || undefined,
    );
    template = t ?? {};
  } catch (err) {
    templateError = (err as Error).message;
  }
  const rendered = deps.renderToHtml(source, template);
  return { parsed, rendered, template, templateError };
}

export const stage02ParseMarkdown = {
  name: "parse-markdown" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (typeof ctx.source !== "string" || !ctx.frontmatter || !ctx.contentType) {
      throw new Error("stage02: ctx.source / frontmatter / contentType must be set before parse-markdown stage");
    }
    // Templates registry is not stored on ctx today; W3 will thread it through.
    // For now consume from a transient temp by re-loading; tests own this contract.
    const validateTemplates: Record<string, unknown> = {};
    if (ctx.deps.loadTemplates) {
      try {
        Object.assign(
          validateTemplates,
          (await ctx.deps.loadTemplates()) as Record<string, unknown>,
        );
      } catch {
        // empty fallback
      }
    }
    const result = parseAndRender(
      ctx.source,
      ctx.contentType,
      ctx.frontmatter,
      validateTemplates,
      ctx.deps,
    );
    ctx.parsed = result.parsed;
    ctx.rendered = result.rendered;
  },
};
