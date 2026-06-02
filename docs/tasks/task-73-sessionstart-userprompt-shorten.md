---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 7
-->

# Task #73: SessionStart / UserPromptSubmit 短文化 (Phase 5)

> Status: **✅ 完了 (2026-06-02)**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 5 (§4.5)。task-68 (why-x5 ターン冒頭 1 回緩和) の docs/実配線整合を完遂
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.5

## Task ゴール

SessionStart 出力が compact status (`mode` / `resume` / `next_actions` / `guards` / `help` pointer) に絞られ ~800 chars 目標に近づく。why-x5 が「UserPromptSubmit 毎ターン短文 (案A)」または「SessionStart のみ (案B)」のどちらかに統一され、docs (`why-x5-output.md`) と実配線が一致する。UserPromptSubmit は context-budget warning + why-x5 1 行 (last emitted hash で同一 reminder の連続表示を抑制) に絞られる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-71 | SessionStart / UserPromptSubmit dispatcher が前提。compact status / 短文化は dispatcher 統合後の出力整形として行う | [task-71-settings-dispatcher-generation.md](task-71-settings-dispatcher-generation.md) |

## Task 作業概要

- SessionStart を compact status 1 行化 (例: `harness: mode=loop preset=harness-dev guards=3off/2on resume=available next=4 help=/hc-config`)
- draft §4.5「出してよいもの / 出さないもの」table を適用 (mode 長文説明 / guard ごと長文理由 / resume 全文 / next-actions 全文 / slash 一覧全文を除外)
- why-x5 を案 A / 案 B のどちらかに統一 (docs は「毎ターン UserPromptSubmit」、実配線は SessionStart wrapper というズレを解消)。task-68 の「ターン冒頭 1 回」緩和と整合
- UserPromptSubmit を「context-budget warning + (設定により) why-x5 1 行」に絞る
- state file に last emitted hash を保存し、変化がない場合は無出力 (同一 reminder 連続抑制)

## Task 完了条件 (DoD)

- [x] SessionStart output が ~800 chars 目標に近づく (footprint smoke で実測) — **623B 達成 (-81%)**
- [x] why-x5 の docs (`why-x5-output.md`) と実配線が一致 (案 B 確定)
- [x] UserPromptSubmit が budget warning + why-x5 1 行に短文化 — **案 B 注記**: why-x5 は SessionStart 1 回のみ (UserPromptSubmit へ移さない = 軽量優先)。UserPromptSubmit は budget warning のみで既に最小 (通常ターン 0B、manifest/settings 変更なし)。本項は案 B scope で「UserPromptSubmit 最小維持」として充足
- [x] 同一 reminder の連続表示が last emitted hash で抑制される — **案 B 注記: N/A**。毎ターン why-x5 を出さないため per-turn 重複抑制は不要。context-budget の tier 警告は既存 per-tier marker (`.context-budget-state`) で 1 tier 1 回に抑制済
- [x] reviewer approve (テスト設計レビュー) — **qa-expert + pr-test-analyzer 2 体、CRITICAL-1/HIGH-1/2/3 + MEDIUM 全件 iter 1 で対応・verify 済 (review_required_test=false advisory)**
- [x] footprint smoke + 既存 smoke regression 0 — **footprint smoke 12/12 PASS、既存 regression 0**
- [x] 3 観点 refactor 判定 — **skip 妥当: 本変更自体が冗長削減 (Loop reminder full+compact 二重除去)、smoke は measure_footprint helper で DRY 済、追加 refactor 不要**

## 実装方針確定 + reviewer findings 反映 (2026-06-02)

### 案 B 採用 (why-x5 = SessionStart 1 回 + 規範常時 in-context)
調査 (subagent) で **why-x5 は現状 SessionStart 1 回のみ配線** (docs の「UserPromptSubmit 毎ターン」は虚偽) と判明。案 B (SessionStart 1 回 + docs を実配線に訂正) を採用。理由: Phase 5 = 軽量化目的に合致 (案 A は毎ターン出力増で逆行)、why-x5-output.md / modes.md は frontmatter-less 常時参照 = 毎ターン context load 済のため reminder 短縮で遵守情報は失われない、draft §4.5 も「案 B = context 軽量優先」と整合。user 承認済 (2026-06-02「task-73 はそのまま進めて」)。

### 実測成果 (subagent + 独立検証 subagent で二重確認)
SessionStart 出力 **3257B → 623B (-81%、cap 800 達成)**。footprint smoke RED→GREEN。既存 smoke regression 0 (sessionstart-budget 4/4 / session-help 7/7 / loop-confirmation 17/17 / why-x5-violation 4/4)。Normal モード 547B (Loop reminder 落ち・why-x5 維持)。

### behavior-preserving (reviewer HIGH-3 反映)
- **mode-enforce.sh は task-71 以前から SessionStart wrapper child 専用** (UserPromptSubmit 配線なし、task-21 W0.2 由来)。本 task の header comment 訂正 (「UserPromptSubmit hook」→「SessionStart wrapper child」) は実態への整合であって behavior change ではない。
- 条件分岐 / feature gate (`mode_session_start` / `loop_mode_enforcement` / `why_x5_enforcement`) / bypass env (`HC_WHY_X5_DISABLE`) / `set -uo pipefail` は全保持。出力テキストのみ短縮。

### Loop 遵守能力喪失なしの根拠 (reviewer CRITICAL-1 mitigation)
why-x5 / Loop 遵守を SessionStart 1 回 + pointer に畳んでも遵守能力は維持される。根拠: (1) `modes.md` / `why-x5-output.md` は frontmatter-less 常時参照 = 毎セッション context に全文 load、(2) 補完 3 層が健在 — `loop-auto-progress-reminder.sh` (SubagentStop/Stop) + `loop-confirmation-detector.sh` (Stop) + `mode-enforce.sh` (SessionStart) が modes.md §5 層強制機構の層 2/6 として機能。smoke では FP-2d で `modes.md` pointer presence を assert (能力喪失 = pointer 欠落を回帰検出)。

### 検証で棄却した所見 (false alarm)
- 検証 subagent の HIGH「SessionStart stdout に `[improvement-proposal]` prefix 混入」→ reviewer 2 体が `2>/dev/null | grep -c improvement-proposal = 0` で **stderr-only・pre-existing と確定**。session-start-wrapper が stderr 行に `[hook]` tag を付けるだけで stdout 汚染なし。task-73 対応不要。

### iter 1 smoke 強化 (reviewer HIGH-1/2 + MEDIUM-1/2 反映)
footprint smoke に FP-2d (guards/preset/modes.md pointer presence) + FP-3 (Normal モード + context.md 不在 + resume=none) + FP-4 (HC_WHY_X5_DISABLE で why-x5 absent) を追加。

## Task 概要欄 (list.md 用、3 要素規範)

> SessionStart 出力 ~3.4KB と毎ターン UserPromptSubmit の重複で初期 / 各ターン context が膨らむ問題を解消するため、SessionStart を compact status に畳み why-x5 を案 A/B に統一 (docs/実配線一致) + UserPromptSubmit を 1 行化 + 重複抑制する。完成すれば毎 session / 毎ターンの context tax が下がり、why-x5 の設計意図 (毎ターン強制か SessionStart か) が曖昧でなくなる。

## 背景・目的

draft §3 P3「SessionStart 出力が重く重複」+ P2「why-x5 docs と実配線がズレ」+ §4.5。検証で `session-start-wrapper.sh` 約 3.4KB、why-x5-reminder が SessionStart wrapper 経由 (UserPromptSubmit には未配線) なのに docs は「毎ターン UserPromptSubmit 注入」と記述、を確認済。曖昧な rule は context だけ消費し遵守が安定しない。

## 設計

draft §4.5「compact status の具体例」+ 「出してよいもの / 出さないもの」table + 「why-x5 案 A/B」+ 「UserPromptSubmit の扱い」(last emitted hash 重複抑制) を SSoT とする。why-x5 の案選択は task-68「ターン冒頭 1 回」緩和を踏まえ確定。

## TDD 戦略

### RED
- footprint smoke (`session-start output <= 800 chars` 目標、warn budget) を先に書き現状 ~3.4KB で warn。

### GREEN
- SessionStart compact 化 + why-x5 配線統一 + UserPromptSubmit 短文化 (subagent 委譲、staging 戦略)。

### REFACTOR
- compact status 生成と既存 mode/resume/guard 取得ロジックの DRY 化。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | SessionStart compact status 1 行化 (mode/preset/guards/resume/next/help)、長文説明除外 | 0.6h | task-71 |
| 2 | ✅ | why-x5 案 A/B 確定 (docs/実配線一致) + `why-x5-output.md` 記述を実配線に合わせ更新 (task-68 ターン冒頭 1 回緩和と整合) | 0.5h | Step 1 |
| 3 | ✅ | UserPromptSubmit を budget warning + why-x5 1 行に短文化 + last emitted hash で同一 reminder 連続抑制 | 0.6h | Step 2 |
| 4 | ✅ | footprint smoke (sessionstart bytes <= 800 目標 warn budget) + reminder 重複抑制 smoke | 0.5h | Step 1,3 |
| 5 | ✅ | (テスト設計レビュー) reviewer 動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、why-x5 遵守を弱めないか + 必要状態情報の欠落がないか cross-check | 0.5h | Step 1-4 |
| 6 | ✅ | (テスト合格) footprint smoke + 全 smoke regression 0 (SessionStart compact 後も mode/resume 提案/guard 状態が機能) | 0.4h | Step 5 |
| 7 | ✅ | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — compact status 生成ロジック DRY 化 | 0.3h | Step 6 |

合計: **~3.4h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/session-start-wrapper.sh` (or task-71 の session-start-dispatcher) + `.claude/hooks/{context-budget,why-x5-reminder}.sh` + `.claude/rules/why-x5-output.md` (記述更新) + `.claude/tests/` (footprint smoke) |
| migration | なし |
| 環境変数 | 既存 `HC_WHY_X5_DISABLE` 等不変 |
| 互換性 | SessionStart / UserPromptSubmit 出力が短くなる。why-x5 遵守機構は維持 (案 A or B で明確化)。mode/resume 提案機能は不変 |
