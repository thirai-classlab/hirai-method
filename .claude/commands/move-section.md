---
name: move-section
description: "Asanaタスクのセクション移動 - APIを使用してタスクを指定セクションに移動"
category: workflow
complexity: basic
model: haiku
---

# /move-section - Asanaセクション移動

## 概要

Asana APIを直接呼び出し、タスクを指定のセクションに移動するコマンド。

## 使用方法

```
/move-section {AsanaタスクURL} {移動先セクション名}
```

例:

```
/move-section https://app.asana.com/.../task/1212783078881318 依頼確定済み
```

## 実行コマンド

```bash
curl -X POST "https://app.asana.com/api/1.0/sections/{section_gid}/addTask" \
  -H "Authorization: Bearer {{ASANA_PERSONAL_ACCESS_TOKEN}}" \
  -H "Content-Type: application/json" \
  -d '{"data": {"task": "{task_gid}"}}'
```

## プロジェクト: ClassLab SalesForce 構築

### セクション一覧

| セクション名                | GID              |
| --------------------------- | ---------------- |
| 工数見積,実現可否の検証     | 1201939731380483 |
| 依頼検討中                  | 1201975562340041 |
| **依頼確定済み**            | 1203436351848909 |
| 構築中(開発環境)            | 1201939731380472 |
| お客様確認中(テスト環境)    | 1204458678797631 |
| リリース待ち                | 1202018010404869 |
| お客様確認中(本番環境)&工数 | 1201939731380525 |
| 完了                        | 1201947180153922 |
| 保留                        | 1201939731380482 |

## /design フローでの使用

PR作成後（B-7完了後）、タスクを「依頼確定済み」セクションに移動:

```bash
curl -X POST "https://app.asana.com/api/1.0/sections/1203436351848909/addTask" \
  -H "Authorization: Bearer {{ASANA_PERSONAL_ACCESS_TOKEN}}" \
  -H "Content-Type: application/json" \
  -d '{"data": {"task": "{AsanaタスクID}"}}'
```

## 注意事項

- PATはコマンド内に直接記載
- セクションGIDはプロジェクト固有
- 移動先セクションは同一プロジェクト内である必要がある
