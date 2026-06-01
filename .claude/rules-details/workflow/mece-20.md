> Layer A: [`workflow.md`](../../rules/workflow.md) §テスト設計の MECE 強制 (W1) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 20 MECE 各論 (Layer B)

`/test-design` の MECE 20 カテゴリ各論 (採用 / 不採用判定例) + 3 agent 投票による default 判定。20 カテゴリ一覧・user スコープ承認・不採用理由 4 種は Layer A 参照。

## 各カテゴリの採用 / 不採用判定例

| # | カテゴリ | 採用例 | 不採用例 |
|---|---|---|---|
| 1 | 単体 | 全機能で原則 ☑ | 純粋 UI prop drilling のみ → `not-applicable` |
| 2 | 統合 | API + DB 連動 → ☑ | 単一 module 完結 → `scope-excluded` |
| 3 | E2E | UI 変更含む Task → 必須 ☑ | backend 専用 task → `scope-excluded` |
| 4 | DB | migration 含む → ☑ | DB 触らない → `not-applicable` |
| 5 | 境界値 | numeric range / string length 制約あり → ☑ | enum 固定値のみ → `accepted-risk` |
| 6 | 異常系 | error handling 重要 → ☑ | happy path 確認 task → `scope-excluded` |
| 7 | 回帰 | 既存機能修正 task は必須 ☑ | 完全新規機能 → `not-applicable` |
| 8 | カバレッジ計測 | 大規模 module → ☑ | 1 file 数十行 → `scope-excluded` |
| 9 | 網羅性検証 | enum / discriminated union → ☑ | bool flag のみ → `not-applicable` |
| 10 | 完全性検証 | invariant 強い構造 → ☑ | 柔軟性優先設計 → `accepted-risk` |
| 11 | 性能 | response time SLA → ☑ | 内部 utility → `not-applicable` |
| 12 | 負荷 | 高 throughput endpoint → ☑ | 管理画面 → `accepted-risk` |
| 13 | セキュリティ | 認証 / 認可 / 入力検証 → ☑ | 内部 helper → `not-applicable` |
| 14 | 互換性 | 公開 API / DB schema → ☑ | private module → `not-applicable` |
| 15 | アクセシビリティ | UI 含む → ☑ | backend → `not-applicable` |
| 16 | i18n | 多言語対応 product → ☑ | 内部 tool → `scope-excluded` |
| 17 | smoke | 重要 happy path → ☑ | edge case のみ → `existing-coverage` |
| 18 | シナリオ | user flow 重要 → ☑ | unit-level fix → `scope-excluded` |
| 19 | chaos・障害注入 | 高可用性要求 → ☑ | 内部 tool → `accepted-risk` |
| 20 | 契約テスト | microservice 跨ぎ → ☑ | monolith → `not-applicable` |

## 3 agent 投票による default 判定

- 3 agent 中 **2 以上が採用推奨** → デフォルト ☑
- 3 agent 中 **2 以上が不採用推奨** → デフォルト ☒
- **意見割れ (1-1-1)** → ☐ + コメント「user 判断要」
