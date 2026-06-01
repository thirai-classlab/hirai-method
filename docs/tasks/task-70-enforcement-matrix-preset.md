---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 7
-->

# Task #70: enforcement matrix / preset 明文化 (Phase 2)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 2 (§4.2)。next-actions #65 (`feature_task_rule_guard_enabled` toggle 意図) を吸収
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.2

## Task ゴール

`harness-config.yml` に preset (`advisory` / `team-default` / `strict` / `harness-dev`) と `enforcement_matrix` が定義され、docs で `BLOCK` と説明する guard と effective config の enabled 状態が一致する (mismatch は `disabled_reason` が無い限り smoke fail)。`hc-config --summary` で「現 preset / 有効 guard / 無効 guard / docs 不一致」が一覧できる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-69 | `enforcement_matrix` も config key として parity 対象。key source の YAML SSoT 化が前提 (matrix table の `--list` / UI 表示が key parity 修正後に正しく出る) | [task-69-hc-config-key-parity.md](task-69-hc-config-key-parity.md) |

## Task 作業概要

- `harness-config.yml` に `enforcement_matrix` を定義 (guard ごとに `feature_key` / `docs_claim` / `events` / `presets` (advisory/team-default/strict/harness-dev) / `disabled_reason`)
- preset 4 種を定義 (advisory=BLOCK 最小 / team-default=重要 guard ON / strict=review・gateguard・workflow 強化 / harness-dev=一部緩和 + 緩和理由明示)
- `hc-config --summary` 実装 (preset / 有効・無効 guard / docs mismatch 件数)
- docs を preset aware に書換 (draft-flow / task-rule / workflow / gateguard / review-required の「常に BLOCK」→「team-default/strict で BLOCK、harness-dev で advisory、現状は `--summary` 参照」)
- mismatch 検出 smoke (mandatory rule wording と feature toggle の不一致、`disabled_reason` 不在で fail)
- **next-actions #65 吸収**: `feature_task_rule_guard_enabled: false` を harness-dev preset の `disabled_reason` として明文化 (「ハーネス自身の task.md 編集を妨げないため」)

## Task 完了条件 (DoD)

- [ ] `enforcement_matrix` + preset 4 種が yml に定義され parity smoke (task-69) を維持
- [ ] `hc-config --summary` が preset / guard 状態 / docs mismatch を出力
- [ ] docs で `BLOCK` 説明の guard と effective enabled 状態が一致 (mismatch smoke green)
- [ ] draft-flow / task-rule / workflow / gateguard / review-required の docs が preset aware に書換
- [ ] 各 disabled guard に `disabled_reason` がある (next-actions #65 の toggle 含む)
- [ ] reviewer approve (テスト設計レビュー)
- [ ] 全 smoke regression 0
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> docs と config の矛盾 (docs は BLOCK と読ませるが config は false) を解消するため、preset (advisory/team-default/strict/harness-dev) + `enforcement_matrix` を定義し docs を preset aware に書換、`--summary` で effective 状態を可視化する。完成すれば「必須と読ませて止めない」危険な中間状態がなくなり、guard の緩和には必ず理由 (disabled_reason) が付き、docs/config の整合が smoke で回帰検出される。

## 背景・目的

draft §3 P1「docs / rules は強制と書くが config では無効」+ §4.2。検証で `feature_draft_flow_guard_enabled` / `feature_task_rule_guard_enabled` / `feature_workflow_enforcement_enabled` / `feature_gateguard_enabled` + `review_required_*` 5 件が全 false を実機確認済。docs は BLOCK と説明するため、遵守が prompt 依存になり docs/config が矛盾する。中間状態が最も危険。

## 設計

draft §4.2「enforcement matrix の具体形」(yaml example: `enforcement_matrix.<guard>.{feature_key,docs_claim,events,presets,disabled_reason}`) + 「`hc-config --summary` の出力案」+ 「docs の書き換え方」(preset aware 文面) を SSoT とする。

## TDD 戦略

### RED
- mismatch 検出 smoke を先に書き、現状 (docs=block / config=false / disabled_reason 不在) で fail させる。

### GREEN
- yml に `enforcement_matrix` + preset 追加、`--summary` 実装、docs 書換 (subagent 委譲、staging 戦略)。

### REFACTOR
- preset 解決ロジックを既存 `is_feature_enabled` と統合 (二重 SSoT 回避)。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `harness-config.yml` に `enforcement_matrix` + preset 4 種を定義 (guard ごとに feature_key/docs_claim/events/presets/disabled_reason) | 0.7h | task-69 |
| 2 | 🔲 | `hc-config --summary` 実装 (preset / 有効・無効 guard / docs mismatch 件数) | 0.6h | Step 1 |
| 3 | 🔲 | docs 書換: CommonRules / workflow.md / task-management.md / development-process.md の「常に BLOCK」記述を preset aware 化 (next-actions #65 toggle の disabled_reason 含む) | 0.7h | Step 1 |
| 4 | 🔲 | mismatch 検出 smoke (mandatory wording vs feature toggle、disabled_reason 不在で fail、対象 draft-flow/task-rule/workflow/gateguard/review-required) | 0.6h | Step 2,3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、docs/config 整合の網羅性 + enforcement 緩和漏れを cross-check | 0.5h | Step 1-4 |
| 6 | 🔲 | (テスト合格) 全 smoke regression 0 (UI なし → unit/integration、`--summary` 出力 + mismatch smoke) | 0.4h | Step 5 |
| 7 | 🔲 | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — preset 解決と is_feature_enabled の統合 | 0.3h | Step 6 |

合計: **~3.8h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/harness-config.yml` (`enforcement_matrix` + preset) + `.claude/scripts/hc-config.sh` (`--summary`) + `.claude/CommonRules.md` / `.claude/rules/{workflow,task-management,development-process}.md` (preset aware 書換) + `.claude/tests/` (mismatch smoke) |
| migration | preset key 追加 (additive)、既存 feature toggle は維持 |
| 環境変数 | 既存 `HC_*` bypass 不変 + preset 選択 env (新、`HC_PRESET` 等) 検討 |
| 互換性 | docs 文面が preset aware に変わる。enforcement の実 enabled 状態は preset で明示制御 (現 false 維持 or team-default で ON 化は preset 既定値で決定、別途 user 判断) |
