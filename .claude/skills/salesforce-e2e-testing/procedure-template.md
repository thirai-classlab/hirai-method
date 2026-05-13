# Procedure Template — Salesforce E2E 標準テスト手順

本ファイルは [SKILL.md](SKILL.md) の補助。E2E テストを実行する際の **標準 8 phase 手順** を定義する。各テストケースはこのテンプレに沿って手順書を作成する。

## 8 Phase 全体像

```
Phase 1: Pre-check    — 環境前提を確認 (sf CLI / metadata / PS)
Phase 2: Baseline     — テスト前 state を snapshot
Phase 3: URL Mint     — sf org open でログイン URL を取得 (60s TTL)
Phase 4: Execute      — シナリオ手順を実行 (e2e-runner / user 手動)
Phase 5: Observe      — 多軸で状態を観測 (SOQL / DOM / Log / Network)
Phase 6: Assert       — PASS / FAIL / WARN を判定
Phase 7: Teardown     — テストデータ削除 / 環境復元
Phase 8: Report       — 結果集計、evidence 保存、次アクション
```

各 phase は独立した責務を持つ。失敗時は次 phase に進まず、phase 内で recovery / abort 判断。

---

## Phase 1: Pre-check

### 目的

テスト実行に必要な前提が整っているか確認。整っていなければ次 phase に進まず abort。

### 入力

- target org alias (例: `mail-in-sf`)
- 対象機能の metadata 名 (Apex / LWC / PS)
- 検証 user (admin / integration / test)

### 作業

1. `sf org list` で alias が認証済か
2. `sf project deploy validate --check-only` で対象 metadata が deploy 可能か
3. `sf data query` で必要 CMDT / Custom Setting の値確認
4. `sf data query` で対象 user の Permission Set assignment 確認
5. 外部依存（GAS WebApp URL 等）が live か（HEAD request / health endpoint）

### 出力

- 前提充足 ✅ / 不足項目リスト ❌
- 不足時は **次 phase へ進まず**、setup 完了後に再開

### 失敗時

- Permission Set 未 assign → setup 手順案内 / 自動 assign（user 承認後）
- metadata 未 deploy → deploy 実行（user 承認後）
- alias 未認証 → `sf org login` 案内（interactive）

### 担当

Agent（sf CLI subagent）+ user 承認

---

## Phase 2: Baseline

### 目的

テスト前の system state を snapshot し、テスト後の delta 計測に使用。

### 入力

- 対象 object 名（例: `MailMessage__c`, `MailThread__c`）
- 対象 user (Phase 1 と同じ)

### 作業

1. 対象 object の `COUNT()` 取得（race condition 注意）
2. 最新 N 件の Id / CreatedDate 取得（後で delta 識別）
3. 関連 child object（Attachment / Junction）も同様に count
4. 必要なら GAS / external system の state も記録

### 出力

- `pre_test_snapshot.json` (記録)
  - object 別 record count
  - 最新 N 件 Id list
  - timestamp

### 失敗時

- SOQL row limit → filter で範囲限定（CreatedDate > 直近 1h 等）
- 権限不足 → user 切替 or Phase 1 戻り

### 担当

Agent（sf CLI subagent）

---

## Phase 3: URL Mint

### 目的

60s TTL の frontdoor URL を mint し Phase 4 へ即時引渡し。

### 入力

- target org alias
- 開きたい path（例: `lightning/n/Mail_Management`）

### 作業

```bash
sf org open --target-org <alias> --path "lightning/n/<Tab>" --url-only --json
```

JSON 出力から `result.url` を抽出して保持。

### 出力

- frontdoor URL（60 秒以内に使用）
- mint timestamp（TTL 計算用）

### 失敗時

- alias auth expired → Phase 1 戻りで `sf org login` 案内
- path 無効 → root path で再 mint、user に App Launcher 案内

### 注意

- **mint 直後に Phase 4 へ**。間に重い処理を挟まない。
- 複数テストを連続実行する場合は **per-test mint**。
- e2e-runner agent への prompt 内に URL を埋込む形が安全。

### 担当

Agent（sf CLI subagent）

---

## Phase 4: Execute

### 目的

シナリオを実行（実 UI 操作 / API 呼出 / 外部システム emulate）。

### 入力

- Phase 3 で取得した URL
- シナリオ手順書（catalog の該当行）

### 作業（手段別）

#### 4a. e2e-runner agent 経由（preferred for UI シナリオ）

- e2e-runner agent に prompt 投入（URL + 操作内容 + 検証指示）
- Vercel Agent Browser / Playwright fallback で実行
- screenshot を都度取得

#### 4b. sf CLI / Anonymous Apex（API シナリオ）

- `sf apex run` で Anonymous Apex 実行
- `sf data create record` で record 作成
- 外部 trigger 系は user に依頼（メール送信、Slack ping 等）

#### 4c. User 手動（特殊 case）

- LWC visual confirmation のみで完結する場合
- e2e-runner agent では再現困難な操作（drag-and-drop 等）

### 出力

- 実行ログ (timestamp、操作、結果)
- screenshot 群
- API response body

### 失敗時

- URL expired (60s 超過) → Phase 3 戻り再 mint
- LWC 描画 fail → methodology.md の technique 切替判断
- 中途で停止 → Phase 7 (Teardown) へ jump で partial cleanup

### 担当

Agent (e2e-runner / sf CLI) + user 一部

---

## Phase 5: Observe

### 目的

テスト後の system state を多軸で観測する。観測 rule は [observation-rules.md](observation-rules.md) 参照。

### 入力

- Phase 4 の実行ログ
- Phase 2 の baseline snapshot

### 作業（5 軸）

| 軸             | 方法                          | 何を見る                               |
| -------------- | ----------------------------- | -------------------------------------- |
| **DOM**        | e2e-runner / Playwright       | element 存在、aria 属性、表示値        |
| **SOQL**       | sf CLI query                  | record の field 値、count delta        |
| **Log**        | sf CLI / GAS Logger / Slack   | error message、stack trace、retry      |
| **Network**    | Playwright / browser devtools | HTTP request/response、status、headers |
| **Screenshot** | e2e-runner / Playwright       | visual confirmation、レイアウト崩れ    |

各軸は **独立** に観測し、後で総合判定（Phase 6）。

### 出力

- `post_test_observation.json`
  - 各軸の観測結果
  - delta from baseline
- evidence ファイル群（screenshot, log dump）

### 失敗時

- observation tool が動かない → 該当軸のみ SKIP（他軸で判定）
- evidence 保存場所不在 → `docs/test-evidence/<scenario>/<timestamp>/` を作成

### 担当

Agent（sf CLI + e2e-runner）

---

## Phase 6: Assert

### 目的

Phase 5 の観測結果を catalog の PASS 条件と照合し、判定。

### 入力

- Phase 5 の `post_test_observation.json`
- catalog の該当行（PASS 条件）

### 判定軸

| 判定    | 条件                                                               |
| ------- | ------------------------------------------------------------------ |
| ✅ PASS | 全 PASS 条件を満たす                                               |
| ❌ FAIL | 必須 PASS 条件のいずれかが不一致                                   |
| ⚠️ WARN | PASS 条件は満たすが想定外の挙動（log warning, 想定外 record 作成） |

### 出力

- 判定結果（PASS / FAIL / WARN）
- 不一致項目の根拠（quote）

### 失敗時

- FAIL → Phase 7 (Teardown) 経由で Phase 8 で報告
- WARN → 継続するが Phase 8 で flag
- 判定不能 → 観測不足、Phase 5 戻り or user 判断要請

### 担当

Agent or user（catalog 設計者）

---

## Phase 7: Teardown

### 目的

テストデータを削除し、Sandbox 汚染を防ぐ。

### 入力

- Phase 2 の baseline snapshot
- Phase 4 で作成された record / file リスト

### 作業

1. テスト中作成された record を Phase 2 delta で識別
2. SOQL DELETE / `sf data delete record` で削除
3. external system 側のテストデータも整理（Gmail label、Slack 投稿等）
4. 関連 child / junction も cascade or 明示削除
5. cache / session cleanup（必要なら）

### 出力

- 削除 record リスト
- teardown 完了確認

### 失敗時

- 削除権限なし → admin に escalate
- cascade で他データを誤削除リスク → user 承認後にのみ実行
- partial cleanup → 残留 record を Phase 8 で flag

### スキップ条件

- Sandbox の週次クリーンで対応する設計 → このフェーズ skip （catalog に明記）
- 既存 record を観測する非破壊テスト → skip

### 担当

Agent（sf CLI）+ user 確認

---

## Phase 8: Report

### 目的

結果集計、evidence 保存、次アクション提案。

### 入力

- 全 phase の出力
- catalog の該当行（メタ情報）

### 出力

- レポート構造:
  ```markdown
  ## Test: <scenario name>

  - 実行日時: ...
  - 結果: PASS / FAIL / WARN
  - 所要時間: ...
  - 観測サマリ: ...
  - Evidence: links to docs/test-evidence/...
  - 次アクション: (FAIL 時) 修正タスク提案
  ```
- evidence ディレクトリへの index 更新

### 次アクション分岐

- ✅ PASS → catalog の該当 row を「最終確認日」更新、commit
- ❌ FAIL → 不具合修正タスクを `docs/tasks/` に追加
- ⚠️ WARN → 再現条件を catalog の Notes 欄に記録

### 担当

Agent + user 共同

---

## Phase 間の典型 transition

```
正常進行: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8
URL TTL 超過: 4 で気づく → 3 戻り
Pre-check fail: 1 で abort → setup 後 1 再実行
観測軸 fail: 5 で部分 SKIP → 6 で判定
FAIL: 6 で確定 → 7 (cleanup) → 8 (報告)
中断: 4 中で abort → 7 (partial cleanup) → 8 (報告)
```

## チェックリスト（テスト 1 件あたり）

実行前:

- [ ] Phase 1 前提全 OK
- [ ] catalog の該当 row 確認
- [ ] 必要なら user 承認

実行中:

- [ ] Phase 3 URL mint から Phase 4 開始まで 60s 以内
- [ ] Phase 5 で 5 軸網羅
- [ ] evidence を `docs/test-evidence/` 配下に保存

実行後:

- [ ] Phase 7 で teardown 完了
- [ ] Phase 8 報告書を作成
- [ ] catalog の最終確認日を更新

## 関連

- 観測の詳細: [observation-rules.md](observation-rules.md)
- パターン定義: [pattern-taxonomy.md](pattern-taxonomy.md)
- 技法選択: [methodology.md](methodology.md)
- プロジェクト固有 catalog: [catalog-template.md](catalog-template.md)
