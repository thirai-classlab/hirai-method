# 自己改善 5 層 + 事実性レイヤー（ECC 由来）

このハーネスは ECC（Everything Claude Code）の自己改善アルゴリズム **5 層 + 事実検証 2 層** を完全模倣している。タスク受領時・失敗時・完了時に「どの層を使うか」を意識する。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: [self-improvement.details.md](./self-improvement.details.md)

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

## いつどの層を使うか（要約）

```
タスク受領 → L1 で合否基準 → L2 でループ実装 → L1 で合否確認
Edit/Write 初回 → F1 BLOCK → 4 事実提示 → retry 通過
破壊的 Bash 初回 → F1 BLOCK → rollback/影響/逐語引用 → retry
PR 直前 → F2 /verify 6 phase → READY なら commit/push
失敗 3 連 → L5 /agent-introspect → L4 /learn で教訓化
セッション終了 → L4 自動観察済 (Hook 経由)
複数 project 反復 → L4 /promote project → global
```

> **判断フロー full / 大規模・並列ケース詳細**: [self-improvement.details.md §いつどの層を使うか-full](./self-improvement.details.md#いつどの層を使うか-full)

## 事実性レイヤー（F1/F2）の効果

| 層 | 検出 | 効果 |
|---|---|---|
| **F1 GateGuard** | 初回の Edit/Write/破壊的 Bash | A/B 実測で **+2.25 / 10 ポイント**（ungated 6.75 → gated 9.0） |
| **F2 Verification** | Build/Type/Lint/Test/Security/Diff の 6 軸 | PR 直前の事故防止 |

両者の役割分離:
- F1 = "**実行前**に事実を強制"（投機的な Edit を防ぐ）
- F2 = "**実行後**に網羅検証"（バグの作り込みを止める）

## メインエージェントへの要請

1. **タスク受領時**: `/eval define` で先に合否基準を書く（できるなら）
2. **失敗が3連した時**: `/agent-introspect` を即起動して盲目リトライしない
3. **完了時**: `/instinct-status` で増えた instinct を確認、user に報告
4. **新規スキル提案時**: `/evolve` で既存 instinct クラスタから派生提案
5. **共通ルール抽出時**: `/promote` で project → global 昇格

> **L4 動作前提 / 信頼度挙動 / 失敗モード対処詳細**: [self-improvement.details.md §l4-動作前提](./self-improvement.details.md#l4-動作前提)

## 関連スキル / コマンド (代表)

- L1: `/eval {define|check|report}` ([eval-harness](../skills/eval-harness/SKILL.md))
- L2: `/gan-design` `/gan-build` ([continuous-agent-loop](../skills/continuous-agent-loop/SKILL.md), [gan-style-harness](../skills/gan-style-harness/SKILL.md))
- L4: `/instinct-status` `/learn` `/evolve` `/promote` ([continuous-learning-v2](../skills/continuous-learning-v2/SKILL.md) — 核心)
- L5: `/agent-introspect` ([agent-introspection-debugging](../skills/agent-introspection-debugging/SKILL.md))
- F1: `/gate-status` `/gate-clear` `/gate-bypass` ([gateguard](../skills/gateguard/SKILL.md))
- F2: `/verify` ([verification-loop](../skills/verification-loop/SKILL.md))

> **全 skill / command 完全 list**: [self-improvement.details.md §関連スキル--コマンド-完全](./self-improvement.details.md#関連スキル--コマンド-完全)
