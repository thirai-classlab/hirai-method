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

## §11. Phase 1 完遂 followup addendum (2026-07-05)

> **位置付け**: §5 Phase 1 (P1-1 〜 P1-7) の実装完遂に伴う Phase 2/3 起案前の refinement 集約。§1〜§10 (本文) は書き換えず、Phase 1 実装で顕在化した知見・副産物・reviewer 発火 pattern を Phase 2/3 draft 起案時の前提として明文化する。本 addendum の approver は §11.5、変更履歴は §12 に統合。

### 11.1 Phase 1 完遂 achievement

2026-07-05 に Phase 1 P1-1 〜 P1-7 の 7 task を **5 PR (HOTFIX + Wave 1-4)** で完遂した (unique PR 5 件 = #68 HOTFIX / #70 Wave 1 / #71 Wave 2 / #72 Wave 3 / #73 Wave 4、§11.6 と一致)。第一原理 v2 DoD (§2.1) のうち **(a) user 介入無し commit / push 到達** = 全 Wave が Workflow 自律 + human review only で達成、**(b) install 直後 setup issue 0 化** = self-doctor D1-D8 で機械保証。

| task | P1-N | 概要 | merge PR |
|---|---|---|---|
| task-85 | P1-1 | install.sh preset 自動切替 (`--preset=<name>` 4 値) + enforcement_matrix advisory disabled_reason 8 行追記 | PR #68 (HOTFIX) |
| task-86 | P1-2 | `hc-config.sh` local.yml 統合 (`--get` / `--summary` / `--validate` / `--list` / `--diff` / TUI に local override 反映 + typo WARN + array key gap 明示) | PR #70 |
| task-88 | P1-4 | SessionStart `hc-config.sh --summary` 全文注入 (cap 800→2400B + sub-toggle + init 失敗経路 fail-open) | PR #71 |
| task-91 | P1-7 | list.md「ここから着手」actionable header + plan-first reminder 2-tier 化 + source gating (resume/compact skip) | PR #70 (併合) |
| task-89 | P1-5 | CLAUDE.md.template auto-fill (manifest 6 種検出 + 言語別 starter 7 件 + `{{TOKEN}}` render 3 関数 + 既存 file 不可侵 HINT) | PR #72 |
| task-90 | P1-6 | `.mcp.json` 配布 (`--mcp-servers=<csv>` opt-in、serena+context7 minimal default、jq 不在 fallback) | PR #72 (併合) |
| task-87 | P1-3 | install.sh 末尾 self-doctor.sh (D1-D8 8 check + WARN/INFO 2 段 + preset-aware D6 + exit code 2 層 fail-open) | PR #73 |

### 11.2 実装で確立した pattern (§4 / §5 前提の更新)

Phase 2/3 draft 起案時に **前提として利用可能** な pattern。各 pattern は Phase 1 で dogfood 実測済:

- **staging 戦略**: `/tmp` Write → mv → 755/644 mode 確認 (subagent silent fail 対策、[[feedback_subagent_staging_mv_silent_fail]])。`.claude/` 配下編集の default 経路
- **mktemp fail-open ガード**: `X` 末尾 + `${TMPDIR:-/tmp}` + `|| true` (§6.4 の先例に準拠、install.sh / hook 共通契約)
- **`set -uo pipefail` fail-open 契約**: hook file-top で `set -euo pipefail` 禁止 (caller への leak 回避)、`do_work() ( set -euo pipefail; ... )` の subshell 化のみ許可
- **feature toggle 3 点 set**: yml key + metadata TSV + env override (`HC_FEATURE_<NAME>_ENABLED`) + hook 冒頭 `is_feature_enabled <name>` check — 新規 hook / command 追加時の default 規範
- **mutation probe**: reviewer 実効性検証の必須 lens。smoke を意図的に壊す (sed で assert 除去) → 本当に FAIL 化するか実測 → 復元。Phase 1 では task-87 self-doctor smoke で dogfood 済
- **逐次 vs 並列判定**: `install.sh` の同域編集 (arg parse / header / summary output) は逐次必須、独立 file (新 hook / 新 smoke / template 追加) は並列 default (task-91 が典型例 — install.sh 変更 0 行で完結)
- **副産物 discharge**: 実装中発見 → next-actions.md 即時 entry → 完了時 user 提示 → 別 task or Phase 2/3 吸収 (Phase 1 で #78-#83 の 6 entry を捕捉)
- **3 点提示 format**: BLOCK / WARN / INFO ごとに `why:` / `fix:` / `silence: <bypass_env>` の 3 行提示 (task-87 self-doctor で全 D1-D8 dogfood、§2.3 BLOCK 教育 3 点提示 と integrated)、P2-3 lib/block-message.sh の直接前提
- **fail-open 2 層 (exit code 分離)**: hook / script は WARN 未満は exit 0 で継続、CRITICAL 発生時のみ exit 2 (BLOCK) or exit 1 (soft fail)。task-87 で dogfood

### 11.3 Phase 2/3 refinement

Phase 2 (P2-1 〜 P2-6 = task #92-#97) / Phase 3 (P3-1 〜 P3-6 = task #98-#103) の draft 起案時に **必ず反映** する 6 refinement。

#### R1: P2-3 (#94) BLOCK 4 引数 と Wave 4 self-doctor 3 点提示の vocabulary 統合

**背景**: Phase 1 Wave 4 (task-87 self-doctor.sh) で `why:` / `fix:` / `silence:` の 3 点提示 format を **WARN の 5 args** (`emit_warn <d_id> <title> <why> <fix> <silence>`) + **INFO の 2 args** (`emit_info <d_id> <detail>`、silence 無し) の **2 severity** で実装済、AI 教育効果を実測 (§2.3 BLOCK 教育 3 点提示と整合)。既存 hook 群の BLOCK 出力は (a) `exit 2` + stderr (`draft-flow-guard.sh` / `task-rule-guard.sh`) / (b) `{decision:"block", reason:...}` JSON stdout (`autonomous-action-guard.sh` / `confidence-gate.sh` / `gateguard.sh emit_block()`) と **2 pattern に分裂**しており、P2-3 の 3 severity 統一 API は本分裂を吸収する契約定義が必要。

**refinement**: `lib/block-message.sh` は 3 severity 統一 API を公開 (`emit_block` / `emit_warn` / `emit_info`)、共通引数 4 種 = **`why` / `fix_one_liner` / `bypass_env` / `docs_link`**。契約 (出力経路 × exit code × JSON decision):

| severity | output 経路 | exit code | JSON decision output |
|---|---|---|---|
| `emit_block` | JSON stdout (`gateguard.sh` L91 pattern を SSoT に統一) + stderr 4 行 (why / fix / bypass_env / docs_link) | 0 (JSON 経由で block 通知) | `{"decision":"block","reason":"<why + fix + bypass + docs 連結>"}` |
| `emit_warn` | stderr 4 行 (why / fix / bypass_env / docs_link) | 0 (fail-open) | なし |
| `emit_info` | stderr 1-2 行 (why + 任意 docs_link のみ、fix/bypass_env 無し = absorb 前提) | 0 | なし |

**`bypass_env` 引数の型**: **env var literal (例: `HC_FEATURE_SELF_DOCTOR_ENABLED=false`)** を default、自由文 fallback 可 (bypass 手順が env 単独で表現不能な hook 用、例: `/gate-bypass <slug>` command 誘導 / `ECC_TASKGUARD=off` 系)。self-doctor 既存 `silence:` label は本 `bypass_env` に **1:1 mapping** — migration 経路は `emit_warn <d_id> <title> <why> <fix> <silence>` (5 args) → 統一 API `emit_warn <why> <fix> <bypass_env> <docs_link>` (4 args) に契約変更し、`d_id` / `title` は caller 側 prefix (例: `[self-doctor] WARN D2: ...`) で吸収。self-doctor は本 lib の初回 caller として dogfood し、BLOCK / WARN / INFO を単一 SSoT で提供。Phase 1 実測の AI 教育効果 (task-87 実装知見) を P2-3 draft §根拠に転記する。

**対象**: #94 draft 起案時に本 refinement を §3 採用案に反映 (契約 table + self-doctor 5→4 args migration 経路 + `docs_link` 追加 4 引数目の位置付け含む)

#### R2: P2-1 (#92) pre-commit + P2-2 (#93) CI matrix への Phase 1 新設 smoke 群組込み

**背景**: Phase 1 で smoke 10+ 本新設 (self-doctor / install-claude-md-autofill / install-mcp-servers / hc-config-local-yml / sessionstart-footprint / sessionstart-budget / list-md-plan-first-reminder 他)。commit 境界 / CI 境界でこれらが自動実行される保証がない。

**refinement**: pre-commit は「**fast smoke (< 3 秒、`bash -n` + grep 系)**」、CI matrix は「**full smoke (< 30 秒、tmp dir 実 install 系)**」で分離。**fast/full 分離は `.claude/tests/run-all-smokes.sh` の 5 カテゴリと直交する新軸** (5 カテゴリの SSoT は `_get_smoke_category()` L46-89 = **parity / behavior / budget / portability / stale-det**、`footprint` はカテゴリ名ではなく `sessionstart-footprint-smoke` が **budget** 所属 L57-60)。Phase 1 新設 smoke 群の暫定分類 (Phase 2 #92/#93 draft 起案者は §3 にそのまま転記可):

| smoke | 5 category | fast/full | 根拠 |
|---|---|---|---|
| `self-doctor-smoke` | behavior | full | tmp dir 実 install + WARN/INFO 分類 (12 case) |
| `install-claude-md-autofill-smoke` | portability | full | tmp dir install + manifest 検出 (Case A-P) |
| `install-mcp-servers-smoke` | portability | full | tmp dir install + jq filter (10 case) |
| `install-local-yml-smoke` | portability | full | tmp dir install case A-J (assertion 追加は副産物 #80 で fold) |
| `hc-config-local-yml-smoke` | parity | fast | grep + `--get` / `--summary` 出力検証 (33 assertion) |
| `hc-config-key-parity-smoke` | parity | fast | metadata key SSoT drift |
| `enforcement-mismatch-smoke` | parity | fast | docs/config mismatch |
| `sessionstart-footprint-smoke` | budget | fast | byte count + regression 検出 |
| `sessionstart-budget-smoke` | budget | fast | tier 算出ロジック検証 |
| `list-md-plan-first-reminder-smoke` | behavior | fast | reminder 発火条件 grep |

**対象**: #92 / #93 draft 起案時に本 table を §3 採用案に転記、5 category × fast/full 2 軸の登録 rule を明示 (run-all-smokes.sh のカテゴリ拡張が必要な場合は §3 側で先行提案)

#### R3: P2-6 (#97) enforcement_matrix 拡張の残 scope 明確化

**背景**: Phase 1 Wave 1 (task-85 Step 2) で advisory disabled_reason **8 行を追記済** (既存 4 guard + review_required 4 種の advisory preset 対応)。P2-6 は matrix 未登録 hook の残 3 件 (W1-1 slip-detector / W1-5 agent-router / W1-6 loop-confirmation-detector) が主 scope として残る。

**refinement**: P2-6 の残 scope は「**matrix 未登録 hook の追加登録 (3 件) + sessionstart 系検証拡張 (副産物 #81)**」に限定。順序制約: **#97 draft 起案は #95 (P2-4 死蔵 hook 棚卸し) 完了後に着手** (残 hook 集合が #95 で確定するため、それ以前は登録 scope が不安定)。

**対象**: #97 draft 起案タイミング (#95 完了後)、§3 に advisory 記法既存 8 行との整合 template を明示

#### R4: 副産物 next-actions #78 / #80-#83 の吸収先明示

Phase 1 実装中に発生した 6 副産物 entry (#78-#83) の Phase 2/3 吸収先を確定する。

| entry | 内容 | 吸収先 | 理由 |
|---|---|---|---|
| #78 | 前セッション WIP 2 件 (install.sh settings seed copy + statusline repo 名表示) | **P2-1 (#92)** に併合 (settings seed) + 独立小タスク化 (statusline) | install.sh §6.3 拡張と file 領域近接 |
| #79 | HOTFIX-2 review LOW 3 件 + `--overwrite-all` 漏洩 | #86 (LOW 3 件)、#47 系 (漏洩) | Phase 2/3 scope 外 |
| #80 | install-local-yml-smoke case I/J false-pass (expected-preset assert 不在) | **P3-5 (#102) install smoke 自動化** | tmp dir 実 install 経路で assert 追加 |
| #81 | sessionstart-footprint FP-7 (fail-open dedicated) + FP-5 label 厳密化 | **P2-6 (#97)** or **P3-5 (#102)** | sessionstart 系検証拡張と併合 |
| #82 | install-claude-md-autofill-smoke `{{TOKEN}}` literal 残存 assertion 追加 | **P3-5 (#102)** | 1 行追加で吸収 (15 min) |
| #83 | autofill smoke Case G/N 初回起動 flakiness (fs sync 疑い) | **P2-2 (#93) CI 導入時に isolation 実装** | CI 上で intermittent FAIL 対策必須 |

**対象**: 該当 task draft 起案時に §外部依存 / §関連 entry で明示的に scope 内と宣言

**吸収完了 verification (#78-#83 各 entry 共通)**:

- 吸収先 task の draft §外部依存 or §関連 entry に本 R4 由来 fold であることを明示 (entry #番号 + 原文参照)
- 吸収完了 task の PR merge 時に `docs/tasks/next-actions.md` 該当 entry の処理結果列を `🔄 未処理` → `✅ → task-<N> (<PR#>) 完了` に更新
- 吸収先 task 完了後の `/finish-task` で next-actions.md diff を verification 対象に含める

#### R5: Phase 2 draft 起案 checklist (Phase 1 reviewer 発火 pattern の予防)

Phase 1 で頻発した reviewer 発火 pattern (draft 引用 drift / cross-file 契約不明 / fail-open 契約不記載 / DoD command 欠落 / 依存強度混同 / frontmatter 二重管理 / docs 反映漏れ) の予防 checklist。Phase 2 の 6 task 全ての draft 起案時に **`verify_dependencies` step に含める**:

- [ ] draft 引用は section 名を default (行番号は avoid、必要時のみ直近 commit hash 併記)
- [ ] 並列 subagent 前提 task は §4 実装設計に **共有契約 SSoT table** (id / symbol / API 名 / 型 / 所有者 file) を必ず記載 ([[feedback_parallel_subagent_cross_file_contract_drift]])
- [ ] 新 hook / lib は fail-open 契約を §4 に明記 (mktemp X 末尾ガード / `|| true` / subshell 化 / set flags 局所化)
- [ ] §6 DoD の全項目に **実 command** 併記 (`bash .claude/tests/xxx-smoke.sh` / `grep -c <pattern> <file> == N` の数値 assertion)
- [ ] 依存記載は **強度 (`hard` / `soft`) + 理由**付き (task-90 で「依存 = task-89 (soft, install.sh 同域編集のみ)」で drift 発生した先例)
- [ ] frontmatter `approved_at:` は 1 箇所 SSoT、本文 §承認は frontmatter 参照 pointer 化
- [ ] docs 反映 step (README / docs/INVENTORY / docs/PORTABILITY / install.sh header) を §7 Step 分解に **default 必須項目** として含める

#### R6: DAG 修正 (§7.2 は Phase 1 完遂後の state に更新)

**背景**: 現 §7.2 の DAG は Phase 1 起案時 (2026-06-18) の粗い矢印で、Phase 2 内部の順序制約と Phase 3 sink 構造が漏れている。

**refinement (Phase 2 起案時に §7.2 参照 pointer を本 §11.3 R6 に寄せる)**:

- Phase 2 内部順序制約: **#97 (P2-6 enforcement_matrix) は #95 (P2-4 死蔵 hook 棚卸し) 依存** (R3)
- Phase 2 内部 vocabulary 統合: **#94 (P2-3 BLOCK 4 引数) は self-doctor 3 点提示 lib と統合** (R1)
- Phase 3 は Phase 2 完了後 (現状維持)
- **#102 (P3-5 install smoke 自動化) が副産物 #78/#80-#83 の吸収 hub** (R4)

**Phase 2/3 個別依存の全体表 pointer**: `docs/tasks/list.md` #92-#103 の依存列参照 (#96→task-86 / #97→task-95 (本 R6 で追加) / #98→task-92 / #100→task-92 / #101→task-97 / #102→task-85+task-92 / #103→task-88+task-97)。本 addendum R6 で追加した内部順序制約は #97→#95 (R3) と #94↔self-doctor 3 点提示 lib (R1) の 2 点

### 11.4 却下事項 / 保留

**Phase 1 完遂に伴い解消済** (§1.2 R1-R7 の解消状況):

- R1 (preset verbatim copy): **解消** (task-85 で `--preset=<name>` 4 値、default = team-default)
- R2 (guard no-op 連鎖): **解消** (R1 解消で連鎖遮断)
- R3 (Loop + honor 化): **2 段解消**
  - consuming repo (team-default default) では **解消** (draft-flow-guard が BLOCK 化)
  - 本 repo (harness-dev preset) は **draft-flow-guard advisory 継続** (`enforcement_matrix.draft_flow_guard.disabled_reason` 参照)。honor system 側の follow-up は Phase 3 P3-6 (task #103 規範文書 SSoT 整合、docs↔effective pointer 化) の scope 内で構造解消
- R4 (list.md placeholder): **解消** (task-91 actionable header + reminder 2-tier)
- R5 (`/doctor` 8 issue): **解消** (task-87 self-doctor D1-D8 で機械保証)
- R6 (hc-config.sh local.yml 未読): **解消** (task-86 で全 CLI subcommand が local.yml 統合)
- R7 (`default_preset` 単独設定不発): **解消** (task-85 で preset 別 toggle 8 件セット化)

**本 addendum で扱わない項目 (別途判断)**:

- 2026-06-10 grand-summary / meta-review 系列の **post-Phase-1 followup review artifact** 起案 (5 docs 更新 or 新規 review doc 起案) は本 addendum の scope 外。Phase 2 完了後の中間 review で別途判断
- Phase 3 の I4 / I5 / I7 / I8 の詳細 refinement は Phase 2 完了後の Phase 3 起案時に別 addendum で扱う (現時点で予測 refinement は R1-R6 で十分)

### 11.5 承認欄

```
approved_at:
approver:
notes:
```

### 11.6 参照

- Phase 1 実装 PR: #68 (HOTFIX task-85) / #70 (task-86 + task-91) / #71 (task-88) / #72 (task-89 + task-90) / #73 (task-87)
- 副産物 registry: `docs/tasks/next-actions.md` #78-#83
- Phase 2/3 task 登録: `docs/tasks/list.md` #92-#103
- 関連 memory: [[feedback_subagent_staging_mv_silent_fail]] / [[feedback_parallel_subagent_cross_file_contract_drift]] / [[feedback_config_value_needs_consumer_and_smoke]]
- Phase 1 前提 task: task-70 (harness-dev preset + enforcement_matrix 導入)、task-77 (mainline_integration_policy 統治)

---

## §12. 変更履歴

| 日付 | 内容 | 起案者 |
|---|---|---|
| 2026-06-18 | 初版起案。subscbase-api install 事案を起点に 5 docs (2026-06-10 set) と統合 | main agent (claude-opus-4-7) |
| 2026-07-05 | §11 Phase 1 完遂 followup addendum 追記 (achievement / pattern / Phase 2/3 refinement 6 件 / 副産物吸収先 / reviewer checklist / DAG 修正)。§11→§12、§12→§13 に number 繰下げ | main agent (claude-opus-4-7) |

---

## §13. 承認

```
approved_at: 2026-06-18
approver: user (kfurutani@classlab.co.jp)
notes: Phase 1 から着手承認。master roadmap として list.md に 19 行先置き。
```

承認後は `slug: install-immediately-usable-redesign-20260618` を `/new-task` の入力に使い、Phase 1 から順次 task 化する。
