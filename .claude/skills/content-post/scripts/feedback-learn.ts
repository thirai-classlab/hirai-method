#!/usr/bin/env tsx
/**
 * scripts/feedback-learn.ts — Phase 8 Wave F (8.F.2) monthly feedback batch.
 *
 * Pipeline:
 *   1. `collectEdits(since, client)` fetches the last 30 days of edits
 *      from `content_edits_log`.
 *   2. `classifyEdits(edits)` buckets them into four categories:
 *      tag_added / tag_removed / body_revised / category_changed.
 *   3. `synthesizeFewShots(classified, { runLLM })` compresses the edits
 *      into `prompt_few_shots`-shaped examples via Haiku.
 *   4. `upsertFewShots(shots, client)` writes them back into Supabase
 *      (unless `--dry-run`).
 *
 * Exit codes:
 *   0 — success
 *   1 — env / usage error
 *   2 — runtime error
 *
 * Plan: /Users/t.hirai/work/classlab-weekly-news/docs/pdca/phase-8-wave-f/plan.md §8.F.2
 */
import "dotenv/config";
import { Command } from "commander";

import { runLLM as runLLMImpl } from "../src/lib/llm.js";
import { getSupabaseClient as getSupabaseClientImpl } from "../src/lib/supabase.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface EditRecord {
  id: string;
  content_type: "issue" | "article" | "knowledge";
  content_id: string;
  admin_user: string;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  edit_type: string;
  created_at: string;
}

export interface ClassifiedEdits {
  tag_added: EditRecord[];
  tag_removed: EditRecord[];
  body_revised: EditRecord[];
  category_changed: EditRecord[];
}

export interface FewShot {
  task_type: string;
  example_input: Record<string, unknown>;
  example_output: Record<string, unknown>;
  quality_score: number;
}

export interface Streams {
  out: string[];
  err: string[];
  write(line: string): void;
  writeErr(line: string): void;
}

export interface FeedbackLearnDeps {
  getSupabaseClient: () => unknown;
  runLLM: typeof runLLMImpl;
  streams: Streams;
  env: Record<string, string | undefined>;
}

// ---------------------------------------------------------------------------
// collectEdits
// ---------------------------------------------------------------------------

export async function collectEdits(
  since: Date,
  client: unknown,
): Promise<EditRecord[]> {
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => {
        gte: (col: string, val: unknown) => {
          order: (col: string, opts?: { ascending: boolean }) => Promise<{
            data: EditRecord[] | null;
            error: unknown;
          }>;
        };
      };
    };
  };
  const iso = since.toISOString();
  const { data, error } = await c
    .from("content_edits_log")
    .select("*")
    .gte("created_at", iso)
    .order("created_at", { ascending: false });
  if (error) {
    throw new Error(
      `collectEdits: supabase error: ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
  return data ?? [];
}

// ---------------------------------------------------------------------------
// classifyEdits
// ---------------------------------------------------------------------------

export function classifyEdits(edits: EditRecord[]): ClassifiedEdits {
  const out: ClassifiedEdits = {
    tag_added: [],
    tag_removed: [],
    body_revised: [],
    category_changed: [],
  };
  for (const e of edits) {
    if (e.edit_type === "tag") {
      const beforeTags = Array.isArray(
        (e.before as { tags?: unknown } | null)?.tags,
      )
        ? ((e.before as { tags: string[] }).tags)
        : [];
      const afterTags = Array.isArray(
        (e.after as { tags?: unknown } | null)?.tags,
      )
        ? ((e.after as { tags: string[] }).tags)
        : [];
      if (afterTags.length > beforeTags.length) {
        out.tag_added.push(e);
      } else if (afterTags.length < beforeTags.length) {
        out.tag_removed.push(e);
      } else {
        // equal length: treat as revised (fall through to added for now)
        out.tag_added.push(e);
      }
    } else if (e.edit_type === "body") {
      out.body_revised.push(e);
    } else if (e.edit_type === "category") {
      out.category_changed.push(e);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// synthesizeFewShots
// ---------------------------------------------------------------------------

export interface SynthDeps {
  runLLM: typeof runLLMImpl;
}

function buildPrompt(
  bucket: keyof ClassifiedEdits,
  edits: EditRecord[],
): string {
  const sample = edits.slice(0, 20).map((e) => ({
    content_type: e.content_type,
    before: e.before,
    after: e.after,
  }));
  return [
    `You are analyzing admin edits labeled "${bucket}".`,
    `Produce JSON strictly in this shape:`,
    `{ "fewShots": [{`,
    `  "task_type": "auto_tag" | "category" | "body" | "ner",`,
    `  "example_input": { ... },`,
    `  "example_output": { ... },`,
    `  "quality_score": 0.0-1.0`,
    `}] }`,
    ``,
    `Edits:`,
    JSON.stringify(sample, null, 2),
    ``,
    `Return ONLY the JSON object, no prose.`,
  ].join("\n");
}

function bucketHasData(c: ClassifiedEdits): boolean {
  return (
    c.tag_added.length +
      c.tag_removed.length +
      c.body_revised.length +
      c.category_changed.length >
    0
  );
}

function tryParse(text: string): FewShot[] | null {
  try {
    const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/```$/, "");
    const parsed = JSON.parse(trimmed);
    const arr = (parsed as { fewShots?: unknown }).fewShots;
    if (!Array.isArray(arr)) return null;
    return arr.map((r) => {
      const row = r as Record<string, unknown>;
      return {
        task_type: String(row.task_type ?? "auto_tag"),
        example_input: (row.example_input as Record<string, unknown>) ?? {},
        example_output: (row.example_output as Record<string, unknown>) ?? {},
        quality_score:
          typeof row.quality_score === "number" ? row.quality_score : 0.5,
      };
    });
  } catch {
    return null;
  }
}

export async function synthesizeFewShots(
  classified: ClassifiedEdits,
  deps: SynthDeps,
): Promise<FewShot[]> {
  if (!bucketHasData(classified)) return [];
  const buckets: Array<keyof ClassifiedEdits> = [
    "tag_added",
    "tag_removed",
    "body_revised",
    "category_changed",
  ];
  const out: FewShot[] = [];
  for (const bucket of buckets) {
    const edits = classified[bucket];
    if (edits.length === 0) continue;
    const prompt = buildPrompt(bucket, edits);

    // Try once, retry once on parse failure, then throw.
    let parsed: FewShot[] | null = null;
    let lastText = "";
    for (let attempt = 0; attempt < 2; attempt++) {
      const res = await deps.runLLM({
        kind: "few-shot-synthesize",
        prompt,
        maxOutputTokens: 600,
        temperature: 0.2,
      });
      lastText = res.text;
      parsed = tryParse(res.text);
      if (parsed) break;
    }
    if (!parsed) {
      throw new Error(
        `synthesizeFewShots: invalid JSON from Haiku for bucket "${bucket}" after 2 attempts. Last text: ${lastText.slice(0, 120)}`,
      );
    }
    out.push(...parsed);
  }
  return out;
}

// ---------------------------------------------------------------------------
// upsertFewShots
// ---------------------------------------------------------------------------

export async function upsertFewShots(
  shots: FewShot[],
  client: unknown,
): Promise<void> {
  if (shots.length === 0) return;
  const c = client as {
    from: (t: string) => {
      upsert: (
        rows: unknown,
        opts?: unknown,
      ) => Promise<{ data: unknown; error: unknown }>;
    };
  };
  const { error } = await c.from("prompt_few_shots").upsert(
    shots.map((s) => ({
      task_type: s.task_type,
      example_input: s.example_input,
      example_output: s.example_output,
      quality_score: s.quality_score,
    })),
    { onConflict: "task_type" },
  );
  if (error) {
    throw new Error(
      `upsertFewShots: supabase error: ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface ParsedOptions {
  since: string;
  dryRun: boolean;
  verbose: boolean;
}

function parseArgs(argv: string[]): ParsedOptions {
  const program = new Command();
  program
    .name("feedback-learn")
    .exitOverride()
    .allowExcessArguments(true)
    .option("--since <date>", "YYYY-MM-DD start date", defaultSince())
    .option("--dry-run", "do not upsert to prompt_few_shots", false)
    .option("--verbose", "detailed logs", false);
  program.parse(argv, { from: "node" });
  const o = program.opts<{
    since?: string;
    dryRun?: boolean;
    verbose?: boolean;
  }>();
  return {
    since: o.since ?? defaultSince(),
    dryRun: !!o.dryRun,
    verbose: !!o.verbose,
  };
}

function defaultSince(): string {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d.toISOString().slice(0, 10);
}

const REQUIRED_ENV = [
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
  "AI_GATEWAY_API_KEY",
] as const;

function validateEnv(
  env: Record<string, string | undefined>,
): { ok: true } | { ok: false; missing: string[] } {
  const missing = REQUIRED_ENV.filter((k) => {
    const v = env[k];
    return !v || v.trim().length === 0;
  });
  if (missing.length > 0) return { ok: false, missing };
  return { ok: true };
}

export async function main(
  argv: string[],
  deps: FeedbackLearnDeps,
): Promise<number> {
  let opts: ParsedOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    deps.streams.writeErr(
      `[feedback-learn] argv parse error: ${(err as Error).message}`,
    );
    return 1;
  }

  const envCheck = validateEnv(deps.env);
  if (!envCheck.ok) {
    deps.streams.writeErr(
      `[feedback-learn] required env missing: ${envCheck.missing.join(", ")}. Check .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / AI_GATEWAY_API_KEY).`,
    );
    return 1;
  }

  const verbose = (s: string) => {
    if (opts.verbose) deps.streams.write(s);
  };

  try {
    const sinceDate = new Date(opts.since);
    if (Number.isNaN(sinceDate.getTime())) {
      deps.streams.writeErr(
        `[feedback-learn] invalid --since value: ${opts.since}`,
      );
      return 1;
    }

    const client = deps.getSupabaseClient();
    verbose(`[feedback-learn] collecting edits since ${sinceDate.toISOString()}`);
    const edits = await collectEdits(sinceDate, client);
    verbose(`[feedback-learn] collected ${edits.length} edits`);

    const classified = classifyEdits(edits);
    verbose(
      `[feedback-learn] classified: tag_added=${classified.tag_added.length} tag_removed=${classified.tag_removed.length} body=${classified.body_revised.length} category=${classified.category_changed.length}`,
    );

    const shots = await synthesizeFewShots(classified, { runLLM: deps.runLLM });
    verbose(`[feedback-learn] synthesized ${shots.length} few-shots`);

    if (opts.dryRun) {
      deps.streams.write(
        `[feedback-learn] (dry-run) would upsert ${shots.length} few-shot rows`,
      );
      return 0;
    }

    await upsertFewShots(shots, client);
    deps.streams.write(
      `[feedback-learn] upserted ${shots.length} few-shot rows into prompt_few_shots`,
    );
    return 0;
  } catch (err) {
    deps.streams.writeErr(
      `[feedback-learn] unexpected error: ${(err as Error).message}`,
    );
    return 2;
  }
}

// ---------------------------------------------------------------------------
// CLI entry
// ---------------------------------------------------------------------------

function isDirectInvocation(): boolean {
  return (
    typeof process !== "undefined" &&
    !!process.argv[1] &&
    import.meta.url === `file://${process.argv[1]}`
  );
}

if (isDirectInvocation()) {
  const streams: Streams = {
    out: [],
    err: [],
    write(line) {
      process.stdout.write(`${line}\n`);
    },
    writeErr(line) {
      process.stderr.write(`${line}\n`);
    },
  };
  const defaultDeps: FeedbackLearnDeps = {
    getSupabaseClient: () => getSupabaseClientImpl(),
    runLLM: runLLMImpl,
    streams,
    env: process.env,
  };
  void (async () => {
    const code = await main(process.argv, defaultDeps);
    process.exit(code);
  })();
}
