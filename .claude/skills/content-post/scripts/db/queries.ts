/**
 * scripts/db/queries.ts — Task #56 W1 (11.3d-A)
 *
 * DB query helpers extracted from scripts/post.ts during the 14-stage
 * pipeline refactor. All four functions wrap supabase-js calls with
 * the same minimal structural-type narrowing used inline in the original
 * post.ts, so callers can keep injecting any object that conforms to
 * that shape.
 *
 * Design intent (動作保存):
 *   - Same signatures, same SQL semantics, same error-message format
 *     ("updateMainContent(${table}) failed: ${msg}" etc.) as the
 *     pre-extraction post.ts definitions.
 *   - upsertEmbedding still relies on toEmbeddingEnum() for the same
 *     content_type narrowing — imported from sibling helpers/.
 *   - Draft: classlab-weekly-news/docs/draft/post-ts-reduction.md §3 W1.
 */

import { toEmbeddingEnum } from "../helpers/type-mapping.js";

export async function fetchBySlug(
  client: unknown,
  table: string,
  slug: string,
): Promise<Record<string, unknown> | null> {
  const c = client as {
    from: (t: string) => {
      select: (cols?: string) => {
        eq: (c: string, v: unknown) => {
          maybeSingle: () => Promise<{
            data: Record<string, unknown> | null;
            error: unknown;
          }>;
        };
      };
    };
  };
  const { data } = await c.from(table).select("*").eq("slug", slug).maybeSingle();
  return data ?? null;
}

export async function updateMainContent(
  client: unknown,
  table: string,
  id: string,
  row: {
    title: string;
    body: string;
    html: string;
    summary?: string;
    periodStart?: string;
    periodEnd?: string;
    thumbnailUrl?: string | null;
    thumbnailAlt?: string | null;
  },
): Promise<void> {
  const c = client as {
    from: (t: string) => {
      update: (r: unknown) => {
        eq: (
          col: string,
          val: unknown,
        ) => Promise<{ data: unknown; error: unknown }>;
      };
    };
  };
  // body = rendered HTML, raw_markdown = source MD. Same mapping as insert.
  const updateRow: Record<string, unknown> = {
    title: row.title,
    body: row.html,
    raw_markdown: row.body,
  };
  // #bug fix: summary was previously stuck at the v1 value because update path
  // did not write the summary column. Re-derive on update so changes to body
  // (image removal, structural rewrites) propagate to the OG / preview text.
  // Wave 48.4 fix: weekly_issues has NO summary column — guard against schema
  // mismatch ("Could not find the 'summary' column of 'weekly_issues'").
  if (
    typeof row.summary === "string" &&
    row.summary.length > 0 &&
    table !== "weekly_issues"
  ) {
    updateRow.summary = row.summary;
  }
  // Only weekly_issues has period_start / period_end columns.
  if (table === "weekly_issues") {
    if (row.periodStart) updateRow.period_start = row.periodStart;
    if (row.periodEnd) updateRow.period_end = row.periodEnd;
  }
  // #30 fix: thumbnail columns flow through on UPDATE the same way they do on INSERT.
  // Only write when we have a non-null URL so we never clobber an existing thumbnail
  // with null when the frontmatter happens to omit the field.
  if (row.thumbnailUrl) {
    updateRow.thumbnail_url = row.thumbnailUrl;
  }
  if (row.thumbnailAlt !== undefined) {
    updateRow.thumbnail_alt = row.thumbnailAlt;
  }
  const res = await c
    .from(table)
    .update(updateRow)
    .eq("id", id);
  const error = (res as { error?: unknown })?.error;
  if (error) {
    const msg =
      (error as { message?: string })?.message ?? JSON.stringify(error);
    throw new Error(`updateMainContent(${table}) failed: ${msg}`);
  }
}

export async function updateHtml(
  client: unknown,
  table: string,
  id: string,
  html: string,
): Promise<void> {
  const c = client as {
    from: (t: string) => {
      update: (r: unknown) => {
        eq: (
          col: string,
          val: unknown,
        ) => Promise<{ data: unknown; error: unknown }>;
      };
    };
  };
  // The rendered-HTML column is `body`, not `html`.
  const res = await c.from(table).update({ body: html }).eq("id", id);
  const error = (res as { error?: unknown })?.error;
  if (error) {
    const msg =
      (error as { message?: string })?.message ?? JSON.stringify(error);
    throw new Error(`updateHtml(${table}) failed: ${msg}`);
  }
}

export async function upsertEmbedding(
  client: unknown,
  row: {
    contentType: string;
    contentId: string;
    embedding: number[];
    model?: string;
  },
): Promise<void> {
  const c = client as {
    from: (t: string) => {
      upsert: (
        r: unknown,
        o?: unknown,
      ) => Promise<{ data: unknown; error: unknown }>;
    };
  };
  // Same enum conversion as insertEmbedding.
  // The DB UNIQUE constraint is (content_type, content_id, model) — 3 columns.
  // ON CONFLICT target MUST match the unique constraint exactly, so we
  // always set `model` on the row and pass the 3-column onConflict string.
  // See classlab-weekly-news commit e5a7ca5 (W2e fix for Edge Function) for
  // the same root cause and resolution in the Augment Edge Function path.
  const model = row.model ?? "text-embedding-3-large";
  const res = await c.from("content_embeddings").upsert(
    {
      content_type: toEmbeddingEnum(row.contentType),
      content_id: row.contentId,
      embedding: row.embedding,
      model,
    },
    { onConflict: "content_type,content_id,model" },
  );
  const error = (res as { error?: unknown })?.error;
  if (error) {
    const msg =
      (error as { message?: string })?.message ?? JSON.stringify(error);
    throw new Error(`upsertEmbedding failed: ${msg}`);
  }
}
