---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #67: rule architecture 再構造 (全 6 rule の Layer A 軽量化 + Layer B 断片化)

> Status: **🔄 進行中** (2026-06-01 着手、branch `refactor/rule-architecture-restructure`)
> 起案: 2026-06-01
> 関連: #66 (advisory 削減、task-68 に吸収), #51 (context-bloat-reduction、静的層)
> 設計起源: [harness-design-fundamental-review.md](../draft/harness-design-fundamental-review.md) ✅承認済 (approved_at 2026-06-01) §3.0 + §3.5 Step 1-3

## Task ゴール

全 6 rule (workflow / development-process / modes / task-management / self-improvement / why-x5-output) が、常時 load される Layer A (`rules/*.md`、目標 <120 行) は概要 + command/key 表 + pointer のみになり、詳細は `rules-details/<rule>/<topic>.md` の topic 別断片 (目標 <100 行) に分割され、Layer A は断片ファイルを直リンク pointer で指す。`rules-details/**` は auto-load されないことが smoke で保証され、enforcement BLOCK ロジックと SSoT 内容は無損失。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-51 | context-bloat-reduction で Layer A/B 2 層構造を確立。本 task はその「Layer B を topic 別断片化 + Layer A をさらに軽量化」への発展。 | [task-51-context-bloat-reduction.md](task-51-context-bloat-reduction.md) |

## Task 作業概要

- 断片化の命名 / ディレクトリ / pointer 規約確定 + `rules-details/README.md` を index 化
- 全 6 rule の Layer B 断片化 (各 `*.details.md` → `rules-details/<rule>/<topic>.md`) + Layer A pointer 直リンク書換
- 全 6 rule の Layer A 軽量化 (full table / 機構詳細を断片へ移送、要約 + pointer 化)
- smoke (Layer A pointer の断片存在検証 / `rules-details/**` auto-load 非対象 / enforcement 不変 / 起動時 token before-after)

## Task 完了条件 (DoD)

- [ ] 全 6 rule の Layer A が <120 行、詳細は `rules-details/<rule>/<topic>.md` 断片に分割
- [ ] Layer A の全 pointer が実在する断片ファイルを直リンク (dangling 0、smoke 検証)
- [ ] `rules-details/**` (subdir 含む) が startup auto-load されない (smoke or 手順で確認)
- [ ] enforcement hook の BLOCK 動作 smoke 全 PASS (rule 再配置で不変)
- [ ] SSoT 内容無損失 (採用 N 条 / 規約 / table を欠落させない、reviewer cross-check)
- [ ] 起動時 token before/after 実測で削減
- [ ] reviewer approve (Step 5)
- [ ] commit (push は feature branch 自律可、main merge は user) + 4 リポ install user manual 案内

## Task 概要欄 (list.md 用、3 要素規範)

> Layer B (*.details.md) が 1 rule = 1 巨大ファイルで「1 detail 欲しいだけで全部読む」構造になっている問題を解消するため、全 6 rule を Layer A (概要+pointer のみ) + Layer B (topic 別断片) に再構造する。完成すれば「必要な時に必要なルール断片だけ Read」になり、常時 load の Layer A も軽量化され context 肥大 (instruction overload) が構造的に削減される。

## 背景・目的

詳細は draft §1.2 (C1/C6) + §3.0 を SSoT とする。現状 Layer A は常時 load なのに過大 (workflow 349 / dev-process 323 / task-mgmt 250 行)、Layer B は monolithic (90-388 行) で on-demand 読込が surgical でない。research (§11 F3-3 prompt bloat ~3000 tok / F3-6 / F4-2 skills-on-demand) が裏付け。

## 設計

draft §3.0 を SSoT とする。目標構造:

```
.claude/rules/<rule>.md          # Layer A: 概要 + command/key 表 + pointer のみ (<120 行)
.claude/rules-details/<rule>/    # Layer B: topic 別断片 (<100 行/file)
    <topic>.md ...
```

pointer 規約: `> 詳細: [rules-details/workflow/workflow-guard.md](../rules-details/workflow/workflow-guard.md)` (anchor 方式廃止)。

## TDD 戦略

### RED
- smoke `rule-architecture-smoke.sh` (新規): 全 Layer A の pointer path を抽出し断片存在を assert / `rules-details/**` が rules/ 外を assert / Layer A 行数上限 assert。

### GREEN
- 断片化 + Layer A 軽量化 + pointer 書換。

### REFACTOR
- 断片の重複統合 / README index 整備。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | 命名 / ディレクトリ / pointer 規約確定 + `rules-details/README.md` index 設計 + auto-load 非対象の検証方法確定 | 0.5h | — |
| 2 | ✅ | 全 6 rule の Layer B 断片化 (`*.details.md` → `rules-details/<rule>/<topic>.md`) + Layer A pointer 直リンク書換 | 2.0h | Step 1 |
| 3 | ✅ | 全 6 rule の Layer A 軽量化 (full table / 機構詳細を断片へ移送、要約 + pointer、<120 行/file) | 1.5h | Step 2 |
| 4 | ✅ | smoke 新規 + 既存更新 (pointer dangling 0 / auto-load 非対象 / 行数上限 / 起動時 token before-after) | 1.0h | Step 3 |
| 5 | ✅ | (テスト設計レビュー) 5 reviewer 動的選定、enforcement 不変 + SSoT 無損失 cross-check 重点。iter1 で全 HIGH/CRIT 修正 (機械検証収束) | 0.5h | Step 4 |
| 6 | 🔄 | (テスト合格) 全 hook / script smoke regression 0 + 起動時 token 削減実測 | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 + 4 リポ install user manual 案内 | 0.3h | Step 6 |

合計: **~6.3h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/rules/*.md` (6) / `.claude/rules-details/**` (断片化) / `.claude/tests/rule-architecture-smoke.sh` (新規) / `install.sh` (再帰 copy 確認) |
| migration | rule 文書の再配置のみ (コード不変) |
| 環境変数 | なし |
| 互換性 | Layer A pointer の参照先変更 (anchor → 断片 file)。enforcement / SSoT 不変 |

## 再発防止

- 「Layer A/B 2 層化したが Layer B が monolithic で on-demand が surgical でない」問題 → 本 task で「1 断片 = 1 pointer 先 = 1 topic、<100 行」を規約化し、将来の rule 追加でも踏襲

## 進捗 / 次セッション継続メモ (2026-06-01)

- **Step 1 完了** (commit `ddc3058`): 断片化規約確定 (`rules-details/<rule>/<topic>.md`、pointer 直リンク、auto-load 非対象検証方法、README index)。
- **Step 2 pilot 完了** (commit `e026f94`): workflow を 12 断片に分割 + Layer A pointer 化 (349→327 行)、smoke 8/8 PASS、SSoT 無損失、旧 details.md 削除。
- **粒度標準 = 積極 (user 決定 2026-06-01)**: Layer A は要約+pointer のみ、**14-stage/10-stage の full 表・workflow-guard 機構等の大表も Layer B 断片へ移送** (Layer A 目標 <120-150 行)。workflow を本標準に再 slim 中 (subagent a856b6eb)。
- **残り 5 rule 完遂 (2026-06-01、51st session)**: 5 subagent 並列 (1 rule=1) で断片化 + Layer A slim。commit `0ffddf2` (self-improvement 70行/why-x5-output 90行、各4断片) / `f45018c` (modes 176行、5断片) / `5211138` (task-management 253行、8断片) / `a362f19` (development-process 324→266行 -18%、8断片)。全 5 rule 旧 .details.md git rm 済、dangling 0、SSoT 無損失 (採用6条条文/遵守事項9件/操作SSoT表はLayer A保持)。dense操作rule (dev-process266/modes176/task-mgmt253) は <120 DoD 超過だが SSoT 優先で妥当 (Step 5 reviewer 評価)。README index 全6 rule ✅。
  - **学習**: subagent が共有 index (README) を stale copy で編集 → 直前 commit 済 task-management ✅ を 🔲 に巻き戻す race 発生。main で復元修正。次回は subagent prompt に「共有 index file は編集禁止、main のみ更新」を明記すべき。
- **Step 4 (進行中、51st)**: rule-architecture-smoke.sh 新規 (dangling 0 / auto-load isolation / back-link 健全性 / 行数報告) + layer-b-context-isolation-smoke 断片対応 + token before-after 実測。subagent a126afe。
- **Step 5-7 (次)**: テスト設計レビュー 5+ reviewer (上限 hc-config 確認、enforcement 不変 + SSoT 無損失 cross-check) + 全 hook/script smoke regression 0 + refactor 3 観点 + PR create (feature branch、user merge) + 4 リポ install user manual。
- branch: `refactor/rule-architecture-restructure` (push 後 PR は user merge)。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-01 | 起案 + 承認 | consolidated draft 承認、2 task 分割の Task-X |
| 2026-06-01 | Step 1+2 pilot | `ddc3058` 規約 / `e026f94` workflow 12 断片。残り 5 rule は次セッション (積極粒度) |

## 派生 task / 次アクション候補

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

**Step 5 reviewer findings 対応結果 (iter1、commit `ef3844f`)**:
- ✅ HIGH (SSoT-audit): dev-process Layer A slim で消失した scope 境界規範 4 項目 (worktree deny / 単一 repo staging 可 / cross-repo Phase 明記 / 副産物 user manual 経路) を staging-strategy.md + cross-repo-write.md 断片に復元 (grep 確認)
- ✅ HIGH (code/architect/qa/pr-test): origin.md 4 件 orphan を Layer A origin pointer 追加で解消、smoke Assert 5 (orphan 検出) で機械防止
- ✅ HIGH (pr-test/qa): smoke Assert 6 (back-link path 解決) 追加、41 件全解決
- ✅ MED (qa): docs/INVENTORY.md を断片構造に更新
- ✅ MED (code/pr-test): back-link §section 修正 (modes/origin, self-improvement/origin)

**defer (🟢 LOW / optional、follow-up 候補)**:
- architect MED「dev-process を更に slim (harness取込 38 行 + default mapping 13 行を断片移送)」→ **却下** (SSoT 損失が過剰 slim から生じた以上、保守的に保持が正。size より SSoT 優先 = `feedback_ssot_priority_over_size_target`)
- pr-test LOW: smoke Case 5 行数下限 >5→≥8 / Assert 4 WARN 閾値 280→200 + dense rule 除外リスト / 断片 sentinel keyword (Case 9) / §section 存在検証 (fragile のため WARN 止まり)
- architect MED: SSoT anchor regression assert (採用 N 条番号 / env 名 / regex の固定 list 突合) — Layer A slim 時の移送漏れを機械検出する将来強化
- **reviewer-count-guard 誤発火** (本 session で累計 subagent 18 体を「reviewer」誤算入、category 推定が断片化/smoke subagent を含む) → 既知 task-68 scope

### 関連

- [`next-actions.md`](next-actions.md)

## 関連

- Draft: [harness-design-fundamental-review.md](../draft/harness-design-fundamental-review.md) ✅承認済 §3.0
- 対の task: [task-68-harness-behavior-fixes.md](task-68-harness-behavior-fixes.md) (挙動修正)
