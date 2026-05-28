#!/usr/bin/env tsx
/**
 * scripts/merge-duplicates.ts — Phase 8 Wave F (8.F.3)
 *
 * READ-ONLY monthly batch: scans `content_embeddings`, computes pairwise
 * cosine similarity, and emits a markdown report of merge candidates.
 * **NEVER writes to the database.** The final merge decision is left to
 * a human.
 *
 * Pipeline:
 *   1. `fetchAllEmbeddings(client, { type })` fetches embedding rows.
 *   2. `findDuplicatePairs(rows, threshold)` computes cosine similarity
 *      for every unordered pair and returns those ≥ threshold.
 *   3. `enrichPairs(pairs, client)` resolves id → slug/title metadata
 *      by content_type.
 *   4. `formatReport(pairs)` renders markdown.
 *   5. Report is printed to stdout and (optionally) written to --output.
 *
 * Exit codes:
 *   0 — success
 *   1 — env / usage error
 *   2 — runtime error
 *
 * Plan: docs/pdca/phase-8-wave-f/plan.md §8.F.3
 */
import "dotenv/config";
import { Command } from "commander";
import fs from "node:fs/promises";

import { getSupabaseClient as getSupabaseClientImpl } from "../src/lib/supabase.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ContentType = "knowledge" | "tech_articles" | "weekly_issues";
export type TypeFilter = ContentType | "all";

export interface EmbeddingRow {
  content_type: string;
  content_id: string;
  embedding: number[];
}

export interface DuplicatePair {
  aType: string;
  aId: string;
  aSlug: string;
  aTitle: string;
  bType: string;
  bId: string;
  bSlug: string;
  bTitle: string;
  similarity: number;
}

export interface Streams {
  out: string[];
  err: string[];
  write(line: string): void;
  writeErr(line: string): void;
}

export interface MergeDuplicatesDeps {
  getSupabaseClient: () => unknown;
  writeFile: (path: string, data: string) => Promise<void>;
  streams: Streams;
  env: Record<string, string | undefined>;
}

// ---------------------------------------------------------------------------
// fetchAllEmbeddings
// ---------------------------------------------------------------------------

export async function fetchAllEmbeddings(
  client: unknown,
  opts: { type: TypeFilter },
): Promise<EmbeddingRow[]> {
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => {
        eq?: (col: string, val: unknown) => unknown;
      } & PromiseLike<{ data: EmbeddingRow[] | null; error: unknown }>;
    };
  };
  let builder = c
    .from("content_embeddings")
    .select("content_type, content_id, embedding") as unknown as {
    eq: (col: string, val: unknown) => unknown;
  } & PromiseLike<{ data: EmbeddingRow[] | null; error: unknown }>;

  if (opts.type !== "all") {
    const mapped = opts.type === "knowledge"
      ? "knowledge"
      : opts.type === "tech_articles"
        ? "article"
        : "issue";
    // content_embeddings stores issue/article/knowledge (from generation log),
    // but many rows may use the table name too. We match both.
    // To keep filtering simple we fetch all and post-filter in JS.
    builder = builder;
    const { data, error } = await (builder as unknown as Promise<{
      data: EmbeddingRow[] | null;
      error: unknown;
    }>);
    if (error) {
      throw new Error(
        `fetchAllEmbeddings: ${(error as { message?: string }).message ?? String(error)}`,
      );
    }
    return (data ?? []).filter(
      (r) => r.content_type === mapped || r.content_type === opts.type,
    );
  }

  const { data, error } = await (builder as unknown as Promise<{
    data: EmbeddingRow[] | null;
    error: unknown;
  }>);
  if (error) {
    throw new Error(
      `fetchAllEmbeddings: ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
  return data ?? [];
}

// ---------------------------------------------------------------------------
// findDuplicatePairs — naive O(n^2) cosine similarity
// ---------------------------------------------------------------------------

function dot(a: number[], b: number[]): number {
  const len = Math.min(a.length, b.length);
  let s = 0;
  for (let i = 0; i < len; i++) s += (a[i] ?? 0) * (b[i] ?? 0);
  return s;
}

function norm(a: number[]): number {
  let s = 0;
  for (let i = 0; i < a.length; i++) {
    const v = a[i] ?? 0;
    s += v * v;
  }
  return Math.sqrt(s);
}

function cosine(a: number[], b: number[]): number {
  const na = norm(a);
  const nb = norm(b);
  if (na === 0 || nb === 0) return 0;
  return dot(a, b) / (na * nb);
}

interface BarePair {
  aType: string;
  aId: string;
  bType: string;
  bId: string;
  similarity: number;
}

export async function findDuplicatePairs(
  rows: EmbeddingRow[],
  threshold: number,
): Promise<
  Array<{
    aType: string;
    aId: string;
    aSlug: string;
    aTitle: string;
    bType: string;
    bId: string;
    bSlug: string;
    bTitle: string;
    similarity: number;
  }>
> {
  const pairs: BarePair[] = [];
  for (let i = 0; i < rows.length; i++) {
    for (let j = i + 1; j < rows.length; j++) {
      const a = rows[i]!;
      const b = rows[j]!;
      // Skip if somehow the same id
      if (a.content_type === b.content_type && a.content_id === b.content_id) {
        continue;
      }
      const sim = cosine(a.embedding, b.embedding);
      if (sim >= threshold) {
        // Stable ordering by (type, id)
        const akey = `${a.content_type}:${a.content_id}`;
        const bkey = `${b.content_type}:${b.content_id}`;
        if (akey < bkey) {
          pairs.push({
            aType: a.content_type,
            aId: a.content_id,
            bType: b.content_type,
            bId: b.content_id,
            similarity: sim,
          });
        } else {
          pairs.push({
            aType: b.content_type,
            aId: b.content_id,
            bType: a.content_type,
            bId: a.content_id,
            similarity: sim,
          });
        }
      }
    }
  }
  // Dedup in case the stable-order path ever collides (defensive)
  const seen = new Set<string>();
  const unique: BarePair[] = [];
  for (const p of pairs) {
    const k = `${p.aType}:${p.aId}|${p.bType}:${p.bId}`;
    if (seen.has(k)) continue;
    seen.add(k);
    unique.push(p);
  }
  unique.sort((x, y) => y.similarity - x.similarity);

  // Return without slug/title populated — enrichment happens in main()
  return unique.map((p) => ({
    aType: p.aType,
    aId: p.aId,
    aSlug: "",
    aTitle: "",
    bType: p.bType,
    bId: p.bId,
    bSlug: "",
    bTitle: "",
    similarity: p.similarity,
  }));
}

// ---------------------------------------------------------------------------
// enrichPairs
// ---------------------------------------------------------------------------

function mapTypeToTable(contentType: string): ContentType | null {
  if (contentType === "knowledge") return "knowledge";
  if (contentType === "tech_articles" || contentType === "article")
    return "tech_articles";
  if (contentType === "weekly_issues" || contentType === "issue")
    return "weekly_issues";
  return null;
}

async function fetchContentMeta(
  client: unknown,
  table: ContentType,
  ids: string[],
): Promise<Map<string, { slug: string; title: string }>> {
  if (ids.length === 0) return new Map();
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => {
        in: (col: string, vals: unknown[]) => PromiseLike<{
          data: Array<{ id: string; slug: string; title: string }> | null;
          error: unknown;
        }>;
      };
    };
  };
  const { data, error } = await c
    .from(table)
    .select("id, slug, title")
    .in("id", ids);
  if (error) {
    throw new Error(
      `fetchContentMeta(${table}): ${(error as { message?: string }).message ?? String(error)}`,
    );
  }
  const out = new Map<string, { slug: string; title: string }>();
  for (const r of data ?? []) {
    out.set(String(r.id), { slug: String(r.slug), title: String(r.title) });
  }
  return out;
}

export async function enrichPairs(
  pairs: DuplicatePair[],
  client: unknown,
): Promise<DuplicatePair[]> {
  const idsByTable: Record<ContentType, Set<string>> = {
    knowledge: new Set(),
    tech_articles: new Set(),
    weekly_issues: new Set(),
  };
  for (const p of pairs) {
    const aTable = mapTypeToTable(p.aType);
    const bTable = mapTypeToTable(p.bType);
    if (aTable) idsByTable[aTable].add(p.aId);
    if (bTable) idsByTable[bTable].add(p.bId);
  }
  const metaByTable: Record<ContentType, Map<string, { slug: string; title: string }>> = {
    knowledge: await fetchContentMeta(client, "knowledge", [...idsByTable.knowledge]),
    tech_articles: await fetchContentMeta(client, "tech_articles", [...idsByTable.tech_articles]),
    weekly_issues: await fetchContentMeta(client, "weekly_issues", [...idsByTable.weekly_issues]),
  };
  return pairs.map((p) => {
    const aTable = mapTypeToTable(p.aType);
    const bTable = mapTypeToTable(p.bType);
    const aMeta = aTable ? metaByTable[aTable].get(p.aId) : undefined;
    const bMeta = bTable ? metaByTable[bTable].get(p.bId) : undefined;
    return {
      ...p,
      aSlug: aMeta?.slug ?? p.aId,
      aTitle: aMeta?.title ?? "(unknown)",
      bSlug: bMeta?.slug ?? p.bId,
      bTitle: bMeta?.title ?? "(unknown)",
    };
  });
}

// ---------------------------------------------------------------------------
// formatReport
// ---------------------------------------------------------------------------

export function formatReport(pairs: DuplicatePair[]): string {
  if (pairs.length === 0) {
    return [
      "# マージ候補レポート",
      "",
      "マージ候補なし（閾値以上の類似ペアが見つかりませんでした）。",
      "",
    ].join("\n");
  }
  const lines: string[] = [
    "# マージ候補レポート",
    "",
    `検出ペア数: ${pairs.length}`,
    "",
    "| # | Type A | Slug A | Type B | Slug B | Similarity |",
    "|---|--------|--------|--------|--------|------------|",
  ];
  pairs.forEach((p, i) => {
    lines.push(
      `| ${i + 1} | ${p.aType} | ${p.aSlug} (${p.aTitle}) | ${p.bType} | ${p.bSlug} (${p.bTitle}) | ${p.similarity.toFixed(4)} |`,
    );
  });
  lines.push("");
  lines.push(
    "※ このレポートはDBに書き込みを行いません。マージ判断は人間が行ってください。",
  );
  lines.push("");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface ParsedOptions {
  threshold: number;
  output?: string;
  type: TypeFilter;
  verbose: boolean;
}

function parseArgs(argv: string[]): ParsedOptions {
  const program = new Command();
  program
    .name("merge-duplicates")
    .exitOverride()
    .allowExcessArguments(true)
    .option("--threshold <n>", "cosine similarity threshold", "0.92")
    .option("--output <path>", "write markdown report to file")
    .option("--type <t>", "knowledge | tech_articles | weekly_issues | all", "all")
    .option("--verbose", "detailed logs", false);
  program.parse(argv, { from: "node" });
  const o = program.opts<{
    threshold?: string;
    output?: string;
    type?: string;
    verbose?: boolean;
  }>();
  const threshold = Number.parseFloat(o.threshold ?? "0.92");
  const typeStr = (o.type ?? "all") as TypeFilter;
  return {
    threshold: Number.isFinite(threshold) ? threshold : 0.92,
    output: o.output,
    type: typeStr,
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
  deps: MergeDuplicatesDeps,
): Promise<number> {
  let opts: ParsedOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    deps.streams.writeErr(
      `[merge-duplicates] argv parse error: ${(err as Error).message}`,
    );
    return 1;
  }

  const envCheck = validateEnv(deps.env);
  if (!envCheck.ok) {
    deps.streams.writeErr(
      `[merge-duplicates] required env missing: ${envCheck.missing.join(", ")}. Check .env (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).`,
    );
    return 1;
  }

  const verbose = (s: string) => {
    if (opts.verbose) deps.streams.write(s);
  };

  try {
    const client = deps.getSupabaseClient();
    verbose(`[merge-duplicates] fetching embeddings (type=${opts.type})`);
    const rows = await fetchAllEmbeddings(client, { type: opts.type });
    verbose(`[merge-duplicates] fetched ${rows.length} embeddings`);

    const rawPairs = await findDuplicatePairs(rows, opts.threshold);
    verbose(
      `[merge-duplicates] found ${rawPairs.length} candidate pairs (threshold=${opts.threshold})`,
    );

    const enriched = await enrichPairs(rawPairs, client);
    const report = formatReport(enriched);
    deps.streams.write(report);

    if (opts.output) {
      await deps.writeFile(opts.output, report);
      deps.streams.write(`[merge-duplicates] report written to ${opts.output}`);
    }
    return 0;
  } catch (err) {
    deps.streams.writeErr(
      `[merge-duplicates] unexpected error: ${(err as Error).message}`,
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
  const defaultDeps: MergeDuplicatesDeps = {
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
