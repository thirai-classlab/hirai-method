---
asana_url: ""
slack_urls: []
deadline: ""
requester: "user"
---

<!--
total_steps: 6
-->

# Task #45: config-yml Phase 2 (hook feature check + review command yml 参照)

> Status: **✅ 完了**
> 起案: 2026-05-27
> 完了: 2026-05-27
> 関連: #44 (Phase 1), #46 (Phase 3)
> 設計起源: [`config-yml-phase2-hook-review-command.md`](../draft/config-yml-phase2-hook-review-command.md) (approved_at: 2026-05-27)
> closure: iter 3 4 reviewer 全員 approve median confidence 0.96 (tdd-guide 0.93 / qa-expert 0.97 / test-automator 0.96 / pr-test-analyzer 0.95)、smoke 7/7 + 既存 100+ smoke regression 0、6 commits

## Task ゴール

`.claude/hooks/*.sh` 21+ 件に `is_feature_enabled` 参照の feature check が追加され、`.claude/commands/{design,test,module,system}-review.md` 4 件に `HC_REVIEW_REQUIRED_*` / `_MIN_COUNT_*` / `_MAX_COUNT_*` / `_ITERATION_MAX` yml 参照 logic が追加される。`bash .claude/tests/review-required-min-count-smoke.sh` 4/4 PASS + 既存 smoke regression 0。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-44 | task-44 で yml schema 36 key + `is_feature_enabled()` 関数が整備されているため、本 task はその関数を hook 21+ で呼び出す前提に立つ。task-44 完遂状態 (PR #18 merged、commit `dfdbfca`) を前提とする。 | [task-44-config-yml-phase1-schema-loader.md](task-44-config-yml-phase1-schema-loader.md) |

## Task 作業概要

- hook 21+ 件 (loop-confirmation-detector / draft-flow-guard / task-rule-guard / delegation-guard / workflow-guard / confidence-gate / gateguard / context-budget / parallel-subagent-reminder / autonomous-action-guard / byproduct-discharge-guard / next-actions-surface / why-x5-reminder / why-x5-violation-detect / session-help-surface / improvement-proposal / mode-session-start / check-serena-mcp / check-required-env / init-tasks-on-start / mode-enforce / 他) 冒頭に `is_feature_enabled <name>` check を追加
- review command 4 件 (`design-review.md` / `test-design.md` / `module-review.md` / `system-review.md`) prompt 冒頭に `HC_REVIEW_REQUIRED_<scope>` / `_MIN_COUNT_<scope>` / `_MAX_COUNT_<scope>` / `_ITERATION_MAX` 参照 logic 追加
- smoke `.claude/tests/review-required-min-count-smoke.sh` 新設 (4 cases)
- reviewer 5+ 並列 iter 1+ (CRITICAL+HIGH+MEDIUM=0 収束)
- PR create + 4 リポ install 案内 (user manual)

## Task 完了条件 (DoD)

- [ ] hook 21+ 件に feature check 追加 (各 hook で `is_feature_enabled <name>` 参照、feature OFF 時 `exit 0` no-op)
- [ ] review command 4 件に yml 参照 logic 追加 (`HC_REVIEW_REQUIRED_*` / `_MIN_COUNT_*` / `_MAX_COUNT_*` / `_ITERATION_MAX` 4 env 参照)
- [ ] smoke `review-required-min-count-smoke.sh` 4 cases PASS
- [ ] 既存 100+ smoke regression 0
- [ ] reviewer iter 5 上限内収束 (CRITICAL+HIGH+MEDIUM=0)
- [ ] commit + push + PR create (feature branch `feat/config-yml-phase2-hook-review-command`)
- [ ] 4 リポ install 案内 (user manual)

## Task 概要欄 (list.md 用、3 要素規範)

機能単位 on/off と reviewer 制御の機械強制のため、21+ 件 hook 冒頭に feature check を追加し、4 件 review command に yml 参照 logic を追加する。完成すれば feature toggle OFF で関連 hook が一括停止し、reviewer 制御 (required / min / max / iteration) が yml 値で動作するようになる。

## 背景・目的

task-44 (Phase 1) で `harness-config.yml` に 36 key (feature_* 21 + review_* 15) が追加され、`config-loader.sh` に `is_feature_enabled()` 関数が実装された。しかし hook 21+ 件と review command 4 件は yml 参照に未対応のため、feature toggle や reviewer 制御が実質的に機能していない。本 task で hook 21+ 件に feature check を追加し、review command 4 件に reviewer 制御 yml 参照 logic を追加することで、yml 値の変更が hook / command 動作に直結する状態を達成する。

## TDD 戦略

### RED

- `.claude/tests/review-required-min-count-smoke.sh` 4 cases (`review_required_design: false` 時 no-op skip / `review_min_count_test: 5` 確認 / `review_max_count_module: 2` 確認 / `review_iteration_max: 3` 確認)
- 既存 smoke (config-feature-toggles 9/9 + delegation-guard 48/48 + 他) の regression 0 検証

### GREEN

- hook 21+ 件冒頭に `is_feature_enabled <name>; or exit 0` の 3 行追加 (staging 戦略 + subagent 並列起動、file 領域独立)
- review command 4 件 prompt 冒頭に yml 参照 logic 追記 (markdown 編集、メイン直接可)

### REFACTOR

- feature check pattern 共通化 (config-loader.sh の helper 関数追加) or 各 hook 内 inline で許容
- review command 共通 helper 抽出検討

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | hook 21+ 件に feature check 追加 (subagent 並列 5-7 件、staging 戦略) | 1.5h | — |
| 2 | 🔲 | review command 4 件に yml 参照 logic 追加 (design / test / module / system) | 0.5h | — |
| 3 | 🔲 | smoke `review-required-min-count-smoke.sh` 新設 (4 cases) | 0.5h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列 iter 1+ | 1.0h | Step 1, 2, 3 |
| 5 | 🔲 | (テスト合格) 全 smoke 統合実行 + 既存 smoke regression 0 | 0.3h | Step 4 |
| 6 | 🔲 | (リファクタリング) feature check pattern 共通化検討 | 0.3h | Step 5 |

合計工数: 4.1h

### Step 1: hook 21+ 件に feature check 追加

**Step status**: 🔲 未着手

**作業概要**: `.claude/hooks/*.sh` 21+ 件冒頭 (`config-loader.sh` source 直後) に `is_feature_enabled <name> || exit 0` を追加。subagent 並列 5-7 件で file 領域独立分割 (loop 系 / draft 系 / delegation 系 / workflow 系 / context 系 / surface 系等)。staging 戦略必須 (`/tmp/foo.sh` → `mv .claude/hooks/foo.sh`)。

**完了条件**: 全 21+ hook で `is_feature_enabled` 参照あり (grep -l 'is_feature_enabled' .claude/hooks/*.sh | wc -l が 21 以上)、feature OFF 時 `exit 0` 動作確認 (smoke or 手動)。

### Step 2: review command 4 件に yml 参照 logic 追加

**Step status**: 🔲 未着手

**作業概要**: `.claude/commands/{design-review,test-design,module-review,system-review}.md` の Phase 1 prompt 冒頭に以下 4 env 参照を追記:
- `HC_REVIEW_REQUIRED_<scope>=false` で no-op skip
- `HC_REVIEW_MIN_COUNT_<scope>=N` で reviewer N 件以上を並列起動
- `HC_REVIEW_MAX_COUNT_<scope>=N` で reviewer N 件以下に絞る
- `HC_REVIEW_ITERATION_MAX=N` で反復上限 (default 5)

メイン直接 Edit 可 (markdown のみ、code file 拡張子外)。

**完了条件**: 各 command で 4 env 参照記述あり (grep -c 'HC_REVIEW_' で各 file >= 4)。

### Step 3: smoke `review-required-min-count-smoke.sh` 新設

**Step status**: 🔲 未着手

**作業概要**: `.claude/tests/review-required-min-count-smoke.sh` 新設、4 cases (上記 4 env 各 1)。test-automator 等 subagent 委譲 (staging 戦略)。

**完了条件**: `bash .claude/tests/review-required-min-count-smoke.sh` exit 0、4/4 PASS。

### Step 4: (テスト設計レビュー)

**Step status**: 🔲 未着手

**作業概要**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + harness-optimizer / code-reviewer / refactoring-specialist)、並列起動、収束まで反復 (上限 5 回)。hook 21+ + command 4 件の大規模変更で reviewer 価値高い (skip 不可)。

**完了条件**: 全 reviewer approve / no objection、iter cycle 5 回以内に CRITICAL+HIGH+MEDIUM=0 収束。

### Step 5: (テスト合格)

**Step status**: 🔲 未着手

**作業概要**: 全 smoke 統合実行 (config-feature-toggles 9/9 + review-required-min-count 4/4 + delegation-guard 48/48 + workflow-guard 8/8 + 他 100+ smoke)。

**完了条件**: 全 smoke exit 0、regression 0。

### Step 6: (リファクタリング)

**Step status**: 🔲 未着手

**作業概要**: feature check pattern 共通化 (config-loader.sh に helper 関数追加) or 各 hook 内 inline で許容。review command 共通 helper 抽出検討。3 観点 (持続可能性 / 汎用性 / 非冗長化) 判定。

**完了条件**: refactor 実施なら指標 (関数 LOC < 50、重複削減 N 箇所) / 不要なら `skip: <理由>` 明示記録。

## 工数見積

4.1 時間 (Step 1: 1.5h hook 21+ subagent 並列 + Step 2: 0.5h review command 4 件 + Step 3: 0.5h smoke + Step 4: 1.0h reviewer iter + Step 5: 0.3h smoke 統合 + Step 6: 0.3h refactor)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/tasks/task-45-config-yml-phase2-hook-review-command.md` / `.claude/tests/review-required-min-count-smoke.sh` |
| 修正 file | `.claude/hooks/*.sh` (21+ 件 feature check 1 行追加) / `.claude/commands/{design,test,module,system}-review.md` (yml 参照 logic) |
| 環境変数 | task-44 で定義済 34 件を参照、本 task で新規追加なし |
| 互換性 | 既存 hook level env (`HC_<HOOK>_ENABLED`) 維持、新 feature toggle は上位 layer (両者併用可) |

## 再発防止

- feature toggle 機構を hook 全体で機械強制 → 「規範はあるが hook が yml 参照しない」silent failure を構造防止
- reviewer 制御 yml 化 → review command の reviewer 数 / iter 上限を採用者が修正容易に

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-27 | 起案 | 設計 draft 起こし (master draft §10 5 件 batch 承認) |
| 2026-05-27 | 承認 | user 承認、`list.md` に追加 |
| 2026-05-27 | 着手 | branch `feat/config-yml-phase2-hook-review-command` (main rebase 完了) |

## 派生 task / 次アクション候補

(本 task 進行中に発見した副産物をここに記入)

## 関連

- Draft: [`config-yml-phase2-hook-review-command.md`](../draft/config-yml-phase2-hook-review-command.md) (approved_at: 2026-05-27)
- master draft: [`config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)
- 依存タスク: #44 (Phase 1)
- 派生タスク: #46 (Phase 3 hc-config.sh)
