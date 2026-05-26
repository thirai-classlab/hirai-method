<!--
approval_required: true
approved_at: 2026-05-26
approved_by: user
retroactive: true
-->

# task 管理ルール拡張 (依存先 + review 反復) + 規範違反防止 hook 機械強制化

**ステータス:** 🔄 **draft (retroactive、2026-05-26 起案、user 既承認 「A」)**
**起点:** 2026-05-26 session — user 指示「タスク管理に少しルールを追加します (1. 依存先タスク列追加 + 開発時必読義務 / 2. draft レビュー最低 3 体・CRITICAL+HIGH+MEDIUM=0 まで反復)」+ user 承認 → 私が `docs/draft/` 起案 + `/new-task` を skip して直接 6 file 規範編集着手 (規範違反) → user 指摘「今の内容がタスクリストへ追加されないのはなぜですか?」+ 「A (retroactive リカバリ)」+ 「これが起きないようにしてください (機械強制 hook 追加)」
**前提:**
- 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) 適用
- `modes.md` 遵守事項 2 例外条項 (Loop モードでも user 承認必須: 設計新規 / 仕様変更 / 戦略判断)
- 既存 `draft-flow-guard.sh` は `docs/` 直下深さ 1 新規 .md/.mdx のみ block (本 case `.claude/rules/*.md` 等は対象外、構造 gap)

**関連 fixture / rule:**
- `.claude/rules/task-management.md` §「設計→承認→タスク追加フロー」(本ルール違反対象)
- `.claude/rules/modes.md` 遵守事項 2 例外条項
- `.claude/hooks/draft-flow-guard.sh` (既存、`docs/` 直下のみ、拡張対象候補)
- 本 session で先行実装した 10 Edit (6 file): task-management.md / workflow.md / _TASK_TEMPLATE.md / list.md template / _DRAFT_TEMPLATE.md / design-review.md

---

## 1. 真因サマリ / 課題サマリ

本 session で 2 種の規範違反 + 構造 gap が同時発生:

| 違反 / gap | 内容 |
|---|---|
| **規範違反 (本 session 主)** | user 指示「タスク管理にルール追加」+ 「承認します」を受けて、main agent が `docs/draft/` 起案 + `/new-task` を skip し直接 6 file 規範編集に着手 (10 Edit)。`task-management.md` §「設計→承認→タスク追加フロー」step 2-4 を skip |
| **dogfooding 失敗** | 新規ルール 1 (依存先タスク列・必読義務) + 新規ルール 2 (reviewer 3+ / 反復) を新設しながら、本 task 自身に適用していない (自己矛盾) |
| **機械強制 gap** | 既存 `draft-flow-guard.sh` は `docs/` 直下のみ block、`.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` への draft 経由なし直接 Edit を block する hook が不在 |
| **CLAUDE.md Critical Lessons 欠落** | hook BLOCK 強制済の 3 教訓を本 session 直前に slim 化したが、本 case (規範変更 draft skip) に該当する HIGH 級教訓が未追加 |

```mermaid
flowchart LR
    A["user 指示 (規範変更)"] --> B["main agent: 承認後の直接実装"]
    B --> C["draft skip + /new-task skip"]
    C --> D["list.md 未反映 + task ファイル不在"]
    D --> E["user 指摘: なぜ list.md に追加されない?"]
    E --> F["retroactive リカバリ"]
    F --> G["機械強制 hook で再発防止"]
```

**真因:**
1. main agent が「規範変更 = 戦術判断 (Loop モード自律実行可)」と誤判定 (実際は `modes.md` 遵守事項 2 例外条項対象)
2. `draft-flow-guard.sh` が `docs/` 直下のみカバーで `.claude/rules/*.md` 等を見ていない構造 gap
3. CLAUDE.md Critical Lessons から hook BLOCK 強制済 3 教訓を本 session 直前に slim 化した際、本 case (規範変更 draft 経路必須) の教訓を hook 化なしで委譲 section に集約せず、結果として「規範変更は honor system」状態が続いていた

**副次:**
- 本 task の retroactive 化は採用 6 条「既存 task 移行ガイド」の retroactive case として記録 + frontmatter `retroactive: true` で機械可読化
- 本 task 自身が新ルール 1 (依存先) + 新ルール 2 (review 反復) を dogfooding (本 draft §8 レビューサイクル table で iter 実施)

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 規範文書のみ追記 (`modes.md` 遵守事項 2 例外条項を強化 + CLAUDE.md Critical Lessons HIGH 級教訓追加)、hook 強制化なし (honor system) | 0.5h | 軽実装 | 「ルールに書いて守らせる」default、AI が忘れたら再発確実 |
| **B** | `draft-flow-guard.sh` 拡張で `.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` を block + 規範文書追記なし | 2.0h | 機械強制 = 物理防止 | hook 強制理由が文書化されないと bypass 乱用される、honor system 補完なし |
| **C ハイブリッド (推奨)** | A + B 段階: (a) 規範追記 (`modes.md` 例外条項強化 + CLAUDE.md HIGH 教訓追加) + (b) `draft-flow-guard.sh` 拡張 (新 path pattern + retroactive draft case 対応 + bypass env) + (c) 本 task で retroactive draft 化 + /new-task で dogfooding + reviewer 3+ レビュー反復 | 3.5h | 機械強制 (hook BLOCK) + 文書化 (再発時の理解促進) + dogfooding (本ルール 1/2 自己適用で妥当性検証)、CLAUDE.md slim 化方針と整合 (BLOCK 強制済は委譲 section へ) | 工数大、hook 拡張テストが必要 |

→ **C ハイブリッド** を推奨。理由:
- 「これが起きないように」(user 指示) の核心は機械強制 (`draft-flow-guard.sh` 拡張)
- 規範追記 (a) + 機械強制 (b) + dogfooding (c) の 3 層で再発防止
- 本 task 自身を新ルール 1/2 の最初の適用例とすることで規範の妥当性検証

---

## 3. 採用案の詳細設計

### Task 計画 (採用 6 条準拠、Phase 中間階層廃止)

#### Step 計画 (本ルール 1 「依存先タスク」を自己適用)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | ルール 1 (依存先タスク列 + 必読義務) を 3 file に規範化 | 0.5h | — |
| 2 | ✅ | ルール 2 (reviewer 3+ / 反復) を 3 file に規範化 | 0.5h | — |
| 3 | 🔄 | retroactive draft 起案 (本 file) + `/new-task` で `list.md` 反映 (本ルール 1 dogfooding、依存先列に — 記入) | 0.3h | Step 1, 2 |
| 4 | 🔲 | `draft-flow-guard.sh` 拡張: 新 path pattern (`.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/**/*.md`) を block 対象に追加、対応 draft (`docs/draft/<slug>.md` で `approved_at` 非空) 存在で pass、bypass `ECC_RULE_CHANGE_GUARD_OFF=1` | 1.0h | Step 3 |
| 5 | 🔲 | `modes.md` 遵守事項 2 例外条項に「規範変更 (`.claude/rules/*.md` 等)」を明示追加 + CLAUDE.md Critical Lessons HIGH 級教訓追加 (hook BLOCK 強制済) | 0.3h | Step 4 |
| 6 | 🔲 | smoke test 新設 (`.claude/tests/rule-change-draft-flow-guard-smoke.sh`): N cases (新 path pattern block / 対応 draft あり pass / bypass env / retroactive case / 既存 docs/ block 回帰 0) | 0.5h | Step 5 |
| 7 | 🔲 | (テスト設計レビュー、本ルール 2 dogfooding) reviewer 3+ 並列、CRITICAL+HIGH+MEDIUM=0 まで反復 (上限 5)、§8 レビューサイクル table に iter 記録 | 0.5h | Step 6 |
| 8 | 🔲 | (テスト合格) smoke 全 PASS + 既存 regression 0 + grep 検証 (CLAUDE.md 教訓 + modes.md 例外条項) | 0.3h | Step 7 |
| 9 | 🔲 | (リファクタリング) 3 観点判定 (持続可能性 / 汎用性 / 非冗長化)、不要なら skip 明示 | 0.2h | Step 8 |

合計工数: **4.1h** (Step 1+2 既完了で残 3.6h)

### Step 1-2 詳細 (既完了)

本 session ターンで以下 10 Edit 実施済:

- **ルール 1 (依存先タスク)**: `task-management.md` 採用 6 条 2 (Task 必須項目に追加) + 6 (list.md column 5→6 列) + 新 §「開発開始時の必読義務」 / `_TASK_TEMPLATE.md` Task ゴール直後に §「Task 依存先タスク」 / `list.md` template column 5→6 列 + 記入ルール更新
- **ルール 2 (reviewer 3+ / 反復)**: `workflow.md` §設計レビューの fan-out §集約 拡張 + 新 §「収束条件」 / `_DRAFT_TEMPLATE.md` §8「レビューサイクル」新設 + §9/§10 繰り下げ / `design-review.md` 使い方に `--min-reviewers 3` + Phase 4 「集約 + 収束判定 + 反復ループ」拡張

### Step 4 詳細 (主 deliverable: hook 機械強制化)

`.claude/hooks/draft-flow-guard.sh` 拡張仕様:

```text
[追加 path pattern]
- .claude/rules/*.md
- .claude/commands/*.md
- .claude/templates/docs/{tasks,draft}/*.md
- .claude/templates/**/*.md (より広い場合)

[追加判定ロジック]
1. tool_input.file_path が上記 pattern に match
2. slug 抽出: file basename or path から推定 (実装方針 §「slug 抽出」で詳細化)
3. 対応 draft (`docs/draft/<slug>.md` for the change scope) 検索
4. draft frontmatter `approved_at` が非空 → pass
5. draft 不在 or `approved_at` 空 → BLOCK + 「先に /new-draft <slug> で設計を起こせ」案内
6. retroactive case (frontmatter `retroactive: true`) → pass + warn 注入 ("retroactive draft 経由、規範遵守は次回から")

[bypass]
- ECC_RULE_CHANGE_GUARD_OFF=1 (1 セッション全体 OFF、bypass.log 記録)
- /gate-bypass <file path> (1 ファイル分 pre-clear)
- HC_RULE_CHANGE_GUARD_ENABLED=false (config レベル OFF)
```

### Step 5 詳細 (規範文書更新)

- `.claude/rules/modes.md` 遵守事項 2 例外条項に追加: 「規範変更 (`.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md` への Edit/Write) は user 承認必須、`draft-flow-guard.sh` が機械強制 BLOCK」
- `CLAUDE.md` Critical Lessons の「hook で完全 BLOCK 強制済の旧教訓」section に追加: 「**`.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/**/*.md` を draft 経由なしで直接 Edit/Write しない** → `draft-flow-guard.sh` 拡張 (本 task で実装)、bypass: `ECC_RULE_CHANGE_GUARD_OFF=1`」

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| hook 拡張で既存 `.claude/rules/*.md` Edit が一律 BLOCK され session 詰まる | M | H | Step 4 で対応 draft 存在 check + retroactive case 対応 + bypass env 多経路用意。本 task の draft 自体は retroactive case で pass |
| slug 抽出ロジックの誤判定で false positive / false negative | M | M | basename 主体 + フォールバック strategy 複数試行、smoke で 5+ ケース検証 |
| 既存規範文書の頻繁な改修が draft 経由必須化で重荷化 | L | M | bypass env / `/gate-bypass` 経路を honor system で残す、緊急 hot fix は bypass + 事後 retroactive draft |
| CLAUDE.md slim 化方針と矛盾 (再び教訓追加で肥大化) | L | L | Critical Lessons table ではなく「hook で完全 BLOCK 強制済の旧教訓」section に集約 (slim 化方針整合) |

---

## 5. 移行計画

- [x] Step 1-2: ルール 1+2 規範化 (本 session 完了、10 Edit)
- [ ] Step 3: 本 retroactive draft 起案 + `/new-task` で `list.md` 反映
- [ ] Step 4: `draft-flow-guard.sh` 拡張 (subagent 委譲 + staging 戦略必須、`.claude/hooks/` は protected_paths_code)
- [ ] Step 5: 規範文書更新 (modes.md + CLAUDE.md)
- [ ] Step 6: smoke 新設
- [ ] Step 7-9: テスト設計レビュー → テスト合格 → リファクタリング
- [ ] 全完遂後: commit + PR (本 session の commit + PR を本 task に統合 or 別 PR)

---

## 6. 完了条件（DoD）

- [ ] 新 path pattern (`.claude/rules/*.md` `.claude/commands/*.md` `.claude/templates/**/*.md`) への draft 経由なし Edit が `draft-flow-guard.sh` で BLOCK される
- [ ] 対応 draft (`approved_at` 非空) ありなら pass、`retroactive: true` の retroactive draft も pass
- [ ] bypass env (`ECC_RULE_CHANGE_GUARD_OFF=1`) で 1 セッション OFF、`bypass.log` 記録
- [ ] smoke `.claude/tests/rule-change-draft-flow-guard-smoke.sh` 全 PASS (5+ cases)
- [ ] 既存 `draft-flow-guard.sh` の `docs/` 直下 block (task-21 W2.3) 回帰 0
- [ ] `modes.md` 遵守事項 2 例外条項に新 entry 追加 (grep 検証)
- [ ] `CLAUDE.md` Critical Lessons「hook で完全 BLOCK 強制済の旧教訓」section に新 entry 追加 (grep 検証)
- [ ] 本 task が `docs/tasks/list.md` に行追加され、依存先列に — (依存なし) 記入、本 task ファイル `task-<id>-task-mgmt-rules-with-draft-flow-enforcement.md` 存在
- [ ] §8 レビューサイクル table に iter 1+ 記録 (reviewer 3+ / CRITICAL+HIGH+MEDIUM=0 収束 / 上限 5 以内)

---

## 7. 工数見積

- Step 1+2 (完了): 1.0h
- Step 3-9 (残): 3.6h
- **合計: 4.1h** (本 session で Step 3 完遂、Step 4-9 は次 session 持ち越し想定)

---

## 8. レビューサイクル (workflow.md §「収束条件」準拠、本ルール 2 自己適用)

> draft レビューは **reviewer 最低 3 体以上 並列起動** + **CRITICAL/HIGH/MEDIUM = 0 まで反復** (LOW 許容、上限 5 回)。本 draft 自身が新ルール 2 の dogfooding。

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | 2026-05-26 | tdd-guide, test-automator, qa-expert, security-reviewer, architect-reviewer (5) | 0 | 9 | 11 | 11 | (修正なし、finding 集約のみ) | 集約完了、iter2 で修正実施 |
| 2 | 2026-05-26 | tdd-guide, test-automator, qa-expert, security-reviewer, architect-reviewer (5) | 0 | 1 | 6 | 13 | a95abcd / ac086d3 / e828cf2 / 2db0102 / 238af0f | 部分収束、iter3 で残 HIGH 1 + MEDIUM 6 修正 |
| 3 | 2026-05-26 | tdd-guide, test-automator, qa-expert, security-reviewer, architect-reviewer (5) | 0 | 0 | 1 (§8 TBD、本 commit で解消) | 8+ | 79607fb / 6922ea7 / 0550ade | 収束達成 (median 0.93、qa MEDIUM-1 本 commit で 0 化) |

**収束判定**: CRITICAL = 0 ∧ HIGH = 0 ∧ MEDIUM = 0 (LOW は許容、cosmetic finding として記録のみ)

**上限超過時 (iter 5 でも未収束)**: user escalation → `ECC_DESIGN_REVIEW_OFF=1` で bypass + `bypass.log` 記録 + bypass 理由を §9 末尾に追記

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-26 | user | 口頭承認「承認します。」(ルール 1+2 規範化、本 session 前半) |
| 2026-05-26 | user | リカバリ承認「A」(retroactive draft 起案 + /new-task + reviewer 3+ レビュー、本 session 後半) |
| 2026-05-26 | user | 機械強制追加指示「これが起きないようにしてください」(本 task の主 deliverable に `draft-flow-guard.sh` 拡張を追加) |

---

## 10. 関連

- 既存規範: [`task-management.md`](../../.claude/rules/task-management.md) §「設計→承認→タスク追加フロー」(本 task で違反した規範) / [`modes.md`](../../.claude/rules/modes.md) 遵守事項 2 例外条項 (Loop モードでも user 承認必須)
- 既存 hook: [`draft-flow-guard.sh`](../../.claude/hooks/draft-flow-guard.sh) (本 task で拡張対象、task-21 W2.3 起源)
- 関連完遂タスク: task-21 (system-reminder-attention、`draft-flow-guard.sh` 新設の起源)
- 副産物 registry: [`next-actions.md`](../tasks/next-actions.md) (本 session 違反は entry 化せず本 retroactive draft で直接管理)
- 関連 master roadmap: [`next-actions-cleanup-batch.md`](next-actions-cleanup-batch.md) (本 task は本 master roadmap の Group F (install.sh 配布漏れ) と類似の構造修正系)
