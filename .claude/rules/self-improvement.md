---
paths:
  - "**/*"
---

# 自己改善 5 層 + 事実性レイヤー（ECC 由来）

このハーネスは ECC（Everything Claude Code）の自己改善アルゴリズム **5 層 + 事実検証 2 層** を完全模倣している。タスク受領時・失敗時・完了時に「どの層を使うか」を意識する。

## 層構造

| 層 | 名称 | 改善対象 | 観察粒度 | 永続化先 |
|---|---|---|---|---|
| **L1** | Eval-Driven Dev | 1 機能の正しさ | コミット単位 | `.claude/evals/` |
| **L2** | Continuous Loop / GAN | 1 タスクの品質 | 1 反復 | `feedback-NNN.md` |
| **L3** | Ralphinho RFC-DAG | プロジェクト構造 | 作業ユニット | jj worktree |
| **L4** | Continuous Learning v2.1（核心） | エージェントの行動 | ツール呼び出し | `~/.claude/homunculus/` |
| **L5** | Introspection Debugging | エージェント自身 | 失敗パターン | introspection report |
| **F1** | **GateGuard**（事前ゲート） | **Edit/Write/Bash の事実性** | **初回ファイル/コマンド** | `.claude/.gateguard-state/` |
| **F2** | **Verification Loop**（事後検証） | **PR 直前の品質** | **6 phases** | `/verify` レポート |

## いつどの層を使うか

```
タスク受領
  → L1 で合否基準を先に書く（/eval define）
  → L2 でループ実装（Sequential / Continuous PR / GAN）
  → L1 で合否確認（/eval check）

ファイルを編集/作成しようとした時
  → F1 GateGuard が初回 BLOCK（事実調査要求）
  → 要求された 4 事実を提示
  → 同ファイルへの retry は通過

破壊的 Bash（rm -rf / git reset --hard 等）
  → F1 GateGuard が初回 BLOCK
  → rollback 手順 + 影響範囲 + 逐語引用 を提示
  → retry で通過

PR 作成直前
  → F2 /verify で 6 phase 検証
  → READY なら commit/push

タスク失敗（同じ失敗3連 / context 肥大 / drift）
  → L5 で自己診断（/agent-introspect）
  → 教訓を L4 へ送る（/learn）

セッション終了
  → L4 が Hook 経由で自動観察済み
  → 余裕があれば /instinct-status 確認
  → /gate-status で何が cleared か確認

複数プロジェクトで同じ patten 反復
  → L4 で /promote project → global

大規模・並列必要
  → L3 Ralphinho（外部 plugin・このハーネスでは雛形のみ）
```

## 事実性レイヤー（F1/F2）の効果

| 層 | 検出 | 効果 |
|---|---|---|
| **F1 GateGuard** | 初回の Edit/Write/破壊的 Bash | A/B 実測で **+2.25 / 10 ポイント**（ungated 6.75 → gated 9.0） |
| **F2 Verification** | Build/Type/Lint/Test/Security/Diff の 6 軸 | PR 直前の事故防止 |

両者の役割分離:
- F1 = "**実行前**に事実を強制"（投機的な Edit を防ぐ）
- F2 = "**実行後**に網羅検証"（バグの作り込みを止める）

## L4（核心）の動作前提

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

## メインエージェントへの要請

1. **タスク受領時**: `/eval define` で先に合否基準を書く（できるなら）
2. **失敗が3連した時**: `/agent-introspect` を即起動して盲目リトライしない
3. **完了時**: `/instinct-status` で増えた instinct を確認、user に報告
4. **新規スキル提案時**: `/evolve` で既存 instinct クラスタから派生提案
5. **共通ルール抽出時**: `/promote` で project → global 昇格

## 失敗モード対処

| 症状 | 層 | 対処 |
|---|---|---|
| ループ churn | L2 | scope 縮小、`/harness-audit`、明示 acceptance |
| Merge stall | L3 | unit 分割、tier 下げ |
| 信頼度爆発（矛盾 instinct） | L4 | confidence decay、user 確認、`/instinct-status` |
| プロジェクト混線 | L4 | v2.1 の project-scoped で隔離（既に有効） |
| Cost drift | L2/L4 | `--max-cost` / Haiku ルーティング |
| 失敗ループ | L5 | `/agent-introspect`、教訓を L4 へ |

## 関連スキル

- `.claude/skills/eval-harness/SKILL.md` (L1)
- `.claude/skills/continuous-agent-loop/SKILL.md` (L2)
- `.claude/skills/gan-style-harness/SKILL.md` (L2+)
- `.claude/skills/continuous-learning-v2/SKILL.md` (L4 — 核心)
- `.claude/skills/agent-introspection-debugging/SKILL.md` (L5)
- `.claude/skills/gateguard/SKILL.md` (F1 — 事前ゲート)
- `.claude/skills/verification-loop/SKILL.md` (F2 — 事後検証)

## 関連コマンド

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
