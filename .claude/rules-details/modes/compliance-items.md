> Layer A: [`modes.md`](../../rules/modes.md) §Loop モード遵守事項 (9 件) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 遵守事項 詳細 (Layer B)

本 file は Layer A の SSoT を補完する詳細解説。Loop モード遵守事項 9 件の例外条項詳細 / 違反例 / 緩和経緯 / 起源を含む。

## 遵守事項 2 例外条項の起源と詳細

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

## 遵守事項 7 (subagent 並走中の独立作業義務) 詳細と違反例

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

## 遵守事項 8 (自律実行禁止リスト) 11 カテゴリ 例外詳細

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

## 遵守事項 8 (自律実行禁止リスト) 緩和経緯詳細

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

## 遵守事項 9 (Loop モード = list.md 全 task 連続自律実行) 起源 task-47 詳細

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
