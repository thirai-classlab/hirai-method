---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #66: hook context 注入インベントリ + サイズ縮小 (案A: advisory pointer 化)

> Status: **⏸️ 保留 (task-68 に吸収・supersede、2026-06-01)** — harness 全体見直し ([harness-design-fundamental-review.md](../draft/harness-design-fundamental-review.md)) で本 task の advisory 削減 scope は task-68 §3.2 に統合。本 task は単独着手せず task-68 で実施。
> 起案: 2026-06-01
> 関連: #51 (context-bloat-reduction、親施策・静的層), #68 (吸収先)
> 設計起源: [context-injection-inventory-reduction.md](../draft/context-injection-inventory-reduction.md) ✅承認済 (approved_at 2026-06-01 / approved_by takuma.hirai1@gmail.com)

## Task ゴール

SessionStart の advisory reminder (why-x5 / mode-enforce / session-help) が pointer 短縮 or opt-in 化され、task-rule-guard の docs/tasks status-sync note が session 1 回に抑制され、起動時 context が実測で削減される (目標 SessionStart -800〜1000 tok)。enforcement 系 hook (delegation / gateguard / autonomous-action / workflow / draft-flow / confidence / byproduct / reviewer-count) の BLOCK 動作は完全不変 (smoke で確認)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-51 | context-bloat-reduction (静的層 claudeMd/rules/memory を ~146K→100K)。本 task はその follow-up で **hook 由来の動的注入** に焦点。Layer A/B 2 層構造 (task-51 確立) の pointer 化方針を踏襲。 | [task-51-context-bloat-reduction.md](task-51-context-bloat-reduction.md) |

## Task 作業概要

- `why-x5-reminder.sh` / `mode-enforce.sh` の SessionStart 出力を pointer 短縮 (rules link + 最重要 1-2 行、bypass 不変)
- `session-help-surface.sh` を default silent + opt-in 化 (既存 `HC_SESSION_HELP_ENABLED` + force flag 活用)
- `task-rule-guard.sh` の docs/tasks status-sync note を session 1 回に抑制 (marker)、task.md 新規作成 BLOCK は不変
- smoke 更新 (各 hook の pointer 出力 + enforcement 不変を検証) + 起動時 token 実測 (before/after diff)

## Task 完了条件 (DoD)

- [ ] SessionStart advisory reminder (why-x5 / mode-enforce / help) が pointer 短縮 or opt-in 化され、起動時 token が実測で削減 (before/after diff)
- [ ] enforcement 系 hook (delegation / gateguard / autonomous / workflow / draft-flow / confidence / byproduct / reviewer-count) の BLOCK 動作 smoke 全 PASS (不変確認)
- [ ] task-rule-guard の task.md 作成 BLOCK 不変 + status-sync note 抑制 smoke PASS
- [ ] 全 hook smoke regression 0
- [ ] 起動時 token 実測削減 (目標 SessionStart -800〜1000 tok)
- [ ] reviewer approve (Step 5、enforcement 不変 cross-check 重点)
- [ ] 4 リポ install (user manual `bash install.sh --update <target>`)
- [ ] commit 完了 (push は feature branch 自律可、main merge は user)

## Task 概要欄 (list.md 用、3 要素規範)

> tool-call parse 失敗の頻発と hook 注入の過剰を解消するため、SessionStart の advisory reminder (why-x5 / mode-enforce / session-help) を pointer 短縮 + opt-in 化し、task-rule-guard の status-sync note を session 1 回抑制する (案A、enforcement 完全凍結)。完成すれば起動時 context が ~800-1000 tok 削減され、ルール保持 (BLOCK 不変) を保ったまま過剰注入が減る。

## 背景・目的

task-51 で起動時 context ~146K→100K を達成済だが、本 task は **hook 由来の動的注入** に焦点を当てる。調査結論として、毎ターン無条件の注入は実質ゼロであり、負荷は (a) SessionStart 1 回の advisory reminder 群 (~1600 tok) と (b) ツール使用毎の条件付き guard 注入 (特に task-rule-guard の docs/tasks 編集 note 毎 ~250 tok) に集中する。enforcement 系は違反時のみ注入で baseline 0。優先度 (① ルール保持 > ② 削減) を守り、enforcement を凍結したまま advisory のみ削減する。

## 仕様（要決定 → 決定済）

詳細は draft §4 (案比較) / §5 (採用案A詳細設計) を SSoT とする。案A採用 (enforcement 凍結 + advisory pointer 化)、案B (完全OFF) は salience 喪失リスクで却下、案C (静的層含む再設計) は別 task 規模で却下。

## 設計

詳細設計は draft §5 を SSoT とする。

## TDD 戦略

### RED
- 各 hook smoke に pointer 出力 / opt-in 動作 / note 抑制 case 追加。enforcement 系 smoke は不変確認 (BLOCK 全 PASS)。

### GREEN
- why-x5-reminder.sh / mode-enforce.sh / session-help-surface.sh / task-rule-guard.sh の surgical 修正 (staging 戦略)。

### REFACTOR
- pointer 文言の共通化 / marker ロジック整理。

## Step 計画

> 採用 6 条 (Task=Phase=N Step)。本 task は hook 修正で UI なし → Step 6 (テスト合格) は smoke regression + 起動時 token 実測。

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | why-x5-reminder.sh / mode-enforce.sh の出力を pointer 短縮 (rules link + 最重要 1-2 行)、bypass 不変 | 0.5h | — |
| 2 | 🔲 | session-help-surface.sh を default silent + opt-in 化 (既存 `HC_SESSION_HELP_ENABLED` + force flag) | 0.3h | — |
| 3 | 🔲 | task-rule-guard.sh の docs/tasks status-sync note を session 1 回抑制 (marker)、task.md 作成 BLOCK 不変 | 0.5h | — |
| 4 | 🔲 | smoke 更新 (各 hook の pointer 出力 + enforcement 不変を検証) | 0.5h | Step 1-3 |
| 5 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 (上限 `review_max_count_*` 確認)、enforcement 不変 cross-check 重点 | 0.5h | Step 4 |
| 6 | 🔲 | (テスト合格) 全 hook smoke regression 0 + 起動時 token 再実測 (before/after diff) | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 + 4 リポ install user manual 案内 | 0.3h | Step 6 |

合計工数: **3.1h**

### Step 1: SessionStart reminder pointer 短縮

**Step status**: 🔲

**作業概要**: `why-x5-reminder.sh` の full format 説明 (~275 tok) → 「Why×5 v10 (1 行 format)。詳細 `.claude/rules/why-x5-output.md`」+ format 1 行例 (~80 tok)。`mode-enforce.sh` の Loop 遵守事項 full (~300 tok) → 「Loop モード稼働中: 確認質問禁止 / AI 推奨即採用 / 自律継続。詳細 `modes.md`」(~100 tok)。bypass env 不変。staging 戦略で subagent 委譲。

**完了条件**: 両 hook の出力が pointer 化され、bypass env (`HC_WHY_X5_DISABLE` / `feature_loop_mode_enforcement_enabled`) 動作不変、smoke PASS。

### Step 2: session-help opt-in 化

**Step status**: 🔲

**作業概要**: `session-help-surface.sh` を default silent + opt-in (`/help` or `HC_SESSION_HELP_FORCE=1` 時のみ注入)。既存 `HC_SESSION_HELP_ENABLED` を活用。

**完了条件**: default で SessionStart に help 注入なし、force flag 時のみ注入、smoke PASS。

### Step 3: task-rule-guard note 抑制

**Step status**: 🔲

**作業概要**: `task-rule-guard.sh` の docs/tasks 配下 status-sync 編集 note を session 1 回のみに抑制 (state marker)。task-*.md / phase-*.md の新規作成 BLOCK は完全不変。

**完了条件**: status-sync 編集 2 回目以降 note 抑制、task.md 作成 BLOCK 不変 (smoke で両方確認)。

### Step 4: smoke 更新

**Step status**: 🔲

**作業概要**: why-x5 / mode / help / task-rule-guard smoke に pointer 出力 + enforcement 不変 case 追加。

**完了条件**: 新規/更新 smoke PASS、既存 hook smoke regression 0。

### Step 5: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: 5+ reviewer 動的選定。起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限確認 (task-64 強制)。並列起動 → 収束まで反復。enforcement 不変の cross-check を重点観点に明示。

**完了条件**: 全 reviewer approve / no objection (CRITICAL+HIGH=0)、iter cycle 上限内収束。

### Step 6: (テスト合格)

**Step status**: 🔲

**作業概要**: 全 hook smoke regression 0 + 起動時 token before/after 実測 diff。UI なしのため E2E/visual 不要。

**完了条件**: 全 hook smoke exit 0、起動時 token 削減を実測で確認 (目標 SessionStart -800〜1000 tok)。

### Step 7: (リファクタリング)

**Step status**: 🔲

**作業概要**: 3 観点 (持続可能性 / 汎用性 / 非冗長化) 判定。pointer 文言の共通化余地を点検。**4 リポ install は user manual** `bash install.sh --update <target>` 案内 (cross-repo write は agent 経路 deny)。

**完了条件 (or skip)**: 3 観点 PASS or `skip: <理由>`、4 リポ install 案内記録。

## 工数見積

合計 **3.1h** (hook 出力短縮 + opt-in + note 抑制 + smoke + reviewer + 実測)。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/why-x5-reminder.sh` / `mode-enforce.sh` / `session-help-surface.sh` / `task-rule-guard.sh` + 各 smoke |
| migration | なし |
| 環境変数 | 既存 bypass env 不変 (`HC_WHY_X5_DISABLE` / `HC_SESSION_HELP_ENABLED` / `HC_SESSION_HELP_FORCE`(新) 等) |
| 互換性 | advisory 出力短縮のみ、enforcement BLOCK 完全不変 |

## 再発防止

- reminder pointer 化で salience 低下リスク (Loop 逸脱 / why-x5 忘れ増) → 最重要 1-2 行は残す + rules pointer、Step 5 reviewer で salience 評価、dogfood 1-2 session 観察 (draft §6)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-01 | 起案 | draft `context-injection-inventory-reduction.md` 起こし (案A) |
| 2026-06-01 | 承認 | user 承認、list.md に追加 |

## 派生 task / 次アクション候補

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

(実装中・レビュー中に発生した副産物を記入。`/finish-task` 時に全 entry 処理済が必須)

### 関連

- [`next-actions.md`](next-actions.md)
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「副産物発生時の即時 draft 起こし義務」

## 関連

- Draft: [context-injection-inventory-reduction.md](../draft/context-injection-inventory-reduction.md) ✅承認済
- 親施策: [task-51-context-bloat-reduction.md](task-51-context-bloat-reduction.md)
