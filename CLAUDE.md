# CLAUDE.md

> **これは汎用ハーネス用 CLAUDE.md テンプレート**（hirai-method）
> プロジェクト固有情報は `<...>` で置換してください。

## Overview

`<プロジェクト名>` — `<1〜2 行でプロジェクトの役割を説明>`。

**本番**: `<URL>` ／ **Repo 役割**: `<このリポは何の責務を持つか / 別リポとの分担>`

## User Context

`<運用者の役割・チームコンテキスト・ドメイン用語の補足を 1〜2 行>`

## Development Policy

- **TDD**: テスト先行（テスト専門エージェント `tdd-guide` / `test-automator` / `qa-expert` で観点出し → Red → Green → Refactor）
- **サブエージェント委譲（Hook 強制 + 背景起動 + 順序整合性 + Task 登録 + Bash deny 反射）**:
  - メインは `src/` `tests/` `scripts/` の Read/Write/Edit/Bash 禁止 → すべて Agent tool 経由
  - **Agent tool は `run_in_background: true` 必須**（メインを user 対話に常時開放）
  - **タスク順序整合性はメインが保証**（依存解決 / 並行判定 / commit conflict 防止）
  - **サブエージェント起動時は必ず TaskCreate**（subagent_id を metadata に記録、Claude Code 内蔵タスクリストに表示）
  - **Bash deny / whitelist 不在 / 委譲ガード block は loop 停止理由にしない**(自動的に Agent 委譲で再試行 — `development-process.md` §5)
  - 詳細は [`.claude/rules/development-process.md`](.claude/rules/development-process.md)
- **指摘対応**: 根本原因 → 修正 → 再発防止策を `.claude/rules/` に追加提案
- **タスク管理（メイン専任）**: `docs/tasks/list.md` で一元管理、サブエージェントに委譲しない
- **設計→承認→タスク追加**: `docs/draft/` 起案 → user 承認 → `docs/tasks/` 反映。設計なしのタスク追加禁止

## Autonomous Progression（自律進行ルール）

user から **タスクと方針の承認**を得た後は、実装・commit・push・本番デプロイ・migration 適用まで自律的に進める。Wave / commit ごとに進行可否を逐一問わない。

### 自律実行可（user 確認不要）
- 承認済み設計書（`docs/tasks/task-N-*.md` or `docs/draft/` 承認済み）に基づく実装
- テスト追加・修正、`git commit`、`git push origin <承認済みブランチ>`（main 含む）
- `<追加のみ・破壊的変更なしの DB migration 等、プロジェクト固有の自律実行範囲>`
- サブエージェント委譲、ローカルサーバー起動、`docs/tasks/list.md` ステータス同期

### chat で必ず確認（クリティカル）
- 承認外の設計変更、破壊的 DB 変更（DROP / 既存 RLS 削除）、データ削除
- secrets ローテーション、`git push --force` / `git reset --hard` / `git branch -D`
- main 以外への push、`<外部サービス quota 超過見込み>`
- 同一エラーで 3 回連続失敗、サブエージェントの「要判断」報告
- security-reviewer の CRITICAL、進行不可ブロッカー

### user 主導切替キーワード
「確認しながら」「逐次」「1 つずつ」「止まって」「ブランチ切って」「PR 経由で」

### 報告フォーマット
- Wave 完了時: `Wave N 完了。commit <hash>、<total> tests PASS。次は Wave N+1。`
- 全完了時: `#<番号> <名称> 完了。累計 +<tests>、commit <count>、push 済 <URL>。`

## Rules（`.claude/rules/`）

`paths:` フロントマターで対象ファイルをスコープ指定し、該当ファイルを読んだ時のみ自動ロードされる。

| ルールファイル | スコープ | 内容 |
|--------------|---------|------|
| [`development-process.md`](.claude/rules/development-process.md) | `src/**`, `scripts/**`, `tests/**`, `docs/tasks/**`, `docs/draft/**` | TDD、委譲、指摘対応、タスク管理、設計→承認フロー |
| [`self-improvement.md`](.claude/rules/self-improvement.md) | (常時参照) | L1〜L5 自己改善 + F1/F2 事実検証の使い分け規約 |
| [`workflow.md`](.claude/rules/workflow.md) | `docs/draft/**`, `docs/tasks/**`, `.claude/commands/**`, `.claude/hooks/workflow-guard.sh`, `.claude/.workflow-state/**` | workflow 強制 (test-design / design-review / module-review / system-review / new-feature / modify-feature / workflow-guard) |
| `<追加ルール 1>` | `<対象 path>` | `<内容>` |
| `<追加ルール 2>` | `<対象 path>` | `<内容>` |

ルール追加・変更時は必ずこのテーブルも更新。

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

### ハーネス組み込みスラッシュコマンド

| カテゴリ | コマンド |
|---|---|
| タスク | `/init-tasks` `/new-draft` `/new-task` `/start-task` `/finish-task` `/task-bypass` |
| Custom PM / Session | `/save-state` `/resume-state` `/pm-start` |
| Git / レビュー | `/commit` `/reviewpr` |
| 自己改善 L1 (Eval) | `/eval` |
| 自己改善 L2 (GAN) | `/gan-design` `/gan-build` |
| 自己改善 L4 (Learning) | `/instinct-status` `/projects` `/learn` `/evolve` `/promote` `/instinct-export` `/instinct-import` |
| 自己改善 L5 (Introspect) | `/agent-introspect` |
| 事実検証 F1 (GateGuard) | `/gate-status` `/gate-clear` `/gate-bypass` |
| 事実検証 F2 (Verify) | `/verify` |
| Workflow 強制 (W1-W4) | `/test-design` `/design-review` `/module-review` `/system-review` `/new-feature` `/modify-feature` |
| 監査 | `/harness-audit` |

詳細: [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md)

## Design Constraints

- `<例: 内製パイプライン HTML のみ（globals.css の .rich-body）>`
- `<例: モノトーン厳守、Tailwind v4 dark: プレフィックス全面禁止>`
- `<例: Cache Components 制約 — export const dynamic/runtime/revalidate 禁止>`
- `<その他、リポ固有の不変制約>`

## Critical Operational Lessons（`<重要操作>`前に必読）

| 教訓 | 重要度 |
|:---|:---:|
| **並列 subagent に同一 branch で `git commit` させる際は `git add <specific files>` 限定 + `git reset` 禁止を prompt 必須記載**。`git reset --soft HEAD^` がメイン / 他 subagent の commit を巻き添えで orphan 化する事故 (2026-05-12, `2bbe079` 混在 → `deda280` orphan → `52a170f` 再 commit で復旧)。完全分離が必要なら `isolation: "worktree"` で worktree 隔離 | HIGH |
| **`.claude/hooks/lib/*.sh` の file-top に `set -euo pipefail` を書かない**。caller の shell flags に leak し、`cmd \| head -1` で SIGPIPE → pipefail → errexit → **exit 141 サイレント終了**。`load_xxx() ( set -uo pipefail; ... )` のように subshell 関数化で局所化する (2026-05-12 CB-verify, `5846925` で根本修正、context-budget hook の未発火問題が解消) | HIGH |
| **Loop モード稼働中、subagent 起動後にメインが `completion 通知の受動待ち` で停止しない**。`run_in_background: true` 必須 + 待ち中は別 task / メイン専任作業 / 規範文書化 / memory 整理 を並行進行する。違反例: subagent #13-#15 起動後にメインがターン区切り報告で停止 → user 「Loop モード継続中。なぜ自動で実行を続けないのか?」を **複数回**指摘 (2026-05-12)。`.claude/hooks/loop-auto-progress-reminder.sh` (UserPromptSubmit) が「待ち中報告」キーワード検出で `<system-reminder>` 強制注入、`modes.md` 遵守事項 7 で機械防止化 | HIGH |
| **Loop モードの「中間確認禁止」を盾に `git push` / `gh pr create` / production deploy 等の破壊的操作を自律実行しない**。準備 (draft / 設計 / 実装 / ローカル commit) のみ自律、撤回不可な操作は user 明示承認必須。違反例: 2026-05-12 セッション中、`git push origin feat/loop-mode` を **5 回以上**自律実行。`.claude/hooks/autonomous-action-guard.sh` (PreToolUse Bash) が 11 カテゴリ (push / PR / release / 本番 deploy / DB push / k8s apply / terraform apply 等) を `{"decision":"block"}` で機械防止化、bypass: `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` + bypass.log 記録、`modes.md` 遵守事項 8 | HIGH |
| `<例: 公開/非公開フィルタは RLS で一元化、queries.ts に .not() 禁止>` | HIGH |
| `<例: vitest は build 制約違反を検出不可、push 前に build 必須>` | HIGH |
| `<例: 独自 secret 認証 API は middleware PUBLIC_PATHS にも追加（3 点セット）>` | HIGH |

その他の教訓は memory `feedback_*.md` を参照。

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
3. プロジェクト固有のルールを `.claude/rules/` に追加し、Rules テーブルを更新
4. Critical Operational Lessons は **実際の事故から書き起こす**（推測で書かない）
5. リポ運用で得た教訓は `~/.claude/memory/feedback_*.md` に蓄積し、本書には頻出のものだけ転載

## ハーネスドキュメント

- [`README.md`](README.md) — 概要 + 採用 5 ステップ
- [`docs/INVENTORY.md`](docs/INVENTORY.md) — 全構成要素の Path 表
- [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md) — L1〜L5 + F1/F2 + 監査の詳細
