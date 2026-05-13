# /resume-state — Resume previous session from Serena memory

前セッションの状態を Serena MCP の memory から復元する自前コマンド。SuperClaude `/sc:load` の後継。Serena MCP 必須。

## 前提

- **Serena MCP が `.mcp.json` に登録され、`mcp__serena__*` tool が利用可能であること**
- 前セッションで `/save-state` が実行され、`session/context` 等の memory key が存在すること
- 未注入時 / memory 不在時は graceful error で終了

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を順次実行してください。

### Phase 1: Onboarding check (必須)

1. `mcp__serena__check_onboarding_performed`
   - 未済なら error message: 「Serena MCP onboarding が未完了です。`/onboarding` 等で完了させてから再実行してください。」+ 終了

### Phase 2: Project activation

1. `mcp__serena__activate_project` (引数 = current project name)
   - project 未登録なら error: 「現プロジェクトが Serena に未登録です。`/save-state` でまず保存してください。」+ 終了

### Phase 3: Memory enumeration

1. `mcp__serena__list_memories` で全 key 取得
2. 期待 key カテゴリ (PM Agent spec 準拠):
   - `session/context` (必須)
   - `session/last` (推奨)
   - `session/checkpoint` (option)
   - `plan/*` (PDCA Plan 進行中なら)
   - `execution/*` / `evaluation/*` / `learning/*` (進行中の cycle あれば)
   - `project/*` (project 全体理解)
3. `session/context` が不在なら error: 「前 session の memory が見つかりません。新規セッションとして開始してください。」+ 終了

### Phase 4: Sequential restore

1. `mcp__serena__read_memory("session/context")` で完全 snapshot 復元
2. `mcp__serena__read_memory("session/last")` で last summary
3. `mcp__serena__read_memory("session/checkpoint")` で進捗 (存在時のみ)
4. その他存在 key (plan/* / execution/* / evaluation/* / learning/*) を逐次 `read_memory` で復元

### Phase 5: 復元レポート (user 提示)

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

### Phase 6: TaskList 再同期 (option)

復元した `session/context` に未完 task (status = `pending` or `in_progress`) が記録されていれば:
1. TaskCreate で復元 (内部 task list と同期)
2. TaskUpdate で status を復元

(本 Phase は user 指示で skip 可。標準では実行)

## 引数

引数なし。常に最新の `session/context` を復元する。

特定 memory key のみ復元したい場合: 本コマンドの Phase 4 を modify した後継 command を別途検討 (本 task scope 外)。

## エラーハンドリング

| 状況 | 動作 |
|---|---|
| Serena MCP 未注入 | Phase 1 で停止 + 案内 + exit |
| onboarding 未済 | 同上 |
| project 未登録 | Phase 2 で停止 + 案内 + exit |
| `session/context` key 不在 | Phase 3 で停止 + 「新規 session として開始」案内 |
| 個別 key の `read_memory` fail | warning 出力 + 残 key 復元続行 |
| Phase 6 TaskList 再同期 fail | warning + 復元レポートは出力 (Phase 5 は成功扱い) |

## 関連

- `/save-state` — 保存コマンド (本コマンドの逆)
- `/pm-start` — PM Agent (Session Start Protocol で本コマンドを auto-invoke)
- `.claude/hooks/mode-session-start.sh` — SessionStart 時に memory 存在を検出して `/resume-state` を提案 (W2)
- Memory key schema: `/save-state` の §関連 参照
