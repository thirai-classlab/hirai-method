# /pm-start — PM Agent orchestration with Serena memory

PM Agent (Project Manager) として user request を分析、適切な subagent に委譲し、PDCA cycle 全段階で Serena memory に永続化する自前コマンド。SuperClaude `/sc:pm` の後継。Serena MCP 必須。

## 前提

- **Serena MCP が `.mcp.json` に登録され、`mcp__serena__*` tool が利用可能であること**
- 命名衝突回避: 既存 `orchestrate` (Legacy slash-entry shim) との shadow を避けるため `/pm-start` を採用
- session 中断耐性 (`/save-state` / `/resume-state`) と相補関係

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を順次実行してください。

### Phase 1: Session Start Protocol (auto-restore)

新規 session 開始 / `/pm-start` 初回呼出時、`/resume-state` 相当の auto-restore を内包:

1. `mcp__serena__activate_project` (引数 = current project name)
   - 戻り値が success: 続行 (onboarding 済 + project 登録済を意味する)
   - 戻り値が error で `onboarding` / `not performed` を含む: 「Serena MCP onboarding が未完了です。`/onboarding` で完了させてください。」+ 終了
   - その他 error: warning 出力 + Phase 2 へ続行 (新規 session 扱い)
2. `mcp__serena__list_memories` で全 key 取得

> **設計補足**: 旧版では `mcp__serena__check_onboarding_performed` を呼んでいたが、現 Serena MCP には該当 tool が存在しない (2026-05-23 確認、deferred tools list にも無し)。代わりに `activate_project` の error response で onboarding 未済を検知する。
3. `session/context` が存在すれば:
   - `read_memory("session/context")` で完全 snapshot 復元
   - `read_memory("session/last")` で last summary
   - 復元レポートを user に提示 (`/resume-state` Phase 4 と同 format):
     - 📋 前回 (Last session) / 📊 進捗 / 🎯 次回 / ⚠️ 課題
4. `session/context` 不在なら新規 session として開始 (Phase 2 へ)

### Phase 2: User request analysis

user の最新 prompt から request の本質を抽出:

1. **request type 判定**:
   - **brainstorm**: 「〇〇について検討」「アイディアを出して」等の発散思考 → Socratic 対話モード
   - **direct**: 「〇〇を実装」「修正して」等の明確タスク → 即実行
   - **multi-agent**: 複数領域横断 (frontend + backend + DB 等) → parallel subagent
   - **wave**: 大規模機能 (W1-Wn の段階実装) → sequential subagent + 各 Wave 検証
2. **複雑度判定** (0-100):
   - 影響ファイル数 / 設計判断点数 / セキュリティ影響 / migration 有無 をスコア化
   - 50 以上なら draft → 承認 → `/new-task` フローを推奨
3. **TaskCreate** で全 sub-task を登録 (依存関係を `addBlockedBy` で明示)

### Phase 3: Subagent delegation

選択した request type に基づき subagent 起動:

1. Agent tool で subagent を起動 (`run_in_background: true` 必須 — `.claude/rules/modes.md` 遵守事項 7)
2. 並列可能なら独立 task を同 turn で複数 subagent 起動
3. 依存関係ある task は完了通知後に次 subagent 起動
4. メインは subagent 待ち中も独立作業を継続 (loop-auto-progress-reminder hook の規範遵守)

### Phase 4: PDCA cycle (continuous)

作業進行に応じて 4 段階で Serena memory を更新:

1. **Plan (仮説形成)**:
   - `mcp__serena__write_memory("plan/<feature>/hypothesis", <仮説>)` で目的 + 期待結果 + リスク
   - 例: `plan/auth/hypothesis` = "JWT validation を middleware に追加。期待: 全 protected route で 401 統一"
2. **Do (実装・試行錯誤)**:
   - `mcp__serena__write_memory("execution/<feature>/do", <試行ログ>)` で実装ステップ + error + 解決
   - root cause first 原則: error は必ず investigate (context7 / WebFetch / Grep) してから fix
   - 同じ failure を盲目 retry しない
3. **Check (評価)**:
   - `mcp__serena__write_memory("evaluation/<feature>/check", <評価>)` で test 結果 + 期待 vs 実測
   - `think_about_task_adherence` 相当の自己評価
4. **Act (改善・教訓)**:
   - 成功 pattern → `mcp__serena__write_memory("learning/patterns/<name>", <pattern>)`
   - error 解決 → `mcp__serena__write_memory("learning/solutions/<error_type>", <solution>)`
   - 失敗 case → `mcp__serena__write_memory("learning/mistakes/<timestamp>", <分析>)`
   - 教訓は CLAUDE.md Critical Operational Lessons / `feedback_*.md` memory にも転載

### Phase 5: Session End

session 終了が予見される (`/save-state` 明示呼出 / context budget 警告 / user 中断指示) 時:

1. `/save-state` を自動呼出 (Phase 1-6 順次実行)
2. user に再開手順を案内:
   ```
   ✅ Session ended. State saved to Serena memory.
   Resume with `/pm-start` (auto-restore) or `/resume-state` (manual) in next session.
   ```

## 引数

- `<user-request>` (option): request text を直接渡す。省略時は最新 user prompt を analysis 対象とする
- `--no-restore`: Phase 1 を skip (新規 session 強制)
- `--mode <brainstorm|direct|multi-agent|wave>`: Phase 2 request type 判定を override

## エラーハンドリング

| 状況 | 動作 |
|---|---|
| Serena MCP 未注入 | Phase 1 で停止 + 案内 |
| onboarding 未済 | 同上 |
| `session/context` 復元失敗 | Phase 1 で warning + 新規 session として続行 |
| subagent 起動失敗 | Phase 3 で再試行 (1 回)、失敗継続なら user 報告 |
| PDCA `write_memory` fail | warning + cycle 続行 (memory なし状態の継続実行) |

## 関連

- `/save-state` — session 状態保存 (Phase 5 で auto-invoke)
- `/resume-state` — session 復元 (Phase 1 で auto-invoke 相当)
- `.claude/hooks/mode-session-start.sh` — SessionStart 時に `/pm-start` 起動を suggesting (W2)
- `.claude/rules/modes.md` 遵守事項 7 (subagent 並走中の独立作業義務)
- Memory key schema:
  - `session/context` / `session/last` / `session/checkpoint` (session 永続化)
  - `plan/<feature>/{hypothesis,architecture,rationale}` (Plan)
  - `execution/<feature>/{do,errors,solutions}` (Do)
  - `evaluation/<feature>/{check,metrics,lessons}` (Check)
  - `learning/{patterns,solutions,mistakes}/<name>` (Act, 横断的)
  - `project/{context,architecture,conventions}` (project 全体理解)

## 設計起源

`docs/draft/custom-pm-commands.md` §3 W1 + `docs/tasks/task-7-custom-pm-commands.md` §設計 W1 (採用プロジェクト側で詳細参照)
