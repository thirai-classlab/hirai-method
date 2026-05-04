---
description: Export instincts to JSON for sharing or backup.
---

# /instinct-export

instinct を JSON 形式で export する。共有・バックアップ・チームでの共通化に使う。

## 使い方

```
/instinct-export                           # 全 instinct を stdout へ
/instinct-export --scope global            # global のみ
/instinct-export --scope project           # project のみ
/instinct-export --domain testing          # domain フィルタ
/instinct-export --output ./my-rules.json  # ファイル保存
```

## 動作

`python3 .claude/skills/continuous-learning-v2/instinct-cli.py export [opts]` を実行。

## 出力フォーマット

```json
{
  "version": "2.1",
  "exported_at": "2026-05-04T10:00:00Z",
  "count": 12,
  "instincts": [
    {
      "id": "always-validate-input",
      "trigger": "when receiving user input",
      "confidence": 0.85,
      "domain": "security",
      "scope": "global",
      "body": "..."
    }
  ]
}
```

## プライバシー

- export されるのは **instinct のみ**（観察ログは含まれない）
- 特定のコード・会話内容は出ない
- ユーザーが何を export するか完全に制御
