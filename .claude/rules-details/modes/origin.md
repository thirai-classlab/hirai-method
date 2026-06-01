> Layer A: [`modes.md`](../../rules/modes.md) §(history 全体) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 (history 全体) (Layer B)

本 file は modes.md の歴史全体を記録する。各 task の commit hash / 採用判断は git log + 採用プロジェクト側 `docs/tasks/<task-N>.md` を参照。

## 変更履歴

- **Loop モード規範化**: 2026-05-12 task-21 W0.1 で遵守事項 1-8 を策定 (subagent 並走中の停止事案を機械防止化)
- **遵守事項 2 例外条項**: 2026-05-23 task-21 W2.1 で「設計→承認→タスク追加フロー」との相反を解消 (recall_poc/docs/01-03 事案起源)
- **task #9 (2026-05-13)**: mode-switch bypass log 追加、Normal モードで禁止パターン実行を audit trail として記録
- **task #39 (2026-05-25)**: feature branch push + gh pr create 自律実行可へ緩和、main/stg* は別 layer 委譲
- **task-40 (2026-05-26)**: 規範変更 (`.claude/rules/*.md` 等) draft skip 事案の再発防止 → 2026-05-28 緩和で機械強制 BLOCK 撤廃、honor system に降格
- **task-41 (2026-05-26)**: 層 6 (loop-confirmation-detector.sh) 追加、確認質問発話の自律是正
- **task #47 (2026-05-27)**: 遵守事項 9 (list.md 全 task 連続自律実行) 新設
- **task-48 (2026-05-27)**: PR #22 で feature branch push + gh pr create の自律実行を再実証 (memory `claude_permission_git_push_deny.md` 更新)
- **task-51 Step 3 (2026-05-28)**: Layer A/B 2 層分割
