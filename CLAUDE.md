# CLAUDE.md

> **これは汎用ハーネス用 CLAUDE.md テンプレート**（hirai-method）
> プロジェクト固有情報は `<...>` で置換してください。
>
> **共通規範**: 本 file は `@.claude/CommonRules.md` を必ず参照 (Claude Code が session 開始時に自動展開)。
> Development Policy / Autonomous Progression / Rules / Design Constraints / Critical Operational Lessons / ハーネス組み込みスラッシュコマンドは CommonRules.md で集中管理。

@.claude/CommonRules.md

## Overview

`<プロジェクト名>` — `<1〜2 行でプロジェクトの役割を説明>`。

**本番**: `<URL>` ／ **Repo 役割**: `<このリポは何の責務を持つか / 別リポとの分担>`

## User Context

`<運用者の役割・チームコンテキスト・ドメイン用語の補足を 1〜2 行>`

## Tech Stack

- **Language / Framework**: `<例: TypeScript / Next.js 16 App Router>`
- **Runtime**: `<例: React 19, Node 22+>`
- **DB**: `<例: PostgreSQL on Supabase Tokyo（migrations は CLI 経由必須）>`
- **Auth**: `<例: NextAuth v5 + Google OAuth>`
- **Hosting**: `<例: Vercel (hnd1)>`
- **AI / 外部 API**: `<例: Vercel AI Gateway, OpenAI text-embedding-3-large>`
- **詳細**: `<docs/tech-stack.md 等のリンク>`

## Architecture / Data

- レイアウト: `<例: 1440px max / 800px content / light only>`
- 公開フロー: `<例: 投稿 → /preview → /api/publish → ISR revalidate>`
- 詳細: `<docs/database-design.md>` ／ `<docs/architecture-roles.md>` ／ `<docs/preview-publish-flow.md>`

## Implementation Status

`<例: Phase N 完了 / Phase N+1 進行中。直近: tests XXX PASS。詳細は docs/tasks/list.md>`

## Commands

```bash
# 開発・ビルド・テスト
<例: npm run dev / build / lint / test>

# DB
<例: supabase db push / db diff / migration list>

# 外部サービス CLI
<例: vercel logs --no-follow>
```

> ハーネス組み込みスラッシュコマンド (`/init-tasks` / `/save-state` / `/eval` / `/verify` / 他) は `@.claude/CommonRules.md` を参照。

## Related Repositories

- `<例: 投稿エージェントリポ — 別リポで content-post を担当>`
- `<例: Edge Function リポ — embed/relate/link 等を担当>`

## Domain Knowledge

`<プロジェクトの事業コンテキスト memo は ~/.claude/memory/ に置く>`:
- `<example>_context.md` — 事業構造・組織・技術スタック
- `<example>_status.md` — プロジェクト進捗

---

## このテンプレートの使い方

1. `<...>` プレースホルダを実際の値に置換
2. 不要セクションを削除（小規模リポでは Implementation Status / Related Repositories は省略可）
3. プロジェクト固有のルールを `.claude/rules/` に追加し、`@.claude/CommonRules.md` 内の Rules table も更新
4. Critical Operational Lessons は **実際の事故から書き起こす**（推測で書かない）。共通教訓は CommonRules.md、project 固有教訓は本 CLAUDE.md 末尾に追記
5. リポ運用で得た教訓は `~/.claude/memory/feedback_*.md` に蓄積し、頻出のものだけ CommonRules.md or CLAUDE.md に転載
