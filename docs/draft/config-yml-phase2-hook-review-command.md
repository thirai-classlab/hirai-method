<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# config-yml Phase 2: hook feature check + review command yml 参照

> **master draft**: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md) §3.2.1 + §3.2.2
> **前提 task**: task-44 (Phase 1: yml schema + config-loader.sh) 完了
> 本 draft は task-45 の Phase 2 spec として固定化、master draft からの抜粋 + Step 計画詳細を持つ。

## §1 真因

master draft §1 参照。本 task は **Phase 2 (hook 21+ 件に feature check + review command 4 件に yml 参照)** のみを扱う。task-44 で yml schema + `is_feature_enabled` 関数が整備された後、各 hook 冒頭で feature toggle 参照、各 review command で reviewer 制御 (required/min/max/iteration) 参照を追加する。

## §2 採用案

master draft §2 「D ハイブリッド」採用。本 task は Phase 2 単独実装。

## §3 採用案 (実装仕様、master §3.2.1 + §3.2.2 抜粋)

### 3.1 hook 21+ 件に feature check 追加

対象 hook (master §3.2.2 引用):
- loop-confirmation-detector / loop-auto-progress-reminder / mode-enforce
- draft-flow-guard / task-rule-guard / list-md-plan-first-reminder
- delegation-guard / workflow-guard / confidence-gate / gateguard
- context-budget / parallel-subagent-reminder / autonomous-action-guard
- byproduct-discharge-guard / next-actions-surface
- why-x5-reminder / why-x5-violation-detect
- session-help-surface / improvement-proposal
- mode-session-start / check-serena-mcp / check-required-env
- init-tasks-on-start / notify / stop / check-md-mermaid / failure-loop-detect

各 hook 冒頭 (config-loader.sh source 直後) に以下追加:

```bash
# Feature toggle 参照 (Phase 2)
if ! is_feature_enabled <name>; then
  exit 0   # feature OFF で no-op
fi
```

実装は staging 戦略 + subagent 並列起動 (file 領域独立、subagent 5+ 並列、test-automator + refactoring-specialist 等動的選定)。

### 3.2 review command 4 件に yml 参照 logic 追加

対象 command:
- `.claude/commands/design-review.md` (W2)
- `.claude/commands/test-design.md` (W1)
- `.claude/commands/module-review.md` (W3)
- `.claude/commands/system-review.md` (W3)

各 command の prompt 冒頭に:

- `HC_REVIEW_REQUIRED_<scope>` = false なら本 command を no-op skip
- `HC_REVIEW_MIN_COUNT_<scope>` = N で reviewer N 件以上を並列起動
- `HC_REVIEW_MAX_COUNT_<scope>` = N で reviewer N 件以下に絞る
- `HC_REVIEW_ITERATION_MAX` = N で反復上限 (default 5)

## §4 TDD 戦略

新 smoke `.claude/tests/review-required-min-count-smoke.sh`:

- Case 1: `review_required_design: false` で `/design-review` no-op skip 確認
- Case 2: `review_min_count_test: 5` で reviewer 5 件以上起動指示確認 (command prompt 解析)
- Case 3: `review_max_count_module: 2` で reviewer 2 件以下絞り込み確認
- Case 4: `review_iteration_max: 3` で反復上限 3 適用確認

hook feature check の smoke は既存 task-44 smoke (`config-feature-toggles-smoke.sh`) を拡張 or 各 hook smoke で個別検証。

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | hook 21+ 件に feature check 追加 (subagent 並列 5-7 件、staging 戦略、各 hook 冒頭 1 行追加) | 全 hook で feature OFF 時 `exit 0` 確認、smoke 経由 |
| 2 | 🔲 | review command 4 件に yml 参照 logic 追加 (design / test / module / system) | 各 command で `HC_REVIEW_REQUIRED_*` 等 4 env 参照記述あり |
| 3 | 🔲 | smoke `review-required-min-count-smoke.sh` 新設 (4 cases) | `bash .claude/tests/review-required-min-count-smoke.sh` 4/4 PASS |
| 4 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列 iter 1+ (hook 21+ + command 4 件の大規模変更、reviewer 価値高い) | iter 5 回上限内で収束 (CRITICAL+HIGH+MEDIUM=0) |
| 5 | 🔲 | (テスト合格) 全 smoke 統合実行 + 既存 smoke regression 0 | 新 4 case + 既存 100+ smoke 全 PASS |
| 6 | 🔲 | (リファクタリング) feature check pattern 共通化 (`config-loader.sh` の関数共通化) + review command 共通 helper 抽出検討 | 3 観点判定 (skip 明示 or 実施) |

## §6 DoD

- [ ] hook 21+ 件に feature check 追加 (各 hook smoke or 統合 smoke で OFF 動作確認)
- [ ] review command 4 件に yml 参照 logic 追加
- [ ] smoke `review-required-min-count-smoke.sh` 4 cases PASS
- [ ] 既存 100+ smoke regression 0
- [ ] reviewer iter 5 上限内収束
- [ ] commit + push + PR create (feature branch `feat/config-yml-phase2-hook-review-command`)
- [ ] 4 リポ install 案内 (user manual)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/draft/config-yml-phase2-hook-review-command.md` / `docs/tasks/task-45-config-yml-phase2-hook-review-command.md` / `.claude/tests/review-required-min-count-smoke.sh` |
| 修正 file | `.claude/hooks/*.sh` (21+ 件 feature check) / `.claude/commands/{design,test,module,system}-review.md` (yml 参照) |
| 環境変数 | task-44 で定義済 34 件を参照、本 task で新規追加なし |
| 互換性 | 既存 hook level env (`HC_<HOOK>_ENABLED`) 維持、新 feature toggle は上位 layer |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (予定) | tdd-guide / test-automator / qa-expert / harness-optimizer / code-reviewer + refactoring-specialist | TBD | TBD | TBD | TBD | 未実施 |

reviewer 5+ 並列 default、hook 21+ + command 4 件の大規模変更で reviewer 価値高い (skip 不可)。

## §9 関連

- master draft: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md)
- 前提 task: task-44 (Phase 1)
- 次 task: task-46 (Phase 3 hc-config.sh)
- 起源: user 直接指示 2026-05-27

## §10 着手前 user 承認

✅ user 承認済 (master draft §10 5 件、AskUserQuestion 2026-05-27)
