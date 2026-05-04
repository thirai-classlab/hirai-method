---
name: gan-style-harness
description: GAN-inspired three-agent harness (Planner / Generator / Evaluator) that iteratively converges to production-grade quality via numerical scoring rubric. Replicated from ECC.
origin: ECC
---

# GAN-Style Harness — 自己改善 L2+

GAN（Generative Adversarial Network）にインスパイアされた3エージェント構造。Planner が仕様を作り、Generator が実装し、Evaluator が live app をテストして数値スコアを返す。閾値到達まで反復。

## When to Activate

- 高品質なフロントエンド/フルスタック成果物が必要
- 「単一エージェント実装」では届かない quality bar
- 視覚品質・craft が要求される（デザイン、UI、ランディング）
- 4-6 時間 / $125-200 のコストを許容できる案件

## Three-Agent Loop

```
User 1行プロンプト
       │
       ▼
   Planner (Opus)
   仕様書 16機能・複数Sprint 化
       │ 仕様書
       ▼
   Generator (Opus)  ←─────────────────┐
   実装 + git管理                       │ feedback-N+1.md
       │ live app deploy (port 3000)   │
       ▼                                │
   Evaluator (Opus + Playwright MCP)    │
   実機テスト → 4基準スコア             │
       └────────────────────────────────┘
```

## Scoring Rubric

各 1-10、重み付き合計。

| 基準 | 重み | 1-3 | 9-10 |
|---|---:|---|---|
| Design Quality | 0.30 | テンプレ的・ストック | プロデザイナー級 |
| Originality | 0.20 | 既視感のある構成 | 独自ビジョン |
| Craft | 0.30 | 雑（spacing/typography 不揃い） | 完璧（anim/responsive 含む） |
| Functionality | 0.20 | 機能不全 | エッジケース対応 |

## Convergence

- Pass threshold: **7.0 / 10**（重み付き合計）
- Max iterations: **15**（典型は 5-15 で十分）
- Plateau detection: **3 反復連続** スコア改善なし → 人間レビューへ

## State / File Layout

```
gan-session-<timestamp>/
├── spec.md                    # Planner output
├── feedback-001.md            # Evaluator output (1st)
├── feedback-002.md
├── ...
├── feedback-NNN.md            # 最終
├── live-app/                  # Generator が実装
└── playwright-runs/           # Evaluator のスクリーンショット
```

Generator は **直前の feedback-NNN.md だけ読む**（コンテキスト爆発防止）。
Evaluator は **live-app の最新版だけ実機評価**。

## Resource Trade-offs

| アプローチ | 時間 | コスト | 成果物 |
|---|---:|---:|---|
| 単一エージェント | 20分 | $9 | barely functional |
| GAN harness | 4-6h | $125-200 | production-ready |

## Slash Commands

- `/gan-design <prompt>` — Planner phase（仕様生成）
- `/gan-build <spec-file>` — Generator/Evaluator loop 起動

## Sprint Contract

Generator は実装前に Evaluator と「sprint contract」を交渉する:

```markdown
# Sprint Contract: <feature>
- 実装範囲: <bullet list>
- 完了条件: <eval が PASS と判定する観測可能な振る舞い>
- 非ゴール: <今回やらないこと>
- 推定時間: <hour>
```

これにより Evaluator が「想定外の角度」で減点する自体を抑制。

## Failure Modes

- スコア plateau → 人間レビュー、仕様書見直し、Tier 切り下げ
- Evaluator が hallucinate（実機を見ずに採点） → Playwright MCP の screenshot を必須化
- コスト爆発 → max-iterations / max-cost を必ず設定

## Integration

- **L1 eval-harness** をスコアリング rubric の単位テストとして併用
- **L4 continuous-learning-v2** で Evaluator の指摘を instinct 化（次回以降の Planner に自動注入）
- **L5 introspection-debugging** でスコア低下の根本原因を分析

## References

- Source: ECC `skills/gan-style-harness/`
- 元アイデア: GANs (Goodfellow 2014) を agent harness に転写
