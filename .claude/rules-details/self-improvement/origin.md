> Layer A: [`self-improvement.md`](../../rules/self-improvement.md) §関連スキル / コマンド (代表) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 詳細 (Layer B)

- **L1-L5 + F1/F2 模倣の起源**: ECC (Everything Claude Code) の自己改善アルゴリズム。ECC から `.claude/skills/` 配下の `eval-harness` / `continuous-agent-loop` / `gan-style-harness` / `continuous-learning-v2` / `agent-introspection-debugging` / `gateguard` / `verification-loop` の 7 skill を移植
- **F1 GateGuard A/B 実測 +2.25 / 10 ポイント**: ECC で計測された ungated 6.75 → gated 9.0 の数値。本ハーネスでも同等効果を期待
- **L4 を「核心」とする位置付け**: ECC の continuous-learning-v2 が **全 tool call を observation** することで instinct を蓄積 → confidence 0.7 で auto-apply → 0.9 で core behavior 化、というアルゴリズムが自己改善の中核
- **規範化経緯**: 各層の commit hash / 採用判断は git log + `docs/SELF_IMPROVEMENT.md` を参照
