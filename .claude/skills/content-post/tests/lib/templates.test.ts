/**
 * Tests for src/lib/templates.ts
 *
 * Covers: loadTemplates / getTemplate / validateRequiredSections
 */
import { describe, it, expect, beforeAll } from "vitest";
import path from "node:path";
import fs from "node:fs/promises";
import os from "node:os";
import {
  loadTemplates,
  getTemplate,
  validateRequiredSections,
  type TemplateRegistry,
  type ParsedSection,
} from "../../src/lib/templates.js";

const REPO_TEMPLATES = path.resolve(
  "/Users/t.hirai/work/classlab-weekly-news/content-templates",
);

describe("loadTemplates()", () => {
  let registry: TemplateRegistry;

  beforeAll(async () => {
    registry = await loadTemplates(REPO_TEMPLATES);
  });

  it("loads all 6 template YAMLs from the classlab-weekly-news repo", () => {
    const keys = Object.keys(registry).sort();
    expect(keys).toEqual(
      [
        "knowledge",
        "tech_article:casestudy",
        "tech_article:comparison",
        "tech_article:deepdive",
        "tech_article:handson",
        "weekly_issue",
      ].sort(),
    );
  });

  it("parses version / required_sections / special_syntax fields", () => {
    const knowledge = registry["knowledge"]!;
    expect(knowledge.version).toBe("1.0.0");
    expect(knowledge.type).toBe("knowledge");
    expect(knowledge.required_sections.length).toBeGreaterThan(0);
    expect(knowledge.special_syntax.length).toBeGreaterThan(0);
  });

  it("preserves `class` field on required_sections for `.rich-*` mapping", () => {
    const knowledge = registry["knowledge"]!;
    const summary = knowledge.required_sections.find((s) => s.id === "summary");
    expect(summary?.class).toBe("rich-summary");
  });

  it("throws a clear error when the YAML version is unsupported", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "cp-tpl-bad-"));
    await fs.writeFile(
      path.join(tmp, "broken.yaml"),
      "type: knowledge\nversion: \"9.9.9\"\nrequired_sections: []\nspecial_syntax: []\n",
    );
    await expect(loadTemplates(tmp)).rejects.toThrow(/version/i);
  });

  it("throws when YAML is syntactically invalid", async () => {
    const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "cp-tpl-parse-"));
    await fs.writeFile(path.join(tmp, "broken.yaml"), "type: [unclosed\n");
    await expect(loadTemplates(tmp)).rejects.toThrow();
  });
});

describe("getTemplate()", () => {
  let registry: TemplateRegistry;

  beforeAll(async () => {
    registry = await loadTemplates(REPO_TEMPLATES);
  });

  it("returns the knowledge template when type=knowledge", () => {
    const tpl = getTemplate(registry, "knowledge");
    expect(tpl.type).toBe("knowledge");
  });

  it("returns the correct subtype for tech_article:deepdive", () => {
    const tpl = getTemplate(registry, "tech_article", "deepdive");
    expect(tpl.type).toBe("tech_article");
    expect(tpl.subtype).toBe("deepdive");
  });

  it("throws when an unknown tech_article subtype is requested", () => {
    expect(() =>
      getTemplate(registry, "tech_article", "invalid" as string),
    ).toThrow(/subtype/i);
  });

  it("returns the weekly_issue template without a subtype", () => {
    const tpl = getTemplate(registry, "weekly_issue");
    expect(tpl.type).toBe("weekly_issue");
  });

  it("weekly_issue template has classlab-usage in optional_sections", () => {
    const tpl = getTemplate(registry, "weekly_issue");
    const usage = tpl.optional_sections.find((s) => s.id === "classlab_usage");
    expect(usage).toBeDefined();
    expect(usage?.heading).toBe("Classlabでの活用");
  });
});

describe("validateRequiredSections()", () => {
  let registry: TemplateRegistry;

  beforeAll(async () => {
    registry = await loadTemplates(REPO_TEMPLATES);
  });

  it("returns ok=true when all required sections exist", () => {
    const tpl = getTemplate(registry, "knowledge");
    const sections: ParsedSection[] = tpl.required_sections.map((r) => ({
      heading: r.heading,
      level: 2,
    }));
    const result = validateRequiredSections(tpl, sections);
    expect(result.ok).toBe(true);
    expect(result.missing).toEqual([]);
  });

  it("lists missing required sections by heading", () => {
    const tpl = getTemplate(registry, "knowledge");
    const result = validateRequiredSections(tpl, [
      { heading: "概要", level: 2 },
      // 本編 missing
    ]);
    expect(result.ok).toBe(false);
    expect(result.missing).toContain("本編");
  });
});
