# Catalog Template — プロジェクト E2E テスト catalog の雛形

本ファイルは [SKILL.md](SKILL.md) の補助。各プロジェクト / 機能領域は本 template を **複製** して `docs/test-catalog/<feature-name>.md` に配置し、自プロジェクト固有の E2E テスト catalog として運用する。

## 複製手順

```bash
cp .claude/skills/salesforce-e2e-testing/catalog-template.md \
   docs/test-catalog/<feature-name>.md
```

その後、本ファイルのプレースホルダ（`<...>` で囲まれた部分）を実値に置換。

---

## ↓↓↓ 以下、複製後にプロジェクト固有内容に書き換える ↓↓↓

# `<機能名>` E2E テスト catalog

> 本 catalog は [.claude/skills/salesforce-e2e-testing](../../.claude/skills/salesforce-e2e-testing/SKILL.md) の標準に準拠して作成。

## メタ情報

| 項目           | 内容                      |
| -------------- | ------------------------- |
| 機能           | `<機能名>`                |
| Owner          | `<Slack / GitHub handle>` |
| Sandbox alias  | `<例: mail-in-sf>`        |
| 関連 Apex      | `<クラス名 list>`         |
| 関連 LWC       | `<コンポーネント名 list>` |
| 関連 Object    | `<Object API name list>`  |
| 関連 PS        | `<PermissionSet 名 list>` |
| 作成日         | `<YYYY-MM-DD>`            |
| 最終 review 日 | `<YYYY-MM-DD>`            |

## アーキテクチャ概要

`<対象機能の data flow を 3-5 行で記述。外部システム連携があれば明示>`

```
<例:
Gmail → GAS pollMail → Apex REST /mail/sync → MailMessage__c
User (LWC) → mailCompose → Apex MailSendBridge → GAS doPost → Gmail
>
```

## カテゴリマッピング

[pattern-taxonomy.md](../../.claude/skills/salesforce-e2e-testing/pattern-taxonomy.md) の 9 カテゴリのうち、本機能で **使う / 使わない** を明示:

| カテゴリ                   | 使用    | 主な対象                                    |
| -------------------------- | ------- | ------------------------------------------- |
| A. データ操作              | ✅ / ❌ | `<例: MailMessage__c CRUD>`                 |
| B. Apex / 統合             | ✅ / ❌ | `<例: MailSyncService REST endpoint>`       |
| C. LWC / UI                | ✅ / ❌ | `<例: mailInbox, mailCompose>`              |
| D. Flow / 自動化           | ✅ / ❌ | `<例: 該当なし>`                            |
| E. 権限 / セキュリティ     | ✅ / ❌ | `<例: MailManagement PS、Integration User>` |
| F. Lifecycle               | ✅ / ❌ | `<例: session timeout 中の compose>`        |
| G. UX / Visual             | ✅ / ❌ | `<例: モバイル layout、日本語>`             |
| H. Error / Edge            | ✅ / ❌ | `<例: 25MB 超、apiKey 不正>`                |
| I. Cross-org / Integration | ✅ / ❌ | `<例: GAS WebApp 連携>`                     |

## 優先度定義

| Tier   | 意味                                                        | 実行頻度                                                 |
| ------ | ----------------------------------------------------------- | -------------------------------------------------------- |
| **P0** | **UI 関連機能・シナリオの網羅 E2E**。Wave / Phase 完了時に全件実行。これが落ちたら本番投入 NG | **各 Wave / Phase 完了時**、リリース毎、本番投入前 |
| **P1** | 重要エッジケース。リグレッション防止                        | 主要機能改修時、月次                                     |
| **P2** | 推奨追加。運用安定後の品質向上                              | 四半期、年次 review                                      |

**P0 の網羅条件**: すべての LWC component / Lightning App / Tab / Record Page で到達可能な UI 操作シナリオ全件、認証 / 権限差分、shadow DOM / LDS キャッシュ絡みの挙動、複数システム横断 round-trip を含む。「最低限スモーク 4-10 ケース」のような絞り込みは禁止 — UI 関連は **全件** が P0。

---

## P0: UI 網羅 E2E (Wave / Phase 完了時 全件実行)

| #    | パターン (taxonomy) | 概要                                                   | 副作用                                | 必須観測軸       | 期待 PASS 条件                                                 |
| ---- | ------------------- | ------------------------------------------------------ | ------------------------------------- | ---------------- | -------------------------------------------------------------- |
| P0-1 | `<A-1, B-1, I-1>`   | `<例: 外部メール送信→Sandbox MailMessage__c 1 件作成>` | `<例: テストレコード 1 件、後で削除>` | `<例: SOQL+Log>` | `<例: COUNT(MailMessage__c) +1, Subject 一致, log エラーなし>` |
| P0-2 | `<...>`             | `<...>`                                                | `<...>`                               | `<...>`          | `<...>`                                                        |

実行手順は [procedure-template.md](../../.claude/skills/salesforce-e2e-testing/procedure-template.md) の 8 phase 標準に従う。各 P0 は **シナリオ別の手順書を別途作成** することを推奨（または下記「実行記録」に inline 記述）。

### 実行記録 (P0)

| Test ID | 最終実行日     | 結果     | Evidence link              | Notes   |
| ------- | -------------- | -------- | -------------------------- | ------- |
| P0-1    | `<YYYY-MM-DD>` | ✅/❌/⚠️ | `<docs/test-evidence/...>` | `<...>` |
| P0-2    | `<YYYY-MM-DD>` | ...      | ...                        | ...     |

---

## P1: 重要エッジケース

| #    | パターン (taxonomy) | 概要                                      | 副作用  | 必須観測軸         | 期待 PASS 条件                        |
| ---- | ------------------- | ----------------------------------------- | ------- | ------------------ | ------------------------------------- |
| P1-1 | `<H-1>`             | `<例: ネットワーク切断中の compose 操作>` | `<...>` | `<DOM+Screenshot>` | `<エラー toast 表示、データロスなし>` |
| P1-2 | `<C-5>`             | `<例: 送信 form の validation>`           | なし    | DOM                | `<必須欠落で submit block>`           |

### 実行記録 (P1)

| Test ID | 最終実行日 | 結果 | Evidence link | Notes |
| ------- | ---------- | ---- | ------------- | ----- |
| P1-1    | `<...>`    | ...  | ...           | ...   |

---

## P2: 推奨追加

| #    | パターン (taxonomy) | 概要                         | 副作用 | 必須観測軸 | 期待 PASS 条件                    |
| ---- | ------------------- | ---------------------------- | ------ | ---------- | --------------------------------- |
| P2-1 | `<G-1>`             | `<例: モバイル layout 確認>` | なし   | Screenshot | `<320px viewport で表示崩れなし>` |
| P2-2 | `<G-2>`             | `<例: 日本語表示>`           | なし   | DOM        | `<label 日本語、date YYYY-MM-DD>` |

### 実行記録 (P2)

| Test ID | 最終実行日 | 結果 | Evidence link | Notes |
| ------- | ---------- | ---- | ------------- | ----- |
| P2-1    | `<...>`    | ...  | ...           | ...   |

---

## 既知の制約 / 観測不能項目

`<E2E では検証できない項目をここに列挙。例: SF 内部の wire batching タイミング>`

## 環境前提（Phase 1 Pre-check 用）

`<本機能をテストするのに必要な前提を箇条書き>`

- [ ] `<例: Sandbox alias mail-in-sf が認証済>`
- [ ] `<例: MailManagement PS が integration user に assign>`
- [ ] `<例: GAS Web App URL が CMDT に populate>`
- [ ] `<例: pollMail trigger が GAS に install 済>`

## Teardown 方針

`<例: テスト毎に作成された MailMessage__c / MailThread__c を Phase 7 で sf data delete record で削除>`

`<または: Sandbox 週次クリーンに依存、teardown skip>`

## 改版履歴

| 日付           | 変更内容 | 変更者  |
| -------------- | -------- | ------- |
| `<YYYY-MM-DD>` | 初版作成 | `<...>` |

---

## ↑↑↑ ここまでが複製対象 ↑↑↑

## 運用 tips

- 各テスト ID は機能横断で一意（`<feature>-P0-1` のような prefix 付き ID 推奨）
- 「実行記録」表は CI/CD 化したら自動更新、手動運用なら最終確認日のみ手入力
- P0 / P1 / P2 の境界が曖昧になったら quarterly で見直し
- 同じ pattern (taxonomy) を複数 catalog で参照する場合、taxonomy への back-link を維持

## 参考実例

`docs/test-catalog/mail-platform.md`（メール管理プラットフォーム）が本 template から派生した最初の実例（**本 skill には含まれない**、各プロジェクトの docs 配下）。
