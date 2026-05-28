/**
 * Tests for src/posting/thumbnail-hearing.ts — Task #32 セッション 2
 *
 * テスト観点 (from task brief):
 *   1. extractHeadlineCandidates
 *      - h1/h2 抽出 (`# title` / `## section`)
 *      - 重複排除 (順序保持)
 *      - max 件数制限
 *      - h3+ は無視
 *      - 空本文 → []
 *   2. filterPatternsByCategory
 *      - lock 違反パターンを除外 (T387 → tech_articles で除外)
 *      - lock なしパターンはクロスカテゴリ可
 *      - `categories.<type>.patterns` 配列を尊重
 *      - 未登録カテゴリ → []
 *   3. buildGeneratorArgs
 *      - --pattern カンマ区切り
 *      - --title / --headlines "h1|h2"
 *      - --out パス
 *      - styleHint を --scene に渡す
 *      - 空の styleHint は --scene を含めない
 *   4. runThumbnailHearing 統合
 *      - frontmatter 指定 → hearingSkipped: true で early return
 *      - autoApprove → prompt 呼ばず default パターンで生成
 *      - weekly_issues → hearing skip + T387+T394 自動 2 連発
 *      - tech/knowledge → b/c/d prompt 順次
 *      - 承認ループ: 「再生成」を 1 回挟んで OK の流れ
 *      - lock 違反パターン入力 → 拒否してリトライ
 *      - dryRun → 生成 spawn は呼ばずに hearingSkipped: false / generated: false
 *      - generator が ok=false → throw
 */
import { describe, it, expect, vi } from "vitest";
import {
  extractHeadlineCandidates,
  filterPatternsByCategory,
  buildGeneratorArgs,
  runThumbnailHearing,
  type ThumbnailHearingDeps,
  type ThumbnailHearingInput,
  type ThumbnailPatternsConfig,
} from "../../src/posting/thumbnail-hearing.js";

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

const SAMPLE_CONFIG: ThumbnailPatternsConfig = {
  version: "2.0",
  categories: {
    weekly_issues: { patterns: ["T387", "T394"], default_count: 2 },
    tech_articles: { patterns: ["T363", "T364"], default_count: 1 },
    knowledge: { patterns: ["T254", "T260"], default_count: 1 },
  },
  patterns: {
    T387: { label: "Isometric", category_lock: "weekly_issues" },
    T394: { label: "Pixel Art", category_lock: "weekly_issues" },
    T363: { label: "Bento Grid" },
    T364: { label: "Swiss Minimalist" },
    T254: { label: "ClassLab Moving Flatlay" },
    T260: { label: "ClassLab Coupon Card" },
  },
};

function makeDeps(overrides: Partial<ThumbnailHearingDeps> = {}): {
  deps: ThumbnailHearingDeps;
  prompts: string[];
  responses: string[];
  spawnArgs: string[][];
  logs: string[];
} {
  const prompts: string[] = [];
  const responses: string[] = [];
  const spawnArgs: string[][] = [];
  const logs: string[] = [];
  const deps: ThumbnailHearingDeps = {
    readPatternsConfig: vi.fn().mockResolvedValue(SAMPLE_CONFIG),
    promptUser: vi.fn().mockImplementation(async (q: string) => {
      prompts.push(q);
      return responses.shift() ?? "";
    }),
    spawnGenerator: vi.fn().mockImplementation(async (args: string[]) => {
      spawnArgs.push(args);
      // derive synthetic file paths from --out + --pattern args
      const outIdx = args.indexOf("--out");
      const patIdx = args.indexOf("--pattern");
      const outPath = outIdx >= 0 ? args[outIdx + 1]! : "/tmp/out.png";
      const patList = patIdx >= 0 ? args[patIdx + 1]!.split(",") : [];
      const files =
        patList.length > 1
          ? patList.map((p) => outPath.replace(/(\.[^.]+)$/, `-${p}$1`))
          : [outPath];
      return { files, ok: true };
    }),
    logger: (m: string) => logs.push(m),
    ...overrides,
  };
  return { deps, prompts, responses, spawnArgs, logs };
}

const SAMPLE_BODY = `# 主見出し

導入文。

## セクション A

中身。

## セクション B

中身。

### 小見出し（無視されるはず）

## セクション A

重複（除外されるはず）。

## セクション C

最後。`;

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

describe("extractHeadlineCandidates", () => {
  it("extracts h1 and h2 in document order", () => {
    expect(extractHeadlineCandidates(SAMPLE_BODY)).toEqual([
      "主見出し",
      "セクション A",
      "セクション B",
      "セクション C",
    ]);
  });

  it("ignores h3 and deeper", () => {
    const body = "# 大\n## 中\n### 小\n#### さらに小";
    expect(extractHeadlineCandidates(body)).toEqual(["大", "中"]);
  });

  it("respects max parameter", () => {
    expect(extractHeadlineCandidates(SAMPLE_BODY, 2)).toEqual([
      "主見出し",
      "セクション A",
    ]);
  });

  it("returns [] for empty body", () => {
    expect(extractHeadlineCandidates("")).toEqual([]);
    expect(extractHeadlineCandidates("\n\n")).toEqual([]);
  });

  it("trims whitespace and # padding", () => {
    expect(extractHeadlineCandidates("##   余分な空白   ")).toEqual([
      "余分な空白",
    ]);
  });
});

describe("filterPatternsByCategory", () => {
  it("returns category patterns excluding category_lock violations", () => {
    expect(filterPatternsByCategory(SAMPLE_CONFIG, "weekly_issues")).toEqual([
      "T387",
      "T394",
    ]);
    expect(filterPatternsByCategory(SAMPLE_CONFIG, "tech_articles")).toEqual([
      "T363",
      "T364",
    ]);
    expect(filterPatternsByCategory(SAMPLE_CONFIG, "knowledge")).toEqual([
      "T254",
      "T260",
    ]);
  });

  it("excludes patterns whose category_lock !== requested category even if listed", () => {
    const cfg: ThumbnailPatternsConfig = {
      version: "2.0",
      categories: {
        tech_articles: { patterns: ["T387", "T363"], default_count: 1 },
      },
      patterns: {
        T387: { label: "Isometric", category_lock: "weekly_issues" },
        T363: { label: "Bento Grid" },
      },
    };
    expect(filterPatternsByCategory(cfg, "tech_articles")).toEqual(["T363"]);
  });

  it("returns [] for unknown category", () => {
    expect(filterPatternsByCategory(SAMPLE_CONFIG, "unknown")).toEqual([]);
  });
});

describe("buildGeneratorArgs", () => {
  it("joins multiple patterns with comma", () => {
    const args = buildGeneratorArgs({
      patterns: ["T387", "T394"],
      title: "Vol.16",
      headlines: ["h1", "h2"],
      outputPath: "/tmp/x.png",
    });
    expect(args).toContain("--pattern");
    expect(args).toContain("T387,T394");
  });

  it("passes single pattern without comma", () => {
    const args = buildGeneratorArgs({
      patterns: ["T363"],
      title: "T",
      headlines: [],
      outputPath: "/tmp/x.png",
    });
    expect(args).toContain("T363");
    expect(args).not.toContain("T363,");
  });

  it("encodes headlines joined by pipe", () => {
    const args = buildGeneratorArgs({
      patterns: ["T363"],
      title: "T",
      headlines: ["A", "B", "C"],
      outputPath: "/tmp/x.png",
    });
    const idx = args.indexOf("--headlines");
    expect(idx).toBeGreaterThanOrEqual(0);
    expect(args[idx + 1]).toBe("A|B|C");
  });

  it("includes --title and --out", () => {
    const args = buildGeneratorArgs({
      patterns: ["T363"],
      title: "My Title",
      headlines: [],
      outputPath: "/tmp/x.png",
    });
    expect(args[args.indexOf("--title") + 1]).toBe("My Title");
    expect(args[args.indexOf("--out") + 1]).toBe("/tmp/x.png");
  });

  it("includes --scene when styleHint provided (non-empty)", () => {
    const args = buildGeneratorArgs({
      patterns: ["T363"],
      title: "T",
      headlines: [],
      outputPath: "/tmp/x.png",
      styleHint: "warm pastel tones",
    });
    expect(args[args.indexOf("--scene") + 1]).toBe("warm pastel tones");
  });

  it("omits --scene when styleHint is empty/whitespace", () => {
    const args = buildGeneratorArgs({
      patterns: ["T363"],
      title: "T",
      headlines: [],
      outputPath: "/tmp/x.png",
      styleHint: "   ",
    });
    expect(args).not.toContain("--scene");
  });
});

// ---------------------------------------------------------------------------
// Integrated runThumbnailHearing
// ---------------------------------------------------------------------------

describe("runThumbnailHearing", () => {
  const baseInput: ThumbnailHearingInput = {
    contentType: "tech_articles",
    title: "テスト記事",
    body: SAMPLE_BODY,
    autoApprove: false,
    dryRun: false,
  };

  it("frontmatter.thumbnail 指定 → hearingSkipped: true で early return", async () => {
    const { deps } = makeDeps();
    const result = await runThumbnailHearing(
      { ...baseInput, frontmatterThumbnail: "./cover.png" },
      deps,
    );
    expect(result).toEqual({
      generated: false,
      thumbnailPath: null,
      candidates: [],
      pattern: null,
      hearingSkipped: true,
    });
    expect(deps.promptUser).not.toHaveBeenCalled();
    expect(deps.spawnGenerator).not.toHaveBeenCalled();
  });

  it("weekly_issues → hearing skip + T387+T394 自動 2 連発", async () => {
    const { deps, spawnArgs } = makeDeps();
    const result = await runThumbnailHearing(
      { ...baseInput, contentType: "weekly_issues", title: "Vol.16" },
      deps,
    );
    expect(deps.promptUser).not.toHaveBeenCalled();
    expect(spawnArgs.length).toBe(1);
    const args = spawnArgs[0]!;
    expect(args[args.indexOf("--pattern") + 1]).toBe("T387,T394");
    expect(result.generated).toBe(true);
    expect(result.candidates.length).toBe(2);
    expect(result.thumbnailPath).toBe(result.candidates[0]);
    expect(result.hearingSkipped).toBe(true);
    expect(result.pattern).toBe("T387,T394");
  });

  it("autoApprove (tech_articles) → prompt なし + default パターンで生成", async () => {
    const { deps, spawnArgs } = makeDeps();
    const result = await runThumbnailHearing(
      { ...baseInput, autoApprove: true },
      deps,
    );
    expect(deps.promptUser).not.toHaveBeenCalled();
    expect(spawnArgs.length).toBe(1);
    // default_count=1 → first allowed pattern (T363)
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T363");
    expect(result.generated).toBe(true);
    expect(result.hearingSkipped).toBe(true);
  });

  it("tech_articles 対話モード → b/c/d prompt 順次 + 承認", async () => {
    const { deps, prompts, responses, spawnArgs } = makeDeps();
    // 順番:
    //   b: pattern (numeric index "1" = T363)
    //   c-title: 空 (= デフォルト維持)
    //   c-subtitle: "サブ"
    //   c-headlines: 空
    //   d: style hint 空
    //   approval: "y"
    responses.push("1", "", "サブ", "", "", "y");
    const result = await runThumbnailHearing(baseInput, deps);
    expect(prompts.length).toBeGreaterThanOrEqual(5);
    expect(result.generated).toBe(true);
    expect(result.hearingSkipped).toBe(false);
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T363");
    expect(result.pattern).toBe("T363");
  });

  it("承認ループ: 再生成 → OK の流れ", async () => {
    const { deps, responses, spawnArgs } = makeDeps();
    // 1st pass
    responses.push("1", "", "", "", "");
    // approval: "r" (regenerate)
    responses.push("r");
    // 2nd pass uses same hearing (only approval re-asked) -> "y"
    responses.push("y");
    const result = await runThumbnailHearing(baseInput, deps);
    expect(spawnArgs.length).toBe(2);
    expect(result.generated).toBe(true);
  });

  it("承認ループ: パターン変更 → b に戻る", async () => {
    const { deps, responses, spawnArgs } = makeDeps();
    // 1st pass: pick T363, accept hearing, generate
    responses.push("1", "", "", "", "");
    // approval: "p" → re-enter pattern selection
    responses.push("p");
    // 2nd hearing: pick T364, accept, generate, "y"
    responses.push("2", "", "", "", "", "y");
    const result = await runThumbnailHearing(baseInput, deps);
    expect(spawnArgs.length).toBe(2);
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T363");
    expect(spawnArgs[1]![spawnArgs[1]!.indexOf("--pattern") + 1]).toBe("T364");
    expect(result.pattern).toBe("T364");
    expect(result.generated).toBe(true);
  });

  it("lock 違反 (T387) を tech_articles で入力 → 拒否してリトライ", async () => {
    const { deps, responses, spawnArgs } = makeDeps();
    // First entry: invalid pattern id
    responses.push("T387");
    // Then: valid index "1" (T363)
    responses.push("1");
    // c/d prompts
    responses.push("", "", "", "");
    // approval
    responses.push("y");
    const result = await runThumbnailHearing(baseInput, deps);
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T363");
    expect(result.generated).toBe(true);
  });

  it("dryRun → spawn しない + generated: false", async () => {
    const { deps, spawnArgs } = makeDeps();
    const result = await runThumbnailHearing(
      { ...baseInput, dryRun: true, autoApprove: true },
      deps,
    );
    expect(spawnArgs.length).toBe(0);
    expect(result.generated).toBe(false);
    expect(result.thumbnailPath).toBeNull();
    expect(result.hearingSkipped).toBe(true);
  });

  it("generator が ok=false → throw", async () => {
    const failingSpawn = vi.fn().mockResolvedValue({ files: [], ok: false });
    const { deps } = makeDeps({ spawnGenerator: failingSpawn });
    await expect(
      runThumbnailHearing(
        { ...baseInput, autoApprove: true },
        deps,
      ),
    ).rejects.toThrow(/thumbnail generator/i);
  });

  it("knowledge auto-approve → first knowledge pattern (T254)", async () => {
    const { deps, spawnArgs } = makeDeps();
    const result = await runThumbnailHearing(
      { ...baseInput, contentType: "knowledge", autoApprove: true },
      deps,
    );
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T254");
    expect(result.generated).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// #58 Step 4: knowledge kind (operation / domain_knowledge) × master tag
// ---------------------------------------------------------------------------

const KIND_CONFIG: ThumbnailPatternsConfig = {
  version: "2.1",
  categories: {
    knowledge: { patterns: ["K-HERO", "K-INLINE", "K-OUTRO"], default_count: 1 },
  },
  knowledge_kinds: {
    concept: { default_patterns: ["K-HERO", "K-INLINE", "K-OUTRO"] },
    operation: {
      axis: "department",
      default_patterns: ["T395"],
      tag_patterns: { system: ["T403"] },
    },
    domain_knowledge: {
      axis: "industry",
      default_patterns: ["T411"],
      tag_patterns: { electricity: ["T415"] },
    },
  },
  patterns: {
    "K-HERO": { label: "Knowledge Hero", category_lock: "knowledge" },
    "K-INLINE": { label: "Knowledge Inline", category_lock: "knowledge" },
    "K-OUTRO": { label: "Knowledge Outro", category_lock: "knowledge" },
    T395: { label: "業務 HERO", category_lock: "knowledge", kind_lock: "operation" },
    T403: { label: "システム部 HERO", category_lock: "knowledge", kind_lock: "operation" },
    T411: { label: "業界 HERO", category_lock: "knowledge", kind_lock: "domain_knowledge" },
    T415: { label: "電気 HERO", category_lock: "knowledge", kind_lock: "domain_knowledge" },
  },
};

describe("runThumbnailHearing — #58 Step 4 kind 連動", () => {
  const kindBase: ThumbnailHearingInput = {
    contentType: "knowledge",
    title: "業務ナレッジ",
    body: SAMPLE_BODY,
    autoApprove: true,
    dryRun: false,
  };

  function makeKindDeps() {
    return makeDeps({
      readPatternsConfig: vi.fn().mockResolvedValue(KIND_CONFIG),
    });
  }

  it("operation + system tag (auto) → T403", async () => {
    const { deps, spawnArgs } = makeKindDeps();
    const result = await runThumbnailHearing(
      { ...kindBase, knowledgeKind: "operation", tags: ["system"] },
      deps,
    );
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T403");
    expect(result.generated).toBe(true);
  });

  it("operation + tag なし (auto) → default T395", async () => {
    const { deps, spawnArgs } = makeKindDeps();
    await runThumbnailHearing(
      { ...kindBase, knowledgeKind: "operation", tags: [] },
      deps,
    );
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T395");
  });

  it("domain_knowledge + electricity tag (auto) → T415", async () => {
    const { deps, spawnArgs } = makeKindDeps();
    await runThumbnailHearing(
      {
        ...kindBase,
        knowledgeKind: "domain_knowledge",
        tags: ["electricity"],
      },
      deps,
    );
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("T415");
  });

  it("concept (auto) → 既存 K-* デフォルト (後方互換)", async () => {
    const { deps, spawnArgs } = makeKindDeps();
    await runThumbnailHearing(
      { ...kindBase, knowledgeKind: "concept", tags: [] },
      deps,
    );
    // default_count=1 → first knowledge pattern K-HERO
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("K-HERO");
  });

  it("knowledgeKind 未指定 (auto) → 既存 knowledge 経路 (後方互換)", async () => {
    const { deps, spawnArgs } = makeKindDeps();
    await runThumbnailHearing({ ...kindBase }, deps);
    expect(spawnArgs[0]![spawnArgs[0]!.indexOf("--pattern") + 1]).toBe("K-HERO");
  });
});
