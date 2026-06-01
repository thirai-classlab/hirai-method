> Layer A: [`task-management.md`](../../rules/task-management.md) §開発開始時の必読義務 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 開発開始時必読 詳細 (Layer B)

## 起源

user 指示「list.md やタスク詳細へ後続のタスクへどう影響するのかを意識させるために list.md へ依存先タスク (table 列追加)、タスク詳細.md へどのように影響するのかとタスク.md へのリンクを表記すること。開発時はそれとリンク先を必ず読むこと」(2026-05-26)。

## 違反検出 (現状 honor system、将来機械強制化)

| 段階 | 検出方法 | 動作 |
|---|---|---|
| **現状 (2026-05-26〜)** | honor system | main agent が `/start-task` 直後に必読対象を Read する宣言 (Why × 5 で「依存先 task-N1 / N2 の影響を確認するため、それぞれの task.md + draft を Read する」と明示) |
| **将来 (案、別 task で起票)** | `task-rule-guard.sh` 拡張 | `/start-task <id>` 検出時に対象 task ファイル + 依存先 task ファイルが本 session で Read 済か判定、未 Read なら warn 注入 (block しない、honor system 維持で過剰防止) |

## 効果 (3 層 DAG)

- 後続タスクへの影響を **着手前に意識** することで、依存先の設計判断 / 完了状態を踏まえた実装が可能
- 「依存先 task は完了済と思い込み実装着手 → 実は ⏸️ 保留中で前提崩壊」のような事故を構造的に防止
- list.md 依存先列で **DAG 視覚化** + task.md 依存先 section で **影響内容明示** + 開始時必読義務で **実 Read 強制** の 3 層で依存関係の暗黙知化を防ぐ
