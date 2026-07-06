---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #96: agent-router LLM fallback default OFF + yml toggle 明示化 (P2-5/W1-5、I7 triplet 遵守)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり default OFF + 3 key + subshell 化 + env 互換層維持採用)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §5 P2-5 / §11.3 R5 / §11.3 R2 / §3 I7 (Config-Consumer-Smoke Triplet)
> 設計起源: [agent-router-llm-fallback-toggle.md](../draft/agent-router-llm-fallback-toggle.md)

## Task ゴール

`.claude/harness-config.yml` に 3 新規 key (`feature_agent_router_llm_fallback_enabled: false` / `agent_router_llm_budget_usd_per_day: 0.1` / `agent_router_llm_similarity_threshold: 0.7`) が SSoT として追加され、`hc-config-metadata.sh` TSV 登録 + `config-loader.sh` default export + `agent-router-suggest.sh` の子 toggle gate + budget 累積 (UTC-day file) + threshold override + env 互換層 (env 明示 set 時 WARN) が実装される。新規 smoke `agent-router-llm-fallback-smoke.sh` (6+ case、`behavior/fast` 分類) が I7 triplet を機械検証し、既存 `AGENT_ROUTER_LLM_*` env との互換動作 (env 優先) が破壊されない。

## Task 依存先タスク

— (依存なし、task-86 = P1-2 `hc-config.sh` local.yml 統合は PR #70 で完了済)

`hc-config.sh --get` の解決順序 (env > local.yml > yml > default) は task-86 で local.yml 統合済のため、本 task は独立着手可。task-97 (P2-6) は本 task の追加 feature toggle 1 件 (`feature_agent_router_llm_fallback_enabled`) を matrix 登録対象として cross-check する (逆方向 cross-check、hard 依存ではない)。

## Task 作業概要

- `.claude/harness-config.yml` に 3 新規 key 追加 + inline comment (default + effect 1 行)
- `.claude/scripts/lib/hc-config-metadata.sh` TSV に 3 行追加 (5 field: key + category + description + effect + label_ja)
- `.claude/hooks/lib/config-loader.sh` に 3 default export 追加 (`HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED` 他)
- `.claude/hooks/agent-router-suggest.sh` refactor (子 toggle gate + budget 累積 + threshold override + env 互換層、`export` 1 mechanism 固定)
- 新規 smoke `agent-router-llm-fallback-smoke.sh` (6+ case: default OFF / opt-in ON / budget 超過 disable / threshold override / env 互換 / env leak 0 & mechanism drift 検出) + `run-all-smokes.sh` category (behavior/fast) 登録
- docs 反映 (harness-config.yml inline comment / docs/INVENTORY / development-process.md drift 確認)

## Task 完了条件 (DoD)

- [ ] `feature_agent_router_llm_fallback_enabled: false` が yml SSoT に存在 (`grep -c` == 1)
- [ ] `agent_router_llm_budget_usd_per_day: 0.1` が yml SSoT に存在 (`grep -c` == 1)
- [ ] `agent_router_llm_similarity_threshold: 0.7` が yml SSoT に存在 (`grep -c` == 1)
- [ ] `hc-config.sh --get <key>` が 3 key で正しく値返却 (false / 0.1 / 0.7)
- [ ] hc-config-metadata.sh TSV に 3 key の 5 field entry (category = `feature_toggle` / `Gate/Confidence` × 2)
- [ ] hook が子 toggle OFF (default) 時に env `AGENT_ROUTER_LLM_FALLBACK` を上書きしない (env 未 set 維持)
- [ ] hook が子 toggle ON 時に `AGENT_ROUTER_LLM_FALLBACK=on` を export (router.py が `--use-llm-fallback` mode)
- [ ] budget 累積 file 超過時に fallback 強制 disable + WARN 1 行 stderr (Case 3)
- [ ] `AGENT_ROUTER_LLM_THRESHOLD` env 未 set かつ子 toggle ON で `HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD=0.7` を export (Case 4)
- [ ] 既存 `AGENT_ROUTER_LLM_FALLBACK` env 明示 set 時は env 優先 (WARN 1 行 stderr、Case 5)
- [ ] env 制御 mechanism drift 検出: `unset AGENT_ROUTER_LLM_` grep 0 hit + inline env prefix 0 hit
- [ ] hook 実行前後の parent shell env 差分 == 0 (leak なし、Case 6)
- [ ] 新 smoke 全 case PASS (>=5) + 既存 wiring smoke regression 0 + run-all-smokes.sh 全体 exit 0
- [ ] enforcement-mismatch-smoke で新 key の docs/config mismatch 0 + hc-config-key-parity-smoke で TSV drift 0
- [ ] docs 反映 (harness-config.yml 3 key 直上 inline comment / development-process.md grep drift 確認 / `hc-config.sh --list` に 3 key discoverable)
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

agent-router LLM fallback が env-only opt-in で yml SSoT 不在 + budget/threshold の default が `.py` hardcode で調整不能な I7 triplet 未達を解消するため、`.claude/harness-config.yml` に 3 key (feature toggle + budget + threshold) を default OFF で明示化し hook を子 toggle + budget 累積 + env 互換層でリファクタする。完成すれば consuming repo が `hc-config.sh --get/--set` で LLM 呼出コストを構造制御でき、既存 env での opt-in も破壊せず維持されるようになる (env 明示時 WARN で drift 通知)。

## Step 計画 (SSoT: draft §7 「Step 分解」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | SSoT 4 file 同時追加 (harness-config.yml 3 key + inline comment / config-loader.sh 3 default export / metadata TSV 3 行 / harness-config.local.yml 参考 comment) | 0.5h | — |
| 2 | 🔲 | consumer refactor: `agent-router-suggest.sh` に子 toggle gate + budget 累積 (UTC-day file) + threshold override + env 互換層 (env 明示 set 時 WARN、`export` 1 mechanism 固定) を実装 | 1.5h | Step 1 |
| 3 | 🔲 | 新 smoke `agent-router-llm-fallback-smoke.sh` 新設 (6+ case: default OFF / opt-in ON / budget 超過 / threshold override / env 互換 / env leak 0 + mechanism drift 検出) + `run-all-smokes.sh` に category (behavior/fast) 登録 | 1.5h | Step 2 |
| 4 | 🔲 | docs 反映 (harness-config.yml inline comment 3 行 / docs/INVENTORY.md yml key 表 / .claude/rules/development-process.md drift 確認、`agent_router_llm` mention 0 hit なら skip) | 0.5h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (LLM API/config 系 domain-specific 加味)、CRITICAL/HIGH/MEDIUM 0 まで反復 (上限 `review_iteration_max`)、reviewer prompt 5 必須項目 (project 整合性 + 他 task 影響確認 含む) | 1.0h | Step 4 |
| 6 | 🔲 | (テスト合格) UI 変更なし → unit/integration smoke で PASS 判定 (§6 DoD 全項目)、既存 smoke regression 0 | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 (持続可能性: budget file schema 将来変更耐性 / 汎用性: 他 LLM 系 hook 横展開余地 / 非冗長化: config-loader.sh + metadata TSV 記法 DRY)、不要なら `skip: <reason>` 明示 | 0.5h | Step 6 |

合計: 6.0h (≒ 0.75 day、Step 5 iter 上限で ±1.5h 変動可)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/agent-router-llm-fallback-toggle.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり案 B 採用 = 3 key + I7 triplet 全遵守 + env 互換層維持 + `export` 1 mechanism 固定 + budget file の task-99 GC 対象化契約) |
| 2026-07-06 | タスク化 | `/new-task 96 agent-router-llm-fallback-toggle`、list.md #96 📝 → 🔲 update、docs/tasks/task-96-*.md 生成 |

## 派生 task / 次アクション候補

Draft §リスク table + §関連からの初期 candidate:

- [ ] (🟡) budget file (`.claude/.workflow-state/agent-router-llm-budget/*.usd`) を task-99 (P3-2 lib/observability.sh + 30 日 GC + fire 0 回 hook 棚卸し) の GC 対象 file list に append する運用義務 — task-99 draft 起案時に main agent が実行 (副産物 candidate として next-actions.md へ append)
- [ ] (🟢) 並列書込み race 対策の `flock` 化 — Phase 3 検討

## 関連

- Draft: [agent-router-llm-fallback-toggle.md](../draft/agent-router-llm-fallback-toggle.md)
- 前提 (完了済): task-81 (agent-router-suggest 配線復活、PR merge 済) / task-86 (hc-config.sh local.yml 統合、PR #70) / task-88 (SessionStart --summary 全文注入、PR #71)
- 後続 cross-check: [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) (P2-6、`feature_agent_router_llm_fallback_enabled` を matrix 登録対象として cross-check、逆方向 = hard 依存ではない)
- 関連 memory: [[feedback_config_value_needs_consumer_and_smoke]] (I7 起源) / [[feedback_parallel_subagent_cross_file_contract_drift]] (§4.1 契約 SSoT 起源)
