/**
 * category-admin.ts — `POST /api/content-categories` 経由で新規カテゴリーを
 * DB に登録する admin 操作 (Wave 11.3e W3)。
 *
 * 設計書: classlab-weekly-news/docs/draft/category-validation-fail-fast.md §3 W3
 *
 * 役割:
 *   - interactive モードで user が「新規追加」を選んだとき、本リポ admin endpoint
 *     を Authorization Bearer で呼んで category を作る。
 *   - 409 (race / 既存) は existing 行を取り出して冪等継続できるよう raise しない。
 *   - 失敗時は呼び出し側で catch して user に手当ての機会を与える。
 *
 * 公開 API:
 *   - postNewCategory(body, deps?): Promise<CategoryAllowEntry>
 */

import type {
  AllowedContentType,
  CategoryAllowEntry,
} from "./category-allowlist.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface PostNewCategoryBody {
  type: AllowedContentType;
  slug: string;
  name: string;
  description?: string | null;
}

export interface PostNewCategoryDeps {
  /** test 用 fetch 注入 */
  fetch?: typeof globalThis.fetch;
  /** test 用 API base URL 注入 */
  apiBase?: string;
  /** test 用 Bearer secret 注入 */
  secret?: string;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function postNewCategory(
  body: PostNewCategoryBody,
  deps: PostNewCategoryDeps = {},
): Promise<CategoryAllowEntry> {
  const apiBase = deps.apiBase ?? process.env.API_BASE_URL;
  const secret = deps.secret ?? process.env.CATEGORY_ADMIN_SECRET;
  if (!apiBase) {
    throw new Error("postNewCategory: API_BASE_URL not set");
  }
  if (!secret) {
    throw new Error("postNewCategory: CATEGORY_ADMIN_SECRET not set");
  }
  const url = `${apiBase.replace(/\/$/, "")}/api/content-categories`;
  const fetchImpl = deps.fetch ?? fetch;
  const res = await fetchImpl(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${secret}`,
    },
    body: JSON.stringify({
      type: body.type,
      slug: body.slug,
      name: body.name,
      description: body.description ?? null,
    }),
  });

  // 409 = (content_type, slug) duplicate — race or 並行追加。`existing` に既存行が入る。
  if (res.status === 409) {
    const data = (await res.json().catch(() => ({}))) as {
      existing?: { slug?: string; name?: string; description?: string | null };
    };
    if (data.existing && typeof data.existing.slug === "string" && typeof data.existing.name === "string") {
      return {
        slug: data.existing.slug,
        name: data.existing.name,
        description: data.existing.description ?? null,
      };
    }
    throw new Error(
      `postNewCategory: HTTP 409 but response lacks valid 'existing' field for slug=${body.slug}`,
    );
  }

  if (!res.ok) {
    let detail = "";
    try {
      const errJson = await res.json();
      detail = JSON.stringify(errJson);
    } catch {
      detail = await res.text().catch(() => "");
    }
    throw new Error(
      `postNewCategory: HTTP ${res.status} ${res.statusText} for slug=${body.slug}: ${detail}`,
    );
  }

  const data = (await res.json()) as {
    category?: {
      slug?: string;
      name?: string;
      description?: string | null;
    };
  };
  if (!data.category || typeof data.category.slug !== "string" || typeof data.category.name !== "string") {
    throw new Error(
      `postNewCategory: 201 but response shape invalid for slug=${body.slug}`,
    );
  }
  return {
    slug: data.category.slug,
    name: data.category.name,
    description: data.category.description ?? null,
  };
}
