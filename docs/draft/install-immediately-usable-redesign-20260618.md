---
slug: install-immediately-usable-redesign-20260618
title: インストール即時利用可能化 改善提案書 (Install-Ready Redesign)
created_at: 2026-06-18
approved_at: 2026-06-18
status: ✅ 承認済 (Phase 1 から着手)
type: master-roadmap (batch planning 経路 B)
related_docs:
  - https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610
  - https://mdv.sandboxes.jp/docs/hirai-method-harness-design-invariants-20260610
  - https://mdv.sandboxes.jp/docs/hirai-method-harness-fp-review-20260610
  - https://mdv.sandboxes.jp/docs/hirai-method-harness-decision-sheets-20260610
  - https://mdv.sandboxes.jp/docs/hirai-method-harness-meta-review-20260610
evidence_sources:
  - subscbase-api 2026-06-18 install 実機検証 (本日)
  - 5 docs (grand-summary を SSoT に他 4 doc 統合)
---

# インストール即時利用可能化 改善提案書

> **TL;DR**: hirai-method ハーネスを「**`bash install.sh <target>` 直後に何も追加設定せず Loop モードで安全に走り始められる**」状態に再設計する。subscbase-api への 2026-06-18 install 実機検証で **タスク管理機能が完全に不発** (8 guard 全 disabled) する規模の伝搬問題が顕在化したため、これを起点に 5 docs (fp-review / decision-sheets / design-invariants / meta-review / grand-summary) で提案された invariant 8 件 + Wave 1-2 改修計画と統合する。**改修方針 A1 (現ハーネス維持 + 品質強化拡張) を採用**、3 Phase で段階導入する。

---

## §1. 背景: subscbase-api dogfood 実機検証で何が起こったか

### 1.1 観測された問題 (1 行サマリ)

別 Claude Code セッションが subscbase-api リポで作業着手した際、ハーネスの **タスク管理機能が一切起動しなかった**:
- `/new-draft` / `/new-task` / `/start-task` / `/finish-task` 等 slash command 未使用
- `docs/tasks/list.md` に 1 行も追加されず (完全 template 状態)
- `TaskCreate (TodoWrite)` tool 未使用
- 設計→承認→タスク追加フロー (CommonRules.md § Development Policy) を踏まずに `Workflow` ツール起動を試行
- `/effort` で ultracode (xhigh + dynamic workflow orchestration) に切替後、即実装に走ろうとした

### 1.2 根本原因 (rank 順、subscbase-api 実機証拠付き)

| # | 原因 | 証拠 |
|---|---|---|
| **R1** | `default_preset: harness-dev` が install.sh で **verbatim copy**、consuming repo で 8 guard 全 disabled | `subscbase-api/.claude/harness-config.yml:470` `default_preset: harness-dev` / `hc-config.sh --summary` で `totals: 0 enabled, 8 disabled` |
| **R2** | 上記の連鎖で **task-rule-guard / draft-flow-guard / workflow-guard / gateguard が no-op** | 各 hook 冒頭の `is_feature_enabled <name>` toggle check が false 評価で即 `echo '{}'; exit 0` |
| **R3** | **`mode: loop` + 設計→タスク追加フローの honor system 化** で AI が直接実装に走る | hook 無効化下で Loop モード「中間確認禁止」が優先解釈、Loop 例外条項 (設計新規追加・仕様変更は確認必須) は honor system のみ |
| **R4** | **`docs/tasks/list.md` が完全 template 状態** で plan-first reminder 発火条件未満 | list.md 全行 placeholder、SessionStart hook 条件 (`draft ≥ 3 ∧ task 行 == 0`) 未達で reminder 注入されず |
| **R5** | **settings.local.json の重複定義** (ASANA_PAT 2 回) など `/doctor` で 8 setup issues | AI 始動時に「ハーネス側問題あり」と認識し、別 path (Workflow / ultracode) へ逃げた疑い |
| **R6** | **`hc-config.sh --get` / `--summary` が `harness-config.local.yml` を読まない実装** | `hc-config.sh` 内 grep "local.yml" 0 hit (CLI parser)、`config-loader.sh` のみ局所対応 (hook runtime と CLI 表示の非対称) |
| **R7** | **`default_preset` 値変更が `feature_*_enabled` に波及しない** | yml line 366-371 で task/draft/workflow/gateguard が個別 `false` 明示。`default_preset: team-default` だけ書いた local.yml は guard を有効化できず、初版応急修正で失敗を確認 |

### 1.3 応急修正の経過 (本日実施済)

| 段階 | 修正内容 | 結果 |
|---|---|---|
| 初版 | `subscbase-api/.claude/harness-config.local.yml` に `default_preset: team-default` のみ | **失敗** (`feature_*_enabled` 波及せず、guards 全 false のまま) |
| 修正版 | 同 local.yml に `feature_task_rule_guard_enabled: true` 等 4 件を **individual** 明示 | **成功** (`config-loader.sh` 経由で hook runtime 値が全部 true、`hc-config.sh --get` の CLI 表示は依然 false = R6 顕在化) |
| C 案併用 | `subscbase-api/CLAUDE.md` 末尾に §6「タスク管理運用 (subscbase-api 固有)」追記 | 設計→承認→タスク化フローを project 規範として明文化 |

→ subscbase-api 単発は救済済だが、**配布元 hirai-method の install.sh が直っていない限り、新規 consuming repo は同じ穴に毎回はまる**。

---

## §2. 第一原理 v2 (meta-review 2026-06-10 由来、品質含む)

### 2.1 自律完遂 DoD の再定義

```
自律完遂 = (a) user 介入無し commit / push 到達
        ∧  (b) 完成後 1 週間 engineer error 報告 0 件
        ∧  (c) 設計違反 / silent failure / regression 0 件
```

旧第一原理 ((a) のみ) では本日の subscbase-api 事案を防げない (commit 直前の honor 違反は機械検出不能)。**品質を DoD に含めることが全 invariant の根拠基盤**。

### 2.2 介入機構の net positive 立証責任

「介入を強要する機構 (BLOCK / 強制 hook / 規範 honor)」は **net positive を立証** できなければ採用しない。立証手段:
- 過去 N 件の事故 / 観察を防げる証拠
- 対応する bypass env の存在 (緊急脱出経路)
- 機械強制 ↔ honor system の選択根拠

### 2.3 BLOCK 教育 3 点提示

BLOCK error は **(1) なぜ block されたか + (2) 復旧 1 行コマンド + (3) bypass env** の 3 点を必須提示。本日 subscbase-api セッションで AI が `Workflow` ツールに逃げた一因は、honor system の規範文書を BLOCK と読み違えた可能性が高い (`fp-review` 観察 1 の AI 萎縮)。

### 2.4 修復可能操作の自律化

修復可能な操作 (commit / branch 切替 / lint 修正 / build retry / feature push) は AI 自律。修復不能 (本流 merge / 本番 deploy / 削除 / secret rotation / 第三者リポ操作) のみ user 承認必須。

---

## §3. 設計 invariant 8 件 (I1〜I8、meta-review/grand-summary 由来)

| # | 名前 | 1 行要約 | 強制機構 | 状態 |
|---|---|---|---|---|
| **I1** | Config SSoT | 全設定は `harness-config.yml` SSoT、`config-loader.sh` 経由のみ参照 | enforcement-mismatch-smoke + pre-commit yml path hardcode grep BLOCK | 既採用 (flat)、nested は W1-7 で補完 |
| **I2** | Dispatcher-Only Hook | 全 hook は dispatcher 経由、`settings.json` 直配線 0 件 | `generate-settings.sh --check` + dispatcher-manifest-smoke | 既達成 (例外 1 件)、W1-8 で完全化 |
| **I3** | Quality Gate | 全 commit が pre-commit smoke 通過、全 PR が CI matrix UNEXPLAINED-FAIL=0 | `.githooks/pre-commit` + `.github/workflows/smoke.yml` matrix | **新規** (W1-9 / W1-10) |
| **I4** | UI Contract | UI 拡張子変更 task は cross-file 契約 SSoT + visual artifact 記録 | PostToolUse(Edit/Write UI ext) + `cross-file-contract-check.sh` + finish-task | **新規** (W1-11) |
| **I5** | Observability | BLOCK / bypass / fire / silent failure 全件 log append、fire 0 回 hook 30 日 GC | `lib/observability.sh` + pre-commit logging grep | **新規** (W2-7) |
| **I6** | Education | BLOCK message は why / fix_one_liner / bypass_env / docs_link の **4 引数必須** | `lib/block-message.sh` + pre-commit BLOCK exit 2 path 経由 grep | **新規** (W1-12) |
| **I7** | Config-Consumer-Smoke Triplet | yml 新規 key 追加 commit は consumer + smoke を同 commit に含む | pre-commit で yml diff 新規 key 抽出 → consumer/smoke 存在 grep BLOCK | **新規** (W2-9) |
| **I8** | Iter Cycle Minimum | `review_iteration_min:3` 未達 closure 禁止、min/max/規範 (採用 6 条 4 上限 5) 3 点一致 | reviewer-count-guard 拡張 + enforcement-mismatch-smoke 拡張 | **新規** (W2-8) |

### 3.1 invariant の根拠 (事故 / 観察由来)

- I3 ← `feedback_set_e_in_sourced_libs` (set -euo pipefail SIGPIPE 141 サイレント死)
- I3 + I4 ← `feedback_ui_rewrite_stale_smoke_regression` (task-76 旧 UI assert smoke が silent break)
- I4 ← `feedback_parallel_subagent_cross_file_contract_drift` (task-63 main-panel ↔ view-container id mismatch)
- I7 ← `feedback_config_value_needs_consumer_and_smoke` (task-44 / 63 / 64、yml 飾り key)
- I8 ← `feedback_iter_fix_introduces_new_crit_pattern` (task-61 iter 2 で iter 1 CRIT 7 全 closure → iter 3 で新規 CRIT 4 出現)
- I5 ← `feedback_subagent_staging_mv_silent_fail` (staging mv で実行 bit 落ち、silent fail)

### 3.2 install/portability 観点の invariant 特定

| invariant | install 観点 |
|---|---|
| **I1 Config SSoT** | install 直後の configuration ground truth が 1 箇所 = consuming repo で混乱しない |
| **I3 Quality Gate** | `install.sh` で `.githooks/pre-commit` 自動配置 + `core.hooksPath` 自動設定 + `.github/workflows/smoke.yml` 配布 → install 直後から quality gate が有効 |
| **I6 Education** | install 直後の BLOCK で AI が萎縮しない (3 点提示で復旧可能) |

### 3.3 採用見送り

旧 I3 (Layer A/B 規範) — `paths:` frontmatter が除外機構として効かず機械強制不能 (`feedback_paths_frontmatter_does_not_exclude` で立証済)、honor system のまま `.claude/rules/` に留置。

---

## §4. インストール即時利用可能化の根本問題と対策 (本提案の主軸)

### 4.1 (R1+R7) `default_preset` verbatim 伝搬 + feature toggle 独立性

| 観点 | 内容 |
|---|---|
| 現状 | hirai-method `harness-config.yml` の `default_preset: harness-dev` (本 repo 内部開発用) が install.sh の rsync で consuming repo に **逐語 copy**。yml 内で `feature_task_rule_guard_enabled: false` 等 5 件が個別 `false` 配布。`default_preset` 値変更だけでは `feature_*_enabled` に波及しない設計 |
| 影響 | consuming repo で task-rule-guard / draft-flow-guard / workflow-guard / gateguard / tool_call_slip が **全部 silent no-op**。AI が「設計→承認→タスク化」を強制されず直接実装に走る (subscbase-api 本日事案) |
| 対策 A (推奨) | `install.sh` に **preset 自動切替 logic** を追加: 新規 install 時は `default_preset: team-default` で書込、feature toggle も対応する team-default 値で書込 (`task_rule_guard / draft_flow_guard / workflow_enforcement / gateguard` を **true** に上書き)。opt-in で `--preset=harness-dev` を allow |
| 対策 B (短期、応急) | install.sh 末尾で `harness-config.local.yml` を自動生成 (`default_preset: team-default` + guard toggle **8 件** individual `true` = feature 4 件 + `review_required_{design,test,module,system}` 4 件)。review_required 4 件を欠くと enforcement_matrix の team-default 期待 (presets.team-default: true、team-default の disabled_reason 無し) と自己矛盾し、consuming repo で enforcement-mismatch-smoke Case 3 が UNDOCUMENTED mismatch FAIL する (2026-07-05 HOTFIX-1 実装時に実測検出、8 件へ修正) |
| 対策 C (構造改革、長期) | `harness-config.yml` を **preset block 構造化**: `preset_table.team-default.features.{task_rule_guard: true, ...}` を yml SSoT 化し、`default_preset:` 切替で feature toggle が自動連動。現在の独立 toggle と互換維持しつつ移行 |

### 4.2 (R6) hc-config.sh CLI の local.yml 非対応

| 観点 | 内容 |
|---|---|
| 現状 | `hc-config.sh --get <key>` と `--summary` が `harness-config.local.yml` を読まない。実 hook runtime は `config-loader.sh` 経由で正しく override 取り込み (本日検証で立証) |
| 影響 | `--summary` で「8 guard disabled」と表示されても、実 runtime は「8 guard enabled」だったり (本日 subscbase-api の応急修正で発生)。CLI と runtime の **真実が 2 つに分裂** |
| 対策 | `hc-config.sh` 内の yml parser (line 280-1248 で `local yml="$1"` 局所変数定義のみ、`harness-config.local.yml` 参照 0 hit) を `config-loader.sh` Step 3.5 と同じく **`harness-config.local.yml` を SSoT yml の後に merge** する実装に変更。`--summary` には local override 適用箇所を `(local overridden)` で明示 |

### 4.3 (R3) CLAUDE.md.template の placeholder 前提

| 観点 | 内容 |
|---|---|
| 現状 | install.sh 既定 install で `CLAUDE.md` は `CLAUDE.md.template` として配置され、user が `<...>` placeholder を手動で埋める前提 (`install.sh:9`) |
| 影響 | 「インストール直後すぐ使える」と矛盾。subscbase-api では旧 CLAUDE.md が `.bak` で退避 + template が別配置、user (本日) が「マージしてください」と明示依頼するまで template のまま放置 |
| 対策 A | `install.sh` で project 検出 (`package.json` / `Cargo.toml` / `go.mod` / `pyproject.toml`) → 言語別 starter CLAUDE.md を自動生成 (Tech Stack / Commands 等を auto-fill) |
| 対策 B | AI 起案: install.sh が `claude` CLI 経由で auto-fill draft を生成 (要 ANTHROPIC_API_KEY 設定、--no-claude で skip) |
| 対策 C | `CLAUDE.md.example.<lang>.md` を `.claude/templates/` に複数 (`ts.md` / `py.md` / `go.md` 等) 配布、install.sh が言語検出して該当版を CLAUDE.md として配置 |

### 4.4 (R5) `.mcp.json` 固定配布 + settings.local.json 重複

| 観点 | 内容 |
|---|---|
| 現状 | install.sh は `.mcp.json` に asana / slack / serena / context7 / agent-browser 等の全 MCP server を verbatim 配布。`/doctor` で「8 setup issues: settings, MCP」が install 直後から報告 |
| 影響 | 必要ない MCP server (例: Asana 連携なし project で asana-pat MCP) で AI が `${ASANA_PAT}` 不在 warning を毎回読む。`/doctor` が常に騒がしく、AI が「ハーネス側問題」を誤認識 |
| 対策 A | `install.sh --mcp-servers=<csv>` で配布 server 選択 (`--mcp-servers=serena,context7` minimal default) |
| 対策 B | install.sh の wizard モード (`--interactive`) で MCP server を 1 つずつ y/N 確認 |
| 対策 C | `mode.yml` の `asana_enabled: false` で `.mcp.json` の asana entry を auto-strip (mode-asana-prompt.sh と連動、`feature_asana_enabled` 新設) |

### 4.5 (R5) /doctor 8 setup issues の install 直後 0 化

| 観点 | 内容 |
|---|---|
| 現状 | install 直後の `/doctor` が 8 件警告。subscbase-api 本日の statusline `8 setup issues: settings, MCP · /doctor` がそれ |
| 影響 | 「install 直後 すぐ使える」と矛盾。各 issue は (a) settings.local.json 重複 (b) MCP 未設定 env (c) permissions stale entry 等 |
| 対策 | `install.sh` 末尾で **self-doctor** を実行 → 期待外 issue があれば user に提示。期待値内 (env 未設定 等) は absorb (`/doctor` も期待値内を grayout) |

### 4.6 (R3) 規範文書 ↔ effective state の乖離 = AI 萎縮

| 観点 | 内容 |
|---|---|
| 現状 | `CommonRules.md` / `task-management.md` / `modes.md` 等は「BLOCK」と書いているが、`harness-dev` preset で実は honor system に降格。consuming repo は `team-default` が正しい姿だが install.sh が反映しない |
| 影響 | AI は in-context rule (BLOCK 表記) を信じて自律実行を控える → 上記 fp-review observation 1。逆に subscbase-api セッションは「実は guard が disabled」を見抜けず Workflow に逃げた |
| 対策 W1-2 (採用済 ✅ conf 0.85) | SessionStart hook で `hc-config.sh --summary` 13 行注入 → AI が常時 effective state を可視化。**ただし対策 4.2 が前提**: CLI が local.yml 読まなければ注入される情報も嘘になる |

### 4.7 quality gate (`.githooks/`, `.github/workflows/`) 不在

| 観点 | 内容 |
|---|---|
| 現状 | install.sh は `.githooks/` / `.github/workflows/` を配布しない。consuming repo は pre-commit / CI matrix を自前で書く前提 |
| 影響 | I3 Quality Gate invariant が install 直後に効かない。subscbase-api では既存 `.husky/` があるが harness 由来 smoke は組み込まれていない |
| 対策 | install.sh で `.githooks/pre-commit` 配布 + `core.hooksPath .githooks` 自動設定 (idempotent)、`.github/workflows/harness-smoke.yml` 配布 (matrix 2 preset: `team-default` + `strict`) |

### 4.8 list.md 完全 template 状態 + plan-first reminder 不発

| 観点 | 内容 |
|---|---|
| 現状 | install.sh の `docs/tasks/list.md` は `<!-- 例: -->` placeholder のみ。SessionStart hook の plan-first reminder 発火条件 (`draft ≥ 3 ∧ task 行 == 0`) を満たさず |
| 影響 | AI に「task 台帳が空である」事実が認識されない |
| 対策 A | install.sh 末尾で **first-task wizard** 起動: 「最初の作業対象は何ですか?」→ `/new-draft` 自動起動 |
| 対策 B | list.md placeholder に「**ここから着手**: `/new-draft <slug>`」の actionable header を埋め込み |
| 対策 C | SessionStart reminder の発火条件緩和: `task 行 == 0` 単独でも reminder 注入 (現状: draft 3 以上 AND task 0 必要 = 過保護) |

---

## §5. 改修計画 (3 Phase、A1 方針)

### Phase 1: Install Ready 化 (本提案の主軸、1-2 day、parallel 着手可)

| ID | 作業 | 対策 | 工数 | conf |
|---|---|---|---|---|
| **P1-1** | install.sh に consuming repo 用 preset 自動切替 | 4.1 A | 0.5 day | 0.90 |
| **P1-2** | `hc-config.sh --get` / `--summary` に local.yml 統合 | 4.2 | 0.5 day | 0.90 |
| **P1-3** | install.sh 末尾 self-doctor (8 issue 0 化検証) | 4.5 | 0.5 day | 0.85 |
| **P1-4** | SessionStart `hc-config.sh --summary` 全文注入 (W1-2 採用済) | 4.6 / W1-2 | 0.5 day | 0.85 |
| **P1-5** | CLAUDE.md.template auto-fill (project 検出 + 言語別 starter) | 4.3 A/C | 1 day | 0.80 |
| **P1-6** | `.mcp.json` 配布 minimal default + opt-in flag | 4.4 A | 0.5 day | 0.85 |
| **P1-7** | list.md actionable header + plan-first reminder 発火緩和 | 4.8 B/C | 0.5 day | 0.85 |

**Phase 1 完了条件 (DoD)**: 新規 dummy repo で `bash install.sh ../dummy-repo` 直後に下記が全部成立:
- `/doctor` issue == 0
- `hc-config.sh --summary` で task_rule_guard / draft_flow_guard / workflow_enforcement / gateguard 全 enabled 表示
- `docs/tasks/list.md` に「ここから着手: `/new-draft <slug>`」header あり
- CLAUDE.md が言語別 starter で auto-fill 済 (`<...>` placeholder == 0)
- Claude Code セッション開始時に `hc-config.sh --summary` 13 行が `<system-reminder>` で AI に注入

### Phase 2: 品質強化 (I3 + I6 機械強制、1-2 week)

| ID | 作業 | invariant | 工数 | conf |
|---|---|---|---|---|
| **P2-1** | install.sh で `.githooks/pre-commit` 配布 + `core.hooksPath` 自動 (W1-9) | I3 | 1 day | 0.85 |
| **P2-2** | install.sh で `.github/workflows/smoke.yml` matrix 2 preset 配布 (W1-10) | I3 | 1 day | 0.80 |
| **P2-3** | BLOCK message 4 引数必須化 + `lib/block-message.sh` 抽出 (W1-12) | I6 | 2 day | 0.85 |
| **P2-4** | 死蔵 hook 棚卸し (slip-detector / mode-asana-prompt / mode-enforce 個別判定) (W1-1) | I2 | 1 day | 0.88 |
| **P2-5** | agent-router LLM fallback default OFF + yml toggle 明示化 (W1-5) | I1 | 0.5 day | 0.85 |
| **P2-6** | enforcement_matrix 全 hook 拡張 (W2-2) | I1 | 1 day | 0.82 |

### Phase 3: 品質保証 (I4 + I5 + I7 + I8、3-4 week)

| ID | 作業 | invariant | 工数 | conf |
|---|---|---|---|---|
| **P3-1** | UI Contract hook + cross-file contract check (W1-11) | I4 | 3 day | 0.80 |
| **P3-2** | `lib/observability.sh` + 30 日 GC + fire 0 回 hook 棚卸し (W2-7) | I5 | 3 day | 0.80 |
| **P3-3** | yml triplet pre-commit (key 追加 → consumer + smoke 同 commit BLOCK) (W2-9) | I7 | 2 day | 0.78 |
| **P3-4** | iter_min:3 規範化 + reviewer-count-guard 拡張 (W2-8) | I8 | 2 day | 0.78 |
| **P3-5** | install smoke 自動化 (tmp dir 実 install + 検証) (W2-3) | I3 | 2 day | 0.75 |
| **P3-6** | 規範文書 SSoT 整合 (W2-1) | I1 | 3 day | 0.78 |

---

## §6. 受け入れ判定 (第一原理 v2 DoD)

| DoD 項目 | 検証手段 | 担当 Phase |
|---|---|---|
| (a) user 介入無し commit / push 到達 | dummy repo で install → first task draft → `/new-task` → `/start-task` → commit → push が全 user 介入 0 で通過 | Phase 1 |
| (b) 完成後 1 週間 engineer error 報告 0 件 | subscbase-api + 別 consuming repo 2 件で 1 週間運用、issue tracker 監視 | Phase 1 完了後 + 1 週間 |
| (c) 設計違反 / silent failure / regression 0 件 | pre-commit + CI matrix 通過率 100%、bypass.log で意図外 bypass 0 件 | Phase 2 完了後 |

---

## §7. 開発の進め方 (`task-management.md` 採用 6 条準拠)

### 7.1 master roadmap 化 (batch planning 経路 B)

本提案 = master roadmap、N = 7 + 6 + 6 = 19 task。**経路 B 適用判定 3 基準** (N ≥ 3 / 複数セッション跨る / Phase 区分あり) を全件 OR で満たす。

承認後の進行:
1. main agent が `docs/tasks/list.md` に **19 行 📝 先置き** (P1-1 〜 P3-6)
2. 各 task の `docs/draft/<slug>.md` を順次起案 (subagent 並列起案可)
3. `/new-task` 実行で 📝 → 🔲 update
4. 着手は依存解決順 (P1-1, P1-2, P1-4 は並列 OK / P1-3 は P1-1+P1-2 後 / P1-5/6/7 は並列 OK / Phase 2 は Phase 1 完了後)

### 7.2 依存関係 (DAG)

```
P1-1 (preset 自動切替) ──┐
P1-2 (hc-config local.yml) ─┼──→ P1-3 (self-doctor)
P1-4 (SessionStart 注入) ────┘     │
                                   │
P1-5 (CLAUDE.md auto-fill) ────────┤
P1-6 (.mcp.json minimal) ──────────┤
P1-7 (list.md header) ─────────────┘
                                   │
                                   ▼
                          Phase 2 全 (P2-1〜6)
                                   │
                                   ▼
                          Phase 3 全 (P3-1〜6)
```

### 7.3 各 task 設計 6 条準拠

各 task = 1 Task = 1 Goal + N Steps。最終 3 Steps = テスト設計レビュー / テスト合格 / リファクタリング (固定)。

例: P1-1 (install.sh preset 自動切替)
- Step 1: 既存 install.sh 構造把握 + テスト設計
- Step 2: `apply_consuming_repo_preset()` 関数追加 + tmp dir test
- Step 3: install.sh 既定モードに組込
- Step 4: opt-in `--preset=<name>` arg parse 追加
- Step 5: テスト設計レビュー (`tdd-guide` + `pr-test-analyzer` + `test-automator` 並列、`review_min_count_test ≤ N ≤ review_max_count_test`)
- Step 6: 全 smoke (`enforcement-mismatch-smoke.sh`、新規 `install-preset-smoke.sh`) 合格
- Step 7: リファクタリング (持続可能性 / 汎用性 / 非冗長化)

---

## §8. リスクと却下事項

### 8.1 alternative architecture 却下 (meta-review §A 由来)

| 案 | 内容 | verdict | 理由 |
|---|---|---|---|
| A1 | **現ハーネス維持 + 品質強化拡張** | ✅ **採用** | 既存 87 flat key + dispatcher 100% を活かし、invariant 8 件で品質保証層を追加 |
| A2 | ECC (Everything Claude Code) 採用 | risky | dogfood 不在、移行コスト高 |
| A3 | Workflow tool 全寄せ | risky | hook layer の機械強制を失う、ただし部分採用 (multi-tool block 対策) は検討 |
| A4 | Claude Code 標準のみ | reject | autonomy 35、現 65 から退行 |
| A5 | scratch から再構築 | reject | 移行コスト huge、既存 instinct 喪失 |
| A6 | 規範のみ (hook 全廃止) | reject | autonomy 30、honor system で本日事案再発確実 |

### 8.2 採用見送り invariant

- **旧 I3 (Layer A/B 規範)** — `paths:` frontmatter 除外機構として効かず機械強制不能、honor system のまま `.claude/rules/` 留置 (token 圧迫の根本解決には別 path 必要、`feedback_layer_a_b_two_tier_rule_structure.md` 参照)

### 8.3 段階移行が必要な領域

- **hc-config UI の nested + array 拡張** — 案 A (Web UI 即拡張) は drift 防止未整備で却下、**案 C (段階移行)** 推奨 (W1-7、grand-summary §6)
- **harness-config.yml の preset block 構造化** (対策 4.1 C) — 現 flat toggle と互換維持しつつ段階導入、Phase 4 (本提案後の別 epic) で扱う

### 8.4 user 確認が必要な未決事項 (decision-sheets §D 由来)

| category | 質問 | 推奨 default |
|---|---|---|
| A 運用方針 | Loop mode 継続? consuming repo 差別化方針? | Loop 継続 + team-default を consuming default に |
| B 設計美学 | yml SSoT vs docs 改訂量 (片側 SSoT 完全化 vs 両側維持) | yml SSoT 優先、docs は pointer 化 (W2-1) |
| C 投資意思 | install smoke 自動化 (W2-3 / P3-5) はやるか? | やる (本提案の DoD 達成に必須) |
| D 副作用許容 | SessionStart +300 tokens / 月 $0.03 許容? | 許容 (本日事案防止価値 >>> cost) |

---

## §9. 次のアクション (user 承認後)

1. **main agent**: `docs/tasks/list.md` に 19 行 📝 先置き (Phase 1: P1-1〜P1-7、Phase 2: P2-1〜P2-6、Phase 3: P3-1〜P3-6)
2. **main agent**: 各 task の `docs/draft/<slug>.md` 起案 (subagent 並列起案可、最大 6 件同時)
3. **user**: 各 draft を順次承認 (`approved_at:` 記入)
4. **main agent**: 承認済 draft から `/new-task <id> <slug>` で task ファイル生成 + 📝 → 🔲 update
5. **main agent**: `/start-task <id>` で着手 (依存解決順、Phase 1 並列可)

### 9.1 緊急 hot fix の候補 (本提案 user 承認とは独立に先行可能)

| ID | 内容 | 工数 | 効果 |
|---|---|---|---|
| **HOTFIX-1** | install.sh §6.4 で `harness-config.local.yml` を create-if-absent 自動生成 (`default_preset: team-default` + guard toggle 8 件 true = feature 4 + review_required 4、§4.1 対策 B 参照。当初案「5 行追加 / toggle 4 件」は enforcement-mismatch-smoke Case 3 自己矛盾のため 8 件へ拡張) | 30 min | subscbase-api 事案の即時防止 (新規 consuming repo) |
| **HOTFIX-2** | hc-config.sh `--get` / `--summary` に `harness-config.local.yml` 読込み追加 | 1-2 h | CLI 表示と runtime 値の一致 |

HOTFIX 2 件は P1-1 / P1-2 の minimal subset。本提案承認待ちの間に user が `feat/hotfix-install-ready` branch で先行 merge 可能。

---

## §10. 用語定義

- **FP**: First Principle (第一原理)。設計判断の最深層命題
- **decision-sheet**: 改修 Wave の各 option を depth 5 + confidence で深掘りした意思決定シート
- **invariant**: ハーネス全体に渡る不変条件 (I1〜I8)
- **preset**: `default_preset` で選択する enforcement profile (advisory / team-default / strict / harness-dev)
- **feature toggle**: `feature_<name>_enabled` で個別 on/off する hook / command の機能スイッチ
- **consuming repo**: hirai-method を install して使う外部 project (subscbase-api 等)
- **harness-dev preset**: 本 hirai-method repo 自身の dogfooding 用 preset (8 guard を意図的に advisory 化、`disabled_reason` 付き)
- **team-default preset**: 一般 consuming repo の標準 preset (主要 guard 全 enabled)

---

## §11. 変更履歴

| 日付 | 内容 | 起案者 |
|---|---|---|
| 2026-06-18 | 初版起案。subscbase-api install 事案を起点に 5 docs (2026-06-10 set) と統合 | main agent (claude-opus-4-7) |

---

## §12. 承認

```
approved_at: 2026-06-18
approver: user (kfurutani@classlab.co.jp)
notes: Phase 1 から着手承認。master roadmap として list.md に 19 行先置き。
```

承認後は `slug: install-immediately-usable-redesign-20260618` を `/new-task` の入力に使い、Phase 1 から順次 task 化する。
