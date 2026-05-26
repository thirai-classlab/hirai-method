# Task 44: config-yml Phase 1 (yml schema 拡張 + config-loader.sh)

> **Status**: 🔄 進行中 (2026-05-27 着手)
> **Branch**: `feat/config-yml-phase1-schema-loader`
> **Draft**: [`docs/draft/config-yml-phase1-schema-loader.md`](../draft/config-yml-phase1-schema-loader.md)
> **Master draft**: [`docs/draft/config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)

## Task ゴール

`.claude/harness-config.yml` に新 34 key (feature toggle 21 件 + review 制御 13 件) を追加し、`.claude/hooks/lib/config-loader.sh` に load logic + `is_feature_enabled <name>` 共通関数を追加する。task-45 (hook feature check) と task-46 (config-editor sh) の基盤を整える。

## Task 作業概要

- yml schema 拡張: 新 34 key (`feature_*_enabled` 21 + `review_*_*` 12 + `review_iteration_max` 1) 追加
- config-loader.sh 拡張: 34 key load logic + `is_feature_enabled <name>` 共通関数 (戻り値 0/1、env override 優先)
- smoke 新設: `config-feature-toggles-smoke.sh` 3 cases (ON / OFF / 未設定 backward compat)
- reviewer 5+ 並列 iter 収束 + 既存 smoke regression 0
- commit + push + PR create + 4 リポ install 案内 (user manual)

## Task 完了条件 (DoD)

- [ ] `.claude/harness-config.yml` に新 34 key 追加 (`grep -cE '^feature_[a-z_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z_]+:' .claude/harness-config.yml` ≥ 13)
- [ ] `.claude/hooks/lib/config-loader.sh` で 34 key load + `is_feature_enabled` 関数追加 (`declare -f is_feature_enabled` で関数存在確認)
- [ ] smoke `.claude/tests/config-feature-toggles-smoke.sh` 3 cases PASS
- [ ] 既存 smoke regression 0 (config-loader 経由の全 hook smoke)
- [ ] reviewer iter 5 上限内収束 (CRITICAL+HIGH+MEDIUM=0)
- [ ] PR create (`feat/config-yml-phase1-schema-loader`)
- [ ] 4 リポ install 案内 (user manual)

## Task 概要欄 (list.md 用、3 要素)

feature toggle と reviewer 制御の yml 化基盤を整えるため、`harness-config.yml` に新 34 key 追加し `config-loader.sh` に load logic + `is_feature_enabled` 共通関数を追加する。完成すれば task-45/46 が yml 経由で feature toggle と reviewer 制御を参照できるようになる。

## Task 依存先タスク

依存なし (—)

## Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | `harness-config.yml` に新 34 key 追加 (feature_* 21 + review_* 13) | `grep -cE '^feature_[a-z_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z_]+:' .claude/harness-config.yml` ≥ 13 |
| 2 | 🔲 | `config-loader.sh` 拡張 (34 key load + `is_feature_enabled` 関数) | `bash -c 'source .claude/hooks/lib/config-loader.sh && declare -f is_feature_enabled'` で関数存在確認 |
| 3 | 🔲 | smoke `config-feature-toggles-smoke.sh` 新設 (3 cases) | `bash .claude/tests/config-feature-toggles-smoke.sh` 3/3 PASS |
| 4 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列 iter 1+ (yml schema + shell 両軸、subagent 並列) | iter 5 回上限内で収束 (CRITICAL+HIGH+MEDIUM=0) |
| 5 | 🔲 | (テスト合格) 新 smoke + 既存 smoke regression 0 (config-loader 関連) | 新 3 case + 既存 smoke 全 PASS |
| 6 | 🔲 | (リファクタリング) 3 観点判定 (持続可能性 / 汎用性 / 非冗長化) | skip 明示 or 実施 |

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
| 修正 file | `.claude/harness-config.yml` (新 34 key) / `.claude/hooks/lib/config-loader.sh` (load + 共通関数) |
| 環境変数 | 34 件新規 (`HC_FEATURE_*_ENABLED` 21 + `HC_REVIEW_*_*` 13) |
| 互換性 | 既存 yml 値 touch しない (新 key default 動作)、採用 4 リポ既存 yml 不変 |

## レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (予定) | tdd-guide / test-automator / qa-expert / harness-optimizer / code-reviewer | TBD | TBD | TBD | TBD | 未実施 |

reviewer 5+ 並列 default、yml schema + shell loader 両軸で reviewer 価値あり (skip 不可)。

## 関連

- master draft: [`docs/draft/config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)
- Phase 1 draft: [`docs/draft/config-yml-phase1-schema-loader.md`](../draft/config-yml-phase1-schema-loader.md)
- 次 task: task-45 (Phase 2 hook + review command) / task-46 (Phase 3 hc-config.sh)
- 起源: user 直接指示 2026-05-27、master draft §10 5 件 user 承認 (AskUserQuestion 2026-05-27)
