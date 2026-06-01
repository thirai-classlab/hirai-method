---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 11
-->

# Task #71: settings 生成化 / hook dispatcher 統合 (Phase 3)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 3 (§4.3)。**最大規模・最高リスク** (settings.json = harness 心臓部)
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.3

## Task ゴール

`harness-config.yml` を SSoT に `settings.json` を generated artifact 化し、event ごとに単一 dispatcher (PreToolUse / PostToolUse / Stop / SessionStart / UserPromptSubmit) へ集約する。disabled feature の hook process が起動せず、hook command が cwd 非依存になり、通常成功時の hook stdout が context を増やさない。**blocker の検出力 (exit code) は dispatcher 化前後で完全不変**。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-70 | settings generator は preset / `enforcement_matrix` を読んで「どの guard を配線するか」を決める。disabled feature 判定が preset 依存のため、enforcement matrix 確定が前提 | [task-70-enforcement-matrix-preset.md](task-70-enforcement-matrix-preset.md) |

## Task 作業概要

- settings.json の inventory 作成 (event / matcher / command / timeout / feature flag / output bytes 抽出、test fixture 保存)
- hook ↔ feature flag 対応表 (対応なしは `always` / `debug` / `deprecated` 分類)
- 5 dispatcher 追加 (`pretool-dispatcher.sh` / `posttool-dispatcher.sh` / `stop-dispatcher.sh` / `session-start-dispatcher.sh` / `userprompt-dispatcher.sh`)、contract JSON (`status` / `summary` / `next_actions` / `additionalContext`)
- settings generator (enabled feature のみ出力、generated block と manual override block 分離)
- 既存 hook を段階的に dispatcher 配下へ (まず dispatcher が既存 hook を呼ぶ形 → 安定後に function / library 化)
- 即時 pruning (PreToolUse:* / PostToolUse:* observe を default から外す、why-x5-violation-detect を Stop/UserPromptSubmit へ、parallel-subagent-reminder を SessionStart pointer 化)
- stdout budget (成功時 `{}` / warn 1-3 行 / BLOCK は reason+next_action+bypass のみ)
- cwd robustness (`${CLAUDE_PROJECT_DIR}` or install 時 generated absolute wrapper)
- 4 smoke (feature pruning / cwd robustness / sessionstart budget / effective hook matrix) + **blocker exit code 不変 smoke**

## Task 完了条件 (DoD)

- [ ] disabled feature の hook process が起動しない (settings から外れる or dispatcher 1 起動で短絡)
- [ ] hook command が repo cwd 非依存 (`${CLAUDE_PROJECT_DIR}` / generated wrapper)
- [ ] PreToolUse / PostToolUse の wildcard hook が必要最小限 + 残す場合は docs に理由
- [ ] high-frequency event の settings command が原則 1 dispatcher
- [ ] 通常成功時の hook stdout が context を増やさない (observer は default preset で stdout なし)
- [ ] **blocker hook の exit code が dispatcher 化前後で同一 (smoke で同一入力に対し検証)**
- [ ] reviewer approve (テスト設計レビュー)
- [ ] 全 smoke regression 0 (既存 enforcement BLOCK 全 PASS 不変)
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> 無効 feature の hook が起動コストを払い hook 過配線で context を圧迫する問題を解消するため、settings.json を harness-config.yml からの generated artifact 化し event ごとに単一 dispatcher へ集約 + stdout budget + cwd 非依存化する。完成すれば disabled feature の hook が起動せず通常成功時の hook 出力が context を増やさなくなり、blocker 検出力は完全に保ったまま harness が軽量化する。

## 背景・目的

draft §3 P2「hooks が過配線で無効 feature でも起動コストを払う」「hook command が相対 path で cwd 依存」+ §4.3。検証で wildcard hook 2 件 (PreToolUse:* / PostToolUse:*)・相対 path 35 件・`${CLAUDE_PROJECT_DIR}` 0 件を実機確認済。feature toggle が false でも hook process は起動し config を読み空 JSON を返すため「無効なのに軽くならない」。

## 設計

draft §4.3「hook 過多の具体的な修正方法」(4 分類: blocker/advisory/observer/bootstrap) + 「目標 event matrix」+ 「dispatcher 実装手順」(7 step) + 「移行中に守ること」(blocker 検出力維持 / exit code 不変 / observer は log) を SSoT とする。

## TDD 戦略

### RED
- blocker exit code 不変 smoke を先に書き、dispatcher 化前の baseline exit code を記録 → 化後に同一を要求。feature pruning smoke で disabled feature が settings に出ないことを先行。

### GREEN
- dispatcher を「既存 hook を呼ぶ薄い wrapper」から始め、段階的に統合 (subagent 委譲、staging 戦略、worktree 隔離検討)。

### REFACTOR
- 安定後に dispatcher 内で shell function / library 化し process 数削減。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | settings.json inventory 抽出 (event/matcher/command/timeout/feature flag/output bytes) + hook↔feature flag 対応表 (always/debug/deprecated 分類)、test fixture 保存 | 0.8h | task-70 |
| 2 | 🔲 | blocker exit code baseline smoke (dispatcher 化前の全 blocker hook の同一入力 exit code を記録) | 0.6h | Step 1 |
| 3 | 🔲 | settings generator (enabled feature のみ出力 + generated/manual override block 分離) | 1.0h | Step 1 |
| 4 | 🔲 | PreToolUse dispatcher (Bash / WriteLike / Agent、blocker のみ実行、contract JSON) | 1.0h | Step 3 |
| 5 | 🔲 | PostToolUse dispatcher (failure のみ処理・成功時無出力) + observer を log/sampled へ移行 | 0.8h | Step 3 |
| 6 | 🔲 | SessionStart / UserPromptSubmit / Stop dispatcher 統合 (reminder を compact status へ畳む) | 1.0h | Step 3 |
| 7 | 🔲 | cwd robustness (`${CLAUDE_PROJECT_DIR}` / generated absolute wrapper) + 即時 pruning (wildcard observe 除外、why-x5-detect/parallel-reminder 再配置) | 0.8h | Step 4,5,6 |
| 8 | 🔲 | stdout budget 適用 (成功 `{}` / warn 1-3 行 / BLOCK 短縮) + 4 smoke (pruning/cwd/sessionstart budget/effective matrix) | 0.8h | Step 7 |
| 9 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、**blocker exit code 不変 + enforcement regression 0 を最重点 cross-check** | 0.6h | Step 1-8 |
| 10 | 🔲 | (テスト合格) 全 smoke regression 0 + blocker exit code 化前後一致確認 (Step 2 baseline と照合) | 0.6h | Step 9 |
| 11 | 🔲 | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — dispatcher の function/library 化で process 数削減 | 0.5h | Step 10 |

合計: **~9.3h** (draft 目安 4-8h より大、最高リスクのため段階移行で安全側)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/settings.json` (generated 化) + `.claude/hooks/*-dispatcher.sh` (5 新規) + 既存 hook 群 (dispatcher 配下移行) + settings generator script + install.sh (wrapper 生成) + `.claude/tests/` (5 smoke 新規) |
| migration | settings.json を generated artifact 化 (手書き override は別 block / settings.local.json)。**全 consuming repo に install.sh 経由で再配布が必要** |
| 環境変数 | `HC_HOOK_TRACE=1` / `observer_level=debug` (新、debug 用) |
| 互換性 | **最重要: blocker BLOCK 挙動は完全不変が DoD**。dispatcher 化は内部構造変更、外部から見た enforcement は同一。settings 生成化で手書き調整が消えるリスク → generated/manual block 分離で緩和 |
