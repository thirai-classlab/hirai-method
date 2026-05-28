/**
 * PlantUML processor — converts <pre data-lang="plantuml"> blocks in HTML to
 * <img> tags pointing at CloudFront-served SVGs.
 *
 * Pipeline per block:
 *   1. Extract source text from <pre data-lang="plantuml"><code>...</code></pre>
 *   2. Decode minimal HTML entities (&lt; &gt; &amp; &quot; &#39;)
 *   3. Skip empty source
 *   4. Call renderPlantUml(source) → { svg, cacheKey }
 *   5. Build S3 key: plantuml/<contentType>/<slug>/<cacheKey>.svg
 *   6. objectExists(key) → upload only when not cached (idempotency)
 *   7. Replace block with <img src="<cdnUrl>" data-plantuml-source="<b64>" alt="PlantUML diagram">
 *      — omit data-plantuml-source when source > 4 KB
 *   8. On PlantUMLRenderError: replace with <pre><code class="language-plantuml">...</code></pre>
 *      + <!-- PlantUML render failed: <reason> --> comment
 *
 * Design doc: /Users/t.hirai/work/classlab-weekly-news/docs/plantuml-integration.md §2-D, §3, §6 Sub-2
 */

import {
  renderPlantUml,
  PlantUMLRenderError,
} from "./plantuml-renderer.js";
import {
  uploadToS3,
  objectExists,
  cloudFrontUrl,
} from "./s3.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ProcessPlantUMLOptions {
  slug: string;
  contentType: "knowledge" | "tech_article" | "issue";
}

export interface PlantUMLReplacement {
  /** 8-char hex cache key */
  cacheKey: string;
  /** plantuml/<contentType>/<slug>/<cacheKey>.svg */
  s3Key: string;
  /** CloudFront URL */
  cdnUrl: string;
  /** Original source byte length (debug) */
  sourceBytes: number;
  /** true when the block was kept as-is due to render error */
  skipped: boolean;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DATA_PLANTUML_SOURCE_MAX_BYTES = 4096;

/** Allowed slug pattern: alphanumeric and hyphens only, 1–200 chars. */
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,199}$/i;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Minimal HTML entity decode for code block contents.
 * Covers the most common entities produced by markdown renderers.
 */
function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Process all <pre data-lang="plantuml"> blocks in the given HTML string.
 * Returns the transformed HTML and an array of replacement metadata.
 */
export async function processPlantUMLBlocks(
  html: string,
  options: ProcessPlantUMLOptions,
): Promise<{ html: string; replacements: PlantUMLReplacement[] }> {
  const { slug, contentType } = options;

  // Validate slug to prevent attribute injection and path traversal
  if (!SLUG_RE.test(slug)) {
    throw new Error(`Invalid slug: "${slug}"`);
  }

  const replacements: PlantUMLReplacement[] = [];

  // Match <pre data-lang="plantuml"><code>...</code></pre>
  // The regex captures the inner code content (including newlines).
  const BLOCK_RE =
    /<pre\s+data-lang="plantuml"><code>([\s\S]*?)<\/code><\/pre>/g;

  let result = html;
  let offset = 0; // track position shift due to replacements

  // Collect all matches first so we can process sequentially without regex
  // state issues caused by mutating the string mid-iteration.
  const matches: Array<{ index: number; fullMatch: string; inner: string }> =
    [];

  let m: RegExpExecArray | null;
  const re = new RegExp(BLOCK_RE.source, "g");
  while ((m = re.exec(html)) !== null) {
    matches.push({
      index: m.index,
      fullMatch: m[0],
      inner: m[1] ?? "",
    });
  }

  for (const match of matches) {
    const rawSource = decodeHtmlEntities(match.inner);

    // Skip empty source — keep original markup, no replacement entry
    if (rawSource.trim() === "") {
      continue;
    }

    const adjustedIndex = match.index + offset;

    try {
      const { svg, cacheKey, width, height } = await renderPlantUml(rawSource);

      const s3Key = `plantuml/${contentType}/${slug}/${cacheKey}.svg`;
      const cdnUrl = cloudFrontUrl(s3Key);

      const exists = await objectExists(s3Key);
      if (!exists) {
        await uploadToS3(s3Key, Buffer.from(svg, "utf8"), "image/svg+xml");
      }

      const sourceBytes = Buffer.from(rawSource, "utf8").byteLength;
      const b64 =
        sourceBytes <= DATA_PLANTUML_SOURCE_MAX_BYTES
          ? Buffer.from(rawSource, "utf8").toString("base64")
          : null;

      const attrs: string[] = [`src="${cdnUrl}"`];
      if (width > 0 && height > 0) {
        attrs.push(`width="${width}"`, `height="${height}"`);
      }
      if (b64) attrs.push(`data-plantuml-source="${b64}"`);
      attrs.push(`alt="PlantUML diagram"`);
      const imgTag = `<img ${attrs.join(" ")}>`;

      result =
        result.slice(0, adjustedIndex) +
        imgTag +
        result.slice(adjustedIndex + match.fullMatch.length);

      offset += imgTag.length - match.fullMatch.length;

      replacements.push({
        cacheKey,
        s3Key,
        cdnUrl,
        sourceBytes,
        skipped: false,
      });
    } catch (err) {
      if (err instanceof PlantUMLRenderError) {
        const reason = err.message;
        const statusLabel = err.httpStatus === 0 ? "network" : String(err.httpStatus);
        console.warn(
          `[plantuml] render failed: ${reason} (status=${statusLabel}) slug=${slug}`,
        );
        const fallback =
          `<pre><code class="language-plantuml">${match.inner}</code></pre>` +
          `<!-- PlantUML render failed: ${reason} -->`;

        result =
          result.slice(0, adjustedIndex) +
          fallback +
          result.slice(adjustedIndex + match.fullMatch.length);

        offset += fallback.length - match.fullMatch.length;

        replacements.push({
          cacheKey: "",
          s3Key: "",
          cdnUrl: "",
          sourceBytes: Buffer.from(rawSource, "utf8").byteLength,
          skipped: true,
        });
      } else {
        throw err;
      }
    }
  }

  return { html: result, replacements };
}
