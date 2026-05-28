---
paths: []
related: modes.md
---

# HIRAI メソッド 動作モード — 詳細版 (Layer B)

> Layer A: [`modes.md`](./modes.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

本 file は Layer A の SSoT を補完する詳細解説。Loop モード遵守事項 9 件の例外条項詳細 / 違反例 / 緩和経緯 / 5 層強制機構の各層動作 / smoke list 完全版 / mode hook 内部仕様 / 関連 artifact 完全 list / 起源を含む。Read trigger 4 条件は Layer A 冒頭参照。

## 遵守事項 詳細

### 遵守事項 2 例外条項の起源と詳細

**起源 (recall_poc/docs/01-03 事案、task-21 W2.1、2026-05-23)**:
- 2026-05-23 user 観察「recall_poc/docs/01-03 が draft 経由なしで docs/ 直下に直接 Write された事案」
- `task-management.md` の「設計→承認→タスク追加フロー」と相反していた構造問題を例外条項で解消
- Loop モードの中間確認禁止が「設計文書の新規追加」まで暴走することを防止

**起源 (規範変更、task-40 + 2026-05-28 緩和)**:
- 2026-05-26 task-40 Step 5: 本 session 規範違反 (規範変更時 draft skip) の再発防止として `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への新規 Write に対して `draft-flow-guard.sh` で機械強制 BLOCK を実装
- 2026-05-28 user 直接指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」で **task-40 拡張部分を撤廃**
- 規範文書 path は新規 Write / 既存 Edit とも hook で PASS、本 hook は一切監視しない
- 機械強制ではなく **規律として残す方針** (honor system)
- bypass env `ECC_RULE_CHANGE_GUARD_OFF` / `HC_RULE_CHANGE_GUARD_ENABLED` は dead path (後方互換で残置、hook は参照しない)

**禁止対象の境界 (戦術判断 vs 戦略判断)**:

| カテゴリ | 例 | 確認要否 |
|---|---|---|
| **戦術判断** (禁止対象) | 実装中の方式選択 / branch 命名 / commit メッセージ / 一時的なエラー対処 / build green までの試行錯誤 | 確認不要 (即採用) |
| **戦略判断** (例外、確認必須) | 設計文書新規追加 / 仕様変更 / scope 拡張 / architecture 選択 / 採用技術スタック変更 / 既存 task 優先順入替 | 確認必須 |
| **規範変更** (例外、honor system) | `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` 編集 | user 確認推奨 / 設計→承認フロー推奨 (機械強制 BLOCK は 2026-05-28 撤廃) |

### 遵守事項 7 (subagent 並走中の独立作業義務) 詳細と違反例

**設計起源**: `docs/draft/loop-auto-progress-enforcement.md` (採用プロジェクト側、本 harness は portable 設計のため起源 draft path のみ参照)。

**違反例 (2026-05-12、subagent #13-#15 起動後の停止事案)**:
- subagent #13-#15 を `run_in_background: true` で起動後、メインが「completion 通知の受動待ち」でターン区切り報告で停止
- user 「Loop モード継続中。なぜ自動で実行を続けないのか?」を **複数回**指摘
- 結果: `.claude/hooks/loop-auto-progress-reminder.sh` (UserPromptSubmit) を導入し、「待ち中報告」キーワード検出で `<system-reminder>` 強制注入
- 機械防止化により「subagent 完了通知後のメイン報告 → 即次タスク自動起動」を default 動作として強制

**並行作業の優先順位**:

| 順位 | 並行作業内容 | 理由 |
|---|---|---|
| 1 | 別の独立 task 着手 (`docs/tasks/list.md` 🔲 行) | 全体進捗を最大化 |
| 2 | メイン専任作業 (タスク管理 / list.md sync / task ファイル生成 / draft 起こし) | サブエージェント完了待ち中の生産的活動 |
| 3 | 規範文書化 (`.claude/rules/` 編集 / `CLAUDE.md` 更新) | 学習機会の活用 |
| 4 | memory / `next-actions.md` 整理 | 軽量タスクで context を温存 |

**「並行作業できない」と判定可能なケース** (停止 OK):
- 依存関係: 全独立 task が背景 subagent に着手済で残 task が依存待ち
- 全 task 着手済: list.md 🔲 行が 0 件
- 上記以外で停止すれば違反、即 hook 強制が発火

### 遵守事項 8 (自律実行禁止リスト) 11 カテゴリ 例外詳細

各カテゴリの「準備として OK」例外を明示。Layer A は条文のみ、本表で実運用 boundary を確認:

| カテゴリ | 対象コマンド / 操作 | 例外 (準備として OK) |
|---|---|---|
| remote 反映 | `git push origin main\|stg*` のみ (protected-branch-push-deny で別 layer block) | feature branch push は自律可 (task #39 緩和) / ローカル `git commit` |
| PR / リリース | `gh pr merge` / `gh release create` / `git tag <name> origin` (tag push) | `gh pr create` は自律可 (task #39 緩和) / task ファイル / draft 起こし |
| main 操作 | main への merge / main checkout 後の編集 | feature branch 編集 |
| DB 作業 | migration 実行 / `INSERT/UPDATE/DELETE` 直接実行 / dump / restore | migration script 作成 (実行しない) |
| 本番 deploy | `vercel --prod` / `supabase deploy` / production environment 触る操作 | preview / staging deploy |
| secrets | `.env*` 編集 / API key 生成・ローテーション / OAuth token 操作 | `.env.example` 更新 |
| 外部通知 | Slack post / メール送信 / Asana タスク作成・更新 | 通知文 draft |
| CI/CD | `.github/workflows/` 編集 + push | local workflow 編集 (push しない) |
| license / public | LICENSE 変更 / README 公開アピール変更 / `package.json` major bump | minor / patch bump 検討 |
| subagent への委譲拡張 | 上記操作を subagent prompt で許可すること | 上記禁止項目を除外した prompt |
| 第三者リポ | submodule update / fork 外への push / `gh repo` 操作 | submodule branch 確認 |

### 遵守事項 8 (自律実行禁止リスト) 緩和経緯詳細

**緩和 1: task #39 (2026-05-25) — feature branch push + gh pr create 自律実行可**

| 項目 | 緩和前 | 緩和後 |
|---|---|---|
| feature branch への `git push` | user 明示承認必須 | **自律実行可** |
| `gh pr create` (feature branch から PR 作成) | user 明示承認必須 | **自律実行可** |
| main / stg* への `git push` | user 明示承認必須 | **継続 user 承認必須** (別 layer `protected-branch-push-deny` に委譲) |
| `gh pr merge` | user 明示承認必須 | **継続 user 承認必須** |

**起源**: 2026-05-25 task #39 + 2026-05-27 task-48 PR #22 で再実証 (feedback memory `claude_permission_git_push_deny.md` 参照)。

**緩和 2: mode-switch bypass log (2026-05-13、task #9)**

Normal モードで禁止パターン match した cmd 実行は `.claude/.workflow-state/bypass.log` に `mode-normal-restricted-cmd` として記録される:

| 項目 | 仕様 |
|---|---|
| OFF env | `HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED=false` |
| 記録内容 | timestamp / cmd 抜粋 / カテゴリ / mode-normal-restricted-cmd マーカー |
| audit 用途 | 「Loop モード規律を一時的に外して破壊的操作を実行した」事実が audit log に残るため `/harness-audit` でトレース可能 |

**bypass log の用途分離**:

| カテゴリ | 記録対象 | 用途 |
|---|---|---|
| `mode-normal-restricted-cmd` | Normal モードで禁止パターン実行 | audit trail (規律外し痕跡) |
| `autonomous-action-guard` | Loop モードで `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` bypass | bypass 理由追跡 |
| `HC_AUTONOMOUS_ACTION_ENABLED=false` | config レベル OFF | config 状態追跡 |

### 遵守事項 9 (Loop モード = list.md 全 task 連続自律実行) 起源 task-47 詳細

**起源**: 2026-05-27 user 直接指示「ループモードはタスクリストから可能な限り進めて欲しい + 閾値到達か続行不可で自動 save-state」、設計 draft `docs/draft/loop-mode-list-md-auto-enque.md`、規範化 task `#47`。

**実装仕様 (Phase 6 詳細)**:

| step | 動作 |
|---|---|
| 3a | list.md から **🔄 進行中** task を抽出 |
| 3b | 続けて **🔲 未着手** task を依存解決順 (DAG 解析) で抽出 |
| 3c | 各 task の draft frontmatter `approved_at:` を確認、非空のみ自律着手可とフラグ |
| 3d | draft 不在 / 未承認 task は user 確認必須項目として stop pool に分類 |
| 3e | 自律着手可 task を順に enque、subagent 並列起動 (run_in_background: true) |
| 4 | 各 task 完了で `/finish-task <id>` 実行 + 次 task 自動起動 |
| 5 | 停止条件 3 つ (context 閾値 / 続行不可 / user 明示停止) 監視 |
| 6 | 停止時に自動 `/save-state` + 残 task 列挙案内 |
| 7 | 新 session で `/resume-state loop` で継続 (state file から復元) |

詳細は `.claude/commands/resume-state.md` Phase 6 step 3a-3e + step 4-7 を参照。

## 5 層強制機構 詳細

### 各層の動作 source code 参照

| 層 | source path | 主要 logic |
|---|---|---|
| 1 | `.claude/rules/modes.md` (本 file 規範) | 遵守事項 7 (subagent 待ち独立作業) + 8 (自律禁止 11 カテゴリ) |
| 2 | `.claude/hooks/loop-auto-progress-reminder.sh` | UserPromptSubmit hook、毎ターン「待ち中報告」regex 検出 + pending Agent tool_use 数集計 → `<system-reminder>` 注入 |
| 3 | `.claude/hooks/autonomous-action-guard.sh` | PreToolUse(Bash) hook、11 カテゴリ regex 照合 → Loop なら `{"decision":"block"}` exit 2 / Normal なら context 注入 + bypass.log 記録 |
| 4 | `.claude/settings.json` (hooks セクション) | UserPromptSubmit 末尾 + PreToolUse Bash 先頭に 5 層 hook を配置 |
| 5 | `.claude/tests/loop-auto-progress-smoke.sh` | 9 ケース smoke (Loop モード ON/OFF × 待ち中報告検出 / 11 カテゴリ block / bypass 動作) |
| 6 | `.claude/hooks/loop-confirmation-detector.sh` | Stop hook、AI 最終 message 出力後に確認質問 regex 検出 → `<system-reminder>` 強制注入で次 turn 自律是正 |

### smoke list 完全版 (9 ケース、`loop-auto-progress-smoke.sh`)

| ケース | 入力 | 期待 |
|---|---|---|
| 1 | Loop モード + 「subagent 完了待ち」発話 | `<system-reminder>` 注入 |
| 2 | Loop モード + pending Agent tool_use 数 ≥ 1 | reminder 注入 |
| 3 | Loop モード + 通常発話 | no-op |
| 4 | Normal モード + 「待ち中」発話 | no-op (Normal は監視外) |
| 5 | Loop モード + `git push origin main` | `{"decision":"block"}` (層 3) |
| 6 | Loop モード + `git push origin feat/xxx` | PASS (task #39 緩和) |
| 7 | Loop モード + `gh pr create` | PASS (task #39 緩和) |
| 8 | Loop モード + `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` + `git push origin main` | PASS + bypass.log 記録 |
| 9 | Loop モード + `HC_AUTONOMOUS_ACTION_ENABLED=false` + `gh pr merge` | PASS + bypass.log 記録 |

### 層 6 (loop-confirmation-detector.sh) task-41 起源

**起源**: 2026-05-26 task-41。

**事案**: 別 session log で「Loop モード自律 patch 着手で OK ですか?」と AI が確認質問を発した事案を user が貼付指摘 (本 session でも user 「Loopモードなのに聞いてきます」指摘あり)。

**設計**:
- Stop hook (AI 最終 message 出力後) で確認質問 regex 検出: 「進めてよいですか」「OK ですか」「お待ちします」「次の指示お待ち」「どちらにしますか」「どうしますか」等
- match 時に `<system-reminder>` で次 turn 自律是正を強制 (BLOCK ではなく warn 注入で物理的に止めない、次 turn で AI が自律是正)
- bypass: `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` (config 系統) / `ECC_LOOP_CONFIRMATION_OFF=1` (env 系統)

**他 5 層との差別化**:
- 層 2 (loop-auto-progress-reminder) = UserPromptSubmit (user 発話を受けた直後の AI 思考前)
- 層 6 (loop-confirmation-detector) = Stop (AI 最終 message が出力された直後)
- 両者で「AI の確認質問発話」を時系列の両端から防止

## mode hook 詳細

### mode-loader.sh 内部仕様

`.claude/hooks/lib/mode-loader.sh` は全 mode 系 hook で source される共通 lib。

**API**:
- `get_mode()` — 現モードを stdout に出力 (`normal` or `loop`)
- 値解決順: `env(HC_MODE)` > `.claude/mode.yml` の `mode:` キー > `default(normal)`
- 値検証: 不正値は `normal` にフォールバック + stderr 警告

**fail policy**:
- `set -uo pipefail` (file-top に書かない、subshell 関数化で局所化、caller の shell flags への leak 防止)
- yml parse 失敗 → `normal` fallback (fail-open、セッション継続)

### mode-session-start.sh の context 注入

| 状況 | 動作 |
|---|---|
| Normal モード | 「現在 Normal モード。Loop モードへの切替は `/mode loop`」を SessionStart で 1 度だけ提案 |
| Loop モード | 「現在 Loop モード。停止は `/mode normal` or 「ストップ」発話」を表示 |
| mode.yml 不在 | `normal` 扱いで切替提案 (fail-open) |

### mode-enforce.sh の context 注入

| 状況 | 動作 |
|---|---|
| Loop モード | 毎ターン UserPromptSubmit で遵守事項 9 件を `<system-reminder>` で再注入 |
| Normal モード | no-op |
| 注入内容 | 遵守事項 9 件の見出しのみ (本文は modes.md 参照と link)、context 節約 |

### context-budget.sh tier 算出ロジック

| tier | ratio 閾値 | 動作 |
|---|---|---|
| 60 | `ratio >= 0.60` | `<system-reminder>` で `/save-state` 提案 |
| 80 | `ratio >= 0.80` | `<system-reminder>` で `/save-state` **強制実行** + 「新 session で `/resume-state` で復元するか継続するか」を user に提示 |
| 95 | `ratio >= 0.95` | `<system-reminder>` で緊急 `/save-state` + セッション終了案内 |

**spam 防止**:
- 同一 tier は 1 セッションあたり 1 度のみ発火
- 状態は `.claude/.workflow-state/context-budget-tiers.json` で永続化
- bypass: `HC_CONTEXT_BUDGET_ENABLED=false` で hook 全停止

**閾値変更**:
- `.claude/harness-config.yml` の `context_budget_threshold:` キーで上書き可
- `hc-config.sh --set context_budget_threshold='[60,80,95]'` で安全に変更可 (atomic backup + type validation)

## 関連 artifact 完全 list

### mode 系 hook

- `.claude/hooks/mode-session-start.sh` (SessionStart、モード表示 / 切替提案)
- `.claude/hooks/mode-enforce.sh` (UserPromptSubmit、遵守事項再注入)
- `.claude/hooks/context-budget.sh` (UserPromptSubmit、context tier 監視)
- `.claude/hooks/lib/mode-loader.sh` (共通 lib、mode 解決)

### 5 層強制機構

- `.claude/rules/modes.md` (層 1、規範本体 = 本 file の Layer A)
- `.claude/hooks/loop-auto-progress-reminder.sh` (層 2、UserPromptSubmit)
- `.claude/hooks/autonomous-action-guard.sh` (層 3、PreToolUse Bash)
- `.claude/settings.json` (層 4、hook 配線)
- `.claude/tests/loop-auto-progress-smoke.sh` (層 5、9 ケース smoke)
- `.claude/hooks/loop-confirmation-detector.sh` (層 6、Stop hook)

### 設定 / state

- `.claude/mode.yml` (mode 永続化、`mode: normal|loop`)
- `.claude/harness-config.yml` (`context_budget_threshold` / `HC_*` env 集中管理)
- `.claude/.workflow-state/bypass.log` (bypass 追跡 audit log)
- `.claude/.workflow-state/context-budget-tiers.json` (tier 発火状態)

### 設計起源 draft (採用プロジェクト側、本 harness は portable 設計のため path のみ参照)

- `docs/draft/loop-auto-progress-enforcement.md` (遵守事項 7+8 起源)
- `docs/draft/loop-mode-list-md-auto-enque.md` (遵守事項 9 起源、task #47)
- `docs/draft/task-equals-phase-step-status-list-normative.md` (task-management.md 採用 6 条と連動)

## 起源 (history 全体)

- **Loop モード規範化**: 2026-05-12 task-21 W0.1 で遵守事項 1-8 を策定 (subagent 並走中の停止事案を機械防止化)
- **遵守事項 2 例外条項**: 2026-05-23 task-21 W2.1 で「設計→承認→タスク追加フロー」との相反を解消 (recall_poc/docs/01-03 事案起源)
- **task #9 (2026-05-13)**: mode-switch bypass log 追加、Normal モードで禁止パターン実行を audit trail として記録
- **task #39 (2026-05-25)**: feature branch push + gh pr create 自律実行可へ緩和、main/stg* は別 layer 委譲
- **task-40 (2026-05-26)**: 規範変更 (`.claude/rules/*.md` 等) draft skip 事案の再発防止 → 2026-05-28 緩和で機械強制 BLOCK 撤廃、honor system に降格
- **task-41 (2026-05-26)**: 層 6 (loop-confirmation-detector.sh) 追加、確認質問発話の自律是正
- **task #47 (2026-05-27)**: 遵守事項 9 (list.md 全 task 連続自律実行) 新設
- **task-48 (2026-05-27)**: PR #22 で feature branch push + gh pr create の自律実行を再実証 (memory `claude_permission_git_push_deny.md` 更新)
- **task-51 Step 3 (2026-05-28)**: 本 Layer A/B 2 層分割

各 task の commit hash / 採用判断は git log + 採用プロジェクト側 `docs/tasks/<task-N>.md` を参照。
