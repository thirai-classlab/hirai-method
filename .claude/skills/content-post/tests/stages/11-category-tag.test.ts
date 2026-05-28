/**
 * tests/stages/11-category-tag.test.ts — Task #56 W3 (11.3d-C)
 *
 * Light-weight check: skip in update mode is owned by the stage descriptor,
 * resolveCategoryAndTags pure path is exercised by post.test.ts; here we pin
 * the confirmMode priority + frontmatter.category override.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const fetchAllowedCategoriesForKindMock = vi.fn(async () => []);
vi.mock("../../src/posting/category-allowlist.js", () => ({
  fetchAllowedCategories: vi.fn(async () => []),
  fetchAllowedCategoriesForKind: (...args: unknown[]) =>
    fetchAllowedCategoriesForKindMock(...(args as [])),
  BUSINESS_AXIS_CATEGORIES: [
    { slug: "vacancy-energization", name: "空室通電", description: null },
    { slug: "lifeline", name: "ライフライン", description: null },
  ],
}));

import { resolveCategoryAndTags } from "../../scripts/stages/11-category-tag.js";
import type { PostDeps } from "../../scripts/post.js";

function makeDeps(over: Partial<PostDeps> = {}): PostDeps {
  return {
    loadFile: vi.fn(),
    validate: vi.fn(),
    parseMarkdown: vi.fn(),
    renderToHtml: vi.fn(),
    renderToHtmlAsync: vi.fn(),
    generateSlug: vi.fn(),
    ensureUniqueSlug: vi.fn(),
    generateEmbedding: vi.fn(),
    checkDuplicate: vi.fn(),
    suggestCategory: vi.fn(async () => ({
      slug: "auto",
      name: "Auto",
      confidence: 0.7,
      isNew: false,
    })),
    suggestTags: vi.fn(async () => []),
    resolveTagAgainstMasters: vi.fn(async () => []),
    confirmInteractively: vi.fn(async () => ({
      committed: true,
      category: { slug: "from-frontmatter", name: "FM", isNew: false },
      tags: [],
    })),
    getSupabaseClient: vi.fn(),
    webSearch: { search: vi.fn() },
    reader: { question: vi.fn(), close: vi.fn() },
    streams: { out: [], err: [], write: vi.fn(), writeErr: vi.fn() },
    env: {},
    ...over,
  } as PostDeps;
}

describe("scripts/stages/11-category-tag — Task #56 W3", () => {
  beforeEach(() => {
    fetchAllowedCategoriesForKindMock.mockClear();
    fetchAllowedCategoriesForKindMock.mockResolvedValue([]);
  });

  it("uses frontmatter.category verbatim when explicitly set", async () => {
    const suggestCategory = vi.fn(async () => ({
      slug: "auto",
      name: "Auto",
      confidence: 0.5,
      isNew: false,
    }));
    const confirmInteractively = vi.fn(async (args: unknown) => {
      // confirmInteractively receives the explicit category
      const { category } = args as { category: { slug: string } };
      return {
        committed: true,
        category: { slug: category.slug, name: category.slug, isNew: false },
        tags: [],
      };
    });
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: { category: "explicit-cat" },
      opts: { dryRun: false, autoApprove: true },
      client: {},
      deps: makeDeps({
        suggestCategory: suggestCategory as never,
        confirmInteractively: confirmInteractively as never,
      }),
      verbose: vi.fn(),
    });
    expect(result.category.slug).toBe("explicit-cat");
  });

  it("falls back to suggested category when frontmatter.category is empty", async () => {
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    // makeDeps confirmInteractively returns slug "from-frontmatter"
    expect(result.category.slug).toBe("from-frontmatter");
  });

  // -------------------------------------------------------------------------
  // #58 Step 2: master tag hearing 配線
  // -------------------------------------------------------------------------
  it("operation: interactive で master 部署 slug を confirmedMeta.tags にマージ", async () => {
    const ask = vi.fn(async () => ["corporate-strategy", "system-tech-lead"]);
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: false }, // interactive
      knowledgeKind: "operation",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
      tagHearing: { ask: ask as never, deps: { promptUser: vi.fn() } },
    });
    expect(ask).toHaveBeenCalledWith("operation", expect.anything());
    expect(result.tags).toEqual([
      { name: "corporate-strategy", isNew: true },
      { name: "system-tech-lead", isNew: true },
    ]);
  });

  it("domain_knowledge: interactive で master 業界 slug をマージ", async () => {
    const ask = vi.fn(async () => ["energy-utilities"]);
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: false },
      knowledgeKind: "domain_knowledge",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
      tagHearing: { ask: ask as never, deps: { promptUser: vi.fn() } },
    });
    expect(ask).toHaveBeenCalledWith("domain_knowledge", expect.anything());
    expect(result.tags).toContainEqual({ name: "energy-utilities", isNew: true });
  });

  it("concept: master hearing を行わない (backward compat)", async () => {
    const ask = vi.fn(async () => ["should-not-happen"]);
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: false },
      knowledgeKind: "concept",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
      tagHearing: { ask: ask as never, deps: { promptUser: vi.fn() } },
    });
    expect(ask).not.toHaveBeenCalled();
    expect(result.tags).toEqual([]); // makeDeps confirmInteractively returns []
  });

  it("operation でも autoApprove のときは hearing を skip (非対話)", async () => {
    const ask = vi.fn(async () => ["corporate-strategy"]);
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true }, // auto-approve → skip
      knowledgeKind: "operation",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
      tagHearing: { ask: ask as never, deps: { promptUser: vi.fn() } },
    });
    expect(ask).not.toHaveBeenCalled();
    expect(result.tags).toEqual([]);
  });

  it("operation でも contentType が knowledge 以外なら hearing を skip", async () => {
    const ask = vi.fn(async () => ["corporate-strategy"]);
    await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "tech_articles",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: false },
      knowledgeKind: "operation",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
      tagHearing: { ask: ask as never, deps: { promptUser: vi.fn() } },
    });
    expect(ask).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // #58 Step 3: kind 別 category allowlist 配線
  // -------------------------------------------------------------------------
  it("operation: business-axis allowlist を suggestCategory に渡す", async () => {
    const businessAxis = [
      { slug: "vacancy-energization", name: "空室通電", description: null },
      { slug: "lifeline", name: "ライフライン", description: null },
    ];
    fetchAllowedCategoriesForKindMock.mockResolvedValue(businessAxis as never);
    const suggestCategory = vi.fn(async () => ({
      slug: "lifeline",
      name: "ライフライン",
      confidence: 0.9,
      isNew: false,
    }));
    await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      knowledgeKind: "operation",
      client: {},
      deps: makeDeps({ suggestCategory: suggestCategory as never }),
      verbose: vi.fn(),
    });
    // kind 別 helper が呼ばれている
    expect(fetchAllowedCategoriesForKindMock).toHaveBeenCalledWith("operation");
    // suggestCategory が business-axis allowlist を受け取っている
    const calls = suggestCategory.mock.calls as unknown as Array<
      [unknown, { allowedCategories: Array<{ slug: string }> }]
    >;
    const passedDeps = calls[0]![1];
    expect(passedDeps.allowedCategories.map((c) => c.slug).sort()).toEqual([
      "lifeline",
      "vacancy-energization",
    ]);
  });

  it("concept: kind helper が concept で呼ばれ既存 knowledge allowlist 経路", async () => {
    await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      knowledgeKind: "concept",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    expect(fetchAllowedCategoriesForKindMock).toHaveBeenCalledWith("concept");
  });

  it("M10: knowledge かつ kind 未指定 (undefined) は concept として明示解決して helper を呼ぶ", async () => {
    // #58 round-2 (M10): fetchAllowedCategoriesForKind は非 undefined の
    // KnowledgeKind しか受けない。stage11 は undefined を DEFAULT_KNOWLEDGE_KIND
    // (= "concept") に解決してから渡すので、helper は "concept" で呼ばれる
    // (undefined の silent fallback が排除されたことの確認)。
    await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      // knowledgeKind を意図的に省略 (undefined)
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    expect(fetchAllowedCategoriesForKindMock).toHaveBeenCalledWith("concept");
  });

  it("tech_articles: kind helper は呼ばれず既存 article allowlist 経路 (動作不変)", async () => {
    await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "tech_articles",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    // 非 knowledge は kind 別 filter の対象外 → 既存 fetchAllowedCategories のまま
    expect(fetchAllowedCategoriesForKindMock).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------------
  // M13: category allowlist 0 件 / fetch 失敗の異常系 (fail-fast の境界)
  //
  // allowlist が空配列で返る (kind seed 未投入など) / fetch が throw する場合でも
  // resolveCategoryAndTags は crash せず suggestCategory へ空 allowlist を渡して
  // 継続する。fetch throw は legacy DB match へフォールバックする (console.warn のみ)。
  // -------------------------------------------------------------------------
  it("M13: allowlist 0 件でも crash せず suggestCategory に空配列を渡す", async () => {
    fetchAllowedCategoriesForKindMock.mockResolvedValue([] as never);
    const suggestCategory = vi.fn(async () => ({
      slug: "fallback",
      name: "Fallback",
      confidence: 0.3,
      isNew: false,
    }));
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      knowledgeKind: "operation",
      client: {},
      deps: makeDeps({ suggestCategory: suggestCategory as never }),
      verbose: vi.fn(),
    });
    // suggestCategory は呼ばれ、allowedCategories は空配列
    const calls = suggestCategory.mock.calls as unknown as Array<
      [unknown, { allowedCategories: unknown[] }]
    >;
    expect(calls[0]![1].allowedCategories).toEqual([]);
    // confirmInteractively (makeDeps) は committed:true を返すので結果が得られる
    expect(result.category.slug).toBe("from-frontmatter");
  });

  it("M13: allowlist fetch が throw しても legacy DB match へフォールバックし継続する", async () => {
    fetchAllowedCategoriesForKindMock.mockRejectedValue(
      new Error("network down") as never,
    );
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const result = await resolveCategoryAndTags({
      title: "T",
      parsedRaw: "B",
      contentType: "knowledge",
      frontmatter: {},
      opts: { dryRun: false, autoApprove: true },
      knowledgeKind: "concept",
      client: {},
      deps: makeDeps(),
      verbose: vi.fn(),
    });
    // fetch 失敗は warn のみで継続 (throw しない)
    expect(warnSpy).toHaveBeenCalled();
    expect(result.category.slug).toBe("from-frontmatter");
    warnSpy.mockRestore();
  });
});
