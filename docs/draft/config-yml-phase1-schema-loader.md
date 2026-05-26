<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# config-yml Phase 1: yml schema 拡張 + config-loader.sh 拡張

> **master draft**: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md) §3.1 + §3.2.3
> 本 draft は task-44 の Phase 1 spec として固定化、master draft からの抜粋 + Step 計画詳細を持つ。

## §1 真因

master draft §1 参照。本 task は **Phase 1 (yml schema 拡張 + config-loader.sh 拡張)** のみを扱う。yml に新 36 key (feature toggle 21 + review 13) を追加し、`config-loader.sh` に load logic + `is_feature_enabled <name>` 共通関数を追加することで、task-45 (hook feature check) と task-46 (config-editor sh) の基盤を整える。

## §2 採用案

master draft §2 「D ハイブリッド」採用。本 task は Phase 1 単独実装。

## §3 採用案 (実装仕様、master §3.1 + §3.2.3 抜粋)

### 3.1 yml schema 拡張

- 新 36 key 追加: `feature_*_enabled` 21 件 + `review_*_*` 12 件 + `review_iteration_max` 1 件 (詳細値は master §3.1.1 + §3.1.2)
- 既存 key (`reviewer_registry_*` / `workflow_stages_*` / `*_state_dir` 等) は touch しない
- 採用先で既存 yml に新 key 不在でも、hook 内 fallback で default 値使用

### 3.2 config-loader.sh 拡張

- 新 36 key load logic 追加 (既存パーサ仕様: フラット `key: value`)
- `is_feature_enabled <feature_name>` 共通関数追加 (戻り値: 0=enabled / 1=disabled、env override `HC_FEATURE_<NAME>_ENABLED` 優先)
- 既存 hook level env (`HC_<HOOK>_ENABLED`) は subordinate として保持 (backward compat)

## §4 TDD 戦略

新 smoke `.claude/tests/config-feature-toggles-smoke.sh`:

- Case 1: feature toggle ON (yml default + env unset) で `is_feature_enabled foo` exit 0
- Case 2: feature toggle OFF (`HC_FEATURE_FOO_ENABLED=false` env or yml `feature_foo_enabled: false`) で `is_feature_enabled foo` exit 1
- Case 3: 新 key 未設定 (採用先 yml に該当 key 不在) で `is_feature_enabled foo` default ON 動作 (backward compat)

reviewer 制御の smoke は task-45 で扱う (本 task は yml + loader のみ)。

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | `harness-config.yml` に新 36 key 追加 (feature_* 21 + review_* 15) | `grep -cE '^feature_[a-z0-9_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z0-9_]+:' .claude/harness-config.yml` ≥ 15 (digit-inclusive、`feature_why_x5_enforcement_enabled` の `5` 計上) |
| 2 | 🔲 | `config-loader.sh` 拡張 (34 key load + `is_feature_enabled` 関数) | `bash -c 'source .claude/hooks/lib/config-loader.sh && declare -f is_feature_enabled'` で関数存在確認 |
| 3 | 🔲 | smoke `config-feature-toggles-smoke.sh` 新設 (6 cases) | `bash .claude/tests/config-feature-toggles-smoke.sh` 6/6 PASS |
| 4 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列 iter 1+ (yml schema + shell 両軸、subagent 並列) | iter 5 回上限内で収束 (CRITICAL+HIGH+MEDIUM=0) |
| 5 | 🔲 | (テスト合格) 新 smoke + 既存 smoke regression 0 (config-loader 関連) | 新 3 case + 既存 smoke 全 PASS |
| 6 | 🔲 | (リファクタリング) 3 観点判定 (持続可能性 / 汎用性 / 非冗長化) | skip 明示 or 実施 |

## §6 DoD

- [ ] `.claude/harness-config.yml` に新 36 key 追加 (grep 検証 `^feature_[a-z0-9_]+_enabled:` ≥ 21 + `^review_[a-z0-9_]+:` ≥ 15、digit-inclusive)
- [ ] `.claude/hooks/lib/config-loader.sh` で 34 key load + `is_feature_enabled` 関数追加
- [ ] smoke `config-feature-toggles-smoke.sh` 6 cases PASS
- [ ] 既存 smoke regression 0 (config-loader 経由の hook 全件)
- [ ] reviewer iter 5 上限内収束
- [ ] commit + push + PR create (feature branch `feat/config-yml-phase1-schema-loader`)
- [ ] 4 リポ install 案内 (user manual)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/draft/config-yml-phase1-schema-loader.md` / `docs/tasks/task-44-config-yml-phase1-schema-loader.md` / `.claude/tests/config-feature-toggles-smoke.sh` |
| 修正 file | `.claude/harness-config.yml` (新 36 key) / `.claude/hooks/lib/config-loader.sh` (load + 共通関数) |
| 環境変数 | 34 件新規 (`HC_FEATURE_*_ENABLED` 21 + `HC_REVIEW_*_*` 13) |
| 互換性 | 既存 yml 値 touch しない (新 key default 動作)、採用 4 リポ既存 yml 不変 |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (予定) | tdd-guide / test-automator / qa-expert / harness-optimizer / code-reviewer | TBD | TBD | TBD | TBD | 未実施 |

reviewer 5+ 並列 default、yml schema + shell loader の両軸で reviewer 価値あり (skip 不可)。

## §9 関連

- master draft: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md)
- 次 task: task-45 (Phase 2 hook + review command) / task-46 (Phase 3 hc-config.sh)
- 起源: user 直接指示 2026-05-27、master draft §10 5 件 user 承認 (AskUserQuestion 2026-05-27)

## §10 着手前 user 承認

✅ user 承認済 (master draft §10 5 件、AskUserQuestion 2026-05-27)

- scope: 3 task 分割 (task-44/45/46)
- feature toggle 21 件: §3.1.2 案そのまま採用
- hc-config.sh: 対話 menu + CLI args 両方 (task-46 で実装)
