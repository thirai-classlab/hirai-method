<!--
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
retroactive: true
-->

# Task #40: タスク管理ルール拡張 (依存先 + review 反復) + 規範違反防止 hook 機械強制化

> Status: **🔄 進行中** (Step 1+2 ✅ 完了 / Step 3 🔄 進行中 / Step 4-9 🔲 未着手)
> 起案: 2026-05-26 (retroactive)
> 関連: #21 (system-reminder-attention、`draft-flow-guard.sh` 新設の起源)
> 設計起源: [`docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md`](../draft/task-mgmt-rules-with-draft-flow-enforcement.md)

## Task ゴール

本 session 規範違反 (規範変更時の `docs/draft/` 起案 + `/new-task` skip 違反) の retroactive リカバリ + 再発防止のため、ルール 1 (依存先タスク列 + 必読義務) + ルール 2 (reviewer 3+ / CRITICAL+HIGH+MEDIUM=0 反復) を規範化し、`draft-flow-guard.sh` を `.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` に拡張する。完成すれば AI が規範変更時に draft 経由なしで直接 Edit すると hook が BLOCK し、本 session 規範違反パターンが再発しなくなる。

## Task 依存先タスク (本ルール 1 自己適用)

— (依存なし)

## Task 作業概要

採用 6 条 (Task=Phase=N Step、Phase 中間階層廃止) 準拠。draft §3 採用案の 6 件:

- (a) 規範追記: `modes.md` 遵守事項 2 例外条項を強化 + CLAUDE.md Critical Lessons HIGH 級教訓追加
- (b) hook 拡張: `draft-flow-guard.sh` を `.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` を block 対象に追加 (対応 draft `approved_at` 非空 で pass、retroactive case 対応、bypass env)
- (c) dogfooding: 本 task 自身を新ルール 1 (依存先) + 新ルール 2 (review 反復) の最初の適用例とする (本 retroactive draft + reviewer 3+ レビュー)
- (d) smoke test 新設: `.claude/tests/rule-change-draft-flow-guard-smoke.sh` (5+ cases)
- (e) regression 検証: 既存 `draft-flow-guard.sh` の `docs/` 直下 block (task-21 W2.3) 回帰 0
- (f) audit: `bypass_log_summary` で新 bypass env (`ECC_RULE_CHANGE_GUARD_OFF=1`) の発火痕跡を再発検知

## Task 完了条件 (DoD)

draft §6 DoD 全 9 項目:

- [ ] 新 path pattern (`.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md`) への draft 経由なし Edit が `draft-flow-guard.sh` で BLOCK される
- [ ] 対応 draft (`approved_at` 非空) ありなら pass、`retroactive: true` の retroactive draft も pass
- [ ] bypass env (`ECC_RULE_CHANGE_GUARD_OFF=1`) で 1 セッション OFF、`bypass.log` 記録
- [ ] smoke `.claude/tests/rule-change-draft-flow-guard-smoke.sh` 全 PASS (5+ cases)
- [ ] 既存 `draft-flow-guard.sh` の `docs/` 直下 block (task-21 W2.3) 回帰 0
- [ ] `modes.md` 遵守事項 2 例外条項に新 entry 追加 (grep 検証)
- [ ] `CLAUDE.md` Critical Lessons「hook で完全 BLOCK 強制済の旧教訓」section に新 entry 追加 (grep 検証)
- [ ] 本 task が `docs/tasks/list.md` に行追加され、依存先列に — (依存なし) 記入、本 task ファイル `task-40-task-mgmt-rules-with-draft-flow-enforcement.md` 存在
- [ ] §8 レビューサイクル table (draft) に iter 1+ 記録 (reviewer 3+ / CRITICAL+HIGH+MEDIUM=0 収束 / 上限 5 以内)

## Task 概要欄 (list.md 用)

本 session 規範違反 (規範変更時の `docs/draft/` 起案 + `/new-task` skip 違反) の retroactive リカバリ + 再発防止のため、ルール 1 (依存先タスク列 + 必読義務) + ルール 2 (reviewer 3+ / CRITICAL+HIGH+MEDIUM=0 反復) を規範化し、`draft-flow-guard.sh` を `.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` に拡張する。完成すれば AI が規範変更時に draft 経由なしで直接 Edit すると hook が BLOCK し、本 session 規範違反パターンが再発しなくなる。

## 背景・目的

本 session 中、user 指示「タスク管理にルール追加 (1. 依存先タスク列 + 必読義務 / 2. draft レビュー最低 3 体・CRITICAL+HIGH+MEDIUM=0 まで反復)」+ user 承認を受けたあと、main agent が `docs/draft/` 起案 + `/new-task` を skip して直接 6 file 規範編集に着手 (10 Edit)。`task-management.md` §「設計→承認→タスク追加フロー」step 2-4 を skip した規範違反が発生した。

真因 3 階層 (draft §1):

1. main agent が「規範変更 = 戦術判断 (Loop モード自律実行可)」と誤判定 (実際は `modes.md` 遵守事項 2 例外条項対象)
2. `draft-flow-guard.sh` が `docs/` 直下のみカバーで `.claude/rules/*.md` 等を見ていない構造 gap
3. CLAUDE.md Critical Lessons から hook BLOCK 強制済 3 教訓を本 session 直前に slim 化した際、本 case (規範変更 draft 経路必須) の教訓を hook 化なしで委譲 section に集約せず、結果として「規範変更は honor system」状態が続いていた

user 指示「これが起きないようにしてください (機械強制 hook 追加)」+ retroactive リカバリ承認「A」により、本 retroactive task で:

- 規範文書のみ追記 (案 A) でなく機械強制 hook 拡張 (案 B) を含む **C ハイブリッド** を採用 (draft §2 案比較)
- 本 task 自身を新ルール 1 (依存先列) + 新ルール 2 (review 反復) の最初の適用例として dogfooding 検証

## 仕様（要決定 → 決定済）

### Q1: hook 機械強制化 vs 規範文書のみ

| 案 | 内容 | 評価 |
|---|---|---|
| A | 規範追記のみ (honor system) | 軽実装だが「ルールに書いて守らせる」default、再発確実 |
| B | hook 拡張のみ | 機械強制だが文書化なしで bypass 乱用される |
| **C ハイブリッド** | A + B 段階: 規範追記 + hook 拡張 + dogfooding | 3 層で再発防止、本 task 自身が新ルール 1/2 の妥当性検証 |

→ **C ハイブリッド** 採用。理由: 「これが起きないように」(user 指示) の核心は機械強制、規範追記 + hook + dogfooding の 3 層で再発防止 + 本 task 自身を新ルール最初の適用例として規範妥当性検証可能。

## 設計

draft §3 採用案を参照。主要要素:

### `draft-flow-guard.sh` 拡張仕様 (draft §3 Step 4 詳細)

```text
[追加 path pattern]
- .claude/rules/*.md
- .claude/commands/*.md
- .claude/templates/docs/{tasks,draft}/*.md
- .claude/templates/**/*.md (より広い場合)

[追加判定ロジック]
1. tool_input.file_path が上記 pattern に match
2. slug 抽出: file basename or path から推定
3. 対応 draft (`docs/draft/<slug>.md` for the change scope) 検索
4. draft frontmatter `approved_at` が非空 → pass
5. draft 不在 or `approved_at` 空 → BLOCK + 「先に /new-draft <slug> で設計を起こせ」案内
6. retroactive case (frontmatter `retroactive: true`) → pass + warn 注入 ("retroactive draft 経由、規範遵守は次回から")

[bypass]
- ECC_RULE_CHANGE_GUARD_OFF=1 (1 セッション全体 OFF、bypass.log 記録)
- /gate-bypass <file path> (1 ファイル分 pre-clear)
- HC_RULE_CHANGE_GUARD_ENABLED=false (config レベル OFF)
```

### 規範文書更新 (draft §3 Step 5)

- `.claude/rules/modes.md` 遵守事項 2 例外条項に追加: 「規範変更 (`.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` への Edit/Write) は user 承認必須、`draft-flow-guard.sh` が機械強制 BLOCK」
- `CLAUDE.md` Critical Lessons「hook で完全 BLOCK 強制済の旧教訓」section に追加: 「**`.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/**/*.md` を draft 経由なしで直接 Edit/Write しない** → `draft-flow-guard.sh` 拡張 (本 task で実装)、bypass: `ECC_RULE_CHANGE_GUARD_OFF=1`」

## TDD 戦略

規範変更 + hook 実装の組合せで unit test + smoke + grep 検証の 3 層構成。

### RED（先に追加するテスト）

- `.claude/tests/rule-change-draft-flow-guard-smoke.sh` 新設 (5+ cases)
  - Case 1: `.claude/rules/foo.md` Edit で対応 draft `docs/draft/foo.md` 不在 → BLOCK 期待
  - Case 2: 対応 draft `docs/draft/foo.md` あり (`approved_at` 非空) → pass 期待
  - Case 3: `approved_at` 空 → BLOCK 期待
  - Case 4: retroactive draft (`retroactive: true`) → pass + warn 注入期待
  - Case 5: bypass env `ECC_RULE_CHANGE_GUARD_OFF=1` → pass 期待
  - Case 6 (regression): 既存 `docs/` 直下 block (task-21 W2.3) 動作維持確認

### GREEN（最小実装）

- `.claude/hooks/draft-flow-guard.sh` 拡張: 新 path pattern + retroactive draft case + bypass env を追加 (subagent 委譲 + staging 戦略必須、`.claude/hooks/` は protected_paths_code)
- `.claude/rules/modes.md` + `CLAUDE.md` に new entry 追加 (grep 検証 PASS)

### REFACTOR

- 3 観点 (持続可能性 / 汎用性 / 非冗長化) で hook 拡張部の判定 (skip 想定: 規範違反防止が core 目的で refactor 余地少)

## Step 計画 (採用 6 条準拠、本ルール 1 「依存先タスク」を自己適用)

| Step | Status | 作業概要 | 完了条件 | 依存 |
|:---:|:---:|:---|:---|:---|
| 1 | ✅ | ルール 1 (依存先タスク列 + 必読義務) を 3 file (task-management.md / _TASK_TEMPLATE.md / list.md template) に規範化 | grep `依存先` で 3 file hit (本 session ターン完了済、10 Edit のうち相当分) | — |
| 2 | ✅ | ルール 2 (reviewer 3+ / 反復) を 3 file (workflow.md / _DRAFT_TEMPLATE.md / design-review.md) に規範化 | grep `収束条件` で 3 file hit、`_DRAFT_TEMPLATE.md` §8 新設確認 (本 session ターン完了済) | — |
| 3 | 🔄 | retroactive draft 起案 (本 file 元 draft) + `/new-task` で list.md 反映 (本ルール 1 dogfooding、依存先列に — 記入) | `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md` 存在 + `docs/tasks/task-40-*.md` 存在 + list.md task-40 行 append (10 行: header + Step 1-9) | Step 1, 2 |
| 4 | 🔲 | `draft-flow-guard.sh` 拡張: 新 path pattern (`.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/**/*.md`) を block 対象に追加、対応 draft (`docs/draft/<slug>.md` で `approved_at` 非空) 存在で pass、bypass `ECC_RULE_CHANGE_GUARD_OFF=1` | smoke 新 5 case 全 PASS + 既存 `docs/` 直下 block (task-21 W2.3) 回帰 0 | Step 3 |
| 5 | 🔲 | `modes.md` 遵守事項 2 例外条項に「規範変更 (`.claude/rules/*.md` 等)」を明示追加 + CLAUDE.md Critical Lessons HIGH 級教訓追加 (hook BLOCK 強制済) | `grep "規範変更" .claude/rules/modes.md` 1+ hit + `grep "ECC_RULE_CHANGE_GUARD_OFF" CLAUDE.md` 1+ hit | Step 4 |
| 6 | 🔲 | smoke test 新設 (`.claude/tests/rule-change-draft-flow-guard-smoke.sh`): N cases (新 path pattern block / 対応 draft あり pass / bypass env / retroactive case / 既存 docs/ block 回帰 0) | smoke 全 PASS (exit 0) | Step 5 |
| 7 | 🔲 | (テスト設計レビュー、本ルール 2 dogfooding) reviewer 3+ 並列、CRITICAL+HIGH+MEDIUM=0 まで反復 (上限 5)、draft §8 レビューサイクル table に iter 記録 | iter 1+ 実施 + 全 reviewer approve / CRITICAL+HIGH+MEDIUM=0 収束 | Step 6 |
| 8 | 🔲 | (テスト合格) smoke 全 PASS + 既存 regression 0 + grep 検証 (CLAUDE.md 教訓 + modes.md 例外条項) | 上記 3 検証全 PASS | Step 7 |
| 9 | 🔲 | (リファクタリング) 3 観点判定 (持続可能性 / 汎用性 / 非冗長化)、不要なら skip 明示 | skip 想定の場合 `skip: <理由>` 明示記録 | Step 8 |

## 工数見積

- Step 1+2 (完了): 1.0h
- Step 3-9 (残): 3.6h
- **合計: 4.1h** (本 session で Step 3 完遂、Step 4-9 は次 session 持ち越し想定)

## 影響範囲

draft §10 関連 file list:

| 範囲 | 詳細 |
|---|---|
| ファイル (規範) | `.claude/rules/task-management.md` / `.claude/rules/modes.md` / `.claude/rules/workflow.md` / `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` / `.claude/templates/docs/tasks/list.md` / `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` / `.claude/commands/design-review.md` / `CLAUDE.md` |
| ファイル (hook) | `.claude/hooks/draft-flow-guard.sh` (拡張) |
| ファイル (test) | `.claude/tests/rule-change-draft-flow-guard-smoke.sh` (新設) |
| ファイル (task 管理) | `docs/tasks/list.md` / `docs/tasks/task-40-task-mgmt-rules-with-draft-flow-enforcement.md` / `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md` |
| migration | なし |
| 環境変数 | `ECC_RULE_CHANGE_GUARD_OFF=1` (新 bypass) / `HC_RULE_CHANGE_GUARD_ENABLED=false` (新 config) |
| 互換性 | 既存 `draft-flow-guard.sh` の `docs/` 直下 block (task-21 W2.3) は維持 (回帰 0)、新 path pattern は追加のみ |

## 再発防止

- 本 task 完了後、規範変更時の draft 経由なし直接 Edit は `draft-flow-guard.sh` で機械強制 BLOCK
- bypass 経路 (`ECC_RULE_CHANGE_GUARD_OFF=1`) は audit log 記録、`/harness-audit` で再発検知可能
- 本 task が新ルール 1 (依存先列) + 新ルール 2 (review 反復) の最初の dogfooding 例として、後続 task の参考事例として保存

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-26 | 起案 | 設計 draft 起こし (retroactive、`frontmatter retroactive: true`) |
| 2026-05-26 | Step 1+2 完了 | 本 session 前半で 10 Edit 実施済 (規範化のみ、draft 起案 / list.md 反映なしの規範違反状態) |
| 2026-05-26 | Step 3 進行中 | 本 subagent で retroactive draft + task file + list.md 反映を実施 |
| (TBD) | Step 4-9 着手 | 次 session 持ち越し想定 (4-9 残 3.6h) |
| (TBD) | 完了 | commit `<sha>`、+<N> tests、PR `<URL>` |

## 派生 task / 次アクション候補

なし (本 session 規範違反は本 task で直接管理、副産物 entry 起票不要)。

## 関連

- Draft: [`task-mgmt-rules-with-draft-flow-enforcement.md`](../draft/task-mgmt-rules-with-draft-flow-enforcement.md)
- 依存タスク: なし (Task 依存先タスク 欄参照)
- 派生タスク: なし
- 既存規範: [`task-management.md`](../../.claude/rules/task-management.md) §「設計→承認→タスク追加フロー」(本 task で違反した規範) / [`modes.md`](../../.claude/rules/modes.md) 遵守事項 2 例外条項
- 既存 hook: [`draft-flow-guard.sh`](../../.claude/hooks/draft-flow-guard.sh) (本 task で拡張対象、task-21 W2.3 起源)
- 関連完遂タスク: task-21 (system-reminder-attention、`draft-flow-guard.sh` 新設の起源)
- 副産物 registry: [`next-actions.md`](next-actions.md) (本 session 違反は entry 化せず本 retroactive draft で直接管理)
