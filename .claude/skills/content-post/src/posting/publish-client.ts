/**
 * src/posting/publish-client.ts — Task #33 W4
 *
 * HTTP クライアント: POST /api/publish エンドポイントへの公開リクエスト。
 * --publish フラグが ON のときに呼ばれる。
 * api-client.ts (ingestViaApi) と同パターンで実装。
 */

export interface PublishResult {
  success: boolean;
  published_at: string;
  revalidated: string[];
  already_published?: boolean;
}

export class PublishApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly body: unknown,
  ) {
    super(message);
    this.name = "PublishApiError";
  }
}

const DEFAULT_API_BASE_URL = "https://classlab-weekly-news.vercel.app";

/**
 * POST /api/publish へ kind + slug を送信し PublishResult を返す。
 *
 * @throws {Error} BATCH_SECRET が未設定の場合（fetch を呼ばずに即座に throw）
 * @throws {PublishApiError} 4xx/5xx レスポンスの場合
 * @throws {TypeError} ネットワークエラーの場合
 */
export async function publishContent({
  kind,
  slug,
}: {
  kind: "tech_article" | "issue" | "knowledge";
  slug: string;
}): Promise<PublishResult> {
  const secret = process.env.BATCH_SECRET;
  if (!secret || secret.trim().length === 0) {
    throw new Error(
      "[publishContent] BATCH_SECRET is not set. " +
        "Set BATCH_SECRET in your .env (same value as the site BATCH_SECRET).",
    );
  }

  const baseUrl = (
    process.env.CLASSLAB_WEEKLY_NEWS_API_URL ?? DEFAULT_API_BASE_URL
  ).replace(/\/$/, "");
  const url = `${baseUrl}/api/publish`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-batch-secret": secret,
    },
    body: JSON.stringify({ kind, slug }),
  });

  let responseBody: unknown;
  try {
    responseBody = await response.json();
  } catch {
    responseBody = { error: "failed to parse response body" };
  }

  if (!response.ok) {
    const bodyStr = JSON.stringify(responseBody);
    const status = response.status;

    if (status === 404) {
      throw new PublishApiError(
        `[publishContent] not_found: ${slug} (HTTP 404: ${bodyStr})`,
        status,
        responseBody,
      );
    }

    throw new PublishApiError(
      `[publishContent] HTTP ${status}: ${bodyStr}`,
      status,
      responseBody,
    );
  }

  const body = responseBody as {
    success: boolean;
    published_at: string;
    revalidated: string[];
    already_published?: boolean;
  };

  return {
    success: body.success,
    published_at: body.published_at,
    revalidated: body.revalidated ?? [],
    ...(body.already_published !== undefined
      ? { already_published: body.already_published }
      : {}),
  };
}
