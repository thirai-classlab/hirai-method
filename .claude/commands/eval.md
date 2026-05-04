---
description: Eval-Driven Development workflow — define / check / report capability + regression evals before and during implementation. L1 of self-improvement.
---

# /eval

実装より先に合否基準を定義する **Eval-Driven Development** ワークフロー。

## 使い方

```
/eval define <feature>      # eval 定義を新規作成
/eval check <feature>       # 現在の状態で eval を実行
/eval report <feature>      # full eval レポート生成
```

## 引数

- `<feature>` — 機能名（kebab-case 推奨。例: `add-authentication`）

## 動作

### `/eval define <feature>`

1. `.claude/evals/<feature>.md` を作成
2. 以下のテンプレを埋める

```markdown
## EVAL DEFINITION: <feature>

### Capability Evals（新能力）
- [ ] Criterion 1
- [ ] Criterion 2

### Regression Evals（既存維持）
- [ ] existing-test-1
- [ ] existing-test-2

### Success Metrics
- pass@3 ≥ 0.90 for capability evals
- pass^3 = 1.00 for regression evals
```

### `/eval check <feature>`

1. `.claude/evals/<feature>.md` を読む
2. 各 criterion を grader で実行
   - **Code grader**: `bash` で deterministic check
   - **Rule grader**: regex/schema
   - **Model grader**: LLM-as-judge
   - **Human grader**: manual review flag
3. `.claude/evals/<feature>.log` に追記
4. PASS/FAIL を提示

### `/eval report <feature>`

1. ログから pass@k / pass^k 計算
2. `docs/releases/<version>/eval-summary.md` に書き出し

## 推奨閾値

| メトリクス | 閾値 |
|---|---:|
| pass@3 (capability) | ≥ 0.90 |
| pass^3 (regression) | = 1.00（release-critical） |

## 関連

- skill: `.claude/skills/eval-harness/SKILL.md`
- rule: `.claude/rules/self-improvement.md`（5層自己改善のうちの L1）
