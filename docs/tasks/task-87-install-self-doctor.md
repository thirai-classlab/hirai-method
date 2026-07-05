---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #87: install.sh 末尾 self-doctor (install 直後の setup issue 0 化検証、P1-3)

> Status: **✅ 完了** (2026-07-05、commit `a7c0287`、DoD 全項目実測 PASS、**Phase 1 完遂**)
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.5 (R5)/§5 P1-3
> 設計起源: [install-self-doctor.md](../draft/install-self-doctor.md)

## Task ゴール

install 直後および consuming repo での随時再実行で、期待外 setup issue のみを 3 点提示 format (why / fix 1 行 / silence) で検出・報告する self-doctor が動作し、dummy repo 新規 install 直後に WARN 0 が成立する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-85 | D1 (local.yml 生成済 check) / D6 (guard effective state) の期待値が preset 別生成に追随する必要 (draft は内容非依存 + --summary 委譲で自動追随設計、smoke Case I の advisory 同型 case は #85 Step 2 merge 後に追加) | [task-85-install-preset-auto-switch.md](task-85-install-preset-auto-switch.md) |
| task-86 | D6 が委譲する `hc-config.sh --summary` の表示一貫性 (local override 可視化) が前提 | [task-86-hc-config-local-yml-integration.md](task-86-hc-config-local-yml-integration.md) |

## Task 作業概要

- `.claude/scripts/self-doctor.sh` 新設 (D1-D8 の 8 check、WARN/INFO 2 段分類、判定は generate-settings.sh --check / hc-config.sh --summary へ委譲)
- install.sh §7.5 から fail-open 呼出 (`--no-doctor` flag + dry-run skip) + summary 案内
- feature toggle 3 点 set (`feature_self_doctor_enabled` + consumer + smoke) + 新規 smoke 10 case

## Task 完了条件 (DoD)

- [ ] dummy repo 新規 install 直後に `self-doctor.sh` が `WARN 0` + exit 0 (D2 は settings.json 非配布のため INFO 側)
- [ ] local.yml 削除後の再実行が `WARN D1` + exit 1 (期待外 issue 検出能力)
- [ ] manifest 乖離 settings.json (`{"hooks":{}}`) 配置で `WARN D2` + exit 1 (Case J)
- [ ] harness-dev local.yml 置換で D6 WARN なし (Case I、preset-aware)
- [ ] self-doctor WARN 検出時も `install.sh --update` は exit 0 (install fail-open)
- [ ] 新規 smoke `self-doctor-smoke.sh` 10/10 PASS + 既存 install 系 smoke regression 0
- [ ] 全 WARN 種で `why:` / `fix:` / `silence:` 3 行存在 (3 点提示 format)
- [ ] `HC_FEATURE_SELF_DOCTOR_ENABLED=false` で出力なし + exit 0 (toggle no-op)

## Task 概要欄 (list.md 用)

install 直後の /doctor 8 setup issues (R5) による AI の「ハーネス側問題」誤認識を解消するため、`.claude/scripts/self-doctor.sh` (D1-D8 check + WARN/INFO 2 段 + 3 点提示 format) を新設し install.sh 末尾から fail-open 呼出する。完成すれば install 直後の期待外 issue が 0 件検証され、consuming repo で随時再実行できる健全性 check が配布される。

## Step 計画 (SSoT: draft §3.6 「Task 計画」)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | `.claude/scripts/self-doctor.sh` 新設 (D1-D8 check + WARN/INFO 分類 + 3 点提示 format + exit code 2 層 fail-open) | 0.4d | — |
| 2 | ✅ | install.sh §7.5 呼出統合 (`--no-doctor` + fail-open + dry-run skip) + §8 summary 案内 | 0.2d | Step 1 |
| 3 | ✅ | feature toggle 3 点 set + 新規 smoke `self-doctor-smoke.sh` 10 case (A-J、詳細は draft §3.6 Step 3) | 0.5d | Step 2 |
| 4 | ✅ | (テスト設計レビュー) reviewer 動的選定、収束まで反復 (上限 `review_iteration_max`) | 0.3d | Step 3 |
| 5 | ✅ | (テスト合格) 新 smoke 10/10 + 既存 install 系 smoke regression 0 (UI 無し task のため E2E/visual 対象外) | 0.2d | Step 4 |
| 6 | ✅ | (リファクタリング) 3 観点 (特に D2/D6 の既存 script 委譲徹底で判定 logic 重複 0)、不要なら `skip: <reason>` | 0.1d | Step 5 |

合計: 1.7 day (roadmap 公称 0.5 day はテスト 3 段を含まない粗見積。Phase 1 クリティカルパス #85 0.75d → #87 1.7d ≈ 2.5d、fallback: smoke 10 → 最小 5 case 縮退可)

> **注意**: install.sh 同域編集の序列化対象 (#85 → #89 → #90 → #87 推奨、2026-07-05 横断レビュー M6)。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、HIGH 2 件 [D6 advisory 衝突 / D2 settings.json 前提] 修正済) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: built-in /doctor 照合は proxy + 手動 / SessionStart 配線見送り / D7 INFO 固定)、list.md 🔲 化 |
| 2026-07-05 | Step 1-3 完了 | Workflow wf_e9b7e2b0-8de、self-doctor.sh +490 行 (D1-D8 + PROJECT_ROOT 解決 + preset-aware D6 + fail-open) / install.sh §7.5 統合 (`--no-doctor` + fail-open 2 層) / feature toggle 3 点 set + smoke 10→12 case |
| 2026-07-05 | Step 4-5 完了 | 3 lens review + Fix iter 1 で HIGH 4 件 (Case G fake test / cascade isolation / D6 一次判定 coverage / install fail-open DoD runtime) + CRITICAL 1 件 (HC_ALLOW_EXTERNAL_CONFIG 修正案 a 適用) 全収束、smoke 12/12 PASS + Wave 1-3 regression 0 |
| 2026-07-05 | Step 6 完了 | refactor `skip: draft §3 (D1-D8 定義 + 3 点提示 format + 2 層 fail-open) 準拠、既存 script (hc-config.sh --summary / generate-settings.sh --check) 委譲徹底で判定 logic 重複 0、review 3 lens で非冗長化確認済` |
| 2026-07-05 | 完了 | commit `a7c0287`、**Phase 1 (P1-1〜P1-7) 完遂達成** |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [install-self-doctor.md](../draft/install-self-doctor.md)
- 依存: #85 / #86。関連: #90 (D5/D7 の .mcp.json 走査契約は #90 draft が定義、実装は本 task)
