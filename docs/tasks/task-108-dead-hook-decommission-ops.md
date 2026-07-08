---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #108: 死蔵 hook 棚卸し実運用 phase (W2-A、30 日 fire audit + 物理削除)

> Status: **🔲 未着手 (trigger 待ち = 2026-08-07 前後、task-99 merge 後 30 日)**
> 起案: 2026-07-08 (Grand Summary SSoT 直行方式、user 承認済)
> 関連: Grand Summary 2026-06-10 §5.3 W2-A / I5 Observability invariant / task-99 lib/observability.sh 完成後の実運用 phase
> 設計起源: [Grand Summary](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §5.3

## Task ゴール

task-99 で新設した `.claude/scripts/hook-fire-audit.sh --days 30` を実運用し、30 日間 fire 0 回の hook を機械検出。該当 hook を (1) feature toggle OFF (advisory 化) → (2) `.claude/hooks/_archive/<date>/` へ git mv → (3) 1-2 リリース後物理削除 の 3 段階で棚卸し。task-104 (wrapper 解体) 完了後 dispatcher-manifest.tsv 真の SSoT 化が完成するため、真 orphan の機械算出が可能になる (Grand Summary §6.1 W1-1 Step B の後続)。完成すれば harness 内の死蔵 hook が定量根拠 (fire 0 回 × 30 日) で機械決定できるようになる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-99 | **hard**。lib/observability.sh 5 API + hook-fire-audit.sh 実装済が前提 (2026-07-08 完了) | [task-99-lib-observability-30d-gc.md](task-99-lib-observability-30d-gc.md) |
| task-104 | **hard**。wrapper 解体で dispatcher-manifest 真の SSoT 化、真 orphan 機械検出が本 task の scope | [task-104-wrapper-hardcode-dissolution.md](task-104-wrapper-hardcode-dissolution.md) |
| task-95 | **soft**。task-95 で確定した死蔵 hook 3 件 (tool_call_slip_detect 等) の棚卸し方針を継承 | [task-95-dead-hook-inventory.md](task-95-dead-hook-inventory.md) |

## Task 作業概要

- `bash .claude/scripts/hook-fire-audit.sh --days 30 --json` で fire 0 hook 一覧を取得
- 各 hook について feature toggle OFF (harness-config.yml で `feature_<name>_enabled: false`) 実施
- 1-2 リリース観察後、`.claude/hooks/_archive/<date>/` へ git mv (即時削除でなく退避)
- 更に 1-2 リリース後、物理削除
- 新規 smoke `.claude/tests/dead-hook-decommission-smoke.sh` (退避された hook が dispatcher から呼出されない assert)
- docs 反映: `docs/INVENTORY.md` に archive dir + 棚卸しログ

## Task 完了条件 (DoD)

- [ ] `hook-fire-audit.sh --days 30` の run で fire 0 hook 一覧取得 + 決定 log を task file に記録
- [ ] 該当 hook 全てで feature toggle OFF 実施 + matrix disabled_reason 追記
- [ ] `.claude/hooks/_archive/<date>/` dir 存在 + 退避完了
- [ ] `dead-hook-decommission-smoke.sh` 追加 + PASS
- [ ] Wave 1-N 全 smoke regression 0
- [ ] docs 反映: `docs/INVENTORY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

死蔵 hook が 30 日間 fire 0 回でも機械判定・退避できない問題を解消するため task-99 lib/observability の hook-fire-audit を実運用し 3 段階棚卸し (toggle OFF → archive 退避 → 物理削除) を実施する。完成すれば hook 増加による観測ノイズが定量根拠で削減され harness スリム化が定期運用化される。

## Step 計画 (Grand Summary §5.3)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `hook-fire-audit.sh --days 30` run + fire 0 hook 一覧 + 決定 log 記録 | 1h | task-99 merge + 30 日経過 |
| 2 | 🔲 | 該当 hook feature toggle OFF + matrix disabled_reason 追記 | 2h | Step 1 |
| 3 | 🔲 | 1-2 リリース観察後 `.claude/hooks/_archive/<date>/` へ git mv | 2h | Step 2 + observation period |
| 4 | 🔲 | 新 smoke `dead-hook-decommission-smoke.sh` + run-all-smokes 登録 | 3h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー + テスト合格 + リファクタリング) | 3h | Step 4 |

合計: 11h ≒ 1.4 day + 観察期間 (30 日 + 1-2 リリース)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §5.3 W2-A、task-99 merge 後 30 日 trigger = 2026-08-07 前後着手可、docs/tasks/task-108-*.md 生成 |

## 派生 task / 次アクション候補

- [ ] (🟢) archive 退避 hook の 1-2 リリース後物理削除 timing — 別 task 起案予定
- [ ] (🟢) task-95 で判定済 3 hook (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) の再棚卸し — Step 1 で確認

## 関連

- Grand Summary §5.3 W2-A
- 前提 (hard): task-99 lib/observability + hook-fire-audit / task-104 wrapper 解体 (dispatcher 真の SSoT 化)
- Trigger: task-99 merge (2026-07-07) + 30 日 = 2026-08-07 前後
