<!--
approval_required: true
approved_at: 2026-05-28
approved_by: user
retroactive: false
-->

# 未 commit sync drift の対応（G1: harness-sync-uncommitted-drift）

**ステータス:** 🔲 **draft（2026-05-28 起案、user 承認済「追加」+「確定して全て進めて」）**
**起点:** 5 リポ調査（2026-05-28）+ harness-engineer レビュー G1（資料 `harness-health-7items-analysis.md` §8/§9）
**前提:** install.sh --update が SSoT を同期するが commit はしない設計

---

## 1. 真因サマリ / 課題サマリ

consuming repo が `install.sh --update` を実行すると `.claude/` が更新されるが **commit はされない**。結果、harness-sync 変更と project 作業が working tree に混在し、分離されないまま 1 commit に巻き込まれる（recall_poc / taskManageSystem で実証、未 commit drift 実在）。

**真因:** install.sh --update が「同期だけして commit 手順を案内しない」ため、ユーザーが harness-sync と project 作業を区別せず commit する。

**副次:** taskManageSystem の `docs_approved_dir` 巻き戻り（task-55=A の対象）も未 commit drift として顕在化していた。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | install.sh --update 完了時に「harness-sync 変更を分離 commit せよ」案内 + 変更 file 一覧表示 | 0.5 | 軽量、運用主体 | honor system（強制力なし） |
| **B** | --update が harness-sync 変更を自動 stage + commit（`chore(harness): sync`） | 1.5 | 完全分離 | user の git 状態を勝手に変える（破壊的、危険） |
| **C ハイブリッド** | A（案内 + file 一覧）+ 任意 `--commit` flag で B 相当を opt-in | 1.0 | 安全 default + 自動化選択肢 | flag 実装 |

→ **C ハイブリッド** 推奨。default は案内のみ（安全）、`install.sh --update --commit` で harness-sync 変更を自動分離 commit を opt-in。

---

## 3. 採用案の詳細設計

#### Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | install.sh --update 完了時に sync 変更 file 一覧 + 分離 commit 案内を出力 | 0.4h | — |
| 2 | 🔲 | `--commit` flag 追加（opt-in で `git add <synced files>` + `chore(harness): sync` commit、project file は触らない） | 0.4h | Step 1 |
| 3 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 | 0.3h | Step 2 |
| 4 | 🔲 | (テスト合格) smoke（案内出力 / --commit で synced file のみ commit / project file 不変） | 0.3h | Step 3 |
| 5 | 🔲 | (リファクタリング) 3 観点 or skip | 0.2h | Step 4 |

合計: 約 1.6h

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| `--commit` が project file を巻き込む | L | H | `git add` は同期対象 path のみ限定、`git reset` 禁止（CLAUDE.md HIGH 教訓） |
| 案内が見落とされる（honor system） | M | L | install.sh 末尾で強調表示 |

---

## 6. 完了条件（DoD）

- [ ] --update 完了時に sync 変更 file 一覧 + 分離 commit 案内を出力
- [ ] `--commit` flag で synced file のみ commit、project file 不変（smoke 実証）
- [ ] 既存 smoke regression 0

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

- 統合分析資料: [`harness-health-7items-analysis.md`](harness-health-7items-analysis.md) §8/§9（G1）
- 関連 task: task-55=A（harness-config 保護、docs_approved_dir drift と関連）/ task-59=G2（sync workflow proactive）
