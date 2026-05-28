#!/usr/bin/env tsx
/**
 * scripts/seed-contents-manage.ts — One-time migration: v1 遡及保存
 *
 * 既存 6 記事 (tech_articles + weekly_issues + knowledge) の DB コンテンツを
 * contents_manage/contents/{slug}/v1/ に保存し、meta.json を初期化する。
 *
 * Usage:
 *   npx tsx scripts/seed-contents-manage.ts
 *   npx tsx scripts/seed-contents-manage.ts --dry-run   # DB fetch のみ、ファイル書き込みなし
 *
 * 実行条件:
 *   - .env に SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY が設定済み
 *   - 複数回実行しても安全 (既存 meta.json は上書きせず skip)
 */
import "dotenv/config";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { getSupabaseClient } from "../src/lib/supabase.js";
import type { ContentKind } from "../src/posting/version-manager.js";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const SKILL_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const CONTENTS_DIR = path.join(SKILL_ROOT, "contents_manage", "contents");

interface SeedTarget {
  slug: string;
  table: "tech_articles" | "weekly_issues" | "knowledge";
  kind: ContentKind;
}

const SEED_TARGETS: SeedTarget[] = [
  {
    slug: "claude-code-vercel-ai-gateway-image-generation",
    table: "tech_articles",
    kind: "tech_article",
  },
  {
    slug: "weekly-news-summary-2026-04-10-16",
    table: "weekly_issues",
    kind: "weekly_issue",
  },
  {
    slug: "weekly-news-summary-2026-04-14-21",
    table: "weekly_issues",
    kind: "weekly_issue",
  },
  {
    slug: "weekly-news-summary-2026-04-18-25",
    table: "weekly_issues",
    kind: "weekly_issue",
  },
  {
    slug: "vercel-ai-gateway-unified-access",
    table: "knowledge",
    kind: "knowledge",
  },
  {
    slug: "skillsh-claude-code-npx-skills-add-1-cli",
    table: "knowledge",
    kind: "knowledge",
  },
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type SupabaseRow = Record<string, unknown>;

async function fetchRow(
  table: string,
  slug: string,
): Promise<SupabaseRow | null> {
  const client = getSupabaseClient();
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => {
        eq: (c: string, v: unknown) => {
          maybeSingle: () => Promise<{
            data: SupabaseRow | null;
            error: { message: string } | null;
          }>;
        };
      };
    };
  };
  const { data, error } = await c
    .from(table)
    .select("*")
    .eq("slug", slug)
    .maybeSingle();
  if (error) throw new Error(`fetchRow(${table}, ${slug}): ${error.message}`);
  return data;
}

function toBodyString(row: SupabaseRow): string {
  const body = row["body"] ?? row["html"] ?? "";
  return typeof body === "string" ? body : "";
}

function toRawMarkdown(row: SupabaseRow): string | null {
  const rm = row["raw_markdown"];
  return typeof rm === "string" ? rm : null;
}

function toTitle(row: SupabaseRow): string {
  const t = row["title"];
  return typeof t === "string" && t.length > 0 ? t : "(no title)";
}

function toPublishedAt(row: SupabaseRow): string | undefined {
  const pa = row["published_at"];
  return typeof pa === "string" ? pa : undefined;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function seed(dryRun: boolean): Promise<void> {
  const now = new Date().toISOString();
  console.log(`[seed-contents-manage] start. dryRun=${dryRun}`);
  console.log(`[seed-contents-manage] CONTENTS_DIR: ${CONTENTS_DIR}`);

  if (!dryRun) {
    await fs.mkdir(CONTENTS_DIR, { recursive: true });
  }

  let seeded = 0;
  let skipped = 0;
  let missing = 0;

  for (const target of SEED_TARGETS) {
    const slugDir = path.join(CONTENTS_DIR, target.slug);
    const metaPath = path.join(slugDir, "meta.json");

    // --- Skip if meta.json already exists (idempotent) ---
    try {
      await fs.access(metaPath);
      console.log(`  [skip] ${target.slug} — meta.json already exists`);
      skipped++;
      continue;
    } catch {
      // not exists, proceed
    }

    // --- Fetch from DB ---
    console.log(`  [fetch] ${target.table}.${target.slug}`);
    let row: SupabaseRow | null;
    try {
      row = await fetchRow(target.table, target.slug);
    } catch (err) {
      console.error(`  [error] ${target.slug}: ${(err as Error).message}`);
      missing++;
      continue;
    }

    if (!row) {
      console.warn(`  [warn] ${target.slug}: not found in ${target.table} — skipping`);
      missing++;
      continue;
    }

    const body = toBodyString(row);
    const rawMarkdown = toRawMarkdown(row);
    const title = toTitle(row);
    const publishedAt = toPublishedAt(row);

    if (!dryRun) {
      // --- Write v1 files ---
      const v1Dir = path.join(slugDir, "v1");
      await fs.mkdir(v1Dir, { recursive: true });

      await fs.writeFile(path.join(v1Dir, "snapshot.html"), body, "utf-8");

      if (rawMarkdown !== null) {
        await fs.writeFile(path.join(v1Dir, "post.md"), rawMarkdown, "utf-8");
      } else {
        console.warn(`  [warn] ${target.slug}: raw_markdown is NULL in DB — post.md not written`);
      }

      // --- Write meta.json ---
      const meta = {
        slug: target.slug,
        kind: target.kind,
        title,
        current_version: 1,
        published_version: 1,
        published_at: publishedAt,
        versions: [
          {
            v: 1,
            created_at: now,
            author: "task-41-seed",
            snapshot_taken: true,
            note: "v1 = 復旧後の現状サイト内容 (画像復旧済)",
          },
        ],
      };

      await fs.writeFile(metaPath, JSON.stringify(meta, null, 2) + "\n", "utf-8");

      console.log(
        `  [ok] ${target.slug} — v1 saved (body=${body.length} chars, md=${rawMarkdown?.length ?? "NULL"} chars)`,
      );
    } else {
      console.log(
        `  [dry-run] ${target.slug} — would save v1 (body=${body.length} chars, md=${rawMarkdown?.length ?? "NULL"} chars, title="${title}")`,
      );
    }
    seeded++;
  }

  console.log(
    `\n[seed-contents-manage] done. seeded=${seeded}, skipped=${skipped}, missing=${missing}`,
  );
  if (missing > 0) {
    console.error(`[seed-contents-manage] WARNING: ${missing} slug(s) not found in DB`);
    process.exit(1);
  }
}

const dryRun = process.argv.includes("--dry-run");
seed(dryRun).catch((err) => {
  console.error(`[seed-contents-manage] fatal: ${(err as Error).message}`);
  process.exit(2);
});
