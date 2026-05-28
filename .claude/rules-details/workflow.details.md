---
paths: []
related: workflow.md
---

# Workflow Enforcement — 詳細版 (Layer B)

> Layer A: [`workflow.md`](../rules/workflow.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

本 file は Layer A の SSoT を補完する詳細解説。14-stage / 10-stage 各 stage の連携 command 詳細 / draft-flow-guard 緩和履歴 (旧 task-40 拡張撤廃) / リファクタリング 3 観点の sub-checklist / 20 MECE カテゴリ各論 / fan-out reviewer-registry stack heuristic 詳細 / 副産物 5 層処理フロー / Session 永続化の Serena 必須化詳細 / 関連 skill 完全 list / 起源を含む。Read trigger 4 条件は Layer A 冒頭参照。

## 14-stage 詳細

### Stage 8 `tdd` の git log 既存 commit 確認義務

- **Step 計画前に `git log --all --grep <finding>` で既存 commit 解消確認必須** (2026-05-21 TM 修正での no-op 重複起動再発防止)
- **Task 最終 3 Steps = テスト設計レビュー → テスト合格 → リファクタリング (固定)**:
  - テスト設計レビューは 5+ reviewer 動的選定 + 修正収束まで反復 + 5 回上限
  - bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1`
  - 詳細: [task-management.md §タスク構造規範](../rules/task-management.md#タスク構造規範-taskphasen-step-phase-中間階層廃止) 採用 6 条 4 [2026-05-25 採用]
  - 旧採用 5 条 4 を supersede

### Stage 10 `local-test` の Step 完了条件検証

- `<slug>.test-design.md` で ☑ にしたテスト全カテゴリを実行
- **Step 完了条件 (定量 or 観察可能事実) で test 結果を検証** (採用 5 条 3 起源)
- 検証コマンドは「`bash .claude/tests/foo-smoke.sh` exit 0」のように再現可能な形で書く

### Stage 13 `scenario-test` の UI 必須化

- **UI 変更を含む Task は E2E 必須** (検出基準: [task-management.md §UI 変更検出基準](../rules/task-management.md#ui-変更検出基準))
- 採用 6 条 4 [2026-05-25 採用、旧採用 5 条 4 supersede] でビジュアル検証も併設必須化 (2026-05-27 採用、`agent-browser` skill + screenshot)
- E2E (機能フロー動作) とビジュアル検証 (見た目) は別レイヤ、両方 PASS で初めて UI Task 完了

### Stage 12 `ci-cd` の skip 条件

- `asana_enabled=false` プロジェクトは default skip
- skip した場合は state JSON の `skip_log` に `{stage: "ci-cd", reason: "asana-disabled", user_approved_at: <ISO-8601>}` を append

## 10-stage 詳細

### Stage 7 `tdd` の git log 検証

- **Wave 計画前に `git log --all --grep <finding>` で既存 commit 解消確認必須** (2026-05-21 TM 修正での no-op 重複起動再発防止)

### `/new-feature` との差分詳細

- 要件定義 (Stage 1 `requirements`) → 不要 (既存機能の修正のため)
- `design-review` (Stage 5 fan-out レビュー) → 不要 (差分のみ retest-design で再評価)
- `task-creation` (Stage 7 task-creation) → branch-decision + checkout で代替
- `ci-cd` (Stage 12) → 不要 (既存 CI 流用)
- `scenario-test` (Stage 13) → full-test (Stage 9) で代替

代わりに以下が入る:
- `recover-design` (Stage 3) — 既存 task / draft を探索、不完全なら逆引き起こし
- `pre-test` (Stage 4) — 修正前 baseline 記録
- `retest-design` (Stage 6) — 差分部 MECE 再評価

詳細比較は [`modify-feature.md`](../commands/modify-feature.md) の「/new-feature との差分」セクション参照。

## draft-flow-guard 緩和履歴

### 2026-05-28 緩和 (task-40 拡張の撤廃)

旧 task-40 拡張 (2026-05-26) は `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への **新規 Write** も draft 承認 (`approved_at` / `retroactive`) 不在で BLOCK していた。

user 指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」により、これらの規範文書 path は **新規 Write / 既存 Edit とも PASS** に緩和。本 hook はもはや `.claude/rules/` / `.claude/commands/` / `.claude/templates/docs/` を一切監視しない。frontmatter parser (`extract_frontmatter_value` / `verify_draft_status`) + 新 path pattern 判定 + retroactive 厳格化ロジックは hook から削除済。

### 規範変更時の hook 役割 (緩和後)

| シナリオ | 動作 |
|---|---|
| `.claude/rules/<basename>.md` / `.claude/commands/<basename>.md` / `.claude/templates/docs/**/<basename>.md` の **新規 Write / 既存 Edit** | **PASS (Edit 同様、2026-05-28 user 指示で緩和)** — 旧 task-40 拡張 (draft 承認不在で BLOCK) を撤廃 |
| `docs/` 直下の既存 file の Edit | **PASS** — 新規 Write のみ block 対象 (`if [ -f "$file_path" ]; then exit 0; fi`) |
| `docs/` 直下への新規設計文書 Write、対応 draft 不在 | **BLOCK** — 「先に `/new-draft <slug>` で設計を起こせ」(元機能、不変) |

### 規範変更の honor system 降格

機械強制 BLOCK は本緩和で解消されたため、規範変更の draft 経由フローは **honor system に降格**:
- `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への新規 Write / 既存 Edit は user 確認必須 / 設計→承認フロー推奨 (規律として残す方針)
- `docs/` 直下の設計文書 block は維持 (機械強制 BLOCK)

### 起源

- 2026-05-26 task-40 で `.claude/rules/*.md` 等の規範文書も draft 経由必須化 (機械強制 BLOCK)、設計起源: `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md`
- 2026-05-28 緩和: user 直接指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」で task-40 拡張部分 (規範文書 path の新規 Write block) を撤廃
- 関連: [`task-management.md`](../rules/task-management.md) §「設計→承認→タスク追加フロー」/ [`modes.md`](../rules/modes.md) 遵守事項 2 例外条項「規範変更」

## リファクタリング 3 観点詳細

### review prompt 規約 (`/module-review` `/system-review` 共通)

- **behavior-preserving 必須** — public API / DB schema 変更禁止
- **全 finding に修正コード提案** — finding だけでなく具体的な patch 候補を併記
- **末尾 `confidence: 0.X`** — F3 抽出対象 (`confidence-gate.sh` で閾値 0.6 未満は block)
- 詳細は [`module-review.md`](../commands/module-review.md) Phase 3 参照

### 持続可能性 (Sustainability) sub-checklist

- 命名 (camelCase / PascalCase / 意味的に明確か)
- 関数 50 行以内 / ファイル 800 行以内 / ネスト 4 階層以内
- magic number 排除 (定数化)
- 副作用局所化 (pure function 優先)
- 型注釈 (TypeScript / Python type hint)
- silent failure 排除 (error handling 明示)

### 汎用性 (Generality) sub-checklist

- 引数化可能性 (hardcoded value を parameter 化)
- 1 callee 特化排除 (汎用化推奨)
- idiom 準拠 (言語別 idiom: Go の error handling / Rust の Result 等)
- 抽象依存 (interface / trait 経由)
- test seam (mock 注入可能性)

### 非冗長化 (Deduplication) sub-checklist

- DRY (重複ロジック抽出)
- table-driven 化 (switch / if-else 連鎖を data 化)
- util/helper 再発明排除 (既存 utility 流用)
- 既存型流用 (重複 type 定義排除)
- over-engineering 排除 (YAGNI)

### system-level 観点 (`/system-review`) sub-checklist

1. **モジュール間重複** — module 横断 DRY (`/module-review` は module 内 DRY のみ)
2. **横断的責務漏れ** — logging / error handling / observability / rate limiting / authn-authz の一貫性
3. **設計乖離** — `docs/draft/<slug>.md` §3 採用案からの逸脱 / `<slug>.test-design.md` ☒ テストが誤実装されていないか / §6 DoD 充足

### MEDIUM / LOW のみ残存時の skip フロー

- MEDIUM / LOW のみが残存する場合は user 承認のうえ `skip_log` に記録すれば pass 可能 (運用判断)
- skip 記録 format: `{stage: "module-review", reason: "<LOW finding ID 列挙> user approved low-priority", user_approved_at: <ISO-8601>}`

## 20 MECE 各論

### 各カテゴリの採用 / 不採用判定例

| # | カテゴリ | 採用例 | 不採用例 |
|---|---|---|---|
| 1 | 単体 | 全機能で原則 ☑ | 純粋 UI prop drilling のみ → `not-applicable` |
| 2 | 統合 | API + DB 連動 → ☑ | 単一 module 完結 → `scope-excluded` |
| 3 | E2E | UI 変更含む Task → 必須 ☑ | backend 専用 task → `scope-excluded` |
| 4 | DB | migration 含む → ☑ | DB 触らない → `not-applicable` |
| 5 | 境界値 | numeric range / string length 制約あり → ☑ | enum 固定値のみ → `accepted-risk` |
| 6 | 異常系 | error handling 重要 → ☑ | happy path 確認 task → `scope-excluded` |
| 7 | 回帰 | 既存機能修正 task は必須 ☑ | 完全新規機能 → `not-applicable` |
| 8 | カバレッジ計測 | 大規模 module → ☑ | 1 file 数十行 → `scope-excluded` |
| 9 | 網羅性検証 | enum / discriminated union → ☑ | bool flag のみ → `not-applicable` |
| 10 | 完全性検証 | invariant 強い構造 → ☑ | 柔軟性優先設計 → `accepted-risk` |
| 11 | 性能 | response time SLA → ☑ | 内部 utility → `not-applicable` |
| 12 | 負荷 | 高 throughput endpoint → ☑ | 管理画面 → `accepted-risk` |
| 13 | セキュリティ | 認証 / 認可 / 入力検証 → ☑ | 内部 helper → `not-applicable` |
| 14 | 互換性 | 公開 API / DB schema → ☑ | private module → `not-applicable` |
| 15 | アクセシビリティ | UI 含む → ☑ | backend → `not-applicable` |
| 16 | i18n | 多言語対応 product → ☑ | 内部 tool → `scope-excluded` |
| 17 | smoke | 重要 happy path → ☑ | edge case のみ → `existing-coverage` |
| 18 | シナリオ | user flow 重要 → ☑ | unit-level fix → `scope-excluded` |
| 19 | chaos・障害注入 | 高可用性要求 → ☑ | 内部 tool → `accepted-risk` |
| 20 | 契約テスト | microservice 跨ぎ → ☑ | monolith → `not-applicable` |

### 3 agent 投票による default 判定

- 3 agent 中 **2 以上が採用推奨** → デフォルト ☑
- 3 agent 中 **2 以上が不採用推奨** → デフォルト ☒
- **意見割れ (1-1-1)** → ☐ + コメント「user 判断要」

## fan-out reviewer-registry 詳細

### stack heuristic 絞り込み

draft 本文を grep して以下キーワードを検出し、不要な reviewer を除外:

- `database` / `migration` / `RLS` 不在 → database-reviewer skip
- `API` / `endpoint` / `REST` / `GraphQL` 不在 → api-designer skip
- `UI` / `component` / `frontend` 不在 → ui-designer skip

`--skip-stack-filter` で全件起動、`--max-reviewers N` で上限指定可。

### 集約フォーマット

各 reviewer の SubagentStop 通知を受けたら findings を `docs/draft/<slug>-review.md` に append:

```markdown
## <reviewer-name> (iter <N>)
- [CRITICAL] <finding summary> — <修正コード提案>
- [HIGH] <finding summary> — <修正コード提案>
- [MEDIUM] <finding summary> — <修正コード提案>
- [LOW] <finding summary>

confidence: 0.X
```

全件完了後に severity 別件数サマリ表 + blocking findings (CRITICAL / HIGH / MEDIUM) + 各 reviewer の confidence score 一覧を提示。

### reviewer 最低数 3 体の理由

- 1 体 → 偏り過大 (1 視点のみ)
- 2 体 → 同意 / 不同意の二択判定不能 (合議制成立せず)
- 3 体 → 過半数判定可能 (2-1 で多数決成立)
- 5+ 体 → テスト設計レビュー (採用 6 条 4) と同水準、cost と quality のバランス

registry 件数不足で 3 体起動不能なら user escalation (`/design-review --max-reviewers 2 --escalate-low-count`)。

## reviewer prompt 共通規約 詳細

### 起源 (2026-05-28 user 直接指示)

PR #28 merge 後の session で user 直接指示「設計後,テスト設計後レビューする際プロジェクトの内容や、他のタスクの内容も鑑みてレビューするようにプロンプトを修正してください」を反映。task-51 iter 2 reviewer 6 並列レビューでも reviewer が single draft inside-out のみ評価し、他 task 重複 / 既存規範矛盾 / 既存実装再利用機会の検出が弱かった経験を踏まえ、reviewer prompt 共通規約として明文化する。

### 必須項目 5 (詳細手順、Layer A §「reviewer prompt 共通規約」table 補完)

1. **task ledger 確認 (`docs/tasks/list.md`)**:
   - 🔄 進行中 task: 並行で着手中の作業との重複 / 競合可能性
   - 🔲 未着手 task: 本対象が前提崩壊させないか / 順序整合性
   - 📝 計画中 task: master roadmap 経路 B (batch planning) との重複
   - ✅ 完了 task: 本対象が既に解決済の問題を再発明していないか

2. **依存先 task.md + draft.md (task-management.md 開発開始時必読義務 準拠)**:
   - 本対象 draft の「依存」section に列挙された task ID 全件
   - draft §「関連 / 派生」section のリンク先
   - 各 task の Task ゴール + 完了条件 + 影響範囲を確認

3. **副産物 registry (`docs/tasks/next-actions.md`)**:
   - 未処理 🔴 緊急 / 🟡 推奨 entry を全件 Read
   - 本対象が解決 / 関連 / 影響する entry を特定し、findings で「entry #N を本対象で解決可」のように参照

4. **既存規範 (`.claude/rules/*.md` Layer A 全 7 file)**:
   - `development-process.md` (TDD / 委譲ガード / Bash 制御 / 並列化義務 等)
   - `task-management.md` (採用 6 条 / parking-lot / 開発開始時必読義務)
   - `workflow.md` (14/10-stage / W1-W4 / 20 MECE / fan-out registry / 本規約)
   - `modes.md` (Normal/Loop / 9 遵守事項 / 自律実行禁止 11 カテゴリ)
   - `self-improvement.md` (L1-L5 + F1/F2)
   - `why-x5-output.md` (1 行 format)
   - `git-workflow.md` (branch 命名規約)
   - 本対象が上記規範と矛盾していないか / 規範更新が必要か判定

5. **プロジェクト構造 / SSoT (`README.md` + `docs/INVENTORY.md`)**:
   - architecture diagram / Layer A/B Strategy 等の最新版を確認
   - 本対象が SSoT を破壊していないか / 拡張すべき INVENTORY entry はあるか

6. **既存実装 patterns 探索 (Glob/Grep)**:
   - `.claude/hooks/` 配下: 類似 hook が既存なら本対象との関係を findings に明記
   - `.claude/commands/` 配下: 類似 command 再利用 / 拡張で対応可能なら再発明回避を推奨
   - `.claude/skills/` 配下: 類似 skill 流用 / 拡張可能性
   - 既存 utility (`.claude/scripts/` `.claude/hooks/lib/`) の流用機会

### OK 例 (適切な findings 反映)

- **「task-51 の Layer A/B 構造と本 draft の規範文書追加方針が整合 (Layer A 要約 + Layer B 詳細の 2 層構造で書く)」** — 既存規範整合性確認
- **「next-actions.md entry #56 (Layer A/B template 整備) が本 draft で解決される、本 PR merge 時に entry #56 を `→ 解決` status に更新せよ」** — 副産物連動
- **「既存 `.claude/hooks/task-rule-guard.sh` の Edit/Write block ロジックが本 draft の新 hook と重複、既存 hook 拡張で対応すべき」** — 既存実装再利用機会
- **「task-21 W3 が UserPromptSubmit 注入数削減を進行中、本 draft の新 hook (`hook-X.sh`) は UserPromptSubmit に注入を追加するため、task-21 W3 の進捗と矛盾」** — 他 task 競合検出
- **「README.md §2.6 Layer A/B Strategy table と本対象の path 規約が不整合、README 同期更新が必要」** — SSoT 整合性

### NG 例 (不適切なレビュー、本規約違反)

- **「本 draft 内の §3 採用案 architecture が clean (SOLID 準拠)」** — inside-out only、他 task 影響 / 既存実装再利用 等の観点が欠落
- **「security 観点: 入力検証 OK」** — single draft レベルの security 観点のみで、`.claude/rules/development-process.md` の cross-repo write 例外 / staging 戦略との整合確認なし
- **「実装提案: 新 file `.claude/hooks/new-hook.sh` を作成」** — 既存 `.claude/hooks/` 内に類似 hook 不在を Glob で確認せずに「新規作成」推奨
- **「task ledger 確認: 関連なし」 (実際は list.md を Read していない)** — Read 不在のまま「関連なし」と結論

### 既存規約との関係

- **behavior-preserving 原則** ([`module-review.md`](../../.claude/commands/module-review.md) Phase 3): 本規約と直交、両方適用。本規約は**レビュー範囲の拡張** (project context)、behavior-preserving は**修正提案の制約** (public API / DB schema 変更禁止)。
- **末尾 `confidence: 0.X`** (F3 confidence-gate): 本規約遵守度も confidence 算出に反映。項目 5 の Read 不在 / 不充分は confidence 0.6-0.7 程度に留まるべき (高すぎる confidence は不正確)。
- **採用 6 条 4 テスト設計レビュー** ([`task-management.md`](../../.claude/rules/task-management.md) 採用 6 条 4): main agent が reviewer 5+ 動的選定して prompt を構築する際、本規約 項目 5 を必ず含める。

### commands 連携

| command | 規約反映先 |
|---|---|
| `/design-review` Phase 3 prompt template | 「対象 draft 全文 + 観点 + findings format + confidence + **項目 5: プロジェクト整合性 + 他 task 影響確認**」 |
| `/test-design` Phase 3 agent prompt (tdd-guide / test-automator / qa-expert) | 「20 カテゴリ採用推奨 + **項目 5: プロジェクト整合性確認** (他 task のテスト戦略との重複検出 + 既存 test infrastructure 流用機会)」 |
| `/module-review` Phase 3 | 「3 観点 + 項目 5: モジュール変更が他 task / 既存規範 / SSoT に与える影響」 |
| `/system-review` Phase 3 | 「system-level 3 観点 + 項目 5 強化 (system 全体の cross-task 影響)」 |
| 採用 6 条 4 (main ad-hoc dispatch) | main agent が reviewer 5+ subagent dispatch 時、各 prompt 末尾に「**項目 5: プロジェクト整合性確認**: list.md / 依存先 task / next-actions / 既存規範 / README+INVENTORY / 既存実装 Glob を必ず実施」明記 |

### bypass の運用詳細

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` の**正当な使用ケース** (honor system):

- typo 1 行修正の `/module-review`
- comment-only refactor の review
- 既に直前の他 review (round-1) で project context 確認済の追加 round (round-2 以降、新規 finding 解消のみ目的)
- hot fix bypass (緊急障害対応で review skip)

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` の **NG ケース** (bypass 禁止):

- 新規 feature の `/design-review` 初回 (round-1)
- `.claude/rules/` 編集を含む change の review
- 採用 6 条 4 のテスト設計レビュー初回 (round-1)
- 規範変更 (`docs/draft/` 新規起案) の review
- 設計 / architecture 大幅変更の review

### Loop モード時の動作

Loop モード稼働中 (modes.md 遵守事項 2 例外条項) でも、本規約は**戦術判断扱い** (実装中の方式選択と同等で、user 中間確認不要)。reviewer subagent は Loop モードでも自律で項目 5 の全 Read を実施する。

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` 適用時のみ、reviewer が項目 5 を skip しても block しない (bypass.log に記録)。

## 副産物 discharge 詳細

### 処理フロー

```
副産物発生
  ↓ (層 1: registry 追加義務)
docs/tasks/next-actions.md に entry 追加 (緊急度 🔴 / 🟡 / 🟢)
  ↓ (層 5: command で移行)
/discharge-byproduct <entry-number>
  ↓
[判定]
  (a) 🔴 / 🟡 → /new-draft <slug> で draft 起こし → user 承認 → /new-task → list.md
  (b) 🟢 + 設計済 → parking-lot.md に保留タスクとして移行
  (c) 不要 → 無視、理由を処理結果列に明記、履歴セクションへ移動
  ↓
next-actions.md 処理結果列を更新
```

### 関連 artifact

- [`docs/tasks/next-actions.md`](../../docs/tasks/next-actions.md) — registry 本体
- [`.claude/templates/docs/tasks/_TASK_TEMPLATE.md`](../templates/docs/tasks/_TASK_TEMPLATE.md) — 派生 task セクション (W2 で追加)
- [`.claude/hooks/next-actions-surface.sh`](../hooks/next-actions-surface.sh) (W1)
- [`.claude/hooks/byproduct-discharge-guard.sh`](../hooks/byproduct-discharge-guard.sh) (W3)
- [`.claude/hooks/lib/next-actions-parser.sh`](../hooks/lib/next-actions-parser.sh) — 共通 parser
- [`.claude/commands/discharge-byproduct.md`](../commands/discharge-byproduct.md) (W4)
- [`.claude/tests/next-actions-hooks-smoke.sh`](../tests/next-actions-hooks-smoke.sh) (W6, 9/9 PASS)
- 設計起源は採用プロジェクト側 `docs/draft/` を参照 (`.claude/` 単独で portable)

### 違反パターン

- 副産物を memory にのみ保存して draft 化しない → 層 1 違反 (registry 不在で発見不能)
- 「次セッションで対応」とコメントだけ残してセッション終了 → 層 4 (Stop hook) で 🔴 残存 BLOCK
- 発生源 task の `/finish-task` 完了前に処理せず後送り → 層 2 (`_TASK_TEMPLATE.md` 派生 task セクション) で task 完了時に検出

## Session 永続化詳細

### Serena 必須化の設計補足

- 旧版では `mcp__serena__check_onboarding_performed` を別 step で呼んでいたが、現 Serena MCP には該当 tool が存在しない (2026-05-23 確認、deferred tools list にも無し)
- `activate_project` の error response で onboarding 未済を検知する形に統合 (`resume-state.md` / `save-state.md` / `pm-start.md` の Phase 1 同期修正済)
- `.mcp.json` の `serena` entry は採用者側で個別登録 (Claude Code 標準には required marker 機構なし、command-level enforcement で代替)

### 関連 artifact (完全 list)

- [`.claude/commands/save-state.md`](../commands/save-state.md)
- [`.claude/commands/resume-state.md`](../commands/resume-state.md)
- [`.claude/commands/pm-start.md`](../commands/pm-start.md)
- [`.claude/hooks/mode-session-start.sh`](../hooks/mode-session-start.sh) (W2 拡張済)
- [`.claude/tests/custom-pm-commands-smoke.sh`](../tests/custom-pm-commands-smoke.sh) (W5, 6/6 PASS)
- 設計起源は採用プロジェクト側 `docs/draft/` を参照 (`.claude/` 単独で portable)

### SessionStart 自動 resume の動作詳細

- `.serena/memories/session/context.md` 存在検知 → `<system-reminder>` で `/resume-state` 提案
- user 入力不要、メインが自動で `/resume-state` 実行 (Loop モード時) or user 承認待ち (Normal モード時)
- 復元対象: TaskList / 直近 commits / 進行中 artifact / 次アクション / context_used_ratio

## 関連 skill 完全

### 直接関連

- `salesforce-e2e-testing` — Wave / Phase 完了時の E2E シナリオ設計 (Stage 13 `scenario-test` / Stage 9 `full-test` で参照)
- `karpathy-guidelines` — surgical changes 原則 (`/module-review` / `/system-review` の behavior-preserving 原則と整合)

### 補助関連

- `tdd-workflow` — Stage 8 `tdd` の RED → GREEN → REFACTOR ループ規範
- `eval-harness` (L1) — Stage 10 `local-test` の pass@k metrics 連携
- `verification-loop` (F2) — Stage 14 `finish` 直前の 6 phase 検証
- `gateguard` (F1) — Stage 8 `tdd` 中の Edit/Write 事前事実検証

### audit 系

- `harness-audit.py` の `bypass_log_summary()` / `fmt_bypass_log()` — `/harness-audit` での bypass 集計
- `.claude/.workflow-state/SCHEMA.md` — workflow-guard.sh が参照する JSON 仕様 SSoT

## 起源

- **W1-W4 規範化**: 設計起源は採用プロジェクト側 `docs/draft/workflow-enforcement.md` v2 §3 W1〜W4 (`.claude/` 単独で portable、本 file は採用後の規範を保持)
- **draft-flow-guard.sh 元機能 (`docs/` 直下 block)**: 起源 commit `6ed9337`、後続緩和 task-40 (2026-05-26) → 撤廃 (2026-05-28、user 直接指示)
- **task-40 拡張 (`.claude/rules/*.md` 等 BLOCK)**: 2026-05-26 採用、設計起源: `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md`、2026-05-28 緩和で撤廃
- **副産物 discharge 5 層強制機構**: 本セッション task #5 で実装、W1 (next-actions-surface) / W2 (`_TASK_TEMPLATE.md`) / W3 (byproduct-discharge-guard) / W4 (`/discharge-byproduct`) / W6 (smoke) の段階実装
- **Session 永続化と PM Orchestration**: 本セッション task #7 で実装、SuperClaude plugin の `/sc:save` `/sc:load` `/sc:pm` を `.claude/` 単独で portable な自前実装に置換
- **テスト設計レビュー収束条件 (CRITICAL+HIGH+MEDIUM=0)**: 2026-05-26 採用 6 条 4 起源、`task-management.md` 採用 5 条 4 から拡張
- **規範文書 honor system 降格 (2026-05-28)**: user 直接指示「規範文書 path は新規 Write / 既存 Edit とも hook で PASS」、機械強制 BLOCK 撤廃、規律として `modes.md` 遵守事項 2 例外条項「規範変更」で残置
- 各規範の commit hash / 採用判断は git log + 関連 draft / 副産物 entry 参照
