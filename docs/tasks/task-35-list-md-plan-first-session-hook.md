---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
# 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) metadata
total_steps: 5
-->

# Task #35: SessionStart hook で「list.md 空 + draft ≥ 3」検出 (plan-first reminder)

> Status: **🔲 未着手** (2026-05-25 起案、task #34 完了後着手予定)
> 起案: 2026-05-25 (task #33 分割、旧 Phase 3)
> 関連: #33 (継承元 task)、#34 (兄弟分割 task、依存先)、#36/#37 (兄弟分割 task)
> 設計起源: [`docs/draft/list-md-plan-first-normative.md`](../draft/list-md-plan-first-normative.md) §3 P3 (SessionStart hook)

## Task ゴール

`docs/draft/*.md` ≥ 3 件 ∧ `list.md` task 行 == 0 を SessionStart hook が検出し `<system-reminder>` で plan-first 規範参照を強制注入する (観察可能: 条件成立 session で SessionStart 出力に「list.md plan-first」keyword 含まれる、新 smoke `list-md-plan-first-reminder-smoke.sh` 3 cases PASS)。

## Task 作業概要

- 既存 `session-help-surface.sh` 拡張 or 新 hook `list-md-plan-first-reminder.sh` 新設 (subagent staging)
- bypass env: `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false`
- settings.json SessionStart 配線 (wrapper 順序確認)
- fail-open guard (list.md 不在環境で誤発火しない)
- 新 smoke 3 cases (条件成立 / 不成立 N=2 境界 / bypass) PASS

## Task 完了条件 (DoD)

- [ ] hook 実装完了 (`.claude/hooks/list-md-plan-first-reminder.sh` or `session-help-surface.sh` 拡張)
- [ ] bypass env `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false` 動作
- [ ] fail-open guard 動作 (list.md 不在で誤発火しない)
- [ ] settings.json SessionStart 配線 (jq 検証可能)
- [ ] `.claude/harness-config.yml` に `list_plan_first_reminder_enabled: true` キー追加 + config-loader.sh で `HC_LIST_PLAN_FIRST_REMINDER_ENABLED` export
- [ ] 6 reviewer 全 approve / no objection (iter cycle 5 回以内収束、Step 3)
- [ ] 新 smoke `list-md-plan-first-reminder-smoke.sh` で 3 cases PASS + 既存 smoke regression 0 (Step 4)
- [ ] リファクタリング 3 観点判定済 (Step 5)
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

batch planning 経路 B 不在事案の機械検出のため、SessionStart hook で「list.md 空 + draft ≥ 3」条件を検知し plan-first 規範参照を `<system-reminder>` 注入する。完成すれば AI が batch planning 計画下で list.md plan-first 先置きを忘れた時に session 開始毎に強制注意できるようになる。

## 背景・目的

task #33 で経路 B (batch planning) を規範化し task #34 で `/new-task` 動作を update or append に拡張したが、これらは AI が「経路 B を選ぶ」前提に依存する honor system。AI が経路 A only に退行する可能性が残存。

本 task では SessionStart hook で「list.md 空 + draft 多数 (= 計画進行中に plan-first 不在)」状態を自動検出し、`<system-reminder>` で plan-first 規範参照を強制注入する。AI の判断ミス回避を hook 経由で構造的に補完する (規範文書 + 機械検出の 2 段構え)。

## 仕様（決定済）

draft §3 P3 採用。SessionStart hook 経由で条件成立時に `<system-reminder>` 出力。

### 計測ロジック

- task エントリ行カウント: `grep -cE '^\| [0-9]' docs/tasks/list.md`
- draft カウント: `find docs/draft -name "*.md" -not -name "_*" | wc -l`
- 検出条件: `task_count == 0 && draft_count >= 3`
- fail-open guard: `[ -f docs/tasks/list.md ] || exit 0` (新規採用 project / `/init-tasks` 未実行環境で grep が exit 2 を返した場合の誤発火回避)
- bypass: `[ "${HC_LIST_PLAN_FIRST_REMINDER_ENABLED:-true}" = "false" ]` で skip

### 出力 format

`<system-reminder>` で stderr 出力 (SessionStart hook 仕様)、keyword `list.md plan-first` を含める。

## 設計

draft §3 P3 + 6 reviewer iter1 想定 finding (harness-opt M-01 / M-02) 反映。

### 既存 hook vs 新 hook 判定

- 案 A: 既存 `session-help-surface.sh` 拡張 — 機能集約だが責務膨張
- 案 B: 新 hook `list-md-plan-first-reminder.sh` 新設 — 責務分離、subagent staging 戦略遵守

**採用: 案 B** (責務分離 + 単体 smoke 容易化、約 30 LOC)。

### settings.json 配線順序 (wrapper 順序確認、harness-opt M-02)

現 SessionStart は `session-start-wrapper.sh` (timeout 15s) + `observe.sh` (timeout 3s) の 2 entry。wrapper.sh 内実装を Read し、新 hook を:
- (a) wrapper 内に組み込み (二重実行リスク回避 + 並列化)
- (b) 直接 SessionStart 配列に追記 (wrapper 後配置で wrapper failure 時の独立発火維持)

**採用: 案 b の wrapper.sh 後配置** (wrapper failure 時の独立発火維持優先、Step 3.2 で確定)。

## TDD 戦略

### RED
新 smoke `.claude/tests/list-md-plan-first-reminder-smoke.sh` を Step 4 で実装、3 cases で動作仕様検証。

### GREEN
- Step 1: hook 実装 (subagent staging で `.claude/hooks/list-md-plan-first-reminder.sh` 新設)
- Step 2: settings.json SessionStart 配線 + harness-config.yml + config-loader.sh 連携

### REFACTOR
- Step 5 で 3 観点判定、新 hook 約 30 LOC のため refactor 余地なし見込み (skip 想定)

## Step 計画

> **採用 6 条 (Task=Phase=N Step、2026-05-25 採用)** 準拠。Phase 中間階層なし、Task 直下 5 Step。

### Step 計画前の事前確認

- `git log --all --grep "plan-first-reminder" --oneline` で既存 commit 確認 (新規実装のため既存解消 commit なし)
- 既存 hook (`session-help-surface.sh` / `session-start-wrapper.sh`) を Read し配線順序確定

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | hook 実装 (subagent staging で `.claude/hooks/list-md-plan-first-reminder.sh` 新設、fail-open guard 含む) | 0.2h | — |
| 2 | 🔲 | settings.json SessionStart 配線 + harness-config.yml + config-loader.sh 連携 | 0.2h | Step 1 |
| 3 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定、iter cycle 5 回以内収束 | 0.5h | Step 2 |
| 4 | 🔲 | (テスト合格) 新 smoke 3 cases PASS + 既存 smoke regression 0 | 0.2h | Step 3 |
| 5 | 🔲 | (リファクタリング) 3 観点判定 (skip 想定: 新 hook 約 30 LOC、helper 抽出余地なし) | 0.1h | Step 4 |

合計工数: **1.2h** (元 Phase 3 工数 0.6 から iter cycle 込み実工数)

### Step 1: hook 実装 (subagent staging)

**Step status**: 🔲 未着手

**作業概要**: `.claude/hooks/list-md-plan-first-reminder.sh` を subagent staging で新設。fail-open guard (`[ -f docs/tasks/list.md ] || exit 0`) を hook 先頭に置く。`set -uo pipefail` (fail-open) で `set -e` なし、grep error は exit code 検知 + skip。

**完了条件**:
- hook file 存在 + bypass env 動作確認
- fail-open guard 動作 (list.md 不在で誤発火しない、Step 4 smoke Case で検証)
- hook 全体は `set -uo pipefail` (Critical Lesson HIGH 違反回避、caller leak 防止)

### Step 2: settings.json 配線 + config 連携

**Step status**: 🔲 未着手

**作業概要**: `.claude/settings.json` SessionStart 配列に新 hook entry 追加 (wrapper.sh 後配置)、`.claude/harness-config.yml` に `list_plan_first_reminder_enabled: true` キー追加、`.claude/hooks/lib/config-loader.sh` で `HC_LIST_PLAN_FIRST_REMINDER_ENABLED` env として export。

**完了条件**:
- `jq '.hooks.SessionStart' .claude/settings.json` で新 entry 含まれる
- `.claude/harness-config.yml` に `list_plan_first_reminder_enabled: true` キー追加
- `config-loader.sh` で `HC_LIST_PLAN_FIRST_REMINDER_ENABLED` export 確認 (_HC_KNOWN_KEYS / defaults / export 節 3 箇所追加)
- wrapper 順序確認: wrapper.sh **後**配置 (wrapper failure 時の独立発火維持)

### Step 3: (テスト設計レビュー)

**Step status**: 🔲 未着手

**作業概要**: 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + harness-optimizer)、並列起動、収束まで反復 (上限 5 回、超過時 user escalation、bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1`)。

**完了条件**:
- 全 reviewer approve / no objection
- iter cycle 5 回以内収束

### Step 4: (テスト合格) 新 smoke 3 cases PASS

**Step status**: 🔲 未着手

**作業概要**: 新 smoke `.claude/tests/list-md-plan-first-reminder-smoke.sh` で 3 cases 検証。tmp dir + hook 直接 bash 実行 + stderr grep。

**完了条件**:
- 新 smoke 3 cases PASS:
  - **Case 1 (条件成立)**: tmp dir に `docs/draft/` 配下 **3 file** 作成 + `docs/tasks/list.md` を task エントリ行 0 状態にして hook 直接 bash 実行 → stderr に `list.md plan-first` keyword を含む `<system-reminder>` 出力 (`grep -q "list.md plan-first"` で検証)
  - **Case 2 (不成立、N=2 境界)**: tmp dir に `docs/draft/` 配下 **2 file** のみ作成 + list.md 同条件 → stderr に keyword **含まれない** (`! grep -q "list.md plan-first"` で検証、N=3 が境界の真値、N=2 で不発火を実証)
  - **Case 3 (bypass)**: Case 1 と同条件 + `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false` env 設定 → stderr に keyword **含まれない**
- 既存 smoke regression 0 (`bash .claude/tests/task-rule-guard-smoke.sh` exit 0 + 既存 11 cases)
- fail-open guard 検証 Case (list.md 不在で hook 直接実行 → exit 0、誤発火なし)

### Step 5: (リファクタリング) 3 観点判定 (skip 想定)

**Step status**: 🔲 未着手

**完了条件**: `skip: hook 新設のみ (約 30 LOC)、汎用 helper 抽出余地なし、refactor 対象パターンなし` 明示記録 (or 実施なら 3 観点指標明示)

## 工数見積

合計 **1.2h** (Step 1: 0.2 + Step 2: 0.2 + Step 3: 0.5 iter cycle + Step 4: 0.2 + Step 5: 0.1)。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/list-md-plan-first-reminder.sh` (新設) / `.claude/settings.json` / `.claude/harness-config.yml` / `.claude/hooks/lib/config-loader.sh` / 新 smoke `.claude/tests/list-md-plan-first-reminder-smoke.sh` |
| migration | なし |
| 環境変数 | `HC_LIST_PLAN_FIRST_REMINDER_ENABLED` 新設 (default: true、bypass: false) |
| 互換性 | 既存 SessionStart hook 不変、新 entry 追記のみで backward 互換 |

## 再発防止

- SessionStart hook で plan-first 不在を毎セッション開始時に強制注意 → AI 判断ミス の構造的補完
- fail-open guard で新規採用 project (list.md 不在環境) での誤発火回避
- bypass env で開発時の一時無効化可能 (audit log に痕跡)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-25 | 起案 | task #33 着手後、採用 6 条 supersede で旧 Phase 3 を本 task に分割 |
| TBD | 着手 | branch `feat/list-md-plan-first-normative` (task #33 から継承) or 新 branch |
| TBD | Step 1 完了 | commit `<sha>` |
| TBD | Step 2 完了 | commit `<sha>` |
| TBD | Step 3-4 完了 | commit `<sha>` |
| TBD | Step 5 完了 | リファクタリング 3 観点判定 (skip 想定) |
| TBD | Task 完了 | 全 Step ✅、commit (push は user manual) |

## 派生 task / 次アクション候補

### 暫定候補 (実装着手時に発見次第追記)

- [ ] (🟢) hook の threshold 動的化 (draft ≥ N の N を env 設定可能化): 本 task scope 外、parking-lot 検討

### 関連

- [`next-actions.md`](next-actions.md) — entry #21 (継承元 task #33 と共有)
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「サブエージェント `.claude/` 編集の staging 戦略」

## 関連

- Draft: [`docs/draft/list-md-plan-first-normative.md`](../draft/list-md-plan-first-normative.md) §3 P3
- 継承元: #33 (task-management.md §plan-first 規範化)
- 兄弟分割: #34 (`/new-task` update or append) / #36 (task-rule-guard draft warn) / #37 (統合)
- 既存実装:
  - `.claude/hooks/session-help-surface.sh` (参考、責務分離のため拡張せず新 hook)
  - `.claude/hooks/session-start-wrapper.sh` (配線順序確認対象)
- 起源: task #33 着手時の採用 6 条 supersede による分割 (2026-05-25)
