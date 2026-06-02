---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai"
---

<!--
total_steps: 5
-->

# Task #75: parallel-subagent-reminder escalating 強化 (連続単発 streak)

> Status: **🔲 未着手**
> 起案: 2026-06-02
> 設計起源: [parallel-subagent-escalating-reminder.md](../draft/parallel-subagent-escalating-reminder.md) ✅承認済 (approved_at 2026-06-02、AskUserQuestion で escalating approach 選択)

## Task ゴール

`parallel-subagent-reminder.sh` が連続単発起動 (parallelizable なのに逐次) の streak を検出し、reminder を tier 1 (現状 hint) → tier 2 (強) → tier 3 (Workflow 誘導) に段階注入する。並列/Workflow 起動で streak リセット。BLOCK しない (fail-open 維持)。advisory を無視し続けにくくし、並列委譲を促進する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | 既存 `parallel-subagent-reminder.sh` (task-38) の escalation 強化、新規依存なし | — |

## Task 作業概要

- `parallel-subagent-reminder.sh` の (A) 並列性 reminder 判定部に連続単発 streak 算出を追加 (既存 recent.json の近接 ts クラスタ判定 or 専用 streak state)
- tier 別 message 分岐 (1=現状 / 2=強 reminder / 3=Workflow 誘導 task-68)
- 並列 batch (近接 ts 複数 entry) / Workflow / TTL / 除外 keyword で streak リセット
- 新 env `HC_PARALLEL_SUBAGENT_STREAK_TIER2`/`_TIER3` (閾値 override、default 2/3)
- 既存 lock / fail-open / TTL / feature toggle / agent type reminder (B) は behavior-preserving

## Task 完了条件 (DoD)

- [ ] 連続単発起動で reminder が tier 1→2→3 に escalate
- [ ] 並列/Workflow 起動で streak リセット (次回 tier 1)
- [ ] BLOCK しない (fail-open 維持)、feature toggle / bypass / agent type reminder 不変
- [ ] smoke で escalation + リセット + regression 0
- [ ] reviewer approve (テスト設計レビュー)
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> parallel-subagent-reminder の advisory が無視され続け逐次起動が常態化する問題を解消するため、連続単発起動 streak を検出し reminder を tier 1→2→3 (現状→強→Workflow 誘導) に段階注入する。完成すれば並列委譲が促進され、independent 作業の wall-clock が短縮し、3+ fan-out が Workflow へ誘導される。

## 設計

draft §3 採用案 (escalating reminder) + §4 実装方針 + §5 テスト + §7 リスク緩和を SSoT とする。BLOCK でなく advisory escalation (genuine 逐次依存もあるため fail-open 維持)。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | streak 算出ロジック実装 (recent.json 近接 ts クラスタ or 専用 streak state) + tier 閾値 env | 0.6h | — |
| 2 | 🔲 | tier 別 message 分岐 (1 現状 / 2 強 / 3 Workflow 誘導) + 並列/Workflow 検出で streak リセット | 0.6h | Step 1 |
| 3 | 🔲 | smoke 拡張 (streak 1/2/3 escalation + リセット + 除外/feature OFF/bypass regression 0) | 0.5h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定、streak 誤判定リスク + behavior-preserving cross-check | 0.4h | Step 1-3 |
| 5 | 🔲 | (テスト合格 + リファクタ) smoke regression 0 + 3 観点 refactor 判定 | 0.3h | Step 4 |

合計: **~2.4h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/parallel-subagent-reminder.sh` (escalation 追加) + `.claude/tests/parallel-subagent-reminder-smoke.sh` (escalation case) + 場合により streak state file |
| migration | なし |
| 環境変数 | 新規 `HC_PARALLEL_SUBAGENT_STREAK_TIER2`/`_TIER3` (default 2/3) |
| 互換性 | advisory escalation 追加のみ、BLOCK しない。feature toggle / bypass / agent type reminder 不変 |
