/**
 * Tests for src/posting/link-card-extractor.ts
 *
 * TDD: RED → write tests first, then implement.
 *
 * Covers:
 *   - isStandaloneUrlLine(): URL-only paragraph detection
 *   - parseOgData(): cheerio-based OG metadata extraction from fixture HTML
 *   - buildLinkCardHtml(): C1 Boxed Card HTML output structure
 *   - enrichLinkCards(): full pipeline with fetch mocking
 *   - Fallback behaviors (fetch failure, missing og tags)
 *   - Pipeline isolation (Mermaid / code blocks / inline links unaffected)
 *   - Fixture contract with classlab-weekly-news globals.css
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  isStandaloneUrlLine,
  parseOgData,
  buildLinkCardHtml,
  enrichLinkCards,
  type OgData,
} from "../../src/posting/link-card-extractor.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Mock global fetch */
function mockFetch(responses: Array<{ url: string; html: string } | { url: string; error: true }>) {
  const impl = vi.fn(async (input: string | URL | { toString(): string }) => {
    const url = typeof input === "string" ? input : input.toString();
    const match = responses.find((r) => r.url === url);
    if (!match) {
      throw new Error(`Unexpected fetch: ${url}`);
    }
    if ("error" in match) {
      throw new Error("Network error");
    }
    return {
      ok: true,
      text: async () => match.html,
    } as unknown as Response;
  });
  vi.stubGlobal("fetch", impl);
  return impl;
}

// ---------------------------------------------------------------------------
// Fixture HTML strings (simulate real OG pages)
// ---------------------------------------------------------------------------

const OG_FULL_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="Example Article Title" />
  <meta property="og:description" content="An example description." />
  <meta property="og:image" content="https://example.com/image.png" />
  <link rel="icon" href="/favicon.ico" />
  <title>Fallback Title</title>
  <meta name="description" content="Fallback description." />
</head>
<body></body>
</html>`;

const OG_NO_IMAGE_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="No Image Article" />
  <meta property="og:description" content="No og:image here." />
  <title>No Image Article</title>
</head>
<body></body>
</html>`;

const OG_FALLBACK_ONLY_HTML = `<!DOCTYPE html>
<html>
<head>
  <title>Plain Title</title>
  <meta name="description" content="Plain description." />
  <link rel="icon" href="https://example.com/favicon.svg" />
</head>
<body></body>
</html>`;

const OG_RELATIVE_IMAGE_HTML = `<!DOCTYPE html>
<html>
<head>
  <meta property="og:title" content="Relative Image" />
  <meta property="og:image" content="/path/to/image.png" />
</head>
<body></body>
</html>`;

const OG_NO_OG_NO_TITLE_HTML = `<!DOCTYPE html>
<html>
<head></head>
<body></body>
</html>`;

// ---------------------------------------------------------------------------
// 1. isStandaloneUrlLine()
// ---------------------------------------------------------------------------

describe("isStandaloneUrlLine()", () => {
  it("returns true for bare https URL paragraph", () => {
    expect(isStandaloneUrlLine("<p>https://example.com</p>")).toBe(true);
  });

  it("returns true for bare http URL paragraph", () => {
    expect(isStandaloneUrlLine("<p>http://example.com/path</p>")).toBe(true);
  });

  it("returns true for autolink-style <a> wrapping same URL", () => {
    // markdown autolinks render as <p><a href="URL">URL</a></p>
    expect(
      isStandaloneUrlLine(
        '<p><a href="https://example.com">https://example.com</a></p>',
      ),
    ).toBe(true);
  });

  it("returns false for inline link with different text", () => {
    expect(
      isStandaloneUrlLine(
        '<p>See <a href="https://example.com">here</a> for details.</p>',
      ),
    ).toBe(false);
  });

  it("returns false for paragraph with text + URL", () => {
    expect(
      isStandaloneUrlLine("<p>Check https://example.com for details.</p>"),
    ).toBe(false);
  });

  it("returns false for empty paragraph", () => {
    expect(isStandaloneUrlLine("<p></p>")).toBe(false);
  });

  it("returns false for non-URL paragraph", () => {
    expect(isStandaloneUrlLine("<p>Just plain text.</p>")).toBe(false);
  });

  it("returns false for URL inside a list item", () => {
    expect(
      isStandaloneUrlLine("<li>https://example.com</li>"),
    ).toBe(false);
  });

  it("returns false for URL inside a code block", () => {
    expect(
      isStandaloneUrlLine('<pre><code>https://example.com</code></pre>'),
    ).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// 2. parseOgData()
// ---------------------------------------------------------------------------

describe("parseOgData()", () => {
  it("extracts og:title, og:description, og:image, and favicon", () => {
    const result = parseOgData(OG_FULL_HTML, "https://example.com");
    expect(result.title).toBe("Example Article Title");
    expect(result.description).toBe("An example description.");
    expect(result.image).toBe("https://example.com/image.png");
    expect(result.favicon).toContain("favicon");
  });

  it("falls back to <title> when og:title is absent", () => {
    const result = parseOgData(OG_FALLBACK_ONLY_HTML, "https://example.com");
    expect(result.title).toBe("Plain Title");
  });

  it("falls back to meta[name=description] when og:description is absent", () => {
    const result = parseOgData(OG_FALLBACK_ONLY_HTML, "https://example.com");
    expect(result.description).toBe("Plain description.");
  });

  it("resolves relative og:image to absolute URL using base URL", () => {
    const result = parseOgData(OG_RELATIVE_IMAGE_HTML, "https://example.com");
    expect(result.image).toBe("https://example.com/path/to/image.png");
  });

  it("returns null image when og:image is absent", () => {
    const result = parseOgData(OG_NO_IMAGE_HTML, "https://example.com");
    expect(result.image).toBeNull();
  });

  it("returns null title when no og:title or <title> is present", () => {
    const result = parseOgData(OG_NO_OG_NO_TITLE_HTML, "https://example.com");
    expect(result.title).toBeNull();
  });

  it("resolves relative favicon to absolute URL", () => {
    const result = parseOgData(OG_FULL_HTML, "https://example.com");
    // favicon href="/favicon.ico" → https://example.com/favicon.ico
    expect(result.favicon).toBe("https://example.com/favicon.ico");
  });

  it("returns absolute favicon as-is", () => {
    const result = parseOgData(OG_FALLBACK_ONLY_HTML, "https://example.com");
    expect(result.favicon).toBe("https://example.com/favicon.svg");
  });

  it("falls back to /favicon.ico when no link[rel=icon]", () => {
    const result = parseOgData(OG_NO_IMAGE_HTML, "https://example.com");
    expect(result.favicon).toBe("https://example.com/favicon.ico");
  });
});

// ---------------------------------------------------------------------------
// 3. buildLinkCardHtml()
// ---------------------------------------------------------------------------

describe("buildLinkCardHtml()", () => {
  const baseUrl = "https://example.com/article";

  it("produces C1 Boxed Card structure with all OG data", () => {
    const og: OgData = {
      title: "Test Title",
      description: "Test Description",
      image: "https://example.com/img.png",
      favicon: "https://example.com/favicon.ico",
    };
    const html = buildLinkCardHtml(baseUrl, og);

    expect(html).toContain('<div class="link-card"');
    expect(html).toContain(`data-url="${baseUrl}"`);
    expect(html).toContain(`href="${baseUrl}"`);
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
    expect(html).toContain('<div class="link-card__body">');
    expect(html).toContain('<h3 class="link-card__title">Test Title</h3>');
    expect(html).toContain('<p class="link-card__description">Test Description</p>');
    expect(html).toContain('<div class="link-card__meta">');
    expect(html).toContain('class="link-card__favicon"');
    expect(html).toContain('class="link-card__domain"');
    expect(html).toContain("example.com");
    expect(html).toContain('<img class="link-card__thumbnail"');
    expect(html).toContain('src="https://example.com/img.png"');
  });

  it("omits thumbnail img when image is null", () => {
    const og: OgData = {
      title: "No Image",
      description: null,
      image: null,
      favicon: "https://example.com/favicon.ico",
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toContain('class="link-card__thumbnail"');
  });

  it("omits description p when description is null", () => {
    const og: OgData = {
      title: "No Desc",
      description: null,
      image: "https://example.com/img.png",
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toContain('class="link-card__description"');
  });

  it("uses URL as title when title is null", () => {
    const og: OgData = {
      title: null,
      description: null,
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).toContain(`<h3 class="link-card__title">${baseUrl}</h3>`);
  });

  it("emits link-card--fallback class on fallback (no OG, no title)", () => {
    const og: OgData = {
      title: null,
      description: null,
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og, { fallback: true });
    expect(html).toContain('class="link-card link-card--fallback"');
  });

  it("emits link-card--no-thumbnail modifier when OG fetch succeeded but image is null", () => {
    // 中間 variant: OG fetch 成功 (title/description/favicon あり) だが og:image だけ null
    // 例: サムネイル図鑑 (https://thumbnail-gallery-xi.vercel.app/) のように
    // SPA で og:image meta が無いサイト
    const og: OgData = {
      title: "サムネイル図鑑",
      description: null,
      image: null,
      favicon: "https://thumbnail-gallery-xi.vercel.app/favicon.ico",
    };
    const html = buildLinkCardHtml("https://thumbnail-gallery-xi.vercel.app/", og);
    expect(html).toContain('class="link-card link-card--no-thumbnail"');
    // thumbnail 要素は無い
    expect(html).not.toContain("link-card__thumbnail");
    // fallback とは別 modifier
    expect(html).not.toContain("link-card--fallback");
  });

  it("does NOT emit link-card--no-thumbnail when fallback option is true (modifier 排他)", () => {
    // fallback の場合は --fallback だけ付き、--no-thumbnail は付与しない
    const og: OgData = {
      title: null,
      description: null,
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og, { fallback: true });
    expect(html).toContain("link-card--fallback");
    expect(html).not.toContain("link-card--no-thumbnail");
  });

  it("does NOT emit link-card--no-thumbnail when image is present (full variant)", () => {
    const og: OgData = {
      title: "Has Image",
      description: null,
      image: "https://example.com/img.png",
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toContain("link-card--no-thumbnail");
    expect(html).not.toContain("link-card--fallback");
  });

  it("extracts domain correctly from URL", () => {
    const og: OgData = {
      title: "Sub Domain",
      description: null,
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml("https://docs.example.co.jp/page", og);
    expect(html).toContain("docs.example.co.jp");
  });

  it("thumbnail img has loading=lazy, width=120, height=120", () => {
    const og: OgData = {
      title: "T",
      description: null,
      image: "https://example.com/img.png",
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).toContain('loading="lazy"');
    expect(html).toContain('width="120"');
    expect(html).toContain('height="120"');
  });

  it("favicon img has width=16 height=16 and empty alt", () => {
    const og: OgData = {
      title: "T",
      description: null,
      image: null,
      favicon: "https://example.com/favicon.ico",
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).toContain('width="16"');
    expect(html).toContain('height="16"');
    expect(html).toContain('alt=""');
  });

  // Task #54 W3: favicon は proxy URL 形式で emit
  it("emits favicon src as /api/favicon?url=<encoded> proxy URL", () => {
    const og: OgData = {
      title: "T",
      description: null,
      image: null,
      favicon: "https://blog.google/favicon.ico",
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).toContain(
      'src="/api/favicon?url=https%3A%2F%2Fblog.google%2Ffavicon.ico"',
    );
    // 元の外部 URL src は出力されない
    expect(html).not.toContain('src="https://blog.google/favicon.ico"');
  });

  it("omits favicon img entirely when favicon is null (no proxy URL emitted)", () => {
    const og: OgData = {
      title: "T",
      description: null,
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toContain("link-card__favicon");
    expect(html).not.toContain("/api/favicon");
  });

  it("encodeURIComponent applied once: favicon URL with query is properly encoded", () => {
    const og: OgData = {
      title: "T",
      description: null,
      image: null,
      favicon: "https://example.com/favicon?v=1&size=16",
    };
    const html = buildLinkCardHtml(baseUrl, og);
    // & ? = は一度だけ encode される
    expect(html).toContain(
      'src="/api/favicon?url=https%3A%2F%2Fexample.com%2Ffavicon%3Fv%3D1%26size%3D16"',
    );
  });

  it("does not produce dark: CSS classes (light-only constraint)", () => {
    const og: OgData = {
      title: "T",
      description: "D",
      image: "https://example.com/img.png",
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toMatch(/dark:/);
  });

  it("escapes special HTML characters in title and description", () => {
    const og: OgData = {
      title: '<script>alert("xss")</script>',
      description: '"><img>',
      image: null,
      favicon: null,
    };
    const html = buildLinkCardHtml(baseUrl, og);
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});

// ---------------------------------------------------------------------------
// 4. enrichLinkCards() — full pipeline with fetch mocking
// ---------------------------------------------------------------------------

describe("enrichLinkCards()", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("replaces bare link-card div with enriched OG card", async () => {
    mockFetch([{ url: "https://example.com", html: OG_FULL_HTML }]);

    const input =
      '<div class="link-card"><a href="https://example.com" data-url="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a></div>';
    const result = await enrichLinkCards(input);

    expect(result).toContain('<div class="link-card"');
    expect(result).toContain('<h3 class="link-card__title">Example Article Title</h3>');
    expect(result).toContain('<p class="link-card__description">An example description.</p>');
    expect(result).toContain('class="link-card__thumbnail"');
  });

  it("uses fallback when fetch throws", async () => {
    mockFetch([{ url: "https://broken.example.com", error: true }]);

    const input =
      '<div class="link-card"><a href="https://broken.example.com" data-url="https://broken.example.com" target="_blank" rel="noopener noreferrer">https://broken.example.com</a></div>';
    const result = await enrichLinkCards(input);

    expect(result).toContain("link-card--fallback");
    expect(result).toContain("https://broken.example.com");
  });

  it("handles multiple link-cards in one HTML string", async () => {
    mockFetch([
      { url: "https://first.example.com", html: OG_FULL_HTML },
      { url: "https://second.example.com", html: OG_NO_IMAGE_HTML },
    ]);

    const input = [
      '<div class="link-card"><a href="https://first.example.com" data-url="https://first.example.com" target="_blank" rel="noopener noreferrer">https://first.example.com</a></div>',
      '<div class="link-card"><a href="https://second.example.com" data-url="https://second.example.com" target="_blank" rel="noopener noreferrer">https://second.example.com</a></div>',
    ].join("\n");

    const result = await enrichLinkCards(input);
    expect(result).toContain("Example Article Title");
    expect(result).toContain("No Image Article");
  });

  it("does not modify content without link-card divs", async () => {
    const fetchMock = mockFetch([]);
    const input = "<p>Normal paragraph.</p>";
    const result = await enrichLinkCards(input);
    expect(result).toBe(input);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does not touch Mermaid placeholders", async () => {
    mockFetch([{ url: "https://example.com", html: OG_FULL_HTML }]);

    const mermaidBlock = '<div class="mermaid-placeholder" data-diagram="flowchart LR\n  A --> B"></div>';
    const linkCard =
      '<div class="link-card"><a href="https://example.com" data-url="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a></div>';
    const input = `${mermaidBlock}\n${linkCard}`;
    const result = await enrichLinkCards(input);

    expect(result).toContain("mermaid-placeholder");
    expect(result).toContain('data-diagram="flowchart LR\n  A --> B"');
  });

  it("does not touch code blocks", async () => {
    mockFetch([{ url: "https://example.com", html: OG_FULL_HTML }]);

    const codeBlock = '<pre data-lang="typescript"><code>const x = 1;</code></pre>';
    const linkCard =
      '<div class="link-card"><a href="https://example.com" data-url="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a></div>';
    const input = `${codeBlock}\n${linkCard}`;
    const result = await enrichLinkCards(input);

    expect(result).toContain('<pre data-lang="typescript">');
    expect(result).toContain("const x = 1;");
  });

  it("does not re-process already-enriched link-cards (idempotent on title class)", async () => {
    // Already-enriched card has link-card__title. Should still process data-url.
    mockFetch([{ url: "https://example.com", html: OG_FULL_HTML }]);

    const enrichedInput =
      '<div class="link-card"><a href="https://example.com" data-url="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a></div>';
    const result = await enrichLinkCards(enrichedInput);

    // Verify the enriched card has proper structure
    expect(result).toContain('class="link-card__title"');
  });

  it("respects 5s fetch timeout (AbortController)", async () => {
    // Simulate a slow fetch that is aborted
    const abortMock = vi.fn();
    const originalAbortController = globalThis.AbortController;

    class MockAbortController {
      signal = { aborted: false } as AbortSignal;
      abort = abortMock;
    }
    vi.stubGlobal("AbortController", MockAbortController);

    // Restore AbortController but let fetch throw to simulate timeout
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("AbortError")));

    const input =
      '<div class="link-card"><a href="https://timeout.example.com" data-url="https://timeout.example.com" target="_blank" rel="noopener noreferrer">https://timeout.example.com</a></div>';
    const result = await enrichLinkCards(input);

    // Should produce fallback
    expect(result).toContain("link-card--fallback");

    vi.stubGlobal("AbortController", originalAbortController);
  });

  it("produces no thumbnail img when og:image is absent", async () => {
    mockFetch([{ url: "https://no-image.example.com", html: OG_NO_IMAGE_HTML }]);

    const input =
      '<div class="link-card"><a href="https://no-image.example.com" data-url="https://no-image.example.com" target="_blank" rel="noopener noreferrer">https://no-image.example.com</a></div>';
    const result = await enrichLinkCards(input);

    expect(result).not.toContain('class="link-card__thumbnail"');
    expect(result).toContain("No Image Article");
    // image なし success variant は --no-thumbnail modifier を付与
    expect(result).toContain("link-card--no-thumbnail");
    // fallback ではない
    expect(result).not.toContain("link-card--fallback");
  });
});

// ---------------------------------------------------------------------------
// 5. Fixture contract — HTML structure the site CSS expects
// ---------------------------------------------------------------------------

describe("C1 Boxed Card fixture contract (site CSS compatibility)", () => {
  it("enriched card has data-url attribute for future reprocessing", async () => {
    mockFetch([{ url: "https://example.com", html: OG_FULL_HTML }]);

    const input =
      '<div class="link-card"><a href="https://example.com" data-url="https://example.com" target="_blank" rel="noopener noreferrer">https://example.com</a></div>';
    const result = await enrichLinkCards(input);
    expect(result).toContain('data-url="https://example.com"');
  });

  it("wrapper div has class='link-card' (CSS selector anchor)", () => {
    const og: OgData = { title: "T", description: null, image: null, favicon: null };
    const html = buildLinkCardHtml("https://example.com", og);
    expect(html).toMatch(/class="link-card(?:\s|")/);
  });

  it("inner <a> has target=_blank and rel=noopener noreferrer (security)", () => {
    const og: OgData = { title: "T", description: null, image: null, favicon: null };
    const html = buildLinkCardHtml("https://example.com", og);
    expect(html).toContain('target="_blank"');
    expect(html).toContain('rel="noopener noreferrer"');
  });

  it("link-card__body contains title and meta children", () => {
    const og: OgData = {
      title: "Title",
      description: "Desc",
      image: null,
      favicon: "https://example.com/favicon.ico",
    };
    const html = buildLinkCardHtml("https://example.com", og);
    // __body should contain __title, optionally __description, __meta
    const bodyMatch = html.match(/<div class="link-card__body">([\s\S]*?)<\/div>/);
    expect(bodyMatch).not.toBeNull();
    expect(bodyMatch![1]).toContain('link-card__title');
    expect(bodyMatch![1]).toContain('link-card__meta');
  });
});
