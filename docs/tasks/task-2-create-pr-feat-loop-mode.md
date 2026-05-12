---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #2: PR 作成 (feat/loop-mode → main)

> Status: **🔲 未着手**
> 起案: 2026-05-12
> 関連: #1 (workflow-enforcement umbrella)
> 設計起源: [create-pr-feat-loop-mode.md](../draft/create-pr-feat-loop-mode.md)

## 背景・目的

`feat/loop-mode` ブランチが本セッションで HEAD `e83a683`+ (19+ commits) まで進んだが、`main` 未反映。HIRAI メソッド workflow-enforcement (task #1) + 副産物 discharge 機構 (#3-#5) の配布前提が崩れている。

## 仕様

`docs/draft/create-pr-feat-loop-mode.md` §3 採用案 B (PR 作成 → `/reviewpr` 全 8 ルール → 修正 → merge commit + branch 削除) に準拠。

## Wave 構成

| Wave | 内容 | 工数 | 依存 |
|:---:|:---|---:|:---|
| W1 | `gh pr create --base main --head feat/loop-mode` で PR 作成 | 0.2h | — |
| W2 | `/reviewpr` 実行で 8 ルール + Critical Lessons + CI 確認 | 0.5h | W1 |
| W3 | レビュー指摘修正反映 | 0.3-1.0h | W2 |
| W4 | merge commit + branch 削除 | 0.2h | W3 |

合計工数: 1.2-1.9 h

## 完了条件

- [ ] main HEAD に本セッション全 commit 反映
- [ ] feat/loop-mode branch 削除済
- [ ] main から `/test-design` `/new-feature` `/module-review` 等が動作確認
- [ ] PR description に Critical Lessons 教訓 2 件記載

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | branch 全体（main マージ） |
| migration | なし |
| 環境変数 | 変更なし |
| 互換性 | feat/loop-mode → main の merge (破壊的変更なし、追加のみ) |

## 関連

- Draft: [create-pr-feat-loop-mode.md](../draft/create-pr-feat-loop-mode.md)
- 派生元: [next-actions.md](next-actions.md) entry #1
