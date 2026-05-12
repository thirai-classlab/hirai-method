---
paths:
  - "docs/draft/**"
  - "docs/tasks/**"
  - ".claude/commands/**"
  - ".claude/hooks/workflow-guard.sh"
  - ".claude/.workflow-state/**"
---

# Workflow Enforcement — 設計レビュー fan-out / テスト設計 MECE / 新規・修正 workflow / リファクタリング強制

> このファイルは [`development-process.md`](./development-process.md) の **後段** に位置する「品質保証 orchestration」レイヤを定義する。
> TDD / サブエージェント委譲 / タスク管理 / 設計→承認→タスク追加フロー等の **既存ルール** は重複記述せず、参照リンクのみに留める。
> 本ルールが対象とするのは W1〜W4 で実装された **workflow 強制機構の使い方** である。

## 概要

`development-process.md` は「設計を起こす → 承認を取る → タスク化する」までを強制する。本 `workflow.md` はその **後段** —「タスク化以降に何を / どの順で / どこで止めるか」を強制する。具体的には:

- **テスト設計 MECE** (W1): テスト観点を 20 カテゴリ MECE で user 判断強制
- **設計レビュー fan-out** (W2): `reviewer-registry` を並列起動して観点漏れを防ぐ
- **モジュール / システムレビュー** (W3): TDD 完了直後と全体統合後の 2 段リファクタリング強制
- **14 / 10 stage workflow** (W4): 新規機能 14-stage / 既存機能修正 10-stage を `workflow-guard.sh` で `/finish-task` 段で検証

これにより「reviewer 偏り / テスト観点抜け / phase skip / refactor 未実施のまま完了」を構造的に防ぐ。

## 関連 command 一覧

| command | 役割 | Wave |
|---|---|:---:|
| [`/test-design <slug>`](../commands/test-design.md) | 設計 draft から MECE 20 カテゴリのテストカタログを生成し user スコープ承認を強制 | W1 |
| [`/design-review <slug>`](../commands/design-review.md) | `reviewer_registry_design` + `_security` の全 agent を並列起動して設計レビューを fan-out | W2 |
| [`/module-review <module>`](../commands/module-review.md) | TDD 完了直後に code-reviewer + refactoring-specialist で 3 観点レビュー (持続可能性 / 汎用性 / 非冗長化) | W3 |
| [`/system-review`](../commands/system-review.md) | 全モジュール統合後に architect-reviewer + refactoring-specialist でモジュール間重複 / 設計乖離検出 | W3 |
| [`/new-feature <slug>`](../commands/new-feature.md) | 新規機能 14-stage workflow を起動する orchestrator | W4 |
| [`/modify-feature <slug>`](../commands/modify-feature.md) | 既存機能修正 10-stage workflow を起動する orchestrator | W4 |
| [`/finish-task <id>`](../commands/finish-task.md) | 完了クローズ。`workflow-guard.sh` が state JSON を検証して BLOCK する判定点 | W4 |

## 新規機能開発フロー (14-stage)

`/new-feature <slug>` で起動。`harness-config.yml` の `workflow_stages_new` (= env `HC_WORKFLOW_STAGES_NEW`) と完全一致する 14 stage を順次進める。

| # | stage 名 | 役割 | 起動 command / 連携 |
|---:|---|---|---|
| 1 | `requirements` | WHAT / WHY を確定し draft §1 を埋める | `/new-draft <slug>` |
| 2 | `basic-design` | 解決アプローチ比較 (複数案 + 工数) を draft §2 に書く | architect agent |
| 3 | `detailed-design` | API / データモデル / UI / DB schema を draft §3 に具体化 | code-architect agent |
| 4 | `test-design` | MECE 20 カテゴリのテストカタログ生成 + user スコープ承認 | `/test-design <slug>` |
| 5 | `design-review` | reviewer-registry の design + security 全 agent を並列起動して fan-out レビュー | `/design-review <slug>` |
| 6 | `user-approval` | draft §8 承認履歴に user 承認エントリ追加 (必須、Loop モードでも) | user 対話 |
| 7 | `task-creation` | `/new-task` でタスク化 + `.claude/.workflow-state/<slug>.json` を初期化 | `/new-task <id> <slug>` |
| 8 | `tdd` | RED → GREEN → REFACTOR (subagent 経由のみ、メイン直接編集禁止) | `/start-task <id>` |
| 9 | `module-review` | モジュール毎に持続可能性 / 汎用性 / 非冗長化 の 3 観点レビュー | `/module-review <module>` |
| 10 | `local-test` | `<slug>.test-design.md` で ☑ にしたテスト全カテゴリを実行 | subagent test runner |
| 11 | `system-review` | 全モジュール統合後にモジュール間重複 / 設計乖離検出 | `/system-review --slug <slug>` |
| 12 | `ci-cd` | `.github/workflows/` 等の更新 (skip 可、`asana_enabled=false` プロジェクトは default skip) | — |
| 13 | `scenario-test` | E2E / シナリオ実行 (`<slug>.test-design.md` の ☑ シナリオ全件) | e2e-runner agent |
| 14 | `finish` | `/finish-task` で完了クローズ。**workflow-guard.sh が state JSON を検証** | `/finish-task <id>` |

各 stage 完了時、メインが `.claude/.workflow-state/<slug>.json` の `current_stage` を次 stage に進め、`completed_stages` に追加する。state JSON は Stage 7 (`task-creation`) で初期化される (Stage 1〜6 完了済として列挙)。

stage 名の正確な配列は env `HC_WORKFLOW_STAGES_NEW` (harness-config.yml `workflow_stages_new`) を SSoT とする。

## 既存機能修正フロー (10-stage)

`/modify-feature <slug>` で起動。`harness-config.yml` の `workflow_stages_modify` (= env `HC_WORKFLOW_STAGES_MODIFY`) と完全一致する 10 stage を順次進める。

| # | stage 名 | 役割 | 起動 command / 連携 |
|---:|---|---|---|
| 1 | `branch-decision` | 影響範囲特定 + branch type (`feat`/`fix`/`refactor`/`hotfix`) 決定 | user 対話 |
| 2 | `checkout` | branch 切替 (regex 検証: git-workflow.md 規約準拠) | `git switch` |
| 3 | `recover-design` | 既存 task / draft を探索、不完全なら現状実装から逆引きで draft 起こし | Glob + Read |
| 4 | `pre-test` | **修正前** の全テスト PASS を baseline として記録 (regression 検出基準) | test runner |
| 5 | `redesign` | draft §3 に「変更前 / 変更後」差分を追記 | architect agent |
| 6 | `retest-design` | `/test-design` 再実行で差分部の MECE 再評価 | `/test-design <slug>` |
| 7 | `tdd` | 新規 test 追加 → 最小修正 → refactor (subagent 経由) | TDD ループ |
| 8 | `module-review` | モジュール毎に 3 観点レビュー | `/module-review <module>` |
| 9 | `full-test` | 全 test PASS + pre-test baseline との regression 検出 | test runner |
| 10 | `system-review` | 全体整合性レビュー → merge 可否判断 → `/finish-task` 案内 | `/system-review` |

`/new-feature` との主要差分: 要件定義 / `design-review` (fan-out) / `task-creation` / `ci-cd` / `scenario-test` は省略され、代わりに `recover-design` / `pre-test` / `retest-design` が入る。詳細比較は [`modify-feature.md` の「/new-feature との差分」セクション](../commands/modify-feature.md) を参照。

## workflow-guard.sh による強制機構

`.claude/hooks/workflow-guard.sh` は **PreToolUse(Bash)** で `/finish-task <slug>` 実行直前に発火する。設計仕様は `docs/draft/workflow-enforcement.md` v2 §3 W4。

### 判定ロジック (構造化 JSON 解析、grep 依存禁止)

1. `tool_name == "Bash"` で `command` に `/finish-task <slug>` パターン (`^[a-z0-9][a-z0-9-]{2,48}$`) を検出
2. `.claude/.workflow-state/<slug>.json` を読む (不在なら旧 task 互換で silent pass)
3. `workflow_type` から stage 列 (`HC_WORKFLOW_STAGES_NEW` または `_MODIFY`) を解決
4. **判定 A**: `current_stage` が stage 列の **最終要素** に到達しているか (new=`finish` / modify=`system-review`)
5. **判定 B**: `pending_findings.module_review` と `pending_findings.system_review` が **両方とも空配列** か
6. A / B いずれか fail なら **exit 2 (BLOCK)** + stderr に「問題」「推奨アクション」「bypass 手順」を出力

step 番号や順序ではなく **stage 名で判定** する設計 (round-2 arch-rev H3 反映)。

### state JSON schema

`.claude/.workflow-state/<slug>.json` の構造定義は [`SCHEMA.md`](../.workflow-state/SCHEMA.md) を SSoT とする。主要フィールド:

| Field | 型 | 説明 |
|---|---|---|
| `slug` | string | 機能識別子。ファイル名と一致 |
| `workflow_type` | `"new" \| "modify"` | どちらの workflow か |
| `current_stage` | string | 現在進行中の stage 名 |
| `completed_stages` | string[] | 完了済 stage の配列 (順序保持) |
| `pending_findings` | object | `module_review` / `system_review` の未解決 findings 配列 |
| `skip_log` | object[] | skip された stage の audit (stage / reason / user_approved_at) |
| `created_at` / `updated_at` | ISO-8601 UTC | timestamp (秒精度、`Z` suffix) |

state JSON 本体 (`<slug>.json`) は `.claude/.workflow-state/.gitignore` で除外され、`SCHEMA.md` / `bypass.log` / `bypass.log.template` のみ git track される。

## Bypass と audit

### bypass 経路

| 方法 | 系統 | スコープ | 痕跡 |
|---|---|---|---|
| `ECC_WORKFLOW_GUARD_OFF=1` | env 系統 | 1 セッション | `.claude/.workflow-state/bypass.log` に append |
| `HC_WORKFLOW_GUARD_ENABLED=false` | config 系統 | 1 セッション | 同上 |
| `ECC_BYPASS_REASON='<reason>'` | 補助 | bypass 1 回分の理由を log 列に記録 | bypass.log の最終列 |

両系統 (`ECC_*_OFF=1` と `HC_*_ENABLED=false`) を併存させているのは round-2 sec-rev H3 反映: env と config から独立に bypass 可能にすることで、別系統のうち片方が誤って enabled なまま放置される事故を防ぐため。

### bypass.log 集計

`.claude/.workflow-state/bypass.log` は `lib/bypass-logger.sh` 経由で統一フォーマット (`<ISO-8601> | <session_id> | <hook_name> | <env_var> | <reason>`) で append される。

`harness-audit.py` の `bypass_log_summary()` がこのファイルを集計し、`/harness-audit` 実行時に最近 N 日の bypass を表示 (`fmt_bypass_log()`)。bypass 頻度が高い hook を発見し、設計改善のシグナルとして活用する。

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリにも記録すること (env 系統だけだと持続的なトレースができない)。

## リファクタリング強制 (W3)

`/module-review` と `/system-review` は workflow の **必須 stage** であり、skip は default 禁止 (workflow-guard.sh が `/finish-task` で BLOCK)。

### 3 観点 (`/module-review`)

各 reviewer に共通プロンプトで提示する 3 観点:

1. **持続可能性 (Sustainability)** — 命名 / 関数 50 行以内 / ファイル 800 行以内 / ネスト 4 階層以内 / magic number 排除 / 副作用局所化 / 型注釈 / silent failure 排除
2. **汎用性 (Generality)** — 引数化可能性 / 1 callee 特化排除 / idiom 準拠 / 抽象依存 / test seam
3. **非冗長化 (Deduplication)** — DRY / table-driven 化 / util/helper 再発明排除 / 既存型流用 / over-engineering 排除 (YAGNI)

### system-level 観点 (`/system-review`)

`/module-review` の 3 観点に加え、system 全体で:

1. **モジュール間重複** — module 横断 DRY (`/module-review` は module 内 DRY のみ)
2. **横断的責務漏れ** — logging / error handling / observability / rate limiting / authn-authz の一貫性
3. **設計乖離** — `docs/draft/<slug>.md` §3 採用案からの逸脱 / `<slug>.test-design.md` の ☒ テストが誤実装されていないか / §6 DoD 充足

### pending_findings 連携

両 review で検出された CRITICAL / HIGH findings は state JSON の `pending_findings.module_review` / `pending_findings.system_review` 配列 (id / severity / summary) に追加される。**CRITICAL / HIGH が残存している間、`workflow-guard.sh` が `/finish-task` を BLOCK する**。

MEDIUM / LOW のみが残存する場合は user 承認のうえ `skip_log` に記録すれば pass 可能 (運用判断)。

review prompt 規約 (behavior-preserving 必須 / public API・DB schema 変更禁止 / 全 finding に修正コード提案 / 末尾 `confidence: 0.X`) の詳細は [`module-review.md`](../commands/module-review.md) Phase 3 を参照。

## テスト設計の MECE 強制 (W1)

`/test-design <slug>` は承認済設計 draft (`docs/draft/<slug>.md`) を読み、`.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md` から **MECE 20 カテゴリ** のテストカタログを `docs/draft/<slug>.test-design.md` に生成する。

### 20 MECE カテゴリ

単体 / 統合 / E2E / DB / 境界値 / 異常系 / 回帰 / カバレッジ計測 / 網羅性検証 / 完全性検証 / 性能 (レスポンスタイム) / 負荷 / セキュリティ / 互換性 / アクセシビリティ / i18n / smoke / シナリオ / chaos・障害注入 / 契約テスト の 20 カテゴリ。

詳細仕様: [`workflow-enforcement.md` §3 W3 / W1 v2 順序](../../docs/draft/workflow-enforcement.md)。template の全行: [`_TEST_DESIGN_TEMPLATE.md`](../templates/docs/draft/_TEST_DESIGN_TEMPLATE.md)。

### user スコープ承認の強制

各カテゴリは user が **採用 (☑) / 不採用 (☒)** を全行決定する。不採用には必ず理由を 4 種から選ぶ:

- `scope-excluded` — タスクスコープ外
- `not-applicable` — 機能特性上不要
- `existing-coverage` — 既存テストで網羅済
- `accepted-risk` — リスク受容 (user 承認)

W4 実装後、`/new-task` は本 user 判断が未確認の場合 BLOCK される (workflow-guard.sh の Stage 4 検証)。

並列起動される agent: `tdd-guide` / `test-automator` / `qa-expert` (`reviewer_registry_test` カテゴリ)。3 agent 中 2 以上が採用推奨ならデフォルト ☑、2 以上が不採用なら ☒、意見割れなら ☐ + コメント「user 判断要」。

## 設計レビューの fan-out (W2)

`/design-review <slug>` は `harness-config.yml` の `reviewer_registry_design` + `reviewer_registry_security` カテゴリに登録された agent を **並列起動** (`run_in_background: true` 必須) し、各 findings を `docs/draft/<slug>-review.md` に集約する。

### reviewer-registry (`harness-config.yml`)

| キー | 起動対象 agent | 用途 |
|---|---|---|
| `reviewer_registry_design` | architect / architect-reviewer / code-architect / api-designer / ui-designer / database-reviewer / harness-optimizer | 設計レビュー (W2 `/design-review`) |
| `reviewer_registry_security` | security-auditor / security-reviewer / penetration-tester | セキュリティレビュー (W2 `/design-review`) |
| `reviewer_registry_test` | tdd-guide / test-automator / qa-expert / pr-test-analyzer | テスト設計 (W1 `/test-design`) |
| `reviewer_registry_impl` | code-reviewer / refactoring-specialist / 言語別 reviewer 群 | 実装レビュー (W3 `/module-review` `/system-review`) |

env 上書き例: `export HC_REVIEWER_REGISTRY_DESIGN=$'architect\narchitect-reviewer'` (改行区切り) で 2 件に絞り cost 制御可能。

### stack heuristic 絞り込み

draft 本文を grep して以下キーワードを検出し、不要な reviewer を除外:

- `database` / `migration` / `RLS` 不在 → database-reviewer skip
- `API` / `endpoint` / `REST` / `GraphQL` 不在 → api-designer skip
- `UI` / `component` / `frontend` 不在 → ui-designer skip

`--skip-stack-filter` で全件起動、`--max-reviewers N` で上限指定可。

### 集約

各 reviewer の SubagentStop 通知を受けたら findings を `docs/draft/<slug>-review.md` に append。全件完了後に severity 別件数サマリ表 + blocking findings (CRITICAL / HIGH) + 各 reviewer の confidence score 一覧を提示。

CRITICAL / HIGH が 0 件 → draft「承認待ち」へ、1 件以上 → 「修正待ち」状態を明示。

## 副産物 discharge (本セッション task #5 で実装)

タスク実装中・レビュー中・セッション中に発生した「副産物 (byproduct)」を **物理的に消えない設計** で管理する。詳細は [`development-process.md`](./development-process.md) §「副産物発生時の即時 draft 起こし義務」参照。

### 5 層強制機構

| 層 | 機構 | 発火 | 動作 |
|---|---|---|---|
| 1 | `docs/tasks/next-actions.md` registry | 副産物発見時にメインが entry 追加 | informal な「TODO / 次アクション候補」を捕捉する公式 location |
| 2 | `_TASK_TEMPLATE.md` 派生 task セクション | task 実装中・完了時 | 発生源 task に「派生 task / 次アクション候補」を明示記録 |
| 3 | `.claude/hooks/next-actions-surface.sh` (SessionStart) | 毎セッション開始 | 未処理 entry を `<system-reminder>` で stderr 強制提示 (緊急度 🔴 強調) |
| 4 | `.claude/hooks/byproduct-discharge-guard.sh` (Stop) | セッション終了時 | 🔴 未処理 entry が残存なら exit 2 で BLOCK + bypass.log 記録 |
| 5 | `.claude/commands/discharge-byproduct.md` | user 任意 | entry → draft / parking-lot / 無視 の移行 helper |

### 処理フロー

```
副産物発生
  ↓ (層 1: registry 追加義務)
docs/tasks/next-actions.md に entry 追加 (緊急度 🔴 / 🟡 / 🟢)
  ↓ (層 5: command で移行)
/discharge-byproduct <entry-number>
  ↓
[判定]
  (a) 🔴 / 🟡 → /new-draft <slug> で draft 起こし → user 承認 → /new-task → list.md
  (b) 🟢 + 設計済 → parking-lot.md に保留タスクとして移行
  (c) 不要 → 無視、理由を処理結果列に明記、履歴セクションへ移動
  ↓
next-actions.md 処理結果列を更新
```

### bypass

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| surface 無効化 | `ECC_NEXT_ACTIONS_SURFACE_OFF=1` | 1 セッション | bypass.log |
| discharge-guard 無効化 | `ECC_BYPASS_DISCHARGE_GUARD=1` | 1 セッション | bypass.log (session_id + reason) |

honor system: bypass 時は理由を `docs/tasks/next-actions.md` 当該 entry のコメント列に記録。

### 関連 artifact

- [`docs/tasks/next-actions.md`](../../docs/tasks/next-actions.md) — registry 本体
- [`.claude/templates/docs/tasks/_TASK_TEMPLATE.md`](../templates/docs/tasks/_TASK_TEMPLATE.md) — 派生 task セクション (W2 で追加)
- [`.claude/hooks/next-actions-surface.sh`](../hooks/next-actions-surface.sh) (W1)
- [`.claude/hooks/byproduct-discharge-guard.sh`](../hooks/byproduct-discharge-guard.sh) (W3)
- [`.claude/hooks/lib/next-actions-parser.sh`](../hooks/lib/next-actions-parser.sh) — 共通 parser
- [`.claude/commands/discharge-byproduct.md`](../commands/discharge-byproduct.md) (W4)
- [`.claude/tests/next-actions-hooks-smoke.sh`](../tests/next-actions-hooks-smoke.sh) (W6, 9/9 PASS)
- 設計起源: [`docs/draft/byproduct-discharge-mechanism.md`](../../docs/draft/byproduct-discharge-mechanism.md)

## Loop モード自律規律

タスク実装中・Loop モード稼働中の「subagent 完了待ち停止」「破壊的操作の自律実行」を **5 層強制** で構造防止する。詳細は [`modes.md`](./modes.md) 遵守事項 7+8 参照。設計の経緯と承認履歴は採用プロジェクト側の `docs/draft/` を参照 (本ルールは `.claude/` 単独で portable)。

### 5 層強制機構

| 層 | 機構 | 発火 | 動作 |
|---|---|---|---|
| 1 | `.claude/rules/modes.md` 遵守事項 7+8 | (規範) | subagent 待ち中独立作業義務 + 自律禁止 11 カテゴリ明文化 |
| 2 | `.claude/hooks/loop-auto-progress-reminder.sh` (UserPromptSubmit) | 毎ターン | 待ち中報告キーワード検出 + pending Agent tool_use 数集計 → `<system-reminder>` 強制注入 |
| 3 | `.claude/hooks/autonomous-action-guard.sh` (PreToolUse Bash) | Bash 実行前 | 11 カテゴリ regex 照合 → Loop なら `{"decision":"block"}` / Normal なら context 注入 |
| 4 | `.claude/settings.json` 配線 | (機構接続) | UserPromptSubmit 末尾 + PreToolUse Bash 先頭に配置 |
| 5 | `.claude/tests/loop-auto-progress-smoke.sh` | 検証 | 9 ケースで両 hook の動作検証 |

### 禁止 11 カテゴリ (default、`HC_AUTONOMOUS_ACTION_PATTERNS` で上書き可)

- remote 反映: `git push` (any branch)
- PR / リリース: `gh pr (create|merge)` / `gh release` / `git tag <name> origin|upstream`
- 第三者リポ: `gh repo (delete|transfer|archive)`
- 本番 deploy: `vercel --prod` / `supabase deploy` / `supabase db (push|reset)`
- infra apply: `kubectl (apply|delete)` / `terraform (apply|destroy)`
- AWS 破壊操作: `aws *-delete-*|terminate-*|destroy-*`

### bypass

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| autonomous-action-guard 無効化 | `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` | 1 セッション | bypass.log (autonomous-action-guard 行) |
| config レベル OFF | `HC_AUTONOMOUS_ACTION_ENABLED=false` | 1 セッション | bypass.log |
| reminder 無効化 | `HC_LOOP_AUTO_PROGRESS_ENABLED=false` | 1 セッション | (記録なし、reminder のみ) |
| パターン上書き | `HC_AUTONOMOUS_ACTION_PATTERNS=...` | env-set 中 | 上書き内容は env のみ |

honor system: bypass 時は理由を `docs/tasks/<task-N>.md` または `ECC_BYPASS_REASON` env に記録すること。

### 関連 artifact

- [`.claude/rules/modes.md`](./modes.md) 遵守事項 7 (subagent 待ち独立作業) + 8 (自律禁止リスト)
- [`.claude/hooks/loop-auto-progress-reminder.sh`](../hooks/loop-auto-progress-reminder.sh) (W2)
- [`.claude/hooks/autonomous-action-guard.sh`](../hooks/autonomous-action-guard.sh) (W3)
- [`.claude/tests/loop-auto-progress-smoke.sh`](../tests/loop-auto-progress-smoke.sh) (W5)
- 設計の起源と承認履歴は採用プロジェクト側 `docs/draft/` / `docs/tasks/` を参照

## Session 永続化と PM Orchestration

`/sc:save` `/sc:load` `/sc:pm` (SuperClaude plugin) を `.claude/` 単独で portable な自前実装に置換。Serena MCP 必須化 + SessionStart resume prompt + PDCA cycle memory 永続化を統合。

### 自前 command

| command | 役割 | 主要 Serena tool |
|---|---|---|
| [`/save-state`](../commands/save-state.md) | session 状態を Serena memory に snapshot 保存 | `write_memory` |
| [`/resume-state`](../commands/resume-state.md) | 前 session 状態を Serena memory から復元 | `list_memories` / `read_memory` |
| [`/pm-start`](../commands/pm-start.md) | PM Agent orchestration + PDCA cycle 永続化 (Session Start Protocol 内包) | 全 memory API |

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

各 command の Phase 1 で `mcp__serena__check_onboarding_performed` を必須実行。未済時は graceful error で `/onboarding` 案内 + 終了。

`.mcp.json` の `serena` entry は採用者側で個別登録 (Claude Code 標準には required marker 機構なし、command-level enforcement で代替)。

### SessionStart 自動 resume

`.claude/hooks/mode-session-start.sh` が `.serena/memories/session/context.md` 存在時に `<system-reminder>` で `/resume-state` 提案を自動注入 (W2)。手動入力不要で前 session からの継続が可能。

### 関連 artifact

- [`.claude/commands/save-state.md`](../commands/save-state.md)
- [`.claude/commands/resume-state.md`](../commands/resume-state.md)
- [`.claude/commands/pm-start.md`](../commands/pm-start.md)
- [`.claude/hooks/mode-session-start.sh`](../hooks/mode-session-start.sh) (W2 拡張済)
- [`.claude/tests/custom-pm-commands-smoke.sh`](../tests/custom-pm-commands-smoke.sh) (W5, 6/6 PASS)
- 設計起源は採用プロジェクト側 `docs/draft/` を参照 (`.claude/` 単独で portable)

## 関連ルール / skill

- [`development-process.md`](./development-process.md) — TDD / サブエージェント委譲 / タスク管理 / 設計→承認→タスク追加フロー (本ルールの前段)
- [`task-management.md`](./task-management.md) — タスク管理メイン専任ルール / Parking Lot 運用
- [`self-improvement.md`](./self-improvement.md) — L1〜L5 自己改善 + F1/F2 事実検証の使い分け (本ルールの workflow 強制は F2 verification-loop と相補関係)
- [`modes.md`](./modes.md) — Normal / Loop モード (Loop モードでは workflow 各 stage 間の user 確認を省略するが、`user-approval` Stage 6 は例外)
- [`git-workflow.md`](./git-workflow.md) — branch 命名規約 (`/modify-feature` Stage 2 `checkout` の検証基準)
- skill: `salesforce-e2e-testing` — Wave / Phase 完了時の E2E シナリオ設計 (Stage 13 `scenario-test` / Stage 9 `full-test` で参照)
- skill: `karpathy-guidelines` — surgical changes 原則 (`/module-review` / `/system-review` の behavior-preserving 原則と整合)
- 設計 draft: [`workflow-enforcement.md`](../../docs/draft/workflow-enforcement.md) v2 §3 — 本ルール群の元設計
- state schema: [`.workflow-state/SCHEMA.md`](../.workflow-state/SCHEMA.md) — workflow-guard.sh が参照する JSON 仕様
- audit: `harness-audit.py` の `bypass_log_summary()` / `fmt_bypass_log()` — `/harness-audit` での bypass 集計
