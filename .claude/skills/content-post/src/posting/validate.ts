/**
 * validate.ts — frontmatter + Markdown body の事前チェック
 *
 * 設計書 `docs/phase-8-posting-skill-design.md` L47-65 Step 1 に対応。
 * plan: `docs/pdca/phase-8-wave-e1/plan.md` §8.E.1
 *
 * 公開 API:
 *   validateInput(raw, { templates }) → ValidationResult
 *
 * ポリシー:
 *   - 構造的に投稿を止めるべき問題 → errors (ok=false)
 *   - LLM 補完や運用者の判断で埋められる問題 → warnings (ok は他の要因次第)
 *   - body 最小文字数 / 必須セクション欠損は warning（Wave E2 以降で Haiku が補完する余地）
 */

import { parseMarkdown, type Frontmatter } from "../lib/markdown.js";
import {
  validateRequiredSections,
  type Template,
  type TemplateRegistry,
} from "../lib/templates.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * 投稿パイプラインで扱うコンテンツタイプ（DB テーブル名に合わせた複数形）。
 * `lib/templates.ts` の ContentType (`knowledge | tech_article | weekly_issue`)
 * とは命名規則が異なる（templates 側は単数形）。`toTemplateType()` で相互変換。
 */
export type PostingContentType =
  | "knowledge"
  | "tech_articles"
  | "weekly_issues";

export const TECH_ARTICLE_SUBTYPES = [
  "deepdive",
  "handson",
  "comparison",
  "casestudy",
] as const;
export type TechArticleSubtype = (typeof TECH_ARTICLE_SUBTYPES)[number];

export interface ValidationError {
  field: string;
  message: string;
}

export interface ValidationWarning {
  field: string;
  message: string;
}

export interface ValidationResult {
  ok: boolean;
  errors: ValidationError[];
  warnings: ValidationWarning[];
  frontmatter: Frontmatter;
  body: string;
}

export interface ValidateOptions {
  templates: TemplateRegistry;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const TITLE_MAX = 120;
const TITLE_MIN = 1;
const SLUG_RE = /^[a-z0-9-]{3,80}$/;
const TAG_MAX_LEN = 40;
const TAG_MIN_LEN = 1;

const MIN_BODY_CHARS: Record<PostingContentType, number> = {
  knowledge: 200,
  tech_articles: 400,
  weekly_issues: 300,
};

const VALID_TYPES: PostingContentType[] = [
  "knowledge",
  "tech_articles",
  "weekly_issues",
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** posting の複数形 → templates.ts 側の単数形にマップ */
export function toTemplateType(
  t: PostingContentType,
): "knowledge" | "tech_article" | "weekly_issue" {
  if (t === "tech_articles") return "tech_article";
  if (t === "weekly_issues") return "weekly_issue";
  return "knowledge";
}

function isString(v: unknown): v is string {
  return typeof v === "string";
}

function isIso8601(v: string): boolean {
  // ISO8601 date or datetime (Z / +HH:MM). Allow what JSON-safe authors emit.
  if (!/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:\d{2})?)?$/
    .test(v)) {
    return false;
  }
  const d = new Date(v);
  return !Number.isNaN(d.getTime());
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export function validateInput(
  raw: string,
  opts: ValidateOptions,
): ValidationResult {
  const errors: ValidationError[] = [];
  const warnings: ValidationWarning[] = [];

  const { frontmatter, sections, raw: body } = parseMarkdown(raw);

  // --- title ---
  const title = frontmatter.title;
  if (!isString(title) || title.trim().length < TITLE_MIN) {
    errors.push({ field: "title", message: "title is required" });
  } else if (title.length > TITLE_MAX) {
    errors.push({
      field: "title",
      message: `title must be ≤${TITLE_MAX} chars (got ${title.length})`,
    });
  }

  // --- type ---
  const typeRaw = frontmatter.type;
  const type: PostingContentType | undefined =
    isString(typeRaw) && (VALID_TYPES as string[]).includes(typeRaw)
      ? (typeRaw as PostingContentType)
      : undefined;
  if (!type) {
    errors.push({
      field: "type",
      message: `type must be one of: ${VALID_TYPES.join(", ")}`,
    });
  }

  // --- subtype (only meaningful for tech_articles) ---
  const subtypeRaw = frontmatter.subtype;
  if (type === "tech_articles") {
    if (!isString(subtypeRaw)) {
      errors.push({
        field: "subtype",
        message: `subtype is required for tech_articles (one of: ${TECH_ARTICLE_SUBTYPES.join(", ")})`,
      });
    } else if (
      !(TECH_ARTICLE_SUBTYPES as readonly string[]).includes(subtypeRaw)
    ) {
      errors.push({
        field: "subtype",
        message: `subtype must be one of: ${TECH_ARTICLE_SUBTYPES.join(", ")} (got "${subtypeRaw}")`,
      });
    }
  }
  // For non-tech_articles, any subtype is silently ignored (no error, no warning).

  // --- slug format (optional field) ---
  const slug = frontmatter.slug;
  if (slug !== undefined && slug !== null) {
    if (!isString(slug) || !SLUG_RE.test(slug)) {
      errors.push({
        field: "slug",
        message: `slug must match /^[a-z0-9-]{3,80}$/ (got "${String(slug)}")`,
      });
    }
  }

  // --- author (optional, string) ---
  const author = frontmatter.author;
  if (author !== undefined && author !== null && !isString(author)) {
    errors.push({ field: "author", message: "author must be a string" });
  }

  // --- tags (optional, string[] with each element 1..40 chars) ---
  const tags = frontmatter.tags;
  if (tags !== undefined && tags !== null) {
    if (!Array.isArray(tags) || !tags.every(isString)) {
      errors.push({
        field: "tags",
        message: "tags must be an array of strings",
      });
    } else {
      for (const t of tags) {
        if (t.length < TAG_MIN_LEN || t.length > TAG_MAX_LEN) {
          errors.push({
            field: "tags",
            message: `each tag must be ${TAG_MIN_LEN}..${TAG_MAX_LEN} chars (offender: "${t}" len=${t.length})`,
          });
          break;
        }
      }
    }
  }

  // --- published_at (optional, ISO8601) ---
  const publishedAt = frontmatter.published_at;
  if (publishedAt !== undefined && publishedAt !== null) {
    if (!isString(publishedAt) || !isIso8601(publishedAt)) {
      errors.push({
        field: "published_at",
        message: "published_at must be an ISO8601 string",
      });
    }
  }

  // --- body length (warning only) ---
  if (type) {
    const min = MIN_BODY_CHARS[type];
    const bodyLen = body.trim().length;
    if (bodyLen < min) {
      warnings.push({
        field: "body",
        message: `body is ${bodyLen} chars, expected ≥${min} for ${type}`,
      });
    }
  }

  // --- required_sections (warning only — LLM can補完) ---
  if (type) {
    const templateType = toTemplateType(type);
    const subtypeForTemplate =
      type === "tech_articles" && isString(subtypeRaw) &&
      (TECH_ARTICLE_SUBTYPES as readonly string[]).includes(subtypeRaw)
        ? subtypeRaw
        : null;
    const key = subtypeForTemplate
      ? `${templateType}:${subtypeForTemplate}`
      : templateType;
    const tpl: Template | undefined = opts.templates[key];
    if (tpl) {
      const { ok, missing } = validateRequiredSections(tpl, sections);
      if (!ok) {
        warnings.push({
          field: "sections",
          message: `missing required sections: ${missing.join(", ")}`,
        });
      }
    }
    // If no template matches (e.g. unknown subtype), skip section check silently.
  }

  return {
    ok: errors.length === 0,
    errors,
    warnings,
    frontmatter,
    body,
  };
}
