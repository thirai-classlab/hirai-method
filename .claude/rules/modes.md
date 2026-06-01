<!--
task-21 W0.1: Loop モード遵守事項規範化 (主に遵守事項 7+8 起源)。
task-39 (2026-05-25): feature branch push + gh pr create 自律実行可へ緩和。
task-41 (2026-05-26): Loop モード確認質問検出 (層 6) 追加。
task-47 (2026-05-27): 遵守事項 9 (list.md 全 task 連続自律実行) 新設。
task-51 Step 3 (2026-05-28): Layer A/B 2 層分割。
task-67 (2026-06-01): Layer B を 5 断片に分割、断片直リンク方式へ移行。
-->

# HIRAI メソッド 動作モード

HIRAI メソッドは **Normal / Loop** 2 つの動作モードを持つ。Loop モードはユーザの明示停止指示まで AI 推奨方法を即採用して実装継続。本 rule は **9 遵守事項 / 自律実行禁止 11 カテゴリ / 5 層強制機構 / mode 切替方法 / context-budget hook tier** の SSoT。常時参照 (frontmatter 無し、毎セッション AI が読む)。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: 各 § 末尾 pointer から該当断片を直リンク Read (断片群: [`../rules-details/modes/`](../rules-details/modes/))

## モード一覧

### Normal モード（既定値）

- 重要分岐でユーザに確認を求めながら進める
- Why × 5 出力（`why-x5-output.md`）は常時 ON
- セッション開始時に Loop モードへの切替を **1 度だけ提案** する

### Loop モード

ユーザの明示的な停止指示まで、AI が推奨する方法を即採用して実装を継続する。

## Loop モード遵守事項 (9 件)

1. **AI 推奨方法を即採用**: 複数選択肢がある場合、ユーザに確認を求めず Why × 5 で評価して推奨を採用
2. **中間確認の停止**: 「進めてもよいですか?」「どちらにしますか?」等の質問は禁止
   - **例外**: 以下は禁止対象外、引き続き user 確認必須:
     - **設計文書の新規追加** (`docs/draft/<slug>.md` の新規起こし + user 承認依頼)
     - **仕様変更 / scope 拡張** (承認済 draft の §3 採用案からの逸脱)
     - **戦略的判断** (architecture 選択 / 採用技術スタック変更 / 既存 task の優先順入替)
     - **規範変更** (`.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への Edit/Write) — honor system (機械強制 BLOCK は 2026-05-28 撤廃)
   - 禁止対象は **戦術判断のみ**: 実装中の方式選択 / branch 命名 / commit メッセージ / 一時的なエラー対処 / build green までの試行錯誤
3. **自律分解と継続**: 大きなタスクは自ら分解し最後まで通す
4. **Why × 5 表示の維持**: 確認は省くが、思考過程の透明性は失わない
5. **適切な粒度でコミット** (必須): 自律実装中も論理単位 (1 機能 / 1 修正 / 1 リファクタ) ごとに `git commit` を切る
   - 各 commit は **独立して動作する状態** を保つ (テスト通過 / build green)
   - メッセージは Conventional Commits 形式 (`feat:` `fix:` `refactor:` 等)
   - 失敗時 `git revert <sha>` / `git reset --hard <sha>` で **戻せる**粒度を維持
   - 巨大コミット (複数機能を 1 つに混ぜる) は禁止
6. **Context 使用率の自動監視と保存** (必須): `context-budget.sh` hook が毎ターン context 使用率を監視
   - **60% / 80% / 95%** の各 tier を初めて超えた時、`<system-reminder>` で警告注入
   - 警告受領 → **このターン内で必ず `/save-state` 実行** + 「新 session で `/resume-state` で復元するか継続するか」を提案
   - 同一 tier は 1 セッションあたり 1 度のみ発火 (spam 防止)
   - 閾値は `.claude/harness-config.yml` の `context_budget_threshold` で変更可
   - 一時無効化: `HC_CONTEXT_BUDGET_ENABLED=false`
7. **subagent 並走中の独立作業義務** (必須): subagent を `run_in_background: true` で起動後、completion 通知を **受動的に待つだけ** は禁止
   - メインは以下のいずれかを並行進行: (a) 別の独立 task 着手 (b) メイン専任作業 (タスク管理 / list.md sync / task ファイル生成 / draft 起こし) (c) 規範文書化 (d) memory / next-actions.md 整理
   - 並行作業ができない場合 (依存関係 / 既に全 task 着手済) のみターン区切り報告で停止可
   - **「subagent 完了通知後のメイン報告 → 即次タスク自動起動」を default 動作**
   - **多数 fan-out は構造化** (task-68): 3 件以上の独立 subagent 起動は `Workflow` ツール default 検討 / 手書きは 2 件/ターン上限 (長 prompt は file 経由) で markup 崩れ loop を防ぐ。詳細は [`development-process.md`](./development-process.md) §「多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限」
8. **自律実行禁止リスト** (必須): Loop モードでも以下 11 カテゴリは **user 明示承認が必要**。準備 (draft / 設計 / ローカル `git commit`) のみ自律可。**2026-05-25 task #39 で緩和**: feature branch (= main / stg* 以外) への `git push` および `gh pr create` を自律実行可とした (main/stg* への push は別 layer `protected-branch-push-deny` に委譲)。

   - **remote 反映**: `git push origin main|stg*` のみ (feature branch push は自律可)
   - **PR / リリース**: `gh pr merge` / `gh release create` / `git tag <name> origin` (`gh pr create` は自律可)
   - **main 操作**: main への merge / main checkout 後の編集
   - **DB 作業**: migration 実行 / `INSERT/UPDATE/DELETE` 直接実行 / dump / restore
   - **本番 deploy**: `vercel --prod` / `supabase deploy` / production environment 触る操作
   - **secrets**: `.env*` 編集 / API key 生成・ローテーション / OAuth token 操作
   - **外部通知**: Slack post / メール送信 / Asana タスク作成・更新
   - **CI/CD**: `.github/workflows/` 編集 + push
   - **license / public**: LICENSE 変更 / README 公開アピール変更 / `package.json` major bump
   - **subagent への委譲拡張**: 上記操作を subagent prompt で許可すること
   - **第三者リポ**: submodule update / fork 外への push / `gh repo` 操作

   違反検出時の hook 強制: `.claude/hooks/autonomous-action-guard.sh` が PreToolUse(Bash) で対象コマンドを `exit 2` BLOCK。bypass: `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` (`.claude/.workflow-state/bypass.log` に記録)。honor system (hook 未実装パスの場合): メインは自律実行せず user に「実行を承認しますか?」と提示してから実行。各カテゴリの例外 (準備として OK) 詳細は Layer B 参照。

9. **Loop モード = list.md 全 task 連続自律実行** (必須、2026-05-27 task-47 新設): `/resume-state loop` 起動時、`session/context` 着手手順完遂後も `docs/tasks/list.md` の **🔄 進行中 + 🔲 未着手** task を依存解決順で自動 enque + 着手。draft `approved_at:` 非空 (= user 承認済) task のみ自律着手可、draft 不在 / 未承認 task は user 確認必須項目として stop。停止条件 3 つ:
   - context 閾値到達 (tier 80 以上で強制 `/save-state`、`context-budget.sh` `ratio >= 0.80` で発火)
   - 続行不可 (同一 error 3 連続失敗 / 致命的 error / security CRITICAL / subagent 「要判断」報告)
   - user 明示停止 (`stop` / 「止めて」等)

   停止時は **自動 `/save-state`** + 「新 session で `/resume-state loop` で継続。残 task: <id 列挙>」案内を実行。Phase 6 実装仕様は `.claude/commands/resume-state.md` Phase 6 step 3a-3e + step 4-7 参照。

**停止条件は以下 3 つのみ**:
- ユーザの明示的な停止指示 ("stop" / "ストップ" / "止めて" 等)
- タスクの完了
- 致命的エラー (権限拒否 / 復旧不能 / 重大なデータ破壊リスク)

> **遵守事項 2 例外条項の起源 / 遵守事項 7 違反例 / 遵守事項 8 緩和経緯 / 遵守事項 9 Phase 6 実装仕様**: [modes/compliance-items.md](../rules-details/modes/compliance-items.md)

## Loop モード自律規律の 5 層強制機構

タスク実装中・Loop モード稼働中の「subagent 完了待ち停止」「破壊的操作の自律実行」「確認質問発話」を **5 層強制** で構造防止する。

| 層 | 機構 | 発火 | 動作 |
|---|---|---|---|
| 1 | `.claude/rules/modes.md` 遵守事項 7+8 | (規範) | subagent 待ち中独立作業義務 + 自律禁止 11 カテゴリ明文化 |
| 2 | `.claude/hooks/loop-auto-progress-reminder.sh` (UserPromptSubmit) | 毎ターン | 待ち中報告キーワード検出 + pending Agent tool_use 数集計 → `<system-reminder>` 強制注入 |
| 3 | `.claude/hooks/autonomous-action-guard.sh` (PreToolUse Bash) | Bash 実行前 | 11 カテゴリ regex 照合 → Loop なら `{"decision":"block"}` / Normal なら context 注入 |
| 4 | `.claude/settings.json` 配線 | (機構接続) | UserPromptSubmit 末尾 + PreToolUse Bash 先頭に配置 |
| 5 | `.claude/tests/loop-auto-progress-smoke.sh` | 検証 | 9 ケースで両 hook の動作検証 |
| 6 | `.claude/hooks/loop-confirmation-detector.sh` (Stop) | AI 最終 message 出力後 | 確認質問 regex 検出 (「進めてよいですか」「OK ですか」「お待ちします」等) → `<system-reminder>` 強制注入で次 turn 自律是正 |

### 禁止 11 カテゴリ (default、`HC_AUTONOMOUS_ACTION_PATTERNS` で上書き可)

- remote 反映: `git push origin main|stg*` のみ (feature branch push は task #39 緩和で自律可)
- PR / リリース: `gh pr merge` / `gh release` / `git tag <name> origin|upstream` (`gh pr create` は task #39 緩和で自律可)
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
| 確認質問検出 OFF | `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` / `ECC_LOOP_CONFIRMATION_OFF=1` | 1 セッション | (記録なし) |

honor system: bypass 時は理由を `docs/tasks/<task-N>.md` または `ECC_BYPASS_REASON` env に記録。

> **各層の動作 source code 参照 / smoke list 9 ケース完全版 / 層 6 task-41 起源**: [modes/five-layer-enforcement.md](../rules-details/modes/five-layer-enforcement.md)

## 設定

モードは `.claude/mode.yml` で永続化。値は `normal` か `loop`。

```yaml
mode: normal  # または loop
```

## 切替方法

| 方法 | 用途 |
|---|---|
| `/mode loop` / `/mode normal` slash command | セッション中の切替 (推奨) |
| `.claude/mode.yml` 直接編集 | 手動切替 |
| `HC_MODE=loop` 環境変数 | YAML を触らず一時切替 |

値解決の優先順 (高 → 低): `env(HC_MODE)` > `mode.yml` > `default(normal)`

## 強制機構 (mode 系 hook)

| Hook | タイミング | 役割 |
|---|---|---|
| `.claude/hooks/mode-session-start.sh` | SessionStart | 現モード表示 / normal 時に切替提案 |
| `.claude/hooks/mode-enforce.sh` | UserPromptSubmit | Loop モード時に毎ターン遵守事項を再注入 |
| `.claude/hooks/context-budget.sh` | UserPromptSubmit | Loop モード時に context 使用率を監視し、60/80/95% 超で `/save-state` 実行 + 再開提案を強制 |

全て `.claude/hooks/lib/mode-loader.sh` で現モードを解決する (Normal モードでは全て no-op)。

> **mode-loader.sh 内部仕様 / mode-session-start.sh / mode-enforce.sh context 注入詳細 / context-budget.sh tier 算出ロジック**: [modes/mode-hooks.md](../rules-details/modes/mode-hooks.md)

## モードと既存ルールの関係

| ルール | Normal | Loop |
|---|---|---|
| `why-x5-output.md` (Why × 5 表示) | ON | ON |
| 中間確認質問 | 要 | 禁止 |
| サブエージェント委譲 (`delegation-guard.sh`) | 要 | 要 |
| 事実検証 (`gateguard.sh`) | 要 | 要 |

Loop モードでも委譲・事実検証等の安全ガードは無効化されない。**省略するのはユーザ確認のみ**。

## 関連 artifact (代表)

- [`.claude/hooks/loop-auto-progress-reminder.sh`](../hooks/loop-auto-progress-reminder.sh) (層 2)
- [`.claude/hooks/autonomous-action-guard.sh`](../hooks/autonomous-action-guard.sh) (層 3)
- [`.claude/hooks/loop-confirmation-detector.sh`](../hooks/loop-confirmation-detector.sh) (層 6)
- [`.claude/tests/loop-auto-progress-smoke.sh`](../tests/loop-auto-progress-smoke.sh) (層 5)

> **関連 artifact 完全 list (mode 系 hook + 5 層強制機構 + smoke 群 + 設計起源 draft path)**: [modes/artifacts.md](../rules-details/modes/artifacts.md)

> **各規範の起源 (history 全体、task-21 W0.1 〜 task-51 Step 3 の変更履歴) / commit hash**: [modes/origin.md](../rules-details/modes/origin.md)
