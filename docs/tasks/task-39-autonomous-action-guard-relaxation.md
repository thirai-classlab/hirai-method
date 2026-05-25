---
asana_url: ""
slack_urls: []
deadline: ""
requester: "user"
---

<!--
total_steps: 4
-->

# Task #39: autonomous-action-guard-relaxation (main/stg 以外 push + PR 作成 自律実行可)

> Status: **🔲 未着手**
> 起案: 2026-05-25
> 関連: protected-branch-push-deny (#18, commit `ad2f7bc`), delegation-guard 二重ガード継続
> 設計起源: [`docs/draft/autonomous-action-guard-relaxation.md`](../draft/autonomous-action-guard-relaxation.md)

## Task ゴール

`autonomous-action-guard.sh` の `AUTONOMOUS_RESTRICTED_PATTERNS` 配列から `git push` 一般 pattern + `gh pr create` を削除し、main/stg 系 push は `protected-branch-push-deny` (`delegation-guard.sh`) の二重ガード維持で保護する。完成時に feature branch への `git push` と `gh pr create` が agent 自律実行可となり、`gh pr merge` / `gh release` / main/stg push のみ user 明示承認必須に絞られる。

## Task 作業概要

- `.claude/hooks/autonomous-action-guard.sh` `AUTONOMOUS_RESTRICTED_PATTERNS` 配列削減 (`git push` 一般 / `gh pr create` 削除、`gh pr merge` 維持)
- `.claude/rules/modes.md` 遵守事項 8 table 更新 (緩和対象明示、protected-branch-push-deny 委譲明記)
- `.claude/tests/autonomous-action-guard-relaxation-smoke.sh` **12 cases** PASS (iter2/iter4 で Case 8-12 拡張: --force/--tags/--all + gh pr merge variants)
- 既存 smoke regression 0 (特に `delegation-guard-deny-layers-smoke.sh` **48/48 PASS** 維持、iter2 で HEAD:main 系 4 case + iter4 で --mirror/--all/--branches/--prune 4 case 追加)

## Task 完了条件 (DoD)

- [ ] `.claude/hooks/autonomous-action-guard.sh` `AUTONOMOUS_RESTRICTED_PATTERNS` 配列から `git push` 一般 pattern 削除 + `gh pr create` 削除 (`gh pr merge` は維持)
- [ ] `.claude/rules/modes.md` 遵守事項 8 table 更新 (緩和対象明示)
- [ ] 新 smoke `.claude/tests/autonomous-action-guard-relaxation-smoke.sh` **12 cases** PASS (iter2/iter4 で Case 8-12 拡張: --force/--tags/--all + gh pr merge variants)
- [ ] 既存 smoke regression 0 (`delegation-guard-deny-layers-smoke.sh` **48/48 PASS** 維持、iter2 で HEAD:main 系 4 case + iter4 で --mirror/--all/--branches/--prune 4 case 追加)
- [ ] 5+ reviewer iter cycle で strict 0-finding 収束 (採用 6 条 4)
- [ ] memory `feedback_claude_permission_git_push_deny.md` 実態確認 (本緩和後 agent 経路で push が動くか別途検証 task 起票候補)
- [ ] commit 完了 (push は user manual で実施、本 task 完了直後ならば本緩和適用後の agent push で実証可能性あり)

## Task 概要欄 (list.md 用、3 要素規範)

> 規約 (採用 6 条 6): 「何のため × 何をやる × 何ができるようになる」の 3 要素を 1 段落で記述

「feature push と PR 作成の過剰制約解消のため、autonomous-action-guard の禁止 pattern 配列から git push 一般 + gh pr create を削除し protected-branch-push-deny との二重ガードに整理する。完成すれば AI が main/stg 以外の branch への push と PR 作成を自律実行できるようになり、merge と main/stg 操作のみ user 明示承認が必須になる。」

## 背景・目的

本 session で task-35 完遂後 push 試行時、`autonomous-action-guard.sh` が `git push -u origin feat/list-md-plan-first-normative` を Loop モード自律実行禁止リスト (modes.md 遵守事項 8) で block。

しかし以下から現規範は過剰制約:
- 本 repo には既に `protected-branch-push-deny` layer (`delegation-guard.sh` の commit `ad2f7bc` 由来) で main / stg 系への push は別 layer で deny されている
- feature branch への push + PR 作成は preparation 範囲 (merge は user 明示承認必要だが、push と PR 作成は revert 容易)
- 本 session で push に 1 subagent + 複数試行コストを払い、最終的に Claude Code permission deny で user manual 委ねとなった

→ autonomous-action-guard の禁止 pattern を **main/stg 系 push + PR merge のみ** に限定し、feature push + PR 作成は自律実行可とする。

ただし Claude Code permission system 自体の deny (memory `feedback_claude_permission_git_push_deny.md`) は本緩和では解消不可、agent 経路で push が真に動くかは別問題 (本 task 完了後検証)。

## 設計

詳細は draft `docs/draft/autonomous-action-guard-relaxation.md` §4 採用案 (案 C: 案 A + 二重ガード継続) を参照。

主要点:
- 4.1: `AUTONOMOUS_RESTRICTED_PATTERNS` 配列削減
- 4.2: protected-branch-push-deny 維持 (二重ガード = defense-in-depth)
- 4.3: modes.md 遵守事項 8 table 更新
- 4.4: 新 smoke (Step 2 iter2/iter4 拡張で 5→12 cases、--force/--tags/--all + gh pr merge variants 網羅)

## TDD 戦略

### RED

- `autonomous-action-guard-relaxation-smoke.sh` を新設し 5 case 全て FAIL から開始 (現状の hook は全 push を block するため Case 1 / Case 4 が FAIL)

### GREEN

- hook 配列削減 → 12 cases PASS (Step 2 iter2/iter4 拡張後)
- 既存 `delegation-guard-deny-layers-smoke.sh` 48/48 regression 0 (Step 2 iter2/iter4 拡張後)

### REFACTOR

- 配列削減のみで refactor 余地なし、skip 想定

## Step 計画

採用 6 条 (Task=Phase=N Step、2026-05-25) 準拠。

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | autonomous-action-guard.sh 配列削減 + modes.md table 更新 (2 並列、独立 file 領域) | 0.5h | — |
| 2 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 (test-automator / qa-expert / tdd-guide / pr-test-analyzer + security-reviewer / harness-optimizer) | 0.5h | Step 1 |
| 3 | 🔲 | (テスト合格) 新 smoke 12 cases PASS + 既存 smoke regression 0 (delegation-guard-deny-layers 48/48 維持) | 0.3h | Step 2 |
| 4 | 🔲 | (リファクタリング) 3 観点判定 (skip 想定: 配列削減のみで refactor 余地なし) | 0.1h | Step 3 |

合計工数: 1.4h

### Step 1: autonomous-action-guard.sh 配列削減 + modes.md table 更新 (2 並列、独立 file 領域)

**Step status**: 🔲

**作業概要 (list.md 概要欄)**: hook 配列削減と modes.md table 更新を 2 並列 subagent で独立 file 領域実装

**完了条件**:
- `.claude/hooks/autonomous-action-guard.sh` `AUTONOMOUS_RESTRICTED_PATTERNS` 配列から `^git[[:space:]]+push([[:space:]]|$)` 削除 + `^gh[[:space:]]+pr[[:space:]]+create` 削除 (`gh pr merge` は維持)
- `.claude/rules/modes.md` 遵守事項 8 table の remote 反映 + PR / リリース 行更新 (緩和対象明示)
- `.claude/tests/autonomous-action-guard-relaxation-smoke.sh` 5 case 新規作成

### Step 2: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: メインが 5+ reviewer 動的選定 (test-automator / qa-expert / tdd-guide / pr-test-analyzer + security-reviewer / harness-optimizer)、並列起動、収束まで反復 (上限 5 回)

**完了条件**: 全 reviewer approve / no objection (修正提案 0 件)、iter cycle 5 回以内収束。security-reviewer による「緩和の妥当性 (defense-in-depth)」確認必須

### Step 3: (テスト合格)

**Step status**: 🔲

**作業概要**: 新 smoke **12 cases** PASS + 既存 smoke regression 0 (特に `delegation-guard-deny-layers-smoke.sh` **48/48 PASS** 維持で二重ガード継続を実証)

**完了条件**: `bash .claude/tests/autonomous-action-guard-relaxation-smoke.sh` exit 0 (**12/12 PASS**、iter2/iter4 で Case 8-12 拡張)、`bash .claude/tests/delegation-guard-deny-layers-smoke.sh` **48/48 PASS** (iter2 で HEAD:main 系 4 case + iter4 で --mirror/--all/--branches/--prune 4 case 追加)

### Step 4: (リファクタリング)

**Step status**: 🔲

**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点で見直す

**完了条件 (or skip)**: 配列削減のみで refactor 余地なし、`skip: 配列削減のみで refactor 余地なし、helper 抽出不要` 想定

## 工数見積

1.4 時間 (実装 30 分 + TDD レビュー 30 分 + 検証 20 分 + リファクタ判定 5 分)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/autonomous-action-guard.sh` + `.claude/rules/modes.md` + 新 smoke = 3 file |
| migration | なし |
| 環境変数 | 新規追加なし (既存 `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` + `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` で十分) |
| 互換性 | 既存 protected-branch-push-deny は不変、autonomous-action-guard が一部緩和のみ |

## 再発防止

本 task 完了後、agent が feature branch への push と PR 作成を自律実行可能になり、user manual push の累積コストが解消。

ただし Claude Code permission deny (memory `feedback_claude_permission_git_push_deny.md`) が agent 経路で push を deny する場合は、本緩和は autonomous-action-guard 層のみで Claude Code permission system 自体は別問題。本緩和実装後の実証検証は別 task で起票候補。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-25 | 起案 | draft `docs/draft/autonomous-action-guard-relaxation.md` 起こし |
| 2026-05-25 | 承認 | user 「draft 2 件レビュー + 承認 → 問題ありません」 |
| 2026-05-25 | 着手予定 | branch `feat/list-md-plan-first-normative` 継続使用 |
| 2026-05-25 | Step 2 iter4 | iter1-3 reviewer findings 全件解消、smoke 12/12 + delegation-guard 48/48 PASS |

## 派生 task / 次アクション候補

本 task 実装中に発見した副産物を本セクションに必ず記入。

- (🟡 想定) Claude Code permission deny 実証検証 task: 本緩和適用後、agent から `git push origin feat/...` が真に動くか別 task で検証。動かなければ permission system 側に申請 or 文書化必要。本 task 完了直後の Step 3 完了時点で test 実行可能 (本緩和適用後の agent push 試行)

## 関連

- Draft: [`docs/draft/autonomous-action-guard-relaxation.md`](../draft/autonomous-action-guard-relaxation.md)
- 依存タスク: なし (本 task は独立、protected-branch-push-deny (#18, commit `ad2f7bc`) を前提とする)
- 派生タスク: Claude Code permission deny 実証検証 (本 task 完了直後に起票候補)
