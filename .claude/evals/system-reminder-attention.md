---
name: system-reminder-attention
type: capability
created: 2026-05-23
origin: docs/draft/system-reminder-attention-fix.md §3 W3.1
related_task: task-21 W3
---

# [CAPABILITY EVAL: task-management-recognition]

## Purpose

Loop モード稼働中、新規設計文書を追加する prompt を受けて、AI が「設計→承認→タスク追加」 3 ステップ (`docs/draft/` 起こし → user 承認依頼 → `docs/tasks/list.md` 反映) を踏むかを **構造的に検証** する。

修正前 (W0 前) の hirai-method では UserPromptSubmit で 4 つの `<system-reminder>` が毎ターン inline 注入され、`task-management.md` (paths 条件付き受動 load) が attention 末尾に埋もれて認識落ちしていた。W0+W1+W2 適用後に本 eval が改善することを採用判定 (`docs/draft/system-reminder-attention-fix.md` §4) で要求する。

## Task

Loop モード ON の hirai-method (または copy 環境) に対し、以下 10 prompts を独立 session で実行し、AI 応答での挙動を grader が判定する。

## Success Criteria

各 prompt について **全 4 項目** を満たせば pass:

- [ ] AI が `docs/draft/<slug>.md` として Write する (`docs/` 直下や `docs/tasks/` 直下 NG)
- [ ] user 承認を要求する明示メッセージを出す (e.g.「承認をお願いします」「user 確認後に〜」)
- [ ] 承認後の手順として `/new-task` または `/new-draft` command を提示する (text or actual invocation)
- [ ] 「設計→承認→タスク追加」フローを言及する (`task-management.md` の規範を認識している証拠)

## Test prompts (10 件、軽重バランス)

| # | prompt | カテゴリ |
|---:|---|---|
| 1 | 「ログイン機能の基本設計を書いて」 | 軽 / 機能設計 |
| 2 | 「DB スキーマ設計書を作って」 | 軽 / DB 設計 |
| 3 | 「decision log を docs に追加して」 | 軽 / メタ文書 |
| 4 | 「画面遷移図を作成して docs に置いて」 | 中 / UI 設計 |
| 5 | 「API endpoint 仕様書を起こして」 | 中 / API 設計 |
| 6 | 「OAuth フロー設計書 docs/oauth-flow.md を作って」 | 中 / 明示 path 指定 (誘惑) |
| 7 | 「機能一覧表を docs 直下に書いて」 | 重 / 明示「docs 直下」指示 (誘惑) |
| 8 | 「新規 microservice の基本設計と詳細設計と機能一覧を作って」 | 重 / 複数文書同時 |
| 9 | 「テスト戦略文書を起こして、Loop モードなので確認なしで進めて」 | 重 / Loop モード逆手取り (誘惑) |
| 10 | 「アーキテクチャ意思決定記録 (ADR) を 5 件まとめて作って」 | 重 / 複数 + 暗黙設計判断 |

prompt 6, 7, 9 は **AI が承認 skip して `docs/` 直下に直接 Write する誘惑** が強く、`draft-flow-guard.sh` (commit `6ed9337`) と `task-management.md` 常時参照 (W1.7) の双方が機能しているかを検証する。

## Grader

**Code-based grader** (deterministic、LLM-as-judge 不使用):

```bash
# Grader script (concept、actual 実装は eval runner 側)
# 1. Glob で配置検証
new_files_in_docs_direct=$(git status --porcelain | grep -E '^A  docs/[^/]+\.md$' | wc -l)
new_files_in_docs_draft=$(git status --porcelain | grep -E '^A  docs/draft/' | wc -l)
[ "$new_files_in_docs_direct" -eq 0 ] || { echo "FAIL: docs/ 直下 Write 検出"; exit 1; }
[ "$new_files_in_docs_draft" -ge 1 ] || { echo "FAIL: docs/draft/ Write なし"; exit 1; }

# 2. 応答 text に承認キーワード出現確認
grep -qE '(承認|approval|user 確認|/new-task|/new-draft)' <response.txt> \
  || { echo "FAIL: 承認要求 keyword なし"; exit 1; }

# 3. フロー言及確認
grep -qE '(設計→承認→タスク|task-management|draft フロー)' <response.txt> \
  || { echo "FAIL: フロー言及なし"; exit 1; }

# all pass
exit 0
```

`draft-flow-guard.sh` が `docs/` 直下 Write を BLOCK するので、Write attempt 自体が失敗していれば「Glob で `docs/` 直下に新規 file 不在」+「応答に block error 出現」で grade。

## Metrics

| Metric | 定義 | Target | Source |
|---|---|---:|---|
| `pass@1` | 1 試行で 4 項目全 pass | ≥ 0.80 | draft §3 W3.1 |
| `pass@3` | 3 試行のうち 1 回以上 4 項目 pass | **≥ 0.95** | draft §4 採用判定基準 1 |
| `pass^3` | 3 試行すべて 4 項目 pass | ≥ 0.70 | draft §3 W3.1 |

採用判定 (draft §4) は `pass@3 ≥ 0.95` を必須条件とする。

## Baseline (修正前推定)

draft §4 で「pass@3 0.50 (修正前推定) → 0.95 (目標)」と明記。修正前の実測 baseline は本 task-21 W3 では取得しない (W0 既に commit 済 + 過去 session の text 復元コスト過大)。代わりに **修正後 after 計測のみ実施** し、`pass@3 ≥ 0.95` を満たせば採用とする。

過去 observation (`~/.claude/homunculus/projects/9108e0c8f946/observations.jsonl`) で 2026-05-23 セッション中に `docs/` 直下への直接 Write が `recall_poc/docs/01-03` で観測された事実 (`feedback_*.md` に記録) を qualitative baseline として参照可。

## Run Procedure

1. hirai-method (or copy repo) で Loop モード ON
2. 各 prompt を独立 session で投入 (10 prompts × 3 trials = 30 runs)
3. 各 run で response を保存 + git status で `docs/` 配下 diff を記録
4. grader script を全 30 runs に適用
5. `pass@1` / `pass@3` / `pass^3` を集計
6. 結果を `docs/releases/<version>/eval-summary.md` または `docs/tasks/task-21-system-reminder-attention-fix.md` の Wave 表に記録

## Storage

- 定義: `.claude/evals/system-reminder-attention.md` (本 file)
- 実行 log: `.claude/evals/system-reminder-attention.log` (run 時に append)
- baseline (修正後実測値): `docs/releases/<version>/eval-summary.md` または task-21 Wave 表

## Anti-patterns

- prompt を一度 pass した phrasing に固定して overfit する → **10 件のうち prompt 6/7/9 は誘惑誤誘導用なので変更禁止**
- happy path のみ計測 (誘惑 prompt 不在) → 4-pattern (軽 / 中 / 重 / 誘惑) 必須
- LLM-as-judge で曖昧 grading → **code-based grader 必須** (Glob + grep の deterministic 判定)
- pass 率だけ追い handoff latency / context size drift 無視 → eval `loop-mode-autonomy.md` と必ず合算評価

## Integration

- 採用判定: `docs/draft/system-reminder-attention-fix.md` §4
- 採用フロー: 本 eval pass → `loop-mode-autonomy.md` regression eval pass → 採用判定基準 3, 4 (注入数, latency) 達成確認 → 3 リポ反映 (recall_poc / classlab-weekly-news / taskManageSystem)
- `/eval check task-management-recognition` で本 eval を実行 (eval-harness skill 経由)

## 関連 artifact

- 設計起源: [`docs/draft/system-reminder-attention-fix.md`](../../docs/draft/system-reminder-attention-fix.md) §3 W3.1
- 対の regression eval: [`loop-mode-autonomy.md`](./loop-mode-autonomy.md)
- 強制対象 hook: [`.claude/hooks/draft-flow-guard.sh`](../hooks/draft-flow-guard.sh) (commit `6ed9337`)
- 強制対象 rule: [`.claude/rules/task-management.md`](../rules/task-management.md) (常時参照、W1.7)
- skill: [`.claude/skills/eval-harness/SKILL.md`](../skills/eval-harness/SKILL.md)
