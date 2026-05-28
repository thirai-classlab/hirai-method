/**
 * Tests for src/posting/tag-hearing.ts — Task #58 Step 2
 *
 * master tag hearing 層: operation → 部署 multi-select / domain_knowledge → 業界
 * multi-select / concept → 既存自由入力 (動作不変)。
 *
 * 観点:
 *   1. DEPARTMENT_TAGS 7 件 / INDUSTRY_TAGS 5 件の master 定義 (slug + name)
 *   2. kind='operation' → 部署 multi-select 経路 (選択 slug 配列を返す)
 *   3. kind='domain_knowledge' → 業界 multi-select 経路
 *   4. kind='concept' → 既存自由入力経路 (legacy fn へ委譲、master を提示しない)
 *   5. multi-select で 1 件以上必須 (空 → 再質問 → 最終的に選択)
 *   6. 番号 / slug いずれの入力も受理、カンマ区切り複数選択
 */
import { describe, it, expect, vi } from "vitest";
import {
  DEPARTMENT_TAGS,
  INDUSTRY_TAGS,
  askTagsForKind,
  type TagHearingDeps,
} from "../../src/posting/tag-hearing.js";

// --- queued reader helper ------------------------------------------------
function makeReader(answers: string[]): TagHearingDeps {
  const queue = [...answers];
  return {
    promptUser: vi.fn(async () => {
      if (queue.length === 0) {
        throw new Error("tag-hearing test: prompt queue exhausted");
      }
      return queue.shift() as string;
    }),
  };
}

// ---------------------------------------------------------------------------
// 1. master 定義
// ---------------------------------------------------------------------------
describe("master tag definitions", () => {
  it("DEPARTMENT_TAGS には 7 件の部署が slug + name で定義される (#57 seed taxonomy)", () => {
    expect(DEPARTMENT_TAGS).toHaveLength(7);
    const bySlug = Object.fromEntries(DEPARTMENT_TAGS.map((t) => [t.slug, t.name]));
    expect(bySlug["cx-ll"]).toBe("CXLL");
    expect(bySlug["cxs"]).toBe("CXS");
    expect(bySlug["ea"]).toBe("EA");
    expect(bySlug["ea-ops"]).toBe("EA2");
    expect(bySlug["nw"]).toBe("NW");
    expect(bySlug["system"]).toBe("システム部");
    expect(bySlug["corporate"]).toBe("コーポレート");
  });

  it("INDUSTRY_TAGS には 5 件の業界が slug + name で定義される (#57 seed taxonomy)", () => {
    expect(INDUSTRY_TAGS).toHaveLength(5);
    const bySlug = Object.fromEntries(INDUSTRY_TAGS.map((t) => [t.slug, t.name]));
    expect(bySlug["electricity"]).toBe("電気");
    expect(bySlug["gas"]).toBe("ガス");
    expect(bySlug["water"]).toBe("水道");
    expect(bySlug["internet"]).toBe("インターネット");
    expect(bySlug["moving"]).toBe("引越し");
  });

  it("master slug はすべて kebab-case (lowercase + 数字 + ハイフン)", () => {
    const slugRe = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
    for (const t of [...DEPARTMENT_TAGS, ...INDUSTRY_TAGS]) {
      expect(t.slug).toMatch(slugRe);
    }
  });
});

// ---------------------------------------------------------------------------
// 2. operation → 部署 multi-select
// ---------------------------------------------------------------------------
describe("askTagsForKind: operation", () => {
  it("番号入力で部署を 1 件選択し slug 配列を返す", async () => {
    const deps = makeReader(["1"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["cx-ll"]);
  });

  it("カンマ区切りで複数の部署を選択できる (番号)", async () => {
    const deps = makeReader(["1,6"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["cx-ll", "system"]);
  });

  it("slug 直接入力でも選択できる", async () => {
    const deps = makeReader(["system"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["system"]);
  });
});

// ---------------------------------------------------------------------------
// 3. domain_knowledge → 業界 multi-select
// ---------------------------------------------------------------------------
describe("askTagsForKind: domain_knowledge", () => {
  it("番号入力で業界を 1 件選択し slug 配列を返す", async () => {
    const deps = makeReader(["1"]);
    const result = await askTagsForKind("domain_knowledge", deps);
    expect(result).toEqual(["electricity"]);
  });

  it("カンマ区切りで複数の業界を選択できる", async () => {
    const deps = makeReader(["1,5"]);
    const result = await askTagsForKind("domain_knowledge", deps);
    expect(result).toEqual(["electricity", "moving"]);
  });
});

// ---------------------------------------------------------------------------
// 4. concept → 既存自由入力 (master を提示しない / legacy fn へ委譲)
// ---------------------------------------------------------------------------
describe("askTagsForKind: concept (backward compat)", () => {
  it("concept では master multi-select を行わず空配列を返す (既存タグ経路に委譲)", async () => {
    // concept は promptUser を 1 度も呼ばない (既存の category-tag.ts 経路が担う)
    const deps = makeReader([]);
    const result = await askTagsForKind("concept", deps);
    expect(result).toEqual([]);
    expect(deps.promptUser).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// 5. 1 件以上必須バリデーション
// ---------------------------------------------------------------------------
describe("askTagsForKind: 1 件以上必須", () => {
  it("空入力では再質問し、有効選択を得るまでループする", async () => {
    const deps = makeReader(["", "  ", "3"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["ea"]);
    expect(deps.promptUser).toHaveBeenCalledTimes(3);
  });

  it("無効な番号 / slug は再質問する", async () => {
    const deps = makeReader(["99", "nope", "5"]);
    const result = await askTagsForKind("domain_knowledge", deps);
    expect(result).toEqual(["moving"]);
  });

  // L8: 番号 0 / 範囲外 (件数+1) は 1-based index 外なので拒否して再質問する
  it("L8: 番号 0 は 1-based index 外として拒否し再質問する", async () => {
    const deps = makeReader(["0", "1"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["cx-ll"]);
    expect(deps.promptUser).toHaveBeenCalledTimes(2);
  });

  it("L8: 範囲外番号 (件数+1) を拒否し再質問する", async () => {
    // DEPARTMENT_TAGS は 7 件なので 8 は範囲外
    const deps = makeReader(["8", "7"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["corporate"]); // index 7 = corporate
    expect(deps.promptUser).toHaveBeenCalledTimes(2);
  });

  it("L8: カンマ区切りに 1 件でも範囲外が混ざると全体を再質問する", async () => {
    // "1,9" の 9 は範囲外 → トークン全体を無効化して再質問
    const deps = makeReader(["1,9", "1,3"]);
    const result = await askTagsForKind("operation", deps);
    expect(result).toEqual(["cx-ll", "ea"]);
    expect(deps.promptUser).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// L9: concept → master を提示せず自由入力タグ経路へ委譲する end-to-end 確認
//   tag-hearing は concept で promptUser を一切呼ばず空配列を返す。後段
//   category-tag.ts の suggestTags / confirmInteractively (自由入力) が担うため、
//   ここでは「hearing 層が concept では一切介入しない」ことを保証する。
// ---------------------------------------------------------------------------
describe("L9: concept は master hearing を介入させず自由入力に委譲", () => {
  it("concept では prompt も master 提示もなく [] を返す (副作用ゼロ)", async () => {
    const deps = makeReader(["should-never-be-consumed"]);
    const result = await askTagsForKind("concept", deps);
    expect(result).toEqual([]);
    expect(deps.promptUser).not.toHaveBeenCalled();
  });
});
