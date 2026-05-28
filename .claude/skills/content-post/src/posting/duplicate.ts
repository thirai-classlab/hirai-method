/**
 * duplicate.ts — 投稿前の重複検知
 *
 * 設計書 `docs/phase-8-posting-skill-design.md` Step 5、plan §8.E.3
 *
 * 公開 API:
 *   checkDuplicate(body, type, { client, threshold? }) → Promise<DuplicateResult>
 *
 * 判定基準（デフォルト）:
 *   similarity ≥ 0.90 → level: 'block'
 *   0.80 ≤ similarity < 0.90 → level: 'warn'
 *   それ以外 → level: 'ok'
 *
 * 実装詳細:
 *   1. 本文を `generateEmbedding()` で 1024 次元ベクトル化
 *   2. `searchSimilar()` RPC で上位 5 件取得
 *   3. similarity 降順でソートして matches に格納
 *   4. 最大 similarity で level を判定、reason に閾値ヒントを詰める
 *
 * 依存の境界（テスト都合）:
 *   - `generateEmbedding` と `searchSimilar` は test 側で `vi.mock()` され、
 *     Supabase クライアントを直接触らない。`opts.client` はシグネチャ互換と
 *     将来の拡張用（RPC を直接呼びたいケース）として保持する。
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { generateEmbedding } from "../lib/embedding.js";
import { searchSimilar, type SimilarContent } from "../lib/rag.js";
import type { PostingContentType } from "./validate.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type DuplicateLevel = "ok" | "warn" | "block";

export interface DuplicateThreshold {
  /** これ以上で block。デフォルト 0.90 */
  block: number;
  /** これ以上で warn（block 未満）。デフォルト 0.80 */
  warn: number;
}

export interface DuplicateMatch extends SimilarContent {}

export interface DuplicateResult {
  level: DuplicateLevel;
  matches: DuplicateMatch[];
  reason: string | null;
}

export interface CheckDuplicateOptions {
  client: SupabaseClient;
  threshold?: DuplicateThreshold;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_THRESHOLD: DuplicateThreshold = {
  block: 0.9,
  warn: 0.8,
};

const SIMILAR_LIMIT = 5;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * 本文に対し既存コンテンツとの類似度をチェックし、投稿可否を判定する。
 *
 * @param body Markdown 本文（frontmatter 剥がし後を想定）
 * @param _type コンテンツ種別（将来 matches 側でフィルタしたくなった時用。現状は未フィルタ）
 * @param opts 必須: client, 任意: threshold
 * @throws generateEmbedding が失敗した場合は上流に伝播
 */
export async function checkDuplicate(
  body: string,
  _type: PostingContentType,
  opts: CheckDuplicateOptions,
): Promise<DuplicateResult> {
  const threshold = opts.threshold ?? DEFAULT_THRESHOLD;

  // 1. 本文 → embedding。失敗は呼び出し元に委ねる（CLI で --force 扱いなど）
  const embedding = await generateEmbedding(body);

  // 2. RPC で上位 N 件取得
  const rawMatches = await searchSimilar(embedding, { limit: SIMILAR_LIMIT });

  // 3. similarity 降順でソート。searchSimilar の戻り値順序に依存しない
  const matches = [...rawMatches].sort((a, b) => b.similarity - a.similarity);

  if (matches.length === 0) {
    return { level: "ok", matches: [], reason: null };
  }

  // 4. 最大類似度で判定
  const top = matches[0]!;
  const { similarity } = top;
  const level = classify(similarity, threshold);
  const reason = level === "ok" ? null : buildReason(level, top);

  return { level, matches, reason };
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

function classify(
  similarity: number,
  threshold: DuplicateThreshold,
): DuplicateLevel {
  if (similarity >= threshold.block) return "block";
  if (similarity >= threshold.warn) return "warn";
  return "ok";
}

function buildReason(level: DuplicateLevel, top: SimilarContent): string {
  const sim = top.similarity.toFixed(2);
  if (level === "block") {
    return `duplicate block: highly similar existing content (similarity=${sim}, content_id=${top.content_id})`;
  }
  return `duplicate warn: similar existing content (similarity=${sim}, content_id=${top.content_id})`;
}
