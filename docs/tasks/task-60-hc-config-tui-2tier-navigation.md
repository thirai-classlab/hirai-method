---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #60: hc-config TUI 真の 2 階層 Navigation

> Status: **🔲 未着手**
> 起案: 2026-05-28
> 承認: 2026-05-29 (user、3 確認ポイントは採用案 default 採用)
> 関連: task-48 (前提 = TUI 化)
> 設計起源: [hc-config-tui-2tier-navigation.md](../draft/hc-config-tui-2tier-navigation.md)

## Task ゴール

`hc-config.sh interactive` を TTY で実行すると category 一覧 menu (6 category) が表示され、↑/↓ + Enter で category 配下 key 一覧 menu に遷移、Enter で effect_edit + cmd_set が実行され、ESC/LEFT で 1 階層 back する **真の 2 階層 navigation** が動作する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-48 | task-48 で TUI 化された `_cmd_interactive_tui` / `_tui_render` / `_tui_order_keys_by_category` を改修対象とする。本 task の修正範囲は task-48 が定義した `hc-config.sh` L1160-L1425。task-48 設計 `docs/draft/hc-config-interactive-tui.md` §3.3 の「category 一覧 → key 一覧」が iter cycle で 1 階層 flat list with category headers に妥協 closure された乖離を本 task で解消。 | [task-48-hc-config-interactive-tui.md](task-48-hc-config-interactive-tui.md) |

## Task 作業概要

- 旧 `_cmd_interactive_tui` を `_cmd_interactive_tui_flat` に rename + `HC_HC_CONFIG_FLAT_NAVIGATION=true` で旧 1 階層 fallback 維持
- `_tui_render_category_menu` 実装 (6 category 一覧 + sel ハイライト)
- `_tui_render_key_menu` 実装 (category 配下 key 一覧 + effect panel)
- `_cmd_interactive_tui` 3-state machine ループ書き換え (`category_menu` / `key_menu` / `effect_edit`、ESC/LEFT で back)
- sel 位置記憶 (scalar 7 var: `_tui_cat_sel` + `_tui_key_sel_0..5`、bash 3.2 互換 `eval` 合成)
- smoke 拡張 (unit 関数テスト方式)

## Task 完了条件 (DoD)

- `hc-config.sh interactive` を TTY で実行すると category 一覧が表示される (6 category)
- ↑/↓ で category 選択 + Enter で当該 category 配下 key 一覧に遷移
- key 一覧で ↑/↓ 選択 + Enter で effect panel 表示 + 新値入力 + cmd_set 実行
- key 一覧で ESC または LEFT で category 一覧に戻る (sel 位置保持)
- category 切替 + 再入で各 category 内の sel が記憶
- `HC_HC_CONFIG_FLAT_NAVIGATION=true` で旧 1 階層実装起動 (regression なし)
- 非 TTY (pipe) 環境では番号選択に降格 (既存 smoke Case 5 PASS)
- `hc-config-tui-smoke.sh` 全 case PASS
- bash 3.2 で矢印キー TUI 動作 (declare -g / 連想配列不使用、静的確認)
- reviewer iter 5 上限内収束 (CRIT+HIGH+MED=0)
- commit + push + PR create (feature branch、task #39 緩和で自律実行可)
- 4 リポ install 案内 (user manual)

## Task 概要欄 (list.md 用、3 要素規範)

- **何のため**: task-48 §3.3 設計乖離 (真の 2 階層 navigation 未実装、1 階層 flat list with category headers で妥協 closure) を解消するため
- **何をやる**: hc-config.sh TUI を 3-state machine (`category_menu` → `key_menu` → `effect_edit`) で書き換え、sel 位置記憶 scalar 7 var + eval (bash 3.2 互換) + 旧 flat rename 保持 + unit 関数テスト方式 smoke を追加
- **何ができる**: user が ↑↓ で 6 category → 配下 key → 編集の階層 navigation でき、74 key 横断 scroll cost が消える

## Step 計画

詳細は draft `docs/draft/hc-config-tui-2tier-navigation.md` §5 参照。

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 旧 `_cmd_interactive_tui` を `_cmd_interactive_tui_flat` に rename + flat fallback env 対応追加 | 0.2h | — |
| 2 | 🔲 | `_tui_render_category_menu` 実装 (6 category 一覧、sel ハイライト) | 0.3h | Step 1 |
| 3 | 🔲 | `_tui_render_key_menu` 実装 (category 配下 key 一覧 + effect panel) | 0.3h | Step 2 |
| 4 | 🔲 | `_cmd_interactive_tui` 3-state machine ループ書き換え (sel 位置記憶 scalar 7 var) | 0.4h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 + iter cycle 収束 | 0.5h | Step 4 |
| 6 | 🔲 | (テスト合格) smoke 拡張 + 手動 TTY 検証 + 既存 smoke regression 0 | 0.4h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 (持続可能性 / 汎用性 / 非冗長化) 判定 | 0.2h | Step 6 |

合計工数: 約 2.3h

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 修正 file | `.claude/scripts/hc-config.sh` のみ (+100-200 LOC、L1160-L1425 書き換え) |
| 新規 env | `HC_HC_CONFIG_FLAT_NAVIGATION` (`true` で旧 1 階層実装) |
| 不変 | `.claude/lib/hc-config-metadata.sh` / `harness-config.yml` / 既存 smoke のインターフェース |
| smoke 拡張 | `hc-config-tui-smoke.sh` に category navigation 確認 case 追加 (非 TTY pipe 経由 fake sequence 困難なため unit 関数テスト方式) |
| 互換性 | 既存 CLI args 不変、旧 1 階層は env で fallback 利用可、非 TTY 番号選択は現状維持 |

## 派生 task / 次アクション候補

- entry #53 (12 件 hc-config fix) は本 task と独立、後続 task として別途起案検討
- 3 階層以上 (group / sub-category) は YAGNI で defer

## 関連

- 設計起源: [hc-config-tui-2tier-navigation.md](../draft/hc-config-tui-2tier-navigation.md)
- 前提 task: [task-48-hc-config-interactive-tui.md](task-48-hc-config-interactive-tui.md)
- 修正先: `.claude/scripts/hc-config.sh` L1160-L1425
- metadata: `.claude/lib/hc-config-metadata.sh`
- smoke: `.claude/tests/hc-config-tui-smoke.sh`

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-28 | 起案 | draft 起こし (subagent af15ad395360120b8 conf 0.92、246 行、Step 7 件) |
| 2026-05-29 | 承認 | user 承認、3 確認ポイント default 採用 (sel = eval scalar 7 var / 旧 flat = rename 保持 + env fallback / smoke = unit 関数テスト方式) |
| 2026-05-29 | task 化 | task-60 file 生成 + list.md row 60 append |
