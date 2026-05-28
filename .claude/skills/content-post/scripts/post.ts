#!/usr/bin/env tsx
/**
 * scripts/post.ts — Task #56 W3 (11.3d-C) thin CLI orchestrator
 *
 * post.ts is now a thin entry that delegates the 14-stage pipeline to
 * PipelineRunner. All stage code lives in scripts/stages/*.ts; the public
 * type surface lives in scripts/post-types.ts; CLI DI lives in
 * scripts/defaultDeps.ts.
 *
 * Exit codes (unchanged from W2):
 *   0 — success
 *   1 — usage / validate / env / update-missing
 *   2 — unexpected pipeline runtime error (incl. SlugConflictError)
 *   3 — duplicate block without --force
 *   5 — --link-check-strict broken links found
 */
import { fileURLToPath } from "node:url";
import path from "node:path";
import { SlugConflictError } from "../src/posting/slug.js";
import { parseArgs, validateEnv } from "./stages/00-parse-args.js";
import { PipelineRunner } from "./runner.js";
import type { Streams, PostDeps, ParsedOptions } from "./post-types.js";

// Re-export the public type surface so external callers (tests, defaultDeps)
// keep working with `import { PostDeps } from "../scripts/post.js"`.
export type { Streams, PostDeps, ParsedOptions, KnowledgeKind } from "./post-types.js";
// #58 Step 1: runtime values for the knowledge-kind enum (used by stages 00/12).
export { KNOWLEDGE_KINDS, DEFAULT_KNOWLEDGE_KIND } from "./post-types.js";

export async function main(argv: string[], deps: PostDeps): Promise<number> {
  let opts: ParsedOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    deps.streams.writeErr(`[post] argv parse error: ${(err as Error).message}`);
    return 1;
  }
  const envCheck = validateEnv(deps.env);
  if (!envCheck.ok) {
    deps.streams.writeErr(
      `[post] required env missing: ${envCheck.missing.join(", ")}. Check .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / AI_GATEWAY_API_KEY / SITE_URL / REVALIDATE_SECRET).`,
    );
    return 1;
  }
  if (!opts.file && !opts.batch) {
    deps.streams.writeErr("[post] --file <path> or --batch <glob> is required");
    return 1;
  }
  if (opts.update && !opts.slug) {
    deps.streams.writeErr("[post] --update requires --slug <slug>");
    return 1;
  }
  const runner = new PipelineRunner(deps, opts);
  try {
    if (opts.file && !opts.batch) {
      return await runner.runSingle(opts.file, argv);
    }
    if (opts.batch) {
      return await runner.runBatch(opts.batch);
    }
  } catch (err) {
    if (err instanceof SlugConflictError) {
      deps.streams.writeErr(
        `[post] ERROR: slug "${err.slug}" は既に存在 (id=${err.existingId ?? "?"}, content_type=${err.contentType})`,
      );
      deps.streams.writeErr(`対処方法:`);
      deps.streams.writeErr(`  1. 上書き更新: --update --slug ${err.slug} を付けて再実行`);
      deps.streams.writeErr(`  2. 別記事として: draft frontmatter に slug: "<別名>" を明示`);
      deps.streams.writeErr(`  3. 強制削除後再作成: DB から該当 row を削除 → 再投稿`);
      return 2;
    }
    const e = err as Error;
    deps.streams.writeErr(`[post] unexpected error: ${e.message}`);
    if (opts.verbose && e.stack) deps.streams.writeErr(e.stack);
    return 2;
  }
  return 1;
}

function isDirectInvocation(): boolean {
  try {
    if (typeof process === "undefined" || !process.argv[1]) return false;
    const scriptPath = fileURLToPath(import.meta.url);
    const invokedPath = path.resolve(process.argv[1]);
    return scriptPath === invokedPath;
  } catch {
    return false;
  }
}

if (isDirectInvocation()) {
  const streams: Streams = {
    out: [],
    err: [],
    write(line: string) {
      process.stdout.write(`${line}\n`);
    },
    writeErr(line: string) {
      process.stderr.write(`${line}\n`);
    },
  };
  void (async () => {
    const { buildDefaultDeps, createDefaultReader } = await import("./defaultDeps.js");
    const defaultDeps = buildDefaultDeps(streams);
    defaultDeps.reader = await createDefaultReader();
    const code = await main(process.argv, defaultDeps);
    defaultDeps.reader.close();
    process.exit(code);
  })();
}
