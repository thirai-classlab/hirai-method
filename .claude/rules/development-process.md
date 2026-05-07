---
paths:
  - "src/**/*"
  - "scripts/**/*"
  - "tests/**/*"
  - "docs/tasks/**/*"
  - "docs/draft/**/*"
---

# 開発プロセスルール

## TDD（テスト駆動開発）

すべての実装はTDDで進める。

1. テスト専門エージェント（`/sc:test`）にテスト観点・テストパターンを洗い出させる
2. テストを設計・実装する（Red: テストが失敗する状態）
3. プロダクションコードを実装してテストを通す（Green）
4. リファクタリング（Refactor）

テストなしでプロダクションコードを書かない。

## サブエージェント委譲（Hook で強制）

メインエージェントは `src/` `tests/` `scripts/` に対する**一切の直接操作を禁止**する。
読み取り（Read/Grep/Glob）・編集（Edit/Write）の両方が Hook でブロックされる。

**メインエージェントの役割（これだけ）:**
- **タスク管理（メイン専任・必須）**: docs/tasks/ の更新、進捗追跡、ステータス変更。サブエージェントにタスク管理を委譲してはならない
- 作業のアサイン（Agent tool でサブエージェントを起動）
- 完了報告・成果物の確認
- docs/, CLAUDE.md, .claude/ など管理ファイルの更新

**メインエージェントが直接使えるツール:**
- `Skill` — 全対象（メインで直接実行可能）
- `mcp__*` — 全対象（メインで直接実行可能）
- docs/, CLAUDE.md, .claude/ の Read/Edit/Write

**サブエージェントに委譲する作業（すべて Agent tool 経由）:**
- コード調査・読み取り → `Agent(subagent_type=Explore)`
- テスト設計 → Agent 内で `/sc:test`
- コード実装 → `Agent(general-purpose)` or `Agent(isolation=worktree)`
- ビルド確認 → Agent 内で `/sc:build`
- Web 調査 → Agent 内で WebSearch/WebFetch
- プログラム実行（Bash） → Agent 内で実行
- 独立したタスクは並列で複数サブエージェントを同時起動すること

**Hook で強制ブロックされるツール（メイン直接使用禁止）:**
- `Edit` / `Write` — src/ tests/ scripts/ 対象
- `Read` / `Grep` / `Glob` — src/ tests/ scripts/ 対象
- `WebSearch` / `WebFetch` — 全対象
- `Bash` — **原則禁止**。`.claude/bash-whitelist.txt` に登録された prefix のみ許可（既定: git/npm run/pnpm/yarn/vercel/supabase/gh/ls/pwd/date/echo/.claude 配下の cat 等）。これらでも src/ tests/ scripts/ パスを直接 inspect する形（例: `cat src/foo.ts`）は別途ブロック

**Bash 制御の SSoT は `.claude/bash-whitelist.txt`:**

- `settings.json` / `settings.local.json` の `permissions.allow` に `Bash(...)` を**重複追加しない**（permission モデル分裂の防止）
- Bash 追加は whitelist への 1 行追記のみで完結
- `permissions.deny` での Bash 禁止（`rm -rf`, `git push --force` 等）は別系統で保持

**Bash ホワイトリスト追加申請（ハーネス構造・品質・工数削減・作業困難の解消に資する場合のみ）:**

1. `.claude/bash-whitelist-requests/YYYY-MM-DD-<slug>.md` を `REQUEST_TEMPLATE.md` に従って作成（パターン / 実行例 / 必要理由 / 副作用）
2. user がレビューし `.claude/bash-whitelist.txt` に 1 行追記
3. その時点から有効

**Hook バイパスは禁止:**
- `CLAUDE_HARNESS_ROLE=` のような inline 環境変数による Hook バイパスは `delegation-guard.sh` が検出してブロック

## サブエージェント委譲の必須要件（背景起動 + 順序整合性）

メインエージェントは Agent tool 起動時、以下 3 点を必須とする。

### 1. バックグラウンド起動の強制（`run_in_background: true`）

メインエージェントは Agent tool 起動時、**`run_in_background: true` を必須**とする。

- **例外**: 30 秒以内に完了する smoke test / dry-run のみ
- **理由**: メインがサブエージェントの完了を待つ間、ユーザーが新規指示を出せない（UX 劣化）。長時間タスクの進捗確認・追加指示・割り込みを常に受け付けるためにメインを解放しておく
- **違反例**: foreground 起動でメインがブロックされ、ユーザーが「進捗確認」さえ困難
- **運用**: 完了通知は SubagentStop hook 経由でメインに届くため、ポーリング不要

### 2. タスク順序整合性の保証（メイン専任）

メインエージェントは複数サブエージェント間の **タスク順序整合性** を保証する責務を持つ。

- **依存関係解決**: タスク A の出力をタスク B が消費する場合、A の完了通知を受けてから B を起動。サブエージェントに依存解決を委譲してはならない
- **並行可能性判定**: 独立ファイル領域 / 独立ブランチ / 独立 cost セッションのタスクは並行起動 OK。重なる場合は逐次化
- **partial commit 整合性**: 各サブエージェントの commit が conflict しないことをメインが事前判定（同一ファイル編集の重複起動を防ぐ）
- **完了通知 → 次タスク**: メインが完了通知を受けたら、次のタスク起動 / user 判断要請 / 中断のいずれかをメイン責任で決定

### 3. メインの orchestration 義務

- Agent tool 起動は **委譲ガード経由のみ**（既存ルール）
- 独立タスクは並列、依存タスクは逐次。これをメインが事前計画して user に開示
- TaskCreate / TaskUpdate（または `docs/tasks/list.md`）で依存関係をトラッキング
- サブエージェント完了通知後の判断（go/no-go / 次タスク起動 / user 判断要請）はメインの責務であり、サブエージェントに委譲してはならない

### 4. サブエージェント起動の Task 登録（必須）

メインエージェントは Agent tool でサブエージェントを起動する **前** または **直後** に、
**必ず TaskCreate** で Claude Code 内蔵タスクリストに登録する。

#### 必須項目
- **subject**: サブエージェントに振り出した作業の概要（例: 「config-loader env override 汎用化」）
- **description**: 委譲スコープ / 完了条件 / 想定 cost / 並行可否
- **metadata.subagent_id**: Agent tool 起動時に得られる `agentId`（追跡可能性）
- **status 遷移**: `pending` → `in_progress`（起動直後）→ `completed`（完了通知受信時）

#### 依存関係の明示
- 並行可能なタスクは独立に作成（依存なし）
- 逐次タスクは `addBlockedBy` / `addBlocks` で依存関係を明示
- メインは TaskList でいつでも全状態を確認可能にする

#### 違反例
- TaskCreate せずに subagent 起動 → ユーザーが何が走っているか不明、進捗確認不可
- 完了通知を受けたのに TaskUpdate で `completed` にしない → 古いタスクが残留
- subagent_id を metadata に記録しない → 後追いトレース不能

#### 理由
- **可観測性**: ユーザーが `TaskList` でいつでも進捗を確認できる
- **責任の明確化**: メインの orchestration 義務（§3）を Claude Code 標準機構に裏付ける
- **再開性**: セッション再起動時もタスクリストから現状を復元可能

### Hook による補助（soft warning）

`.claude/hooks/agent-marker-set.sh` は PreToolUse(Agent) で foreground 起動を検出した場合、stderr に WARN を出す（block ではない）。`tool_input.run_in_background != true` のときに発火。

## サブエージェント完了サマリ（Confidence Gate / F3 必須）

サブエージェントが返す **最後の assistant text** には **必ず `confidence: 0.X`**（0.0〜1.0）を含める。
SubagentStop hook (`.claude/hooks/confidence-gate.sh`) が抽出し、閾値（既定 0.6）未満は **block** する。

### 算出基準（4 段階）

| レンジ | 状態 |
|---|---|
| 0.9 - 1.0 | 全条件を実測値で確認（build / test / grep の生 log 引用可） |
| 0.7 - 0.8 | 主要条件は確認、周辺は推定（一部 grep 未実行など） |
| 0.5 - 0.6 | 実装は完了したが検証が浅い、あるいは未確認の前提に依存 |
| 0.0 - 0.4 | 方針が不明確、あるいは曖昧な仮実装 |

### 完了宣言の最低ライン

- **0.6 以上**: そのまま `/finish-task` へ進める
- **0.6 未満**: ゲートが block する。検証を追加して再評価するか、未解決事項を箇条書きで明示し user 判断を仰ぐ
- **未記載**: `confidence_required: true`（既定）下では block

### 記載例

```text
F3 confidence-gate.sh を実装し以下を確認:
- 6 ケースの mock transcript で期待動作を確認（pass/block/env override/bypass）
- harness-audit に新セクション追加、bypass.log を集計
- settings.json の SubagentStop に wired

confidence: 0.9
```

### Bypass

詳細は [`docs/CONFIDENCE-GATE.md`](../../docs/CONFIDENCE-GATE.md):

| 方法 | スコープ | 痕跡 |
|---|---|---|
| `ECC_CONFIDENCE_GATE=off` | セッション全体 | env のみ |
| `HC_CONFIDENCE_REQUIRED=false` | セッション全体（config 同等） | env のみ |
| `/gate-bypass confidence <reason>` | 次回 1 回のみ（再 arm） | `.claude/.confidence-gate-state/bypass.log` |

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリに記録すること。

## 指摘対応

指摘やエラーを受けた場合は必ず:

1. 根本原因を特定する
2. 修正する
3. 再発防止策を考える
4. `.claude/rules/` へのルール追加を提案する

## タスク管理（メイン専任）

タスク管理はメインエージェントのみが行う。サブエージェントにタスク管理を委譲してはならない。

- `docs/tasks/list.md` のステータス更新 → メインが必ず実行
- 個別タスクファイルの作成・更新 → メインが必ず実行
- サブエージェント起動前にタスクを「進行中」に、完了後に「完了」に更新

## 設計→承認→タスク追加フロー（必須）

**設計なしのタスク追加は禁止**。下記 4 ステップを厳守:

1. **テンプレ初期化**（初回のみ・自動）: SessionStart hook で `docs/tasks/list.md` `parking-lot.md` `_TASK_TEMPLATE.md` および `docs/draft/_DRAFT_TEMPLATE.md` がテンプレートから自動生成される。明示実行は `/init-tasks`
2. **設計起こし**: `/new-draft <slug>` で `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から生成 → §1〜9 を埋める
3. **承認依頼**: ユーザーにレビュー・承認を依頼。承認履歴を draft の §8 に記録
4. **タスク化**: 承認後に `/new-task <id> <slug>` を実行 — 以下が **同時に** 行われる:
   - `docs/tasks/task-<id>-<slug>.md` を `_TASK_TEMPLATE.md` から生成
   - `docs/tasks/list.md` に `🔲 未着手` 行を追加
   - draft は `docs/draft/<slug>.md` に保存（履歴として残す）

### テンプレートの場所

- `.claude/templates/docs/tasks/list.md` — タスク台帳ひな型（凡例・依存関係図・更新ルール込み）
- `.claude/templates/docs/tasks/parking-lot.md` — 保留タスクひな型（必須 7 項目フォーマット込み）
- `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` — 個別タスクひな型（背景 / 仕様 / 設計 / TDD / Wave / 完了条件 / 影響範囲）
- `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` — 設計 draft ひな型（真因 / 案比較 / Wave / リスク / DoD / 承認履歴）

### 自動生成のセーフティ

- **冪等**: 既存ファイルは絶対に上書きしない（`/init-tasks --force` のみ例外）
- **ID 重複検知**: `/new-task` は同 ID が既に存在する場合中断
- **設計欠落検知**: `/new-task` は対応 draft が無い場合中断（`--no-draft` で hot fix の例外）
- **fail-open**: SessionStart hook 失敗時もセッション継続

### Hook による強制（コマンド経由でなくても発動）

`.claude/hooks/task-rule-guard.sh` が PreToolUse で以下を **block** で強制する:

| シナリオ | 動作 |
|---|---|
| `docs/tasks/task-<id>-<slug>.md` の Write、対応する `docs/draft/{<slug>.md, task-<slug>.md, <basename>}` が無い | **BLOCK** — 「先に `/new-draft` で設計を起こせ」と提示 |
| `docs/tasks/task-<id>-*.md` / `phase-<id>-*.md` の Write、同 `<id>` が既に存在 | **BLOCK** — 「別 ID を割り当てるか既存を Edit せよ」と提示 |
| `docs/tasks/` への命名規約外 Write（`task-` `phase-` で始まらない） | 警告 context 注入（block しない） |
| `docs/tasks/task-*.md` の **Edit**（既存編集） | 「list.md と同期更新せよ」context 注入 |
| `docs/tasks/parking-lot.md` の Edit | 必須 7 項目の hint context 注入 |
| `list.md` `_TASK_TEMPLATE.md` `_DRAFT_TEMPLATE.md` の Edit/Write | exempt（素通り） |
| サブエージェント実行中 | 全パス通過（多重ゲート防止） |

### Bypass

| 方法 | 用途 |
|---|---|
| `ECC_TASKGUARD=off` | セッション全体で OFF |
| `/task-bypass <slug>` | 1 ファイル分 pre-clear（`.claude/.taskguard-state/<slug>.cleared`） |
| `/task-bypass --clear-all` | 全 marker 削除 |

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリに記録すること。

## Parking Lot（保留タスク）

着手不可の保留タスクは [`docs/tasks/parking-lot.md`](../../docs/tasks/parking-lot.md) で管理する。テンプレは `.claude/templates/docs/tasks/parking-lot.md`。

- **追加条件**: 既存設計書（`docs/` 配下）または `docs/draft/` の承認済み設計へのリンクが必須
- **必須項目 7 つ**: 起案日 / 保留日 / 保留理由 / 設計書 / 実装状態 / 再検討トリガー / 代替現状
- **ステータス**: 🧊 保留 / 🔍 再検討予定 / ❌ 不採用
- **移行**: 再検討トリガー成立時に parking-lot から削除し、list.md に新規タスクとして追加（通常フロー = `/new-task`）
- **定期レビュー**: 🔍 エントリは四半期ごとに見直し
- **不採用**: ❌ エントリは履歴として残す（過去意思決定のトレーサビリティ）

## タスク管理の関連コマンド

| コマンド | 役割 |
|---|---|
| `/init-tasks` | 台帳テンプレ初期化（SessionStart hook で自動実行） |
| `/new-draft <slug>` | 設計 draft 起こし（`_DRAFT_TEMPLATE.md` から） |
| `/new-task <id> <slug>` | 設計承認後にタスク化（`_TASK_TEMPLATE.md` から）+ list.md 行追加 |
| `/start-task <id>` | 着手（branch 切替 + status 同期） |
| `/finish-task <id>` | 完了（build/test/docs 検証 + done 化 + commit 提案） |
| `/task-bypass <slug>` | task-rule-guard を 1 ファイル分 bypass（hot fix 用） |
