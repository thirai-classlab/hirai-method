/**
 * src/posting/tag-hearing.ts — Task #58 Step 2
 *
 * master tag hearing 層。`knowledge.kind` (concept | operation | domain_knowledge)
 * に応じて、operation/domain_knowledge 投稿時に master tag を multi-select させる。
 *
 * - operation        → 部署 master (DEPARTMENT_TAGS) から 1 件以上を選択
 * - domain_knowledge → 業界 master (INDUSTRY_TAGS) から 1 件以上を選択
 * - concept          → master 提示なし (既存の自由入力タグ経路 = category-tag.ts
 *                       が担うため、ここは空配列を返して委譲する)
 *
 * 戻り値は選択された **tag slug** の配列。呼び出し側 (stage 11) が
 * confirmedMeta.tags へマージし、後続の /api/ingest 経路へ流す。
 *
 * 設計メモ:
 *   - master tag 定義はサイト側 migration で seed 済み (#57)。本 Step では定数で
 *     ハードコードする (DRY の単一真実源)。将来 `/api/tags?kind=department` 等の
 *     endpoint fetch 化の余地はあるが、本 Step ではスコープ外。
 *   - readline 等の外部境界は TagHearingDeps.promptUser で抽象化し、テストから
 *     差し替え可能にする (thumbnail-hearing.ts と同じ DI パターン)。
 */

import type { KnowledgeKind } from "../../scripts/post-types.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface MasterTag {
  /** kebab-case の slug (サイト側 tags.slug と一致、#57 で seed 済み) */
  slug: string;
  /** 日本語表示名 (サイト側 tags.name と一致) */
  name: string;
}

export interface TagHearingDeps {
  /** readline ベースの 1 行プロンプト。改行除去後の文字列を返す。 */
  promptUser: (question: string) => Promise<string>;
  /** 進捗ログ (省略可、未指定時は no-op) */
  logger?: (msg: string) => void;
}

// ---------------------------------------------------------------------------
// Master tag definitions (#57 seed と一致、本 Step の単一真実源)
//   将来 `/api/tags?kind=department|industry` の fetch 化余地あり (本 Step 外)。
// ---------------------------------------------------------------------------

/**
 * 部署 master (operation 用) — 7 件。
 * #58 round-2: サイト側 Task #57 migration の本番 seed taxonomy (Option A) に是正。
 * slug / name はサイト DB の tags(kind='department') と完全一致させる (単一真実源)。
 */
export const DEPARTMENT_TAGS: readonly MasterTag[] = [
  { slug: "cx-ll", name: "CXLL" },
  { slug: "cxs", name: "CXS" },
  { slug: "ea", name: "EA" },
  { slug: "ea-ops", name: "EA2" },
  { slug: "nw", name: "NW" },
  { slug: "system", name: "システム部" },
  { slug: "corporate", name: "コーポレート" },
] as const;

/**
 * 業界 master (domain_knowledge 用) — 5 件。
 * #58 round-2: サイト側 Task #57 migration の本番 seed taxonomy (Option A) に是正。
 * slug / name はサイト DB の tags(kind='industry') と完全一致させる。
 */
export const INDUSTRY_TAGS: readonly MasterTag[] = [
  { slug: "electricity", name: "電気" },
  { slug: "gas", name: "ガス" },
  { slug: "water", name: "水道" },
  { slug: "internet", name: "インターネット" },
  { slug: "moving", name: "引越し" },
] as const;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

const MAX_ATTEMPTS = 5;

/**
 * kind に応じた master tag hearing を実行し、選択された slug 配列を返す。
 *
 *   - operation        → 部署 multi-select (1 件以上必須)
 *   - domain_knowledge → 業界 multi-select (1 件以上必須)
 *   - concept          → master 提示なし → [] (既存自由入力経路へ委譲、後方互換)
 *
 * @throws 再質問の上限 (MAX_ATTEMPTS) を超えても有効選択が得られない場合
 */
export async function askTagsForKind(
  kind: KnowledgeKind,
  deps: TagHearingDeps,
): Promise<string[]> {
  if (kind === "concept") {
    // 既存の自由入力タグ経路 (category-tag.ts) が担う。master は提示しない。
    return [];
  }

  const masters = kind === "operation" ? DEPARTMENT_TAGS : INDUSTRY_TAGS;
  const label = kind === "operation" ? "部署" : "業界";
  return askMasterMultiSelect(masters, label, deps);
}

// ---------------------------------------------------------------------------
// Internal: multi-select prompt loop
// ---------------------------------------------------------------------------

async function askMasterMultiSelect(
  masters: readonly MasterTag[],
  label: string,
  deps: TagHearingDeps,
): Promise<string[]> {
  const log = deps.logger ?? (() => {});
  const lines = masters.map((m, i) => `  ${i + 1}. ${m.slug}  (${m.name})`);
  const message = [
    "",
    `[tag] ${label}を選択してください (1 件以上必須):`,
    ...lines,
    "  番号 (例: 1) または slug (例: system-tech-lead) を入力。",
    "  複数選択はカンマ区切り (例: 1,4)。",
    "> ",
  ].join("\n");

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const raw = (await deps.promptUser(message)).trim();
    if (raw === "") {
      log(`[tag] ${label}が未選択です。1 件以上選択してください。`);
      continue;
    }
    const tokens = raw
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);
    const resolved = resolveTokens(tokens, masters, log);
    if (resolved === null) continue; // 無効トークンあり → 再質問
    if (resolved.length === 0) {
      log(`[tag] ${label}が未選択です。1 件以上選択してください。`);
      continue;
    }
    return resolved;
  }
  throw new Error(
    `[tag-hearing] ${label} selection: too many invalid attempts`,
  );
}

/**
 * 入力トークン (番号 or slug) を slug 配列へ解決する。
 * いずれかが無効なトークンを含む場合は null を返す (再質問させる)。
 * 重複は順序を保って除去。
 */
function resolveTokens(
  tokens: string[],
  masters: readonly MasterTag[],
  log: (msg: string) => void,
): string[] | null {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of tokens) {
    const slug = resolveOne(t, masters);
    if (!slug) {
      log(`[tag] "${t}" は候補にありません。`);
      return null;
    }
    if (!seen.has(slug)) {
      seen.add(slug);
      out.push(slug);
    }
  }
  return out;
}

/** 単一トークン (番号 1-based or slug) を slug へ解決。無効時 undefined。 */
function resolveOne(
  token: string,
  masters: readonly MasterTag[],
): string | undefined {
  const asIndex = Number.parseInt(token, 10);
  if (
    String(asIndex) === token &&
    asIndex >= 1 &&
    asIndex <= masters.length
  ) {
    return masters[asIndex - 1]?.slug;
  }
  const bySlug = masters.find((m) => m.slug === token);
  return bySlug?.slug;
}

// ---------------------------------------------------------------------------
// Default promptUser factory (CLI entry; tests inject their own)
// ---------------------------------------------------------------------------

/**
 * readline ベースの 1 行プロンプト。質問ごとに interface を開閉する
 * (thumbnail-hearing.ts makeDefaultPromptUser と同方針)。
 */
export function makeDefaultTagPromptUser(): (q: string) => Promise<string> {
  return async (question: string) => {
    const readline = await import("node:readline/promises");
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    try {
      return await rl.question(question);
    } finally {
      rl.close();
    }
  };
}
