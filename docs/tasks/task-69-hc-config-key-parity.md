---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma hirai (codex harness review)"
---

<!--
total_steps: 8
-->

# Task #69: hc-config config / metadata / UI key parity 修正 (Phase 1)

> Status: **🔲 未着手**
> 起案: 2026-06-01
> 関連: harness-review-remediation-plan Phase 1 (§4.1)。後続 task-70〜74 の config 基盤
> 設計起源: [harness-review-remediation-plan.md](../draft/harness-review-remediation-plan.md) ✅承認済 (approved_at 2026-06-01) §4.1

## Task ゴール

`harness-config.yml` の top-level key (79 件) と `hc-config.sh --list` / Web UI `/api/keys` / TUI の key set が完全一致し、metadata 未分類 key も全て表示される。今回欠落していた 4 key (`feature_reviewer_count_guard_enabled` / `feature_stale_harness_detect_enabled` / `harness_version` / `stale_harness_markers`) が list / TUI / Web UI で見える。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | 依存なし (Phase 1 = config 基盤、最優先) | — |

## Task 作業概要

- `hc-config.sh` の `cmd_list()` を「YAML top-level key を必ず全件出力」に修正、metadata 未掲載 key は `未分類` category として表示
- `hc-config-metadata.sh` に欠落 4 key を追加 + metadata を「key 存在判定の SSoT」から「label/category/description の表示補助」に降格
- Web server `/api/keys` を「metadata table 由来」から「YAML top-level keys 基準 + metadata/schema を left join」に修正
- `harness-config.local.yml` にだけ存在する key を `unknown_local_key` warning 表示 (誤字検出)
- `deprecated_keys` table + `hc-config --migrate` (old key 検出 → new key 移行 → ログ → 残存で smoke fail) の migration 機構
- key parity smoke 追加 (`yml_keys == --list keys == /api/keys`)

## Task 完了条件 (DoD)

- [ ] YAML 79 key と `--list` / Web API `/api/keys` の key set が完全一致 (parity smoke green)
- [ ] metadata 未整備の key が `--list` / TUI / Web UI から消えない (未分類 group 表示)
- [ ] 欠落 4 key が list / TUI / Web UI で見える (実機確認)
- [ ] local override の未知 key が warning になる
- [ ] deprecated key 残存時に migrate 案内 + smoke fail
- [ ] reviewer approve (テスト設計レビュー)
- [ ] 全 smoke regression 0 + Web UI visual 検証 (採用 6 条 4: UI 含む)
- [ ] 3 観点 refactor 判定

## Task 概要欄 (list.md 用、3 要素規範)

> config 操作の基盤を安全にするため、hc-config の key parity (YAML を唯一の key source とし metadata を表示補助に降格 + `--list` / Web UI / TUI の YAML 基準 merge + 欠落 4 key 復元 + local 未知 key warning + deprecated migrate) を直す。完成すれば top-level key と CLI / UI の key set が常に一致し、以後の設定変更で key 欠落・UI 不整合・drift が起きなくなる。

## 背景・目的

draft §3 P1「`hc-config --list` / TUI / Web UI が config key を欠落させる」+ §4.1。検証 (subagent a09e0418、confidence 0.97) で yml 79 / `--list` 75 / 欠落 4 key を実機確認済。原因は `cmd_list()` が metadata category 掲載 key のみ出力する点。metadata は表示補助であり key 存在判定の SSoT ではない (SSoT は YAML)。

## 設計

draft §4.1「config 生合成 / drift の具体修正」table + 「目標データモデル」(YAML=SSoT / metadata=表示補助 / schema=validation 補助 / UI=派生物) + local override / migration の扱いを SSoT とする。

## TDD 戦略

### RED
- parity smoke (`yml_keys == --list == /api/keys`) を先に書き、現状の 79≠75 で fail させる。local 未知 key warning / deprecated migrate の期待 case も先行。

### GREEN
- `cmd_list()` / `hc-config-metadata.sh` / Web server `/api/keys` を YAML 基準に修正 (subagent 委譲、staging 戦略)。

### REFACTOR
- key source 取得ロジックを共通 helper 化 (CLI / Web / TUI で重複しないよう DRY)。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `cmd_list()` を YAML top-level key 全件出力に修正 + 未分類 category 表示 | 0.5h | — |
| 2 | 🔲 | `hc-config-metadata.sh` 欠落 4 key 追加 + metadata を表示補助に降格 (key 存在 SSoT は YAML) | 0.5h | Step 1 |
| 3 | 🔲 | Web server `/api/keys` を YAML keys 基準 + metadata/schema left join に修正 | 0.7h | Step 2 |
| 4 | 🔲 | local override 未知 key warning + `deprecated_keys` table + `--migrate` 機構 | 0.7h | Step 2 |
| 5 | 🔲 | key parity smoke 追加 (`yml == --list == /api/keys`、unknown local key、deprecated 残存 fail) | 0.6h | Step 3,4 |
| 6 | 🔲 | (テスト設計レビュー) reviewer を `review_min_count_test`〜`review_max_count_test` 範囲で動的選定 (`hc-config.sh --get review_max_count_test` で上限確認)、parity / drift 検出網羅性を cross-check | 0.5h | Step 1-5 |
| 7 | 🔲 | (テスト合格) 全 smoke regression 0 + Web UI `/api/keys` の visual 検証 (key 一覧表示、欠落 4 key 可視、agent-browser skill screenshot) | 0.5h | Step 6 |
| 8 | 🔲 | (リファクタリング) 持続可能性 / 汎用性 / 非冗長化 — key source helper の DRY 化 | 0.3h | Step 7 |

合計: **~4.3h**

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/scripts/hc-config.sh` (`cmd_list`) + `.claude/scripts/lib/hc-config-metadata.sh` + `.claude/scripts/lib/hc-config-web-server.js` (`/api/keys`) + `.claude/tests/` (parity smoke 新規) |
| migration | `deprecated_keys` table 新設 (既存 key 削除なし、追加のみ) |
| 環境変数 | 既存不変 |
| 互換性 | `--list` 出力に未分類 4 key が増える (additive)、Web UI key 一覧が増える。BLOCK 系 enforcement は無関係 (不変) |
