---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #107: hc-config UI nested + array 残 scope (W1-7、CLI or Web UI 選択)

> Status: **🔲 未着手 (user UX 方針 確定待ち)**
> 起案: 2026-07-08 (Grand Summary SSoT 直行方式、user 承認済)
> 関連: Grand Summary 2026-06-10 §6.7 W1-7 / task-76 / task-78 で UX 部分実現済
> 設計起源: [Grand Summary](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §6.7

## Task ゴール

Grand Summary §6.7 W1-7 の nested + array UI 残 scope を実装。task-76/78 で UX 部分実現 (flat 87 key CLI/Web UI) 済だが、`enforcement_matrix.<guard>.<field>` の nested 45 面 (9 guard × 5 field) 書込 (`_em_set` API) が未実装。task-97/104 で matrix guards が 26+ に拡張された今、nested 書込 UI が不在なため matrix 編集は yml 直接 edit 経由のみ。user UX 方針決断後着手 (Phase 2 CLI `--set-nested` or Phase 3 Web UI)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-97 | **soft**。task-97 で拡張された 26 guards の matrix 編集対象が確定 | [task-97-enforcement-matrix-full-hook-expansion.md](task-97-enforcement-matrix-full-hook-expansion.md) |
| task-104 | **soft**。task-104 で追加される 10 guard の matrix 編集も本 task の scope | [task-104-wrapper-hardcode-dissolution.md](task-104-wrapper-hardcode-dissolution.md) |

## Task 作業概要

user 選択 (Phase 2 CLI or Phase 3 Web UI) に応じて分岐:

### 案 P2 (CLI 拡張):
- `.claude/scripts/hc-config.sh --set-nested enforcement_matrix.<guard>.<field>=<value>` API 追加
- yml parser 拡張で nested 45 面書込対応
- 新規 smoke `hc-config-nested-set-smoke.sh` 5 case

### 案 P3 (Web UI 拡張):
- 既存 Web UI (task-78) に enforcement_matrix section 追加
- nested field 編集フォーム (guard select → field select → value input)
- 変更差分 preview + yml commit UI

## Task 完了条件 (DoD)

- [ ] 選択案の主要 file 存在 (CLI: `hc-config.sh --set-nested` API / Web UI: matrix section 実装)
- [ ] nested 45 面 (9 guard × 5 field = 45) or matrix 全 26+ guards × 5 field 書込動作
- [ ] 新規 smoke or E2E test PASS
- [ ] Wave 1-6 全 smoke regression 0
- [ ] docs 反映: `docs/INVENTORY.md` + Web UI 案は README + docs/PORTABILITY.md
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

enforcement_matrix.<guard>.<field> の nested 書込 UI が不在で matrix 編集が yml 直接 edit 依存な問題を解消するため CLI `--set-nested` or Web UI matrix section を拡張する。完成すれば task-97/104 で 26+ に拡張された matrix guards の設定変更が UI 経由で完結し yml 直接 edit の error prone な操作が排除される。

## Step 計画 (user 選択後確定)

user 選択待ちのため Step 具体化は着手前に更新。仮 draft:

| Step | Status | 作業概要 | 工数 |
|:---:|:---:|:---|---:|
| 1 | 🔲 | user UX 方針決断 (Phase 2 CLI or Phase 3 Web UI) | user 判断 |
| 2 | 🔲 | 選択案の主要 file 実装 (CLI 4h / Web UI 12h) | 4-12h |
| 3 | 🔲 | 新 smoke or E2E test | 3h |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h |
| 5 | 🔲 | (テスト合格) 全 smoke PASS | 1h |
| 6 | 🔲 | (リファクタリング) 3 観点判定 | 0.5h |

合計: 10-22h (case 別)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §6.7 W1-7 残 scope、task-76/78 で UX 部分実現済、docs/tasks/task-107-*.md 生成 |

## 派生 task / 次アクション候補

- [ ] (🟡) user UX 方針 (Phase 2 CLI or Phase 3 Web UI) — 着手前 user 明示判断必須

## 関連

- Grand Summary §6.7 W1-7
- 前提: task-76 (hc-config CLI) / task-78 (hc-config Web UI) 完了済
- 依存: task-97 (26 guards) / task-104 (+ 10 guards)
