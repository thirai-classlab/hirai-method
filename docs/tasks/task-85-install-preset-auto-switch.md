---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #85: install.sh consuming repo 用 preset 自動切替 (P1-1 残 scope)

> Status: **🔲 未着手**
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.1/§5 P1-1
> 設計起源: [install-preset-auto-switch.md](../draft/install-preset-auto-switch.md)

## Task ゴール

install.sh が opt-in `--preset=<name>` (advisory/team-default/strict/harness-dev、不正値 exit 64) を受けて preset 別 toggle set で `harness-config.local.yml` を生成し、4 preset いずれの生成下でも target の enforcement-mismatch-smoke が 5 PASS 0 FAIL (自己矛盾ゼロ) になる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-70 | enforcement preset / enforcement_matrix 基盤 (完了済 ✅)。本 task は matrix の presets 期待値と advisory disabled_reason 追記に依存 | task-70 (完了済) |

## Task 作業概要

- install.sh arg parse に `--preset=<name>` 追加 (4 値 validation、default team-default = HOTFIX-1 後方互換)
- §6.4 local.yml 生成を preset 別 toggle set で parameterize (`_preset_toggle_value` 関数化)
- harness-config.yml enforcement_matrix 8 guard に advisory `disabled_reason` 追記 (Case 3/5 構造的 FAIL 解消)
- install summary に preset 名 + 変更手順 + `hc-config.sh --summary` 検証導線
- install-local-yml-smoke.sh に case H-M 追加

## Task 完了条件 (DoD)

- [ ] `bash install.sh <tmp> --preset=strict|advisory|harness-dev --no-mcp --no-docs` で local.yml が preset 別 toggle set で生成される (case H/I/J PASS)
- [ ] 4 preset いずれの生成 local.yml 下でも target の `enforcement-mismatch-smoke.sh` が 5 PASS 0 FAIL (case G/I/J で機械検証)
- [ ] `--preset=bogus` が exit 64 で reject (case K PASS)
- [ ] `--preset` 無指定の default 生成が HOTFIX-1 と同一内容 (既存 case A/B PASS 維持)
- [ ] 本 repo (harness-dev) の enforcement-mismatch-smoke が advisory disabled_reason 追記後も 5 PASS 0 FAIL
- [ ] hc-config-local-yml-smoke.sh 12 assert PASS 維持 (regression 0)
- [ ] install summary に preset 案内出力 (`grep -c "preset"` ≥ 2)

## Task 概要欄 (list.md 用)

consuming repo の preset 選択を install 時に完結させるため、install.sh に `--preset=<name>` opt-in を追加し preset 別 toggle set で local.yml 生成を parameterize + enforcement_matrix に advisory disabled_reason を追記する。完成すれば 4 preset いずれ選択でも自己矛盾ゼロで install 直後から意図した enforcement が effective になる (HOTFIX-1 の 8 toggle bootstrap は PR #68 実装済、本 task は残 scope)。

## Step 計画 (SSoT: draft §3 「Step 計画」+ Step N 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | install.sh: `--preset=<name>` arg parse + validation + §6.4 生成 parameterize + summary 更新 | 2.5h | — |
| 2 | 🔲 | harness-config.yml: enforcement_matrix 8 guard に advisory `disabled_reason` 追記 | 0.5h | — |
| 3 | 🔲 | install-local-yml-smoke.sh: case H-M 追加 (preset 別生成 / reject / 既存保持 / set drift 静的検査) | 1.5h | Step 1, 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `review_min_count_test ≤ N ≤ review_max_count_test` | 0.5h | Step 3 |
| 5 | 🔲 | (テスト合格) 新旧 smoke 全 PASS (install-local-yml 7+N case / enforcement-mismatch 5 case / hc-config-local-yml 12 assert) | 0.5h | Step 4 |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.3h | Step 5 |

合計: 5.8h (≒ 0.75 day、roadmap P1-1 見積 0.5 day + advisory matrix 追記分)

> **注意**: install.sh は #87/#89/#90 も同域 (arg parse / header / summary) を編集する。着手順は #85 → #89 → #90 (→ #87) で序列化し、並列 subagent での install.sh 同時編集は禁止 (2026-07-05 横断レビュー M6)。header 行数変更時は install.sh:90 の `-h` sed 範囲を同 commit で更新。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、横断レビュー 2 lens 反映済) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: 対策 A 不採用確定 / advisory v1 採用 / review_required_security 不含)、list.md 🔲 化 |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [install-preset-auto-switch.md](../draft/install-preset-auto-switch.md)
- 前提実装: PR #68 (HOTFIX-1 §6.4 bootstrap)
- 後続: #87 (self-doctor D1/D6 が本 task の preset 別生成に追随) / #92 (P2-1 が task-85 依存)
