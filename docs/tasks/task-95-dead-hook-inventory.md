---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #95: 死蔵 hook 3 件個別判定 + enforcement_matrix 登録 (P2-4/W1-1)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり 3 hook 個別判定採用、`mode_enforce` は集合 1 entry `hooks_covered` 記法採用)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §5 P2-4 (W1-1) / §11.3 R3
> 設計起源: [dead-hook-inventory.md](../draft/dead-hook-inventory.md)

## Task ゴール

`.claude/harness-config.yml` の `enforcement_matrix` に 3 新規 entry (`tool_call_slip_detect` / `asana_prompt` / `loop_mode_enforcement` = 集合 1 entry + `hooks_covered` sub-field) が追加され、H2 用 feature toggle 3 点 set (`feature_asana_prompt_enabled` = yml key + config-loader default + hook 冒頭 check) が新設される。`.claude/tests/dead-hook-inventory-smoke.sh` 6 case (DHI-1〜6) が「3 hook 個別判定結果が matrix に登録され、fire 実績 log / feature toggle 現値 / 現 preset 期待値が整合する」ことを機械保証する。task-97 (P2-6) の残 scope (matrix 未登録 hook の残集合) が本 task 完遂で確定する (addendum §11.3 R3 順序制約)。

## Task 依存先タスク

— (依存なし、task-88 = P1-4 SessionStart `--summary` 全文注入は PR #71 で完了済)

Phase 1 資産 (task-88 の SessionStart summary) が完了済のため本 task は独立着手可。task-97 (P2-6) が本 task を **hard 依存**として明記済 (残 scope 確定のため、addendum §11.3 R3 順序制約 #97→#95)。

## Task 作業概要

- `.claude/harness-config.yml` enforcement_matrix に 3 新規 entry 追加 (§3.1.a-c)
- `feature_asana_prompt_enabled` の 3 点 set 実装 (yml key + config-loader default+export + hook 冒頭 `is_feature_enabled asana_prompt` check)
- `.claude/tests/dead-hook-inventory-smoke.sh` 新設 (DHI-1〜6 の 6 case、`enforcement-mismatch-smoke.sh` の subshell isolation pattern 踏襲)
- `run-all-smokes.sh` に新 smoke 登録 (parity カテゴリ、`_get_smoke_category` L46-89 拡張)
- docs 反映 (README / docs/INVENTORY のいずれか 1 file 以上に `dead-hook-inventory` pointer)

## Task 完了条件 (DoD)

- [ ] enforcement_matrix に 3 新 entry 存在 (`tool_call_slip_detect` / `asana_prompt` / `loop_mode_enforcement`): `awk '/^enforcement_matrix:/,/^[^ ]/' .claude/harness-config.yml | grep -Ec '^  (tool_call_slip_detect|asana_prompt|loop_mode_enforcement):'` == **3**
- [ ] 3 新 entry の必須 field (`feature_key` / `docs_claim` / `events` / `presets`) が全て非空 (smoke DHI-2 PASS)
- [ ] `feature_asana_prompt_enabled` の 3 点 set 完備 (yml key + config-loader default + hook 冒頭 check の各 grep 1 hit)
- [ ] `hc-config.sh --summary` に 3 新 guard 名が表示 (grep 3 以上)
- [ ] 新 smoke `dead-hook-inventory-smoke.sh` 6 case 全 PASS
- [ ] 既存 `enforcement-mismatch-smoke.sh` regression 0
- [ ] `run-all-smokes.sh` に新 smoke 登録 (parity カテゴリ) + 全体 regression 0
- [ ] `HC_FEATURE_ASANA_PROMPT_ENABLED=false bash .claude/hooks/mode-asana-prompt.sh < /dev/null` が silent exit 0 (feature toggle 動作確認)
- [ ] docs 反映 (`grep -c 'dead-hook-inventory' README.md docs/INVENTORY.md 2>/dev/null` >= 1)
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

I2 (Dispatcher-Only Hook) invariant の完全化と 3 死蔵 hook (slip-detector / mode-asana-prompt / mode-enforce) の docs↔effective 可視性欠落を解消するため、enforcement_matrix に 3 新 entry (slip-detector 温存 advisory / asana_prompt 全 preset true + feature 3 点 set 新設 / loop_mode_enforcement 集合 1 entry + `hooks_covered`) を登録し新規 smoke 6 case で機械保証する。完成すれば 3 hook 全てが `hc-config.sh --summary` で CLI 可視化され、task-97 (P2-6) の残 scope (matrix 未登録 hook の残集合) が本 task 完遂で確定するようになる。

## Step 計画 (SSoT: draft §6 「Step 分解」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `harness-config.yml` enforcement_matrix に 3 新 entry (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) 追加 + 各 disabled_reason 記入 (§3.1.a-c 参照、pointer 分離で GC 耐性) | 0.5h | — |
| 2 | 🔲 | `feature_asana_prompt_enabled` 3 点 set 実装 (yml key / config-loader default + export / hook 冒頭 `is_feature_enabled asana_prompt` check) | 0.5h | Step 1 |
| 3 | 🔲 | `.claude/tests/dead-hook-inventory-smoke.sh` 新設 (DHI-1〜6 の 6 case、`enforcement-mismatch-smoke.sh` の subshell isolation pattern 踏襲、bypass.log 不在時 DHI-4/5 skip fail-open) | 1.0h | Step 1, 2 |
| 4 | 🔲 | `run-all-smokes.sh` に新 smoke 登録 (parity カテゴリ、`_get_smoke_category` L46-89 拡張) + `hc-config.sh --summary` に新 3 guard 表示確認 | 0.5h | Step 3 |
| 5 | 🔲 | docs 反映 (`README.md` / `docs/INVENTORY.md` に P2-4 完遂 pointer、`.claude/CommonRules.md` は該当なし = skip) | 0.3h | Step 4 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (`hc-config.sh --get review_max_count_test` 確認、config-domain 加味)、reviewer prompt 5 必須項目 (project 整合性 + 他 task 影響確認 含む) 全採用 | 0.5h | Step 5 |
| 7 | 🔲 | (テスト合格) 全 smoke PASS (DoD-2〜7 全項目 検証コマンド実行、UI 変更 0 のため E2E/visual 対象外) | 0.5h | Step 6 |
| 8 | 🔲 | (リファクタリング) 3 観点判定 (matrix entry 共通構造抽出 lib / smoke DHI-2 の 12 field 抽出 loop 化 検討)、不要なら `skip: <reason>` 明示 | 0.3h | Step 7 |

合計: 4.1h (roadmap P2-4 見積 1 day 内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/dead-hook-inventory.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり 3 hook 個別判定 = 案 A 採用、`mode_enforce` は集合 1 entry + `hooks_covered` 記法採用、`feature_asana_prompt_enabled` 3 点 set 新設承認) |
| 2026-07-06 | タスク化 | `/new-task 95 dead-hook-inventory`、list.md #95 📝 → 🔲 update、docs/tasks/task-95-*.md 生成 |

## 派生 task / 次アクション候補

Draft §8 副産物 candidate:

- [ ] (🟢) matrix advisory 共通 template lib 抽出候補 (Step 8 refactor で判定)
- [ ] (🟢) smoke DHI-4/5 の bypass.log path SSoT lib 化候補
- [ ] (🟡) enforcement_matrix schema 拡張 (`hooks_covered` optional field の top-level schema 昇格 + `enforcement-matrix-parse.sh` の parser 契約明記) — task-70 系列の別 task として next-actions.md へ append (reviewer finding 由来、本 task 承認後 main agent が実行)

## 関連

- Draft: [dead-hook-inventory.md](../draft/dead-hook-inventory.md)
- 前提 (完了済): task-70 Phase 2 (enforcement preset + `enforcement_matrix.disabled_reason`) / task-85 (advisory disabled_reason 追記) / task-88 (SessionStart `--summary` 全文注入、PR #71)
- 後続 (Phase 2 依存): [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) (P2-6、本 task **hard 依存**、addendum §11.3 R3 順序制約)
