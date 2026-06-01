> Layer A: [`workflow.md`](../../rules/workflow.md) §既存機能修正フロー (10-stage) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 10-stage 詳細 (Layer B)

既存機能修正フロー (`/modify-feature <slug>`、`HC_WORKFLOW_STAGES_MODIFY` 10 stage) の各 stage 補足。stage 表本体は Layer A 参照。

## Stage 7 `tdd` の git log 検証

- **Wave 計画前に `git log --all --grep <finding>` で既存 commit 解消確認必須** (2026-05-21 TM 修正での no-op 重複起動再発防止)

## `/new-feature` との差分詳細

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
