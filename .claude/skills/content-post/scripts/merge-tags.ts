#!/usr/bin/env tsx
/**
 * scripts/merge-tags.ts — Phase 8 Wave F (8.F.4)
 *
 * Monthly batch that scans `tags`, finds pairs with trigram similarity
 * above --threshold, and reports them as alias candidates.
 *
 * Trigram similarity is computed in JS (pad with 2 leading/trailing spaces,
 * build 3-gram set, Jaccard overlap). Less precise than pg_trgm but
 * adequate for monthly review.
 *
 * Pipeline:
 *   1. `fetchAllTags(client)` loads the full tags table.
 *   2. `findSimilarTagPairs(tags, threshold)` computes pairwise trigram
 *      similarity (post-normalization) and selects pairs ≥ threshold.
 *      The higher-usage tag becomes the canonical; the other becomes
 *      an alias.
 *   3. `formatTagAliasReport(candidates)` renders markdown.
 *   4. `maybeApplyAliases(candidates, client, { auto })` upserts to
 *      `term_aliases` (scope='tag') ONLY when `--auto` is set. Default is dry.
 *
 * Exit codes:
 *   0 — success
 *   1 — env / usage error
 *   2 — runtime error
 *
 * Plan: docs/pdca/phase-8-wave-f/plan.md §8.F.4
 */
import "dotenv/config";
import { Command } from "commander";
import fs from "node:fs/promises";

import { getSupabaseClient as getSupabaseClientImpl } from "../src/lib/supabase.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface TagRow {
  id: string;
  name: string;
  usage_count: number;
}

export interface TagAliasCandidate {
  alias: string;
  aliasId: string;
  canonicalName: string;
  canonicalId: string;
  similarity: number;
  aliasUsage: number;
  canonicalUsage: number;
}

export interface Streams {
  out: string[];
  err: string[];
  write(line: string): void;
  writeErr(line: string): void;
}

export interface MergeTagsDeps {
  getSupabaseClient: () => unknown;
  writeFile: (path: string, data: string) => Promise<void>;
  streams: Streams;
  env: Record<string, string | undefined>;
}

// ---------------------------------------------------------------------------
// fetchAllTags
// ---------------------------------------------------------------------------

export async function fetchAllTags(client: unknown): Promise<TagRow[]> {
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => PromiseLike<{
        data: TagRow[] | null;
        error: unknown;
      }>;
    };
  };
  const { data, error } = await c.from("tags").select("id, name, usage_count");
  if (error) {
    throw new Error(
      `fetchAllTags: ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
  return data ?? [];
}

// ---------------------------------------------------------------------------
// Trigram similarity (Jaccard on 3-gram sets)
// ---------------------------------------------------------------------------

function normalizeTagName(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

function trigrams(s: string): Set<string> {
  const padded = `  ${s}  `;
  const out = new Set<string>();
  for (let i = 0; i < padded.length - 2; i++) {
    out.add(padded.slice(i, i + 3));
  }
  return out;
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 0;
  let intersection = 0;
  for (const x of a) {
    if (b.has(x)) intersection++;
  }
  const union = a.size + b.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

export function trigramSimilarity(a: string, b: string): number {
  return jaccard(trigrams(normalizeTagName(a)), trigrams(normalizeTagName(b)));
}

// ---------------------------------------------------------------------------
// findSimilarTagPairs
// ---------------------------------------------------------------------------

export async function findSimilarTagPairs(
  tags: TagRow[],
  threshold: number,
): Promise<TagAliasCandidate[]> {
  const candidates: TagAliasCandidate[] = [];
  const seen = new Set<string>();

  for (let i = 0; i < tags.length; i++) {
    for (let j = i + 1; j < tags.length; j++) {
      const a = tags[i]!;
      const b = tags[j]!;
      if (a.id === b.id) continue;
      const sim = trigramSimilarity(a.name, b.name);
      if (sim < threshold) continue;

      // Choose canonical: higher usage wins, ties → alphabetical
      let canonical: TagRow;
      let alias: TagRow;
      if (a.usage_count > b.usage_count) {
        canonical = a;
        alias = b;
      } else if (b.usage_count > a.usage_count) {
        canonical = b;
        alias = a;
      } else {
        // Tie → alphabetical
        if (a.name <= b.name) {
          canonical = a;
          alias = b;
        } else {
          canonical = b;
          alias = a;
        }
      }
      const key = `${canonical.id}|${alias.id}`;
      if (seen.has(key)) continue;
      seen.add(key);

      candidates.push({
        alias: alias.name,
        aliasId: alias.id,
        canonicalName: canonical.name,
        canonicalId: canonical.id,
        similarity: sim,
        aliasUsage: alias.usage_count,
        canonicalUsage: canonical.usage_count,
      });
    }
  }

  candidates.sort((x, y) => y.similarity - x.similarity);
  return candidates;
}

// ---------------------------------------------------------------------------
// formatTagAliasReport
// ---------------------------------------------------------------------------

export function formatTagAliasReport(
  candidates: TagAliasCandidate[],
): string {
  if (candidates.length === 0) {
    return [
      "# タグ alias 候補レポート",
      "",
      "alias 候補なし（閾値以上の類似タグが見つかりませんでした）。",
      "",
    ].join("\n");
  }
  const lines: string[] = [
    "# タグ alias 候補レポート",
    "",
    `検出候補数: ${candidates.length}`,
    "",
    "| # | Alias (usage) | → Canonical (usage) | Trigram Similarity |",
    "|---|---------------|----------------------|--------------------|",
  ];
  candidates.forEach((c, i) => {
    lines.push(
      `| ${i + 1} | ${c.alias} (${c.aliasUsage}) | ${c.canonicalName} (${c.canonicalUsage}) | ${c.similarity.toFixed(4)} |`,
    );
  });
  lines.push("");
  lines.push(
    "※ デフォルトでは DB に書き込みを行いません。--auto を付けると term_aliases (scope='tag') に upsert します。",
  );
  lines.push("");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// maybeApplyAliases
// ---------------------------------------------------------------------------

export async function maybeApplyAliases(
  candidates: TagAliasCandidate[],
  client: unknown,
  opts: { auto: boolean },
): Promise<void> {
  if (!opts.auto || candidates.length === 0) return;
  const c = client as {
    from: (t: string) => {
      upsert: (
        rows: unknown,
        opts?: unknown,
      ) => Promise<{ data: unknown; error: unknown }>;
    };
  };
  // term_aliases columns:
  //   - term            TEXT NOT NULL  (= old tag_aliases.alias)
  //   - canonical       TEXT NOT NULL  (= canonical tag display name)
  //   - canonical_tag_id UUID REFERENCES tags(id)
  //   - scope           TEXT NOT NULL CHECK (scope IN ('tag','search'))
  //   - UNIQUE (term, scope)
  // We always write scope='tag' here (this script is the tag-aliasing batch).
  const rows = candidates.map((cand) => ({
    term: normalizeTagName(cand.alias),
    canonical: cand.canonicalName,
    canonical_tag_id: cand.canonicalId,
    scope: "tag",
  }));
  const { error } = await c
    .from("term_aliases")
    .upsert(rows, { onConflict: "term,scope" });
  if (error) {
    throw new Error(
      `maybeApplyAliases: ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface ParsedOptions {
  threshold: number;
  output?: string;
  auto: boolean;
  verbose: boolean;
}

function parseArgs(argv: string[]): ParsedOptions {
  const program = new Command();
  program
    .name("merge-tags")
    .exitOverride()
    .allowExcessArguments(true)
    .option("--threshold <n>", "trigram similarity threshold", "0.85")
    .option("--output <path>", "write markdown report to file")
    .option("--auto", "also INSERT into term_aliases scope='tag' (default: report only)", false)
    .option("--verbose", "detailed logs", false);
  program.parse(argv, { from: "node" });
  const o = program.opts<{
    threshold?: string;
    output?: string;
    auto?: boolean;
    verbose?: boolean;
  }>();
  const threshold = Number.parseFloat(o.threshold ?? "0.85");
  return {
    threshold: Number.isFinite(threshold) ? threshold : 0.85,
    output: o.output,
    auto: !!o.auto,
    verbose: !!o.verbose,
  };
}

const REQUIRED_ENV = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"] as const;

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
  deps: MergeTagsDeps,
): Promise<number> {
  let opts: ParsedOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    deps.streams.writeErr(
      `[merge-tags] argv parse error: ${(err as Error).message}`,
    );
    return 1;
  }

  const envCheck = validateEnv(deps.env);
  if (!envCheck.ok) {
    deps.streams.writeErr(
      `[merge-tags] required env missing: ${envCheck.missing.join(", ")}. Check .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).`,
    );
    return 1;
  }

  const verbose = (s: string) => {
    if (opts.verbose) deps.streams.write(s);
  };

  try {
    const client = deps.getSupabaseClient();
    verbose(`[merge-tags] fetching tags`);
    const tags = await fetchAllTags(client);
    verbose(`[merge-tags] fetched ${tags.length} tags`);

    const candidates = await findSimilarTagPairs(tags, opts.threshold);
    verbose(
      `[merge-tags] found ${candidates.length} alias candidates (threshold=${opts.threshold})`,
    );

    const report = formatTagAliasReport(candidates);
    deps.streams.write(report);

    if (opts.output) {
      await deps.writeFile(opts.output, report);
      deps.streams.write(`[merge-tags] report written to ${opts.output}`);
    }

    if (opts.auto) {
      verbose(
        `[merge-tags] --auto enabled: upserting into term_aliases (scope='tag')`,
      );
      await maybeApplyAliases(candidates, client, { auto: true });
      deps.streams.write(
        `[merge-tags] upserted ${candidates.length} rows into term_aliases (scope='tag')`,
      );
    }

    return 0;
  } catch (err) {
    deps.streams.writeErr(
      `[merge-tags] unexpected error: ${(err as Error).message}`,
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
  const defaultDeps: MergeTagsDeps = {
    getSupabaseClient: () => getSupabaseClientImpl(),
    writeFile: (p, d) => fs.writeFile(p, d, "utf-8"),
    streams,
    env: process.env,
  };
  void (async () => {
    const code = await main(process.argv, defaultDeps);
    process.exit(code);
  })();
}
