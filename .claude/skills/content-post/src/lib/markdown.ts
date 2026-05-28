/**
 * Markdown → .rich-* HTML converter.
 *
 * Pipeline:
 *   1. `parseMarkdown(source)` — split frontmatter + pick up all headings
 *   2. `renderToHtml(source, template)`
 *      a. Strip frontmatter
 *      b. Pre-process GFM alerts (`> [!note]`) into raw HTML blockquotes
 *      c. Pre-process custom containers (`:::name ... :::`) into raw HTML wrappers,
 *         tagged so that post-processing can promote special cases (e.g. `:::steps`
 *         rewriting `<ol>` / `<li>` classes, `:::compare` promoting `<table>` class,
 *         `:::keypoints` rewriting `<ul>`).
 *      d. Run `marked` with a custom renderer for headings / links / tables / code /
 *         inline code, and a tokenizer extension for `[[Kbd]]`.
 *      e. Post-process the HTML string for structural promotions (step items,
 *         keypoints ul, compare table, checkbox ul).
 *
 * Spec: /Users/t.hirai/work/classlab-weekly-news/docs/rich-content-classes.md §4
 */

import { Marked, type RendererObject, type TokenizerAndRendererExtension } from "marked";
import { parse as parseYaml } from "yaml";
import type { Template } from "./templates.js";
import type { PlantUMLReplacement as _PlantUMLReplacement, ProcessPlantUMLOptions } from "./plantuml-processor.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type Frontmatter = Record<string, unknown>;

export interface ParsedSection {
  heading: string;
  level: number;
}

export interface ParsedMarkdown {
  frontmatter: Frontmatter;
  sections: ParsedSection[];
  /** The body after the frontmatter block has been stripped. */
  raw: string;
}

// Re-export PlantUMLReplacement so consumers can import from a single module.
export type { _PlantUMLReplacement as PlantUMLReplacement };

export interface RenderResult {
  html: string;
  appliedClasses: string[];
  /** Populated by renderToHtmlAsync when options are provided. */
  plantumlReplacements?: _PlantUMLReplacement[];
}

// ---------------------------------------------------------------------------
// Heading anchor ID — slug used for id attributes and TOC href anchors
//
// Algorithm (Unicode-aware, matches GitHub-style slugger and marked's default):
//   1. Lowercase
//   2. Replace every run of chars that are NOT Unicode letters, digits, or hyphens
//      with a single hyphen (uses \p{L}\p{N} Unicode property escapes)
//   3. Collapse consecutive hyphens
//   4. Trim leading/trailing hyphens
//
// Unicode support is required so that Japanese/CJK headings generate non-empty
// slugs that match the <a href="#..."> anchors the markdown TOC produces.
// E.g. "1. 西側はモノづくりを忘れ" → "1-西側はモノづくりを忘れ"
//
// Export allows callers (posting agents, tests) to generate matching anchors.
// ---------------------------------------------------------------------------

export function headingAnchorId(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}-]+/gu, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
}

// ---------------------------------------------------------------------------
// Heading → class lookup (from rich-content-classes.md §4.3)
// ---------------------------------------------------------------------------

const HEADING_CLASS_TABLE: Record<string, string> = {
  概要: "rich-summary",
  背景: "rich-background",
  参考資料: "rich-references",
  TL$DR: "rich-tldr", // placeholder; TL;DR handled separately because of ';' char
};

function headingClassFor(text: string, tpl: Template): string | undefined {
  // 1. Template-declared class wins (covers sections like 実例 / ハマりどころ).
  const trimmed = text.trim();
  const required = Array.isArray(tpl?.required_sections) ? tpl.required_sections : [];
  const optional = Array.isArray(tpl?.optional_sections) ? tpl.optional_sections : [];
  for (const spec of [...required, ...optional]) {
    if (spec.heading.trim() === trimmed && spec.class) {
      return spec.class;
    }
  }
  // 2. Global fallback for the spec's heading-driven classes.
  if (trimmed === "TL;DR") return "rich-tldr";
  return HEADING_CLASS_TABLE[trimmed];
}

// ---------------------------------------------------------------------------
// Container mapping (rich-content-classes.md §4.2)
// ---------------------------------------------------------------------------

interface ContainerRule {
  openTag: string;
  closeTag: string;
  /** Marker used for post-processing to promote children (e.g. ol → steps). */
  kind?: "steps" | "keypoints" | "compare";
}

const CONTAINER_RULES: Record<string, ContainerRule> = {
  tldr: { openTag: '<div class="rich-tldr">', closeTag: "</div>" },
  summary: { openTag: '<div class="rich-summary">', closeTag: "</div>" },
  goal: { openTag: '<div class="rich-goal">', closeTag: "</div>" },
  prereq: { openTag: '<div class="rich-prerequisites">', closeTag: "</div>" },
  prerequisites: { openTag: '<div class="rich-prerequisites">', closeTag: "</div>" },
  background: { openTag: '<div class="rich-background">', closeTag: "</div>" },
  example: { openTag: '<div class="rich-example">', closeTag: "</div>" },
  pitfall: { openTag: '<div class="rich-pitfall">', closeTag: "</div>" },
  references: { openTag: '<div class="rich-references">', closeTag: "</div>" },
  steps: { openTag: '<div data-rich-container="steps">', closeTag: "</div>", kind: "steps" },
  checklist: { openTag: '<div data-rich-container="checklist">', closeTag: "</div>" },
  keypoints: { openTag: '<div data-rich-container="keypoints">', closeTag: "</div>", kind: "keypoints" },
  troubleshoot: { openTag: '<section class="rich-troubleshoot">', closeTag: "</section>" },
  recommend: { openTag: '<section class="rich-recommend">', closeTag: "</section>" },
  learnings: { openTag: '<div class="rich-learnings">', closeTag: "</div>" },
  next: { openTag: '<div class="rich-next">', closeTag: "</div>" },
  highlights: { openTag: '<section class="rich-highlights">', closeTag: "</section>" },
  editorial: { openTag: '<section class="rich-editorial">', closeTag: "</section>" },
  "source-section": { openTag: '<section class="rich-source-section">', closeTag: "</section>" },
  related: { openTag: '<aside class="rich-related">', closeTag: "</aside>" },
  "classlab-usage": { openTag: '<aside class="rich-callout--usage">', closeTag: "</aside>" },
  tags: { openTag: '<div class="rich-tags-inline">', closeTag: "</div>" },
  meta: { openTag: '<div class="rich-meta">', closeTag: "</div>" },
  section: { openTag: '<section class="rich-section">', closeTag: "</section>" },
  quote: { openTag: '<blockquote class="rich-quote">', closeTag: "</blockquote>" },
  compare: { openTag: '<div data-rich-container="compare">', closeTag: "</div>", kind: "compare" },
};

const ALERT_ALIASES: Record<string, "note" | "tip" | "warn" | "info" | "pitfall"> = {
  note: "note",
  tip: "tip",
  warning: "warn",
  warn: "warn",
  caution: "warn",
  info: "info",
  important: "info",
  pitfall: "pitfall",
};

function alertOpenTag(kind: string): string {
  if (kind === "pitfall") return '<div class="rich-pitfall">';
  return `<div class="rich-callout rich-callout--${kind}">`;
}

// ---------------------------------------------------------------------------
// Frontmatter
// ---------------------------------------------------------------------------

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/;

function splitFrontmatter(source: string): { frontmatter: Frontmatter; body: string } {
  const m = source.match(FRONTMATTER_RE);
  if (!m) return { frontmatter: {}, body: source };
  let parsed: unknown = {};
  try {
    parsed = parseYaml(m[1]!);
  } catch {
    parsed = {};
  }
  const body = source.slice(m[0].length);
  return {
    frontmatter:
      parsed && typeof parsed === "object" ? (parsed as Frontmatter) : {},
    body,
  };
}

// ---------------------------------------------------------------------------
// Section extraction
// ---------------------------------------------------------------------------

function extractSections(body: string): ParsedSection[] {
  const sections: ParsedSection[] = [];
  const lines = body.split(/\r?\n/);
  let inFence = false;
  for (const line of lines) {
    if (/^```/.test(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    const m = line.match(/^(#{1,6})\s+(.+?)\s*$/);
    if (m) {
      sections.push({ level: m[1]!.length, heading: m[2]!.trim() });
    }
  }
  return sections;
}

// ---------------------------------------------------------------------------
// Pre-processing (before handing off to marked)
// ---------------------------------------------------------------------------

function preprocessAlerts(source: string): string {
  // Collapse `> [!kind]\n> line1\n> line2` into a raw-HTML block so marked
  // does not see them as regular blockquotes.
  const lines = source.split(/\r?\n/);
  const out: string[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    const m = line.match(/^>\s*\[!(note|tip|warning|warn|info|caution|important|pitfall)\]\s*$/i);
    if (!m) {
      out.push(line);
      i += 1;
      continue;
    }
    const kind = ALERT_ALIASES[m[1]!.toLowerCase()]!;
    i += 1;
    const inner: string[] = [];
    while (i < lines.length && /^>\s?/.test(lines[i]!)) {
      inner.push(lines[i]!.replace(/^>\s?/, ""));
      i += 1;
    }
    // Use an HTML block separated by blank lines so marked processes the
    // inner content as markdown.
    out.push("");
    out.push(alertOpenTag(kind));
    out.push("");
    out.push(inner.join("\n"));
    out.push("");
    out.push("</div>");
    out.push("");
  }
  return out.join("\n");
}

function preprocessContainers(source: string): string {
  // `:::name` ... `:::` — non-nested, line-anchored. Each match becomes an
  // HTML open/close wrapper with a blank line around it so marked treats the
  // inner content as markdown.
  const lines = source.split(/\r?\n/);
  const out: string[] = [];
  const stack: ContainerRule[] = [];
  let inFence = false;

  for (const line of lines) {
    if (/^```/.test(line)) {
      inFence = !inFence;
      out.push(line);
      continue;
    }
    if (inFence) {
      out.push(line);
      continue;
    }
    const open = line.match(/^:::(\S+)\s*$/);
    const close = /^:::\s*$/.test(line);
    if (open) {
      const name = open[1]!.toLowerCase();
      const rule = CONTAINER_RULES[name];
      if (rule) {
        stack.push(rule);
        out.push("");
        out.push(rule.openTag);
        out.push("");
        continue;
      }
      // Unknown container: leave as-is so that later passes or authors see the
      // literal line (avoids silent data loss).
      out.push(line);
      continue;
    }
    if (close && stack.length > 0) {
      const rule = stack.pop()!;
      out.push("");
      out.push(rule.closeTag);
      out.push("");
      continue;
    }
    out.push(line);
  }
  // If unbalanced, close remaining (best-effort; later a validator can warn).
  while (stack.length > 0) {
    const rule = stack.pop()!;
    out.push(rule.closeTag);
  }
  return out.join("\n");
}

// ---------------------------------------------------------------------------
// Post-processing (after marked) — structural promotions
// ---------------------------------------------------------------------------

function postprocess(html: string): string {
  // 1. `:::steps` wrapper: inner <ol> gets class=rich-steps and its <li>
  //    children get class=rich-steps__item. Drop the wrapper div.
  html = html.replace(
    /<div data-rich-container="steps">([\s\S]*?)<\/div>/g,
    (_m, inner: string) => {
      const withOl = inner.replace(
        /<ol(\s[^>]*)?>([\s\S]*?)<\/ol>/,
        (_m2, attrs: string | undefined, body: string) => {
          const attrStr = attrs ?? "";
          const bodyWithClasses = body.replace(
            /<li(\s[^>]*)?>/g,
            (_m3, liAttrs: string | undefined) => {
              const a = liAttrs ?? "";
              if (/class="/.test(a)) {
                return `<li${a.replace(
                  /class="([^"]*)"/,
                  (_mm, cls: string) => `class="${cls} rich-steps__item"`,
                )}>`;
              }
              return `<li${a} class="rich-steps__item">`;
            },
          );
          return `<ol${attrStr} class="rich-steps">${bodyWithClasses}</ol>`;
        },
      );
      return withOl;
    },
  );

  // 2. `:::keypoints` → rewrite first <ul> as class=rich-keypoints.
  html = html.replace(
    /<div data-rich-container="keypoints">([\s\S]*?)<\/div>/g,
    (_m, inner: string) => {
      return inner.replace(
        /<ul(\s[^>]*)?>/,
        (_m2, attrs: string | undefined) =>
          `<ul${attrs ?? ""} class="rich-keypoints">`,
      );
    },
  );

  // 3. `:::compare` → promote inner table to class="rich-table rich-table--compare".
  html = html.replace(
    /<div data-rich-container="compare">([\s\S]*?)<\/div>/g,
    (_m, inner: string) => {
      return inner.replace(
        /<table class="rich-table">/,
        '<table class="rich-table rich-table--compare">',
      );
    },
  );

  // 4. `:::checklist` → keep inner as-is but ensure ul has rich-checklist.
  html = html.replace(
    /<div data-rich-container="checklist">([\s\S]*?)<\/div>/g,
    (_m, inner: string) => {
      return inner.replace(
        /<ul(\s[^>]*)?>/,
        (_m2, attrs: string | undefined) =>
          `<ul${attrs ?? ""} class="rich-checklist">`,
      );
    },
  );

  // 5. URL-only paragraph → link-card div.
  //
  // Pattern: <p><a href="URL">URL</a></p> where href === link text and URL
  // starts with http(s)://. These originate from autolinks or markdown like
  // `https://example.com` written as a lone paragraph.
  //
  // The inner <a> is mandatory for clickability and accessibility.
  // target="_blank" + rel="noopener noreferrer" opens safely in a new tab.
  // data-url is kept for future OG-fetch use.
  //
  // We use a post-process regex rather than AST manipulation so the approach
  // stays consistent with the other structural promotions above.
  html = html.replace(
    /<p><a\s[^>]*href="(https?:\/\/[^"]+)"[^>]*>\1<\/a><\/p>/g,
    (_m, url: string) =>
      `<div class="link-card"><a href="${url}" data-url="${url}" target="_blank" rel="noopener noreferrer">${url}</a></div>`,
  );

  return html;
}

// ---------------------------------------------------------------------------
// Security — URL sanitization
// ---------------------------------------------------------------------------

const UNSAFE_SCHEMES = /^(javascript|vbscript|data:text\/html|data:application\/xhtml)/i;

function sanitizeHref(href: string): string {
  const trimmed = href.trim();
  if (UNSAFE_SCHEMES.test(trimmed)) return "#";
  // Permit mailto:, tel:, http(s), relative, fragment.
  return trimmed;
}

function isExternalUrl(href: string): boolean {
  return /^https?:\/\//i.test(href);
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ---------------------------------------------------------------------------
// Code block raw encoding for clipboard support (Task #48 Wave 48.3)
//
// 投稿エージェントが生成する <pre> タグに raw ソーステキストを保持するため、
// data-raw 属性で encoding 済の値を埋め込む。本リポ classlab-weekly-news 側の
// CodeBlockEnhancer (src/lib/code-block-decode.ts) が同形式でデコードする。
//
// ルール:
//   - 500 文字未満: encodeURIComponent (encoding="url")
//     → ASCII / 日本語ともに HTML 属性安全 (" や < は %22 / %3C にエスケープ)
//   - 500 文字以上: base64 (UTF-8 bytes) (encoding="base64")
//     → 長いコードで URL エンコード比率が高くなりサイズが膨張するのを防ぐ
//
// 設計書: /Users/t.hirai/work/classlab-weekly-news/docs/task-48-code-block-enhancement-design.md §C.4
// ---------------------------------------------------------------------------

const CODE_RAW_BASE64_THRESHOLD = 500;

function encodeRawForCodeBlock(code: string): {
  raw: string;
  encoding: "url" | "base64";
} {
  if (code.length >= CODE_RAW_BASE64_THRESHOLD) {
    return {
      raw: Buffer.from(code, "utf-8").toString("base64"),
      encoding: "base64",
    };
  }
  return {
    raw: encodeURIComponent(code),
    encoding: "url",
  };
}

// ---------------------------------------------------------------------------
// Claude Code structured rendering (Task #48 Wave 48.7)
//
// 著者は claude-code 言語ブロックを <prompt>...</prompt> / <output>...</output>
// で構造化する。renderer.code() はこれを <div class="claude-line claude-line--prompt">
// / <div class="claude-line claude-line--output"> 構造化 HTML に変換する。
//
// 後方互換 (案 A): タグなしの旧記法は <output> 扱い + console.warn。
// 既存記事は再投稿不要で動作するが、新規記事では <prompt>/<output> 必須。
//
// 設計: Wave 48.7 prompt §「やること > ステップ 1」
// ---------------------------------------------------------------------------

const CLAUDE_CODE_LANGS: ReadonlySet<string> = new Set([
  "claude-code",
  "claude",
  "claude-prompt",
  "cc",
]);

interface ClaudeSegment {
  type: "prompt" | "output";
  text: string;
}

function parseClaudeSegments(code: string): ClaudeSegment[] {
  const re = /<(prompt|output)>([\s\S]*?)<\/\1>/g;
  const result: ClaudeSegment[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(code)) !== null) {
    result.push({
      type: m[1] as "prompt" | "output",
      text: m[2] ?? "",
    });
  }
  return result;
}

function renderClaudeSegment(seg: ClaudeSegment): string {
  const escaped = escapeHtml(seg.text);
  if (seg.type === "prompt") {
    return [
      '<div class="claude-line claude-line--prompt">',
      '<span class="claude-prompt-mark">❯</span>',
      `<span class="claude-prompt-text">${escaped}</span>`,
      "</div>",
    ].join("");
  }
  return `<div class="claude-line claude-line--output">${escaped}</div>`;
}

function renderClaudeCodeBlock(code: string): string {
  const segments = parseClaudeSegments(code);
  if (segments.length === 0) {
    // 後方互換: タグなしの旧記法は <output> 扱い + warn。
    // 末尾の trailing newline は表示の見た目を保つため trimEnd で 1 段だけ落とす。
    console.warn(
      "[content-post] claude-code block contains no <prompt>/<output> tags; treating entire body as <output>. New articles should use the structured form.",
    );
    segments.push({ type: "output", text: code.replace(/\n+$/, "") });
  }
  return segments.map(renderClaudeSegment).join("\n");
}

// ---------------------------------------------------------------------------
// Keystroke tokenizer extension ([[Cmd+S]] → <kbd class=rich-kbd>)
// ---------------------------------------------------------------------------

const kbdExtension: TokenizerAndRendererExtension = {
  name: "richKbd",
  level: "inline",
  start(src: string) {
    const idx = src.indexOf("[[");
    return idx === -1 ? undefined : idx;
  },
  tokenizer(src: string) {
    const m = /^\[\[([^\]]+?)\]\]/.exec(src);
    if (!m) return undefined;
    return {
      type: "richKbd",
      raw: m[0],
      text: m[1]!,
    };
  },
  renderer(token) {
    const text = (token as { text?: string }).text ?? "";
    return `<kbd class="rich-kbd">${escapeHtml(text)}</kbd>`;
  },
};

// ---------------------------------------------------------------------------
// Renderer factory
// ---------------------------------------------------------------------------

function buildRenderer(
  tpl: Template,
  applied: Set<string>,
): RendererObject {
  // Track heading id usage counts within a single document to deduplicate.
  const idCounts = new Map<string, number>();
  let headingCounter = 0;

  function uniqueHeadingId(base: string): string {
    // When the text produces no ASCII-safe slug (e.g. pure Japanese), fall
    // back to a positional id so the attribute is always non-empty.
    const key = base.length > 0 ? base : `heading-${++headingCounter}`;
    const count = idCounts.get(key) ?? 0;
    idCounts.set(key, count + 1);
    return count === 0 ? key : `${key}-${count + 1}`;
  }

  return {
    heading({ tokens, depth }) {
      // Render inner markdown tokens to text/HTML using this renderer.
      // `this.parser.parseInline(tokens)` is the marked v15 idiom.
      const text = (this as unknown as { parser: { parseInline(t: unknown[]): string } })
        .parser.parseInline(tokens as unknown[]);
      const plain = tokens
        .map((t) => ("text" in t ? (t as { text: string }).text : ""))
        .join("")
        .trim();

      const baseId = headingAnchorId(plain);
      const id = uniqueHeadingId(baseId);
      const idAttr = ` id="${id}"`;

      // Source section pattern: ## [source:slug]
      const srcMatch = plain.match(/^\[source:([^\]]+)\]$/);
      if (srcMatch) {
        applied.add("rich-source-section");
        const slug = srcMatch[1]!;
        return `<section class="rich-source-section" data-source="${escapeHtml(slug)}"><h${depth}${idAttr}>${text}</h${depth}>\n`;
      }

      const cls = headingClassFor(plain, tpl);
      if (cls) {
        applied.add(cls);
        return `<h${depth}${idAttr} class="${cls}">${text}</h${depth}>\n`;
      }
      return `<h${depth}${idAttr}>${text}</h${depth}>\n`;
    },

    link({ href, title, tokens }) {
      const safe = sanitizeHref(href);
      const text = (this as unknown as { parser: { parseInline(t: unknown[]): string } })
        .parser.parseInline(tokens as unknown[]);
      const titleAttr = title ? ` title="${escapeHtml(title)}"` : "";
      if (isExternalUrl(safe)) {
        return `<a href="${escapeHtml(safe)}"${titleAttr} target="_blank" rel="noopener noreferrer">${text}</a>`;
      }
      return `<a href="${escapeHtml(safe)}"${titleAttr}>${text}</a>`;
    },

    codespan({ text }) {
      applied.add("rich-inline-code");
      return `<code class="rich-inline-code">${escapeHtml(text)}</code>`;
    },

    code({ text, lang }) {
      const { raw, encoding } = encodeRawForCodeBlock(text);
      const dataAttrs = ` data-raw="${raw}" data-raw-encoding="${encoding}"`;
      if (lang === "diff") {
        applied.add("rich-code-diff");
        const escaped = escapeHtml(text);
        return `<pre class="rich-code-diff"${dataAttrs}><code>${escaped}</code></pre>\n`;
      }
      // Wave 48.7: claude-code (alias claude / claude-prompt / cc) は <prompt>/<output>
      // タグ構造化の専用レンダリング
      if (lang && CLAUDE_CODE_LANGS.has(lang)) {
        const inner = renderClaudeCodeBlock(text);
        const langAttr = ` data-lang="${escapeHtml(lang)}"`;
        return `<pre${langAttr}${dataAttrs}><code>${inner}</code></pre>\n`;
      }
      const langAttr = lang ? ` data-lang="${escapeHtml(lang)}"` : "";
      const escaped = escapeHtml(text);
      return `<pre${langAttr}${dataAttrs}><code>${escaped}</code></pre>\n`;
    },

    table(token) {
      // token: { header: TableCell[], rows: TableCell[][] }
      applied.add("rich-table");
      const headerHtml = token.header
        .map(
          (cell) =>
            `<th>${(this as unknown as { parser: { parseInline(t: unknown[]): string } }).parser.parseInline(cell.tokens as unknown[])}</th>`,
        )
        .join("");
      const rowsHtml = token.rows
        .map(
          (row) =>
            "<tr>" +
            row
              .map(
                (cell) =>
                  `<td>${(this as unknown as { parser: { parseInline(t: unknown[]): string } }).parser.parseInline(cell.tokens as unknown[])}</td>`,
              )
              .join("") +
            "</tr>",
        )
        .join("");
      return `<table class="rich-table"><thead><tr>${headerHtml}</tr></thead><tbody>${rowsHtml}</tbody></table>\n`;
    },

    list(token) {
      const parser = (this as unknown as { parser: { parse(t: unknown[]): string } }).parser;
      const items = token.items as Array<{
        tokens: unknown[];
        task: boolean;
        checked?: boolean;
      }>;

      // Detect checklist: every item has task=true
      const allTasks = items.length > 0 && items.every((it) => it.task);
      if (allTasks && !token.ordered) {
        applied.add("rich-checklist");
        const itemsHtml = items
          .map((it) => {
            const body = parser.parse(it.tokens);
            // Strip the leading "[ ] " or "[x] " that marked leaves inside the paragraph.
            const stripped = body.replace(/<input[^>]*>\s*/i, "");
            const checked: boolean = it.checked === true;
            return `<li${checked ? ' data-checked="true"' : ""}>${stripped}</li>`;
          })
          .join("");
        return `<ul class="rich-checklist">${itemsHtml}</ul>\n`;
      }

      const tag = token.ordered ? "ol" : "ul";
      const itemsHtml = items
        .map((it) => `<li>${parser.parse(it.tokens)}</li>`)
        .join("");
      return `<${tag}>${itemsHtml}</${tag}>\n`;
    },
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function parseMarkdown(source: string): ParsedMarkdown {
  const { frontmatter, body } = splitFrontmatter(source);
  return {
    frontmatter,
    sections: extractSections(body),
    raw: body,
  };
}

export function renderToHtml(source: string, template: Template): RenderResult {
  const { body } = splitFrontmatter(source);
  let md = preprocessAlerts(body);
  md = preprocessContainers(md);

  const applied = new Set<string>();
  const marked = new Marked({ gfm: true, async: false });
  marked.use({ extensions: [kbdExtension] });
  marked.use({ renderer: buildRenderer(template, applied) });

  let html = marked.parse(md) as string;
  html = postprocess(html);

  // Append structural classes picked up during postprocess.
  if (html.includes("rich-steps")) applied.add("rich-steps");
  if (html.includes("rich-keypoints")) applied.add("rich-keypoints");
  if (html.includes("rich-table--compare")) applied.add("rich-table--compare");
  if (html.includes("rich-pitfall")) applied.add("rich-pitfall");

  // Scan the HTML for alert callout variants that were inserted pre-marked.
  for (const v of ["note", "tip", "warn", "info"] as const) {
    if (html.includes(`rich-callout--${v}`)) {
      applied.add("rich-callout");
      applied.add(`rich-callout--${v}`);
    }
  }

  return { html, appliedClasses: [...applied] };
}

/**
 * Async variant of renderToHtml.
 *
 * When `options` is provided, runs processPlantUMLBlocks on the rendered HTML
 * and returns the replaced HTML along with PlantUML replacement metadata.
 *
 * When `options` is omitted, behaves identically to `renderToHtml` but wrapped
 * in a Promise. `plantumlReplacements` is `undefined` in that case.
 */
export async function renderToHtmlAsync(
  source: string,
  template: Template,
  options?: ProcessPlantUMLOptions,
): Promise<RenderResult> {
  const base = renderToHtml(source, template);

  if (!options) {
    return base;
  }

  // Lazily import to avoid loading the module (and its heavy deps) in sync paths.
  const { processPlantUMLBlocks } = await import("./plantuml-processor.js");
  const { html: processedHtml, replacements } = await processPlantUMLBlocks(
    base.html,
    options,
  );

  return {
    html: processedHtml,
    appliedClasses: base.appliedClasses,
    plantumlReplacements: replacements,
  };
}
