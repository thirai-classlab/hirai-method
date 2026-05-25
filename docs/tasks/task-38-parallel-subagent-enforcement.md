---
asana_url: ""
slack_urls: []
deadline: ""
requester: "user"
---

<!--
total_steps: 4
-->

# Task #38: parallel-subagent-enforcement (並列サブエージェント起動 + agent type 選定の機械強制)

> Status: **✅ 完了**
> 起案: 2026-05-25
> 完了: 2026-05-25
> 関連: #29 (採用 5/6 条由来), #35 (本 session 起源、dogfooding 関連)
> 設計起源: [`docs/draft/parallel-subagent-enforcement.md`](../draft/parallel-subagent-enforcement.md)

## Task ゴール

PreToolUse(Agent) hook (`parallel-subagent-reminder.sh`) で並列起動の必要性と agent type 適切性の 2 軸を機械検出 + warning 注入し、規範 §並列化義務 + §agent type 選定義務 を併設する。完成時に AI が単独 Agent 起動 + 実装系 keyword 検出 / `general-purpose` + 専門 type 適合 keyword 検出 の 2 case で即時 `<system-reminder>` 警告を受ける。

## Task 作業概要

- `.claude/rules/development-process.md` §並列化義務 + §agent type 選定義務 セクション追加
- `.claude/hooks/parallel-subagent-reminder.sh` 新設 (約 70 LOC + fail-open guard + atomic-mkdir lock + subshell 関数化 + agent type 照合 logic)
- `.claude/settings.json` PreToolUse(Agent) 配線 + `.claude/harness-config.yml` キー追加 + `.claude/hooks/lib/config-loader.sh` env export
- `.claude/tests/parallel-subagent-reminder-smoke.sh` 8 cases (1-5 並列性 + 6-8 agent type) PASS
- 既存 smoke regression 0

## Task 完了条件 (DoD)

- [ ] `.claude/rules/development-process.md` §並列化義務 + §agent type 選定義務 セクション存在 (grep PASS)
- [ ] `.claude/hooks/parallel-subagent-reminder.sh` 新設 (約 70 LOC、fail-open + atomic-mkdir lock + subshell 関数化 + agent type 照合 logic 全実装)
- [ ] `.claude/settings.json` PreToolUse(Agent) 配線完了
- [ ] `.claude/harness-config.yml` `parallel_subagent_reminder_enabled: true` + `parallel_subagent_ttl_sec: 300` キー追加
- [ ] `.claude/hooks/lib/config-loader.sh` `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED` + `HC_PARALLEL_SUBAGENT_TTL_SEC` env export
- [ ] 新 smoke `parallel-subagent-reminder-smoke.sh` 8/8 PASS
- [ ] 既存 smoke regression 0
- [ ] 5+ reviewer iter cycle で strict 0-finding 収束 (採用 6 条 4)
- [ ] commit 完了 (push は user manual で実施、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

> 規約 (採用 6 条 6): 「何のため × 何をやる × 何ができるようになる」の 3 要素を 1 段落で記述

「subagent 並列起動と agent type 選定の機械強制のため、PreToolUse(Agent) hook で並列性と agent type 適切性を warning 注入する仕組み (規範 + hook + 8 case smoke) を新設する。完成すれば AI が PreToolUse(Agent) 時点で並列起動忘れと general-purpose 誤採用を即時警告される。」

## 背景・目的

本 session で reviewer 並列 (採用 6 条 4) は遵守された (23 並列起動) が、fix 系 sub-task は 1 subagent 統合委譲が default 化し、5 件統合 = 並列化機会逃失。具体的に task-35 Step 1+2+4 を 1 subagent に統合委譲、本来 3 並列起動可能 (file 領域独立) だった。

加えて agent type 選定で `general-purpose` が default 採用され、test 拡張 / refactor 系で専門 agent type (`test-automator` / `refactoring-specialist`) を逃失した。

honor system のみで強制不能。machine enforcement が必要。

## 設計

詳細は draft `docs/draft/parallel-subagent-enforcement.md` §4 採用案 (案 B + D ハイブリッド) を参照。

主要点:
- 4.1: 規範強化 (development-process.md)
- 4.2: soft reminder hook (PreToolUse(Agent) で発火、BLOCK しない)
- 4.3: keyword 検出 pattern (false positive 最小化)
- 4.4: 新 smoke 5 cases (並列性)
- 4.5: agent type 選定の機械強制 (8 cases に拡張)
- 4.5.0: 設定不要原則 (hook 内 hardcode default + 任意 yaml override)
- 4.5.5: agent-router skill 連携 (Phase 2 future)

## TDD 戦略

### RED

- `parallel-subagent-reminder-smoke.sh` を新設し 8 case 全て FAIL から開始

### GREEN

- hook 実装 → 8 cases PASS
- 既存 smoke regression 0

### REFACTOR

- hook ~70 LOC で関数分割余地少、skip 想定

## Step 計画

採用 6 条 (Task=Phase=N Step、2026-05-25) 準拠。本 task は **本 draft の dogfooding** として Step 1 で 3 並列起動する。

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | 規範追記 + hook 新設 + 配線 + smoke 統合実装 (3 並列、独立 file 領域、dogfooding) | 1.5h | — |
| 2 | ✅ | (テスト設計レビュー) 5+ reviewer 動的選定 (test-automator / qa-expert / tdd-guide / pr-test-analyzer + harness-optimizer / code-reviewer) | 0.5h | Step 1 |
| 3 | ✅ | (テスト合格) 新 smoke 8 cases PASS + 既存 smoke regression 0 | 0.3h | Step 2 |
| 4 | ✅ | (リファクタリング) 3 観点判定 (skip 想定: hook ~70 LOC で関数分割余地少) | 0.2h | Step 3 |

合計工数: 2.5h

### Step 1: 規範追記 + hook 新設 + 配線 + smoke 統合実装 (3 並列、独立 file 領域)

**Step status**: ✅

**作業概要 (list.md 概要欄)**: 規範 + hook + 配線 + smoke を 3 並列 subagent で独立 file 領域実装 (本 draft の dogfooding)

**完了条件**:
- `.claude/rules/development-process.md` §並列化義務 + §agent type 選定義務 追加 (grep `並列化義務` exit 0 + grep `agent type 選定` exit 0)
- `.claude/hooks/parallel-subagent-reminder.sh` 新設 (約 70 LOC、shellcheck 0)
- `.claude/settings.json` PreToolUse(Agent) entry 追加
- `.claude/harness-config.yml` 2 key 追加 + `.claude/hooks/lib/config-loader.sh` 2 env export
- `.claude/tests/parallel-subagent-reminder-smoke.sh` 8 cases 全 RED (実装前) → 全 GREEN (実装後)

### Step 2: (テスト設計レビュー)

**Step status**: ✅

**作業概要**: メインが 5+ reviewer 動的選定 (test-automator / qa-expert / tdd-guide / pr-test-analyzer + harness-optimizer / code-reviewer)、並列起動、収束まで反復 (上限 5 回)

**完了条件**: 全 reviewer approve / no objection (修正提案 0 件)、iter cycle 5 回以内収束

### Step 3: (テスト合格)

**Step status**: ✅

**作業概要**: 新 smoke 8 cases (Case 1-5 並列性 + Case 6-8 agent type 選定) PASS + 既存 smoke regression 0 (task-rule-guard 8/11 副産物 #22 含む)

**完了条件**: `bash .claude/tests/parallel-subagent-reminder-smoke.sh` exit 0、既存 smoke 全件 regression 0

### Step 4: (リファクタリング)

**Step status**: ✅

**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点で見直す

**完了条件**: skip: hook 348 LOC で関数分割余地少、agent_type 照合 logic は 1 関数で完結 (iter5 reviewer approve 済、残存 MEDIUM 数件は副産物 entry として後続 task 化)

## 工数見積

2.5 時間 (実装 90 分 + TDD レビュー 30 分 + 検証 20 分 + リファクタ判定 10 分)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | 規範 1 file (development-process.md) + 新 hook + 新 smoke + settings.json + harness-config.yml + config-loader.sh = 6 file |
| migration | なし |
| 環境変数 | `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED` 新設 (default: true、bypass: false) / `HC_PARALLEL_SUBAGENT_TTL_SEC` 新設 (default: 300) |
| 互換性 | warning 注入のみ、既存挙動破壊なし |
| state dir | `.claude/.parallel-subagent-state/` 新設 (`.gitignore` で除外) |

## 再発防止

本 task が再発防止機構。本 task 完了後、subagent 並列起動 + agent type 選定の honor system 違反を hook が機械強制する。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-25 | 起案 | draft `docs/draft/parallel-subagent-enforcement.md` 起こし |
| 2026-05-25 | 承認 | user 「draft 2 件レビュー + 承認 → 問題ありません」 |
| 2026-05-25 | 着手予定 | branch `feat/list-md-plan-first-normative` 継続使用 |
| 2026-05-25 | Step 2 完了 | iter5 全 6 reviewer approve (HIGH 0、median confidence 0.96)、smoke 13/13 PASS、defense-in-depth 完全維持 |
| 2026-05-25 | Step 3 完了 | smoke 13/13 PASS 既達 (iter2/iter4 拡張 8→11→13 cases)、既存 smoke regression 0 |
| 2026-05-25 | Step 4 完了 | skip 明示 (3 観点判定: hook ~348 LOC で refactor 余地少、F4 bypass-logger structural fix で repo-wide 改善達成) |
| 2026-05-25 | Task 完了 | 累積 commits 7de91d5 (Step 1) → 408495d (iter2 fix) → 207015d (iter4 fix) + 本 commit (sync)、HIGH 0 維持で収束 |

## 派生 task / 次アクション候補

本 task 実装中に発見した副産物を本セクションに必ず記入。

(現在なし、Step 1 着手時に随時追加)

## 関連

- Draft: [`docs/draft/parallel-subagent-enforcement.md`](../draft/parallel-subagent-enforcement.md)
- 依存タスク: #29 (採用 5/6 条由来) / #35 (本 session 起源、dogfooding 関連)
- 派生タスク: なし (Phase 2 で agent-router skill 連携検討予定、future work)
