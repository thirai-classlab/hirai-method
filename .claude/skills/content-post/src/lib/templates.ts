/**
 * Template loader for content-post skill.
 *
 * Reads YAML templates (`content-templates/*.yaml`) synced from the
 * classlab-weekly-news repo via `scripts/postinstall.ts`. Provides a
 * type-safe registry keyed by `${type}` or `${type}:${subtype}` and
 * validation helpers for required sections.
 *
 * Spec reference: /Users/t.hirai/work/classlab-weekly-news/docs/rich-content-classes.md
 */

import path from "node:path";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ContentType = "knowledge" | "tech_article" | "weekly_issue";
export type TechArticleSubtype =
  | "deepdive"
  | "handson"
  | "comparison"
  | "casestudy";

/** Required / optional section definition as declared in YAML. */
export interface SectionSpec {
  id: string;
  heading: string;
  heading_level: "h2" | "h3" | "h4";
  class?: string;
  position?: "top" | "body" | "bottom";
}

/** Custom syntax substitution defined per template. */
export interface SpecialSyntaxRule {
  pattern: string;
  replace_with: string;
}

export interface Template {
  type: ContentType;
  subtype: TechArticleSubtype | null;
  version: string;
  required_sections: SectionSpec[];
  optional_sections: SectionSpec[];
  special_syntax: SpecialSyntaxRule[];
  /** Source file the template was loaded from (absolute path). */
  sourceFile: string;
}

export type TemplateRegistry = Record<string, Template>;

/** A single parsed heading from an authored Markdown draft. */
export interface ParsedSection {
  heading: string;
  level: number;
}

export interface ValidationResult {
  ok: boolean;
  missing: string[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const SUPPORTED_VERSIONS = new Set(["1.0.0"]);

const REGISTRY_KEY = (type: ContentType, subtype: string | null) =>
  subtype ? `${type}:${subtype}` : type;

function defaultTemplatesDir(): string {
  // <skillRoot>/src/lib/templates.ts → <skillRoot>/content-templates
  const here = fileURLToPath(new URL(".", import.meta.url));
  return path.resolve(here, "..", "..", "content-templates");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Load every `*.yaml` under `dir` (defaults to `<skillRoot>/content-templates`).
 * @throws if YAML parsing fails or a template declares an unsupported version.
 */
export async function loadTemplates(
  dir: string = defaultTemplatesDir(),
): Promise<TemplateRegistry> {
  let entries: string[];
  try {
    entries = await fs.readdir(dir);
  } catch (err) {
    throw new Error(
      `Cannot read templates directory: ${dir} (${(err as Error).message})`,
    );
  }

  const registry: TemplateRegistry = {};

  for (const name of entries) {
    if (!name.endsWith(".yaml") && !name.endsWith(".yml")) continue;
    const file = path.join(dir, name);
    const raw = await fs.readFile(file, "utf8");

    let parsed: unknown;
    try {
      parsed = parseYaml(raw);
    } catch (err) {
      throw new Error(`Failed to parse YAML ${file}: ${(err as Error).message}`);
    }

    const tpl = assertValidTemplate(parsed, file);
    registry[REGISTRY_KEY(tpl.type, tpl.subtype)] = tpl;
  }

  return registry;
}

/**
 * Select a template from the registry.
 * @throws if the type (or subtype when required) is unknown.
 */
export function getTemplate(
  registry: TemplateRegistry,
  type: ContentType,
  subtype?: string,
): Template {
  const key = subtype ? `${type}:${subtype}` : type;
  const hit = registry[key];
  if (!hit) {
    if (type === "tech_article" && subtype) {
      throw new Error(
        `Unknown tech_article subtype: "${subtype}" (known keys: ${Object.keys(
          registry,
        )
          .filter((k) => k.startsWith("tech_article:"))
          .map((k) => k.split(":")[1])
          .join(", ")})`,
      );
    }
    throw new Error(
      `Template not found for type="${type}"${subtype ? `, subtype="${subtype}"` : ""}`,
    );
  }
  return hit;
}

/**
 * Validate that every required section in `template` is present in the draft.
 * Matching is by `heading` string (exact equality on the required_sections
 * heading field; draft-side heading may omit the `## ` prefix).
 */
export function validateRequiredSections(
  template: Template,
  sections: ParsedSection[],
): ValidationResult {
  const seen = new Set(sections.map((s) => s.heading.trim()));
  const missing: string[] = [];
  for (const req of template.required_sections) {
    // body sections without an explicit heading text (rare: see weekly_issue
    // "source_sections") are skipped here — they are validated per-template
    // elsewhere. For now, if heading is a plain text, require match.
    if (!seen.has(req.heading.trim())) {
      missing.push(req.heading);
    }
  }
  return { ok: missing.length === 0, missing };
}

// ---------------------------------------------------------------------------
// Internal validation
// ---------------------------------------------------------------------------

function assertValidTemplate(parsed: unknown, file: string): Template {
  if (!parsed || typeof parsed !== "object") {
    throw new Error(`Template ${file} is not an object`);
  }
  const p = parsed as Record<string, unknown>;

  const type = p.type;
  if (
    type !== "knowledge" &&
    type !== "tech_article" &&
    type !== "weekly_issue"
  ) {
    throw new Error(`Template ${file} has invalid type: ${String(type)}`);
  }

  const rawSubtype = p.subtype;
  const subtype =
    rawSubtype === null || rawSubtype === undefined
      ? null
      : (String(rawSubtype) as TechArticleSubtype);

  const version = String(p.version ?? "");
  if (!SUPPORTED_VERSIONS.has(version)) {
    throw new Error(
      `Template ${file} declares unsupported version "${version}" (supported: ${[
        ...SUPPORTED_VERSIONS,
      ].join(", ")})`,
    );
  }

  const required_sections = coerceSections(p.required_sections, file, "required_sections");
  const optional_sections = coerceSections(p.optional_sections ?? [], file, "optional_sections");
  const special_syntax = coerceSyntax(p.special_syntax ?? [], file);

  return {
    type,
    subtype,
    version,
    required_sections,
    optional_sections,
    special_syntax,
    sourceFile: file,
  };
}

function coerceSections(value: unknown, file: string, label: string): SectionSpec[] {
  if (!Array.isArray(value)) {
    throw new Error(`Template ${file}: ${label} must be an array`);
  }
  return value.map((entry, idx) => {
    if (!entry || typeof entry !== "object") {
      throw new Error(`Template ${file}: ${label}[${idx}] is not an object`);
    }
    const e = entry as Record<string, unknown>;
    const id = String(e.id ?? "");
    const heading = String(e.heading ?? "");
    const heading_level = (String(e.heading_level ?? "h2") as SectionSpec["heading_level"]);
    const cls = e.class === undefined ? undefined : String(e.class);
    const position = e.position === undefined ? undefined : (String(e.position) as SectionSpec["position"]);
    if (!id || !heading) {
      throw new Error(
        `Template ${file}: ${label}[${idx}] missing id or heading (id=${id}, heading=${heading})`,
      );
    }
    return { id, heading, heading_level, class: cls, position };
  });
}

function coerceSyntax(value: unknown, file: string): SpecialSyntaxRule[] {
  if (!Array.isArray(value)) {
    throw new Error(`Template ${file}: special_syntax must be an array`);
  }
  return value.map((entry, idx) => {
    if (!entry || typeof entry !== "object") {
      throw new Error(`Template ${file}: special_syntax[${idx}] is not an object`);
    }
    const e = entry as Record<string, unknown>;
    const pattern = String(e.pattern ?? "");
    const replace_with = String(e.replace_with ?? "");
    if (!pattern || !replace_with) {
      throw new Error(
        `Template ${file}: special_syntax[${idx}] missing pattern or replace_with`,
      );
    }
    return { pattern, replace_with };
  });
}
