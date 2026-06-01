> Layer A: [`workflow.md`](../../rules/workflow.md) (全 §共通の起源 / commit hash) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 (Layer B)

workflow.md 各規範 (W1-W4 / draft-flow-guard / 副産物 discharge / Session 永続化 / テスト設計レビュー収束条件 / 規範文書 honor system 降格) の起源・commit hash・採用判断の集約。

- **W1-W4 規範化**: 設計起源は採用プロジェクト側 `docs/draft/workflow-enforcement.md` v2 §3 W1〜W4 (`.claude/` 単独で portable、本 file は採用後の規範を保持)
- **draft-flow-guard.sh 元機能 (`docs/` 直下 block)**: 起源 commit `6ed9337`、後続緩和 task-40 (2026-05-26) → 撤廃 (2026-05-28、user 直接指示)
- **task-40 拡張 (`.claude/rules/*.md` 等 BLOCK)**: 2026-05-26 採用、設計起源: `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md`、2026-05-28 緩和で撤廃
- **副産物 discharge 5 層強制機構**: task #5 で実装、W1 (next-actions-surface) / W2 (`_TASK_TEMPLATE.md`) / W3 (byproduct-discharge-guard) / W4 (`/discharge-byproduct`) / W6 (smoke) の段階実装
- **Session 永続化と PM Orchestration**: task #7 で実装、SuperClaude plugin の `/sc:save` `/sc:load` `/sc:pm` を `.claude/` 単独で portable な自前実装に置換
- **テスト設計レビュー収束条件 (CRITICAL+HIGH+MEDIUM=0)**: 2026-05-26 採用 6 条 4 起源、`task-management.md` 採用 5 条 4 から拡張
- **規範文書 honor system 降格 (2026-05-28)**: user 直接指示「規範文書 path は新規 Write / 既存 Edit とも hook で PASS」、機械強制 BLOCK 撤廃、規律として `modes.md` 遵守事項 2 例外条項「規範変更」で残置
- 各規範の commit hash / 採用判断は git log + 関連 draft / 副産物 entry 参照
