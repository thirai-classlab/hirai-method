/**
 * scripts/types/pipeline-context.ts — Task #56 W1 (11.3d-A)
 *
 * Pass-through state object threaded through the 14 pipeline stages.
 * Stages mutate the context in place; no globals.
 *
 * Design intent:
 *   - W1 (this wave) only DEFINES the interface; no stage consumes it yet.
 *   - W2 introduces stages/00..04 + runner.ts which actually own and
 *     mutate PipelineContext instances.
 *   - Field set follows classlab-weekly-news/docs/draft/post-ts-reduction.md §3.2.
 */

import type { Streams, ParsedOptions, PostDeps } from "../post.js";
import type { ParsedMarkdown } from "../../src/lib/markdown.js";

/**
 * Final outcome of a single-file pipeline run. W2 stages set this when
 * they conclude with anything other than "continue to next stage".
 */
export type PipelineOutcome =
  | { kind: "success"; contentId: string }
  | { kind: "dry-run" }
  | { kind: "duplicate-block"; reason: string }
  | { kind: "user-aborted" }
  | { kind: "error"; exitCode: number; message: string };

export interface PipelineContext {
  // CLI / env inputs (前段で確定)
  filePath: string;
  argv: string[];
  opts: ParsedOptions;
  env: Record<string, string | undefined>;
  streams: Streams;
  deps: PostDeps;

  // Stage outputs (順次 accumulate)
  source?: string;
  frontmatter?: Record<string, unknown>;
  parsed?: ParsedMarkdown;
  rendered?: { html: string; appliedClasses: string[] };
  slug?: string;
  contentType?: string;
  tableName?: string;
  existing?: Record<string, unknown>;
  // confirmedMeta shape mirrors runOne's confirmInteractively return value.
  // Stored as `unknown` because stages 12/13 type-narrow it themselves and
  // duplicating the cast logic across stages would be noise.
  confirmedMeta?: unknown;
  contentId?: string;
  thumbnailCdnUrl?: string | null;
  snapshotNextVersion?: number | null;
  // W3: stage 09 outputs.
  embedding?: number[];
  relatedKnowledgeIds?: string[];

  // Outcome
  outcome?: PipelineOutcome;
}
