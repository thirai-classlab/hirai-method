> Layer A: [`self-improvement.md`](../../rules/self-improvement.md) §メインエージェントへの要請 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# L4 動作前提 + 信頼度挙動 + 失敗モード対処 詳細 (Layer B)

## L4 動作前提

このハーネスは **すべての tool call を `.claude/skills/continuous-learning-v2/hooks/observe.sh` で観察** する。

- Hook 100% 確実発火
- 観察先: `~/.claude/homunculus/projects/<hash>/observations.jsonl`
- 個人データ・コードは送信されない（完全ローカル）
- `git remote` で project hash 自動検出
- 検出失敗時は global fallback

## L4 信頼度（confidence）の挙動

| Score | 表示 | 行動 |
|---|---|---|
| 0.3 | 提示するが強制せず | suggest |
| 0.5 | 関連時のみ適用 | apply when relevant |
| 0.7 | 自動適用承認 | auto-apply |
| 0.9 | コア行動 | core behavior |

**confidence が上がる**: 同パターン再観察、user 非否定、横断的合意
**confidence が下がる**: user 修正、長期未観察、矛盾観察

## 失敗モード対処

| 症状 | 層 | 対処 |
|---|---|---|
| ループ churn | L2 | scope 縮小、`/harness-audit`、明示 acceptance |
| Merge stall | L3 | unit 分割、tier 下げ |
| 信頼度爆発（矛盾 instinct） | L4 | confidence decay、user 確認、`/instinct-status` |
| プロジェクト混線 | L4 | v2.1 の project-scoped で隔離（既に有効） |
| Cost drift | L2/L4 | `--max-cost` / Haiku ルーティング |
| 失敗ループ | L5 | `/agent-introspect`、教訓を L4 へ |
