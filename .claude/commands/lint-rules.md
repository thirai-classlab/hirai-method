---
name: lint-rules
description: "コーディングルールチェック - 現在のブランチで新規作成されたファイルに対してコーディングルール・リスク・非機能要件をチェック"
category: quality
complexity: standard
model: sonnet
mcp-servers: []
---

# /lint-rules - コーディングルールチェック（拡張版）

## 概要

現在のブランチで新規作成されたファイルに対して、以下の3カテゴリのチェックを実施するコマンドです。

| カテゴリ | チェック内容 | ルールファイル |
|---------|------------|---------------|
| **A. コーディングルール** | 命名規則、ドキュメント規則、セキュリティ | `apex-naming.md`, `apex-documentation.md`, `security-checklist.md` |
| **B. リスクチェック** | トリガー連鎖、フロー影響、デプロイ影響 | `risk-checklist.md` |
| **C. 非機能要件** | ガバナ制限、バルク処理、パフォーマンス | `nfr-checklist.md` |

## 使用方法

```
/lint-rules
```

または特定のカテゴリのみをチェック:

```
/lint-rules [category]
# 例: /lint-rules code     # コーディングルールのみ
# 例: /lint-rules risk     # リスクチェックのみ
# 例: /lint-rules nfr      # 非機能要件のみ
```

## リスクレベル定義

| レベル | ラベル | 説明 | 対応 |
|--------|--------|------|------|
| 🔴 | **Critical** | 本番環境に重大な影響、ガバナ制限超過の可能性 | 必須対応 |
| 🟠 | **High** | 一部機能に影響、パフォーマンス低下の可能性 | 要検討 |
| 🟡 | **Medium** | 軽微な影響、最適化の余地あり | 推奨対応 |

## 実行フロー

### 1. 新規ファイル一覧の取得

```bash
# デフォルトブランチ（develop）との差分で新規追加されたファイルを取得
git diff --name-status develop...HEAD | grep '^A' | cut -f2
```

### 2. チェックルールの読み込み

`.ai/rules/` 配下の全ルールファイルを読み込む:

| ルールファイル | 対象 |
|---------------|------|
| `apex-naming.md` | Apex 命名規則 |
| `apex-documentation.md` | Apex ドキュメンテーション規則 |
| `security-checklist.md` | セキュリティチェックリスト |
| `risk-checklist.md` | リスクチェックリスト |
| `nfr-checklist.md` | 非機能要件チェックリスト |

### 3. 設計書の読み込み（リスクチェック用）

リスクチェックでは以下のドキュメントも参照:

- `doc/detailed-design/objects/` - オブジェクト設計書
- `doc/detailed-design/trigger/` - トリガー設計書
- `doc/detailed-design/flow/` - フロー設計書

### 4. ファイル種別によるルール適用

| ファイル種別 | コードルール | リスク | NFR |
|-------------|-------------|--------|-----|
| `*.cls` (Apex クラス) | ✅ | ✅ | ✅ |
| `*.trigger` (Apex トリガー) | ✅ | ✅ | ✅ |
| `*.js` (LWC JavaScript) | ✅ セキュリティのみ | - | - |
| `*.html` (LWC HTML) | ✅ セキュリティのみ | - | - |
| `*.flow-meta.xml` (フロー) | - | ✅ | - |
| `*.object-meta.xml` (オブジェクト) | - | ✅ | - |
| `*.field-meta.xml` (項目) | - | ✅ | - |

---

## A. コーディングルールチェック

### A.1 apex-naming.md からのチェック項目

**クラス名:**
- [ ] PascalCase になっているか
- [ ] 適切なサフィックス（Controller, Service, Handler, TriggerHandler, Batch, Scheduler, Queueable, Action, Api, RestResource, Selector, Domain, Factory, Exception, Mock, Test, Utils/Helper）が付いているか
- [ ] 40文字以内か
- [ ] 小文字始まりでないか

**メソッド名:**
- [ ] camelCase になっているか
- [ ] 動詞から始まっているか（get, find, query, create, insert, update, upsert, delete, send, validate, convert, parse, build, process, handle, execute, schedule）
- [ ] Boolean メソッドは is/has/can/should で始まっているか

**TriggerHandler メソッド名:**
- [ ] handleBeforeInsert, handleBeforeUpdate 等の命名パターンに従っているか

**Trigger 名:**
- [ ] `[ObjectApiName]Trigger` パターンに従っているか

**テストクラス:**
- [ ] `[テスト対象クラス名]Test` パターンに従っているか
- [ ] テストメソッド名が `test[メソッド名]_[シナリオ]` パターンに従っているか

**変数・定数:**
- [ ] ローカル変数/メンバ変数/パラメータが camelCase になっているか
- [ ] 定数が SCREAMING_SNAKE_CASE になっているか

### A.2 apex-documentation.md からのチェック項目

**クラスレベル:**
- [ ] クラス先頭にドキュメンテーションコメント（`/** ... */`）があるか
- [ ] `@description` でクラスの説明が記載されているか
- [ ] `@see` で詳細設計書へのリンクが記載されているか
- [ ] リンク先パスが `doc/detailed-design/` 形式になっているか

**メソッドレベル:**
- [ ] すべての `public`/`global` メソッドにドキュメンテーションコメントがあるか
- [ ] `@description` でメソッドの説明が記載されているか
- [ ] 引数がある場合、すべての引数に `@param` が記載されているか
- [ ] 戻り値がある場合（void 以外）、`@return` が記載されているか

### A.3 security-checklist.md からのチェック項目

**SOQL/SOSLインジェクション:**
- [ ] 動的 SOQL でユーザー入力を `String.escapeSingleQuotes()` でエスケープしているか
- [ ] バインド変数 `:variable` を使用しているか
- [ ] `Database.query()` にユーザー入力を直接使用していないか

**XSS:**
- [ ] Visualforce で `escape="false"` を不用意に使用していないか
- [ ] LWC で innerHTML を直接操作していないか

**アクセス制御:**
- [ ] `with sharing` を適切に使用しているか
- [ ] CRUD チェック（`isCreateable()`, `isUpdateable()`, `isDeletable()`）を実装しているか
- [ ] FLS チェックを実装しているか

**その他:**
- [ ] 機密情報をログ出力していないか
- [ ] 例外メッセージに機密情報を含めていないか

---

## B. リスクチェック

### B.1 トリガー連鎖リスク

| # | チェック項目 | リスクレベル |
|---|-------------|-------------|
| 1 | 同一オブジェクトに既存トリガーが存在するか | 🔴 Critical |
| 2 | トリガーから他オブジェクトの DML → 他トリガー呼び出しの可能性 | 🔴 Critical |
| 3 | 再帰呼び出し防止機構（Static フラグ）があるか | 🟠 High |
| 4 | トリガーの実行順序に依存する処理があるか | 🟠 High |

### B.2 フロー影響リスク

| # | チェック項目 | リスクレベル |
|---|-------------|-------------|
| 1 | 同一オブジェクトにレコードトリガーフローが存在するか | 🔴 Critical |
| 2 | Apex トリガーとフローが同じ項目を更新していないか | 🔴 Critical |
| 3 | フローの Before/After 設定との競合がないか | 🟠 High |

### B.3 デプロイ影響リスク

| # | チェック項目 | リスクレベル |
|---|-------------|-------------|
| 1 | 既存データへの影響（必須項目追加等） | 🔴 Critical |
| 2 | 入力規則の追加・変更 | 🟠 High |
| 3 | 数式項目・積み上げ集計項目の変更 | 🟠 High |
| 4 | Apex テストが 75% 以上を維持しているか | 🔴 Critical |

---

## C. 非機能要件チェック（NFR）

### C.1 ガバナ制限チェック

| # | チェック項目 | リスクレベル | 検出パターン |
|---|-------------|-------------|-------------|
| 1 | ループ内での SOQL クエリ | 🔴 Critical | `for.*{[^}]*\[SELECT` |
| 2 | ループ内での DML 操作 | 🔴 Critical | `for.*{[^}]*(insert\|update\|delete)` |
| 3 | ネストされたループ内での処理 | 🟠 High | 二重ループ検出 |
| 4 | 無制限の SOQL（LIMIT なし） | 🟠 High | `SELECT.*FROM.*(?!LIMIT)` |
| 5 | Future メソッドの連続呼び出し | 🔴 Critical | ループ内 @future |

### C.2 バルク処理対応チェック

| # | チェック項目 | リスクレベル |
|---|-------------|-------------|
| 1 | SOQL クエリがバルク対応（IN 演算子使用）しているか | 🔴 Critical |
| 2 | DML 操作がバルク対応（リスト操作）しているか | 🔴 Critical |
| 3 | Map/Set を使用してルックアップしているか | 🟠 High |
| 4 | Trigger.new/old をコレクション処理しているか | 🔴 Critical |
| 5 | 200 レコードでテストしているか | 🟠 High |

### C.3 パフォーマンス指標チェック

| # | チェック項目 | リスクレベル |
|---|-------------|-------------|
| 1 | SELECT で必要な項目のみ取得しているか | 🟡 Medium |
| 2 | WHERE 句でインデックス可能項目を使用しているか | 🟠 High |
| 3 | 大量のオブジェクトをヒープに保持していないか | 🟠 High |
| 4 | Describe コールをキャッシュしているか | 🟠 High |
| 5 | 正規表現の Pattern をキャッシュしているか | 🟡 Medium |

### C.4 org全体の日次リソース予算チェック

org全体で共有される日次ガバナ制限に影響する処理が含まれる場合、予算管理シートとの整合性を確認する。

管理シート: https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/

| # | チェック項目 | リスクレベル | 検出パターン | 管理シート |
|---|-------------|-------------|-------------|------------|
| 1 | 非同期処理（Batch/Queueable/Future/Scheduled）の日次実行予算 | 🔴 Critical | `Database.Batchable`, `Queueable`, `@future`, `Schedulable` の実装 | [非同期実行予算（gid=1338771297）](https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/edit?gid=1338771297#gid=1338771297) |
| 2 | API実行（REST/SOAP/外部Callout）の日次実行予算 | 🔴 Critical | `HttpRequest`, `HttpCalloutMock`, `WebServiceCallout`, 外部API呼び出し | [API実行予算（gid=1408277633）](https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/edit?gid=1408277633#gid=1408277633) |

**確認観点:**
- **DailyAsyncApexExecutions**: 非同期処理が新規追加・変更される場合、既存の消費量と合わせて日次上限内に収まるか確認。超過するとバッチ・Queueable等が実行不可になる。
- **DailyApiRequests**: API実行が新規追加・変更される場合、既存の消費量と合わせて日次上限内に収まるか確認。超過するとSalesforceが停止する可能性がある。
- 非機能要件（日次予算）が未定義の場合は 🔴 Critical として報告し、早急な定義を求める。

### C.5 プラットフォーム・インフラ管理チェック

GAS・オンプレミス・拡張機能の開発が含まれる場合、対応する管理シートへの登録状況を確認する。

| # | チェック項目 | リスクレベル | 管理シート |
|---|-------------|-------------|------------|
| 1 | GAS（Google Apps Script）開発が管理シートに登録されているか | 🟠 High | [GAS管理（gid=274510541）](https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/edit?gid=274510541#gid=274510541) |
| 2 | オンプレミス（Windowsサーバー）処理が管理シートに登録されているか | 🟠 High | [オンプレミス管理（gid=1085039133）](https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/edit?gid=1085039133#gid=1085039133) |
| 3 | 拡張機能（Chrome拡張等）が管理シートに登録されているか | 🟠 High | [拡張機能管理（gid=1621667722）](https://docs.google.com/spreadsheets/d/1nQTqOUhGNTxLCg-RJJvS_9PIP8rOCwH9LyrnpxWEpkg/edit?gid=1621667722#gid=1621667722) |

---

## 出力形式

### サマリー

```
========================================
コーディングルールチェック結果（拡張版）
========================================
チェック対象ファイル数: X 件
========================================

## サマリー

| カテゴリ | Critical | High | Medium | 合計 |
|---------|----------|------|--------|------|
| A. コーディングルール | X | X | X | X |
| B. リスクチェック | X | X | X | X |
| C. 非機能要件 | X | X | X | X |
| **合計** | **X** | **X** | **X** | **X** |

========================================
```

### 詳細レポート

```markdown
## A. コーディングルール違反

### 1. force-app/main/default/classes/ExampleClass.cls

| # | ルール | カテゴリ | 行番号 | リスク | 違反内容 | 修正提案 |
|---|--------|----------|--------|--------|----------|----------|
| 1 | apex-naming | クラス名 | 1 | 🟠 High | 小文字始まりのクラス名 | `ExampleClass` に変更 |
| 2 | security | SOQL | 25 | 🔴 Critical | エスケープなしの動的SOQL | `String.escapeSingleQuotes()` を使用 |

---

## B. リスクチェック結果

### トリガー連鎖リスク

| # | 対象 | リスク | 詳細 | 対応策 |
|---|------|--------|------|--------|
| 1 | AccountTrigger | 🔴 Critical | Contact への DML が ContactTrigger を呼び出す可能性 | 再帰防止フラグを追加 |

### フロー影響リスク

| # | 対象 | リスク | 詳細 | 対応策 |
|---|------|--------|------|--------|
| 1 | Account_After_Update Flow | 🟠 High | 同じ Status__c 項目を更新 | 実行順序を確認 |

### デプロイ影響リスク

| # | 対象 | リスク | 詳細 | 対応策 |
|---|------|--------|------|--------|
| 1 | RequiredField__c | 🔴 Critical | 必須項目追加（デフォルト値なし） | デフォルト値を設定 |

---

## C. 非機能要件チェック結果

### ガバナ制限

| # | ファイル | 行番号 | リスク | 指摘内容 | 修正提案 |
|---|----------|--------|--------|----------|----------|
| 1 | ExampleService.cls | 45 | 🔴 Critical | ループ内 SOQL | ループ外でバルク取得 |

### バルク処理対応

| # | ファイル | リスク | 指摘内容 | 修正提案 |
|---|----------|--------|----------|----------|
| 1 | AccountTriggerHandler.cls | 🟠 High | Map 未使用のネストループ | Map でルックアップを最適化 |

### パフォーマンス指標

| # | ファイル | 行番号 | リスク | 指摘内容 | 修正提案 |
|---|----------|--------|--------|----------|----------|
| 1 | ReportService.cls | 78 | 🟡 Medium | SELECT * 相当のクエリ | 必要項目のみ取得 |

---

## 総合判定

### リリース判定チェックリスト

- [ ] Critical 指摘: X 件 → すべて対応必須
- [ ] High 指摘: X 件 → リリース判断時に検討
- [ ] Medium 指摘: X 件 → 可能であれば対応

### 判定結果

- [ ] ✅ リリース可能（Critical なし）
- [ ] ⚠️ 条件付きリリース可能（Critical 対応後）
- [ ] ❌ リリース不可（Critical 未解決）
```

### 違反なしの場合

```
========================================
コーディングルールチェック結果（拡張版）
========================================
チェック対象ファイル数: X 件
========================================

## サマリー

| カテゴリ | Critical | High | Medium | 合計 |
|---------|----------|------|--------|------|
| A. コーディングルール | 0 | 0 | 0 | 0 |
| B. リスクチェック | 0 | 0 | 0 | 0 |
| C. 非機能要件 | 0 | 0 | 0 | 0 |
| **合計** | **0** | **0** | **0** | **0** |

========================================
✅ すべてのファイルがチェックに合格しました！
リリース判定: リリース可能
========================================
```

---

## 実行例

```bash
# Claude Code CLI でコマンド実行（全チェック）
claude "/lint-rules"

# コーディングルールのみ
claude "/lint-rules code"

# リスクチェックのみ
claude "/lint-rules risk"

# 非機能要件のみ
claude "/lint-rules nfr"
```

---

## 関連ドキュメント

- `.ai/rules/apex-naming.md` - Apex 命名規則
- `.ai/rules/apex-documentation.md` - Apex ドキュメンテーション規則
- `.ai/rules/security-checklist.md` - セキュリティチェックリスト
- `.ai/rules/risk-checklist.md` - リスクチェックリスト
- `.ai/rules/nfr-checklist.md` - 非機能要件チェックリスト
- `.ai/instructions/review.md` - コードレビュー指示
- `doc/detailed-design/` - 設計書（リスク分析で参照）

---

## 更新履歴

| 日付 | 更新者 | 内容 |
|------|--------|------|
| 2026-01-16 | - | 初版作成 |
| 2026-02-05 | - | リスクチェック・非機能要件チェック機能を追加 |
