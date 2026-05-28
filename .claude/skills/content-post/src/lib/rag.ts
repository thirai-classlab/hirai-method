/**
 * RAG: 本リポの `search_hybrid` / `search_similar` RPC ラッパ
 *
 * 戻り値の型は本リポ (classlab-weekly-news) `src/types/database.ts` と整合:
 *   - HybridSearchResult: id / content_type / title / slug / summary / category /
 *                        rank / matched_sources / ft_rank / tg_rank / sem_rank / published_at
 *   - SimilarContent:     id / content_type / content_id / similarity
 *
 * Wave D3 で Supabase 型生成後は `Database["public"]["Functions"]["search_hybrid"]["Returns"]`
 * を直接参照する予定。現時点では構造を明示した型を同梱する。
 *
 * エラー方針:
 *   - 設定エラー (env 欠落等) は supabase.ts が throw
 *   - RPC エラーは console.error + 空配列を返して呼び出し元の制御フローを壊さない
 */

import { getSupabaseClient } from "./supabase.js";
import { generateEmbedding } from "./embedding.js";

/** 本リポ `src/types/database.ts` の ContentType と一致させる */
export type ContentType = "issue" | "article" | "knowledge";

/** 本リポ `HybridSearchResult` と同形 */
export interface HybridSearchResult {
  id: string;
  content_type: ContentType;
  title: string;
  slug: string;
  summary: string;
  category: string | null;
  rank: number;
  matched_sources: string[]; // ['ft','tg','sem'] の組み合わせ
  ft_rank: number | null;
  tg_rank: number | null;
  sem_rank: number | null;
  published_at: string | null;
}

/** 本リポ `SimilarContent` と同形 */
export interface SimilarContent {
  id: string;
  content_type: ContentType;
  content_id: string;
  similarity: number;
}

export interface SearchHybridOptions {
  /** 返却件数。デフォルト 20 */
  limit?: number;
  /** 取得後にクライアント側でフィルタする content_type 一覧（省略時は全種別） */
  types?: ContentType[];
}

export interface SearchSimilarOptions {
  /** 類似度の下限（0.0-1.0）。デフォルト 0 (RPC 側のデフォルトに委ねる) */
  threshold?: number;
  /** 返却件数。デフォルト 10 */
  limit?: number;
}

const DEFAULT_HYBRID_LIMIT = 20;
const DEFAULT_SIMILAR_LIMIT = 10;

/**
 * ハイブリッド検索 (全文 + trigram + ベクトル、RPC 側で RRF 統合)
 * クエリを embedding 化してから `search_hybrid` を呼ぶ。
 * @param query 検索クエリ（2 文字未満は即座に空配列）
 */
export async function searchHybrid(
  query: string,
  opts: SearchHybridOptions = {},
): Promise<HybridSearchResult[]> {
  const trimmed = query?.trim() ?? "";
  if (trimmed.length < 2) return [];

  const limit = opts.limit ?? DEFAULT_HYBRID_LIMIT;
  const types = opts.types;

  let embedding: number[];
  try {
    embedding = await generateEmbedding(trimmed);
  } catch (err) {
    console.error("[searchHybrid] embedding failed:", err);
    return [];
  }

  const supabase = getSupabaseClient();
  const { data, error } = await supabase.rpc("search_hybrid", {
    query_text: trimmed,
    query_embedding: embedding,
    match_count: limit,
  });

  if (error) {
    console.error("[searchHybrid] rpc error:", error);
    return [];
  }

  const rows = (data ?? []) as HybridSearchResult[];
  return types && types.length > 0
    ? rows.filter((r) => types.includes(r.content_type))
    : rows;
}

/**
 * セマンティック類似検索 (cosine 距離、RPC `search_similar`)
 * @param embedding クエリ側の embedding（次元は EMBEDDING_DIMENSIONS と一致必須）
 */
export async function searchSimilar(
  embedding: number[],
  opts: SearchSimilarOptions = {},
): Promise<SimilarContent[]> {
  if (!embedding || embedding.length === 0) {
    console.error("[searchSimilar] empty embedding");
    return [];
  }

  const limit = opts.limit ?? DEFAULT_SIMILAR_LIMIT;
  const threshold = opts.threshold;

  const supabase = getSupabaseClient();
  const { data, error } = await supabase.rpc("search_similar", {
    query_embedding: embedding,
    match_count: limit,
  });

  if (error) {
    console.error("[searchSimilar] rpc error:", error);
    return [];
  }

  const rows = (data ?? []) as SimilarContent[];
  return threshold !== undefined
    ? rows.filter((r) => r.similarity >= threshold)
    : rows;
}

/**
 * コンテンツ ID から embedding を引き、自身を除外した類似件を返す便利関数
 * （本リポ `getSimilarContent` と同等、投稿時の関連紐付けに利用）
 */
export async function searchSimilarById(
  contentType: ContentType,
  contentId: string,
  opts: SearchSimilarOptions = {},
): Promise<SimilarContent[]> {
  const supabase = getSupabaseClient();

  const { data: ownEmbeddingRow, error: err1 } = await supabase
    .from("content_embeddings")
    .select("embedding")
    .eq("content_type", contentType)
    .eq("content_id", contentId)
    .single();

  if (err1 || !ownEmbeddingRow) {
    console.error(
      "[searchSimilarById] embedding not found for",
      contentType,
      contentId,
      err1,
    );
    return [];
  }

  const embedding = (ownEmbeddingRow as { embedding: number[] }).embedding;
  const limit = opts.limit ?? DEFAULT_SIMILAR_LIMIT;

  // 自身を含む可能性があるので +1 件取って後段で除外
  const results = await searchSimilar(embedding, {
    ...opts,
    limit: limit + 1,
  });

  return results
    .filter(
      (r) => !(r.content_type === contentType && r.content_id === contentId),
    )
    .slice(0, limit);
}
