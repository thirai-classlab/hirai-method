#!/usr/bin/env node
/**
 * For each published slug across weekly_issues / tech_articles / knowledge,
 * fetch raw_markdown + metadata from Supabase, synthesize a frontmatter,
 * and write /tmp/classlab-rebuilds/<slug>.md so post.ts --update can re-render.
 *
 * Source of body: DB raw_markdown (preserves any --update after v1).
 * Frontmatter: minimum required by validateInput.
 */
import fs from "node:fs";
import path from "node:path";
import { createClient } from "@supabase/supabase-js";
import dotenv from "dotenv";

// Load 雑務 env
dotenv.config({
  path: "/Users/t.hirai/work/雑務/.claude/skills/content-post/.env",
});

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in env");
  process.exit(1);
}
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const OUT_DIR = "/tmp/classlab-rebuilds";
fs.mkdirSync(OUT_DIR, { recursive: true });

const TABLES = [
  {
    table: "weekly_issues",
    type: "weekly_issues",
    fields:
      "slug, title, raw_markdown, period_start, period_end, thumbnail_url, thumbnail_alt, source_urls, template_version",
  },
  {
    table: "tech_articles",
    type: "tech_articles",
    fields:
      "slug, title, raw_markdown, category, summary, author, difficulty, thumbnail_url, thumbnail_alt, source_urls, template_version",
  },
  {
    table: "knowledge",
    type: "knowledge",
    fields:
      "slug, title, raw_markdown, category, summary, author, thumbnail_url, thumbnail_alt, source_urls, template_version",
  },
];

function yamlEscape(v) {
  if (v == null) return "";
  if (typeof v === "string") {
    // Always quote to be safe against ":" and Japanese.
    return JSON.stringify(v);
  }
  return String(v);
}

function buildFrontmatter(row, type) {
  const lines = ["---"];
  lines.push(`title: ${yamlEscape(row.title)}`);
  lines.push(`type: ${type}`);
  lines.push(`slug: ${row.slug}`);
  if (type === "tech_articles") {
    // post.ts validate.ts requires subtype for tech_articles.
    // DB column is `category` which holds the subtype value.
    const subtype = row.category || "deepdive";
    lines.push(`subtype: ${subtype}`);
    if (row.category) lines.push(`category: ${row.category}`);
  } else if (type === "knowledge") {
    if (row.category) lines.push(`category: ${row.category}`);
  }
  if (row.summary) lines.push(`summary: ${yamlEscape(row.summary)}`);
  if (row.author) lines.push(`author: ${yamlEscape(row.author)}`);
  if (row.difficulty) lines.push(`difficulty: ${row.difficulty}`);
  if (row.thumbnail_url) lines.push(`thumbnail: ${yamlEscape(row.thumbnail_url)}`);
  if (row.thumbnail_alt) lines.push(`thumbnail_alt: ${yamlEscape(row.thumbnail_alt)}`);
  if (row.period_start) lines.push(`period_start: ${row.period_start.split("T")[0].split(" ")[0]}`);
  if (row.period_end) lines.push(`period_end: ${row.period_end.split("T")[0].split(" ")[0]}`);
  if (row.template_version) lines.push(`template_version: ${row.template_version}`);
  if (row.source_urls && Array.isArray(row.source_urls) && row.source_urls.length > 0) {
    lines.push(`source_urls:`);
    for (const u of row.source_urls) lines.push(`  - ${yamlEscape(u)}`);
  }
  lines.push("---");
  return lines.join("\n");
}

const results = [];
for (const t of TABLES) {
  const { data, error } = await supabase
    .from(t.table)
    .select(t.fields)
    .not("published_at", "is", null);
  if (error) {
    console.error(`fetch ${t.table} failed:`, error.message);
    process.exit(1);
  }
  for (const row of data) {
    if (!row.raw_markdown || row.raw_markdown.length === 0) {
      console.error(`SKIP ${row.slug}: empty raw_markdown`);
      continue;
    }
    const fm = buildFrontmatter(row, t.type);
    const md = `${fm}\n\n${row.raw_markdown}`;
    const outPath = path.join(OUT_DIR, `${row.slug}.md`);
    fs.writeFileSync(outPath, md, "utf-8");
    results.push({
      type: t.type,
      slug: row.slug,
      path: outPath,
      bytes: md.length,
    });
    console.log(`OK ${t.type.padEnd(15)} ${row.slug.padEnd(55)} bytes=${md.length}`);
  }
}

const summaryPath = path.join(OUT_DIR, "_index.json");
fs.writeFileSync(summaryPath, JSON.stringify(results, null, 2));
console.log(`\nWrote ${results.length} files to ${OUT_DIR}`);
console.log(`Index: ${summaryPath}`);
