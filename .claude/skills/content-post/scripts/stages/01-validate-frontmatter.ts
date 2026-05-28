/**
 * scripts/stages/01-validate-frontmatter.ts — Task #56 W2 (11.3d-B)
 *
 * Stage 01: validate raw markdown source and extract frontmatter.
 *
 * Pure function (signature mirrors the inline runOne step 3 from post.ts):
 *   - validateFrontmatter(source, deps): loadTemplates + validateInput
 *     - returns { ok: true, frontmatter, title, contentType, validateTemplates }
 *       or { ok: false, errors: Array<{ field, message }> }
 *
 * Stage descriptor:
 *   - stage01Validate.run(ctx): populates ctx.source / ctx.frontmatter, sets
 *     ctx.outcome on validation failure (exit code 1).
 *
 * Design intent (動作保存):
 *   - Same loadTemplates fallback semantics: failures yield an empty registry.
 *   - Same return shape for the success path. Existing post.ts tests are the
 *     contract.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W2.
 */
import type { PipelineContext } from "../types/pipeline-context.js";
import type { PostDeps } from "../post.js";

export type ValidateResult =
  | {
      ok: true;
      frontmatter: Record<string, unknown>;
      title: string;
      contentType: string;
      validateTemplates: Record<string, unknown>;
    }
  | {
      ok: false;
      errors: Array<{ field: string; message: string }>;
    };

/**
 * Validate the source via deps.validate and derive the frontmatter/title/
 * contentType triple. Templates are loaded best-effort (errors → empty).
 */
export async function validateFrontmatter(
  source: string,
  deps: PostDeps,
): Promise<ValidateResult> {
  let validateTemplates: Record<string, unknown> = {};
  if (deps.loadTemplates) {
    try {
      validateTemplates = (await deps.loadTemplates()) as Record<string, unknown>;
    } catch {
      validateTemplates = {};
    }
  }
  const validation = deps.validate(source, {
    templates: validateTemplates as never,
  });
  if (!validation.ok) {
    const errors = (validation as unknown as {
      errors: Array<{ field: string; message: string }>;
    }).errors;
    return { ok: false, errors };
  }
  const frontmatter = (
    validation as unknown as { frontmatter: Record<string, unknown> }
  ).frontmatter;
  const title = String(frontmatter.title ?? "");
  const contentType = String(frontmatter.type ?? "knowledge");
  return { ok: true, frontmatter, title, contentType, validateTemplates };
}

export const stage01Validate = {
  name: "validate-frontmatter" as const,
  async run(ctx: PipelineContext): Promise<void> {
    if (typeof ctx.source !== "string") {
      throw new Error("stage01: ctx.source must be populated before validate stage");
    }
    const result = await validateFrontmatter(ctx.source, ctx.deps);
    if (!result.ok) {
      const msgs = result.errors
        .map((e) => `  - ${e.field}: ${e.message}`)
        .join("\n");
      ctx.outcome = {
        kind: "error",
        exitCode: 1,
        message: `validate failed:\n${msgs}`,
      };
      throw new Error("validate-failed");
    }
    ctx.frontmatter = result.frontmatter;
    // contentType / title flow downstream via additional ctx fields (W3).
    ctx.contentType = result.contentType;
  },
};
