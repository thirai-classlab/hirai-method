---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #68: harness 挙動修正 (Workflow 標準化 / why-x5 緩和 / advisory pointer 化 / delegation-guard 修正)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: #67 (rule 再構造、対の task), #66 (advisory 削減、本 task に吸収・supersede)
> 設計起源: [harness-design-fundamental-review.md](../draft/harness-design-fundamental-review.md) ✅承認済 (approved_at 2026-06-01) §3.1-3.4 + §11 hook 注入判定

## Task ゴール

観測バグ (1 ターン多数 complex tool block → markup 崩れ → loop) の主犯と寄与要因が構造的に緩和される: (1) 多数 subagent fan-out が Workflow 標準化 + 1 ターン tool block 上限で規範化、(2) why-x5 が「tool 前毎回散文」→「ターン冒頭 1 回」へ緩和、(3) SessionStart advisory reminder が pointer 短縮 + 事実文化 + task-rule-guard note が session 1 回抑制 (task-66 吸収、enforcement 凍結)、(4) delegation-guard の改行/pipe 誤検知が解消。dogfood で markup 崩れが再現しない。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-67 | rule 再構造で modes.md / development-process.md / why-x5-output.md が Layer A/B 断片化される。本 task の規範追記 (Workflow 標準化 / why-x5 緩和) はその再構造後の構造に対して行うため、task-67 完遂後着手が望ましい (順序依存)。 | [task-67-rule-architecture-restructure.md](task-67-rule-architecture-restructure.md) |
| task-66 | advisory reminder 削減 (SessionStart pointer 化) を本 task に吸収。task-66 は supersede。 | [task-66-context-injection-inventory-reduction.md](task-66-context-injection-inventory-reduction.md) |

## Task 作業概要

- 多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限 (長 prompt は file 経由) を modes.md / development-process.md に規範化
- why-x5 を「tool 前毎回散文」→「ターン冒頭 1 回」へ緩和 (透明性維持、思考ロジックは内部)
- SessionStart advisory reminder pointer 短縮 + mode-enforce 事実文化 + session-help opt-in + task-rule-guard status-sync note を session 1 回抑制 (task-66 吸収、enforcement 凍結)
- delegation-guard splitter の改行/pipe (`| head` 等 read-only filter) 誤検知修正 (危険コマンド BLOCK は不変)

## Task 完了条件 (DoD)

- [ ] 多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限が規範化され、dogfood で markup 崩れが再現しない
- [ ] why-x5 がターン冒頭 1 回に緩和され、why-x5-reminder smoke regression 0
- [ ] SessionStart advisory pointer 化で起動時 token 実測削減、mode-enforce 事実文化、enforcement BLOCK smoke 全 PASS (不変)
- [ ] task-rule-guard status-sync note が session 1 回抑制、task.md 作成 BLOCK 不変 (smoke)
- [ ] delegation-guard の `| head`/`| tail`/`| wc` 等 read-only filter pipe が通り、危険コマンド BLOCK は不変 (smoke)
- [ ] reviewer approve (Step 4)
- [ ] commit + 4 リポ install user manual 案内

## Task 概要欄 (list.md 用、3 要素規範)

> 観測バグ (1 ターン多数 complex tool block で tool-call markup 崩れ → loop) の主犯と寄与要因を構造緩和するため、多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限 + why-x5 緩和 + advisory pointer 化/事実文化 (task-66 吸収) + delegation-guard 誤検知修正を行う。完成すれば tool-call 信頼性が上がり、起動時 context が削減され、enforcement を保ったまま過剰 reminder と harness friction が減る。

## 背景・目的

詳細は draft §1.1 (root cause) + §3.1-3.4 + §11 (research) を SSoT とする。research (§11): F1-4 Programmatic Tool Calling 優位 / F2-4 ordering effect / F4-1〜6 hook 注入の正しい使い方 / 過剰 3 点判定。

## 設計

draft §3.1 (Workflow 標準化) / §3.2 (advisory pointer 化、task-66 吸収) / §3.3 (why-x5 緩和) / §3.4 (delegation-guard 修正) を SSoT とする。

## TDD 戦略

### RED
- why-x5 / mode-enforce / session-help / task-rule-guard / delegation-guard smoke に pointer 出力 / opt-in / note 抑制 / pipe 誤検知解消 case 追加。enforcement BLOCK 不変 case 維持。

### GREEN
- 各 hook surgical 修正 (staging 戦略) + modes.md/development-process.md 規範追記。

### REFACTOR
- pointer 文言共通化 / splitter ロジック整理。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | Workflow 標準化 + 1 ターン tool block 上限 + why-x5 緩和 (ターン冒頭 1 回) を modes.md / development-process.md / why-x5-output.md に規範化 | 0.7h | — |
| 2 | 🔲 | SessionStart advisory pointer 化 + mode-enforce 事実文化 + session-help opt-in + task-rule-guard note 抑制 (task-66 吸収、enforcement 凍結) | 1.0h | — |
| 3 | 🔲 | delegation-guard splitter の改行/pipe read-only filter 誤検知修正 (危険 BLOCK 不変) + smoke 更新 | 0.8h | — |
| 4 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 (上限確認)、enforcement 不変の cross-check 重点 | 0.5h | Step 1-3 |
| 5 | 🔲 | (テスト合格 + リファクタ) 全 hook smoke regression 0 + 起動時 token 実測 + 1 ターン多数tool dogfood + 3 観点 refactor + 4 リポ install 案内 | 0.7h | Step 4 |

合計: **~3.7h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/{why-x5-reminder,mode-enforce,session-help-surface,task-rule-guard,delegation-guard}.sh` + `.claude/rules/{modes,development-process,why-x5-output}.md` + 各 smoke |
| migration | なし |
| 環境変数 | 既存 bypass env 不変 + `HC_SESSION_HELP_FORCE` (新、opt-in) |
| 互換性 | advisory 短縮 + splitter 誤検知修正のみ、enforcement BLOCK 完全不変 |

## 再発防止

- draft §1.2 C2/C3/C4 + §6 DoD の dogfood (1 ターン多数tool 再現有無) で効果を実測検証

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-01 | 起案 + 承認 | consolidated draft 承認、2 task 分割の Task-Y。task-66 を吸収・supersede |

## 派生 task / 次アクション候補

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

(実装中・レビュー中に発生した副産物を記入)

### 関連

- [`next-actions.md`](next-actions.md)

## 関連

- Draft: [harness-design-fundamental-review.md](../draft/harness-design-fundamental-review.md) ✅承認済 §3.1-3.4
- 対の task: [task-67-rule-architecture-restructure.md](task-67-rule-architecture-restructure.md) (rule 再構造)
- supersede: [task-66-context-injection-inventory-reduction.md](task-66-context-injection-inventory-reduction.md) (本 task に吸収)
