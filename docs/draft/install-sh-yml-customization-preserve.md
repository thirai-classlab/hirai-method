<!--
approval_required: true
approved_at:
approved_by:
retroactive: false
-->

# install.sh `--update` で harness-config.yml customization を保護

**ステータス:** 🔲 **draft（2026-06-07 起案、user 承認待ち）**
**起点:** next-actions #47（2026-05-27 task-44 Step 4 reviewer harness-optimizer abc8bc60 confidence 0.93 発見）。task-84 (準自動 update) 完了で「consuming repo が頻繁に update する」動線が現実化し、本問題の実害が顕在化したため discharge。
**前提:**
- task-82（project-rules 保護）が rule について同型問題を解決済（RSYNC_EXCLUDES + create-if-absent）
- task-84 で `npx ... update` が推奨動線化 → update 頻度上昇で customization 消失リスク増大

**関連 fixture / rule:**
- `install.sh` の `RSYNC_EXCLUDES`（update mode）
- `.claude/harness-config.yml` / `.claude/harness-config.local.yml`（保護対象候補）

---

## 1. 真因サマリ / 課題サマリ

`install.sh --update` は `.claude/` を rsync で source から上書きする。`harness-config.yml` は RSYNC_EXCLUDES 未登録のため、consuming repo が yml で行った customization（feature toggle OFF / `review_min_count` 調整 / preset 変更等）が update で**上書き消失**する。task-84 で `npx ... update` が推奨動線化したことで update 頻度が上がり、実害が現実化する。

**真因:** harness 共通設定（source が持つ default）と project 固有 customization が同一 file（`harness-config.yml`）に同居し、update 時に分離できない。task-82 が rule で解決した「harness 所有 vs project 所有」の分離が config には未適用。

**副次:** `harness-config.local.yml`（override 用、既存概念）があるが、user が本体 yml を直接編集する運用が黙認されており、local.yml 誘導が不十分。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | `RSYNC_EXCLUDES` に `harness-config.yml` 追加（update mode 限定）+ create-if-absent（init のみ配置） | 1.0 | task-82 と同型、customization 完全保護 | source の新規 default key が既存 repo に伝播しない（key 追加時 stale 化） |
| **B** | update 後に `harness-config.yml` の source ↔ target diff を表示、手動 merge 案内 | 1.2 | 新 key 伝播を user が判断できる | 手動 merge 負担、自動保護でない |
| **C ハイブリッド** | 本体 yml は update 追従（上書き）+ `harness-config.local.yml`（RSYNC_EXCLUDES 済 = 保護）へ customization を寄せる運用を規範化 + update 時に「customization は local.yml へ」と案内 + local.yml が本体 yml を override する読み込み順を保証 | 1.5 | 新 key 伝播（本体追従）と customization 保護（local）を両立、值解決順（既存 `env > local.yml > yml > default`）と整合 | user の運用移行が必要（本体 yml 直接編集をやめる） |

→ **案 C ハイブリッド** を推奨。理由: 案 A は customization を守るが source の新 default key（本 session で追加した `feature_stale_harness_detect_enabled` 等）が既存 repo に伝播せず stale 化する（task-84 の update 動線と矛盾）。既存の値解決順（`hc-config.sh` が `env > harness-config.local.yml > harness-config.yml > default` で解決）を活かし、**本体 yml = harness 所有（update 追従）/ local.yml = project 所有（update 免除、既に RSYNC_EXCLUDES 済か要確認）** に責務分離するのが config-loader の設計と最も整合する。案 A（本体 yml も exclude）は local.yml 運用が定着するまでの過渡的 fallback として併用検討。

---

## 3. 採用案の詳細設計（案 C、要 user 承認で確定）

### Step 計画（暫定）

| Step | 作業概要 | 工数 |
|:---:|:---|---:|
| 1 | `harness-config.local.yml` が RSYNC_EXCLUDES 済か確認、未登録なら追加 + create-if-absent（空 template） | 0.3h |
| 2 | 値解決順（`local.yml > yml`）が config-loader.sh / hc-config.sh で保証されているか確認、gap あれば修正 | 0.4h |
| 3 | update 完了 summary に「customization は harness-config.local.yml へ。本体 yml は update で上書きされます」案内追加 | 0.2h |
| 4 | 規範追記（development-process.md §harness 取込 / README）: customization は local.yml、本体 yml 直接編集は非推奨 | 0.2h |
| 5 | (テスト設計レビュー) reviewer 動的選定 | 0.3h |
| 6 | (テスト合格) smoke（local.yml customization が update で保持 / 本体 yml 新 key が update で伝播 / 値解決順 local > yml） | 0.4h |
| 7 | (リファクタリング) 3 観点 or skip | 0.2h |

合計: 約 2.0h（案確定後に採用 6 条準拠で詳細化）

> 案 A（本体 yml exclude）を選ぶ場合は Step 1-2 が「RSYNC_EXCLUDES に harness-config.yml 追加 + create-if-absent」に置換。**案 A/C の最終決定は user 承認時に確定**。

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| 案 A で source 新 default key が既存 repo に伝播しない | M | M | 案 C 採用（本体 yml は追従）で回避、または update 後 diff 案内 |
| local.yml 運用移行が進まず本体 yml 直接編集が続く | M | M | update summary 案内 + 規範明記、過渡的に案 A fallback |
| 値解決順の gap（local.yml が yml を override しない実装漏れ） | L | H | Step 2 で config-loader.sh / hc-config.sh の解決順を smoke 検証 |

---

## 5-9. 移行 / DoD / 工数 / レビュー / 承認

- **DoD**: local.yml customization が update で保持（smoke）/ 本体 yml 新 key 伝播（smoke）/ 値解決順 local > yml 保証 / 規範追記 / 既存 install smoke regression 0。
- **承認履歴**: 2026-06-07 起案、user 承認待ち（案 A/C 決定含む）。

---

## 10. 関連

- next-actions #47（本 draft の起点）
- task-82 [project-rules-protection.md](project-rules-protection.md)（同型の harness/project 分離、rule 版）
- task-84 [npx-auto-update.md](npx-auto-update.md)（update 動線の推奨化で本問題が顕在化）
- `install.sh` RSYNC_EXCLUDES / `hc-config.sh` 値解決順
