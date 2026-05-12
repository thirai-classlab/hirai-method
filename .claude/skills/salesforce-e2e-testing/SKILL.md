---
name: salesforce-e2e-testing
description: Salesforce 開発 (LWC / Apex / Flow / Trigger / Integration) の E2E テスト設計・観測・手順の標準。テスト実行は含まず、設計・計画・レビュー時に参照する knowledge base。e2e-runner agent + sf CLI Pattern B (sf org open --url-only) を推奨技法として明示。
license: ClassLab internal
---

# Salesforce E2E Testing Standard

ClassLab の Salesforce 開発における E2E テストの **手法 (methodology)・観測 (observation)・手順 (procedure)** を標準化する。テスト実行・自動化コードは含まない。

## このスキルの性質

- ✅ **含む**: テスト設計の指針、パターン分類、手順テンプレ、観測 rules、catalog の雛形
- ❌ **含まない**: 実際の Playwright スクリプト、テストランナー、CI/CD 構成、プロジェクト固有 scenarios
- 🎯 **対象読者**: SF 開発者 / レビュワー / AI agent（テストを設計・計画する役割）

プロジェクト固有のテスト catalog は本 skill の `catalog-template.md` を雛形として各プロジェクトの `docs/test-catalog/` 配下に複製して使う。

## いつ invoke するか

| トリガー                     | 利用シーン                     |
| ---------------------------- | ------------------------------ |
| 新機能の E2E テスト設計時    | 何をテストすべきか網羅検討     |
| テスト計画レビュー時         | 観点抜けの発見、優先度判定     |
| Wave / Phase 完了時          | UI 関連機能・シナリオの **網羅 E2E** 設計 |
| リリース前 regression 計画時 | リグレッション範囲の確定       |
| AI agent への E2E 設計委譲時 | 標準的な手順・観測軸を伝達     |

## 読む順序

このスキルは 5 つの補助ファイルから構成される。**目的に応じて参照**:

1. **[methodology.md](methodology.md)** — テスト技法（Pattern B + e2e-runner、判定基準）
2. **[pattern-taxonomy.md](pattern-taxonomy.md)** — 9 カテゴリ (A-I) の汎用テストパターン分類（何をテストするか）
3. **[procedure-template.md](procedure-template.md)** — 標準テスト手順 8 phase（どう手順化するか）
4. **[observation-rules.md](observation-rules.md)** — 観測 / assertion / PASS 判定（何を見るか）
5. **[catalog-template.md](catalog-template.md)** — プロジェクト用 test catalog の空テンプレ（複製して使う）

### 用途別ナビゲーション

| やりたいこと                        | 参照すべきファイル                     |
| ----------------------------------- | -------------------------------------- |
| E2E と何かを始めて聞かれた          | SKILL.md (本ファイル) + methodology.md |
| テストパターンを網羅したい          | pattern-taxonomy.md                    |
| 個別テストの手順書を書く            | procedure-template.md                  |
| PASS / FAIL の判定基準を知りたい    | observation-rules.md                   |
| 新規プロジェクトの catalog を立てる | catalog-template.md（複製して使う）    |

## 基本思想

### 1. フェーズ / Wave 完了時は UI 関連機能・シナリオを網羅 E2E

E2E は遅く・脆いが、**UI に関連する機能とシナリオは網羅的に E2E でテストする**。「重要な最低限のみ」では LWC / Lightning Experience / shadow DOM / LDS キャッシュの複雑な UI 相互作用に起因するバグを取り逃がすため、各 Wave / Phase 完了時に **網羅的 E2E** を完了条件に含める。

**Wave / Phase 完了時の E2E 必須範囲（網羅対象）**:

- すべての LWC component の UI 操作シナリオ（クリック / 入力 / 選択 / 検証メッセージ）
- 各 Lightning App / Tab / Record Page の主要ユースケース全件
- ユーザ操作で到達可能なすべての画面遷移（navigation / modal / quick action）
- 認証 / 権限による UI 表示差分（Admin / Integration / End User）
- shadow DOM / LDS キャッシュが絡む UI 挙動（再描画 / wire 反応）
- 複数システム横断（GAS ↔ Apex ↔ LWC 等）の round-trip シナリオ
- UI からトリガされる Flow / Apex の end-to-end 動作

**E2E から除外可能**（引き続き Apex Test / jest で代替）:

- 単一 Apex メソッドの正常 / 異常系 → Apex Test
- 単一 LWC の wire / event の reactive 反応のみ → jest
- 単一 LWC のスナップショット → jest snapshot
- ビジネスロジック単体（UI を通さない計算 / バリデーション）→ Apex Test

UI を 1 つでも触る変更を含む Wave / Phase は、UI 関連シナリオの **網羅 E2E 実行** が完了条件。最低限スモークでの代替は禁止。

### 2. 手法は Pattern B 標準

ログインは `sf org open --url-only --json` で frontdoor URL を mint、e2e-runner agent or Playwright で開く。MFA 回避 + 追加 user 不要 + 認証情報コードに含めない。詳細は **[methodology.md](methodology.md)**。

### 3. 観測は多軸

UI の screenshot のみに依存しない。**SOQL データ assertion + DOM 構造 + ログ (GAS Logger / Apex Debug) + Network レスポンス** を組合せる。詳細は **[observation-rules.md](observation-rules.md)**。

### 4. Teardown 必須

Sandbox 汚染を防ぐため、テストで作成したレコードは必ず削除する。または「テスト後の状態を完全に記述してレビュー可能にする」。詳細は **[procedure-template.md](procedure-template.md)** の Phase 8。

### 5. Catalog で可視化

各プロジェクトは「何を E2E でテストしているか」を `docs/test-catalog/[feature].md` で公開し、レビュー / 引継 / 改修時に参照可能な状態に保つ。詳細は **[catalog-template.md](catalog-template.md)**。

## 適用前の前提

このスキルを使うプロジェクトは以下が整っていること:

- `sf` CLI が target org に認証済み (`sf org list` で確認)
- Sandbox alias が明確 (例: `mail-in-sf`)
- 対象機能の Apex / LWC / metadata がデプロイ済 (`sf project deploy validate` で確認)
- 必要な Permission Set が integration / test user に assign 済

整っていない場合は **本 skill を invoke せず**、まず環境構築を完了させる。

## 関連 skill / agent

- **e2e-runner agent**: 実行を担当（Vercel Agent Browser preferred / Playwright fallback）。本 skill が標準化するのは「e2e-runner に何を依頼するか」「結果をどう判定するか」
- **verification-loop skill**: コード変更後の build/type/lint/test/security/diff 6 phase 検証。E2E はこのループの一部 phase として組込む
- **eval-harness skill**: Eval-Driven Development。E2E テストの合否基準を eval として定義する場合に併用
- **webapp-testing skill**: 一般 webapp 向け Playwright skill。SF 認証経路が異なるため本 skill が SF 特化版を提供

## 改版ポリシー

- Salesforce Release (Spring / Summer / Winter) ごとに、`methodology.md` の URL TTL / frontdoor 仕様変更を見直す
- 新機能 / 廃止機能（例: `clasp run` の API Executable 仕様変更 等）に追随
- 改版時は本 SKILL.md の「読む順序」セクションに変更点を明記

## 例: メール管理プラットフォーム

ClassLab メール管理プラットフォーム（`docs/test-catalog/mail-platform.md`）が本 skill 適用の最初の実例。catalog-template から複製し、9 カテゴリの該当パターン (A/B/C/E/H/I) を組み合わせて P0-P2 で構造化している（**この skill 自体には含まれない**）。
