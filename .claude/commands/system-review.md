---
description: 全モジュール統合後の全体レビュー + リファクタリング (モジュール間重複 / 横断的責務 / 設計乖離検出)
---

# /system-review — 全体レビュー & リファクタリング

`/new-feature` Step 11 / `/modify-feature` Step 9 で呼ばれる。複数モジュール統合後に全体的なレビューを実行し、**モジュール間重複 / 横断的責務漏れ / 設計乖離** を検出。`reviewer_registry_impl` + `architect-reviewer` を並列起動し、`/module-review` では拾えない system 全体の問題を捕捉。

## 前提

- 全モジュールの `/module-review` が完了し、CRITICAL/HIGH 0 件
- 全テストが PASS (`/test-design` で採用したテストカテゴリすべて)
- 該当タスクファイル `docs/tasks/task-<id>-<slug>.md` の全モジュール Wave が ✅ 完了

## 使い方

```
/system-review                          # 既定: 現在進行中タスクの全モジュール
/system-review --since <commit>         # 比較開始 commit 明示
/system-review --slug <slug>            # タスク slug を明示
/system-review --skip-refactor          # findings 検出のみ
/system-review --max-reviewers 5        # cost 制御
```

## 引数

- `--slug <slug>` — タスク slug (省略時は `docs/work.md` または最後の `start-task` から推定)
- `--since <commit>` — 比較開始 commit (省略時はタスク開始時点)
- `--skip-refactor` — 修正コード提案を skip

## 動作

### Phase 1: 前提チェック

1. 現タスク slug を解決 (`<slug>` 引数 or `docs/work.md` or branch 名)
2. `docs/tasks/task-<id>-<slug>.md` を読み、全 Wave が ✅ 完了であることを確認
3. 全採用テストが直近 PASS 済みであること (`/finish-task` の build/test 検証と同等)

### Phase 2: スコープ抽出 + 全体構造把握

1. `git diff --stat <since>..HEAD` で変更ファイル一覧
2. ファイル群から「モジュール境界」を推定 (ディレクトリ / 言語別 / sub-system 別)
3. 該当 draft (`docs/draft/<slug>.md`) を読み、想定設計との乖離を比較対象に設定

### Phase 3: 並列 Agent fan-out (system-level scope)

1. `harness-config.yml` の `reviewer_registry_impl` + `architect-reviewer` を起動:
   - **code-reviewer** — 全変更コードの一貫性
   - **refactoring-specialist** — モジュール間重複 / 共通化候補
   - **architect-reviewer** — 設計 draft との乖離 / アーキ整合性
2. 各 agent 起動前に **TaskCreate** + **Agent tool** (`run_in_background: true` 必須)
3. 共通 prompt 規約:

```
入力:
- 対象 slug: <slug>
- 全変更 diff: <git diff の本文>
- 設計 draft: docs/draft/<slug>.md
- module-review 集約結果: docs/draft/<slug>-module-review-*.md (複数)

レビュー観点 (system-level):

1. **モジュール間重複 (Cross-module Duplication)**:
   - 同一ロジックが複数モジュールに散在していないか
   - module-review では module 内 DRY のみ、本 review は module 横断 DRY

2. **横断的責務漏れ (Missing Cross-cutting Concerns)**:
   - logging / error handling / observability が module 間で一貫しているか
   - rate limiting / retry / circuit-breaker パターンが必要箇所に適用されているか
   - secret 管理 / authn / authz が module 境界で正しく扱われているか

3. **設計乖離 (Design Drift)**:
   - 採用案 (`docs/draft/<slug>.md` §3) からの逸脱がないか
   - 「採用しない」テスト (`<slug>.test-design.md` の ☒) が実装されていないか (逆方向の drift)
   - DoD (§6) が全項目満たされているか

4. **持続可能性 / 汎用性 / 非冗長化** (`/module-review` の 3 観点を system-level で再評価):
   - 個別 module は OK だが組み合わせで持続可能性が崩れる箇所
   - 全体として汎用性が低い (specific use case に縛られすぎ)

出力 format:
- 4 観点ごとに findings (CRITICAL / HIGH / MED / LOW)
- 各 finding に「該当箇所 / 問題 / 修正提案 (差分 + 影響範囲)」
- behavior-preserving 必須 (public API / DB schema 変更禁止)
- 末尾に `confidence: 0.X` 必須
```

### Phase 4: 集約 + 修正案提示

1. 全 agent 完了通知後、findings を `docs/draft/<slug>-system-review.md` に集約
2. CRITICAL/HIGH を blocking findings として表示
3. `--skip-refactor` 未指定時は、修正案を user 承認後に適用

### Phase 5: 修正適用 + 全テスト再 PASS

1. 承認修正を適用 (subagent 経由)
2. **全テスト再実行** (採用カテゴリすべて、smoke + e2e 含む)
3. 全 PASS なら Wave 進捗を「シナリオテスト」(`/new-feature` Step 13) または「マージ」(`/modify-feature` Step 10) に進める
4. FAIL なら修正取り消し + user 確認

## 制約

- behavior-preserving 必須
- 全テスト再 PASS が完了条件 (1 件でも FAIL なら次 step 進めない)
- workflow-guard.sh は本 step skip した `/finish-task` を block
- skip する場合は `docs/work.md` に skip 理由必須記載
- bypass: `ECC_SYSTEM_REVIEW_OFF=1` (推奨せず、hot fix 用)

## 関連

- `/module-review <module>` — モジュール単位レビュー (本 command の前段)
- `/finish-task` — タスク完了 (本 command 後)
- `/design-review <slug>` — 設計レビュー (実装前)
- config: `.claude/harness-config.yml` の `reviewer_registry_impl`
- 設計 draft: `docs/draft/workflow-enforcement.md` §3 W3
