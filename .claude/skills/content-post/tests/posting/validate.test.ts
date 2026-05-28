/**
 * Tests for src/posting/validate.ts — Phase 8 Wave E1
 *
 * Observation list from
 *   docs/pdca/phase-8-wave-e1/plan.md §テスト観点 (validate.test.ts)
 */
import { describe, it, expect, beforeAll } from "vitest";
import path from "node:path";
import {
  loadTemplates,
  type TemplateRegistry,
} from "../../src/lib/templates.js";
import { validateInput } from "../../src/posting/validate.js";

const REPO_TEMPLATES = path.resolve(
  "/Users/t.hirai/work/classlab-weekly-news/content-templates",
);

let registry: TemplateRegistry;
beforeAll(async () => {
  registry = await loadTemplates(REPO_TEMPLATES);
});

function makeDoc(
  fm: Record<string, unknown>,
  body: string = "a".repeat(500),
): string {
  const yamlLines = Object.entries(fm).map(([k, v]) => {
    if (Array.isArray(v)) {
      return `${k}:\n${v.map((x) => `  - ${JSON.stringify(x)}`).join("\n")}`;
    }
    if (typeof v === "object" && v !== null) return `${k}: ${JSON.stringify(v)}`;
    return `${k}: ${JSON.stringify(v)}`;
  });
  return `---\n${yamlLines.join("\n")}\n---\n\n${body}\n`;
}

describe("validateInput — title validation", () => {
  it("emits an error when title is missing", () => {
    const raw = makeDoc({ type: "knowledge" });
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(false);
    expect(res.errors.some((e) => e.field === "title")).toBe(true);
  });

  it("emits an error when title exceeds 120 chars", () => {
    const raw = makeDoc({ type: "knowledge", title: "x".repeat(121) });
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(false);
    expect(res.errors.some((e) => e.field === "title")).toBe(true);
  });
});

describe("validateInput — type / subtype validation", () => {
  it("emits an error for an invalid type", () => {
    const raw = makeDoc({ type: "podcast", title: "ok" });
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(false);
    expect(res.errors.some((e) => e.field === "type")).toBe(true);
  });

  it("requires a subtype for tech_articles", () => {
    const raw = makeDoc({ type: "tech_articles", title: "ok" });
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(false);
    expect(res.errors.some((e) => e.field === "subtype")).toBe(true);
  });

  it("rejects an invalid tech_articles subtype", () => {
    const raw = makeDoc({
      type: "tech_articles",
      title: "ok",
      subtype: "rambling",
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(false);
    expect(res.errors.some((e) => e.field === "subtype")).toBe(true);
  });

  it("accepts subtype on knowledge as ignored (no error)", () => {
    const raw = makeDoc(
      { type: "knowledge", title: "ok", subtype: "deepdive" },
      "x".repeat(300),
    );
    const res = validateInput(raw, { templates: registry });
    // unknown/extra subtype on knowledge should not be an error
    expect(res.errors.some((e) => e.field === "subtype")).toBe(false);
  });
});

describe("validateInput — body length", () => {
  it("warns when knowledge body is under 200 chars", () => {
    const raw = makeDoc(
      { type: "knowledge", title: "ok" },
      "short body",
    );
    const res = validateInput(raw, { templates: registry });
    expect(res.warnings.some((w) => w.field === "body")).toBe(true);
    // body-length is NOT an error — ok can still be true if nothing else failed
    expect(res.errors.some((e) => e.field === "body")).toBe(false);
  });
});

describe("validateInput — slug format", () => {
  it("rejects slug containing uppercase letters", () => {
    const raw = makeDoc({
      type: "knowledge",
      title: "ok",
      slug: "HelloWorld",
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.errors.some((e) => e.field === "slug")).toBe(true);
  });

  it("rejects slug containing symbols", () => {
    const raw = makeDoc({
      type: "knowledge",
      title: "ok",
      slug: "hello_world!",
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.errors.some((e) => e.field === "slug")).toBe(true);
  });
});

describe("validateInput — tags", () => {
  it("rejects tags that is not a string array", () => {
    const raw = makeDoc({
      type: "knowledge",
      title: "ok",
      tags: "not-an-array",
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.errors.some((e) => e.field === "tags")).toBe(true);
  });

  it("rejects a tag longer than 40 chars", () => {
    const raw = makeDoc({
      type: "knowledge",
      title: "ok",
      tags: ["x".repeat(41)],
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.errors.some((e) => e.field === "tags")).toBe(true);
  });
});

describe("validateInput — published_at", () => {
  it("rejects a published_at that is not ISO8601", () => {
    const raw = makeDoc({
      type: "knowledge",
      title: "ok",
      published_at: "not-a-date",
    });
    const res = validateInput(raw, { templates: registry });
    expect(res.errors.some((e) => e.field === "published_at")).toBe(true);
  });
});

describe("validateInput — happy path", () => {
  it("returns ok=true with all required fields filled", () => {
    const body = [
      "## 概要",
      "これは概要セクションです。".repeat(5),
      "",
      "## 本編",
      "これは本編セクションです。".repeat(20),
    ].join("\n");
    const raw = makeDoc({ type: "knowledge", title: "良いタイトル" }, body);
    const res = validateInput(raw, { templates: registry });
    expect(res.ok).toBe(true);
    expect(res.errors).toEqual([]);
  });
});

describe("validateInput — required sections warning", () => {
  it("warns (not errors) when a required section heading is missing", () => {
    // body has only 本編, missing 概要
    const body = ["## 本編", "x".repeat(400)].join("\n");
    const raw = makeDoc({ type: "knowledge", title: "ok" }, body);
    const res = validateInput(raw, { templates: registry });
    expect(res.warnings.some((w) => w.field === "sections")).toBe(true);
    expect(res.errors.some((e) => e.field === "sections")).toBe(false);
  });
});
