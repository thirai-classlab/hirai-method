<!--
approval_required: true
approved_at: 2026-05-28
approved_by: user
retroactive: false
-->

# sync workflow の proactive 改善（G2: harness-sync-proactive-workflow）

**ステータス:** 🔲 **draft（2026-05-28 起案、user 承認済「追加」+「確定して全て進めて」）**
**起点:** harness-engineer レビュー G2（資料 `harness-health-7items-analysis.md` §8/§9）。F（stale 検出）は事後 WARN のみで再発を防げない
**前提:** task-56=F（stale-harness 検出）は reactive 検出。本 task は proactive 取込を担う

---

## 1. 真因サマリ / 課題サマリ

F（stale-harness-detection）は consuming repo が旧 harness で稼働中だと SessionStart で **事後 WARN** するが、「いつ・どの branch に `install.sh --update` を取り込むか」の **proactive な運用手順が存在しない**。classlab は最新 sync を未マージ branch に隔離したまま旧 harness で稼働継続 → F だけでは WARN が繰り返され改善しない。

**真因:** harness 取込の運用 workflow（タイミング / branch 戦略 / 自動化）が未定義。F は検出のみで取込を促さない。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 取込チェックリスト（stg*/main merge 前に `install.sh --update` 実施を規範化） | 0.5 | 軽量 | honor system |
| **B** | CI（GitHub Actions）で SSoT との .claude diff を定期検出 → PR / issue 自動起票 | 2.5 | 自動・確実 | CI 構築 + consuming repo ごと設定、cross-repo は user manual |
| **C ハイブリッド** | A（チェックリスト規範）+ F の WARN に「`install.sh --update` 実行手順」を含める + B は将来 opt-in | 1.0 | 規範 + F 連携で取込を促す、CI は段階導入 | 完全自動化は将来 |

→ **C ハイブリッド** 推奨。F の WARN に具体的取込手順を含め、規範でチェックリスト化。CI 自動 diff（B）は consuming repo 側の opt-in で将来導入。

---

## 3. 採用案の詳細設計

#### Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 規範（development-process.md or modes.md）に「harness 取込チェックリスト」追加（stg*/main merge 前 / 定期 `install.sh --update`） | 0.4h | task-56=F |
| 2 | 🔲 | F の stale WARN 文に「`bash install.sh --update <repo>` で取込」手順を含める | 0.3h | task-56=F |
| 3 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 | 0.3h | Step 2 |
| 4 | 🔲 | (テスト合格) grep 検証（規範追記）+ F WARN smoke に手順文字列確認追加 | 0.2h | Step 3 |
| 5 | 🔲 | (リファクタリング) 3 観点 or skip | 0.1h | Step 4 |

合計: 約 1.3h。CI 自動 diff（案 B）は parking-lot 将来 task として別途。

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| チェックリストが honor system で守られない | M | M | F の WARN（機械検出）と連携して実効性を補完 |
| 規範追記が常時注入を肥大（G9 違反） | M | L | 追記は paths-scoped（development-process.md）へ、CommonRules は 1 行リンク |

---

## 6. 完了条件（DoD）

- [ ] 取込チェックリストが development-process.md に追加（grep 検証）
- [ ] F の stale WARN に取込手順が含まれる（smoke 検証）
- [ ] G9 原則遵守（常時注入層に 1 行リンクのみ）
- [ ] CI 自動 diff（案 B）は parking-lot に将来 task として記録

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | — | — | — | — | — | — | 未実施 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-28 | user | 「追加」+「確定して全て進めて」で承認 |

---

## 10. 関連

- 統合分析資料: [`harness-health-7items-analysis.md`](harness-health-7items-analysis.md) §8/§9（G2）
- 関連 task: task-56=F（stale-harness 検出、本 task の前提）/ task-58=G1（未 commit drift）
- 将来 task（parking-lot）: CI 自動 .claude diff 検出（案 B）
