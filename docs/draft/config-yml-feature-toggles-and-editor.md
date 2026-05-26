<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# yml 設定値拡張 (reviewer 必須・体数 + 機能単位 on/off) + 対話的 config-editor sh

## §1 真因 (背景)

本 session で task-42 (CLAUDE.md slim 化) + task-43 (research-reuse 規範) を完遂し、ハーネス採用 4 リポへ portable 同期可能な状態が整った。しかし以下の構造問題が残る:

### 問題 1: reviewer 制御は hardcode

- `harness-config.yml` の `reviewer_registry_*` は **agent type 列挙のみ**、「必須かどうか」「最小起動数」「最大起動数」は hook 内 hardcode
- 採用 6 条 4「テスト設計レビュー → テスト合格 → リファクタリング」で reviewer 5+ 並列起動が default 規範、ただし採用先で「reviewer 不要」「3 体で十分」等の調整が必要な場面で yml 修正経路が不在
- 現状の bypass は `ECC_*_OFF=1` 等の env (全 OFF / no-op)、min_count や required boolean の細粒度制御不可

### 問題 2: 機能 on/off が hook 単位散在

- 各 hook ごとに `HC_<HOOK>_ENABLED=false` env が散在 (例: `HC_CONFIDENCE_REQUIRED` / `HC_RULE_CHANGE_GUARD_ENABLED` / `HC_LOOP_CONFIRMATION_DETECTION_ENABLED` / `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED` 等)
- 採用先で「Loop モード自律規律」「draft-flow 強制」「workflow 強制」等の **機能 (feature) 単位** で on/off したい場合、関連 hook を個別に env 指定する必要があり煩雑
- user 視点で「○○機能を OFF」と直感的に表現できる abstraction layer 不在

### 問題 3: yml 設定値の編集経路が手動のみ

- 採用 4 リポでの portable 運用時、`harness-config.yml` を直接編集して `git commit` 必要
- 値型 (bool / int / string / array / CSV) の validation なし
- key 一覧と現値の確認が `cat .claude/harness-config.yml` 等の生 file 参照のみ
- 「設定値を変更できる sh」を新設することで、対話的 menu / CLI args で安全に編集できる

### user 質問起源

「1. 各箇所 (設計 or テスト) でエージェントのレビューが必須かどうか何体で行うかも yml の設定値に加えて変更できるようにしてください。2. それぞれの機能の on/off できるようにしてください。Hook を利用するもの、hook 単位ではなく機能単位で。3. 全ての設定値を変更できる SH を作成してください。」(2026-05-27、user 直接指示)

## §2 採用案

| 案 | 内容 | 評価 |
|---|---|---|
| A | yml 拡張のみ (新 key 追加、code 側は default 値で動作) | 軽量、ただし script 側の対話的編集経路なし |
| B | yml 拡張 + 各 hook logic 修正 (reviewer 制御 / feature toggle 参照) | 機能完全だが工数大 |
| C | yml 拡張 + hook logic 修正 + 対話的 config-editor sh 新設 | user 要望 3 件を全充足、工数最大 |
| **D ハイブリッド (推奨)** | C を **3 Phase 段階実装** で進める (Phase 1 yml schema、Phase 2 hook logic、Phase 3 config-editor sh) | 段階リリースで context 節約 + 各 Phase で smoke 検証 |

→ **D ハイブリッド** 採用。

## §3 採用案 (実装仕様)

### 3.1 yml schema 拡張 (Phase 1)

#### 3.1.1 reviewer 制御 (新規 15 key: required 5 + min_count 5 + max_count 4 + iteration_max 1)

```yaml
# === Reviewer Required / Min Count / Iteration (採用 6 条 4 の制御) ===
# /design-review / /test-design / /module-review / /system-review command が消費。
# yml 値 default で動作、env override 可 (HC_REVIEW_*)。

# 設計レビュー (W2 /design-review)
review_required_design: true          # false なら /design-review が no-op skip
review_min_count_design: 3            # default 3、reviewer_registry_design 件数下限
review_max_count_design: 7            # default registry 全件、上限指定

# テスト設計レビュー (W1 /test-design、採用 6 条 4)
review_required_test: true            # false なら採用 6 条 4「テスト設計レビュー」step skip 可
review_min_count_test: 5              # default 5 (採用 6 条 4 で 5+ 動的選定)
review_max_count_test: 10             # default registry 全件、上限指定

# モジュールレビュー (W3 /module-review)
review_required_module: true          # false なら /module-review skip 可
review_min_count_module: 2            # default 2 (code-reviewer + refactoring-specialist)
review_max_count_module: 5            # default registry 全件、上限指定

# システムレビュー (W3 /system-review)
review_required_system: true          # false なら /system-review skip 可
review_min_count_system: 2            # default 2 (architect-reviewer + refactoring-specialist)
review_max_count_system: 5            # default registry 全件、上限指定

# security レビュー (W2 /design-review 内 security category)
review_required_security: false       # default false (security 影響 task のみ)
review_min_count_security: 1          # default 1 (security-reviewer)

# 反復制御
review_iteration_max: 5               # default 5 (採用 6 条 4 で 5 回上限)
```

#### 3.1.2 機能単位 on/off (新規 21 key)

```yaml
# === Feature Toggles (機能単位 on/off) ===
# 各 feature key は **上位 layer**、関連 hook の `HC_<HOOK>_ENABLED` は subordinate。
# feature 単位で OFF にすれば、hook level に関わらず全 hook 停止 (feature 内 hook 一括 OFF)。

feature_loop_mode_enforcement_enabled: true       # loop-confirmation-detector + loop-auto-progress-reminder + mode-enforce
feature_draft_flow_guard_enabled: true            # draft-flow-guard
feature_task_rule_guard_enabled: true             # task-rule-guard + list-md-plan-first-reminder
feature_delegation_guard_enabled: true            # delegation-guard
feature_workflow_enforcement_enabled: true        # workflow-guard
feature_confidence_gate_enabled: true             # confidence-gate (F3)
feature_gateguard_enabled: true                   # gateguard (F1)
feature_context_budget_enabled: true              # context-budget
feature_parallel_subagent_reminder_enabled: true  # parallel-subagent-reminder
feature_autonomous_action_guard_enabled: true     # autonomous-action-guard
feature_byproduct_discharge_enabled: true         # byproduct-discharge-guard + next-actions-surface
feature_why_x5_enforcement_enabled: true          # why-x5-reminder + why-x5-violation-detect
feature_session_help_surface_enabled: true        # session-help-surface
feature_improvement_proposal_enabled: true        # improvement-proposal
feature_mode_session_start_enabled: true          # mode-session-start
feature_check_serena_mcp_enabled: true            # check-serena-mcp
feature_check_required_env_enabled: true          # check-required-env
feature_init_tasks_on_start_enabled: true         # init-tasks-on-start
feature_notify_enabled: true                      # notify + stop (sound)
feature_check_md_mermaid_enabled: true            # check-md-mermaid
feature_failure_loop_detect_enabled: true         # failure-loop-detect
```

#### 3.1.3 yml schema 互換性

- 既存 key (`reviewer_registry_*` / `workflow_stages_*` / `*_state_dir` 等) は touch しない
- 新 key は default 値で動作 (採用先で既存 yml に新 key 不在でも、hook 内 fallback で default 値使用)
- env override は既存 `HC_*` パターン継承

### 3.2 hook 内 logic 修正 (Phase 2)

#### 3.2.1 reviewer 制御参照

対象 command:
- `.claude/commands/design-review.md` (W2)
- `.claude/commands/test-design.md` (W1)
- `.claude/commands/module-review.md` (W3)
- `.claude/commands/system-review.md` (W3)

各 command の prompt 冒頭に以下追加 (config-loader.sh で yml 値 export 済 env 参照):

- `HC_REVIEW_REQUIRED_<scope>` = false なら本 command を no-op skip (skip 理由を user に提示)
- `HC_REVIEW_MIN_COUNT_<scope>` = N なら reviewer N 件以上を並列起動 (registry から stack heuristic で絞り込み後、N 未満なら全件起動)
- `HC_REVIEW_MAX_COUNT_<scope>` = N なら reviewer N 件以下に絞る (priority 順: registry の先頭 N 件)
- `HC_REVIEW_ITERATION_MAX` = N で反復上限 (default 5)

#### 3.2.2 機能 on/off 参照 (各 hook 冒頭)

対象 hook (21 件): loop-confirmation-detector / loop-auto-progress-reminder / mode-enforce / draft-flow-guard / task-rule-guard / list-md-plan-first-reminder / delegation-guard / workflow-guard / confidence-gate / gateguard / context-budget / parallel-subagent-reminder / autonomous-action-guard / byproduct-discharge-guard / next-actions-surface / why-x5-reminder / why-x5-violation-detect / session-help-surface / improvement-proposal / mode-session-start / check-serena-mcp / check-required-env / init-tasks-on-start / notify / stop / check-md-mermaid / failure-loop-detect

各 hook 冒頭 (config-loader.sh source 直後) に以下追加:

```bash
# Feature toggle 参照 (Phase 2)
# config-loader.sh の is_feature_enabled 関数で env > yml > defaults priority を統一的に判定
# (大小文字無視 / 行末コメント strip / 引数欠如時 safe default ON 等の挙動を関数に集約)
if ! is_feature_enabled <name>; then
  exit 0   # feature OFF で no-op
fi
```

> ⚠️ 旧サンプル (`[[ "${HC_FEATURE_<NAME>_ENABLED:-true}" == "false" ]]`) は **大小文字無視 / 行末コメント strip / 0|off|no も同義扱い** が効かないため非推奨。task-44 iter 2 で `is_feature_enabled` 関数経由に統一 (MEDIUM-3 fix)。

既存 hook level env (`HC_<HOOK>_ENABLED`) は subordinate として保持 (Phase 2 で feature key を新 layer 追加、hook level は backward compat)。

#### 3.2.3 config-loader.sh 拡張

`.claude/hooks/lib/config-loader.sh` に新 key 34 件 (21 feature + 13 review) の load logic 追加 + `is_feature_enabled <name>` 共通関数追加。既存パーサ仕様 (フラット key: value) で対応可能。

### 3.3 対話的 config-editor sh (Phase 3)

新規 file: `.claude/scripts/hc-config.sh`

#### 3.3.1 機能仕様

- **対話的 menu** (default、引数なし起動):
  1. 全 key 一覧表示 (key | current value | default | type | description)
  2. key 選択 → 現値 + default 表示 → 新値入力 → 確認 → yml 保存 (backup `.bak` 作成)
  3. feature toggle 一括 on/off (上位 layer、関連 hook を集約表示)
  4. reviewer 設定 quick edit (`review_*_*` を 1 画面で編集)
  5. 終了 (smoke test 案内: `bash .claude/tests/<関連 smoke>.sh`)

- **CLI args** (script 自動化用):
  - `--list` : 全 key 一覧 (table form)
  - `--get <key>` : 単一 key 値取得
  - `--set <key>=<value>` : 単一 key 設定 (validation 後 yml 保存)
  - `--feature <name>=<true|false>` : feature toggle 1 行設定
  - `--reset <key>` : default 値に戻す
  - `--reset-all` : 全 key を default に戻す (confirmation 必須)
  - `--diff` : 現値と default の差分表示
  - `--validate` : yml 構文 + 値型検証 (smoke 前 check)
  - `--help` : usage

#### 3.3.2 値型 validation

- **bool**: `true|false` のみ (大小文字無視)
- **int**: 正整数 (`min_count` / `max_count` / `iteration_max` 等)
- **float**: `0.0〜1.0` (`confidence_threshold` / `context_budget_threshold`)
- **string**: 任意文字列
- **array**: `[a, b, c]` インライン形式 (既存パーサ仕様)
- **CSV**: `a,b,c` 形式 (`docs_approved_dir`)
- **path**: 相対 path or `~/` prefix (tilde 展開対応、`homunculus_root` 等)

各 key の型は script 内 metadata (associative array or here-doc table) で管理。

#### 3.3.3 yml 編集 atomic 操作

- 編集前に `.claude/harness-config.yml.bak.<timestamp>` でバックアップ
- 一時 file (`.claude/harness-config.yml.tmp`) に新内容 write
- 構文検証 (python yaml.safe_load 経由 or `awk` で軽量実装) PASS で `mv` 上書き
- FAIL なら `.tmp` 削除 + 旧 yml 維持 + error 表示

### 3.4 規範文書更新 (Phase 4)

- `.claude/rules/development-process.md` §「サブエージェント委譲」内に reviewer 制御の参照を追記
- `.claude/rules/workflow.md` §「設計レビューの fan-out」/ §「テスト設計の MECE 強制」/ §「リファクタリング強制」内に yml key 参照追記
- `.claude/CommonRules.md` Design Constraints に「機能 on/off は yml feature toggle で集中管理」追記
- `.claude/rules/task-management.md` 採用 6 条 4 (テスト設計レビュー) に yml key 参照追記
- `docs/SELF_IMPROVEMENT.md` に config-editor.sh の使用方法追記

### 3.5 採用 4 リポへの portable 同期 (Phase 5)

本 PR merge 後、`bash install.sh --update <target>` で以下が反映:

- `.claude/harness-config.yml` (新 key 追加分のみ、既存値は touch しない rsync 動作確認必要)
- `.claude/hooks/lib/config-loader.sh` (新 key 34 件の load logic + 共通関数)
- `.claude/hooks/*.sh` (21+ 件 hook の feature toggle check 追加)
- `.claude/scripts/hc-config.sh` (新規 script)
- `.claude/rules/*.md` (5 file 規範追記)
- `.claude/CommonRules.md` (Design Constraints 追記)

各 repo で動作確認:
- `bash .claude/scripts/hc-config.sh --list` で全 key + 現値表示
- `bash .claude/scripts/hc-config.sh --set feature_loop_mode_enforcement_enabled=false` で feature OFF 試行
- `bash .claude/scripts/hc-config.sh --get review_min_count_test` で値取得確認

## §4 TDD 戦略

### Phase 1 (yml schema 拡張) RED → GREEN

1. **RED**: 新 key を yml に追加した状態で各 hook が default 値で動作することを確認する smoke 新設 (`.claude/tests/config-feature-toggles-smoke.sh`)
   - Case 1: feature toggle ON で hook 通常動作
   - Case 2: feature toggle OFF で hook no-op exit 0
   - Case 3: 新 key 未設定で hook default 動作 (backward compat)
2. **GREEN**: yml に新 key 追加 + hook 内 feature check 実装 (Phase 2 と並行)
3. **REFACTOR**: hook 内 feature check pattern を共通関数化 (`config-loader.sh` の `is_feature_enabled <name>`)

### Phase 2 (hook logic) RED → GREEN

1. **RED**: reviewer 制御 smoke 新設 (`.claude/tests/review-required-min-count-smoke.sh`)
   - Case 1: `review_required_<scope>: false` で command skip
   - Case 2: `review_min_count_<scope>: N` で N 件以上 reviewer 起動
   - Case 3: `review_max_count_<scope>: N` で N 件以下に絞る
2. **GREEN**: 各 review command に yml 参照 logic 追加
3. **REFACTOR**: review command 共通 helper (`.claude/scripts/lib/review-helper.sh`) 抽出

### Phase 3 (config-editor sh) RED → GREEN

1. **RED**: config-editor 動作 smoke 新設 (`.claude/tests/hc-config-script-smoke.sh`)
   - Case 1: `--list` で全 key 一覧表示
   - Case 2: `--get <key>` で値取得
   - Case 3: `--set <key>=<value>` で yml 編集 + backup 作成
   - Case 4: 値型 validation (bool / int / float / array)
   - Case 5: 構文 invalid な値で error + rollback
   - Case 6: `--reset <key>` で default 復元
   - Case 7: 対話 menu (expect 等で自動化、または stdin redirect)
2. **GREEN**: script 実装
3. **REFACTOR**: 関数分割 (parse / validate / write / backup)

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 | 工数推定 |
|:---:|:---:|:---|:---|:---:|
| 1 | 🔲 | draft + task file + list.md row + user 承認 | 全 file 存在、`approved_at` 非空 | 0.5h |
| 2 | 🔲 | Phase 1: yml schema 拡張 (34 新 key 追加) | yml grep `feature_` ≥ 21 + `review_` ≥ 13 | 1h |
| 3 | 🔲 | Phase 1: config-loader.sh 拡張 (34 key load + `is_feature_enabled` 関数) | smoke Case 3 backward compat PASS | 2h |
| 4 | 🔲 | Phase 2: hook 21+ 件に feature check 追加 (staging 戦略、subagent 並列) | 各 hook 冒頭で feature OFF 時 exit 0 確認 | 3h (並列で 1h 短縮可) |
| 5 | 🔲 | Phase 2: review command 4 件に yml 参照追加 (design / test / module / system) | reviewer 制御 smoke 3 件 PASS | 2h |
| 6 | 🔲 | Phase 3: `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation) | hc-config-script-smoke 7 件 PASS | 4h |
| 7 | 🔲 | Phase 4: 規範文書更新 (development-process / workflow / CommonRules / task-management / SELF_IMPROVEMENT) | grep 検証 5 件 | 1h |
| 8 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列で iter 1+ (本 task は規範文書 + script + hook 大規模変更で reviewer 価値あり) | iter 5 回上限内で収束 | 2h |
| 9 | 🔲 | (テスト合格) 全 smoke 統合実行 + 既存 smoke regression 0 | 新 3 smoke + 既存 100+ smoke 全 PASS | 1h |
| 10 | 🔲 | (リファクタリング) feature check pattern / review helper 共通化 | 3 観点判定 (持続可能性 / 汎用性 / 非冗長化) PASS | 1h |
| 11 | 🔲 | commit + push + PR create | PR URL 提示 | 0.5h |
| 12 | 🔲 | 4 リポ user manual install 案内 (`bash install.sh --update`) | install command 提示 | 0.5h |

**総工数推定**: 18.5h (並列化で 14h 程度に短縮可能)。**本セッション内完遂は無理、複数セッション跨ぎ想定**。

## §6 DoD

- [ ] `docs/draft/config-yml-feature-toggles-and-editor.md` 存在 + `approved_at` 非空
- [ ] `.claude/harness-config.yml` に新 36 key 追加 (`grep -cE '^feature_[a-z0-9_]+_enabled:' .claude/harness-config.yml` ≥ 21 + `grep -cE '^review_[a-z0-9_]+:' .claude/harness-config.yml` ≥ 15、digit-inclusive で `feature_why_x5_enforcement_enabled` の `5` 計上)
- [ ] `.claude/hooks/lib/config-loader.sh` で 34 key load + `is_feature_enabled` 関数追加
- [ ] 21+ 件 hook に feature check 追加 (各 hook 冒頭、staging 戦略)
- [ ] 4 件 review command に yml 参照 logic 追加
- [ ] `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation)
- [ ] 3 件 smoke 新設 (config-feature-toggles / review-required-min-count / hc-config-script) 全 PASS
- [ ] 既存 100+ smoke regression 0
- [ ] reviewer iter 5 上限内で収束 (CRITICAL + HIGH + MEDIUM = 0)
- [ ] 規範文書 5 file 更新
- [ ] PR create + user merge 案内
- [ ] 4 リポ user manual install 案内

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (新規) | `docs/draft/config-yml-feature-toggles-and-editor.md` / `docs/tasks/task-44-config-yml-feature-toggles-and-editor.md` / `.claude/scripts/hc-config.sh` / `.claude/tests/config-feature-toggles-smoke.sh` / `.claude/tests/review-required-min-count-smoke.sh` / `.claude/tests/hc-config-script-smoke.sh` |
| ファイル (修正) | `.claude/harness-config.yml` (新 34 key) / `.claude/hooks/lib/config-loader.sh` (load logic + 共通関数) / `.claude/hooks/*.sh` (21+ 件 feature check) / `.claude/commands/*.md` (4 件 review command yml 参照) / `.claude/rules/*.md` (5 file 規範追記) / `.claude/CommonRules.md` (Design Constraints) / `docs/tasks/list.md` (task-44 row) |
| ファイル (test) | 3 件新規 + 既存 100+ smoke regression check |
| migration | なし (yml schema 拡張のみ、backward compat 維持) |
| 環境変数 | 34 件新規 (`HC_FEATURE_*_ENABLED` 21 + `HC_REVIEW_*_*` 13) |
| 互換性 | 採用 4 リポは `install.sh --update` で yml + hook + script + 規範 file 自動同期。既存 yml 値は touch しない (新 key は default 値で動作)。 |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (予定) | tdd-guide / test-automator / qa-expert / harness-optimizer / architect-reviewer + (security-reviewer for env injection、code-reviewer for shell script) | TBD | TBD | TBD | TBD | 未実施 |

reviewer 5+ 並列起動 default (採用 6 条 4)、本 task は規模大 + script + hook + 規範 大規模変更で reviewer 価値高い。skip 不可。

## §9 関連

- 起源: 2026-05-27 user 直接指示「reviewer 必須・体数 yml 化 + 機能単位 on/off + 全設定値変更 sh」
- 前提 task: task-42 (CLAUDE.md slim 化) + task-43 (research-reuse) + context7 MCP `.mcp.json` 追加
- 影響 task: task-29 / task-33-36 (採用 6 条) / task-38 (parallel-subagent) / task-40 (rule change guard) / task-41 (loop confirmation) — feature toggle 経由で集中制御化
- 関連 memory: `feedback_verify_path_before_implementation.md` (yml key 命名前に既存 key 全件 verify)

## §10 着手前 user 承認事項

本 draft 起案後、user に以下を確認してから着手:

1. **scope 確認**: 新 34 key (feature 21 + review 13) + script 1 件 + hook 21+ 件 + command 4 件 + 規範 5 file の大規模変更を本 task で進めるか? (segment 分割案: 別 task 化 = Phase 1/2/3 を 3 task に分けるか)
2. **工数承認**: 推定 14-18h、複数セッション跨ぎ承認
3. **feature 粒度承認**: §3.1.2 の 21 feature mapping が user 想定と一致するか (例: 「Loop モード」を 3 hook 集約で扱う、等)
4. **script 命名**: `.claude/scripts/hc-config.sh` で OK か、`.claude/scripts/config-editor.sh` か他名前か
5. **対話 menu vs CLI**: §3.3.1 の機能仕様で OK か、CLI args 中心 / 対話 menu 中心の bias 調整あるか
