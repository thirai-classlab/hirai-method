# /save-state — Save session state to Serena memory

セッション状態を Serena MCP の memory に永続化する自前コマンド。SuperClaude `/sc:save` の後継。Serena MCP 必須。

## 前提

- **Serena MCP が `.mcp.json` に登録され、`mcp__serena__*` tool が利用可能であること**
- 未注入時は Phase 1 で error 終了し、user に Serena 導入手順を案内する

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を順次実行してください。

### Phase 1: Onboarding & project activation (必須)

1. `mcp__serena__check_onboarding_performed` を実行
   - 戻り値が "未済" / "Error" を含む場合:
     - stdout に error message: 「Serena MCP onboarding が未完了です。`/onboarding` 等で完了させてから再実行してください。」
     - 以降の Phase を skip して終了
2. `mcp__serena__activate_project` を実行 (引数 = current project name 推定 or git remote の repo name)
   - 既に activated なら no-op、未 active なら activate

### Phase 2: Session context snapshot

1. 現在のセッション状態を構造化 summary に整理:
   - **Project**: 現在 branch / 直近 commit hash / 進捗概要
   - **TaskList 最終状態**: TaskList ツールで取得した全 task の (id / status / subject) 一覧
   - **累計 commits**: 本セッション中の commit 一覧 (`git log` で取得、新しい順 max 10 件)
   - **主要 artifact**: 本セッション中に追加・変更した主要ファイル (一覧)
   - **user 要求への対応**: user の主要指示と対応結果
   - **次セッション着手手順**: 番号付きリストで明示
   - **教訓**: 本セッション末で memory `feedback_*.md` に追加すべき教訓 (あれば)
2. `mcp__serena__write_memory("session/context", <full_state_markdown>)` で保存

### Phase 3: Last-session summary

1. 本セッションの achievement / user 指摘 / 次セッション着手 を 1-2 段落に要約 (`session/context` より簡潔版)
2. `mcp__serena__write_memory("session/last", <summary>)`

### Phase 4: Incremental checkpoint (option)

PDCA cycle 中の進捗が `session/context` より新しい場合のみ:
1. 直近 30 分相当の進捗を抽出
2. `mcp__serena__write_memory("session/checkpoint", <progress>)`

### Phase 5: docs/temp/ cleanup (option)

`docs/temp/` 配下に PDCA cycle の hypothesis-* / experiment-* / lessons-* ファイルがあれば:
- 成功 pattern → `docs/patterns/<name>.md` に昇格 (write)
- 失敗 case → `docs/mistakes/<feature>-YYYY-MM-DD.md` に昇格
- 該当 temp file は削除

(本 cleanup は optional、user 指示がなければ skip 可)

### Phase 6: 完了報告

stdout に以下を出力:

```
✅ Session state saved to Serena memory.
   - session/context (full snapshot)
   - session/last (1-2 paragraph summary)
   - session/checkpoint (if incremental progress)

Resume with `/resume-state` in next session.
```

## 引数

引数なし。常に full session state を保存する。

## エラーハンドリング

| 状況 | 動作 |
|---|---|
| Serena MCP 未注入 (`mcp__serena__*` tool 不在) | Phase 1 で停止 + 案内 message + exit |
| `check_onboarding_performed` が未済を返す | 同上 |
| `activate_project` が fail (project 不在 / hash 不一致) | warning 出力 + 続行 (memory 書き込みは試行) |
| `write_memory` の各 key が fail | 該当 key を skip + 残り key を試行、最後に集計報告 |

## 関連

- `/resume-state` — 復元コマンド (本コマンドの逆)
- `/pm-start` — PM Agent (Session End Protocol で本コマンドを自動呼び出し)
- Serena MCP: `~/.claude/projects/<project_hash>/memory/` 配下に Markdown ファイルとして物理保存
- Memory key schema (PM Agent spec 準拠):
  - `session/context` — 完全 snapshot
  - `session/last` — 前 session summary
  - `session/checkpoint` — 進捗 checkpoint
  - `plan/<feature>/hypothesis` — Plan 仮説
  - `execution/<feature>/do` — Do 実験ログ
  - `evaluation/<feature>/check` — Check 評価
  - `learning/patterns/<name>` — 成功 pattern
  - `learning/solutions/<error>` — error 解決 DB
  - `learning/mistakes/<timestamp>` — 失敗分析
  - `project/context` — project 全体理解
  - `project/architecture` — system architecture
