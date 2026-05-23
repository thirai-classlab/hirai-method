---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #29: Phase→Step 強制タスク構造規範

> Status: **🔲 未着手**
> 起案: 2026-05-23
> 関連: task-20 (`wave-precheck-template`、テンプレ拡張系の先行 task) / task-22 (`hook-reliability-uplift`、smoke 拡充の先行) / Phase: harness-foundation 系の structure 規範拡張
> 設計起源: [phase-step-task-structure.md](../draft/phase-step-task-structure.md) (2026-05-23 user 承認、W3 判断点 A: 規範のみ採用)

## 背景・目的

既存 `_TASK_TEMPLATE.md` は **Wave 単位** での task 分解を強制するが、Wave 内の **Step 粒度 / 完了条件 / E2E 条件 / リファクタ強制** が未規範化。結果として subagent 委譲時の acceptance criteria が曖昧 (本セッション 11 subagent median confidence 0.88、再委譲発生事案あり) / TDD GREEN → REFACTOR 規範違反 (test PASS 後にリファクタ skip 事案複数) / UI 動作未検証で「build green = 完了」誤判定 (E2E 未配線、Critical Operational Lessons HIGH「UI または frontend changes は browser 検証」未強制) が継続している。

本 task で **Phase→Step 2 階層強制 + Phase ゴール+概要必須 + Step 完了条件 (定量 or 観察可能) 必須 + 最終 Step = テスト設計レビュー → テスト合格 → リファクタリング (3 段必須、UI 含む = E2E 必須、refactor 不要なら `skip: reason` 明示記録) + 小タスクは 1 Phase+1 Step 許容** の 5 条規範を導入し、`_TASK_TEMPLATE.md` / `task-management.md` / `workflow.md` 14-stage / smoke を統合する。

> **2026-05-23 仕様変更承認**: 採用 5 条 4 を **2 段 → 3 段** に拡張。テスト設計レビュー Step を追加し、メインが 5+ reviewer を動的選定 (固定 registry 不採用、case-by-case)、並列起動、修正収束まで反復 (上限 5 回、超過時 user escalation、bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1` セッション全体)。詳細は [`docs/draft/phase-step-task-structure.md` §3 採用 5 条 4](../draft/phase-step-task-structure.md) を参照。

## 仕様（決定済）

### Q1: 適用閾値

| 案 | 内容 | 評価 |
|---|---|---|
| **A** | 全タスク強制 (閾値なし) | **採用** — user 明示決定 (2026-05-23) |
| B | 3 Step 以上のみ強制 | 不採用 — 適用基準曖昧、small fix → 大 task 昇格時に再構造化必要 |
| C | 現状維持 | 不採用 — confidence / TDD / E2E 問題が継続 |

→ **A** 採用。small fix は最小 Phase 1 + Step 1 の単一構造で吸収。

### Q2: UI 変更検出による E2E 強制

| 案 | 内容 | 評価 |
|---|---|---|
| **A** | 規範のみ (markdown で「UI 変更なら E2E 必須」記述) | **採用** — user 承認 (2026-05-23、判断点 A) |
| B | 機械強制 hook (task-rule-guard.sh で Phase 内容解析して E2E Step 存在検証) | 不採用 (別 task 化) — 本 task 範囲外、規範のみフェーズで効果観察後に検討 |

### Q3: UI 変更検出基準

→ 拡張子 (`*.tsx` / `*.vue` / `*.svelte` / `*.jsx` / `*.html` / `*.css` 等) + path (`src/components/**` / `src/pages/**` / `apps/**/components/**` 等) の **OR** 条件で過検知許容、手動 skip 記録可能。

## 設計

採用 5 条 (draft §3 規範本体):

1. **Phase→Step 2 階層必須** — 1 Phase = 1 完了 commit 単位 / 1 Step = 1 subagent 委譲 or 1 操作、最小 1 Phase + 1 Step
2. **Phase 必須項目** — ゴール (1 文、観察可能) + 作業概要 (箇条書き 3-5 件)
3. **Step 必須項目** — 内容 (1-2 文) + 完了条件 (定量 or 観察可能な事実)
4. **Phase 最終 Step = テスト設計レビュー → テスト合格 → リファクタリング (3 段必須)** — テスト設計レビュー Step でメインが 5+ reviewer 動的選定 (常時 base: tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific: UI / DB / API / 言語 / security)、並列起動、収束まで反復 (上限 5 回、超過時 user escalation、bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1`)。UI 含む Phase は E2E 必須、refactor 不要なら `skip: reason` 明示
5. **小タスク許容** — 1 Step 完結作業は単一 Phase + 単一 Step OK、テスト設計レビュー + テスト合格 (規範文書は observability check 代替) + refactor skip 記録は必須

## TDD 戦略

### RED

- `.claude/tests/task-rule-guard-smoke.sh` に新 case 追加:
  - case: template に「Phase 計画」「テスト合格」「リファクタリング」セクションが grep 確認可
  - case: 既存「Wave 構成」セクションが廃止 (or 「Phase 計画」へ rename) 確認

### GREEN

- `_TASK_TEMPLATE.md` 改訂 (Phase/Step セクション追加、Wave → Phase rename)
- `task-management.md` に §「タスク構造規範 (Phase→Step 強制)」 + §「既存 task 移行ガイド」追加
- `workflow.md` 14-stage Stage 8 / 10 / 13 から本規範への参照リンク

### REFACTOR

- smoke の重複 grep ロジックを共通関数化 (該当時のみ)
- 規範文書セクション間の cross-link を整理

## Phase 計画

### Phase 1: `_TASK_TEMPLATE.md` schema 改訂

**ゴール**: テンプレに Phase 計画セクション + Step サブセクション + テスト設計レビュー / テスト合格 / リファクタリング 3 step が定型化された雛形が組み込まれる。

**作業概要**:
- 既存 `## Wave 構成` セクションを `## Phase 計画` に rename
- 各 Phase 内に `### Step <N>: <名前>` (内容 / 完了条件) を template 化
- 各 Phase 末尾に「テスト設計レビュー」「テスト合格」「リファクタリング (skip 理由明記)」3 step を雛形固定配置
- 上部 frontmatter HTML comment に `phase_count: N` / `total_steps: M` 追加

**Step**:

- **Step 1**: subagent 委譲で `_TASK_TEMPLATE.md` を新 schema に改訂
  - 完了条件: `grep -q '## Phase 計画' .claude/templates/docs/tasks/_TASK_TEMPLATE.md && grep -q 'テスト設計レビュー' _TASK_TEMPLATE.md && grep -q 'リファクタリング' _TASK_TEMPLATE.md` exit 0
- **Step 2 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific)、並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection (修正提案 0 件)
- **Step 3 (テスト合格)**: 既存 task-rule-guard-smoke.sh で regression 0
  - 完了条件: `bash .claude/tests/task-rule-guard-smoke.sh` exit 0、全 case PASS 出力
- **Step 4 (リファクタリング)**: `skip: 単一 template file の structure 追加、refactor 対象なし`

### Phase 2: 規範文書統合 (`task-management.md` + `workflow.md`)

**ゴール**: 規範文書 2 件に Phase→Step 強制条項が追加され、14-stage workflow から参照される統合構造が完成する。

**作業概要**:
- `task-management.md` に §「タスク構造規範 (Phase→Step 強制)」追加 (採用 5 条 + bypass 経路 `ECC_PHASE_STEP_STRUCTURE_OFF=1`)
- `task-management.md` に §「既存 task 移行ガイド」追加 (active 3 件 = task-21/23/24 優先、completed 移行不要)
- `workflow.md` Stage 8 `tdd` / Stage 10 `local-test` / Stage 13 `scenario-test` から本規範への参照リンク

**Step**:

- **Step 1**: subagent 委譲で `task-management.md` Edit
  - 完了条件: 2 §セクションが grep で存在確認可、採用 5 条全項目記載
- **Step 2**: subagent 委譲で `workflow.md` Edit
  - 完了条件: Stage 8 / 10 / 13 に `task-management.md#タスク構造規範` (or 同等) への参照リンクが含まれる
- **Step 3 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific)、並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection (修正提案 0 件)
- **Step 4 (テスト合格)**: 既存 smoke 全 PASS regression 0
  - 完了条件: `bash .claude/tests/workflow-guard-smoke.sh` + `task-rule-guard-smoke.sh` 両方 exit 0
- **Step 5 (リファクタリング)**: `skip: 規範文書追記のみ、refactor 対象なし`

### Phase 3: UI 変更検出基準の文書化 (規範のみ)

**ゴール**: `task-management.md` に UI 変更検出基準と E2E 必須化判定が markdown で文書化される (機械強制は別タスク化)。

**作業概要**:
- 検出基準 §追加: 拡張子 (`*.tsx` 等) + path (`src/components/**` 等) の OR 条件
- 手動 skip 記録方法 §追加: 「UI 変更だが E2E 不要 (CSS 変更で view 影響なし等)」の例外記録 format

**Step**:

- **Step 1**: subagent 委譲で `task-management.md` に §「UI 変更検出基準」追加
  - 完了条件: `grep -q 'UI 変更検出' task-management.md` exit 0、拡張子 list + path list + skip format 記載
- **Step 2 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific)、並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection (修正提案 0 件)
- **Step 3 (テスト合格)**: markdown 整合性 (section 存在 grep)
  - 完了条件: 上記 grep が exit 0
- **Step 4 (リファクタリング)**: `skip: 文書追加のみ、refactor 対象なし`

### Phase 4: smoke 拡充 + 実適用効果実測

**ゴール**: `task-rule-guard-smoke.sh` に Phase/Step format 検証 case が追加され、本セッション内に最低 1 task で実適用して subagent median confidence ≥ 0.92 を実測する。

**作業概要**:
- `task-rule-guard-smoke.sh` 拡張 (Phase/Step section 存在検証、`phase_count`/`total_steps` frontmatter 集計)
- 本セッション内に 1 task で実適用 (推奨: task-21 W3 capability eval の Phase→Step 化)
- subagent confidence 実測 → DoD §6 達成判定

**Step**:

- **Step 1**: subagent 委譲で smoke 拡張
  - 完了条件: 新 case 追加後 `bash .claude/tests/task-rule-guard-smoke.sh` exit 0、全 case PASS
- **Step 2**: 実適用 task の Phase→Step 化 (subagent 委譲、対象は task-21 W3 or 他 active task)
  - 完了条件: 該当 task ファイルに Phase 計画セクション + 各 Phase 内 Step 構造 + 最終 Step 3 段 (テスト設計レビュー → テスト合格 → リファクタリング) が存在
- **Step 3 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + domain-specific)、並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection (修正提案 0 件)
- **Step 4 (テスト合格)**: 全 smoke PASS + subagent confidence 実測
  - 完了条件: 全 smoke exit 0 (regression 0) + Step 2 subagent confidence ≥ 0.92
- **Step 5 (リファクタリング)**: smoke の重複 grep ロジック共通化
  - 不要なら `skip: smoke case 数少なく duplication なし、refactor 対象なし` で OK

## 完了条件

- [ ] `_TASK_TEMPLATE.md` に Phase/Step セクション + テスト設計レビュー / テスト合格 / リファクタリング 3 step 固定が追加済
- [ ] `task-management.md` に §「タスク構造規範 (Phase→Step 強制)」+ §「既存 task 移行ガイド」+ §「UI 変更検出基準」が追加済 (採用 5 条 4 は 3 段必須 + テスト設計レビュー 5+ 動的選定 + 5 回上限を明文化)
- [ ] `workflow.md` 14-stage の Stage 8 / 10 / 13 から本規範への参照リンク追加済 (Stage 8 cell に「3 段必須」記載)
- [ ] `task-rule-guard-smoke.sh` で Phase/Step format 検証 case 追加 + テスト設計レビュー 3 段化検証 case 追加 + 全 PASS
- [ ] 本セッション内に最低 1 task で実適用、subagent median confidence ≥ 0.92 実測
- [ ] regression 0 (既存 smoke 全 PASS)

## 工数見積

合計 2.4-3.0 工数 (Phase 1: 0.5 / Phase 2: 0.4 / Phase 3: 0.4 / Phase 4: 0.7、加えて regression 検証 0.4)。

W3 (Phase 3) は規範のみ採用で 0.4 工数固定 (機械強制 hook 案は別タスク化済)。

> **2026-05-23 仕様変更による工数調整**: 採用 5 条 4 の 3 段化 (テスト設計レビュー追加) で各 Phase の最終 Step が 1 増、1 Phase あたり +0.1〜+0.2 工数加算。テスト設計レビューの反復 5 回上限 + 動的 reviewer 選定の cost を考慮し +0.5〜+0.6 増。

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` (Phase 1) / `.claude/rules/task-management.md` (Phase 2-3) / `.claude/rules/workflow.md` (Phase 2) / `.claude/tests/task-rule-guard-smoke.sh` (Phase 4) |
| migration | 既存 task 6 件 (task-21 / 23 / 24 / 27 / 28 + 本 task) は Phase 2 §「既存 task 移行ガイド」に従い個別 task 着手時に Phase→Step 形式に再構造化 (本 task では移行ガイド文書化のみ、実適用は task-21 等の着手時) |
| 環境変数 | `ECC_PHASE_STEP_STRUCTURE_OFF=1` (bypass、hot fix 用) |
| 互換性 | 既存 task ファイル (task-1〜task-28) は Wave 構成のまま残存、本 task 完了後に着手する task のみ Phase→Step 形式必須 |

## 再発防止

- Phase 4 で実装する `task-rule-guard-smoke.sh` 拡張で新規 task の Phase/Step format 不備を検出
- 機械強制化 (PreToolUse hook で Phase/Step 構造を検証して BLOCK) は本 task 範囲外、別タスク化候補 (規範のみフェーズの効果観察後に判断)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-23 | 起案 | draft 起こし `docs/draft/phase-step-task-structure.md` |
| 2026-05-23 | 承認 | user 承認、W3 判断点 A: 規範のみ採用、`list.md` に追加 |
| 2026-05-23 | 仕様変更 | 採用 5 条 4 を 2 段 → 3 段に拡張 (テスト設計レビュー追加、5+ 動的選定 + 5 回上限、bypass `ECC_TEST_DESIGN_REVIEW_OFF=1`)。5 file (task-management.md / _TASK_TEMPLATE.md / draft / 本 task / workflow.md) に patch 反映 |
| YYYY-MM-DD | 着手 | branch (未定、`feat/phase-step-task-structure` 候補) |
| YYYY-MM-DD | 完了 | commit `<sha>`、+<N> tests |

## 派生 task / 次アクション候補

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

- 副産物発見の瞬間に **必ず本セクションに記入** (memory / 会話履歴に流すだけは禁止)
- task 完了 (`/finish-task`) 時、本セクションのすべての entry が以下のいずれかに処理済であること:
  - (a) `docs/draft/<slug>.md` に draft 起こし済 (緊急度 🔴 / 🟡)
  - (b) `docs/tasks/next-actions.md` に entry 追加済 (緊急度 🟢 + 後日判断)
  - (c) 無視 (理由を明記、commit message に記録)

### 起案時点で予測される派生 task 候補

- [ ] (🟡) UI 変更検出の機械強制 hook 実装 — 本 task では規範のみフェーズ採用、効果観察後に W3 判断点 A の B 案 (機械強制 hook) を別タスク化検討
- [ ] (🟢) 既存 task 6 件 (task-21 / 23 / 24 / 27 / 28) の Phase→Step 形式への実適用移行 — 本 task では移行ガイド文書化のみ、各 task の次回着手時に個別実装

### 関連

- [`next-actions.md`](next-actions.md) — 本セクションと連動する registry
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「副産物発生時の即時 draft 起こし義務」

## 関連

- Draft: [phase-step-task-structure.md](../draft/phase-step-task-structure.md)
- 依存タスク: task-20 (`wave-precheck-template`、テンプレ拡張系の先行) / task-22 (`hook-reliability-uplift`、smoke 拡充先行)
- 派生タスク: 機械強制 hook 案 (未起案、本 task 完了後に効果観察) / 既存 task 移行 (5 件)
- 関連 feedback memory: `feedback_chat_list_output_as_table.md` (2026-05-23、リスト視認性のテーブル化規範) — Phase→Step 構造提示時もテーブル形式で表現する規範と整合
