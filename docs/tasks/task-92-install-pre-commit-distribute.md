---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #92: install.sh pre-commit 配布 + core.hooksPath 自動設定 + settings seed 吸収 (P2-1/I3/W1-9)

> Status: **🔲 未着手**
> 起案: 2026-07-06 / 承認: 2026-07-06 (AI 推奨どおり fast smoke 4 本採用、副産物 #78 sub-item 1 吸収承認)
> 関連: Phase 2 (#92-#97)、master roadmap install-immediately-usable-redesign-20260618 §5 P2-1 / §4.7 / §11.3 R2 / §11.3 R4
> 設計起源: [install-pre-commit-distribute.md](../draft/install-pre-commit-distribute.md)

## Task ゴール

`bash install.sh <target>` 直後に `<target>/.githooks/pre-commit` (mode 755) が配置され `core.hooksPath .githooks` が idempotent 設定される。全 commit で fast smoke curated set 4 本 (< 3s 目安) が実行され、FAIL で BLOCK / 未整備で fail-open WARN。既存 `.githooks/` は保護、`--no-hooks` で opt-out 可。副産物 next-actions #78 sub-item 1 (install.sh §6.3 settings seed source copy) を §6.3 structural change で吸収。

## Task 依存先タスク

— (依存なし、task-85 = P1-1 は完了済)

Phase 1 資産 (self-doctor / auto-fill / mcp minimal / preset switch) は完了済で本 task は独立着手可。task-94 (P2-3) が本 task を **hard 依存**として明記済 (pre-commit の暫定 `_pc_emit_*` helper を task-94 の lib/block-message.sh へ 1:1 migration)。

## Task 作業概要

- `.claude/templates/githooks/pre-commit` 新設 (fast smoke curated set + fail-open 2 層 + `_pc_emit_*` 3 点提示 helper + feature toggle check)
- install.sh §6.8 新設で pre-commit 配布 + `core.hooksPath` idempotent 設定 + `--no-hooks` arg + summary 更新
- install.sh §6.3 settings.json 不在時の source seed copy (副産物 #78 sub-item 1 吸収、install mode 分岐 structural change)
- harness-config.yml に `feature_pre_commit_smoke_enabled: true` + `pre_commit_smoke_budget_sec: 3` 追加 + metadata TSV 登録 (I7 triplet)
- 新規 smoke `.claude/tests/install-pre-commit-smoke.sh` (7 case) + `install-local-yml-smoke.sh` に Case K/L 追加 (install mode + settings.json 有無 contract 検証)

## Task 完了条件 (DoD)

- [ ] `bash install.sh <tmp> --no-mcp --no-docs` 直後に `<tmp>/.githooks/pre-commit` が mode 755 で存在
- [ ] fresh install 後 `<tmp>` の `git commit -m x` で pre-commit が起動し fast smoke 4 本を実行 (経過時間 < 3s)
- [ ] `.githooks/pre-commit` 既存の consuming repo で `bash install.sh --update <repo>` が上書きせず WARN 出力
- [ ] `bash install.sh <tmp> --no-hooks` で `.githooks/` 未配置 + `core.hooksPath` 未設定
- [ ] `bash install.sh <tmp> --dry-run` で file / git config が 0 件変更
- [ ] `HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false git commit` で pre-commit が silent pass
- [ ] install-local-yml-smoke Case K PASS (install mode + settings.json 不在で source seed copy) + Case L PASS (update mode + 既存不在で NOTE 維持、task-71 H2 regression 0)
- [ ] 新規 smoke `install-pre-commit-smoke.sh` 7 case 全 PASS + 既存 smoke regression 0 (`install-local-yml-smoke.sh` / `install-sh-sync-drift-smoke.sh` / `enforcement-mismatch-smoke.sh` / `hc-config-key-parity-smoke.sh`)
- [ ] docs 反映 (README.md / docs/INVENTORY.md / docs/PORTABILITY.md 各 grep `pre-commit` ≥ 1 + install.sh header に `--no-hooks` doc)
- [ ] next-actions #78 処理結果列が「🔄 部分処理: sub-item 1 → task-92 完了 / sub-item 2 (statusline) は独立小タスク化待ち」に更新 (R4 verification 契約)
- [ ] pre-commit 内 `_pc_emit_*` 3 helper の 4 引数 signature が task-94 draft §3.1 契約と一致 (`sed 's/_pc_emit_/emit_/g'` で 1:1 migration 可能)
- [ ] curated set drift 検出 case (pre-commit hardcode の 4 smoke path 実 file 存在) 追加
- [ ] commit 完了 (push は user manual、Loop モード自律実行禁止)

## Task 概要欄 (list.md 用、3 要素規範)

I3 Quality Gate (roadmap §3 invariant) の commit 境界機械強制不在を解消するため、`install.sh` に `.githooks/pre-commit` 配布 + `core.hooksPath` idempotent 設定 + `--no-hooks` opt-out + settings seed §6.3 structural change 吸収を追加する。完成すれば consuming repo が install 直後から全 commit で fast smoke curated set 4 本 (< 3s) を通過し、commit 境界の quality gate が honor system から機械強制に昇格するようになる。

## Step 計画 (SSoT: draft §3 「Step 計画」+ 各 Step 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `.claude/templates/githooks/pre-commit` 新設 (fast smoke curated set + fail-open 2 層 + `_pc_emit_*` 3 点提示 helper + feature toggle check) | 2.0h | — |
| 2 | 🔲 | install.sh §6.8 新設 (pre-commit 配布 + `core.hooksPath` idempotent + `--no-hooks` arg + summary Next steps 更新) | 2.0h | Step 1 |
| 3 | 🔲 | install.sh §6.3 settings.json 不在時 source seed copy 吸収 (#78 sub-item 1、install mode 分岐 structural change) | 1.0h | Step 2 |
| 4 | 🔲 | harness-config.yml: `feature_pre_commit_smoke_enabled: true` + `pre_commit_smoke_budget_sec: 3` 追加 + metadata TSV 登録 (I7 triplet) | 0.5h | Step 1 |
| 5 | 🔲 | 新規 smoke `install-pre-commit-smoke.sh` (7 case) + 既存 `install-local-yml-smoke.sh` に Case K/L 追加 (install mode + settings.json 有無 contract) | 2.0h | Step 2, 3, 4 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 `min ≤ N ≤ max` (`hc-config.sh --get review_max_count_test` で上限確認) | 0.5h | Step 5 |
| 7 | 🔲 | (テスト合格) 新旧 smoke 全 PASS + docs 反映 (README / docs/INVENTORY / docs/PORTABILITY / install.sh header) | 0.7h | Step 6 |
| 8 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.3h | Step 7 |

合計: 9.0h (≒ 1.1 day、roadmap P2-1 見積 1 day + R4 副産物吸収 0.1 day)

**注意 (install.sh 同域編集の順序整合)**: task-93 (§5.6) と本 task (§6.3 / §6.8) は install.sh の異なる section を編集するが、arg parse (L65-171) + summary heredoc は共通。着手順は #92 → #93 で序列化し、並列 subagent での install.sh 同時編集は禁止 (Phase 1 の #85/#89/#90 横断レビュー M6 と同型)。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-06 | 起案 | Phase 2 batch planning 経路 B、docs/draft/install-pre-commit-distribute.md 起こし |
| 2026-07-06 | 承認 | user 承認 (AI 推奨どおり fast smoke curated set 4 本採用 / 副産物 #78 sub-item 1 吸収承認 / statusline 行 2 表示は独立小タスク化) |
| 2026-07-06 | タスク化 | `/new-task 92 install-pre-commit-distribute`、list.md #92 📝 → 🔲 update、docs/tasks/task-92-*.md 生成 |

## 派生 task / 次アクション候補

Task 実装中・レビュー中・完了時に発見した副産物は本セクション + `docs/tasks/next-actions.md` に即時記入 (development-process.md §「副産物発生時の即時 draft 起こし義務」)。

Draft §未決事項からの初期 candidate:

- [ ] (🟢) run-all-smokes.sh に `fast/full` 軸追加 (curated set drift 検出 case 由来、P3-5 fold 候補) — 起案時に `docs/tasks/next-actions.md` へ append
- [ ] (🟢) statusline 行 2 の repo/dir 名表示 (#78 sub-item 2、R4 「独立小タスク化」) — 本 task 完遂時に user 提示 + `docs/tasks/next-actions.md` の #78 処理結果列を更新

## 関連

- Draft: [install-pre-commit-distribute.md](../draft/install-pre-commit-distribute.md)
- 前提 (Phase 1 資産、完了済): PR #68 (task-85) / PR #73 (task-87 self-doctor) / PR #72 (task-89 auto-fill / task-90 mcp minimal)
- 後続 (Phase 2 依存):
  - task-93 (P2-2 CI matrix、本 task **hard 依存**)
  - task-94 (P2-3 BLOCK 4 引数 lib、本 task **hard 依存** — pre-commit 暫定 helper を lib へ 1:1 migration)
- 副産物: [next-actions #78 sub-item 1 (settings seed)](next-actions.md) を本 task で吸収、sub-item 2 (statusline) は独立小タスク化 (R4 契約)
