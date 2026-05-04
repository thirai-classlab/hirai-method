---
name: continuous-agent-loop
description: Patterns for continuous autonomous agent loops with quality gates, evals, and recovery controls. 6 patterns from sequential pipelines to RFC-DAG orchestration. Replicated from ECC.
origin: ECC
---

# Continuous Agent Loop — 自己改善 L2

ECC 由来の 6 ループパターンと、それらに付随する品質ゲート・回復機構。

## 6 Patterns at a Glance

| Pattern | 複雑度 | Best For |
|---|---|---|
| Sequential Pipeline (`claude -p`) | 低 | 日次開発・スクリプト化ワークフロー |
| NanoClaw REPL | 低 | 対話的・継続セッション |
| Infinite Agentic Loop | 中 | 並列バリエーション生成 |
| Continuous Claude PR Loop | 中 | 多日 PR + CI 自動化 |
| De-Sloppify Pattern | add-on | どのループにも追加可能なクリーンアップ |
| Ralphinho RFC-DAG | 高 | 大規模・並列・マージキュー必要 |

## Selection Flow

```
Start
  ├─ 単一の絞られた変更？
  │   └─ Yes → Sequential or NanoClaw
  └─ No → 仕様/RFC あり？
        ├─ Yes → 並列実装必要？
        │       ├─ Yes → Ralphinho RFC-DAG
        │       └─ No → Continuous Claude PR
        └─ No → 同種の多バリエーション必要？
              ├─ Yes → Infinite Agentic Loop
              └─ No → Sequential + De-Sloppify
```

## 1. Sequential Pipeline

```bash
#!/bin/bash
set -e
claude -p "Implement OAuth2 in src/auth/. TDD."
claude -p "De-sloppify: remove tests of language behavior, redundant type checks."
claude -p "Run build + lint + tests. Fix failures."
claude -p "Commit: feat: add OAuth2 login flow"
```

**Key principles**:
- 各ステップは isolated context（コンテキスト混入なし）
- 順序が意味を持つ
- Negative instructions は危険 → 別パスで除去

## 2. NanoClaw REPL

ECC 内蔵の永続セッション REPL。`/claw` コマンドで使う。

| | NanoClaw | Sequential Pipeline |
|---|---|---|
| 対話的探索 | ✓ | – |
| スクリプト化 | – | ✓ |
| セッション永続 | 内蔵 | 手動 |
| context 蓄積 | turn 毎 | step 毎にリセット |
| CI/CD 統合 | 不適 | 適 |

## 3. Infinite Agentic Loop（@disler）

Two-prompt system でサブエージェント並列展開。

```
PROMPT 1 (Orchestrator)         PROMPT 2 (Sub-Agents)
仕様解析 → 出力dir scan         全コンテキスト受領
                deploy N agents 割当番号 + 創造方向
波管理                          spec 厳守
                                ユニーク出力
```

**バッチ戦略**:
| count | strategy |
|---|---|
| 1-5 | 全エージェント同時 |
| 6-20 | バッチ 5 |
| infinite | 波 3-5、漸進的に高度化 |

## 4. Continuous Claude PR Loop（@AnandChowdhary）

```
1. branch (continuous-claude/iteration-N) 作成
2. claude -p で実装
3. (任意) Reviewer pass
4. commit
5. push + gh pr create
6. CI 待機
7. CI 失敗 → auto-fix pass
8. merge PR
9. main 戻り → 反復
```

**Cross-iteration context**: `SHARED_TASK_NOTES.md` が反復間で永続。

**完了シグナル**: 特殊文字列を出力で停止判定。3 連続で停止。

## 5. De-Sloppify Pattern

ネガティブ指示の代替として、別 pass で不要物除去:

```bash
# Step 1: 思いっきり実装
claude -p "Implement with full TDD."

# Step 2: De-sloppify (focused cleanup)
claude -p "Review changes. Remove:
- Tests of language/framework behavior
- Redundant type checks
- Over-defensive error handling
- console.log / commented code

Keep business logic tests. Run test suite."
```

> 制約された 1 エージェントより、フォーカスした 2 エージェントが勝つ

## 6. Ralphinho RFC-DAG（@enitrat、最高品質）

```
RFC/PRD → AI Decomposition → 依存DAG
  │
  └─ 各 Layer（依存順）
       └─ Quality Pipelines（並列、worktree隔離）
            research → plan → implement → test → review → fix
       └─ Merge Queue
            rebase → test → land or evict
            evicted → 衝突コンテキスト保持して次 pass
```

**Tier 別パイプライン**:
| Tier | Pipeline |
|---|---|
| trivial | implement → test |
| small | implement → test → code-review |
| medium | research → plan → implement → test → reviews → fix |
| large | + final-review |

**ステージ別モデル割当（Author-Bias排除）**:
- Plan / Code-Review / Final-Review = **Opus**
- Research / Test / PRD-Review = Sonnet
- Implement / Review-Fix = Codex

> **レビュアーは絶対にコード執筆者になっていない**

## Failure Modes & Recovery

```
loop churn（進歩なき反復）
  → /harness-audit、scope 縮小、明示的な acceptance criteria で replay

merge stall
  → unit 分割、tier 下げ

cost drift
  → --max-cost / --max-runs で制限、Haiku ルーティング
```

## Anti-Patterns

1. exit 条件なき無限ループ → 必ず max-runs / max-cost / max-duration
2. 反復間 context bridge なし → SHARED_TASK_NOTES.md で渡す
3. 同じ失敗をリトライ → 失敗 context を次の試行に feed
4. ネガティブ指示 → 別 pass で除去
5. 全 agent 同 context → 関心分離、reviewer ≠ author
6. 並列で衝突無視 → merge strategy 必須

## Combining

ベスト推奨:
1. RFC decomposition (`ralphinho-rfc-pipeline`)
2. Quality gates (`plankton-code-quality`)
3. Eval loop (`eval-harness`)
4. Session persistence (`nanoclaw-repl`)

## References

| Project | Author |
|---|---|
| Ralphinho | @enitrat |
| Infinite Agentic Loop | @disler |
| Continuous Claude | @AnandChowdhary |
| NanoClaw / Verification Loop | ECC |
