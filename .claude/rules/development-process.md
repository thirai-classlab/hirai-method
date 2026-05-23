---
paths:
  - "src/**/*"
  - "scripts/**/*"
  - "tests/**/*"
  - "docs/tasks/**/*"
  - "docs/draft/**/*"
  - "doc/**/*"
  - "force-app/**/*"
---

# 開発プロセスルール

## コーディング指針（必読）

実装・レビュー・リファクタの前に [`.claude/skills/karpathy-guidelines/SKILL.md`](../skills/karpathy-guidelines/SKILL.md) を参照すること。LLM コーディング特有の落とし穴（過剰実装・想定の隠蔽・周辺コードの勝手な改変・曖昧な完了宣言など）を抑える行動規約。

主要原則の要点（詳細は SKILL.md）:
- **Think Before Coding**: 想定は明示し、不明点は黙って解釈せず質問する
- **Simplicity First**: 依頼範囲を超える機能・抽象・エラーハンドリングを足さない
- **Surgical Changes**: 触らなければいけない箇所だけを編集する。隣接コードの「ついで改善」禁止
- **Verifiable Success Criteria**: 完了条件を実測可能な形（test pass / build green / 出力一致など）で定義する

サブエージェントへ作業を委譲する際は、プロンプトに本ガイドラインへの遵守を明記する。

## 出力フォーマット（必読）

メインエージェントは各作業ステップで「Why × 5 階層 / 現在行っていること / 他の選択肢を取らなかった理由」の 3 点を必ず明示する。詳細は [`why-x5-output.md`](./why-x5-output.md)。`.claude/hooks/why-x5-reminder.sh` が UserPromptSubmit hook で本ルールを毎ターン強制する。

## TDD（テスト駆動開発）

すべての実装はTDDで進める。

1. テスト専門エージェント (`Agent(tdd-guide)` / `Agent(test-automator)` / `Agent(qa-expert)`) にテスト観点・テストパターンを洗い出させる
2. テストを設計・実装する（Red: テストが失敗する状態）
3. プロダクションコードを実装してテストを通す（Green）
4. リファクタリング（Refactor）

テストなしでプロダクションコードを書かない。

## サブエージェント委譲（Hook で強制）

メインエージェントは `src/` `tests/` `scripts/` に対する**一切の直接操作を禁止**する。
読み取り（Read/Grep/Glob）・編集（Edit/Write）の両方が Hook でブロックされる。

**メインエージェントの役割（これだけ）:**
- **タスク管理（メイン専任・必須）**: docs/tasks/ の更新、進捗追跡、ステータス変更。サブエージェントにタスク管理を委譲してはならない (詳細は [`task-management.md`](./task-management.md) §「メインエージェント専任（必須）」)
- 作業のアサイン（Agent tool でサブエージェントを起動）
- 完了報告・成果物の確認
- docs/, CLAUDE.md, .claude/ など管理ファイルの更新

**メインエージェントが直接使えるツール:**
- `Skill` — 全対象（メインで直接実行可能）
- `mcp__*` — 全対象（メインで直接実行可能）
- docs/, CLAUDE.md, .claude/ の Read/Edit/Write

**サブエージェントに委譲する作業（すべて Agent tool 経由）:**
- コード調査・読み取り → `Agent(subagent_type=Explore)`
- テスト設計 → `Agent(tdd-guide)` / `Agent(test-automator)` / `Agent(qa-expert)` (MECE 観点は `/test-design <slug>` command で並列 fan-out)
- コード実装 → `Agent(general-purpose)` or `Agent(isolation=worktree)`
- ビルド確認 → 言語別 `/go-build` / `/rust-build` / `/cpp-build` / `/kotlin-build` / `/flutter-build` / `/java-build` 等の build command、または `verification-loop` skill (`/verify` command)
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

> **heredoc / quoted string 内の特殊文字は保護される**: `git commit -m "table|cell"` や `git commit -m 'A || B'` の `|` `||` `&&` `;` は quote-aware segment splitter (`split_command_segments` 関数、`.claude/hooks/delegation-guard.sh`) が separator 扱いせず単一 segment として whitelist 照合する。詳細は `.claude/tests/delegation-guard-segment-smoke.sh` Case 4-6 を参照。heredoc 本文 (`<<EOF ... EOF`) は単行解析の限界で未対応 (将来 B フル parser 化で対応)。

### 5. Bash deny / whitelist 不在時の subagent 委譲反射（必須）

メインエージェントが Bash 実行で deny / whitelist 不在 / 委譲ガード block を受けた場合、
**自動的に Agent tool で subagent に委譲して再試行する**ことを必須とする。

#### 禁止事項

- **Bash deny を loop 停止理由にしてはならない**
- 「これ以上進めない」と user に報告して止まる前に、必ず Agent tool で subagent に振り出す
- whitelist への 1 行追加申請は user の選択肢として提示してよいが、提示する前に subagent 委譲を試行する

#### 委譲反射の手順

1. **Bash が deny された** → tool error / hook block / whitelist 不在を検知
2. **直ちに Agent tool 起動**(`run_in_background: true` 必須 — §1)
3. subagent に「メインで block された Bash 操作」を委譲
4. **TaskCreate でタスク登録**(§4 ルール)

#### 違反例

- メインが「Bash 全面 block でこれ以上進めません。loop 停止します」と発言
  → これは誤動作。Agent 委譲で進められる
- whitelist 1 行追加申請のみ提案して subagent 委譲を試みない
  → 申請は user 検討事項。**まずは委譲反射**を試行する

#### 例外

- subagent も deny で進められない場合(極稀) → user に状況報告 + permission 設定変更を依頼
- 委譲先が無いタスク(例: メインの memory 操作) → そもそも Bash 不要なはず

#### 理由

- Bash whitelist は **メインからの直接 Bash** 許可リスト。subagent 経由は別経路
- 委譲ガード(`delegation-guard.sh`)は「メインが直接コードを触る」ことを防ぐためで、subagent はその対象外
- 「Bash deny = 進行不能」と短絡判断するとハーネス本来の目的(メイン → subagent 委譲)を裏切る

### Hook による補助（soft warning）

`.claude/hooks/agent-marker-set.sh` は PreToolUse(Agent) で foreground 起動を検出した場合、stderr に WARN を出す（block ではない）。`tool_input.run_in_background != true` のときに発火。

## サブエージェント `.claude/` 編集の staging 戦略（必須）

Claude Code permission system は subagent context での `.claude/` 配下への直接 `Write` / `Edit` / `Bash` heredoc redirect を **一律 denied** する (sub-agent isolation)。メインからの Write/Edit は通過するが、subagent に委譲した場合は次の **staging 戦略** を必須とする。本規範は task #12 dual-mode-portability 実装中の発見 (2026-05-13) から起こされた。

### 強制プロンプト雛型

メインが subagent に `.claude/` 編集を含む task を委譲する際、Agent tool prompt に以下を **必ず明示** する:

> 本 task は `.claude/<sub>/foo.sh` 等への新規作成 / 編集を含む。Claude Code permission system が subagent context での `.claude/` 直接 Write を deny するため、以下の staging 戦略を使え:
>
> 1. `/tmp/foo.sh` (または任意の `/tmp/` パス) に `Write` で内容を書く
> 2. `mv /tmp/foo.sh .claude/<sub>/foo.sh` で install
> 3. 実行 file の場合 `chmod +x .claude/<sub>/foo.sh`
>
> Edit の場合: 既存 file を Read → 内容を編集して `/tmp/foo.sh` に `Write` → `mv` で上書き install

### 検出パターン（subagent 失敗時の即時切替）

subagent が以下のいずれかで block / error 報告した場合、ただちに staging 戦略へ切替えて retry:

- `Write` tool で `file_path` が `.claude/` 配下 → permission denied
- `Edit` tool で `file_path` が `.claude/` 配下 → permission denied
- `Bash` で `cat > .claude/...` / `tee .claude/...` heredoc redirect → block

これら 3 パターンは task #12 subagent ad80e8f5b63437f01 で全件確認済。

### 例外

- **メインからの `.claude/` Write/Edit は通過** (`delegation-guard.sh` が `.claude/` をメイン許可)。本 staging は **subagent 委譲時のみ** 該当
- `worktree` isolation で起動した subagent も同 permission policy 下 (task #12 で foreground / background / worktree いずれも denied 確認)

### 起源

- task #12 dual-mode-portability (`feat/loop-mode` ブランチ、commit `4ddf115`〜`93100a8`、2026-05-13)
- Serena memory: `learning/solutions/subagent-claude-permission-staging` (subagent context での `.claude/` write 制約と staging 回避策、task #12 で発見)
- 副産物 entry: `docs/tasks/next-actions.md` entry #12 (2026-05-13、🟡)
- 規範化 task: #13 (本セクション追加)

### 再発検出時の昇格判定

honor system のため、subagent dispatch prompt への staging 明示忘れリスクは残存する。再発が **N=2 以上** 観測されたら、副産物 entry を起こし以下を検討:

- 案 B: `.claude/templates/` に staging 強制プロンプト template 新設 + `/new-task` 系 command が自動参照
- 案 C: 専用 hook `subagent-staging-reminder.sh` で PreToolUse(Agent) に staging 強制注入

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

### major subagent only block (2026-05-13、task #9)

F3 confidence-gate は **major subagent (`general-purpose` / `Explore` / `Task` allowlist or `is_sidechain==path_subagents`)** のみ confidence 自己評価を強制し、軽量 sidechain (Task tool query / 短い tool-use only sidechain) は **fail-open** で通過させる。

- env `HC_CONFIDENCE_MAJOR_AGENT_ONLY=false` で従来動作 (全 stop event で block 判定) に復帰可
- 設計起源: `docs/draft/harness-audit-followups.md` §3 W1 (2026-05-13)
- 観測: `/harness-audit` で `regex_no_match` 累計が major subagent 由来のみに絞られる

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

詳細は [`task-management.md`](./task-management.md) §「メインエージェント専任（必須）」を参照。

## 副産物発生時の即時 draft 起こし義務（必須・再発防止）

タスク実装中・レビュー中・セッション中に「これは別 task として管理すべき」と判断した副産物 (byproduct) は **memory / 会話履歴に流すだけでは禁止**。必ず以下フローを取る:

1. **即時記録**: `docs/tasks/next-actions.md` に entry 追加（緊急度 / 推奨処理を明記）
2. **当セッション内に draft 起こし**: 緊急度 🔴 (次セッション着手必須) と 🟡 (近日) の entry は当セッション中に `/new-draft <slug>` で `docs/draft/<slug>.md` を起こす
3. **次セッション or 同セッション内に承認 + tasking**: user 承認後に `/new-task <id> <slug>` で list.md に行追加
4. **next-actions.md の処理結果列に移行先を記入** (例: 「→ `docs/draft/<slug>.md` → task #N」)

### 違反パターン (絶対禁止)

- 副産物を memory (`~/.claude/projects/.../memory/`) にのみ保存して draft 化しない
- 副産物を「次セッションで対応」とコメントだけ残してセッション終了する
- 副産物を発生源 task の `/finish-task` 完了前に処理せず後送りする

### 強制機構

- `.claude/hooks/next-actions-surface.sh` (SessionStart): 未処理 entry を毎セッション開始時に `<system-reminder>` で stderr 出力（緊急度 🔴 は強調表示）— **次セッションで実装予定** (`docs/draft/byproduct-discharge-mechanism.md` W1)
- `.claude/hooks/workflow-guard.sh` (PreToolUse Bash `/finish-task`): 発生源 task の next-actions.md 関連 entry が未処理なら BLOCK — **次セッションで実装予定** (同 draft W3)
- `_TASK_TEMPLATE.md` の「派生 task / 次アクション候補」セクション: task 実装中に発見した副産物を本セクションに必ず記入、`/finish-task` で空 or 全件転記済を検証 — **次セッションで実装予定** (同 draft W2)

詳細は [`workflow.md`](./workflow.md) の関連セクションおよび [`docs/draft/byproduct-discharge-mechanism.md`](../../docs/draft/byproduct-discharge-mechanism.md) を参照。

## 設計→承認→タスク追加フロー

詳細は [`task-management.md`](./task-management.md) §「設計→承認→タスク追加フロー（必須）」を参照。テンプレ初期化 / 設計起こし / 承認 / タスク化の 4 ステップ、テンプレート配置、自動生成セーフティ、`task-rule-guard.sh` による Hook 強制表、bypass 経路 (`ECC_TASKGUARD` / `/task-bypass`)、関連コマンド一覧を集約。

## Parking Lot（保留タスク）

詳細は [`task-management.md`](./task-management.md) §「Parking Lot（今後検討タスク）」を参照。必須 7 項目 / ステータス記号 / 移行ルール / 定期レビューを集約。
