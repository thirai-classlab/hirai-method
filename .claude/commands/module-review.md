---
description: TDD 完了直後のモジュール単位レビュー + リファクタリング (持続可能性 / 汎用性 / 非冗長化 の 3 観点)
---

# /module-review — モジュール単位レビュー & リファクタリング

`/new-feature` Step 9 / `/modify-feature` Step 7 で呼ばれる。指定モジュール (ファイル / ディレクトリ) の TDD 完了直後に、`reviewer_registry_impl` カテゴリの agent を並列起動し、**持続可能性 / 汎用性 / 非冗長化** の 3 観点で findings を集約 + 修正提案。

## 前提

- 対象モジュールの TDD (Red/Green/Refactor) が完了し、テストが全 PASS
- 該当タスクファイル `docs/tasks/task-<id>-<slug>.md` が存在 (workflow 進行中の文脈確認)
- 直前の commit ハッシュが取得できる (`git log -1 --format=%H`)

## 使い方

```
/module-review <module>                       # 既定: code-reviewer + refactoring-specialist + 言語別 reviewer
/module-review <module> --since <commit>      # 比較対象の commit を明示
/module-review <module> --skip-refactor       # findings 検出のみ、修正提案を生成しない
/module-review <module> --max-reviewers 3     # cost 制御
```

## 引数

- `<module>` — ファイル path または ディレクトリ path (validation: `src/` `tests/` `.claude/` 配下のみ)
- `--since <commit>` — 比較開始 commit (省略時は直前 commit)
- `--skip-refactor` — 修正コード提案を skip (検出 only)

## 動作

### Phase 0: yml 参照 (task-45 Phase 2、reviewer 制御 yml 経由化)

本 command 開始前に `harness-config.yml` から以下 4 値を参照 (env > yml > default、`config-loader.sh` 仕様):

| 環境変数 | yml key | default | 用途 |
|---|---|---:|---|
| `HC_REVIEW_REQUIRED_MODULE` | `review_required_module` | `true` | `false` なら本 command を **no-op skip** (理由付きでユーザに報告 + 終了、`/new-feature` Step 9 / `/modify-feature` Step 7 で skip 可) |
| `HC_REVIEW_MIN_COUNT_MODULE` | `review_min_count_module` | `2` | reviewer 最低数 (default 2 = code-reviewer + refactoring-specialist) |
| `HC_REVIEW_MAX_COUNT_MODULE` | `review_max_count_module` | `5` | reviewer 上限 (`--max-reviewers` 未指定時の default) |
| `HC_REVIEW_ITERATION_MAX` | `review_iteration_max` | `5` | findings 修正後の反復ループ上限 |

`HC_REVIEW_REQUIRED_MODULE=false` で skip した場合は、bypass.log に記録し、ユーザに「review_required_module=false のため /module-review を skip した、Phase 1 以降を実行しない」と明示。

### Phase 1: 前提チェック

1. `<module>` が valid な path か (`^[a-zA-Z0-9_./-]+$`)、`..` 含まないこと
2. `git diff --stat <since>..HEAD -- <module>` で diff が存在するか
3. `docs/tasks/task-<id>-<slug>.md` (現在進行中タスク) が存在し、Wave 進捗が「実装 (TDD) 完了」状態か

### Phase 2: 対象抽出 + stack 推定

1. `git diff <since>..HEAD -- <module>` で変更コード + 関連 test を抽出
2. 言語推定 (`.ts` `.py` `.go` `.rs` 等の拡張子 + `package.json` / `pyproject.toml` 検出)
3. `harness-config.yml` の `reviewer_registry_impl` から起動 reviewer を選定:
   - **code-reviewer** — 常時起動
   - **refactoring-specialist** — 常時起動 (本 command の中核)
   - 言語別 reviewer (typescript-reviewer / python-reviewer / go-reviewer 等) — stack 適合時のみ

### Phase 3: 並列 Agent fan-out

1. 選定 reviewer ごとに **TaskCreate** + **Agent tool 起動** (`run_in_background: true` 必須)
2. 共通 prompt 規約 (refactoring-specialist 中心):

```
入力:
- 対象モジュール: <module>
- 変更 diff: <git diff の本文>
- 関連 test: <tests/... の本文>

レビュー観点 (3 観点必須):

1. **持続可能性 (Sustainability)**:
   - (a) 命名が意図を表しているか
   - (b) 関数 50 行以内・ファイル 800 行以内
   - (c) ネスト 4 階層以内
   - (d) magic number 排除
   - (e) 副作用が局所化
   - (f) 型注釈・docstring が将来の読み手に必要十分
   - (g) error path が silent failure になっていない

2. **汎用性 (Generality)**:
   - (a) 引数で挙動を切替可能か
   - (b) 1 callee に特化したコードでないか
   - (c) 言語/framework idiom に従っているか
   - (d) interface が抽象に依存し具象に縛られていないか
   - (e) test seam が存在するか

3. **非冗長化 (Deduplication)**:
   - (a) 同一ロジックの複製がないか (DRY)
   - (b) 似た条件分岐の table-driven 化候補
   - (c) 既存 util/helper の再発明をしていないか
   - (d) 既存型・既存 schema を流用できる箇所
   - (e) 不要な抽象 (over-engineering) を作っていないか (YAGNI)

4. **プロジェクト整合性 + 他 task 影響確認 (項目 5、`workflow.md` §reviewer prompt 共通規約 準拠、2026-05-28 追加)**:
   - (a) `docs/tasks/list.md` を Read、本 module 変更が他 task (🔄 進行中 / 🔲 未着手 / 📝 計画中) と重複 / 競合 / 前提崩壊しないか
   - (b) 本対象の依存先 task.md + draft.md を Read、影響範囲を把握
   - (c) `docs/tasks/next-actions.md` の未処理 🔴 / 🟡 entry を確認、本 module 変更で解決 / 関連する entry を特定
   - (d) `.claude/rules/*.md` (Layer A 全 7 file) を Read、本 module 変更が既存規範と矛盾していないか / 規範更新が必要か
   - (e) `README.md` / `docs/INVENTORY.md` を Read、本 module 変更が project SSoT を破壊していないか
   - (f) `.claude/hooks/` `.claude/commands/` `.claude/skills/` を Glob/Grep、類似機能が既存なら本変更との関係を findings に明記 (再発明回避)

出力 format:
- 4 観点ごとに findings (CRITICAL / HIGH / MED / LOW)
- 各 finding に「該当ファイル:行 / 問題 / 修正コード提案 (具体 diff)」
- 項目 4 (プロジェクト整合性) の findings には「他 task #N との重複」「既存 rule §X と矛盾」「副産物 entry #Y を解決可能」「既存 hook/command/skill 再利用可」「SSoT 矛盾」のいずれかを該当時に明示
- behavior-preserving 原則必須 (public API / DB schema 変更禁止)
- 全 finding に対応 → modified diff を提示
- 末尾に `confidence: 0.X` 必須
- bypass: `HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` (typo 1 行 / comment-only refactor 等の cost 過大ケースのみ、`.claude/rules/` 編集を含む change では NG)
```

### Phase 4: 集約 + 修正案提示

1. 全 agent 完了通知後、findings を `docs/draft/<slug>-module-review-<module-slug>.md` に集約
2. CRITICAL/HIGH を blocking findings として表示
3. `--skip-refactor` 未指定時は、refactoring-specialist の修正案を user に提示し承認後に適用

### Phase 5: 修正適用 + テスト再 PASS 確認

1. 承認された修正をモジュールに適用 (subagent 経由、main は直接編集禁止)
2. 該当モジュールのテスト再実行
3. 全 PASS なら Wave 進捗を「ローカルテスト」に進める
4. FAIL なら修正取り消し + user 確認

## 制約

- behavior-preserving 必須 (public API / DB schema 変更不可)
- workflow-guard.sh (W4 実装後) はこの step を skip した `/finish-task` を block
- skip する場合は `docs/work.md` 時系列ログに skip 理由 + user 承認時刻記載必須
- bypass: `ECC_MODULE_REVIEW_OFF=1` (推奨せず、hot fix 用)

## 関連

- `/system-review` — 全体統合レビュー (本 command の後段)
- `/design-review` — 設計レビュー (本 command の前段)
- `/finish-task` — タスク完了 (本 command 後)
- config: `.claude/harness-config.yml` の `reviewer_registry_impl`
- 設計 draft: `docs/draft/workflow-enforcement.md` §3 W3
