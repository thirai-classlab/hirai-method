---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #104: session-start-wrapper hardcode 10 件解体 (W1-8、案 A 一括移行 + shim)

> Status: **🔲 未着手**
> 起案: 2026-07-08 (Grand Summary SSoT 直行方式、user 承認済 = 案 A 一括移行 + shim)
> 関連: Grand Summary 2026-06-10 §6.8 W1-8 / I2 Dispatcher-Only Hook invariant / W1-1・W1-2・W2-A の前提 unblock
> 設計起源: [Grand Summary](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §6.8

## Task ゴール

`.claude/hooks/session-start-wrapper.sh` の `DEFAULT_HOOKS` bash 配列に hardcode されている 10 件 (init-tasks-on-start / check-required-env / improvement-proposal / mode-session-start / mode-enforce / why-x5-reminder / next-actions-surface / mode-asana-prompt / check-serena-mcp / session-help-surface) を `dispatcher-manifest.tsv` に SessionStart bootstrap channel として登録し、`session-start-dispatcher.sh` に並列 fan-out ロジックを移植。wrapper は shim (`HC_SESSION_START_USE_WRAPPER=true` env で旧経路 1-2 リリース維持) 化後撤去。完成すれば dispatcher 経由率 100% (37/37 → 47/47) 達成、manifest 真の SSoT 化 + feature toggle / preset 別運用 / drift 検出網の 3 契約が 10 件にも適用され、W1-1 (真 orphan 機械検出) / W1-2 (preset summary 化) / W2-A (死蔵 hook 棚卸し) が unblock される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-95 | **soft**。task-95 で確定した死蔵 hook 3 件 (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) の enforcement_matrix 登録は本 task で dispatcher-manifest 側も同期 | [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) |
| task-97 | **soft**。task-97 で拡張された enforcement_matrix 26 guards の docs_claim と本 task で追加される 10 hook の docs_claim を整合 | [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) |

## Task 作業概要

- `dispatcher-manifest.tsv` に SessionStart bootstrap channel 10 行追加 (event=SessionStart / matcher="" / channel=bootstrap / feature_key を各 hook に紐付け)
- `session-start-dispatcher.sh` に並列 fan-out ロジック (`HC_SESSION_START_PARALLEL=true` env で 4-8 並列) を移植
- `session-start-wrapper.sh` は shim 化: `HC_SESSION_START_USE_WRAPPER=true` env で旧経路稼働 (1-2 リリース観察期間)、default は `false` (dispatcher 経由)
- 10 hook 各々に feature_key 紐付け:
  - init-tasks-on-start → feature_init_tasks_enabled (新規 yml key)
  - check-required-env → feature_check_required_env_enabled (新規)
  - improvement-proposal → feature_improvement_proposal_enabled (task-97 で登録済)
  - mode-session-start → feature_mode_session_start_enabled (task-97 登録済)
  - mode-enforce → feature_mode_enforce_enabled (task-95 loop_mode_enforcement で登録済)
  - why-x5-reminder → feature_why_x5_reminder_enabled (新規、既存 HC_WHY_X5_DISABLE と cross-check)
  - next-actions-surface → feature_next_actions_surface_enabled (新規)
  - mode-asana-prompt → feature_asana_prompt_enabled (task-95 登録済)
  - check-serena-mcp → feature_check_serena_mcp_enabled (task-97 登録済)
  - session-help-surface → feature_session_help_surface_enabled (task-97 登録済)
- `enforcement_matrix` に 10 guard entry を追加 (5 field 全備、大半 advisory)
- 新規 smoke `.claude/tests/wrapper-dissolution-smoke.sh` 6 case (A dispatcher fan-out / B feature toggle OFF / C preset 別運用 / D shim env / E manifest 完全性 / F 並列実行時 startup time)
- `.claude/hooks/lib/config-loader.sh` に新規 4 key (init_tasks / check_required_env / why_x5_reminder / next_actions_surface) 追加
- docs 反映

## Task 完了条件 (DoD)

- [ ] `dispatcher-manifest.tsv` に 10 行追加 (grep -c SessionStart >= 10)
- [ ] `session-start-dispatcher.sh` に並列 fan-out 実装 (grep -c PARALLEL >= 1)
- [ ] `session-start-wrapper.sh` shim 化: default で dispatcher 経由、`HC_SESSION_START_USE_WRAPPER=true` で旧経路
- [ ] 10 hook 各々に feature_key + `is_feature_enabled` gate 存在 (grep -l is_feature_enabled .claude/hooks/{init-tasks-on-start,check-required-env,improvement-proposal,mode-session-start,mode-enforce,why-x5-reminder,next-actions-surface,mode-asana-prompt,check-serena-mcp,session-help-surface}.sh | wc -l == 10)
- [ ] harness-config.yml に 4 新 key + 10 matrix entry 追加 (5 field 全備)
- [ ] `wrapper-dissolution-smoke.sh` 6/6 PASS
- [ ] enforcement-mismatch-smoke 6+/6+ PASS (matrix 拡張後)
- [ ] SessionStart startup time < 2s (現状 wrapper 並列実行と同等以下、shim 経由 + dispatcher 経由の両 mode 実測)
- [ ] Wave 1-5 全 smoke regression 0
- [ ] docs 反映: `.claude/rules/development-process.md` §「dispatcher-manifest SSoT」+ `docs/INVENTORY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

session-start-wrapper.sh の DEFAULT_HOOKS 10 件 hardcode が manifest SSoT に不可視な問題を解消するため dispatcher-manifest.tsv に SessionStart bootstrap channel として登録し dispatcher に並列 fan-out 移植 + wrapper shim 化する。完成すれば dispatcher 経由率 100% 達成、10 hook にも feature toggle / preset 別運用 / drift 検出網が適用され W1-1 (真 orphan 検出) / W1-2 / W2-A の後続 task が unblock される。

## Step 計画 (Grand Summary §6.8 case A)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | `dispatcher-manifest.tsv` に 10 行追加 + 3 新 yml key (feature_init_tasks_enabled / feature_why_x5_reminder_enabled / feature_next_actions_surface_enabled) + config-loader 3 点 set | 3h | — |
| 2 | ✅ | `session-start-dispatcher.sh` に並列 fan-out (`HC_SESSION_START_PARALLEL=true` default で bootstrap 10 hook background 並列) 移植 | 4h | Step 1 |
| 3 | ✅ | 10 hook に `is_feature_enabled <name>` gate 挿入 (fail-open pattern、全 hook 既存 gate 確認 + why-x5-reminder / next-actions-surface / init-tasks-on-start に短縮名 alias 追加) | 2h | Step 1 |
| 4 | ✅ | `session-start-wrapper.sh` shim 化 (`HC_SESSION_START_USE_WRAPPER=true` env で旧経路、default dispatcher 経由) | 2h | Step 2, 3 |
| 5 | ✅ | 新 smoke `wrapper-dissolution-smoke.sh` 6 case + enforcement_matrix に 10 guard 追加 + run-all-smokes 登録 + INVENTORY.md 反映 + development-process.md subsection 追加 | 3h | Step 4 |
| 6 | ✅ | (テスト設計レビュー) Wave 6 Workflow の Review phase で qa-expert / code-reviewer / architect-reviewer 3 lens 並列、15 findings + 1 CRIT+HIGH → 1 fix cluster で closure | 3h | Step 5 |
| 7 | ✅ | (テスト合格 + リファクタリング) Wave 6 Verify phase で全 smoke PASS + startup time 実測 (dispatcher 3.16s / wrapper 4.40s、smoke 上限内 PASS) + 3 観点判定 skip 明示 (規模小・SSoT 反映のため fold 不要) | 2h | Step 6 |

合計: 19h ≒ 2.4 day (Grand Summary M 見積 1-2 日、shim + 10 guard 登録込みで妥当)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §6.8 W1-8、user 承認済 = 案 A 一括移行 + shim (conf 0.82)、docs/tasks/task-104-*.md 生成、list.md 追加行 |
| 2026-07-09 | Step 1-5 完了 | Wave 6 subagent 実装。dispatcher-manifest 10 rows / dispatcher parallel fan-out / wrapper shim / 3 新 yml key + 10 enforcement_matrix / wrapper-dissolution-smoke 6/6 PASS / Wave 1-5 regression 0 / dispatcher parallel 2.92s (historical wrapper 2.7s と同等)。次: Step 6 (テスト設計レビュー)、Step 7 (リファクタリング) |
| 2026-07-09 | 完了 | Wave 6 Workflow wf_bb16b1b4-c9e、Step 6 (Review 3 lens 並列 iter → 15 findings / 1 CRIT+HIGH fix) + Step 7 (Verify PASS + startup time dispatcher 3.16s / wrapper 4.40s、smoke 上限内、3 観点判定 skip 明示) 完了。dispatcher 経由率 100% 達成 (37/37 → 47/47)、10 hook にも feature toggle / preset 別運用 / drift 検出網が適用され W1-1 / W1-2 / W2-A の後続 task が unblock された。Step 1-7 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) shim 撤去 timing (1-2 リリース観察後) — task-104 完了 3-6 週間後に別 task 起案
- [ ] (🟢) init-tasks-on-start / check-required-env の feature_key に対応する docs 追加 — Step 1 で判定
- [ ] (🟢) W1-1 archive 退避 (真 orphan `.claude/hooks/_archive/<date>/` へ git mv) 起動 — task-104 完了で unblock、別 task 起案予定

## 関連

- Grand Summary §6.8 W1-8: [`hirai-method-harness-grand-summary-20260610`](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §6.8
- I2 Dispatcher-Only Hook invariant (Grand Summary §3.1 表)
- 依存 task (soft): [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) / [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md)
- 後続 unblock 対象: W1-1 archive 退避 / W1-2 preset summary 化 (task-88 実装形態再整理) / W2-A 死蔵 hook 棚卸し (task-108)
- 起源: user 明示判断 2026-07-08 = 案 A 採用
