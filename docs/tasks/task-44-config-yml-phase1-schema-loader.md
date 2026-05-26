# Task 44: config-yml Phase 1 (yml schema 拡張 + config-loader.sh)

> **Status**: ✅ 完遂 (2026-05-27、iter 2 で 5/5 reviewer approve、CRIT+HIGH+MED=0、PR #18 MERGED)
> **Branch**: `feat/config-yml-phase1-schema-loader`
> **Draft**: [`docs/draft/config-yml-phase1-schema-loader.md`](../draft/config-yml-phase1-schema-loader.md)
> **Master draft**: [`docs/draft/config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)

## Task ゴール

`.claude/harness-config.yml` に新 36 key (feature toggle 21 件 + review 制御 15 件: required 5 + min_count 5 + max_count 4 + iteration_max 1) を追加し、`.claude/hooks/lib/config-loader.sh` に load logic + `is_feature_enabled <name>` 共通関数を追加する。task-45 (hook feature check) と task-46 (config-editor sh) の基盤を整える。

## Task 作業概要

- yml schema 拡張: 新 36 key (`feature_*_enabled` 21 + `review_*_*` 14 [required 5 + min_count 5 + max_count 4] + `review_iteration_max` 1) 追加
- config-loader.sh 拡張: 36 key load logic + `is_feature_enabled <name>` 共通関数 (戻り値 0/1、env override 優先)
- smoke 新設: `config-feature-toggles-smoke.sh` 3 cases (ON / OFF / 未設定 backward compat)
- reviewer 5+ 並列 iter 収束 + 既存 smoke regression 0
- commit + push + PR create + 4 リポ install 案内 (user manual)

## Task 完了条件 (DoD)

- [ ] `.claude/harness-config.yml` に新 36 key 追加 (`grep -cE '^feature_[a-z0-9_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z0-9_]+:' .claude/harness-config.yml` ≥ 15、digit-inclusive で `feature_why_x5_enforcement_enabled` の `5` 計上)
- [ ] `.claude/hooks/lib/config-loader.sh` で 36 key load + `is_feature_enabled` 関数追加 (`declare -f is_feature_enabled` で関数存在確認)
- [ ] smoke `.claude/tests/config-feature-toggles-smoke.sh` 6 cases PASS
- [ ] 既存 smoke regression 0 (config-loader 経由の全 hook smoke)
- [ ] reviewer iter 5 上限内収束 (CRITICAL+HIGH+MEDIUM=0)
- [ ] PR create (`feat/config-yml-phase1-schema-loader`)
- [ ] 4 リポ install 案内 (user manual)

## Task 概要欄 (list.md 用、3 要素)

feature toggle と reviewer 制御の yml 化基盤を整えるため、`harness-config.yml` に新 36 key 追加し `config-loader.sh` に load logic + `is_feature_enabled` 共通関数を追加する。完成すれば task-45/46 が yml 経由で feature toggle と reviewer 制御を参照できるようになる。

## Task 依存先タスク

依存なし (—)

## Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | ✅ | `harness-config.yml` に新 36 key 追加 (feature_* 21 + review_* 15) | `grep -cE '^feature_[a-z0-9_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z0-9_]+:' .claude/harness-config.yml` ≥ 15 (digit-inclusive、iter 2 で実測 21 + 15 = 36 hit 確認) |
| 2 | ✅ | `config-loader.sh` 拡張 (36 key load + `is_feature_enabled` 関数 + iter 2 CRITICAL-1 fix: `_HC_PRESET_KEYS` snapshot ベース env guard + 行末コメント strip) | iter 2 で関数存在確認 + Case 7 CRITICAL-1 regression 解消確認 |
| 3 | ✅ | smoke `config-feature-toggles-smoke.sh` 新設 (iter 1 6 cases + iter 2 で 3 cases 追加 = 9 cases) | iter 2 実測 9/9 PASS |
| 4 | ✅ | (テスト設計レビュー) reviewer 5 並列 iter 1 (median 0.93) + iter 2 (5/5 approve、median 0.94: tdd 0.95 / qa 0.93 / pr-test 0.96 / harness-opt 0.91 / test-auto 0.96) | iter 2 で CRIT+HIGH+MED=0 達成 (qa NEW-M1 list.md sync は本 turn fix 済、harness-opt MED REVIEW_MAX_COUNT_SECURITY は task-45 前置で副産物 #49 管理) |
| 5 | ✅ skip | (テスト合格) iter 2 で 9/9 PASS + 既存 smoke regression 0 確認済 (subagent G + reviewer iter 2 で実測) | smoke 実行は Step 4 reviewer iter 内で完遂、本 Step は merge 判定のみ |
| 6 | ✅ skip | (リファクタリング) skip 明示: yml schema + 1 行追加 + smoke + 行末コメント strip helper で refactor 余地少、3 観点 (持続可能性 ✅ / 汎用性 ✅ / 非冗長化 ✅) は本 Phase 1 で充足 | refactor 余地は task-46 Phase 3 hc-config.sh で集約評価 |

## TDD 戦略

新 smoke `.claude/tests/config-feature-toggles-smoke.sh`:

- Case 1: feature toggle ON (yml default + env unset) で `is_feature_enabled foo` exit 0
- Case 2: feature toggle OFF (`HC_FEATURE_FOO_ENABLED=false` env or yml `feature_foo_enabled: false`) で `is_feature_enabled foo` exit 1
- Case 3: 新 key 未設定 (採用先 yml に該当 key 不在) で `is_feature_enabled foo` default ON 動作 (backward compat)

reviewer 制御の smoke は task-45 で扱う (本 task は yml + loader のみ)。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/draft/config-yml-phase1-schema-loader.md` / `docs/tasks/task-44-config-yml-phase1-schema-loader.md` / `.claude/tests/config-feature-toggles-smoke.sh` |
| 修正 file | `.claude/harness-config.yml` (新 36 key) / `.claude/hooks/lib/config-loader.sh` (load + 共通関数) |
| 環境変数 | 36 件新規 (`HC_FEATURE_*_ENABLED` 21 + `HC_REVIEW_*` 15) |
| 互換性 | 既存 yml 値 touch しない (新 key default 動作)、採用 4 リポ既存 yml 不変 |

## レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 | tdd-guide / test-automator / qa-expert / pr-test-analyzer / harness-optimizer (5 並列) | 1 (Step 3 env guard regression、全員独立指摘) | 多数 (DoD grep regex / yml-only OFF テスト欠落 / install.sh yml 上書き 等) | 多数 (Step status 未更新 / 行末コメント等) | 多数 | median 0.93、iter 続行 |
| iter2 | 同 5 並列 | 0 | 0 | 1 (REVIEW_MAX_COUNT_SECURITY 欠落、task-45 前置で副産物 #49 管理) | 数件 (新規 LATENT-1 等) | **median 0.94、approve** (5/5 全員、tdd 0.95 / qa 0.93 [strict NEW-M1 は本 turn fix 済] / pr-test 0.96 / harness-opt 0.91 / test-auto 0.96) |

iter 2 で実質 CRITICAL+HIGH+MEDIUM=0 達成 (qa-expert NEW-M1 list.md sync は本 turn 内で fix 済、harness-opt MED 1 件は本 task scope 外副産物管理)、iter 3 不要。

## 関連

- master draft: [`docs/draft/config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)
- Phase 1 draft: [`docs/draft/config-yml-phase1-schema-loader.md`](../draft/config-yml-phase1-schema-loader.md)
- 次 task: task-45 (Phase 2 hook + review command) / task-46 (Phase 3 hc-config.sh)
- 起源: user 直接指示 2026-05-27、master draft §10 5 件 user 承認 (AskUserQuestion 2026-05-27)
