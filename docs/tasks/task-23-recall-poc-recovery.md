# Task #23: recall_poc Recovery — git init / CLAUDE.md 改訂 / draft フロー復旧 / list.md 初期化

> Status: **✅ 完了** (2026-05-27、W1-W5 全完了)
> 起案: 2026-05-23
> 関連: #21 (CLAUDE.md template 改訂と同根。**依存は task-21 W2.5 [template 改訂、完了済 `a9902c8`] に限定で実質解消**。task-21 残 W3 [42 sessions eval] は本 task と無関係)
> 設計起源: [recall-poc-recovery.md](../draft/recall-poc-recovery.md)

## 完了サマリ (2026-05-27)

- **W1** git init `875d2ea` (recall_poc 独立 project hash)
- **W2** CLAUDE.md Autonomous Progression 同期 (recall_poc/CLAUDE.md 再生成、task-21 W2.5 template 改訂と共通)
- **W3** 遡及 draft 12 件に approved frontmatter 追記
- **W4** recall_poc/docs/tasks/list.md 初期化 + 設計分解 — **recall_poc 側で 2026-05-26 完了済 (26 task / 180 Step、W4 想定 5-10 を大幅超過、self-progress で task-5 実装中)**。subagent afdbbd9cec515a37a が no-op 判断 (既存上書きは破壊的、confidence 0.88)
- **W5** `recall_poc/.claude/tests/recall-poc-recovery-smoke.sh` 新設 (cross-repo agent 着手 [task-42 superseded]、subagent a4f95e5457cf85356 confidence 0.97): 5/5 PASS (project_id 独立 / draft-flow-guard BLOCK+PASS / list.md 26 task)、recall_poc local commit `cfe879a` (push は user follow-up)

## user follow-up

- recall_poc local commit `cfe879a` (W5 smoke) の push (別 repo push 自律禁止)

## 背景・目的

2026-05-23 の recall_poc 調査で 4 件の運用課題が判明:
- git 未 init → observe.jsonl が hirai-method (9108e0c8f946) に混入
- CLAUDE.md (AI 自動生成) が template の draft フローを独自構造に置換 → docs/01-03 が docs/ 直下直接 Write
- 遡及 draft の frontmatter 不在
- list.md template のまま、設計 01-03 が task 化されていない

本 task で構造復旧 + 規範整合化を行う。

## 仕様 (要決定 → 決定済)

### Q1: docs/01-03 の扱い

→ **C ハイブリッド**: docs/ 直下に「承認済み設計書」として残し、遡及 draft (docs/draft/) を「設計起源 + 承認履歴」として整備。既存 file path 維持 + 規範整合の両立。

### Q2: CLAUDE.md template 改訂は本 task に含めるか

→ **task #21 (W2.5) と本 task の W2 で共通実装**。template 改訂は task #21 で、recall_poc/CLAUDE.md 再生成は本 task で対応。

## 設計

詳細は [recall-poc-recovery.md](../draft/recall-poc-recovery.md) §3 参照。

### Wave 構成

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W1 | recall_poc git init + 初回 commit | 0.1 |
| W2 | CLAUDE.md template 改訂 (task #21 と共通) + recall_poc/CLAUDE.md 再生成 | 0.4 |
| W3 | 遡及 draft 3 件に frontmatter 追記 | 0.2 |
| W4 | docs/tasks/list.md 初期化 + 実装 task 5-10 件分解 | 0.3 |
| W5 | 復旧検証 (新 session + /init-tasks + harness-audit) | 0.2 |

合計 1.2 session。

## TDD 戦略

### RED

- `recall_poc/.claude/tests/recall-poc-recovery-smoke.sh` 新設 — 復旧後の verify (project_id 独立 / draft-flow-guard 動作 / list.md タスク有り)

### GREEN

- 各 Wave を順次実装、検証 smoke を pass

## 派生 task / 次アクション候補

- recall_poc 用 instinct (L4 学習) が独立蓄積され始めるので、3 ヶ月後に `/promote` 候補を harness-audit で集計

## 完了条件

- [x] recall_poc が独立 project hash で observation 記録される (W1 git init `875d2ea`、smoke Case 1 で git root 独立確認)
- [x] recall_poc/CLAUDE.md が draft フロー強制版に更新 (W2)
- [x] docs/draft/0[1-3]_*.md に承認 frontmatter あり (W3、12 draft 確認)
- [x] docs/tasks/list.md に実装 task 行が 5+ 件 (W4、26 task / 180 Step、smoke Case 3 で確認)
- [x] draft-flow-guard.sh が recall_poc で誤検知なく動作 (W5 smoke Case 2a/b/c で BLOCK+PASS 確認)
