> Layer A: [`workflow.md`](../../rules/workflow.md) §リファクタリング強制 (W3) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# リファクタリング 3 観点詳細 (Layer B)

`/module-review` 3 観点 / `/system-review` system-level 観点の sub-checklist。3 観点本体・pending_findings 連携・yml 制御は Layer A 参照。

## review prompt 規約 (`/module-review` `/system-review` 共通)

- **behavior-preserving 必須** — public API / DB schema 変更禁止
- **全 finding に修正コード提案** — finding だけでなく具体的な patch 候補を併記
- **末尾 `confidence: 0.X`** — F3 抽出対象 (`confidence-gate.sh` で閾値 0.6 未満は block)
- 詳細は [`module-review.md`](../../commands/module-review.md) Phase 3 参照

## 持続可能性 (Sustainability) sub-checklist

- 命名 (camelCase / PascalCase / 意味的に明確か)
- 関数 50 行以内 / ファイル 800 行以内 / ネスト 4 階層以内
- magic number 排除 (定数化)
- 副作用局所化 (pure function 優先)
- 型注釈 (TypeScript / Python type hint)
- silent failure 排除 (error handling 明示)

## 汎用性 (Generality) sub-checklist

- 引数化可能性 (hardcoded value を parameter 化)
- 1 callee 特化排除 (汎用化推奨)
- idiom 準拠 (言語別 idiom: Go の error handling / Rust の Result 等)
- 抽象依存 (interface / trait 経由)
- test seam (mock 注入可能性)

## 非冗長化 (Deduplication) sub-checklist

- DRY (重複ロジック抽出)
- table-driven 化 (switch / if-else 連鎖を data 化)
- util/helper 再発明排除 (既存 utility 流用)
- 既存型流用 (重複 type 定義排除)
- over-engineering 排除 (YAGNI)

## system-level 観点 (`/system-review`) sub-checklist

1. **モジュール間重複** — module 横断 DRY (`/module-review` は module 内 DRY のみ)
2. **横断的責務漏れ** — logging / error handling / observability / rate limiting / authn-authz の一貫性
3. **設計乖離** — `docs/draft/<slug>.md` §3 採用案からの逸脱 / `<slug>.test-design.md` ☒ テストが誤実装されていないか / §6 DoD 充足

## MEDIUM / LOW のみ残存時の skip フロー

- MEDIUM / LOW のみが残存する場合は user 承認のうえ `skip_log` に記録すれば pass 可能 (運用判断)
- skip 記録 format: `{stage: "module-review", reason: "<LOW finding ID 列挙> user approved low-priority", user_approved_at: <ISO-8601>}`
