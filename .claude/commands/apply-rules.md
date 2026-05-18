---
name: apply-rules
description: "ルール適用 - 指定Apexファイルにコーディングルール適用・Sentryエラー追跡追記・詳細設計書更新を一括実行"
category: quality
complexity: enhanced
model: opus
mcp-servers: []
---

# /apply-rules - コーディングルール適用 & Sentry追記 & 設計書更新

## 概要

指定したApexファイルに対して、以下の3つを一括で実行するコマンド。

1. **Phase 1:** コーディングルールチェック＆修正（コード編集）
2. **Phase 2:** Sentryエラー追跡の追記（コード編集）
3. **Phase 3:** 対応する詳細設計書の更新（設計書編集）

## 使用方法

```
/apply-rules $ARGUMENTS
```

**引数:** 対象ファイルパスまたはファイル名

```
/apply-rules TaskTriggerHandler.cls
/apply-rules force-app/main/default/classes/TaskTriggerHandler.cls
/apply-rules force-app/main/default/triggers/EmployeeTrigger.trigger
```

---

## 事前チェック

コマンド実行時、以下を確認してからフェーズを開始する。

### 1. 引数の検証

- `$ARGUMENTS` が空の場合 → エラー: `対象ファイルを指定してください。例: /apply-rules TaskTriggerHandler.cls`
- ファイルが存在しない場合 → `force-app/main/default/classes/` と `force-app/main/default/triggers/` を検索して候補を提示

### 2. 対象外ファイルのスキップ

以下のファイルは自動的にスキップし、理由を表示して終了する。

| パターン | 理由 |
|---------|------|
| `*Test.cls`, `*TEST.cls` | テストクラス |
| `Sentry*.cls` | Sentry基盤クラス |
| `*Mock.cls` | モッククラス |

### 3. ファイル種別の自動判定

対象ファイルを読み込み、以下の順で種別を判定する。

| 優先順 | 判定条件 | 種別 |
|-------|---------|------|
| 1 | `.trigger` 拡張子 | **Trigger** |
| 2 | `@RestResource` アノテーション | **REST API** |
| 3 | `Database.Batchable` を実装 | **Batch** |
| 4 | `Schedulable` を実装 | **Schedulable** |
| 5 | `Queueable` を実装 | **Queueable** |
| 6 | `@AuraEnabled` メソッドを含む | **Controller** |
| 7 | クラス名に `Handler` / `TriggerHandler` | **TriggerHandler** |
| 8 | 上記以外 | **Service/Utility** |

### 4. 対応する詳細設計書の特定

| コードファイルの場所 | 設計書の場所 |
|-------------------|------------|
| `force-app/.../classes/XxxYyy.cls` | `doc/detailed-design/apex/xxx-yyy.md` |
| `force-app/.../triggers/XxxTrigger.trigger` | `doc/detailed-design/trigger/xxx-trigger.md` |

**命名変換:** PascalCase → kebab-case

---

## Phase 1: コーディングルールチェック＆修正

### 参照するルールファイル

以下のルールファイルを**すべて読み込んでから**チェックを開始する。

1. `.ai/rules/apex-naming.md` - 命名規則
2. `.ai/rules/apex-documentation.md` - ドキュメンテーション規則
3. `.ai/rules/security-checklist.md` - セキュリティチェックリスト
4. `.ai/rules/risk-checklist.md` - リスクチェックリスト
5. `.ai/rules/nfr-checklist.md` - 非機能要件チェックリスト
6. `.ai/instructions/code-generation.md` - コード生成指示
7. `.ai/instructions/review.md` - レビュー指示

### 自動修正する項目

対象ファイルを読み込み、以下の違反を検出して**自動修正**する。

| # | チェック項目 | 修正内容 |
|---|-------------|---------|
| 1 | クラスJavadocコメント不足 | `/** @description ... @see doc/detailed-design/... */` を追加 |
| 2 | public/globalメソッドのJavadoc不足 | `/** @description ... @param ... @return ... */` を追加 |
| 3 | `with sharing` 未指定 | `with sharing` を追加（REST API等は `without sharing` が適切な場合あり。判断して適用） |

### レポートのみの項目（自動修正しない）

以下はレポートに警告として記載するが、自動修正は行わない。

| # | チェック項目 | 理由 |
|---|-------------|------|
| 1 | CRUD/FLSチェック未実装 | 自動修正は危険 |
| 2 | ループ内SOQL/DML | リファクタリングが必要 |
| 3 | トリガー連鎖リスク | 設計判断が必要 |
| 4 | フロー影響リスク | 設計判断が必要 |
| 5 | 動的SOQLのエスケープ不足 | コンテキスト判断が必要 |

---

## Phase 2: Sentryエラー追跡の追記

### 参照するガイドライン

以下を**必ず読み込んでから**Sentry追記を開始する。

- `doc/manual/sentry-guidelines.md` - Sentry運用ガイドライン（テンプレート・ルール全体）

### 追記前チェック

- 対象ファイルに既に `Sentry.addBreadcrumb` または `Sentry.record` が存在する場合 → **スキップ**（レポートに「Sentry導入済み」と記載）
- 既存の `try-catch` がある場合 → 二重にせず、既存の `catch` ブロック内にSentryコードを追加

### ファイル種別ごとの追記内容

#### TriggerHandler / Trigger

各public/globalメソッドに対して：

```apex
// メソッド冒頭に追加
Sentry.addBreadcrumb(
    'クラス名.メソッド名 entered',
    'info',
    new Map<String, Object>{
        'recordCount' => records.size(),
        'triggerContext' => 'AFTER_INSERT'  // 実際のコンテキストに合わせる
    }
);

// 既存処理をtry-catchで囲む（既存try-catchがあればその中に追加）
try {
    // === 既存処理 ===

    Sentry.addBreadcrumb('クラス名.メソッド名 completed', 'info');

} catch (Exception e) {
    Sentry.preserveStackTrace(e);
    Sentry.addBreadcrumb('Exception caught: ' + e.getMessage(), 'error',
        new Map<String, Object>{
            'exceptionType' => e.getTypeName(),
            'lineNumber' => e.getLineNumber()
        }
    );
    Sentry.record(e);
    throw e;  // Trigger/TriggerHandlerは必ず再スロー
}
```

#### Batch

- `start()`: ブレッドクラムのみ（jobId含む）
- `execute()`: ブレッドクラム + try-catch + Sentry送信（**throwしない** - 他のスコープを継続させるため）
- `finish()`: ブレッドクラムのみ（jobId含む）

```apex
// execute() の catch
} catch (Exception e) {
    Sentry.preserveStackTrace(e);
    Sentry.addBreadcrumb('Batch exception: ' + e.getMessage(), 'error');
    Sentry.record(e);
    // Batchはrethrowしない
}
```

#### REST API (@RestResource)

```apex
// メソッド冒頭: リクエスト情報をブレッドクラムに含める
RestRequest req = RestContext.request;
Sentry.addBreadcrumb('クラス名.メソッド名 entered', 'info',
    new Map<String, Object>{
        'httpMethod' => req.httpMethod,
        'requestUri' => req.requestURI,
        'params' => req.params
    }
);

// catch: エラーレスポンスを返す
} catch (Exception e) {
    Sentry.preserveStackTrace(e);
    Sentry.addBreadcrumb('API exception: ' + e.getMessage(), 'error');
    Sentry.record(e);
    RestContext.response.statusCode = 500;
    return 'Internal Server Error';  // 既存のレスポンス形式に合わせる
}
```

#### Controller (@AuraEnabled)

```apex
// catch: AuraHandledExceptionをスロー
} catch (Exception e) {
    Sentry.preserveStackTrace(e);
    Sentry.addBreadcrumb('Error: ' + e.getMessage(), 'error');
    Sentry.record(e);
    throw new AuraHandledException(e.getMessage());
}
```

#### Schedulable / Queueable

```apex
// execute() にブレッドクラム + try-catch + Sentry送信
} catch (Exception e) {
    Sentry.preserveStackTrace(e);
    Sentry.addBreadcrumb('Exception: ' + e.getMessage(), 'error');
    Sentry.record(e);
    // 状況に応じてrethrowするか判断
}
```

#### Service / Utility（中間層）

**try-catchは追加しない。** ブレッドクラムのみ追加する（トランザクション終端原則）。

```apex
// メソッド冒頭
Sentry.addBreadcrumb('クラス名.メソッド名 entered', 'info',
    new Map<String, Object>{ 'recordCount' => records.size() }
);

// メソッド末尾
Sentry.addBreadcrumb('クラス名.メソッド名 completed', 'info');
```

### 追記時の重要ルール

| # | ルール |
|---|--------|
| 1 | **既存try-catchの尊重** - 既存のtry-catchがあれば、そのcatch内にSentryコードを追加。二重try-catchにしない |
| 2 | **preserveStackTrace必須** - catch内で最初に `Sentry.preserveStackTrace(e)` を呼ぶ |
| 3 | **ブレッドクラムのフォーマット** - `'クラス名.メソッド名 entered/completed'` の形式 |
| 4 | **コンテキスト情報** - メソッド引数、レコード件数、ID等をMap<String, Object>で含める |
| 5 | **機密情報の除外** - パスワード、トークン、認証情報をブレッドクラムに含めない |
| 6 | **既存ロジック不変** - 既存の業務ロジックは一切変更しない。Sentryコードの追記のみ |

---

## Phase 3: 詳細設計書の更新

### 対応する設計書を開く

事前チェックで特定した設計書ファイルを読み込む。

- 設計書が**存在する**場合 → 該当セクションを更新
- 設計書が**存在しない**場合 → レポートに「⚠️ 設計書なし: doc/detailed-design/apex/xxx.md が見つかりません」と警告。設計書の新規作成は行わない

### 更新するセクション

#### セクション「エラーハンドリング」

既存の「エラーハンドリング」セクション（通常セクション9）に、以下を追記または更新する。

```markdown
### X.X Sentry エラー追跡

| メソッド | ブレッドクラム | try-catch | Sentry送信 | 備考 |
|---------|-------------|-----------|-----------|------|
| handleAfterInsert | 開始・終了 | あり | record + throw | トランザクション終端 |
| handleAfterUpdate | 開始・終了 | あり | record + throw | トランザクション終端 |

**例外処理方針:**
- トランザクション終端で catch し、`Sentry.preserveStackTrace(e)` → `Sentry.record(e)` → `throw e` の順で処理
- ビジネスエラーは `addError()` で処理（Sentryに送信しない）
- システムエラーは Sentry に送信後、再スロー
```

**注意:** 上記テーブルの内容は実際のメソッド名・追記内容に合わせて記載する。

#### セクション「改訂履歴」

既存の「改訂履歴」セクション（通常セクション12）に1行追加する。

```markdown
| X.X | 2026-XX-XX | Sentryエラー追跡追加、コーディングルール適用（/apply-rules） |
```

**バージョン:** 既存の最新バージョンのマイナーバージョンを+1する（例: 1.0 → 1.1）

---

## レポート出力

3つのフェーズ完了後、以下の形式でレポートを表示する。

```markdown
========================================
/apply-rules 実行結果
========================================
対象ファイル: [ファイル名]
ファイル種別: [TriggerHandler / Batch / REST API / Controller / Service 等]
対応設計書: [設計書パス] または「なし（警告）」
========================================

## Phase 1: コーディングルールチェック

| # | ルール | 行番号 | リスク | 内容 | 対応 |
|---|--------|--------|--------|------|------|
| 1 | documentation | - | 🟠 | クラスJavadoc不足 | ✅ 修正済み |
| ... | ... | ... | ... | ... | ... |

（違反なしの場合: 「✅ コーディングルール違反なし」）

## Phase 2: Sentry追記

| # | 対象メソッド | 追記内容 |
|---|-------------|---------|
| 1 | handleAfterInsert | ブレッドクラム（開始・終了）+ try-catch + Sentry送信 |
| ... | ... | ... |

（既に導入済みの場合: 「ℹ️ Sentry導入済み - スキップ」）

## Phase 3: 設計書更新

| # | 更新セクション | 内容 |
|---|--------------|------|
| 1 | エラーハンドリング | Sentry追跡情報を追記 |
| 2 | 改訂履歴 | v[X.X] 変更履歴を追記 |

（設計書なしの場合: 「⚠️ 設計書が見つかりません」）

========================================
完了
========================================
```

---

## 参照ドキュメント

本コマンド実行時に読み込むドキュメント一覧。

| ドキュメント | フェーズ | 用途 |
|-------------|---------|------|
| `.ai/rules/apex-naming.md` | Phase 1 | 命名規則 |
| `.ai/rules/apex-documentation.md` | Phase 1 | ドキュメンテーション規則 |
| `.ai/rules/security-checklist.md` | Phase 1 | セキュリティチェック |
| `.ai/rules/risk-checklist.md` | Phase 1 | リスクチェック |
| `.ai/rules/nfr-checklist.md` | Phase 1 | 非機能要件チェック |
| `.ai/instructions/code-generation.md` | Phase 1 | コード生成指示 |
| `.ai/instructions/review.md` | Phase 1 | レビュー指示 |
| `doc/manual/sentry-guidelines.md` | Phase 2 | Sentry運用ガイドライン |
| `.ai/templates/apex_class.template.md` | Phase 3 | 設計書テンプレート（参考） |
| `.ai/templates/apex_trigger.template.md` | Phase 3 | トリガー設計書テンプレート（参考） |
