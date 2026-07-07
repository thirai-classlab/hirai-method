---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #99: lib/observability.sh + 30 日 GC + fire 0 回 hook 棚卸し (P3-2/I5/W2-7)

> Status: **🔲 未着手**
> 起案: 2026-07-07 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I5 / §5 P3-2
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I5 + §5 P3-2

## Task ゴール

`.claude/hooks/lib/observability.sh` 新設 (BLOCK / bypass / fire / silent failure イベントを 4 種の event kind で log append する 5 関数 API)。全 hook + self-doctor + smoke runner が本 lib source 経由で構造化 log を吐き、`observations.jsonl` の event kind coverage が完成する。加えて 30 日 GC (`.claude/scripts/observability-gc.sh`) + fire 0 回 hook 棚卸し (`bash .claude/scripts/hook-fire-audit.sh` で `--days 30` 期間内で 1 度も fire していない hook を検出) を実装。完成すれば silent failure が全件 log 経由で観測可能になり、死蔵 hook が数値根拠で棚卸しできる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-95 | **soft**。task-95 で確定した 3 死蔵 hook (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) の判定精度を数値化 (30 日 fire 0 回数) するための metric source | [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) |
| task-94 | **soft**。task-94 の lib/block-message.sh と本 lib の設計 pattern (subshell 関数化 + jq fallback + 4 args) を統一 | [task-94-lib-block-message-4args.md](task-94-lib-block-message-4args.md) |

## Task 作業概要

- `.claude/hooks/lib/observability.sh` 新設 (5 関数 = `log_block` / `log_bypass` / `log_fire` / `log_silent_failure` / `log_event`、共通 4-5 args = `<event_kind> <hook_name> <reason> [payload_json]`、subshell 関数化 + jq fallback)
- 主要 hook (gateguard / task-rule-guard / workflow-guard / autonomous-action-guard / confidence-gate / byproduct-discharge-guard / draft-flow-guard / delegation-guard) に log_* 呼出を追加
- `.claude/scripts/observability-gc.sh` 新設 (`observations.jsonl` の 30 日超え entry を archive dir に移動、`.claude/observability/archive/YYYY-MM.jsonl` 形式)
- `.claude/scripts/hook-fire-audit.sh` 新設 (最終 N 日間で fire 0 回の hook を検出、`--days` / `--json` / `--verbose` オプション)
- 新規 smoke `.claude/tests/lib-observability-smoke.sh` (5 case A-E) + `.claude/tests/hook-fire-audit-smoke.sh` (3 case A-C)

## Task 完了条件 (DoD)

- [ ] `.claude/hooks/lib/observability.sh` 存在 + 5 API: `source ...; declare -f log_block log_bypass log_fire log_silent_failure log_event | wc -l >= 5`
- [ ] 主要 8 hook が log_* を呼出済: `grep -l 'lib/observability.sh' .claude/hooks/*.sh | wc -l >= 8`
- [ ] `.claude/scripts/observability-gc.sh` 存在、`--dry-run` で 30 日超え entry の一覧提示 + `--apply` で archive 移動
- [ ] `.claude/scripts/hook-fire-audit.sh` 存在、`--days 30` で fire 0 回 hook 一覧を stdout 出力 (JSON or table)
- [ ] `lib-observability-smoke.sh` 5/5 PASS
- [ ] `hook-fire-audit-smoke.sh` 3/3 PASS
- [ ] Wave 1-3 全 smoke regression 0
- [ ] enforcement_matrix に `feature_observability_enabled` guard 登録 (5 field 全備)
- [ ] docs 反映: `.claude/rules/development-process.md` §「Observability」+ `docs/INVENTORY.md` 追加
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

silent failure と死蔵 hook が観測不能な問題を解消するため BLOCK/bypass/fire/silent failure を全件 log append する lib/observability.sh を新設し fire 0 回 hook を 30 日 GC する。完成すれば全 hook の発火が観測可能になり死蔵検出と silent failure 追跡が機械化される。

## Step 計画 (SSoT: master roadmap §5 P3-2 + §3 I5)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `.claude/hooks/lib/observability.sh` 新設 (5 関数、subshell 関数化 + jq fallback、feedback_set_e_in_sourced_libs 遵守) | 4h | — |
| 2 | 🔲 | 主要 8 hook に log_* 呼出追加 (fire / block / bypass emit) | 4h | Step 1 |
| 3 | 🔲 | `.claude/scripts/observability-gc.sh` 新設 (30 日超え archive、`.claude/observability/archive/` mkdir) | 3h | Step 1 |
| 4 | 🔲 | `.claude/scripts/hook-fire-audit.sh` 新設 (fire 0 回 hook 検出、JSON + table 出力) | 3h | Step 1 |
| 5 | 🔲 | 新 smoke `lib-observability-smoke.sh` (5 case) + `hook-fire-audit-smoke.sh` (3 case) + run-all-smokes 登録 | 3h | Step 2, 3, 4 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h | Step 5 |
| 7 | 🔲 | (テスト合格 + リファクタリング) 全 smoke PASS + 3 観点判定 | 1.5h | Step 6 |

合計: 20h ≒ 2.5 day (roadmap 3 day 見積内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-07 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済、docs/tasks/task-99-*.md 生成、list.md #99 📝 → 🔲 update |
| 2026-07-07 | 完了 | Wave 4 Workflow wf_94c193f7-246 経由。lib/observability.sh 5 API (log_block / log_bypass / log_fire / log_silent_failure / log_event、subshell 関数化 + jq fallback、feedback_set_e_in_sourced_libs 遵守) + 8 hook injections (gateguard / task-rule-guard / workflow-guard / autonomous-action-guard / confidence-gate / byproduct-discharge-guard / draft-flow-guard / delegation-guard) + observability-gc.sh (30d archive) + hook-fire-audit.sh (fire 0 hook 検出、--days/--json/--verbose)。lib-observability-smoke 5/5 + hook-fire-audit-smoke 3/3 PASS + 既存 gateguard/confidence-gate regression 0。feature_observability_enabled toggle + matrix entry 追加。Step 1-7 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) `observations.jsonl` schema versioning (`_schema_version` field) — Step 1 で判定
- [ ] (🟢) fire 0 回 hook 自動削除の PR 生成 helper — Step 4 refactor で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I5 + §5 P3-2
- 起源 memory: [[feedback_config_value_needs_consumer_and_smoke]] (I7 triplet)
- 依存 task (soft): [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) (死蔵 hook metric) / [task-94-lib-block-message-4args.md](task-94-lib-block-message-4args.md) (lib pattern 統一)
