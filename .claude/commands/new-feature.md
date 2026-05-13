---
description: 新規機能開発の 14-stage workflow を起動する (要件→設計→テスト→TDD→レビュー→完了)
args: <slug>
related: [/test-design, /design-review, /new-task, /start-task, /module-review, /system-review, /finish-task]
---

# /new-feature — 新規機能開発 14-stage workflow オーケストレータ

新規機能開発の 14-stage workflow を起動する。要件定義から完了までを workflow-guard.sh が `.claude/.workflow-state/<slug>.json` を参照して強制する。

設計 draft v2 §3 W4 準拠。stage 名は `harness-config.yml` の `workflow_stages_new` (= env `HC_WORKFLOW_STAGES_NEW`) と完全一致。

## 使い方

```
/new-feature <slug>
```

## 引数

- `<slug>` — kebab-case の機能識別子
  - validation: `^[a-z0-9][a-z0-9-]{2,48}$` (git-workflow.md branch 規約準拠)
  - path traversal 防止: `.` `/` `..` を含む値は reject
  - 例: `loop-mode`, `proxy-rate-limit`, `link-card-componentize`

## 動作

このコマンドが呼ばれたら、メインエージェントは以下 14 stage を順次実行する。各 stage 完了時に `.claude/.workflow-state/<slug>.json` の `current_stage` と `completed_stages` を更新する。

### Stage 1: `requirements` — 要件定義

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- user との対話で WHAT (何を作るか) / WHY (なぜ作るか) を確定
- `/new-draft <slug>` を起動して `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から生成
- draft §1 (真因サマリ / 課題サマリ) を埋める
- 完了条件: §1 が user 確認済み
- 完了したら state JSON `current_stage` を `basic-design` に進め、`completed_stages` に `requirements` を追加

### Stage 2: `basic-design` — 基本設計

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- draft §2 (解決アプローチ比較) を埋める
- 複数案 (最小 2 案) + 工数 + メリット/デメリット表
- Wave 分割の方針を user に提示
- 完了条件: 採用案が user 承認済み
- 完了したら state JSON を更新し `detailed-design` に進む

### Stage 3: `detailed-design` — 詳細設計

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- draft §3 (採用案の詳細設計 / Wave / Sub-task 分割) を埋める
- API endpoint / データモデル / UI コンポーネント / DB schema を具体化
- 影響範囲を明示 (ファイル path レベル)
- 完了条件: §3 が user 確認済み
- 完了したら state JSON を更新し `test-design` に進む

### Stage 4: `test-design` — テスト設計 (W1)

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/test-design <slug>` を実行
- MECE 20 カテゴリ表が `docs/draft/<slug>.test-design.md` に生成される
- 採用/不採用を user が全行確認 (不採用には必ず理由)
- 完了条件: 全 20 行が ☑/☒ で確定 + user スコープ承認済み
- 完了したら state JSON を更新し `design-review` に進む

### Stage 5: `design-review` — 設計レビュー fan-out (W2)

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/design-review <slug>` を実行
- `reviewer_registry_design` + `reviewer_registry_security` カテゴリの全 agent を **並列 fan-out** (`run_in_background: true` 必須)
- 各 agent からの findings を `docs/draft/<slug>-review.md` に集約
- TaskCreate で全 subagent を登録 (subagent_id を metadata 記録)
- 完了条件: CRITICAL/HIGH 件数 0 件、もしくは draft 修正後再 review で 0 件
- 完了したら state JSON を更新し `user-approval` に進む

### Stage 6: `user-approval` — user 承認

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- user に draft 承認依頼 (review 集約結果を提示)
- 承認履歴を `docs/draft/<slug>.md` §8 に記録 (日付 + 承認者 + 結果)
- 完了条件: §8 に「承認」エントリが追加された
- 完了したら state JSON を更新し `task-creation` に進む

### Stage 7: `task-creation` — タスク化

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/new-task <id> <slug>` を実行
- `_TASK_TEMPLATE.md` から `docs/tasks/task-<id>-<slug>.md` 生成
- `docs/tasks/list.md` に `🔲 未着手` 行追加
- **`.claude/.workflow-state/<slug>.json` を初期化** (`workflow_type=new`, `current_stage=task-creation`, `completed_stages` は Stage 1〜6 を列挙, `pending_findings={module_review:[],system_review:[]}`, `skip_log=[]`, `created_at` `updated_at`)
- 完了条件: state JSON が作成され、task ファイル + list.md 行が存在
- 完了したら state JSON を更新し `tdd` に進む

### Stage 8: `tdd` — TDD 実装

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/start-task <id>` で着手 (branch 切替 + status 同期)
- RED: 採用テスト (Stage 4 で確定) を `tests/` に追加し、FAIL を確認
- GREEN: 最小実装で PASS させる
- REFACTOR: behavior-preserving で整理
- **テスト経由でしか実装しない** (テスト先行を厳守)
- 実装は subagent 経由 (メインは `src/` `tests/` 直接編集禁止)
- 完了条件: モジュール毎の単体テストが全 PASS
- 完了したら state JSON を更新し `module-review` に進む

### Stage 9: `module-review` — モジュール単位レビュー (W3)

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- 変更があった各モジュールについて `/module-review <module>` を実行
- refactoring-specialist + code-reviewer + 言語別 reviewer を並列起動
- 3 観点 (持続可能性 / 汎用性 / 非冗長化) で findings 収集
- 検出された findings を state JSON の `pending_findings.module_review` 配列に追加 (id / severity / summary)
- CRITICAL/HIGH を修正 (subagent 経由) し、対応済 finding を `pending_findings.module_review` から除去
- 完了条件: `pending_findings.module_review` が空、または残存は MEDIUM/LOW のみ + user 承認済
- 完了したら state JSON を更新し `local-test` に進む

### Stage 10: `local-test` — ローカル全テスト green

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- 採用テスト全カテゴリを実行 (subagent 経由)
- 単体 / 統合 / E2E / smoke 等、`<slug>.test-design.md` で ☑ にしたもの全て
- 完了条件: 全 PASS
- FAIL 時は Stage 8 (tdd) に戻る (state JSON `current_stage` を `tdd` に戻し、`completed_stages` からは除去しない=再実行扱い)
- 完了したら state JSON を更新し `system-review` に進む

### Stage 11: `system-review` — 全体統合レビュー (W3)

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/system-review --slug <slug>` を実行
- architect-reviewer + refactoring-specialist + code-reviewer を並列起動
- モジュール間重複 / 横断的責務漏れ / 設計乖離 を検出
- findings を state JSON の `pending_findings.system_review` 配列に追加
- CRITICAL/HIGH を修正、対応済を pending から除去
- 完了条件: `pending_findings.system_review` が空、または残存は MEDIUM/LOW のみ + user 承認済
- 完了したら state JSON を更新し `ci-cd` に進む

### Stage 12: `ci-cd` — CI/CD 適用 (skippable)

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `.github/workflows/` 等の CI/CD 設定を更新 (必要時のみ)
- **skip 可能 stage**: `.claude/mode.yml` の `asana_enabled: false` プロジェクトでは default skip 推奨
- skip する場合: state JSON `skip_log` 配列に `{stage:"ci-cd", reason:"<skip 理由>", user_approved_at:"<ISO-8601 UTC>"}` を追加
- 完了条件: CI/CD 適用済 OR skip ログ記録済
- 完了したら state JSON を更新し `scenario-test` に進む

### Stage 13: `scenario-test` — シナリオテスト

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- user 主導でシナリオを実行、または `e2e-runner` agent を起動 (`run_in_background: true`)
- `<slug>.test-design.md` で ☑ にしたシナリオテスト / E2E を全て実施
- 完了条件: 全シナリオ PASS
- FAIL 時は該当 stage (tdd / module-review) に戻る (state JSON の `current_stage` を巻き戻し)
- 完了したら state JSON を更新し `finish` に進む

### Stage 14: `finish` — 完了

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください:

- `/finish-task <id>` を実行
- **workflow-guard.sh** が PreToolUse(Bash) で `/finish-task` 起動を検知し、state JSON を検証:
  - 14 stage 全てが `completed_stages` に含まれているか
  - `pending_findings.module_review` `pending_findings.system_review` が空 (または MEDIUM/LOW のみ + skip_log 記載)
  - 不足があれば BLOCK + 「Stage X が未完了」「pending finding ID-YYY が未対応」と提示
- 検証 PASS で `/finish-task` が継続:
  - `docs/tasks/list.md` の該当行を `done` 化
  - commit + push (CLAUDE.md "Autonomous Progression" 準拠)
- 完了報告フォーマット:
  ```
  #<id> <タスク名> 完了。
  14-stage workflow 通過、累計 +<N> tests、commit <count>、push 済 <URL>。
  ```

## State 管理

`.claude/.workflow-state/<slug>.json` を SSoT として各 stage 完了時に以下を更新:

- `current_stage` — 次に進む stage 名 (`HC_WORKFLOW_STAGES_NEW` の値と一致)
- `completed_stages` — 完了済 stage 名の配列 (順序保持)
- `pending_findings` — module-review / system-review で発生した未解決 findings
- `skip_log` — skip された stage の audit ログ
- `updated_at` — ISO-8601 UTC

schema 詳細: [`.claude/.workflow-state/SCHEMA.md`](../.workflow-state/SCHEMA.md)

state JSON が存在しない場合、Stage 7 (`task-creation`) で初期化する。Stage 1〜6 は state JSON 作成前なので、メインは内部で stage 進行を追跡し、Stage 7 到達時に `completed_stages` に 1〜6 を列挙する。

## Skip ルール

| Stage | skippable | default |
|---|:---:|---|
| `requirements` | × | 必須 |
| `basic-design` | × | 必須 |
| `detailed-design` | × | 必須 |
| `test-design` | × | 必須 |
| `design-review` | × | 必須 |
| `user-approval` | × | 必須 |
| `task-creation` | × | 必須 |
| `tdd` | × | 必須 |
| `module-review` | × | 必須 |
| `local-test` | × | 必須 |
| `system-review` | × | 必須 |
| `ci-cd` | ○ | `asana_enabled=false` で default skip |
| `scenario-test` | △ | user 明示承認時のみ skip 可 |
| `finish` | × | 必須 |

skip する場合は state JSON `skip_log` に必ず以下を記録:

```json
{
  "stage": "<stage-name>",
  "reason": "<user が提示した skip 理由>",
  "user_approved_at": "<ISO-8601 UTC 秒精度 Z suffix>"
}
```

`ci-cd` 以外を skip する際は **user 明示承認必須**。承認なしで skip した場合は workflow-guard.sh が Stage 14 (`finish`) で BLOCK する。

## workflow-guard.sh との連携

`/finish-task` 起動時、`workflow-guard.sh` が PreToolUse(Bash) hook で発火し、state JSON を検証:

1. `.claude/.workflow-state/<slug>.json` を読む (slug は branch 名 / task ファイル / `docs/work.md` から解決)
2. `completed_stages` が `HC_WORKFLOW_STAGES_NEW` の 14 stage 全てを含むか確認
3. `pending_findings.module_review` と `pending_findings.system_review` を確認:
   - CRITICAL/HIGH が残っていれば BLOCK
   - MEDIUM/LOW のみ残存 + `skip_log` に該当 finding の skip 理由あり → 通過
4. skip された stage は `skip_log` エントリが存在することを確認 (`reason` + `user_approved_at` 両必須)
5. 検証失敗時は stderr に「Stage X 未完了 / Finding ID-YYY 未対応 / skip_log エントリ不足」を出力して exit 2 (BLOCK)
6. 検証 PASS で `/finish-task` が継続

bypass: `ECC_WORKFLOW_GUARD=off` (緊急用、`bypass.log` に audit 記録される)

## 制約

- 各 stage は順序固定。前 stage 未完了で次に進むと workflow-guard.sh が BLOCK
- subagent 起動は **必ず** `run_in_background: true` + TaskCreate (CLAUDE.md §1 §4)
- `<slug>` validation 違反は即 reject (path traversal 防止)
- state JSON 更新は subagent でも main でも可だが、整合性責任は main にある (CLAUDE.md §2 順序整合性)
- bypass env (`ECC_WORKFLOW_GUARD=off`) は緊急時のみ、`bypass.log` で audit

## Loop モード時の特例

- 各 stage 間で「進めてもよいですか?」を聞かない (Loop モード「中間確認の停止」原則)
- Why × 5 評価で推奨を即採用
- ただし `user-approval` (Stage 6) は本質的に user 承認が必要なので確認する (Loop モードでも例外)
- `pending_findings` の CRITICAL/HIGH 修正は自動適用 (subagent 経由、behavior-preserving)

## 関連

- `/test-design <slug>` — Stage 4 (W1)
- `/design-review <slug>` — Stage 5 (W2)
- `/new-task <id> <slug>` — Stage 7
- `/start-task <id>` — Stage 8 着手
- `/module-review <module>` — Stage 9 (W3)
- `/system-review` — Stage 11 (W3)
- `/finish-task <id>` — Stage 14
- config: `.claude/harness-config.yml` の `workflow_stages_new` (= env `HC_WORKFLOW_STAGES_NEW`)
- state schema: [`.claude/.workflow-state/SCHEMA.md`](../.workflow-state/SCHEMA.md)
- template: `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` (frontmatter 拡張済)
- hook: `.claude/hooks/workflow-guard.sh` (W4-guard で実装予定)
- 設計 draft: [`docs/draft/workflow-enforcement.md`](../../docs/draft/workflow-enforcement.md) §3 W4
- 既存 modify workflow: `/modify-feature <slug>` (10-stage、別 command)
