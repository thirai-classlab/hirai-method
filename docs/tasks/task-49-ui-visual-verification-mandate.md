---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 1
-->

# Task #49: UI 実装後のビジュアル検証必須化 (採用 6 条 4 統合、honor-system)

> Status: **✅ 完了** (2026-05-27、小タスク [採用 6 条 5、1 Task + 1 Step]、honor-system doc 追記)
> 起案: 2026-05-27
> 設計起源: [ui-visual-verification-mandate.md](../draft/ui-visual-verification-mandate.md) (approved_at: 2026-05-27)

## Task ゴール

`.claude/rules/task-management.md` 採用 6 条 4「テスト合格 Step」に「UI (browser/web) 含む Task は E2E に加えてビジュアル検証 (agent-browser skill + screenshot) を必須」を統合し、機能 (E2E) と見た目 (visual) を別品質軸として両方必須化する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | 依存なし (独立した規範追記) | — |

## Task 概要欄 (list.md 用、3 要素規範)

UI 実装で E2E PASS でも見た目崩れを捕捉できない品質 gap を埋めるため、採用 6 条 4「テスト合格 Step」に browser/web UI のビジュアル検証 (agent-browser + screenshot、E2E と別レイヤ) を必須化する。完成すれば AI が UI Task 完了前に必ず見た目を視覚確認し、E2E のみ / 型チェックのみでの完了宣言を防げるようになる。

## 背景・目的

user 直接指示 (2026-05-27)「UI実装後はビジュアルの検証を必須化してください。ブラウザ検証は vercel/agentブラウザースキルを利用する。スクリーンショットなども利用する。e2eとは別」。

現行採用 6 条 4「テスト合格 Step」は「UI 含む Task は E2E 必須」止まりで、ビジュアル (見た目) 検証が未明示だった。E2E (機能フロー) と visual (見た目) は別品質軸であり、E2E PASS でも見た目崩れは捕捉できないため、本 task で gap を埋める。

## 設計方針 (AskUserQuestion 2026-05-27 確定)

- **強制方法**: honor-system のみ (機械強制 hook なし)
- **codify 先**: 採用 6 条 4 に統合 (新規 section / workflow stage 追加なし)
- **スコープ**: browser/web UI のみ (terminal TUI 対象外)
- **検証ツール**: agent-browser skill + screenshot

## Step 計画 (1 Step、採用 6 条 5 小タスク)

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | ✅ | 採用 6 条 4「テスト合格 Step」にビジュアル検証必須化を追記 + §UI 変更検出基準 future hook 案の整合更新 | task-management.md に「UI (browser/web) は E2E + ビジュアル検証必須」+ agent-browser/screenshot/breakpoint/E2E 別レイヤ/terminal TUI 除外 が記載される |

### Step 1: 規範追記 (テスト検証 + refactor 判定併記、採用 6 条 5)

**Step status**: ✅

**作業概要**: `.claude/rules/task-management.md` 採用 6 条 4「テスト合格 Step」にビジュアル検証 block を追記 (agent-browser + screenshot + 主要 breakpoint/状態/theme + E2E との別レイヤ明記 + UI 変更検出基準流用 + terminal TUI 除外 + honor-system)。§UI 変更検出基準 future hook 案も E2E + ビジュアル検証に整合更新。

**完了条件**: task-management.md に上記記載 (実施済)。**test 検証**: 規範文書追記のみで自動 test 対象外 (honor-system、hook/code/smoke 変更なし)。**refactor 判定**: skip (単純な規範追記で refactor 余地なし)。

## 完了条件 (DoD)

- [x] 採用 6 条 4「テスト合格 Step」に「UI (browser/web) は E2E + ビジュアル検証必須」追記
- [x] ビジュアル検証手順 (agent-browser + screenshot + breakpoint/状態/theme + E2E 別レイヤ + terminal TUI 除外) 記載
- [x] UI 変更検出基準の流用を明記
- [x] honor-system (hook なし) を明記
- [x] §UI 変更検出基準 future hook 案との整合更新
- [x] memory `feedback_ui_visual_verification_mandate` 保存 + MEMORY.md index

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 修正 file | `.claude/rules/task-management.md` (採用 6 条 4「テスト合格 Step」+ §UI 変更検出基準 future hook 案) |
| 新規 file | draft + 本 task file + memory のみ (hook / smoke / code 新設なし) |
| 機械強制 | なし (honor-system、user 決定) |
| 4 リポ反映 | install.sh --update で各 repo に task-management.md 同期 (user manual) |

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-27 | 起案 | user 指示「UI実装後はビジュアル検証必須化」、AskUserQuestion で方針確定 |
| 2026-05-27 | 承認 | user「承認します。」(確認 3 点 OK)、approved_at 記入 |
| 2026-05-27 | 完了 | task-management.md 採用 6 条 4 + §UI 変更検出基準 追記、honor-system doc-only |

## 関連

- Draft: [`ui-visual-verification-mandate.md`](../draft/ui-visual-verification-mandate.md)
- memory: `feedback_ui_visual_verification_mandate`
- skill: `agent-browser` / `webapp-testing` / `ui-demo`
- 既存規範: 採用 6 条 4 (テスト合格 Step) / §UI 変更検出基準 / `~/.claude/rules/web/testing.md` (Visual Regression)
