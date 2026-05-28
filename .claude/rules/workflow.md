---
paths:
  - "docs/draft/**"
  - "docs/tasks/**"
  - ".claude/commands/**"
  - ".claude/hooks/workflow-guard.sh"
  - ".claude/.workflow-state/**"
---

# Workflow Enforcement — 設計レビュー fan-out / テスト設計 MECE / 新規・修正 workflow / リファクタリング強制

本ルールは [`development-process.md`](./development-process.md) の **後段** に位置する「品質保証 orchestration」レイヤを定義する。タスク化以降の **何を / どの順で / どこで止めるか** を W1〜W4 hook で構造強制し、reviewer 偏り / テスト観点抜け / phase skip / refactor 未実施のまま完了を防ぐ。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: [workflow.details.md](../rules-details/workflow.details.md)

## 概要

- **テスト設計 MECE** (W1): テスト観点を 20 カテゴリ MECE で user 判断強制
- **設計レビュー fan-out** (W2): `reviewer-registry` を並列起動して観点漏れを防ぐ
- **モジュール / システムレビュー** (W3): TDD 完了直後と全体統合後の 2 段リファクタリング強制
- **14 / 10 stage workflow** (W4): 新規 14-stage / 修正 10-stage を `workflow-guard.sh` で `/finish-task` 段で検証

## 関連 command 一覧

| command | 役割 | Wave |
|---|---|:---:|
| [`/test-design <slug>`](../commands/test-design.md) | 設計 draft から MECE 20 カテゴリのテストカタログ生成 + user スコープ承認 | W1 |
| [`/design-review <slug>`](../commands/design-review.md) | `reviewer_registry_design` + `_security` を並列起動して fan-out レビュー | W2 |
| [`/module-review <module>`](../commands/module-review.md) | TDD 完了直後に 3 観点レビュー (持続可能性 / 汎用性 / 非冗長化) | W3 |
| [`/system-review`](../commands/system-review.md) | 全モジュール統合後にモジュール間重複 / 設計乖離検出 | W3 |
| [`/new-feature <slug>`](../commands/new-feature.md) | 新規機能 14-stage workflow orchestrator | W4 |
| [`/modify-feature <slug>`](../commands/modify-feature.md) | 既存機能修正 10-stage workflow orchestrator | W4 |
| [`/finish-task <id>`](../commands/finish-task.md) | 完了クローズ。`workflow-guard.sh` が state JSON を検証して BLOCK | W4 |

## 新規機能開発フロー (14-stage)

`/new-feature <slug>` で起動。`harness-config.yml` の `workflow_stages_new` (= env `HC_WORKFLOW_STAGES_NEW`) と完全一致する 14 stage を順次進める。

| # | stage 名 | 役割 | 起動 command / 連携 |
|---:|---|---|---|
| 1 | `requirements` | WHAT / WHY 確定 + draft §1 | `/new-draft <slug>` |
| 2 | `basic-design` | 解決アプローチ比較 + draft §2 | architect agent |
| 3 | `detailed-design` | API / データモデル / UI / DB schema を draft §3 | code-architect agent |
| 4 | `test-design` | MECE 20 カテゴリのテストカタログ + user スコープ承認 | `/test-design <slug>` |
| 5 | `design-review` | reviewer-registry design + security を並列起動して fan-out | `/design-review <slug>` |
| 6 | `user-approval` | draft §8 承認履歴に user 承認エントリ追加 (必須、Loop モードでも) | user 対話 |
| 7 | `task-creation` | `/new-task` + `.claude/.workflow-state/<slug>.json` 初期化 | `/new-task <id> <slug>` |
| 8 | `tdd` | RED → GREEN → REFACTOR (subagent 経由のみ)。**Task 最終 3 Steps = テスト設計レビュー → テスト合格 → リファクタリング (固定)** ([task-management.md §タスク構造規範](./task-management.md) 採用 6 条 4) | `/start-task <id>` |
| 9 | `module-review` | モジュール毎に 3 観点レビュー | `/module-review <module>` |
| 10 | `local-test` | `<slug>.test-design.md` ☑ カテゴリ全実行 + Step 完了条件で検証 | subagent test runner |
| 11 | `system-review` | 全モジュール統合後に重複 / 設計乖離検出 | `/system-review --slug <slug>` |
| 12 | `ci-cd` | `.github/workflows/` 更新 (skip 可) | — |
| 13 | `scenario-test` | E2E / シナリオ実行 (UI 変更含む Task は E2E 必須、検出基準: [task-management.md §UI 変更検出基準](./task-management.md)) | e2e-runner agent |
| 14 | `finish` | `/finish-task` で完了クローズ。**workflow-guard.sh が state JSON 検証** | `/finish-task <id>` |

各 stage 完了時、メインが `.claude/.workflow-state/<slug>.json` の `current_stage` を次 stage に進め、`completed_stages` に追加。state JSON は Stage 7 で初期化 (Stage 1〜6 完了済として列挙)。stage 名の SSoT は env `HC_WORKFLOW_STAGES_NEW`。

> **Stage 8 TDD の git log 既存 commit 確認義務 / 各 stage 連携 command 詳細**: [workflow.details.md §14-stage 詳細](../rules-details/workflow.details.md#14-stage-詳細)

## 既存機能修正フロー (10-stage)

`/modify-feature <slug>` で起動。`harness-config.yml` の `workflow_stages_modify` (= env `HC_WORKFLOW_STAGES_MODIFY`) と完全一致する 10 stage を順次進める。

| # | stage 名 | 役割 | 起動 command / 連携 |
|---:|---|---|---|
| 1 | `branch-decision` | 影響範囲特定 + branch type (`feat`/`fix`/`refactor`/`hotfix`) 決定 | user 対話 |
| 2 | `checkout` | branch 切替 (regex 検証: git-workflow.md 規約準拠) | `git switch` |
| 3 | `recover-design` | 既存 task / draft 探索、不完全なら逆引きで draft 起こし | Glob + Read |
| 4 | `pre-test` | **修正前** 全テスト PASS を baseline 記録 (regression 検出基準) | test runner |
| 5 | `redesign` | draft §3 に「変更前 / 変更後」差分追記 | architect agent |
| 6 | `retest-design` | `/test-design` 再実行で差分部 MECE 再評価 | `/test-design <slug>` |
| 7 | `tdd` | 新規 test → 最小修正 → refactor (subagent 経由) | TDD ループ |
| 8 | `module-review` | モジュール毎に 3 観点レビュー | `/module-review <module>` |
| 9 | `full-test` | 全 test PASS + pre-test baseline regression 検出 | test runner |
| 10 | `system-review` | 全体整合性レビュー → merge 可否判断 → `/finish-task` 案内 | `/system-review` |

`/new-feature` との主要差分: 要件定義 / `design-review` / `task-creation` / `ci-cd` / `scenario-test` は省略され、代わりに `recover-design` / `pre-test` / `retest-design` が入る。

> **詳細比較 / Stage 7 TDD git log 検証**: [workflow.details.md §10-stage 詳細](../rules-details/workflow.details.md#10-stage-詳細) + [`modify-feature.md`](../commands/modify-feature.md)

## workflow-guard.sh による強制機構

`.claude/hooks/workflow-guard.sh` は **PreToolUse(Bash)** で `/finish-task <slug>` 実行直前に発火。

### 判定ロジック (構造化 JSON 解析、grep 依存禁止)

1. `tool_name == "Bash"` で `command` に `/finish-task <slug>` パターン (`^[a-z0-9][a-z0-9-]{2,48}$`) 検出
2. `.claude/.workflow-state/<slug>.json` 読み (不在なら旧 task 互換で silent pass)
3. `workflow_type` から stage 列を解決
4. **判定 A**: `current_stage` が stage 列の **最終要素** (new=`finish` / modify=`system-review`)
5. **判定 B**: `pending_findings.module_review` と `pending_findings.system_review` が **両方とも空配列**
6. A / B いずれか fail なら **exit 2 (BLOCK)** + stderr に「問題」「推奨アクション」「bypass 手順」出力

stage 名で判定する設計 (round-2 arch-rev H3 反映、step 番号や順序判定ではない)。

### state JSON schema

`.claude/.workflow-state/<slug>.json` 構造定義は [`SCHEMA.md`](../.workflow-state/SCHEMA.md) が SSoT。主要 field:

| Field | 型 | 説明 |
|---|---|---|
| `slug` | string | 機能識別子。ファイル名と一致 |
| `workflow_type` | `"new" \| "modify"` | どちらの workflow か |
| `current_stage` | string | 現在進行中の stage 名 |
| `completed_stages` | string[] | 完了済 stage の配列 (順序保持) |
| `pending_findings` | object | `module_review` / `system_review` の未解決 findings 配列 |
| `skip_log` | object[] | skip された stage の audit |
| `created_at` / `updated_at` | ISO-8601 UTC | timestamp (秒精度、`Z` suffix) |

state JSON 本体 (`<slug>.json`) は `.gitignore` で除外、`SCHEMA.md` / `bypass.log` / `bypass.log.template` のみ git track。

## Bypass と audit

### bypass 経路

| 方法 | 系統 | スコープ | 痕跡 |
|---|---|---|---|
| `ECC_WORKFLOW_GUARD_OFF=1` | env 系統 | 1 セッション | `.claude/.workflow-state/bypass.log` に append |
| `HC_WORKFLOW_GUARD_ENABLED=false` | config 系統 | 1 セッション | 同上 |
| `ECC_BYPASS_REASON='<reason>'` | 補助 | bypass 1 回分の理由を log 列に記録 | bypass.log の最終列 |

両系統併存は round-2 sec-rev H3 反映 (env と config から独立に bypass 可能、片方が誤って enabled なまま放置される事故を防ぐ)。

### bypass.log 集計

`.claude/.workflow-state/bypass.log` は `lib/bypass-logger.sh` 経由で統一フォーマット (`<ISO-8601> | <session_id> | <hook_name> | <env_var> | <reason>`) で append。`harness-audit.py` の `bypass_log_summary()` が集計し `/harness-audit` で最近 N 日の bypass を表示。

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ にも記録 (env 系統だけだと持続的トレース不能)。

## draft-flow-guard.sh による docs/ 直下 block (2026-05-28 緩和後)

`.claude/hooks/draft-flow-guard.sh` は **PreToolUse(Edit/Write)** で `docs/` 直下の新規設計文書 Write を BLOCK。

### 監視対象 path

| # | path pattern | 動作 |
|---|---|---|
| 1 | `<root>/docs/<basename>.md` (深さ 1) | 対応 `docs/draft/<basename>.md` 不在で **BLOCK** (元機能、不変) |
| — | `<root>/.claude/rules/<basename>.md` 等 (旧 task-40 拡張) | **監視対象外 (2026-05-28 緩和で撤廃)** — 新規 Write / Edit とも PASS |

### bypass 経路

| 方法 | 系統 | スコープ | 痕跡 |
|---|---|---|---|
| `ECC_DRAFT_FLOW_GUARD_OVERRIDE=1` | env 系統 (docs/ block を skip) | 1 セッション | `bypass.log` に append |
| `HC_DOCS_APPROVED_DIR=<dir>[,<dir>...]` | config 系統 | 1 セッション | (記録なし) |
| `ECC_RULE_CHANGE_GUARD_OFF=1` / `HC_RULE_CHANGE_GUARD_ENABLED=false` | (旧 task-40 用、緩和で **dead path**) | — | hook 参照なし (後方互換で set しても無害) |

honor system: bypass 根拠は `docs/tasks/<task-N>.md` の該当 entry に記録。

> **2026-05-28 緩和の経緯 (task-40 拡張撤廃) / frontmatter parser 削除詳細 / 関連 rule**: [workflow.details.md §draft-flow-guard 緩和履歴](../rules-details/workflow.details.md#draft-flow-guard-緩和履歴)

## リファクタリング強制 (W3)

`/module-review` と `/system-review` は workflow の **必須 stage**、skip は default 禁止 (workflow-guard.sh が `/finish-task` で BLOCK)。

### 3 観点 (`/module-review`)

1. **持続可能性 (Sustainability)** — 命名 / 関数 50 行以内 / ファイル 800 行以内 / ネスト 4 階層以内 / magic number 排除 / 副作用局所化 / 型注釈 / silent failure 排除
2. **汎用性 (Generality)** — 引数化可能性 / 1 callee 特化排除 / idiom 準拠 / 抽象依存 / test seam
3. **非冗長化 (Deduplication)** — DRY / table-driven 化 / util/helper 再発明排除 / 既存型流用 / over-engineering 排除 (YAGNI)

### system-level 観点 (`/system-review`)

3 観点に加え、system 全体で:

1. **モジュール間重複** — module 横断 DRY (`/module-review` は module 内 DRY のみ)
2. **横断的責務漏れ** — logging / error handling / observability / rate limiting / authn-authz の一貫性
3. **設計乖離** — `docs/draft/<slug>.md` §3 採用案からの逸脱 / `<slug>.test-design.md` ☒ テストが誤実装されていないか / §6 DoD 充足

### pending_findings 連携

CRITICAL / HIGH findings は state JSON の `pending_findings.module_review` / `pending_findings.system_review` 配列 (id / severity / summary) に追加。**CRITICAL / HIGH 残存中は `workflow-guard.sh` が `/finish-task` を BLOCK**。MEDIUM / LOW のみ残存は user 承認のうえ `skip_log` 記録で pass 可。

**yml 値による制御**: `/module-review` は `review_required_module` / `review_min_count_module` (default 2) / `review_max_count_module` (default 5)、`/system-review` は `review_required_system` / `review_min_count_system` / `review_max_count_system`。`review_iteration_max` (default 5) は全レビュー共通。`hc-config.sh --set review_required_module=false` で局所無効化可。

> **review prompt 規約 (behavior-preserving / 末尾 confidence:0.X) / Layer 詳細 sub-checklist**: [workflow.details.md §リファクタリング 3 観点詳細](../rules-details/workflow.details.md#リファクタリング-3-観点詳細) + [`module-review.md`](../commands/module-review.md) Phase 3

## テスト設計の MECE 強制 (W1)

`/test-design <slug>` は承認済 draft (`docs/draft/<slug>.md`) を読み、`_TEST_DESIGN_TEMPLATE.md` から **MECE 20 カテゴリ** のテストカタログを `docs/draft/<slug>.test-design.md` に生成。

### 20 MECE カテゴリ

単体 / 統合 / E2E / DB / 境界値 / 異常系 / 回帰 / カバレッジ計測 / 網羅性検証 / 完全性検証 / 性能 (レスポンスタイム) / 負荷 / セキュリティ / 互換性 / アクセシビリティ / i18n / smoke / シナリオ / chaos・障害注入 / 契約テスト の 20 カテゴリ。

### user スコープ承認の強制

各カテゴリは user が **採用 (☑) / 不採用 (☒)** を全行決定。不採用には必ず理由を 4 種から選ぶ:

- `scope-excluded` — タスクスコープ外
- `not-applicable` — 機能特性上不要
- `existing-coverage` — 既存テストで網羅済
- `accepted-risk` — リスク受容 (user 承認)

W4 実装後、`/new-task` は本 user 判断が未確認の場合 BLOCK (workflow-guard.sh の Stage 4 検証)。

並列起動 agent: `tdd-guide` / `test-automator` / `qa-expert` (`reviewer_registry_test` カテゴリ)。3 agent 中 2 以上が採用推奨ならデフォルト ☑、2 以上が不採用なら ☒、意見割れなら ☐ + コメント「user 判断要」。

**yml 値による制御**: `review_required_test` / `review_min_count_test` (default 5、採用 6 条 4 起源) / `review_max_count_test` (default 10) / `review_iteration_max` (default 5) で集中制御。

> **20 MECE カテゴリ各論 (採用 / 不採用判定例)**: [workflow.details.md §20 MECE 各論](../rules-details/workflow.details.md#20-mece-各論) + [`_TEST_DESIGN_TEMPLATE.md`](../templates/docs/draft/_TEST_DESIGN_TEMPLATE.md)

## 設計レビューの fan-out (W2)

`/design-review <slug>` は `reviewer_registry_design` + `reviewer_registry_security` カテゴリ登録 agent を **並列起動** (`run_in_background: true` 必須) し、findings を `docs/draft/<slug>-review.md` に集約。

### reviewer-registry (`harness-config.yml`)

| キー | 起動対象 agent | 用途 |
|---|---|---|
| `reviewer_registry_design` | architect / architect-reviewer / code-architect / api-designer / ui-designer / database-reviewer / harness-optimizer | W2 `/design-review` |
| `reviewer_registry_security` | security-auditor / security-reviewer / penetration-tester | W2 `/design-review` |
| `reviewer_registry_test` | tdd-guide / test-automator / qa-expert / pr-test-analyzer | W1 `/test-design` |
| `reviewer_registry_impl` | code-reviewer / refactoring-specialist / 言語別 reviewer 群 | W3 `/module-review` `/system-review` |

env 上書き例: `export HC_REVIEWER_REGISTRY_DESIGN=$'architect\narchitect-reviewer'` (改行区切り) で cost 制御可。

**並列数 / 反復制御**: `review_required_design` (default true) / `review_min_count_design` (default 3) / `review_max_count_design` (default 7) / `review_iteration_max` (default 5) で制御。`hc-config.sh --get review_min_count_design` で現在値確認、`--set` で変更 (atomic backup)。

### 収束条件 (反復ループ)

draft レビューは「修正 → 再レビュー」を **CRITICAL + HIGH + MEDIUM = 0** になるまで反復 (LOW は許容、cosmetic finding として記録のみ)。

| 規約 | 内容 |
|---|---|
| **reviewer 最低数** | **3 体以上** 並列起動 (default は reviewer-registry 全件 + stack heuristic 絞り込み、`N ≥ 3` 必須、不足で user escalation) |
| **件数取得 severity** | CRITICAL / HIGH / MEDIUM / LOW の 4 段階 |
| **収束条件** | CRITICAL = 0 ∧ HIGH = 0 ∧ MEDIUM = 0 (LOW は許容) |
| **反復上限** | 5 回 (default、超過時 user escalation) |
| **iteration 記録** | 各 iter の reviewer / 件数 / 修正 commit hash を draft §「レビューサイクル」table に append |
| **bypass** | `ECC_DESIGN_REVIEW_OFF=1` (反復 5 回上限超過時の user escalation 後の継続用) |

CRITICAL / HIGH / MEDIUM 全て 0 件 → draft「承認待ち」へ遷移可、1 件以上 → 「修正待ち」状態を明示し draft 修正 → 再 `/design-review` で round-N+1 review。

> **stack heuristic 絞り込みロジック詳細 (database / API / UI 検出) / 集約フォーマット**: [workflow.details.md §fan-out reviewer-registry 詳細](../rules-details/workflow.details.md#fan-out-reviewer-registry-詳細)

## 副産物 discharge (5 層強制機構)

タスク実装中・レビュー中・セッション中に発生した「副産物 (byproduct)」を **物理的に消えない設計** で管理。詳細は [`development-process.md`](./development-process.md) §「副産物発生時の即時 draft 起こし義務」参照。

### 5 層強制機構

| 層 | 機構 | 発火 | 動作 |
|---|---|---|---|
| 1 | `docs/tasks/next-actions.md` registry | 副産物発見時にメインが entry 追加 | informal な「TODO / 次アクション候補」を捕捉する公式 location |
| 2 | `_TASK_TEMPLATE.md` 派生 task セクション | task 実装中・完了時 | 発生源 task に「派生 task / 次アクション候補」を明示記録 |
| 3 | `next-actions-surface.sh` (SessionStart) | 毎セッション開始 | 未処理 entry を `<system-reminder>` で stderr 強制提示 (緊急度 🔴 強調) |
| 4 | `byproduct-discharge-guard.sh` (Stop) | セッション終了時 | 🔴 未処理 entry 残存なら exit 2 で BLOCK + bypass.log 記録 |
| 5 | `/discharge-byproduct` | user 任意 | entry → draft / parking-lot / 無視 の移行 helper |

### bypass

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| surface 無効化 | `ECC_NEXT_ACTIONS_SURFACE_OFF=1` | 1 セッション | bypass.log |
| discharge-guard 無効化 | `ECC_BYPASS_DISCHARGE_GUARD=1` | 1 セッション | bypass.log (session_id + reason) |

honor system: bypass 時は理由を `docs/tasks/next-actions.md` 当該 entry のコメント列に記録。

> **処理フロー (entry → draft / parking-lot / 無視 の判定) / 関連 artifact**: [workflow.details.md §副産物 discharge 詳細](../rules-details/workflow.details.md#副産物-discharge-詳細)

## Loop モード自律規律

詳細は [`modes.md`](./modes.md) §「Loop モード自律規律の 5 層強制機構」を参照。subagent 並走中の独立作業義務 (modes.md 遵守事項 7) と自律実行禁止 11 カテゴリ (同 8) を 5 層強制機構 (規範 / reminder hook / action-guard hook / settings 配線 / smoke) で構造防止。bypass 経路と関連 artifact も modes.md 側に集約。

## Session 永続化と PM Orchestration

`/sc:save` `/sc:load` `/sc:pm` (SuperClaude plugin) を `.claude/` 単独で portable な自前実装に置換。Serena MCP 必須化 + SessionStart resume prompt + PDCA cycle memory 永続化を統合。

### 自前 command

| command | 役割 | 主要 Serena tool |
|---|---|---|
| [`/save-state`](../commands/save-state.md) | session 状態を Serena memory に snapshot 保存 | `write_memory` |
| [`/resume-state`](../commands/resume-state.md) | 前 session 状態を Serena memory から復元 | `list_memories` / `read_memory` |
| [`/pm-start`](../commands/pm-start.md) | PM Agent orchestration + PDCA cycle 永続化 | 全 memory API |

### memory key schema

- `session/context` — 完全 snapshot (TaskList / commits / artifact / 次アクション)
- `session/last` — 1-2 段落要約
- `session/checkpoint` — 進捗 checkpoint
- `plan/<feature>/{hypothesis,architecture,rationale}` (PDCA Plan)
- `execution/<feature>/{do,errors,solutions}` (PDCA Do)
- `evaluation/<feature>/{check,metrics,lessons}` (PDCA Check)
- `learning/{patterns,solutions,mistakes}/<name>` (PDCA Act)
- `project/{context,architecture,conventions}` (project 全体理解)

### Serena 必須化

各 command の Phase 1 で `mcp__serena__activate_project` を必須実行し、戻り値 error に `onboarding` / `not performed` を含む場合は onboarding 未済と判定して graceful error で `/onboarding` 案内 + 終了。

### SessionStart 自動 resume

`mode-session-start.sh` が `.serena/memories/session/context.md` 存在時に `<system-reminder>` で `/resume-state` 提案を自動注入 (W2)。手動入力不要で前 session からの継続が可能。

> **Serena 必須化の設計補足 (旧 check_onboarding_performed tool 不在経緯) / 関連 artifact 完全 list**: [workflow.details.md §Session 永続化詳細](../rules-details/workflow.details.md#session-永続化詳細)

## 関連ルール / skill (代表)

- [`development-process.md`](./development-process.md) — TDD / サブエージェント委譲 / タスク管理 (本ルールの前段)
- [`task-management.md`](./task-management.md) — タスク管理メイン専任 / Parking Lot 運用 / 採用 6 条
- [`self-improvement.md`](./self-improvement.md) — L1〜L5 + F1/F2 (本ルールの W は F2 verification-loop と相補)
- [`modes.md`](./modes.md) — Normal / Loop モード (`user-approval` Stage 6 は例外)
- [`git-workflow.md`](./git-workflow.md) — branch 命名規約 (`/modify-feature` Stage 2 `checkout` の検証基準)
- state schema: [`.workflow-state/SCHEMA.md`](../.workflow-state/SCHEMA.md)

> **全 skill / 設計 draft 完全 list**: [workflow.details.md §関連 skill 完全](../rules-details/workflow.details.md#関連-skill-完全)
