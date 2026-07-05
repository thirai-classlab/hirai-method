---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #88: SessionStart hc-config --summary 全文注入 (effective state 常時可視化、P1-4)

> Status: **🔲 未着手**
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.6 (W1-2 採用済)/§5 P1-4
> 設計起源: [sessionstart-summary-injection.md](../draft/sessionstart-summary-injection.md)

## Task ゴール

SessionStart で `hc-config.sh --summary` 全文が `<system-reminder>` 注入され (追加 subprocess 0、footprint cap 2400B 内)、AI が session 冒頭から effective preset / guard 状態の ground truth を把握できる。

## Task 依存先タスク

— (依存なし)

> list.md 旧依存 task-86 は「HOTFIX-2 subset (--summary local tier、PR #68 merge 済)」への依存であり成立済。#86 残 scope (typo WARN / validate / 表示一貫性) には非依存のため並行着手可 (2026-07-05 横断レビュー M1 で確定)。

## Task 作業概要

- mode-session-start.sh 拡張: 既取得 SUMMARY 変数の全文注入 (`SUMMARY=""` 初期化 + 不在時 enabled 扱いの fail-open gate)
- feature toggle 3 点 set (`feature_sessionstart_summary_enabled` default true + metadata TSV + HC_ env)
- footprint smoke cap 800→2400 + FP-5 (presence) / FP-6 (toggle-off) 新設 + budget smoke 同期

## Task 完了条件 (DoD)

- [ ] dispatcher stdout に summary 全文 1 回出現 (`grep -c 'totals:'` → 1)
- [ ] `HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false` で注入 0 (`grep -c 'totals:'` → 0)
- [ ] `sessionstart-footprint-smoke.sh` 全 case PASS (cap 2400、FP-5/FP-6 含む)
- [ ] `sessionstart-budget-smoke.sh` PASS (WARN 0)
- [ ] `--get feature_sessionstart_summary_enabled` → true (yml key 登録)
- [ ] regression 0: enforcement-mismatch + SessionStart 系 smoke PASS
- [ ] I2 無違反: `git diff --name-only` に settings.json / dispatcher-manifest.tsv 不含

## Task 概要欄 (list.md 用)

規範文書 (BLOCK 表記) と effective state の乖離による AI 萎縮 (R3) を解消するため、mode-session-start.sh を拡張し hc-config --summary 全文を SessionStart で注入する (cap 800→2400B、sub-toggle 付き)。完成すれば AI が install 直後から ground truth を常時把握でき、guard 状態の読み違いによる萎縮 / 逃避が起きなくなる。

## Step 計画 (SSoT: draft §3 「Step 計画」)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `mode-session-start.sh` 拡張: SUMMARY 全文注入 + fail-open gate (`SUMMARY=""` 初期化 + is_feature_enabled 不在時 enabled 扱い) | 1.0h | — |
| 2 | 🔲 | feature toggle 3 点 set: yml key + metadata 登録 + env override 確認 | 0.5h | Step 1 |
| 3 | 🔲 | smoke 更新: footprint cap 2400 + FP-5/FP-6 新設 + budget warn 同期 | 1.0h | Step 1-2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `review_min_count_test ≤ N ≤ review_max_count_test` | 0.5h | Step 3 |
| 5 | 🔲 | (テスト合格) 全対象 smoke PASS + regression 0 | 0.5h | Step 4 |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.3h | Step 5 |

合計: 約 0.5 day (roadmap P1-4 見積と整合)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、M4 [SUMMARY set -u 途中死 + fail-closed gate] 修正済) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: cap 2400B 承認 / toggle 階層許容)、list.md 🔲 化 + 依存先 — 化 |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [sessionstart-summary-injection.md](../draft/sessionstart-summary-injection.md)
- 相互参照: #91 (tier B は stderr 経路で footprint cap 非干渉、smoke 衝突なし)
- 後続: #95 (P2-4)、#103 (P3-6) が本 task に依存
