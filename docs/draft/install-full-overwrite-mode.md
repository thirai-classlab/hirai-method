<!--
approval_required: true
approved_at: 2026-06-04
approved_by: user
retroactive: false
-->

# install.sh 全上書きモード追加 (settings.local.json 以外を上書き)

**ステータス:** 🔲 **draft（2026-06-04 起案、user 承認待ち）**
**起点:** user 依頼 (2026-06-04)「全上書きするモードを sh に追加 (settings.local.json 以外、今回は使わない)」
**前提:**
- 既存 install.sh の 3 mode (install / `--update` / `--force`) と RSYNC_EXCLUDES 機構 (install.sh L195-209)

**関連 rule:**
- `.claude/rules/development-process.md` §「harness 取込チェックリスト」

---

## 1. 課題サマリ

現行の install.sh には「target の `.claude/` を source とほぼ一致させたい (local 機械固有設定のみ残す)」mode が無い。

- `install` (default): 既存 `.claude` を `.bak` 退避して新規配置。CLAUDE.md は template 化
- `--update`: 増分上書き。**多数を exclude で温存** (state dir 8 種 / settings.json / settings.local.json / harness-config.local.yml / bash-whitelist-requests / worktrees)
- `--force`: backup せず上書き。ただし exclude は `--update` と同一 (state / local 温存)

→ いずれも `settings.json` / `harness-config.local.yml` / state dir を温存するため、「drift した target を source の状態へ強制リセット (machine-local の `settings.local.json` だけ残す)」用途を満たせない。

**真因:** RSYNC_EXCLUDES が全 mode 共通で、exclude を「settings.local.json のみ」に絞る経路が存在しない。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 新 mode flag `--overwrite-all` を追加。exclude は `settings.local.json` のみ、`--delete` 無し (上書きのみ) | 0.8 | 既存 mode 非破壊、用途明確 | flag 1 個追加 |
| **B** | `--force` に `--minimal-exclude` 補助 flag を組合せ | 1.0 | flag 直交 | 組合せ爆発・help 複雑化 |

→ **案 A** を推奨。user 指定の「上書きのみ (削除なし)」= rsync `--delete` を**使わない**。target 独自 file は残す。

---

## 3. 採用案の詳細設計

### 確定仕様 (user 2026-06-04)
- **挙動**: 上書きのみ (`--delete` 無し)。source の全 file で target を上書き、target にしかない file は残す
- **exclude**: `settings.local.json` のみ (state dir / settings.json / harness-config.local.yml も**上書きする**)
- **flag 名 (提案)**: `--overwrite-all` (AI 推奨、別案 `--full` / `--mirror-soft`)
- CLAUDE.md / .mcp.json / .gitignore の扱い: 既存 mode の慣習を踏襲 (本 mode では `--force` 同等 = CLAUDE.md は placeholder 上書きせず… は要確定 → 下記 Step 1 で決定)

### Step 計画 (採用 6 条準拠)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `--overwrite-all` mode 追加: arg parse (M-1 conflict 検出に追加) + 専用 `RSYNC_EXCLUDES_MINIMAL=(--exclude=settings.local.json)` + MODE 分岐で rsync 呼出 + dirty-tree warn 流用。CLAUDE.md/.mcp.json 扱いを `--force` 準拠で確定 | 0.4h | — |
| 2 | 🔲 | `--dry-run` 対応 + help/usage 更新 + 冒頭コメント (mode 一覧) 追記 + summary「Next steps」整合 | 0.2h | 1 |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (min≤N≤max、`hc-config.sh --get review_max_count_test` 確認) | 0.3h | 2 |
| 4 | 🔲 | (テスト合格) smoke 新規: settings.local.json のみ温存 / 他 file 上書き / `--delete` 不使用 (target 独自 file 残存) / dry-run / conflict flag。bash 3.2 互換 | 0.3h | 3 |
| 5 | 🔲 | (リファクタリング) RSYNC_EXCLUDES 系の重複判定、不要なら skip | 0.1h | 4 |

合計: 約 1.3h

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| harness-config.local.yml / settings.json を上書きし target の local 設定が消える | H | M | **これは仕様** (全上書きの意図)。help / summary に「local override も上書きされる、`settings.local.json` のみ残る」を明記。dirty-tree warn で事前停止可 |
| `--overwrite-all` を `--update` 感覚で誤用し state/設定喪失 | M | M | help に用途 (drift リセット専用) と他 mode との差分表を明記 |
| flag 名衝突 / 既存 conflict 検出 (M-1) との不整合 | L | M | Step 1 で `--update`/`--force`/`--overwrite-all` 3 者排他を M-1 ロジックに統合 |

---

## 6. 完了条件（DoD）

- [ ] `--overwrite-all` で target `.claude/` が source で上書きされ `settings.local.json` のみ温存 (smoke 実測)
- [ ] `--delete` 不使用 = target 独自 file が残る (smoke 実測)
- [ ] `--dry-run --overwrite-all` で実行内容プレビュー
- [ ] mode 排他 (`--update`/`--force`/`--overwrite-all` 同時指定で error)
- [ ] help / usage / 冒頭コメント / summary 整合
- [ ] 既存 install/update/force smoke regression 0
- [ ] bash 3.2 互換

---

## 7. 工数見積

約 1.3h (Step 1 0.4 + Step 2 0.2 + Step 3 0.3 + Step 4 0.3 + Step 5 0.1)

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | (Task 最終 Step のテスト設計レビューで実施) | — | — | — | — | — | 未着手 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-06-04 | (待ち) | 仕様 4 点 user 確定済 (上書きのみ / exclude settings.local.json のみ)、draft 承認待ち |
| 2026-06-04 | user | **承認** (「両方承認」) → task-79 化 |

---

## 10. 関連

- `install.sh` L195-265 (RSYNC_EXCLUDES + MODE 分岐)
- next-actions.md #75
- 関連タスク: 4 リポ install (#74)
