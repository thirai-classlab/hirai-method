---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 9
-->

# Task #72: agents / skills 露出削減 (action space 縮小、Phase 4)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 4 (§4.4)。task-51 (context-bloat-reduction) / task-67 (rule 再構造) の延長
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.4

## Task ゴール

project `.claude/agents` の常時露出を 15-25 程度、`.claude/skills` を 8-12 程度に絞り、long-tail は **削除せず** user scope / plugin / archive へ移して復帰経路を残す。`CommonRules.md` は invariant kernel のみ残し詳細は `rules-details/` 参照にする。選択面 (description) が縮小し action space の判断負荷が下がる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-69 | config key parity 基盤 (harness 全体整合の前提)。settings dispatcher (task-71) とは独立領域 (agents/skills は別 discover 機構) のため並行可 | [task-69-hc-config-key-parity.md](task-69-hc-config-key-parity.md) |

## Task 作業概要

- 使用頻度集計 (docs / tasks / transcripts / settings から agent / skill 名の参照回数)
- 責務重複を畳む (reviewer / build resolver / planner 系の粒度統一、似た description を 1 つに統合)
- project 固有か判定 (この repo のハーネス運用に固有でないものは project `.claude/` から外す)
- deterministic 化できるもの (config parity / hook inventory / smoke 実行等) を agent でなく script / command 化
- 復帰経路を残す (削除でなく `archive/` or user scope へ移動 + 復帰コマンドを docs に記載)
- description ルール適用 (短く非重複、自動選択の入口を濁さない)
- `CommonRules.md` を invariant kernel (<=150 行目標) に絞り詳細を `rules-details/` 参照化

## Task 完了条件 (DoD)

- [ ] project `.claude/agents` 常時露出が棚卸しされ目標 <=25 に近づく (現 144)
- [ ] project `.claude/skills` 常時露出が棚卸しされ目標 <=12 に近づく (現 63)
- [ ] 外した agent / skill は archive / user scope へ移動され復帰経路が docs に記載 (能力喪失なし)
- [ ] `CommonRules.md` <=150 行目標 / `rules/*.md` total <=700 行目標 (regression budget、warn)
- [ ] 残す / 外す判断が draft §4.4「残す候補の基準」で明示棚卸しされ user 確認済
- [ ] reviewer approve (テスト設計レビュー)
- [ ] count smoke (agents/skills) + 既存 smoke regression 0
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> context bloat が rule 本文だけでなく agents 144 / skills 63 の action space 肥大で起きている問題を解消するため、使用頻度 + 責務重複 + project 固有性 + deterministic 化可否で棚卸しし long-tail を archive / user scope へ退避 (復帰経路つき) する。完成すれば自動選択の入口 (description) が縮小し、必要な action を選びやすくなり、能力を失わずに常時 context と判断負荷が下がる。

## 背景・目的

draft §3 P2「context bloat は action space の肥大で起きている」+ §4.4。検証で agents 144 / skills 63 (draft 45 は過小、実測 63) / commands 59 を確認。Claude Code は skills / subagents の description を自動選択に使うため、本文が遅延 load でも選択肢の多さが毎回の判断負荷になる。

## 設計

draft §4.4「agents / skills 棚卸し手順」(5 step) + 「残す候補の基準」table + 「description のルール」+ 「分類案」(project-critical / occasionally useful / historical / deterministic task) を SSoT とする。**削除でなく退避 (復帰経路必須)**。数値は hard fail でなく regression budget (warn)。

## TDD 戦略

### RED
- count smoke (`agents count <= 25` / `skills count <= 12`) を warn budget で先に書き、現状 144 / 63 で warn させる。

### GREEN
- 棚卸し結果に基づき archive / user scope へ移動 (subagent 委譲、staging 戦略)。**移動先の復帰検証も smoke に含める**。

### REFACTOR
- 重複 description の統合、CommonRules invariant kernel 化。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 使用頻度集計 (docs/tasks/transcripts/settings の agent/skill 参照回数) + 責務重複 / project 固有性 / deterministic 化可否でタグ付け | 1.0h | task-69 |
| 2 | 🔲 | 残す / 外す判断を draft §4.4 基準で確定 → **user に棚卸し結果を提示して承認** (削減対象は harness 運用方針に関わるため) | 0.5h | Step 1 |
| 3 | 🔲 | 外す agent / skill を archive / user scope へ移動 + 復帰コマンドを docs に記載 | 1.5h | Step 2 |
| 4 | 🔲 | deterministic 化できる agent (config parity / inventory 等) を script / command 化 | 1.0h | Step 2 |
| 5 | 🔲 | `CommonRules.md` invariant kernel 化 (<=150 行目標、詳細 rules-details 参照) + description ルール適用 | 0.8h | Step 3 |
| 6 | 🔲 | count smoke (agents<=25 / skills<=12 warn budget) + 移動先復帰検証 smoke | 0.6h | Step 3,4,5 |
| 7 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、**能力喪失リスク (退避で必要 agent が discover 不能化しないか) を最重点 cross-check** | 0.5h | Step 1-6 |
| 8 | 🔲 | (テスト合格) 全 smoke regression 0 + 主要 workflow で退避後も必要 agent/skill が起動可能なことを確認 | 0.5h | Step 7 |
| 9 | 🔲 | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — 重複 description 統合の最終整理 | 0.4h | Step 8 |

合計: **~6.8h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/agents/*` (退避) + `.claude/skills/*` (退避) + `.claude/CommonRules.md` (kernel 化) + archive ディレクトリ新設 + 復帰 docs + `.claude/tests/` (count + 復帰 smoke) |
| migration | agent / skill の物理移動 (削除なし、archive / user scope)。**install.sh の配布対象も連動更新が必要** |
| 環境変数 | 既存不変 |
| 互換性 | 退避した agent / skill は自動選択対象から外れる (明示復帰可能)。**戦略判断要素**: 残す / 外すの最終確定は Step 2 で user 承認必須 (harness 運用方針) |
