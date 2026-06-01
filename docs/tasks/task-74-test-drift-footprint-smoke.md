---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 7
-->

# Task #74: test drift 修正 + context footprint / parity smoke 統合 (Phase 6)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 6 (§4.6) + §5 順序 7。**全 Phase (69-73) の回帰 budget を統合検証する最終 task**
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.6

## Task ゴール

`session-help-surface` の現仕様が確定し `hook-frequency-tweaks-smoke.sh` の旧期待値 (Case 7) が更新され fail が解消する。localhost bind が必要な Web UI smoke は sandbox / CI 条件が明示される。context footprint smoke (SessionStart bytes / agents count / skills count) が追加される。test が parity / behavior / budget / portability / stale-detector の種別に整理され、古い test が regression / spec drift / obsolete / environmental に分類され放置されない。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-69 | key parity smoke が確定 (本 task で統合検証) | [task-69-hc-config-key-parity.md](task-69-hc-config-key-parity.md) |
| task-70 | effective enforcement (mismatch) smoke が確定 | [task-70-enforcement-matrix-preset.md](task-70-enforcement-matrix-preset.md) |
| task-71 | hook cwd robustness / feature pruning smoke が確定 | [task-71-settings-dispatcher-generation.md](task-71-settings-dispatcher-generation.md) |
| task-72 | agents / skills count smoke が確定 | [task-72-action-space-pruning.md](task-72-action-space-pruning.md) |
| task-73 | SessionStart footprint smoke が確定 | [task-73-sessionstart-userprompt-shorten.md](task-73-sessionstart-userprompt-shorten.md) |

## Task 作業概要

- `session-help-surface` の現仕様 (opt-in pointer 化) を確定し `hook-frequency-tweaks-smoke.sh` Case 7 の旧期待値を新仕様に更新
- localhost bind が必要な Web UI smoke に sandbox / CI 条件 (network 可否) を明示し environmental skip を整備
- context footprint smoke を統合 (SessionStart bytes / agents count / skills count、各 Phase で追加した budget smoke を束ねる)
- test を 5 種別 (parity / behavior / budget / portability / stale-detector) に整理
- 古い test を 4 分類 (regression=修正 / spec drift=期待値更新 / obsolete=削除 or deprecated / environmental=skip) で処理し fail を放置しない
- draft §6「受け入れ条件」の必須 / 軽量化 / 検証 を全項目チェック

## Task 完了条件 (DoD)

- [ ] `hook-frequency-tweaks-smoke.sh` Case 7 fail が解消 (session-help 現仕様に期待値更新)
- [ ] Web UI smoke が sandbox / CI network 条件を明示し environmental skip 整備
- [ ] context footprint smoke (SessionStart bytes / agents / skills count) が追加され統合実行できる
- [ ] test が 5 種別に整理され、古い test が 4 分類で処理 (放置 fail 0)
- [ ] draft §6 受け入れ条件 (必須 6 + 軽量化 3 + 検証 4) が全項目チェック
- [ ] reviewer approve (テスト設計レビュー)
- [ ] **全 Phase (69-73) の smoke を束ねた統合実行で regression 0**
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> 軽量化施策で test 期待値が変わり古い test がノイズ化する問題を解消するため、session-help 旧仕様 fail を更新 + Web UI smoke の環境条件明示 + context footprint smoke 統合 + test を 5 種別に整理する。完成すれば軽量化が regression test で守られ、古い test が放置されず、Phase 1-6 全体の受け入れ条件が機械検証可能になる。

## 背景・目的

draft §3 P3「test drift がある」+ §4.6 + §6 受け入れ条件。検証で `hook-frequency-tweaks-smoke.sh` Case 7 (session-help 初回表示 + marker 作成を期待) が opt-in pointer 化された現実装と不一致で FAIL を確認済。軽量化施策 (Phase 3/4/5) は test 期待値も変えるため、古い test は回帰検出でなくノイズになる。

## 設計

draft §4.6「test 整理の具体方針」(5 種別 table) + 「古い test の扱い」(4 分類) + §6「受け入れ条件」を SSoT とする。本 task は Phase 1-5 で各 Phase 追加した smoke を束ね、全体回帰 budget として統合する位置づけ。

## TDD 戦略

### RED
- 統合 footprint / parity smoke を先に束ね、現状 (Case 7 fail / footprint 超過) で fail させる。

### GREEN
- Case 7 期待値更新 + footprint smoke 統合 + test 種別整理 (subagent 委譲、staging 戦略)。

### REFACTOR
- smoke runner の共通化 (種別ごとの一括実行 entry)。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `session-help-surface` 現仕様確定 + `hook-frequency-tweaks-smoke.sh` Case 7 旧期待値を新仕様 (opt-in pointer) に更新 | 0.5h | task-69,70,71,72,73 |
| 2 | 🔲 | Web UI smoke に sandbox / CI network 条件明示 + environmental skip 整備 | 0.5h | Step 1 |
| 3 | 🔲 | context footprint smoke 統合 (SessionStart bytes / agents count / skills count、各 Phase budget smoke を束ねる runner) | 0.7h | Step 1 |
| 4 | 🔲 | test 5 種別整理 (parity/behavior/budget/portability/stale-detector) + 古い test 4 分類処理 (放置 fail 0) | 0.7h | Step 2,3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、draft §6 受け入れ条件の網羅性 + stale-test 検出力を cross-check | 0.5h | Step 1-4 |
| 6 | 🔲 | (テスト合格) **全 Phase (69-73) smoke を束ねた統合実行で regression 0** + draft §6 受け入れ条件 全項目チェック | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — smoke runner の種別一括実行 entry 共通化 | 0.4h | Step 6 |

合計: **~3.8h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/tests/hook-frequency-tweaks-smoke.sh` (Case 7 更新) + Web UI smoke (環境条件) + `.claude/tests/` (footprint 統合 smoke / smoke runner) + `.claude/hooks/session-help-surface.sh` (現仕様確定) |
| migration | なし |
| 環境変数 | Web UI smoke の network 条件 env (sandbox skip) |
| 互換性 | test の期待値更新 + 新規 budget smoke 追加。enforcement 挙動は無関係 (test 整理のみ) |
