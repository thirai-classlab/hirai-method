---
description: GAN harness Generator/Evaluator loop — iterate implementation against live-app eval until score ≥7.0 or 15 iterations.
---

# /gan-build

GAN-Style Harness の **Generator/Evaluator ループ** フェーズ。実装 → live app デプロイ → Playwright で評価 → feedback → 次反復、を閾値到達まで繰り返す。

## 使い方

```
/gan-build <spec-file>                    # 既定: max 15 iter, threshold 7.0
/gan-build <spec-file> --max-iter 10      # 反復上限
/gan-build <spec-file> --threshold 7.5    # 合格スコア
/gan-build <spec-file> --max-cost 200     # USD 制限
```

## 動作

### Initialization

1. `<spec-file>` を読み込み
2. セッション dir 作成: `.gan-sessions/<timestamp>/`
3. live-app workspace 作成

### Main Loop

```
for i in 1..max_iter:
  # Generator
  spec + (if i>1) feedback-{i-1}.md を context に
  Generator(Opus) が実装 + git commit
  live-app を port 3000 で起動

  # Evaluator
  Evaluator(Opus + Playwright MCP) が実機テスト
  4基準（design/originality/craft/functionality）でスコア
  feedback-{i}.md を保存

  # Convergence check
  if weighted_score >= threshold:
    break "PASS"
  if i >= 3 and no improvement:
    break "PLATEAU - 人間レビュー要求"
  if cost > max_cost:
    break "BUDGET EXCEEDED"
```

### Sprint Contract

各反復前に Generator と Evaluator が実装範囲を交渉:

```markdown
# Sprint Contract: <feature>
- 実装範囲: <list>
- 完了条件: <eval が PASS と判定する観測可能な振る舞い>
- 非ゴール: <list>
- 推定時間: <hour>
```

## Convergence

- 合格閾値: **7.0 / 10**（重み付き合計）
- 上限: **15 反復**（典型は 5-15 で十分）
- Plateau: **3 反復連続でスコア改善なし** → 人間レビュー

## 出力

```
.gan-sessions/<timestamp>/
├── spec.md                  # /gan-design の出力
├── feedback-001.md          # iter 1 のスコア + 指摘
├── feedback-002.md          # iter 2
├── ...
├── feedback-NNN.md
├── live-app/                # 最終成果物
└── playwright-runs/         # スクリーンショット履歴
```

## コスト感

| パターン | 時間 | コスト | 品質 |
|---|---:|---:|---|
| 単一エージェント | 20分 | $9 | barely functional |
| GAN harness | 4-6h | $125-200 | production-ready |

## 関連

- skill: `.claude/skills/gan-style-harness/SKILL.md`
- `/gan-design`
- L4 instinct 化: Evaluator の指摘パターンを `/learn` 経由で instinct DB へ
