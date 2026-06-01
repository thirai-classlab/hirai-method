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
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。各 § 末尾の pointer から該当断片を直リンクで明示 Read する (断片群: [`../rules-details/workflow/`](../rules-details/workflow/))。

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

`/new-feature <slug>` で起動。`requirements` → `basic-design` → `detailed-design` → `test-design` → `design-review` → `user-approval` → `task-creation` → `tdd` → `module-review` → `local-test` → `system-review` → `ci-cd` → `scenario-test` → `finish` の 14 stage を順次進める。stage 名の SSoT は env `HC_WORKFLOW_STAGES_NEW` (= `harness-config.yml` の `workflow_stages_new`)。各 stage 完了時にメインが state JSON の `current_stage` を進める (Stage 7 で初期化)。

> **14-stage full 表 (役割 / 起動 command) + Stage 8 TDD git log 確認義務 / Stage 10 完了条件検証 / Stage 13 UI 必須化 / Stage 12 ci-cd skip 条件**: [workflow/14-stage.md](../rules-details/workflow/14-stage.md)

## 既存機能修正フロー (10-stage)

`/modify-feature <slug>` で起動。`branch-decision` → `checkout` → `recover-design` → `pre-test` → `redesign` → `retest-design` → `tdd` → `module-review` → `full-test` → `system-review` の 10 stage を順次進める。stage 名の SSoT は env `HC_WORKFLOW_STAGES_MODIFY`。`/new-feature` との差分: 要件定義 / `design-review` / `task-creation` / `ci-cd` / `scenario-test` を省略し、`recover-design` / `pre-test` / `retest-design` を追加。

> **10-stage full 表 + Stage 7 TDD git log 検証 / `/new-feature` との差分詳細**: [workflow/10-stage.md](../rules-details/workflow/10-stage.md) + [`modify-feature.md`](../commands/modify-feature.md)

## workflow-guard.sh による強制機構

`.claude/hooks/workflow-guard.sh` は **PreToolUse(Bash)** で `/finish-task <slug>` 実行直前に発火し、構造化 JSON 解析で 2 判定 (A: `current_stage` が stage 列の最終要素か / B: `pending_findings.module_review` と `system_review` が両方空配列か) を行い、いずれか fail で **exit 2 (BLOCK)** + stderr に「問題 / 推奨アクション / bypass 手順」出力。stage 名で判定 (step 番号 / 順序判定ではない)。state JSON 構造定義は [`SCHEMA.md`](../.workflow-state/SCHEMA.md) が SSoT。

> **判定ロジック詳細手順 (1〜6) / state JSON schema field 表 (型・説明) / bypass.log 集計補足**: [workflow/workflow-guard.md](../rules-details/workflow/workflow-guard.md)

## Bypass と audit

| 方法 | 系統 | スコープ | 痕跡 |
|---|---|---|---|
| `ECC_WORKFLOW_GUARD_OFF=1` | env 系統 | 1 セッション | `bypass.log` に append |
| `HC_WORKFLOW_GUARD_ENABLED=false` | config 系統 | 1 セッション | 同上 |
| `ECC_BYPASS_REASON='<reason>'` | 補助 | bypass 1 回分の理由を log 列に記録 | bypass.log の最終列 |

両系統併存は env と config から独立に bypass 可能とし、片方が誤って enabled なまま放置される事故を防ぐ。`.claude/.workflow-state/bypass.log` は `lib/bypass-logger.sh` 経由で統一フォーマット (`<ISO-8601> | <session_id> | <hook_name> | <env_var> | <reason>`) で append、`harness-audit.py` の `bypass_log_summary()` が `/harness-audit` で最近 N 日分を集計表示。honor system: bypass 根拠は CLAUDE.md / docs/tasks/ にも記録 (env 系統だけだと持続的トレース不能)。

## draft-flow-guard.sh による docs/ 直下 block (2026-05-28 緩和後)

`.claude/hooks/draft-flow-guard.sh` は **PreToolUse(Edit/Write)** で `docs/` 直下 (深さ 1) の新規設計文書 Write を、対応 `docs/draft/<basename>.md` 不在で **BLOCK**。`.claude/rules/` 等への新規 Write / Edit は 2026-05-28 緩和で監視対象外 (旧 task-40 拡張撤廃、`ECC_RULE_CHANGE_GUARD_OFF` 等は dead path)。bypass: `ECC_DRAFT_FLOW_GUARD_OVERRIDE=1` (env、bypass.log 記録) / `HC_DOCS_APPROVED_DIR=<dir>[,...]` (config)。honor system: bypass 根拠は `docs/tasks/<task-N>.md` 該当 entry に記録。

> **2026-05-28 緩和の経緯 (task-40 拡張撤廃) / 監視対象 path 表 / 緩和後 hook 役割 / 規範変更 honor system 降格 / 起源**: [workflow/draft-flow-guard.md](../rules-details/workflow/draft-flow-guard.md)

## リファクタリング強制 (W3)

`/module-review` と `/system-review` は workflow の **必須 stage**、skip は default 禁止 (workflow-guard.sh が `/finish-task` で BLOCK)。

### 観点 (`/module-review` 3 観点 + `/system-review` system-level)

`/module-review` は **持続可能性 (Sustainability)** / **汎用性 (Generality)** / **非冗長化 (Deduplication)** の 3 観点。`/system-review` はこれに加え system 全体で **モジュール間重複** (module 横断 DRY) / **横断的責務漏れ** (logging / error handling / observability / rate limiting / authn-authz の一貫性) / **設計乖離** (draft §3 採用案逸脱 / test-design ☒ 誤実装 / §6 DoD 充足) を検査。各観点の sub-checklist 各論は fragment 参照。

### pending_findings 連携

CRITICAL / HIGH findings は state JSON の `pending_findings.module_review` / `pending_findings.system_review` 配列 (id / severity / summary) に追加。**CRITICAL / HIGH 残存中は `workflow-guard.sh` が `/finish-task` を BLOCK**。MEDIUM / LOW のみ残存は user 承認のうえ `skip_log` 記録で pass 可。

**yml 値による制御**: `/module-review` は `review_required_module` / `review_min_count_module` / `review_max_count_module`、`/system-review` は `review_required_system` / `review_min_count_system` / `review_max_count_system`。`review_iteration_max` は全レビュー共通。**具体値は散文に hardcode せず、起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_module` 等で現在値を確認する** (値解決順 `env > harness-config.local.yml > harness-config.yml > default`)。`hc-config.sh --set review_required_module=false` で局所無効化可。

> **review prompt 規約 (behavior-preserving / 末尾 confidence:0.X) / 3 観点 sub-checklist 各論 / system-level sub-checklist / MEDIUM-LOW skip フロー**: [workflow/refactoring.md](../rules-details/workflow/refactoring.md) + [`module-review.md`](../commands/module-review.md) Phase 3

## テスト設計の MECE 強制 (W1)

`/test-design <slug>` は承認済 draft (`docs/draft/<slug>.md`) を読み、`_TEST_DESIGN_TEMPLATE.md` から **MECE 20 カテゴリ** (単体 / 統合 / E2E / DB / 境界値 / 異常系 / 回帰 / カバレッジ計測 / 網羅性検証 / 完全性検証 / 性能 / 負荷 / セキュリティ / 互換性 / アクセシビリティ / i18n / smoke / シナリオ / chaos・障害注入 / 契約テスト) のテストカタログを `docs/draft/<slug>.test-design.md` に生成。

### user スコープ承認の強制

各カテゴリは user が **採用 (☑) / 不採用 (☒)** を全行決定。不採用には必ず理由を 4 種 (`scope-excluded` / `not-applicable` / `existing-coverage` / `accepted-risk`) から選ぶ。W4 実装後、`/new-task` は本 user 判断が未確認の場合 BLOCK (workflow-guard.sh の Stage 4 検証)。並列起動 agent は `tdd-guide` / `test-automator` / `qa-expert` (`reviewer_registry_test`)、3 agent 中 2 以上採用推奨で default ☑ / 2 以上不採用で ☒ / 意見割れで ☐ + 「user 判断要」。

**yml 値による制御**: `review_required_test` / `review_min_count_test` / `review_max_count_test` / `review_iteration_max` で集中制御。**reviewer 並列起動数は固定 default ではなく `min ≤ N ≤ max` の範囲で動的選定**し、起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限を確認する (青天井「5+」は task-64 で廃止、値解決順 `env > harness-config.local.yml > harness-config.yml > default`)。

> **20 MECE カテゴリ各論 (採用 / 不採用判定例 table) / 3 agent 投票 default 判定**: [workflow/mece-20.md](../rules-details/workflow/mece-20.md) + [`_TEST_DESIGN_TEMPLATE.md`](../templates/docs/draft/_TEST_DESIGN_TEMPLATE.md)

## 設計レビューの fan-out (W2)

`/design-review <slug>` は `reviewer_registry_design` + `reviewer_registry_security` カテゴリ登録 agent を **並列起動** (`run_in_background: true` 必須) し、findings を `docs/draft/<slug>-review.md` に集約。reviewer-registry (design / security / test / impl の 4 キー) と起動対象 agent の対応は `harness-config.yml` が SSoT、env (例: `HC_REVIEWER_REGISTRY_DESIGN`) で改行区切り上書き可。

**並列数 / 反復制御**: `review_required_design` / `review_min_count_design` / `review_max_count_design` / `review_iteration_max` で制御。**具体値は hardcode せず `hc-config.sh --get review_min_count_design` 等で現在値確認** (値解決順 `env > harness-config.local.yml > harness-config.yml > default`)。draft レビューは「修正 → 再レビュー」を **CRITICAL + HIGH + MEDIUM = 0** になるまで反復 (LOW は許容、cosmetic finding として記録のみ)、reviewer は **3 体以上** 並列起動 (不足で user escalation)、反復上限超過時は user escalation (bypass: `ECC_DESIGN_REVIEW_OFF=1`)。各 iter の reviewer / 件数 / 修正 commit hash は draft §「レビューサイクル」table に append。

> **reviewer-registry 4 キー全 agent 表 / 並列数・反復制御 yml 値 / 収束条件 table / stack heuristic 絞り込みロジック (database / API / UI 検出) / 集約フォーマット / reviewer 最低数 3 体の理由**: [workflow/fan-out.md](../rules-details/workflow/fan-out.md)

## reviewer prompt 共通規約 (2026-05-28 追加)

`/design-review` (W2) / `/test-design` (W1) / `/module-review` (W3) / `/system-review` (W3) + 採用 6 条 4「テスト設計レビュー」([`task-management.md`](./task-management.md)) で起動する**全 reviewer subagent prompt**の必須 5 項目。reviewer は単一 draft の inside-out 評価では不十分であり、プロジェクト全体 + 他 task 文脈を踏まえた findings を必ず提示する。

1. **対象 artifact Read** — 対象 draft / test-design / module / system の全文
2. **観点** — reviewer-registry / agent type 固有 (architect / security / qa 等)
3. **findings format** — CRITICAL / HIGH / MEDIUM / LOW + 具体修正提案 (behavior-preserving、public API 変更禁止)
4. **末尾 `confidence: 0.X`** — F3 confidence-gate 抽出対象 (閾値 0.6 未満は block)
5. **プロジェクト整合性 + 他 task 影響確認** (2026-05-28 user 直接指示) — `docs/tasks/list.md` + 依存先 task.md / draft.md + `next-actions.md` + `.claude/rules/*.md` + `README.md` / `docs/INVENTORY.md` + 既存実装 (Glob/Grep) を Read し、他 task 重複・前提崩壊 / 既存 rule 矛盾 / 副産物 entry 解決機会 / 既存 hook・command・skill 再利用 / SSoT 不整合を findings に含める

bypass: `HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` (項目 5 の project context 確認 skip、typo 1 行修正 / comment-only refactor / 直前 round 確認済 round-N+1 等 cost 過大ケース、honor system)。新規 feature の `/design-review` 初回 / `.claude/rules/` 編集 change / 採用 6 条 4 初回での bypass は NG。

> **起源 (2026-05-28 user 直接指示) / 必須項目 5 詳細手順 + findings 観点 / OK・NG 例 / 既存規約 (behavior-preserving / confidence) との関係 / commands 連携 / 採用 6 条 4 連携 / bypass 運用詳細 / Loop モード時の動作**: [workflow/reviewer-prompt.md](../rules-details/workflow/reviewer-prompt.md)

## 副産物 discharge (5 層強制機構)

タスク実装中・レビュー中・セッション中に発生した「副産物 (byproduct)」を **物理的に消えない設計** で管理。詳細は [`development-process.md`](./development-process.md) §「副産物発生時の即時 draft 起こし義務」参照。5 層: (1) `docs/tasks/next-actions.md` registry (entry 追加) (2) `_TASK_TEMPLATE.md` 派生 task セクション (3) `next-actions-surface.sh` (SessionStart で未処理 entry を `<system-reminder>` 強制提示) (4) `byproduct-discharge-guard.sh` (Stop で 🔴 未処理残存なら exit 2 BLOCK) (5) `/discharge-byproduct` (entry → draft / parking-lot / 無視 の移行 helper)。bypass: `ECC_NEXT_ACTIONS_SURFACE_OFF=1` (surface 無効化) / `ECC_BYPASS_DISCHARGE_GUARD=1` (discharge-guard 無効化)、両者 bypass.log 記録。honor system: bypass 理由を next-actions.md 当該 entry コメント列に記録。

> **処理フロー (entry → draft / parking-lot / 無視 の判定) / 各層機構 table / 関連 artifact / 違反パターン**: [workflow/byproduct-discharge.md](../rules-details/workflow/byproduct-discharge.md)

## Loop モード自律規律

詳細は [`modes.md`](./modes.md) §「Loop モード自律規律の 5 層強制機構」を参照。subagent 並走中の独立作業義務 (modes.md 遵守事項 7) と自律実行禁止 11 カテゴリ (同 8) を 5 層強制機構 (規範 / reminder hook / action-guard hook / settings 配線 / smoke) で構造防止。bypass 経路と関連 artifact も modes.md 側に集約。

## Session 永続化と PM Orchestration

`/sc:save` `/sc:load` `/sc:pm` (SuperClaude plugin) を `.claude/` 単独で portable な自前実装 ([`/save-state`](../commands/save-state.md) / [`/resume-state`](../commands/resume-state.md) / [`/pm-start`](../commands/pm-start.md)) に置換。Serena MCP 必須化 + SessionStart resume prompt + PDCA cycle memory 永続化を統合。各 command の Phase 1 で `mcp__serena__activate_project` を必須実行 (onboarding 未済は graceful error で `/onboarding` 案内)、`mode-session-start.sh` が `session/context` memory 存在時に `/resume-state` 提案を自動注入。memory key schema は `session/{context,last,checkpoint}` + PDCA 系 (`plan/` `execution/` `evaluation/` `learning/`) + `project/{context,architecture,conventions}`。

> **memory key schema 全列挙 / Serena 必須化の設計補足 (旧 check_onboarding_performed tool 不在経緯) / 関連 artifact 完全 list / SessionStart 自動 resume 動作詳細**: [workflow/session-persistence.md](../rules-details/workflow/session-persistence.md)

## 関連ルール / skill (代表)

- [`development-process.md`](./development-process.md) — TDD / サブエージェント委譲 / タスク管理 (本ルールの前段)
- [`task-management.md`](./task-management.md) — タスク管理メイン専任 / Parking Lot 運用 / 採用 6 条
- [`self-improvement.md`](./self-improvement.md) — L1〜L5 + F1/F2 (本ルールの W は F2 verification-loop と相補)
- [`modes.md`](./modes.md) — Normal / Loop モード (`user-approval` Stage 6 は例外)
- [`git-workflow.md`](./git-workflow.md) — branch 命名規約 (`/modify-feature` Stage 2 `checkout` の検証基準)
- state schema: [`.workflow-state/SCHEMA.md`](../.workflow-state/SCHEMA.md)

> **全 skill 完全 list (直接関連 / 補助関連 / audit 系)**: [workflow/related-skills.md](../rules-details/workflow/related-skills.md)
> **各規範の起源 / commit hash / 採用判断**: [workflow/origin.md](../rules-details/workflow/origin.md) (git log + 関連 draft / 副産物 entry 参照)
