/**
 * Tests for src/posting/thumbnail-hearing.ts — Task #58 Step 4
 *
 * kind (concept / operation / domain_knowledge) × master tag (部署 / 業界) に応じた
 * thumbnail pattern 選択ロジックの単体テスト。
 *
 * テスト観点:
 *   selectKindTagPatterns(config, kind, tags)
 *     - concept → categories.knowledge.patterns (K-*) をそのまま (後方互換)
 *     - operation + 既知 tag → tag_patterns[tag] (HERO/INLINE)
 *     - domain_knowledge + 既知 tag → tag_patterns[tag]
 *     - 複数 tag → 先頭の既知 tag を採用
 *     - 未登録/未選択 tag → kind の default_patterns
 *     - knowledge_kinds 未定義の config → categories fallback (後方互換)
 *     - 返る ID はすべて patterns に存在し category_lock/kind_lock 整合
 */
import { describe, it, expect } from "vitest";
import {
  selectKindTagPatterns,
  defaultReadPatternsConfig,
  type ThumbnailPatternsConfig,
} from "../../src/posting/thumbnail-hearing.js";
import {
  DEPARTMENT_TAGS,
  INDUSTRY_TAGS,
} from "../../src/posting/tag-hearing.js";

// kind 細分化を含む最小 config (実ファイル schema を踏襲)
const CFG: ThumbnailPatternsConfig = {
  version: "2.1",
  categories: {
    knowledge: { patterns: ["K-HERO", "K-INLINE", "K-OUTRO"], default_count: 1 },
  },
  knowledge_kinds: {
    concept: { default_patterns: ["K-HERO", "K-INLINE", "K-OUTRO"] },
    operation: {
      axis: "department",
      default_patterns: ["T395", "T396"],
      tag_patterns: {
        corporate: ["T397", "T398"],
        system: ["T403", "T404"],
      },
    },
    domain_knowledge: {
      axis: "industry",
      default_patterns: ["T411", "T412"],
      tag_patterns: {
        electricity: ["T415", "T416"],
        moving: ["T419", "T420"],
      },
    },
  },
  patterns: {
    "K-HERO": { label: "Knowledge Hero", category_lock: "knowledge" },
    "K-INLINE": { label: "Knowledge Inline", category_lock: "knowledge" },
    "K-OUTRO": { label: "Knowledge Outro", category_lock: "knowledge" },
    T395: { label: "業務 HERO (汎用)", category_lock: "knowledge", kind_lock: "operation" },
    T396: { label: "業務 INLINE (汎用)", category_lock: "knowledge", kind_lock: "operation" },
    T397: { label: "コーポレート HERO", category_lock: "knowledge", kind_lock: "operation" },
    T398: { label: "コーポレート INLINE", category_lock: "knowledge", kind_lock: "operation" },
    T403: { label: "システム部 HERO", category_lock: "knowledge", kind_lock: "operation" },
    T404: { label: "システム部 INLINE", category_lock: "knowledge", kind_lock: "operation" },
    T411: { label: "業界 HERO (汎用)", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T412: { label: "業界 INLINE (汎用)", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T415: { label: "電気 HERO", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T416: { label: "電気 INLINE", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T419: { label: "引越し HERO", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T420: { label: "引越し INLINE", category_lock: "knowledge", kind_lock: "domain_knowledge" },
  },
};

describe("selectKindTagPatterns", () => {
  it("concept → K-* category patterns (後方互換)", () => {
    expect(selectKindTagPatterns(CFG, "concept", [])).toEqual([
      "K-HERO",
      "K-INLINE",
      "K-OUTRO",
    ]);
    // tags are ignored for concept
    expect(selectKindTagPatterns(CFG, "concept", ["electricity"])).toEqual([
      "K-HERO",
      "K-INLINE",
      "K-OUTRO",
    ]);
  });

  it("operation + 既知の部署 tag → tag_patterns[tag]", () => {
    expect(
      selectKindTagPatterns(CFG, "operation", ["corporate"]),
    ).toEqual(["T397", "T398"]);
    expect(
      selectKindTagPatterns(CFG, "operation", ["system"]),
    ).toEqual(["T403", "T404"]);
  });

  it("domain_knowledge + 既知の業界 tag → tag_patterns[tag]", () => {
    expect(
      selectKindTagPatterns(CFG, "domain_knowledge", ["electricity"]),
    ).toEqual(["T415", "T416"]);
    expect(
      selectKindTagPatterns(CFG, "domain_knowledge", ["moving"]),
    ).toEqual(["T419", "T420"]);
  });

  it("複数 tag → 先頭の既知 tag を採用", () => {
    expect(
      selectKindTagPatterns(CFG, "operation", [
        "unknown-tag",
        "system",
        "corporate",
      ]),
    ).toEqual(["T403", "T404"]);
  });

  it("未選択 tag → kind の default_patterns", () => {
    expect(selectKindTagPatterns(CFG, "operation", [])).toEqual([
      "T395",
      "T396",
    ]);
    expect(selectKindTagPatterns(CFG, "domain_knowledge", [])).toEqual([
      "T411",
      "T412",
    ]);
  });

  it("未登録 tag のみ → kind の default_patterns", () => {
    expect(
      selectKindTagPatterns(CFG, "operation", ["does-not-exist"]),
    ).toEqual(["T395", "T396"]);
  });

  it("knowledge_kinds 未定義 config → categories.knowledge fallback (後方互換)", () => {
    const legacy: ThumbnailPatternsConfig = {
      version: "2.0",
      categories: {
        knowledge: { patterns: ["K-HERO", "K-INLINE", "K-OUTRO"], default_count: 1 },
      },
      patterns: {
        "K-HERO": { label: "h", category_lock: "knowledge" },
        "K-INLINE": { label: "i", category_lock: "knowledge" },
        "K-OUTRO": { label: "o", category_lock: "knowledge" },
      },
    };
    expect(selectKindTagPatterns(legacy, "operation", ["corporate"])).toEqual([
      "K-HERO",
      "K-INLINE",
      "K-OUTRO",
    ]);
  });

  it("返る ID はすべて patterns に存在する", () => {
    const all = [
      ...selectKindTagPatterns(CFG, "operation", ["corporate"]),
      ...selectKindTagPatterns(CFG, "domain_knowledge", ["electricity"]),
      ...selectKindTagPatterns(CFG, "operation", []),
    ];
    for (const id of all) {
      expect(CFG.patterns[id]).toBeDefined();
    }
  });
});

// ---------------------------------------------------------------------------
// M11: 実 thumbnail-patterns.json と DEPARTMENT_TAGS/INDUSTRY_TAGS の整合 smoke
//
// tag-hearing.ts の master slug (#57 seed taxonomy) と thumbnail-patterns.json の
// knowledge_kinds.<kind>.tag_patterns key が drift していないことを実ファイルで保証する。
// round-2 で slug を是正したため、両者が乖離すると本番でサムネ選択が default に落ちて
// 部署/業界別の visual がまったく当たらなくなる。
// ---------------------------------------------------------------------------
describe("M11: 実 JSON と master tag slug の整合", () => {
  it("全 7 部署 slug が operation.tag_patterns に存在し、専用 pattern を引く", async () => {
    const cfg = await defaultReadPatternsConfig();
    const opTagPatterns = cfg.knowledge_kinds?.operation?.tag_patterns ?? {};
    const opDefault = cfg.knowledge_kinds?.operation?.default_patterns ?? [];
    for (const dept of DEPARTMENT_TAGS) {
      // tag_patterns に slug key が存在する (drift 検出)
      expect(
        Object.prototype.hasOwnProperty.call(opTagPatterns, dept.slug),
      ).toBe(true);
      const picked = selectKindTagPatterns(cfg, "operation", [dept.slug]);
      // 専用 pattern が引けて、default にフォールバックしていない
      expect(picked.length).toBeGreaterThan(0);
      expect(picked).not.toEqual(opDefault);
      // 返る ID はすべて実在し operation/knowledge lock 整合
      for (const id of picked) {
        const def = cfg.patterns[id];
        expect(def).toBeDefined();
        expect(def?.kind_lock).toBe("operation");
        expect(def?.category_lock).toBe("knowledge");
      }
    }
  });

  it("全 5 業界 slug が domain_knowledge.tag_patterns に存在し、専用 pattern を引く", async () => {
    const cfg = await defaultReadPatternsConfig();
    const dkTagPatterns =
      cfg.knowledge_kinds?.domain_knowledge?.tag_patterns ?? {};
    const dkDefault =
      cfg.knowledge_kinds?.domain_knowledge?.default_patterns ?? [];
    for (const ind of INDUSTRY_TAGS) {
      expect(
        Object.prototype.hasOwnProperty.call(dkTagPatterns, ind.slug),
      ).toBe(true);
      const picked = selectKindTagPatterns(cfg, "domain_knowledge", [ind.slug]);
      expect(picked.length).toBeGreaterThan(0);
      expect(picked).not.toEqual(dkDefault);
      for (const id of picked) {
        const def = cfg.patterns[id];
        expect(def).toBeDefined();
        expect(def?.kind_lock).toBe("domain_knowledge");
        expect(def?.category_lock).toBe("knowledge");
      }
    }
  });

  it("旧 slug (corporate-strategy 等) は tag_patterns に残っていない", async () => {
    const cfg = await defaultReadPatternsConfig();
    const opKeys = Object.keys(
      cfg.knowledge_kinds?.operation?.tag_patterns ?? {},
    );
    const dkKeys = Object.keys(
      cfg.knowledge_kinds?.domain_knowledge?.tag_patterns ?? {},
    );
    const stale = [
      "corporate-strategy",
      "sales-marketing",
      "customer-service",
      "system-tech-lead",
      "business-operations",
      "hr-recruitment",
      "finance-accounting",
      "realestate-property-management",
      "energy-utilities",
      "telecom-internet",
      "moving-relocation",
      "household-services",
    ];
    for (const s of stale) {
      expect(opKeys).not.toContain(s);
      expect(dkKeys).not.toContain(s);
    }
  });
});
