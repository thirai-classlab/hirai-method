/**
 * scripts/stages/00-parse-args.ts — Task #56 W2 (11.3d-B)
 *
 * Stage 00: CLI argv → ParsedOptions and env validation.
 *
 * Pure functions (extracted from post.ts):
 *   - parseArgs(argv): commander-based CLI parsing
 *   - validateEnv(env): REQUIRED_ENV presence check
 *
 * Stage descriptor (consumed by runner.ts in W3):
 *   - stage00ParseArgs.run(ctx): mutates ctx.opts; throws on missing env.
 *
 * Design intent (動作保存):
 *   - parseArgs / validateEnv signatures and return values are byte-identical
 *     to the original post.ts definitions. Existing 521 test suite is the
 *     primary contract.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W2.
 */
import { Command } from "commander";
import type { PipelineContext } from "../types/pipeline-context.js";
import type { ParsedOptions, KnowledgeKind } from "../post.js";
import { KNOWLEDGE_KINDS, DEFAULT_KNOWLEDGE_KIND } from "../post.js";

/**
 * Parse argv into the ParsedOptions struct used throughout the pipeline.
 * Uses commander with .exitOverride() so test callers receive thrown errors
 * instead of process.exit().
 */
export function parseArgs(argv: string[]): ParsedOptions {
  const program = new Command();
  program
    .name("post")
    .exitOverride()
    .allowExcessArguments(true)
    .option("--file <path>", "markdown file to post")
    .option("--batch <glob>", "glob for batch mode")
    .option("--dry-run", "no DB writes, show proposed steps only", false)
    .option("--auto-approve", "skip interactive prompts", false)
    .option("--update", "update existing content (requires --slug)", false)
    .option("--slug <slug>", "target slug when --update")
    .option("--force", "ignore duplicate block", false)
    .option("--verbose", "detailed logs", false)
    // #32: thumbnail hearing layer — defaults ON, --no-thumbnail-hearing to skip
    .option("--no-thumbnail-hearing", "skip thumbnail hearing (no auto-generation when frontmatter.thumbnail is empty)")
    // #33: draft → publish flow
    .option("--publish", "publish content after INSERT via POST /api/publish", false)
    // link-check phase: external URL reachability check (default ON, warn-only)
    .option("--no-link-check", "skip external link reachability check")
    .option("--link-check-strict", "fail (exit 5) if any external link is broken", false)
    // #58 Step 1: knowledge.kind 列 (concept|operation|domain_knowledge)。knowledge 以外では無視
    .option(
      "--kind <kind>",
      `knowledge kind (one of: ${KNOWLEDGE_KINDS.join(", ")}); only applies when type is knowledge`,
    );

  program.parse(argv, { from: "node" });
  const opts = program.opts<{
    file?: string;
    batch?: string;
    dryRun?: boolean;
    autoApprove?: boolean;
    update?: boolean;
    slug?: string;
    force?: boolean;
    verbose?: boolean;
    thumbnailHearing?: boolean;
    publish?: boolean;
    linkCheck?: boolean;
    linkCheckStrict?: boolean;
    kind?: string;
  }>();

  // #58 Step 1: validate --kind fail-fast. Omitted → "concept" (backward compat).
  const knowledgeKind = resolveKnowledgeKind(opts.kind);

  return {
    file: opts.file,
    batch: opts.batch,
    dryRun: !!opts.dryRun,
    autoApprove: !!opts.autoApprove,
    update: !!opts.update,
    slug: opts.slug,
    force: !!opts.force,
    verbose: !!opts.verbose,
    thumbnailHearing: opts.thumbnailHearing !== false,
    publish: !!opts.publish,
    linkCheck: opts.linkCheck !== false,
    linkCheckStrict: !!opts.linkCheckStrict,
    knowledgeKind,
  };
}

/**
 * #58 Step 1: resolve and validate the `--kind` flag.
 * Omitted/undefined → "concept" (backward compat). Invalid value → throw
 * (fail-fast; main() converts the thrown error into exit 1).
 */
function resolveKnowledgeKind(raw: string | undefined): KnowledgeKind {
  if (raw === undefined) return DEFAULT_KNOWLEDGE_KIND;
  if ((KNOWLEDGE_KINDS as readonly string[]).includes(raw)) {
    return raw as KnowledgeKind;
  }
  throw new Error(
    `--kind must be one of: ${KNOWLEDGE_KINDS.join(", ")} (got "${raw}")`,
  );
}

/** Required env vars for pipeline execution (every CLI invocation). */
export const REQUIRED_ENV = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "AI_GATEWAY_API_KEY",
  "SITE_URL",
  "REVALIDATE_SECRET",
] as const;

/**
 * Check that every REQUIRED_ENV key is present and non-empty.
 * Returns the original tagged-union shape used by post.ts main().
 */
export function validateEnv(
  env: Record<string, string | undefined>,
): { ok: true } | { ok: false; missing: string[] } {
  const missing = REQUIRED_ENV.filter((k) => {
    const v = env[k];
    return !v || v.trim().length === 0;
  });
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true };
}

/**
 * Stage descriptor (consumed by PipelineRunner in W3).
 * W2 ships the descriptor but runner.ts wires it from W3 onwards.
 */
export const stage00ParseArgs = {
  name: "parse-args" as const,
  async run(ctx: PipelineContext): Promise<void> {
    ctx.opts = parseArgs(ctx.argv);
    const envCheck = validateEnv(ctx.env);
    if (!envCheck.ok) {
      throw new Error(
        `required env missing: ${envCheck.missing.join(", ")}. Check .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / AI_GATEWAY_API_KEY / SITE_URL / REVALIDATE_SECRET).`,
      );
    }
  },
};
