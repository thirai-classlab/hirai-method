> Layer A: [`workflow.md`](../../rules/workflow.md) §副産物 discharge (5 層強制機構) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 副産物 discharge 詳細 (Layer B)

副産物 discharge 5 層強制機構の表 / bypass は Layer A 参照。本 file は処理フロー / 関連 artifact / 違反パターン。

## 処理フロー

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

## 関連 artifact

- [`docs/tasks/next-actions.md`](../../../docs/tasks/next-actions.md) — registry 本体
- [`.claude/templates/docs/tasks/_TASK_TEMPLATE.md`](../../templates/docs/tasks/_TASK_TEMPLATE.md) — 派生 task セクション (W2 で追加)
- [`.claude/hooks/next-actions-surface.sh`](../../hooks/next-actions-surface.sh) (W1)
- [`.claude/hooks/byproduct-discharge-guard.sh`](../../hooks/byproduct-discharge-guard.sh) (W3)
- [`.claude/hooks/lib/next-actions-parser.sh`](../../hooks/lib/next-actions-parser.sh) — 共通 parser
- [`.claude/commands/discharge-byproduct.md`](../../commands/discharge-byproduct.md) (W4)
- [`.claude/tests/next-actions-hooks-smoke.sh`](../../tests/next-actions-hooks-smoke.sh) (W6, 9/9 PASS)
- 設計起源は採用プロジェクト側 `docs/draft/` を参照 (`.claude/` 単独で portable)

## 違反パターン

- 副産物を memory にのみ保存して draft 化しない → 層 1 違反 (registry 不在で発見不能)
- 「次セッションで対応」とコメントだけ残してセッション終了 → 層 4 (Stop hook) で 🔴 残存 BLOCK
- 発生源 task の `/finish-task` 完了前に処理せず後送り → 層 2 (`_TASK_TEMPLATE.md` 派生 task セクション) で task 完了時に検出
