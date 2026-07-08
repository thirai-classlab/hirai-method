---
# optional. format: https://app.asana.com/0/<project_id>/<task_id>
asana_url: ""
# optional. array of Slack permalinks (https://<workspace>.slack.com/archives/<channel>/p<timestamp>)
slack_urls: []
# optional. ISO-8601 date (例: 2026-06-01)
deadline: ""
# optional. 依頼者名 (Asana 連携 off プロジェクトでは空のままで OK)
requester: ""
---

<!--
# 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) metadata
# 実 task では下記を値で埋める。
total_steps: 0
-->

# Task #<ID>: <タスク名>

> Status: **draft (要承認)** | **🔲 未着手** | **🔄 進行中** | **✅ 完了**
> 起案: YYYY-MM-DD
> 関連: <#N, #M>
> 設計起源: [<draft または PDCA リンク>](../draft/<file>.md)

> **現 effective preset は** `bash .claude/scripts/hc-config.sh --summary` で確認。本 task 内 BLOCK 記述 / hook 強制動作は preset 依存 (harness-dev では advisory、team-default / strict では BLOCK)。docs↔effective 乖離は `.claude/tests/enforcement-mismatch-smoke.sh` が機械検証する。

## Task ゴール

<完了時に何が達成されているか、1 文、観察可能な事実で記述>

例: 「`.claude/rules/task-management.md` に §「plan-first」が追加され、batch planning 時の 📝 行先置きフロー 2 経路分岐 (経路 A/B) と凡例 📝 用途 (2 用途) が明文化される」

## Task 依存先タスク

> **規約 (採用 6 条 2、2026-05-26 追加)**: 0 以上の複数可。依存なしは「— (依存なし)」と明示 (空欄禁止)。各依存先について **影響内容 (1-2 文)** + **依存先 task.md へのリンク** を記載。本 task 開発開始時 (`/start-task` 直後) に依存先 task.md + 関連 draft を **必ず Read** すること (詳細: `.claude/rules/task-management.md` §「開発開始時の必読義務」)。

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-N1 | <本 task が task-N1 の何にどう影響を受ける / 何を前提とするか> | [task-N1-<slug>.md](task-N1-<slug>.md) |
| task-N2 | <影響内容 2> | [task-N2-<slug>.md](task-N2-<slug>.md) |

(依存なしの場合は table を削除し「— (依存なし)」と記載)

## Task 作業概要

- <作業項目 1>
- <作業項目 2>
- <作業項目 3>
- (3-5 件、箇条書き)

## Task 完了条件 (DoD)

- [ ] <観察可能な振る舞い 1>
- [ ] <観察可能な振る舞い 2>
- [ ] テスト追加 + 全 PASS (regression 0)
- [ ] docs 反映（rules / runbook 含む）
- [ ] reviewer 5+ approve (Task 最終 3 Steps の「テスト設計レビュー Step」で達成)
- [ ] 既存 N tests 維持
- [ ] commit 完了 (push は user manual で実施、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

> **規約 (採用 6 条 6)**: 「何のため × 何をやる × 何ができるようになる」の 3 要素を 1 段落で記述

例: 「recall_poc plan-first 不在事案の再発防止のため、task-management.md §plan-first を追加し batch planning 時の 📝 行先置きフロー 2 経路分岐を明文化する。完成すれば AI が batch planning 時に list.md plan-first 先置きを規範通り実行できるようになる。」

## 背景・目的

<なぜこのタスクが必要か。1〜3 段落で。>

## 仕様（要決定 → 決定済）

### Q1: <決定すべき事項>

| 案 | 内容 | 評価 |
|---|---|---|
| **A** | … | … |
| B | … | … |

→ <選択結果と理由>

### Q2: …

## 設計

<採用案に基づく具体設計。図・コード・schema を含めて良い。>

```mermaid
flowchart LR
    A --> B
```

## TDD 戦略

> **本セクションと「Step 計画」最終 3 Steps の関係**:
> 本 §「TDD 戦略」は **Task 全体に対する戦略** (RED/GREEN/REFACTOR) を記述する。
> 一方、§「Step 計画」末尾に固定配置される **テスト設計レビュー → テスト合格 → リファクタリング** の 3 Steps は **Task 単位の REVIEW→GREEN→REFACTOR** を表す。
> 両者は **互いに補完する関係** (二重化ではない)。本 §で全体戦略を、Step 計画末尾で実行手順を書く。

### RED（先に追加するテスト）

- `tests/foo.test.ts`
  - <観点1>
  - <観点2>

### GREEN（最小実装）

- `src/lib/foo.ts` を新設し <X> を実装
- 既存 N tests + 新規 M tests を全 PASS

### REFACTOR

- <抽出・命名整理・重複排除の余地>

## Step 計画

> **採用 6 条 (Task=Phase=N Step、2026-05-25 採用)**:
> Phase 中間階層は廃止。Task 直下に N Step を列挙し、最終 3 Steps は固定 (テスト設計レビュー / テスト合格 / リファクタリング)。
> 旧 task で `Wave` / `Phase` 表記を使用していた箇所は本セクションの `Step` と読み替える (移行ガイドは `.claude/rules/task-management.md` §「既存 task 移行ガイド」参照)。

### Step 計画前の事前確認 (必須)

別 repo 作業 / 既存 gap-review report 起点の Step 計画では、各 finding に対し以下を**着手前に**実施:

1. `git log --all --grep <finding-id-or-keyword> --oneline` で既存 commit を確認 (別 repo は `git -C <abs path> log --all --grep ...`)
2. 該当 file を Read で現状確認
3. 解消済 finding は Step list から除外し、本テンプレに「[no-op、commit <sha> で解消済]」と記録
4. 未解消 finding のみ subagent dispatch 対象に残す

省略時: 重複 subagent 起動 / no-op 発覚での Step 再計画コスト

### cross-repo write を含む Step の注意 (必須)

cross-repo write (本 repo → 外部 repo への Write / cp / mv / heredoc redirect) を含む Step は、Step description に **user manual 注意書きを必ず明記**:

> 例: `Step N (cross-repo): user manual `bash install.sh --update <target>` 案内`

理由: cross-repo write は Claude Code sandbox + `delegation-guard.sh` 二重制約で agent 経路完全 denied、user manual (terminal) 実行のみ可能 (詳細: `.claude/rules/development-process.md` §「cross-repo write 例外」)。Step 計画段で明記しないと、subagent dispatch 時に sandbox deny で進行不能 / loop 停止の誤判断リスクあり (development-process.md §5 と同種の反射パターン)。

省略時: subagent 起動 → 即時 deny → 「進められない」誤報告 → loop 停止のコスト

### Step schema (採用 6 条準拠)

各 Step に **作業概要 (1-2 文 actionable description)** + **完了条件 (定量指標 or 観察可能な事実)** + **Step status (📝/🔲/🔄/✅/⏸️)** + **概要欄 (list.md 用、作業概要のみ)** を必ず記載する。
Task の **最終 3 Steps は固定**: `(テスト設計レビュー) → (テスト合格) → (リファクタリング)`。
- テスト設計レビュー: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific) → 並列起動 → 収束まで反復 (上限 5 回、超過時 user escalation、bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1`)
- テスト合格: UI 含む Task は E2E 必須 (Playwright 等)、それ以外は unit/integration test
- リファクタリング: 不要なら `skip: <reason>` 明示

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | <作業 1> | 0.3h | — |
| 2 | 🔲 | <作業 2> | 0.5h | Step 1 |
| 3 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 | 0.5h | Step 2 |
| 4 | 🔲 | (テスト合格) unit/integration/E2E test | 0.3h | Step 3 |
| 5 | 🔲 | (リファクタリング) 3 観点判定 or skip | 0.2h | Step 4 |

合計工数: <X> h

### Step 1: <作業概要 1>

**Step status**: 🔲 未着手 | 🔄 進行中 | ✅ 完了

**作業概要 (list.md 概要欄)**: <1-2 文 actionable description>

**完了条件**: <定量指標 or 観察可能な事実 (例: `pnpm test` exit 0、grep -q 'X' file)>

### Step 2: <作業概要 2>

**Step status**: 🔲

**作業概要**: <1-2 文>

**完了条件**: <…>

### Step 3: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific)、並列起動、収束まで反復 (上限 5 回)

**完了条件**: 全 reviewer approve / no objection (修正提案 0 件)、iter cycle 5 回以内収束

### Step 4: (テスト合格)

**Step status**: 🔲

**作業概要**: <UI 含む Task なら E2E 必須 (Playwright 等)、それ以外は unit/integration test>

**完了条件**: `<test command>` exit 0、全 case PASS (regression 0)

### Step 5: (リファクタリング)

**Step status**: 🔲

**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点で見直す

**完了条件 (or skip)**: refactor 実施なら指標 (例: 関数 LOC < 50、重複削減 N 箇所) / 不要なら `skip: <理由>` を明示記録

### 小タスクモード (1 Task + 1 Step 完結)

typo 修正 / 1 行 fix / コメント追加 / 規範文書の文言調整 等、**1 Task + 1 Step で完結する作業** は以下の最小 schema で OK。
ただし「テスト設計レビュー (5+ reviewer 動的選定、収束まで反復、上限 5 回) + テスト合格 (規範文書修正なら observability check で代替) + リファクタ skip 記録」は **必須** (Step 内に併記可)。

```markdown
### Step 1: <作業概要>

**Step status**: 🔲

**作業概要**: <1-2 文>

**完了条件**:
- <定量 or 観察可能 (例: `grep -q 'X' file` PASS)>
- reviewer 5+ approve (本 Step 内で完結)
- unit test or observability check (規範文書なら grep 等) exit 0
- refactor 判定: skip (理由: 1 行 fix、refactor 対象なし) or 実施
```

## 工数見積

<例: 2-3 時間（実装 60 分 + TDD テスト 60 分 + 検証 30 分）>

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `src/...`, `tests/...`, `docs/...` |
| migration | <あり/なし> |
| 環境変数 | <追加・変更> |
| 互換性 | <破壊的変更の有無> |

## 再発防止

<このタスクから派生する rule / skill / 監査項目があれば。>

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| YYYY-MM-DD | 起案 | 設計 draft 起こし |
| YYYY-MM-DD | 承認 | user 承認、`list.md` に追加 |
| YYYY-MM-DD | 着手 | branch `<type>/<short-kebab-description>` |
| YYYY-MM-DD | Step 1 完了 | commit `<sha>` |
| YYYY-MM-DD | Step 2 完了 | commit `<sha>` |
| YYYY-MM-DD | 完了 | commit `<sha>`、+<N> tests |

## 派生 task / 次アクション候補

このタスクの実装中・レビュー中・完了時に「これは別 task として管理すべき」と判断した副産物 (byproduct) を箇条書きで記入する。

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

- 副産物発見の瞬間に **必ず本セクションに記入** (memory / 会話履歴に流すだけは禁止)
- task 完了 (`/finish-task`) 時、本セクションのすべての entry が以下のいずれかに処理済であること:
  - (a) `docs/draft/<slug>.md` に draft 起こし済 (緊急度 🔴 / 🟡)
  - (b) `docs/tasks/next-actions.md` に entry 追加済 (緊急度 🟢 + 後日判断)
  - (c) 無視 (理由を明記、commit message に記録)
- 未処理 entry が残ったまま `/finish-task` は `workflow-guard.sh` が BLOCK する (将来 W4 拡張)

### 記入例

- [ ] (🔴) PR 作成 — `feat/loop-mode` → `main` の merge → [draft 起こし済](../draft/create-pr-feat-loop-mode.md) → task #2
- [ ] (🟡) context-budget hook 実発火検証 — → [draft 起こし済](../draft/context-budget-hook-verification.md) → task #3
- [ ] (🟢) 別リポ調査 (後日) — [next-actions.md](next-actions.md) entry #N で記録
- [x] (🟢→無視) 旧 API のリファクタ案 — 工数過大 + 互換性破壊リスクで不採用、本 commit message に理由記載

### 関連

- [`next-actions.md`](next-actions.md) — 本セクションと連動する registry
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「副産物発生時の即時 draft 起こし義務」

## 関連

- Draft: [<draft file>](../draft/<file>.md)
- 依存タスク: <#N>
- 派生タスク: <#M>
