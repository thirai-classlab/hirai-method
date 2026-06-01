> Layer A: [`self-improvement.md`](../../rules/self-improvement.md) §関連スキル / コマンド (代表) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 関連スキル / コマンド 完全 (Layer B)

## スキル

- `.claude/skills/eval-harness/SKILL.md` (L1)
- `.claude/skills/continuous-agent-loop/SKILL.md` (L2)
- `.claude/skills/gan-style-harness/SKILL.md` (L2+)
- `.claude/skills/continuous-learning-v2/SKILL.md` (L4 — 核心)
- `.claude/skills/agent-introspection-debugging/SKILL.md` (L5)
- `.claude/skills/gateguard/SKILL.md` (F1 — 事前ゲート)
- `.claude/skills/verification-loop/SKILL.md` (F2 — 事後検証)

## コマンド

```
/eval {define|check|report} <feature>     # L1
/gan-design <prompt>                       # L2+ Planner
/gan-build <spec>                          # L2+ Generator/Evaluator loop
/instinct-status                           # L4 一覧
/projects                                  # L4 既知プロジェクト
/learn                                     # L4 ヒューリスティック抽出
/evolve                                    # L4 クラスタリング
/promote [id]                              # L4 project → global
/instinct-export [opts]                    # L4 export
/instinct-import <file>                    # L4 import
/agent-introspect                          # L5 自己診断

/gate-status                               # F1 cleared/pending 状態
/gate-clear [file|all]                     # F1 state リセット
/gate-bypass <file>                        # F1 pre-clear

/verify                                    # F2 6 phase 事後検証
```
