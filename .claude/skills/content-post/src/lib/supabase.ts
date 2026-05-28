/**
 * Supabase クライアント (投稿スキル専用 / service_role)
 *
 * Wave D3 で `src/types/database.ts` が postinstall により自動生成される。
 * 現時点では generic `SupabaseClient` を返し、型は後段で `Database` に差し替え予定。
 *
 * Notes:
 *  - RLS をバイパスするため `SUPABASE_SERVICE_ROLE_KEY` を利用
 *  - `.env` は import 時点で `dotenv.config()` により読込
 *  - Vercel Marketplace 同様の `NEXT_PUBLIC_*` フォールバックは不要（雑務は Vercel 環境ではない）
 *  - 致命的な env 欠落（URL / service_role key）時のみ throw、それ以外は呼び出し側でハンドリング
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config as loadDotenv } from "dotenv";

// `.env` をスキル作業ディレクトリから読込（存在しなければ黙ってスキップ）
loadDotenv();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

let _client: SupabaseClient | null = null;

/**
 * service_role キーで認証された Supabase クライアントを返す（プロセス内シングルトン）
 * @throws 環境変数が未設定の場合のみ throw（初回呼び出し時に検出）
 */
export function getSupabaseClient(): SupabaseClient {
  if (_client) return _client;

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required in .env",
    );
  }

  _client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      // service_role はサーバー用途のためセッション管理不要
      persistSession: false,
      autoRefreshToken: false,
    },
  });
  return _client;
}

/** import 時点での env の有無だけ判定する軽量ヘルパ（throw しない） */
export function hasSupabaseConfig(): boolean {
  return Boolean(SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY);
}

/** テスト用: プロセス内キャッシュをクリア */
export function __resetSupabaseClientForTest(): void {
  _client = null;
}
