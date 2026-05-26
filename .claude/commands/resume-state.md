# /resume-state — Resume previous session from Serena memory

前セッションの状態を Serena MCP の memory から復元する自前コマンド。SuperClaude `/sc:load` の後継。Serena MCP 必須。

## 前提

- **Serena MCP が `.mcp.json` に登録され、`mcp__serena__*` tool が利用可能であること**
- 前セッションで `/save-state` が実行され、`session/context` 等の memory key が存在すること
- 未注入時 / memory 不在時は graceful error で終了

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を順次実行してください。

### Phase 1: Project activation & onboarding check (必須、統合)

1. `mcp__serena__activate_project` (引数 = current project name)
   - 戻り値が success: 続行 (onboarding 済 + project 登録済を意味する)
   - 戻り値が error: 内容に応じて分岐:
     - `onboarding` / `not performed` を含む → error message: 「Serena MCP onboarding が未完了です。`/onboarding` 等で完了させてから再実行してください。」+ 終了
     - その他 (project 不在等) → error message: 「現プロジェクトが Serena に未登録です。`/save-state` でまず保存してください。」+ 終了

> **設計補足**: 旧版では `mcp__serena__check_onboarding_performed` を Phase 1 で呼んでいたが、現 Serena MCP には該当 tool が存在しない (2026-05-23 確認、deferred tools list にも無し)。代わりに `activate_project` の error response で onboarding 未済 / project 未登録を一括検知する。

### Phase 2: Memory enumeration

1. `mcp__serena__list_memories` で全 key 取得
2. 期待 key カテゴリ (PM Agent spec 準拠):
   - `session/context` (必須)
   - `session/last` (推奨)
   - `session/checkpoint` (option)
   - `plan/*` (PDCA Plan 進行中なら)
   - `execution/*` / `evaluation/*` / `learning/*` (進行中の cycle あれば)
   - `project/*` (project 全体理解)
3. `session/context` が不在なら error: 「前 session の memory が見つかりません。新規セッションとして開始してください。」+ 終了

### Phase 3: Sequential restore

1. `mcp__serena__read_memory("session/context")` で完全 snapshot 復元
2. `mcp__serena__read_memory("session/last")` で last summary
3. `mcp__serena__read_memory("session/checkpoint")` で進捗 (存在時のみ)
4. その他存在 key (plan/* / execution/* / evaluation/* / learning/*) を逐次 `read_memory` で復元

### Phase 4: 復元レポート (user 提示)

stdout に以下 4 項目を構造化して提示:

```
🔄 Previous session restored from Serena memory.

📋 前回 (Last session):
   <session/last の要約を 1-2 段落>

📊 進捗 (Current progress):
   <session/context の "TaskList 最終状態" + "累計 commits" から抽出>

🎯 次回 (Planned next actions):
   <session/context の "次セッション着手手順" を番号付きリストで>

⚠️  課題 (Blockers / open issues):
   <存在すれば箇条書き、なければ "なし">
```

### Phase 5: TaskList 再同期 (option)

復元した `session/context` に未完 task (status = `pending` or `in_progress`) が記録されていれば:
1. TaskCreate で復元 (内部 task list と同期)
2. TaskUpdate で status を復元

(本 Phase は user 指示で skip 可。標準では実行)

### Phase 6: Loop モード自律実行 (引数 `loop` 時のみ、2026-05-26 追加)

引数 `$ARGUMENTS == "loop"` の場合、復元後に自動的に Loop モードへ切替えて「次セッション着手手順」を自律実行する。引数なしの場合は本 Phase を skip して Phase 4 復元レポート提示で完了 (user 手動指示待ち)。

1. **Loop モード切替**: 現モードが Normal なら `.claude/mode.yml` を `loop` に更新 (or env `HC_MODE=loop` を export)。既に Loop モードなら no-op
2. **次アクション解析**: `session/context` の「次セッション着手手順」セクションを読み、自律実行可能項目と user 確認必須項目を分類:

   | 分類 | 内容 | 動作 |
   |---|---|---|
   | **自律実行可** (modes.md 遵守事項 2 非例外) | 実装 / commit / test / refactor / branch 切替 / status sync / 既存 task の Step 進行 / subagent 並列起動 | 順次自律実行 |
   | **user 確認必須** (modes.md 遵守事項 2 例外) | 設計文書新規追加 / 仕様変更 / scope 拡張 / 戦略判断 (architecture / 技術スタック / 既存 task 優先順入替) | 提示のみ、user 承認待ち停止 |
   | **自律実行禁止** (modes.md 遵守事項 8、11 カテゴリ) | main/stg* push / `gh pr merge` / 本番 deploy / DB migration / secrets ローテーション / 等 | 提示のみ、user 明示承認必須 |

3. **自律実行可項目を順次実行**:
   - 各 step 前に Why × 5 (v10 1 行 format「<何のため> のため、<何をやる> を行う」) 出力 (`.claude/rules/why-x5-output.md`)
   - subagent 委譲時は `run_in_background: true` 必須 (`development-process.md` §3 No. 1)
   - 起動前 / 直後に TaskCreate で内蔵 task list に登録 (`development-process.md` §3 No. 4)
   - 並列化義務遵守: 独立 sub-task 2 件以上は並列起動 default (`development-process.md` §6)
   - 完了報告は `confidence: 0.X` 必須 (F3 ConfidenceGate)
   - 適切な粒度で commit (modes.md 遵守事項 5、1 機能 / 1 修正 / 1 リファクタごと)

4. **user 確認必須項目で stop**:
   - 次アクションが user 確認必須項目 (上記表 (b) (c) 分類) に到達したら、「次は <項目>。承認後に進めます」と提示
   - 次の user message を待機 (Phase 7 context 監視は継続)

5. **完了通知**: 自律実行可項目が全て完遂したら「全自律実行項目完遂、待機中の user 確認項目: <list>」と報告して継続待機

### Phase 7: Context budget 監視 + 自動 `/save-state` (引数 `loop` 時のみ、2026-05-26 追加)

Phase 6 実行中、context 使用率を継続監視し、`harness-config.yml` の `context_budget_threshold` に達したら `/save-state` を自動実行して session を区切る。**閾値・上限値は全て yml の値を SSoT として参照** (hardcode 禁止)。

1. **設定 SSoT (yml 参照、env 上書き可)**:

   | yml key (`.claude/harness-config.yml`) | env override | 役割 | 現 hirai-method 値 |
   |---|---|---|---|
   | `context_budget_enabled` | `HC_CONTEXT_BUDGET_ENABLED` | hook 全体の有効化 | `true` |
   | `context_budget_limit` | `HC_CONTEXT_BUDGET_LIMIT` | context window サイズ (tokens、Opus 1M = `1000000` / Sonnet & Haiku 200K = `200000`、モデル切替時手動更新) | `1000000` |
   | `context_budget_threshold` | `HC_CONTEXT_BUDGET_THRESHOLD` | warning 開始 ratio (`0.0`〜`1.0`、これ未満は silent) | `0.66` |
   | `context_budget_state_dir` | `HC_CONTEXT_BUDGET_STATE_DIR` | 警告済 tier marker の保管 dir | `.claude/.context-budget-state` |

2. **既存 hook 機構利用**: `.claude/hooks/context-budget.sh` (UserPromptSubmit) が yml の `context_budget_threshold` を warning 開始ラインとし、tier 3 段階 (`60` / `80` / `95`、`.claude/hooks/context-budget.sh` L141-146 で `ratio >= 0.60 / 0.80 / 0.95` で発火) で escalation 警告を `<system-reminder>` で強制注入。各 tier は 1 セッションあたり 1 度のみ発火 (spam 防止、上位 tier 発火時は下位 tier 再警告 skip)

3. **Loop モードでは tier 警告 = stop signal** (tier 閾値は context-budget.sh で hardcode、yml `context_budget_threshold` は warning 開始ライン制御):
   - **tier 60 警告** (yml `context_budget_threshold` 越え時に最初発火): 1 度だけ「`/save-state` 推奨タイミング」表示、自律実行は継続
   - **tier 80 警告** (`ratio >= 0.80` で発火): **強制 `/save-state` 実行** + 次 session 移行案内 (「新 session で `/resume-state loop` で継続」)
   - **tier 95 警告** (`ratio >= 0.95` で発火): 即時 `/save-state` + session 終了 (context overflow 直前の緊急停止)

4. **`/save-state` 自動実行**: tier 80 以上で main agent が `/save-state` を実行、`session/context` に「Loop モード自律実行で context 閾値到達、次 session で `/resume-state loop` で継続」と記録、stdout に再開コマンドを表示して Phase 7 exit

5. **無効化**: yml で `context_budget_enabled: false` (or env `HC_CONTEXT_BUDGET_ENABLED=false`) で context 監視 OFF (Phase 7 全 skip)、Phase 6 は無限ループ可能性あるため非推奨

6. **閾値調整の運用**:
   - 早めに warning したい → yml `context_budget_threshold: 0.50` (= 50% で warning 開始)
   - 一時的に厳しく → env `HC_CONTEXT_BUDGET_THRESHOLD=0.40` (env-set 中のみ有効)
   - tier 閾値 (60/80/95) を変更したい場合は `.claude/hooks/context-budget.sh` L141-146 を直接編集 (subagent 委譲 + staging 戦略必須)

## 引数

| 引数 | 動作 |
|---|---|
| **(なし、default)** | 復元のみ mode (Phase 1-5)。user が手動で次アクション選択 |
| **`loop`** | 復元 + Loop モード自律実行 mode (Phase 1-7)。context 閾値到達まで継続、user 確認必須項目で stop |
| **その他** | warning 出力 + 復元のみ mode で続行 |

引数解析: `$ARGUMENTS` の値で分岐 (case-insensitive 推奨、`loop` / `Loop` / `LOOP` 受理)。

特定 memory key のみ復元したい場合: 本コマンドの Phase 3 を modify した後継 command を別途検討 (本 task scope 外)。

## エラーハンドリング

| 状況 | 動作 |
|---|---|
| Serena MCP 未注入 | Phase 1 で停止 + 案内 + exit |
| onboarding 未済 | Phase 1 で `activate_project` error として停止 + 案内 + exit |
| project 未登録 | Phase 1 で `activate_project` error として停止 + 案内 + exit |
| `session/context` key 不在 | Phase 2 で停止 + 「新規 session として開始」案内 |
| 個別 key の `read_memory` fail | warning 出力 + 残 key 復元続行 |
| Phase 5 TaskList 再同期 fail | warning + 復元レポートは出力 (Phase 4 は成功扱い) |
| Phase 6 自律実行中の subagent fail | confidence-gate で BLOCK、main が自律 retry / user 通知 / 次 task 進行のいずれかを判断 |
| Phase 7 context tier 警告 + `/save-state` fail | warning 出力 + Phase 6 自律実行は緊急 stop、user に手動 `/save-state` 案内 |

## 関連

- `/save-state` — 保存コマンド (本コマンドの逆)
- `/pm-start` — PM Agent (Session Start Protocol で本コマンドを auto-invoke)
- `.claude/hooks/mode-session-start.sh` — SessionStart 時に memory 存在を検出して `/resume-state` を提案 (W2)
- `.claude/hooks/context-budget.sh` — context 使用率監視 (Phase 7 で利用)
- `.claude/rules/modes.md` — Loop モード規範 (遵守事項 2 例外条項 / 5 commit 粒度 / 7 並走中独立作業 / 8 自律実行禁止 11 カテゴリ) / context-budget 設定
- `.claude/rules/development-process.md` — subagent 委譲 3 必須要件 (background 起動 / 並列化義務 / agent type 選定) / TaskCreate 義務
- `.claude/rules/why-x5-output.md` — Why × 5 v10 1 行 format (Phase 6 各 step 前に必須出力)
- `.claude/harness-config.yml` — `context_budget_threshold` (Phase 7 閾値) / `auto_loop_resume_*` (将来拡張用キー、現状未実装)
- Memory key schema: `/save-state` の §関連 参照
