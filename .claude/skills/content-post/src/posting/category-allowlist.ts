/**
 * category-allowlist.ts — 本リポ `/api/content-categories?type=...` から
 * 許可カテゴリー一覧を取得し、process-scoped memoize する。
 *
 * 設計書: classlab-weekly-news/docs/draft/category-validation-fail-fast.md §3 W2
 * 関連: classlab-weekly-news/docs/tasks/task-51-category-validation-fail-fast.md
 *
 * 役割:
 *   - LLM の category 自動分類が DB allowlist 外を出力するのを防ぐため、
 *     skill 起動時に許可リストを fetch して prompt に closed-enum を埋め込む。
 *   - 1 process で type ごとに 1 回の fetch しか行わない（Map memoize）。
 *   - 失敗 promise はキャッシュから除外し次回再試行を許可する（resilient cache）。
 *
 * 公開 API:
 *   - fetchAllowedCategories(type, deps?): Promise<CategoryAllowEntry[]>
 *   - fetchAllowedCategoriesForKind(kind, deps?): Promise<CategoryAllowEntry[]>
 *       — #58 Step 3: knowledge.kind 別 fail-fast filter
 *   - clearAllowlistCache(): void  — テスト用
 */

import type { KnowledgeKind } from "../../scripts/post-types.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface CategoryAllowEntry {
  slug: string;
  name: string;
  description: string | null;
}

/** 本リポ /api/content-categories が受け付ける content type enum */
export type AllowedContentType = "article" | "knowledge" | "issue";

// ---------------------------------------------------------------------------
// #58 Step 3: business-axis (事業軸) category 固定リスト
//
// operation / domain_knowledge は knowledge テーブルに格納されるが、category は
// 事業軸 2 件「空室通電 / ライフライン」のみを候補とする。これらは本リポ
// migration 20260527005417 で content_categories(content_type='operation' /
// 'domain_knowledge', slug='vacancy-energization' / 'lifeline') に seed 済み。
//
// GET /api/content-categories の許可 type は article|knowledge|issue のみで、
// operation/domain_knowledge type は fetch できない (route.ts ALLOWED_TYPES)。
// そのため tag-hearing.ts の master tag 定数と同じく seed と一致する定数を
// 単一真実源としてここに置く (DRY、fetch 不要 = fail-fast に強い)。
// ---------------------------------------------------------------------------

/** 事業軸 category — operation / domain_knowledge 共通の 2 件 (#57 seed と一致) */
// SSoT: 本番 migration 20260527005417 の content_categories seed と同期必須。category 追加時は migration + 本定数 + test の 3 箇所更新
export const BUSINESS_AXIS_CATEGORIES: readonly CategoryAllowEntry[] = [
  { slug: "vacancy-energization", name: "空室通電", description: null },
  { slug: "lifeline", name: "ライフライン", description: null },
] as const;

export interface FetchAllowedCategoriesDeps {
  /** test 用 fetch 注入。default は globalThis.fetch */
  fetch?: typeof globalThis.fetch;
  /** test 用 API base URL 注入。default は process.env.API_BASE_URL */
  apiBase?: string;
}

// ---------------------------------------------------------------------------
// Internal cache
// ---------------------------------------------------------------------------

const _cache = new Map<AllowedContentType, Promise<CategoryAllowEntry[]>>();

/** テスト用に process-scoped cache を全削除する */
export function clearAllowlistCache(): void {
  _cache.clear();
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function fetchAllowedCategories(
  type: AllowedContentType,
  deps: FetchAllowedCategoriesDeps = {},
): Promise<CategoryAllowEntry[]> {
  const cached = _cache.get(type);
  if (cached) return cached;

  const promise = (async (): Promise<CategoryAllowEntry[]> => {
    // 優先順位: deps.apiBase > SITE_URL > API_BASE_URL
    // `/api/content-categories` は本リポ classlab-weekly-news 側に実装されている
    // エンドポイントなので、サイト本体 URL (SITE_URL) を優先する。
    // API_BASE_URL は将来の独立 API サーバー用途のため fallback 扱い。
    // example.com 系のプレースホルダ値は捨てる。
    const candidates: (string | undefined)[] = [
      deps.apiBase,
      process.env.SITE_URL,
      process.env.API_BASE_URL,
    ];
    const apiBase = candidates.find(
      (v): v is string => typeof v === "string" && v.trim().length > 0 && !/\.example\.com\b/.test(v),
    );
    if (!apiBase) {
      throw new Error(
        "fetchAllowedCategories: SITE_URL / API_BASE_URL not set (env or deps.apiBase)",
      );
    }
    const url = `${apiBase.replace(/\/$/, "")}/api/content-categories?type=${encodeURIComponent(type)}`;
    const fetchImpl = deps.fetch ?? fetch;
    const res = await fetchImpl(url);
    if (!res.ok) {
      throw new Error(
        `fetchAllowedCategories: HTTP ${res.status} ${res.statusText} for type=${type}`,
      );
    }
    const body = (await res.json()) as {
      type?: string;
      categories?: CategoryAllowEntry[];
    };
    if (!body || !Array.isArray(body.categories)) {
      throw new Error(
        `fetchAllowedCategories: invalid response shape for type=${type}`,
      );
    }
    return body.categories;
  })();

  _cache.set(type, promise);

  // 失敗 promise はキャッシュから外し、次回呼び出しで再試行可能にする。
  // race-safe: 別の呼び出しが既に上書きしている可能性があるため同一性確認。
  promise.catch(() => {
    if (_cache.get(type) === promise) {
      _cache.delete(type);
    }
  });

  return promise;
}

/**
 * #58 Step 3: knowledge.kind 別の許可カテゴリーを返す。
 *
 *   - operation / domain_knowledge → 事業軸 2 件 (BUSINESS_AXIS_CATEGORIES)
 *     のみを候補とする。API fetch は行わない (seed 固定 = fail-fast)。
 *   - concept                      → 既存通り knowledge type の allowlist を
 *     API から fetch (動作不変、後方互換)。
 *
 * concept を knowledge へマップするのは、concept が
 * content_categories(content_type='knowledge') を参照するため
 * (本リポ migration trigger と整合)。
 *
 * #58 round-2 (M10) — 型を `KnowledgeKind` (非 undefined) に絞った。
 *   従来は `kind | undefined` を受け、undefined を concept と同じ allowlist 経路へ
 *   silent に吸わせていた。これだと将来 KnowledgeKind に新 kind を足したとき、
 *   呼び出し元の default 解決漏れ (undefined のまま渡す) が無音で concept 扱いになり
 *   気付けない。本シグネチャでは default 解決を **呼び出し元の責務** とし
 *   (`stage11CategoryTag.run` で `knowledgeKind ?? DEFAULT_KNOWLEDGE_KIND`)、
 *   ここに到達する値は必ず明示の KnowledgeKind になる。新 kind 追加時は本関数の
 *   分岐 (operation/domain_knowledge 判定) を見直す必要があり、漏れれば concept
 *   経路へ落ちる点は変わらないが、少なくとも「未指定 undefined の silent fallback」
 *   は型で排除される。
 */
export async function fetchAllowedCategoriesForKind(
  kind: KnowledgeKind,
  deps: FetchAllowedCategoriesDeps = {},
): Promise<CategoryAllowEntry[]> {
  if (kind === "operation" || kind === "domain_knowledge") {
    // 事業軸 2 件のみ。immutable な複製を返す (constant 共有汚染を防ぐ)。
    return BUSINESS_AXIS_CATEGORIES.map((c) => ({ ...c }));
  }
  // concept → knowledge allowlist (既存経路、動作不変)
  return fetchAllowedCategories("knowledge", deps);
}
