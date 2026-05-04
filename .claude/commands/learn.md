---
description: Manual pattern extraction from current session — heuristic instinct candidate generation without invoking Haiku.
---

# /learn

現セッションの観察ログから instinct 候補をヒューリスティックに抽出する。Haiku observer が動いていない / 確認したいときの手動実行口。

## 使い方

```
/learn                       # 現プロジェクトの観察を分析
/learn --project-id <hash>   # 特定プロジェクト
```

## 動作

1. `python3 .claude/skills/continuous-learning-v2/instinct-cli.py observe-analyze` を実行
2. observations.jsonl を読み、ツール使用の bigram などから繰返パターンを抽出
3. instinct 候補を提示

## 出力例

```
=== Observation Summary (1234 tool calls) ===

Top tools:
  Edit                  450
  Read                  321
  Bash                  208
  Grep                  150
  Write                 105

Frequent tool bigrams (≥3):
  Read            → Edit            ×88
  Grep            → Read            ×54
  Edit            → Bash            ×33
  Bash            → Read            ×21
  Read            → Read            ×18

→ これらを基に instinct を手動作成するか、Haiku observer を有効化してください。
```

## 次のステップ

抽出されたパターンから instinct を作る場合:

1. Claude に「Read→Edit が 88 回観察された。これは grep-before-edit パターン候補だね」と相談
2. 合意できたら `~/.claude/homunculus/projects/<hash>/instincts/personal/grep-before-edit.md` を作成
3. confidence は最初 0.3 から始める（観察を重ねて上げる）

## 関連

- skill: `.claude/skills/continuous-learning-v2/SKILL.md`
- `/instinct-status`
