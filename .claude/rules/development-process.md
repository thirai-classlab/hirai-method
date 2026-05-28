---
paths:
  - "src/**/*"
  - "scripts/**/*"
  - "tests/**/*"
  - "docs/tasks/**/*"
  - "docs/draft/**/*"
  - "doc/**/*"
  - "force-app/**/*"
  - "**/*.js"
  - "**/*.php"
  - "**/*.jsx"
  - "**/*.html"
  - "**/*.css"
---

# 開発プロセスルール

本 rule は TDD・サブエージェント委譲・Bash 制御・並列化・staging 戦略・Confidence Gate・harness 取込の SSoT を集約する。`src/` `tests/` `scripts/` `docs/tasks/` `docs/draft/` 編集時に自動 Read される。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: [development-process.details.md](../rules-details/development-process.details.md)

## コーディング指針 / 出力 / 研究 (必読)

| 規範 | SSoT |
|---|---|
| LLM コーディング行動規約 (Think Before Coding / Simplicity / Surgical / Verifiable) | [`.claude/skills/karpathy-guidelines/SKILL.md`](../skills/karpathy-guidelines/SKILL.md) |
| Why × 5 階層 / 現作業 / 他選択肢の 3 点を毎ステップ明示 | [`why-x5-output.md`](./why-x5-output.md)、`why-x5-reminder.sh` 強制 |
| 外部 library 仕様確認は context7 MCP → WebFetch → GitHub/Exa の fallback chain | training data outdated 回避、推測実装禁止 |

context7 fail で loop 停止しない / 「training data で確信あり」で skip しない (verify before recommending 原則)。

> **適用対象 task 完全 list / `.mcp.json` 設定詳細**: [details §研究と再利用-詳細](../rules-details/development-process.details.md#研究と再利用-詳細)

## TDD (テスト駆動開発)

すべての実装は TDD で進める:

1. テスト専門 agent (`Agent(tdd-guide)` / `test-automator` / `qa-expert`) でテスト観点洗い出し
2. テスト設計・実装 (Red: 失敗状態)
3. プロダクションコード実装 (Green)
4. リファクタリング (Refactor)

テストなしでプロダクションコードを書かない。

## サブエージェント委譲 (Hook で強制)

メインは `src/` `tests/` `scripts/` への **一切の直接操作を禁止**。読み取り (Read/Grep/Glob)・編集 (Edit/Write) 両方が Hook ブロック。

### メインの役割

- タスク管理 (専任、[`task-management.md`](./task-management.md) §「メインエージェント専任」)
- 作業のアサイン (Agent tool 経由)
- 完了報告・成果物の確認
- docs/, CLAUDE.md, .claude/ の更新

### メイン直接使用可

- `Skill` / `mcp__*` 全対象
- docs/, CLAUDE.md, .claude/ の Read/Edit/Write

### Agent tool 経由委譲

- コード調査 → `Agent(Explore)`
- テスト設計 → `Agent(tdd-guide)` / `test-automator` / `qa-expert` (MECE 観点は `/test-design <slug>`)
- コード実装 → `Agent(general-purpose)` or `Agent(isolation=worktree)`
- ビルド確認 → 言語別 `/go-build` / `/rust-build` 等 or `/verify`
- 独立タスクは並列複数起動

### Hook で強制ブロック (メイン直接禁止)

- `Edit` / `Write` / `Read` / `Grep` / `Glob` — src/ tests/ scripts/ 対象
- `WebSearch` / `WebFetch` — 全対象
- `Bash` — **原則禁止**、`.claude/bash-whitelist.txt` 登録 prefix のみ許可

### Bash 制御 SSoT

- `.claude/bash-whitelist.txt` が SSoT、`settings.json` の `permissions.allow` に `Bash(...)` を **重複追加しない**
- Bash 追加は whitelist 1 行追記のみで完結
- 追加申請: `.claude/bash-whitelist-requests/YYYY-MM-DD-<slug>.md` 作成 → user レビュー
- `permissions.deny` での禁止 (`rm -rf`, `git push --force` 等) は別系統

### Hook バイパス禁止

`CLAUDE_HARNESS_ROLE=` 等 inline env による Hook バイパスは `delegation-guard.sh` がブロック。

### Reviewer 制御 SSoT (`harness-config.yml`)

| key | 用途 |
|---|---|
| `review_required_<design\|test\|module\|system\|security>` | 各レビュー要否 |
| `review_min_count_<design\|test\|module\|system\|security>` | 並列起動 reviewer 数下限 |
| `review_max_count_<design\|test\|module\|system>` | 並列起動上限 (cost 制御) |
| `review_iteration_max` | 反復上限 (default 5) |

操作: `bash .claude/scripts/hc-config.sh --get <key>` / `--set <key>=<value>` (atomic backup + type validation)。詳細は [`workflow.md`](./workflow.md) + [`task-management.md`](./task-management.md) 採用 6 条 4 + `docs/SELF_IMPROVEMENT.md` 参照。

## サブエージェント委譲の必須要件 7 件

| # | 要件 | 概要 |
|---|---|---|
| 1 | **background 起動強制** | `run_in_background: true` 必須。例外: 30 秒以内 smoke のみ。完了通知は SubagentStop hook 経由 |
| 2 | **順序整合性保証** | 依存解決 / 並行可能性判定 / partial commit 整合性をメインが事前判定 |
| 3 | **orchestration 義務** | Agent 起動は委譲ガード経由のみ、独立=並列 / 依存=逐次を事前計画 → user に開示 |
| 4 | **TaskCreate 登録** | Agent 起動前後で必ず TaskCreate (`subject` / `description` / `metadata.subagent_id` / status 遷移) |
| 5 | **Bash deny 時の委譲反射** | deny / whitelist 不在 / block を **loop 停止理由にしない**、直ちに Agent 委譲で再試行 |
| 6 | **並列化義務** | 独立 sub-task 2 件以上は並列起動 default、1 統合は明示理由 (race / 共有 file / context budget / sequential) 必要 |
| 7 | **agent type 選定義務** | task description に応じた specialist agent_type を default (test→`test-automator` / refactor→`refactoring-specialist` 等)、`general-purpose` は不在時のみ |

### 機械強制 (要件 6 + 7)

`.claude/hooks/parallel-subagent-reminder.sh` (PreToolUse(Agent)) が soft warning:

- 同 turn 内で過去 N 分 (default 5 分) に他 Agent 履歴なし ∧ 並列化対象 keyword 検出 → `<system-reminder>` 注入 (BLOCK しない)
- 並列化対象 keyword: "実装" "fix" "refactor" "設計" "新設" "拡張" "改修"
- 除外 keyword: "reviewer" "review" "監査" "audit" (採用 6 条 4 で別途並列強制)
- agent type 照合: `tool_input.subagent_type == "general-purpose"` ∧ 専門 type 適合 keyword 検出 → 推奨 warning 注入

state: `.claude/.parallel-subagent-state/recent.json` (TTL 5 分、atomic-mkdir lock)。

### bypass

| 経路 | env |
|---|---|
| reminder 無効化 | `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false` |
| TTL 変更 | `HC_PARALLEL_SUBAGENT_TTL_SEC=<秒>` |
| state dir 隔離 | `HC_PARALLEL_SUBAGENT_STATE_DIR=<path>` |
| agent type mapping override | `HC_AGENT_TYPE_KEYWORD_MAPPING=...` (改行区切り、advanced) |

### default mapping (要件 7、hook 内 SSoT、設定不要原則)

| keyword | 推奨 subagent_type |
|---|---|
| "smoke 拡張" / "test 追加" / "regression test" | `test-automator` |
| "refactor" / "関数分割" / "cleanup" | `refactoring-specialist` (or `refactor-cleaner`) |
| "build error" / "compile error" / "type error" | 言語別 `*-build-resolver` |
| "bash 品質" / "shellcheck" / "subshell" | `code-reviewer` |
| "設計レビュー" / "architecture review" | `architect-reviewer` |
| "セキュリティレビュー" / "OWASP" | `security-reviewer` (or `security-auditor`) |
| (specialized 不在) | `general-purpose` |

`harness-config.yml` 編集不要 (hook 内 hardcode 自動判定)、override は任意 (env `HC_AGENT_TYPE_KEYWORD_MAPPING`)。

> **要件 1-7 各論詳細 / 違反例 / heredoc 保護仕様 / 機械強制判定境界**: [details §委譲必須要件-詳細](../rules-details/development-process.details.md#委譲必須要件-詳細)
>
> **並列化義務 / agent type 選定の起源 (task-35 / task-34 実例)**: [details §並列化義務-起源](../rules-details/development-process.details.md#並列化義務-起源)

## サブエージェント `.claude/` 編集の staging 戦略 (必須)

Claude Code permission system は subagent context での `.claude/` 配下への直接 `Write` / `Edit` / `Bash` heredoc redirect を **一律 denied** (sub-agent isolation)。メインからは通過、subagent 委譲時は **staging 戦略** 必須。

### 強制プロンプト雛型 (Agent tool prompt に必ず明示)

> 本 task は `.claude/<sub>/foo.sh` 等への新規作成 / 編集を含む。Claude Code permission system が subagent context での `.claude/` 直接 Write を deny するため、以下の staging 戦略を使え:
>
> 1. `/tmp/foo.sh` に `Write` で内容を書く
> 2. `mv /tmp/foo.sh .claude/<sub>/foo.sh` で install
> 3. 実行 file の場合 `chmod +x .claude/<sub>/foo.sh`
>
> Edit の場合: 既存 file を Read → 編集して `/tmp/foo.sh` に `Write` → `mv` で上書き install

### 検出パターン (subagent 失敗時の即時切替)

- `Write` tool で `file_path` が `.claude/` 配下 → permission denied
- `Edit` tool で `file_path` が `.claude/` 配下 → permission denied
- `Bash` で `cat > .claude/...` / `tee .claude/...` heredoc redirect → block

### 例外

- **メインからの `.claude/` Write/Edit は通過** (`delegation-guard.sh` がメイン許可)
- `worktree` isolation でも同 policy (foreground / background / worktree いずれも denied)

> **起源 (task #12 dual-mode-portability) / 規範化経緯 / 再発検出時の昇格判定 (案 B / 案 C)**: [details §staging-戦略-起源](../rules-details/development-process.details.md#staging-戦略-起源)

## cross-repo write 例外 (agent 経路 deny / user manual 専用)

本 repo から外部 repo (例: `taskManageSystem` / `recall_poc` / `classlab-weekly-news`) への **cross-repo write** (Write / cp / mv / heredoc redirect) は agent context (main / subagent / `worktree` 含む全経路) で **完全 denied**。`bash install.sh --update <target>` は **user manual (terminal) 実行のみ可能**。

### Why (二重制約)

| layer | 制約 |
|---|---|
| **system-level** | Claude Code **sandbox** が cross-repo Write / cp / mv / heredoc redirect を一律 deny (`dangerouslyDisableSandbox: true` 付き Bash も block) |
| **harness-level** | 本 repo の `delegation-guard.sh` が main からの `.claude/hooks/*.sh` 等 code 配下 Write を block |

- subagent foreground / background / `worktree` 全経路で回避不可
- `ECC_*_OVERRIDE` / `HC_*_ENABLED=false` 等 bypass env は **system-level には効かない** (harness-level のみ無効化可能)

### How to apply

- 3 リポ反映系 task は `bash install.sh --update <target>` を **user に手動依頼** が default
- task draft / task file の Phase 計画段で「Phase N (cross-repo): user manual `bash install.sh --update <target>` 案内」と最初から明記
- 副産物 entry 起票時も「(c) user manual 経路で対応」を推奨処理に明記
- 「sandbox deny で進められない」を loop 停止理由にしない

### 例外

- **単一 repo 内 (hirai-method 内 `.claude/hooks/` 編集) は staging 戦略で subagent から可能** (§「staging 戦略」)
- cross-repo Write のみが完全 deny

> **起源 (task-24 W1 実証 confidence 0.85) / 緩和 (task-42 4 リポ全件 agent 直接成功実証) / 将来追随窓口**: [details §cross-repo-write-起源](../rules-details/development-process.details.md#cross-repo-write-起源)

## サブエージェント完了サマリ (Confidence Gate / F3 必須)

subagent の **最後の assistant text** に **必ず `confidence: 0.X`** (0.0〜1.0) を含める。`confidence-gate.sh` (SubagentStop hook) が抽出し閾値 (既定 0.6) 未満は **block**。

### 算出基準 (4 段階)

| レンジ | 状態 |
|---|---|
| 0.9 - 1.0 | 全条件を実測値で確認 (build / test / grep 生 log 引用可) |
| 0.7 - 0.8 | 主要条件確認、周辺は推定 (一部 grep 未実行など) |
| 0.5 - 0.6 | 実装完了だが検証浅い、未確認前提に依存 |
| 0.0 - 0.4 | 方針不明確、曖昧な仮実装 |

### 完了宣言の最低ライン

- **0.6 以上**: そのまま `/finish-task` へ進める
- **0.6 未満**: ゲートが block。検証追加 or 未解決事項を箇条書きで明示し user 判断
- **未記載**: `confidence_required: true` (既定) 下で block

### Bypass

| 方法 | スコープ | 痕跡 |
|---|---|---|
| `ECC_CONFIDENCE_GATE=off` | セッション全体 | env のみ |
| `HC_CONFIDENCE_REQUIRED=false` | セッション全体 | env のみ |
| `/gate-bypass confidence <reason>` | 次回 1 回のみ | `.claude/.confidence-gate-state/bypass.log` |

詳細: [`docs/CONFIDENCE-GATE.md`](../../docs/CONFIDENCE-GATE.md)。bypass 根拠は CLAUDE.md / docs/tasks/ に記録 (honor system)。

> **major subagent only block 仕様 (task #9) / 記載例 full**: [details §confidence-gate-詳細](../rules-details/development-process.details.md#confidence-gate-詳細)

## 指摘対応

指摘やエラーを受けた場合は必ず:

1. 根本原因を特定する
2. 修正する
3. 再発防止策を考える
4. `.claude/rules/` へのルール追加を提案する

## タスク管理 (メイン専任)

詳細は [`task-management.md`](./task-management.md) §「メインエージェント専任（必須）」を参照。

## harness 取込チェックリスト (proactive sync、consuming repo 必須)

consuming repo は **proactive に harness 最新版を取り込む** 義務を持つ。F (`stale-harness-detect.sh`、task-56) は SessionStart で **事後 WARN** を出すが、本 checklist で取込タイミング / 手順 / 検証を規範化する。

### 取込タイミング (4 経路、いずれかが trigger)

| # | trigger | 必須/推奨 |
|---|---|---|
| 1 | **stg* / main merge の直前** | **必須** (feature branch merge で WARN 状態のまま本番反映を防ぐ) |
| 2 | **定期 sync** (週次、曜日固定推奨) | 推奨 |
| 3 | **F WARN 検出時** (reactive 補完) | **必須** (`stale-harness-detect.sh` WARN → `bash install.sh --update <repo>` 即実行) |
| 4 | **重大 fix 通知時** (hirai-method release notes / commit log 監視) | 任意 |

### 取込手順 5 step

1. **hirai-method 最新化**: `git checkout main && git pull origin main`
2. **`bash install.sh --update <consuming repo absolute path>` を terminal で実行** — cross-repo write は agent 経路 deny のため **user manual のみ**
3. **差分確認**: consuming repo で `git status` / `git diff`
4. **分離 commit** (task-58 G1): `chore: sync .claude/ from hirai-method <YYYY-MM-DD>` 形式、`install.sh --update --commit` flag で自動 commit 可
5. **smoke 再実行**: consuming repo 側の smoke / test 再実行

### 取込後検証

- [ ] `.claude/CommonRules.md` の harness_version が最新 stamp
- [ ] consuming repo SessionStart で stale-harness-detect WARN 消去
- [ ] 既存 smoke / test 全 PASS

### bypass

| 経路 | env | スコープ |
|---|---|---|
| 意図的旧 harness 稼働継続 | `harness-config.yml` の `feature_stale_harness_detect_enabled: false` | 永続 |
| 一時抑制 | `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false` | 1 セッション |

bypass 根拠は consuming repo の `CLAUDE.md` に記録 (honor system)。

> **CI 自動化 (将来 opt-in 案 B) / 前提 task 連携詳細 / F WARN 案内文の grep 検証経緯**: [details §harness-取込-詳細](../rules-details/development-process.details.md#harness-取込-詳細)

---

## 副産物発生時の即時 draft 起こし義務 (必須・再発防止)

タスク実装中・レビュー中に「これは別 task として管理すべき」と判断した副産物 (byproduct) は **memory / 会話履歴に流すだけでは禁止**。必ず以下フロー:

1. **即時記録**: `docs/tasks/next-actions.md` に entry 追加 (緊急度 / 推奨処理を明記)
2. **当セッション内に draft 起こし**: 緊急度 🔴 / 🟡 entry は当セッション中に `/new-draft <slug>` で draft 起こし
3. **次セッション or 同セッション内に承認 + tasking**: user 承認後に `/new-task <id> <slug>` で list.md 行追加
4. **next-actions.md の処理結果列に移行先記入** (例: 「→ `docs/draft/<slug>.md` → task #N」)

### 違反パターン (絶対禁止)

- 副産物を memory にのみ保存して draft 化しない
- 「次セッションで対応」とコメントだけ残してセッション終了
- 発生源 task の `/finish-task` 完了前に処理せず後送り

### 強制機構 (実装予定)

- `next-actions-surface.sh` (SessionStart): 未処理 entry を毎セッション開始時に `<system-reminder>` で stderr 出力
- `workflow-guard.sh` (PreToolUse Bash `/finish-task`): next-actions.md 関連 entry 未処理なら BLOCK
- `_TASK_TEMPLATE.md` の「派生 task / 次アクション候補」セクション: `/finish-task` で空 or 全件転記済を検証

詳細は [`workflow.md`](./workflow.md) + [`docs/draft/byproduct-discharge-mechanism.md`](../../docs/draft/byproduct-discharge-mechanism.md) 参照。

## 設計→承認→タスク追加フロー

詳細は [`task-management.md`](./task-management.md) §「設計→承認→タスク追加フロー（必須）」を参照。

## Parking Lot (保留タスク)

詳細は [`task-management.md`](./task-management.md) §「Parking Lot（今後検討タスク）」を参照。
