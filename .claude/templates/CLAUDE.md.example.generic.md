# CLAUDE.md

> **本 file は `install.sh` が manifest 検出に失敗 (lang=generic) したため generic starter を配置した状態です。**
> `TODO(auto-fill)` 記法の HTML コメントが付いた field は自動抽出できなかったので手動で埋めてください。
> project 実態に合った言語別 template で再生成したい場合は `install.sh --lang=<ts|py|go|rust|php|swift>` を指定してください。
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

- **Language / Framework**: <!-- TODO(auto-fill): 主要言語 / framework -->{{FRAMEWORK_LINE}}
- **Runtime**: {{RUNTIME_LINE}}
- **Build Tool**: <!-- TODO(auto-fill): 例 make / bazel / justfile / scripts/build.sh -->
- **DB**: <!-- TODO(auto-fill): 例 PostgreSQL / MySQL / SQLite / 該当なし -->
- **Auth**: <!-- TODO(auto-fill): 例 OAuth / API key / 該当なし -->
- **Hosting**: <!-- TODO(auto-fill): 例 AWS / GCP / bare metal -->
- **AI / 外部 API**: <!-- TODO(auto-fill): 例 OpenAI, Anthropic -->

## Architecture / Data

<!-- TODO(auto-fill): レイアウト / 主要フロー / docs リンク -->

## Implementation Status

<!-- TODO(auto-fill): Phase N 完了 / Phase N+1 進行中。直近テスト件数。詳細は docs/tasks/list.md -->

## Commands

```bash
{{COMMANDS_BLOCK}}
```

> ハーネス組み込みスラッシュコマンド (`/init-tasks` / `/save-state` / `/eval` / `/verify` / 他) は `@.claude/CommonRules.md` を参照。

## Related Repositories

<!-- TODO(auto-fill): 関連リポ・別リポ責務分担 -->

## Domain Knowledge

<!-- TODO(auto-fill): プロジェクトの事業コンテキスト memo は ~/.claude/memory/ に置く -->
