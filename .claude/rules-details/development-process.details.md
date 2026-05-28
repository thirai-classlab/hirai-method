---
paths: []
related: development-process.md
---

# 開発プロセスルール — 詳細版 (Layer B)

> Layer A: [`development-process.md`](../rules/development-process.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

本 file は Layer A の SSoT を補完する詳細解説。委譲必須要件 7 件の各論 / 違反例 / staging 戦略の起源 / cross-repo write 例外の実証経緯 / Confidence Gate の記載例 / harness 取込チェックリストの CI 自動化案 / 各規範の起源 (commit hash / draft path / 副産物 entry) を含む。Read trigger 4 条件は Layer A 冒頭参照。

## 研究と再利用-詳細

### 適用対象 task (完全 list)

- 新 library / package 採用前 (npm install / pnpm add / pip install 等の **直前**)
- 既存 library の major version migration (例: React 18 → 19、Next.js 14 → 16)
- API syntax / config / option の確認 (新 hook / 新 API 利用時)
- error message debug (library 由来 error の stack trace を context7 / 公式 docs と照合)
- 新機能 / lifecycle hook の利用 (例: Next.js Cache Components / use cache directive 等)

### 関連設定

- `.mcp.json` の context7 entry (`npx -y @upstash/context7-mcp@latest`、stdio transport)
- 採用 4 リポへ portable 同期済 (本 repo `.mcp.json` SSoT + `install.sh --update` で同期)
- subagent 委譲時も同 chain 適用 (Agent prompt に「library 仕様確認は context7 を最初に」と明示)

### bypass の補足

- MCP server fail (context7 unreachable / npx fail) で loop 停止しない構造は §「Bash deny / whitelist 不在時の subagent 委譲反射」と類似 (fail → fallback chain に自動 retry、停止理由にしない)
- 起源 memory: `feedback_verify_path_before_implementation.md` (verify before recommending 原則)

## 委譲必須要件-詳細

### 要件 1: background 起動強制 の補足

- **理由**: メインがサブの完了を待つ間、ユーザーが新規指示を出せない (UX 劣化)。長時間タスクの進捗確認・追加指示・割り込みを常に受け付けるためメインを解放
- **違反例**: foreground 起動でメインがブロックされ、ユーザーが「進捗確認」さえ困難
- **運用**: 完了通知は SubagentStop hook 経由でメインに届く (ポーリング不要)

### 要件 2: 順序整合性保証 の各論

- **依存関係解決**: タスク A の出力をタスク B が消費する場合、A 完了通知を受けてから B 起動。サブに委譲不可
- **並行可能性判定**: 独立ファイル領域 / 独立ブランチ / 独立 cost セッションのタスクは並行 OK。重なる場合は逐次化
- **partial commit 整合性**: 各サブの commit が conflict しないことをメインが事前判定 (同一 file 編集の重複起動を防ぐ)
- **完了通知 → 次タスク**: メインが完了通知を受けたら次タスク起動 / user 判断要請 / 中断のいずれかをメイン責任で決定

### 要件 4: TaskCreate 登録 の必須項目

- **subject**: サブに振り出した作業の概要 (例: 「config-loader env override 汎用化」)
- **description**: 委譲スコープ / 完了条件 / 想定 cost / 並行可否
- **metadata.subagent_id**: Agent tool 起動時の `agentId` (追跡可能性)
- **status 遷移**: `pending` → `in_progress` (起動直後) → `completed` (完了通知受信時)

#### 依存関係の明示

- 並行可能タスクは独立に作成 (依存なし)
- 逐次タスクは `addBlockedBy` / `addBlocks` で依存関係明示
- メインは TaskList でいつでも全状態確認可能にする

#### 違反例

- TaskCreate せずに subagent 起動 → ユーザーが何が走っているか不明
- 完了通知後に `completed` にしない → 古いタスクが残留
- subagent_id 未記録 → 後追いトレース不能

#### 理由

- **可観測性**: ユーザーが `TaskList` でいつでも進捗確認
- **責任の明確化**: メインの orchestration 義務 (要件 3) を Claude Code 標準機構に裏付け
- **再開性**: セッション再起動時もタスクリストから現状復元可能

### 要件 5: Bash deny 時の委譲反射 の詳細

#### 禁止事項

- **Bash deny を loop 停止理由にしてはならない**
- 「これ以上進めない」と user に報告して止まる前に、必ず Agent tool で subagent に振り出す
- whitelist への 1 行追加申請は user の選択肢として提示してよいが、提示前に subagent 委譲を試行する

#### 委譲反射の手順

1. Bash が deny された → tool error / hook block / whitelist 不在を検知
2. 直ちに Agent tool 起動 (`run_in_background: true` 必須)
3. subagent に「メインで block された Bash 操作」を委譲
4. TaskCreate でタスク登録 (要件 4)

#### 違反例

- メインが「Bash 全面 block でこれ以上進めません。loop 停止します」と発言 → 誤動作
- whitelist 1 行追加申請のみ提案して subagent 委譲を試みない → 申請は user 検討事項、まずは委譲反射

#### 例外

- subagent も deny で進められない場合 (極稀) → user に状況報告 + permission 設定変更を依頼
- 委譲先が無いタスク (例: メインの memory 操作) → そもそも Bash 不要なはず

#### 理由

- Bash whitelist は **メインからの直接 Bash** 許可リスト。subagent 経由は別経路
- 委譲ガード (`delegation-guard.sh`) は「メインが直接コードを触る」ことを防ぐためで、subagent はその対象外
- 「Bash deny = 進行不能」と短絡判断するとハーネス本来の目的 (メイン → subagent 委譲) を裏切る

### heredoc / quoted string の保護 (要件 4 補足)

`git commit -m "table|cell"` や `git commit -m 'A || B'` の `|` `||` `&&` `;` は quote-aware segment splitter (`split_command_segments` 関数、`.claude/hooks/delegation-guard.sh`) が separator 扱いせず単一 segment として whitelist 照合する。詳細は `.claude/tests/delegation-guard-segment-smoke.sh` Case 4-6 を参照。

heredoc 本文 (`<<EOF ... EOF`) は単行解析の限界で未対応 (将来 B フル parser 化で対応予定)。

### 要件 6: 並列化義務 の機械強制詳細

#### 機械強制 hook の判定境界 (count ≤ 1 で warning)

`parallel-subagent-reminder.sh` は **TTL filter 後の他 Agent 起動数 ≤ 1** で「単独起動」と判定し warning 注入:

- `count=0`: 完全初回起動 (warning)
- `count=1`: 直前 TTL 内に 1 件、本起動が 2 件目だが保守的に warning 注入 (並列化推奨継続)
- `count≥2`: 並列起動済み (silent)

「他 Agent 起動なし = 0 件」と読めた旧表現は `≤ 1` 境界値の正確な表現に修正。

#### 違反例

- 独立 file 領域 (例: 3 file 編集) を 1 subagent に統合委譲 → 並列化機会逃失
- 「規範追加 + hook 新設 + smoke 新設」のような完全独立 sub-task を sequential 起動 → 3 倍時間消費

#### 違反検出時の対応

1. **即時切替**: 起動済 subagent を継続させつつ、次の sub-task 群から並列起動に切替
2. **教訓記録**: memory `feedback_*.md` に「並列化逃失の trigger / 真因 / 再発防止策」追記
3. **規範補強**: 同種違反の再発観測時、本セクションに具体例追加

### 要件 7: agent type 選定義務 の各論

#### 設定不要原則 (user 強調要件、2026-05-25)

採用者は `harness-config.yml` を編集しなくても、**hook 内 hardcode の default mapping** で agent type が自動判定される。`harness-config.yml` での override は任意 (advanced 用途のみ)、未設定でも完全動作。

これは「ハーネス採用 = box-open で即動作」を保証する SSoT 設計。default mapping を hook 内 SSoT として保持し、yaml override は補完オプション位置付け。

#### agent-router skill 連携 (補完オプション、Phase 2 future)

既存 `agent-router` skill (Anthropic 提供) を SessionStart で auto-trigger 可能なら、本 hook と組合せで深い解析対応:

- 本 hook (`parallel-subagent-reminder.sh`): PreToolUse(Agent) 時点の即時 warning 注入 (軽量 keyword 照合)
- `agent-router` skill: task description の semantic 解析 (LLM 経由、深い推論)

採用判断:
- **Phase 1 (現状)**: 本 hook のみ実装 (軽量、確実、LLM cost 0)
- **Phase 2 (future)**: `agent-router` skill auto-trigger 検討 (LLM cost 評価後)

#### 違反例

- test 拡張 task で `general-purpose` を default 採用 → `test-automator` の専門知識を逃失 (2026-05-25 task-35 Subagent B 実例)
- refactor task で `general-purpose` を default 採用 → `refactoring-specialist` の behavior-preserving 知識を逃失 (2026-05-25 task-34 Step 5 実例)
- 言語別 build error で `general-purpose` 採用 → 言語特化 `*-build-resolver` の error pattern 知識を逃失

#### 違反検出時の対応

1. **即時切替**: 該当 sub-task を停止せず継続、次の同種 sub-task から専門 agent type 採用
2. **mapping 拡張検討**: 既存 mapping に該当 keyword がない場合、Layer A の mapping 表に追記提案 (規範化 task 起票)
3. **教訓記録**: memory `feedback_*.md` に「agent type 選定逃失の trigger / 真因」追記

#### 機械強制 (soft warning)

同 `parallel-subagent-reminder.sh` 内で agent type 選定を照合:

- PreToolUse(Agent) 時点で `tool_input.subagent_type == "general-purpose"` ∧ task description に専門 type 適合 keyword 検出 → `<system-reminder>` で「専門 type 推奨」warning 注入
- BLOCK しない (false positive 回避、AI 判断尊重)

#### bypass

並列化義務 §6 の bypass (`HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false`) で agent type 選定 warning も同時無効化 (1 hook 統合のため)。個別無効化は現状未提供 (将来 `HC_AGENT_TYPE_REMINDER_ENABLED` 等で分離検討可)。

#### 任意 override (advanced 用途)

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

## 並列化義務-起源

### 並列化義務 (要件 6) の起源

- 2026-05-25 task-35 Step 1+2+4 を 1 subagent に統合委譲した実例 (本来 3 並列起動可能だった file 領域独立 sub-task)
- 設計 draft: `docs/draft/parallel-subagent-enforcement.md` §4.1 (規範強化部)
- 副産物 entry #23
- 規範化 task: #38

### agent type 選定義務 (要件 7) の起源

- 2026-05-25 task-35 Subagent B (test 拡張) で `general-purpose` 採用、`test-automator` を逃失
- 2026-05-25 task-34 Step 5 (refactor) で `general-purpose` 採用、`refactoring-specialist` を逃失
- user 強調要件「設定不要で自動的に判断」(2026-05-25 13th save-state 後)
- 設計 draft: `docs/draft/parallel-subagent-enforcement.md` §4.5 + §4.5.0 設定不要原則
- 規範化 task: #38

### Hook による補助 (soft warning)

`.claude/hooks/agent-marker-set.sh` は PreToolUse(Agent) で foreground 起動を検出した場合、stderr に WARN を出す (block ではない)。`tool_input.run_in_background != true` のときに発火。

## staging-戦略-起源

### task #12 dual-mode-portability 由来

本規範は task #12 dual-mode-portability 実装中の発見 (2026-05-13) から起こされた。subagent ad80e8f5b63437f01 で以下 3 パターンの permission denied を全件確認:

1. `Write` tool で `file_path` が `.claude/` 配下
2. `Edit` tool で `file_path` が `.claude/` 配下
3. `Bash` で `cat > .claude/...` / `tee .claude/...` heredoc redirect

### 関連 artifact

- task #12: `feat/loop-mode` ブランチ、commit `4ddf115`〜`93100a8` (2026-05-13)
- Serena memory: `learning/solutions/subagent-claude-permission-staging` (subagent context での `.claude/` write 制約と staging 回避策)
- 副産物 entry: `docs/tasks/next-actions.md` entry #12 (2026-05-13、🟡)
- 規範化 task: #13 (本セクション追加)

### 再発検出時の昇格判定

honor system のため、subagent dispatch prompt への staging 明示忘れリスクは残存する。再発が **N=2 以上** 観測されたら、副産物 entry を起こし以下を検討:

- **案 B**: `.claude/templates/` に staging 強制プロンプト template 新設 + `/new-task` 系 command が自動参照
- **案 C**: 専用 hook `subagent-staging-reminder.sh` で PreToolUse(Agent) に staging 強制注入

## cross-repo-write-起源

### 実証経緯

- 2026-05-23 task-24 W1 subagent a174bcef696b54860 confidence 0.85 で実証 (cross-repo Write / cp / mv / heredoc redirect が一律 deny、`dangerouslyDisableSandbox: true` 付き Bash も block)
- task-26 W6 / task-21 W3.3 で同じ blocker を再確認、user manual `bash install.sh --update <target>` で 3 リポ反映完了

### 関連 artifact

- Serena memory: `feedback_cross_repo_write_sandbox_block.md` (2026-05-23、本 rule の事実根拠)
- 副産物 entry: `docs/tasks/next-actions.md` entry #17 (2026-05-23、🟡)
- 規範化 task: #31 (本セクション追加)
- audit: `.claude/.workflow-state/bypass.log` (cross-repo agent 試行 block 痕跡)、`harness-audit.py` `bypass_log_summary` (再発検知)

### 関連 memory (緩和方向)

- `feedback_cross_repo_write_sandbox_block.md` (2026-05-26 SUPERSEDED): task-42 Step 9 で 4 リポ全件 agent 直接 Read/Write 成功実証 (classlab-weekly-news / TEST / recall_poc / taskManageSystem confidence 0.92)、cross-repo task は最初に試行 → block 確認で user manual 切替の判断順序に変更

### 将来追随窓口

system-level sandbox 仕様変化 (例: Claude Code が cross-repo Write を opt-in で許可する future feature) への追随は `docs/tasks/parking-lot.md` 🔍「cross-repo sandbox 緩和の future Claude Code 仕様変化追随」entry で四半期 review、Claude Code release notes 監視を user manual で実施。

## confidence-gate-詳細

### 記載例

```text
F3 confidence-gate.sh を実装し以下を確認:
- 6 ケースの mock transcript で期待動作を確認（pass/block/env override/bypass）
- harness-audit に新セクション追加、bypass.log を集計
- settings.json の SubagentStop に wired

confidence: 0.9
```

### major subagent only block (2026-05-13、task #9) の補足

F3 confidence-gate は **major subagent (`general-purpose` / `Explore` / `Task` allowlist or `is_sidechain==path_subagents`)** のみ confidence 自己評価を強制し、軽量 sidechain (Task tool query / 短い tool-use only sidechain) は **fail-open** で通過させる。

- env `HC_CONFIDENCE_MAJOR_AGENT_ONLY=false` で従来動作 (全 stop event で block 判定) に復帰可
- 設計起源: `docs/draft/harness-audit-followups.md` §3 W1 (2026-05-13)
- 観測: `/harness-audit` で `regex_no_match` 累計が major subagent 由来のみに絞られる

## harness-取込-詳細

### CI 自動化 (将来 opt-in、parking-lot)

CI (GitHub Actions 等) で hirai-method SSoT と `.claude/` の diff を定期検出 → PR / issue 自動起票する自動化案 (案 B) は **consuming repo 側の opt-in** で将来導入。詳細は `docs/tasks/parking-lot.md` の 🔍 entry「CI 自動 .claude diff 検出 (G2 案 B)」を参照。

### 取込手順の補足

- **hirai-method 最新化**: consuming repo 側に直接 push する場合は不要
- **`bash install.sh --update <consuming repo absolute path>`** は cross-repo write のため **user manual (terminal) 実行のみ可能** (詳細: §「cross-repo write 例外」)
- **分離 commit** (task-58 G1) で `chore: sync .claude/ from hirai-method <YYYY-MM-DD>` 形式で記録、`install.sh --update --commit` flag で自動 commit 可能

### 起源

- 2026-05-28 task-59 (G2: harness-sync-proactive-workflow)、設計 draft: [`docs/draft/harness-sync-proactive-workflow.md`](../../docs/draft/harness-sync-proactive-workflow.md) §3 採用案 C ハイブリッド
- 前提:
  - task-56 = F (stale-harness-detect、reactive 検出 + WARN 案内、commit `f5149fb`)
  - task-58 = G1 (未 commit drift、`install.sh --update --commit` flag)
- F WARN 連携: `stale-harness-detect.sh` の WARN 文に既に「`bash install.sh --update <repo>`」案内が含まれる (commit `f5149fb`、smoke Case 2 で grep verify 済、Case 10 で取込手順 strengthen)

## 起源

- **コーディング指針 (karpathy-guidelines)**: 採用済 skill `.claude/skills/karpathy-guidelines/SKILL.md`、LLM コーディング行動規約の SSoT
- **TDD 4 step**: 採用済 skill `.claude/skills/tdd-workflow/SKILL.md` 由来
- **委譲必須要件 7 件**: 各要件の起源は各 §「起源」 (要件 6: task-35 / 要件 7: task-35 + task-34)、規範化 task #38
- **staging 戦略**: task #12 (2026-05-13)、規範化 task #13
- **cross-repo write 例外**: task-24 W1 / task-26 W6 / task-21 W3.3 (2026-05-23)、規範化 task #31、緩和 task-42 (2026-05-26)
- **Confidence Gate F3**: F3 confidence-gate.sh、`docs/CONFIDENCE-GATE.md` SSoT、major subagent only block は task #9 (2026-05-13)
- **harness 取込チェックリスト**: task-59 (G2、2026-05-28)、前提 task-56 (F) / task-58 (G1)
- **副産物即時 draft 起こし義務**: `docs/draft/byproduct-discharge-mechanism.md`、強制機構は次セッション実装予定
- 各規範の commit hash / 採用判断は git log + 関連 draft 参照
