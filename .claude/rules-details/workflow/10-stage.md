> Layer A: [`workflow.md`](../../rules/workflow.md) §既存機能修正フロー (10-stage) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 10-stage 詳細 (Layer B)

既存機能修正フロー (`/modify-feature <slug>`、`HC_WORKFLOW_STAGES_MODIFY` 10 stage) の full 表 + 各 stage 補足。stage 名の SSoT は env `HC_WORKFLOW_STAGES_MODIFY` (= `harness-config.yml` の `workflow_stages_modify`) で、本表と完全一致する。

## 10-stage full 表

| # | stage 名 | 役割 | 起動 command / 連携 |
|---:|---|---|---|
| 1 | `branch-decision` | 影響範囲特定 + branch type (`feat`/`fix`/`refactor`/`hotfix`) 決定 | user 対話 |
| 2 | `checkout` | branch 切替 (regex 検証: git-workflow.md 規約準拠) | `git switch` |
| 3 | `recover-design` | 既存 task / draft 探索、不完全なら逆引きで draft 起こし | Glob + Read |
| 4 | `pre-test` | **修正前** 全テスト PASS を baseline 記録 (regression 検出基準) | test runner |
| 5 | `redesign` | draft §3 に「変更前 / 変更後」差分追記 | architect agent |
| 6 | `retest-design` | `/test-design` 再実行で差分部 MECE 再評価 | `/test-design <slug>` |
| 7 | `tdd` | 新規 test → 最小修正 → refactor (subagent 経由) | TDD ループ |
| 8 | `module-review` | モジュール毎に 3 観点レビュー | `/module-review <module>` |
| 9 | `full-test` | 全 test PASS + pre-test baseline regression 検出 | test runner |
| 10 | `system-review` | 全体整合性レビュー → merge 可否判断 → `/finish-task` 案内 | `/system-review` |

各 stage 完了時、メインが state JSON の `current_stage` を次 stage に進め `completed_stages` に追加 (workflow_type=`modify`)。

## Stage 7 `tdd` の git log 検証

- **Wave 計画前に `git log --all --grep <finding>` で既存 commit 解消確認必須** (2026-05-21 TM 修正での no-op 重複起動再発防止)

## `/new-feature` との差分詳細

`/new-feature` (14-stage) との主要差分: 要件定義 / `design-review` / `task-creation` / `ci-cd` / `scenario-test` は省略され、代わりに `recover-design` / `pre-test` / `retest-design` が入る。

- 要件定義 (Stage 1 `requirements`) → 不要 (既存機能の修正のため)
- `design-review` (Stage 5 fan-out レビュー) → 不要 (差分のみ retest-design で再評価)
- `task-creation` (Stage 7 task-creation) → branch-decision + checkout で代替
- `ci-cd` (Stage 12) → 不要 (既存 CI 流用)
- `scenario-test` (Stage 13) → full-test (Stage 9) で代替

代わりに以下が入る:
- `recover-design` (Stage 3) — 既存 task / draft を探索、不完全なら逆引き起こし
- `pre-test` (Stage 4) — 修正前 baseline 記録
- `retest-design` (Stage 6) — 差分部 MECE 再評価

詳細比較は [`modify-feature.md`](../../commands/modify-feature.md) の「/new-feature との差分」セクション参照。
