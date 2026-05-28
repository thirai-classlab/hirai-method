/**
 * Minimal Supabase client mock for posting/* tests.
 *
 * Covers only the two chains the posting pipeline actually uses:
 *   1. `client.from(table).select(cols).eq(col, val).maybeSingle()`
 *      — used by `checkSlugCollision` to probe a single table for an existing slug.
 *   2. `client.rpc(name, args)` — used by `duplicate.ts` via `searchSimilar()`.
 *
 * The helper is intentionally tiny. Tests configure an in-memory `rows` map
 * keyed by table name (array of { slug }) and an `rpcImpl(name, args)` function
 * when RPC behaviour is needed.
 */
import type { SupabaseClient } from "@supabase/supabase-js";

type Row = Record<string, unknown>;

export interface SupabaseMockConfig {
  /** Rows keyed by table name. Only `slug` field is consulted. */
  tables?: Record<string, Row[]>;
  /** Synchronous/async handler for `.rpc(name, args)`. */
  rpcImpl?: (
    name: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: unknown }> | { data: unknown; error: unknown };
}

export function createMockSupabase(cfg: SupabaseMockConfig = {}): SupabaseClient {
  const tables = cfg.tables ?? {};

  const builder = (tableName: string) => {
    const rows = tables[tableName] ?? [];
    let filters: { col: string; val: unknown }[] = [];
    const chain = {
      select: (_cols?: string) => chain,
      eq: (col: string, val: unknown) => {
        filters.push({ col, val });
        return chain;
      },
      maybeSingle: async () => {
        const match = rows.find((r) =>
          filters.every((f) => (r as Row)[f.col] === f.val),
        );
        return { data: match ?? null, error: null };
      },
      single: async () => {
        const match = rows.find((r) =>
          filters.every((f) => (r as Row)[f.col] === f.val),
        );
        return match
          ? { data: match, error: null }
          : { data: null, error: { code: "PGRST116", message: "no rows" } };
      },
    };
    return chain;
  };

  return {
    from: (table: string) => builder(table),
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (!cfg.rpcImpl) return { data: [], error: null };
      return await cfg.rpcImpl(name, args);
    },
  } as unknown as SupabaseClient;
}
