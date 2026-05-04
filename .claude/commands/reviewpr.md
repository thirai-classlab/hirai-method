---
description: GitHub PR を既存 8 ルール + Critical Operational Lessons + CI 状況と照合してレビュー。引数: PR 番号 or URL。
---

# /reviewpr — PR 多軸レビュー

GitHub MCP / `gh` CLI で PR を取得し、本リポの精緻なルール群と照合してレビューを実施します。

## 使い方

```
/reviewpr 123                       # PR 番号
/reviewpr https://github.com/ORG/REPO/pull/123
/reviewpr 123 --quick                # CI + diff 行数のみ高速確認
/reviewpr 123 --focus auth           # 特定ルールに絞る (auth/db/cache/style/posting)
```

## 動作

### Phase 1: 取得

GitHub MCP の `mcp__github__pull_request_read` を使用(失敗時は `gh pr view` フォールバック):

1. PR タイトル / 説明 / リンク issue
2. 変更ファイル一覧 + 差分行数
3. CI 状況 (`gh pr checks`)
4. レビューコメント既存分

### Phase 2: 8 ルール照合

変更ファイルパスから該当する `.claude/rules/` を特定し、各ルールの観点で違反を検出:

| 変更パス | 該当ルール | 主要チェック観点 |
|---------|-----------|---------------|
| `src/**` `tests/**` `scripts/**` | development-process.md | TDD・委譲・1 ファイル責任 |
| `src/**/*.{css,tsx}` | styling.md | Tailwind v4 `dark:` 禁止・モノトーン・見出し階層 |
| `src/lib/supabase*.ts` `src/types/**` `supabase/migrations/**` | database.md | RLS・モックモード・CLI 経由 |
| `src/lib/auth.ts` `middleware.ts` | auth.md | Google SSO・`allowed_emails.role` SSoT・PUBLIC_PATHS |
| `docs/tasks/**` `docs/draft/**` | development-process.md | 設計→承認→タスク化フロー |
| `next.config.ts` `src/app/**` `src/components/**` | nextjs-cache-components.md | `dynamic`/`runtime`/`revalidate` 禁止・Suspense 境界・`'use cache'` 内非決定値禁止 |
| `src/lib/{extract-mermaid,highlight,rewrite-images}.ts` `src/__tests__/fixtures/**` | posting-html-fixture-sync.md | 投稿側-消費側 fixture 共有 |
| 全変更 | CLAUDE.md "Autonomous Progression" | 自律進行範囲内か・破壊的 DB 変更がないか |

### Phase 3: Critical Operational Lessons 照合

CLAUDE.md の HIGH 教訓 5 件を必ずチェック:

- [ ] RLS 一元化、`queries.ts` への `.not()` 追加なし
- [ ] `.single()` を chunked テーブルで使っていない(`.limit(1)[0]` 必須)
- [ ] `--update` フローで snapshot を伴う実装か(関連箇所のみ)
- [ ] 独自 secret 認証 API を増やしている場合、middleware `PUBLIC_PATHS` も更新済か(3 点セット)
- [ ] Cache Components 影響変更がある場合、`npm run build` を CI で必ず実行しているか

### Phase 4: 構造化レビュー出力

```markdown
## PR #<NUMBER>: <TITLE>

**サマリ:** <1 行>
**ファイル数:** <N> / **追加行:** <+X> / **削除行:** <-Y>
**CI:** ✅ all green / ⚠ 一部失敗 / ❌ blocking
**該当ルール:** auth.md, database.md, ...

### CRITICAL(blocking)
- <ファイル>:<行> — <指摘>
  - 違反ルール: `auth.md` "PUBLIC_PATHS 3 点セット"
  - 提案: ...

### HIGH(merge 前修正推奨)
- ...

### MEDIUM(可能なら修正)
- ...

### LOW / 提案
- ...

### Critical Operational Lessons チェック
- [x] RLS 一元化 OK
- [ ] Cache Components ビルド検証 — **未確認、要 `npm run build`**
- ...

### 総評
<1-2 行>
```

### Phase 5: 反映オプション

ユーザー指示があれば:
- `gh pr review --request-changes -b "<上記サマリ>"` で review 提出
- 修正提案を inline コメントとして `mcp__github__pull_request_review_write` で送信
- 修正自体は **コードレビューだけが役割**。実装は別途 subagent 委譲

## サブエージェント並列起動

複数観点を並列で評価する場合(推奨):

```
Agent 1 (subagent_type=code-reviewer, グローバル) — 一般品質
Agent 2 (subagent_type=security-reviewer, グローバル) — 認証/権限変更時
Agent 3 (subagent_type=typescript-reviewer, グローバル) — TS 意味論
Agent 4 (subagent_type=database-reviewer, グローバル) — migration 含む場合
```

メインは 4 つの結果を集約して上記フォーマットで出力。

## 制約

- **コード修正は行わない**(指摘までが役割)
- 推測で書かない(diff から読める事実だけを根拠にする)
- 既存の review コメントと**重複**しない(Phase 1 で取得して exclude)
- CRITICAL は `.claude/rules/` 違反 or Critical Operational Lessons 違反のみに限定

## 関連

- 既存ルール: [`.claude/rules/`](../rules/)
- 教訓: [CLAUDE.md](../../CLAUDE.md) の Critical Operational Lessons セクション
- GitHub MCP: `mcp__github__pull_request_read` `mcp__github__pull_request_review_write`
