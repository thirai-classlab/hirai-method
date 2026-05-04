---
name: agent-introspection-debugging
description: Structured self-debugging workflow for AI agent failures using 4-phase capture / diagnose / recover / report loop. Replicated from ECC.
origin: ECC
---

# Agent Introspection Debugging — 自己改善 L5

Claude セッションが失敗を繰り返す・ループする・ドリフトするときに **盲目リトライではなく系統的に自己診断** するワークフロー。

## When to Activate

- 最大ツール呼び出し / ループ制限到達
- 同コマンド3回連続失敗
- context 肥大で出力品質が劣化
- ファイルシステム/環境状態が期待と乖離
- 復旧可能と思われるツール失敗

## Scope Boundaries

**使う場面**:
- 失敗状態を捕捉してから retry する
- 既知失敗パターンとの照合
- 含意の小さい復旧アクション
- 人間向け debug report 生成

**使わない場面**:
- コード変更後の機能検証 → `verification-loop`
- フレームワーク固有の debug → 専用スキル

## Four-Phase Loop

### Phase 1: Failure Capture

```markdown
## Failure Capture
- Session / task:
- Goal in progress:
- Error:
- Last successful step:
- Last failed tool / command:
- Repeated pattern seen:
- Environment assumptions to verify:
```

### Phase 2: Root-Cause Diagnosis

| パターン | 推定原因 | 検査 |
|---|---|---|
| 最大ツール呼出 / 同コマンド連発 | ループ・無出口観察パス | 直近 N tool call の繰返検査 |
| Context overflow / 推論劣化 | 無制限ノート・重複プラン | 重複・低信号の混入確認 |
| `ECONNREFUSED` / timeout | サービス断・ポート違い | service health / URL / port |
| `429` / quota 枯渇 | retry storm・backoff 欠如 | 連続呼出回数・retry 間隔 |
| 書込後ファイル消失 | race / cwd違い / branch ドリフト | path 再確認・git status |
| "fix"後もテスト失敗 | 仮説違い | 失敗テスト 1 つに絞り再導出 |

**診断質問**:
- これは logic / state / environment / policy のどの失敗？
- agent は本来の目的を見失って違うサブタスクを最適化している？
- 決定的か transient か？
- 仮説を検証する **最小可逆アクション** は何か？

### Phase 3: Contained Recovery

```markdown
## Recovery Action
- Diagnosis chosen:
- Smallest action taken:
- Why this is safe:
- What evidence would prove the fix worked:
```

**安全な復旧アクション**:
- リトライを止めて仮説を再記述
- 低信号 context をトリミング
- 実ファイルシステム / branch / process を直接観察
- タスクを 1 つの failing command に絞る
- 推測でなく直接観察に切り替え
- リスクが高ければ人間にエスカレーション

### Phase 4: Introspection Report

```markdown
## Agent Self-Debug Report
- Session / task:
- Failure:
- Root cause:
- Recovery action:
- Result: success | partial | blocked
- Token / time burn risk:
- Follow-up needed:
- Preventive change to encode later:  ← L4 instinct 候補へ
```

## Recovery Heuristics（優先順）

1. 真の目的を 1 文で再定義
2. メモリではなく現実状態を確認
3. 失敗範囲を縮小
4. 1 つだけ判別検査
5. 検査が仮説を支持したときのみリトライ

> ❌ 同じアクションを微妙な言い換えで 3 回試す
> ✅ capture → 分類 → 1 つだけ直接検査 → 検査が支持したら計画変更

## Integration

- 復旧後に `verification-loop` でコード変更を検証
- 失敗パターンが instinct 化価値あれば `continuous-learning-v2` へ送る
- 技術ではなく決定の曖昧さなら `council`
- ローカル状態の競合なら `workspace-surface-audit`

## Output Standard

「直しました」だけで終わらない。必ず以下を提示:
- failure pattern
- root-cause hypothesis
- recovery action
- 状況改善 / 依然ブロック の証拠

## Slash command

`/agent-introspect` — 上記 4 フェーズをガイドする
