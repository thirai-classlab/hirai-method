<!--
task-21 W1.7: paths 条件付き受動 load を廃止し、常時参照 rule に格上げ。
task-26 W4: 設計→承認→タスク追加フロー / メイン専任 / Parking Lot の SSoT として確立。
task-29 Phase 2+3 (2026-05-23): Phase→Step 規範化。
2026-05-25 採用 6 条 (Task=Phase=N Step) で task-29 採用 5 条を supersede。
task-51 Step 3 (2026-05-28): Layer A/B 2 層分割。
task-67 Step 3 (2026-06-01): Layer B 断片化、Layer A pointer 直リンク化。
-->

# タスク管理ルール

本 rule は **メイン専任 / 採用 6 条 (Task=Phase=N Step) / 設計→承認→タスク追加フロー / plan-first 行先置き 2 経路 / 開発開始時必読義務 / parking-lot 運用** の SSoT。常時参照 (frontmatter 無し、毎セッション AI が読む)。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: 各 § 末尾 pointer から該当断片を直リンク Read (断片群: [`../rules-details/task-management/`](../rules-details/task-management/))

## bypass env naming convention (SSoT)

本 harness の全 bypass env は **2 系統に分離** され、用途・痕跡・スコープが明確に区別される。各規範文書 (`task-management.md` / `workflow.md` / `modes.md` / `development-process.md`) の bypass table はこの規約に従う。

| prefix | 系統 | 用途 | 痕跡 |
|---|---|---|---|
| `ECC_*` | env 系統 | 1 セッション限定 bypass、操作の audit trail を `.claude/.workflow-state/bypass.log` に append | bypass.log |
| `HC_*` | config 系統 | feature toggle / yml override (`harness-config.yml` 経由で永続化される可能性あり) | yml + bypass.log (一部) |

両系統併存は意図的 (env 系統と config 系統から独立に bypass 可能、片方の誤った enabled 状態放置を防ぐ)。

## メインエージェント専任（必須）

タスク管理はメインエージェントのみが行う。サブエージェントにタスク管理を委譲してはならない。

- `docs/tasks/list.md` のステータス更新 → メインが必ず実行
- 個別タスクファイルの作成・更新 → メインが必ず実行
- サブエージェント起動前にタスクを「進行中」に更新
- サブエージェント完了後にタスクを「完了」に更新

## タスク構造規範 — 採用 6 条 (Task=Phase=N Step、Phase 中間階層廃止)

**起源**: 2026-05-25 採用、`docs/draft/task-equals-phase-step-status-list-normative.md`。task-29 採用 5 条を supersede。Phase 中間階層を廃止し「Task = Phase = N Step」の 2 階層に圧縮。

### 採用 6 条 (条文)

1. **Task = Phase = N Step (2 階層、Phase 廃止)** — 1 task は 1 Goal + N Steps。Phase / Wave / Sub-Phase 等の中間階層は禁止。既存 Wave / Phase 構造は次回着手時に再構造化。

2. **Task 必須項目 (5 件)**: 「**ゴール** (1 文、観察可能)」+ 「**作業概要** (箇条書き 3-5 件)」+ 「**完了条件** (定量 or 観察可能な事実、DoD)」+ 「**概要欄** (list.md 用、「**何のため × 何をやる × 何ができるようになる**」3 要素必須)」+ 「**依存先タスク** (`task-N1, task-N2` 形式で ID 列挙、依存なしは `—`、空欄禁止 + Task header section に **影響内容 + 依存先 task.md リンク** 記載)」。`/start-task` 直後に依存先 task.md + 関連 draft を **必ず Read** (§「開発開始時の必読義務」)。

3. **Step 必須項目 (4 件)**: 「**作業概要** (1-2 文 actionable)」+ 「**完了条件** (再現可能な検証コマンド)」+ 「**Step status** (📝/🔲/🔄/✅/⏸️)」+ 「**概要欄** (list.md 用、**作業概要のみ**、3 要素不要)」。

4. **Task 最終 = テスト設計レビュー → テスト合格 → リファクタリング (3 段必須)**:
   - **テスト設計レビュー**: メイン agent がテスト設計を分析 → reviewer を **`review_min_count_test`〜`review_max_count_test` の範囲で動的選定** (`tdd-guide` / `test-automator` / `qa-expert` / `pr-test-analyzer` base、UI/DB/API/言語/security で加味)。**起動前に必ず `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限を確認し、並列起動数 N が `min ≤ N ≤ max` に収まることを保証する** (`review_required_test: false` なら本 step skip 可、青天井「5+」は廃止 = task-64) → 並列起動 (`run_in_background: true`) → 修正提案集約 → 再起動。**収束条件**: 全 reviewer approve / no objection。**反復上限**: `review_iteration_max` (`hc-config.sh --get review_iteration_max` で確認、default 5、`ECC_TEST_DESIGN_REVIEW_OFF=1` で bypass)。値解決順: `env(HC_REVIEW_*)` > `harness-config.local.yml` > `harness-config.yml` > default。reviewer prompt は [workflow.md §reviewer prompt 共通規約](./workflow.md) 5 必須項目 (対象 Read / 観点 / findings format / confidence / **プロジェクト整合性 + 他 task 影響確認**) を必ず含める (2026-05-28 追加、`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` で bypass 可だが採用 6 条 4 初回 round-1 は NG ケース)。
   - **テスト合格**: UI 含 Task → **E2E 必須 + ビジュアル検証必須** (agent-browser skill で screenshot、主要 breakpoint / 状態 / theme 撮影)。UI なし → unit/integration PASS で OK。terminal TUI 対象外。
   - **リファクタリング**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点。不要なら `skip: <reason>` 明示記録。

5. **小タスク許容**: hot fix / typo 修正 / config 1 行追加 等は「1 Task + 1 Step」OK。条 4 の最終 3 Step は「1 Step 内に test + refactor 判定を併記」で代替可。

6. **list.md 表現規約 (6 列、2026-05-26 依存先列追加)**:
   - **column**: `# | Step Status | Task / Step | 概要 | 依存先 | 詳細`
   - **Task header row**: `| <id> | <集約 status> | **Task: <名>** | <Task 概要 3 要素> | <依存先 ID or —> | [task-<id>-<slug>.md] |`
   - **Step sub-row**: `|    | <Step status> | Step N | <作業概要> | | |` (#列 + 依存先列空)
   - **集約 status**: 全 ✅ → ✅、🔄/🔲 混在 → 🔄、全 🔲 → 🔲、全 📝 → 📝、⏸️ 含む → ⏸️
   - **status 凡例**: SSoT は直下の Step status emoji 凡例 mini-table 参照 (5 種限定: 📝🔲🔄✅⏸️)
   - **概要欄 2 種規約**: Task = 3 要素 (purpose × work × outcome) / Step = 作業概要のみ

> **Step status emoji 凡例 (SSoT)**: 📝 設計未承認 / 🔲 未着手 / 🔄 進行中 / ✅ 完了 / ⏸️ 保留 — 本 harness の全 rule / template / list.md / task.md で本 5 種のみ使用。他の emoji (例: 🟢 🟡 🔴 等) は緊急度や別軸用途で混同禁止。

> **3 観点 (リファクタリング、採用 6 条 4)**: 持続可能性 (Sustainability) / 汎用性 (Generality) / 非冗長化 (Deduplication)。詳細 sub-checklist は [`workflow.md`](./workflow.md) §「リファクタリング強制 (W3)」参照。

> **OK/NG 例詳細 (条 2/3/6) / task-29 採用 5 条 supersede 経緯**: [task-management/six-articles.md](../rules-details/task-management/six-articles.md)

### bypass

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| Task=Phase 構造強制無効化 | `ECC_PHASE_STEP_STRUCTURE_OFF=1` | 1 セッション | `.claude/.workflow-state/bypass.log` |
| テスト設計レビュー (条 4) 無効化 | `ECC_TEST_DESIGN_REVIEW_OFF=1` | 1 セッション | `.claude/.workflow-state/bypass.log` |

honor system: bypass 時は理由を CLAUDE.md or `docs/tasks/<task-N>.md` に記録。機械強制 hook は本規範採用フェーズでは未実装。

## 開発開始時の必読義務 (2026-05-26 採用)

採用 6 条 2 の **依存先タスク** を実効化するため、Task 開発開始時 (`/start-task <id>` 直後) に以下を **必ず Read**。

### 必読対象

| 対象 | 読み方 |
|---|---|
| **本 task の `docs/tasks/task-<id>-<slug>.md`** | 全文 Read |
| **本 task の `docs/draft/<slug>.md`** (存在時) | 全文 Read |
| **依存先 task の `docs/tasks/task-<N>-<slug>.md` 全件** | Task ゴール + 完了条件 + 影響範囲を最低限 Read |
| **依存先 task の `docs/draft/<dep-slug>.md`** (存在時) | 採用案 + リスク sections を Read |

### 例外

- **依存先 0 件**: 本 task の task.md + draft.md のみで OK
- **小タスク (1 Task + 1 Step、条 5)**: 本 task ファイルのみで OK
- **依存先が parking-lot の 🧊 / ❌**: 履歴として Read 推奨

違反検出は当面 honor system (main agent が Why × 5 で必読宣言)、将来 `task-rule-guard.sh` 拡張で warn 注入予定。

> **必読義務の起源 (2026-05-26 user 指示) / 効果 3 層 (list.md DAG + task.md 影響内容 + 開始時 Read 強制)**: [task-management/mandatory-reading.md](../rules-details/task-management/mandatory-reading.md)

## 既存 task 移行ガイド

**適用範囲**: 2026-05-25 以降の新規 task のみ採用 6 条必須。それ以前は段階移行。

| 世代 | 採用規範 | 既存 task | 扱い |
|---|---|---|---|
| **G1 (Wave、〜2026-05-23)** | 自由 Wave 構成 | task-1〜20 + 22/25/26 | 移行不要、履歴保持 |
| **G2 (Phase→Step、2026-05-23〜25)** | task-29 採用 5 条 | task-21/23/24/27/28/29〜32/33 | 次回着手時に新採用 6 条へ再構造化推奨 (honor system) |
| **G3 (Task=Phase=N Step、2026-05-25〜)** | 新採用 6 条 | task-34〜 | 必須適用 |

> **移行優先度 task 個別 table / task-33 即 restructure 経緯**: [task-management/task-migration.md](../rules-details/task-management/task-migration.md)

## UI 変更検出基準

採用 6 条 4 の「UI 含 Task は E2E + ビジュアル検証必須」発動判定。本規範採用フェーズでは **手動運用** (機械強制 hook は future work)。

### 判定基準 (OR 条件、過検知許容)

- **拡張子**: `*.tsx` / `*.jsx` / `*.vue` / `*.svelte` / `*.html` / `*.css` / `*.scss` / `*.sass` / `*.less`
- **path**: `src/components/**` / `src/pages/**` / `src/app/**` / `apps/**/components/**` / `apps/**/pages/**` / `components/**`

### 検出コマンド (手動)

```bash
git diff --name-only <base>...HEAD | grep -E '\.(tsx|jsx|vue|svelte|html|css|scss|sass|less)$|^(src|apps/[^/]+)/(components|pages|app)/|^components/'
```

### 手動 skip format

UI 変更だが view 影響なし時、Step 完了条件に明示:

```
完了条件: skip: UI 変更だが view 影響なし (CSS 変数 rename のみ、レンダリング結果同一)
```

> **機械強制 hook 案 (future work) 詳細**: [task-management/ui-detection.md](../rules-details/task-management/ui-detection.md)

## 設計→承認→タスク追加フロー（必須）

**設計なしのタスク追加は禁止**。下記 4 ステップ厳守:

> **Loop モードでも本フローは免除されない** (task-21 W2.2)。`modes.md` 遵守事項 2 例外条項参照。`draft-flow-guard.sh` が機械強制で BLOCK。

1. **テンプレ初期化** (SessionStart hook で自動、明示は `/init-tasks`)
2. **設計起こし**: `/new-draft <slug>` で `docs/draft/<slug>.md` 生成 → §1〜9 を埋める
3. **承認依頼**: user レビュー・承認、履歴を draft §8 に記録
4. **タスク化**: `/new-task <id> <slug>` で `task-<id>-<slug>.md` 生成 + list.md 行追加 (📝 既存 → 🔲 update、不在なら append)

### plan-first 行先置きフロー (batch planning) — 2 経路分岐 (task-33 規範化、2026-05-25)

| 経路 | 用途 | 手順 |
|---|---|---|
| **A (単発、default)** | hot fix / 1 機能 / 副産物 entry 由来 | 1 task ずつ draft 起案 → 承認 → `/new-task` で 1 行 append |
| **B (batch planning)** | master roadmap で N 個 task を一括計画 (N ≥ 3) | (1) master roadmap §plan で N task 確定 + 承認 → (2) main が list.md に N 行 📝 先置き → (3) 個別 draft 起案 (subagent 並列可) → (4) `/new-task` で 📝 → 🔲 update |

#### 経路 B 適用判定 (3 基準、OR)

- master roadmap で **N ≥ 3 個 task 一括計画** (機械検出: SessionStart hook で `draft ≥ 3 ∧ task 行 == 0`)
- 全 task 完了まで複数セッション跨る見込み (honor system)
- task 間に強い順序依存 / Phase 区分 (honor system)

#### 凡例 📝 の 2 用途

| 用途 | 状態 |
|---|---|
| (1) draft 起案中 / user 承認待ち | 単発 task の `/new-task` 前中間状態 (経路 A) |
| (2) batch plan 計画段階先置き | master roadmap 承認済 N task の list.md 先置き (経路 B) |

両用途で `/new-task` 実行時に 🔲 に update。

> **経路 B ID 払い出し / 重複検知 / Loop モード整合 / 機械検出 hook フィルタ順序注意 / 起源 (recall_poc plan-first 不在事案)**: [task-management/plan-first.md](../rules-details/task-management/plan-first.md)

### テンプレート

- `.claude/templates/docs/tasks/list.md` / `parking-lot.md` / `_TASK_TEMPLATE.md`
- `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md`

### 自動生成のセーフティ

- **冪等**: 既存 file は上書きしない (`/init-tasks --force` のみ例外)
- **ID 重複検知**: `/new-task` は同 ID 既存で中断
- **設計欠落検知**: `/new-task` は対応 draft 不在で中断 (`--no-draft` で hot fix 例外)
- **fail-open**: SessionStart hook 失敗もセッション継続

### Hook による強制 (PreToolUse、`task-rule-guard.sh`)

| シナリオ | 動作 |
|---|---|
| `task-<id>-<slug>.md` Write、対応 draft 不在 | **BLOCK** |
| `task-<id>-*.md` / `phase-<id>-*.md` Write、同 ID 既存 | **BLOCK** |
| `docs/tasks/` 命名規約外 Write | 警告 context 注入 |
| `task-*.md` Edit (既存編集) | 「list.md 同期更新せよ」context 注入 |
| `parking-lot.md` Edit | 必須 7 項目の hint 注入 |
| `list.md` / `_*_TEMPLATE.md` Edit/Write | exempt |
| サブエージェント実行中 | 全パス通過 |

### Bypass

| 方法 | 用途 |
|---|---|
| `ECC_TASKGUARD=off` | セッション全体 OFF |
| `/task-bypass <slug>` | 1 file 分 pre-clear |
| `/task-bypass --clear-all` | 全 marker 削除 |

> **Hook 検出仕様詳細 / subagent 通過理由 / 違反パターン例**: [task-management/hook-enforcement.md](../rules-details/task-management/hook-enforcement.md)

## チェックリスト

タスク追加時の確認:

- [ ] `docs/draft/` に設計ドキュメントが存在するか
- [ ] user 承認を得たか
- [ ] `docs/tasks/list.md` の一覧テーブルを更新したか
- [ ] 個別タスクファイルを作成したか
- [ ] 設計ドキュメントへのリンクを含めたか
- [ ] task ファイルが採用 6 条 (Task=Phase=N Step) に準拠しているか

## 承認されていない設計

未承認設計は `docs/draft/` に置く。承認済のみ `docs/tasks/` にリンク可。

## Parking Lot（今後検討タスク）

着手不可保留タスクは [`docs/tasks/parking-lot.md`](../../docs/tasks/parking-lot.md) で管理。

- **追加条件**: 既存設計書 or `docs/draft/` 承認済設計へのリンク必須 (設計なし追加禁止)
- **必須項目 7 つ**: 起案日 / 保留日 / 保留理由 / 設計書 / 実装状態 / 再検討トリガー / 代替現状
- **status**: 🧊 保留 / 🔍 再検討予定 / ❌ 不採用
- **移行**: 再検討トリガー成立時に `parking-lot.md` から削除 → `list.md` に新規 task 追加 (`/new-task`)
- **定期レビュー**: 🔍 entry は四半期見直し
- **不採用**: ❌ entry は削除せず履歴保持

`list.md` 冒頭に parking-lot.md リンクを明記し、全タスク台帳として発見可能にする。

> **必須 7 項目 format / 定期レビュー手順**: [task-management/parking-lot.md](../rules-details/task-management/parking-lot.md)

## タスク管理の関連コマンド

| コマンド | 役割 |
|---|---|
| `/init-tasks` | 台帳テンプレ初期化 (SessionStart 自動) |
| `/new-draft <slug>` | 設計 draft 起こし |
| `/new-task <id> <slug>` | タスク化 + list.md 行追加 |
| `/start-task <id>` | 着手 (branch 切替 + status 同期) |
| `/finish-task <id>` | 完了 (検証 + done 化 + commit 提案) |
| `/task-bypass <slug>` | task-rule-guard 1 file 分 bypass |

> **各規範の起源 / 採用経緯 (task-21 W1.7 / task-26 W4 / 採用 6 条 supersede 経緯 / plan-first 規範化)**: [task-management/origin.md](../rules-details/task-management/origin.md)
