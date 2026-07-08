---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #103: 規範文書 SSoT 整合 (docs↔effective pointer 化) (P3-6/I1/W2-1)

> Status: **🔲 未着手**
> 起案: 2026-07-08 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I1 / §5 P3-6
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I1 + §5 P3-6

## Task ゴール

`.claude/rules/{modes,task-management,workflow,development-process,self-improvement,git-workflow,why-x5-output}.md` (7 file) 冒頭に **preset pointer 1 行** (「現 effective preset は `bash .claude/scripts/hc-config.sh --summary` で確認。BLOCK 記述は preset 依存 (harness-dev では advisory)」) を追加。BLOCK 記述の 15 箇所 (`grep -cE 'BLOCK|block' .claude/rules/*.md 実測`) から effective state 参照式 (`hc-config.sh --summary`) へ寄せる。完成すれば docs↔effective 乖離が SSoT 1 行に集約され、AI の読み違い萎縮 (memory [[feedback_iter_approve_design_drift_user_verify]] 派生の drift 認識問題) が構造解消する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-88 | **hard**。task-88 で SessionStart hook が hc-config --summary 全文注入するので、本 task の pointer 1 行と重複しない (pointer は AI が Read 時に見る用、summary 注入は session 起動時) | (list.md #88 参照、PR merged 済) |
| task-97 | **hard**。task-97 で拡張された 23 guards の docs_claim と本 task の BLOCK 記述整合を最終検証 | [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) |

## Task 作業概要

- 7 rule file 冒頭 (Layer B Read trigger の直後、または最初の `##` 前) に preset pointer 1 行を統一 format で追加
- BLOCK 記述 15 箇所を grep で列挙 → 各記述に **preset aware badge** (「⚠️ preset dependent、harness-dev では advisory」) を suffix 追加、または effective 参照 (`docs/SELF_IMPROVEMENT.md` §「preset 制御」への link 化)
- `_TASK_TEMPLATE.md` / `_DRAFT_TEMPLATE.md` に preset pointer 1 行の項目追加 (新規 task/draft が SSoT 整合を継承)
- 新規 smoke `.claude/tests/normative-ssot-integrity-smoke.sh` 3 case (A: 7 rule file に pointer 存在 / B: BLOCK 記述に preset aware badge / C: template 継承)
- docs 反映: `docs/SELF_IMPROVEMENT.md` §「preset 制御」の updated pointer + `docs/INVENTORY.md` (本 smoke 追加)

## Task 完了条件 (DoD)

- [ ] 7 rule file 全てに preset pointer 1 行存在: `grep -lE '現 effective preset は.*hc-config.sh --summary' .claude/rules/*.md | wc -l >= 7`
- [ ] BLOCK 記述 15 箇所全てに preset aware badge or pointer link: `grep -cE 'BLOCK.*preset|preset aware|preset dependent' .claude/rules/*.md >= 15`
- [ ] `_TASK_TEMPLATE.md` + `_DRAFT_TEMPLATE.md` に preset pointer 項目 grep hit
- [ ] `normative-ssot-integrity-smoke.sh` 3/3 PASS
- [ ] Wave 1-4 全 smoke regression 0
- [ ] `hc-config.sh --summary` 出力の canonical 参照式が docs で統一 (旧「`bash .claude/scripts/hc-config.sh --list`」等 legacy 記述 0)
- [ ] docs 反映: `docs/SELF_IMPROVEMENT.md` + `docs/INVENTORY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

規範本文の BLOCK 表記と effective state の二重 SSoT を解消するため規範文書冒頭に preset pointer 1 行を追加し effective state 参照式 (hc-config.sh --summary) へ寄せる。完成すれば docs↔effective 乖離 15 箇所が SSoT 1 行に集約され AI の読み違い萎縮が構造解消する。

## Step 計画 (SSoT: master roadmap §5 P3-6 + §3 I1)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 7 rule file 冒頭に preset pointer 1 行追加 (統一 format) | 2h | — |
| 2 | 🔲 | BLOCK 記述 15 箇所に preset aware badge or pointer link 追加 | 4h | Step 1 |
| 3 | 🔲 | `_TASK_TEMPLATE.md` + `_DRAFT_TEMPLATE.md` に preset pointer 項目追加 (新規 task/draft 継承) | 1.5h | Step 1 |
| 4 | 🔲 | 新 smoke `normative-ssot-integrity-smoke.sh` 3 case + run-all-smokes 登録 (parity) | 3h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h | Step 4 |
| 6 | 🔲 | (テスト合格 + リファクタリング) 全 smoke PASS + 3 観点判定 | 1.5h | Step 5 |

合計: 13.5h ≒ 1.7 day (roadmap 3 day 見積内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済、docs/tasks/task-103-*.md 生成、list.md #103 📝 → 🔲 update |
| 2026-07-08 | 完了 | Wave 5 Workflow wf_070a6dcf-dc2 経由。7 rule files (modes / task-management / workflow / development-process / self-improvement / git-workflow / why-x5-output) 冒頭に preset pointer 1 行統一 format 追加 (DoD A: 7/7 files matched)。BLOCK 記述に preset aware badge 追加 total=25 (DoD B: >= 15 達成)。_TASK_TEMPLATE.md + _DRAFT_TEMPLATE.md に preset pointer 追加 (DoD C: PASS)。normative-ssot-integrity-smoke 3/3 PASS (Case A pointer / B badge / C template)。Step 1-6 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) preset pointer format の統一 (`.claude/rules-details/preset-pointer.md` fragment 化) — Step 1 で判定
- [ ] (🟢) BLOCK 記述の legacy pattern audit (`grep 'BLOCK'` で false positive 除外方法) — Step 2 で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I1 + §5 P3-6
- 起源 memory: [[feedback_iter_approve_design_drift_user_verify]] (drift 認識問題)
- 依存 task (hard): task-88 (SessionStart summary 注入) / [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) (23 guards docs_claim 整合)
