---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #100: yml triplet pre-commit (key+consumer+smoke 同 commit BLOCK) (P3-3/I7/W2-9)

> Status: **🔲 未着手**
> 起案: 2026-07-07 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I7 / §5 P3-3
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I7 + §5 P3-3

## Task ゴール

`.claude/templates/githooks/pre-commit` に yml triplet policy layer 追加。pre-commit が `harness-config.yml` の diff から新規 key (`feature_*_enabled` / `<key>: <value>` の追加) を検出し、consumer (該当 key を Read する hook or script) + smoke (該当 key を試験する `.claude/tests/*-smoke.sh`) の存在を grep で検証。三点揃わない状態で commit → `BLOCK` + `emit_block_pretool` で 3 点提示。完成すれば新規 config 値追加が必ず consumer + smoke を同 commit に含み、値が「飾り化」(memory [[feedback_config_value_needs_consumer_and_smoke]] 実証、task-44 事案) しなくなる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-92 | **hard**。task-92 で配布された pre-commit template (`.claude/templates/githooks/pre-commit`) が本 task の grep policy layer 追加の base | [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) |
| task-94 | **soft**。task-94 で追加された emit_block_pretool を本 task の BLOCK 出力に使用 | [task-94-lib-block-message-4args.md](task-94-lib-block-message-4args.md) |

## Task 作業概要

- `.claude/templates/githooks/pre-commit` に §4.5 yml triplet policy layer 追加 (`harness-config.yml` diff → 新規 key 抽出 → consumer + smoke grep → 不足で BLOCK)
- Bypass env: `HC_YML_TRIPLET_CHECK_ENABLED=false` / `ECC_YML_TRIPLET_OFF=1`
- 新規 smoke `.claude/tests/yml-triplet-pre-commit-smoke.sh` 5 case (A-E: key+consumer+smoke 三点揃 / consumer 不在 BLOCK / smoke 不在 BLOCK / bypass / 既存 key 通過)
- `.claude/hooks/lib/config-loader.sh` に `HC_YML_TRIPLET_CHECK_ENABLED` toggle 追加
- harness-config.yml に `feature_yml_triplet_check_enabled: true` + enforcement_matrix entry
- docs 反映

## Task 完了条件 (DoD)

- [ ] pre-commit template に yml triplet 検出 code 存在: `grep -c 'yml.*triplet\|_yml_new_key_check' .claude/templates/githooks/pre-commit >= 1`
- [ ] 新規 key 追加 + consumer/smoke 不在 → BLOCK 動作確認 (smoke Case B/C)
- [ ] Bypass env 動作: `HC_YML_TRIPLET_CHECK_ENABLED=false` / `ECC_YML_TRIPLET_OFF=1`
- [ ] `yml-triplet-pre-commit-smoke.sh` 5/5 PASS
- [ ] Wave 1-4 全 smoke regression 0
- [ ] enforcement_matrix に `yml_triplet_check` guard 登録 (5 field 全備)
- [ ] docs 反映: `.claude/rules/development-process.md` §「I7 triplet」+ `docs/INVENTORY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

yml 飾り key (定義のみで consumer/smoke 不在) を解消するため pre-commit で yml diff 新規 key を抽出し consumer + smoke 存在を grep BLOCK する。完成すれば新規 config 値追加が必ず consumer + smoke を同 commit に含み値が飾り化しなくなる。

## Step 計画 (SSoT: master roadmap §5 P3-3 + §3 I7)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | pre-commit template に §4.5 yml triplet layer 追加 (harness-config.yml diff → 新規 key → consumer/smoke grep) | 4h | — |
| 2 | 🔲 | harness-config.yml + metadata + config-loader.sh の 3 点 set (feature_yml_triplet_check_enabled) | 1.5h | Step 1 |
| 3 | 🔲 | 新規 smoke `yml-triplet-pre-commit-smoke.sh` 5 case + run-all-smokes 登録 (portability) | 3h | Step 1, 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h | Step 3 |
| 5 | 🔲 | (テスト合格) 全 smoke PASS | 1h | Step 4 |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or skip 明示 | 0.5h | Step 5 |

合計: 11.5h ≒ 1.4 day (roadmap 2 day 見積内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-07 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済、docs/tasks/task-100-*.md 生成、list.md #100 📝 → 🔲 update |
| 2026-07-08 | 完了 | Wave 5 Workflow wf_070a6dcf-dc2 経由。pre-commit template §4.5 yml triplet layer 追加 (`_run_yml_triplet_check()` subshell 関数、awk hunk 単位で新規 top-level key 抽出、consumer + smoke grep BLOCK、bypass 2 系統 HC_YML_TRIPLET_CHECK_ENABLED=false / ECC_YML_TRIPLET_OFF=1) + yml-triplet-pre-commit-smoke 5/5 PASS (A 三点揃 / B consumer 不在 BLOCK / C smoke 不在 BLOCK / D bypass / E 既存 key modification 通過)。feature_yml_triplet_check_enabled toggle + matrix 26 guards に yml_triplet_check 登録。Step 1-6 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) 既存 yml 飾り key の一括 audit script — Step 5 で判定
- [ ] (🟢) consumer/smoke grep pattern の false positive 軽減 (task-101 iter-min-3 のような meta key 特例) — Step 4 review で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I7 + §5 P3-3
- 起源 memory: [[feedback_config_value_needs_consumer_and_smoke]] (task-44 事案)
- 依存 task (hard): [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) (pre-commit template base)
