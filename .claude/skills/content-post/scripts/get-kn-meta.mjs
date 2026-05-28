#!/usr/bin/env node
/**
 * Fetch knowledge meta + raw_markdown for given slugs.
 * Usage: node scripts/get-kn-meta.mjs <slug1> [slug2 ...]
 */

import { createClient } from "@supabase/supabase-js";
import { config as loadDotenv } from "dotenv";

loadDotenv();

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const supabase = createClient(url, key, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const slugs = process.argv.slice(2);
if (slugs.length === 0) {
  console.error("Usage: node scripts/get-kn-meta.mjs <slug1> [slug2 ...]");
  process.exit(1);
}

const { data, error } = await supabase
  .from("knowledge")
  .select("*")
  .in("slug", slugs);

if (error) {
  console.error("Error:", error);
  process.exit(1);
}

console.log(JSON.stringify(data, null, 2));
