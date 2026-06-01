---
description: 設計 draft に対し reviewer-registry の design + security カテゴリ全 agent を並列起動して fan-out レビューを実行する。
---

# /design-review — 設計レビュー fan-out

承認待ち設計 draft (`docs/draft/<slug>.md`) を読み、`harness-config.yml` の `reviewer_registry_design` + `reviewer_registry_security` に登録された agent を **並列起動** (`run_in_background: true` 必須) して fan-out レビューを実行。各 agent の findings を `docs/draft/<slug>-review.md` に集約する。

## 前提

- 対象 draft (`docs/draft/<slug>.md`) が存在する
- `confidence-gate.sh` が subagent transcript path を正しく解決できる (commit 96da878 適用済)
- `harness-config.yml` の reviewer_registry_* が定義されている

## 使い方

```
/design-review <slug>                        # 既定: design + security 全 agent 並列起動 (min 3 強制、2026-05-26)
/design-review <slug> --categories design    # design カテゴリのみ
/design-review <slug> --max-reviewers 5      # 上限指定 (cost 制御、N ≥ 3 必須)
/design-review <slug> --min-reviewers 3      # 下限指定 (default 3、N ≥ 3 必須、registry 件数不足時は user escalation)
/design-review <slug> --skip-stack-filter    # stack heuristic 絞り込みを無効化
```

## 引数

- `<slug>` — kebab-case、既存 `docs/draft/<slug>.md` の slug
  - validation: `^[a-z0-9][a-z0-9-]{2,48}$` (git-workflow.md branch 規約準拠)
  - path traversal 防止 (`.` `/` `..` 含む値は reject)

## 動作

### Phase 0: yml 参照 (task-45 Phase 2、reviewer 制御 yml 経由化)

本 command 開始前に `harness-config.yml` から以下 4 値を参照 (env > yml > default、`config-loader.sh` 仕様):

| 環境変数 | yml key | default | 用途 |
|---|---|---:|---|
| `HC_REVIEW_REQUIRED_DESIGN` | `review_required_design` | `true` | `false` なら本 command を **no-op skip** (理由付きでユーザに報告 + 終了) |
| `HC_REVIEW_MIN_COUNT_DESIGN` | `review_min_count_design` | `3` | reviewer 範囲下限 (`--min-reviewers` 未指定時の default) |
| `HC_REVIEW_MAX_COUNT_DESIGN` | `review_max_count_design` | `7` | reviewer 範囲上限 (`--max-reviewers` 未指定時の default) |
| `HC_REVIEW_ITERATION_MAX` | `review_iteration_max` | `5` | Phase 4 反復ループ上限 (収束まで再 review、超過時 user escalation) |

**起動前に必ず以下を実行して reviewer 数を確定する (task-64、散文参照でなく実行手順)**:

```bash
bash .claude/scripts/hc-config.sh --get review_required_design   # false なら本 command を no-op skip
bash .claude/scripts/hc-config.sh --get review_min_count_design  # 範囲下限
bash .claude/scripts/hc-config.sh --get review_max_count_design  # 範囲上限
# → min ≤ 並列起動 reviewer 数 N ≤ max を保証して起動 (青天井禁止)。security category は review_required_security / review_min_count_security も別途確認。値解決順 env > harness-config.local.yml > harness-config.yml > default
```

`HC_REVIEW_REQUIRED_DESIGN=false` で skip した場合は、bypass.log に記録し、ユーザに「review_required_design=false のため /design-review を skip した、Phase 1 以降を実行しない」と明示。

### Phase 1: 前提チェック

1. slug を validation regex でチェック (不正なら reject)
2. `docs/draft/<slug>.md` が存在することを確認
3. `docs/draft/<slug>-review.md` が既存でないことを確認 (上書き防止)、存在時は `<slug>-review-2.md` `-3.md` と suffix 付与

### Phase 2: reviewer-registry 読み込み + stack 推定

1. `harness-config.yml` から `reviewer_registry_design` `_security` を読む
2. 対象 draft 本文を読んで stack を heuristic 推定:
   - mermaid 内 / 採用案 / 影響範囲セクションを grep
   - `database` / `migration` / `RLS` keyword → database-reviewer を含む
   - `API` / `endpoint` / `REST` / `GraphQL` → api-designer を含む
   - `UI` / `component` / `frontend` keyword → ui-designer を含む
   - DB/API/UI keyword 無 → 対応 reviewer を除外
3. `--skip-stack-filter` 指定時は全件起動
4. `--max-reviewers N` 指定時は最初の N 件に絞る

### Phase 3: 並列 Agent fan-out (Loop モードでは無条件、Normal モードは user 確認 1 回)

1. 選定 reviewer ごとに以下を実行:
   - **TaskCreate** で subagent_id metadata 付きタスク登録 (CLAUDE.md §4 必須)
   - **Agent tool** で起動 (`run_in_background: true` 必須):
     - prompt: 共通テンプレ「対象 draft 全文 + 観点 (reviewer 別) + findings format (CRITICAL/HIGH/MED/LOW 分類, 具体修正提案、behavior-preserving) + 末尾 `confidence: 0.X` 必須 + **項目 5 プロジェクト整合性 + 他 task 影響確認** (必須、`workflow.md` §reviewer prompt 共通規約準拠): `docs/tasks/list.md` (他 task ledger) + 依存先 task.md / draft.md + `docs/tasks/next-actions.md` (副産物 registry) + `.claude/rules/*.md` (既存規範 Layer A 全 7 file) + `README.md` / `docs/INVENTORY.md` (project SSoT) + 既存実装 (Glob/Grep で `.claude/hooks/` `.claude/commands/` `.claude/skills/` 内類似探索) を Read。findings に「他 task #N との重複 / 競合 / 前提崩壊」「既存 rule §X と矛盾 / 拡張必要」「副産物 entry #Y を本対象で解決可能」「既存 hook/command/skill 再利用可 (再発明回避)」「SSoT 重複 / 矛盾」を該当時に必ず含める。bypass: `HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` (新規 feature 初回 round-1 / `.claude/rules/` 編集 change の review では NG)」
2. 全 agent 起動後、メインは即座に user 制御に戻る (notification を待たない、ユーザは次操作可能)

### Phase 4: 集約 + 収束判定 + 反復ループ (各 agent 完了通知到着時、2026-05-26 拡張)

1. SubagentStop notification を受信したら以下を順次:
   - findings を `docs/draft/<slug>-review.md` に追記 (reviewer 名 + severity 別)
   - 並行起動中の他 reviewer はそのまま継続
2. 全 reviewer 完了後、集約レポートを作成:
   - severity 別件数サマリ表 (CRITICAL / HIGH / MEDIUM / LOW の 4 段階、各 reviewer prompt で severity 分類強制)
   - blocking findings (CRITICAL / HIGH / MEDIUM) ハイライト
   - 各 reviewer の confidence score 一覧
3. **収束判定** (workflow.md §「収束条件」準拠、2026-05-26 追加):
   - CRITICAL = 0 ∧ HIGH = 0 ∧ MEDIUM = 0 → 「収束」、draft ステータスを「承認待ち」に遷移可能 (LOW は許容、cosmetic finding として記録のみ)
   - 1 件以上 → 「修正待ち」、draft 修正 → 再度 /design-review で **round-N+1 review**
4. **反復ループ**:
   - **reviewer 最低数**: 各 iter で **3 体以上** 並列起動 (default は reviewer-registry 全件 + stack heuristic 絞り込み、`--max-reviewers N` 指定時も `N ≥ 3` 必須、registry 件数不足で 3 体起動不能なら user escalation)
   - **反復上限**: **5 回** (default)、超過時は user escalation
   - **bypass**: `ECC_DESIGN_REVIEW_OFF=1` (反復 5 回上限超過時の user escalation 後の継続用、`.claude/.workflow-state/bypass.log` に append + draft §9 承認履歴末尾に bypass 理由追記)
   - **iteration 記録**: 各 iter の reviewer 一覧 + 件数 (CRITICAL/HIGH/MEDIUM/LOW) + 修正 commit hash を `docs/draft/<slug>.md` §「レビューサイクル」table (`_DRAFT_TEMPLATE.md` §8) に append

### Phase 5: ユーザ報告

```
🔍 Design Review 完了: docs/draft/<slug>-review.md

並列起動 reviewer: N 件 (design X / security Y)
集約結果: CRITICAL: A / HIGH: B / MEDIUM: C / LOW: D
平均 confidence: 0.XX

次の操作:
  - CRITICAL/HIGH があれば draft 修正後、再度 /design-review で round-2 review
  - 0 件なら user 明示承認 → /new-task で W2 タスク化
```

## 制約

- 全 agent は **必ず** `run_in_background: true` (CLAUDE.md §1 必須、30 秒以内例外なし)
- 各 agent 起動前後に **必ず** TaskCreate (CLAUDE.md §4 必須、subagent_id を metadata 記録)
- 集約レポートは `docs/draft/` 配下に置く (`docs/draft/reviews/` サブディレクトリ案は v3 で検討)
- bypass: `ECC_DESIGN_REVIEW_OFF=1` で fan-out skip (template 集約レポートのみ生成)

## Loop モード時の特例

- 起動前 user 確認なし (Loop モード「中間確認の停止」原則遵守)
- 全件起動 (`--max-reviewers` 未指定時の制限なし)
- CRITICAL/HIGH 自動修正提案も Why × 5 で評価して draft v2 を即適用

## Normal モード時

- 起動前に user に「N 件 reviewer を並列起動します。cost 影響 → 続行?」を 1 回確認
- 集約後の draft 修正も user 確認

## 関連

- `/new-draft <slug>` — 設計 draft 起こし (本 command の前段)
- `/test-design <slug>` — テスト設計 MECE (本 command と並行実行可能)
- `/new-task <id> <slug>` — タスク化 (本 command + /test-design 完了後)
- config: `.claude/harness-config.yml` の `reviewer_registry_*`
- hook 依存: `.claude/hooks/confidence-gate.sh` (subagent transcript 解決 fix 適用済)
- 設計 draft: `docs/draft/workflow-enforcement.md` §3 W2
