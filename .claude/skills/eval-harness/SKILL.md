---
name: eval-harness
description: Eval-Driven Development (EDD) framework. Define pass/fail criteria before implementation, measure with pass@k / pass^k metrics, gate releases on regression evals. Replicated from ECC.
origin: ECC
tools: Read, Write, Edit, Bash, Grep, Glob
---

# Eval Harness — 自己改善 L1（基盤層）

実装より先に合否基準を定義する **Eval-Driven Development**。すべての上位層（L2-L5）の合否判定基盤として機能する。

## When to Activate

- 新機能の合否基準を定義する
- 上位ループ（L2/L3）の終端条件として使う
- リグレッションを定量管理する
- モデル切替時の品質ベンチマーク

## Philosophy

> Evals are the unit tests of AI development.

- 期待挙動を実装より **先に** 定義する
- 開発中は継続的に走らせる
- 各変更でリグレッションを追跡
- pass@k メトリクスで信頼性を測る

## Eval Types

### Capability Evals（新能力）

```markdown
[CAPABILITY EVAL: feature-name]
Task: <Claude が達成すべきこと>
Success Criteria:
  - [ ] Criterion 1
  - [ ] Criterion 2
Expected Output: <期待結果>
```

### Regression Evals（既存維持）

```markdown
[REGRESSION EVAL: feature-name]
Baseline: <SHA or checkpoint>
Tests:
  - existing-test-1: PASS/FAIL
  - existing-test-2: PASS/FAIL
Result: X/Y passed (previously Y/Y)
```

## Grader Types

| Grader | 用途 | 例 |
|---|---|---|
| **Code grader** | 決定的判定 | `grep -q "..." && npm test` |
| **Rule grader** | regex/schema 制約 | JSON schema validation |
| **Model grader** | LLM-as-judge | "Score 1-5: ..." |
| **Human grader** | 曖昧出力 | manual review flag |

## Metrics

| メトリクス | 定義 | 推奨閾値 |
|---|---|---:|
| `pass@1` | 1試行で成功 | – |
| `pass@3` | 3試行で1回以上成功 | **≥ 0.90**（capability） |
| `pass^3` | 3試行すべて成功 | **= 1.00**（release-critical） |

## Workflow

```
1. Define   →  .claude/evals/<feature>.md
2. Implement
3. Evaluate →  pass@k 計測
4. Report   →  docs/releases/<ver>/eval-summary.md
```

## Storage

```
.claude/evals/
├── <feature>.md       # 定義
├── <feature>.log      # 実行履歴
└── baseline.json      # リグレッションベースライン
```

## Anti-patterns

- ❌ 既知の eval 例にプロンプトを過剰適合
- ❌ ハッピーパスのみ測定
- ❌ pass率だけ追ってコスト/遅延ドリフト無視
- ❌ flaky な grader をリリースゲートに使う

## Integration

- `/eval define <feature>` — eval 定義
- `/eval check <feature>` — 実行
- `/eval report <feature>` — レポート生成

詳細: `.claude/commands/eval.md`
