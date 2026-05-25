# タスク一覧

> セッション開始時にこのファイルを読み込み、タスクの状態を復元すること。
> タスクの追加・削除・ステータス変更時は必ずこのファイルも更新すること。
>
> **保留・今後検討タスク**は [`parking-lot.md`](parking-lot.md) で管理。
> **設計（未承認）**は [`../draft/`](../draft/) で管理し、承認後にここへ追加。
> **副産物 / 派生 task 候補**（informal な TODO / 次アクション）は [`next-actions.md`](next-actions.md) で管理。設計起こし or parking-lot 移行 or 無視 の判断前段。

## 凡例 (Step Status / Task header 集約 Status 共通)

| アイコン | ステータス |
|:---:|:---|
| ✅ | 完了 |
| 🔄 | 進行中 |
| 🔲 | 未着手 |
| ⏸️ | 保留 |
| 📝 | 設計（未承認）/ batch planning 経路 B 中間状態 |

**Task header 集約 Status 計算規則** (採用 6 条 6):
- 全 Step ✅ → ✅
- Step に 🔄 / 🔲 混在 → 🔄
- 全 🔲 → 🔲
- 全 📝 → 📝
- ⏸️ 含む → ⏸️

## タスク

> **新採用 6 条 (2026-05-25)**: Task = Phase = N Step、Phase 中間階層廃止。
> 各 Task は header row + Step sub-rows で表現。概要欄規約:
> - Task: 「**何のため × 何をやる × 何ができる**」3 要素
> - Step: **作業概要**のみ (1-2 文)

| # | Step Status | Task / Step | 概要 | 詳細 |
|:---:|:---:|:---|:---|:---|
| <!-- 例: 1 --> | <!-- ✅ --> | <!-- **Task: <タスク名>** --> | <!-- Task 概要 (何のため × 何をやる × 何ができる) --> | <!-- [task-1-foo.md](task-1-foo.md) --> |
| <!-- 空 --> | <!-- ✅ --> | <!-- Step 1 --> | <!-- 作業概要 --> | <!-- 空 --> |
| <!-- 空 --> | <!-- 🔄 --> | <!-- Step 2 --> | <!-- 作業概要 --> | <!-- 空 --> |

<!--
記入ルール (採用 6 条準拠):
- # は Task 単位の連番。Task header row にのみ記載、Step sub-row は空欄
- Step Status 列: Task header は集約 status、Step sub-row は個別 status (📝/🔲/🔄/✅/⏸️)
- Task / Step 列: Task header は `**Task: <タスク名>**` (太字)、Step sub-row は `Step N` (Step 番号、N は 1 から連番)
- 概要列:
  - Task: 「<何のため> のため、<何をやる> する。完成すれば <何ができる>。」3 要素を 1 段落で
  - Step: 作業概要のみ (1-2 文)
- 詳細列: Task header にのみ task ファイル link、Step sub-row は空欄
- ステータス変更時は完了日 + commit hash + 主要 metric を Task 概要末尾に追記
  例: "（Step 1-3 完了 @ 2026-04-29、commit `abc1234`、+15 tests=215 PASS）"

記入例 (実 entry):
| 33 | ✅ | **Task: list-md plan-first 規範追加** | recall_poc plan-first 不在事案再発防止のため、task-management.md §plan-first を追加し batch planning 時の 📝 行先置きフロー 2 経路分岐 (経路 A/B) と凡例 📝 用途 (2 用途) を明文化する。完成すれば AI が batch planning 時に list.md plan-first 先置きを規範通り実行できるようになる。 | [task-33-list-md-plan-first-normative-rules.md](task-33-list-md-plan-first-normative-rules.md) |
|    | ✅ | Step 1 | task-management.md §plan-first 新規 subsection 追加 (経路 A/B 分岐 + 凡例 📝 用途明文化) | |
|    | ✅ | Step 2 | テスト設計レビュー (5 reviewer 並列 × 5 iter で strict 0-finding 収束) | |
|    | ✅ | Step 3 | テスト合格 (4-grep + smoke 11/11 + env override PASS) | |
|    | ✅ | Step 4 | リファクタリング (skip 明示: 規範文書追記のみ refactor 余地なし) | |
-->

## 依存関係図

```
<!-- 例:
Task 1 → Task 2 → Task 3
              → Task 4

(Phase 中間階層廃止後は Task 単位の DAG)
-->
```

## ステータス更新ルール

1. **新規追加**: 必ず `_TASK_TEMPLATE.md` (採用 6 条 準拠) から個別ファイルを起こすか、`docs/draft/` の承認済設計から移行する
2. **Step Status 個別更新**: 各 Step 完了時に Step sub-row の Status を 🔄 → ✅ に更新、Task header 集約 status を再計算
3. **🔄 → ✅ (Task 完了)**: `/finish-task <id>` で Task 完了条件 (build / test / docs 反映 + reviewer 5+ approve) を満たしてから更新。全 Step ✅ で Task header も ✅ に
4. **🔄 → ⏸️**: 保留事由を [`parking-lot.md`](parking-lot.md) に転記し、ここの行 (Task header + Step sub-rows 全て) は削除
5. **削除**: 不採用の場合も履歴として `parking-lot.md` の `❌` セクションに残す
