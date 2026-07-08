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

## Phase 2 Wave 1 追加 (2026-07、task-92 / task-95 / task-96)

`install.sh` 側で consuming repo へ curated pre-commit hook を配布する仕組み、`.claude/hooks/` 群の dead/live/alias 判定 smoke、そして agent-router LLM fallback child toggle を追加。

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/templates/githooks/pre-commit` | consuming repo へ配布する pre-commit template。4 smoke curated set (enforcement-mismatch / delegation-guard / task-rule-guard / dispatcher-manifest) を実行。既存 `.githooks/pre-commit` は上書きせず skip + WARN、`--no-hooks` で install 時 skip、`HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false` で template opt-out、`HC_PRECOMMIT_SKIP=1` で 1 回 bypass。 | New (task-92) |
| `.claude/tests/install-pre-commit-smoke.sh` | task-92 の distribution 契約 smoke。install.sh --update 経由での pre-commit 配布 + 既存保護 + `--no-hooks` skip + feature toggle OFF 挙動を検証。 | New (task-92) |
| `.claude/tests/dead-hook-inventory-smoke.sh` | `enforcement_matrix` 配下 hook を 3-way (dead / live / alias) 自動分類し、`harness-config.yml` grep で live 定義と `disabled_reason` 整合を機械判定。 | New (task-95) |
| `.claude/tests/agent-router-llm-fallback-smoke.sh` | task-96 の LLM fallback child toggle 契約 smoke (ARF-1..13)。default OFF / opt-in / budget 強制 disable / threshold override / env 互換 WARN / budget accumulator + static drift check (`unset` / inline env prefix) + parent-child toggle interaction を検証。 | New (task-96) |
| `harness-config.yml` keys: `feature_pre_commit_smoke_enabled` / `pre_commit_smoke_budget_sec` / `feature_asana_prompt_enabled` / `feature_agent_router_llm_fallback_enabled` / `agent_router_llm_budget_usd_per_day` / `agent_router_llm_similarity_threshold` | Wave 1 追加 yml key 集約。`hc-config.sh --get <key>` で raw 値取得、`--set <key>=<val>` で local override。 | New (task-92 / task-96) |

## Phase 2 Wave 3 追加 (2026-07、task-97)

`enforcement_matrix` を全 hook 拡張 (11 → 23 guard) し、`sessionstart-footprint-smoke.sh` に FP-7 fail-open dedicated case 追加 + FP-5 label 厳密化 (field 数検証) で副産物 next-actions #81 を fold。

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/harness-config.yml` `enforcement_matrix.*` | 12 新規 guard 追加: 中核 BLOCK 4 (`delegation_guard` / `confidence_gate` / `autonomous_action_guard` / `byproduct_discharge`) + advisory 6 (`context_budget` / `parallel_subagent_reminder` / `reviewer_count_guard` / `why_x5_enforcement` / `failure_loop_detect` / `stale_harness_detect`) + Gate/Confidence 2 (`agent_router_suggest` parent / `agent_router_llm_fallback` child、task-96 由来)。全 entry が 5 field (`feature_key` / `docs_claim` / `events` / `presets` / `disabled_reason`) 全備、既存 11 guard は verbatim 維持。 | ✅ Wave 3 (task-97) |
| `.claude/tests/enforcement-mismatch-smoke.sh` `required` set | Case 2 の期待集合を 11 → 23 guard に拡張 (現状維持 semantics = 最小必須 guard 存在確認)。 | ✅ Wave 3 (task-97) |
| `.claude/tests/sessionstart-footprint-smoke.sh` FP-5 / FP-7 | FP-5 label のみ match を `totals: [0-9]+ enabled, [0-9]+ disabled` field 数検証へ強化 (副産物 #81b)。FP-7 は hc-config.sh 不在 fixture で fail-open dedicated (dispatcher exit 0 + `<system-reminder>` open==close 均衡、副産物 #81a、mutation probe: mode-session-start.sh `SUMMARY=""` 削除で FP-7b FAIL)。FOOTPRINT_CAP を 2400 → 3100 に引上げ (23 guard summary 出力の増分 ~600B 対応)。 | ✅ Wave 3 (task-97) |

## Phase 2 Wave 2 追加 (2026-07、task-93 / task-94)

CI 品質ゲート (matrix 10 job) と、全 hook + self-doctor が共有する BLOCK/WARN/INFO 統一出力 API を追加する。

| Path | 役割 | ステータス |
|---|---|---|
| `.github/workflows/harness-smoke.yml` | matrix (2 preset × 5 category = 10 並列 job) で `run-all-smokes.sh --category <name>` を実行する CI workflow。preset override は `HC_DEFAULT_PRESET` (config-loader.sh:353 SSoT)、fail-fast: false で 10 job signal 独立、失敗時は `.claude/.workflow-state/**` + `/tmp/smoke-runner-out.*` を artifact 保存 (retention 7 日)。既存 workflow.yml は create-if-absent で touch しない。 | ✅ Wave 2 (task-93) |
| `.claude/tests/install-ci-matrix-smoke.sh` | task-93 の CI matrix workflow 配布契約 smoke。install.sh 経由での `.github/workflows/harness-smoke.yml` 配布 + 既存 workflow 保護 + matrix 構造 (2×5=10) + preset env SSoT 名 (`HC_DEFAULT_PRESET`) 一致を検証。 | ✅ Wave 2 (task-93) |
| `.claude/hooks/lib/block-message.sh` | 全 hook (PreToolUse × 5 / Stop × 1 / SubagentStop × 1) + self-doctor が共有する BLOCK/WARN/INFO 統一 4 引数 API (`why` / `fix_one_liner` / `bypass_env` / `docs_link`)。BLOCK は 3 variant (`emit_block_pretool` / `emit_block_stop` / `emit_block_subagent`) に分割し event 別 semantics ずれを実装層で排除、`emit_warn` / `emit_info` は event 非依存。file-top strict mode leak 防止 (subshell 関数化) + jq 不在時 printf JSON fallback。 | ✅ Wave 2 (task-94) |
| `.claude/tests/lib-block-message-smoke.sh` | task-94 の 4 引数 API 契約 smoke。event 別 stdout / stderr 契約 (JSON 有無 / 4 行 label pattern / severity 前置) + sanitize (改行 → 空白、pipe → カンマ) + fail-open (jq 不在 fallback) + BLOCK 3 variant / WARN / INFO の分岐を検証。 | ✅ Wave 2 (task-94) |
| `.claude/tests/byproduct-discharge-guard-smoke.sh` | Stop hook `byproduct-discharge-guard.sh` の `lib/block-message.sh emit_block_stop` 移行 regression gate。JSON stdout 非出力 + 4 label stderr (why/fix/bypass/docs) + BLOCK exit 2 + bypass 挙動を A-D 4 case で検証。 | ✅ Wave 2 (task-94) |

## Phase 3 Wave 4 追加 (2026-07、task-98 / task-99 / task-101)

`.claude/hooks/ui-contract.sh` + `.claude/scripts/cross-file-contract-check.sh` で並列 subagent の cross-file 契約乖離 (memory `feedback_parallel_subagent_cross_file_contract_drift` 実証) を PostToolUse(Edit|Write) で advisory 検出。`.claude/hooks/lib/observability.sh` 5 API + `.claude/scripts/observability-gc.sh` (30 日 GC) + `.claude/scripts/hook-fire-audit.sh` (fire 0 回 hook 検出) で silent failure と死蔵 hook を機械可視化。`review_iteration_min: 3` を yml default で規範化し `reviewer-count-guard.sh` を拡張して iter 未達 slug に advisory warn を注入 (iter 後半 CRIT 検出担保、memory `feedback_iter_fix_introduces_new_crit_pattern` 実証)。

| Path | 役割 | ステータス |
|---|---|---|
| `.claude/hooks/ui-contract.sh` | PostToolUse(Edit\|Write) hook。UI 拡張子 (`.tsx` / `.jsx` / `.vue` / `.svelte` / `.html` / `.css` / `.scss`) 検出時 `cross-file-contract-check.sh` を呼出し、drift を stderr WARN 注入 (BLOCK しない advisory、fail-open)。bypass: `ECC_UI_CONTRACT_OFF=1` (env、bypass.log 記録) / `HC_FEATURE_UI_CONTRACT_ENABLED=false` (config)。 | New (task-98) |
| `.claude/scripts/cross-file-contract-check.sh` | id / symbol / API 名の cross-file grep assert。`.claude/contracts/*.yml` optional SSoT + git diff 対象 file 内相互参照 assert。drift 検出時 rc=1 + stdout に検出内容 1 行/件。 | New (task-98) |
| `.claude/tests/ui-contract-smoke.sh` | task-98 Step 5 smoke (case A-E)。id mismatch fixture / symbol drift fixture / visual artifact 不在 / bypass env / fail-open 動作を検証。 | New (task-98) |
| `.claude/hooks/lib/observability.sh` | 全 hook + self-doctor + smoke runner が source する 5 API (`log_event` / `log_block` / `log_bypass` / `log_fire` / `log_silent_failure`)。common 4-5 args + subshell 関数化 + jq 不在 fallback + fail-open。`observations.jsonl` に append。`log_bypass` は `bypass-logger.sh` の 3-arg signature 互換 (superset)。 | New (task-99) |
| `.claude/scripts/observability-gc.sh` | `observations.jsonl` の 30 日超え entry を `.claude/observability/archive/YYYY-MM.jsonl` へ移動。`--dry-run` / `--apply` オプション。 | New (task-99) |
| `.claude/scripts/hook-fire-audit.sh` | 最終 N 日間で `log_fire` 呼出 0 回の hook を検出 (`--days` / `--json` / `--verbose`)。死蔵 hook 棚卸しの数値根拠を提供。 | New (task-99) |
| `.claude/tests/lib-observability-smoke.sh` | task-99 Step 5 smoke (case A-E)。5 API 存在 + JSON literal escape + jq fallback + feature toggle OFF no-op + 30 日 GC 挙動を検証。 | New (task-99) |
| `.claude/tests/hook-fire-audit-smoke.sh` | task-99 Step 5 smoke (case A-C)。fire 0 回 hook 検出 + `--days` 期間絞込 + JSON / table 出力を検証。 | New (task-99) |
| `.claude/tests/iter-min-3-smoke.sh` | task-101 Step 4 smoke (case A-C)。`reviewer-count-guard.sh` の iter_min:3 拡張動作 (iter 1/2/3 実行時の warn 挙動) を検証。 | New (task-101) |
| `harness-config.yml` keys: `feature_ui_contract_enabled` / `feature_observability_enabled` / `review_iteration_min` + `enforcement_matrix.ui_contract` / `.observability` (5 field 全備、reviewer_count_guard は extended semantics 記載) | Wave 4 追加 yml key + matrix entry 集約。`hc-config.sh --get <key>` で取得、`--set` で local override。 | New (task-98/99/101) |
| `.claude/tests/enforcement-mismatch-smoke.sh` Case 6 | reviewer 制御 3 点一致検証 (`iter_min` ≤ `iter_max` ∧ `iter_min` ∈ [1,5] ∧ `test_min` ≤ `test_max`)。task-101 DoD の「min/max/採用 6 条 4 上限 5 の 3 点一致」を機械強制。 | New (task-101) |
| `.claude/tests/yml-triplet-pre-commit-smoke.sh` | task-100 P3-3 Step 3 smoke (case A-E、portability)。`.claude/templates/githooks/pre-commit` §4.5 yml triplet policy を機械検証。新規 top-level key + consumer + smoke の三点揃 (A: 揃 → PASS、B: consumer 不在 → BLOCK、C: smoke 不在 → BLOCK、D: `HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false` / `ECC_YML_TRIPLET_OFF=1` bypass → PASS、E: 既存 key 値変更のみ → PASS)。 | New (task-100) |
| `.claude/tests/install-full-smoke.sh` | task-102 P3-5 Step 3 smoke (case 9 件、portability)。`install.sh` 全 mode / preset を tmp dir で実 install し、consuming repo 側 portability regression を捕捉する「全体健全性 gate」。副産物 #78 settings seed / #80 install-local-yml case I/J 補強 / #82 `{{TOKEN}}` literal 残存 assertion / #83 first-win/--force flakiness を横断 fold。 | New (task-102) |
| `.claude/tests/normative-ssot-integrity-smoke.sh` | task-103 Step 4 smoke (case A-C、parity)。規範文書 SSoT 整合検証。7 rule file の preset pointer (`現 effective preset は... hc-config.sh --summary` 1 行) 全存在 / BLOCK 記述への preset aware badge 総数 >= 15 / `_TASK_TEMPLATE.md` + `_DRAFT_TEMPLATE.md` preset pointer 存在を機械検証。 | New (task-103) |
| `harness-config.yml` keys: `feature_yml_triplet_check_enabled` + `enforcement_matrix.yml_triplet_check` (5 field 全備、docs_claim=block、harness-dev 含む 3 preset で true、advisory のみ disabled_reason 記載) | Wave 5 追加 yml key + matrix entry。「config 値は consumer + smoke がなければ飾り」memory 起点の 3-point set (yml + hc-config-metadata TSV + config-loader default/export) を規範に機械強制するための guard。 | New (task-100) |

## 規範文書の Layer A/B Strategy (2026-05-28、task-51)

`.claude/rules/*.md` (規範文書) は **Layer A (要約、context 自動注入) + Layer B (詳細、明示 Read のみ)** の 2 層構造で運用する。

| Path | 役割 | 物理配置 | context 注入 |
|---|---|---|---|
| `.claude/rules/<rule>.md` | **Layer A** — 要約版 (採用 N 条 / 遵守事項 / table / bypass env 1-2 行 / Layer B link / 起源 1 行) | `.claude/rules/` (Claude Code 再帰 discover 対象) | claudeMd 経由で常時注入 |
| `.claude/rules-details/<rule>/<topic>.md` | **Layer B 断片** — topic 別詳細 (OK/NG 例 / history / SUPERSEDED / bypass 詳細 / 起源 / 5 層強制機構詳細 / 関連 artifact 完全 list) | `.claude/rules-details/<rule>/` (別 dir + subdir、Claude Code discover 対象外) | **非注入** (Read tool で明示参照のみ) |

> **設計経緯 (2026-05-28 A 案 redesign)**: 当初は `.claude/rules/<rule>.details.md` + frontmatter `paths: []` で非注入を狙ったが、Claude Code 公式仕様 (code.claude.com/docs/en/memory.md) で「`.claude/rules/*.md` は再帰 discover + startup load」「`paths:` は path match 時の**追加適用** (除外機構ではない)」が確定 (claude-code-guide subagent + 公式 doc、confidence 0.95)。token 実測でも `paths: []` 配置で context は逆に増加 (153K vs before ~146K) したため、Layer B を別 dir へ物理移動して除外を実現。

**現状の 2 層分割対象** (task-51 Step 3+5b で 2 層化、task-67 で Layer B を topic 別断片化、6 rule):

| Layer A (`.claude/rules/`) | Layer B 断片 (`.claude/rules-details/<rule>/`) | Layer A 抜粋 keyword |
|---|---|---|
| `self-improvement.md` | `self-improvement/` (4 断片) | L1-L5 + F1/F2 規約 / 5 + 3 層 |
| `development-process.md` | `development-process/` (8 断片) | TDD / 委譲ガード 7 必須要件 / staging 戦略 / cross-repo write 例外 / Confidence Gate (F3) |
| `task-management.md` | `task-management/` (8 断片) | 採用 6 条 / メイン専任 / 開発開始時必読義務 / parking-lot |
| `workflow.md` | `workflow/` (12 断片) | 14-stage / 10-stage / W1-W4 / 20 MECE / fan-out reviewer-registry |
| `modes.md` | `modes/` (5 断片) | Normal/Loop / 9 遵守事項 / 自律実行禁止 11 カテゴリ / 5 層強制機構 |
| `why-x5-output.md` | `why-x5-output/` (4 断片) | v10 1 行 format (`<何のため> のため、<何をやる> を行う`) |

`git-workflow.md` は ~1K で退避不要 (Layer A のみ)。

**Layer B Read trigger 4 条件** (Layer A 冒頭に admonition 配置):
1. 違反検出時 (hook BLOCK / warn 注入受領 / regex 不一致)
2. 規範変更時 (rule 編集 / draft 起案 / 採用 N 条改定)
3. 新規事案 (初遭遇 keyword / 例外パターン疑い)
4. 学習 / dogfood (task 着手前依存先必読 / harness audit / 副産物整理)

通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。

**規約** (task-67 断片版): Layer A → Layer B 断片 link は断片ファイル直リンク (`[<rule>/<topic>.md](../rules-details/<rule>/<topic>.md)`、anchor 方式廃止)。Layer B 断片 → A back-link は `../../rules/<rule>.md` (2 階層上り)。dangling 0 は `.claude/tests/rule-architecture-smoke.sh` で機械検証。

**機械強制**:
- `install.sh` `rsync -a .claude/` で `.claude/rules-details/` 配下も自動同期 (RSYNC_EXCLUDES 不在、4 リポへ配布)
- `.claude/tests/layer-b-context-isolation-smoke.sh` (8 cases) + `.claude/tests/rule-architecture-smoke.sh` (3 asserts: dangling 0 / auto-load isolation / back-link 健全性) で Layer B 物理 dir / link 存在 / install.sh sync pattern 等を検証

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
