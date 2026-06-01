> Layer A: [`workflow.md`](../../rules/workflow.md) §Session 永続化と PM Orchestration | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# Session 永続化詳細 (Layer B)

自前 command 表 / memory key schema 全列挙 / Serena 必須化 / SessionStart 自動 resume の詳細。Layer A は要約のみ。

## 自前 command

| command | 役割 | 主要 Serena tool |
|---|---|---|
| [`/save-state`](../../commands/save-state.md) | session 状態を Serena memory に snapshot 保存 | `write_memory` |
| [`/resume-state`](../../commands/resume-state.md) | 前 session 状態を Serena memory から復元 | `list_memories` / `read_memory` |
| [`/pm-start`](../../commands/pm-start.md) | PM Agent orchestration + PDCA cycle 永続化 | 全 memory API |

## memory key schema (全列挙)

- `session/context` — 完全 snapshot (TaskList / commits / artifact / 次アクション)
- `session/last` — 1-2 段落要約
- `session/checkpoint` — 進捗 checkpoint
- `plan/<feature>/{hypothesis,architecture,rationale}` (PDCA Plan)
- `execution/<feature>/{do,errors,solutions}` (PDCA Do)
- `evaluation/<feature>/{check,metrics,lessons}` (PDCA Check)
- `learning/{patterns,solutions,mistakes}/<name>` (PDCA Act)
- `project/{context,architecture,conventions}` (project 全体理解)

## Serena 必須化の設計補足

- 各 command の Phase 1 で `mcp__serena__activate_project` を必須実行し、戻り値 error に `onboarding` / `not performed` を含む場合は onboarding 未済と判定して graceful error で `/onboarding` 案内 + 終了
- 旧版では `mcp__serena__check_onboarding_performed` を別 step で呼んでいたが、現 Serena MCP には該当 tool が存在しない (2026-05-23 確認、deferred tools list にも無し)
- `activate_project` の error response で onboarding 未済を検知する形に統合 (`resume-state.md` / `save-state.md` / `pm-start.md` の Phase 1 同期修正済)
- `.mcp.json` の `serena` entry は採用者側で個別登録 (Claude Code 標準には required marker 機構なし、command-level enforcement で代替)

## 関連 artifact (完全 list)

- [`.claude/commands/save-state.md`](../../commands/save-state.md)
- [`.claude/commands/resume-state.md`](../../commands/resume-state.md)
- [`.claude/commands/pm-start.md`](../../commands/pm-start.md)
- [`.claude/hooks/mode-session-start.sh`](../../hooks/mode-session-start.sh) (W2 拡張済)
- [`.claude/tests/custom-pm-commands-smoke.sh`](../../tests/custom-pm-commands-smoke.sh) (W5, 6/6 PASS)
- 設計起源は採用プロジェクト側 `docs/draft/` を参照 (`.claude/` 単独で portable)

## SessionStart 自動 resume の動作詳細

- `.serena/memories/session/context.md` 存在検知 → `<system-reminder>` で `/resume-state` 提案
- user 入力不要、メインが自動で `/resume-state` 実行 (Loop モード時) or user 承認待ち (Normal モード時)
- 復元対象: TaskList / 直近 commits / 進行中 artifact / 次アクション / context_used_ratio
