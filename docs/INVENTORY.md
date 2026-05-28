# Inventory — Claude Code ハーネス構成要素

`./claude-code-harness` に含まれるすべての設定ファイル・hook・skill・command の役割表。

## 設定 / 委譲ガード / 通知

| Path | 役割 | ステータス |
|---|---|---|
| `CLAUDE.md` | プロジェクトルート用テンプレート。Overview / Autonomous Progression / Rules table / Tech Stack / Critical Operational Lessons の骨格。`<...>` プレースホルダを置換して使う。 | テンプレート |
| `.claude/settings.json` | Hook 配線 + 共通 deny ルール + 最小 ask リスト。サニタイズ済み: `permissions.ask` から `supabase db push` / `supabase functions deploy` / `vercel env add/rm` を除去。 | サニタイズ済 |
| `.claude/harness-config.yml` | **Portability SSoT**。`protected_paths` / `task_dir` / `draft_dir` / `bash_whitelist_path` / state dir / `homunculus_root` / 通知音源を集中管理。3 つの guard hook + audit script が `config-loader.sh` 経由で参照。別リポ移植時はここ 1 枚を編集すれば挙動が連動変化する。 | New (2026-05-04) |
| `.claude/hooks/lib/config-loader.sh` | 純 bash の YAML サブセットパーサ（`yq` 等の外部依存ゼロ）。`harness-config.yml` を読んで `HC_*` 変数として export。tilde 展開対応、fail-open（不在時はハードコード fallback）。 | New (2026-05-04) |
| `.claude/hooks/delegation-guard.sh` | メインエージェントの保護パス（既定 `src/`/`tests/`/`scripts/`、`harness-config.yml` で上書き可）への直接アクセスを block。bash whitelist を強制。inline 環境変数による Hook バイパスも検出。Edit/Write/Read/Grep/Glob/Bash を 1 スクリプトで集約。 | config 化済 |
| `.claude/hooks/agent-marker-set.sh` | PreToolUse(Agent\|Task): `.claude/.agent-markers/*.lock` を書き出し、サブエージェント実行中であることを delegation-guard に伝える。 | そのまま |
| `.claude/hooks/agent-marker-clear.sh` | PostToolUse(Agent\|Task): 当該 session の marker を削除 + 期限切れ marker（>60 分）を sweep。 | そのまま |
| `.claude/hooks/notify.sh` | Claude が入力を求めた時の macOS 通知 + 音。 | そのまま |
| `.claude/hooks/stop.sh` | Claude のターン終了時の macOS 通知 + 音。 | そのまま |
| `.claude/hooks/check-md-mermaid.sh` | PostToolUse(Edit\|Write) on `.md`/`.mdx`: ` ```mermaid ` ブロックを抽出し mermaid@11 パーサーで検証。 | そのまま |
| `.claude/scripts/check-md-mermaid.mjs` | hook が呼び出す Node スクリプト。mermaid@11 が parse 中に DOMPurify を呼ぶため jsdom shim を仕込む。 | そのまま |
| `.claude/skills/check-md-mermaid/SKILL.md` | Mermaid 検証スクリプトの手動実行用スキルドキュメント。 | そのまま |
| `.claude/bash-whitelist.txt` | メインエージェントが実行可能な Bash コマンドの SSoT。1 行 1 正規表現、`^` で先頭固定。**セクションマーカー**で path-aware / path-restricted を区分（W1.2 以降）。 | そのまま |
| `.claude/bash-whitelist-requests/REQUEST_TEMPLATE.md` | 新規 whitelist エントリ申請用テンプレート（`.claude/bash-whitelist-requests/YYYY-MM-DD-<slug>.md` 形式で配置）。 | そのまま |
| `.claude/rules/development-process.md` | TDD / サブエージェント委譲 / タスク管理 / 設計→承認→タスク追加フロー。`src/` `tests/` `scripts/` と `docs/tasks/` `docs/draft/` に依存。 | そのまま — パス要適応 |

## 既存スラッシュコマンド

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/commands/commit.md` | `/commit`: `git diff` から Conventional Commits 自動生成。scope 自動判定（`src/lib/` → lib、`supabase/migrations/` → db 等）に依存。 | そのまま — scope 要適応 |
| `.claude/commands/reviewpr.md` | `/reviewpr <pr>`: rules + CI + Critical Operational Lessons との多軸 PR レビュー。 | そのまま — rule リスト要適応 |
| `.claude/commands/start-task.md` | `/start-task <id>`: `docs/tasks/list.md` + `task-N-*.md` を開く、branch 切替、ステータス in_progress 化。 | そのまま — タスク layout 要適応 |
| `.claude/commands/finish-task.md` | `/finish-task <id>`: build/test/docs を検証し、done に更新、commit 提案。 | そのまま — タスク layout 要適応 |

## 自己改善 5 層（ECC 由来）

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/rules/self-improvement.md` | ECC 5 層自己改善アルゴリズム（L1〜L5）の使い分け規約。タスク受領時・失敗時・完了時の分岐を定義。 | New (2026-05-04) |
| `.claude/skills/continuous-learning-v2/SKILL.md` | **L4（核心）**: Hook ベース自動学習。Atomic instinct + 信頼度 0.3-0.9 + project-scoped。 | ECC v2.1.0 から複製 |
| `.claude/skills/continuous-learning-v2/hooks/observe.sh` | PreToolUse/PostToolUse hook。100% 確実観察、git remote 検出、project-scoped 振り分け。 | New (2026-05-04) |
| `.claude/skills/continuous-learning-v2/instinct-cli.py` | 標準ライブラリのみで動く instinct 管理 CLI。status / projects / evolve / promote / export / import / observe-analyze。 | New (2026-05-04) |
| `.claude/skills/continuous-learning-v2/config.json` | Observer 設定（Haiku モデル・閾値・confidence 力学パラメータ）。 | New (2026-05-04) |
| `.claude/skills/eval-harness/SKILL.md` | **L1**: pass@k / pass^k メトリクスと code/rule/model/human grader。 | ECC から複製 |
| `.claude/skills/continuous-agent-loop/SKILL.md` | **L2**: 6 ループパターン（Sequential / NanoClaw / Infinite / Continuous PR / De-Sloppify / Ralphinho）。 | ECC から複製 |
| `.claude/skills/gan-style-harness/SKILL.md` | **L2+**: Planner / Generator / Evaluator 3 エージェントが 4 基準スコアで収束。 | ECC から複製 |
| `.claude/skills/agent-introspection-debugging/SKILL.md` | **L5**: 失敗時の 4 フェーズ自己診断（Capture / Diagnose / Recover / Report）。 | ECC から複製 |
| `.claude/commands/instinct-status.md` `/projects.md` `/evolve.md` `/promote.md` `/instinct-export.md` `/instinct-import.md` `/learn.md` | L4 操作系スラッシュコマンド 7 本。 | New (2026-05-04) |
| `.claude/commands/eval.md` | L1 操作（define / check / report）。 | New (2026-05-04) |
| `.claude/commands/gan-design.md` `/gan-build.md` | L2+ Planner / Generator-Evaluator 起動。 | New (2026-05-04) |
| `.claude/commands/agent-introspect.md` | L5 起動。 | New (2026-05-04) |

## 事実検証レイヤー（F1 / F2）

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/skills/gateguard/SKILL.md` | **F1 事前ゲート**: 初回 Edit/Write/破壊的 Bash で 4 種の事実を強制要求。+2.25/10 ポイントの品質改善（A/B 実測）。 | ECC から複製 |
| `.claude/skills/gateguard/.gateguard.yml` | GateGuard 設定（gate 対象・除外パス・破壊的コマンドパターン）。 | New (2026-05-04) |
| `.claude/hooks/gateguard.sh` | PreToolUse hook（Edit/Write/Bash matcher で発火）。state file で 2 回目以降を通過させる。 | New (2026-05-04) |
| `.claude/skills/verification-loop/SKILL.md` | **F2 事後検証**: build / type / lint / test / security / diff の 6 phase 検証。 | ECC から複製 |
| `.claude/commands/verify.md` `/gate-status.md` `/gate-clear.md` `/gate-bypass.md` | F1/F2 操作系スラッシュコマンド 4 本。 | New (2026-05-04) |
| `.claude/.gitignore` | `.gateguard-state/` `.agent-markers/` を git から除外。 | New (2026-05-04) |

## タスク管理

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/hooks/init-tasks-on-start.sh` | SessionStart hook。`docs/tasks/list.md` 等が未存在ならテンプレから生成。 | そのまま |
| `.claude/hooks/task-rule-guard.sh` | PreToolUse(Edit\|Write)。`docs/tasks/` への新規 Write を draft 不在 / ID 重複で BLOCK。 | そのまま |
| `.claude/templates/docs/tasks/list.md` | タスク台帳ひな型（凡例・依存関係図・更新ルール込み）。 | そのまま |
| `.claude/templates/docs/tasks/parking-lot.md` | 保留タスクひな型（必須 7 項目フォーマット込み）。 | そのまま |
| `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` | 個別タスクひな型。 | そのまま |
| `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` | 設計 draft ひな型。 | そのまま |
| `.claude/commands/init-tasks.md` `/new-draft.md` `/new-task.md` `/start-task.md` `/finish-task.md` `/task-bypass.md` | タスク管理スラッシュコマンド 6 本。 | そのまま |

## 自己診断 / 観測（W2 で追加）

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/hooks/failure-loop-detect.sh` | PostToolUse(`*`)。同種エラー 3 連続を検出して `/agent-introspect` を `additionalContext` で提案。 | New (W2.1) |
| `.claude/scripts/harness-audit.py` | ハーネス健全性レポートを実測値で出力（observations.jsonl / GateGuard / TaskGuard / failure-window）。 | New (W2.2) |
| `.claude/commands/harness-audit.md` | `/harness-audit`: 上記スクリプトを起動して結果を整形。 | New (W2.2) |

## 規範文書の Layer A/B Strategy (2026-05-28、task-51)

`.claude/rules/*.md` (規範文書) は **Layer A (要約、context 自動注入) + Layer B (詳細、明示 Read のみ)** の 2 層構造で運用する。

| Path | 役割 | 物理配置 | context 注入 |
|---|---|---|---|
| `.claude/rules/<rule>.md` | **Layer A** — 要約版 (採用 N 条 / 遵守事項 / table / bypass env 1-2 行 / Layer B link / 起源 1 行) | `.claude/rules/` (Claude Code 再帰 discover 対象) | claudeMd 経由で常時注入 |
| `.claude/rules-details/<rule>.details.md` | **Layer B** — 詳細版 (OK/NG 例 / history / SUPERSEDED / bypass 詳細 / 起源詳細 / 5 層強制機構詳細 / 関連 artifact 完全 list) | `.claude/rules-details/` (別 dir、Claude Code discover 対象外) | **非注入** (Read tool で明示参照のみ) |

> **設計経緯 (2026-05-28 A 案 redesign)**: 当初は `.claude/rules/<rule>.details.md` + frontmatter `paths: []` で非注入を狙ったが、Claude Code 公式仕様 (code.claude.com/docs/en/memory.md) で「`.claude/rules/*.md` は再帰 discover + startup load」「`paths:` は path match 時の**追加適用** (除外機構ではない)」が確定 (claude-code-guide subagent + 公式 doc、confidence 0.95)。token 実測でも `paths: []` 配置で context は逆に増加 (153K vs before ~146K) したため、Layer B を別 dir へ物理移動して除外を実現。

**現状の 2 層分割対象** (task-51 Step 3+5b 完了、6 file):

| Layer A (`.claude/rules/`) | Layer B (`.claude/rules-details/`) | Layer A 抜粋 keyword |
|---|---|---|
| `self-improvement.md` | `self-improvement.details.md` | L1-L5 + F1/F2 規約 / 5 + 3 層 |
| `development-process.md` | `development-process.details.md` | TDD / 委譲ガード 7 必須要件 / staging 戦略 / cross-repo write 例外 / Confidence Gate (F3) |
| `task-management.md` | `task-management.details.md` | 採用 6 条 / メイン専任 / 開発開始時必読義務 / parking-lot |
| `workflow.md` | `workflow.details.md` | 14-stage / 10-stage / W1-W4 / 20 MECE / fan-out reviewer-registry |
| `modes.md` | `modes.details.md` | Normal/Loop / 9 遵守事項 / 自律実行禁止 11 カテゴリ / 5 層強制機構 |
| `why-x5-output.md` | `why-x5-output.details.md` | v10 1 行 format (`<何のため> のため、<何をやる> を行う`) |

`git-workflow.md` は ~1K で退避不要 (Layer A のみ)。

**Layer B Read trigger 4 条件** (Layer A 冒頭に admonition 配置):
1. 違反検出時 (hook BLOCK / warn 注入受領 / regex 不一致)
2. 規範変更時 (rule 編集 / draft 起案 / 採用 N 条改定)
3. 新規事案 (初遭遇 keyword / 例外パターン疑い)
4. 学習 / dogfood (task 着手前依存先必読 / harness audit / 副産物整理)

通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。

**規約**: Layer A → Layer B link は **2 要素 hard match** (`details.md` 含む markdown link + section anchor) を満たせば spec compliant (task-51 Step H、iter 2 fix、2026-05-28 緩和)。link path 規約: Layer A → B は `../rules-details/<rule>.details.md`、Layer B → A は `../rules/<rule>.md` (相対参照、深さ同じ sibling dir)。

**機械強制**:
- `install.sh` `rsync -a .claude/` で `.claude/rules-details/` 配下も自動同期 (RSYNC_EXCLUDES 不在、4 リポへ配布)
- `.claude/tests/layer-b-context-isolation-smoke.sh` (8 cases) で Layer B 物理 dir / link 存在 / install.sh sync pattern 等を検証

**起源**: task-51 (context-bloat-reduction、2026-05-28)、設計 draft `docs/draft/context-bloat-reduction.md` §3 (Q2) + A 案 redesign (2026-05-28、smoke 実測で `paths: []` 無効判明 → Layer B 物理移動)。

## 外部インポート（コミュニティ由来）

### Agents（[VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) MIT）

`.claude/agents/<category>/<name>.md` 形式で **144 agents / 10 categories** を配置。

| Category | 件数 | 主な内容 |
|---|---:|---|
| `01-core-development` | 11 | api-designer / backend-developer / frontend-developer / mobile-developer など |
| `02-language-specialists` | 30 | python / typescript / golang / rust / java / kotlin / swift など各言語 pro |
| `03-infrastructure` | 16 | devops / kubernetes / terraform / cloud-architect など |
| `04-quality-security` | 16 | code-reviewer / security-auditor / penetration-tester / qa-expert など |
| `05-data-ai` | 13 | data-scientist / ml-engineer / nlp-engineer / mlops-engineer など |
| `06-developer-experience` | 14 | tooling-engineer / build-engineer / dx-optimizer / cli-developer など |
| `07-specialized-domains` | 13 | blockchain / iot / game-developer / embedded-systems など |
| `08-business-product` | 12 | product-manager / scrum-master / business-analyst など |
| `09-meta-orchestration` | 11 | multi-agent-coordinator / task-distributor / workflow-orchestrator など |
| `10-research-analysis` | 8 | research-analyst / market-researcher / trend-analyst など |

### Skills（[ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)）

`.claude/skills/<name>/` に **32 skills** を配置（既存 9 と衝突なし）。

主要グループ:
- **コンテンツ生成**: `artifacts-builder` `brand-guidelines` `canvas-design` `theme-factory` `tailored-resume-generator`
- **ドキュメント変換**: `document-docx` `document-pdf` `document-pptx` `document-xlsx`
- **ビジネス自動化**: `changelog-generator` `internal-comms` `invoice-organizer` `meeting-insights-analyzer`
- **リサーチ**: `content-research-writer` `developer-growth-analysis` `lead-research-assistant` `competitive-ads-extractor`
- **ユーティリティ**: `file-organizer` `image-enhancer` `video-downloader` `webapp-testing` `domain-name-brainstormer` `raffle-winner-picker`
- **メタ**: `skill-creator` `skill-share` `template-skill` `mcp-builder`
- **連携**: `connect` `connect-apps` `langsmith-fetch` `slack-gif-creator` `twitter-algorithm-optimizer`

### 除外したもの

- `composio-skills/` — 832 個の Composio platform 連携サブスキル（platform 依存が強すぎ）
- `connect-apps-plugin/` — plugin 形式（commands のみで SKILL.md なし）

### ライセンス

- VoltAgent: **MIT License** — 各 agent ファイル末尾の attribution は temp ファイル参照ではないため改変不要
- ComposioHQ: 個別 skill により異なる（`SKILL.md` frontmatter の `license:` フィールドおよび `LICENSE.txt` を確認）
