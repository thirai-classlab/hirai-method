---
name: sentry-pr
description: "Sentry導入PR作成 - apply-rules実行後のコミット・プッシュ・PR作成を自動実行"
category: workflow
complexity: basic
model: opus
mcp-servers: []
---

# /sentry-pr - Sentry導入PR自動作成

## 概要

`/apply-rules` 実行後の変更をコミット・プッシュし、PRを作成するコマンド。
変更点のサマリーを自動生成する。

## 使用方法

```
/sentry-pr $ARGUMENTS
```

**引数:** 対象ファイル名（例: `TaskTriggerHandler.cls`）

---

## 実行手順

### Step 1: 引数の検証

- `$ARGUMENTS` が空の場合 → エラー: `対象ファイルを指定してください。例: /sentry-pr TaskTriggerHandler.cls`
- 現在のブランチが `Sentry-` で始まることを確認

### Step 2: 変更サマリーの生成

`git diff` を実行し、以下の情報を抽出する：

1. **変更ファイル一覧**（`git diff --name-only`）
2. **変更統計**（`git diff --stat`）
3. **コード変更の要約**:
   - Phase 1 (コーディングルール): `with sharing` 追加、Javadoc追加 等
   - Phase 2 (Sentry): breadcrumb追加箇所、try-catch変更 等
   - Phase 3 (設計書): 更新セクション
4. **関連テストクラスの探索**:
   以下の順序で対応するテストクラスを探索する。
   - `{クラス名}Test.cls` が存在するか確認（例: `TaskTriggerHandler.cls` → `TaskTriggerHandlerTest.cls`）
   - 見つからない場合、`force-app/main/default/classes/` 内で `@IsTest` かつクラス名の一部を含むファイルを検索
   - 見つからない場合、「⚠️ テストクラスなし」とレポートに記載
   - 複数見つかった場合はすべて列挙する

### Step 3: コミット

変更ファイルをステージングし、以下の形式でコミットする：

```
[Sentry] {ファイル名} - コーディングルール適用 & Sentryエラー追跡追加

Phase 1: コーディングルール適用
- with sharing 追加
- クラス/メソッド Javadoc 追加

Phase 2: Sentry エラー追跡追記
- メソッド開始・終了ブレッドクラム追加
- 既存 catch に Sentry.preserveStackTrace/record 追加

Phase 3: 詳細設計書更新
- エラーハンドリングセクションに Sentry 情報追記
- 改訂履歴更新
```

### Step 4: プッシュ

```bash
git push -u origin {ブランチ名}
```

### Step 5: PRのbaseブランチ選択と確認

ユーザーにPRのbaseブランチ（マージ先）を選択してもらう。

**選択肢:**
- `main`
- `dev`
- `stg`
- `STG` で始まるブランチ（例: `STG-release-2026-02`）

`STG` で始まるブランチを選択肢に含める場合は、`git branch -r` でリモートの `STG*` ブランチを一覧取得して候補に追加する。

**選択後、必ず以下の確認を行う:**

> 「`{選択されたブランチ}` ブランチにPRしてもよろしいでしょうか？」

ユーザーが承認した場合のみ、次のStep 6に進む。
拒否された場合は、再度ブランチ選択に戻る。

### Step 6: PR作成

`gh pr create --base {選択されたブランチ}` で PR を作成する。以下のテンプレートを使用：

```markdown
## 概要
{ファイル名} に Sentry エラー追跡を導入

## ドメイン
{ドメイン名}（git diff またはファイル内容から推定）

## 変更内容
- [x] Phase 1: コーディングルール適用
- [x] Phase 2: Sentry エラー追跡追記
- [x] Phase 3: 詳細設計書更新

### Phase 1: コーディングルール
{自動生成: 修正した項目リスト}

### Phase 2: Sentry 追記
{自動生成: 追加したブレッドクラム/catch変更のサマリー}

### Phase 3: 設計書
{自動生成: 更新したセクション}

## ファイル種別
{TriggerHandler / Batch / REST API / Controller / Service 等}

## リリース時に実行するテストクラス
| # | テストクラス | パス |
|---|------------|------|
| 1 | {テストクラス名} | `force-app/main/default/classes/{テストクラス名}.cls` |

**デプロイコマンド例:**
```bash
sf project deploy start -m ApexClass:{変更クラス名} -m ApexClass:{テストクラス名} --test-level RunSpecifiedTests --tests {テストクラス名} --target-org {org}
```

{テストクラスが見つからない場合は以下を記載}
> ⚠️ 対応するテストクラスが見つかりません。リリース前にテストクラスの作成または特定が必要です。

## テスト確認
- [ ] 上記テストクラスが PASS すること
- [ ] Sentry のブレッドクラム・エラー送信が適切なこと（コードレビューで確認）

## 関連
- Asana タスク: [Sentry追加プロジェクト](https://app.asana.com/0/1213212167180469)
- /apply-rules 実行結果: 下記レポート参照
```

### Step 7: 結果表示

PR の URL を表示する。

---

## 注意事項

- コミット前に `git diff` で変更内容を確認する
- PR の base ブランチはユーザーが選択（main / dev / stg / STG*）
- base ブランチは必ずユーザーに確認してから PR を作成する
- レビュアーは指定しない（手動で追加）
