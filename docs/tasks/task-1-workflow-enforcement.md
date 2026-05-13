# Task #1: HIRAI メソッド Workflow Enforcement (W1-W6 umbrella)

> Status: **🔄 進行中 (W5 完了、W6 out-of-scope)**
> 起案: 2026-05-12
> 関連: — / Phase: workflow-enforcement
> 設計起源: [`workflow-enforcement.md`](../draft/workflow-enforcement.md)

## 背景・目的

HIRAI メソッドハーネスに「品質保証 orchestration」を追加し、設計レビュー fan-out / テスト設計 MECE / new-feature・modify-feature workflow 強制 / リファクタリング強制 を一気通貫で実演可能にする。

draft v2 (round-2 review 反映済 + Asana mode 追加) を 6 Wave に分割し各 Wave を独立 deliver する。

## 仕様

詳細は [`docs/draft/workflow-enforcement.md`](../draft/workflow-enforcement.md) §0 v2 変更点 + §3 採用案を参照。

### 重要な user 要件追加 (2026-05-12)

- **Asana 利用可否は session 開始時にヒアリング、`.claude/mode.yml` の `asana_enabled` キーで永続化**
- Asana 非利用プロジェクトでは W6 全機能を disable

## Wave 進捗

| Wave | 内容 | 状態 | commit | 完了日 | Asana mode 依存 |
|:---:|:---|:---:|:---|:---:|:---:|
| **W1** | /test-design + MECE テンプレ | ✅ 完了 | `1e8aa0e` | 2026-05-12 | 独立 |
| **W2** | /design-review fan-out + reviewer-registry を harness-config.yml に集約 | ✅ 完了 | `21f1d78` | 2026-05-12 | 独立 |
| **W3** | /module-review /system-review + refactoring-specialist 規約 | ✅ 完了 | `e8e6704` | 2026-05-12 | 独立 |
| **W4** | /new-feature /modify-feature + workflow-guard.sh + workflow-state.json + _TASK_TEMPLATE 拡張 | ✅ 完了 | `52a170f` / `d66243f` / `1c55899` / `c57636c` / `cba14bd` / `1873522` / `1eb3515` / `555b0ee` | 2026-05-12 | 独立 |
| **W5** | workflow.md rule 文書化 + CLAUDE.md 表更新 | ✅ 完了 | (本 commit) | 2026-05-12 | 一部 |
| **W6** | docs/work.md + /work-init + Asana/Slack MCP + asana_enabled mode 管理 | 🚫 out-of-scope | — | — | `asana_enabled=false` のため不要 |

### W4 sub-commit 内訳

W4 は 8 sub-commits で構成 (順):
- `52a170f` W4-config-base — harness-config.yml に `workflow_stages_new` / `_modify` 追加
- `d66243f` W4-state-schema — `.workflow-state/SCHEMA.md` + bypass.log.template
- `1c55899` W4-template — `_TASK_TEMPLATE` frontmatter 拡張 (asana_url / slack_urls / deadline / requester)
- `c57636c` W4-command-new — `/new-feature` 14-stage orchestrator command
- `cba14bd` W4-command-modify — `/modify-feature` 10-stage orchestrator command
- `1873522` W4-hook — `workflow-guard.sh` (PreToolUse(Bash) `/finish-task` 検証)
- `1eb3515` W4-bypass-audit — bypass logging 一元化 + harness-audit summary
- `555b0ee` W4-smoke-test — workflow-guard end-to-end 8 ケース smoke (8/8 PASS)

### 累計実績 (W1〜W5)

- **commits**: 11 (W1 `1e8aa0e` / W2 `21f1d78` / W3 `e8e6704` / W4 8 sub-commits / W5 本 commit)
- **smoke test**: workflow-guard 8/8 PASS (`555b0ee`)
- **新規 command**: 6 (`/test-design`, `/design-review`, `/module-review`, `/system-review`, `/new-feature`, `/modify-feature`)
- **新規 hook**: 1 (`workflow-guard.sh`)
- **新規 rule**: 1 (`.claude/rules/workflow.md`)
- **harness-config 拡張**: 4 keys (`reviewer_registry_design` / `_security` / `_test` / `_impl`) + 2 keys (`workflow_stages_new` / `_modify`)
- **template 拡張**: `_TEST_DESIGN_TEMPLATE.md` (20 MECE カテゴリ) + `_TASK_TEMPLATE.md` frontmatter
- **state schema**: `.claude/.workflow-state/SCHEMA.md` + `bypass.log`

## TDD 戦略

### W1 (本 task 範囲)

#### RED
- `_TEST_DESIGN_TEMPLATE.md` に 20 MECE カテゴリ全行が存在することを grep 検証
- `/test-design` command が 規定 frontmatter + Phase 1-5 構造を持つことを grep 検証

#### GREEN
- `.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md` 新設 (20 カテゴリ)
- `.claude/commands/test-design.md` 新設

#### REFACTOR
- W3 / W4 で enforcement hook 連携時に再評価

### W6 (Asana mode 連動)

- `.claude/mode.yml` に `asana_enabled` field 追加 (default null = unset)
- SessionStart hook で `asana_enabled` が unset の場合 user にヒアリング (`<system-reminder>` で「Asana 利用しますか? `/mode asana on` または `/mode asana off`」を 1 度だけ提示)
- `/mode asana on|off` で値を更新
- `/work-init` 起動時に `asana_enabled=true` を check、false なら exit 0

## 完了条件 (W1 単独)

- [x] `.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md` 存在、20 カテゴリ全列挙
- [x] `.claude/commands/test-design.md` 存在、command frontmatter + Phase 構造
- [x] 本 task ファイル W1 状態が ✅ 完了
- [x] commit + push (commit `1e8aa0e`)

## 完了条件 (umbrella 全 W1-W6)

- [x] W1-W5 が ✅ 完了
- [x] W6 は `mode.yml` の `asana_enabled: false` (commit `9337afd`) により out-of-scope と確定
- [x] workflow-enforcement draft v2 §6 DoD のうち Asana 連携項目以外は全件 PASS
- [x] CLAUDE.md Rules 表更新 (workflow.md 行追加)
- [x] CLAUDE.md Commands 表更新 (Workflow 強制 W1-W4 行追加)

## 工数見積

draft v2 §7 工数見積参照。合計 4.5 工数 + Asana mode 追加で +0.3 = **4.8 工数**。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/commands/*.md`, `.claude/hooks/*.sh`, `.claude/templates/docs/draft/*.md`, `.claude/rules/workflow.md`, `.claude/mode.yml` (asana_enabled 追加), `docs/work.md` (optional) |
| migration | なし |
| 環境変数 | `HC_WORKFLOW_GUARD_ENABLED` 等を harness-config.yml に追加 |
| 互換性 | 既存 `/new-draft` `/new-task` `/start-task` `/finish-task` に追加機能、破壊的変更なし |

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-12 | 起案 | draft v1 起こし |
| 2026-05-12 | review round-2 完了 | 46 findings 受領 |
| 2026-05-12 | draft v2 反映 | CRITICAL 6 + HIGH 主要反映 |
| 2026-05-12 | Asana mode 要件追加 | user 指示「Asana 利用可否を mode で管理」を draft v2 + 本 task に反映 |
| 2026-05-12 | 着手 | branch `feat/loop-mode`、W1 開始 |
| 2026-05-12 | W1 完了 | commit `1e8aa0e` (/test-design + MECE template) |
| 2026-05-12 | W2 完了 | commit `21f1d78` (/design-review + reviewer-registry in harness-config.yml) |
| 2026-05-12 | W3 完了 | commit `e8e6704` (/module-review + /system-review + refactoring 3 観点) |
| 2026-05-12 | W6 out-of-scope 確定 | commit `9337afd` で `asana_enabled: false` を OSS-friendly default に設定 |
| 2026-05-12 | W4 完了 | 8 sub-commits (`52a170f` `d66243f` `1c55899` `c57636c` `cba14bd` `1873522` `1eb3515` `555b0ee`)、smoke 8/8 PASS |
| 2026-05-12 | W5 完了 | `.claude/rules/workflow.md` 新設 + CLAUDE.md Rules / Commands 表更新 |
| 2026-05-12 | task #1 全体完了 | W1-W5 完了、W6 out-of-scope、累計 11 commits、umbrella close 可 |

## 関連

- Draft: [`workflow-enforcement.md`](../draft/workflow-enforcement.md)
- レビュー成果物 (transcripts): architect-reviewer / code-architect / security-reviewer round-2
- 関連 commits: `69159b7` `96da878` `a7d6558` `f7b2a0d` `24f4a8f` `d45076f` `83fc6ea`
