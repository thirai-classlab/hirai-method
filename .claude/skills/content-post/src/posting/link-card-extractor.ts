/**
 * link-card-extractor.ts
 *
 * Enriches bare link-card divs (emitted by markdown.ts postprocess step 5)
 * with real OG metadata fetched at post time.
 *
 * Pipeline position: after markdown.ts renderToHtml(), before DB write.
 * Runs AFTER extractMermaid / code-block processing so those blocks are
 * already converted and do not interfere with link-card matching.
 *
 * C1 Boxed Card output structure:
 *   <div class="link-card" data-url="URL">
 *     <a href="URL" target="_blank" rel="noopener noreferrer">
 *       <div class="link-card__body">
 *         <h3 class="link-card__title">title</h3>
 *         <p class="link-card__description">desc</p>   <!-- optional -->
 *         <div class="link-card__meta">
 *           <img class="link-card__favicon" src="..." alt="" width="16" height="16" />
 *           <span class="link-card__domain">example.com</span>
 *         </div>
 *       </div>
 *       <img class="link-card__thumbnail" src="..." alt="" loading="lazy" width="120" height="120" />  <!-- optional -->
 *     </a>
 *   </div>
 */

import * as cheerio from "cheerio";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface OgData {
  title: string | null;
  description: string | null;
  image: string | null;
  favicon: string | null;
}

export interface BuildOptions {
  /** Emit link-card--fallback modifier class */
  fallback?: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Escape special HTML characters to prevent XSS. */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Extract hostname from a URL string. Returns the full URL on parse failure. */
function extractDomain(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}

/** Resolve a potentially relative URL against a base URL. */
function resolveUrl(href: string, base: string): string {
  try {
    return new URL(href, base).toString();
  } catch {
    return href;
  }
}

// ---------------------------------------------------------------------------
// isStandaloneUrlLine()
//
// Accepts a single HTML fragment that may be a <p> wrapping either:
//   - A bare URL text: <p>https://...</p>
//   - An autolink-style anchor: <p><a href="URL">URL</a></p>
//
// Returns true only when the paragraph content is exclusively a standalone URL.
// List items, code blocks, and inline links with different text are rejected.
// ---------------------------------------------------------------------------

export function isStandaloneUrlLine(fragment: string): boolean {
  const trimmed = fragment.trim();

  // Must be a <p>…</p> block (not li, pre, code, etc.)
  if (!/^<p>/i.test(trimmed) || !/<\/p>$/i.test(trimmed)) {
    return false;
  }

  // Extract inner content between <p> and </p>
  const inner = trimmed.replace(/^<p>/i, "").replace(/<\/p>$/i, "").trim();

  if (!inner) return false;

  // Case 1: bare URL text
  if (/^https?:\/\/\S+$/.test(inner)) {
    return true;
  }

  // Case 2: <a href="URL">URL</a> where href === link text (autolink pattern)
  const anchorMatch = inner.match(
    /^<a\s[^>]*href="(https?:\/\/[^"]+)"[^>]*>([^<]+)<\/a>$/i,
  );
  if (anchorMatch) {
    const href = anchorMatch[1];
    const text = anchorMatch[2];
    if (href === text) {
      return true;
    }
  }

  return false;
}

// ---------------------------------------------------------------------------
// parseOgData()
//
// Given raw HTML text and a base URL, extract OG metadata using cheerio.
// ---------------------------------------------------------------------------

export function parseOgData(html: string, baseUrl: string): OgData {
  const $ = cheerio.load(html);

  // Title: og:title > <title>
  const ogTitle =
    $('meta[property="og:title"]').attr("content")?.trim() ?? null;
  const pageTitle = $("title").text().trim() || null;
  const title = ogTitle ?? pageTitle ?? null;

  // Description: og:description > meta[name=description]
  const ogDesc =
    $('meta[property="og:description"]').attr("content")?.trim() ?? null;
  const metaDesc =
    $('meta[name="description"]').attr("content")?.trim() ?? null;
  const description = ogDesc ?? metaDesc ?? null;

  // Image: og:image (resolve relative)
  const rawImage =
    $('meta[property="og:image"]').attr("content")?.trim() ?? null;
  const image = rawImage ? resolveUrl(rawImage, baseUrl) : null;

  // Favicon: link[rel~=icon] > fallback /favicon.ico
  let faviconHref =
    $('link[rel~="icon"]').first().attr("href")?.trim() ?? null;
  let favicon: string | null;
  if (faviconHref) {
    favicon = resolveUrl(faviconHref, baseUrl);
  } else {
    // Default fallback
    try {
      const origin = new URL(baseUrl).origin;
      favicon = `${origin}/favicon.ico`;
    } catch {
      favicon = null;
    }
  }

  return { title, description, image, favicon };
}

// ---------------------------------------------------------------------------
// buildLinkCardHtml()
//
// Construct the C1 Boxed Card HTML from a URL and OG data.
// ---------------------------------------------------------------------------

export function buildLinkCardHtml(
  url: string,
  og: OgData,
  options: BuildOptions = {},
): string {
  // Variants:
  //   - link-card                            : full enriched (image + body)
  //   - link-card link-card--no-thumbnail    : OG fetch succeeded but image is null
  //                                            (compact layout on consumer CSS side)
  //   - link-card link-card--fallback        : OG fetch failed (URL only)
  const classNames = ["link-card"];
  if (options.fallback) {
    classNames.push("link-card--fallback");
  } else if (og.image === null) {
    classNames.push("link-card--no-thumbnail");
  }
  const wrapperClass = classNames.join(" ");

  const title = og.title ?? url;
  const domain = extractDomain(url);
  const safeUrl = escapeHtml(url);
  const safeTitle = escapeHtml(title);

  // Description (optional)
  const descHtml =
    og.description !== null
      ? `<p class="link-card__description">${escapeHtml(og.description)}</p>`
      : "";

  // Favicon (optional inside meta)
  //
  // Task #54 W3: favicon は同一オリジン proxy 経由で出力する。
  //
  // - CSP `img-src 'self'` 完結のため、外部 favicon ドメインを allowlist せずに済む
  //   (#24 Sub-3 enforce のブロッカー解消)
  // - 相対 path `/api/favicon?url=...` を採用 (preview / 本番 / ステージ 透過動作)
  // - encodeURIComponent → escapeHtml の順で 1 度だけ encode (二重 encode 禁止)
  // - サイト側 `rewriteLinkCardFavicons()` は同形式に対し冪等 (二重 wrap しない)
  const faviconHtml =
    og.favicon !== null
      ? `<img class="link-card__favicon" src="/api/favicon?url=${escapeHtml(encodeURIComponent(og.favicon))}" alt="" width="16" height="16" />`
      : "";

  const metaHtml = `<div class="link-card__meta">${faviconHtml}<span class="link-card__domain">${escapeHtml(domain)}</span></div>`;

  // Thumbnail (optional, right side)
  const thumbHtml =
    og.image !== null
      ? `<img class="link-card__thumbnail" src="${escapeHtml(og.image)}" alt="" loading="lazy" width="120" height="120" />`
      : "";

  return (
    `<div class="${wrapperClass}" data-url="${safeUrl}">` +
    `<a href="${safeUrl}" target="_blank" rel="noopener noreferrer">` +
    `<div class="link-card__body">` +
    `<h3 class="link-card__title">${safeTitle}</h3>` +
    descHtml +
    metaHtml +
    `</div>` +
    thumbHtml +
    `</a>` +
    `</div>`
  );
}

// ---------------------------------------------------------------------------
// buildFallbackCardHtml()
//
// When fetch fails, produce a minimal fallback card showing just the URL.
// ---------------------------------------------------------------------------

function buildFallbackCardHtml(url: string): string {
  const og: OgData = {
    title: url,
    description: null,
    image: null,
    favicon: null,
  };
  return buildLinkCardHtml(url, og, { fallback: true });
}

// ---------------------------------------------------------------------------
// enrichLinkCards()
//
// Main pipeline function. Finds all bare link-card divs in the HTML (as
// emitted by markdown.ts postprocess step 5), fetches OG data for each URL,
// and replaces the div with the enriched C1 Boxed Card HTML.
//
// The input format matched:
//   <div class="link-card"><a href="URL" data-url="URL" ...>URL</a></div>
// ---------------------------------------------------------------------------

/** Regex matching a bare (un-enriched) link-card div. */
const BARE_LINK_CARD_RE =
  /<div class="link-card"><a\s[^>]*data-url="([^"]+)"[^>]*>[^<]*<\/a><\/div>/g;

export async function enrichLinkCards(html: string): Promise<string> {
  // Collect all bare link-card matches first (avoid mutating during iteration)
  const matches: Array<{ full: string; url: string }> = [];
  let m: RegExpExecArray | null;
  const re = new RegExp(BARE_LINK_CARD_RE.source, "g");
  while ((m = re.exec(html)) !== null) {
    matches.push({ full: m[0]!, url: m[1]! });
  }

  if (matches.length === 0) {
    return html;
  }

  // Fetch OG data for each URL (in parallel)
  const enriched = await Promise.all(
    matches.map(async ({ full, url }) => {
      let replacement: string;
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        let fetchedHtml: string;
        try {
          const res = await fetch(url, { signal: controller.signal });
          fetchedHtml = await res.text();
        } finally {
          clearTimeout(timeoutId);
        }
        const og = parseOgData(fetchedHtml, url);
        replacement = buildLinkCardHtml(url, og);
      } catch {
        replacement = buildFallbackCardHtml(url);
      }
      return { original: full, replacement };
    }),
  );

  // Replace each original bare card with enriched version
  let result = html;
  for (const { original, replacement } of enriched) {
    // Use callback form to avoid $& and $1 special-replacement interpretation
    result = result.replace(original, () => replacement);
  }

  return result;
}
