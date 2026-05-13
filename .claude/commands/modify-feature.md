---
description: 既存機能修正の 10-stage workflow を起動する (ブランチ確定→既存設計回収→pre-test→改修→TDD→レビュー→merge)
args: <slug>
related: [/test-design, /design-review, /start-task, /module-review, /system-review, /finish-task]
---

# /modify-feature — 既存機能修正 10-stage workflow オーケストレータ

既存機能の修正を **10 stage** で自動進行する workflow command。新規開発 (`/new-feature`) と異なり、要件定義 / detailed-design / task-creation の段が省略され、代わりに **recover-design** (既存設計回収) / **pre-test** (修正前 baseline) / **retest-design** (差分反映 test-design) が入る。

stage 名は `.claude/harness-config.yml` の `workflow_stages_modify` (`HC_WORKFLOW_STAGES_MODIFY`) と完全一致する 10 要素の配列。`workflow-guard.sh` が `.claude/.workflow-state/<slug>.json` の `current_stage` を参照して進行を検証する。

## 前提

- 修正対象機能の slug が既存 `docs/tasks/task-<id>-<slug>.md` または `docs/draft/<slug>.md` と紐付くこと
- 修正前の状態で **既存テストが全 PASS**(`pre-test` stage の baseline)
- `git status` がクリーン (uncommitted changes は事前に commit / stash)

## 使い方

```
/modify-feature <slug>
```

## 引数

- `<slug>` — kebab-case、既存 task / draft の slug と一致
  - validation: `^[a-z0-9][a-z0-9-]{2,48}$`(git-workflow.md branch 規約準拠)
  - path traversal 防止のため `.` `/` `..` を含む値は reject

## 動作

10 stage を順次進める。各 stage 完了で `.claude/.workflow-state/<slug>.json` の `current_stage` / `completed_stages` を更新。

### Stage 1: `branch-decision`

修正対象機能の影響範囲を特定し、修正ブランチ命名を決定する。

1. `git grep` / `Glob` で `<slug>` 関連ファイル (`src/**` `tests/**` `docs/**`) を抽出 → 影響範囲を user に提示
2. 修正の性質を判定して branch type を提案(git-workflow.md 規約準拠):
   - bug 修正 → `fix/<slug>`(または `fix/<slug>-<short-desc>`)
   - 内部構造改善 → `refactor/<slug>`
   - 機能追加(既存機能内) → `feat/<slug>`
   - hot fix → `hotfix/<slug>`
3. user に branch 名を提示し承認を得る(Loop モード時は AI 推奨を即採用)
4. State 初期化: `.claude/.workflow-state/<slug>.json` を `workflow_type=modify`, `current_stage=branch-decision` で生成 → 完了で `completed_stages` に追加

### Stage 2: `checkout`

決定した branch に切替える。

1. 既存 branch なら `git switch <branch>`、新規なら `git switch -c <branch>`
2. branch 命名 regex (`^(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)/[a-z0-9][a-z0-9-]{2,48}$`) を検証 → 不適合なら BLOCK
3. State 更新: `current_stage=checkout` → 完了で `completed_stages` 追加

### Stage 3: `recover-design`

既存設計を回収する。

1. **既存 task 探索**: `Glob` で `docs/tasks/task-*-<slug>.md` を検索 → 見つかったら Read で内容を取得
2. **既存 draft 探索**: `docs/draft/<slug>.md` を Read
3. **設計の充足度判定**:
   - 両方存在 + §1〜9 が埋まっている → 既存設計を採用、次 stage へ
   - draft なし or 不完全 → **reverse-engineer**: 該当コード (`src/**`) を Read して `_DRAFT_TEMPLATE.md` から新規 `docs/draft/<slug>.md` を起こす(現状実装を §3 詳細設計に転記)
4. **Skip ルール**: 既存設計が完備で diff が小さい(例: 単一関数の bug fix)場合、user 承認のうえ `recover-design` を `skip_log` に記録して短縮可
5. State 更新: `current_stage=recover-design` → 完了で `completed_stages` 追加

### Stage 4: `pre-test`

**修正前**の全テストを実行し green baseline を確認する。

1. `npm run test`(または stack に応じた test runner)を実行
2. **failing test があれば BLOCK**: 「修正前の test が既に fail。本 workflow 開始不可。先に別タスクとして該当 test を修正せよ」と user に提示し中断
3. baseline test 数 + PASS 数を State に記録(後の `full-test` stage との regression 比較用)
4. State 更新: `current_stage=pre-test` → 完了で `completed_stages` 追加

### Stage 5: `redesign`

`docs/draft/<slug>.md` に変更点を追記する(既存設計に diff を載せる)。

1. user から修正内容のヒアリング(または `/new-feature` 時の本タスクからの転記)
2. draft の §3 詳細設計に「変更前 / 変更後」の差分セクションを追記
3. 関連 §2 基本設計 / §6 リスク も影響があれば更新
4. State 更新: `current_stage=redesign` → 完了で `completed_stages` 追加

### Stage 6: `retest-design`

`/test-design <slug>` を再実行 (W1)。既存テスト + 修正部の新規テスト観点を MECE で出し直す。

1. 既存 `docs/draft/<slug>.test-design.md` があれば backup (`<slug>.test-design.md.bak`) して再生成
2. `/test-design <slug>` を起動 → tdd-guide / test-automator / qa-expert を並列 fan-out
3. 20 カテゴリの採用 / 不採用を user スコープ決定 (差分部のみ新規採用も可)
4. **Skip ルール**: 変更影響が `tests/` 内のみ(test refactor 等)で production code (`src/**`) 変更がない場合、user 承認 + `skip_log` 記録で skip 可
5. State 更新: `current_stage=retest-design` → 完了で `completed_stages` 追加

### Stage 7: `tdd`

TDD red-green-refactor。修正部の新規テストを **書いてから** 実装する。

1. retest-design で採用された新規 test を `tests/` に追加 (RED)
2. production code (`src/**`) を最小変更で修正 → 新規 test を PASS させる (GREEN)
3. リファクタリング (REFACTOR) — 既存挙動を変えない範囲で
4. モジュール単位の段階的 commit を推奨(Loop モード遵守事項 §5)
5. State 更新: `current_stage=tdd` → 完了で `completed_stages` 追加

### Stage 8: `module-review`

`/module-review <module>` を実行 (W3)。3 観点 (持続可能性 / 汎用性 / 非冗長化) レビュー。

1. 修正対象モジュールを引数に `/module-review` を起動
2. 並列 reviewer (code-reviewer + refactoring-specialist + 言語別 reviewer) fan-out
3. `pending_findings.module_review` に findings 配列を記録
4. **CRITICAL / HIGH findings が残っている間は次 stage 進行不可** (workflow-guard で block)
5. user が修正対応 → findings を resolve → 全テスト再 PASS
6. State 更新: `current_stage=module-review` → 完了で `completed_stages` 追加

### Stage 9: `full-test`

全テスト green 確認 (既存 regression なし + 新規 test pass)。

1. `npm run test` を全体実行
2. **regression 検出**: `pre-test` stage で記録した baseline PASS 数と比較。既存 test が新たに fail していたら BLOCK
3. 新規 test が全 PASS していることを確認
4. State 更新: `current_stage=full-test` → 完了で `completed_stages` 追加

### Stage 10: `system-review`

`/system-review` を実行 (W3)。マージ前最終整合性確認。

1. `/system-review` を起動 → architect-reviewer + code-reviewer + refactoring-specialist を並列 fan-out
2. モジュール間整合性 / 既存コードとの統合面の重複・乖離を検出
3. `pending_findings.system_review` に findings 配列を記録
4. **CRITICAL / HIGH findings が残っている間は merge 不可** (workflow-guard で block)
5. pass で merge 可 → user 確認のうえ `git push` → `/finish-task <id>` を案内
6. State 更新: `current_stage=system-review` → 完了で `completed_stages` 追加 → 全 stage 完了

## State 管理

- ファイル: `.claude/.workflow-state/<slug>.json`
- schema: `.claude/.workflow-state/SCHEMA.md`
- 主要フィールド:
  - `workflow_type`: `"modify"` 固定
  - `current_stage`: 現在進行中の stage 名 (上記 10 stage 名のいずれか)
  - `completed_stages`: 完了済 stage の配列 (順序保持)
  - `pending_findings.module_review` / `pending_findings.system_review`: 未解決 findings
  - `skip_log`: skip された stage の audit ログ (stage / reason / user_approved_at)
- 全 timestamp は ISO-8601 UTC 秒精度、`Z` suffix

## Skip ルール

| Stage | Skip 可否 | 条件 |
|---|---|---|
| `recover-design` | 短縮可 | 既存設計が完備 (`docs/draft/<slug>.md` §1〜9 充足) で diff が小さい (単一関数 bug fix 等)。user 承認 + `skip_log` 必須 |
| `retest-design` | skip 可 | 変更影響が `tests/` 内のみで production code (`src/**`) 変更なし。user 承認 + `skip_log` 必須 |
| 上記以外 | skip 不可 | branch-decision / checkout / pre-test / redesign / tdd / module-review / full-test / system-review は workflow-guard が block |

skip 時は必ず `skip_log` に `{stage, reason, user_approved_at}` を記録すること (`workflow-guard.sh` が grep 検証)。

## workflow-guard.sh との連携

- **PreToolUse(Bash) `/finish-task` 検知**: `workflow-guard.sh` は `/finish-task <id>` 実行直前に `.claude/.workflow-state/<slug>.json` を読み、以下を検証:
  - `current_stage == "system-review"` かつ全 stage が `completed_stages` に含まれること
  - `pending_findings.module_review` / `system_review` に CRITICAL / HIGH が **残っていない** こと
  - 未完了の必須 stage を skip している場合、`skip_log` に対応エントリと `user_approved_at` があること
- 違反時は BLOCK + 「先に stage N を完了せよ」(または「未対応 findings を解決せよ」) と提示
- bypass: `ECC_WORKFLOW_GUARD=off` (緊急時のみ)

## /new-feature との差分

| 観点 | `/new-feature` (14 stage) | `/modify-feature` (10 stage) |
|---|---|---|
| 要件定義 | あり (Step 1: requirements) | **なし** (既存機能のため省略) |
| 基本設計 | あり (Step 2: basic-design) | recover-design で既存を回収 |
| 詳細設計 | あり (Step 3: detailed-design) | redesign で diff を追記 |
| テスト設計 | test-design (Step 4) | retest-design (Stage 6) |
| design-review | あり (Step 5) | **なし** (既存設計の差分のみのため省略) |
| user-approval | あり (Step 6) | branch-decision の branch 承認に統合 |
| task-creation | あり (Step 7: /new-task) | **なし** (既存 task を流用) |
| TDD | あり (Step 8) | tdd (Stage 7) |
| module-review | あり (Step 9) | module-review (Stage 8) |
| local-test | あり (Step 10) | full-test (Stage 9) — pre-test baseline 比較あり |
| system-review | あり (Step 11) | system-review (Stage 10) |
| CI/CD | あり (Step 12) | **なし** (既存 pipeline 流用) |
| scenario-test | あり (Step 13) | **なし** (regression test で代替) |
| 完了 | finish (Step 14) | `/finish-task` で完了 |
| **追加 stage** | — | **branch-decision** / **checkout** / **recover-design** / **pre-test** / **retest-design** |

## 関連

- `/test-design <slug>` — Stage 6 retest-design で起動 (W1)
- `/design-review <slug>` — modify では Stage 5 redesign 内で必要に応じ起動 (W2)
- `/start-task <id>` — task 単位の branch 切替 (modify-feature の checkout と相補)
- `/module-review <module>` — Stage 8 で起動 (W3)
- `/system-review` — Stage 10 で起動 (W3)
- `/finish-task <id>` — 全 stage 完了後の最終クローズ (workflow-guard が state JSON を検証)
- state schema: `.claude/.workflow-state/SCHEMA.md`
- config: `.claude/harness-config.yml` の `workflow_stages_modify`
- 設計: `docs/draft/workflow-enforcement.md` §3 W4
