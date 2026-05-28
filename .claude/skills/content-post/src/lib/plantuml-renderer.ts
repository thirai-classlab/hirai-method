/**
 * PlantUML renderer — fetch SVG from the public plantuml.com server.
 *
 * Pipeline:
 *   1. Validate source length (guard HTTP 414)
 *   2. injectTheme: insert `!theme blueprint` after @startuml unless user
 *      already specified a !theme directive
 *   3. plantuml-encoder.encode → build URL
 *   4. fetch with 1-retry / 500 ms backoff on failure
 *   5. Scan SVG for <script> tags (XSS guard)
 *   6. computeCacheKey: sha256(originalSource + "\n---THEME---\n" + themeDirective)[0..8]
 *   7. Return { svg, cacheKey, warnings }
 *
 * Design doc: /Users/t.hirai/work/classlab-weekly-news/docs/plantuml-integration.md
 */

import { createHash } from "node:crypto";
// plantuml-encoder is a CJS module; use createRequire for ESM compatibility.
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const plantumlEncoder = require("plantuml-encoder") as {
  encode: (source: string) => string;
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const THEME_DIRECTIVE = "!theme blueprint";

/** Maximum source length before we bail out to avoid HTTP 414 from the server. */
export const MAX_PLANTUML_CHARS = 100_000;

const PLANTUML_SERVER_BASE = "https://www.plantuml.com/plantuml/svg";
const RETRY_BACKOFF_MS = 500;

// ---------------------------------------------------------------------------
// Error class
// ---------------------------------------------------------------------------

export class PlantUMLRenderError extends Error {
  constructor(
    public readonly httpStatus: number,
    message: string,
  ) {
    super(message);
    this.name = "PlantUMLRenderError";
  }
}

// ---------------------------------------------------------------------------
// Return types
// ---------------------------------------------------------------------------

export interface InjectThemeResult {
  /** The (potentially modified) source to send to the server. */
  injected: string;
  /** True when injection was skipped for any reason. */
  skipped: boolean;
}

export interface RenderResult {
  svg: string;
  /** sha256(originalSource + "\n---THEME---\n" + themeDirective).slice(0, 8) */
  cacheKey: string;
  /** Non-empty when something noteworthy happened (e.g. theme injection was skipped). */
  warnings: string[];
  /** Width in px extracted from SVG root element; 0 when not available. */
  width: number;
  /** Height in px extracted from SVG root element; 0 when not available. */
  height: number;
}

// ---------------------------------------------------------------------------
// Pure helpers — exported for test-ability
// ---------------------------------------------------------------------------

/**
 * Inject THEME_DIRECTIVE after the first @startuml line.
 *
 * Skip conditions (returns skipped: true):
 *  - source has no @startuml (malformed)
 *  - source already contains a `!theme ` directive (whitespace-tolerant)
 */
export function injectTheme(source: string): InjectThemeResult {
  // Check if user already has an explicit !theme directive (leading spaces allowed)
  const hasExplicitTheme = /^\s*!theme\s/m.test(source);
  if (hasExplicitTheme) {
    return { injected: source, skipped: true };
  }

  // Locate the first @startuml
  const startumlIndex = source.indexOf("@startuml");
  if (startumlIndex === -1) {
    return { injected: source, skipped: true };
  }

  // Find the end of the @startuml line (the newline after it)
  const newlineAfterStartuml = source.indexOf("\n", startumlIndex);
  if (newlineAfterStartuml === -1) {
    // @startuml is the last line with no trailing newline — append theme
    return {
      injected: source + "\n" + THEME_DIRECTIVE,
      skipped: false,
    };
  }

  const before = source.slice(0, newlineAfterStartuml + 1);
  const after = source.slice(newlineAfterStartuml + 1);

  return {
    injected: before + THEME_DIRECTIVE + "\n" + after,
    skipped: false,
  };
}

/**
 * Compute a stable 8-character hex cache key.
 *
 * Key = sha256(source + "\n---THEME---\n" + themeDirective).hex()[0..8]
 *
 * Using the original (pre-injection) source so the key is stable even when
 * the encoder library changes.
 */
export function computeCacheKey(
  source: string,
  themeDirective: string,
): string {
  const input = source + "\n---THEME---\n" + themeDirective;
  return createHash("sha256").update(input, "utf8").digest("hex").slice(0, 8);
}

// ---------------------------------------------------------------------------
// Internal: SVG dimension extraction
// ---------------------------------------------------------------------------

const WIDTH_RE = /<svg\b[^>]*?\bwidth\s*=\s*["']?(\d+)(?:px)?["']?/i;
const HEIGHT_RE = /<svg\b[^>]*?\bheight\s*=\s*["']?(\d+)(?:px)?["']?/i;

function extractSvgDimensions(svg: string): { width: number; height: number } {
  const wm = WIDTH_RE.exec(svg);
  const hm = HEIGHT_RE.exec(svg);
  const width = wm ? parseInt(wm[1]!, 10) : 0;
  const height = hm ? parseInt(hm[1]!, 10) : 0;
  return { width, height };
}

// ---------------------------------------------------------------------------
// Internal: sleep helper
// ---------------------------------------------------------------------------

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Internal: single fetch attempt
// ---------------------------------------------------------------------------

async function fetchSvg(url: string): Promise<{ ok: boolean; status: number; body: string }> {
  const res = await fetch(url);
  const body = await res.text();
  return { ok: res.ok, status: res.status, body };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Render a PlantUML source string to SVG via the public plantuml.com server.
 *
 * @throws {PlantUMLRenderError} on size guard, persistent HTTP error, or XSS detection.
 */
export async function renderPlantUml(source: string): Promise<RenderResult> {
  // 1. Size guard
  if (source.length > MAX_PLANTUML_CHARS) {
    throw new PlantUMLRenderError(0, "source too large");
  }

  // 2. Theme injection
  const { injected, skipped } = injectTheme(source);
  const warnings: string[] = [];
  if (skipped) {
    warnings.push("source has explicit !theme, skipping injection");
  }

  // 3. Encode + build URL
  const encoded = plantumlEncoder.encode(injected);
  const url = `${PLANTUML_SERVER_BASE}/${encoded}`;

  // 4. Fetch with 1 retry
  let result: { ok: boolean; status: number; body: string };
  try {
    result = await fetchSvg(url);
  } catch {
    // Network error — retry after backoff
    await sleep(RETRY_BACKOFF_MS);
    try {
      result = await fetchSvg(url);
    } catch {
      throw new PlantUMLRenderError(0, "network error after retry");
    }
  }

  if (!result.ok) {
    // HTTP error — retry once
    await sleep(RETRY_BACKOFF_MS);
    try {
      result = await fetchSvg(url);
    } catch {
      throw new PlantUMLRenderError(0, "network error after retry");
    }
    if (!result.ok) {
      throw new PlantUMLRenderError(
        result.status,
        `PlantUML server returned HTTP ${result.status}`,
      );
    }
  }

  const svg = result.body;

  // 5. XSS scan
  if (/<script\b/i.test(svg)) {
    throw new PlantUMLRenderError(0, "SVG contains <script>");
  }

  // 6. Cache key (based on original source, not injected)
  const cacheKey = computeCacheKey(source, THEME_DIRECTIVE);

  // 7. Extract SVG dimensions
  const { width, height } = extractSvgDimensions(svg);

  return { svg, cacheKey, warnings, width, height };
}
