---
description: Import instincts from a JSON file shared by another developer or exported earlier.
---

# /instinct-import

instinct JSON を読み込む。チーム共通ルールの配布、別マシンからの移行に使う。

## 使い方

```
/instinct-import <file>                                    # global inherited へ
/instinct-import <file> --scope project --project-id <id>  # project inherited へ
```

## 動作

`python3 .claude/skills/continuous-learning-v2/instinct-cli.py import <file> [opts]` を実行。

## インポート先

- `--scope global`（既定） → `~/.claude/homunculus/instincts/inherited/`
- `--scope project --project-id <id>` → `~/.claude/homunculus/projects/<id>/instincts/inherited/`

`source` フィールドは自動で `imported` に書き換わる。元の confidence は保持。

## 例

```bash
# チーム共通の testing 規約を取り込み
/instinct-import team-testing-rules.json

# 特定プロジェクトに技術スタック固有 instinct を流し込む
/instinct-import nextjs-app-rules.json --scope project --project-id a1b2c3d4e5f6
```

## 注意

- 既存 instinct と ID 衝突した場合は **上書き**
- 個人観察（personal/）は影響を受けない（inherited/ に隔離）
- `/instinct-status` で「どこから来たか」確認可能
