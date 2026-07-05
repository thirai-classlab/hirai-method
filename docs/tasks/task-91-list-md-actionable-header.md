---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #91: list.md actionable header + plan-first reminder 発火緩和 (P1-7)

> Status: **✅ 完了** (2026-07-05、commit `6321ce7`、DoD 全項目実測 PASS)
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.8 対策 B/C/§5 P1-7
> 設計起源: [list-md-actionable-header.md](../draft/list-md-actionable-header.md)

## Task ゴール

新規 install の template list.md に「ここから着手: `/new-draft <slug>`」actionable header が入り、plan-first reminder が task 行 0 単独 (tier B、短文 5 行、startup/clear 限定) でも発火する — install 直後に AI が空台帳を認識し最初の draft 起案へ誘導される。

## Task 依存先タスク

— (依存なし)

> list.md 旧依存 task-85 は soft (file 領域完全独立、install.sh 変更 0 行が DoD で機械保証) のため削除、並行着手可 (2026-07-05 横断レビュー L1 で確定)。

## Task 作業概要

- template list.md に self-descriptive な削除条件付き actionable header 追加 (本 repo 稼働 list.md は無変更)
- list-md-plan-first-reminder.sh を 2-tier 化 (tier A = 現行 full message 完全維持 / tier B = task 行 0 単独で短文、source gating で resume/compact skip)
- smoke 期待値反転 2 case + 新 case 4 件 (計 13 case、発火系は `HC_FEATURE_TASK_RULE_GUARD_ENABLED=true` per-case 注入) + run-all-smokes note 更新

## Task 完了条件 (DoD)

- [ ] `grep -c 'ここから着手' .claude/templates/docs/tasks/list.md` = 1 (blockquote に `/new-draft <slug>` 含む)
- [ ] `grep -c 'ここから着手' docs/tasks/list.md` = 0 (本 repo 稼働台帳は無変更)
- [ ] tmp fixture (draft 0 + task 0) + env prefix で tier B keyword が stderr 出力
- [ ] stdin `{"source":"resume"}` で stderr 空 (source gating)
- [ ] draft 3 件 fixture で tier A message が 1 文字も変わらず出力 (diff 一致)
- [ ] smoke 13/13 PASS + run-all-smokes 新規 FAIL 0 (environmental note 更新済)
- [ ] `git diff --stat install.sh` が空 (install.sh 変更 0 行)

## Task 概要欄 (list.md 用)

list.md 完全 template で plan-first reminder が発火しない問題 (R4) を解消するため、template に actionable header を追加し reminder hook を 2-tier 化 (task 行 0 単独で短文発火、resume/compact skip) する。完成すれば install 直後に AI が空台帳を認識し最初の draft 起案へ誘導される (install.sh 変更 0 行、#85-#90 と file 独立で並行着手可)。

## Step 計画 (SSoT: draft §3 「Step 計画」+ Step N 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | template list.md に actionable header 追加 (対策 B) | 0.5h | — |
| 2 | ✅ | hook 発火条件 2-tier 化 + tier B source gating (対策 C) | 1.5h | — |
| 3 | ✅ | smoke 期待値反転 2 case + 新 case 4 件 + run-all-smokes note 更新 | 1.0h | Step 2 |
| 4 | ✅ | (テスト設計レビュー) reviewer 動的選定 | 0.5h | Step 3 |
| 5 | ✅ | (テスト合格) smoke 全 PASS + run-all-smokes regression 0 | 0.3h | Step 4 |
| 6 | ✅ | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.2h | Step 5 |

合計: 4.0h (≒ 0.5 day、roadmap P1-7 見積と一致)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、M5 [DoD 13/13 vs expected-fail 矛盾 → env 注入で解消] + L4 [dispatcher 直接起動検証] 修正済) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: tier B に compact 不含 / 遡及挿入見送り / Case 9 保守維持)、list.md 🔲 化 + 依存先 — 化 |
| 2026-07-05 | Step 1-3 完了 | Workflow wf_5408d0a6-00d、template +7 / hook 2-tier +69 / smoke 13 case 化 +273 / run-all note 更新 |
| 2026-07-05 | Step 4-5 完了 | 3 lens review + Fix iter 1 + DoD 全項目 PASS (tier B 発火 / resume 沈黙 / tier A golden diff 一致 / smoke 13/13 / install.sh diff 0) |
| 2026-07-05 | Step 6 完了 | refactor `skip: tier A 完全温存が設計制約のため構造変更余地なし、review 3 lens で非冗長化確認済` |
| 2026-07-05 | 完了 | commit `6321ce7` |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [list-md-actionable-header.md](../draft/list-md-actionable-header.md)
- 相互参照: #88 (tier B は stderr 経路で #88 の footprint cap 非干渉、smoke 衝突なし)
