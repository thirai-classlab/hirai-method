/**
 * auto-tag.ts — Haiku による カテゴリ1件 + タグ複数件 の候補抽出コア
 *
 * 設計書 `docs/phase-8-posting-skill-design.md` L210-276, plan §8.E.5
 *
 * 役割:
 *   category-tag.ts から切り出した「Haiku プロンプト組み立て + JSON パース」のみを扱う
 *   pure function 層。I/O は runLLM の 1 回きり（失敗時 1 回リトライ）。
 *
 * 公開 API:
 *   - buildAutoTagPrompt(input): string            — few-shot 付きプロンプト文字列
 *   - parseAutoTagResponse(raw, opts?): Parsed    — JSON 抽出と検証
 *   - extractCandidatesFromContent(input, deps?)  — Haiku 呼び出し + 失敗時 1 回リトライ
 *
 * 方針:
 *   - Haiku は温度 0.2 / max 300 tokens に抑え、JSON 出力を強制
 *   - ` ```json ` や ` ``` ` の code fence が混ざっても吸収
 *   - tags は default 5 件までに truncate（エラーにしない）
 */

import { runLLM, type RunLLMResult } from "../lib/llm.js";
import type { CategoryAllowEntry } from "./category-allowlist.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** posting side で扱う 3 種のコンテンツタイプ */
export type AutoTagContentType = "knowledge" | "tech_articles" | "weekly_issues";

export interface AutoTagInput {
  title: string;
  body: string;
  type: AutoTagContentType;
}

/** buildAutoTagPrompt のオプション (Wave 11.3e W2) */
export interface BuildAutoTagPromptOpts {
  /** 本リポ /api/content-categories から取得した許可カテゴリーリスト */
  allowedCategories?: CategoryAllowEntry[];
}

export interface CategorySuggestion {
  slug: string;
  name: string;
  confidence: number;
  /** resolve 後に付与される。Haiku 出力には含まれない */
  isNew?: boolean;
}

export interface TagSuggestion {
  name: string;
  confidence: number;
}

export interface AutoTagParsed {
  category: CategorySuggestion;
  tags: TagSuggestion[];
}

export interface ParseOptions {
  /** tags の上限。default 5。指定を超えたら truncate */
  tagLimit?: number;
}

export interface ExtractDeps {
  /** 注入可能な runLLM。テストは vi.mock() を使うが将来 DI に切替可能 */
  runLLM?: (
    args: Parameters<typeof runLLM>[0],
  ) => Promise<RunLLMResult>;
  /** 許可カテゴリーリスト (Wave 11.3e W2)。設定されたらプロンプトに closed-enum 制約として埋め込む */
  allowedCategories?: CategoryAllowEntry[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_TAG_LIMIT = 5;
const BODY_EXCERPT_MAX = 800; // 本文はプロンプトに 800 文字まで抜粋
const HAIKU_MAX_TOKENS = 300;
const HAIKU_TEMPERATURE = 0.2;

/**
 * 3 種のコンテンツタイプに最低 1 件ずつ掲載する few-shot 例。
 * プロンプト総量が膨らみすぎないよう、summary を短めに抑える。
 */
const FEW_SHOTS: Array<{
  title: string;
  excerpt: string;
  type: AutoTagContentType;
  category: CategorySuggestion;
  tags: TagSuggestion[];
}> = [
  {
    title: "Next.js 16 の Cache Components を本番で試した",
    excerpt:
      "Next.js 16 の Cache Components (旧 PPR) を週報サイトに導入し、TTFB を 90% 以上削減した。use cache ディレクティブと Suspense 境界の扱いが肝だった。",
    type: "tech_articles",
    category: { slug: "casestudy", name: "ケーススタディ", confidence: 0.95 },
    tags: [
      { name: "Next.js", confidence: 0.95 },
      { name: "Cache Components", confidence: 0.9 },
      { name: "パフォーマンス", confidence: 0.8 },
    ],
  },
  {
    title: "pnpm workspace の node_modules が膨らんだときの削減手順",
    excerpt:
      "モノレポ開発で node_modules が肥大化した際の、不要依存の特定と dedupe、公開レジストリキャッシュの見直しの TIPS。",
    type: "knowledge",
    category: { slug: "tips", name: "TIPS", confidence: 0.9 },
    tags: [
      { name: "pnpm", confidence: 0.95 },
      { name: "モノレポ", confidence: 0.85 },
      { name: "DevOps", confidence: 0.75 },
    ],
  },
  {
    title: "今週のフロントエンドニュース 2026-04-10",
    excerpt:
      "TC39 の ES2026 ステージ 4 ジャンプ、React 20 α、Vite 8 のメタフレームワーク API 正式化など。",
    type: "weekly_issues",
    category: { slug: "frontend", name: "フロントエンド", confidence: 0.93 },
    tags: [
      { name: "TC39", confidence: 0.85 },
      { name: "React", confidence: 0.85 },
      { name: "Vite", confidence: 0.8 },
    ],
  },
];

// ---------------------------------------------------------------------------
// Public API: buildAutoTagPrompt
// ---------------------------------------------------------------------------

/**
 * Haiku に渡すプロンプトを組み立てる。
 *   - few-shot を 3 件埋め込み、出力は 1 個の JSON オブジェクトのみ
 *   - 本文は {@link BODY_EXCERPT_MAX} 文字で打ち切って送る
 */
export function buildAutoTagPrompt(
  input: AutoTagInput,
  opts: BuildAutoTagPromptOpts = {},
): string {
  const excerpt = input.body.length > BODY_EXCERPT_MAX
    ? input.body.slice(0, BODY_EXCERPT_MAX) + "…"
    : input.body;

  const shots = FEW_SHOTS.map((s, i) => {
    const out = JSON.stringify({ category: s.category, tags: s.tags });
    return [
      `例${i + 1}:`,
      `タイトル: ${s.title}`,
      `種別: ${s.type}`,
      `本文: ${s.excerpt}`,
      `出力: ${out}`,
    ].join("\n");
  }).join("\n\n");

  const baseLines = [
    "あなたはコンテンツ分類アシスタントです。与えられた記事に対して、",
    "最も適切なカテゴリ1件とタグを最大5件、信頼度 (0.0〜1.0) を添えて提案してください。",
    "出力は JSON 1 オブジェクトのみ。余計な説明や装飾は一切不要です。",
    "",
    "スキーマ:",
    '  { "category": { "slug": string, "name": string, "confidence": number },',
    '    "tags": [{ "name": string, "confidence": number }] }',
    "",
    shots,
    "",
    "対象:",
    `タイトル: ${input.title}`,
    `種別: ${input.type}`,
    `本文: ${excerpt}`,
    "出力:",
  ];

  // Wave 11.3e W2: allowedCategories が指定されたら "出力:" の直前に
  // closed-enum 制約 section を挿入する。LLM が allowlist 外を生成しないよう抑止。
  const allowList = opts.allowedCategories ?? [];
  if (allowList.length === 0) {
    return baseLines.join("\n");
  }
  const allowSection = [
    "",
    "**厳格な制約: category.slug は必ず以下の許可リストから選ぶこと。**",
    "**新規 slug の生成は禁止。**",
    ...allowList.map(c =>
      `  - ${c.slug}: ${c.name}${c.description ? ` — ${c.description}` : ""}`,
    ),
    "",
    "もし既存 slug が全くマッチしない場合は、最も意味が近いものを選び confidence を < 0.5 に下げること。",
    "",
  ];
  const outputIdx = baseLines.indexOf("出力:");
  return [
    ...baseLines.slice(0, outputIdx),
    ...allowSection,
    ...baseLines.slice(outputIdx),
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Public API: parseAutoTagResponse
// ---------------------------------------------------------------------------

/**
 * Haiku の出力を JSON としてパースする。
 *   - ```json ... ``` / ``` ... ``` の code fence を剥がす
 *   - JSON 構造・型・confidence レンジを検証
 *   - tags は tagLimit (default 5) で truncate
 *
 * @throws 不正な JSON / 不正な構造 / 不正な confidence の場合
 */
export function parseAutoTagResponse(
  raw: string,
  opts: ParseOptions = {},
): AutoTagParsed {
  const tagLimit = opts.tagLimit ?? DEFAULT_TAG_LIMIT;
  const stripped = stripCodeFence(raw);

  let obj: unknown;
  try {
    obj = JSON.parse(stripped);
  } catch (err) {
    throw new Error(
      `parseAutoTagResponse: failed to parse JSON: ${(err as Error).message}; raw="${truncate(raw, 120)}"`,
    );
  }

  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    throw new Error(
      `parseAutoTagResponse: expected object, got ${Array.isArray(obj) ? "array" : typeof obj}`,
    );
  }

  const cat = (obj as Record<string, unknown>).category;
  if (!cat || typeof cat !== "object" || Array.isArray(cat)) {
    throw new Error("parseAutoTagResponse: missing/invalid `category`");
  }
  const c = cat as Record<string, unknown>;
  const slug = c.slug;
  const name = c.name;
  const confidence = c.confidence;
  if (typeof slug !== "string" || slug.length === 0) {
    throw new Error("parseAutoTagResponse: category.slug must be non-empty string");
  }
  if (typeof name !== "string" || name.length === 0) {
    throw new Error("parseAutoTagResponse: category.name must be non-empty string");
  }
  if (typeof confidence !== "number" || Number.isNaN(confidence)) {
    throw new Error(
      `parseAutoTagResponse: category.confidence must be a number (got ${typeof confidence})`,
    );
  }
  if (confidence < 0 || confidence > 1) {
    throw new Error(
      `parseAutoTagResponse: category.confidence out of [0,1]: ${confidence}`,
    );
  }

  const tagsRaw = (obj as Record<string, unknown>).tags;
  if (!Array.isArray(tagsRaw)) {
    throw new Error("parseAutoTagResponse: tags must be an array");
  }
  const tags: TagSuggestion[] = [];
  for (const t of tagsRaw) {
    if (!t || typeof t !== "object" || Array.isArray(t)) continue;
    const tn = (t as Record<string, unknown>).name;
    const tc = (t as Record<string, unknown>).confidence;
    if (typeof tn !== "string" || tn.length === 0) {
      throw new Error("parseAutoTagResponse: tag.name must be non-empty string");
    }
    if (typeof tc !== "number" || Number.isNaN(tc)) {
      throw new Error(
        `parseAutoTagResponse: tag.confidence must be a number (got ${typeof tc})`,
      );
    }
    if (tc < 0 || tc > 1) {
      throw new Error(
        `parseAutoTagResponse: tag.confidence out of [0,1]: ${tc}`,
      );
    }
    tags.push({ name: tn, confidence: tc });
  }

  return {
    category: { slug, name, confidence },
    tags: tags.slice(0, tagLimit),
  };
}

// ---------------------------------------------------------------------------
// Public API: extractCandidatesFromContent
// ---------------------------------------------------------------------------

/**
 * 本文 → Haiku → JSON パース を一本化した高レベル API。
 * 失敗時は 1 回だけリトライし、それでも駄目なら throw する。
 */
export async function extractCandidatesFromContent(
  input: AutoTagInput,
  deps: ExtractDeps = {},
): Promise<AutoTagParsed> {
  const llm = deps.runLLM ?? runLLM;
  const prompt = buildAutoTagPrompt(input, {
    allowedCategories: deps.allowedCategories,
  });
  const args = {
    kind: "auto-tag" as const,
    prompt,
    maxOutputTokens: HAIKU_MAX_TOKENS,
    temperature: HAIKU_TEMPERATURE,
  };

  try {
    const first = await llm(args);
    return parseAutoTagResponse(first.text);
  } catch (err) {
    // 1 度だけリトライ。失敗も同様に上流へ伝播させる。
    const retry = await llm(args);
    try {
      return parseAutoTagResponse(retry.text);
    } catch (err2) {
      throw new Error(
        `extractCandidatesFromContent: failed to parse after retry — initial="${(err as Error).message}", retry="${(err2 as Error).message}"`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function stripCodeFence(raw: string): string {
  const trimmed = raw.trim();
  // ```json\n ... \n```  /  ```\n ... \n```
  const fence = /^```(?:json)?\s*\n([\s\S]*?)\n```$/;
  const m = trimmed.match(fence);
  if (m) return m[1]!.trim();
  return trimmed;
}

function truncate(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, n) + "…";
}
