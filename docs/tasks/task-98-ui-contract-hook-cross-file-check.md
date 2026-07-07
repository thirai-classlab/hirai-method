---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #98: UI Contract hook + cross-file contract check (P3-1/I4/W1-11)

> Status: **🔲 未着手**
> 起案: 2026-07-07 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I4 / §5 P3-1
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I4 + §5 P3-1

## Task ゴール

UI 拡張子変更 (`.tsx` / `.jsx` / `.vue` / `.svelte` / `.html` / `.css`) を含む task で、`.claude/hooks/ui-contract.sh` (PostToolUse: Edit/Write) + `.claude/scripts/cross-file-contract-check.sh` + `/finish-task` 機械検証を新設し、cross-file 契約 SSoT (id / symbol / API 名) + visual artifact 記録 を強制する。完成すれば並列 subagent の cross-file 契約乖離 (memory [[feedback_parallel_subagent_cross_file_contract_drift]] 実証) が commit 前に検出され、visual regression が構造防止される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-92 | **soft**。pre-commit template が Wave 1 で配布済、本 task の contract check pre-commit 統合の consumer になる可能性 (Step 3 で判定) | [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) |

## Task 作業概要

- `.claude/hooks/ui-contract.sh` 新設 (PostToolUse: Edit/Write、UI 拡張子検出 + cross-file-contract-check.sh 呼出、fail-open)
- `.claude/scripts/cross-file-contract-check.sh` 新設 (id / symbol / API 名の cross-file grep 検証、SSoT contract file を `.claude/contracts/*.yml` から参照、または git diff 対象 file 内の相互参照 assert)
- `/finish-task` に UI task の visual artifact 記録義務追加 (`docs/tasks/<task>-visual-*.png` 存在確認 or bypass 明示)
- 新 smoke `.claude/tests/ui-contract-smoke.sh` (case A-E、id mismatch fixture / symbol drift fixture / visual artifact 不在 / bypass env / fail-open)
- `harness-config.yml` に `feature_ui_contract_enabled` toggle + docs 反映

## Task 完了条件 (DoD)

- [ ] `.claude/hooks/ui-contract.sh` 存在、PostToolUse:Edit/Write で発火、UI 拡張子検出時 cross-file-contract-check 呼出
- [ ] `.claude/scripts/cross-file-contract-check.sh` 存在、id / symbol / API 名の cross-file assert 実装
- [ ] harness-config.yml の enforcement_matrix に `ui_contract` guard 登録 (5 field 全備、feature_key = `feature_ui_contract_enabled`)
- [ ] enforcement-mismatch-smoke 6/6 PASS (拡張後 required= set に本 guard 含む)
- [ ] `ui-contract-smoke.sh` 5/5 PASS (case A-E)
- [ ] `/finish-task` に UI task 検出時の visual artifact 存在チェック layer 追加 (`grep -l 'visual-.*\.\(png\|jpg\)' docs/tasks/` or bypass log)
- [ ] docs 反映: `.claude/rules/development-process.md` §並列 subagent cross-file 契約 subsection + `docs/INVENTORY.md` に本 hook + script entry
- [ ] Wave 1-3 全 smoke regression 0 (`bash .claude/tests/run-all-smokes.sh` PASS)
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

並列 subagent の cross-file 契約乖離が visual/E2E でしか出ない問題を解消するため PostToolUse(UI ext) + cross-file-contract-check.sh + finish-task 機械検証を新設し UI 拡張子変更 task に契約 SSoT + visual artifact 記録を強制する。完成すれば id/symbol/API 契約乖離が commit 前に検出され visual regression が構造防止される。

## Step 計画 (SSoT: master roadmap §5 P3-1 + §3 I4)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `.claude/hooks/ui-contract.sh` 新設 (PostToolUse Edit/Write、UI 拡張子 regex 検出 + fail-open) | 3h | — |
| 2 | 🔲 | `.claude/scripts/cross-file-contract-check.sh` 新設 (id / symbol / API 名 cross-file grep assert、`.claude/contracts/*.yml` optional SSoT) | 6h | Step 1 |
| 3 | 🔲 | harness-config.yml enforcement_matrix + feature toggle + settings.json hook 配線 | 2h | Step 1, 2 |
| 4 | 🔲 | `/finish-task` に visual artifact 検証 layer 追加 | 2h | Step 2 |
| 5 | 🔲 | 新 smoke `ui-contract-smoke.sh` (5 case A-E) + `run-all-smokes.sh` behavior category 登録 | 3h | Step 4 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 min ≤ N ≤ max、収束まで反復 | 1.5h | Step 5 |
| 7 | 🔲 | (テスト合格 + リファクタリング) 全 smoke PASS + 3 観点判定 | 1.5h | Step 6 |

合計: 19h ≒ 2.4 day (roadmap 3 day 見積内)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-07 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済 (Phase 3 approach = option A)、docs/tasks/task-98-*.md 生成、list.md #98 📝 → 🔲 update |
| 2026-07-07 | 完了 | Wave 4 Workflow wf_94c193f7-246 経由。ui-contract.sh (PostToolUse:Edit/Write、UI ext 検出 + fail-open) + cross-file-contract-check.sh (id/symbol/API bidirectional grep assert) + ui-contract-smoke 6/6 PASS (Case A/B drift 検出 + Case C hook fires + Case D bypass ECC_UI_CONTRACT_OFF + Case E fail-open + Case F fix loop で追加した WARN 実 emission chain)。feature_ui_contract_enabled toggle + matrix entry 追加。Step 1-7 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) `.claude/contracts/*.yml` optional SSoT format の初期例 (button.tsx ↔ button.test.tsx id contract) — Step 2 で判定
- [ ] (🟢) visual artifact 記録の naming convention (`<task-N>-visual-<state>.png`) 標準化 — Step 4 で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I4 + §5 P3-1
- 起源 memory: [[feedback_parallel_subagent_cross_file_contract_drift]] (task-63 実証、UI 全体非描画事案)
- 依存 task (soft): [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) (pre-commit 統合 optional)
