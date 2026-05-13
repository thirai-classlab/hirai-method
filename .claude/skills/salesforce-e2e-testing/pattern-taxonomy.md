# Pattern Taxonomy — Salesforce E2E テストパターン分類

本ファイルは [SKILL.md](SKILL.md) の補助。Salesforce 開発の E2E テストで網羅すべきパターンを 9 カテゴリ (A-I) に分類する。各プロジェクトは該当カテゴリから必要パターンを選んで catalog 化する。

## カテゴリ一覧

| カテゴリ | 領域                    | テストの主目的                              |
| -------- | ----------------------- | ------------------------------------------- |
| A        | データ操作 (DML / SOQL) | CRUD 経路、bulk、ガバナ制限境界             |
| B        | Apex / 統合             | REST 経路、非同期、callout                  |
| C        | LWC / UI                | render、reactivity、event、shadow DOM       |
| D        | Flow / 自動化           | record-triggered、screen、scheduled         |
| E        | 権限 / セキュリティ     | profile/PS、FLS、CRUD、sharing、OAuth       |
| F        | Lifecycle               | navigation、session、refresh                |
| G        | UX / Visual             | mobile、i18n、theme、a11y                   |
| H        | Error / Edge            | network、5xx、validation、limit、concurrent |
| I        | Cross-org / Integration | inbound、outbound、retry、idempotency       |

---

## A. データ操作 (DML / SOQL)

### A-1 Create

- **何を見る**: Apex / Flow / LWC からの insert で record が作成され、required field が populate
- **典型的失敗**: required 違反、validation rule、trigger NPE、duplicate rule
- **観測**: SOQL で Id 取得、各 field 値 assert、CreatedDate 範囲

### A-2 Read

- **何を見る**: SOQL / @wire / imperative で正しい record set が返る
- **典型的失敗**: sharing で見えない、FLS で field 欠落、SOQL limit、@wire の cacheable=true 罠
- **観測**: 期待 record 数、選択 field、order

### A-3 Update

- **何を見る**: DML update / inline edit / LWC edit で field 変更が永続化
- **典型的失敗**: lock contention、trigger 再帰、CreatedDate 自動 update なし
- **観測**: LastModifiedDate 更新、SystemModstamp、変更 field 値

### A-4 Delete

- **何を見る**: manual delete / cascade / restrict 動作
- **典型的失敗**: child cascade 未実装、Restrict relationship、recycle bin 残存
- **観測**: SOQL で record 不存在、related child の状態

### A-5 Bulk (200+ records)

- **何を見る**: 大量 record DML がガバナ制限内で処理される
- **典型的失敗**: SOQL row limit (50,000)、CPU time、DML statement 数、heap size
- **観測**: 処理件数、所要時間、debug log の limit 警告

---

## B. Apex / 統合

### B-1 REST endpoint（正常系）

- **何を見る**: `@RestResource` endpoint が 200 で正しい body 返却
- **典型的失敗**: serialization 失敗、namespace prefix、status code 誤り
- **観測**: HTTP response status / body、Apex Debug Log

### B-2 REST endpoint（負テスト: 401/403/400/500）

- **何を見る**: 不正 auth / 不正 payload / Apex 例外で適切な status + error body
- **典型的失敗**: 例外を握り潰して 200 返す、stack trace 漏洩、CORS 不整合
- **観測**: HTTP status、error body 構造、log の例外 trace

### B-3 Schedulable / Batchable

- **何を見る**: schedule 登録後の execute、batch 200 record 単位処理
- **典型的失敗**: CronTrigger 未登録、Database.Batchable の retry、ガバナリセット
- **観測**: AsyncApexJob 状態、Status=Completed、NumberOfErrors

### B-4 Queueable / Future

- **何を見る**: 非同期キックで job 完了
- **典型的失敗**: chained queueable depth 制限、future 不可コンテキスト
- **観測**: AsyncApexJob、CompletedDate、JobItemsProcessed

### B-5 Trigger（before/after, 再帰防止）

- **何を見る**: bulk DML で trigger が期待回数のみ発火、再帰しない
- **典型的失敗**: 無限再帰、Trigger.new と old の混同、bulk 非対応
- **観測**: 副作用 field（Update_Count\_\_c 等）、log の trigger entry/exit

### B-6 Custom Metadata / Settings ロード

- **何を見る**: `Mdt.getInstance()` / `Settings.getOrgDefaults()` で正しい値取得
- **典型的失敗**: 同一 transaction での insert 後参照、Cache miss、test の SeeAllData
- **観測**: 取得値、log で getInstance return

### B-7 Named Credentials callout

- **何を見る**: Named Credential 経由の外部 API 呼び出し成功
- **典型的失敗**: credential 期限切れ、IP allowlist、protocol mismatch
- **観測**: HTTP request log、response、token rotation

### B-8 Platform Events

- **何を見る**: publish → subscribe で event が delivery
- **典型的失敗**: event volume limit、failed retry、CometD 接続切断
- **観測**: EventBus.publish の result、subscriber log、Replay ID

---

## C. LWC / UI

### C-1 初期 render

- **何を見る**: ページロード後 component が DOM に展開
- **典型的失敗**: connectedCallback の例外、import エラー、scoped style 崩れ
- **観測**: DOM existence、shadow root 構造、screenshot

### C-2 Loading state / spinner

- **何を見る**: 非同期処理中に spinner / skeleton が表示
- **典型的失敗**: loading=true がずっと残る、即 false で flash
- **観測**: spinner element の visibility 遷移、duration

### C-3 @wire 反応性

- **何を見る**: reactive parameter 変更で wire が再 fetch
- **典型的失敗**: reactive 変数の `$` 抜け、cacheable=true で stale、refreshApex 未呼出
- **観測**: 表示データの更新、network 再リクエスト、debug log

### C-4 imperative call

- **何を見る**: ボタン click で `@AuraEnabled` メソッド呼出 → 結果反映
- **典型的失敗**: promise エラーハンドル抜け、then/catch 順序、toast 不発火
- **観測**: response data、UI 更新、toast text

### C-5 Form validation

- **何を見る**: 入力 invalid で送信 block、エラー表示
- **典型的失敗**: client validation で stop せず server まで投げる、message 多言語化
- **観測**: error message DOM、submit button disabled、focus 遷移

### C-6 Action button / Modal open-close

- **何を見る**: ボタン click で modal/dialog 開く、閉じるで状態クリア
- **典型的失敗**: lightning-modal の close callback 不発火、backdrop click が漏れる
- **観測**: modal DOM presence、aria-hidden、focus trap

### C-7 ナビゲーション

- **何を見る**: NavigationMixin で別 page / record / URL へ遷移
- **典型的失敗**: relative URL の解釈、param 欠落、Lightning Out で動かない
- **観測**: URL 変化、新ページ DOM、history stack

### C-8 Lightning Data Service cache

- **何を見る**: `getRecord` / `getRecordCreateDefaults` のキャッシュヒット
- **典型的失敗**: stale cache、recordId 変更で再 fetch せず
- **観測**: network request の有無、data 反映

### C-9 Custom Event 親子通信

- **何を見る**: child から `dispatchEvent` で parent が受信
- **典型的失敗**: bubbles/composed 設定漏れで親に届かず、detail シリアライズ
- **観測**: parent component の state 変化、handler 呼出回数

### C-10 Toast notification

- **何を見る**: 成功 / エラー時に lightning toast 表示
- **典型的失敗**: variant 違い、自動消失なし、stacking で先のが消える
- **観測**: toast DOM、role="status"、message text

### C-11 Shadow DOM 経由の選択

- **何を見る**: テストで shadow root 内の要素を取得・操作
- **典型的失敗**: querySelector が shadow 越え不可、Playwright が pierce 失敗
- **観測**: Playwright `getByRole`、locator chain、shadowRoot.querySelector

---

## D. Flow / 自動化

### D-1 Record-triggered flow

- **何を見る**: insert/update trigger で flow が発火、record field 更新
- **典型的失敗**: entry condition mismatch、bulk 非対応、recursive update
- **観測**: 対象 field 値、FlowInterview record、debug log

### D-2 Screen flow path

- **何を見る**: ユーザ操作で screen 遷移、Resource に値設定
- **典型的失敗**: validation rule、Decision 分岐 mismatch、Loop 無限
- **観測**: 最終 screen の表示、変数値、screenshot

### D-3 Scheduled flow

- **何を見る**: schedule 登録、定刻で record バッチ処理
- **典型的失敗**: 大量 record で limit、frequency 不正、time zone
- **観測**: FlowInterview、対象 record の更新

### D-4 Auto-launched flow

- **何を見る**: Apex / Process から invoke、変数受け渡し
- **典型的失敗**: input variable mismatch、return variable 不在、subflow chain
- **観測**: 呼出元での結果取得、副作用 record

### D-5 Error handling path

- **何を見る**: Fault Connector / Default fault が error メッセージ表示
- **典型的失敗**: fault path 未設定で UnhandledFault email 飛ぶ、message 抽象的
- **観測**: 表示 message、log の Exception、admin email

---

## E. 権限 / セキュリティ

### E-1 Profile + Permission Set 組合せ

- **何を見る**: profile + PS の union で適切な permission
- **典型的失敗**: PS assign 漏れ、PS Group の inherit、Muting PS
- **観測**: SetupEntityAccess query、UI Setup の Access Check

### E-2 FLS 制限 user の表示

- **何を見る**: FLS で field 不可の user に LWC で表示されない
- **典型的失敗**: `WITH SECURITY_ENFORCED` 抜け、`stripInaccessible` 未使用
- **観測**: 異なる user で同じ LWC を開いて表示差分

### E-3 CRUD 制限操作

- **何を見る**: CRUD 不可 user が DML 試行で reject
- **典型的失敗**: Apex with sharing で bypass、`Schema.sObjectType.X.isCreateable()` 抜け
- **観測**: DML 例外、AccessException、UI の disabled state

### E-4 Sharing rule

- **何を見る**: 所有者 / Role hierarchy / Sharing rule で record 可視
- **典型的失敗**: Public Read/Write OWD で意図せず公開、Manual share 未付与
- **観測**: 異なる user で SOQL、UserRecordAccess、Sharing reason

### E-5 Apex Class Access via PS

- **何を見る**: integration user が PS 経由で Apex class 呼出可
- **典型的失敗**: classAccesses 未付与で 403 FORBIDDEN
- **観測**: SetupEntityAccess (SetupEntityType='ApexClass')、REST 401/403

### E-6 Connected App + OAuth

- **何を見る**: Username-Password Flow / JWT Bearer Flow で access_token 取得
- **典型的失敗**: invalid_grant、IP block、Client Credential mismatch
- **観測**: token response、instance_url、token exchange error

---

## F. Lifecycle

### F-1 ページ遷移

- **何を見る**: app navigation で state 保持 / リセット
- **典型的失敗**: cache 残留、background tab で wire 不発、url state lost
- **観測**: URL hash、component state、wire result

### F-2 Session timeout

- **何を見る**: 長時間放置で session expire → 再認証 prompt
- **典型的失敗**: silent re-auth で UX 断絶、unsaved data lost
- **観測**: 30 分後の API call で 401、login redirect

### F-3 再認証

- **何を見る**: session 失効後の再 login 成功 → 元 page 復帰
- **典型的失敗**: redirect 先 lost、retry 失敗、CSRF token mismatch
- **観測**: login 後の URL、operation 再実行

### F-4 Browser back/forward

- **何を見る**: navigation history で前 / 次の state が正しく restore
- **典型的失敗**: SPA history.pushState の管理漏れ
- **観測**: 戻った state の component / data

### F-5 Refresh

- **何を見る**: page reload で state 復元 / 再 fetch
- **典型的失敗**: local-only state lost、wire 再 cache されず stale
- **観測**: 再 render 後の data、network fetch

---

## G. UX / Visual

### G-1 Mobile layout

- **何を見る**: Salesforce Mobile / responsive で layout 崩れず
- **典型的失敗**: SLDS breakpoint、column 1 stack 崩れ、touch target 過小
- **観測**: 異なる viewport size の screenshot

### G-2 Localization (ja_JP)

- **何を見る**: label / message / date format が日本語適切
- **典型的失敗**: Custom Label 翻訳漏れ、date が MM/DD/YYYY のまま、漢字 vs かな
- **観測**: profile language=ja の表示、Locale=ja_JP の日付

### G-3 Lightning vs Classic

- **何を見る**: Classic でも壊れない（必要なら）
- **典型的失敗**: LWC は Lightning 専用、$Api.Session_ID の context 違い
- **観測**: 両 mode で同じページを開く

### G-4 A11y（screen reader, keyboard）

- **何を見る**: aria-label、tab order、focus visible
- **典型的失敗**: button が div で実装、aria-label 不足、focus trap 欠落
- **観測**: keyboard 操作で全機能到達、screen reader 読み上げ

---

## H. Error / Edge

### H-1 Network failure mid-action

- **何を見る**: 通信切断中の操作で適切な error 表示
- **典型的失敗**: spinner 永続、partial commit、retry なし
- **観測**: offline 状態にして操作、UI 表示、retry button

### H-2 Server 5xx

- **何を見る**: Apex 例外 / external 500 で UI が graceful 失敗
- **典型的失敗**: toast 出さず silent fail、内部 stack leak
- **観測**: toast variant=error、error message、log

### H-3 Validation rule 違反

- **何を見る**: validation rule trip で field error 表示
- **典型的失敗**: server error を生で表示、custom error message 表示崩れ
- **観測**: lightning-input の `messageWhenInvalid`、form-level error

### H-4 Trigger error

- **何を見る**: trigger 内 `addError` で operation reject、message 表示
- **典型的失敗**: 全 record reject (bulk で 1 件 fail で全部 rollback)
- **観測**: DML 例外、error message、UI display

### H-5 Concurrent edit conflict

- **何を見る**: 2 user 同時 edit で last-write-wins / optimistic lock
- **典型的失敗**: silent overwrite、SystemModstamp mismatch 未検出
- **観測**: 2 session で同 record edit、保存後の値

### H-6 Governor limit 違反

- **何を見る**: SOQL 100、DML 150、CPU 10s 等の境界
- **典型的失敗**: bulk 非対応、loop 内 SOQL、無限再帰
- **観測**: System.LimitException、debug log の limit 警告

---

## I. Cross-org / Integration

### I-1 External system POST receive

- **何を見る**: 外部システムから REST POST で record 作成
- **典型的失敗**: auth bypass、payload validation 不足、idempotency なし
- **観測**: HTTP request log、created record、HTTP response

### I-2 Outbound callout to external

- **何を見る**: Apex から external API 呼出、retry、timeout
- **典型的失敗**: timeout 短すぎ、retry なし、circuit breaker なし
- **観測**: Apex Debug Log、external system 受信記録

### I-3 Webhook 認証

- **何を見る**: HMAC / API Key / OAuth の各方式で auth
- **典型的失敗**: secret 漏洩、timing attack、replay attack
- **観測**: 不正 secret で reject、replay test

### I-4 Retry / idempotency

- **何を見る**: 重複 request で record 二重作成しない
- **典型的失敗**: unique key 欠如、retry で duplicate insert
- **観測**: 同 request 2 回送信、record count 1 のみ

---

## カテゴリ選択ガイド（プロジェクト類型別）

| プロジェクト類型       | 主要カテゴリ     | 補助カテゴリ |
| ---------------------- | ---------------- | ------------ |
| LWC + Apex CRUD UI     | A, C, E          | F, G         |
| 外部システム統合       | B, I, E          | H            |
| Workflow / Automation  | A, D, E          | H            |
| Reporting / Dashboard  | A, C, E          | G            |
| Multi-org sync         | A, B, I          | E, H         |
| メール / Inbox 系 (例) | A, B, C, E, H, I | F, G         |

具体的なプロジェクト catalog は [catalog-template.md](catalog-template.md) を複製して作成する。
