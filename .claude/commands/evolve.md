---
description: Cluster related instincts and suggest skill / command / agent generation. Replicated from ECC.
---

# /evolve

関連 instinct を domain 別にクラスタリングし、十分な confidence と数があれば skill/command/agent への昇格候補を提示する。

## 使い方

```
/evolve
```

## 動作

1. `python3 .claude/skills/continuous-learning-v2/instinct-cli.py evolve` を実行
2. domain 毎に instinct をグループ化
3. 平均 conf ≥0.7 かつ ≥2 件のクラスタを抽出
4. **4件以上 → skill 推奨**、**2-3件 → command 推奨**

## 出力例

```
=== Evolution Candidates ===

[testing] 4 instincts, avg conf 0.75
  - test-with-vitest (0.80)
  - aaa-pattern (0.75)
  - mock-supabase-client (0.70)
  - integration-over-unit (0.75)
  → 推奨: skill を生成 → ~/.claude/homunculus/evolved/skills/testing-cluster.md

[git] 2 instincts, avg conf 0.85
  - conventional-commits (0.90)
  - small-focused-commits (0.80)
  → 推奨: command を生成 → ~/.claude/homunculus/evolved/commands/git-cluster.md
```

## 次のステップ

1. 候補から良さそうなクラスタを選ぶ
2. メインエージェントに「この instinct 群を 1 つの skill にまとめて」と依頼
3. 生成された skill を `~/.claude/skills/<name>/` または `<repo>/.claude/skills/<name>/` に置く

## 関連

- `/instinct-status`
- `/promote`
