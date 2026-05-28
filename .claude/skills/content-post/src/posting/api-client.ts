/**
 * src/posting/api-client.ts — Phase 11 W1.D-2 (11.1.9)
 *
 * HTTP クライアント: POST /api/ingest エンドポイントへの投稿。
 * --via-api フラグが ON のときに呼ばれる新パス。
 * 旧パス（Supabase 直接 INSERT）は Wave 11.3 まで残す。
 */

import { SlugConflictError } from "./slug-errors.js";
import type { KnowledgeKind } from "../../scripts/post-types.js";

export interface IngestPayload {
  type: "issue" | "article" | "knowledge";
  title: string;
  slug: string;
  html: string;
  raw_markdown?: string | null;
  category_slug: string;
  summary?: string;
  author?: string;
  tag_ids: string[];
  tag_names_new: string[];
  related_content_ids: string[];
  related_content_types: string[];
  parent_content_id?: string | null;
  parent_content_type?: string | null;
  depth?: number;
  root_content_id?: string | null;
  root_content_type?: string | null;
  /** #30: サムネイル画像の CDN URL（ローカルパスは Stage 5b+ で S3 upload 済み） */
  thumbnail_url?: string | null;
  /** #30: サムネイル画像の alt テキスト */
  thumbnail_alt?: string | null;
  /** #29: weekly_issue の関連 knowledge ID リスト（先頭 3 件、issue のみ有効） */
  knowledge_ids?: string[];
  /**
   * #58 Step 1: knowledge.kind 列 (concept|operation|domain_knowledge)。
   * type === "knowledge" のときのみ送信。サイト側 Task #57 で追加済み。
   * #58 round-2 (H2): 文字列リテラル再定義をやめ post-types.ts の KnowledgeKind
   * を単一真実源として import (DRY)。
   */
  kind?: KnowledgeKind;
}

export interface IngestResult {
  id: string;
  slug: string;
  augment_job_id: string | null;
  mode?: "mock";
  /** x-trace-id レスポンスヘッダから抽出 */
  trace_id: string;
}

export class IngestApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly body: unknown,
  ) {
    super(message);
    this.name = "IngestApiError";
  }
}

const DEFAULT_API_BASE_URL = "https://classlab-weekly-news.vercel.app";

/**
 * POST /api/ingest へペイロードを送信し IngestResult を返す。
 *
 * @throws {Error} INGEST_SECRET が未設定の場合（fetch を呼ばずに即座に throw）
 * @throws {IngestApiError} 4xx/5xx レスポンスの場合
 * @throws {TypeError} ネットワークエラーの場合
 */
export async function ingestViaApi(
  payload: IngestPayload,
  opts?: { traceId?: string },
): Promise<IngestResult> {
  const secret = process.env.INGEST_SECRET;
  if (!secret || secret.trim().length === 0) {
    throw new Error(
      "[ingestViaApi] INGEST_SECRET is not set. " +
        "Set INGEST_SECRET in your .env (same value as the site INGEST_SECRET).",
    );
  }

  const baseUrl =
    (process.env.CLASSLAB_WEEKLY_NEWS_API_URL ?? DEFAULT_API_BASE_URL).replace(/\/$/, "");
  const url = `${baseUrl}/api/ingest`;

  const traceId = opts?.traceId ?? crypto.randomUUID();

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-ingest-secret": secret,
      "x-trace-id": traceId,
    },
    body: JSON.stringify(payload),
  });

  const serverTraceId = response.headers.get("x-trace-id") ?? traceId;
  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    responseBody = { error: "failed to parse response body" };
  }

  if (!response.ok) {
    if (response.status === 409) {
      // Server-side slug collision (fail-loud). Convert to SlugConflictError so
      // post.ts can show the same exit-2 guidance whether the collision was
      // detected locally (assertSlugAvailable) or on the server.
      const body = (responseBody ?? {}) as {
        existing_slug?: unknown;
        existing_id?: unknown;
        slug?: unknown;
        id?: unknown;
        content_type?: unknown;
        type?: unknown;
      };
      const conflictSlug =
        (typeof body.existing_slug === "string" && body.existing_slug) ||
        (typeof body.slug === "string" && body.slug) ||
        payload.slug;
      const existingId =
        typeof body.existing_id === "string"
          ? body.existing_id
          : typeof body.id === "string"
            ? body.id
            : undefined;
      const contentTypeOnRow =
        (typeof body.content_type === "string" && body.content_type) ||
        (typeof body.type === "string" && body.type) ||
        payload.type;
      throw new SlugConflictError(conflictSlug, contentTypeOnRow, existingId);
    }
    const bodyStr = JSON.stringify(responseBody);
    throw new IngestApiError(
      `[ingestViaApi] HTTP ${response.status}: ${bodyStr}`,
      response.status,
      responseBody,
    );
  }

  const body = responseBody as {
    id: string;
    slug: string;
    augment_job_id: string | null;
    mode?: "mock";
  };

  return {
    id: body.id,
    slug: body.slug,
    augment_job_id: body.augment_job_id ?? null,
    mode: body.mode,
    trace_id: serverTraceId,
  };
}
