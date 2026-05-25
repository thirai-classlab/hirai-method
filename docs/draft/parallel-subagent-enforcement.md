---
approval_required: true
approved_at: ""
---

# Draft: parallel-subagent-enforcement (並列サブエージェント起動の機械強制)

> Status: 起案 (2026-05-25)
> 起案者: user (本 session 後半「ハーネスで並列化を強制してください (可能な限り、作業に齟齬がでないように)」)
> 関連: 副産物 entry #23 / 既存規範 `.claude/rules/development-process.md` §「サブエージェント委譲」

## 1. 背景

本 session で reviewer 並列 (採用 6 条 4) は遵守された (23 並列起動) が、fix 系 sub-task は 1 subagent 統合委譲が default 化し、5 件統合 = 並列化機会逃失。具体的に task-35 Step 1+2+4 を 1 subagent に統合委譲、本来 3 並列起動可能 (file 領域独立) だった。

honor system のみで強制不能。machine enforcement が必要。

## 2. 要件

- 独立 sub-task (file 領域独立 / 依存関係なし) の **並列起動を default** とする
- 機械強制 + soft warning で AI 判断を補完
- false positive 最小化 (誤検知で並列強制すると race condition / 共有 file 衝突 リスク)
- bypass env で開発時の一時無効化可能
- 既存 reviewer 並列 (採用 6 条 4) と整合 (重複 reminder 禁止)

## 3. 設計案 (4 案比較)

### 案 A: PreToolUse(Agent) hook で並列度強制 BLOCK

- 同 turn 内で過去 N tool_use 内に同種 task description の Agent 起動なし → 単独 Agent 起動を BLOCK
- 強: 機械強制で確実
- 弱: 「同種 task description」判定が困難、false positive リスク大、AI が回避困難で詰む

### 案 B: UserPromptSubmit / PreToolUse(Agent) で soft reminder

- 該当 turn で Agent tool_use 1 件のみ + 直近の task description に「実装」「fix」「refactor」「設計」「smoke 拡張」keyword 検出 → `<system-reminder>` で warning 注入
- 強: false positive でも warning のみで BLOCK しない、AI が判断可能、開発体験悪化最小
- 弱: 機械強制ではなく honor system に依存

### 案 C: SubagentStop hook で post-hoc 監査

- 各 turn の Agent 起動数を観測、N=1 起動なら次 turn で reminder
- 強: 観測ベース、誤検知少ない
- 弱: 違反検出が turn 遅延、開発体験悪化

### 案 D: 規範強化のみ (development-process.md §並列化義務)

- machine enforcement なし、honor system のみ
- 強: 実装コスト 0
- 弱: 違反継続のリスク (本 session で実証済)

## 4. 採用案 (案 B + D ハイブリッド)

### 4.1 規範強化 (案 D 部分)

`.claude/rules/development-process.md` §「サブエージェント委譲」配下に「並列化義務」サブセクション追加:

- 独立 sub-task (file 領域独立 + 依存関係なし) を 2+ 検出した場合、並列起動を **default**
- 1 subagent 統合委譲は **明示的理由が必要** (race risk / 共有 file 衝突 / context budget 制約 / sequential 必須)
- 違反検出時の対応: 次の sub-task で並列化 + 教訓 memory 追加

### 4.2 soft reminder hook (案 B 部分)

新 hook `.claude/hooks/parallel-subagent-reminder.sh`:

- PreToolUse(Agent) で発火
- 直近 N 分間の Agent tool_use 履歴を参照 (`.claude/.parallel-subagent-state/recent.json` 等で軽量記録、TTL 5 分)
- 単独起動 (履歴に他 Agent 起動なし) + task description に keyword 検出 → `<system-reminder>` 注入
- BLOCK しない (soft warning)
- bypass: `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false`

### 4.3 keyword 検出 pattern (false positive 最小化)

trigger keyword (1+ match で trigger):
- "実装" "fix" "refactor" "設計" "新設" "拡張" "改修"

除外 keyword (1+ match で skip、reviewer 系を除外):
- "reviewer" "review" "監査" "audit"

### 4.4 新 smoke (5 cases、§4.5 追加で 8 cases に拡張)

- Case 1: 単独 Agent 起動 + 実装系 description → warning 注入 (並列性)
- Case 2: 単独 Agent 起動 + review 系 description → silent
- Case 3: 並列 (2+) Agent 起動 → silent (history に既に Agent あり)
- Case 4 (fail-open): state file 不在環境 → exit 0 + silent
- Case 5 (bypass): env で disable → silent

### 4.5 適切な agent type 選定の機械強制 (本 session 2026-05-25 user 追加要件)

並列起動だけでなく **agent type 選定の適切性** も hook で強制する。本 session で `general-purpose` を default 採用した結果、test 拡張 / refactor 系で専門 agent type (`test-automator` / `refactoring-specialist`) を逃失した。

#### 4.5.0 設定不要原則 (user 強調要件「設定不要で自動的に判断」、2026-05-25)

採用者が `harness-config.yml` を編集しなくても、**hook 内 hardcode の default mapping** で自動判定する。`harness-config.yml` での override は **任意 (advanced 用途のみ)**、未設定でも完全動作する。

加えて、既存 `agent-router` skill (Anthropic 提供、`Route ambiguous "general-purpose" subagent prompts to the most appropriate specialist`) を SessionStart で auto-trigger 検討可。本 hook (`parallel-subagent-reminder.sh`) と agent-router skill は補完関係:
- 本 hook = PreToolUse(Agent) 時点の warning 注入 (即時介入)
- agent-router skill = `general-purpose` task description を解析し最適 specialist を推奨 (深い解析)

#### 4.5.1 default mapping (PreToolUse(Agent) で `subagent_type` + task description 照合)

| task description keyword | 推奨 subagent_type | 本 session 実例 |
|---|---|---|
| "smoke 拡張" "test 追加" "test 修正" "regression test" | `test-automator` | task-35 Subagent B (general-purpose 採用 ⚠️) |
| "refactor" "関数分割" "cleanup" "dead code" | `refactoring-specialist` or `refactor-cleaner` | task-34 Step 5 (general-purpose 採用 ⚠️) |
| "build error" "compile error" "type error" | 言語別 `*-build-resolver` | (本 session 該当なし) |
| "bash 品質" "shellcheck" "subshell" | `code-reviewer` | iter review で実証 (適切) |
| "設計レビュー" "architecture review" | `architect-reviewer` | iter review で実証 (適切) |
| "新 hook" "新 script" "新 file 実装" | `general-purpose` (OK、specialized 不在) | task-35 Subagent A (適切) |

#### 4.5.2 検出ロジック (案 B 拡張)

PreToolUse(Agent) で:
- `tool_input.subagent_type == "general-purpose"` ∧ task description に専門 type 適合 keyword 検出 → `<system-reminder>` で「専門 type 推奨」warning 注入
- BLOCK しない (false positive 回避、AI 判断尊重)

#### 4.5.3 新 smoke 拡張 (3 cases 追加で計 8 cases)

- Case 6: `general-purpose` + 「smoke 拡張」description → `test-automator` 推奨 warning
- Case 7: `general-purpose` + 「refactor」description → `refactoring-specialist` 推奨 warning
- Case 8: 専門 type (`test-automator` 等) 採用 → silent (適切)

#### 4.5.4 keyword → type mapping の hook 内 hardcode (default) + 任意 override

**default は hook 内 hardcode** (採用者設定不要、上記 4.5.1 mapping 表が SSoT):

```bash
# .claude/hooks/parallel-subagent-reminder.sh 内 (抜粋)
declare -A AGENT_TYPE_MAPPING=(
    ["test-automator"]="smoke 拡張|test 追加|test 修正|regression test"
    ["refactoring-specialist"]="refactor|関数分割|cleanup|dead code"
    ["code-reviewer"]="bash 品質|shellcheck|subshell"
    # 採用 6 条 4 規範化 = mapping 拡張時は本配列に追記
)
```

**任意 override** (advanced 用途、`harness-config.yml`):

```yaml
# 採用者が default mapping を上書き / 拡張したい場合のみ
agent_type_keyword_mapping:
  test-automator:
    - "smoke 拡張"
    - "test 追加"
    - "<採用者追加 keyword>"
  # 採用 6 条 4 ではなく Phase 設計で追記
```

未設定なら hook 内 hardcode が動作。設定不要原則 (4.5.0) 遵守。

#### 4.5.5 agent-router skill 連携 (補完オプション)

既存 skill `agent-router` (Anthropic 提供) を SessionStart で auto-trigger 可能なら、本 hook と組合せで深い解析対応:

- 本 hook: 即時 warning 注入 (PreToolUse、軽量 keyword 照合)
- agent-router skill: task description の semantic 解析 (LLM 経由、深い推論)

採用判断:
- Phase 1: 本 hook のみ実装 (軽量、確実)
- Phase 2 (future): agent-router skill auto-trigger 検討 (LLM cost 評価後)

## 5. リスク

- **false positive**: 真に sequential 依存があり 1 subagent が正解 case で warning 注入 → AI 判断負荷
  - 緩和策: warning text に「無視可、明示的理由ある場合は続行」明記、bypass env 周知
- **state file race**: 並列 Agent 起動時に state file 並列 write で race
  - 緩和策: atomic-mkdir lock (task-34 iter3 で確立 pattern 流用)
- **false negative**: 履歴 TTL 5 分超過で並列性検出失敗
  - 緩和策: TTL 値は env override 可能 (`HC_PARALLEL_SUBAGENT_TTL_SEC=300`)

## 6. 完了条件 (DoD)

- [ ] `.claude/rules/development-process.md` §並列化義務 + §agent type 選定義務 セクション追加 (grep `並列化義務` exit 0 + grep `agent type 選定` exit 0)
- [ ] `.claude/hooks/parallel-subagent-reminder.sh` 新設 (約 70 LOC + fail-open guard + atomic-mkdir lock + subshell 関数化 + agent type 照合 logic)
- [ ] `.claude/settings.json` PreToolUse(Agent) 配線
- [ ] `.claude/harness-config.yml` `parallel_subagent_reminder_enabled: true` + `parallel_subagent_ttl_sec: 300` キー追加 (`agent_type_keyword_mapping` は **設定不要原則** で hook 内 hardcode、yaml override は **任意 / advanced 用途**)
- [ ] `.claude/hooks/lib/config-loader.sh` で `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED` + `HC_PARALLEL_SUBAGENT_TTL_SEC` export (`HC_AGENT_TYPE_KEYWORD_MAPPING` は optional、未設定なら hook 内 default 使用)
- [ ] 新 smoke `.claude/tests/parallel-subagent-reminder-smoke.sh` **8 cases** PASS (Case 1-5 並列性 + Case 6-8 agent type 選定)
- [ ] 既存 smoke regression 0
- [ ] 5+ reviewer iter cycle で strict 0-finding 収束 (採用 6 条 4)

## 7. 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | 規範 1 file (development-process.md) + 新 hook + 新 smoke + settings.json + harness-config.yml + config-loader.sh = 6 file |
| migration | なし |
| 環境変数 | `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED` 新設 (default: true、bypass: false) / `HC_PARALLEL_SUBAGENT_TTL_SEC` 新設 (default: 300) |
| 互換性 | warning 注入のみ、既存挙動破壊なし |
| state dir | `.claude/.parallel-subagent-state/` 新設 (`.gitignore` で除外) |

## 8. Phase 計画 (採用 6 条 4 準拠、Task = Phase = N Step)

- Step 1+2+3 統合実装: 規範追記 + hook 新設 + 配線 (3 並列、独立 file 領域: 規範 md / hook sh / settings/yaml/loader) ← **本 draft の dogfooding**
- Step 4 (テスト合格): 新 smoke 5 cases + 既存 regression 0
- Step 5 (リファクタリング 3 観点): hook ~50 LOC で refactor 余地なし見込み (skip 想定)
- Step 3+4 reviewer: 5+ 動的選定で iter cycle (採用 6 条 4)

## 9. 承認履歴

- 2026-05-25: 起案 (user 要望「ハーネスで並列化を強制してください」)
- TBD: user 承認 (本 draft レビュー後)
- TBD: task #38 として起票 (`/new-task 38 parallel-subagent-enforcement`)
- TBD: 実装着手 (3 並列起動で本 draft の dogfooding)
