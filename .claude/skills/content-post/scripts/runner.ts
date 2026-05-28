/**
 * scripts/runner.ts — Task #56 W3 (11.3d-C)
 *
 * PipelineRunner orchestrates the 14-stage posting pipeline (stages 01..14).
 * Stage 00 (parseArgs / validateEnv) runs *before* the runner in main() so
 * argv-error paths can return early without constructing a context.
 *
 * Design intent:
 *   - Each stage receives the same PipelineContext object and mutates it in
 *     place. No globals, no return values (stages can set ctx.outcome to
 *     short-circuit the pipeline by throwing — runner re-throws unknown errors
 *     so main() can convert SlugConflictError into the documented exit 2 path).
 *   - Batch mode (runBatch) expands the user-supplied glob via deps.expandGlob
 *     when available; otherwise it treats the pattern as a literal path
 *     (matches inline post.ts fallback semantics).
 *
 * Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W3.
 */
import type { PipelineContext } from "./types/pipeline-context.js";
import type { PostDeps, ParsedOptions } from "./post.js";
import { contentTypeToTable } from "./helpers/type-mapping.js";
import {
  stage01Validate,
  stage02ParseMarkdown,
  stage03LinkCheck,
  stage04SlugResolve,
  stage04bMermaidImage,
  stage05ImageUpload,
  stage06Thumbnail,
  stage07RenderAsync,
  stage08LinkCards,
  stage09Embedding,
  stage10Duplicate,
  stage11CategoryTag,
  stage12Ingest,
  stage13Update,
  stage14Publish,
} from "./stages/index.js";

export interface StageDescriptor {
  readonly name: string;
  run(ctx: PipelineContext): Promise<void>;
}

/**
 * Ordered pipeline. W3 wires stages 01..14 (stage 00 runs before the runner
 * in main() so we can short-circuit on argv/env errors without constructing
 * a context).
 */
export const STAGES: ReadonlyArray<StageDescriptor> = [
  stage01Validate,
  stage02ParseMarkdown,
  stage03LinkCheck,
  stage04SlugResolve,
  stage04bMermaidImage,
  stage05ImageUpload,
  stage06Thumbnail,
  stage07RenderAsync,
  stage08LinkCards,
  stage09Embedding,
  stage10Duplicate,
  stage11CategoryTag,
  stage12Ingest,
  stage13Update,
  stage14Publish,
];

/** Build a fresh PipelineContext for a single-file pipeline run. */
export function createContext(
  filePath: string,
  argv: string[],
  opts: ParsedOptions,
  deps: PostDeps,
): PipelineContext {
  return {
    filePath,
    argv,
    opts,
    env: deps.env,
    streams: deps.streams,
    deps,
  };
}

export class PipelineRunner {
  constructor(
    private readonly deps: PostDeps,
    private readonly opts: ParsedOptions,
  ) {}

  /**
   * Run all wired stages (01..14) against a single file. Returns the resolved
   * exit code (0 on success, ctx.outcome.exitCode when a stage short-circuited).
   * Unhandled errors are re-thrown so main() can convert known exceptions
   * (e.g. SlugConflictError) into their documented exit codes + guidance.
   */
  async runSingle(filePath: string, argv: string[] = []): Promise<number> {
    const ctx = createContext(filePath, argv, this.opts, this.deps);
    // Load file source up-front so stages can assume ctx.source exists.
    ctx.source = await this.deps.loadFile(filePath);
    for (const stage of STAGES) {
      try {
        await stage.run(ctx);
      } catch (err) {
        // ctx.outcome populated → graceful short-circuit (e.g. validate/dup/link-strict).
        if (ctx.outcome?.kind === "error") {
          // Surface the message to streams. Inline post.ts called logErr at
          // each stage exit point; we centralise that here so stage descriptors
          // can stay declarative. Stages that already wrote their own detail
          // line (link-check, duplicate) include the prefix in `message`.
          if (ctx.outcome.message) {
            this.deps.streams.writeErr(`[post] ${ctx.outcome.message}`);
          }
          return ctx.outcome.exitCode;
        }
        // Otherwise propagate so main() can convert known errors.
        throw err;
      }
    }
    return ctx.outcome?.kind === "error" ? ctx.outcome.exitCode : 0;
  }

  /**
   * Run all wired stages against every file matched by the batch glob.
   *
   * Behaviour mirrors post.ts.main()\'s pre-W3 batch path:
   *   - Glob expansion via deps.expandGlob (fallback: literal single path).
   *   - Per-file errors are written to streams but never abort the batch.
   *   - Returns exit 0 on partial failure (batch mode is best-effort by design).
   */
  async runBatch(batchGlob: string): Promise<number> {
    const expand =
      this.deps.expandGlob ??
      (async (pattern: string) => {
        return [pattern];
      });
    let files: string[];
    try {
      files = await expand(batchGlob);
    } catch (err) {
      this.deps.streams.writeErr(
        `[post] batch glob expansion failed: ${(err as Error).message}`,
      );
      return 1;
    }
    if (files.length === 0) {
      this.deps.streams.writeErr(`[post] batch matched 0 files: ${batchGlob}`);
      return 1;
    }
    let okCount = 0;
    let failCount = 0;
    for (const f of files) {
      try {
        const code = await this.runSingle(f);
        if (code === 0) okCount++;
        else failCount++;
      } catch (err) {
        failCount++;
        // SlugConflictError is structured; match the same message format as
        // pre-W3 main() so existing operators see no diff.
        const e = err as { name?: string; slug?: string; contentType?: string; existingId?: string; message?: string };
        if (e?.name === "SlugConflictError") {
          this.deps.streams.writeErr(
            `[post] batch file ${f} slug conflict: "${e.slug}" 既に ${e.contentType} に存在 (id=${e.existingId ?? "?"}) — --update --slug ${e.slug} か別 slug を指定`,
          );
        } else {
          this.deps.streams.writeErr(
            `[post] batch file ${f} failed: ${(err as Error).message}`,
          );
        }
      }
    }
    this.deps.streams.write(
      `[post] batch complete: ${okCount} ok / ${failCount} failed / ${files.length} total`,
    );
    return 0;
  }
}

/** Re-export contentTypeToTable for callers that need it without pulling helpers/ directly. */
export { contentTypeToTable };
