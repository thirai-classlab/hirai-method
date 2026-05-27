<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# config-yml Phase 3: 対話的 config-editor hc-config.sh + 規範文書更新

> **master draft**: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md) §3.3 + §3.4 + §3.5
> **前提 task**: task-44 (Phase 1) + task-45 (Phase 2) 完了
> 本 draft は task-46 の Phase 3 spec として固定化、master draft からの抜粋 + Step 計画詳細を持つ。

## §1 真因

master draft §1 参照。本 task は **Phase 3 (hc-config.sh + 規範文書 5 file 更新)** のみを扱う。task-44/45 で yml + hook + review command 経路が整備された後、対話的 config-editor `.claude/scripts/hc-config.sh` を新設し、規範文書 5 file (development-process / workflow / CommonRules / task-management / SELF_IMPROVEMENT) を更新する。

## §2 採用案

master draft §2 「D ハイブリッド」採用。本 task は Phase 3 単独実装。

## §3 採用案 (実装仕様、master §3.3 + §3.4 + §3.5 抜粋)

### 3.1 hc-config.sh 新設 (master §3.3.1)

新規 file: `.claude/scripts/hc-config.sh`

機能:

- **対話 menu** (default、引数なし起動):
  1. 全 key 一覧表示 (key | current | default | type | description)
  2. key 選択 → 現値 + default 表示 → 新値入力 → 確認 → yml 保存 (backup `.bak.<ts>` 作成)
  3. feature toggle 一括 on/off (上位 layer、関連 hook を集約表示)
  4. reviewer 設定 quick edit (`review_*_*` を 1 画面で編集)
  5. 終了 (smoke test 案内)

- **CLI args** (script 自動化用):
  - `--list` / `--get <key>` / `--set <key>=<value>`
  - `--feature <name>=<true|false>` / `--reset <key>` / `--reset-all`
  - `--diff` / `--validate` / `--help`

### 3.1.1 5 共有 feature toggle と制御 hook の mapping

起源: task-45 reviewer iter 1 MEDIUM finding (5 共有 toggle mapping draft 不在、entry #52 (2))。`hc-config.sh --feature <name>=<value>` の対象となる **5 共有 feature toggle** が hook 群とどう紐付くかを設計文書として明文化する。task-44 で 23 件全 feature toggle を `harness-config.yml` 定義済 (line 318-339)、task-45 Phase 2 で各 hook 冒頭に `is_feature_enabled` 配線完了済。

#### mapping table

| toggle name | default | yml line | 制御対象 hook | 制御 logic |
|---|---|---|---|---|
| `loop_mode_enforcement` | true | 318 | `loop-confirmation-detector.sh` (Stop) / `loop-auto-progress-reminder.sh` (UserPromptSubmit) / `mode-enforce.sh` (UserPromptSubmit) | Loop モード稼働中の自律進行強制 + 確認質問抑制 + 待ち中独立作業義務 reminder を **group 単位で OFF** 可。静かな調査セッション等で Loop 規律を一時的に外す用途 |
| `task_rule_guard` | true | 320 | `task-rule-guard.sh` (PreToolUse Edit/Write) / `list-md-plan-first-reminder.sh` (SessionStart) | タスク管理規範強制 (draft 不在で task 新規作成 BLOCK + 同 ID 重複 BLOCK) + batch planning plan-first reminder を **group 単位で OFF** 可。hot fix で list.md を bypass したい場合の用途 |
| `byproduct_discharge` | true | 328 | `byproduct-discharge-guard.sh` (Stop) / `next-actions-surface.sh` (SessionStart) | 副産物 registry surface (毎セッション開始時 stderr 提示) + Stop hook BLOCK (🔴 未処理 entry 残存で session 終了 block) を **group 単位で OFF** 可。次 session で対応予定の 🔴 entry を一時的に通過させる用途 |
| `notify` | true | 336 | `stop.sh` (Stop、afplay 通知音 + osascript notification) / `notify.sh` (Notification、macOS 通知バナー) | macOS 通知音 + 通知バナー (Stop / Notification hook の両 trigger 経路) を **group 単位で OFF** 可。静音セッション (会議中 / 夜間作業) の用途 |
| `why_x5_enforcement` | true | 329 | `why-x5-reminder.sh` (UserPromptSubmit) / `why-x5-violation-detect.sh` (PostToolUse) | Why × 5 出力規範の毎 turn reminder 注入 + 違反検出 PostToolUse 注入を **group 単位で OFF** 可。雑談セッション / 短い確認応答のみの session で 1 行 format 義務を外す用途 (`why-x5-output.md` §「一時無効化」と整合) |

#### 制御 logic 統一仕様

各 toggle は `feature_<name>_enabled` (default `true`) として `harness-config.yml` line 318-339 に定義済 (task-44 Phase 1)。各 hook 冒頭で `is_feature_enabled <name>` (`config-loader.sh` L498-525 共通関数) が `true` を返さない場合に **no-op で exit 0** する (task-45 Phase 2 で 27 件 hook 配線済)。本 Phase 3 で新設する `hc-config.sh --feature <name>=<value>` は yml の該当 key を atomic + backup 付きで書き換えるため、安全に on/off 切替可能。

#### 5 共有 toggle の存在意義 (group 単位制御)

23 件全 toggle のうち上記 5 件のみを「共有 toggle」と位置付ける理由は **2 件以上の hook を group として制御するため**:

- 同一 group 内 hook を **個別 enable/disable** すると hook 間の不整合が起きやすい (例: Loop モードで auto-progress reminder のみ ON + confirmation-detector OFF → 確認質問が漏れて自律進行のみ強制される片肺状態、規範意図と乖離)
- group 単位の集約 toggle で「**機能群として ON/OFF**」する設計により、規範意図 (Loop 規律 / タスク管理規範 / 副産物管理 / 通知 / Why × 5 出力) を整合的に on/off 可能
- 残り 18 件 toggle は単一 hook 制御 (`task_rule_guard` 以外の hook 群)、本 mapping table の対象外 (個別制御で十分)

#### `hc-config.sh --feature` での操作例

```bash
# Loop 規律を group 単位で OFF (3 hook 同時無効化)
bash .claude/scripts/hc-config.sh --feature loop_mode_enforcement=false

# 通知音 + バナーを group 単位で OFF (2 hook 同時無効化、静音セッション)
bash .claude/scripts/hc-config.sh --feature notify=false

# Why × 5 出力規範を group 単位で OFF (2 hook 同時無効化、雑談セッション)
bash .claude/scripts/hc-config.sh --feature why_x5_enforcement=false

# 全 group を default (true) へ復元
bash .claude/scripts/hc-config.sh --reset-all
```

### 3.2 値型 validation (master §3.3.2)

- **bool**: `true|false` (大小無視)
- **int**: 正整数 (`min_count` / `max_count` / `iteration_max`)
- **float**: `0.0〜1.0` (`confidence_threshold` / `context_budget_threshold`)
- **string** / **array** / **CSV** / **path** (tilde 展開)

各 key の型は script 内 metadata で管理 (associative array or here-doc table)。

### 3.3 atomic yml 操作 (master §3.3.3)

- `harness-config.yml.bak.<timestamp>` でバックアップ
- 一時 file (`.tmp`) に write → 構文検証 (python yaml.safe_load) → `mv` 上書き
- FAIL で `.tmp` 削除 + 旧 yml 維持 + error 表示

### 3.4 規範文書 5 file 更新 (master §3.4)

- `.claude/rules/development-process.md` §「サブエージェント委譲」内に reviewer 制御 yml 参照追記
- `.claude/rules/workflow.md` §「設計レビュー fan-out」/ §「テスト設計 MECE」/ §「リファクタリング強制」内に yml key 参照追記
- `.claude/CommonRules.md` Design Constraints に「機能 on/off は yml feature toggle で集中管理」追記
- `.claude/rules/task-management.md` 採用 6 条 4 (テスト設計レビュー) に yml key 参照追記
- `docs/SELF_IMPROVEMENT.md` に config-editor.sh 使用方法追記

draft-flow-guard.sh が `.claude/rules/*.md` 等への直接 Write を BLOCK するので、本 task で **本 draft (`config-yml-phase3-hc-config-script.md`) を retroactive: false ∧ approved_at: 2026-05-27 非空** にすることで rule 変更 5 件を許可。

### 3.5 採用 4 リポ portable 同期 (master §3.5)

PR merge 後、`bash install.sh --update <target>` で全 file 同期。動作確認:
- `bash .claude/scripts/hc-config.sh --list` で全 key + 現値表示
- `bash .claude/scripts/hc-config.sh --set feature_loop_mode_enforcement_enabled=false` で feature OFF 試行
- `bash .claude/scripts/hc-config.sh --get review_min_count_test` で値取得確認

## §4 TDD 戦略

新 smoke `.claude/tests/hc-config-script-smoke.sh`:

- Case 1: `--list` で全 key 一覧表示 (34+ key 確認)
- Case 2: `--get <key>` で値取得 (default 値 + env override 両方)
- Case 3: `--set <key>=<value>` で yml 編集 + backup 作成 (file 存在確認)
- Case 4: 値型 validation (bool / int / float / array、不正値で error)
- Case 5: 構文 invalid な値で error + rollback (yml unchanged)
- Case 6: `--reset <key>` で default 復元
- Case 7: 対話 menu (expect 自動化 or stdin redirect、最小 case)

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | `hc-config.sh` 実装 (対話 menu + CLI args + 値型 validation + atomic 操作、staging 戦略) | `bash .claude/scripts/hc-config.sh --help` 実行成功 |
| 2 | 🔲 | smoke `hc-config-script-smoke.sh` 新設 (7 cases) | 7/7 PASS |
| 3 | 🔲 | 規範文書 5 file 更新 (development-process / workflow / CommonRules / task-management / SELF_IMPROVEMENT) | grep 検証 5 件 PASS (各 file で yml 参照 keyword 確認) |
| 4 | 🔲 | (テスト設計レビュー) reviewer 5+ 並列 iter 1+ (script + 規範文書の両軸、reviewer 価値高い) | iter 5 回上限内収束 (CRITICAL+HIGH+MEDIUM=0) |
| 5 | 🔲 | (テスト合格) 全 smoke 統合実行 + 既存 smoke regression 0 | 新 7 case + 既存 smoke 全 PASS |
| 6 | 🔲 | (リファクタリング) script 関数分割 (parse / validate / write / backup)、3 観点判定 | skip 明示 or 実施 |

## §6 DoD

- [ ] `.claude/scripts/hc-config.sh` 新設 (対話 menu + CLI args + 値型 validation + atomic)
- [ ] smoke `hc-config-script-smoke.sh` 7 cases PASS
- [ ] 規範文書 5 file 更新 (grep 検証 5 件 PASS)
- [ ] 既存 100+ smoke regression 0
- [ ] reviewer iter 5 上限内収束
- [ ] commit + push + PR create (feature branch `feat/config-yml-phase3-hc-config-script`)
- [ ] 4 リポ install 案内 (user manual)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/draft/config-yml-phase3-hc-config-script.md` / `docs/tasks/task-46-config-yml-phase3-hc-config-script.md` / `.claude/scripts/hc-config.sh` / `.claude/tests/hc-config-script-smoke.sh` |
| 修正 file | `.claude/rules/development-process.md` / `.claude/rules/workflow.md` / `.claude/CommonRules.md` / `.claude/rules/task-management.md` / `docs/SELF_IMPROVEMENT.md` |
| 環境変数 | task-44 で定義済 34 件参照、本 task で新規追加なし |
| 互換性 | 既存 yml + hook + command 不変、hc-config.sh は新規追加のみ |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (予定) | tdd-guide / test-automator / qa-expert / code-reviewer + security-reviewer (env injection) + harness-optimizer | TBD | TBD | TBD | TBD | 未実施 |

reviewer 6 並列 default、script + 規範文書の両軸 + security (env injection 防止) で reviewer 価値高い (skip 不可)。

## §9 関連

- master draft: [`config-yml-feature-toggles-and-editor.md`](./config-yml-feature-toggles-and-editor.md)
- 前提 task: task-44 (Phase 1) + task-45 (Phase 2)
- 起源: user 直接指示 2026-05-27

## §10 着手前 user 承認

✅ user 承認済 (master draft §10 5 件、AskUserQuestion 2026-05-27)
