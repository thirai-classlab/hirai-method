---
paths:
  - "src/**/*"
  - "scripts/**/*"
  - "tests/**/*"
  - "docs/tasks/**/*"
  - "docs/draft/**/*"
  - "doc/**/*"
  - "force-app/**/*"
  - "**/*.js"
  - "**/*.php"
  - "**/*.jsx"
  - "**/*.html"
  - "**/*.css"
---

# 開発プロセスルール

本 rule は TDD・サブエージェント委譲・Bash 制御・並列化・staging 戦略・Confidence Gate・harness 取込の SSoT を集約する。`src/` `tests/` `scripts/` `docs/tasks/` `docs/draft/` 編集時に自動 Read される。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: 各 § 末尾 pointer から該当断片を直リンク Read (断片群: [`../rules-details/development-process/`](../rules-details/development-process/))

> **現 effective preset は** `bash .claude/scripts/hc-config.sh --summary` で確認。本 rule 内 BLOCK 記述は preset 依存 (harness-dev では advisory、team-default / strict では BLOCK)。docs↔effective 乖離は `.claude/tests/enforcement-mismatch-smoke.sh` が機械検証する。

## コーディング指針 / 出力 / 研究 (必読)

| 規範 | SSoT |
|---|---|
| LLM コーディング行動規約 (Think Before Coding / Simplicity / Surgical / Verifiable) | [`.claude/skills/karpathy-guidelines/SKILL.md`](../skills/karpathy-guidelines/SKILL.md) |
| Why × 5 階層 / 現作業 / 他選択肢の 3 点を毎ステップ明示 | [`why-x5-output.md`](./why-x5-output.md)、`why-x5-reminder.sh` 強制 |
| 外部 library 仕様確認は context7 MCP → WebFetch → GitHub/Exa の fallback chain | training data outdated 回避、推測実装禁止 |

context7 fail で loop 停止しない / 「training data で確信あり」で skip しない (verify before recommending 原則)。

> **適用対象 task 完全 list / `.mcp.json` 設定詳細**: [development-process/research-reuse.md](../rules-details/development-process/research-reuse.md)

## TDD (テスト駆動開発)

すべての実装は TDD で進める:

1. テスト専門 agent (`Agent(tdd-guide)` / `test-automator` / `qa-expert`) でテスト観点洗い出し
2. テスト設計・実装 (Red: 失敗状態)
3. プロダクションコード実装 (Green)
4. リファクタリング (Refactor)

テストなしでプロダクションコードを書かない。

## サブエージェント委譲 (Hook で強制)

メインは `src/` `tests/` `scripts/` への **一切の直接操作を禁止**。読み取り (Read/Grep/Glob)・編集 (Edit/Write) 両方が Hook ブロック。

### メインの役割

- タスク管理 (専任、[`task-management.md`](./task-management.md) §「メインエージェント専任」)
- 作業のアサイン (Agent tool 経由)
- 完了報告・成果物の確認
- docs/, CLAUDE.md, .claude/ の更新

### メイン直接使用可 / Agent tool 経由委譲

| 操作種 | 経路 |
|---|---|
| `Skill` / `mcp__*` 全対象、docs/ / CLAUDE.md / .claude/ の Read/Edit/Write | メイン直接 |
| コード調査 | `Agent(Explore)` |
| テスト設計 | `Agent(tdd-guide)` / `test-automator` / `qa-expert` (`/test-design <slug>`) |
| コード実装 | `Agent(general-purpose)` or `Agent(isolation=worktree)` |
| ビルド確認 | 言語別 `/go-build` / `/rust-build` or `/verify` |

独立タスクは並列複数起動。

### Hook で強制ブロック (メイン直接禁止)

- `Edit` / `Write` / `Read` / `Grep` / `Glob` — src/ tests/ scripts/ 対象
- `WebSearch` / `WebFetch` — 全対象
- `Bash` — **原則禁止**、`.claude/bash-whitelist.txt` 登録 prefix のみ許可

### Bash 制御 SSoT

- `.claude/bash-whitelist.txt` が SSoT、`settings.json` の `permissions.allow` に `Bash(...)` を **重複追加しない**
- Bash 追加は whitelist 1 行追記のみで完結
- 追加申請: `.claude/bash-whitelist-requests/YYYY-MM-DD-<slug>.md` 作成 → user レビュー
- `permissions.deny` での禁止 (`rm -rf`, `git push --force` 等) は別系統

### Hook バイパス禁止

`CLAUDE_HARNESS_ROLE=` 等 inline env による Hook バイパスは `delegation-guard.sh` がブロック。

### Reviewer 制御 SSoT (`harness-config.yml`)

| key | 用途 |
|---|---|
| `review_required_<design\|test\|module\|system\|security>` | 各レビュー要否 |
| `review_min_count_<design\|test\|module\|system\|security>` | 並列起動 reviewer 数下限 |
| `review_max_count_<design\|test\|module\|system>` | 並列起動上限 (cost 制御) |
| `review_iteration_max` | 反復上限 (default 5) |

操作: `bash .claude/scripts/hc-config.sh --get <key>` / `--set <key>=<value>` (atomic backup + type validation)。詳細は [`workflow.md`](./workflow.md) + [`task-management.md`](./task-management.md) 採用 6 条 4 + `docs/SELF_IMPROVEMENT.md` 参照。

> **preset aware (task-70 Phase 2)**: `review_required_*` が「BLOCK して該当レビューを必須化する」と読める場合、その強制レベルは **enforcement preset** に依存する。team-default / strict preset では required (BLOCK)、harness-dev preset (本 repo 採用) では advisory (緩和理由は `harness-config.yml` の `enforcement_matrix.review_required_<x>.disabled_reason`、ハーネス自体のレビューは手動 fan-out 運用)。同様に **gateguard (F1)** の初回 Edit/Write/破壊的 Bash BLOCK (`self-improvement.md` §F1) も `feature_gateguard_enabled` 依存で harness-dev では advisory。現 effective 状態と docs/config mismatch は `bash .claude/scripts/hc-config.sh --summary`、整合は `.claude/tests/enforcement-mismatch-smoke.sh` が機械検証する。

## サブエージェント委譲の必須要件 7 件

| # | 要件 | 概要 |
|---|---|---|
| 1 | **background 起動強制** | `run_in_background: true` 必須。例外: 30 秒以内 smoke のみ。完了通知は SubagentStop hook 経由 |
| 2 | **順序整合性保証** | 依存解決 / 並行可能性判定 / partial commit 整合性をメインが事前判定 |
| 3 | **orchestration 義務** | Agent 起動は委譲ガード経由のみ、独立=並列 / 依存=逐次を事前計画 → user に開示 |
| 4 | **TaskCreate 登録** | Agent 起動前後で必ず TaskCreate (`subject` / `description` / `metadata.subagent_id` / status 遷移) |
| 5 | **Bash deny 時の委譲反射** | deny / whitelist 不在 / block を **loop 停止理由にしない**、直ちに Agent 委譲で再試行 |
| 6 | **並列化義務** | 独立 sub-task 2 件以上は並列起動 default、1 統合は明示理由 (race / 共有 file / context budget / sequential) 必要 |
| 7 | **agent type 選定義務** | task description に応じた specialist agent_type を default (test→`test-automator` / refactor→`refactoring-specialist` 等)、`general-purpose` は不在時のみ |

### 機械強制 (要件 6 + 7) と bypass

`.claude/hooks/parallel-subagent-reminder.sh` (PreToolUse(Agent)) が soft warning。並列化対象 keyword: "実装" "fix" "refactor" "設計" "新設" "拡張" "改修"。除外: "reviewer" "review" "監査" "audit"。

| bypass 経路 | env |
|---|---|
| reminder 無効化 | `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false` |
| TTL 変更 | `HC_PARALLEL_SUBAGENT_TTL_SEC=<秒>` (default 300) |
| state dir 隔離 | `HC_PARALLEL_SUBAGENT_STATE_DIR=<path>` |
| 連続単発 streak batch 窓 (task-75) | `HC_PARALLEL_SUBAGENT_BATCH_WINDOW_SEC=<秒>` (default 5、near-ts batch 判定窓) |
| tier2 (強 reminder) 発火閾値 (task-75) | `HC_PARALLEL_SUBAGENT_STREAK_TIER2=<n>` (default 2、連続単発 streak) |
| tier3 (Workflow 誘導) 発火閾値 (task-75) | `HC_PARALLEL_SUBAGENT_STREAK_TIER3=<n>` (default 3、連続単発 streak) |
| agent type mapping override | `HC_AGENT_TYPE_KEYWORD_MAPPING=...` (改行区切り、advanced) |

### default mapping (要件 7、hook 内 SSoT、設定不要原則)

| keyword | 推奨 subagent_type |
|---|---|
| "smoke 拡張" / "test 追加" / "regression test" | `test-automator` |
| "refactor" / "関数分割" / "cleanup" | `refactoring-specialist` (or `refactor-cleaner`) |
| "build error" / "compile error" / "type error" | 言語別 `*-build-resolver` |
| "bash 品質" / "shellcheck" / "subshell" | `code-reviewer` |
| "設計レビュー" / "architecture review" | `architect-reviewer` |
| "セキュリティレビュー" / "OWASP" | `security-reviewer` (or `security-auditor`) |
| (specialized 不在) | `general-purpose` |

`harness-config.yml` 編集不要 (hook 内 hardcode 自動判定)、override は任意 (env `HC_AGENT_TYPE_KEYWORD_MAPPING`)。

> **要件 1-7 各論詳細 / 違反例 / heredoc 保護仕様 / 機械強制判定境界**: [development-process/delegation-requirements.md](../rules-details/development-process/delegation-requirements.md)
>
> **並列化義務 / agent type 選定の起源 (task-35 / task-34 実例)**: [development-process/parallelization-origin.md](../rules-details/development-process/parallelization-origin.md)

## 多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限 (必須、task-68)

観測バグ「1 アシスタントターンに散文 + 多数 (4-6) の複雑 (長文 / 引用符 / markup 風) tool_use を詰めると invoke/parameter タグ脱落 → 実行されず本文化 → 同 batch リトライ (loop)」(memory [[feedback_multi_tool_block_serialization_failure]]) の構造防止。**単発でも複雑 command で誘発する** (2026-06-01 task-69 で実証、下記 **単発複雑 command 回避** 行)。

| 規範 | 内容 |
|---|---|
| **3+ fan-out は Workflow** | 3 件以上の独立 subagent fan-out は `Workflow` ツール (決定論 orchestration) を default 検討。手書き N block は **2 件まで許容**、3 件以上は Workflow 提案 (user opt-in 要件のため「多数時は Workflow を提案」運用とセット) |
| **1 ターン tool block 上限** | 1 アシスタントターンに emit する tool_use は、**長 prompt (>5 行) を含む場合 最大 1〜2 件**。長 prompt は file 経由 (subagent に Read させる) で payload を軽くする (本 session task-67 で実証: `/tmp/*-instructions.md` に共通指示を書き subagent prompt を短縮) |
| **単発複雑 command 回避** (2026-06-01 task-69) | 単発 Bash でも **複数 `;`/`|` 連結 + grep の alternation (`A\|B\|C`) + 多数 quote + 日本語混在** の複雑 command は slip を誘発する。検証は **ad-hoc 複合 grep を inline で組まず、既存/専用 smoke script を 1 コマンド実行** するか、目的ごとに 1 command へ分割する。subagent staging 検証 ([[feedback_subagent_staging_mv_silent_fail]]) も専用 smoke or 単一 `grep -n <key> <file>` で行う |
| **前置き語禁止** | tool 呼び出しの前に `call` 等の前置き語を書かない (slip 残渣 `call` と混同を招く)。「tool 前に `call` と書くと antml: prefix が脱落する」は **誤診断** — `call` は破綻した invoke wrapper の残渣であって原因ではない |
| **enforcement** | 予防規範は advisory (BLOCK しない)。事後検出は `tool-call-slip-detector.sh` (Stop hook) が最終 assistant `.text` の slip 痕跡 (`^call$` / `<parameter name=` 等) を grep → `{"decision":"block"}` で次 turn 自己是正を注入 (Normal/Loop 両モード、bypass `ECC_TOOL_CALL_SLIP_OFF=1`)。設計: [`tool-call-slip-detector-hook.md`](../../docs/draft/tool-call-slip-detector-hook.md) |

> **起源 / research 根拠 (§11 F1-4 Programmatic Tool Calling 優位 / F2-4 ordering)**: [harness-design-fundamental-review.md](../../docs/draft/harness-design-fundamental-review.md) §3.1

## hook BLOCK/WARN/INFO 統一出力 (`lib/block-message.sh`、必須、task-94)

全 hook (PreToolUse × 5 / Stop × 1 / SubagentStop × 1) + self-doctor は `.claude/hooks/lib/block-message.sh` の 4 引数 API (`why` / `fix_one_liner` / `bypass_env` / `docs_link`) 経由で BLOCK / WARN / INFO を出力する。event 別 semantics ずれ (Stop 系 `{"decision":"block"}` の主 tool 停止阻止 semantic 誤発火等) を実装層で排除するため、BLOCK は event 別 3 variant に分割 (順序不変):

- **PreToolUse hook** → `emit_block_pretool` (JSON stdout `{decision:"block",...}` + stderr 4 行)
- **Stop hook** (`byproduct-discharge-guard.sh` 等) → `emit_block_stop` (stderr 4 行のみ、JSON stdout **非出力**)
- **SubagentStop hook** (`confidence-gate.sh`) → `emit_block_subagent` (JSON stdout + stderr 4 行)

`emit_warn` / `emit_info` は event 非依存 (stderr のみ)。file-top strict mode leak 防止 (subshell 関数化) + jq 不在時 printf JSON fallback で fail-open。exit code は caller が event / 現行 exit code semantics に基づき明示する (本 lib は exit を呼ばない)。詳細契約は [`docs/draft/lib-block-message-4args.md`](../../docs/draft/lib-block-message-4args.md) §3.1 / §3.5、smoke は [`.claude/tests/lib-block-message-smoke.sh`](../tests/lib-block-message-smoke.sh)。

## サブエージェント `.claude/` 編集の staging 戦略 (必須)

Claude Code permission system は subagent context での `.claude/` 配下への直接 `Write` / `Edit` / `Bash` heredoc redirect を **一律 denied** (sub-agent isolation)。メインからは通過。subagent 委譲時は `/tmp/<file>` に `Write` → `mv` で install する staging 戦略が必須。

> **強制プロンプト雛型 / 検出パターン (subagent 失敗時の即時切替) / 起源 / 再発検出時の昇格判定 (案 B / 案 C)**: [development-process/staging-strategy.md](../rules-details/development-process/staging-strategy.md)

## cross-repo write 例外 (agent 経路 deny / user manual 専用)

本 repo から外部 repo への **cross-repo write** は agent context (main / subagent / `worktree` 含む全経路) で **完全 denied**。`bash install.sh --update <target>` は **user manual (terminal) 実行のみ可能**。

二重制約: system-level sandbox (cross-repo Write 一律 deny、`dangerouslyDisableSandbox: true` 付き Bash も block) + harness-level `delegation-guard.sh`。`ECC_*_OVERRIDE` / `HC_*_ENABLED=false` は system-level には効かない。

- 3 リポ反映系 task は `bash install.sh --update <target>` を **user に手動依頼** が default
- 「sandbox deny で進められない」を loop 停止理由にしない

> **起源 (task-24 W1 実証 confidence 0.85) / 緩和 (task-42 4 リポ全件 agent 直接成功実証) / 将来追随窓口**: [development-process/cross-repo-write.md](../rules-details/development-process/cross-repo-write.md)

## サブエージェント完了サマリ (Confidence Gate / F3 必須)

subagent の **最後の assistant text** に **必ず `confidence: 0.X`** (0.0〜1.0) を含める。`confidence-gate.sh` (SubagentStop hook) が抽出し閾値 (既定 0.6) 未満は **block** ⚠️ preset aware (`feature_confidence_gate_enabled`、harness-dev では advisory)。

### 算出基準 (4 段階)

| レンジ | 状態 |
|---|---|
| 0.9 - 1.0 | 全条件を実測値で確認 (build / test / grep 生 log 引用可) |
| 0.7 - 0.8 | 主要条件確認、周辺は推定 (一部 grep 未実行など) |
| 0.5 - 0.6 | 実装完了だが検証浅い、未確認前提に依存 |
| 0.0 - 0.4 | 方針不明確、曖昧な仮実装 |

0.6 以上: `/finish-task` へ進める / 0.6 未満: block、検証追加 or 未解決事項明示 / 未記載: block。

### Bypass

| 方法 | スコープ | 痕跡 |
|---|---|---|
| `ECC_CONFIDENCE_GATE=off` | セッション全体 | env のみ |
| `HC_CONFIDENCE_REQUIRED=false` | セッション全体 | env のみ |
| `/gate-bypass confidence <reason>` | 次回 1 回のみ | `.claude/.confidence-gate-state/bypass.log` |

詳細: [`docs/CONFIDENCE-GATE.md`](../../docs/CONFIDENCE-GATE.md)。bypass 根拠は CLAUDE.md / docs/tasks/ に記録 (honor system)。

> **major subagent only block 仕様 (task #9) / 記載例 full**: [development-process/confidence-gate.md](../rules-details/development-process/confidence-gate.md)

## 並列 subagent cross-file 契約 (task-98)

並列 subagent が相互参照 file (例: `app.js` の render target ↔ `index.html` の DOM id、`api.ts` と `types.ts` の shape、`button.tsx` と `button.test.tsx` の props) を独立に実装すると、静的 grep smoke では単一 file 内存在確認のみで **file 間契約 (id / symbol / API 名)** の drift を捕捉できない (memory `feedback_parallel_subagent_cross_file_contract_drift` の task-63 実証: `main-panel` ↔ `view-container` id mismatch で UI 全体非描画)。

### 契約 SSoT 事前明示 (必須)

並列 subagent 委譲時、以下の共有契約はメイン prompt で **事前に SSoT を明示**する:

- **DOM id / class 名** — subagent が生成する HTML/JSX の id と consumer が参照する id
- **symbol / 変数名** — module 間で export/import する identifier
- **API 名 / endpoint / shape** — client と server の契約
- **event 名 / message type** — publisher と subscriber の契約

任意で `.claude/contracts/<slug>.yml` に yml 化した契約を置き、`cross-file-contract-check.sh --file <path>` で assert 可能。

### 機械強制 (advisory)

`.claude/hooks/ui-contract.sh` (PostToolUse Edit|Write、`feature_ui_contract_enabled`) が UI 拡張子 (`.tsx` / `.jsx` / `.vue` / `.svelte` / `.html` / `.css` / `.scss`) を検出時、`.claude/scripts/cross-file-contract-check.sh` を呼出し drift を stderr WARN 注入する (BLOCK しない advisory、fail-open)。`/finish-task` は UI 変更含 task で `docs/tasks/<task>-visual-*.png` (or bypass log) を検証 (採用 6 条 4「UI 含 task = E2E + visual 必須」の機械強制)。

| bypass 経路 | env |
|---|---|
| hook 全停止 | `HC_FEATURE_UI_CONTRACT_ENABLED=false` (config) |
| 1 セッション OFF | `ECC_UI_CONTRACT_OFF=1` (env、bypass.log 記録) |
| UI 拡張子 override | `HC_UI_CONTRACT_EXTENSIONS=".tsx,.jsx"` (default 7 種) |

## Observability (task-99、hook 発火・BLOCK・bypass・silent failure の構造化 log)

silent failure と死蔵 hook を機械可視化するため、全 hook (PreToolUse × 5 / Stop × 1 / SubagentStop × 1) + self-doctor + smoke runner は `.claude/hooks/lib/observability.sh` を source し 5 API 経由で `observations.jsonl` に構造化 log を append する。

### 5 API (event_kind ごとの semantics)

| API | event_kind | 用途 |
|---|---|---|
| `log_fire <hook_name> <reason> [payload]` | `fire` | hook が実行された事実 (BLOCK 有無関わらず) |
| `log_block <hook_name> <reason> [payload]` | `block` | BLOCK 判定を下した事実 (exit 2 / decision block) |
| `log_bypass <hook_name> <env_var> <reason> [payload]` | `bypass` | bypass env で BLOCK 回避した事実 (bypass-logger.sh 3-arg 互換 superset) |
| `log_silent_failure <hook_name> <reason> [payload]` | `silent_failure` | 想定外の内部エラー (jq 不在 / write 失敗等、hook を止めずに log) |
| `log_event <event_kind> <hook_name> <reason> [payload]` | 任意 | 上記に該当しない custom event |

### GC + audit

- **30 日 GC**: `bash .claude/scripts/observability-gc.sh --apply` で 30 日超えを `.claude/observability/archive/YYYY-MM.jsonl` に移動 (`--dry-run` で候補一覧)。
- **fire 0 回検出**: `bash .claude/scripts/hook-fire-audit.sh --days 30` で最終 30 日 fire 0 回 hook を JSON / table 出力 → 死蔵 hook 棚卸しの数値根拠。

### 実装規範

- `file-top に set -euo pipefail を書かない` (feedback_set_e_in_sourced_libs、caller shell への leak 防止)
- 各関数 body は `subshell ( set -uo pipefail; ... )` で局所化
- jq 不在時は printf JSON literal escape で fallback
- write 失敗は silent skip (fail-open、hook 本体を止めない)

### bypass

| 経路 | env | 効果 |
|---|---|---|
| hook 全 log_* を no-op 化 | `HC_FEATURE_OBSERVABILITY_ENABLED=false` | observations.jsonl への append 停止 |
| log path 明示上書き | `HC_OBSERVABILITY_LOG_PATH=<abs path>` | test isolation / cross-repo 集約用 |

## 指摘対応

1. 根本原因を特定する
2. 修正する
3. 再発防止策を考える
4. `.claude/rules/` へのルール追加を提案する

## タスク管理 (メイン専任)

詳細は [`task-management.md`](./task-management.md) §「メインエージェント専任（必須）」を参照。

## harness 取込チェックリスト (proactive sync、consuming repo 必須)

consuming repo は **proactive に harness 最新版を取り込む** 義務を持つ。

### 取込タイミング (4 経路、いずれかが trigger)

| # | trigger | 必須/推奨 |
|---|---|---|
| 1 | **stg* / main merge の直前** | **必須** |
| 2 | **定期 sync** (週次、曜日固定推奨) | 推奨 |
| 3 | **F WARN 検出時** (`stale-harness-detect.sh` が SessionStart で npm registry 最新版と `harness_npm_version` stamp を比較 → 新版検出で `npx @takuma-hirai/hirai-method@latest update <dir>` を WARN 誘導 → 即実行、task-84) | **必須** |
| 4 | **重大 fix 通知時** (hirai-method release notes / commit log 監視) | 任意 |

### 取込手順 5 step

1. `git checkout main && git pull origin main` (clone 経路の場合。**npx 経路なら本 step 不要**)
2. harness を target に反映。2 経路いずれか (cross-repo write は agent 経路 deny のため **どちらも user manual / terminal 実行のみ**):
   - **clone 経路**: `bash install.sh --update <consuming repo absolute path>`
   - **npx 経路 (task-83)**: `npx @takuma-hirai/hirai-method@latest update <consuming repo absolute path>` (clone 不要、registry から最新取得。事前に `npx @takuma-hirai/hirai-method@latest check` で stale 確認可)
3. consuming repo で `git status` / `git diff`
4. `chore: sync .claude/ from hirai-method <YYYY-MM-DD>` で分離 commit (`install.sh --update --commit` flag で自動 commit 可)
5. consuming repo 側の smoke / test 再実行

### 取込後検証

- [ ] `.claude/CommonRules.md` の harness_version が最新 stamp
- [ ] consuming repo SessionStart で stale-harness-detect WARN 消去
- [ ] 既存 smoke / test 全 PASS

### bypass

| 経路 | env | スコープ |
|---|---|---|
| 意図的旧 harness 稼働継続 | `harness-config.yml` の `feature_stale_harness_detect_enabled: false` | 永続 |
| 一時抑制 | `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false` | 1 セッション |

> **CI 自動化 (将来 opt-in 案 B) / 前提 task 連携詳細 / F WARN 案内文の grep 検証経緯**: [development-process/harness-sync.md](../rules-details/development-process/harness-sync.md)

---

## 副産物発生時の即時 draft 起こし義務 (必須・再発防止)

タスク実装中・レビュー中に「これは別 task として管理すべき」と判断した副産物 (byproduct) は **memory / 会話履歴に流すだけでは禁止**。必ず以下フロー:

1. **即時記録**: `docs/tasks/next-actions.md` に entry 追加 (緊急度 / 推奨処理を明記)
2. **当セッション内に draft 起こし**: 緊急度 🔴 / 🟡 entry は当セッション中に `/new-draft <slug>` で draft 起こし
3. **次セッション or 同セッション内に承認 + tasking**: user 承認後に `/new-task <id> <slug>` で list.md 行追加
4. **next-actions.md の処理結果列に移行先記入** (例: 「→ `docs/draft/<slug>.md` → task #N」)

### 違反パターン (絶対禁止)

- 副産物を memory にのみ保存して draft 化しない
- 「次セッションで対応」とコメントだけ残してセッション終了
- 発生源 task の `/finish-task` 完了前に処理せず後送り

### 強制機構 (実装予定)

- `next-actions-surface.sh` (SessionStart): 未処理 entry を毎セッション開始時に `<system-reminder>` で stderr 出力
- `workflow-guard.sh` (PreToolUse Bash `/finish-task`): next-actions.md 関連 entry 未処理なら BLOCK ⚠️ preset aware (`feature_byproduct_discharge_enabled`、harness-dev では advisory、現 effective 状態は `bash .claude/scripts/hc-config.sh --summary` 参照)

詳細は [`workflow.md`](./workflow.md) + [`docs/draft/byproduct-discharge-mechanism.md`](../../docs/draft/byproduct-discharge-mechanism.md) 参照。

## 設計→承認→タスク追加フロー

詳細は [`task-management.md`](./task-management.md) §「設計→承認→タスク追加フロー（必須）」を参照。

## Parking Lot (保留タスク)

詳細は [`task-management.md`](./task-management.md) §「Parking Lot（今後検討タスク）」を参照。

> **各規範の起源 / commit hash / 採用判断 (TDD / 委譲必須要件 7 件 / staging / cross-repo / Confidence Gate F3 / harness 取込)**: [development-process/origin.md](../rules-details/development-process/origin.md)

---
> **project 固有の追補・override は `.claude/project-rules/development-process.md` に書く** (本 file は harness 所有、`install.sh --update` で上書きされる。project 固有編集は下記 import 先へ)。
@../project-rules/development-process.md
