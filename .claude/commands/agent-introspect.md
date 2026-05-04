---
description: Self-debug a stuck / looping / drifting agent run via the 4-phase Capture / Diagnose / Recover / Report loop. L5 of self-improvement.
---

# /agent-introspect

エージェントが詰まっている・同じことを繰り返している・目的を見失っているときに、**盲目リトライではなく系統的に自己診断** する。

## いつ使うか

- 最大ツール呼出 / ループ制限を打ちそう
- 同コマンド3回連続失敗
- context 肥大で出力品質劣化
- ファイルシステム/環境の状態が期待と乖離

## 使い方

```
/agent-introspect
```

## 動作（4フェーズ）

### Phase 1: Failure Capture

以下を埋めて記録する。

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

下表で既知パターンと照合:

| パターン | 推定原因 | 検査 |
|---|---|---|
| 最大ツール呼出 / 同コマンド連発 | ループ・無出口観察パス | 直近 N tool call 繰返検査 |
| Context overflow / 推論劣化 | 重複プラン・巨大ログ | 重複・低信号の混入確認 |
| `ECONNREFUSED` / timeout | サービス断・ポート違い | service health / URL / port |
| `429` / quota 枯渇 | retry storm・backoff 欠如 | 連続呼出・retry 間隔 |
| 書込後ファイル消失 | race / cwd違い / branch ドリフト | path 再確認・git status |
| "fix"後もテスト失敗 | 仮説違い | 失敗テスト 1 つに絞り再導出 |

### Phase 3: Contained Recovery

最小可逆アクション:

```markdown
## Recovery Action
- Diagnosis chosen:
- Smallest action taken:
- Why this is safe:
- What evidence would prove the fix worked:
```

優先順:
1. 真の目的を 1 文で再定義
2. メモリでなく現実状態を確認
3. 失敗範囲を縮小
4. 1 つだけ判別検査
5. 検査が仮説を支持したときのみリトライ

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
- Preventive change to encode later:    ← /learn 経由で instinct 化
```

## 関連

- skill: `.claude/skills/agent-introspection-debugging/SKILL.md`
- rule: `.claude/rules/self-improvement.md`（L5）
- `/learn` — Preventive change を instinct 化
