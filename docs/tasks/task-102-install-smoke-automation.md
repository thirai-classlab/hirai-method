---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #102: install smoke 自動化 (tmp dir 実 install + 検証) (P3-5/I3/W2-3)

> Status: **🔲 未着手**
> 起案: 2026-07-07 (master roadmap SSoT 直行方式、user 承認済)
> 関連: Phase 3 (#98-#103)、master roadmap install-immediately-usable-redesign-20260618 §3 I3 / §5 P3-5 / §11.3 R4 (副産物 #78/#80-#83 吸収 hub)
> 設計起源: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I3 + §5 P3-5

## Task ゴール

`.claude/tests/install-full-smoke.sh` 新設。tmp dir で `install.sh` を実 install し、yml key 完全性 (matrix 全 guard 存在) + hook permission 755 + lib source 健全性 (bash -n on new libs) + preset effective (hc-config.sh --summary で strict/team-default/harness-dev/advisory 3 preset の値差検出) + 副産物 #78/#80/#82/#83 の吸収検証 (settings seed / install-local-yml case I/J false-pass / autofill `{{TOKEN}}` literal 残存 / autofill Case G/N flakiness) を assert。完成すれば install.sh の変更が regression test で守られ、portability が構造保証される。副産物 4 件を本 task で吸収 (§11.3 R4)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-85 | **hard**。task-85 で追加された `--preset` opt-in 3 preset 動作を tmp dir で assert | (list.md #85 参照、PR #68 merge 済) |
| task-92 | **hard**。task-92 で配布された pre-commit template + `--no-hooks` の tmp install 挙動 assert | [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md) |
| task-97 | **soft**。task-97 で追加された 12 guards の tmp install 直後 matrix 完全性検証 | [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) |

## Task 作業概要

- `.claude/tests/install-full-smoke.sh` 新設 (`mktemp -d` + `bash install.sh --dest <tmp> --install --preset harness-dev` + 全項目 assert)
- 副産物 #78 (settings.json seed 動作) + #80 (install-local-yml case I/J assert 追加) + #82 (autofill `{{TOKEN}}` literal 残存 assert) + #83 (autofill Case G/N flakiness、既に task-93 で吸収済確認) を本 smoke に統合
- yml key 完全性: `grep -c 'enforcement_matrix:' <tmp>/.claude/harness-config.yml` + `bash <tmp>/.claude/scripts/hc-config.sh --summary` で 25 guards 検出
- hook permission: `find <tmp>/.claude/hooks -name '*.sh' -not -perm 0755` は 0 件
- lib source: `bash -n <tmp>/.claude/hooks/lib/*.sh` は全 exit 0
- preset effective: 3 preset で `hc-config.sh --summary` 値差検出 (feature toggle enable count が異なる)
- `run-all-smokes.sh` `_get_smoke_category()` に本 smoke を **portability** 登録
- next-actions #78/#80/#82/#83 処理結果列を `✅ → task-102` に更新

## Task 完了条件 (DoD)

- [ ] `install-full-smoke.sh` 新設 + `run-all-smokes.sh --list` の portability カテゴリで discover
- [ ] 5+ case 全 PASS (fresh install / update / preset 切替 / --no-hooks / 副産物吸収)
- [ ] tmp dir で `bash install.sh --dest <tmp> --install --auto-confirm` 全 mode 通過
- [ ] yml key 完全性: 25 guards (base 8 + task-95 3 + task-97 12 + Wave 4 追加) 全 detected
- [ ] hook 755 検証 + lib syntax 検証 PASS
- [ ] preset 3 種 (strict / team-default / harness-dev) で hc-config.sh --summary 値差 assert
- [ ] 副産物 #78/#80/#82/#83 の processing 列を `✅ → task-102` に更新
- [ ] Wave 1-4 全 smoke regression 0
- [ ] docs 反映: `.claude/rules/development-process.md` + `docs/INVENTORY.md` + `docs/PORTABILITY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

consuming repo の install 健全性が手動検証依存の問題を解消するため tmp dir で実 install し yml key 完全性 + hook permission 755 + lib source 健全性 + preset effective を assert する install smoke を自動化する。完成すれば install.sh の変更が regression test で守られ portability が構造保証される。副産物 #78/#80/#82/#83 も本 task で吸収。

## Step 計画 (SSoT: master roadmap §5 P3-5 + §3 I3 + §11.3 R4)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `install-full-smoke.sh` scaffold (tmp dir setup + install.sh 実行 + cleanup) | 4h | — |
| 2 | 🔲 | yml key + hook permission + lib source + preset effective assert 実装 (5 case A-E) | 6h | Step 1 |
| 3 | 🔲 | 副産物 #78/#80/#82/#83 の吸収 assert 統合 (4 case F/G/H/I) | 4h | Step 2 |
| 4 | 🔲 | `run-all-smokes.sh` に portability 登録 + next-actions.md 4 entry 更新 | 1h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h | Step 4 |
| 6 | 🔲 | (テスト合格) 全 smoke PASS + install 実行時間 < 60s | 1.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点判定 or skip | 0.5h | Step 6 |

合計: 18.5h ≒ 2.3 day (roadmap 2 day 見積内、副産物 4 件吸収含む)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-07 | 起案 + タスク化 | master roadmap SSoT 直行方式、user 承認済、docs/tasks/task-102-*.md 生成、list.md #102 📝 → 🔲 update、副産物 #78/#80/#82/#83 吸収 hub |
| 2026-07-08 | 完了 | Wave 5 Workflow wf_070a6dcf-dc2 経由。install-full-smoke.sh 新設 (9 case、17.5KB、wall-clock 50.7s target <60s 内)。Core 5 case A-E (fresh install / matrix 24+ guards / hook 755 / lib syntax / preset effective 差) + 副産物吸収 4 case F-I (#78 settings.json seed / #80 --preset=advisory 保存 / #82 autofill {{TOKEN}} literal 0 / #83 flakiness 3 連 md5 一致)。Step 1-7 全 ✅ |

## 派生 task / 次アクション候補

- [ ] (🟢) install 実行時間 > 60s 検出時の smoke 分割 — Step 6 実測後判定
- [ ] (🟢) preset 3 種の tmp install 全 mode 網羅 (fresh / update / force / overwrite-all の 4×3=12 パターン) — Step 3 で判定

## 関連

- Master roadmap: [install-immediately-usable-redesign-20260618.md](../draft/install-immediately-usable-redesign-20260618.md) §3 I3 + §5 P3-5 + §11.3 R4
- 起源 memory: [[feedback_ui_rewrite_stale_smoke_regression]] (install regression detection)
- 依存 task (hard): task-85 (--preset opt-in) / [task-92-install-pre-commit-distribute.md](task-92-install-pre-commit-distribute.md)
- 依存 task (soft): [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) (matrix 25 guards 完全性)
- 吸収 副産物: next-actions #78 (WIP stash 正規化 (2) statusline は別 task 残) / #80 (install-local-yml case I/J) / #82 (autofill `{{TOKEN}}` literal 残存) / #83 (autofill flakiness、task-93 で先行吸収済)
