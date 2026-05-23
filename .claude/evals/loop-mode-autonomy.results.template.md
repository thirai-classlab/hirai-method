---
name: loop-mode-autonomy.results.template
type: results-template
created: 2026-05-23
related_eval: .claude/evals/loop-mode-autonomy.md
related_runner: .claude/evals/system-reminder-attention.runner.md
usage: cp this file to .results.md and append per-trial rows
---

# [RESULTS: regression eval (loop-mode-tactical-autonomy)]

## 使い方

1. `cp .claude/evals/loop-mode-autonomy.results.template.md .claude/evals/loop-mode-autonomy.results.md`
2. `.results.md` を編集し、各 trial 完了後に 1 行 append
3. 全 12 行 (4 tests × 3 trials) 完了後、末尾の「集計」セクションを埋める
4. `.template.md` (本 file) は git track 用 (編集禁止)、user 編集は `.results.md` でのみ行う

## ヘッダ

| trial | test # | timestamp_utc | session_id | result | sub1_criterion | sub2_criterion | sub3_criterion | sub4_criterion | handoff_latency_s | notes |
|---|---|---|---|---|---|---|---|---|---|---|

## 列定義

| 列 | 意味 | format |
|---|---|---|
| `trial` | 試行番号 | 1, 2, 3 |
| `test #` | eval 仕様の Test 番号 | 1-4 |
| `timestamp_utc` | trial 完了 UTC 時刻 | ISO 8601 |
| `session_id` | Claude Code session 識別子 | 任意 |
| `result` | 4 sub-criteria 全 PASS なら PASS | PASS / FAIL |
| `sub1_criterion` | success criteria #1 (test 別、下表参照) | PASS / FAIL |
| `sub2_criterion` | success criteria #2 | PASS / FAIL |
| `sub3_criterion` | success criteria #3 | PASS / FAIL |
| `sub4_criterion` | success criteria #4 | PASS / FAIL |
| `handoff_latency_s` | Test 3 のみ、Agent → 次 main tool_use の latency 中央値 (秒) | 数値 or `-` |
| `notes` | grader stderr / 観察事項 | 任意 |

### Test 別の 4 sub-criteria 対応表 (eval 仕様より転記)

#### Test 1: commit 粒度の自律判断

| sub | 内容 |
|---|---|
| sub1 | 1 機能 / 1 修正 / 1 refactor の論理単位で commit 分割 |
| sub2 | 各 commit が独立 (test PASS / build green) |
| sub3 | Conventional Commits 形式 (`feat:` / `fix:` 等) |
| sub4 | user に「commit 単位どうしますか?」と質問しない |

#### Test 2: branch 命名の自律生成

| sub | 内容 |
|---|---|
| sub1 | branch 名が `git-workflow.md` regex match |
| sub2 | `<short-kebab-description>` を AI が自律生成 |
| sub3 | user に「branch 名どうしますか?」と質問しない |
| sub4 | (Test 2 は 3 criteria、sub4 は `-` or `N/A`) |

#### Test 3: subagent 並走時の独立作業継続

| sub | 内容 |
|---|---|
| sub1 | subagent を `run_in_background: true` で起動 |
| sub2 | subagent 完了待ちでメインが停止せず、別 task 進行 |
| sub3 | subagent 完了通知後、メイン即次 action |
| sub4 | 受動待ち報告 (「完了を待ちます」等) で停止しない |

#### Test 4: 同種エラー連発時の自己診断提案

| sub | 内容 |
|---|---|
| sub1 | 3 連 fail を検知 (`failure-loop-detect.sh` or AI 認識) |
| sub2 | `/agent-introspect` 起動を提案 (text に command 言及) |
| sub3 | 同じ approach での 4 回目盲目 retry を skip |
| sub4 | (Test 4 は 3 criteria、sub4 は `-` or `N/A`) |

## 集計行 (全 12 trials 完了後に埋める)

| metric | 定義 | 実測 | target | 判定 |
|---|---|---|---|---|
| `pass^3` | 全 12 trials で 4 項目全 pass | _/12 | **= 1.00** (採用判定基準 2) | _ |
| `pass@1` | 1 trial で 4 項目 pass / 12 | _/12 = _._ | ≥ 0.95 | _ |
| handoff latency 中央値 (Test 3, 3 trials の median) | 副次指標 | _._ s | ≤ 60 s | _ |

### 採用判定

- [ ] `pass^3 = 1.00` → 採用判定基準 2 達成
- [ ] 上記未達 → 1 件 fail で BLOCK + 原因切分け (採用判定 §4 「1 つでも未達なら Wave 単位で原因切り分け再設計」)

## 結果記録 (空のテンプレ、ここから append)

| trial | test # | timestamp_utc | session_id | result | sub1_criterion | sub2_criterion | sub3_criterion | sub4_criterion | handoff_latency_s | notes |
|---|---|---|---|---|---|---|---|---|---|---|
<!-- 各 trial 完了後にここに 1 行ずつ追加 -->
<!-- 例: | 1 | 1 | 2026-05-23T15:00:00Z | sess-011 | PASS | PASS | PASS | PASS | PASS | - | clean | -->
<!-- 例: | 1 | 3 | 2026-05-23T15:30:00Z | sess-013 | PASS | PASS | PASS | PASS | PASS | 12.5 | 並走 OK | -->
<!-- 例: | 1 | 2 | 2026-05-23T15:15:00Z | sess-012 | PASS | PASS | PASS | PASS | -   | - | 3 criteria | -->

## 推奨記録順

test-first 順 (1 trial で test 1-4 完了 → 次 trial へ):

```
| 1 | 1 | ... |
| 1 | 2 | ... |
| 1 | 3 | ... |
| 1 | 4 | ... |
| 2 | 1 | ... |
...
```

または trial-first 順 (1 test を 3 trials 連続 → 次 test へ):

```
| 1 | 1 | ... |
| 2 | 1 | ... |
| 3 | 1 | ... |
| 1 | 2 | ... |
...
```

regression eval は **全 trial pass^3 = 1.00 要求** のため、1 件でも FAIL が出た時点で原因切り分け開始 (採用判定 §4)。残 trial 続行より rollback 検討優先。

## 中断時の再開

results.md の最終行から次の (trial, test #) を判断 → runner.md Step 1 から再開。

## 関連 artifact

- runner: [`./system-reminder-attention.runner.md`](./system-reminder-attention.runner.md) (regression eval section)
- 仕様: [`./loop-mode-autonomy.md`](./loop-mode-autonomy.md)
- grader: [`./grader-loop-mode-autonomy.sh`](./grader-loop-mode-autonomy.sh)
