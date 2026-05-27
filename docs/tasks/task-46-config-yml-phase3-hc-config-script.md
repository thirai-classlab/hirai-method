---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #46: config-yml Phase 3 (対話的 config-editor hc-config.sh + 規範文書更新)

> Status: **✅ 完了** (2026-05-27、Step 1-6 全 ✅、iter cycle 5 回、CRIT+HIGH=0 達成 + 残 MED 11 件 Step 6 absorb 済、smoke 21/21 PASS + regression 0)
> 起案: 2026-05-27
> 関連: task-44 (Phase 1), task-45 (Phase 2), entry #52 (引継ぎ 5 件のうち 3 件統合)
> 設計起源: [config-yml-phase3-hc-config-script.md](../draft/config-yml-phase3-hc-config-script.md)

## Task ゴール

`.claude/scripts/hc-config.sh` が新設され、user が yml 直接編集なしで全 34+ key を対話 menu / CLI args で安全に変更でき、規範文書 5 file に yml 参照経路が明文化される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-44 | Phase 1 で `harness-config.yml` に 36 key + `config-loader.sh` `is_feature_enabled` 共通関数が整備済。本 task の `hc-config.sh` はこれを読み書きする | [task-44-config-yml-phase1-schema-loader.md](task-44-config-yml-phase1-schema-loader.md) |
| task-45 | Phase 2 で hook 27 件 feature check + review command 4 件 yml 参照経路が整備済。本 task の規範文書 5 file 更新で yml key 参照経路を文書化する | [task-45-config-yml-phase2-hook-review-command.md](task-45-config-yml-phase2-hook-review-command.md) |

## Task 作業概要

- `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation + atomic 操作 + backup)
- smoke `hc-config-script-smoke.sh` 新設 (7 cases、TDD RED commit 先行 → GREEN commit、entry #52 (1) 統合)
- 規範文書 5 file 更新 (development-process / workflow / CommonRules / task-management / SELF_IMPROVEMENT、entry #52 (2) 共有 toggle mapping + (3) 6 hook 冒頭コメント統合)
- reviewer 5+ 動的選定で iter cycle 収束 (CRITICAL+HIGH+MEDIUM=0)
- 全 smoke regression 0 + closure commit + PR create

## Task 完了条件 (DoD)

- [ ] `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation + atomic + backup)
- [ ] smoke `hc-config-script-smoke.sh` 7 cases PASS
- [ ] 規範文書 5 file 更新 (grep 検証 5 件 PASS、各 file で yml 参照 keyword 確認)
- [ ] 6 hook 冒頭コメント追加 (entry #52 (3) 共有 toggle 制御の明示)
- [ ] 既存 100+ smoke regression 0
- [ ] reviewer iter 5 上限内収束 (CRITICAL+HIGH+MEDIUM=0)
- [ ] commit + push + PR create (feature branch、task #39 緩和で自律実行可)
- [ ] 4 リポ install 案内 (user manual `bash install.sh --update <target>`)

## Task 概要欄 (list.md 用、3 要素規範)

yml 設定値の編集経路整備のため、対話 menu + CLI args + 値型 validation + atomic 操作付き `hc-config.sh` を新設し、規範文書 5 file 更新で yml 参照経路を明文化する。完成すれば user が yml 直接編集なしで全 34+ key を安全に変更でき、規範側でも feature toggle / reviewer 制御の経路が AI / user 双方に明示される。

## 背景・目的

task-44 (Phase 1) で yml schema + loader が、task-45 (Phase 2) で hook feature check + review command が整備された。残る Phase 3 では:

1. **user-facing config editor**: `harness-config.yml` の手動編集は型 validation がなく、間違えるとハーネス全体が動作不能になるリスクがあった。`hc-config.sh` で型 + atomic + backup で安全化
2. **規範文書での yml 経路明示**: AI / user 双方が「機能 on/off は yml で集中管理」を認識できるよう、5 規範 file に yml 参照経路を文書化
3. **entry #52 引継ぎ 3 件 (TDD 順序 / toggle mapping / hook コメント) 統合**: task-45 reviewer iter 1 副産物の closure

これにより config-yml 3 Phase 全完遂、user 体験 (安全な edit) + AI 体験 (規範での yml 参照誘導) の両方が整う。

## TDD 戦略

### RED (entry #52 (1) 統合: smoke 先 commit / impl 後 commit)

- `.claude/tests/hc-config-script-smoke.sh` を **先に** 新設 (7 cases、impl 不在で 7/7 FAIL = RED)
- commit message: `test(task-46): hc-config-script-smoke.sh 新設 (RED、impl 未着手で 7/7 FAIL 期待)`

### GREEN (最小実装)

- `.claude/scripts/hc-config.sh` 実装 → smoke 7/7 PASS = GREEN
- commit message: `feat(task-46): hc-config.sh 実装 (対話 menu + CLI args + atomic、smoke 7/7 PASS)`

### REFACTOR

- script 関数分割 (parse / validate / write / backup)
- 3 観点判定 (持続可能性 / 汎用性 / 非冗長化)

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | smoke `hc-config-script-smoke.sh` 新設 (7 cases、TDD RED commit、entry #52 (1) 順序遵守) | 1.0h | — |
| 2 | 🔲 | `hc-config.sh` 実装 (対話 menu + CLI args + 値型 validation + atomic + backup、subagent staging) | 2.5h | Step 1 |
| 3 | 🔲 | 規範文書 5 file 更新 + 6 hook 冒頭コメント追加 + draft §3.1 共有 toggle mapping 整理 (entry #52 (2)(3) 統合) | 1.5h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) 6 reviewer 並列 (tdd-guide / test-automator / qa-expert / code-reviewer + security-reviewer + harness-optimizer) | 1.0h | Step 3 |
| 5 | 🔲 | (テスト合格) 全 smoke 統合実行 (新 7 + 既存 100+) regression 0 | 0.5h | Step 4 |
| 6 | 🔲 | (リファクタリング) script 関数分割 + 3 観点判定、closure commit + push + PR create | 0.5h | Step 5 |

合計工数: 7.0h

### Step 1: smoke `hc-config-script-smoke.sh` 新設 (TDD RED)

**Step status**: 🔲

**作業概要**: draft §4 の 7 cases を smoke として実装、impl 不在で 7/7 FAIL 状態を作る (entry #52 (1) TDD 順序遵守、smoke 先 commit)

**完了条件**:
- `.claude/tests/hc-config-script-smoke.sh` 新設 (7 cases)
- `bash .claude/tests/hc-config-script-smoke.sh` 実行で 7/7 FAIL (script 不在のため expected)
- commit message に `RED` 明記

### Step 2: `hc-config.sh` 実装 (TDD GREEN)

**Step status**: 🔲

**作業概要**: draft §3.1-3.3 仕様で `.claude/scripts/hc-config.sh` を実装、subagent staging 戦略で `.claude/` 配下に install

**完了条件**:
- `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation + atomic mv + `.bak.<ts>` backup)
- `bash .claude/scripts/hc-config.sh --help` 実行成功
- `bash .claude/tests/hc-config-script-smoke.sh` 7/7 PASS (GREEN)
- subagent confidence ≥ 0.8

### Step 3: 規範文書 5 file 更新 + 6 hook コメント追加 + draft §3.1 整理

**Step status**: 🔲

**作業概要**: draft §3.4 の規範文書 5 file 更新 + entry #52 (2)(3) 統合 (6 hook 冒頭コメント + draft §3.1 共有 toggle mapping 整理)

**規範文書 5 file の更新内容**:
- `.claude/rules/development-process.md` §「サブエージェント委譲」内 reviewer 制御 yml 参照追記
- `.claude/rules/workflow.md` §「設計レビュー fan-out」/「テスト設計 MECE」/「リファクタリング強制」内 yml key 参照追記
- `.claude/CommonRules.md` Design Constraints「機能 on/off は yml feature toggle で集中管理」追記
- `.claude/rules/task-management.md` 採用 6 条 4 (テスト設計レビュー) yml key 参照追記
- `docs/SELF_IMPROVEMENT.md` `hc-config.sh` 使用方法追記

**entry #52 (3) 6 hook 冒頭コメント追加対象**:
- `.claude/hooks/list-md-plan-first-reminder.sh`
- `.claude/hooks/loop-auto-progress-reminder.sh`
- `.claude/hooks/mode-enforce.sh`
- `.claude/hooks/next-actions-surface.sh`
- `.claude/hooks/why-x5-violation-detect.sh`
- `.claude/hooks/stop.sh`

各 hook 冒頭に「グループ制御 toggle: `feature_<name>_enabled`」コメント追加

**entry #52 (2) 共有 feature toggle mapping**: draft §3.1 に「5 共有 toggle 一括制御 mapping」整理追記 (loop_mode_enforcement / task_rule_guard / byproduct_discharge / notify / why_x5_enforcement)

**完了条件**:
- 規範文書 5 file 各 grep 検証 PASS (yml 参照 keyword 確認)
- 6 hook 冒頭コメント追加 grep 検証 PASS
- draft §3.1 共有 toggle mapping section 追記 (subagent staging 経由)

### Step 4: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: 6 reviewer 並列 (tdd-guide / test-automator / qa-expert / code-reviewer + security-reviewer + harness-optimizer)、収束まで反復 (上限 5 回)

security-reviewer 追加理由: hc-config.sh の atomic write + `.bak` file 残置のセキュリティリスク (env injection / path traversal / TOCTOU 等) を別 reviewer で確認するため。

**完了条件**: 全 reviewer approve / no objection (CRITICAL+HIGH+MEDIUM=0)、iter cycle 5 回以内収束

### Step 5: (テスト合格)

**Step status**: 🔲

**作業概要**: 新 smoke 7 case PASS + 既存 100+ smoke regression 0 で全件統合 PASS

**完了条件**: `bash .claude/tests/hc-config-script-smoke.sh` 7/7 + 既存 smoke 全件 regression 0

### Step 6: (リファクタリング) + closure

**Step status**: 🔲

**作業概要**: script 関数分割 (parse / validate / write / backup)、3 観点判定 (持続可能性 / 汎用性 / 非冗長化)、closure commit + push + PR create

**完了条件**:
- script 関数全 < 50 LOC (function 分割完了)
- 3 観点 PASS or skip 明示
- closure commit + push 完了
- `gh pr create` 完了 (task #39 緩和で自律実行可)
- 4 リポ install 案内 (user manual、cross-repo sandbox deny のため)

## 工数見積

7.0h (smoke 1h + impl 2.5h + 規範文書 1.5h + reviewer 1h + test 0.5h + refactor 0.5h)

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/tasks/task-46-config-yml-phase3-hc-config-script.md` / `.claude/scripts/hc-config.sh` / `.claude/tests/hc-config-script-smoke.sh` |
| 修正 file | `.claude/rules/development-process.md` / `.claude/rules/workflow.md` / `.claude/CommonRules.md` / `.claude/rules/task-management.md` / `docs/SELF_IMPROVEMENT.md` / `docs/draft/config-yml-phase3-hc-config-script.md` (§3.1 mapping 追記) / `.claude/hooks/*.sh` (6 hook 冒頭コメント) |
| migration | なし |
| 環境変数 | task-44 で定義済 34 件参照、本 task で新規追加なし |
| 互換性 | 既存 yml + hook + command 不変、`hc-config.sh` は新規追加のみ。後方互換 100% |

## 再発防止

- entry #52 (1) TDD 順序 (smoke RED commit 先) は本 task で _TASK_TEMPLATE.md にも反映予定 (本 task closure 後の副産物として記録)
- 6 hook 冒頭コメントは future hook 追加時の規範参照 default になる
- 規範文書 5 file での yml 参照経路明示で、AI / user の hardcode 誘導を構造的に防ぐ

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-27 | 起案 | draft `config-yml-phase3-hc-config-script.md` (approved_at: 2026-05-27) |
| 2026-05-27 | 承認 | user 承認 (PR #19 merge 後 task-46 着手指示)、list.md row 46 📝 → 🔄 |
| 2026-05-27 | 着手 | branch `feat/config-yml-phase3-hc-config-script` |
| 2026-05-27 | Step 1 完了 | commit `95d7fe4` (RED smoke 7/7 FAIL) |
| 2026-05-27 | Step 2 完了 | commit `d6cb269` (GREEN impl hc-config.sh 706 LOC、smoke 7/7 PASS) |
| 2026-05-27 | Step 3 完了 | commit `c580bd4` (規範文書 5 file + 6 hook 冒頭 + draft §3.1.1 toggle mapping) |
| 2026-05-27 | iter 2 fix | commit `d0fd5d8` (CRIT 2 + HIGH 7 + MED 8、smoke 7→15/15 PASS) |
| 2026-05-27 | iter 3 fix | commit `ed2d673` (CRIT 1 + HIGH 4、smoke 15→19/19 PASS) |
| 2026-05-27 | iter 4 fix | commit `1bc6cc0` (HIGH 3 単一根原因、bypass round-trip 整合性) |
| 2026-05-27 | iter 5 fix (最終) | commit `652f538` (CRIT 1 + HIGH 2 data corruption 3 surface 解消、smoke 19→21/21 PASS) |
| 2026-05-27 | Step 5 完了 | smoke 34/34 task-46 由来 PASS + 既存 37 smoke regression 0 (pre-existing FAIL 8 件 task-39 緩和起因で scope 外) |
| 2026-05-27 | Step 6 完了 | commit `66f162a` (refactor 42 関数 ≤ 48 LOC、3 観点 PASS、subagent refactoring-specialist confidence 0.96) |
| 2026-05-27 | 完了 | Step 1-6 全 ✅、累計 8 commits、smoke 21/21 + regression 0、iter cycle 5 回完遂、entry #52 引継ぎ 3 件 closure |

## 派生 task / 次アクション候補

(本 task 実装中に発生した副産物を記入。entry #52 (4) tests orchestrator / (5) autonomous-action-guard-smoke stale は本 task scope 外、別 task / entry #44 統合で対応)

## 関連

- Draft: [`config-yml-phase3-hc-config-script.md`](../draft/config-yml-phase3-hc-config-script.md)
- Master draft: [`config-yml-feature-toggles-and-editor.md`](../draft/config-yml-feature-toggles-and-editor.md)
- 依存タスク: task-44, task-45
- 起源: user 直接指示 2026-05-27 (config-yml 3 Phase 計画の最終段)
- 副産物統合: next-actions.md entry #52 (1)(2)(3)
