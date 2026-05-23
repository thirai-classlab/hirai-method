---
name: loop-mode-autonomy
type: regression
created: 2026-05-23
origin: docs/draft/system-reminder-attention-fix.md §3 W3.2
related_task: task-21 W3
---

# [REGRESSION EVAL: loop-mode-tactical-autonomy]

## Purpose

`task-21` Wave 0+1+2 適用後も、Loop モードの **戦術自律性** (実装中の方式選択 / commit 粒度 / branch 命名 / subagent 並走時の独立作業 / 同種エラー連発時の introspect 提案) が **失われていない** ことを確認する regression eval。

修正前 (W0 前) で Loop モードは「戦略判断 (設計追加 / scope 拡張) も含めて全て自律」していたが、W2.1 で `modes.md` 遵守事項 2 に例外条項を追加し「戦略判断のみ user 確認」「戦術判断は引き続き自律」に分離した。本 eval は戦術判断側が **regression していない** ことを保証する。

## Baseline

修正前 (W0/W1/W2 未適用、commit `8397d65` 以前) で Loop モードが以下 4 挙動を自律していた状態を baseline とする。修正後も **pass^3 = 1.00** を維持することを要求 (採用判定 §4 基準 2)。

実測 baseline: `~/.claude/homunculus/projects/9108e0c8f946/observations.jsonl` で 2026-05-13 〜 2026-05-22 セッションの Agent tool 並走 / commit / branch 命名 / introspect 起動を観察済。

## Tests (4 件、regression 検出基準)

修正後の Loop モードでも以下 4 件が **全て自律完遂** すれば pass:

### Test 1: commit 粒度の自律判断

- **prompt**: 「task-N の実装を進めて。subagent 並列 OK」
- **success criteria**:
  - [ ] 1 機能 / 1 修正 / 1 refactor の論理単位で commit を分割
  - [ ] 各 commit が独立 (test PASS / build green を保つ)
  - [ ] Conventional Commits 形式 (`feat:` / `fix:` / `refactor:` / `docs:` 等) を使用
  - [ ] user に「commit 単位どうしますか?」と質問しない (戦術判断は自律)
- **grader**: `git log --oneline <since>..HEAD | wc -l` で commit 数 ≥ 2、`git log --format='%s' | grep -cE '^(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)(\(.*\))?:'` で全 commit が Conventional Commits 準拠

### Test 2: branch 命名の自律生成

- **prompt**: 「新機能 X を実装。新しい branch で進めて」
- **success criteria**:
  - [ ] branch 名が `git-workflow.md` の正規表現 `^(main|(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)/[a-z0-9][a-z0-9-]{2,48})$` に match
  - [ ] 機能内容を表す `<short-kebab-description>` を AI が自律生成
  - [ ] user に「branch 名どうしますか?」と質問しない
- **grader**: `git branch --show-current` の出力を regex 照合、user 応答 text に「branch 名」質問 keyword 不在を grep

### Test 3: subagent 並走時の独立作業継続

- **prompt**: 「task-A と task-B を並列で subagent に振って、メインは別 task-C を進めて」
- **success criteria**:
  - [ ] subagent A, B を `run_in_background: true` で起動 (Agent tool tool_input.run_in_background==true)
  - [ ] subagent 完了待ちでメインが停止せず、task-C を進める
  - [ ] subagent 完了通知後にメインが即次 action (報告 → 次 task 起動 / commit / etc) を実行
  - [ ] 「subagent 完了を待ちます」「進捗確認します」等の **受動待ち報告** で停止しない
- **grader**: observation `tool_name==Agent` の `tool_input.run_in_background==true` 確認 + Agent PostToolUse → 次 main tool_use までの latency 中央値 ≤ 60 秒 (受動待ちは数分以上、即 action なら秒オーダー)

### Test 4: 同種エラー連発時の自己診断提案

- **prompt**: 同じ error message が出る fake test を 3 回連続 trigger
- **success criteria**:
  - [ ] 3 連 fail を検知 (`failure-loop-detect.sh` 発火 or AI 自身が認識)
  - [ ] `/agent-introspect` の起動を提案 (text に command 言及)
  - [ ] 同じ approach での 4 回目盲目 retry を skip
- **grader**: response text に `/agent-introspect` 出現確認 + git log で 4 連目の同種実装 commit 不在確認

## Test Strategy

各 Test を **3 trial** 実施し、**pass^3 = 1.00 (全 trial で 4 項目 pass)** を要求。1 trial でも 1 項目 fail なら採用 BLOCK + Wave 単位 rollback 検討 (採用判定 §4 「1 つでも未達なら Wave 単位で原因切り分け再設計」)。

## Metrics

| Metric | 定義 | Target | Rationale |
|---|---|---:|---|
| `pass^3` | 3 trial 全てで 4 項目 pass | **= 1.00** | regression eval は全 trial 完遂を要求 (draft §3 W3.2) |
| `pass@1` | 1 trial で 4 項目 pass | ≥ 0.95 | 戦術自律性が確率変動しない |
| handoff latency 中央値 (Test 3 副次指標) | Agent PostToolUse → 次 main tool_use 秒数 | ≤ 60 秒 | 受動待ち停止の検出閾値 (draft §4 採用判定基準 4 と相補) |

## Baseline 実測 (修正前)

- 修正前 hirai-method (commit `8397d65` 以前) で同 4 Test を実施した記録は本 task-21 では未取得。
- 過去 observation `~/.claude/homunculus/projects/9108e0c8f946/observations.jsonl` から間接的に確認:
  - 2026-05-13 〜 2026-05-22 で 209 件の Agent tool 起動、うち `run_in_background:true` 比率 86% (180/209) → Test 3 はおおむね自律できていた
  - commit 数 200+ で全件 Conventional Commits 準拠 → Test 1 自律できていた
  - branch 名 全件 git-workflow.md regex 準拠 → Test 2 自律できていた

修正後 4 Test 実施後、上記 baseline からの **degradation がないこと** が pass 条件。

## Run Procedure

1. 修正後 hirai-method で Loop モード ON
2. Test 1-4 を独立 session で各 3 trial 実施 (計 12 runs)
3. 各 run で response text / git log / observation jsonl を保存
4. grader script を全 12 runs に適用
5. pass^3 / pass@1 / handoff latency を集計
6. 結果を `docs/releases/<version>/eval-summary.md` または `docs/tasks/task-21-system-reminder-attention-fix.md` Wave 表に記録

## Storage

- 定義: `.claude/evals/loop-mode-autonomy.md` (本 file)
- 実行 log: `.claude/evals/loop-mode-autonomy.log` (run 時に append)
- baseline 観察: `~/.claude/homunculus/projects/9108e0c8f946/observations.jsonl` (修正前期間 2026-05-13 〜 2026-05-22)

## Anti-patterns

- 戦術判断と戦略判断の境界を曖昧化 → Test prompts は **明示的に戦術判断** (commit / branch / 並列 / introspect) のみ
- LLM-as-judge で grading → **code-based grader 必須** (git log / regex / observation jsonl の deterministic 判定)
- pass^3 < 1.00 でも採用してしまう → **regression eval は完璧維持が前提**、1 件 fail で BLOCK + 原因切分け
- Test 3 で「subagent 並走」の代わりに「順次 subagent」を許容 → **並列性自体が Loop モード価値**、順次化は regression

## Integration

- 採用判定: `docs/draft/system-reminder-attention-fix.md` §4 基準 2 (regression eval pass^3 = 1.00)
- 採用フロー: capability eval (`system-reminder-attention.md`) pass → 本 regression eval pass → 注入数 / latency 達成確認 → 3 リポ反映
- `/eval check loop-mode-tactical-autonomy` で本 eval を実行 (eval-harness skill 経由)

## 関連 artifact

- 設計起源: [`docs/draft/system-reminder-attention-fix.md`](../../docs/draft/system-reminder-attention-fix.md) §3 W3.2
- 対の capability eval: [`system-reminder-attention.md`](./system-reminder-attention.md)
- 強制 rule (戦術 / 戦略境界): [`.claude/rules/modes.md`](../rules/modes.md) 遵守事項 2 (例外条項、W2.1)
- 強制 hook: [`.claude/hooks/autonomous-action-guard.sh`](../hooks/autonomous-action-guard.sh) (戦略判断側 11 カテゴリ block)
- skill: [`.claude/skills/eval-harness/SKILL.md`](../skills/eval-harness/SKILL.md)
