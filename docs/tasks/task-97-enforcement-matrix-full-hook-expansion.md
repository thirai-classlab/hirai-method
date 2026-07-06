---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #97: enforcement_matrix 全 hook 拡張 (残 scope 明確化、task-95 + task-96 hard 依存) (P2-6/W2-2)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり task-95 hard 依存 + task-96 hard 依存化採用、Case 2 semantics = 現状維持推奨)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §5 P2-6 (W2-2) / §11.3 R3 (最重要) / §11.3 R6 (依存明示) / §11.3 R4 (副産物 #81 吸収候補)
> 設計起源: [enforcement-matrix-full-hook-expansion.md](../draft/enforcement-matrix-full-hook-expansion.md)

## Task ゴール

task-95 完了後の hook 分類 (slip-detector / mode-asana-prompt / mode-enforce 個別判定) + task-96 完了後の追加 feature toggle (`feature_agent_router_llm_fallback_enabled`) を受けて enforcement_matrix を全対象 hook まで拡張し、`enforcement-mismatch-smoke.sh` の対象集合を同期更新し、副産物 next-actions #81 (`sessionstart-footprint-smoke` FP-7 fail-open dedicated case + FP-5 label 厳密化) を fold して「全 hook の docs_claim + preset 期待 + disabled_reason が宣言済」状態を達成する。task-102 (P3-5) draft 起案時に #81 fold 重複回避の cross-check 契約が確立される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-95 | **hard**。matrix 追加登録 hook set が本 task 着手時に確定している必要 (§11.3 R3 順序制約 #97→#95)。task-95 §DoD 分類 table を Step 1 で必ず Read し、`mode_enforce` の集合登録判定 (案 a / 案 b) を task-95 が確定した結果に従う | [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) |
| task-96 | **hard**。task-96 で追加される新 feature toggle 1 件 (`feature_agent_router_llm_fallback_enabled`) が matrix 登録候補として本 task 実施時に確定している必要。残 2 key (`agent_router_llm_budget_usd_per_day` / `agent_router_llm_similarity_threshold`) は Gate/Confidence カテゴリで matrix 対象外を明示 (§3 Step 1) | [task-96-agent-router-llm-fallback-toggle.md](task-96-agent-router-llm-fallback-toggle.md) |

## Task 作業概要

- task-95 分類結果 + task-96 追加 3 key を Read し matrix 追加登録候補 hook set を確定 (Step 1)
- `.claude/harness-config.yml` enforcement_matrix に追加登録 (guard block ごとに `feature_key` / `docs_claim` / `events` / `presets` / `disabled_reason` 5 field 全備)
- `enforcement-mismatch-smoke.sh` の `required` set (現行 8 guard hardcode) を Step 2 で追加された guard 群まで拡張 + 副産物 #81 (FP-7 / FP-5 厳密化) を smoke case として追加
- task-102 (P3-5) draft との fold 重複 cross-check (task-102 draft 起案が先行している場合は §吸収先 entry を確認、未起案時は本 task PR 説明文 + next-actions.md #81 コメント列に運用義務追記)
- docs 反映 (`docs/INVENTORY.md` matrix guard 表 + `.claude/rules/workflow.md` §「workflow-guard.sh」pointer)

## Task 完了条件 (DoD)

- [ ] task-95 で確定した hook 分類 (slip-detector / mode-asana-prompt / mode-enforce) 全件が enforcement_matrix に登録済 (`grep -cE "^  (tool_call_slip_detect|mode_asana_prompt|mode_enforce):" .claude/harness-config.yml >= 3` or task-95 分類に一致する count)
- [ ] Step 1 で確定した matrix 追加登録 hook 全件が 5 field 全備 (Case 4 feature_key 実在 + Case 5 disabled_reason 網羅 PASS)
- [ ] enforcement-mismatch-smoke.sh の Case 2 が拡張後の guard 集合を verify (semantics 判断 = 現状維持 (最小必須 guard 存在確認) or 緩和 (matrix 実登録 N 件以上) は Step 1 で確定)
- [ ] 副産物 #81 FP-7 fail-open dedicated case が `sessionstart-footprint-smoke.sh` に追加 (mutation probe: FP-7 assert 削除で smoke 全 PASS 継続なら FAIL)
- [ ] #81 FP-5 label 厳密化 (`[0-9]+ enabled, [0-9]+ disabled` field 数検証) 完了
- [ ] `docs/tasks/next-actions.md` #81 entry の処理結果列を `🔄 未処理` → `✅ → task-97 (<PR#>) 完了` に更新
- [ ] task-102 (P3-5) draft との fold 重複 cross-check 完了 (task-102 draft 起案済なら §吸収先 grep で `task-97` ≥ 1、未起案なら次 draft 起案時 confirm 運用義務を next-actions.md #81 コメント列に追記)
- [ ] 本 repo (harness-dev) の `enforcement-mismatch-smoke.sh` 全 case PASS 維持 (regression 0)
- [ ] 全 smoke regression 0 (`bash .claude/tests/run-all-smokes.sh` PASS)
- [ ] docs 反映: `docs/INVENTORY.md` matrix guard 表 + `.claude/rules/workflow.md` §「workflow-guard.sh」pointer 更新
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

matrix 未登録 hook が docs↔effective 乖離を残し `enforcement-mismatch-smoke` が false negative を返す状態を解消するため、task-95 で確定した死蔵 hook 分類 + task-96 で追加された agent-router LLM feature toggle を受けて enforcement_matrix を全対象 hook まで拡張し smoke `required` set 同期更新 + 副産物 #81 fold を行う。完成すれば全 guard の docs_claim + preset 期待 + disabled_reason が宣言され `enforcement-mismatch-smoke` が全 hook を verified 状態にできるようになる。

## Step 計画 (SSoT: draft §3 「Step 計画」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | task-95 分類結果 + task-96 3 key を Read し matrix 追加登録 hook set を確定 (temporarily list) + Case 2 semantics 判断 (現状維持 or 緩和) 確定 | 0.5h | task-95, task-96 merge |
| 2 | 🔲 | `.claude/harness-config.yml` enforcement_matrix に追加登録 (guard block ごとに 5 field 記載、既存 8 guard の schema を SSoT template として踏襲) | 2.0h | Step 1 |
| 3 | 🔲 | `enforcement-mismatch-smoke.sh` の `required` set (現行 8 guard hardcode) を Step 2 追加 guard 群まで拡張 + 副産物 #81 (FP-7 + FP-5 厳密化) を smoke case として追加 + task-102 draft 起案 timing で #81 fold 重複 cross-check 契約明示 | 1.5h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (`hc-config.sh --get review_max_count_test` 上限確認、shell/yaml domain 加味) | 0.5h | Step 3 |
| 5 | 🔲 | (テスト合格) `enforcement-mismatch-smoke.sh` (拡張後全 case) + `sessionstart-footprint-smoke.sh` (FP-7 追加後) + 既存 smoke regression 0 (UI 変更 0 のため E2E/visual 対象外) | 0.5h | Step 4 |
| 6 | 🔲 | (リファクタリング) 3 観点 (`_matrix_field` / `em_field` DRY 再評価)、不要なら `skip: <reason>` 明示 | 0.3h | Step 5 |

合計: 5.3h (roadmap P2-6 見積 1 day = 8h に対し -2.7h、enforcement_matrix schema 既存確立 + task-95/96 分類確定の 2 前提が効いている)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/enforcement-matrix-full-hook-expansion.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり案 A 採用 = task-95 完了後着手 + task-96 追加 toggle 1 件 matrix 登録 + `mode_enforce` は集合 1 entry + `hooks_covered` 記法 + Case 2 semantics 現状維持 + #81 fold = P2-6 に集約 + task-102 cross-check 契約明示) |
| 2026-07-06 | タスク化 | `/new-task 97 enforcement-matrix-full-hook-expansion`、list.md #97 📝 → 🔲 update + 依存列 = `task-95, task-96` 維持、docs/tasks/task-97-*.md 生成 |

## 派生 task / 次アクション候補

Draft §未決事項 + §関連からの初期 candidate:

- [ ] (🟡) enforcement_matrix schema 拡張追跡 (`hooks_covered` optional field の top-level schema 昇格 + `enforcement-matrix-parse.sh` parser 契約明記) — task-70 系列の別 task、task-95 §派生 candidate と同一 (重複 dedupe: task-95 側で管理)
- [ ] (🟢) 未登録 hook のうち `stale-harness-detect` (F WARN 誘導系、AI 教育効果あり) の matrix 登録優先度 — Step 1 で task-95/96 分類外 hook も本 task で判定 (全 hook 網羅方針)

## 関連

- Draft: [enforcement-matrix-full-hook-expansion.md](../draft/enforcement-matrix-full-hook-expansion.md)
- 依存 task (hard):
  - [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) (P2-4 死蔵 hook 棚卸し、matrix 追加登録 hook set 確定に必要)
  - [task-96-agent-router-llm-fallback-toggle.md](task-96-agent-router-llm-fallback-toggle.md) (P2-5 agent-router LLM fallback toggle、追加 feature toggle 1 件の matrix 登録判定に必要)
- 逆方向 cross-check task: task-102 (未起案 draft、P3-5 install smoke 自動化) — 副産物 #81 fold 重複回避 (§3 Step 3b + §6 DoD、task-102 draft 起案 timing で main agent が本 draft と cross-check)
- 前提 (完了済): task-70 Phase 2 (enforcement_matrix schema 定義) / task-85 Wave 1 (8 guard 定義 + advisory disabled_reason 追記、PR #68 merge 済) / task-84 (F WARN 誘導 / npx 経路)
- 副産物: [next-actions #81 (sessionstart-footprint FP-7 + FP-5)](next-actions.md) を本 task で吸収
- 関連 memory: [[feedback_config_value_needs_consumer_and_smoke]] (I7 triplet 起源) / [[feedback_design_external_dependency_verification]] (外部依存の起案時存在確認)
