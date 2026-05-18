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
| 13 | ✅ | byproduct-discharge | Subagent `.claude/` 配下 permission denied 回避 staging 戦略の規範化 完了 (2026-05-13、3 commits: W0 `3423e40` task #13 spawn / W1+W2 `9473657` development-process.md に新セクション「サブエージェント `.claude/` 編集の staging 戦略 (必須)」+ 5 sub-sections (強制プロンプト雛型 / 検出パターン / 例外 / 起源 / 再発時 B/C 昇格判定)、§起源 Serena memory link で W2 §関連 merge 充足 / W3 `4a6f007` next-actions entry #12 ✅ sync)、DoD 全項目実証、subagent confidence W0 0.95 + W1+W2/W3 0.97、起源は task #12 staging 発見 (next-actions entry #12 🟡 推奨処理 (a)) | #12 | [task-13-subagent-claude-permission-staging-doc.md](task-13-subagent-claude-permission-staging-doc.md) |
| 14 | ✅ | byproduct-discharge | Custom-PM Case 5 follow-up: `/sc:` 残存解消 完了 (2026-05-14、5 commits: W0 `f3f64ba` task spawn + draft 承認反映 / W1 `9b1545e` smoke allowlist +3 path 暫定拡張 (subagent confidence 0.95) / W2 `90fdebb` next-actions entry #9 履歴化 + `/sc:` literal 除去 (Grep verify 0 matches, catch-22 解消) / W3 `bdbcbb0` allowlist 整理 (-1 path) + 全 smoke 42/42 PASS (custom-pm 6/6 + workflow-guard 8/8 + next-actions-hooks 9/9 + loop-auto-progress 9/9 + delegation-guard-segment 6/6 + audit-followups 4/4、regression 0) (subagent confidence 0.97) / sync (本 commit))、案 C ハイブリッドで catch-22 解消 + audit trail 維持 + smoke regression 0 を構造的に達成、Critical Operational Lessons + Loop 自律実行禁止リスト 全項目 0 違反 | #7, #10 | [task-14-custom-pm-case-5-followup.md](task-14-custom-pm-case-5-followup.md) |
| 15 | ✅ | claude-portability | C #7 `.claude/` 汎用化リファクタ完遂 (2026-05-18、subagent ade48ed39cbd44b5e confidence 0.97): `.claude/rules/workflow.md` 内 `docs/draft/` 直リンク 2 箇所 (line 265 byproduct-discharge §関連 artifact / line 360 §関連ルール) を「採用プロジェクト側 `docs/draft/` を参照」表記に統一 (commit `20f4eb6`)、4 sections 全揃で `.claude/` 単独 portable 完成。next-actions entry #7 起源、user 自己 handle 撤回 → claude 着手 | — | (hot-fix `--no-draft` style、next-actions entry #7 起源) |
| 16 | ✅ | project-root | C #11 CLAUDE_PROJECT_DIR fallback chain 完遂 (2026-05-18、subagent ade48ed39cbd44b5e confidence 0.97): `.claude/hooks/lib/project-root.sh` の `resolve_project_root()` に CLAUDE_PROJECT_DIR check を 3 段目挿入 (commit `4a35511`)、新 4 段 chain (HC_PROJECT_ROOT → git rev-parse → CLAUDE_PROJECT_DIR → pwd) 完成、`project-root-smoke.sh` 新規 5 cases PASS、`dual-mode-portability-smoke.sh` 4 cases regression 0 | — | (hot-fix `--no-draft` style、next-actions entry #11 起源) |
| 17 | ✅ | bash-whitelist-git | Main agent 用 git 非破壊実行許可 + destructive deny layer 追加完遂 (2026-05-18、user 直接指示): `.claude/bash-whitelist.txt` の git regex を `^git( \|$)` に簡素化 (全 subcommand と global option -C 等を許可) + `.claude/hooks/delegation-guard.sh` Bash branch に常時 git destructive deny layer 10 patterns (push --force / push -f / reset --hard / branch -D / clean -f / checkout -- / restore --worktree\|--source / stash drop\|clear / tag -d\|-f / reflog expire / gc --prune=now) 追加 (commit `b7eea6e`)、bypass `ECC_ALLOW_DESTRUCTIVE_GIT=1`、`git status` 動作確認済、destructive 単体 smoke は next-actions entry #13 で別 task | — | (hot-fix `--no-draft` style、user 指示 2026-05-18「mainAgentでgitコマンドは基本的(破壊的変更以外)に実行できるようにしてください」起源) |
| 18 | ✅ | protected-branch-push | main / stg を含む branch への push deny layer 追加完遂 (2026-05-18、user 直接指示): `.claude/hooks/delegation-guard.sh` Bash branch に protected branch push deny layer 追加 (commit `ad2f7bc`、+90/-5)、明示 refspec (origin main / origin stg-v1 / HEAD:main / feat:refs/heads/stg) + refspec 省略 (current branch fallback via git rev-parse) 2 段 check、`git push origin main` で `[protected branch push deny]` reason 返却を実測確認、bypass `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1`、`bash-whitelist.txt` コメント block も 2 layer (destructive + protected branch) 言及で更新、単体 smoke は next-actions entry #14 で別 task | #17 | (hot-fix `--no-draft` style、user 指示 2026-05-18「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」起源) |
| 19 | ✅ | smoke-coverage | git destructive deny smoke 完遂 + hook regex bug fix (2026-05-18、user 指示「next-actions #13 完了していれば push」起源): `.claude/tests/git-destructive-deny-smoke.sh` 新規 (206 行、19 block + 10 pass + 3 bypass = 32/32 PASS) + `.claude/hooks/delegation-guard.sh` の `-f` regex bug fix (旧 `[[:space:]]-f` が effectively 2-space 必要で `git push -f` single space を取りこぼし、新 `([^|;&]*[[:space:]])?-f` で intervening segment optional 化)、bug 発見 → fix → smoke 統合を 1 commit (`9eacc3c`、+212/-1) に集約、既存 segment smoke 6/6 PASS regression 0、subagent 2 段 (acf4733319eb2deea v1 confidence 0.92 + a3d41d744ebbbc1a2 v2 confidence 0.97) | #17 | (hot-fix `--no-draft` style、next-actions entry #13 起源、user 指示時 hook bug が smoke から逆発見) |

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
