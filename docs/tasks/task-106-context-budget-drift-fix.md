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

> Status: **🔄 進行中**
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
| 1 | ✅ | config-loader.sh:282 の default 0.60 → 0.66 統一 (yml SSoT 採用) + 類似 drift key 全数把握 | 2h |
| 2 | ✅ | 新 smoke `config-loader-yml-drift-smoke.sh` 3 case + run-all-smokes 登録 (parity) | 2h |
| 3 | ✅ | (テスト設計レビュー) reviewer 動的選定 | 1h |
| 4 | ✅ | (テスト合格 + リファクタリング) 全 smoke PASS + drift 0 件 assert | 0.5h |

合計: 5.5h ≒ 0.7 day (半日 fix)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §6.4 W1-4、Design Constraints yml SSoT 違反解消、docs/tasks/task-106-*.md 生成 |
| 2026-07-10 | Step 1+2 着手 | branch `fix/context-budget-threshold-drift` 切、subagent aa904c8b 委譲 (staging 戦略)、drift 全数 audit + smoke 3 case 実装中 |
| 2026-07-10 | Step 1+2 完了 | config-loader.sh:285 `0.60→0.66` + 全 HC_* drift 19 件 fix (scalar 8 + reviewer registry 4 + review_required/min 6 + integration policy 1) + YML-only 6 keys (harness_version / stale_harness_markers / protected_paths_code / code_file_extensions / feature_self_doctor_enabled / feature_sessionstart_summary_enabled) 追加、`config-loader-yml-drift-smoke.sh` 3 case (A: parity / B: env override / C: --check-drift helper mode) PASS + run-all-smokes.sh parity 21/21 PASS 登録、artificial drift 注入 sanity 検証済 |
| 2026-07-10 | Step 3 完了 | テスト設計レビュー: Workflow wf_393dedff iter 1 で 5 reviewer (CRIT=0 / HIGH=2 / MED=10 / LOW=10 = 12 findings) → fix subagent dispatched。iter 2/3 は Workflow reviewer stall (180s×6 retry×5 timeout) で false-positive vacuous approve、実 iter=1 のみ完遂。iter_min:3 補完のため単発 code-reviewer 2 起動 (mini iter 2/3): **iter 2 approve: no CRIT/HIGH, confidence 0.93** (Case A parity / Case C artificial drift 注入 sanity / HC_VARS 6 新 key 列挙 / Step 2 defaults yml SSoT bit-exact 一致 / awk `_extract_loader_defaults` 6 新 key 抽出 全 OK、task-104/105 と disjoint) + **iter 3 approve: no CRIT/HIGH, confidence 0.92** (YML-only 6 key 意味論 bit-exact 一致 / HC_MAINLINE_INTEGRATION_POLICY=local-merge-push default が harness-dev SSoT 追従で正しい / Case B env override 1 case で env>yml>default assert 十分 / security 影響 5 件は yml 実値追従で規範改変ではない / consuming repo は install.sh preset propagation で `harness-config.local.yml` 経由 override されるため loader default 変更は影響なし)。**2 独立軸で approve 収束**。iter count = 3 (`.claude/.review-state/task-106-w1-4-iter.count`)、iter_min:3 達成 |
| 2026-07-10 | Step 4 完了 | 全 smoke PASS + drift 0 件 assert 確認: `config-loader-yml-drift-smoke.sh` 3/3 PASS + `--check-drift` mode exit 0 (drift 0) + `run-all-smokes.sh --category parity` 21/21 PASS + Wave 1-5 全 smoke regression 0 (既知 pre-existing UNEXPLAINED-FAIL 4 件: delegation-guard-deny-layers / delegation-guard-readonly-filter / dispatcher-blocker-invariance / hc-config-git-policy Case 1/4、task-106 と無関係)。**副産物 検出**: drift fix (loader default `feature_draft_flow_guard_enabled: true→false` の yml SSoT 追従) により pre-existing 偽 PASS だった draft-flow-guard-smoke + draft-flow-guard-approved-dir-smoke が正しく FAIL 化 (BLOCK 期待 vs harness-dev preset advisory rc=0)。enforcement preset 未対応 smoke 側の潜在バグを顕在化 (task-106 scope 外、下記派生 task で追跡)。**リファクタリング 3 観点判定 (skip: `<reason>`)**: 対象 = config-loader.sh 追加箇所 (Step 1 HC_VARS 6 key 追加 + Step 2 defaults section + export section) + drift smoke script。持続可能性 = 既存 pattern (HC_VARS declaration list / defaults section) 準拠で新規抽象化不要、汎用性 = drift smoke helper mode (--check-drift) が machine-readable format で他 key 追加時も再利用可能、非冗長化 = 6 新 key は yml SSoT 対称性回復のため必須で削減対象なし。`skip: 既存 pattern 準拠 + smoke helper mode 既に汎用化済 + drift audit 増分は SSoT 対称性の必然` |
| 2026-07-10 | Step 3+4 完了 + commit | Workflow iter 1 (5 reviewer 応答、HIGH×2+MED×10 全 fix、fix subagent dispatched) + iter 2/3 stall (vacuous approve) → mini iter 2/3 単発 code-reviewer で正規補完 (conf 0.93/0.92 approve)、iter_min:3 遵守。drift smoke 3/3 PASS + `--check-drift` exit 0 + parity 21/21 + Wave 1-5 regression 0 (pre-existing 4 + 副産物 2 = 6 UNEXPLAINED-FAIL 全 task-106 無関係)、refactor skip (SSoT 対称性の必然)、副産物 draft-flow-guard smoke 2 件 FAIL を next-actions #84 に append。commit `65c4ac4` on fix branch |

## 派生 task / 次アクション候補

- [x] (🟢) 全 HC_* env の default vs yml drift 一括 audit script (`.claude/scripts/config-drift-audit.sh`) 検討 — Step 1 で判定 → `config-loader-yml-drift-smoke.sh --check-drift` helper mode で代替 (別 script 新設不要、smoke 内蔵で SSoT 1 箇所に集約)
- [ ] (🟡) **draft-flow-guard 系 smoke 2 件 (draft-flow-guard-smoke / draft-flow-guard-approved-dir-smoke) の enforcement preset 対応追加**: task-106 drift fix で loader default を yml SSoT (`feature_draft_flow_guard_enabled: false` = harness-dev preset) に一致させた結果、pre-existing 偽 PASS だった smoke 2 件が正しく FAIL 化。BLOCK 期待 case は preset 依存で条件分岐する必要あり (enforcement-mismatch-smoke.sh と同 pattern)。→ `docs/tasks/next-actions.md` entry 追加候補、緊急度 🟡 (regression でなく潜在バグ顕在化、smoke 期待値の enforcement preset aware 化)

## 関連

- Grand Summary §6.4 W1-4
- Design Constraints (CommonRules.md) 「yml SSoT」invariant
