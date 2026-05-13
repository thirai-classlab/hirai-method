# Observation Rules — 観測・assertion・PASS 判定ルール

本ファイルは [SKILL.md](SKILL.md) の補助。E2E テストの **何を / どう / どこまで観測するか** を標準化する。procedure の Phase 5 (Observe) と Phase 6 (Assert) で参照。

## 観測の 5 軸

各テストは以下 5 軸を網羅して観測する。1 軸 = 1 evidence source。

### 1. DOM 軸（UI 構造）

#### 何を見るか

- 期待 element の存在 / 非存在
- text content の一致
- aria 属性（role, label, hidden）
- class / disabled state
- focus 位置

#### ツール

- e2e-runner agent: 自然言語で「ボタンが表示されているか」
- Playwright: `expect(locator).toBeVisible()`, `expect(locator).toHaveText(...)`

#### 評価ルール

- ✅ PASS: 期待 selector で element 取得、属性一致
- ❌ FAIL: element 取得不能、テキスト不一致
- ⚠️ WARN: 取得できるが想定外属性混入

#### 注意

- LWC は shadow DOM。selector は piercing 対応
- Loading state を待つ。`waitFor` で element 安定化

### 2. SOQL 軸（データ実体）

#### 何を見るか

- record の存在 / 非存在
- field 値（type 含む）
- count delta（baseline 比）
- related child の cascade

#### ツール

- `sf data query --target-org <alias> --query "SELECT ..."` （subagent 委譲）
- `sf data query --json` で structured 取得

#### 評価ルール

- ✅ PASS: 期待 record が期待値で存在
- ❌ FAIL: record 不存在 / field 値 mismatch / count 不一致
- ⚠️ WARN: 余分 record が混入（cleanup 漏れ）

#### 注意

- SOQL row limit (50k) に注意、必要なら where 句で絞る
- timezone を意識（CreatedDate は UTC）
- Custom Setting / CMDT は同 transaction 不可

### 3. Log 軸（実行ログ）

#### 何を見るか

- Apex Debug Log の例外 stack
- GAS Logger (`Logger.log`) の trace
- Slack notification の有無 / 内容
- External system log（Gmail label、Drive 等）

#### ツール

- `sf apex log list` / `sf apex log get` で Apex Debug
- GAS Web Editor → 実行ログ（user 確認）または `clasp logs`
- Slack: web UI / channel API

#### 評価ルール

- ✅ PASS: 期待 log 出力あり、例外なし
- ❌ FAIL: 想定外例外、error log
- ⚠️ WARN: warning level の log、retry log

#### 注意

- Debug Log は user 毎、trace flag 必要
- GAS Logger は **実行ログ画面で目視 or `clasp logs`**（リアルタイム視聴は GAS Web Editor）

### 4. Network 軸（HTTP 通信）

#### 何を見るか

- API request URL / method / body
- response status / body / headers
- timing（timeout 内）
- 認証 header（Authorization, apiKey 等）

#### ツール

- Playwright `page.on('request', ...)` / `page.on('response', ...)`
- Vercel Agent Browser の network capture
- `sf data query --use-tooling-api` で API call log（限定）

#### 評価ルール

- ✅ PASS: 期待 endpoint への期待 status response
- ❌ FAIL: 4xx/5xx unexpected、timeout、無 call
- ⚠️ WARN: retry が想定より多い、slow response

#### 注意

- CORS 制約で browser から外部 API 直叩きは見えない
- Salesforce 内部の Aura/LWC ↔ Apex は internal request、observability 限定

### 5. Screenshot 軸（visual）

#### 何を見るか

- レイアウト崩れ
- localization（日本語表示）
- error toast / modal display
- responsive 挙動

#### ツール

- e2e-runner agent / Playwright `page.screenshot()`
- baseline screenshot との diff（option）

#### 評価ルール

- ✅ PASS: 期待画面と一致（人間判定 or pixel diff threshold）
- ❌ FAIL: 表示崩れ、欠落、error visible
- ⚠️ WARN: minor visual change、font 差

#### 注意

- viewport size を catalog で明示（320 / 768 / 1024 / 1440）
- timestamp は image filename に含めて再現性確保

---

## PASS / FAIL / WARN 判定の総合ルール

### ✅ PASS 条件

**全 5 軸**（または catalog で明示した必須軸）が PASS。

### ❌ FAIL 条件（即失敗）

- 必須軸（catalog で _required_）のいずれかが FAIL
- 例外発生（Apex / JS unhandled exception）
- データ整合性破壊（孤立 record、ロック残留）
- セキュリティ違反（権限 bypass、apiKey 漏洩）

### ⚠️ WARN 条件

- 必須軸は PASS だが、optional 軸で想定外
- log に warning が出ているが操作完了
- visual diff が threshold 内だが目視で気になる

WARN は **継続するが catalog の Notes 欄に記録**。連続 WARN は P0 化検討。

### 判定不能 (?)

- 観測 tool が不安定（network 接続不可、screenshot 失敗）
- 観測軸が catalog で未定義
- expected value が catalog に書かれていない

**判定不能 = テスト再設計** が必要、PASS とみなしてはならない。

---

## Evidence 保存規約

### ディレクトリ構造

```
docs/test-evidence/
└── <feature-name>/
    └── <scenario-id>/
        └── <timestamp>/
            ├── screenshot-<phase>.png
            ├── soql-<phase>.json
            ├── apex-log-<phase>.txt
            ├── network-<phase>.har
            └── report.md
```

### 命名規約

- `<feature-name>`: 機能領域（例: `mail-platform`, `account-management`）
- `<scenario-id>`: catalog の ID（例: `P0-1`, `C-5`）
- `<timestamp>`: ISO 8601 形式（例: `2026-05-12T10-30-00Z`）
- `<phase>`: Phase 番号（例: `phase4-execute`, `phase5-observe`）

### 保存期間

- PASS の evidence: 30 日（最新のみ保持、古いものは削除）
- FAIL の evidence: **永続**（bug fix 完了後も regression 防止のため）
- WARN の evidence: 90 日

### Evidence のスタイル

- ファイル先頭にメタ情報（timestamp、user、env）
- 機微情報（API Key、PII）は **redact**（末尾 6 文字以外マスク）
- バイナリ（screenshot）以外は plain text / json で diff 可能に

---

## 観測「しない」境界

以下は E2E では **観測しない**（unit / integration test の責務）:

- Apex 内部関数の input/output（→ Apex Test）
- LWC component の internal state（→ jest）
- DB index 効率（→ Performance Test）
- Memory profile（→ Apex Test System.Limits）
- 機微情報の暗号化アルゴリズム（→ Security Audit）

E2E は「**user / 外部システムから観測可能な振る舞い**」のみ扱う。

---

## 共通エラーパターン辞書

過去観測された FAIL / WARN の代表的 message / 対処:

### Apex / API

| エラー                                                         | 原因                              | 対処                                   |
| -------------------------------------------------------------- | --------------------------------- | -------------------------------------- |
| `FORBIDDEN: You do not have access to the Apex class named: X` | classAccesses 未付与              | PS に classAccesses 追加               |
| `INVALID_LOGIN`                                                | password + token 未連結、IP block | Connected App OAuth Policy、Trusted IP |
| `INVALID_SESSION_ID`                                           | session timeout                   | Phase 3 URL mint 再実行                |
| `LIMIT_EXCEEDED: ApexCPU`                                      | loop 内 SOQL、bulk 非対応         | Apex bulkify                           |
| `INSUFFICIENT_ACCESS_OR_READONLY`                              | sharing / OWD                     | Sharing Rule, profile 確認             |

### LWC / UI

| 症状                 | 原因                                 | 対処                                         |
| -------------------- | ------------------------------------ | -------------------------------------------- |
| LWC が描画されない   | shadow DOM piercing 失敗、wire error | Playwright `getByRole` 使用、@wire error log |
| Toast が見えない     | variant ミスマッチ、auto-close       | element wait + screenshot                    |
| Modal が閉じない     | close event 未 handle                | event bubbles/composed 確認                  |
| @wire が更新されない | reactive `$` 抜け                    | `@wire(method, { param: '$reactive' })`      |

### Network / Auth

| エラー             | 原因                    | 対処                               |
| ------------------ | ----------------------- | ---------------------------------- |
| `URL expired`      | mint から 60s 超        | per-test mint                      |
| `401 unauthorized` | apiKey / token mismatch | Custom Metadata 確認、token rotate |
| `403 FORBIDDEN`    | PS / FLS / sharing      | E-1 / E-2 / E-4 trace              |
| `CORS error`       | Origin mismatch         | Connected App / CSP 確認           |

### Data Integrity

| 症状             | 原因                                    | 対処                            |
| ---------------- | --------------------------------------- | ------------------------------- |
| Duplicate record | unique key 欠如、retry idempotency なし | Composite key、external Id      |
| Orphan child     | cascade delete 不在                     | Master-Detail relationship 確認 |
| Stale cache      | Lightning Data Service stale            | `refreshApex` 呼出              |

---

## 観測の自動化提案

将来的に CI/CD 化する場合:

- Phase 5 の SOQL 軸: GitHub Actions で `sf data query` 結果を assertion script に流す
- Log 軸: Apex Debug Log を artifact として保存
- Screenshot 軸: visual regression tool（Percy, Chromatic）連携
- Evidence: tarball で run artifact、index は GitHub Actions Summary

ただし本 skill の範囲は **観測 rules の定義** までであり、自動化実装は scope 外。

## 関連

- 手順: [procedure-template.md](procedure-template.md)
- パターン: [pattern-taxonomy.md](pattern-taxonomy.md)
- 技法: [methodology.md](methodology.md)
- Catalog 雛形: [catalog-template.md](catalog-template.md)
