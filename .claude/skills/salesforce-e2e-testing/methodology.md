# Methodology — Salesforce E2E テスト技法

本ファイルは [SKILL.md](SKILL.md) の補助。E2E テスト実行に推奨する **技法 (technique)** を定義する。

## 推奨技法: Pattern B（`sf org open --url-only` + e2e-runner agent）

### 概要

Salesforce CLI の `sf org open --url-only --json` で **single-use 60 秒 TTL の frontdoor URL** を mint し、e2e-runner agent（Vercel Agent Browser preferred / Playwright fallback）で開く。**MFA 回避・追加 user 不要・credentials がコードに残らない**。

### コマンド例

```bash
# org root を開く
sf org open --target-org <alias> --url-only --json

# 特定 Lightning App / Tab を開く
sf org open --target-org <alias> --path "lightning/n/<TabName>" --url-only --json

# 特定 record を開く
sf org open --target-org <alias> --path "lightning/r/<ObjectApi>/<recordId>/view" --url-only --json

# FlexiPage / App page を開く
sf org open --target-org <alias> --path "lightning/app/<AppApi>" --url-only --json
```

`--json` 指定で `url` フィールドに完全な frontdoor URL が含まれる。`url-only` で URL のみ取得（ブラウザを開かない）。

### 60 秒 TTL 制約

CLI v2.81.8 (2025/8) 以降、`--url-only --json` で取得した URL は **single-use・60 秒で失効** する。

**運用ルール**:

1. URL mint **直後** に e2e-runner / Playwright に渡す
2. テストケース毎に **per-test で再 mint**（事前にまとめて mint して保存・再利用は禁止）
3. CI 実行で長いセットアップを挟む場合は、UI 操作開始の直前で mint

### e2e-runner agent 連携

#### 標準 prompt template

```text
Open this Salesforce Lightning URL and verify [テスト内容].

URL: <mint した frontdoor URL>
Constraints:
- URL is single-use and expires in 60 seconds — open immediately
- After landing, expect Lightning Experience interface
- Do NOT navigate to login page; the URL contains pre-authenticated session
- Take screenshot before any interaction
- [テスト固有の検証手順]
- Report: PASS / FAIL with screenshot path and any error
```

#### Vercel Agent Browser vs Playwright fallback

e2e-runner agent は内部で Vercel Agent Browser を preferred 経路として試行し、不可なら Playwright にフォールバックする。明示指定が必要な場合は prompt に記載。

| Backend              | 利点                                               | 制約                        |
| -------------------- | -------------------------------------------------- | --------------------------- |
| Vercel Agent Browser | Headless、AI 操作、スクショ自動                    | Vercel 環境依存             |
| Playwright           | 完全 local、shadow DOM piercing native、debug 容易 | install 必要、起動 overhead |

### Shadow DOM の扱い

LWC は Lightning Experience 内で **shadow DOM** に閉じている。Playwright は **`>>` シャドウ piercing が native** で動く。`getByRole` / `locator(...).filter(...)` が SF UI でも動作する。

Vercel Agent Browser は AI 駆動なので「メールリストの最初の行をクリック」のような **自然言語指示で shadow DOM 越え** が可能。

## 代替技法

### Pattern A: MFA 免除テスト専用ユーザー

CI/CD 環境で `sf` CLI 認証 context が共有しにくい場合 / 完全に unattended で複数 alias 切替する場合は、専用 user (`ci-e2e-tests@...`) に `Waive Multi-Factor Authentication for Exempt Users` permission set + Login IP Range 制限を組合せる方式が公式推奨。詳細手順:

1. Sandbox / 本番でテスト専用 user を新規作成
2. 「自動テスト用」profile（最小権限 + 必要な PS）を assign
3. 「Multi-Factor Authentication for User Interface Logins」を含む PS（または System Permission "Waive Multi-Factor Authentication for Exempt Users"）を assign
4. Network Access で CI/CD の IP range を Trusted IP に登録
5. Playwright login で username/password で login（MFA 出ない）

**Pattern A を選ぶ場合**:

- License 追加コスト許容
- 監査で「test user 用途を文書化」要請がある
- 同一 org に複数開発者 / 複数 CI job が並行 access

### Pattern C: JWT Bearer Flow + frontdoor

Connected App + 証明書ベース JWT で `sf org login jwt` を unattended 化、その後 Pattern B と同じく frontdoor URL を mint。

**Pattern C を選ぶ場合**:

- 完全 unattended が必要（cron / GitHub Actions / CI）
- 個人 SFDX auth token を CI に置けない
- 証明書管理 / Connected App 設計の運用負荷を許容

### Pattern D: `storageState` cookie reuse（Playwright）

初回 login（Pattern A/B/C いずれか）でセッション cookie を `storageState.json` に保存、以降のテストはそれを load して login skip。**Pattern A/B/C と組合せて使う高速化技法**で、単独の代替ではない。

### Pattern E: TOTP shared secret 自動化（非推奨）

TOTP secret を vault に保存しコードから生成・MFA prompt に入力。**MFA theater** で監査 reject されやすい。**避ける**。

## 技法選択フローチャート

```
Q1: テストを今すぐ 1 回試したいだけ?
  YES → Pattern B（30 秒で実行可能）
  NO ↓

Q2: 個人 SFDX auth context を使える環境?
  YES → Pattern B + Pattern D（storageState で高速化）
  NO ↓

Q3: License 追加コスト OK?
  YES → Pattern A + Pattern D
  NO ↓

Q4: Connected App + 証明書管理 OK?
  YES → Pattern C + Pattern D
  NO → Pattern A を再検討 / または LWC unit (jest) で代替可能か再評価
```

## E2E と他テストの境界

| テスト種別         | ツール                   | 速度   | 範囲                                           | カバー対象                     |
| ------------------ | ------------------------ | ------ | ---------------------------------------------- | ------------------------------ |
| Apex Test          | `sf apex run test`       | 高速   | Apex 1 クラス                                  | ビジネスロジック、SOQL、DML    |
| LWC unit           | sfdx-lwc-jest (jsdom)    | 高速   | 1 component                                    | wire / event / template render |
| Integration        | Apex Test (mock callout) | 中     | Apex + 外部 stub                               | callout 経路、retry、auth      |
| **E2E (本 skill)** | **e2e-runner + sf CLI**  | **遅** | **Gmail/外部 → GAS → Apex → SF → LWC → 実 UI** | **真の round-trip、UI 描画**   |

**E2E に上げる判断基準（Wave / Phase 完了時は網羅）**:

- **UI 操作を含むすべてのシナリオ**（Wave / Phase 完了時の網羅範囲）
- LWC / Lightning Experience で実描画が必要なすべての画面遷移
- 認証 / 権限の実 user 体感（profile / permission set 別 UI 差分）
- shadow DOM / LDS キャッシュが絡む UI 挙動
- 複数システム横断（GAS ↔ Apex ↔ LWC 等）の round-trip
- UI からトリガされる Flow / Apex の end-to-end 動作
- リリース blocker / 自動 regression 価値高

**E2E に上げない判断基準（引き続き 単体テストで代替）**:

- 単一 Apex メソッドの正常系 / 異常系 → Apex Test
- 単一 LWC の wire / event の reactive 反応 → jest
- 単一 LWC のスナップショット → jest snapshot
- ビジネスロジック単体（UI を通さない計算 / バリデーション）→ Apex Test

## 環境ごとの注意

| 環境        | 注意点                                                     |
| ----------- | ---------------------------------------------------------- |
| Scratch Org | 短命、毎回フル setup 必要、E2E より jest 中心が現実的      |
| Sandbox     | 標準的 E2E 対象、データ汚染を teardown で管理              |
| Production  | E2E は原則禁止、smoke のみ。Sandbox で完全検証後に本番投入 |

## 失敗時の technique 切替

Pattern B で連続失敗する典型と切替:

| 症状                      | 推定原因                     | 切替先                           |
| ------------------------- | ---------------------------- | -------------------------------- |
| 「URL expired」エラー     | mint から 60 秒経過          | mint を per-test に変更          |
| 「Invalid session」エラー | session context 不一致       | sf CLI 再 login (Pattern A 検討) |
| LWC が描画されない        | "second-class" session token | Pattern A に切替                 |
| 同時並行で session 衝突   | sf CLI auth が単一           | Pattern A or C で複数 user 用意  |

詳細な error pattern と recovery は [observation-rules.md](observation-rules.md) 参照。

## まとめ

- 第一選択: **Pattern B (`sf org open --url-only`) + e2e-runner agent**
- CI/CD: **Pattern A + Pattern D** または **Pattern C + Pattern D**
- 避ける: **Pattern E**（監査 reject）
- 60 秒 TTL の per-test mint を厳守
