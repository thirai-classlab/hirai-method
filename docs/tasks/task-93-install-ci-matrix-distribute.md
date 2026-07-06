---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 9
-->

# Task #93: install.sh で CI matrix (2 preset × 5 category) 配布 + run-all-smokes 分割実行 (P2-2/I3/W1-10)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり preset × per-category matrix 採用、副産物 #83 autofill flakiness 吸収)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §3 I3 / §4.7 / §5 P2-2 / §11.3 R2 / §11.3 R4 / §11.3 R5
> 設計起源: [install-ci-matrix-distribute.md](../draft/install-ci-matrix-distribute.md)

## Task ゴール

`bash install.sh <target>` 直後に `<target>/.github/workflows/harness-smoke.yml` が create-if-absent 配置される。matrix 2 軸 (preset = `[team-default, strict]` × category = `[parity, behavior, budget, portability, stale-det]` = 10 並列 job) で `run-all-smokes.sh --category ${{ matrix.category }}` を実行し、hirai-method 本体 PR で全 10 job が UNEXPLAINED-FAIL=0 で通過する。副産物 next-actions #83 (`install-claude-md-autofill-smoke` Case G/N flakiness) を smoke 側 subshell isolation で吸収し、5 回連続 PASS を機械保証する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-92 | **hard**。pre-commit で fast smoke 分離 / CI matrix で full smoke 分離の fast/full 2 軸を SSoT で揃える。R2 の 5 category × fast/full 判定 table (task-92 §3.3) が本 task の per-category matrix の SSoT | [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) |

## Task 作業概要

- `.github/workflows/harness-smoke.yml` を hirai-method 本体に新規作成 (matrix 2 preset × 5 category + `run-all-smokes.sh --category` + fail 時 artifact upload)
- install.sh §5.6 新設 (create-if-absent 配布、既存 CI 完全保護、`--force` でも上書きせず)
- `install-claude-md-autofill-smoke.sh` Case G/N に subshell isolation + 前 `rm -rf` を追加 (副産物 #83 吸収、案 3)
- 新規 smoke `install-ci-matrix-smoke.sh` (5 case A-E、preset env 名 `HC_DEFAULT_PRESET` の `_OVERRIDE` NG-guard 含む Case C の 5 点 grep)
- `run-all-smokes.sh` `_get_smoke_category()` に本 smoke を **portability** カテゴリで登録
- docs 反映 + per-category timing 実測 (10 データ点、3min 超過は個別 smoke 分割の追跡 entry を next-actions.md へ append)

## Task 完了条件 (DoD)

- [ ] `.github/workflows/harness-smoke.yml` が hirai-method 本体に存在
- [ ] `install.sh` §5.6 で create-if-absent 配置 (fresh install / update / force / overwrite-all いずれも既存保護)
- [ ] matrix `preset: [team-default, strict]` + `category: [parity, behavior, budget, portability, stale-det]` + `fail-fast: false` + `if: failure()` artifact upload の 4 契約が yml に存在
- [ ] preset env override が `HC_DEFAULT_PRESET` (config-loader.sh:353 SSoT、`_OVERRIDE` suffix 禁止、Case C の NG-guard で検証)
- [ ] matrix job が `bash .claude/tests/run-all-smokes.sh --category ${{ matrix.category }}` を実行
- [ ] hirai-method 本体 PR で matrix 全 10 job が UNEXPLAINED-FAIL == 0 (blocking check)
- [ ] per-job wall time < 3min (empirical 実測、超過 category は Step 5 で個別 smoke 分割の追跡)
- [ ] `install-ci-matrix-smoke.sh` 5 case 全 PASS + `run-all-smokes.sh --list` の portability カテゴリで discover
- [ ] `install-claude-md-autofill-smoke.sh` 5 回連続実行で Case G/N が全 PASS (副産物 #83 verification)
- [ ] 既存 `run-all-smokes.sh` の全 smoke で UNEXPLAINED-FAIL == 0 継続 (regression 0)
- [ ] docs 反映 (README / docs/INVENTORY / docs/PORTABILITY / install.sh header の 4 箇所に harness-smoke.yml 記述)
- [ ] next-actions #83 処理結果列を `🔄 未処理` → `✅ → task-93 (<PR#>) 完了` に更新 (§11.3 R4 verification)
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

I3 Quality Gate の PR 境界機械強制不在と preset 間挙動差の CI 自動検証不在を解消するため、`install.sh` §5.6 で `.github/workflows/harness-smoke.yml` を create-if-absent 配布し matrix 2 preset × 5 category で `run-all-smokes.sh --category` を並列実行する。完成すれば全 PR が CI matrix (10 job / per-job < 3min) UNEXPLAINED-FAIL=0 を要求され preset 間挙動差が構造検証されるようになり、副産物 #83 (autofill flakiness) も subshell isolation で解消される。

## Step 計画 (SSoT: draft §7 「Step 分解」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `.github/workflows/harness-smoke.yml` 新規作成 (matrix 2 preset × 5 category、preset env = `HC_DEFAULT_PRESET`、`_OVERRIDE` suffix 禁止) | 3h | — |
| 2 | 🔲 | `install.sh` §5.6 追加 (create-if-absent 配布 + summary vocabulary 統合 5 行追記) | 2h | Step 1 |
| 3 | 🔲 | `install-claude-md-autofill-smoke.sh` に前 `rm -rf` + subshell 独立実行を追加 (副産物 #83 吸収、案 3) | 1.5h | — (Step 1/2 と並列可) |
| 4 | 🔲 | 新 smoke `install-ci-matrix-smoke.sh` 追加 (5 case) + `run-all-smokes.sh` に portability カテゴリで登録 | 2.5h | Step 1, 2 |
| 5 | 🔲 | docs 反映 (4 file) + per-category timing 実測 (10 データ点、3min 超過は追跡 entry を next-actions.md へ append) | 1h | Step 2 |
| 6 | 🔲 | `next-actions.md` #83 処理結果列を `✅ → task-93` に更新 (§11.3 R4 verification) | 0.2h | Step 3 |
| 7 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (base 4 + CI/GitHub Actions 経験 domain)、収束まで反復 (上限 `review_iteration_max`) | 1.5h | Step 4 |
| 8 | 🔲 | (テスト合格) 全 smoke PASS + Actions success + 5 回連続 autofill smoke で FAIL 行 0 (UI 変更 0 のため E2E/visual 対象外) | 0.8h | Step 7 |
| 9 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` (持続可能性 = GH Actions v4 pin / 汎用性 = matrix preset list yaml anchor 化は YAGNI 却下 skip / 非冗長化 = §5.6 の create-if-absent block DRY OK なら skip) | 0.5h | Step 8 |

合計: 12.5h (≒ 1.5 day、roadmap P2-2 見積 1.5 day)

**注意 (install.sh 同域編集の順序整合)**: task-92 (§6.3/§6.8) と本 task (§5.6) は install.sh の異なる section を編集するが、arg parse + summary heredoc は共通。着手順は #92 → #93 で序列化し、並列 subagent での install.sh 同時編集は禁止。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/install-ci-matrix-distribute.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり preset × per-category matrix 採用、findings-2 fix、R2 SSoT propagate 契約 = task-93 draft §4.2 timing 補正で解消) |
| 2026-07-06 | タスク化 | `/new-task 93 install-ci-matrix-distribute`、list.md #93 📝 → 🔲 update、docs/tasks/task-93-*.md 生成 |
| 2026-07-07 | 完了 | Wave 2 Workflow wf_ac31538c-e9c 経由で impl → barrier → review → fix → verify を実行、worktree isolation → reconcile → Case E awk 範囲式 bug fix。install-ci-matrix-smoke 5/5 PASS + autofill 5/5 exit 0 flakiness 解消 + .github/workflows/harness-smoke.yml matrix 2preset×5category 配布 + install.sh §5.6 create-if-absent。Step 1-9 全 ✅。副産物 #83 autofill flakiness を subshell isolation + `rm -rf` pre-run で吸収 |

## 派生 task / 次アクション候補

- [ ] (🟢) per-category timing で 3min 超過検出時 → 該当 category を個別 smoke 単位に更に分割 (`run-all-smokes.sh --category` 内 dispatch の smoke 単位細分化は task-83 CLI 拡張の scope、Step 5 実測後に判断)
- [ ] (🟢) autofill Case G/N 以外に intermittent FAIL 発生時は subshell wrapper を該当 Case へ横展開 (LOW-20 fix contract、+0.5h 見積)

## 関連

- Draft: [install-ci-matrix-distribute.md](../draft/install-ci-matrix-distribute.md)
- 依存 task: [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) (hard、fast/full 2 軸 SSoT)
- 前提 (完了済): PR #68 (task-85 `--preset` opt-in) / PR #73 (task-87 self-doctor / `run-all-smokes.sh --category` 分類)
- 副産物: [next-actions #83 (autofill flakiness)](next-actions.md) を本 task で吸収
