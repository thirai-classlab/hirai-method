# タスク一覧

> セッション開始時にこのファイルを読み込み、タスクの状態を復元すること。
> タスクの追加・削除・ステータス変更時は必ずこのファイルも更新すること。
>
> **保留・今後検討タスク**は [`parking-lot.md`](parking-lot.md) で管理。
> **設計（未承認）**は [`../draft/`](../draft/) で管理し、承認後にここへ追加。

## 凡例

| アイコン | ステータス |
|:---:|:---|
| ✅ | 完了 |
| 🔄 | 進行中 |
| 🔲 | 未着手 |
| ⏸️ | 保留 |
| 📝 | 設計（未承認） |

## タスク

| # | ステータス | Phase | 概要 | 依存 | 詳細 |
|:---:|:---:|:---|:---|:---|:---|
| 1 | 🔄 | workflow-enforcement | W1-W6 umbrella: 設計レビュー fan-out / テスト設計 MECE / workflow 強制 / リファクタリング強制 / Asana mode 管理 (W1 完了 @ commit `1e8aa0e`、W2 着手予定) | — | [task-1-workflow-enforcement.md](task-1-workflow-enforcement.md) |

<!--
記入ルール:
- # は連番。同フェーズ内で複数タスクなら "11.3a" のような sub-id 可
- ステータス変更時は完了日 + commit hash + 主要 metric を「概要」末尾に追記
  例: "（W1-W3 完了 @ 2026-04-29、commit `abc1234`、+15 tests=215 PASS）"
- 依存は "—"（なし）/ "#N" / "Phase N" 形式
- 詳細は個別ファイルへの相対リンク（無ければ "—"）
-->

## 依存関係図

```
<!-- 例:
Phase 1 → Phase 2 → Phase 3
                 → Phase 4
-->
```

## ステータス更新ルール

1. **新規追加**: 必ず `_TASK_TEMPLATE.md` から個別ファイルを起こすか、`docs/draft/` の承認済設計から移行する
2. **🔄 → ✅**: `/finish-task <id>` で完了 3 条件（build / test / docs 反映）を満たしてから更新
3. **🔄 → ⏸️**: 保留事由を [`parking-lot.md`](parking-lot.md) に転記し、ここの行は削除
4. **削除**: 不採用の場合も履歴として `parking-lot.md` の `❌` セクションに残す
