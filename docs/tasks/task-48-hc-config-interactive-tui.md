---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #48: hc-config.sh 矢印キー TUI 化 + key metadata (説明 + 変更効果) 表示

> Status: **✅ 完了** (2026-05-27、8 commits `a353b2e`..`c48f15f`、PR [#22](https://github.com/thirai-classlab/hirai-method/pull/22))
> 起案: 2026-05-27
> 関連: task-46 (config-yml Phase 3、hc-config.sh 新設)
> 設計起源: [hc-config-interactive-tui.md](../draft/hc-config-interactive-tui.md) (approved_at: 2026-05-27)

## Task ゴール

`bash .claude/scripts/hc-config.sh` が実 terminal で矢印キー (↑↓ + Enter) ナビゲーション + effect panel (選択 key の 説明/型/現値/default/変更効果) を表示し、`--list` が各 key の「説明 + 変更効果」を表示する。非 TTY 環境では現行番号選択に自動 fallback する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-46 | hc-config.sh (1112 LOC、74 key、cmd_interactive 番号選択 menu + --list 4 列) を本 task で TUI 化 + 説明列拡張する。既存 CLI args 10 種 + atomic write は維持 | [task-46-config-yml-phase3-hc-config-script.md](task-46-config-yml-phase3-hc-config-script.md) |

## Task 作業概要

- `lib/hc-config-metadata.sh` 新設 (74 key 全てに description + effect、inline comment 35 抽出 + hardcode 39)
- 矢印キー TUI 実装 (↑↓ ナビ + Enter 決定 + effect panel + 編集フロー)
- TTY fallback (非 TTY で現行番号選択に自動降格、`HC_HC_CONFIG_FORCE_NUMERIC=1` 強制)
- `--list` 説明列拡張 + `--list --verbose` 6 列 (category 別グルーピング)
- smoke 新設 (metadata 完全性 + --list 説明列 + TTY fallback) + 手動 TUI 検証

## Task 完了条件 (DoD)

- [ ] `lib/hc-config-metadata.sh` 新設 (74 key 全てに description + effect)
- [ ] 矢印キー TUI (↑↓ ナビ + Enter 決定 + effect panel + 編集フロー)
- [ ] TTY fallback (非 TTY で番号選択に自動降格、`HC_HC_CONFIG_FORCE_NUMERIC=1` 強制)
- [ ] `--list` 説明列拡張 + `--list --verbose` 6 列 (category グルーピング)
- [ ] smoke `hc-config-tui-smoke.sh` 7 cases PASS
- [ ] 既存 smoke regression 0 (hc-config-script-smoke 21/21 維持 + 既存 37 smoke)
- [ ] 手動 TUI 検証 (実 terminal で ↑↓ + effect panel + 編集動作確認)
- [ ] reviewer iter 5 上限内収束
- [ ] commit + push + PR create (feature branch、task #39 緩和で自律実行可)
- [ ] 4 リポ install 案内 (user manual)

## Task 概要欄 (list.md 用、3 要素規範)

hc-config.sh の UX 改善のため、番号選択 menu を矢印キー TUI (↑↓ + Enter + effect panel) に拡張し、74 key 全てに「説明 + 変更効果」metadata を定義して対話時 + --list 両方に表示する。完成すれば user が実 terminal で各 key の意味と変更影響を視認しながら gcloud/gh CLI 風に設定編集でき、非 TTY 環境では現行番号選択に自動 fallback する。

## 背景・目的

task-46 で hc-config.sh を新設したが、(1) 対話 menu が番号選択のみで gcloud/gh CLI のような ↑↓ ナビ体験がない (2) `--list` が各 key の意味/変更効果を表示せず user が yml を理解せず編集するリスク (3) harness-config.yml の inline comment (密度 47%) が説明として活用されていない、という UX 課題があった。

本 task で矢印キー TUI + key metadata 表示を実装し、設定編集の安全性と理解しやすさを向上する。AskUserQuestion (2026-05-27) で UI 方式「矢印キー TUI」+ 説明表示「対話時 + --list 両方」を user 確定済。

## TDD 戦略

### RED (先に smoke 新設)

`.claude/tests/hc-config-tui-smoke.sh` 新設 (7 cases、impl 不在で 7/7 FAIL):
- Case 1: metadata 完全性 (74 key 全てに description + effect)
- Case 2: category グルーピング (6 category 全 key 分類)
- Case 3: --list 説明列拡張
- Case 4: --list --verbose 6 列
- Case 5: TTY fallback (非 TTY pipe で番号選択降格)
- Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 強制番号選択
- Case 7: inline comment 抽出 (harness-config.yml comment が description に)

### GREEN

- `lib/hc-config-metadata.sh` (74 key metadata) → Case 1/2/7 PASS
- `hc-config.sh` 拡張 (TUI + fallback + --list 説明列) → Case 3-6 PASS

### REFACTOR

- TUI 描画ロジック関数分割 (描画 / 入力 decode / effect panel / fallback)、全関数 ≤ 50 LOC 維持

### 矢印キー TUI 検証方針 (TTY 制約)

TUI 描画は TTY 必須で自動 smoke 困難。自動 smoke は非 TTY fallback + metadata 中心、↑↓ 描画は手動検証 (DoD に明記)。expect/pty は Phase 2 / 別途。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | smoke `hc-config-tui-smoke.sh` 新設 (7 cases、TDD RED commit) | 1.0h | — |
| 2 | 🔲 | `lib/hc-config-metadata.sh` 新設 (74 key description + effect、inline comment 抽出 + hardcode) | 2.5h | Step 1 |
| 3 | 🔲 | `hc-config.sh` 拡張 (矢印キー TUI + TTY fallback + --list 説明列、subagent staging) | 3.0h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) 6 reviewer (tdd-guide / test-automator / qa-expert / code-reviewer + ui-designer + pr-test-analyzer) | 1.5h | Step 3 |
| 5 | 🔲 | (テスト合格) 全 smoke 統合 + 既存 regression 0 + 手動 TUI 検証 | 1.0h | Step 4 |
| 6 | 🔲 | (リファクタリング) TUI 描画関数分割 + 3 観点判定、closure + PR | 0.5h | Step 5 |

合計工数: 9.5h

### Step 1: smoke `hc-config-tui-smoke.sh` 新設 (TDD RED)

**Step status**: 🔲

**作業概要**: draft §4 の 7 cases を smoke 実装、impl 不在で 7/7 FAIL 状態 (EXPECTED FAIL marker、TDD RED 順序遵守)

**完了条件**: `.claude/tests/hc-config-tui-smoke.sh` 新設 (7 cases)、`bash .claude/tests/hc-config-tui-smoke.sh` で 7/7 FAIL、commit message に RED 明記

### Step 2: `lib/hc-config-metadata.sh` 新設 (TDD GREEN 前半)

**Step status**: 🔲

**作業概要**: 74 key 全てに `{category, description, effect}` metadata 定義。inline comment 35 抽出 + hardcode 39 のハイブリッド (CSV here-doc、bash 3.2 互換)

**完了条件**: 全 74 key metadata、Case 1 (完全性) + Case 2 (category) + Case 7 (comment 抽出) PASS、subagent confidence ≥ 0.8

### Step 3: `hc-config.sh` 拡張 (TDD GREEN 後半)

**Step status**: 🔲

**作業概要**: 矢印キー TUI (`read -rsn1` ESC sequence decode + effect panel) + TTY fallback (`[ -t 0 ] && [ -t 1 ]`) + `--list` 説明列拡張。subagent staging 戦略で `.claude/` に install

**完了条件**: Case 3-6 PASS (--list 説明列 / --verbose 6 列 / TTY fallback / 強制番号選択)、既存 hc-config-script-smoke 21/21 維持、subagent confidence ≥ 0.8

### Step 4: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: 6 reviewer 並列 (tdd-guide / test-automator / qa-expert / code-reviewer + ui-designer [TUI UX] + pr-test-analyzer)、収束まで反復 (上限 5 回)

ui-designer 追加理由: 矢印キー TUI の UX (ハイライト / effect panel レイアウト / 操作性 / fallback の自然さ) を専門観点でレビュー。

**完了条件**: 全 reviewer approve / no objection (CRIT+HIGH+MED=0)、iter cycle 5 回以内収束

### Step 5: (テスト合格)

**Step status**: 🔲

**作業概要**: 新 smoke 7 case + 既存 smoke regression 0 + 手動 TUI 検証 (実 terminal で ↑↓ + effect panel + 編集)

**完了条件**: `bash .claude/tests/hc-config-tui-smoke.sh` 7/7 + 既存 smoke 全 regression 0 + 手動 ↑↓ 動作確認

### Step 6: (リファクタリング) + closure

**Step status**: 🔲

**作業概要**: TUI 描画ロジック関数分割 (描画 / 入力 decode / effect panel / fallback)、全関数 ≤ 50 LOC、3 観点判定、closure commit + push + PR

**完了条件**: 全関数 ≤ 50 LOC、3 観点 PASS or skip 明示、closure commit + push + `gh pr create` 完了、4 リポ install 案内 (user manual)

## 工数見積

9.5h (smoke 1h + metadata 2.5h + TUI impl 3h + reviewer 1.5h + test 1h + refactor 0.5h)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/tasks/task-48-hc-config-interactive-tui.md` / `.claude/scripts/lib/hc-config-metadata.sh` / `.claude/tests/hc-config-tui-smoke.sh` |
| 修正 file | `.claude/scripts/hc-config.sh` (cmd_interactive 拡張 + --list 拡張) |
| migration | なし |
| 環境変数 | `HC_HC_CONFIG_FORCE_NUMERIC` 新規追加 |
| 互換性 | 既存 CLI args 10 種不変、対話 menu は TTY 時 TUI / 非 TTY 時現行番号選択で後方互換維持。task-46 の 21 smoke は全て非 TTY (pipe) で fallback path PASS 継続 |

## 再発防止

- key metadata (description + effect) を持つことで、future の yml key 追加時に「説明 + 変更効果」記載が default 規範になる (metadata 完全性 smoke で強制)
- TTY fallback パターンは future の対話的 script の参考実装になる

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-27 | 起案 | draft `hc-config-interactive-tui.md` (AskUserQuestion で UI 方針確定) |
| 2026-05-27 | 承認 | user「問題ありません。」(確認 3 点 OK)、approved_at 記入 |
| 2026-05-27 | 着手 | branch `feat/hc-config-interactive-tui` |
| 2026-05-27 | 完了 | 8 commits `a353b2e`..`c48f15f`、reviewer iter1→iter3 収束 (全 6 approve CRIT+HIGH+MED=0)、TUI 14/14 + script 21/21 (bash3.2) + 全 harness regression 0、全関数 ≤45 LOC、PR [#22](https://github.com/thirai-classlab/hirai-method/pull/22)。user follow-up: 手動 TUI 検証 + 4 リポ install |

## 派生 task / 次アクション候補

(本 task 実装中の副産物を記入)

## 関連

- Draft: [`hc-config-interactive-tui.md`](../draft/hc-config-interactive-tui.md)
- 依存タスク: task-46 (hc-config.sh 新設)
- 設計調査: subagent aef203d58008a374f (confidence 0.85)
- UI 方針: AskUserQuestion 2026-05-27 (矢印キー TUI + 対話/--list 両方)
