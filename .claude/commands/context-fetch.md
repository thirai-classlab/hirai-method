---
name: context-fetch
description: "関連情報取得 - Asana/Slack/GitHubから並列で情報を収集"
category: skill
complexity: basic
model: haiku
mcp-servers: [asana, slack, github]
---

# /context-fetch - 関連情報取得スキル

## 概要

Asana・Slack・GitHubから関連情報を並列で取得するヘルパースキル。
`/requirement` や `/design` コマンドから内部的に呼び出されます。

## 使用方法

```
/context-fetch [Asanaタスク名またはURL]
```

オプション:

```
/context-fetch [タスク] --source asana,slack,github
/context-fetch [タスク] --depth shallow|deep
```

## 実行フロー

### 1. Asana情報取得

- タスク詳細
- コメント履歴
- 関連タスク
- 添付ファイル

### 2. Slack情報取得

#### トークン確認

Slackのメッセージ検索はUser Token（xoxp）が必要です。

| トークン設定           | 検索機能    | 動作               |
| ---------------------- | ----------- | ------------------ |
| User Token（xoxp）あり | ✅ 利用可能 | 通常通り検索実行   |
| Bot Token（xoxb）のみ  | ❌ 利用不可 | **検索をスキップ** |

#### User Tokenが設定されている場合

- タスク名に関連するスレッド検索
- 関連チャンネルの議論
- メンション・リンク

#### Bot Tokenのみの場合（User Token未設定）

```
⚠️ Slackメッセージ検索をスキップしました（User Tokenが未設定のため）
```

検索はスキップし、他の情報取得（Asana/GitHub）は継続します。

### 3. GitHub情報取得

- 関連するPR/Issue
- 既存コードの参照
- コミット履歴

## 出力フォーマット

```markdown
## コンテキスト情報

### Asana

| 項目       | 内容 |
| ---------- | ---- |
| タスク名   | xxx  |
| ステータス | xxx  |
| 担当者     | xxx  |
| 期日       | xxx  |

#### コメント

- [日時] ユーザー: コメント内容

### Slack

#### 関連スレッド

- [チャンネル名](URL) - スレッド概要

### GitHub

#### 関連コード

- `path/to/file.cls` - 説明
```

## MCP連携

| MCP      | 取得情報                         |
| -------- | -------------------------------- |
| `asana`  | タスク詳細、コメント、関連タスク |
| `slack`  | スレッド検索、チャンネル履歴     |
| `github` | コード検索、PR/Issue、コミット   |

## 注意事項

- 並列で情報取得を行い、効率化
- 取得情報は構造化して返却
- 機密情報は適切にフィルタリング
