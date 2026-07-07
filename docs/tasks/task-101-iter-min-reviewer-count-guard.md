---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #101: iter_min:3 規範化 + reviewer-count-guard 拡張 (P3-4/I8/W2-8)

> Status: **🔲 未着手**
> 起案: 2026-07-07 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I8 / §5 P3-4
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I8 + §5 P3-4

## Task ゴール

`.claude/harness-config.yml` に `review_iteration_min: 3` を default 追加し、`.claude/rules/workflow.md` §「テスト設計レビュー / 設計レビュー」に「iter 3 未達 closure 禁止」を明文化。`.claude/hooks/reviewer-count-guard.sh` (task-64 実装) を拡張して iter_min:3 未達での /finish-task を advisory 警告注入。加えて `.claude/tests/enforcement-mismatch-smoke.sh` に「min/max/採用 6 条 4 上限 5 の 3 点一致」検証 case を追加。完成すれば review が最低 3 iter 回り iter 後半の新規 CRIT 検出 (memory [[feedback_iter_fix_introduces_new_crit_pattern]] 実証) が担保される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-97 | **hard**。task-97 で拡張された enforcement_matrix (23 guards) と本 task の reviewer-count-guard (feature_reviewer_count_guard_enabled) の schema 整合が前提。同じく matrix の disabled_reason 更新に affect | [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) |

## Task 作業概要

- `harness-config.yml` に `review_iteration_min: 3` default + metadata TSV 登録
- `.claude/rules/workflow.md` §「テスト設計レビュー」+ §「設計レビュー」に「iter 3 未達 closure 禁止」明文化
- `.claude/rules/task-management.md` 採用 6 条 4 (テスト設計レビュー Step) に iter_min:3 追記
- `.claude/hooks/reviewer-count-guard.sh` 拡張 (iter 実行 count 検出 + iter_min:3 未達で advisory warn 注入)
- `.claude/tests/enforcement-mismatch-smoke.sh` に Case 6 (min/max/採用 6 条 4 上限 5 の 3 点一致検証) 追加
- 新規 smoke `.claude/tests/iter-min-3-smoke.sh` (case A-C、iter 1/2/3 実行時の guard 動作)

## Task 完了条件 (DoD)

- [ ] `harness-config.yml` に `review_iteration_min: 3` 存在 + metadata TSV 登録 + config-loader.sh default + export
- [ ] `bash .claude/scripts/hc-config.sh --get review_iteration_min` が `3` を返す
- [ ] `.claude/rules/workflow.md` に「iter 3 未達 closure 禁止」grep hit >= 1
- [ ] `.claude/rules/task-management.md` 採用 6 条 4 に iter_min:3 追記 grep hit >= 1
- [ ] `reviewer-count-guard.sh` 拡張 (現在 min/max のみ検証 → iter_count も検証)
- [ ] `enforcement-mismatch-smoke` Case 6 追加 + 6/6 PASS
- [ ] `iter-min-3-smoke.sh` 3/3 PASS
- [ ] Wave 1-3 全 smoke regression 0
- [ ] docs 反映: `docs/INVENTORY.md` 追記
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

iter cycle が偽収束する問題 (iter N fix が N+1 で新規 CRIT 導入) を解消するため review_iteration_min:3 未達 closure 禁止を規範化し min/max/採用 6 条 4 上限 5 の 3 点一致を enforcement-mismatch-smoke で検証する。完成すれば review が最低 3 iter 回り iter 後半の新規 CRIT 検出が担保される。

## Step 計画 (SSoT: master roadmap §5 P3-4 + §3 I8)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `harness-config.yml` + metadata + config-loader.sh の 3 点 set (review_iteration_min:3) | 2h | — |
| 2 | 🔲 | `.claude/rules/workflow.md` + `.claude/rules/task-management.md` に iter_min:3 規範追加 | 2h | Step 1 |
| 3 | 🔲 | `.claude/hooks/reviewer-count-guard.sh` 拡張 (iter_count 検証) | 3h | Step 1 |
| 4 | 🔲 | `enforcement-mismatch-smoke.sh` Case 6 + 新 smoke `iter-min-3-smoke.sh` 3 case | 3h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h | Step 4 |
| 6 | 🔲 | (テスト合格 + リファクタリング) 全 smoke PASS + 3 観点判定 | 1.5h | Step 5 |

合計: 13h ≒ 1.6 day (roadmap 2 day 見積内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-07 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済、docs/tasks/task-101-*.md 生成、list.md #101 📝 → 🔲 update |
| 2026-07-07 | 完了 | Wave 4 Workflow wf_94c193f7-246 経由。review_iteration_min: 3 default 追加 (harness-config.yml + metadata + config-loader.sh 3 点 set) + reviewer-count-guard.sh 拡張 (iter_count 検出 + advisory warn 注入) + iter-min-3-smoke 3/3 PASS + enforcement-mismatch-smoke Case 6 追加 (matrix 25 guards 検証、6/6 PASS)。.claude/rules/workflow.md + task-management.md に iter_min:3 未達 closure 禁止 規範明文化。harness-config.local.yml も review_iteration_max: 2 → 5 に更新 (iter_min:3 ≤ max 制約対応)。Step 1-6 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) 既存 review iter cycle の再 audit (iter 1-2 で closure された過去 task) — Step 3 で判定
- [ ] (🟢) iter_min:3 の "3 は magic number か 経験値か" 定量化 script (task-46 iter cycle 実測データ) — Step 6 で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I8 + §5 P3-4
- 起源 memory: [[feedback_iter_fix_introduces_new_crit_pattern]] (task-61 iter 3 実証) / [[feedback_config_value_needs_consumer_and_smoke]] (I7 triplet)
- 依存 task (hard): [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) (matrix schema 整合)
