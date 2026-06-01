> Layer A: [`development-process.md`](../../rules/development-process.md) §サブエージェント委譲の必須要件 7 件 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 委譲必須要件 詳細 (Layer B)

## 要件 1: background 起動強制 の補足

- **理由**: メインがサブの完了を待つ間、ユーザーが新規指示を出せない (UX 劣化)。長時間タスクの進捗確認・追加指示・割り込みを常に受け付けるためメインを解放
- **違反例**: foreground 起動でメインがブロックされ、ユーザーが「進捗確認」さえ困難
- **運用**: 完了通知は SubagentStop hook 経由でメインに届く (ポーリング不要)

## 要件 2: 順序整合性保証 の各論

- **依存関係解決**: タスク A の出力をタスク B が消費する場合、A 完了通知を受けてから B 起動。サブに委譲不可
- **並行可能性判定**: 独立ファイル領域 / 独立ブランチ / 独立 cost セッションのタスクは並行 OK。重なる場合は逐次化
- **partial commit 整合性**: 各サブの commit が conflict しないことをメインが事前判定 (同一 file 編集の重複起動を防ぐ)
- **完了通知 → 次タスク**: メインが完了通知を受けたら次タスク起動 / user 判断要請 / 中断のいずれかをメイン責任で決定

## 要件 4: TaskCreate 登録 の必須項目

- **subject**: サブに振り出した作業の概要 (例: 「config-loader env override 汎用化」)
- **description**: 委譲スコープ / 完了条件 / 想定 cost / 並行可否
- **metadata.subagent_id**: Agent tool 起動時の `agentId` (追跡可能性)
- **status 遷移**: `pending` → `in_progress` (起動直後) → `completed` (完了通知受信時)

### 依存関係の明示

- 並行可能タスクは独立に作成 (依存なし)
- 逐次タスクは `addBlockedBy` / `addBlocks` で依存関係明示
- メインは TaskList でいつでも全状態確認可能にする

### 違反例

- TaskCreate せずに subagent 起動 → ユーザーが何が走っているか不明
- 完了通知後に `completed` にしない → 古いタスクが残留
- subagent_id 未記録 → 後追いトレース不能

### 理由

- **可観測性**: ユーザーが `TaskList` でいつでも進捗確認
- **責任の明確化**: メインの orchestration 義務 (要件 3) を Claude Code 標準機構に裏付け
- **再開性**: セッション再起動時もタスクリストから現状復元可能

## 要件 5: Bash deny 時の委譲反射 の詳細

### 禁止事項

- **Bash deny を loop 停止理由にしてはならない**
- 「これ以上進めない」と user に報告して止まる前に、必ず Agent tool で subagent に振り出す
- whitelist への 1 行追加申請は user の選択肢として提示してよいが、提示前に subagent 委譲を試行する

### 委譲反射の手順

1. Bash が deny された → tool error / hook block / whitelist 不在を検知
2. 直ちに Agent tool 起動 (`run_in_background: true` 必須)
3. subagent に「メインで block された Bash 操作」を委譲
4. TaskCreate でタスク登録 (要件 4)

### 違反例

- メインが「Bash 全面 block でこれ以上進めません。loop 停止します」と発言 → 誤動作
- whitelist 1 行追加申請のみ提案して subagent 委譲を試みない → 申請は user 検討事項、まずは委譲反射

### 例外

- subagent も deny で進められない場合 (極稀) → user に状況報告 + permission 設定変更を依頼
- 委譲先が無いタスク (例: メインの memory 操作) → そもそも Bash 不要なはず

### 理由

- Bash whitelist は **メインからの直接 Bash** 許可リスト。subagent 経由は別経路
- 委譲ガード (`delegation-guard.sh`) は「メインが直接コードを触る」ことを防ぐためで、subagent はその対象外
- 「Bash deny = 進行不能」と短絡判断するとハーネス本来の目的 (メイン → subagent 委譲) を裏切る

## heredoc / quoted string の保護 (要件 4 補足)

`git commit -m "table|cell"` や `git commit -m 'A || B'` の `|` `||` `&&` `;` は quote-aware segment splitter (`split_command_segments` 関数、`.claude/hooks/delegation-guard.sh`) が separator 扱いせず単一 segment として whitelist 照合する。詳細は `.claude/tests/delegation-guard-segment-smoke.sh` Case 4-6 を参照。

heredoc 本文 (`<<EOF ... EOF`) は単行解析の限界で未対応 (将来 B フル parser 化で対応予定)。

## 要件 6: 並列化義務 の機械強制詳細

### 機械強制 hook の判定境界 (count ≤ 1 で warning)

`parallel-subagent-reminder.sh` は **TTL filter 後の他 Agent 起動数 ≤ 1** で「単独起動」と判定し warning 注入:

- `count=0`: 完全初回起動 (warning)
- `count=1`: 直前 TTL 内に 1 件、本起動が 2 件目だが保守的に warning 注入 (並列化推奨継続)
- `count≥2`: 並列起動済み (silent)

「他 Agent 起動なし = 0 件」と読めた旧表現は `≤ 1` 境界値の正確な表現に修正。

### 違反例

- 独立 file 領域 (例: 3 file 編集) を 1 subagent に統合委譲 → 並列化機会逃失
- 「規範追加 + hook 新設 + smoke 新設」のような完全独立 sub-task を sequential 起動 → 3 倍時間消費

### 違反検出時の対応

1. **即時切替**: 起動済 subagent を継続させつつ、次の sub-task 群から並列起動に切替
2. **教訓記録**: memory `feedback_*.md` に「並列化逃失の trigger / 真因 / 再発防止策」追記
3. **規範補強**: 同種違反の再発観測時、本セクションに具体例追加

## 要件 7: agent type 選定義務 の各論

### 設定不要原則 (user 強調要件、2026-05-25)

採用者は `harness-config.yml` を編集しなくても、**hook 内 hardcode の default mapping** で agent type が自動判定される。`harness-config.yml` での override は任意 (advanced 用途のみ)、未設定でも完全動作。

これは「ハーネス採用 = box-open で即動作」を保証する SSoT 設計。default mapping を hook 内 SSoT として保持し、yaml override は補完オプション位置付け。

### agent-router skill 連携 (補完オプション、Phase 2 future)

既存 `agent-router` skill (Anthropic 提供) を SessionStart で auto-trigger 可能なら、本 hook と組合せで深い解析対応:

- 本 hook (`parallel-subagent-reminder.sh`): PreToolUse(Agent) 時点の即時 warning 注入 (軽量 keyword 照合)
- `agent-router` skill: task description の semantic 解析 (LLM 経由、深い推論)

採用判断:
- **Phase 1 (現状)**: 本 hook のみ実装 (軽量、確実、LLM cost 0)
- **Phase 2 (future)**: `agent-router` skill auto-trigger 検討 (LLM cost 評価後)

### 違反例

- test 拡張 task で `general-purpose` を default 採用 → `test-automator` の専門知識を逃失 (2026-05-25 task-35 Subagent B 実例)
- refactor task で `general-purpose` を default 採用 → `refactoring-specialist` の behavior-preserving 知識を逃失 (2026-05-25 task-34 Step 5 実例)
- 言語別 build error で `general-purpose` 採用 → 言語特化 `*-build-resolver` の error pattern 知識を逃失

### 違反検出時の対応

1. **即時切替**: 該当 sub-task を停止せず継続、次の同種 sub-task から専門 agent type 採用
2. **mapping 拡張検討**: 既存 mapping に該当 keyword がない場合、Layer A の mapping 表に追記提案 (規範化 task 起票)
3. **教訓記録**: memory `feedback_*.md` に「agent type 選定逃失の trigger / 真因」追記

### 機械強制 (soft warning)

同 `parallel-subagent-reminder.sh` 内で agent type 選定を照合:

- PreToolUse(Agent) 時点で `tool_input.subagent_type == "general-purpose"` ∧ task description に専門 type 適合 keyword 検出 → `<system-reminder>` で「専門 type 推奨」warning 注入
- BLOCK しない (false positive 回避、AI 判断尊重)

### bypass

並列化義務 §6 の bypass (`HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false`) で agent type 選定 warning も同時無効化 (1 hook 統合のため)。個別無効化は現状未提供 (将来 `HC_AGENT_TYPE_REMINDER_ENABLED` 等で分離検討可)。

### 任意 override (advanced 用途)

採用者が hook 内 default mapping を上書き / 拡張したい場合のみ `harness-config.yml` で override 可:

```yaml
# 設定不要原則のため、本キーは optional (未設定なら hook 内 hardcode 使用)
agent_type_keyword_mapping:
  test-automator:
    - "smoke 拡張"
    - "test 追加"
    - "<採用者追加 keyword>"
```

env override: `HC_AGENT_TYPE_KEYWORD_MAPPING=...` (改行区切り、advanced 用途)。
