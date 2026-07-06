---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #94: BLOCK message 4 引数統一 lib/block-message.sh (P2-3/I6/W1-12)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり event 別 3 variant + warn + info の 5 関数明示 API 採用、self-doctor 5→4 args migration 承認)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §5 P2-3 / §11.3 R1 / §11.2 3 点提示 / §11.3 R2 / §11.3 R5 / §11.3 R6
> 設計起源: [lib-block-message-4args.md](../draft/lib-block-message-4args.md)

## Task ゴール

`.claude/hooks/lib/block-message.sh` 新設 (5 関数 = event 別 3 variant `emit_block_pretool` / `emit_block_stop` / `emit_block_subagent` + `emit_warn` + `emit_info`、共通 4 args = `<why> <fix_one_liner> <bypass_env> <docs_link>`)。既存 7 hook (PreToolUse × 5 + Stop × 1 + SubagentStop × 1) + self-doctor.sh が単一 lib source に置換され、pre-commit grep policy が raw 直書き BLOCK を機械検出可能な状態を達成する。`emit_block_stop` は JSON stdout emission を明示 disable、event 別 semantic の誤 caller を実装層で排除。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-92 | **hard**。Step 4 で pre-commit grep policy layer を追加する consumer 側 (task-92 の pre-commit 骨格が前提)。task-92 未 merge の間は grep 検査 skip で fail-open。pre-commit 内 `_pc_emit_*` 3 helper を本 lib の event 別 variant へ 1:1 migration (`sed 's/_pc_emit_/emit_/g'`) | [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) |

**task-87 self-doctor SSoT 三重不整合** (2026-07-06 実測、draft §前提): 本 branch (`docs/phase2-drafts` HEAD `c61402f`) 上に `.claude/scripts/self-doctor.sh` **不在**、list.md L244 task-87 = 🔲、addendum §11.1 は PR #73 merged と記載。Step 3 (self-doctor migration) は task-87 の本 branch reflect を **hard dependency** とし、reflect 前は Step 3 のみ defer (Step 1/2/4-8 は独立実装可)。draft §未決事項 3 の 3 選択肢 (a 先行完遂 / b PR #73 cherry-pick / c Step 3 defer) は着手前 `/start-task 94` 段で user 判断確定。

## Task 作業概要

- `.claude/hooks/lib/block-message.sh` 新設 (5 関数 = 3 event 別 variant + warn + info、subshell 関数化 + jq fallback + 4 args sanitize)
- 全 7 hook を lib source + `emit_block_<event>` / `emit_warn` / `emit_info` 経由に置換 (event 別 exit code semantic 現状維持)
- self-doctor.sh 5→4 args migration (task-87 reflect 完了後、`_sd_warn` wrapper で `d_id` / `title` prefix 吸収)
- pre-commit grep policy layer 追加 (`.githooks/pre-commit`、task-92 完了後有効化、grep pattern は `.claude/hooks/*.sh` 限定)
- 新規 smoke `.claude/tests/lib-block-message-smoke.sh` 7 case (A-G、case F/G は event 別 semantic 検証)

## Task 完了条件 (DoD)

- [ ] lib 新設 + 5 API 契約: `bash -c 'source .claude/hooks/lib/block-message.sh; declare -f emit_block_pretool emit_block_stop emit_block_subagent emit_warn emit_info | wc -l'` >= 5
- [ ] 全 7 hook migration: `grep -l 'lib/block-message.sh' .claude/hooks/*.sh | wc -l` >= 7
- [ ] event 別 variant 誤 caller 0 件: (a) PreToolUse hook で `emit_block_stop` / `emit_block_subagent` 呼出 0 / (b) Stop hook (byproduct-discharge-guard) で `emit_block_pretool` / `emit_block_subagent` 呼出 0 / (c) SubagentStop hook (confidence-gate) で `emit_block_pretool` / `emit_block_stop` 呼出 0
- [ ] raw 直書き排除: `grep -lE '(printf.*"BLOCK|cat <<.*EOF.*BLOCK)' .claude/hooks/*.sh | xargs grep -L 'lib/block-message.sh' | wc -l` == 0
- [ ] self-doctor migration (task-87 reflect 済前提、未 reflect 時は skip 記録): stderr label 4 種 (`why:` / `fix:` / `silence:` / `docs:`) が lib 由来と一致
- [ ] 新 smoke 全 case (A-G) PASS: `bash .claude/tests/lib-block-message-smoke.sh` → `PASS 7 / FAIL 0`
- [ ] 既存 smoke regression 0 (gateguard / confidence-gate / autonomous-action-guard / draft-flow-guard / byproduct-discharge-guard の各 smoke 全 PASS)
- [ ] pre-commit grep policy (task-92 完了後): `.githooks/pre-commit` に §4.4 layer 存在 + 意図的違反 fixture で non-zero exit
- [ ] fail-open 契約: `grep -c '^set -\(e\|euo\)' .claude/hooks/lib/block-message.sh` == 0 (file-top `set -e` 系 0 件)
- [ ] docs 反映: `.claude/rules/development-process.md` に「BLOCK は lib 経由必須 + event 別 variant 明示」+ hook event ↔ variant mapping 3 行追記、README または `docs/INVENTORY.md` の hook lib 一覧に本 lib entry (grep 総計 >= 3)
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

roadmap §2.3 「BLOCK 教育 3 点提示」の hook 間 drift (JSON stdout / stderr + exit 2 の 2 分裂) と復旧 1 行 / bypass env / docs_link 未提示率を解消するため、`.claude/hooks/lib/block-message.sh` を event 別 3 variant + warn + info の 5 関数 API で新設し全 hook + self-doctor を lib 経由に置換 + pre-commit grep policy で raw 直書きを機械禁止する。完成すれば BLOCK 時に AI が復旧 1 行 / bypass env / docs pointer を必ず得られて自律継続できるようになり、event 別 semantic (PreToolUse / Stop / SubagentStop) の誤 caller が実装層で排除される。

## Step 計画 (SSoT: draft §3.7 「Task 計画」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `.claude/hooks/lib/block-message.sh` 新設 (5 関数 = event 別 3 variant + warn + info、subshell 関数化 + jq fallback + 4 args sanitize、§3.1 event 別契約 table SSoT、`emit_block_stop` の JSON stdout emission 明示 disable) | 0.5d | — |
| 2 | 🔲 | 全 7 hook migration (gateguard / confidence-gate / autonomous-action-guard / task-rule-guard / draft-flow-guard / workflow-guard / byproduct-discharge-guard を lib source + emit_* 経由に置換、§3.5 exit code policy 準拠) | 0.6d | Step 1 |
| 3 | 🔲 | self-doctor.sh 5→4 args migration (§3.6、task-87 reflect 完了想定、未 reflect 時は defer) | 0.3d | Step 1 (task-87 reflect) |
| 4 | 🔲 | pre-commit grep policy layer 追加 (§4.4、task-92 完了後有効化、grep pattern `.claude/hooks/*.sh` 限定) | 0.3d | Step 2, task-92 |
| 5 | 🔲 | 新規 smoke `.claude/tests/lib-block-message-smoke.sh` 7 case (A-G、addendum §11.3 R2 fast smoke `parity/fast`、case F/G で event 別 semantic 検証) | 0.3d | Step 1 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (`hc-config.sh --get review_max_count_test` 上限確認)、reviewer prompt 必須項目 = Stop/SubagentStop hook 移行後の `{decision:"block"}` semantics 変化検証 + event 別 variant caller 整合 grep + `_emit_stderr_4lines` 内部 helper 経路の存在確認 | 0.3d | Step 5 |
| 7 | 🔲 | (テスト合格) 新 smoke 7/7 + 既存 hook smoke regression 0 (UI 無し task のため E2E/visual 対象外) | 0.2d | Step 6 |
| 8 | 🔲 | (リファクタリング) 3 観点 (持続可能性 / 汎用性 / 非冗長化 — 特に `confidence-gate/messages.sh` の `build_*_reason` 群を本 lib への fold 判定)、不要なら `skip: <reason>` 明示 | 0.2d | Step 7 |

合計: 2.7 day (roadmap P2-3 見積 2 day + task-92 依存 pre-commit grep policy + 既存 messages.sh 非冗長化検討)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/lib-block-message-4args.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり event 別 3 variant 命名 = function 名 embed 型採用、self-doctor 5→4 args migration 承認、pre-commit grep false positive の bypass env 承認) |
| 2026-07-06 | タスク化 | `/new-task 94 lib-block-message-4args`、list.md #94 📝 → 🔲 update、docs/tasks/task-94-*.md 生成 |
| 2026-07-07 | 完了 | Wave 2 Workflow wf_ac31538c-e9c 経由で lib/block-message.sh 新設 (5 API: emit_block_pretool/stop/subagent + emit_warn/info) + 7 hook migration (autonomous-action-guard / byproduct-discharge-guard / confidence-gate / draft-flow-guard / gateguard / task-rule-guard / workflow-guard) + self-doctor 5→4 args + pre-commit grep policy layer。lib-block-message-smoke 7/7 (A-G) + byproduct-discharge-guard-smoke 4/4 (A-D、Stop hook migration regression gate) PASS。既存 hook smoke (confidence-gate 5/5 PASS 等) regression 0。Step 1-8 全 ✅ |

## 派生 task / 次アクション候補

Draft §未決事項からの初期 candidate:

- [ ] (🟢) `confidence-gate/messages.sh` の `build_*_reason` fold 判定 — Step 8 refactor で確定 (推奨: 残置、fold すると lib が domain 知識を持ち込み汎用性を損なう)
- [ ] (🟢) exit 2 系 hook の JSON stdout + exit 2 重複解釈の Claude Code 実測検証 — Step 1 実装レビュー時に確定 (起きる場合は `_emit_stderr_4lines` 内部 helper 経路採用)
- [ ] (🟢) task-87 self-doctor 本 branch reflect の 3 選択肢 (a 先行完遂 / b PR #73 cherry-pick / c Step 3 defer) — `/start-task 94` 前に user 判断確定

## 関連

- Draft: [lib-block-message-4args.md](../draft/lib-block-message-4args.md)
- 依存 task (hard): [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) (pre-commit 骨格 + `_pc_emit_*` 1:1 migration)
- SSoT 三重不整合対象 task: task-87 (P1-3 self-doctor、addendum §11.1 PR #73 merged 記載 vs 本 branch `.claude/scripts/self-doctor.sh` 不在の drift 解決が Step 3 前提)
- 関連 memory: [[feedback_set_e_in_sourced_libs]] (subshell 関数化根拠) / [[feedback_config_value_needs_consumer_and_smoke]] (I7 triplet)
