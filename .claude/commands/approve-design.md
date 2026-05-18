---
name: approve-design
description: "設計書承認 - doc_draft/ から doc/ へ設計書を移動し、承認完了を記録"
category: workflow
complexity: standard
model: sonnet
mcp-servers: [asana, slack, github]
---

# /approve-design - 設計書承認フェーズ

## 概要

設計書PRの承認後に実行するコマンド。
`doc_draft/` にある設計書を `doc/` に移動し、承認済みとして確定します。

## トリガー

- `/design` で作成した設計書PRがマージされた後
- 設計書レビューが承認された後

## 使用方法

```
/approve-design [Asana依頼名]
```

または

```
/approve-design
# → doc_draft/ から最新の承認済み設計書を自動検出
```

## 前提条件

- 設計書PRがマージ済みであること
- `doc_draft/basic-design/[依頼名]/` に設計書が存在すること

## 実行フロー

### D-1: 対象特定

1. Asana依頼名を確認
2. `doc_draft/` 配下から該当する設計書を検索:
   - `doc_draft/basic-design/[依頼名]/`
   - `doc_draft/detailed-design/` 配下の関連ファイル

### D-2: 移動対象の確認

移動対象ファイルをリストアップし、ユーザーに確認:

```
以下のファイルを doc/ に移動します:

📁 基本設計
  - doc_draft/basic-design/[依頼名]/readme.md
  - doc_draft/basic-design/[依頼名]/feature/01_xxx.md
  - doc_draft/basic-design/[依頼名]/task-breakdown.md

📁 詳細設計
  - doc_draft/detailed-design/apex/xxx.md
  - doc_draft/detailed-design/trigger/xxx.md

続行しますか？ [Y/n]
```

### D-3: ファイル移動

`git mv` を使用してファイルを移動（履歴を保持）:

| 移動元（doc_draft/）                | 移動先（doc/）                      |
| ----------------------------------- | ----------------------------------- |
| `basic-design/[依頼名]/`            | `domains/[依頼名]/`                 |
| `detailed-design/apex/[file].md`    | `detailed-design/apex/[file].md`    |
| `detailed-design/trigger/[file].md` | `detailed-design/trigger/[file].md` |
| `detailed-design/lwc/[file].md`     | `detailed-design/lwc/[file].md`     |
| `detailed-design/flow/[file].md`    | `detailed-design/flow/[file].md`    |
| `detailed-design/objects/[file].md` | `detailed-design/objects/[file].md` |

**注意**: `doc_draft/requirement/` は移動しない（要件定義書は参照用として残す）

### D-4: リンク更新

移動したファイル内の相対パスを更新:

```markdown
# 更新前

[要件定義書](../../requirement/[依頼名]/requirement.md)

# 更新後

[要件定義書](../../../doc_draft/requirement/[依頼名]/requirement.md)
```

### D-5: インデックス更新

以下のインデックスファイルを更新:

1. `doc/README.md` - 承認済み設計書一覧に追加
2. `doc/domains/README.md` - ドメイン一覧に追加（存在する場合）
3. `doc/detailed-design/[type]/README.md` - 詳細設計一覧に追加

#### インデックス追記フォーマット

```markdown
## 承認済み設計書

| 依頼名   | 概要設計                                | 承認日     |
| -------- | --------------------------------------- | ---------- |
| [依頼名] | [readme.md](domains/[依頼名]/readme.md) | YYYY-MM-DD |
```

### D-6: Asanaセクション移動

タスクを「設計書承認」→「構築待ち」セクションに移動:

```bash
curl -X POST "https://app.asana.com/api/1.0/sections/{構築待ちセクションGID}/addTask" \
  -H "Authorization: Bearer {token}" \
  -H "Content-Type: application/json" \
  -d '{"data": {"task": "{AsanaタスクID}"}}'
```

**移動先セクション**: 構築待ち（GIDは要確認）

### D-7: Asanaコメント追加

```
設計書が承認されました。
📁 設計書: doc/domains/[依頼名]/

次のステップ: `/build` で構築フェーズへ進む
```

### D-8: Slack通知

**通知先チャンネル**: `C07JMC480EA`

```
✅ [依頼名] の設計書が承認されました

📁 設計書: https://github.com/classlab-inc/cl-crm-salesforce/tree/main/doc/domains/[依頼名]

次のステップ: `/build` で構築開始
```

### D-9: コミット & プッシュ

```bash
git add .
git commit -m "[承認] {依頼名} の設計書を doc/ に移動

- doc_draft/basic-design/ → doc/domains/ に移動
- doc_draft/detailed-design/ → doc/detailed-design/ に移動
- インデックスを更新

Refs: Asana#{task-id}"

git push origin HEAD
```

## 出力物

```
doc/
├── domains/
│   └── [依頼名]/
│       ├── readme.md              ← 概要設計書（移動後）
│       ├── feature/
│       │   └── 01_[機能名].md     ← 機能設計書（移動後）
│       └── task-breakdown.md      ← タスク分解（移動後）
│
├── detailed-design/
│   ├── apex/
│   │   └── [クラス名].md          ← 詳細設計（移動後）
│   ├── trigger/
│   │   └── [トリガー名].md
│   ├── lwc/
│   │   └── [コンポーネント名].md
│   └── flow/
│       └── [フロー名].md
│
└── README.md                      ← インデックス更新済み
```

## MCP連携

| MCP      | 用途                         |
| -------- | ---------------------------- |
| `asana`  | セクション移動、コメント追加 |
| `slack`  | 承認完了通知                 |
| `github` | コミット、プッシュ           |

## エラーハンドリング

| エラー                     | 対応                              |
| -------------------------- | --------------------------------- |
| 設計書が見つからない       | `doc_draft/` を検索し、候補を表示 |
| 移動先に同名ファイルが存在 | バックアップを作成して上書き確認  |
| Asanaタスクが見つからない  | タスク名で検索し、候補を表示      |

## 注意事項

- 設計書PRがマージされていることを確認してから実行
- `doc_draft/requirement/` は移動対象外（参照用として残す）
- 移動後は `doc_draft/` の該当ファイルは削除される（git mv）

## 完了条件

1. 設計書が `doc/` に移動されている
2. インデックスが更新されている
3. Asanaタスクが「構築待ち」セクションに移動されている
4. Slack通知が送信されている

## 次のステップ

承認完了後、`/build` コマンドで構築フェーズへ進む
