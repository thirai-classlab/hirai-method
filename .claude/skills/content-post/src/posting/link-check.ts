/**
 * link-check.ts
 *
 * Markdown 本文から外部 http(s) URL を抽出し、HTTP 到達性をチェックする。
 * post.ts パイプラインの「リンクチェック フェーズ」で呼び出される。
 *
 * 設計方針:
 *   - 抽出対象: link-card 記法（URL 単独行）/ `[text](url)` / 生 URL
 *   - 除外: コードブロック内 URL、画像 URL (`![alt](url)`)、内部 URL (SITE_URL)
 *   - チェック: HEAD → 失敗時 GET (一部サイトが HEAD を 405 で返すため)
 *   - リダイレクト追従 (最大 5 回)
 *   - 並列度制限 (デフォルト 8 並列)
 *   - タイムアウト (デフォルト 10 秒)
 *
 * 判定:
 *   - ok: 最終ステータス 2xx
 *   - redirect: 最終ステータス 2xx だが初回が 3xx (情報のみ)
 *   - broken: 4xx / 5xx / ネットワークエラー / タイムアウト
 *
 * post.ts 統合:
 *   - デフォルトでチェック実行 (warn-only モード)
 *   - --link-check-strict でブロック (broken 1件以上で exit 5)
 *   - --no-link-check でフェーズ自体を skip
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type LinkStatus = "ok" | "redirect" | "broken" | "timeout";

export interface LinkCheckResult {
  /** 元のURL (リダイレクト前) */
  url: string;
  /** 最終解決URL (リダイレクト後) */
  finalUrl: string | null;
  /** 最終 HTTP ステータスコード (ネットワーク失敗時は null) */
  status: number | null;
  /** 判定 */
  result: LinkStatus;
  /** リダイレクトが発生したか */
  redirected: boolean;
  /** エラーメッセージ (broken/timeout 時) */
  error: string | null;
}

export interface CheckOptions {
  /** 1 リクエストあたりのタイムアウト (ms)。default 10000 */
  timeoutMs?: number;
  /** 並列度。default 8 */
  concurrency?: number;
  /** リダイレクト最大回数。default 5 */
  maxRedirects?: number;
  /** チェック対象外にする URL の prefix リスト (例: SITE_URL を除外) */
  excludeOrigins?: readonly string[];
  /** 注入用 fetch (テスト/モック)。default は globalThis.fetch */
  fetchImpl?: typeof globalThis.fetch;
  /** 注入用 User-Agent。default は一般的なブラウザ風 */
  userAgent?: string;
}

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

const DEFAULT_TIMEOUT_MS = 10_000;
const DEFAULT_CONCURRENCY = 8;
const DEFAULT_MAX_REDIRECTS = 5;
const DEFAULT_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

// ---------------------------------------------------------------------------
// URL extraction
// ---------------------------------------------------------------------------

/**
 * Markdown から外部 http(s) URL を抽出する。
 *
 * 対象:
 *   - URL 単独行 (link-card 記法)
 *   - `[text](url)` 形式のリンク
 *   - 生 URL (テキスト中の `https://...`)
 *
 * 除外:
 *   - コードブロック内 (``` で囲まれた範囲)
 *   - インラインコード内 (`...` で囲まれた範囲)
 *   - 画像リンク `![alt](url)` (CDN 画像は別フェーズでチェック済み)
 *   - excludeOrigins に一致する URL
 *
 * 返り値は重複排除済みの順序保存配列。
 */
export function extractExternalUrls(
  markdown: string,
  options: { excludeOrigins?: readonly string[] } = {},
): string[] {
  const excludeOrigins = options.excludeOrigins ?? [];

  // 1. コードブロックを除去 (``` で囲まれた範囲)
  const withoutFences = markdown.replace(/```[\s\S]*?```/g, "");
  // 2. インラインコードを除去 (`...`)
  const withoutCode = withoutFences.replace(/`[^`\n]*`/g, "");
  // 3. 画像を除去 (![alt](url))
  const withoutImages = withoutCode.replace(/!\[[^\]]*\]\([^)]+\)/g, "");

  const found = new Set<string>();
  const ordered: string[] = [];

  const addUrl = (raw: string): void => {
    const url = sanitizeUrl(raw);
    if (!url) return;
    if (excludeOrigins.some((origin) => url.startsWith(origin))) return;
    if (found.has(url)) return;
    found.add(url);
    ordered.push(url);
  };

  // パターン1: [text](url)
  const mdLinkRegex = /\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)/g;
  let match: RegExpExecArray | null;
  while ((match = mdLinkRegex.exec(withoutImages)) !== null) {
    addUrl(match[2]);
  }

  // パターン2: 残ったテキストから生 URL を抽出
  const remainingText = withoutImages.replace(mdLinkRegex, "");
  const bareUrlRegex = /https?:\/\/[^\s<>"'`)\]}]+/g;
  while ((match = bareUrlRegex.exec(remainingText)) !== null) {
    addUrl(match[0]);
  }

  return ordered;
}

/** URL の末尾の句読点 (.,;:!?) や閉じ括弧を取り除く。 */
function sanitizeUrl(raw: string): string | null {
  let url = raw.trim();
  // 末尾の句読点・括弧を剥がす
  while (url.length > 0 && /[.,;:!?)\]}]$/.test(url)) {
    url = url.slice(0, -1);
  }
  if (!url.startsWith("http://") && !url.startsWith("https://")) return null;
  try {
    // eslint-disable-next-line no-new
    new URL(url);
    return url;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// HTTP check (single URL)
// ---------------------------------------------------------------------------

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  fetchImpl: typeof globalThis.fetch,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchImpl(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 単一 URL のチェック。
 *
 * 戦略:
 *   1. HEAD リクエスト (リダイレクト manual で chain を観測)
 *   2. HEAD が 405/501/4xx の場合は GET で再試行 (一部サイトが HEAD 拒否のため)
 *   3. ネットワーク失敗 / タイムアウト時は broken/timeout
 */
export async function checkUrl(
  url: string,
  options: CheckOptions = {},
): Promise<LinkCheckResult> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxRedirects = options.maxRedirects ?? DEFAULT_MAX_REDIRECTS;
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  const userAgent = options.userAgent ?? DEFAULT_USER_AGENT;

  const headers: Record<string, string> = {
    "user-agent": userAgent,
    accept: "*/*",
  };

  const tryMethod = async (
    method: "HEAD" | "GET",
  ): Promise<LinkCheckResult> => {
    let currentUrl = url;
    let redirected = false;
    let lastStatus: number | null = null;

    for (let i = 0; i <= maxRedirects; i++) {
      let res: Response;
      try {
        res = await fetchWithTimeout(
          currentUrl,
          { method, headers, redirect: "manual" },
          timeoutMs,
          fetchImpl,
        );
      } catch (err: unknown) {
        const msg = err instanceof Error ? err.message : String(err);
        const isAbort = msg.includes("aborted") || msg.includes("AbortError");
        return {
          url,
          finalUrl: null,
          status: null,
          result: isAbort ? "timeout" : "broken",
          redirected,
          error: msg,
        };
      }

      lastStatus = res.status;

      // 2xx は成功
      if (res.status >= 200 && res.status < 300) {
        return {
          url,
          finalUrl: currentUrl,
          status: res.status,
          result: redirected ? "redirect" : "ok",
          redirected,
          error: null,
        };
      }

      // 3xx はリダイレクト追従
      if (res.status >= 300 && res.status < 400) {
        const location = res.headers.get("location");
        if (!location) {
          return {
            url,
            finalUrl: currentUrl,
            status: res.status,
            result: "broken",
            redirected,
            error: "redirect without Location header",
          };
        }
        currentUrl = new URL(location, currentUrl).toString();
        redirected = true;
        continue;
      }

      // 4xx/5xx はエラー
      return {
        url,
        finalUrl: currentUrl,
        status: res.status,
        result: "broken",
        redirected,
        error: `HTTP ${res.status}`,
      };
    }

    return {
      url,
      finalUrl: currentUrl,
      status: lastStatus,
      result: "broken",
      redirected,
      error: `too many redirects (>${maxRedirects})`,
    };
  };

  // First try HEAD
  const headResult = await tryMethod("HEAD");

  // HEAD で 405/501 や 4xx が返るサイト (X.com / SNS など) は GET で再試行
  const headStatus = headResult.status;
  const shouldRetryWithGet =
    headResult.result === "broken" &&
    headStatus !== null &&
    (headStatus === 403 || headStatus === 404 || headStatus === 405 || headStatus === 501 || headStatus >= 500);

  if (!shouldRetryWithGet) return headResult;

  const getResult = await tryMethod("GET");
  // GET の結果を優先 (HEAD は実装次第のため信頼度低)
  return getResult;
}

// ---------------------------------------------------------------------------
// Parallel check
// ---------------------------------------------------------------------------

/**
 * 複数 URL を並列度制限付きでチェックする。
 *
 * 入力配列の順序を保ったまま結果を返す。
 */
export async function checkUrls(
  urls: readonly string[],
  options: CheckOptions = {},
): Promise<LinkCheckResult[]> {
  const concurrency = Math.max(1, options.concurrency ?? DEFAULT_CONCURRENCY);
  const results: LinkCheckResult[] = new Array(urls.length);
  let cursor = 0;

  const worker = async (): Promise<void> => {
    while (true) {
      const idx = cursor++;
      if (idx >= urls.length) return;
      results[idx] = await checkUrl(urls[idx], options);
    }
  };

  const workers: Promise<void>[] = [];
  for (let i = 0; i < Math.min(concurrency, urls.length); i++) {
    workers.push(worker());
  }
  await Promise.all(workers);
  return results;
}

// ---------------------------------------------------------------------------
// Summary helpers (consumed by post.ts for logging)
// ---------------------------------------------------------------------------

export interface LinkCheckSummary {
  total: number;
  ok: number;
  redirect: number;
  broken: number;
  timeout: number;
  brokenItems: LinkCheckResult[];
}

export function summarize(results: readonly LinkCheckResult[]): LinkCheckSummary {
  const summary: LinkCheckSummary = {
    total: results.length,
    ok: 0,
    redirect: 0,
    broken: 0,
    timeout: 0,
    brokenItems: [],
  };
  for (const r of results) {
    summary[r.result] += 1;
    if (r.result === "broken" || r.result === "timeout") {
      summary.brokenItems.push(r);
    }
  }
  return summary;
}

/** broken/timeout の結果を 1 行ずつフォーマット (post.ts でログ出力)。 */
export function formatBrokenLine(r: LinkCheckResult): string {
  const status = r.status === null ? "ERR" : String(r.status);
  const reason = r.error ?? "unknown";
  return `  [${status}] ${r.url} — ${reason}`;
}
