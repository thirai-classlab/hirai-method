---
name: system-reminder-attention.results.template
type: results-template
created: 2026-05-23
related_eval: .claude/evals/system-reminder-attention.md
related_runner: .claude/evals/system-reminder-attention.runner.md
usage: cp this file to .results.md and append per-trial rows
---

# [RESULTS: capability eval (task-management-recognition)]

## 使い方

1. `cp .claude/evals/system-reminder-attention.results.template.md .claude/evals/system-reminder-attention.results.md`
2. `.results.md` を編集し、各 trial 完了後に 1 行 append
3. 全 30 行 (10 prompts × 3 trials) 完了後、末尾の「集計」セクションを埋める
4. `.template.md` (本 file) は git track 用 (編集禁止)、user 編集は `.results.md` でのみ行う

## ヘッダ

| trial | prompt # | timestamp_utc | session_id | result | sub1_path | sub2_approval | sub3_command | sub4_flow_mention | notes |
|---|---|---|---|---|---|---|---|---|---|

## 列定義

| 列 | 意味 | format |
|---|---|---|
| `trial` | 試行番号 | 1, 2, 3 |
| `prompt #` | eval 仕様の prompt 番号 | 1-10 |
| `timestamp_utc` | trial 完了 UTC 時刻 | ISO 8601 (例: `2026-05-23T14:32:15Z`) |
| `session_id` | Claude Code session 識別子 | 任意 (例: `sess-001` or hash) |
| `result` | 4 sub-criteria 全 PASS なら PASS | PASS / FAIL |
| `sub1_path` | `docs/draft/<slug>.md` Write 確認 | PASS / FAIL |
| `sub2_approval` | user 承認要求メッセージあり | PASS / FAIL |
| `sub3_command` | `/new-task` or `/new-draft` 提示 | PASS / FAIL |
| `sub4_flow_mention` | 「設計→承認→タスク追加」フロー言及 | PASS / FAIL |
| `notes` | 自由記述 (grader stderr / 観察事項) | 任意 |

## 集計行 (全 30 trials 完了後に埋める)

| metric | 定義 | 実測 | target | 判定 |
|---|---|---|---|---|
| `pass@1` | 1 試行で 4 項目全 pass の trial 数 / 30 | _/30 = _._ | ≥ 0.80 | _ |
| `pass@3` | 同一 prompt の 3 trials のうち 1 回以上 4 項目 pass の prompt 数 / 10 | _/10 = _._ | **≥ 0.95** (採用判定基準 1) | _ |
| `pass^3` | 同一 prompt の 3 trials すべて 4 項目 pass の prompt 数 / 10 | _/10 = _._ | ≥ 0.70 | _ |

### 採用判定

- [ ] `pass@3 ≥ 0.95` → 採用判定基準 1 達成
- [ ] 上記未達 → Wave 単位で原因切り分け再設計 (採用判定 §4)

## 結果記録 (空のテンプレ、ここから append)

| trial | prompt # | timestamp_utc | session_id | result | sub1_path | sub2_approval | sub3_command | sub4_flow_mention | notes |
|---|---|---|---|---|---|---|---|---|---|
<!-- 各 trial 完了後にここに 1 行ずつ追加 -->
<!-- 例: | 1 | 1 | 2026-05-23T14:30:00Z | sess-001 | PASS | PASS | PASS | PASS | PASS | clean run | -->

## 推奨記録順

trial-first 順 (1 trial で prompt 1-10 完了 → 次 trial へ):

```
| 1 | 1 | ... |
| 1 | 2 | ... |
...
| 1 | 10 | ... |
| 2 | 1 | ... |
...
| 3 | 10 | ... |
```

または prompt-first 順 (1 prompt を 3 trials 連続 → 次 prompt へ):

```
| 1 | 1 | ... |
| 2 | 1 | ... |
| 3 | 1 | ... |
| 1 | 2 | ... |
...
```

どちらでも grader 結果は同じ、user の運用都合で選択可。

## 中断時の再開

results.md の最終行から次の (trial, prompt #) を判断 → runner.md Step 1 から再開。

## 関連 artifact

- runner: [`./system-reminder-attention.runner.md`](./system-reminder-attention.runner.md)
- 仕様: [`./system-reminder-attention.md`](./system-reminder-attention.md)
- grader: [`./grader-system-reminder-attention.sh`](./grader-system-reminder-attention.sh)
