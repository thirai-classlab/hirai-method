# CLAUDE.md

> **本 file は `install.sh` が manifest 検出 (lang=swift) 後に auto-fill 生成した starter です。**
> `TODO(auto-fill)` 記法の HTML コメントが付いた field は manifest から抽出不能だったので手動で埋めてください。
>
> **共通規範**: 本 file は `@.claude/CommonRules.md` を必ず参照 (Claude Code が session 開始時に自動展開)。
> Development Policy / Autonomous Progression / Rules / Design Constraints / Critical Operational Lessons / ハーネス組み込みスラッシュコマンドは CommonRules.md で集中管理。

@.claude/CommonRules.md

## Overview

`{{PROJECT_NAME}}` — <!-- TODO(auto-fill): 1〜2 行でプロジェクトの役割を説明 -->

**本番**: <!-- TODO(auto-fill): URL / App Store link --> ／ **Repo 役割**: <!-- TODO(auto-fill): このリポは何の責務を持つか / 別リポとの分担 -->

## User Context

<!-- TODO(auto-fill): 運用者の役割・チームコンテキスト・ドメイン用語の補足を 1〜2 行 -->

## Tech Stack

- **Language / Framework**: Swift{{FRAMEWORK_LINE}}
- **Runtime / Swift tools**: {{RUNTIME_LINE}}
- **Build Tool**: Swift Package Manager (SwiftPM)
- **Platform**: <!-- TODO(auto-fill): 例 iOS 17+ / macOS 14+ / server-side Swift -->
- **DB**: <!-- TODO(auto-fill): 例 CoreData / GRDB / PostgreSQL (Vapor 経由) -->
- **Hosting / Distribution**: <!-- TODO(auto-fill): 例 App Store / TestFlight / AWS -->
- **AI / 外部 API**: <!-- TODO(auto-fill): 例 OpenAI, Firebase -->

## Architecture / Data

<!-- TODO(auto-fill): レイアウト / target 構成 / docs リンク (例: docs/architecture.md) -->

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
