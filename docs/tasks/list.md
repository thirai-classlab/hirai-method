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
| 2 | ✅ | byproduct-discharge | PR 作成 (feat/loop-mode → main) 完了 (2026-05-12): PR #3 (state=OPEN, mergeable=MERGEABLE) として task #6+#7+#8 統合済 +17 commits push (`ea597e1..1037e7d`)、URL: https://github.com/thirai-classlab/hirai-method/pull/3、user 明示承認下で mode.yml 一時 normal 切替で autonomous-action-guard bypass、push 完了後 loop 復帰 | — | [task-2-create-pr-feat-loop-mode.md](task-2-create-pr-feat-loop-mode.md) |
| 3 | ✅ | byproduct-discharge | context-budget hook 実発火検証: CB-verify (`5846925`) の運用効果実証 (本セッション 2026-05-12 で **60% tier 発火を観測**、611K/1000K tokens、mode-loader.sh pipefail leak 修正の実証完了) | — | [task-3-context-budget-hook-verification.md](task-3-context-budget-hook-verification.md) |
| 4 | ✅ | byproduct-discharge | CLAUDE.md Critical Operational Lessons に教訓 2 件転載: 並列 subagent git 競合 / set -e leak (完了 @ 2026-05-12) | — | [task-4-critical-lessons-transfer.md](task-4-critical-lessons-transfer.md) |
| 5 | ✅ | byproduct-discharge | 副産物 discharge 機構の本格実装: W1 hook surface + W2 template 派生セクション + W3 Stop guard + W4 `/discharge-byproduct` + W5 workflow.md セクション + W6 smoke 9/9 PASS (完了 @ 2026-05-12、commits `2789457` `9013404` `c88f974` `6ec3286`) | — | [task-5-byproduct-discharge-mechanism.md](task-5-byproduct-discharge-mechanism.md) |
| 6 | ✅ | loop-auto-progress | Loop モード自律進行強制 + 自律実行禁止リスト: W1-W6 全完了 (W5 smoke **9/9 PASS** + vercel regex re-verify 3/3 PASS)、PR #3 として merge 待ち @ 2026-05-12 | #1, #5 | [task-6-loop-auto-progress-enforcement.md](task-6-loop-auto-progress-enforcement.md) |
| 7 | ✅ | custom-pm-commands | Custom PM / Session Commands 完了 (2026-05-12): W1 `77124a9` (3 markdown command 新設) + W2 `1010b53` (mode-session-start.sh resume prompt 注入) + W3 verified (3 command 全て onboarding check 既存実装、`.mcp.json` required marker は Claude Code 仕様非サポート → command-level enforcement で代替) + W4 `f063ff3` (3 files /sc:* → 自前 command 1:1 置換) + W5 `b8c626e` + follow-up `1d63aff` (smoke 6/6 PASS) + W6 `c6fba4b` (CLAUDE.md commands table + workflow.md Session 永続化セクション + next-actions entry #7)、push 待ち @ 2026-05-12 | #6 | [task-7-custom-pm-commands.md](task-7-custom-pm-commands.md) |
| 8 | ✅ | delegation-guard-fix | delegation-guard.sh heredoc segment splitter 修正 完了 (2026-05-12): W1+W3 `df587b0` (関数化 + smoke scaffold、TDD RED 3/6) + W2 `8aaa76a` (quote-aware regex、smoke 6/6 PASS) + W4 `86ba4da` (development-process.md 文書反映)、既存 smoke 4 件 regression 0 (workflow-guard 8/8 / next-actions 9/9 / loop-auto-progress 9/9 / custom-pm 6/6)、push 待ち | #6, #7 | [task-8-delegation-guard-heredoc-fix.md](task-8-delegation-guard-heredoc-fix.md) |
| 9 | ✅ | harness-audit-followups | /harness-audit 観察候補の改修 完了 (2026-05-13): W1 `bb38bc9` (F3 agent_type allowlist + sidechain fail-open) + W2 `a306bdc` (autonomous-action-guard Normal 分岐 log_bypass 条件付き呼出) + W3 `a43a0ba` (audit-followups smoke 4/4 PASS) + W4 `f45085d` (development-process.md + modes.md 反映)、既存 smoke regression 0 (workflow-guard 8/8 / next-actions 9/9 / loop-auto-progress 9/9 / delegation-guard-segment 6/6、custom-pm-commands case-5 は本 task 範囲外の pre-existing) | #6, #8 | [task-9-harness-audit-followups.md](task-9-harness-audit-followups.md) |
| 10 | ✅ | sc-removal-serena-warning | `/sc:*` 排除 + Serena MCP 不在警告 完了 (2026-05-13、並列 subagent 同時完了): W1 `55db628` (CLAUDE.md L18 + dev-process L32+L57+L59 + start-task L72 の `/sc:test`/`/sc:build` → 自前 agent/skill 呼出、Python ワンライナー fallback) + W2 `96eb892` (`.claude/hooks/check-serena-mcp.sh` 新規 SessionStart hook + `.claude/settings.json` 配線 + smoke 4/4 PASS)、既存 smoke 5 件 regression 0 (Case 5 pre-existing)、file 完全分離で commit race 回避、両者 confidence 0.92 | #7, #9 | (draft 履歴: `docs/draft/` 未作成、hot-fix `--no-draft` style refactoring quality improvement) |
| 11 | ✅ | session-help-surface | SessionStart help/hint 表示 hook 新規 完了 (2026-05-13): commit `652098d` で `.claude/hooks/session-help-surface.sh` 新規 (9 カテゴリ slash commands + onboarding hint、`HC_SESSION_HELP_ENABLED=false` で OFF / `HC_SESSION_HELP_VERBOSE=true` で詳細版) + `.claude/settings.json` SessionStart index 7 配線 + smoke 4/4 PASS、既存 smoke 7 件 regression 0、subagent confidence 0.92 | #10 | (hot-fix `--no-draft` style、user ask「Hint や help コマンドについてもセッション開始時に記載」起源) |
| 12 | ✅ | dual-mode-portability | hook 物理位置と PROJECT_ROOT 分離 + 4 hooks (PROJECT_ROOT 実利用箇所のみ、surgical) 統一更新 + settings.json 2 テンプレート + smoke/docs で user-level / project-level 両対応 完了 (2026-05-13、5 commits: W0 `4c2fc07` 承認反映 / W1 `4ddf115` lib/project-root.sh / W2 `eb9925b` 4 hooks 統一 / W3 `4dbf9c9` user-level template / W4 `93100a8` smoke+docs)、新規 smoke 4/4 PASS、既存 smoke 8/9 PASS (Case 5 pre-existing と無関係)、subagent confidence 0.85、W2 surgical 4/11 判断は次 task 副産物として next-actions に記録 | #7, #10, #11 | [task-12-dual-mode-portability.md](task-12-dual-mode-portability.md) |

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
