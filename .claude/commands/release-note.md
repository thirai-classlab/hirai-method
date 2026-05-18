---
name: release-note
description: "リリースノート作成 - Asanaタスクから非エンジニア向けリリースノートを生成"
category: workflow
complexity: enhanced
model: opus
mcp-servers: [asana, github]
---

# /release-note - リリースノート作成

## 概要

AsanaタスクURLを入力し、非エンジニア向けのリリースノートを自動生成するコマンド。
技術詳細ではなく「何が変わったか」「どう使うか」を伝えることを目的とする。

## 対象読者

- 非エンジニア（営業、CS、管理者など）
- 機能の追加/変更を把握したいステークホルダー

## 使用方法

```
/release-note {AsanaタスクURL}
```

例:

```
/release-note https://app.asana.com/1/1200587159396891/project/1201939731380471/task/1212783078881318
```

## 実行フロー

### Step 1: AsanaタスクURLからタスクID抽出

URLパターン: `https://app.asana.com/.../task/{task_id}`

### Step 2: Asanaから情報取得

```
asana_get_task:
  task_id: {タスクID}
  opt_fields: name,notes,custom_fields,custom_fields.name,custom_fields.text_value,custom_fields.enum_value,custom_fields.display_value
```

取得項目:
| 項目 | 用途 |
|------|------|
| name | 機能名 |
| notes | 背景・目的・依頼内容 |
| 依頼種別 | 新機能 / 改修 / バグ修正 |
| 実装方法,セグメント | 影響範囲の特定 |
| 【APP】Git開発ブランチ | Git情報の特定 |

### Step 3: Gitから変更概要を取得

カスタムフィールド「【APP】Git開発ブランチ」からブランチURLを取得し、以下を実行:

```bash
# ブランチ名を抽出
branch_name=$(echo "{GitブランチURL}" | sed 's|.*/tree/||')

# 関連PRを検索
gh pr list --head "{branch_name}" --json number,title,body,url

# PRの変更ファイル一覧
gh pr view {PR番号} --json files
```

### Step 4: 設計書から機能詳細を取得（任意）

以下のパスを参照（存在する場合）:

- `doc_draft/requirement/{依頼名}/requirement.md`
- `doc_draft/basic-design/{依頼名}/readme.md`
- `doc_draft/basic-design/{依頼名}/feature/*.md`

### Step 5: リリースノート生成

テンプレート（`.ai/templates/release_note.template.md`）に基づき生成

## 出力先

`release_note_dist/{依頼名}/release-note.md`

## カスタムフィールドGID参照

| フィールド名               | GID              |
| -------------------------- | ---------------- |
| 依頼種別                   | 1201975562340066 |
| 実装方法,セグメント        | 1206473222489511 |
| 【APP】Git開発ブランチ - 1 | 1212822927674553 |
| 【APP】Git開発ブランチ - 2 | 1212822927674555 |
| 【APP】Git開発ブランチ - 3 | 1212822927674557 |

## 依頼種別の値

| enum_value GID   | 名前     |
| ---------------- | -------- |
| 1201975562340067 | 保守     |
| 1207986026567981 | 質問     |
| 1201975562340068 | 別途見積 |
| 1201976005712360 | 瑕疵対応 |
| 1202463306510195 | 随時対応 |
| 1207764263348032 | 不明     |

## MCP連携

| MCP      | 用途                     |
| -------- | ------------------------ |
| `asana`  | タスク情報取得           |
| `github` | PR情報、変更ファイル取得 |

## テンプレート参照

- `.ai/templates/release_note.template.md`

## 注意事項

- Gitブランチ情報がない場合はAsana情報のみでリリースノートを生成
- 設計書が存在しない場合はスキップ
- テンプレートは後から改修可能な設計

## 今後の拡張予定

- [ ] Slack通知機能
- [ ] Asanaコメントへの投稿
- [ ] 複数タスクの一括処理
