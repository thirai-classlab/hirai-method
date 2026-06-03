---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #79: install.sh 全上書きモード追加

> Status: **🔄 進行中** (2026-06-04 draft 承認、実装着手)
> 起案: 2026-06-04
> 設計起源: [install-full-overwrite-mode](../draft/install-full-overwrite-mode.md) ✅承認済 (approved_at 2026-06-04)

## Task ゴール

`install.sh` に新 mode flag `--overwrite-all` を追加し、target の `.claude/` を source で上書きする (削除なし)。exclude は `settings.local.json` のみ (settings.json / harness-config.local.yml / state dir も上書き)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | install.sh の既存 mode (install/update/force) と RSYNC_EXCLUDES を拡張するが依存 task なし | — |

## Task 作業概要

- 新 mode flag `--overwrite-all` (AI 推奨名、別案 `--full`) を arg parse + M-1 conflict 検出に統合
- 専用 `RSYNC_EXCLUDES_MINIMAL=(--exclude=settings.local.json)` で rsync (`--delete` なし)
- dirty-tree warn 流用、CLAUDE.md/.mcp.json は `--force` 準拠で扱い確定
- `--dry-run` 対応 + help/usage/冒頭コメント/summary 整合
- smoke 新規 (settings.local.json のみ温存 / 他上書き / target 独自 file 残存 / dry-run / conflict)

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: `--overwrite-all` で settings.local.json のみ温存・他上書き (smoke 実測) / `--delete` 不使用で target 独自 file 残存 / dry-run プレビュー / mode 排他 error / help・summary 整合 / 既存 install·update·force smoke regression 0 / bash 3.2 互換。

## Task 概要欄 (list.md 用、3 要素規範)

drift した target を source 状態へ強制リセットするため、settings.local.json 以外を全上書きする `--overwrite-all` モードを install.sh に追加する。完成すれば machine-local 設定だけ残して harness を source 完全一致に戻せ、既存 install/update/force を壊さず、誤用防止のため help に用途と差分を明示できる。

## 設計

draft [install-full-overwrite-mode](../draft/install-full-overwrite-mode.md) §3 を SSoT (採用案 A、上書きのみ、exclude settings.local.json のみ)。

## Step 計画

draft §「Step 計画」を SSoT。

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | `--overwrite-all` mode 追加 (arg parse + M-1 conflict + RSYNC_EXCLUDES_MINIMAL + MODE 分岐 + CLAUDE.md/.mcp.json 扱い確定) | — |
| 2 | 🔲 | dry-run 対応 + help/usage/冒頭コメント/summary 更新 | 1 |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (min≤N≤max) | 2 |
| 4 | 🔲 | (テスト合格) smoke 新規 + 既存 regression 0 | 3 |
| 5 | 🔲 | (リファクタリング) RSYNC_EXCLUDES 重複判定 or skip | 4 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `install.sh` (mode flag + exclude + rsync 分岐 + help), smoke (新規 or 既存拡張) |
| migration | なし |
| 互換性 | 既存 install/update/force 非破壊 (新 flag 追加のみ) |

## 再発防止

- 「local override も上書き」は仕様 → help/summary に明記し誤用防止
- mode 3 者排他を M-1 conflict 検出に統合

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-04 | 起案+承認+着手 | user「全上書きモード追加」依頼、仕様確定 (上書きのみ)、draft 承認、実装着手 |

## 関連
- Draft: [install-full-overwrite-mode](../draft/install-full-overwrite-mode.md)
- next-actions.md #75 / 4 リポ install #74
