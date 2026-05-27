# CommonRules.md — HIRAI メソッド 共通規範

> 本 file は `.claude/` に配置され、CLAUDE.md から `@.claude/CommonRules.md` で auto-expand される。
> Claude Code memory file import 機能で session 開始時に CLAUDE.md と同等に load される。
>
> **責務分離**:
> - CLAUDE.md = project 固有 (Tech Stack / User Context / Implementation Status / Commands (project 固有 dev command))
> - CommonRules.md (本 file) = harness 共通 (Development Policy / Autonomous Progression / Rules / Critical Operational Lessons 等)
>
> 本 file は `install.sh --update` で自動同期される (CLAUDE.md は保護対象、project 固有編集を維持)。

## Development Policy

- **TDD**: テスト先行（テスト専門エージェント `tdd-guide` / `test-automator` / `qa-expert` で観点出し → Red → Green → Refactor）
- **サブエージェント委譲（Hook 強制 + 背景起動 + 順序整合性 + Task 登録 + Bash deny 反射）**:
  - メインは `src/` `tests/` `scripts/` の Read/Write/Edit/Bash 禁止 → すべて Agent tool 経由
  - **Agent tool は `run_in_background: true` 必須**（メインを user 対話に常時開放）
  - **タスク順序整合性はメインが保証**（依存解決 / 並行判定 / commit conflict 防止）
  - **サブエージェント起動時は必ず TaskCreate**（subagent_id を metadata に記録、Claude Code 内蔵タスクリストに表示）
  - **Bash deny / whitelist 不在 / 委譲ガード block は loop 停止理由にしない**(自動的に Agent 委譲で再試行 — `development-process.md` §5)
  - 詳細は [`.claude/rules/development-process.md`](.claude/rules/development-process.md)
- **指摘対応**: 根本原因 → 修正 → 再発防止策を `.claude/rules/` に追加提案
- **タスク管理(メイン専任)**: `docs/tasks/list.md` で一元管理、サブエージェントに委譲しない
- **設計→承認→タスク追加**: `docs/draft/` 起案 → user 承認 → `docs/tasks/` 反映。設計なしのタスク追加禁止
- **外部 library / framework 仕様確認**: context7 MCP を default 利用 (既知 library でも training data outdated 回避)、fallback chain (context7 → WebFetch → GitHub code search / Exa) の詳細は `.claude/rules/development-process.md` §「研究と再利用」参照

## Autonomous Progression（自律進行ルール）

user から **タスクと方針の承認**を得た後は、実装・commit・push・本番デプロイ・migration 適用まで自律的に進める。Wave / commit ごとに進行可否を逐一問わない。

### 自律実行可（user 確認不要、戦術判断のみ）
- 承認済み設計書（`docs/tasks/task-N-*.md` or `docs/draft/<slug>.md` で frontmatter `approved_at:` 記載済）に基づく **実装** (`src/` `apps/` `packages/` 等)
- テスト追加・修正、ローカル `git commit`（feature branch 上のみ）
- 実装中の方式選択 / branch 命名 / commit メッセージ / build green までの試行錯誤
- サブエージェント委譲、ローカルサーバー起動、`docs/tasks/list.md` ステータス同期
- `<追加のみ・破壊的変更なしの DB migration 等、プロジェクト固有の自律実行範囲>`

### chat で必ず確認（クリティカル / 戦略判断 / task-21 W2.5 拡張）
- **設計文書 (要件 / 基本設計 / 詳細設計 / 機能一覧) の新規追加** — 必ず `docs/draft/<slug>.md` 経由で起こす。`docs/` 直下への直接 Write は `draft-flow-guard.sh` (commit `6ed9337`) で BLOCK
- **仕様変更 / scope 拡張** — 承認済 draft の §3 採用案からの逸脱
- **戦略的判断** — architecture 選択 / 採用技術スタック変更 / 既存 task の優先順入替
- 承認外の設計変更、破壊的 DB 変更（DROP / 既存 RLS 削除）、データ削除
- secrets ローテーション、`git push --force` / `git reset --hard` / `git branch -D`
- `git push origin main|stg*` (protected-branch-push-deny で別 layer block 維持)、`gh pr merge` (user 明示承認必須)
- (緩和、task #39 由来) feature branch への `git push` および `gh pr create` は自律実行可 (modes.md 遵守事項 8 と整合)
- `<外部サービス quota 超過見込み>`
- 同一エラーで 3 回連続失敗、サブエージェントの「要判断」報告
- security-reviewer の CRITICAL、進行不可ブロッカー

### user 主導切替キーワード
「確認しながら」「逐次」「1 つずつ」「止まって」「ブランチ切って」「PR 経由で」

### 報告フォーマット
- Wave 完了時: `Wave N 完了。commit <hash>、<total> tests PASS。次は Wave N+1。`
- 全完了時: `#<番号> <名称> 完了。累計 +<tests>、commit <count>、push 済 <URL>。`

## Rules（`.claude/rules/`）

`paths:` フロントマターで対象ファイルをスコープ指定し、該当ファイルを読んだ時のみ自動ロードされる。

| ルールファイル | スコープ | 内容 |
|--------------|---------|------|
| [`development-process.md`](.claude/rules/development-process.md) | `src/**`, `scripts/**`, `tests/**`, `docs/tasks/**`, `docs/draft/**` | TDD、委譲、指摘対応、タスク管理、設計→承認フロー |
| [`self-improvement.md`](.claude/rules/self-improvement.md) | **(常時参照)** | L1〜L5 自己改善 + F1/F2 事実検証の使い分け規約 |
| [`workflow.md`](.claude/rules/workflow.md) | `docs/draft/**`, `docs/tasks/**`, `.claude/commands/**`, `.claude/hooks/workflow-guard.sh`, `.claude/.workflow-state/**` | workflow 強制 (test-design / design-review / module-review / system-review / new-feature / modify-feature / workflow-guard) |
| [`task-management.md`](.claude/rules/task-management.md) | **(常時参照、task-21 W1.7 で paths 廃止)** | メイン専任 / 設計→承認→タスク追加フロー (Loop モードでも免除されない、`modes.md` 遵守事項 2 例外条項参照) / Parking Lot 運用 / **タスク構造規範 採用 6 条 (Task=Phase=N Step、Phase 中間階層廃止、Step status 5 種、Task 概要欄 3 要素規範、2026-05-25 採用、task-29 採用 5 条 supersede)** / batch planning 経路 B (plan-first 行先置きフロー、task #33 規範化) |
| [`modes.md`](.claude/rules/modes.md) | **(常時参照)** | Normal / Loop モード仕様 + 8 遵守事項 (中間確認禁止の例外条項 / 自律実行禁止 11 カテゴリ含む) |
| [`why-x5-output.md`](.claude/rules/why-x5-output.md) | **(常時参照、v10 2026-05-23)** | 「<何のため> のため、<何をやる> を行う」1 行 format 強制 |
| [`git-workflow.md`](.claude/rules/git-workflow.md) | **(常時参照)** | branch 命名規約 (`<type>/<short-kebab-description>`、main は唯一例外) |

ルール追加・変更時は必ずこのテーブルも更新。

## ハーネス組み込みスラッシュコマンド

| カテゴリ | コマンド |
|---|---|
| タスク | `/init-tasks` `/new-draft` `/new-task` `/start-task` `/finish-task` `/task-bypass` |
| Custom PM / Session | `/save-state` `/resume-state` `/pm-start` |
| Git / レビュー | `/commit` `/reviewpr` |
| 自己改善 L1 (Eval) | `/eval` |
| 自己改善 L2 (GAN) | `/gan-design` `/gan-build` |
| 自己改善 L4 (Learning) | `/instinct-status` `/projects` `/learn` `/evolve` `/promote` `/instinct-export` `/instinct-import` |
| 自己改善 L5 (Introspect) | `/agent-introspect` |
| 事実検証 F1 (GateGuard) | `/gate-status` `/gate-clear` `/gate-bypass` |
| 事実検証 F2 (Verify) | `/verify` |
| Workflow 強制 (W1-W4) | `/test-design` `/design-review` `/module-review` `/system-review` `/new-feature` `/modify-feature` |
| 監査 | `/harness-audit` |

詳細: [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md)

## Design Constraints

- **`.claude/` 単独で portable**: 別 repo に `cp -r .claude` (または `./install.sh <target>`) で即動作する設計を維持。project 固有の値 (URL / path / 個人 token) を `.claude/` 配下にハードコードしない (`.claude/harness-config.yml` 経由で env override 可能にする)
- **保護パス / 配置 / 拡張子は `harness-config.yml` で集中管理**: `protected_paths` / `protected_paths_code` / `task_dir` / `draft_dir` / `bash_whitelist_path` / `code_file_extensions` 等を hook に直接ハードコードしない (`.claude/hooks/lib/config-loader.sh` 経由で `HC_*` env として export)
- **hook の fail policy 統一**: 全 hook は `set -uo pipefail` (errexit 外し) を default、`set -euo pipefail` は subshell 関数化 (`do_work() ( set -euo pipefail; ... )`) でのみ使用。caller の shell flags への leak と SIGPIPE → exit 141 サイレント死を防ぐ (CLAUDE.md Critical Lessons HIGH)
- **規範違反は機械強制 hook で防止**: 「ルールに書いて守らせる」ではなく「hook で BLOCK して守らせる」を default。違反検出 → next-actions entry → draft 起こし → 機械強制 hook 実装の閉ループ (task-21 / task-26 が典型例)
- **機能 on/off は yml feature toggle で集中管理**: hook / command の機能群は `harness-config.yml` の **feature toggle** (`feature_<name>_enabled: true|false`) で集中制御する。各 hook 冒頭で `is_feature_enabled <name>` check を入れて false なら即 no-op で抜ける paired 実装を default 規範とする。新 hook / command 追加時は (1) yml に 1 key 追加 (`feature_xxx_enabled: true` + comment で対象 hook 名明示) (2) hook 冒頭で feature check (3) env 上書きは `HC_FEATURE_XXX_ENABLED` で可能、の 3 点 set を必須とする。これにより「特定機能を試験的に OFF」「regression debug 中の局所無効化」「project 単位の feature 取捨選択」が hook source を触らずに完結する。`hc-config.sh --feature <name>=false` で安全に切替可能 (atomic backup + type validation + 復元は `--reset feature_<name>_enabled`)。詳細: `docs/SELF_IMPROVEMENT.md` §「hc-config.sh による yml 編集」

## Critical Operational Lessons（`<重要操作>`前に必読）

| 教訓 | 重要度 |
|:---|:---:|
| **並列 subagent に同一 branch で `git commit` させる際は `git add <specific files>` 限定 + `git reset` 禁止を prompt 必須記載**。`git reset --soft HEAD^` がメイン / 他 subagent の commit を巻き添えで orphan 化する事故 (2026-05-12, `2bbe079` 混在 → `deda280` orphan → `52a170f` 再 commit で復旧)。完全分離が必要なら `isolation: "worktree"` で worktree 隔離 | HIGH |
| **`.claude/hooks/lib/*.sh` の file-top に `set -euo pipefail` を書かない**。caller の shell flags に leak し、`cmd \| head -1` で SIGPIPE → pipefail → errexit → **exit 141 サイレント終了**。`load_xxx() ( set -uo pipefail; ... )` のように subshell 関数化で局所化する (2026-05-12 CB-verify, `5846925` で根本修正、context-budget hook の未発火問題が解消) | HIGH |
| **Loop モード稼働中、subagent 起動後にメインが `completion 通知の受動待ち` で停止しない**。`run_in_background: true` 必須 + 待ち中は別 task / メイン専任作業 / 規範文書化 / memory 整理 を並行進行する。違反例: subagent #13-#15 起動後にメインがターン区切り報告で停止 → user 「Loop モード継続中。なぜ自動で実行を続けないのか?」を **複数回**指摘 (2026-05-12)。`.claude/hooks/loop-auto-progress-reminder.sh` (UserPromptSubmit) が「待ち中報告」キーワード検出で `<system-reminder>` 強制注入、`modes.md` 遵守事項 7 で機械防止化 | HIGH |
| **Loop モードでも「設計→承認→タスク追加」フローは免除されない**。`modes.md` 遵守事項 2「中間確認の停止」の禁止対象は **戦術判断のみ** (実装中の方式選択 / branch 命名 / commit メッセージ / build green までの試行錯誤)。設計文書の新規追加 / 仕様変更 / scope 拡張 / 戦略的判断 は引き続き user 承認必須 (task-21 W2.1 で modes.md 遵守事項 2 に例外条項明文化、commit `7684c09`) | HIGH |
| **task 構造は採用 6 条 (Task=Phase=N Step、Phase 中間階層廃止) を採用**。task-29 採用 5 条 (Phase→Step 強制、2026-05-23) を 2026-05-25 supersede。新規範: (1) 1 task = 1 Goal + N Steps、Phase 中間階層は廃止 (2) Step status 個別管理 (📝/🔲/🔄/✅/⏸️、list.md sub-row 表現) (3) Task 完了条件 (DoD) は Task header に集約 (4) list.md 概要欄 2 種規約 (Task: 何のため × 何をやる × 何ができる / Step: 作業概要のみ) (5) Task 最終 3 Steps = テスト設計レビュー / テスト合格 / リファクタリング (固定) (6) 既存 task は次回着手時に新構造へ移行推奨 (honor system)。違反例: task-33 が 5 Phase × 14 Step に肥大化、Phase 1 完遂時点の status 判定困難、Step status が IDE 視点で不可視。詳細: `.claude/rules/task-management.md` §タスク構造規範 (採用 6 条) + `docs/draft/task-equals-phase-step-status-list-normative.md` | HIGH |
| **list.md plan-first 不在 → SessionStart hook + Write warn 2 段検出**: batch planning 経路 B (master roadmap で N task 一括計画) で list.md plan-first 先置きを怠ると、26 task 計画下でも list.md 空のまま draft 起案だけ進み user 進捗追跡不可。違反例: 2026-05-25 recall_poc で 26 task batch plan、list.md 空継続 + user 明示質問でようやく顕在化 (task #33 規範化、task #34 `/new-task` の 📝→🔲 update 動作、task #35 SessionStart hook、task #36 PreToolUse(Write) warn の 4 task で対処完了)。再発防止: task #35 SessionStart hook (`docs/draft/*.md` ≥ 3 件 ∧ `list.md` task 行 == 0 で `<system-reminder>` 注入) + task #36 PreToolUse(Write `docs/draft/*.md`) で list.md に対応 slug の 📝 行不在なら warn 注入 (awk col 非依存設計 5/6/7 列 format 進化耐性)。bypass: `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false` (task-35 SessionStart hook) / `ECC_TASKGUARD=off` (task-36 全 OFF) | HIGH |

### hook で完全 BLOCK 強制済の旧教訓 (本表から委譲、2026-05-26 user 指示)

本表は **hook で防げない教訓 (honor system / warn 注入のみ)** に絞り、CLAUDE.md slim 化を優先。以下の旧教訓は hook で機械防止 (BLOCK または warn 注入) されるため本表から委譲した (うち規範文書 `.claude/rules/` 等の BLOCK は **2026-05-28 緩和で撤廃**、honor system に降格):

- **main/stg* push + `gh pr merge` + 本番 deploy 等の自律実行禁止** → `.claude/hooks/autonomous-action-guard.sh` (PreToolUse Bash 11 カテゴリ regex BLOCK、`{"decision":"block"}` 強制) + `.claude/hooks/delegation-guard.sh` の `protected-branch-push-deny` layer 二重ガード。bypass: `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` / `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` (痕跡 `bypass.log`)。詳細: `.claude/rules/modes.md` 遵守事項 8 + 自律実行禁止 11 カテゴリ table。task-39 緩和 (2026-05-25) で feature branch push + `gh pr create` は自律実行可、main/stg* push と `gh pr merge` のみ user 明示承認必須
- **`.claude/hooks/*.sh` / `.claude/skills/**/*.{sh,py,mjs}` / `.claude/scripts/**/*` 直接 Edit/Write 禁止** → `.claude/hooks/delegation-guard.sh` (`HC_PROTECTED_PATHS_CODE` + `HC_CODE_FILE_EXTENSIONS` BLOCK)。回避は subagent 委譲 + staging 戦略 (`/tmp` Write → `mv` → `chmod +x`) 必須。bypass: `ECC_ALLOW_MAIN_CODE_EDIT=1`。詳細: `.claude/rules/development-process.md` §「サブエージェント `.claude/` 編集の staging 戦略」
- **`docs/` 直下に新規設計文書 (要件 / 基本設計 / 機能一覧等) 直接 Write 禁止** → `.claude/hooks/draft-flow-guard.sh` (`docs/` 深さ 1 新規 .md/.mdx BLOCK、対応 draft 存在で pass)。`docs/draft/<slug>.md` 起こし → 承認 → `docs/tasks/list.md` 反映の 3 step フロー必須。bypass: `ECC_DRAFT_FLOW_GUARD_OVERRIDE=1` or `harness-config.yml draft_flow_guard_whitelist`
- **(2026-05-28 緩和) `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` は Edit/Write とも許容 (draft 経由不要)** → 旧 task-40 拡張 (2026-05-26) は `.claude/hooks/draft-flow-guard.sh` でこれらの **新規 Write** を draft 承認 (`approved_at` 非空 or `retroactive: true`) 不在で BLOCK していたが、user 直接指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」(2026-05-28) で **task-40 拡張部分を撤廃**。これらの規範文書 path は新規 Write / 既存 Edit とも PASS となり、本 hook は一切監視しない (frontmatter parser + 新 path pattern 判定 + retroactive 厳格化ロジックを hook から削除)。bypass env `ECC_RULE_CHANGE_GUARD_OFF` / `HC_RULE_CHANGE_GUARD_ENABLED` は dead path (後方互換で残置、hook は参照しない)。**規範文書の物理 BLOCK は本緩和で解消されたため、規範変更の draft 経由フローは honor system に降格** (`docs/` 直下の設計文書 block は L116 通り維持)。なお `.claude/rules/*.sh` 等の **code file** は依然 `delegation-guard.sh` で BLOCK 対象 (L115)、本緩和は `.md` 規範文書のみ。起源: 2026-05-26 task-40 (実装) → 2026-05-28 user 指示 (緩和・撤廃)
- **Loop モード時の確認質問は禁止** → `.claude/hooks/loop-confirmation-detector.sh` (Stop hook) が AI 最終 message を regex 検出 (「進めてよいですか」「OK ですか」「お待ちします」「次の指示お待ち」等) → `<system-reminder>` で次 turn 自律是正を強制 (BLOCK ではなく warn 注入で物理的に止めない、次 turn で AI が自律是正)。bypass: `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` (config 系統) / `ECC_LOOP_CONFIRMATION_OFF=1` (env 系統)。起源: 2026-05-26 task-41、本 session で user 「Loopモードなのに聞いてきます」+ 別 session log 「Loop モード自律 patch 着手で OK ですか?」貼付指摘の再発防止

事故事例 / 真因 / 規範化経緯は git log + `.claude/rules/development-process.md` + `.claude/rules/workflow.md` + 各 hook source 参照。

その他の教訓は memory `feedback_*.md` を参照。

## ハーネスドキュメント

- [`README.md`](README.md) — 概要 + 採用 5 ステップ
- [`docs/INVENTORY.md`](docs/INVENTORY.md) — 全構成要素の Path 表
- [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md) — L1〜L5 + F1/F2 + 監査の詳細
