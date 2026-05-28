import "dotenv/config";
import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set");
  process.exit(1);
}

const client = createClient(url, key);

interface Category {
  id: string;
  slug: string;
  name: string;
  content_type: string;
}

async function main(): Promise<void> {
  const slug = "claude-code";
  const name = "Claude Code";
  const contentType = "article";

  const { data: existing } = await client
    .from("content_categories")
    .select("id, slug, name, content_type")
    .eq("content_type", contentType)
    .eq("slug", slug)
    .maybeSingle<Category>();

  if (existing) {
    console.log(`[skip] already exists: ${existing.slug} (${existing.id})`);
    return;
  }

  const { data, error } = await client
    .from("content_categories")
    .insert({ content_type: contentType, slug, name })
    .select("id, slug, name, content_type")
    .single<Category>();

  if (error) {
    console.error(`[error] ${error.message}`);
    process.exit(1);
  }

  console.log(`[ok] inserted: ${data.slug} / ${data.name} (id=${data.id})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
