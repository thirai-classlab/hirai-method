# CLAUDE.md

> **本 file は `install.sh` が manifest 検出 (lang=ts) 後に auto-fill 生成した starter です。**
> `TODO(auto-fill)` 記法の HTML コメントが付いた field は manifest から抽出不能だったので手動で埋めてください。
>
> **共通規範**: 本 file は `@.claude/CommonRules.md` を必ず参照 (Claude Code が session 開始時に自動展開)。
> Development Policy / Autonomous Progression / Rules / Design Constraints / Critical Operational Lessons / ハーネス組み込みスラッシュコマンドは CommonRules.md で集中管理。

@.claude/CommonRules.md

## Overview

`{{PROJECT_NAME}}` — <!-- TODO(auto-fill): 1〜2 行でプロジェクトの役割を説明 -->

**本番**: <!-- TODO(auto-fill): URL --> ／ **Repo 役割**: <!-- TODO(auto-fill): このリポは何の責務を持つか / 別リポとの分担 -->

## User Context

<!-- TODO(auto-fill): 運用者の役割・チームコンテキスト・ドメイン用語の補足を 1〜2 行 -->

## Tech Stack

- **Language / Framework**: TypeScript{{FRAMEWORK_LINE}}
- **Runtime**: {{RUNTIME_LINE}}
- **Package Manager**: <!-- TODO(auto-fill): 例 npm / pnpm / yarn / bun -->
- **DB**: <!-- TODO(auto-fill): 例 PostgreSQL on Supabase / MySQL / SQLite -->
- **Auth**: <!-- TODO(auto-fill): 例 NextAuth v5 / Auth0 / Clerk -->
- **Hosting**: <!-- TODO(auto-fill): 例 Vercel / Cloudflare Pages / AWS -->
- **AI / 外部 API**: <!-- TODO(auto-fill): 例 Vercel AI Gateway, OpenAI -->

## Architecture / Data

<!-- TODO(auto-fill): レイアウト / 公開フロー / docs リンク (例: docs/database-design.md, docs/architecture-roles.md) -->

## Implementation Status

<!-- TODO(auto-fill): Phase N 完了 / Phase N+1 進行中。直近テスト件数。詳細は docs/tasks/list.md -->

## Commands

```bash
{{COMMANDS_BLOCK}}
```

> ハーネス組み込みスラッシュコマンド (`/init-tasks` / `/save-state` / `/eval` / `/verify` / 他) は `@.claude/CommonRules.md` を参照。

## Related Repositories

<!-- TODO(auto-fill): 関連リポ・別リポ責務分担 (例: 投稿エージェントリポ / Edge Function リポ) -->

## Domain Knowledge

<!-- TODO(auto-fill): プロジェクトの事業コンテキスト memo は ~/.claude/memory/ に置く -->
