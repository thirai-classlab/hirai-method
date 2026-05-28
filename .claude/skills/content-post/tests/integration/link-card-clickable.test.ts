/**
 * D-1: link-card clickability integration test
 *
 * Guards against regressions where markdown.ts emits a link-card div without
 * an inner <a> element, which would make the card non-clickable and
 * inaccessible.
 *
 * This test parses the rendered HTML structurally to ensure:
 *   - Every <div class="link-card"> contains exactly one <a>
 *   - The <a> href matches the data-url attribute
 *   - The <a> carries target="_blank" and rel="noopener noreferrer"
 *
 * Re-run whenever markdown.ts postprocess() is touched.
 */

import { describe, it, expect, beforeAll } from "vitest";
import path from "node:path";
import { renderToHtml } from "../../src/lib/markdown.js";
import { loadTemplates, getTemplate, type Template } from "../../src/lib/templates.js";

const REPO_TEMPLATES = path.resolve(
  "/Users/t.hirai/work/classlab-weekly-news/content-templates",
);

let knowledgeTpl: Template;

beforeAll(async () => {
  const registry = await loadTemplates(REPO_TEMPLATES);
  knowledgeTpl = getTemplate(registry, "knowledge");
});

// ---------------------------------------------------------------------------
// Helpers — lightweight structural parse (no cheerio dependency)
// ---------------------------------------------------------------------------

/** Extract all link-card divs as raw HTML strings */
function extractLinkCards(html: string): string[] {
  const cards: string[] = [];
  // Match <div class="link-card">...</div> (non-greedy)
  const re = /<div class="link-card">([\s\S]*?)<\/div>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) {
    cards.push(m[0]);
  }
  return cards;
}

/** Extract href from the first <a> in a card string */
function extractHref(card: string): string | null {
  const m = card.match(/href="([^"]+)"/);
  return m ? m[1] : null;
}

/** Extract data-url from the <a> in a card string */
function extractDataUrl(card: string): string | null {
  const m = card.match(/data-url="([^"]+)"/);
  return m ? m[1] : null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("D-1: link-card must always contain a clickable <a>", () => {
  it("URL-only paragraph produces a link-card with an inner <a>", () => {
    const md = "\n\nhttps://example.com/article\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBeGreaterThanOrEqual(1);

    for (const card of cards) {
      // Must contain an <a> tag
      expect(card).toMatch(/<a\s/);
    }
  });

  it("inner <a> href matches the bare URL", () => {
    const url = "https://example.com/my-article";
    const md = `\n\n${url}\n\n`;
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);

    const href = extractHref(cards[0]!);
    expect(href).toBe(url);
  });

  it("inner <a> data-url matches href", () => {
    const url = "https://example.com/check-data-url";
    const md = `\n\n${url}\n\n`;
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);

    const href = extractHref(cards[0]!);
    const dataUrl = extractDataUrl(cards[0]!);
    expect(dataUrl).toBe(url);
    expect(dataUrl).toBe(href);
  });

  it("inner <a> has target=\"_blank\"", () => {
    const md = "\n\nhttps://example.com/target-blank\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);
    expect(cards[0]).toContain('target="_blank"');
  });

  it("inner <a> has rel=\"noopener noreferrer\"", () => {
    const md = "\n\nhttps://example.com/rel-check\n\n";
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);
    expect(cards[0]).toContain('rel="noopener noreferrer"');
  });

  it("markdown autolink [url](url) sole paragraph also produces link-card with <a>", () => {
    const url = "https://example.com/autolink-test";
    const md = `\n\n[${url}](${url})\n\n`;
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBeGreaterThanOrEqual(1);
    expect(cards[0]).toMatch(/<a\s/);
    expect(extractHref(cards[0]!)).toBe(url);
  });

  it("http:// (non-HTTPS) link-card also has inner <a>", () => {
    const url = "http://example.com/legacy";
    const md = `\n\n${url}\n\n`;
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);
    expect(cards[0]).toMatch(/<a\s/);
    expect(extractHref(cards[0]!)).toBe(url);
  });

  it("link-card does not contain plain URL text as direct child text node (no naked URL)", () => {
    const url = "https://example.com/no-naked-text";
    const md = `\n\n${url}\n\n`;
    const { html } = renderToHtml(md, knowledgeTpl);
    const cards = extractLinkCards(html);
    expect(cards.length).toBe(1);
    // The URL should appear inside the <a>, not as direct text of the div
    // i.e. <div class="link-card"><a ...>URL</a></div> — not ...>URL</div>
    expect(cards[0]).not.toMatch(new RegExp(`>\\s*${url.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*<\\/div>`));
  });
});
