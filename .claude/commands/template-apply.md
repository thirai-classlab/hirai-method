---
name: template-apply
description: "テンプレート適用 - 設計書テンプレートを適用してドキュメント生成"
category: skill
complexity: basic
model: haiku
mcp-servers: []
---

# /template-apply - テンプレート適用スキル

## 概要

`.ai/templates/` 内のテンプレートを適用してドキュメントを生成するヘルパースキル。
`/design` コマンドから内部的に呼び出されます。

## 使用方法

```
/template-apply [テンプレート名] [出力パス]
```

例:
```
/template-apply apex_class doc_draft/design/[依頼名]/詳細設計書.md
/template-apply lwc doc_draft/design/[依頼名]/機能設計書.md
```

## 利用可能なテンプレート

| テンプレート | 説明 |
|-------------|------|
| `apex_class` | Apex クラス設計書 |
| `apex_trigger` | Apex トリガー設計書 |
| `apex_batch` | Apex バッチ設計書 |
| `apex_schedulable` | Apex スケジューラブル設計書 |
| `apex_rest_api` | Apex REST API 設計書 |
| `apex_invocable` | Apex Invocable 設計書 |
| `apex_handler` | Apex ハンドラー設計書 |
| `apex_controller` | Apex コントローラー設計書 |
| `apex_utility` | Apex ユーティリティ設計書 |
| `apex_test` | Apex テスト設計書 |
| `lwc` | Lightning Web Component 設計書 |
| `flow` | Flow 設計書 |
| `visualforce` | Visualforce 設計書 |

## テンプレートパス

```
.ai/templates/
├── apex_class.template.md
├── apex_trigger.template.md
├── apex_batch.template.md
├── apex_schedulable.template.md
├── apex_rest_api.template.md
├── apex_invocable.template.md
├── apex_handler.template.md
├── apex_controller.template.md
├── apex_utility.template.md
├── apex_test.template.md
├── lwc.template.md
├── flow.template.md
└── visualforce.template.md
```

## 変数置換

テンプレート内の変数を自動置換:

| 変数 | 説明 |
|------|------|
| `{{PROJECT_NAME}}` | プロジェクト名 |
| `{{CLASS_NAME}}` | クラス名 |
| `{{AUTHOR}}` | 作成者 |
| `{{DATE}}` | 作成日 |
| `{{ASANA_TASK}}` | Asanaタスク名 |

## 実行フロー

1. テンプレートファイルを読み込み
2. コンテキスト情報から変数を抽出
3. 変数を置換
4. 出力パスにファイルを生成

## 注意事項

- テンプレートが存在しない場合はエラー
- 出力先が既に存在する場合は確認を求める
- 追加機能の場合は既存ファイルとのマージを考慮
