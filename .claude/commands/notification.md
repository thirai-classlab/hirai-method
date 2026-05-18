---
name: notification
description: "通知送信 - Slack/Asanaへ通知を送信"
category: skill
complexity: basic
model: haiku
mcp-servers: [asana, slack]
---

# /notification - 通知送信スキル

## 概要

Slack・Asanaへ通知を送信するヘルパースキル。
各コマンドから内部的に呼び出されます。

## 使用方法

```
/notification [通知タイプ] [宛先] [メッセージ]
```

例:
```
/notification approval 平井 "設計承認をお願いします"
/notification review engineer "PRレビューをお願いします"
/notification complete all "タスクが完了しました"
```

## 通知タイプ

| タイプ | 説明 | 送信先 |
|--------|------|--------|
| `approval` | 承認依頼 | Slack + Asana |
| `review` | レビュー依頼 | Slack + GitHub |
| `complete` | 完了通知 | Slack |
| `progress` | 進捗報告 | Asana |
| `alert` | 警告・問題報告 | Slack |

## 通知テンプレート

### 承認依頼 (approval)

```
:memo: 【承認依頼】{タスク名}

設計書の承認をお願いします。

- タスク: {Asana URL}
- PR: {GitHub PR URL}
- 工数: {合計工数}

確認後、承認または修正依頼をお願いします。
```

### レビュー依頼 (review)

```
:eyes: 【レビュー依頼】{タスク名}

コードレビューをお願いします。

- PR: {GitHub PR URL}
- 変更ファイル: {ファイル数}

レビュー観点:
- ガバナ制限
- バルク処理対応
- セキュリティ
```

### 完了通知 (complete)

```
:white_check_mark: 【完了】{タスク名}

タスクが完了しました。

- PR: {GitHub PR URL} (マージ済み)
- Asana: {Asana URL}

お疲れ様でした！
```

## MCP連携

| MCP | 用途 |
|-----|------|
| `slack` | Slack通知送信 |
| `asana` | Asanaコメント追加、タスク更新 |

## 送信先解決

| 宛先キーワード | 実際の送信先 |
|---------------|-------------|
| `平井` | 平井さんのSlack DM |
| `engineer` | 担当エンジニア |
| `requester` | 依頼者 |
| `all` | 関連者全員 |
| `channel` | プロジェクトチャンネル |

## 注意事項

- 通知は適切なタイミングで送信
- 重複通知を避ける
- 緊急度に応じてメンション方法を調整
- 営業時間外の通知は控える（設定可能）
