/**
 * slug.ts — slug 生成と DB 衝突回避
 *
 * 設計書 `docs/phase-8-posting-skill-design.md` Step 3、plan §8.E.2
 *
 * 公開 API:
 *   generateSlug(title, type)           → Promise<string>   (slugify + Haiku fallback)
 *   checkSlugCollision(slug, type, db)  → Promise<boolean>
 *   ensureUniqueSlug(base, type, db)    → Promise<string>   (-2, -3, ... を付与)
 *   normalizeSlug(raw)                  → string            (小文字化・連続ハイフン除去・80 文字 trim)
 *
 * 衝突回避の最大試行回数は 20。越えた場合は error。
 */

import { SlugConflictError } from "./slug-errors.js";
import type { SupabaseClient } from "@supabase/supabase-js";
import slugifyLib from "slugify";
import { runLLM } from "../lib/llm.js";
import type { PostingContentType } from "./validate.js";

// slugify lives as a CJS default-export; `slugifyLib` is the callable function.
const slugify = slugifyLib as unknown as (
  input: string,
  opts?: { lower?: boolean; strict?: boolean; trim?: boolean },
) => string;

const SLUG_MAX = 80;
const SLUG_MIN = 3;
const MAX_COLLISION_ATTEMPTS = 20;

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

/**
 * 入力文字列を slug-safe な形に正規化する
 *   - 小文字化
 *   - 英数字・ハイフン以外を除去
 *   - 連続ハイフンを 1 個に畳む
 *   - 先頭末尾のハイフンを除去
 *   - 80 文字で切り詰め（切り詰め後も末尾ハイフンを除去）
 */
export function normalizeSlug(raw: string): string {
  const lowered = raw.toLowerCase();
  const dashed = lowered
    .replace(/[^a-z0-9-]+/g, "-") // unsafe → hyphen
    .replace(/-+/g, "-") // collapse
    .replace(/^-+|-+$/g, ""); // trim edges
  if (dashed.length <= SLUG_MAX) return dashed;
  return dashed.slice(0, SLUG_MAX).replace(/-+$/g, "");
}

/** posting の複数形 → Supabase テーブル名（plan に準拠、そのまま複数形を採用） */
function tableNameFor(type: PostingContentType): string {
  return type; // knowledge / tech_articles / weekly_issues は全て複数形でテーブル名と一致
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * タイトル → slug を生成。
 *   1. `slugify(title, { lower, strict })` を試行
 *   2. 結果が空 or 3 文字未満なら Haiku (`runLLM({ kind: 'slug' })`) にフォールバック
 *   3. 最後に normalizeSlug で整形して返す
 */
export async function generateSlug(
  title: string,
  type: PostingContentType,
): Promise<string> {
  const asciiCandidate = slugify(title, {
    lower: true,
    strict: true,
    trim: true,
  });

  const normalized = normalizeSlug(asciiCandidate);

  // Usable if non-empty AND the slugifier preserved most of the title's
  // semantic signal. Titles dominated by CJK/non-ASCII collapse hard — e.g.
  // "Next.js 16 のキャッシュコンポーネント入門" → "nextjs-16", which loses the
  // topical phrase and should go through Haiku instead.
  const titleNonSpaceLen = title.replace(/\s+/g, "").length;
  const kept = normalized.replace(/-/g, "").length;
  const retentionOk = titleNonSpaceLen === 0 || kept / titleNonSpaceLen >= 0.5;

  if (normalized.length >= SLUG_MIN && retentionOk) return normalized;

  // Haiku fallback for titles that produce no / too-short ASCII slug.
  const prompt = [
    `次のタイトルに対し、3〜60 文字の英小文字・数字・ハイフンのみで構成される短い slug を提案してください。説明や装飾は不要で、slug 1 行のみ出力してください。`,
    `タイトル: ${title}`,
    `コンテンツ種別: ${type}`,
  ].join("\n");

  const result = await runLLM({
    kind: "slug",
    prompt,
    maxOutputTokens: 30,
    temperature: 0.2,
  });
  const candidate = normalizeSlug(result.text.split(/\r?\n/)[0]!.trim());
  if (candidate.length < SLUG_MIN) {
    throw new Error(
      `generateSlug: Haiku produced unusable slug "${result.text}" for title "${title}"`,
    );
  }
  return candidate;
}

/**
 * 指定 slug が該当テーブルに存在するかを検査。
 * `.from(table).select('slug').eq('slug', slug).maybeSingle()` の単純クエリ。
 */
export async function checkSlugCollision(
  slug: string,
  type: PostingContentType,
  client: SupabaseClient,
): Promise<boolean> {
  const table = tableNameFor(type);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const chain = (client as any).from(table).select("slug").eq("slug", slug);
  const { data, error } = await chain.maybeSingle();
  if (error) {
    throw new Error(
      `checkSlugCollision: supabase error on ${table}: ${String((error as { message?: string }).message ?? error)}`,
    );
  }
  return data != null;
}

/**
 * 衝突した場合 `-2`, `-3`, ... を付与してユニークな slug を返す。
 * 20 回試行しても空かないときは throw。
 *
 * @deprecated 暗黙の suffix 採番は本番でのデータ取り違えにつながるため新規呼び出しは
 *   避け、{@link assertSlugAvailable} を使って衝突時は SlugConflictError を投げる方針
 *   へ移行する。本関数は後方互換のため残置。
 */
export async function ensureUniqueSlug(
  base: string,
  type: PostingContentType,
  client: SupabaseClient,
): Promise<string> {
  const normalized = normalizeSlug(base);
  if (normalized.length < SLUG_MIN) {
    throw new Error(
      `ensureUniqueSlug: base slug "${base}" normalized to "${normalized}" (too short)`,
    );
  }

  if (!(await checkSlugCollision(normalized, type, client))) {
    return normalized;
  }

  for (let i = 2; i <= MAX_COLLISION_ATTEMPTS; i++) {
    const suffix = `-${i}`;
    const body = normalized.length + suffix.length > SLUG_MAX
      ? normalized.slice(0, SLUG_MAX - suffix.length).replace(/-+$/g, "")
      : normalized;
    const candidate = `${body}${suffix}`;
    if (!(await checkSlugCollision(candidate, type, client))) {
      return candidate;
    }
  }

  throw new Error(
    `ensureUniqueSlug: exceeded ${MAX_COLLISION_ATTEMPTS} attempts for base "${normalized}" on ${type}`,
  );
}

// ---------------------------------------------------------------------------
// fail-loud collision guard (new): use this instead of ensureUniqueSlug
// ---------------------------------------------------------------------------

// Re-exported from slug-errors.ts so api-client.ts can throw SlugConflictError
// without pulling in this module's slugify / llm.ts (dotenv side-effect) chain.
export { SlugConflictError } from "./slug-errors.js";

/**
 * Assert that `slug` is available on the table for `contentType`.
 *
 * Unlike {@link ensureUniqueSlug}, this does not auto-append `-2..-20`. On
 * collision it throws {@link SlugConflictError} so the caller can surface a
 * clear error and let the operator choose: `--update <slug>`, set a different
 * `slug:` in frontmatter, or delete the existing row.
 *
 * Probes `from(table).select('id').eq('slug', slug).maybeSingle()` so the
 * existing row's id (when present) is attached to the thrown error.
 */
export async function assertSlugAvailable(
  slug: string,
  contentType: PostingContentType,
  client: SupabaseClient,
): Promise<void> {
  const table = tableNameFor(contentType);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const chain = (client as any).from(table).select("id").eq("slug", slug);
  const { data, error } = await chain.maybeSingle();
  if (error) {
    throw new Error(
      `assertSlugAvailable: supabase error on ${table}: ${String((error as { message?: string }).message ?? error)}`,
    );
  }
  if (data == null) return;
  const existingId =
    typeof (data as { id?: unknown }).id === "string"
      ? ((data as { id: string }).id)
      : undefined;
  throw new SlugConflictError(slug, contentType, existingId);
}
