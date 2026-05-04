---
description: List all known projects observed by continuous-learning-v2 with their instinct counts.
---

# /projects

このマシン上で observe された全プロジェクトと、各プロジェクトの instinct 数・最終観察日時を一覧。

## 使い方

```
/projects
```

## 動作

`python3 .claude/skills/continuous-learning-v2/instinct-cli.py projects` を実行。

## 出力例

```
HASH           NAME                           INSTINCTS  LAST_SEEN
--------------------------------------------------------------------------------
a1b2c3d4e5f6   my-app                                12  2026-05-04T10:32:00Z
e5d4c3b2a1f6   infra-deploy                           3  2026-05-04T09:15:00Z
123456789abc   scratch                                7  2026-05-03T18:22:00Z
```

## 関連

- `/instinct-status` — 全 instinct
- `/promote` — project → global
