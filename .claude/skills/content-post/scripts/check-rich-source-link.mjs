#!/usr/bin/env node
/**
 * Count rich-source-link occurrences in knowledge body for given slugs.
 * Usage: node scripts/check-rich-source-link.mjs <slug1> [slug2 ...]
 */

import { createClient } from "@supabase/supabase-js";
import { config as loadDotenv } from "dotenv";

loadDotenv();

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const slugs = process.argv.slice(2);
const { data, error } = await supabase
  .from("knowledge")
  .select("slug, body")
  .in("slug", slugs);

if (error) {
  console.error("Error:", error);
  process.exit(1);
}

for (const r of data) {
  const matches = (r.body || "").match(/class="rich-source-link"/g);
  const count = matches ? matches.length : 0;
  console.log(`${r.slug}: rich-source-link count = ${count}`);
}
