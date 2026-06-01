> Layer A: [`workflow.md`](../../rules/workflow.md) §新規機能開発フロー (14-stage) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 14-stage 詳細 (Layer B)

新規機能開発フロー (`/new-feature <slug>`、`HC_WORKFLOW_STAGES_NEW` 14 stage) の各 stage 補足。stage 表本体・state JSON 進行は Layer A 参照。

## Stage 8 `tdd` の git log 既存 commit 確認義務

- **Step 計画前に `git log --all --grep <finding>` で既存 commit 解消確認必須** (2026-05-21 TM 修正での no-op 重複起動再発防止)
- **Task 最終 3 Steps = テスト設計レビュー → テスト合格 → リファクタリング (固定)**:
  - テスト設計レビューは 5+ reviewer 動的選定 + 修正収束まで反復 + 5 回上限
  - bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1`
  - 詳細: [task-management.md §タスク構造規範](../../rules/task-management.md#タスク構造規範-taskphasen-step-phase-中間階層廃止) 採用 6 条 4 [2026-05-25 採用]
  - 旧採用 5 条 4 を supersede

## Stage 10 `local-test` の Step 完了条件検証

- `<slug>.test-design.md` で ☑ にしたテスト全カテゴリを実行
- **Step 完了条件 (定量 or 観察可能事実) で test 結果を検証** (採用 5 条 3 起源)
- 検証コマンドは「`bash .claude/tests/foo-smoke.sh` exit 0」のように再現可能な形で書く

## Stage 13 `scenario-test` の UI 必須化

- **UI 変更を含む Task は E2E 必須** (検出基準: [task-management.md §UI 変更検出基準](../../rules/task-management.md#ui-変更検出基準))
- 採用 6 条 4 [2026-05-25 採用、旧採用 5 条 4 supersede] でビジュアル検証も併設必須化 (2026-05-27 採用、`agent-browser` skill + screenshot)
- E2E (機能フロー動作) とビジュアル検証 (見た目) は別レイヤ、両方 PASS で初めて UI Task 完了

## Stage 12 `ci-cd` の skip 条件

- `asana_enabled=false` プロジェクトは default skip
- skip した場合は state JSON の `skip_log` に `{stage: "ci-cd", reason: "asana-disabled", user_approved_at: <ISO-8601>}` を append
