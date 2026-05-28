/**
 * category-tag.ts — カテゴリ & タグの候補生成 / マスタ照合 / 対話確定 / INSERT
 *
 * 設計書 `docs/phase-8-posting-skill-design.md` L210-276, plan §8.E.4
 *
 * 公開 API:
 *   suggestCategory(input, { client, deps? })                 → Promise<CategorySuggestion>
 *   suggestTags(input, { client, deps? })                     → Promise<TagSuggestion[]>
 *   resolveTagAgainstMasters(candidates, client)              → Promise<ResolvedTags>
 *   confirmInteractively(args, { reader })                    → Promise<ConfirmedMeta>
 *
 * Phase 11 W11.3a: commitCategoryAndTags は削除（POST /api/ingest がサーバ側で処理）。
 *
 * 依存:
 *   - `extractCandidatesFromContent` (auto-tag.ts) — Haiku 抽出
 *   - `readline/promises` を `InteractiveReader` interface で抽象化し、テストから差し替え可能に
 *   - Supabase client は引数で受け取り、モジュール内で singleton には触らない
 *
 * マスタ照合の優先順位:
 *   1. tags.name 完全一致 → kind: 'existing'
 *   2. term_aliases.term 一致 (scope='tag') → kind: 'alias'
 *   3. search_tags_similar RPC で similarity > 0.75 → kind: 'similar'
 *   4. それ以外 → kind: 'new'
 *
 * 対話フロー (設計書 L247-276):
 *   [Y] すべて承認  [E] 個別編集  [S] 既存のみ  [N] キャンセル
 *   auto-approve:
 *     既存 && confidence > 0.8 → 採用
 *     新規 && confidence > 0.85 → 採用
 *     similar && confidence > 0.75 → 採用（寄せ）
 *   dry-run:
 *     提案の整形だけ行い INSERT しない
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  extractCandidatesFromContent,
  type AutoTagContentType,
  type AutoTagInput,
  type CategorySuggestion,
  type TagSuggestion,
} from "./auto-tag.js";
import type { CategoryAllowEntry } from "./category-allowlist.js";
import { postNewCategory as postNewCategoryFn } from "./category-admin.js";

// ---------------------------------------------------------------------------
// Re-exports from auto-tag (public API seam)
// ---------------------------------------------------------------------------

export type {
  CategorySuggestion,
  TagSuggestion,
  AutoTagContentType,
} from "./auto-tag.js";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export type ResolvedTag =
  | {
      kind: "existing";
      id: string;
      name: string;
      usageCount: number;
      confidence: number;
    }
  | {
      kind: "alias";
      alias: string;
      canonicalId: string;
      canonicalName: string;
      confidence: number;
    }
  | {
      kind: "similar";
      suggested: string;
      existingName: string;
      existingId: string;
      similarity: number;
      confidence: number;
    }
  | {
      kind: "new";
      name: string;
      confidence: number;
    };

export type ResolvedTags = ResolvedTag[];

export type ConfirmMode = "interactive" | "auto-approve" | "dry-run";

export interface ConfirmedMetaCategory {
  slug: string;
  name: string;
  isNew: boolean;
  id?: string;
}

export interface ConfirmedMetaTag {
  name: string;
  id?: string;
  isNew: boolean;
}

export interface ConfirmedMeta {
  committed: boolean;
  cancelled?: boolean;
  category: ConfirmedMetaCategory;
  tags: ConfirmedMetaTag[];
}

export interface CommittedMeta {
  categoryId: string | null;
  tagIds: string[];
}

export interface InteractiveReader {
  question(prompt: string): Promise<string>;
  close(): void;
}

export interface SuggestDeps {
  client: SupabaseClient;
  extract?: typeof extractCandidatesFromContent;
  /** 本リポ /api/content-categories から取得済の許可カテゴリーリスト (Wave 11.3e W3) */
  allowedCategories?: CategoryAllowEntry[];
  /** allowlist 違反時の挙動 (Wave 11.3e W3): 既定 'auto-approve' */
  mode?: ConfirmMode;
  /** interactive モードで三択 prompt を実行する reader */
  reader?: InteractiveReader;
  /** test 用注入: postNewCategory の実装差し替え */
  postNewCategory?: typeof postNewCategoryFn;
}

/** Wave 11.3e W3: allowlist 違反時にどの fallback で復帰したかのトレース */
export type CategoryFallback =
  | "none"
  | "second-pass"
  | "user-confirm"
  | "user-added";

export interface CategorySuggestionResult extends CategorySuggestion {
  fallbackUsed?: CategoryFallback;
}

export interface ConfirmArgs {
  category: CategorySuggestion;
  resolved: ResolvedTags;
  mode: ConfirmMode;
}

export interface ConfirmDeps {
  reader: InteractiveReader;
}

export interface CommitOptions {
  contentType: AutoTagContentType;
}

// ---------------------------------------------------------------------------
// DB enum conversion — content_categories.content_type CHECK constraint
// accepts 'issue' | 'article' | 'knowledge', but AutoTagContentType uses
// tableName format ('weekly_issues' | 'tech_articles' | 'knowledge').
// ---------------------------------------------------------------------------

export function toContentTypeEnum(
  tableName: AutoTagContentType,
): "issue" | "article" | "knowledge" {
  switch (tableName) {
    case "weekly_issues":
      return "issue";
    case "tech_articles":
      return "article";
    case "knowledge":
      return "knowledge";
    default: {
      // Exhaustiveness check — will catch new values at compile time.
      const _never: never = tableName;
      throw new Error(`toContentTypeEnum: unknown tableName: ${String(_never)}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Constants — thresholds are from design doc L271-274
// ---------------------------------------------------------------------------

const AUTO_APPROVE_EXISTING = 0.8;
const AUTO_APPROVE_NEW = 0.85;
const AUTO_APPROVE_SIMILAR = 0.75;

const TRGM_SIMILARITY_THRESHOLD = 0.75;

// ---------------------------------------------------------------------------
// Public API: suggestCategory
// ---------------------------------------------------------------------------

export async function suggestCategory(
  input: AutoTagInput,
  deps: SuggestDeps,
): Promise<CategorySuggestionResult> {
  const extract = deps.extract ?? extractCandidatesFromContent;
  const allow = deps.allowedCategories ?? [];

  // 1st pass — allowlist を Haiku プロンプトに埋め込んで extract
  const first = await extract(input, {
    allowedCategories: allow.length > 0 ? allow : undefined,
  });

  // 旧パス (allowlist 未提供) — 互換性維持の DB 照合のみ
  if (allow.length === 0) {
    return legacyDbMatch(first.category, input, deps);
  }

  // allowlist 内 → そのまま採用
  if (allow.some((c) => c.slug === first.category.slug)) {
    return { ...first.category, isNew: false, fallbackUsed: "none" };
  }

  // 2nd pass — 温度ゆらぎで違う slug を引き出す (LLM が allow を見直す機会)
  const second = await extract(input, { allowedCategories: allow });
  if (allow.some((c) => c.slug === second.category.slug)) {
    return { ...second.category, isNew: false, fallbackUsed: "second-pass" };
  }

  // 2 連続 miss — fallback B
  const mode = deps.mode ?? "auto-approve";
  if (mode === "auto-approve" || mode === "dry-run") {
    throw new Error(
      `suggestCategory: LLM returned non-allowlist slugs '${first.category.slug}' and '${second.category.slug}' in ${mode} mode. ` +
        `Re-run with --interactive to add a new category or pick an existing one.`,
    );
  }

  // interactive 三択
  if (!deps.reader) {
    throw new Error(
      "suggestCategory: interactive mode requires deps.reader (InteractiveReader)",
    );
  }
  return runCategoryThreeChoice({
    input,
    first: first.category,
    second: second.category,
    allow,
    reader: deps.reader,
    postNew: deps.postNewCategory ?? postNewCategoryFn,
  });
}

async function legacyDbMatch(
  category: CategorySuggestion,
  input: AutoTagInput,
  deps: SuggestDeps,
): Promise<CategorySuggestionResult> {
  // マスタ照合: content_categories.(content_type, slug) UNIQUE
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const chain = (deps.client as any)
    .from("content_categories")
    .select("id, slug, name, content_type")
    .eq("content_type", input.type)
    .eq("slug", category.slug);
  const { data, error } = await chain.maybeSingle();
  if (error) {
    throw new Error(
      `suggestCategory: supabase error: ${String((error as { message?: string }).message ?? error)}`,
    );
  }
  return {
    ...category,
    isNew: data == null,
  };
}

async function runCategoryThreeChoice(args: {
  input: AutoTagInput;
  first: CategorySuggestion;
  second: CategorySuggestion;
  allow: CategoryAllowEntry[];
  reader: InteractiveReader;
  postNew: typeof postNewCategoryFn;
}): Promise<CategorySuggestionResult> {
  const { input, first, second, allow, reader, postNew } = args;
  const enumType = toContentTypeEnum(input.type);
  const summary = [
    "",
    "[skill] LLM が許可リスト外の category を提案しました。",
    `        type      : ${input.type} (api enum: ${enumType})`,
    `        提案 slug : ${first.slug}${second.slug !== first.slug ? ` / ${second.slug}` : ""}`,
    `        提案 name : ${first.name}`,
    `        confidence: ${first.confidence.toFixed(2)}`,
    `        既存リスト: ${allow.map((c) => c.slug).join(" / ")}`,
    "",
    "どうしますか?",
    "  [1] 既存から選び直す",
    `  [2] 新規追加: type=${enumType}, slug='${first.slug}', name='${first.name}' を DB に登録`,
    "  [3] abort（投稿を中止）",
    "",
  ].join("\n");
  const choice = (await reader.question(`${summary}> `)).trim();

  if (choice === "3" || choice.toLowerCase() === "abort") {
    throw new Error("suggestCategory: aborted by user (choice=3)");
  }

  if (choice === "2") {
    // 新規追加 — POST /api/content-categories
    const created = await postNew({
      type: enumType,
      slug: first.slug,
      name: first.name,
      description: null,
    });
    return {
      slug: created.slug,
      name: created.name,
      confidence: first.confidence,
      isNew: false,
      fallbackUsed: "user-added",
    };
  }

  // choice === "1" — 既存から選び直す
  const list = allow
    .map((c, i) => `  [${i + 1}] ${c.slug} — ${c.name}`)
    .join("\n");
  const pickRaw = await reader.question(
    `${list}\n既存 slug 番号 (1-${allow.length}) > `,
  );
  const idx = Number.parseInt(pickRaw.trim(), 10) - 1;
  const picked = allow[idx];
  if (!picked) {
    throw new Error(
      `suggestCategory: invalid pick index '${pickRaw}' (allowed 1-${allow.length})`,
    );
  }
  return {
    slug: picked.slug,
    name: picked.name,
    confidence: 0.5,
    isNew: false,
    fallbackUsed: "user-confirm",
  };
}

// ---------------------------------------------------------------------------
// Public API: suggestTags
// ---------------------------------------------------------------------------

export async function suggestTags(
  input: AutoTagInput & { limit?: number },
  deps: SuggestDeps,
): Promise<TagSuggestion[]> {
  const extract = deps.extract ?? extractCandidatesFromContent;
  const { tags } = await extract(input);
  const limit = input.limit ?? 5;
  return tags.slice(0, limit);
}

// ---------------------------------------------------------------------------
// Public API: resolveTagAgainstMasters
// ---------------------------------------------------------------------------

export async function resolveTagAgainstMasters(
  candidates: TagSuggestion[],
  client: SupabaseClient,
): Promise<ResolvedTags> {
  const out: ResolvedTags = [];
  for (const cand of candidates) {
    const resolved = await resolveOne(cand, client);
    out.push(resolved);
  }
  return out;
}

async function resolveOne(
  cand: TagSuggestion,
  client: SupabaseClient,
): Promise<ResolvedTag> {
  // 1. Exact tags.name match.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const tagQ = (client as any)
    .from("tags")
    .select("id, name, usage_count")
    .eq("name", cand.name)
    .maybeSingle();
  const { data: exact, error: exactErr } = await tagQ;
  if (exactErr) {
    throw new Error(
      `resolveTagAgainstMasters: tags select error: ${String(
        (exactErr as { message?: string }).message ?? exactErr,
      )}`,
    );
  }
  if (exact) {
    const row = exact as { id: string; name: string; usage_count?: number };
    return {
      kind: "existing",
      id: row.id,
      name: row.name,
      usageCount: row.usage_count ?? 0,
      confidence: cand.confidence,
    };
  }

  // 2. term_aliases.term match (scope='tag') → canonical tag.
  // term_aliases unifies the legacy tag_aliases (scope='tag') and the
  // search synonym dictionary (scope='search'). For tag resolution we
  // MUST filter to scope='tag' so search-only synonyms don't leak in.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const aliasQ = (client as any)
    .from("term_aliases")
    .select("term, canonical, canonical_tag_id, scope")
    .eq("term", cand.name)
    .eq("scope", "tag")
    .maybeSingle();
  const { data: aliasRow } = await aliasQ;
  if (aliasRow) {
    const arow = aliasRow as {
      term: string;
      canonical: string;
      canonical_tag_id: string;
      scope: string;
    };
    // fetch canonical tag name (canonical_tag_id is REFERENCES tags(id))
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const canonQ = (client as any)
      .from("tags")
      .select("id, name")
      .eq("id", arow.canonical_tag_id)
      .maybeSingle();
    const { data: canon } = await canonQ;
    if (canon) {
      const crow = canon as { id: string; name: string };
      return {
        kind: "alias",
        alias: arow.term,
        canonicalId: crow.id,
        canonicalName: crow.name,
        confidence: cand.confidence,
      };
    }
  }

  // 3. pg_trgm similarity via RPC.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data: simRows } = await (client as any).rpc("search_tags_similar", {
    query: cand.name,
    threshold: TRGM_SIMILARITY_THRESHOLD,
  });
  if (Array.isArray(simRows) && simRows.length > 0) {
    // Take the top match if above threshold.
    const top = simRows[0] as {
      id: string;
      name: string;
      similarity: number;
    };
    if (typeof top.similarity === "number" && top.similarity > TRGM_SIMILARITY_THRESHOLD) {
      return {
        kind: "similar",
        suggested: cand.name,
        existingName: top.name,
        existingId: top.id,
        similarity: top.similarity,
        confidence: cand.confidence,
      };
    }
  }

  // 4. Fallback: brand new.
  return { kind: "new", name: cand.name, confidence: cand.confidence };
}

// ---------------------------------------------------------------------------
// Public API: confirmInteractively
// ---------------------------------------------------------------------------

export async function confirmInteractively(
  args: ConfirmArgs,
  deps: ConfirmDeps,
): Promise<ConfirmedMeta> {
  const { category, resolved, mode } = args;
  const categoryMeta: ConfirmedMetaCategory = {
    slug: category.slug,
    name: category.name,
    isNew: category.isNew ?? false,
  };

  if (mode === "dry-run") {
    return {
      committed: false,
      category: categoryMeta,
      tags: resolvedToMetaAll(resolved),
    };
  }

  if (mode === "auto-approve") {
    const accepted = resolved.filter(passesAutoApprove);
    return {
      committed: true,
      category: categoryMeta,
      tags: resolvedToMeta(accepted),
    };
  }

  // interactive
  return runInteractiveLoop(categoryMeta, resolved, deps.reader);
}

function passesAutoApprove(r: ResolvedTag): boolean {
  switch (r.kind) {
    case "existing":
    case "alias":
      return r.confidence > AUTO_APPROVE_EXISTING;
    case "new":
      return r.confidence > AUTO_APPROVE_NEW;
    case "similar":
      return r.confidence > AUTO_APPROVE_SIMILAR;
  }
}

async function runInteractiveLoop(
  category: ConfirmedMetaCategory,
  resolved: ResolvedTags,
  reader: InteractiveReader,
): Promise<ConfirmedMeta> {
  const answerRaw = (await reader.question(
    "[Y] すべて承認  [E] 個別編集  [S] 既存のみ  [N] キャンセル > ",
  ))
    .trim()
    .toUpperCase();

  if (answerRaw === "N") {
    return {
      committed: false,
      cancelled: true,
      category,
      tags: [],
    };
  }

  if (answerRaw === "Y") {
    return {
      committed: true,
      category,
      tags: resolvedToMetaAll(resolved),
    };
  }

  if (answerRaw === "S") {
    // "既存のみ" = existing + alias + similar（寄せによる既存採用）
    const picked = resolved.filter(
      (r) => r.kind === "existing" || r.kind === "alias" || r.kind === "similar",
    );
    return {
      committed: true,
      category,
      tags: resolvedToMeta(picked),
    };
  }

  if (answerRaw === "E") {
    const picked: ResolvedTag[] = [];
    for (const r of resolved) {
      const label = describeResolved(r);
      const yn = (await reader.question(`  採用しますか? (y/n) ${label}: `))
        .trim()
        .toLowerCase();
      if (yn === "y") picked.push(r);
    }
    return {
      committed: true,
      category,
      tags: resolvedToMeta(picked),
    };
  }

  // 不明入力はキャンセル扱い（安全側）
  return {
    committed: false,
    cancelled: true,
    category,
    tags: [],
  };
}

function describeResolved(r: ResolvedTag): string {
  switch (r.kind) {
    case "existing":
      return `✓ ${r.name} (既存, 使用 ${r.usageCount})`;
    case "alias":
      return `→ ${r.alias} ⇒ ${r.canonicalName} (エイリアス)`;
    case "similar":
      return `≈ ${r.suggested} → ${r.existingName} (類似 ${r.similarity.toFixed(2)})`;
    case "new":
      return `+ ${r.name} (新規)`;
  }
}

function resolvedToMetaAll(resolved: ResolvedTags): ConfirmedMetaTag[] {
  return resolvedToMeta(resolved);
}

function resolvedToMeta(resolved: ResolvedTags): ConfirmedMetaTag[] {
  const out: ConfirmedMetaTag[] = [];
  for (const r of resolved) {
    switch (r.kind) {
      case "existing":
        out.push({ name: r.name, id: r.id, isNew: false });
        break;
      case "alias":
        out.push({ name: r.canonicalName, id: r.canonicalId, isNew: false });
        break;
      case "similar":
        // 「寄せる」= 既存タグを採用
        out.push({ name: r.existingName, id: r.existingId, isNew: false });
        break;
      case "new":
        out.push({ name: r.name, isNew: true });
        break;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Default InteractiveReader factory — tests don't use this, production CLI does.
// Wrapped in a factory so importing this module does not eagerly open stdin.
// ---------------------------------------------------------------------------

export async function createDefaultReader(): Promise<InteractiveReader> {
  const readline = await import("readline/promises");
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return {
    question: (q: string) => rl.question(q),
    close: () => rl.close(),
  };
}
