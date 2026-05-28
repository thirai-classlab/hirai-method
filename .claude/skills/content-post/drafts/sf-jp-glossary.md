# Salesforce 英日対訳辞書（日本語UI公式表記）

3記事の本文・画像で英語表記を日本語SF UI表記に統一するための辞書。

## 商談フェーズ（標準ピックリスト値の日本語UI表示）

| 英語 (API値) | 日本語UI表記 |
|---|---|
| Prospecting | 検討 |
| Qualification | 認定 |
| Needs Analysis | ニーズ分析 |
| Value Proposition | 価値提案 |
| Id. Decision Makers | 意思決定者の特定 |
| Perception Analysis | 提案分析 |
| Proposal/Price Quote | 提案/価格見積もり |
| Negotiation/Review | 交渉/レビュー |
| Closed Won | 受注 |
| Closed Lost | 失注 |
| Pending Review | レビュー保留中 (カスタム例) |

**運用ルール**: 数式やコード (`ISPICKVAL(Stage__c, "Closed Won")`) ではAPI値を維持。本文の説明・例示値は日本語UI表記に置換。

## オブジェクト・項目・リレーション

| 英語 | 日本語UI |
|---|---|
| Account | 取引先 |
| Contact | 取引先責任者 |
| Lead | リード |
| Opportunity | 商談 |
| Case | ケース |
| Product | 商品 |
| Pricebook | 価格表 |
| Object | オブジェクト |
| Field | 項目 |
| Standard Object | 標準オブジェクト |
| Custom Object | カスタムオブジェクト |
| External Object | 外部オブジェクト |
| Lookup Relationship | 参照関係 |
| Master-Detail Relationship | 主従関係 |
| Junction Object | ジャンクションオブジェクト |
| Hierarchical Relationship | 階層関係 |
| External Lookup | 外部参照関係 |
| Indirect Lookup | 間接参照関係 |
| Many-to-Many | 多対多 |
| Picklist | 選択リスト |
| Dependent Picklist | 連動選択リスト |
| Field Dependency | 項目の連動関係 |
| Controlling Field | 制御項目 |
| Dependent Field | 従属項目 |
| Schema Builder | スキーマビルダー |
| Roll-Up Summary | 積み上げ集計項目 |
| Formula Field | 数式項目 |
| Auto Number | 自動採番 |
| Geolocation | 位置情報 |
| Long Text Area | ロングテキストエリア |

## UI レイアウト

| 英語 | 日本語UI |
|---|---|
| Page Layout | ページレイアウト |
| Compact Layout | コンパクトレイアウト |
| Highlights Panel | ハイライトパネル |
| Record Type | レコードタイプ |
| List View | リストビュー |
| Lightning Record Page | Lightning レコードページ |
| Lightning App Builder | Lightning アプリケーションビルダー |
| Section | セクション |
| Detail Section | 詳細セクション |
| Related List | 関連リスト |
| Buttons / Actions | ボタン / アクション |
| Path | パス |
| Tab | タブ |

## ルール・検証

| 英語 | 日本語UI |
|---|---|
| Validation Rule | 入力規則 |
| Required (Field) | 必須項目 |
| Field-Level Security / FLS | 項目レベルセキュリティ |
| Required (Layout) | (レイアウト)必須 |
| Duplicate Rule | 重複ルール |
| Matching Rule | 一致ルール |
| Block | 拒否 (ブロック) |
| Allow with Alert | 警告とともに許可 |
| Allow without Alert | 警告なしで許可 |

## 自動化

| 英語 | 日本語UI |
|---|---|
| Flow | フロー |
| Flow Builder | フロービルダー |
| Screen Flow | 画面フロー |
| Record-Triggered Flow | レコードトリガーフロー |
| Scheduled Flow | スケジュールフロー |
| Autolaunched Flow | 自動起動フロー |
| Before-Save Flow | 保存前フロー |
| After-Save Flow | 保存後フロー |
| Approval Process | 承認プロセス |
| Workflow Rule | ワークフロールール |
| Process Builder | プロセスビルダー |
| Apex Trigger | Apex トリガ |
| Order of Execution | 実行順序 |
| Trigger Order | トリガ順序 |

## 権限・共有

| 英語 | 日本語UI |
|---|---|
| Profile | プロファイル |
| Permission Set | 権限セット |
| Permission Set Group | 権限セットグループ |
| License | ライセンス |
| Role | ロール |
| Role Hierarchy | ロール階層 |
| Sharing Rule | 共有ルール |
| Organization-Wide Defaults / OWD | 組織の共有設定 |
| Manual Sharing | 手動共有 |
| Apex Sharing | Apex 共有 |
| Public Group | 公開グループ |
| Queue | キュー |
| Territory Management | テリトリー管理 |
| View All / Modify All | すべて表示 / すべて変更 |
| Public Read Only | 公開/参照のみ |
| Public Read/Write | 公開/参照・更新可能 |
| Private | 非公開 |
| Owner | 所有者 |
| Owner-based Sharing Rule | 所有者ベース共有ルール |
| Criteria-based Sharing Rule | 条件ベース共有ルール |
| Freeze | 凍結 |
| CRED (Create/Read/Edit/Delete) | 作成/参照/編集/削除 |

## レポート・ダッシュボード

| 英語 | 日本語UI |
|---|---|
| Report | レポート |
| Report Type | レポートタイプ |
| Custom Report Type | カスタムレポートタイプ |
| Report Folder | レポートフォルダ |
| Report Filter | レポート検索条件 |
| Filter | 絞り込み条件 |
| Filter Logic | 条件ロジック |
| Cross Filter | クロス条件 |
| Bucket Field | バケット項目 |
| Summary Formula | サマリー数式 |
| Row-Level Formula | 行レベルの数式 |
| Tabular | 表形式 |
| Summary | サマリー |
| Matrix | マトリックス |
| Joined | 結合 |
| Row Group | 行グループ |
| Column Group | 列グループ |
| Format | レポート形式 |
| Group | グループ化 |
| Sum | 集計 |
| Dashboard | ダッシュボード |
| Dynamic Dashboard | 動的ダッシュボード |
| Dashboard Filter | ダッシュボード検索条件 |
| Subscribe / Subscription | 配信登録 |
| Schedule | スケジュール |
| Snapshot / Reporting Snapshot | レポートスナップショット |
| Historical Trending | 履歴トレンドレポート |
| Run Report | レポート実行 |
| Pipeline | パイプライン |
| Forecast | 予測 |
| Salesforce DB | Salesforce データベース |

## システム・データ

| 英語 | 日本語UI |
|---|---|
| Setup | 設定 |
| Object Manager | オブジェクトマネージャ |
| Data Loader | データローダ |
| Data Import Wizard | データインポートウィザード |
| API Name | API 参照名 |
| Developer Name | 開発者名 |
| Field Dependencies | 項目の連動関係 |
| New | 新規 |
| Edit | 編集 |
| Delete | 削除 |
| Save | 保存 |
| Cancel | キャンセル |
| User | ユーザー |
| User Save | ユーザー保存 |
| DB Commit | DBコミット |

## 翻訳しないもの（固有名詞）

- `Salesforce` / `Apex` / `Lightning` / `Lightning Experience` / `Trailhead`
- API参照名（`__c` / `__x` / `Property__c` / `Stage__c` / `Amount__c` 等）
- DeveloperName (`"Renew"` 等の英語固定値)
- 関数名 (`ISPICKVAL` / `IF` / `CASE` / `TEXT` / `ISBLANK` / `REGEX` 等)
- 試験ドメイン名 (公式英語名: `Data and Analytics Management` 等。任意で日本語併記可)
- Trailhead モジュール名（公式英語名で参照されるため）
- エディション名 (`Enterprise Edition` / `Unlimited Edition`)
- プロダクト名 (`CRM Analytics` / `Einstein Analytics` / `Wave` / `Salesforce Connect`)
- リリース名 (`Spring '20` 等)
- SOQL / DML / FK 等の DB 用語
