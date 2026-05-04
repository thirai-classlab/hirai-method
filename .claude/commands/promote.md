---
description: Promote project-scoped instincts to global when seen in 2+ projects with avg confidence ≥0.8.
---

# /promote

project-scoped instinct を global へ昇格させる。

## 使い方

```
/promote               # 全候補を一括昇格
/promote <id>          # 特定 ID のみ
/promote --dry-run     # 候補一覧のみ（書き込まない）
```

## 自動候補条件

- 同じ instinct ID が **2+ プロジェクト** で観察されている
- 平均 confidence **≥ 0.8**

## 動作

1. `python3 .claude/skills/continuous-learning-v2/instinct-cli.py promote [target] [--dry-run]` を実行
2. 候補を提示
3. （`--dry-run` でなければ）最高 confidence の instinct を `~/.claude/homunculus/instincts/personal/` へコピー
4. scope を `global` に書き換え、project_id/project_name を除去

## 出力例

```
=== Promotion Candidates (2) ===

  prefer-explicit-errors  avg=0.85  projects=3
    → promoted to ~/.claude/homunculus/instincts/personal/prefer-explicit-errors.md
  always-test-edge-cases  avg=0.82  projects=2
    → promoted to ~/.claude/homunculus/instincts/personal/always-test-edge-cases.md
```

## 関連

- `/projects` — どのプロジェクトに何があるか
- `/instinct-status`
