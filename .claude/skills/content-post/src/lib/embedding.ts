/**
 * Embedding 生成 (OpenAI text-embedding-3-large / 1024 次元)
 *
 * 本リポ `src/lib/embedding.ts` とインターフェースを揃え、同一モデル・同一次元で
 * `content_embeddings` に投入することで `search_hybrid` / `search_similar` と整合させる。
 *
 * AI Gateway 経由 (`AI_GATEWAY_API_KEY` 環境変数で自動認証)
 * モデル文字列 `openai/text-embedding-3-large` を渡すと AI SDK が Gateway を経由する。
 *
 * Gotchas:
 *  - 空文字 / 空白のみは OpenAI が 400 を返すため事前に除外する
 *  - 実質上限 8191 tokens を文字数で 6000 に近似し切り詰め
 *  - feedback_ai_gateway_gotchas.md 参照
 */

import { embed, embedMany } from "ai";
import { config as loadDotenv } from "dotenv";

loadDotenv();

// AI Gateway 経由。モデル ID は設計書 (Phase 8) 準拠。
// 実 ID は初回実行時に `curl /v1/models` で存在確認すること。
const MODEL = "openai/text-embedding-3-large";
export const EMBEDDING_DIMENSIONS = 1024;

const MAX_CHARS = 6000;

/**
 * 単一テキストの embedding を生成する
 * @throws 空文字（sanitize 後）の場合
 */
export async function generateEmbedding(text: string): Promise<number[]> {
  const safe = sanitize(text);
  if (!safe) {
    throw new Error("generateEmbedding: empty input after sanitize");
  }

  const { embedding } = await embed({
    model: MODEL,
    value: safe,
    providerOptions: {
      openai: { dimensions: EMBEDDING_DIMENSIONS },
    },
  });
  return embedding;
}

/**
 * 複数テキストの embedding をバッチ生成する（入力順保持、空入力位置は null）
 * @remarks embedMany は大量投入時に 1件ずつより大幅に高速（本リポ実測: 16分 → 2分 / 10,000件）
 */
export async function generateEmbeddings(
  texts: string[],
): Promise<(number[] | null)[]> {
  // 空でない input のみ抽出、元インデックスを保持
  const valid: { idx: number; text: string }[] = [];
  texts.forEach((t, idx) => {
    const safe = sanitize(t);
    if (safe) valid.push({ idx, text: safe });
  });

  if (valid.length === 0) {
    return texts.map(() => null);
  }

  const { embeddings } = await embedMany({
    model: MODEL,
    values: valid.map((v) => v.text),
    providerOptions: {
      openai: { dimensions: EMBEDDING_DIMENSIONS },
    },
  });

  // 元の順序に戻す（欠けた位置は null）
  const result: (number[] | null)[] = texts.map(() => null);
  valid.forEach((v, i) => {
    const emb = embeddings[i];
    if (emb) result[v.idx] = emb;
  });
  return result;
}

/**
 * 空文字・空白のみ・改行のみを弾き、trim + truncate したテキストを返す
 * @returns sanitize 済みテキスト、または空入力なら null
 */
function sanitize(text: string | null | undefined): string | null {
  if (!text) return null;
  const trimmed = text.trim();
  if (trimmed.length === 0) return null;
  return trimmed.length > MAX_CHARS ? trimmed.slice(0, MAX_CHARS) : trimmed;
}
