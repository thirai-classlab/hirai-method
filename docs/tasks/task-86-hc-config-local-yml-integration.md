---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #86: hc-config.sh local.yml 統合 (P1-2 残 scope — typo WARN / validate / smoke / 表示一貫性)

> Status: **🔲 未着手**
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.2 (R6)/§5 P1-2、next-actions entry #79 吸収
> 設計起源: [hc-config-local-yml-integration.md](../draft/hc-config-local-yml-integration.md)

## Task ゴール

hc-config.sh CLI が local-only key の typo WARN / `--validate` の local.yml 検証 / `--list`・`--diff`・TUI の local override 可視化を備え、array 表示 gap の明示固定を含めて「CLI 表示 = runtime 実効値の真実 1 本化」が完成する (smoke 12 → 20+ assertions)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-69 | config-loader.sh の local.yml 対応 (Step 3.5/3.6、完了済 ✅)。本 task は Step 3.6 の typo WARN 文言・`HC_UNKNOWN_LOCAL_KEY_WARN` guard を CLI 側で共用する | task-69 (完了済) |

## Task 作業概要

- smoke 拡張 Case 6〜10 を先行追加 (TDD RED)
- `cmd_get` に local-only key typo WARN (config-loader Step 3.6 同文言 body、fail-open)
- `cmd_validate` の local.yml 検証対応 (SSoT 在 key は型検証で非 0 exit、local-only は WARN のみ)
- `--list` / `--diff` stderr notice + TUI effect panel `(local overridden)` marker + array gap 明示 comment

## Task 完了条件 (DoD)

- [ ] `hc-config-local-yml-smoke.sh` 0 FAIL、assertion 12 → 20 以上 (Case 6〜10 追加)
- [ ] local-only key typo WARN: `--get <typo_key>` が値 + exit 0 + stderr に `unknown_local_key: <typo_key>` 1 回
- [ ] `--validate`: local.yml の不正型 (`banana`) で exit 非 0 + stderr `invalid (local)`、正常 local で exit 0 + `validation OK` 行不変
- [ ] `hc-config-key-parity-smoke.sh` PASS (`--list` stdout 汚染 0)
- [ ] regression 0: hc-config-script / hc-config-tui / enforcement-mismatch / install-local-yml 各 smoke 全 PASS
- [ ] `_get_current` header comment に array 表示 gap の明示 (grep 1 hit 以上)

## Task 概要欄 (list.md 用)

CLI と runtime の真実 1 本化を完成させるため (R6 残 scope)、hc-config.sh に local-only key typo WARN / --validate の local.yml 検証 / --list・--diff・TUI の local override 可視化を追加し smoke を 20+ assertions へ拡張する。完成すれば local.yml の誤記が CLI で即検知され、全表示経路で override が可視化される (--get/--summary の tier 統合は HOTFIX-2 = PR #68 実装済、本 task は残 scope)。

## Step 計画 (SSoT: draft §3 「Step 計画」+ Step N 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | smoke 拡張 Case 6〜10 追加 (RED: Case 8/9/10 FAIL 確認、Case 6/7 は現挙動固定) | 1.0h | — |
| 2 | 🔲 | `cmd_get` local-only key typo WARN (Step 3.6 同文言、fail-open) | 0.5h | Step 1 |
| 3 | 🔲 | `cmd_validate` の local.yml 検証対応 | 0.7h | Step 1 |
| 4 | 🔲 | `--list` / `--diff` stderr notice + TUI effect panel marker + array gap 明示 comment | 0.8h | Step 1 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`review_min_count_test`〜`review_max_count_test` 範囲) | 0.5h | Step 2-4 |
| 6 | 🔲 | (テスト合格) local-yml smoke 全 PASS + 既存 smoke regression 0 | 0.3h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.2h | Step 6 |

合計: 4.0h (roadmap P1-2 見積 0.5 day から HOTFIX-2 実装済分を控除した残量)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、entry #79 (1)(2)(3) 吸収、(4) は #47 系 draft へ分離) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: array gap 明示固定 / #79(4) は install-sh-yml-customization-preserve 統合)、list.md 🔲 化 |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [hc-config-local-yml-integration.md](../draft/hc-config-local-yml-integration.md)
- 前提実装: PR #68 (HOTFIX-2 local.yml tier)
- 関連 registry: next-actions.md entry #79
