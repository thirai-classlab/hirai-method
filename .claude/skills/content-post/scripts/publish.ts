#!/usr/bin/env tsx
/**
 * scripts/publish.ts — Task #33 W4 スタンドアロン公開 CLI
 *
 * 使い方:
 *   # 単体公開
 *   node scripts/publish.ts --slug <slug> --type tech_article|issue|knowledge
 *
 *   # draft 一覧表示（Supabase 直読み）
 *   node scripts/publish.ts --pending --type tech_article
 *
 *   # draft 一括公開
 *   node scripts/publish.ts --pending --type tech_article --confirm
 *
 * 環境変数:
 *   BATCH_SECRET              — /api/publish 認証シークレット（必須）
 *   SUPABASE_URL              — --pending モード用（必須）
 *   SUPABASE_SERVICE_ROLE_KEY — --pending モード用（必須）
 *   CLASSLAB_WEEKLY_NEWS_API_URL — 任意。未設定時は本番 URL
 */
import "dotenv/config";
import { Command } from "commander";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { publishContent } from "../src/posting/publish-client.js";
import { createClient } from "@supabase/supabase-js";

interface PublishOptions {
  slug?: string;
  type?: string;
  pending: boolean;
  confirm: boolean;
  dryRun: boolean;
}

function parseArgs(argv: string[]): PublishOptions {
  const program = new Command();
  program
    .name("publish")
    .exitOverride()
    .allowExcessArguments(true)
    .option("--slug <slug>", "slug to publish")
    .option("--type <type>", "content type: tech_article | issue | knowledge")
    .option("--pending", "list (or publish with --confirm) all drafts of given --type", false)
    .option("--confirm", "with --pending: publish all listed drafts", false)
    .option("--dry-run", "with --pending --confirm: show what would be published without calling API", false);

  program.parse(argv, { from: "node" });
  const opts = program.opts<{
    slug?: string;
    type?: string;
    pending?: boolean;
    confirm?: boolean;
    dryRun?: boolean;
  }>();

  return {
    slug: opts.slug,
    type: opts.type,
    pending: !!opts.pending,
    confirm: !!opts.confirm,
    dryRun: !!opts.dryRun,
  };
}

function typeToTable(type: string): string {
  switch (type) {
    case "tech_article":
      return "tech_articles";
    case "issue":
      return "weekly_issues";
    case "knowledge":
    default:
      return "knowledge";
  }
}

function typeToKind(type: string): "tech_article" | "issue" | "knowledge" {
  if (type === "tech_article") return "tech_article";
  if (type === "issue") return "issue";
  return "knowledge";
}

async function run(argv: string[]): Promise<number> {
  let opts: PublishOptions;
  try {
    opts = parseArgs(argv);
  } catch (err) {
    process.stderr.write(`[publish] argv parse error: ${(err as Error).message}\n`);
    return 1;
  }

  // --- Single slug mode ---
  if (opts.slug && !opts.pending) {
    if (!opts.type) {
      process.stderr.write("[publish] --type is required when --slug is set\n");
      return 1;
    }
    const kind = typeToKind(opts.type);
    try {
      const result = await publishContent({ kind, slug: opts.slug });
      if (result.already_published) {
        process.stdout.write(`[publish] already published: ${opts.slug}\n`);
      } else {
        process.stdout.write(`[publish] published: ${opts.slug} at ${result.published_at}\n`);
      }
      return 0;
    } catch (err) {
      process.stderr.write(`[publish] error: ${(err as Error).message}\n`);
      return 1;
    }
  }

  // --- Pending mode ---
  if (opts.pending) {
    if (!opts.type) {
      process.stderr.write("[publish] --type is required with --pending\n");
      return 1;
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      process.stderr.write(
        "[publish] SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required for --pending mode\n",
      );
      return 1;
    }

    const table = typeToTable(opts.type);
    const client = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await client
      .from(table)
      .select("slug")
      .is("published_at", null)
      .order("created_at", { ascending: true });

    if (error) {
      process.stderr.write(`[publish] supabase query failed: ${error.message}\n`);
      return 1;
    }

    const drafts: Array<{ slug: string }> = data ?? [];
    if (drafts.length === 0) {
      process.stdout.write(`[publish] no drafts found in ${table}\n`);
      return 0;
    }

    process.stdout.write(`[publish] ${drafts.length} draft(s) in ${table}:\n`);
    for (const d of drafts) {
      process.stdout.write(`  - ${d.slug}\n`);
    }

    if (!opts.confirm) {
      process.stdout.write("[publish] use --confirm to publish all listed drafts\n");
      return 0;
    }

    // Publish each draft
    const kind = typeToKind(opts.type);
    let okCount = 0;
    let failCount = 0;
    for (const d of drafts) {
      if (opts.dryRun) {
        process.stdout.write(`[publish] (dry-run) would publish: ${d.slug}\n`);
        okCount++;
        continue;
      }
      try {
        const result = await publishContent({ kind, slug: d.slug });
        if (result.already_published) {
          process.stdout.write(`[publish] already published: ${d.slug}\n`);
        } else {
          process.stdout.write(`[publish] published: ${d.slug} at ${result.published_at}\n`);
        }
        okCount++;
      } catch (err) {
        process.stderr.write(`[publish] failed ${d.slug}: ${(err as Error).message}\n`);
        failCount++;
      }
    }
    process.stdout.write(
      `[publish] complete: ${okCount} ok / ${failCount} failed / ${drafts.length} total\n`,
    );
    return failCount > 0 ? 1 : 0;
  }

  process.stderr.write("[publish] --slug <slug> --type <type> or --pending --type <type> is required\n");
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
  run(process.argv).then((code) => process.exit(code));
}

export { run, parseArgs };
