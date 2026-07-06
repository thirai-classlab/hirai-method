# 平井メソッド (hirai-method)

> **Defense-first Claude Code harness** — 委譲強制 / 事実検証ゲート / 100% 観測 / 5 + 3 層自己改善 / Workflow 強制 / 副産物 discharge / Session 永続化

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![agents](https://img.shields.io/badge/active%20agents-100-blue)
![skills](https://img.shields.io/badge/skills-43-blue)
![dispatch rate](https://img.shields.io/badge/router%20dispatch-84.1%25-green)

---

## TL;DR (3 軸先出し)

| 軸 | 内容 |
|---|---|
| **🎯 なんのため** | AI エージェントの fabrication (捏造) / scope creep (範囲逸脱) / silent failure (隠れた失敗) を **hook によるコード強制レベル** で抑止し、Claude Code を「設計通り動かす」ためのハーネス |
| **⚡ 何ができる** | (1) 委譲ガード + 事実検証ゲート (F1-F3) (2) 5 層自己改善 (L1-L5) (3) Workflow 強制 (W1-W4) (4) 副産物 discharge registry (5) Session 永続化 + PM Orchestration (6) 100 active agents + 43 skills + agent-router |
| **🚀 どう使う** | `bash install.sh /path/to/project` → `bash .claude/scripts/hc-config.sh` で設定 → Claude Code 起動 → `/init-tasks` → `/mode loop` → `/new-draft` → `/new-task` → 自律実装 (詳細フロー: [§3.9.2](#392-インストール--設定--利用の全体フロー)) |

---

## 1. なんのためにあるか (Why)

### 1.1 解決する課題

通常の Claude Code 利用で頻発する問題:

| 問題 | 症状 | 平井メソッドの対策 |
|---|---|---|
| 委譲スキップ | メインが本来 subagent 委譲すべき作業を直接実行、責務逸脱 | `delegation-guard.sh` で `src/` `tests/` `scripts/` への直接 Edit/Write/Bash を block |
| 投機的編集 | 事実確認なしに大規模変更を加え後戻り不能 | `gateguard.sh` (F1) で初回 Edit/Write 前に importers / callers / data 構造 / user 逐語引用の 4 事実を要求 |
| 完了報告の乖離 | subagent が「完了しました」と虚偽報告、実態は test fail | `confidence-gate.sh` (F3) で `confidence: 0.X` (0.0-1.0) を強制、閾値 0.6 未満で block |
| 設計なき着手 | draft なしで実装着手、scope creep / 仕様変更が随所で起きる | `task-rule-guard.sh` (F2) で `docs/draft/<slug>.md` 承認なしの `docs/tasks/` Write を block |
| 破壊的操作の暴発 | `git push --force` / `reset --hard` / main push 等の事故 | `delegation-guard.sh` 内 git destructive deny + protected branch push deny + `autonomous-action-guard.sh` (Loop モード自律実行禁止 11 カテゴリ) |
| 副産物の蒸発 | 「あとで対応」の付箋が memory / 会話に流れて消失 | `next-actions.md` registry + SessionStart hook で未処理 entry を毎セッション surface |
| Session 状態の喪失 | context 上限到達で会話が分断、復元手段なし | `/save-state` / `/resume-state` で Serena MCP memory に snapshot 永続化 |

### 1.2 設計思想 (defense-first)

- **「ルールに書いて守らせる」ではなく「hook で BLOCK して守らせる」**: 違反検出 → 副産物 entry → draft 起こし → 機械強制 hook 実装の閉ループ
- **可観測性 = 信頼性**: 100% tool call 観測 (`observe.sh` で全 PostToolUse JSONL 記録) + `/harness-audit` で集計可能
- **bypass は痕跡を残す**: `ECC_*_OVERRIDE` 等 bypass env は `.claude/.workflow-state/bypass.log` に append、`/harness-audit` で集計
- **`.claude/` 単独で portable**: 別 repo に `cp -r .claude` で即動作、project 固有値は `harness-config.yml` env override で吸収

---

## 2. 何ができるか (What)

### 2.1 強制機構 (5 + 3 層)

| 層 | 名前 | 改善対象 | 発火 event | 永続化先 |
|---|---|---|---|---|
| **F1** | GateGuard | Edit/Write/Bash の事実性 | PreToolUse | `.claude/.gateguard-state/` |
| **F2** | TaskRule + Verification | タスク規律 + PR 直前 6-phase 検証 | PreToolUse + 任意 | `.claude/.taskguard-state/` + `/verify` レポート |
| **F3** | ConfidenceGate | subagent 完了報告の self-confidence | SubagentStop | `.claude/.confidence-gate-state/` |
| **L1** | eval-harness | 1 機能の正しさ (pass@k) | コミット単位 | `.claude/evals/` |
| **L2** | gan-harness | 1 タスクの品質 (adversarial 反復) | 1 反復 | `feedback-NNN.md` |
| **L3** | verification-loop | 多段検証 (lint / test / build / type / coverage / security) | PR 直前 | レポート |
| **L4** | continuous-learning-v2 | エージェントの行動 (instinct 学習) | 全 tool call | `~/.claude/homunculus/` |
| **L5** | agent-introspection-debugging | 失敗パターン自己診断 | 失敗 3 連続 | introspection report |

### 2.2 Workflow 強制 (W1-W4)

| W | command | 役割 |
|---|---|---|
| **W1** | `/test-design <slug>` | MECE 20 カテゴリのテストカタログ生成 + user スコープ承認強制 |
| **W2** | `/design-review <slug>` | `reviewer-registry` の design + security 全 agent を並列起動して fan-out レビュー |
| **W3** | `/module-review` / `/system-review` | TDD 完了直後と全体統合後の 3 観点 (持続可能性 / 汎用性 / 非冗長化) リファクタリング強制 |
| **W4** | `/new-feature` (14-stage) / `/modify-feature` (10-stage) | workflow orchestrator + `workflow-guard.sh` で `/finish-task` 段 BLOCK 判定 |

### 2.3 副産物 discharge (next-actions registry)

タスク実装中・レビュー中に発生した「副産物」を **物理的に消えない設計** で管理:

| 層 | 機構 | 動作 |
|---|---|---|
| 1 | `docs/tasks/next-actions.md` registry | informal な「TODO / 次アクション候補」の公式 location |
| 2 | `_TASK_TEMPLATE.md` 派生 task section | 発生源 task に副産物を明示記録 |
| 3 | `next-actions-surface.sh` (SessionStart) | 未処理 entry を `<system-reminder>` で stderr 強制提示 |
| 4 | `byproduct-discharge-guard.sh` (Stop) | 🔴 未処理 entry 残存で session 終了を `exit 2` BLOCK |
| 5 | `/discharge-byproduct <entry>` | entry → draft / parking-lot / 無視 の移行 helper |

### 2.4 Session 永続化 + PM Orchestration (Serena MCP 必須)

`/sc:save` `/sc:load` `/sc:pm` (SuperClaude plugin) を `.claude/` 単独 portable な自前実装に置換:

| command | 役割 |
|---|---|
| `/save-state` | session 状態を Serena memory に snapshot 保存 (`session/context` + `session/last` + `session/checkpoint`) |
| `/resume-state` | 前 session 状態を memory から復元、未完 task を TaskList 再同期 |
| `/pm-start` | PM Agent orchestration + PDCA cycle 永続化 (Session Start Protocol 内包) |

memory key schema: `session/*` (snapshot) / `plan/<feature>/*` (Plan) / `execution/<feature>/*` (Do) / `evaluation/<feature>/*` (Check) / `learning/{patterns,solutions,mistakes}/*` (Act) / `project/*` (project 全体理解)。

### 2.5 Action Space

- **100 active agents** (10 カテゴリ別、44 件は `docs/archive/agents/` 履歴保持)
- **43 skills** (eval-harness / continuous-learning-v2 / verification-loop / agent-router / repo-map ほか)
- **agent-router**: prompt → named agent 自動推薦 (300+ keywords、84.1% dispatch rate、Phase 2 Hybrid mode で低信頼 prompt に LLM selector)
- **repo-map**: Aider 風シンボル抽出による context 圧縮

### 2.6 規範文書の Layer A/B Strategy (2026-05-28、task-51)

`.claude/rules/*.md` (規範文書) は **Layer A (要約版、context 自動注入) + Layer B (詳細版、明示 Read のみ)** の 2 層構造で運用する。AI は通常運用で Layer A のみを参照し、token 節約 + 規範 visibility 維持を両立。

| 層 | 物理配置 | context 注入 | 内容 |
|---|---|---|---|
| **Layer A** | `.claude/rules/<rule>.md` | claudeMd 経由で常時注入 (Claude Code が `.claude/rules/` を再帰 discover) | 採用 N 条 / 遵守事項 / table (条文 keep) / bypass env 1-2 行 / 重要 keyword 見出し / Layer B link / hook 名 / 起源 1 行 |
| **Layer B** | `.claude/rules-details/<rule>.details.md` | **非注入** (Claude Code は `.claude/rules/` のみ discover、別 dir は対象外) | OK/NG 例詳細 / history / SUPERSEDED 履歴 / bypass 詳細仕様 / 起源詳細 / 5 層強制機構の詳細 / 関連 artifact 完全 list |

> **設計経緯 (2026-05-28 A 案 redesign)**: 当初 `.claude/rules/<rule>.details.md` + frontmatter `paths: []` で非注入を狙ったが、Claude Code 公式仕様 (code.claude.com/docs/en/memory.md) で「`.claude/rules/*.md` は再帰 discover + startup load」「`paths:` は path match 時の**追加適用** (除外機構ではない)」が確定 (claude-code-guide subagent + 公式 doc、confidence 0.95)。token 実測でも `paths: []` は無効で逆に context が増えたため、Layer B を別 dir `.claude/rules-details/` (discover 対象外) へ物理移動して除外を実現。

**Layer B Read trigger (4 条件、Layer A 冒頭に admonition 配置)**:
1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理

通常運用 (上記 4 trigger 非該当) は Layer A のみで判断、Layer B Read skip (token 節約)。詳細は `.claude/rules-details/<rule>.details.md` の各 §「<該当 section>」を参照。

**規約**: Layer A → Layer B link は **2 要素 hard match** (`details.md` 含む markdown link + section anchor) を満たせば spec compliant (2026-05-28 緩和、iter 1 review H-2 反映)。link path は forward `../rules-details/<rule>.details.md` / back `../rules/<rule>.md` (相対参照)。

### 2.7.1 Phase 2 Wave 1 additions (2026-07、task-92 / task-95 / task-96)

Phase 1 完遂後の品質強化 Wave として 3 機構を追加:

| 機構 | 概要 | opt-out |
|---|---|---|
| **pre-commit smoke distribution** (task-92) | `install.sh --update` が `.claude/templates/githooks/pre-commit` (4 smoke curated set: enforcement-mismatch / delegation-guard / task-rule-guard / dispatcher-manifest) を配置。consuming repo 側で `.githooks/pre-commit` を有効化すると commit 前に自動実行される。既存 hook は上書きせず (skip + WARN)。デフォルト予算 60s (`pre_commit_smoke_budget_sec`) | `--no-hooks` (install 時 skip) / `HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false` (template opt-out) / `HC_PRECOMMIT_SKIP=1` (1 回 bypass) |
| **dead-hook inventory smoke** (task-95) | `.claude/tests/dead-hook-inventory-smoke.sh` が `enforcement_matrix` 配下の hook を 3-way (dead / live / alias) 分類、`harness-config.yml` grep で live 定義と `disabled_reason` 整合を自動判定 | (smoke 単体、opt-out 不要) |
| **agent-router LLM fallback toggle** (task-96) | `.claude/hooks/agent-router-suggest.sh` に Anthropic API selector を optional child toggle として追加。default OFF、opt-in で低信頼 prompt (< similarity threshold) のみ LLM 経路へ。daily budget cap + budget 超過時強制 disable + env 互換層 (`AGENT_ROUTER_LLM_FALLBACK`) | default false / `feature_agent_router_llm_fallback_enabled: true` で opt-in / `agent_router_llm_budget_usd_per_day: 0.1` (default) で cap |

### 2.7 アーキテクチャ

```mermaid
flowchart TD
    User[User Prompt] --> Main[Main Agent]
    Main -->|"UserPromptSubmit"| WX[why-x5-reminder]
    Main -->|"UserPromptSubmit"| ME[mode-enforce]
    Main -->|"UserPromptSubmit"| CB[context-budget]
    Main -->|"UserPromptSubmit"| LP[loop-auto-progress]
    Main -->|"UserPromptSubmit"| AR[agent-router]
    Main -->|"PreToolUse"| DG[delegation-guard]
    Main -->|"PreToolUse"| GG[gateguard F1]
    Main -->|"PreToolUse"| TG[task-rule F2]
    Main -->|"PreToolUse Bash"| AA[autonomous-action-guard]
    Main -->|"PreToolUse Bash"| WG[workflow-guard]
    Main -->|"PreToolUse Agent"| PS[parallel-subagent-reminder]
    Main -->|"Agent tool"| Sub[Sub Agent]
    Sub -->|"PostToolUse"| OB[observe.sh]
    Sub -->|"PostToolUse"| FL[failure-loop-detect]
    Sub -->|"SubagentStop"| CG[confidence-gate F3]
    OB --> Audit[harness-audit]
    Audit --> User
    SessionStart[SessionStart] --> NA[next-actions-surface]
    SessionStart --> MS[mode-session-start]
    Stop[Stop] --> BD[byproduct-discharge-guard]
```

---

## 3. どう使うか (How)

### 3.1 前提条件

| 種別 | 要件 |
|---|---|
| 必須 | Claude Code CLI (claude.ai)、Bash 4+、Python 3.9+、jq、git、**rsync** (install.sh) |
| 推奨 | Node.js 22+ / npx (Mermaid hook 用、ローカル install 推奨) |
| 任意 | Docker (SWE-bench 評価機構を使う場合) |
| **MCP 必須** (`/save-state` `/resume-state` `/pm-start` 利用時) | Serena MCP — `.mcp.json` に `serena` entry 登録 (`uvx --from git+https://github.com/oraios/serena serena start-mcp-server --context ide-assistant`) |

### 3.2 Quick Start (install.sh)

新規 project への install / 既存 project への update / dry-run を 1 script で完結:

```bash
# 1. ハーネス本体を clone
git clone https://github.com/thirai-classlab/hirai-method.git ~/hirai-method

# 2. 対象 project に install (新規)
cd ~/hirai-method
bash install.sh /path/to/your-project

# 3. project root で次を実施 (install.sh が案内する)
cd /path/to/your-project
$EDITOR .claude/harness-config.yml         # protected_paths / task_dir / ...
$EDITOR .claude/bash-whitelist.txt         # 使う CLI (pnpm/poetry/cargo/...) を追記
$EDITOR CLAUDE.md                          # task-89 auto-fill 済 (`<...>` placeholder 0)、<!-- TODO(auto-fill) --> comment を補完
git init                                   # observe.sh の project hash 検出を有効化
# Claude Code session 起動 → /init-tasks → /mode loop
```

install.sh は **冪等** で、既存 `.claude/` は `.claude.bak.<timestamp>` に退避してから新規 install (data loss なし)。**CLAUDE.md は default/update mode で既存不可侵** (task-89、`.bak` 退避廃止 = subscbase-api 再発防止)、不在時のみ manifest 検出 → 言語別 template から auto-fill 生成する (`--lang=<id>` で言語 override 可)。

#### install.sh モード

| flag | 用途 |
|---|---|
| (default) | 新規 install。既存 `.claude` は `.bak.<timestamp>` 退避。**CLAUDE.md 不在時は manifest 検出 → 言語別 template から auto-fill 生成** (task-89、`<...>` placeholder 0 + `@.claude/CommonRules.md` 参照済)。**既存 CLAUDE.md は不可侵** (`.bak` 退避廃止)、CommonRules 参照不在時のみ HINT 出力 |
| `--update` | 既存 `.claude/` を rsync 増分上書き。state dir + `settings.local.json` 保持、CLAUDE.md / .mcp.json / .gitignore は不変 (既存 CLAUDE.md に CommonRules 参照不在なら HINT のみ、read-only)。**settings.json は rsync 除外だが rsync 後に自動再生成** (task-80、statusLine / hook / dispatcher 配線を手動なしで同期、permissions 保持) |
| `--force` | 既存 `.claude` を **backup なしで** 上書き (危険)。CLAUDE.md は **auto-fill 生成物で上書き** (task-89、既存内容失われる)。settings.json は破壊リセット後 不在のため自動再生成は skip |
| `--lang=<id>` | (task-89) CLAUDE.md auto-fill 対象言語を明示指定 (`ts` \| `py` \| `go` \| `rust` \| `php` \| `swift` \| `generic`、未指定なら manifest 検出で自動判定) |
| `--dry-run` | 実行内容を表示のみ (rsync -n + 各 cp / mkdir を echo) |
| `--no-mcp` | `.mcp.json` を配置しない (Serena MCP 不要な project) |
| `--mcp-servers=<csv>` | (task-90) 配布する MCP server を csv で選択 (default: `serena,context7` = env placeholder 0 minimal / `--mcp-servers=all` で従来全 7 server 配布 / 選択可能: `serena`, `context7`, `github`, `salesforce`, `agent-browser`, `asana-pat`, `slack` / `--no-mcp` との併用は exit 64) |
| `--no-docs` | `docs/tasks/` `docs/draft/` の templates 配置を skip |

`--update` の除外 (保護) 対象: 全 state dir (`.gateguard-state/` `.taskguard-state/` `.confidence-gate-state/` `.failure-window/` `.agent-markers/` `.context-budget-state/` `.improvement-proposal-state/` `.workflow-state/`) + `settings.json` + `settings.local.json` + `settings.local.example.json` + **`harness-config.local.yml`** (project 固有 override) + `bash-whitelist-requests/` + `worktrees/`

> なお `settings.json` は **rsync 除外** (repo 固有 permissions 保護) だが、`--update` は rsync 後に `generate-settings.sh` を**自動実行して settings.json を再生成**する (task-80、既存 permissions を保持したまま statusLine / 新 hook / dispatcher 配線を反映)。自動再生成は「既存 settings.json + jq あり」が条件で、満たさない時のみ手動再生成が必要。

#### Update 運用 (複数 project)

```bash
cd ~/hirai-method && git pull
bash install.sh --update /path/to/project-a
bash install.sh --update /path/to/project-b
```

> ⚠️ **cross-repo write は Claude Code sandbox + delegation-guard 二重制約で agent 実行不能**。`bash install.sh --update <target>` は **user manual 実行のみ可能**、agent task として subagent / main から呼び出すと sandbox deny される (詳細: memory `feedback_cross_repo_write_sandbox_block.md` / `.claude/rules/development-process.md` §「cross-repo write 例外」)。

> ⚠️ **`--update` は project 固有 file を上書きする**: `.claude/harness-config.yml` / `bash-whitelist.txt` / `settings.json` / `rules/*.md` / `agents/*` / `skills/**` / `commands/*` は exclude されない。事前 `git stash` or `cp <file>.bak` で backup 推奨。

### 3.2.1 導入マニュアル (新規プロジェクト / 既存プロジェクト)

> install.sh の引数は **target ディレクトリのみ** (言語指定引数は無い)。`./install.sh typescript` のような言語名指定は **別物 (`~/.claude/rules/` の rules 用 installer)** で、本ハーネスの install.sh には適用されない。本ハーネスは `bash install.sh <target-dir>` が正。

#### A. 新規プロジェクトに導入する (初回、default mode)

```bash
# 1. ハーネス本体を clone (初回のみ)
git clone https://github.com/thirai-classlab/hirai-method.git ~/hirai-method

# 2. 対象 project に install (target は "ディレクトリ path")
cd ~/hirai-method
bash install.sh /path/to/your-project          # 事前確認したいときは末尾に --dry-run
```

install.sh が配置するもの (既存 `.claude` は `.bak.<timestamp>` 退避、既存 `CLAUDE.md` は default/update mode 不可侵 = data loss なし):

| 配置物 | 備考 |
|---|---|
| `.claude/` 一式 (hooks / skills / rules / commands / scripts / templates / config) | rsync 配置 |
| `CLAUDE.md` (auto-fill、task-89) | 不在時のみ生成: manifest (`package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `composer.json` / `Package.swift`) 検出 → 言語別 template から `<...>` placeholder 0 で直接生成 (`@.claude/CommonRules.md` 参照込み)。既存あれば不可侵 (`.bak` 退避なし)。`--lang=<id>` で言語 override 可 (`ts` \| `py` \| `go` \| `rust` \| `php` \| `swift` \| `generic`) |
| `.mcp.json` | 既存があれば触らない / `--no-mcp` で skip / `--mcp-servers=<csv>` で配布 server を選択 (default `serena,context7`、`all` で全 7 server) |
| `.gitignore` | harness state 除外行を追記 (無ければ新規) |
| `docs/tasks/{list,parking-lot,_TASK_TEMPLATE}.md` + `docs/draft/_DRAFT_TEMPLATE.md` | 既存は skip / `--no-docs` で全 skip |
| `harness-config.yml` の `harness_version: <install 日 UTC>` | install 日 stamp |

導入後の初期設定 (install.sh 完了時にも案内が出る):

```bash
cd /path/to/your-project

# 1. preset を選ぶ (consuming repo は team-default 推奨。重要 guard が ON になる)
#    ※ harness-dev は本ハーネス自身の開発専用 (guard を意図的に緩和) なので consuming repo では選ばない
bash .claude/scripts/hc-config.sh --set default_preset=team-default

# 2. project 固有の上書きは SSoT yml ではなく local.yml に書く (--update で温存される)
$EDITOR .claude/harness-config.local.yml

# 3. 使う CLI を whitelist に追記 (pnpm / poetry / cargo / ...)
$EDITOR .claude/bash-whitelist.txt

# 4. settings.json を生成して hook を配線する (★必須・最重要)
#    install.sh は settings.json を配らない (task-71: repo 固有 permissions / preset を守るため exclude)。
#    未実行だと hook が一切発火せずハーネスが効かない。preset / feature toggle を変えたら再実行する。
bash .claude/scripts/generate-settings.sh --out .claude/settings.json

# 5. CLAUDE.md の TODO comment を補完 (task-89 auto-fill 済で `<...>` placeholder 0、`@.claude/CommonRules.md` 参照込み)
#    manifest から抽出不能な field (User Context / Domain Knowledge 等) は `<!-- TODO(auto-fill): ... -->` で残置される
$EDITOR CLAUDE.md                                       # <!-- TODO(auto-fill) --> comment を project 固有情報で補完

# 6. git 初期化 (observe.sh の project hash 検出に必要)
git init

# 7. 導入確認
bash .claude/scripts/hc-config.sh --summary             # 現 preset / 有効・無効 guard / docs mismatch
```

> ⚠️ **`generate-settings.sh` を実行しないと hook が 1 つも発火しません** (install.sh は settings.json を配布しないため)。これが「install したのにガードが効かない」の最頻原因です。preset 変更 / feature toggle 変更後も再実行してください。

Claude Code session を起動 → `/init-tasks` → (任意 `/mode loop`) → `/new-draft` → 承認 → `/new-task` → 自律実装。

#### B. 既存プロジェクト (導入済) を最新ハーネスに更新する (--update mode)

```bash
cd ~/hirai-method && git pull                            # ハーネス本体を最新化
bash install.sh --update /path/to/your-project           # .claude/ 一式を増分同期 + settings.json 自動再生成
bash install.sh --update /path/to/your-project --commit  # 同期 + .claude/ のみ自動 commit (git repo 必須)

# settings.json は --update が rsync 後に自動再生成する (task-80)。
# → statusLine / 新規 hook / dispatcher 配線が手動なしで反映され、既存 permissions は保持される。
# 自動再生成は「既存 settings.json + jq あり」が条件。満たさない時のみ手動で:
#   cd /path/to/your-project && bash .claude/scripts/generate-settings.sh --out .claude/settings.json
```

`--update` は **既存 `.claude/` 必須** (無ければ exit 64 → 新規は default mode を使う)。

> ✅ **task-80 以降、`--update` は rsync 後に settings.json を自動再生成する** (既存 settings.json + jq あり時)。新しい task で hook / dispatcher manifest / statusLine が追加されても、**手動再生成なしで配線が反映**される (既存 permissions は保持)。jq 不在 / 既存 settings.json 不在の時のみ自動再生成が skip されるので、その場合のみ手動で `generate-settings.sh --out .claude/settings.json` を実行する。
>
> ⚠️ settings.json への**手編集** (dispatcher-manifest 外の独自トップレベル key / 独自 hook) は自動再生成で manifest 由来に**置換され脱落**する。独自 hook は `.claude/scripts/dispatcher-manifest.tsv` に登録すること (これが正しい運用)。

**`--update` で保護される (上書きされない) もの** = project 固有の値:

| 保護対象 | 理由 |
|---|---|
| 全 state dir (`.gateguard-state/` `.taskguard-state/` `.confidence-gate-state/` `.workflow-state/` 他) | session 状態 |
| `settings.json` | repo 固有 permissions / preset (rsync 除外。ただし `--update` 後に**自動再生成**され statusLine / hook 配線が反映、**permissions は保持**) |
| `settings.local.json` / `settings.local.example.json` | ローカル設定 |
| **`harness-config.local.yml`** | project 固有 override (← ここに書けば update で消えない) |
| `bash-whitelist-requests/` / `worktrees/` | 申請・作業領域 |
| `CLAUDE.md` / `.mcp.json` / `.gitignore` | touch しない |

> ⚠️ 逆に `.claude/harness-config.yml` (SSoT) / `bash-whitelist.txt` / `rules/*.md` / `agents/*` / `skills/**` / `commands/*` は **exclude されず上書きされる**。project 固有値はこれらに直書きせず **`harness-config.local.yml` に書く**こと。`--update` 時に SSoT yml へ直書き値を検出すると **MIGRATE warning** が出るので、その値を local.yml に移す。

更新後: `bash install.sh --update` は `.claude/` 配下の変更を列挙する。`--commit` 未指定なら手動で `.claude/` のみ分離 commit (project file と混ぜない)。

> ⚠️ `bash install.sh --update <target>` は **user manual (terminal) 実行のみ可能**。cross-repo write は Claude Code sandbox + delegation-guard 二重制約で agent からは実行不能 (agent task にしない)。

#### B-2. CLAUDE.md 統合 (既存 project の CLAUDE.md と harness を統合する)

`install.sh` (default / `--update` とも) は **既存 CLAUDE.md を不可侵**とする (project 固有情報を守るため、task-89 で `.bak` 退避も廃止 = subscbase-api 再発防止)。default mode で CLAUDE.md 不在時のみ manifest 検出 → 言語別 template から auto-fill 生成する (`<...>` placeholder 0、`@.claude/CommonRules.md` 参照込み)。既存 project に harness を導入/更新した際、project の CLAUDE.md に harness 規範を載せるには **手動統合**する (既存 CLAUDE.md に `@.claude/CommonRules.md` 参照行が不在なら `install.sh` は stdout に HINT を出す)。方針は「**project 固有情報は全保持 + harness 共通規範は `@.claude/CommonRules.md` import に集約**」。

**統合手順**:

1. **`@.claude/CommonRules.md` import を CLAUDE.md 冒頭付近に追加** (既にあれば重複させない)。この 1 行で harness 共通規範 (Development Policy / Autonomous Progression / Rules / 動作モード / Critical Lessons / slash-command 一覧) が session 開始時に load される。
   ```markdown
   @.claude/CommonRules.md
   ```

2. **project 固有内容は全保持** (削除厳禁): Overview / User Context / Tech Stack / Architecture / Implementation Status / Commands / Domain Knowledge / Related Repositories / **project 固有の Critical Lessons**。迷ったら残す。

3. **harness 汎用の本体テキストは重複削除可** (CommonRules.md に集約済): inline 展開していた Development Policy 本体 / Autonomous Progression 本体 / Rules table / harness slash-command 一覧 / 並列 git commit 競合・`set -e` leak 等の harness 共通 Lessons。ハーネステンプレのメタ説明文 ("これは汎用ハーネス用テンプレ" 等) と未使用 placeholder `<...>` も除去 (placeholder は project 実値で埋める)。

4. **project 固有の harness delta は `## Project 固有 追補 (CommonRules への delta)` セクションに集約**: 委譲スコープの path 読替 (例 `apps/**/src`) / project 固有の autonomous 確認項目 (例 本番 deploy / DB migration) / project 固有 rule row 等、CommonRules 汎用規範に対する「この repo だけの差分」をここに置く。

> このセクションは `--update` では同期されない (CLAUDE.md は protect)。harness 更新で CommonRules 側の共通規範が変わっても、project の CLAUDE.md は **import 1 行経由で自動追従**する (= 二重管理不要、共通規範を各 repo に転記しない)。新しい project 固有事情が出たら本セクション (Project 固有 追補) に追記する。

#### B-3. project-rules 保護 (harness rule を上書きせず project 固有 override を書く)

harness の 7 共通 rule (`.claude/rules/{development-process,git-workflow,modes,self-improvement,task-management,why-x5-output,workflow}.md`) は **harness 所有**で `install.sh --update` の rsync で上書き追従される。consuming repo がこれらを直接編集すると update で消失する。これを防ぐため、各 harness rule の末尾から `@../project-rules/<name>.md` を **@import** で結合 load する設計を採る。

| layer | 配置 | update 挙動 | 用途 |
|---|---|---|---|
| **harness rule** (上書き) | `.claude/rules/<name>.md` | rsync で上書き (harness 所有) | 共通規範本体 + 末尾に `@../project-rules/<name>.md` 1 行 |
| **project rule** (保護) | `.claude/project-rules/<name>.md` | **なければ作成・あれば更新しない** | project 固有の拡張 / override (harness rule の**後に**結合) |

- **編集先の指針**: harness 共通 rule を project 固有に変えたい / 追補したい時は、**7 harness rule (`.claude/rules/*.md`) を一切触らず** `.claude/project-rules/<name>.md` に書く。@import で harness rule の後に load されるため、後勝ちで override / 追補できる。
- **保護機構 (二重)**: `install.sh` は (1) `RSYNC_EXCLUDES` / `RSYNC_EXCLUDES_MINIMAL` に `--exclude=project-rules/` を含め update/force/overwrite-all いずれの rsync でも project-rules を touch しない、(2) create-if-absent で **なければ空テンプレ配置・あれば skip** (既存 project 編集を上書きしない)。→ harness 共通 rule は update 追従、project 固有 override は永続保護を両立。
- **新規ルール領域**: `.claude/project-rules/` に新 file を追加 + 必要なら CLAUDE.md / 既存 rule から `@import` する (7 harness rule 本体は触らない)。

#### C. mode / flag 早見表

| flag | 用途 |
|---|---|
| (なし) | 新規 install (既存 `.claude` は `.bak` 退避)。**CLAUDE.md は不在時のみ auto-fill 生成** (task-89、manifest 検出 → 言語別 template)、既存は不可侵 + CommonRules 参照不在時 HINT |
| `--update` | 既存 `.claude/` 増分上書き (state / local 保持、CLAUDE.md 等 不変。既存 CLAUDE.md に `@.claude/CommonRules.md` 参照不在なら HINT のみ)。settings.json は rsync 除外後に**自動再生成** (task-80、配線同期 + permissions 保持)。既存 .claude 必須 |
| `--update --commit` | 上記 + sync された `.claude/` path のみ自動 commit (非 git target は skip + WARN) |
| `--force` | backup なしで上書き (危険)。CLAUDE.md は **auto-fill 生成物で上書き** (task-89、既存内容失われる) |
| `--lang=<id>` | (task-89) CLAUDE.md auto-fill 対象言語を明示指定 (`ts` \| `py` \| `go` \| `rust` \| `php` \| `swift` \| `generic`) |
| `--dry-run` | 実行内容を表示のみ |
| `--no-mcp` | `.mcp.json` を配置しない |
| `--mcp-servers=<csv>` | (task-90) 配布 MCP server を csv 選択 (default `serena,context7`、`all` で全 7 server、`--no-mcp` と併用は exit 64) |
| `--no-docs` | docs templates 配置を skip |

exit code: 引数エラー / 不正 flag / 不正 `--lang` 値 / target 不在 / self-install 等 = **64**、rsync 未 install = **69**。

> 詳細フロー図は [§3.9.2](#392-インストール--設定--利用の全体フロー)、project/user-level の 2 install モードは [§3.11](#311-2-つの-install-モード-project-level--user-level) を参照。

### 3.3 動作モード (Normal / Loop)

| モード | 用途 | 動作 |
|---|---|---|
| **Normal** (既定) | 探索的作業、user 確認分岐重視 | 重要分岐で user 確認を求める / SessionStart で Loop 切替を 1 度提案 |
| **Loop** | 設計承認済 task の自律進行 | 戦術判断は AI 推奨を即採用 / 中間確認禁止 / Why × 5 表示は維持 / 適切な粒度で commit 必須 |

切替: `/mode loop` / `/mode normal` (`.claude/mode.yml` に永続化、`HC_MODE=loop` env でも一時切替可)。

**Loop モードでも user 確認必須の例外** (`modes.md` 遵守事項 2):
- 設計文書の新規追加 (`docs/draft/<slug>.md` 起こし + 承認)
- 仕様変更 / scope 拡張
- 戦略的判断 (architecture 選択 / 技術スタック変更)
- 自律実行禁止 11 カテゴリ (main/stg* push / `gh pr merge` / 本番 deploy / DB migration / secrets / 等)

### 3.4 タスク管理フロー (採用 6 条準拠、2026-05-25)

**Task = Phase = N Step、Phase 中間階層廃止** の 2 階層構造を強制。

| 項目 | 規約 |
|---|---|
| Task 必須項目 | ゴール (1 文、観察可能) / 作業概要 (3-5 件) / 完了条件 (DoD) / 概要欄 (list.md 用、3 要素: 何のため × 何をやる × 何ができる) |
| Step 必須項目 | 作業概要 (1-2 文) / 完了条件 (定量 or 観察可能事実) / Step status (📝/🔲/🔄/✅/⏸️) / 概要欄 (作業概要のみ) |
| Task 最終 3 Steps (固定) | テスト設計レビュー (5+ reviewer 動的選定) → テスト合格 (UI 含むなら E2E 必須) → リファクタリング (3 観点判定 or skip) |
| 小タスク許容 | hot fix / typo / config 1 行追加は「1 Task + 1 Step」OK |
| 既存 task 移行 | 2026-05-25 以前作成 task は次回着手時に honor system で新構造へ再構造化推奨 |

### 3.5 plan-first 経路 B (batch planning)

**3 件以上の task を一括計画する場合**は経路 B を選択:

```mermaid
flowchart LR
    A["master roadmap で N task §plan 確定"] --> B["user 承認"]
    B --> C["main agent が list.md に N 行 📝 batch 先置き"]
    C --> D["個別 draft 起案 (subagent 並列可)"]
    D --> E["user 承認"]
    E --> F["/new-task で 📝 → 🔲 update"]
```

機械強制 hook:
- **SessionStart**: `docs/draft/*.md` ≥ 3 件 ∧ `list.md` task 行 == 0 で `<system-reminder>` 注入 (経路 B 適用検討促進)
- **PreToolUse(Write `docs/draft/*.md`)**: 新規 draft Write 時 list.md に対応 slug の 📝 行不在なら warn 注入 (block しない、honor system)

### 3.6 基本コマンド

| カテゴリ | コマンド |
|---|---|
| **タスク** | `/init-tasks` `/new-draft` `/new-task` `/start-task` `/finish-task` `/task-bypass` `/discharge-byproduct` |
| **Session** | `/save-state` `/resume-state` `/pm-start` |
| **Git / レビュー** | `/commit` `/reviewpr` |
| **自己改善 L1 (Eval)** | `/eval define\|check\|report` |
| **自己改善 L2 (GAN)** | `/gan-design` `/gan-build` |
| **自己改善 L4 (Learning)** | `/instinct-status` `/projects` `/learn` `/evolve` `/promote` `/instinct-export` `/instinct-import` |
| **自己改善 L5 (Introspect)** | `/agent-introspect` |
| **事実検証 F1 (GateGuard)** | `/gate-status` `/gate-clear` `/gate-bypass` |
| **事実検証 F2 (Verify)** | `/verify` |
| **Workflow 強制 (W1-W4)** | `/test-design` `/design-review` `/module-review` `/system-review` `/new-feature` `/modify-feature` |
| **動作モード** | `/mode normal\|loop` |
| **監査** | `/harness-audit` (`--swe-bench` / `--router` flag) |

### 3.7 典型開発フロー

```mermaid
flowchart LR
    S1["/new-draft slug"] --> S2["user 承認"]
    S2 --> S3["/new-task id slug"]
    S3 --> S4["/start-task id"]
    S4 --> S5["Agent tool で subagent 委譲<br/>(並列起動が default)"]
    S5 --> S6["subagent 実装 + 完了報告<br/>(confidence: 0.X 必須)"]
    S6 --> S7["/module-review"]
    S7 --> S8["/finish-task id"]
    S8 --> S9["/commit"]
    S9 --> S10["user manual push + PR"]
```

### 3.8 サブエージェント運用 (3 必須要件)

| 要件 | 規範 |
|---|---|
| **背景起動** | Agent tool は `run_in_background: true` 必須 (30s 以内 smoke のみ例外)、メインを user 対話に常時開放 |
| **並列化義務** | file 領域独立な sub-task 2 件以上は並列起動 default、1 subagent 統合委譲は明示的理由 (race risk / 共有 file 衝突 / context budget / sequential 依存) が必要 |
| **agent type 選定** | `general-purpose` は specialized agent 不在時のみ、`test-automator` / `refactoring-specialist` / `*-build-resolver` / `code-reviewer` / `security-reviewer` 等を default 採用 |

機械強制 hook:
- `agent-marker-set.sh` (foreground 起動 warning)
- `parallel-subagent-reminder.sh` (単独起動 + 並列化対象 keyword 検出で warning)
- agent type mismatch 検出 (`general-purpose` + 専門 type 適合 keyword で推奨 type 注入)

### 3.9 設定 (`.claude/harness-config.yml`)

全挙動は `.claude/harness-config.yml` の集中設定で制御する。主要 key:

```yaml
# 保護パス (メインからの直接 Edit/Write を block)
protected_paths: [src, tests, scripts]
protected_paths_code: [.claude/hooks, .claude/skills, .claude/scripts]
code_file_extensions: [.sh, .py, .mjs, .ts, .js]

# タスク管理
task_dir: docs/tasks
draft_dir: docs/draft

# Bash 許可リスト (SSoT)
bash_whitelist_path: .claude/bash-whitelist.txt

# Confidence Gate (F3)
confidence_threshold: 0.6
confidence_required: true
confidence_state_dir: .claude/.confidence-gate-state

# Context budget
context_budget_threshold: 0.66

# 機能 on/off (feature toggle、各 hook を group 単位で集中制御)
feature_loop_mode_enforcement_enabled: true   # loop-auto-progress / mode-enforce / loop-confirmation-detector
feature_task_rule_guard_enabled: true         # task-rule-guard / list-md-plan-first-reminder
feature_byproduct_discharge_enabled: true     # next-actions-surface / byproduct-discharge-guard
feature_why_x5_enforcement_enabled: true      # why-x5-violation-detect / why-x5-reminder
feature_notify_enabled: true                  # stop / notify (macOS 通知音)

# reviewer 制御 (W1-W4 + Task 最終 3 Step のレビュー反復)
review_min_count_test: 5         # テスト設計レビュー reviewer 数下限
review_max_count_test: 10        # 同上限 (cost 制御)
review_iteration_max: 5          # レビュー反復上限 (採用 6 条 4)

# 観測
homunculus_root: ~/.claude/homunculus
```

#### 3.9.1 設定編集ツール `hc-config.sh` (推奨)

yml を直接 `$EDITOR` で編集すると **型ミス / 構文崩れでハーネス全体が動作不能**になるリスクがある。`hc-config.sh` は型 validation + atomic write + 自動 backup 付きで安全に編集する CLI / 対話ツール。

**実行コマンド**:

```bash
# 対話 menu (引数なしで起動、推奨)
bash .claude/scripts/hc-config.sh

# 使い方表示
bash .claude/scripts/hc-config.sh --help
```

**CLI args (script 自動化 / 単発編集用)**:

| コマンド | 動作 |
|---|---|
| `--list` | 全 key 一覧 (key / current / default / type の 4 列) |
| `--get <key>` | 値取得 (env override > yml > default の 3 段解決) |
| `--set <key>=<value>` | 値設定 + 型 validation + `.bak.<ts>` backup + atomic write |
| `--feature <name>=<true\|false>` | feature toggle 専用 shorthand (`feature_<name>_enabled` の alias) |
| `--reset <key>` | default 値に戻す |
| `--reset-all` | 全 key を default に戻す |
| `--diff` | 現在値と default の差分一覧 |
| `--validate` | 全 key の型 validation のみ実行 (yml 編集なし) |
| `--config <path>` | 編集対象 yml を override (任意 yml file 指定 / staging 確認用) |
| `--help` | 使い方表示 |

**対話 menu (引数なし起動)**: ①全 key 一覧 ②key 選択 → 値編集 ③feature toggle 一括 on/off ④reviewer 設定 quick edit ⑤終了。`q` / `0` / `Ctrl-D` でいつでも終了。

**使用例**:

```bash
# 現在値を確認
bash .claude/scripts/hc-config.sh --get review_iteration_max     # → 5

# Loop モード強制 hook 群を一括 OFF (試験的 / regression debug 時)
bash .claude/scripts/hc-config.sh --feature loop_mode_enforcement=false

# reviewer 反復上限を 3 に変更 (cost 制御、atomic backup 付き)
bash .claude/scripts/hc-config.sh --set review_iteration_max=3

# 通知音を OFF (静音セッション)
bash .claude/scripts/hc-config.sh --feature notify=false

# 全設定を default に戻す
bash .claude/scripts/hc-config.sh --reset-all
```

**安全機構**: 各編集前に `harness-config.yml.bak.<timestamp>.<pid>` を自動作成 (最新 10 件保持、`HC_BAK_RETENTION_COUNT` で変更可)。`.tmp` に書込 → yaml 構文検証 → `mv` で atomic 上書き。検証 FAIL なら旧 yml を維持して rollback。

> env 上書き例: `HC_PROTECTED_PATHS="src tests"` / `HC_TASK_DIR=tasks` / `HC_REVIEW_ITERATION_MAX=3` 等で yml を触らず一時調整も可 (優先順: env > yml > default)。詳細は [`docs/PORTABILITY.md`](docs/PORTABILITY.md) / [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md) §「hc-config.sh による yml 編集」。

### 3.9.2 インストール → 設定 → 利用の全体フロー

```mermaid
flowchart TD
    I1["bash install.sh /path/to/project<br/>(ハーネス本体を配置)"] --> I2["cd /path/to/project"]
    I2 --> C1["bash .claude/scripts/hc-config.sh<br/>(対話 menu で設定確認 / 調整)"]
    C1 --> C2["$EDITOR .claude/bash-whitelist.txt<br/>(使う CLI を追記: pnpm/poetry/cargo...)"]
    C2 --> C3["$EDITOR CLAUDE.md<br/>(task-89 auto-fill 済、&lt;!-- TODO(auto-fill) --&gt; comment を補完)"]
    C3 --> C4["git init<br/>(observe.sh の project hash 検出)"]
    C4 --> U1["Claude Code session 起動"]
    U1 --> U2["/init-tasks (タスク台帳初期化)"]
    U2 --> U3["/mode loop (自律進行モード)"]
    U3 --> U4["/new-draft → 承認 → /new-task<br/>→ /start-task → 自律実装"]
```

| 段階 | コマンド | 目的 |
|---|---|---|
| **① インストール** | `bash install.sh /path/to/project` | `.claude/` 一式配置 + **CLAUDE.md auto-fill 生成** (task-89、manifest 検出で `<...>` placeholder 0)。既存 `.claude` は `.bak` 退避、既存 `CLAUDE.md` は不可侵 |
| **② 設定** | `bash .claude/scripts/hc-config.sh` | feature toggle / reviewer 制御 / 保護パス等を安全に確認・調整 |
| | `$EDITOR .claude/bash-whitelist.txt` | project で使う CLI prefix を追記 |
| | `$EDITOR CLAUDE.md` (TODO comment 補完) | task-89 auto-fill 済、`<!-- TODO(auto-fill) -->` comment を project 固有情報 (User Context / Domain Knowledge 等 manifest から抽出不能な field) で埋める |
| | `git init` | observe.sh の project hash 検出を有効化 |
| **③ 利用** | Claude Code 起動 → `/init-tasks` → `/mode loop` | session 開始 + タスク台帳初期化 + 自律進行モード |
| | `/new-draft <slug>` → 承認 → `/new-task <id> <slug>` | 設計→承認→タスク化の 3 step (設計なき着手を hook が block) |
| | `/start-task <id>` → subagent 委譲 → `/finish-task <id>` | 着手 → 実装 (並列 subagent) → 完了クローズ |

> ②③ の途中で feature toggle を切り替えたくなったら、いつでも `bash .claude/scripts/hc-config.sh --feature <name>=false` で安全に変更できる (atomic backup 付き、ハーネス再起動不要)。

### 3.10 動作確認

```bash
cd /path/to/your-project
bash .claude/hooks/lib/config-loader.sh && echo "config-loader OK"
# Claude Code session 起動後:
#   - 任意の Read で hook 発火、observe.sh が ~/.claude/homunculus/projects/<hash>/ に記録
#   - 保護パス配下の Edit が delegation-guard.sh で BLOCK されること
#   - /harness-audit で hook 発火率 / GateGuard 状況を確認
```

### 3.11 2 つの install モード (project-level / user-level)

| モード | settings.json | hook path | 対象 project 解決 | 用途 |
|---|---|---|---|---|
| **project-level** (既定、install.sh の対象) | `<project>/.claude/settings.json` | `bash .claude/hooks/X.sh` | cwd = project root 前提 | 1 project 専用、`.claude/` を repo に commit |
| **user-level** | `~/.claude/settings.json` (templates から copy) | `bash ${HOME}/.claude/hooks/X.sh` | 4 段 fallback (`HC_PROJECT_ROOT` env → `git rev-parse` → `CLAUDE_PROJECT_DIR` env → `pwd`) | 複数 project で hooks 共有 |

user-level setup:

```bash
mkdir -p ~/.claude
cp -R ~/hirai-method/.claude/{hooks,skills,rules,commands} ~/.claude/
cp ~/hirai-method/.claude/templates/settings.user-level.json.template ~/.claude/settings.json
# git 外で動かす場合のみ:
export HC_PROJECT_ROOT=/path/to/your-project
```

---

## 4. 重要規律 (Critical Lessons)

本 harness 運用で繰り返し発生した事故 → 機械強制化した教訓 (詳細は [`CLAUDE.md`](CLAUDE.md) §「Critical Operational Lessons」):

| # | 教訓 | 重要度 | 機械強制 hook |
|---:|---|:---:|---|
| 1 | 並列 subagent に同一 branch で `git commit` させる際は `git add <specific files>` 限定 + `git reset` 禁止 | HIGH | (prompt 規約、honor system) |
| 2 | `.claude/hooks/lib/*.sh` の file-top に `set -euo pipefail` を書かない (caller leak → SIGPIPE → exit 141 silent) | HIGH | (regression review、honor system) |
| 3 | Loop モード中、subagent 起動後にメインが受動待ち停止しない | HIGH | `loop-auto-progress-reminder.sh` |
| 4 | Loop モードの「中間確認禁止」を盾に `git push origin main\|stg*` / `gh pr merge` / 本番 deploy を自律実行しない | HIGH | `autonomous-action-guard.sh` + `delegation-guard.sh` (protected branch push deny) |
| 5 | メインが `.claude/hooks/*.sh` `.claude/skills/**/*.{sh,py,mjs}` `.claude/scripts/**/*` を直接 Edit/Write しない (subagent + staging 戦略必須) | HIGH | `delegation-guard.sh` (`HC_PROTECTED_PATHS_CODE` + `HC_CODE_FILE_EXTENSIONS`) |
| 6 | メインが `docs/` 直下に新規設計文書を直接 Write しない (`docs/draft/` 起こし → 承認 → `docs/tasks/` 反映の 3 step 必須) | HIGH | `draft-flow-guard.sh` |
| 7 | Loop モードでも「設計→承認→タスク追加」フローは免除されない | HIGH | (規範、`modes.md` 遵守事項 2 例外条項) |
| 8 | task 構造は採用 6 条 (Task=Phase=N Step、Phase 中間階層廃止) を採用 | HIGH | (規範、`task-management.md` §タスク構造規範) |
| 9 | list.md plan-first 不在 → SessionStart hook + Write warn 2 段検出 | HIGH | `list-md-plan-first-reminder.sh` (SessionStart) + `task-rule-guard.sh` (PreToolUse Write) |

---

## 5. Hook 仕様

| Event | Hook | 役割 |
|---|---|---|
| **PreToolUse** | `delegation-guard.sh` | メインの保護パス到達 block + Bash 3 layers (whitelist / git destructive deny / protected branch push deny) |
| | `gateguard.sh` (F1) | 事実材料未提示時の Edit/Write/破壊的 Bash を block |
| | `task-rule-guard.sh` (F2) | draft なきタスク作成を block + draft path warn 注入 (list.md 📝 行不在検出) |
| | `draft-flow-guard.sh` | `docs/` 直下深さ 1 新規 .md/.mdx を block (draft 経路強制) |
| **PreToolUse(Bash)** | `autonomous-action-guard.sh` | Loop モード自律実行禁止 11 カテゴリ (`git push origin main\|stg*` / `gh pr merge` / `vercel --prod` / `terraform apply` 等) を BLOCK、Normal モードでは warning |
| | `workflow-guard.sh` | `/finish-task <slug>` 直前に state JSON 検証、未完 stage / pending findings 残存で BLOCK |
| **PreToolUse(Agent)** | `agent-marker-set.sh` | foreground 起動 warning |
| | `parallel-subagent-reminder.sh` | 単独起動 + 並列化対象 keyword 検出で warning + agent type 推奨注入 |
| **PostToolUse** | `observe.sh` | 全 tool call を JSONL 記録 (`~/.claude/homunculus/`) |
| | `failure-loop-detect.sh` | 同種エラー 3 連続で `/agent-introspect` 提案 |
| | `check-md-mermaid.sh` | `.md` / `.mdx` 内 mermaid block を mermaid@11 で構文検証 |
| **SubagentStop** | `confidence-gate.sh` (F3) | 完了報告 confidence (≥0.6) 検証 (major subagent only) |
| **UserPromptSubmit** | `why-x5-reminder.sh` | 「<何のため> のため、<何をやる> を行う」1 行 format を毎ターン強制 (v10、2026-05-23) |
| | `mode-enforce.sh` | Loop モード稼働中、毎ターン遵守事項 5/7/8 再注入 |
| | `context-budget.sh` | Context 使用率 60% / 80% / 95% tier 突破で `/save-state` 実行 + 再開提案を強制 |
| | `loop-auto-progress-reminder.sh` | Loop モード subagent 待ち中の停止検出で独立作業強制を注入 |
| | `agent-router-suggest.sh` | named agent 推薦 hint 注入 (300+ keywords、84.1% dispatch rate) |
| **SessionStart** | `init-tasks.sh` | タスク状態復元 (`list.md` / `parking-lot.md` / template 自動生成) |
| | `mode-session-start.sh` | 現モード表示 + Normal モード時 Loop 切替提案 + Serena memory 存在時 `/resume-state` 自動提案 |
| | `next-actions-surface.sh` | 未処理 next-actions entry を `<system-reminder>` で stderr 提示 (緊急度 🔴 強調) |
| | `list-md-plan-first-reminder.sh` | `docs/draft/*.md` ≥ 3 件 ∧ `list.md` task 行 == 0 で 経路 B 適用検討促進 |
| **Stop** | `byproduct-discharge-guard.sh` | next-actions 🔴 未処理 entry 残存時に session 終了を `exit 2` BLOCK |
| | `stop.sh` | macOS 通知音 (Glass.aiff) |
| **Notification** | `notify.sh` | macOS 通知音 (Hero.aiff) |

bypass: `/gate-bypass <gate-name> <理由>` で 1 回限り skip 可能、`.claude/.workflow-state/bypass.log` に append + `/harness-audit` 集計。

---

## 6. エージェント / スキル

### 6.1 エージェント (active 100 件、10 カテゴリ)

| カテゴリ | active 数 | 代表例 |
|---|---:|---|
| 01-core-development | 11 | api-designer, backend-developer, frontend-developer |
| 02-language-specialists | 8 | typescript-pro, python-pro, golang-pro, react-specialist |
| 03-infrastructure | 11 | docker-expert, kubernetes-specialist, terraform-engineer |
| 04-quality-security | 13 | code-reviewer, security-auditor, debugger |
| 05-data-ai | 11 | ml-engineer, prompt-engineer, postgres-pro |
| 06-developer-experience | 12 | git-workflow-manager, refactoring-specialist |
| 07-specialized-domains | 4 | seo-specialist, payment-integration |
| 08-business-product | 12 | product-manager, technical-writer |
| 09-meta-orchestration | 11 | workflow-orchestrator, agent-organizer |
| 10-research-analysis | 7 | research-analyst, market-researcher |

archive 44 件は `docs/archive/agents/` に履歴保持 (restore 可)。詳細: [`docs/INVENTORY.md`](docs/INVENTORY.md)。

agent-router 確認: `python3 .claude/skills/agent-router/router.py --explain "<prompt>"`

### 6.2 スキル (43 件、代表)

- `eval-harness` — pass@k 評価フレーム (L1)
- `gan-style-harness` — adversarial 反復 (L2)
- `continuous-learning-v2` — instinct 学習 (L4)
- `verification-loop` — 多段検証 (L3)
- `agent-introspection-debugging` — 失敗自己診断 (L5)
- `agent-router` — subagent_type 推薦
- `repo-map` — Aider 風シンボル抽出 (context 圧縮)
- `gateguard` — F1 ゲートのスキル化レイヤー
- `check-md-mermaid` — Markdown mermaid 構文検証
- `mcp-builder` — MCP server 雛形生成
- `karpathy-guidelines` — LLM コーディング行動規約 (Think Before Coding / Simplicity First / Surgical Changes / Verifiable Success Criteria)
- ほか 32 件

全件確認: `find .claude/skills -maxdepth 1 -type d`

---

## 7. ベンチマーク

### 7.1 SWE-bench Lite (dry-run 実測)

| version | 改善内容 | 適用率 (sample) | 累計 cost |
|---|---|---:|---:|
| C-1 | unified-diff prompt | 40% (2/5) | $1.078 |
| C-1.5 | 全文出力 + difflib | 60% (3/5) | $0.853 |
| C-1.6 | whole-file timeout → unified-diff fallback (hybrid) | N/A (中断) | — |

C-1.5 は適用率 1.5× にしつつコスト低下。本番 200 task (50 × F1/F2 on/off) は約 $45-60 / 3.5h (parallel=4) 見込み。

評価実行:

```bash
python3 .claude/skills/eval-harness/swe-bench/runner.py \
    --tasks tasks/lite-50.json --variant hybrid
```

### 7.2 agent-router dispatch rate

| 指標 | 値 | 備考 |
|---|---|---|
| Phase 1 (keyword only) — 90 日サンプル | 84.1% (991/1,178 prompts) | 目標 70% 超過 |
| Phase 1 — 20 representative prompts | 100% (20/20) | tests/test_router.py fixture |
| Phase 2 (Hybrid mock) — 15 low-/subtle-signal | 100% (15/15) | mock selector wiring 検証 |
| Phase 2 LLM selector per-call cap | $0.05 / call | `--llm-budget-usd` で調整可 |

実運用 dispatch は `~/.claude/homunculus/projects/<hash>/dispatch.jsonl` に永続化 (2026-05-05 開始)、`/harness-audit --router` で経時集計可能。

---

## 8. ハーネス比較

平井メソッドを他 OSS と比較:

| OSS | Dispatch 方式 | SSoT | LLM 利用 | star |
|---|---|---|---|---:|
| **平井メソッド** | Phase 1: keyword 一段 / Phase 2: Hybrid (keyword → LLM selector for conf < 0.5) | dispatch-table.yml + .claude/agents/*.md | Phase 2 で Hybrid 化 ($0.05/call cap) | (本リポ) |
| Claude Code 公式 sub-agents | 親 LLM が description を読み Agent tool で起動 | Markdown frontmatter | Yes | 純正 |
| AutoGen SelectorGroupChat | LLM が selector で次話者選定 | Python class | Yes | 54k |
| LangGraph supervisor | handoff tool 呼出で routing | create_supervisor | Yes | 24.8k+ |
| CrewAI hierarchical | manager_llm が役割で動的割当 | Agent class | Yes | 49.9k |
| BMAD-METHOD | "BMad Master" が persona 切替 | .bmad-core | Yes | 43k+ |
| SuperClaude | keyword + 拡張子 + flag | CLAUDE.md / AGENTS.md | No | 6k |
| OpenHands | AgentDelegateAction で明示呼出 | register_agent | Yes | 72.3k |

### 哲学的位置付け

- **平井メソッド**: defense-first (fabrication 抑止 / 委譲強制 / 監査可能性)。LLM-based dispatch を排し、coverage を犠牲にしてでも決定論性を取る
- **SuperClaude / OpenHands**: 親 LLM の判断に丸投げ、設計はミニマル
- **CrewAI / AutoGen / LangGraph**: 多 agent collaboration が価値、dispatch 精度はトレードオフ

詳細: [`docs/AGENT-ROUTER.md`](docs/AGENT-ROUTER.md#改善-backlog)

---

## 9. トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `delegation-guard.sh: BLOCKED` | メインから保護パス (`src/` `tests/` `scripts/` or `.claude/hooks/` 等) への直接 Edit | Agent tool で subagent 委譲 (`run_in_background: true` 必須) |
| `gateguard.sh: BLOCKED — 事実材料が不足` | 初回 Edit/Write 前の事実材料 (importers / callers / data 構造 / user 逐語引用) 未提示 | 4 事実を提示するか `/gate-bypass gateguard <理由>` |
| `confidence-gate.sh: BLOCKED` | subagent 完了 summary に `confidence: 0.X` 不在 or < 0.6 | `confidence: 0.X` 記載 + 必要なら検証追加で 0.6 以上に、bypass `/gate-bypass confidence <理由>` |
| `git destructive guard: BLOCKED` | `push --force` / `reset --hard` / `branch -D` / `clean -f` / `checkout --` / `stash drop\|clear` / `tag -d\|-f` / `reflog expire` / `gc --prune=now` 等 | 非破壊代替 (`git revert` / `git stash pop`) 優先、必要時 `export ECC_ALLOW_DESTRUCTIVE_GIT=1` |
| `protected branch push deny: BLOCKED` | `git push origin main` / `stg*` / `release/stg-prod` 等 | feature branch + PR 経由を推奨、必要時 `export ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` |
| `autonomous-action-guard: BLOCKED` (Loop モード) | 自律実行禁止 11 カテゴリ (`git push origin main\|stg*` / `gh pr merge` / 本番 deploy 等) | user 明示承認を取る、必要時 `export ECC_AUTONOMOUS_ACTION_OVERRIDE=1` |
| `task-rule-guard: BLOCKED — draft 不在` | `docs/draft/<slug>.md` なしで `docs/tasks/task-<id>-<slug>.md` Write 試行 | `/new-draft <slug>` で draft 起こし → 承認 → `/new-task` |
| `draft-flow-guard: BLOCKED` | `docs/` 直下 (深さ 1) に新規 .md/.mdx を直接 Write | `docs/draft/<slug>.md` 起こし → 承認 → `docs/tasks/` 反映 |
| `agent-router suggestion` が出ない | confidence < 0.5 で hint 抑制、または fallback=true | `python3 .claude/skills/agent-router/router.py --explain "<prompt>"` で手動確認 |
| `git push` が permission deny される | Claude Code permission system が一律 deny (subagent / bypass env 回避不可、既知事象) | **user manual terminal 必須**、`git push -u origin <branch>` を直接実行 |
| `parallel-subagent-reminder` warning | 単独 Agent 起動 + 並列化対象 keyword 検出 | 並列起動を default に、意図的なら無視 OK (`HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false` で off) |
| Mermaid hook 遅い / オフライン | `check-md-mermaid.sh` が npx で都度 install (30MB / 10-20s) | `npm install -g mermaid@11.13.0 jsdom` で事前 install、または project-local install |

---

## 10. ドキュメント

| File | 内容 |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | プロジェクト固有設定 (templates 付き) + Critical Operational Lessons |
| [`docs/INVENTORY.md`](docs/INVENTORY.md) | 全構成要素の Path 表 |
| [`docs/INVENTORY-stocktake-2026-05-04.md`](docs/INVENTORY-stocktake-2026-05-04.md) | agent 棚卸しレポート |
| [`docs/PORTABILITY.md`](docs/PORTABILITY.md) | 別リポへの移植手順 + 4 段 PROJECT_ROOT 解決仕様 |
| [`docs/SELF_IMPROVEMENT.md`](docs/SELF_IMPROVEMENT.md) | F1-F3 + L1-L5 詳細 + 監査 |
| [`docs/CONFIDENCE-GATE.md`](docs/CONFIDENCE-GATE.md) | Confidence Gate (F3) 仕様 |
| [`docs/AGENT-ROUTER.md`](docs/AGENT-ROUTER.md) | agent-router 設計詳細 |
| [`.claude/rules/development-process.md`](.claude/rules/development-process.md) | TDD / 委譲 / Bash deny 反射 / 並列化義務 / agent type 選定 |
| [`.claude/rules/workflow.md`](.claude/rules/workflow.md) | Workflow 強制 (W1-W4) + 副産物 discharge + Session 永続化 |
| [`.claude/rules/task-management.md`](.claude/rules/task-management.md) | タスク構造規範 (採用 6 条) + plan-first 経路 A/B + Parking Lot |
| [`.claude/rules/modes.md`](.claude/rules/modes.md) | Normal / Loop モード仕様 + 遵守事項 8 + 自律実行禁止 11 カテゴリ |
| [`.claude/rules/why-x5-output.md`](.claude/rules/why-x5-output.md) | 「<何のため> のため、<何をやる> を行う」1 行 format (v10、2026-05-23) |
| [`.claude/rules/self-improvement.md`](.claude/rules/self-improvement.md) | L1-L5 + F1/F2 事実検証の使い分け規約 |
| [`.claude/rules/git-workflow.md`](.claude/rules/git-workflow.md) | branch 命名規約 (`<type>/<short-kebab-description>`) |

---

## 11. ライセンス / 寄稿

- MIT — see [`LICENSE`](LICENSE)
- Issue / PR welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md)
