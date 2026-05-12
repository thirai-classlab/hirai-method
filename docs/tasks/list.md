# タスク一覧

> セッション開始時にこのファイルを読み込み、タスクの状態を復元すること。
> タスクの追加・削除・ステータス変更時は必ずこのファイルも更新すること。
>
> **保留・今後検討タスク**は [`parking-lot.md`](parking-lot.md) で管理。
> **設計（未承認）**は [`../draft/`](../draft/) で管理し、承認後にここへ追加。
> **副産物 / 派生 task 候補**（informal な TODO / 次アクション）は [`next-actions.md`](next-actions.md) で管理。設計起こし or parking-lot 移行 or 無視 の判断前段。

## 凡例

| アイコン | ステータス |
|:---:|:---|
| ✅ | 完了 |
| 🔄 | 進行中 |
| 🔲 | 未着手 |
| ⏸️ | 保留 |
| 📝 | 設計（未承認） |

## タスク

| # | ステータス | Phase | 概要 | 依存 | 詳細 |
|:---:|:---:|:---|:---|:---|:---|
| 1 | ✅ | workflow-enforcement | W1-W5 umbrella: 設計レビュー fan-out / テスト設計 MECE / workflow 強制 / リファクタリング強制 (W1-W5 全完了 @ 2026-05-12、W4 smoke 8/8 PASS @ commit `555b0ee`、W5 @ commit `b8084c8`+`0ff9654`、W6 は `asana off` により out-of-scope) | — | [task-1-workflow-enforcement.md](task-1-workflow-enforcement.md) |
| 2 | 🔲 | byproduct-discharge | PR 作成 (feat/loop-mode → main): 本セッション 19+ commits の merge 動線 (起案 2026-05-12) | — | [task-2-create-pr-feat-loop-mode.md](task-2-create-pr-feat-loop-mode.md) |
| 3 | ✅ | byproduct-discharge | context-budget hook 実発火検証: CB-verify (`5846925`) の運用効果実証 (本セッション 2026-05-12 で **60% tier 発火を観測**、611K/1000K tokens、mode-loader.sh pipefail leak 修正の実証完了) | — | [task-3-context-budget-hook-verification.md](task-3-context-budget-hook-verification.md) |
| 4 | ✅ | byproduct-discharge | CLAUDE.md Critical Operational Lessons に教訓 2 件転載: 並列 subagent git 競合 / set -e leak (完了 @ 2026-05-12) | — | [task-4-critical-lessons-transfer.md](task-4-critical-lessons-transfer.md) |
| 5 | ✅ | byproduct-discharge | 副産物 discharge 機構の本格実装: W1 hook surface + W2 template 派生セクション + W3 Stop guard + W4 `/discharge-byproduct` + W5 workflow.md セクション + W6 smoke 9/9 PASS (完了 @ 2026-05-12、commits `2789457` `9013404` `c88f974` `6ec3286`) | — | [task-5-byproduct-discharge-mechanism.md](task-5-byproduct-discharge-mechanism.md) |
| 6 | ✅ | loop-auto-progress | Loop モード自律進行強制 + 自律実行禁止リスト: W1-W6 全完了 (W5 smoke **9/9 PASS** + vercel regex re-verify 3/3 PASS)、PR #3 として merge 待ち @ 2026-05-12 | #1, #5 | [task-6-loop-auto-progress-enforcement.md](task-6-loop-auto-progress-enforcement.md) |
| 7 | ✅ | custom-pm-commands | Custom PM / Session Commands 完了 (2026-05-12): W1 `77124a9` (3 markdown command 新設) + W2 `1010b53` (mode-session-start.sh resume prompt 注入) + W3 verified (3 command 全て onboarding check 既存実装、`.mcp.json` required marker は Claude Code 仕様非サポート → command-level enforcement で代替) + W4 `f063ff3` (3 files /sc:* → 自前 command 1:1 置換) + W5 `b8c626e` + follow-up `1d63aff` (smoke 6/6 PASS) + W6 `c6fba4b` (CLAUDE.md commands table + workflow.md Session 永続化セクション + next-actions entry #7)、push 待ち @ 2026-05-12 | #6 | [task-7-custom-pm-commands.md](task-7-custom-pm-commands.md) |
| 8 | 🔲 | delegation-guard-fix | delegation-guard.sh heredoc segment splitter 修正: awk gsub regex の `\|` 単独文字置換が quoted/heredoc 内 `\|` も separator 誤認する bug。C ハイブリッド (関数化 + quote-aware regex + smoke 6 cases + 文書) で W1-W4 = 1.0h (起案 2026-05-12、user 承認済 2026-05-12) | #6, #7 | [task-8-delegation-guard-heredoc-fix.md](task-8-delegation-guard-heredoc-fix.md) |

<!--
記入ルール:
- # は連番。同フェーズ内で複数タスクなら "11.3a" のような sub-id 可
- ステータス変更時は完了日 + commit hash + 主要 metric を「概要」末尾に追記
  例: "（W1-W3 完了 @ 2026-04-29、commit `abc1234`、+15 tests=215 PASS）"
- 依存は "—"（なし）/ "#N" / "Phase N" 形式
- 詳細は個別ファイルへの相対リンク（無ければ "—"）
-->

## 依存関係図

```
<!-- 例:
Phase 1 → Phase 2 → Phase 3
                 → Phase 4
-->
```

## ステータス更新ルール

1. **新規追加**: 必ず `_TASK_TEMPLATE.md` から個別ファイルを起こすか、`docs/draft/` の承認済設計から移行する
2. **🔄 → ✅**: `/finish-task <id>` で完了 3 条件（build / test / docs 反映）を満たしてから更新
3. **🔄 → ⏸️**: 保留事由を [`parking-lot.md`](parking-lot.md) に転記し、ここの行は削除
4. **削除**: 不採用の場合も履歴として `parking-lot.md` の `❌` セクションに残す
