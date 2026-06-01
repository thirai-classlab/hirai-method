---
description: 設計 draft からテスト設計を起こし、MECE 20 カテゴリで採用/不採用を user に決定させる。
---

# /test-design — テスト設計 MECE カタログ生成

承認済設計 draft (`docs/draft/<slug>.md`) を読み、テスト設計ファイル `docs/draft/<slug>.test-design.md` を `.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md` から生成。MECE 20 カテゴリの「採用/不採用 + 理由」を user 判断に委ねる。

## 前提

- 対象 draft (`docs/draft/<slug>.md`) が存在し、設計内容が記入済
- W4 で実装される `/new-task` の block 機構と連動 (本 command 単独では block しない)

## 使い方

```
/test-design <slug>                  # 既定: tdd-guide + test-automator + qa-expert を並列起動して採用推奨を生成
/test-design <slug> --no-suggest     # agent 提案なしで空のカタログだけ生成
/test-design <slug> --skip-agents    # agent 起動を完全 skip (静的テンプレートのみ)
```

## 引数

- `<slug>` — kebab-case、既存 `docs/draft/<slug>.md` の slug と一致
  - validation: `^[a-z0-9][a-z0-9-]{2,48}$` (git-workflow.md branch 規約準拠)
  - path traversal 防止のため slug の `.` `/` `..` を含む値は reject

## 動作

### Phase 0: yml 参照 (task-45 Phase 2、reviewer 制御 yml 経由化)

本 command 開始前に `harness-config.yml` から以下 4 値を参照 (env > yml > default、`config-loader.sh` 仕様):

| 環境変数 | yml key | default | 用途 |
|---|---|---:|---|
| `HC_REVIEW_REQUIRED_TEST` | `review_required_test` | `true` | `false` なら本 command を **no-op skip** (理由付きでユーザに報告 + 終了、採用 6 条 4「テスト設計レビュー」step skip 可) |
| `HC_REVIEW_MIN_COUNT_TEST` | `review_min_count_test` | `5` | reviewer 範囲下限 (青天井「5+」は task-64 で廃止) |
| `HC_REVIEW_MAX_COUNT_TEST` | `review_max_count_test` | `10` | reviewer 範囲上限 |
| `HC_REVIEW_ITERATION_MAX` | `review_iteration_max` | `5` | テスト設計レビュー反復上限 (超過時 user escalation、bypass `ECC_TEST_DESIGN_REVIEW_OFF=1`) |

**起動前に必ず以下を実行して reviewer 数を確定する (task-64、散文参照でなく実行手順)**:

```bash
bash .claude/scripts/hc-config.sh --get review_required_test    # false なら本 command を no-op skip
bash .claude/scripts/hc-config.sh --get review_min_count_test   # 範囲下限
bash .claude/scripts/hc-config.sh --get review_max_count_test   # 範囲上限
# → min ≤ 並列起動 reviewer 数 N ≤ max を保証して起動 (青天井禁止)。値解決順 env > harness-config.local.yml > harness-config.yml > default
```

`HC_REVIEW_REQUIRED_TEST=false` で skip した場合は、bypass.log に記録し、ユーザに「review_required_test=false のため /test-design を skip した、Phase 1 以降を実行しない」と明示。

### Phase 1: 前提チェック

1. slug を validation regex でチェック (不正なら reject)
2. `docs/draft/<slug>.md` が存在することを確認
3. `docs/draft/<slug>.test-design.md` が既存でないことを確認 (上書き防止)

### Phase 2: テンプレ展開

1. `.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md` をコピーして `docs/draft/<slug>.test-design.md` を作成
2. プレースホルダ置換:
   - `<タスク名>` → 対象 draft の H1 タイトル
   - 生成日 → 今日 (YYYY-MM-DD)

### Phase 3: agent 並列起動 (`--skip-agents` 指定時は skip)

1. 対象 draft の本文を読み込み、stack/scope を heuristic で推定
2. 以下 3 agent を並列起動 (`run_in_background: true` 必須):
   - **tdd-guide** — RED/GREEN/REFACTOR 視点で必要テストを抽出
   - **test-automator** — フレームワーク選定 + 自動化観点
   - **qa-expert** — QA 戦略 + 非機能テスト観点
3. 各 agent に「20 カテゴリ各行への採用推奨 (☑/☒) + 1 行理由 + **項目 5 プロジェクト整合性 + 他 task 影響確認** (必須、`workflow.md` §reviewer prompt 共通規約準拠): `docs/tasks/list.md` (他 task のテスト戦略との重複) + 依存先 task の test-design.md + `docs/tasks/next-actions.md` (副産物 registry) + 既存 test infrastructure (`.claude/tests/` 配下の smoke / `tests/` 配下の既存テスト framework) を Read。findings に「他 task のテストカバレッジで本対象も網羅済 (existing-coverage)」「既存 smoke 再利用可」「他 task #N のテスト戦略と整合性確保」を該当時に必ず含める」を返答させる
4. TaskCreate でタスク登録 (subagent_id を metadata 記録)
5. 完了通知を待ち、3 agent の推奨を集約

### Phase 4: 採用推奨の反映

1. 集約結果を `<slug>.test-design.md` の 20 カテゴリ表に書き込む:
   - 3 agent 中 2 以上が採用推奨 → デフォルト ☑
   - 3 agent 中 2 以上が不採用推奨 → デフォルト ☒ + 理由テンプレ (`scope-excluded`)
   - 意見が割れる場合 → ☐ + コメント「agent 意見分かれ、user 判断要」
2. 採用カテゴリには「採用テストの実行戦略」セクションを追加 (TC-N の skeleton)
3. 不採用カテゴリには「不採用テストの記録」セクションを追加 (理由テンプレ)

### Phase 5: ユーザ承認案内

```
🧪 Test Design 起こしました: docs/draft/<slug>.test-design.md

次の操作:
  1. ファイルを開いて 20 カテゴリの採用/不採用を確認・修正
  2. 不採用には必ず理由を記入 (scope-excluded / not-applicable / existing-coverage / accepted-risk)
  3. 末尾の「ユーザ承認」セクションをチェック
  4. 承認後: /new-task <id> <slug> でタスク化（W4 実装後は本ファイル未確認時 block）

並列 agent 推奨:
  tdd-guide: 採用 X / 不採用 Y
  test-automator: 採用 X / 不採用 Y
  qa-expert: 採用 X / 不採用 Y
```

## 制約

- agent 並列起動は `confidence-gate.sh` 通過必須 (subagent transcript 解決 fix 適用済)
- 既存 `docs/draft/<slug>.test-design.md` は **絶対に上書きしない** (Phase 1 check)
- 本 command 単独では `/new-task` を block しない (W4 で実装される `task-rule-guard.sh` 拡張 or `workflow-guard.sh` で block)
- bypass: `ECC_TEST_DESIGN_SKIP=1` で生成だけ行い agent skip

## 関連

- `/new-draft <slug>` — 設計 draft 起こし (本 command の前段)
- `/new-task <id> <slug>` — タスク化 (本 command で生成した test-design.md を参照、W4 で block 連動)
- `/design-review <slug>` — 設計レビュー fan-out (本 command と並行実行可能)
- template: `.claude/templates/docs/draft/_TEST_DESIGN_TEMPLATE.md`
- rule: `.claude/rules/workflow.md` (W5 で新設予定)
- 設計 draft: `docs/draft/workflow-enforcement.md` §3 W1 (v2 順序)
