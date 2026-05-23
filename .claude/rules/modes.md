# HIRAI メソッド 動作モード

HIRAI メソッドは 2 つの動作モードを持つ。

## モード一覧

### Normal モード（既定値）

- 重要分岐でユーザに確認を求めながら進める
- Why × 5 出力（`why-x5-output.md`）は常時 ON
- セッション開始時に Loop モードへの切替を **1 度だけ提案** する

### Loop モード

ユーザの明示的な停止指示まで、AI が推奨する方法を即採用して実装を継続する。

**遵守事項**:
1. **AI 推奨方法を即採用**: 複数選択肢がある場合、ユーザに確認を求めず Why × 5 で評価して推奨を採用
2. **中間確認の停止**: 「進めてもよいですか?」「どちらにしますか?」等の質問は禁止
   - **例外 (task-21 W2.1)**: 以下は禁止対象外、引き続き user 確認必須:
     - **設計文書の新規追加** (`docs/draft/<slug>.md` の新規起こし + user 承認依頼)
     - **仕様変更 / scope 拡張** (承認済 draft の §3 採用案からの逸脱)
     - **戦略的判断** (architecture 選択 / 採用技術スタック変更 / 既存 task の優先順入替)
   - 禁止対象は **戦術判断のみ**: 実装中の方式選択 / branch 命名 / commit メッセージ / 一時的なエラー対処 / build green までの試行錯誤
   - 起源: 2026-05-23 user 観察「recall_poc/docs/01-03 が draft 経由なしで docs/ 直下に直接 Write された事案」、`task-management.md` の「設計→承認→タスク追加フロー」と相反していた構造問題を例外条項で解消
3. **自律分解と継続**: 大きなタスクは自ら分解し最後まで通す
4. **Why × 5 表示の維持**: 確認は省くが、思考過程の透明性は失わない
5. **適切な粒度でコミット**（必須）: 自律実装中も論理単位（1 機能 / 1 修正 / 1 リファクタ）ごとに `git commit` を切る
   - 各コミットは **独立して動作する状態** を保つ（テスト通過 / build green）
   - コミットメッセージは Conventional Commits 形式（`feat:` `fix:` `refactor:` 等）
   - これにより失敗時に `git revert <sha>` や `git reset --hard <sha>` で **戻せる**
   - 巨大コミット（複数機能を 1 つに混ぜる）は禁止 — 復旧粒度が失われるため
6. **Context 使用率の自動監視と保存**（必須）: `context-budget.sh` hook が毎ターン context 使用率を監視する
   - 使用率が **60% / 80% / 95%** の各 tier を初めて超えた時、`<system-reminder>` で警告が注入される
   - 警告を受けたメインは **このターン内で必ず `/save-state` を実行** してセッション状態を永続化
   - 続けてユーザに「新セッションで `/resume-state` で復元するか継続するか」を提案する
   - 同一 tier は 1 セッションあたり 1 度のみ発火（spam 防止）
   - 閾値は `.claude/harness-config.yml` の `context_budget_threshold` で変更可能
   - 一時無効化: `HC_CONTEXT_BUDGET_ENABLED=false`

7. **subagent 並走中の独立作業義務**（必須）: subagent を `run_in_background: true` で起動した後、completion 通知を **受動的に待つだけ** は禁止。設計起源: `docs/draft/loop-auto-progress-enforcement.md`。
   - メインは以下のいずれかを並行進行すること:
     - 別の独立 task (`docs/tasks/list.md` の `🔲 未着手` 行) を着手
     - メイン専任作業 (タスク管理 / `list.md` sync / `_TASK_TEMPLATE.md` から task ファイル生成 / `docs/draft/` 起こし)
     - 規範文書化 (`.claude/rules/` 編集 / `CLAUDE.md` 更新)
     - memory / `next-actions.md` 整理
   - 並行作業ができない場合（依存関係 / 既に全 task 着手済）のみターン区切り報告で停止可
   - **「subagent 完了通知後のメイン報告 → 即次タスク自動起動」を default 動作とする**
   - 違反検出時の hook 強制 (W2 で実装予定): `.claude/hooks/loop-auto-progress-reminder.sh` が UserPromptSubmit で「待ち中停止」キーワードを検出し `<system-reminder>` 強制注入

8. **自律実行禁止リスト**（必須）: Loop モードでも以下の操作は **user の明示承認が必要**。準備（draft / 設計 / ローカル `git commit`）のみ自律可。設計起源: `docs/draft/loop-auto-progress-enforcement.md`。

   | カテゴリ | 対象コマンド / 操作 | 例外（準備として OK） |
   |---|---|---|
   | remote 反映 | `git push` (any branch) | ローカル `git commit` |
   | PR / リリース | `gh pr create` / `gh pr merge` / `gh release create` / `git tag <name> origin` (tag push) | task ファイル / draft 起こし |
   | main 操作 | main への merge / main checkout 後の編集 | feature branch 編集 |
   | DB 作業 | migration 実行 / `INSERT/UPDATE/DELETE` 直接実行 / dump / restore | migration script 作成（実行しない） |
   | 本番 deploy | `vercel --prod` / `supabase deploy` / production environment 触る操作 | preview / staging deploy |
   | secrets | `.env*` 編集 / API key 生成・ローテーション / OAuth token 操作 | `.env.example` 更新 |
   | 外部通知 | Slack post / メール送信 / Asana タスク作成・更新 | 通知文 draft |
   | CI/CD | `.github/workflows/` 編集 + push | local workflow 編集（push しない） |
   | license / public | LICENSE 変更 / README 公開アピール変更 / `package.json` major bump | minor / patch bump 検討 |
   | subagent への委譲拡張 | 上記操作を subagent prompt で許可すること | 上記禁止項目を除外した prompt |
   | 第三者リポ | submodule update / fork 外への push / `gh repo` 操作 | submodule branch 確認 |

   違反検出時の hook 強制: `.claude/hooks/autonomous-action-guard.sh` が PreToolUse(Bash) で対象コマンドを `exit 2` BLOCK。bypass: `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` (user の明示承認をセッション env で表明)、`.claude/.workflow-state/bypass.log` に記録。

   - **mode-switch bypass の log** (2026-05-13、task #9): Normal モードで禁止パターン match した cmd 実行は `.claude/.workflow-state/bypass.log` に `mode-normal-restricted-cmd` として記録される。env `HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED=false` で OFF 可。「Loop モード規律を一時的に外して破壊的操作を実行した」事実が audit log に残るため `/harness-audit` でトレース可能。

   honor system (hook 未実装パスの場合): メインは自律実行せず、user に「実行を承認しますか?」と提示してから実行する。

**停止条件は以下 3 つのみ**:
- ユーザの明示的な停止指示（"stop" / "ストップ" / "止めて" 等）
- タスクの完了
- 致命的エラー（権限拒否 / 復旧不能 / 重大なデータ破壊リスク）

## Loop モード自律規律の 5 層強制機構

タスク実装中・Loop モード稼働中の「subagent 完了待ち停止」「破壊的操作の自律実行」を **5 層強制** で構造防止する。設計の経緯と承認履歴は採用プロジェクト側の `docs/draft/` を参照 (本ルールは `.claude/` 単独で portable)。

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
- [`.claude/hooks/loop-auto-progress-reminder.sh`](../hooks/loop-auto-progress-reminder.sh)
- [`.claude/hooks/autonomous-action-guard.sh`](../hooks/autonomous-action-guard.sh)
- [`.claude/tests/loop-auto-progress-smoke.sh`](../tests/loop-auto-progress-smoke.sh)
- 設計の起源と承認履歴は採用プロジェクト側 `docs/draft/` / `docs/tasks/` を参照

## 設定

モードは `.claude/mode.yml` で永続化される。値は `normal` か `loop`。

```yaml
mode: normal  # または loop
```

## 切替方法

| 方法 | 用途 |
|---|---|
| `/mode loop` / `/mode normal` slash command | セッション中の切替（推奨） |
| `.claude/mode.yml` 直接編集 | 手動切替 |
| `HC_MODE=loop` 環境変数 | YAML を触らず一時切替 |

値解決の優先順（高 → 低）: `env(HC_MODE)` > `mode.yml` > `default(normal)`

## 強制機構

| Hook | タイミング | 役割 |
|---|---|---|
| `.claude/hooks/mode-session-start.sh` | SessionStart | 現モード表示 / normal 時に切替提案 |
| `.claude/hooks/mode-enforce.sh` | UserPromptSubmit | Loop モード時に毎ターン遵守事項を再注入 |
| `.claude/hooks/context-budget.sh` | UserPromptSubmit | Loop モード時に context 使用率を監視し、60/80/95% 超で `/save-state` 実行 + 再開提案を強制 |

全て `.claude/hooks/lib/mode-loader.sh` で現モードを解決する（Normal モードでは全て no-op）。

## モードと既存ルールの関係

| ルール | Normal | Loop |
|---|---|---|
| `why-x5-output.md` (Why × 5 表示) | ON | ON |
| 中間確認質問 | 要 | 禁止 |
| サブエージェント委譲（`delegation-guard.sh`） | 要 | 要 |
| 事実検証（`gateguard.sh`） | 要 | 要 |

Loop モードでも委譲・事実検証等の安全ガードは無効化されない。**省略するのはユーザ確認のみ**。
