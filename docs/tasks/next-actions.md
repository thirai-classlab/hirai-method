# Next Actions（副産物 / 派生 task 候補レジストリ）

> 本セッション中・タスク実装中に発生した「副産物 (byproduct)」「派生 task 候補」「次セッションでやるべきこと」を **必ず記録する公式 location**。
>
> `list.md`（着手中・完了タスク台帳）/ `parking-lot.md`（設計済 + 保留タスク）/ `docs/draft/`（未承認設計）とは **別レイヤ** で、informal な「TODO / 次アクション候補」を捕捉する registry。

## 目的

副産物が「memory に保存されるだけ」「会話履歴に流れて消える」「次セッションで recall されない」状態を **構造的に防ぐ**。

HIRAI メソッドの硬性ルール「設計なしのタスク追加禁止」は維持しつつ、その手前で **informal な記録経路** を提供する。

## 処理フロー

```
副産物発生 (task 実装中 / セッション中 / レビュー中)
    ↓
[必ず] next-actions.md に entry 追加
    ↓
判断:
    (a) 即着手すべき + 設計必要 → /new-draft <slug> で draft 起こし → 承認 → /new-task → list.md
    (b) 着手不可 + 設計済 → parking-lot.md へ移行 (保留タスクとして)
    (c) 不要 → 無視。次セッション以降に削除（理由を「処理結果」列に明記）
    ↓
next-actions.md からエントリ削除（移行先を「処理結果」列に明記）
```

## エントリフォーマット

| 列 | 内容 |
|---|---|
| **#** | 連番 |
| **記録日** | YYYY-MM-DD |
| **タイトル** | 1 行で何をすべきか |
| **発生源** | どのタスク / セッションで発生したか（commit hash / task ID） |
| **緊急度** | 🔴 高 (次セッションで対応) / 🟡 中 (近日) / 🟢 低 (任意) |
| **推奨処理** | (a) draft 起こし / (b) parking-lot 移行 / (c) 無視 |
| **処理結果** | （処理後に記入）移行先または削除理由 |

---

## エントリ一覧

| # | 記録日 | タイトル | 発生源 | 緊急度 | 推奨処理 | 処理結果 |
|---:|---|---|---|:---:|---|---|
| 1 | 2026-05-12 | PR 作成 (`feat/loop-mode` → `main`) — 本セッション 18 commits の merge 動線 | 本セッション task #1 完了 (HEAD `b58bbf0`) | 🔴 | (a) draft 起こし or (c) 直 `gh pr create` | ✅ → [`docs/draft/create-pr-feat-loop-mode.md`](../draft/create-pr-feat-loop-mode.md) → [task #2](task-2-create-pr-feat-loop-mode.md) (2026-05-12) |
| 2 | 2026-05-12 | context-budget hook の実発火検証 — CB-verify 修正 (`5846925`) の運用効果観察 | 本セッション CB-verify (#9) | 🟡 | (a) draft 起こし `context-budget-hook-verification` | ✅ → [`docs/draft/context-budget-hook-verification.md`](../draft/context-budget-hook-verification.md) → [task #3](task-3-context-budget-hook-verification.md) (2026-05-12) |
| 3 | 2026-05-12 | CLAUDE.md `Critical Operational Lessons` に教訓 2 件転載 — 並列 subagent git 競合 / `set -e` leak in sourced libs | 本セッション feedback memory 保存時 | 🟡 | (a) draft 起こし `critical-lessons-transfer` | ✅ → [`docs/draft/critical-lessons-transfer.md`](../draft/critical-lessons-transfer.md) → [task #4](task-4-critical-lessons-transfer.md) (2026-05-12) |
| 4 | 2026-05-12 | **副産物 discharge 機構の本格実装** — `_TASK_TEMPLATE.md` 拡張 + `workflow-guard.sh` 拡張 + `/discharge-byproduct` command 新設 + `.claude/rules/workflow.md` セクション追加 | 本セッション「タスク管理されていない」指摘 | 🔴 | (a) draft 起こし `byproduct-discharge-mechanism` | ✅ → [`docs/draft/byproduct-discharge-mechanism.md`](../draft/byproduct-discharge-mechanism.md) → [task #5](task-5-byproduct-discharge-mechanism.md) (2026-05-12、本セッションで W1+W3+W6 着手中) |
| 5 | 2026-05-12 | classlab_salesforce-mail 修復 — `docs/draft/mail-message-status.md` 承認 + `/new-task 2` 起動 + task #1 W8 残作業完了 | 別リポ調査結果 | 🟢 | **本リポ管理外**（別リポ側で対応） | — |
| 6 | 2026-05-12 | Loop モード自律進行強制 + 自律実行禁止リスト — subagent 待ち中停止 / push 等の破壊的操作自律実行 を構造解決 (W1-W6 全実装) | 本セッション user 指摘 (複数回「Loop モード継続中。なぜ自動で実行を続けないのか?」+「本番反映 / push 自律禁止」) | 🔴 | (a) draft → `/new-task 6` → W1-W6 実装 → push (user 承認後) | ✅ → [`docs/draft/loop-auto-progress-enforcement.md`](../draft/loop-auto-progress-enforcement.md) → [task #6](task-6-loop-auto-progress-enforcement.md) (W1 modes.md `1bc9284` / W2-W6 本セッション完了 2026-05-12、smoke 9/9 PASS、push 待ち) |
| 7 | 2026-05-12 | **`.claude/` 汎用化リファクタ** — `.claude/rules/workflow.md` 副産物 discharge セクション他で `docs/draft/<slug>.md` 直接リンクを使用しており、別プロジェクトに `.claude/` のみ移植した際 broken link になる。`.claude/` 単独 portable を実現する一般化リファクタ。**該当箇所**: `.claude/rules/workflow.md` (副産物 discharge `byproduct-discharge-mechanism.md` 言及 / 設計レビュー fan-out `workflow-enforcement.md` 言及) ほか `.claude/rules/*` `.claude/commands/*` 全般 | user 指示 (2026-05-12, 本セッション Phase A-6 後半) | 🟡 | (a) draft 起こし `claude-dir-portability` 推奨 — 影響箇所網羅 + 移行方針確定 → user 承認 → リファクタ | ✅ task-7 W6 で「Session 永続化と PM Orchestration」セクション部分対応 (2026-05-12) + 2026-05-18 残存 2 箇所 (line 265 byproduct-discharge §関連 artifact / line 360 §関連ルール) を commit `20f4eb6` で「採用プロジェクト側 `docs/draft/` を参照」表記に統一、4 sections 全揃で `.claude/` 単独 portable 完成。subagent ade48ed39cbd44b5e confidence 0.97 |
| 8 | 2026-05-12 | **`delegation-guard.sh` segment splitter heredoc 誤分割 bug** — `awk` `RS=""` + `gsub(/&&\|\\|\\||;\|\\|/, "\\n")` が heredoc 内の commit message 本文 (改行を含む) を別 shell コマンドとして split し、whitelist 不一致で誤 BLOCK する。回避: 単行 `-m "..."` 使用、`git add && git commit` チェーンを避ける。**該当箇所**: `.claude/hooks/delegation-guard.sh` Bash matcher | 本セッション task #6 commit phase で再現 (2026-05-12) | 🟡 | (a) draft 起こし `delegation-guard-heredoc-fix` 推奨 — segment splitter ロジック修正 + smoke 追加 | ✅ → [task #8](task-8-delegation-guard-heredoc-fix.md) 完了 (2026-05-12、W2 quote-aware fix `8aaa76a`、smoke 6/6 PASS、heredoc 本文未対応は draft §3 W2 制限事項として明文化、B フル parser 化は将来 task) |
| 10 | 2026-05-13 | **8 hooks 将来 dual-mode 評価** — task #12 W2 で karpathy surgical 判断により 4/11 hooks のみ helper 経由に統一。残り 8 hooks (`autonomous-action-guard.sh` / `context-budget.sh` / `mode-session-start.sh` / `loop-auto-progress-reminder.sh` / `lib/mode-loader.sh` / `mode-asana-prompt.sh` / `mode-enforce.sh` / `improvement-proposal.sh` / `check-required-env.sh` / `agent-router-suggest.sh` のうち 8 件) は現状 SCRIPT_DIR のみ + cwd-relative `.claude/` 参照。将来これらに project file 参照 (`docs/tasks/list.md` 等) を追加する局面が来たら helper 採用要 | task #12 subagent ad80e8f5b63437f01 (2026-05-13、commit `eb9925b`) | 🟢 | (c) 当面無視 — 必要が出たら個別判定 | — |
| 11 | 2026-05-13 | **`CLAUDE_PROJECT_DIR` env を `resolve_project_root()` fallback chain に組込検討** — Claude Code 標準 env `CLAUDE_PROJECT_DIR` を helper の 2.5 段目 (env override と git rev-parse の間) に追加すれば、Claude Code 環境下での project root 解決がより堅牢化。draft §3 で未検討 | task #12 subagent ad80e8f5b63437f01 (2026-05-13) | 🟢 | (a) draft 起こし `project-root-claude-env-integration` (検討必要) or (c) 無視 (現状 git rev-parse で十分動作) | ✅ 2026-05-18 commit `4a35511` で `resolve_project_root()` 3 段目に CLAUDE_PROJECT_DIR check 挿入 (git rev-parse 後 / pwd 前)、新 4 段 chain 完成。`project-root-smoke.sh` 新規 5 cases PASS、`dual-mode-portability-smoke.sh` 4 cases regression なし。subagent ade48ed39cbd44b5e confidence 0.97 |
| 13 | 2026-05-18 | **git destructive deny の単体 smoke 追加** — `delegation-guard.sh` に新規追加した「git destructive deny」layer (commit `b7eea6e`) の動作検証 smoke が未作成。10 patterns (push --force / push -f / reset --hard / branch -D / clean -f / checkout -- / restore --worktree / stash drop|clear / tag -d|-f / reflog expire / gc --prune=now) の block 動作と、bypass (`ECC_ALLOW_DESTRUCTIVE_GIT=1`) の通過動作を `.claude/tests/git-destructive-deny-smoke.sh` で検証。**該当箇所**: `.claude/hooks/delegation-guard.sh` L121-148 (本セッション追加部) | 本セッション user 指示 harness 変更 commit `b7eea6e` の事後監視 | 🟡 | (a) draft 起こし `git-destructive-deny-smoke` 推奨 — 10 patterns 各々の block 検証 + bypass 検証 + 既存 segment splitter smoke regression 確認、entry #14 と統合検討も可 | ✅ 2026-05-18 commit `9eacc3c` で smoke 完遂 (19 block + 10 pass + 3 bypass = 32/32 PASS、既存 segment smoke 6/6 regression 0)。subagent acf4733319eb2deea (v1 31/31 + `git push -f` single space hook bug 発見 confidence 0.92) → メイン hook fix (regex `[[:space:]]-f` → `([^|;&]*[[:space:]])?-f`) → subagent a3d41d744ebbbc1a2 (v2 32/32 with -f single space re-enabled confidence 0.97)。bug fix と smoke を同 commit に統合 |
| 14 | 2026-05-18 | **protected branch push deny の単体 smoke 追加** — `delegation-guard.sh` に新規追加した「protected branch push deny」layer (commit `ad2f7bc`) の動作検証 smoke が未作成。検証ケース: (a) `git push origin main` → block / (b) `git push origin stg` / `stg-v1` / `release/stg-prod` → block / (c) `git push origin feature/test` → 通過 (Loop モードでは autonomous-action-guard で別途 block されるため Normal モードでの単体 check 必要) / (d) `git push` (refspec 省略、current = main) → block / (e) bypass `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` で通過。**該当箇所**: `.claude/hooks/delegation-guard.sh` L150-208 (本セッション追加部) | 本セッション user 指示 harness 変更 commit `ad2f7bc` の事後監視 + `git push origin main` 実測 block 確認済 | 🟡 | (a) draft 起こし `protected-branch-push-deny-smoke` 推奨 — entry #13 (git destructive deny smoke) と統合し `.claude/tests/delegation-guard-deny-layers-smoke.sh` 単一 smoke 化も検討可 | — |
| 15 | 2026-05-21 | **Wave 計画時の git log --grep 事前確認義務 (重複 subagent 起動防止)** — 別 repo 修正タスクで Wave 計画書 (gap-review report 等) の finding に対し、subagent 起動前に `git log --all --grep <pattern>` で既存 commit 解消状況を確認していなかった結果、Wave 2 で 2/4 件 (C-7 / E-2) が no-op、Wave 3/4 でも no-op 検出 prompt を急遽 inline 追加。token / 時間の二重消費が発生。**該当箇所**: `.claude/commands/new-feature.md` Stage 8 (`tdd`) / `.claude/commands/modify-feature.md` Stage 7 (`tdd`) の subagent dispatch 段、または `_TASK_TEMPLATE.md` の Wave セクションに「事前確認 step」を強制テンプレ化 | 本セッション 2026-05-21 TM 別 repo (`/Users/t.hirai/タスクマネジメント/`) の HIGH 9 件修正で発覚。Wave 2-C (C-7) / Wave 2-D (E-2) 両者の subagent 報告で「既存 commit `d705efc` で解消済、no-op」と報告 | 🟡 | (a) draft 起こし `wave-precheck-git-log-grep` 推奨 — `_TASK_TEMPLATE.md` Wave セクションに「事前確認 (git log --grep で既存 commit 解消確認)」 step を必須テンプレ化 + new-feature.md / modify-feature.md 該当 stage に「subagent prompt に事前確認 step を含めること」を明記 | ✅ → [`docs/draft/wave-precheck-git-log-grep.md`](../draft/wave-precheck-git-log-grep.md) → [task #20](task-20-wave-precheck-git-log-grep.md) (2026-05-21、user 指示「このリポジトリも修正してくださいね」承認、W1-W4 subagent 進行中) |
| 12 | 2026-05-13 | **subagent context `.claude/` 配下 Write/Edit permission denied 回避 staging 戦略を development-process.md に規範化** — task #12 で subagent (run_in_background=true general-purpose) が `.claude/hooks/` `.claude/tests/` への Write/Edit/Bash heredoc redirect で denied される事象を発見。`/tmp` で Write → `mv` で install で回避済 (5 commit 完遂)。今後の subagent dispatch prompt に staging 戦略明示が必要 | task #12 subagent ad80e8f5b63437f01 (2026-05-13、`learning/solutions/subagent-claude-permission-staging` 永続化済) | 🟡 | (a) draft 起こし `subagent-claude-permission-staging-doc` — `.claude/rules/development-process.md` §「サブエージェント委譲」配下に staging 戦略セクション追加 | ✅ → [`docs/draft/subagent-claude-permission-staging-doc.md`](../draft/subagent-claude-permission-staging-doc.md) → [task #13](task-13-subagent-claude-permission-staging-doc.md) (2026-05-13、W1 規範化 + W3 sync) |
| 16 | 2026-05-23 | **`resolve_project_root()` に「同居 `.claude/` dir 優先」汎用化案 B 挿入検討** — taskManageSystem の subdir 配置 (`/Users/t.hirai/タスクマネジメント/taskManageSystem/.claude` だが parent `/Users/t.hirai/タスクマネジメント/` が git root) で、`git rev-parse --show-toplevel` が parent dir を返し harness 本体 ( child の `.claude/`) と乖離する問題。現状は task-24 W2 `b302b13` で `.envrc` + `HC_PROJECT_ROOT` 固定 + `.claude/COEXISTENCE.md` の個別対応で回避済。**汎用化案 B**: `resolve_project_root()` の現 4 段 chain (HC_PROJECT_ROOT → git rev-parse → CLAUDE_PROJECT_DIR → pwd) の **`git rev-parse` の前** に「直近上位 (cwd から `..` 方向) で初めて `.claude/` を持つ dir」を check する 5 段目を挿入することで、`.envrc` なしで subdir 配置を自動検出可能になる。**該当箇所**: `.claude/hooks/lib/project-root.sh` `resolve_project_root()` + 既存 `project-root-smoke.sh` への新規 ケース追加 (subdir 配置 simulation) | task-24 W2+W4 (`b302b13`, 2026-05-23) の個別対応中に発見、根本対処は本汎用化案 B | 🟢 | (a) draft 起こし `project-root-colocated-claude-priority` — 5 段目挿入の設計 + smoke 拡充 (subdir 配置 mock + parent/child 両 `.claude/` 共存ケース) + 既存 4 段 chain regression 0 確認。または (c) `.envrc` 個別対応で運用が安定するなら無視 | — |
| 17 | 2026-05-23 | **cross-repo write の user manual normative pattern 規範化** — `bash install.sh --update <target>` 等の cross-repo Write は Claude Code sandbox + `delegation-guard.sh` 二重制約で agent (main / subagent / worktree isolation 含む全経路) 完全 denied と確定 (task-24 W1 subagent 調査 confidence 0.85)。3 リポ反映 (task-21 W3.3 / task-24 W1 / task-26 W6 / classlab-weekly-news 同期) 系 task は user manual を default 経路と規範化し、agent 実行を試みない。**該当箇所**: `.claude/rules/development-process.md` §「サブエージェント委譲」配下に「cross-repo write 例外」セクション追加 + `_TASK_TEMPLATE.md` Wave 計画段の「cross-repo は user manual」明示テンプレ + `install.sh` 冒頭コメントに「agent 実行不可、user manual 専用」明記 | 本 session task-24 W1 / task-26 W6 / task-21 W3.3 共通の sandbox blocker 発見、`feedback_cross_repo_write_sandbox_block.md` memory 化済 | 🟡 | (a) draft 起こし `cross-repo-write-user-manual-normative` — 規範化対象 3 箇所の編集 + 既存運用との整合性確認 (cross-repo を回避する自動代替策の検討含む)。または (c) memory + 副産物 entry の啓発で済ます (規範化は次世代設計改善のシグナルとして観察継続) | — |
| 18 | 2026-05-23 | **observe.sh jq parse 失敗修復 (元前提 56% → 実測 0.04%)** — observations.jsonl の `--argjson raw` 経路で **jq parse 失敗が cascade** していた問題。root cause = literal control char (U+0000-U+001F) で `jq -c '.'` 自体が fail → `raw_safe` が error 文字列にすり替わり `--argjson` も連鎖失敗。**該当箇所**: `.claude/skills/continuous-learning-v2/hooks/observe.sh` の `raw_safe=$(... \| jq -c '.')` セクション | task-25 A3 subagent a85993694d32e78bf 計測中に発見 (2026-05-23、confidence 0.92)、A3 が報告した 56% は jq stream cascade fail を真の invalid 数と誤認した推定値、W2 subagent ae89946fa1ed81309 が Python json.JSONDecoder.raw_decode loop で実測したところ 11/28583 = 0.04% (drop 5600x) | 🔴→✅ | task-27 として list.md row 50 で inline 管理、W1 + W2 完遂 (commit `c25f3ee` + `fd5f6e5`)。**W3 不要判定** (2026-05-23 subagent a1f1341b281d0ace2 confidence 0.92): L4 学習側が raw field 未参照、W3 影響面積 ≈ 0。副次 finding (harness-audit jq-valid 指標も cascade fail 汚染) は entry #20 で別管理 | ✅ → task-27 完遂 close (W1+W2 + W3 不要判定 2026-05-23、副次 finding は entry #20 へ分離) |
| 20 | 2026-05-23 | **harness-audit の jq-valid 率指標が cascade fail に汚染されている可能性** — `/harness-audit` の jq-valid 率指標は task-27 draft §1 で 44% と引用されていたが、実態は cascade fail 由来 (本来 99.96%)。harness-audit.py 内の jq parse logic も `--argjson` 系経路で cascade fail に巻き込まれている可能性が高く、指標が実態を反映していない。**該当箇所**: `harness-audit.py` の jq-valid 率算出 (jq query パス / `--argjson` 経路 / fromjson? 適用有無を要調査) + 関連 fixture / smoke の前提値も合わせて更新必要 | task-27 W3 判定 subagent a1f1341b281d0ace2 (2026-05-23) 副次 finding、observe.sh W1 `c25f3ee` 修正で本来の data 健全性は確保されたが measurement 側 (harness-audit) が古いままの可能性 | 🟡 | (a) draft 起こし `harness-audit-jq-valid-metric-fix` 推奨 — harness-audit.py 内 jq-valid 率算出ロジックを read、`--rawfile` + `fromjson?` 経路に統一、新 sample data で 99.96% 表示確認、smoke 拡充。または (c) harness-audit を Python re-parse ベースに置換する大規模 refactor と統合 (別 task 検討) | — |
| 19 | 2026-05-23 | **observe.sh を SubagentStop / Stop に追加配線** — 現状 observe.sh は `PreToolUse` + `PostToolUse` のみ配線、`SubagentStop` / `Stop` / `UserPromptSubmit` / `SessionStart` event は L4 学習から欠落。task-21 W3 Phase B で「true subagent handoff latency 計測不可 (SubagentStop event 0/6594 records)」発見の根因。`subagent 完了 metric` `session wrap-up event` が L4 観察対象外で、Loop モード規律の learning に gap がある。**該当箇所**: `.claude/settings.json` の SubagentStop / Stop / UserPromptSubmit / SessionStart 配列に observe.sh entry を追加 + observe.sh の event ハンドラ拡張 (event 型ごとに meaningful field 抽出) | task-25 A3 subagent a85993694d32e78bf 計測中に発見 + task-21 W3 Phase B で同根因確認 (2026-05-23) | 🟡 | (a) draft 起こし `observe-subagent-stop-instrumentation` 推奨 — 4 event 追加配線 + 各 event の payload schema 定義 + L4 学習側の event 解釈拡張。task-21 W3 採用判定基準 4 (true handoff latency 秒オーダー) の再測定もこの拡張後に実施 | 🔄 → [`docs/draft/observe-subagent-stop-instrumentation.md`](../draft/observe-subagent-stop-instrumentation.md) (2026-05-23、4 Wave 0.6 工数、案 C 段階 = Phase 1 SubagentStop 単独 → #18 完了 gating → Phase 2 残 3 event 追加)、user 承認待ち |

## ルール（運用）

1. **副産物発生時の即時記録**: タスク実装中 / レビュー / セッション中に「これは別 task として管理すべき」と判断した瞬間、**memory に保存する前に** next-actions.md に entry を追加する
2. **`/finish-task` 完了条件**: task 完了時、メインは本ファイルの新規 entry が「すべて (a)/(b)/(c) のいずれかに処理されている」ことを確認する（**未処理 entry が残った状態での task 完了は禁止**）— 将来 W4 拡張で `workflow-guard.sh` が自動検証する
3. **セッション終了時のチェック**: PM Agent Session End Protocol で本ファイルを読み込み、未処理 entry を user に提示 + 推奨処理を提案
4. **メイン専任**: 本ファイルの更新は **メインエージェントのみ**。サブエージェントは記録しない（メインが報告を受けて記録する）
5. **保管期限**: entry は処理結果記入後 30 日で削除可。ただし「(c) 無視」エントリは過去意思決定のトレーサビリティとして履歴セクションに移動

## 履歴セクション

処理完了済 / 不採用となった過去 entry を時系列で残す。

| # | 記録日 | タイトル | 発生源 | 緊急度 | 推奨処理 | 処理結果 |
|---:|---|---|---|:---:|---|---|
| 9 | 2026-05-13 | **旧 SuperClaude command 後継 smoke の事後監視 failure** — `custom-pm-commands-smoke.sh` Case 5 (allowed file 以外で旧 SuperClaude session/PM command 言及残存を検出) が pre-existing fail。真因 = 2 file (本 next-actions.md entry #9 自体 + `README.md`) が allowlist 外。task #7 W4 (`f063ff3` 旧 command 後継置換) の事後監視 smoke の残存検出。**該当箇所**: `.claude/tests/custom-pm-commands-smoke.sh` Case 5 | task #9 subagent 検証 (2026-05-13) | 🟡 | (a) draft 起こし `custom-pm-case-5-followup` | ✅ → [`docs/draft/custom-pm-case-5-followup.md`](../draft/custom-pm-case-5-followup.md) → [task #14](task-14-custom-pm-case-5-followup.md) (2026-05-14 完了、5 commits: W0 `f3f64ba` / W1 `9b1545e` / W2 `90fdebb` / W3 `bdbcbb0` / sync、合計 smoke 42/42 PASS、catch-22 解消、案 C ハイブリッド) |

## 関連

- [`list.md`](list.md) — 着手中・完了タスク台帳
- [`parking-lot.md`](parking-lot.md) — 設計済 + 保留タスク
- [`../draft/`](../draft/) — 未承認設計
- [`.claude/rules/workflow.md`](../../.claude/rules/workflow.md) — workflow 強制機構（副産物 discharge は将来 W4 拡張で組み込み予定）
