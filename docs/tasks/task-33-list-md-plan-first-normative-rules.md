---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
# 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) metadata
total_steps: 4
-->

# Task #33: list-md plan-first 規範追加 (task-management.md §plan-first)

> Status: **✅ 完了** (2026-05-25)
> 起案: 2026-05-25
> 関連: #29 (旧採用 5 条、本 task は採用 6 条 supersede 下で完遂)、#34/#35/#36/#37 (旧 Phase 2-5 を分割した派生 task)
> 設計起源: [`docs/draft/list-md-plan-first-normative.md`](../draft/list-md-plan-first-normative.md)

## Task ゴール

`.claude/rules/task-management.md` に「plan-first 行先置きフロー (batch planning)」subsection が追加され、batch planning 時の 📝 行先置きフロー 2 経路分岐 (経路 A 単発 / 経路 B batch) と凡例 📝 用途 (2 用途) が明文化される (観察可能: `grep -q "経路 B (batch planning)" .claude/rules/task-management.md` exit 0)。

## Task 作業概要

- 既存 §「設計→承認→タスク追加フロー（必須）」直後に新 subsection 追加
- 経路 A (単発): 既存フロー保持
- 経路 B (batch planning): 4 step (master roadmap plan → list.md 📝 batch 先置き → 個別 draft 起案 → `/new-task` で 📝 → 🔲 update)
- 凡例 📝 用途明文化: 「draft 起案中 / 承認待ち + 計画段階の先置き」(2 用途 table)
- 5 reviewer 並列 × 5 iter で strict 0-finding 収束 (旧採用 5 条 4 反復上限 5 回内)

## Task 完了条件 (DoD)

- [x] `grep -q "経路 B (batch planning)" .claude/rules/task-management.md` exit 0
- [x] `grep -q "経路 A (単発、既存フロー、default)" .claude/rules/task-management.md` exit 0
- [x] `grep -q "2 用途" .claude/rules/task-management.md` exit 0 (凡例 📝 table 存在)
- [x] reviewer 5+ approve (iter5 strict 0-finding)
- [x] 既存 11 smoke regression 0 (`bash .claude/tests/task-rule-guard-smoke.sh` exit 0)
- [x] commit 完了 (`b662f88` / `583b1e3` / `19e7b42` / `9691a1a`、Step 1-3 集約、push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

recall_poc plan-first 不在事案の再発防止のため、task-management.md §plan-first を追加し batch planning 時の 📝 行先置きフロー 2 経路分岐 (経路 A/B) と凡例 📝 用途 (2 用途) を明文化する。完成すれば AI が batch planning 時に list.md plan-first 先置きを規範通り実行できるようになる。

## 背景・目的

`/new-task` は **1 task ずつ sequential** に list.md へ 🔲 行 append する設計で、master roadmap で **N 個の task を batch plan** する用途を想定していない。結果、26 task の batch 計画下でも list.md は空のまま draft 起案だけが進み、user が IDE で進捗追跡不可になる事案が recall_poc で発生 (2026-05-25 観測)。

本 task は案 C ハイブリッド (P1+P2+P3+P5) の **P1 (規範文書化)** のみを scope とする。P2 (`/new-task` 動作拡張) / P3 (SessionStart hook) / P5 (task-rule-guard 拡張) / 統合 (CLAUDE.md 教訓) は派生 task #34/#35/#36/#37 へ分割。

詳細は draft §1 真因サマリを参照。

## 仕様（決定済）

draft §2 の 4 案比較から **案 C ハイブリッド (P1+P2+P3+P5)** を採用。本 task では P1 (task-management.md §plan-first 規範文書化) のみ実施。

## 設計

draft §3 を参照。task-management.md §「設計→承認→タスク追加フロー（必須）」直後に新 subsection「plan-first 行先置きフロー (batch planning) — 2 経路分岐」を挿入。

## TDD 戦略

### RED
規範文書系のため unit test 不要、grep 検証ベース (Step 3 で 4-grep + 既存 smoke regression 0)。

### GREEN
- task-management.md §plan-first 追加 (main 直接 Edit、`.claude/rules/` 許可)

### REFACTOR
- skip (規範文書追記のみ、refactor 余地なし)

## Step 計画

> **採用 6 条 (Task=Phase=N Step、2026-05-25 採用)** 準拠。Phase 中間階層なし、Task 直下 4 Step。

### Step 計画前の事前確認

`git log --all --grep "plan-first" --grep "list.md" --oneline` で既存 commit 確認済 (新規規範化のため既存解消 commit なし)。

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | task-management.md §plan-first 新規 subsection 追加 (経路 A/B 分岐 + 凡例 📝 用途明文化) | 0.5h | — |
| 2 | ✅ | (テスト設計レビュー) 5 reviewer 並列 × 5 iter で strict 0-finding 収束 | 0.5h | Step 1 |
| 3 | ✅ | (テスト合格) 4-grep + smoke 11/11 + env override PASS | 0.2h | Step 2 |
| 4 | ✅ | (リファクタリング) skip 明示: 規範文書追記のみ refactor 余地なし | 0.1h | Step 3 |

合計工数: **1.3h** (元 Phase 1 工数 0.5 から iter cycle 込み実工数)

### Step 1: task-management.md §plan-first 新規 subsection 追加

**Step status**: ✅ 完了

**作業概要**: 既存 §「設計→承認→タスク追加フロー（必須）」直後に新 subsection「plan-first 行先置きフロー (batch planning) — 2 経路分岐」を追加。経路 A (単発) と経路 B (batch planning) の 4 step を明文化、凡例 📝 用途 2 種を table 化。

**完了条件**:
- `grep -q "経路 B (batch planning)" .claude/rules/task-management.md` exit 0 ✅
- 新 subsection 存在 (`grep -q "plan-first 行先置きフロー" .claude/rules/task-management.md` exit 0) ✅
- commit `b662f88` (initial) + `583b1e3` (iter2 fix 19 件) + `19e7b42` (iter4 fix 17 件) + `9691a1a` (iter5 micro-fix 2 件)

### Step 2: (テスト設計レビュー)

**Step status**: ✅ 完了

**作業概要**: 5 reviewer 動的選定 (architect-reviewer / harness-optimizer / qa-expert / tdd-guide / pr-test-analyzer) を並列起動、収束まで反復 (上限 5 回)。iter3 16 findings → iter4 fix 17 件 → iter5 で 3 strict approve (architect/harness-opt/tdd-guide median 0.97) + qa-expert QA-09 + pr-test L-02 残存 = iter5 micro-fix 2 件で strict 0-finding 達成。

**完了条件**:
- 全 reviewer approve / no objection ✅ (iter5 strict 0-finding)
- iter cycle 5 回以内収束 ✅ (iter1-5 = 5 回)

### Step 3: (テスト合格)

**Step status**: ✅ 完了

**作業概要**: 規範文書のため grep 検証 (4 件) + 既存 smoke regression 0 + env override 動作検証。

**完了条件**:
- `grep -q "経路 A (単発、既存フロー、default)" .claude/rules/task-management.md` exit 0 ✅ (経路 A 不破壊)
- `grep -q "経路 B (batch planning)" .claude/rules/task-management.md` exit 0 ✅ (経路 B 追加)
- `grep -q "📝 設計（未承認）" .claude/rules/task-management.md` exit 0 ✅ (凡例 📝 status 文言)
- `grep -q "2 用途" .claude/rules/task-management.md` exit 0 ✅ (用途 (1)/(2) table 存在、QA-08 強化)
- `bash .claude/tests/task-rule-guard-smoke.sh` exit 0 ✅ (既存 11 cases regression 0)

### Step 4: (リファクタリング)

**Step status**: ✅ 完了

**完了条件**: `skip: 規範文書追記のみ、refactor 余地なし` 明示記録 ✅

## 工数見積

合計 **1.3h** (Step 1: 0.5 + Step 2: 0.5 iter cycle + Step 3: 0.2 + Step 4: 0.1)。元 Phase 1 工数 0.5 に iter cycle 実工数を反映。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/rules/task-management.md` (規範文書) |
| migration | なし |
| 環境変数 | なし (本 task で新設なし、派生 task #35 で `HC_LIST_PLAN_FIRST_REMINDER_ENABLED` 新設予定) |
| 互換性 | 経路 A (単発) 既存フロー保持で backward 互換、経路 B opt-in |

## 再発防止

- 規範文書化のみで AI が経路 B を選択可能にする (honor system 基盤)
- 機械検出 (P3 SessionStart hook / P5 task-rule-guard 拡張) は派生 task #35/#36 で実装
- CLAUDE.md 教訓追加は task #37 (統合) で実装

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-25 | 起案 | 設計 draft `docs/draft/list-md-plan-first-normative.md` 起こし (commit `87a50ea`) |
| 2026-05-25 | 承認 | user「a」発話で承認、`docs/tasks/task-33-list-md-plan-first-normative.md` 作成 |
| 2026-05-25 | 着手 | branch `feat/list-md-plan-first-normative` |
| 2026-05-25 | Step 1 完了 | commit `b662f88` |
| 2026-05-25 | Step 2 iter2 fix | commit `583b1e3` (HIGH/CRIT 8 + MEDIUM 7 + LOW 4) |
| 2026-05-25 | Step 2 iter4 fix | commit `19e7b42` (iter3 5 reviewer findings 14 解消) |
| 2026-05-25 | Step 2-4 完了 | commit `9691a1a` (iter5 micro-fix 2 件、strict 0-finding 達成) |
| 2026-05-25 | Task 完了 | 採用 6 条 supersede 下で本 file 再構造化、派生 task #34/#35/#36/#37 へ Phase 2-5 分割 |

## 派生 task / 次アクション候補

### 確定派生 (Wave C-1 で分割)

- [x] (🔄) task #34: `/new-task` の 📝 → 🔲 update or append 動作実装 (旧 Phase 2、本 task 着手後に分割) — [task-34-list-md-plan-first-new-task-update.md](task-34-list-md-plan-first-new-task-update.md)
- [x] (🔲) task #35: SessionStart hook で「list.md 空 + draft ≥ 3」検出 (旧 Phase 3) — [task-35-list-md-plan-first-session-hook.md](task-35-list-md-plan-first-session-hook.md)
- [x] (🔲) task #36: `task-rule-guard.sh` PreToolUse(Write `docs/draft/*.md`) で 📝 不在 warn (旧 Phase 4) — [task-36-list-md-plan-first-draft-warn.md](task-36-list-md-plan-first-draft-warn.md)
- [x] (🔲) task #37: 統合 + CLAUDE.md Critical Lessons 教訓追加 (旧 Phase 5) — [task-37-list-md-plan-first-integration.md](task-37-list-md-plan-first-integration.md)

### parking-lot 候補 (継承)

- [ ] (🟢) P4 `_LIST_PLAN_TEMPLATE.md` 新設 + auto-insert hook (本 task scope 外、parking-lot 検討対象)

### 関連

- [`next-actions.md`](next-actions.md) — entry #21
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「副産物発生時の即時 draft 起こし義務」

## 関連

- Draft: [`docs/draft/list-md-plan-first-normative.md`](../draft/list-md-plan-first-normative.md)
- 依存タスク: #29 (Phase→Step 旧採用 5 条、本 task は採用 6 条 supersede 下で完遂)
- 派生タスク: #34 / #35 / #36 / #37 (旧 Phase 2-5 分割)
- 既存規範: `.claude/rules/task-management.md` §「設計→承認→タスク追加フロー（必須）」(P1 修正対象)
- 副産物 entry: `docs/tasks/next-actions.md` entry #21 (2026-05-25、🟡 → 🔄 → ✅ Phase 1 部分)
- 観測 project: recall_poc (本リポでは hot fix 適用済、hirai-method 反映 Phase 1 完遂)
- 起源: user Post-Mortem 報告 (2026-05-25)
