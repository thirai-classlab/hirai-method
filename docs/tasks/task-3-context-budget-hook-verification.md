---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #3: context-budget hook 実発火検証

> Status: **🔲 未着手**
> 起案: 2026-05-12
> 関連: CB-verify (`5846925`)
> 設計起源: [context-budget-hook-verification.md](../draft/context-budget-hook-verification.md)

## 背景・目的

CB-verify (commit `5846925`) で context-budget hook の mode-loader.sh pipefail leak バグを根本修正。smoke 11/11 PASS は確認したが mock 環境のみで、**実セッションでの 60/80/95% 閾値発火** は未検証。回帰リスクあり。

## 仕様

`docs/draft/context-budget-hook-verification.md` §3 採用案 C (1 週間受動観察 + `.context-budget-state/` 集計 + 観察ゼロ時に再修正 draft 自動エスカレーション) に準拠。

## Wave 構成

| Wave | 内容 | 工数 | 依存 |
|:---:|:---|---:|:---|
| W1 | 観察開始日記録 (2026-05-12) + 受動観察期間設定 | 0.1h | — |
| W2 | 1 週間後 (2026-05-19) に `.claude/.context-budget-state/<session>.warned` を集計 | 0.3h | W1 |
| W3 | 発火履歴 report + ゼロ時は再修正 draft 起こし | 0.3h | W2 |

合計工数: 0.7 h (受動観察期間除く)

## 完了条件

- [ ] 2026-05-19 までに 60% 発火を 1 回以上観測 OR
- [ ] 観測ゼロの場合は再修正 draft `context-budget-hook-rework.md` を起こし next-actions.md entry 追加

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/.context-budget-state/` 読み取りのみ |
| migration | なし |
| 環境変数 | 変更なし |
| 互換性 | 観察のみで影響なし |

## 関連

- Draft: [context-budget-hook-verification.md](../draft/context-budget-hook-verification.md)
- 派生元: [next-actions.md](next-actions.md) entry #2
- 関連 commit: `5846925` `383f084`
