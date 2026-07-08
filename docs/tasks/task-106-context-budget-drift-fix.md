---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 4
-->

# Task #106: context-budget drift 修正 (W1-4、config-loader.sh:282 → harness-config.yml SSoT 統一)

> Status: **🔲 未着手**
> 起案: 2026-07-08 (Grand Summary SSoT 直行方式、user 承認済)
> 関連: Grand Summary 2026-06-10 §6.4 W1-4 / Design Constraints「yml SSoT」invariant
> 設計起源: [Grand Summary](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §6.4

## Task ゴール

`.claude/hooks/lib/config-loader.sh:282` の `HC_CONTEXT_BUDGET_THRESHOLD` default 値 `0.60` を `harness-config.yml:context_budget_threshold` の値 `0.66` に統一 (or 逆方向)。Design Constraints「機能 on/off は yml feature toggle で集中管理」+ 「hook / command の機能群は harness-config.yml の feature toggle で集中制御」invariant 遵守。1 行 fix + smoke で drift 検出構造化。完成すれば context-budget 60% tier の発火閾値が SSoT 1 箇所に集約される。

## Task 依存先タスク

依存なし (— 依存なし)

## Task 作業概要

- config-loader.sh:282 の default value 変更 (0.60 → 0.66 に統一、or yml 側を 0.60 に統一)
- yml SSoT 側の値を採用: 0.66 が現在 harness-config.yml で運用中なので 0.66 に統一
- 新規 smoke `.claude/tests/config-loader-yml-drift-smoke.sh` 3 case (A default 値の yml SSoT 一致 / B env override 動作 / C key 追加時の drift 検出 helper)
- 副産物: 類似 drift の全 key 検出 (config-loader.sh vs harness-config.yml の default 値差) を smoke 化

## Task 完了条件 (DoD)

- [ ] config-loader.sh の HC_CONTEXT_BUDGET_THRESHOLD default = harness-config.yml の context_budget_threshold value
- [ ] 全 HC_* default value が yml default と一致 (drift 0 件): `config-loader-yml-drift-smoke.sh` 3/3 PASS
- [ ] Wave 1-5 全 smoke regression 0
- [ ] docs 反映: yml SSoT invariant を development-process.md で強調
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

config-loader.sh:282 の default 0.60 が harness-config.yml 0.66 と drift している問題を解消するため config-loader default 値を yml SSoT に統一する。完成すれば全 HC_* env の default 値が harness-config.yml の値と一致し「yml SSoT」invariant が 100% 遵守されるようになる。

## Step 計画 (Grand Summary §6.4)

| Step | Status | 作業概要 | 工数 |
|:---:|:---:|:---|---:|
| 1 | 🔲 | config-loader.sh:282 の default 0.60 → 0.66 統一 (yml SSoT 採用) + 類似 drift key 全数把握 | 2h |
| 2 | 🔲 | 新 smoke `config-loader-yml-drift-smoke.sh` 3 case + run-all-smokes 登録 (parity) | 2h |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1h |
| 4 | 🔲 | (テスト合格 + リファクタリング) 全 smoke PASS + drift 0 件 assert | 0.5h |

合計: 5.5h ≒ 0.7 day (半日 fix)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §6.4 W1-4、Design Constraints yml SSoT 違反解消、docs/tasks/task-106-*.md 生成 |

## 派生 task / 次アクション候補

- [ ] (🟢) 全 HC_* env の default vs yml drift 一括 audit script (`.claude/scripts/config-drift-audit.sh`) 検討 — Step 1 で判定

## 関連

- Grand Summary §6.4 W1-4
- Design Constraints (CommonRules.md) 「yml SSoT」invariant
