#!/usr/bin/env tsx
/**
 * scripts/rollback.ts — コンテンツの任意バージョンへのロールバック CLI
 *
 * Usage:
 *   node scripts/rollback.ts --slug <slug> --to-version <N> [--dry-run] [--no-revalidate]
 *
 * Exit codes:
 *   0 — success (または dry-run 完了)
 *   1 — DB UPDATE 失敗
 *   2 — snapshot.html 不在 / 空
 */
import "dotenv/config";
import { Command } from "commander";
import { createClient } from "@supabase/supabase-js";
import {
  rollbackVersion,
  type RollbackVersionDeps,
} from "../src/posting/version-manager.js";
import { fileURLToPath } from "node:url";
import path from "node:path";

// ---------------------------------------------------------------------------
// Types (injectable for tests)
// ---------------------------------------------------------------------------

export interface RollbackDeps {
  rollbackVersion?: typeof rollbackVersion;
  updateContent?: (
    slug: string,
    opts: { body: string; rawMarkdown: string | null },
  ) => Promise<void>;
  revalidate?: () => Promise<void>;
  contentsDir?: string;
  streams?: {
    write: (line: string) => void;
    writeErr: (line: string) => void;
  };
  env?: Record<string, string | undefined>;
}

// ---------------------------------------------------------------------------
// defaultContentsDir
// ---------------------------------------------------------------------------

function defaultContentsDir(): string {
  const skillRoot = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    "..",
  );
  return path.join(skillRoot, "contents_manage", "contents");
}

// ---------------------------------------------------------------------------
// main (exported for tests)
// ---------------------------------------------------------------------------

export async function main(
  argv: string[],
  deps: RollbackDeps = {},
): Promise<number> {
  const streams = deps.streams ?? {
    write: (line: string) => console.log(line),
    writeErr: (line: string) => console.error(line),
  };

  const program = new Command();
  program
    .name("rollback")
    .description("任意バージョンの snapshot.html を DB に書き戻す")
    .option("--slug <slug>", "対象スラッグ")
    .option("--to-version <n>", "復元先バージョン番号", parseInt)
    .option("--dry-run", "DB を変更せず読み込み確認のみ", false)
    .option("--no-revalidate", "ISR revalidate をスキップ", false)
    .allowUnknownOption(true)
    .exitOverride();

  try {
    program.parse(argv);
  } catch {
    streams.writeErr("[rollback] argument parse error");
    return 1;
  }

  const opts = program.opts<{
    slug?: string;
    toVersion?: number;
    dryRun: boolean;
    revalidate: boolean;
  }>();

  if (!opts.slug) {
    streams.writeErr("[rollback] --slug is required");
    return 1;
  }
  if (!opts.toVersion || isNaN(opts.toVersion)) {
    streams.writeErr("[rollback] --to-version <n> is required (integer)");
    return 1;
  }

  const env = deps.env ?? (process.env as Record<string, string | undefined>);
  const contentsDir = deps.contentsDir ?? defaultContentsDir();

  // Build updateContent: DB update via Supabase
  let updateContentFn = deps.updateContent;
  if (!updateContentFn) {
    const supabaseUrl = env["SUPABASE_URL"] ?? env["NEXT_PUBLIC_SUPABASE_URL"];
    const supabaseKey = env["SUPABASE_SERVICE_ROLE_KEY"];
    if (!supabaseUrl || !supabaseKey) {
      streams.writeErr(
        "[rollback] SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required",
      );
      return 1;
    }
    const supabase = createClient(supabaseUrl, supabaseKey);

    updateContentFn = async (slug, { body, rawMarkdown }) => {
      // Try all three content tables
      for (const table of ["tech_articles", "weekly_issues", "knowledge"] as const) {
        const { data, error } = await supabase
          .from(table)
          .update({ body, ...(rawMarkdown !== null ? { raw_markdown: rawMarkdown } : {}) })
          .eq("slug", slug)
          .select("id")
          .maybeSingle();

        if (error) {
          throw new Error(`DB UPDATE failed on ${table}: ${error.message}`);
        }
        if (data) {
          // Found and updated
          return;
        }
      }
      throw new Error(`slug "${slug}" not found in any content table`);
    };
  }

  // Build revalidate
  let revalidateFn = deps.revalidate;
  if (!revalidateFn && !opts.dryRun && opts.revalidate) {
    const siteUrl = env["SITE_URL"];
    const secret = env["REVALIDATE_SECRET"];
    if (siteUrl && secret) {
      revalidateFn = async () => {
        const res = await fetch(`${siteUrl}/api/revalidate`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ secret, tags: [`slug:${opts.slug}`] }),
        });
        if (!res.ok) {
          throw new Error(`revalidate failed: ${res.status}`);
        }
      };
    }
  }

  const rollbackFn = deps.rollbackVersion ?? rollbackVersion;

  const rollbackDeps: RollbackVersionDeps = {
    contentsDir,
    updateContent: updateContentFn,
    revalidate: revalidateFn,
  };

  if (opts.dryRun) {
    streams.write(`[rollback] dry-run: slug=${opts.slug} to-version=${opts.toVersion}`);
  }

  try {
    const result = await rollbackFn(
      opts.slug,
      opts.toVersion,
      { dryRun: opts.dryRun, noRevalidate: !opts.revalidate },
      rollbackDeps,
    );

    if (opts.dryRun) {
      streams.write(
        `[rollback] dry-run complete: would rollback ${result.slug} from v${result.previousVersion} → v${result.rolledBackToVersion}`,
      );
    } else {
      streams.write(
        `[rollback] success: ${result.slug} rolled back from v${result.previousVersion} → v${result.rolledBackToVersion}`,
      );
    }
    return 0;
  } catch (err) {
    const e = err as Error & { exitCode?: number };
    streams.writeErr(`[rollback] ${e.message}`);
    return e.exitCode ?? 1;
  }
}

// ---------------------------------------------------------------------------
// CLI entrypoint
// ---------------------------------------------------------------------------

function isDirectInvocation(): boolean {
  try {
    if (typeof process === "undefined" || !process.argv[1]) return false;
    const scriptPath = fileURLToPath(import.meta.url);
    const invokedPath = path.resolve(process.argv[1]);
    return scriptPath === invokedPath || process.argv[1].endsWith("rollback.ts");
  } catch {
    return false;
  }
}

if (isDirectInvocation()) {
  main(process.argv).then((code) => process.exit(code));
}
