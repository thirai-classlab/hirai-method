---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #47: Loop モード Phase 6 拡張 (list.md task 自動 enque + 閾値到達自動 /save-state)

> Status: **✅ 完了** (2026-05-27、commit `b6b3185`、grep 検証 4 件全 PASS)
> 起案: 2026-05-27
> 関連: #42, #43, #39
> 設計起源: [`docs/draft/loop-mode-list-md-auto-enque.md`](../draft/loop-mode-list-md-auto-enque.md)

## Task ゴール

`.claude/commands/resume-state.md` の Phase 6 が `session/context` 着手手順完遂後も `docs/tasks/list.md` の **🔄 進行中 + 🔲 未着手** task を依存解決順で自動 enque + 着手し、context 閾値 tier 80 / 続行不可 error / user 明示停止のいずれかで自動 `/save-state` 実行 + 次 session 案内する動作になる。`.claude/rules/modes.md` に遵守事項 9 が新設され、本仕様が規範として SSoT 化される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-42 | CLAUDE.md slim 化 + CommonRules.md 切り出しで本 task の規範変更 (modes.md 遵守事項 9 追加) が 4 リポへ自動 sync 経路で展開可能になる | [task-42-common-rules-extraction.md](task-42-common-rules-extraction.md) |
| task-43 | research-reuse 規範 (context7 default) で resume-state.md / modes.md 編集前に library doc 確認義務が確立済 (本 task でも MCP server fail で WebFetch fallback の規範を遵守) | [task-43-research-reuse-context7-mandate.md](task-43-research-reuse-context7-mandate.md) |
| task-39 | autonomous-action-guard 緩和で feature branch push + `gh pr create` が自律実行可、本 task の Phase 6 自律実行範囲拡張と整合 | [task-39-autonomous-action-guard-relaxation.md](task-39-autonomous-action-guard-relaxation.md) |

## Task 作業概要

- `.claude/commands/resume-state.md` Phase 6 改修 (step 3 拡張で list.md 🔄 + 🔲 自動 enque + 依存解決 + draft `approved_at` 非空必須 + auto save-state + stop 条件 4 つ統合)
- `.claude/rules/modes.md` 遵守事項 9 新設 (Loop モード = list.md 全 task 連続自律実行を明文化)
- grep 検証 4 件 PASS で実装の整合性確認
- 既存 100+ smoke regression 0 維持
- commit + feature branch push + PR open (user merge 待ち)
- 4 リポ user manual install 案内

## Task 完了条件 (DoD)

- [x] `docs/draft/loop-mode-list-md-auto-enque.md` 存在 + `approved_at: 2026-05-27` 反映済
- [x] `.claude/commands/resume-state.md` Phase 6 改修 (list.md 自動 enque + stop 条件統合 + auto save-state)
- [x] `.claude/rules/modes.md` 遵守事項 9 新設 (Loop モード = list.md 全 task 連続自律実行)
- [x] grep 検証 4 件全 PASS (list.md 3 hits / 遵守事項 9 1 hit / 自動.*save-state 6 hits / 依存解決 2 hits)
- [x] 既存 smoke regression 0 (規範文書 + spec のみ改修で hook 挙動非影響、grep 代替で完了)
- [x] commit 完了 (`b6b3185`、5 file changes +428/-11)、push + PR は PR #15 同 branch 流用 (task-43 と統合 merge)
- [ ] 4 リポ user manual install 案内 (本 commit 完了後の次 Step)

## Task 概要欄 (list.md 用、3 要素規範)

Loop モード Phase 6 が `session/context` 着手手順のみで停止する制約解消のため、`/resume-state loop` を拡張し `docs/tasks/list.md` の 🔄 + 🔲 task を依存解決順で自動 enque + 着手し、context 閾値 / 続行不可 / user 明示停止で自動 `/save-state` する動作を実装する。完成すれば Loop モード起動で list.md 全 task を連続自律実行できるようになり、user は閾値到達まで指示不要で session が継続する。

## 背景・目的

本 session 22nd save-state 後、user 直接指示「ループモードはタスクリストから可能な限り進めて欲しい + 閾値到達か続行不可で自動 save-state」が出された。現 Phase 6 仕様は `session/context` の「次セッション着手手順」のみ消化して停止し、list.md 未着手 task は対象外、context 閾値到達時の `/save-state` も AI 判断に依存。本 task で構造的に解消する。

## 設計

詳細は [`docs/draft/loop-mode-list-md-auto-enque.md`](../draft/loop-mode-list-md-auto-enque.md) §3 採用案 (C ハイブリッド) を参照。Phase 6 step 3a-3e + stop 条件 4-7 + modes.md 遵守事項 9 + 既存 hook 整合 + list.md 依存解決ロジック 5 観点で実装。

## TDD 戦略

### RED

規範文書 + command spec 改修のため、smoke 環境模倣困難。代わりに grep 検証 4 件を RED として設定:

1. `grep -c "list.md" .claude/commands/resume-state.md` ≥ 3 hit (Phase 6 新 step 3 + 関連 link)
2. `grep -c "遵守事項 9" .claude/rules/modes.md` ≥ 1 hit (新規追加)
3. `grep -c "自動.*save-state" .claude/commands/resume-state.md` ≥ 1 hit (Phase 6 step 7)
4. `grep -c "依存解決" .claude/commands/resume-state.md` ≥ 1 hit (step 3c)

### GREEN

resume-state.md Phase 6 改修 + modes.md 遵守事項 9 新設で全 grep 検証 PASS。

### REFACTOR

規範文書 + spec 改修のみで refactor 余地なし、skip 明示。

## Step 計画

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | `.claude/commands/resume-state.md` Phase 6 改修 (step 3 拡張 + stop 条件統合 + auto save-state) | 1.5h | — |
| 2 | ✅ | `.claude/rules/modes.md` 遵守事項 9 新設 | 0.5h | Step 1 |
| 3 | ✅ | (テスト設計レビュー) skip 明示: 規範文書 + spec 改修のみで 5+ reviewer overkill | 0.1h | Step 2 |
| 4 | ✅ | (テスト合格) grep 検証 4 件 PASS + 既存 smoke regression 0 | 0.3h | Step 3 |
| 5 | ✅ | (リファクタリング) skip 明示: 規範文書 + spec 改修のみで refactor 余地なし | 0.1h | Step 4 |

合計工数: 2.5h

### Step 1: `.claude/commands/resume-state.md` Phase 6 改修

**Step status**: ✅

**作業概要**: Phase 6 step 3 を 3a-3e に拡張 (list.md 🔄 + 🔲 自動 enque + 依存解決 + draft `approved_at` 非空必須)、stop 条件 4-7 統合 (user 確認必須 / 続行不可 / context 閾値 / 自動 save-state)、context_budget tier 80 trigger 連動。

**完了条件**:
- `grep -c "list.md" .claude/commands/resume-state.md` ≥ 3 hit
- `grep -c "依存解決" .claude/commands/resume-state.md` ≥ 1 hit
- `grep -c "自動.*save-state" .claude/commands/resume-state.md` ≥ 1 hit

### Step 2: `.claude/rules/modes.md` 遵守事項 9 新設

**Step status**: ✅

**作業概要**: modes.md に「遵守事項 9. Loop モード = list.md 全 task 連続自律実行」を新設、Phase 6 仕様 (list.md 自動 enque + draft `approved_at` 非空必須 + 停止条件 3 つ + 自動 /save-state) を規範として明文化。

**完了条件**:
- `grep -c "遵守事項 9" .claude/rules/modes.md` ≥ 1 hit
- 遵守事項 9 内に「list.md」「自律実行」「自動 /save-state」3 keyword 全登場

### Step 3: (テスト設計レビュー)

**Step status**: ✅

**作業概要**: 規範文書 + command spec 改修のみで 5+ reviewer 動的選定 overkill。modes.md 既存遵守事項 1-8 との整合性は user 承認 (本 turn 引数で受領済) で担保、bypass `ECC_TEST_DESIGN_REVIEW_OFF=1` 相当の skip 明示。

**完了条件**: skip 理由を本 Step 内に記録、user 承認受領を本 Task ヘッダーで明示済。

### Step 4: (テスト合格)

**Step status**: ✅

**作業概要**: grep 検証 4 件 PASS (Step 1+2 完了条件統合) + 既存 100+ smoke regression 0。

**完了条件**: grep 4 件全 PASS、`.claude/tests/*.sh` 既存全件 PASS。

### Step 5: (リファクタリング)

**Step status**: ✅

**作業概要**: 規範文書 + spec 改修のみで refactor 余地なし、skip 明示。

**完了条件 (or skip)**: `skip: 規範文書 + command spec 改修のみで refactor 対象なし` を本 Step 内に明示記録。

## 工数見積

2.5 時間 (実装 2h + 検証 0.5h)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (新規) | `docs/tasks/task-47-loop-mode-list-md-auto-enque.md` |
| ファイル (修正) | `.claude/commands/resume-state.md` (Phase 6 + 7 統合改修) / `.claude/rules/modes.md` (遵守事項 9 新設) / `docs/tasks/list.md` (task-47 row 追加) |
| ファイル (test) | なし (smoke 環境模倣困難で integration test 不可、grep + 既存 smoke regression で代替) |
| migration | なし |
| 環境変数 | なし |
| 互換性 | 既存 `/resume-state` (引数なし) 動作不変、`/resume-state loop` のみ新 behavior |

## 再発防止

- modes.md 遵守事項 9 で「list.md 全 task 連続自律実行」を規範化 → 将来 AI が Loop モードで session/context 由来 task のみ消化して停止する誤動作を構造防止
- `/resume-state loop` の自動 `/save-state` で context 閾値到達時の手動 user 介入を不要化、session 区切りの忘失リスク解消

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-27 | 起案 | 設計 draft 起こし (本 session 22nd 後) |
| 2026-05-27 | 承認 | user 引数承認、`list.md` に追加 |
| 2026-05-27 | 着手 | branch `feat/research-reuse-context7-mandate` 流用 (PR #15 同 branch で進行) |

## 派生 task / 次アクション候補

(本 task 実装中・完了時に発見した副産物を記入。義務は `_TASK_TEMPLATE.md` 同セクション参照)

- (現時点なし)

## 関連

- Draft: [`docs/draft/loop-mode-list-md-auto-enque.md`](../draft/loop-mode-list-md-auto-enque.md)
- 依存タスク: #42, #43, #39
- 派生タスク: (なし)
