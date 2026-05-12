---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #4: CLAUDE.md Critical Operational Lessons に教訓 2 件転載

> Status: **🔲 未着手**
> 起案: 2026-05-12
> 関連: 本セッション feedback memory 2 件
> 設計起源: [critical-lessons-transfer.md](../draft/critical-lessons-transfer.md)

## 背景・目的

memory `~/.claude/projects/.../memory/feedback_*.md` (2 件) に保存済の教訓は **session 自動ロードされず** に recall 経路が memory 検索依存。HIGH 重要度の教訓 SSoT は `CLAUDE.md` `Critical Operational Lessons` テーブル (session 起動時必読)。

## 仕様

`docs/draft/critical-lessons-transfer.md` §3 採用案 A (CLAUDE.md 直記、HIGH 重要度 2 行追加) に準拠。

転載 2 教訓:
1. **並列 subagent の git operation 競合**: `git add <specific files>` 限定 / `git reset` 禁止 / worktree 隔離を subagent prompt に明記する (HIGH)
2. **source される lib に `set -euo pipefail` を書かない**: file-top strict mode が caller に leak、subshell 関数化で局所化する (HIGH)

## Wave 構成

| Wave | 内容 | 工数 | 依存 |
|:---:|:---|---:|:---|
| W1 | CLAUDE.md `Critical Operational Lessons` テーブルに教訓 1 を HIGH 行追加 | 0.1h | — |
| W2 | 同テーブルに教訓 2 を HIGH 行追加 | 0.1h | W1 |
| W3 | commit + push | 0.1h | W2 |

合計工数: 0.3 h

## 完了条件

- [ ] CLAUDE.md `Critical Operational Lessons` テーブルに 2 行追加 (HIGH 重要度)
- [ ] commit + push 完了
- [ ] memory `feedback_*.md` 2 件は履歴として保持 (削除しない)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `CLAUDE.md` 1 ファイル、2 行追加 |
| migration | なし |
| 環境変数 | なし |
| 互換性 | テンプレート使用先で「教訓は実体験から書き起こす」原則あり (本リポ自身の実体験なので OK) |

## 関連

- Draft: [critical-lessons-transfer.md](../draft/critical-lessons-transfer.md)
- 派生元: [next-actions.md](next-actions.md) entry #3
- Memory: `~/.claude/projects/-Users-t-hirai-work-hirai-method/memory/feedback_parallel_subagent_git_conflict.md` + `feedback_set_e_in_sourced_libs.md`
