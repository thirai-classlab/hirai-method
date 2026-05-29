---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #61: hc-config Web UI + Preset 一括変更機能

> Status: **🔲 未着手**
> 起案: 2026-05-29
> 承認: 2026-05-29 (user、4 確認ポイント全 AI 推奨採用)
> 関連: task-60 (TUI legacy 維持) / task-48 (hc-config TUI 化) / task-46 (hc-config.sh 新設)
> 設計起源: [hc-config-web-ui.md](../draft/hc-config-web-ui.md)

## Task ゴール

`hc-config.sh interactive` 起動で Node.js HTTP server (port 3060-3070 自動 detect) が立ち上がり、browser に Tailwind CDN + 素 JS で構築された 4 領域 UI (preset selector / category list / key list / edit + diff panel) が表示され、**10 named preset** から「品質レベル × 言語/FW × Git/push 制御 × TDD × reviewer × autonomy」軸の一括変更 (diff preview + checkbox toggle + batch cmd_set + history rollback) ができる。env `HC_HC_CONFIG_TUI_LEGACY=true` で task-60 TUI fallback 可。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-60 | task-60 で完遂した TUI 実装 (`_cmd_interactive_tui` / `_cmd_interactive_tui_2tier` / `_cmd_interactive_tui_flat`) を本 task で **legacy fallback** として保持。`HC_HC_CONFIG_TUI_LEGACY=true` 時のみ起動、default は Web UI 起動。task-60 commits (`761c1cd`/`7de5b9d`/`21fe83f`/`e34e3a8`/`e65c98d`/`93edfef`/`3249ae7`) の挙動は不変。 | [task-60-hc-config-tui-2tier-navigation.md](task-60-hc-config-tui-2tier-navigation.md) |
| task-48 | task-48 で実装した `hc-config.sh` の `cmd_set` / `cmd_get` / `cmd_list` / metadata lib API を本 Web UI から bash subprocess 経由で呼出。API 不変。 | [task-48-hc-config-interactive-tui.md](task-48-hc-config-interactive-tui.md) |
| task-46 | task-46 で新設した `hc-config.sh` script 本体 (wrapper 修正対象、`_cmd_interactive_web` 新規追加 + env switch dispatcher 拡張) | [task-46-config-yml-phase3-hc-config-script.md](task-46-config-yml-phase3-hc-config-script.md) |

## Task 作業概要

- `hc-config.sh` wrapper 修正 (legacy env switch + node 起動 dispatcher、~40 LOC)
- `.claude/scripts/lib/hc-config-web-server.js` 新規 (Node.js `http` module + API 7+ endpoint + bash subprocess for cmd_set、~400 LOC)
- `.claude/scripts/lib/hc-config-web-ui/{index.html,app.js,style.css}` (Tailwind CDN + 素 JS、4 領域 layout、~550 LOC)
- `.claude/presets/*.yml` 10 named preset 定義 (`poc-no-git` / `poc-with-git` / `inner-typescript` / `inner-python` / `production-typescript-personal` / `production-typescript-enterprise` / `production-python` / `production-rust` / `production-go` / `harness-development`、各 ~30 LOC)
- preset 適用ロジック (server.js 内 batch cmd_set + `.preset-history/` rollback)
- 6 軸 hardcode definition (server.js 内 const、yml 外部化は YAGNI 判断)
- `install.sh` で Node.js install check + 未 install で WARN + legacy TUI fallback 案内

## Task 完了条件 (DoD)

- `hc-config.sh interactive` を TTY で実行すると Node.js server 起動 + browser auto-open + 4 領域 UI 表示
- 10 named preset 全て selector に表示、選択 → Diff Preview (current/new/effect 3 列) → checkbox toggle → Apply → batch cmd_set 実行
- 6 軸 (`quality_level` / `language_framework` / `git_workflow` / `tdd_policy` / `review_intensity` / `autonomy_level`) 全て preset で正しく適用される
- `.claude/.preset-history/<timestamp>-<preset_name>.json` 記録 + Web UI から rollback 動作
- 個別 key 編集 (preset 適用後 + 任意時) も動作 (既存 cmd_set 経路)
- `HC_HC_CONFIG_TUI_LEGACY=true` で task-60 TUI (2tier or flat) 起動 (regression なし、smoke 21/21 + 14/14 維持)
- 非 TTY (pipe / CI) で Web UI 起動 skip、`_cmd_interactive_numeric` 降格 (task-46 既存)
- Node.js standard module のみ依存 (`http` / `child_process` / `fs` / `path` / `os`)、npm dep 0
- Tailwind CDN online で UI 完全動作 (CDN 不在で page 機能不全は warning + legacy 案内)
- port 3060-3070 内 LISTEN 失敗で次 port、3071 全 occupied で error exit
- browser auto-open OS 検出 (`open` / `xdg-open` / `start`)、失敗で URL 表示 + 手動案内
- localhost only bind (`127.0.0.1`)、外部 access 禁止
- preset 適用は atomic (途中失敗で partial state なし、`.preset-history/` に rollback record)
- 新規 smoke `.claude/tests/hc-config-web-ui-smoke.sh` 全 case PASS (server unit + API endpoint + preset apply + legacy fallback)
- 既存 smoke 21/21 + 14/14 regression 0
- reviewer iter 5 上限内収束 (CRIT+HIGH+MED=0)
- commit + push + PR create (feature branch `feat/hc-config-web-ui`、task #39 緩和で自律実行可)
- 4 リポ install 案内 (user manual + Node.js install check)

## Task 概要欄 (list.md 用、3 要素規範)

- **何のため**: task-60 完遂後の user UX 改善要望「UX 悪い、戻ったりできません。Web で変更する仕様に変更したい」+ 「プリセットを作成して一括変更できるように」を実現するため
- **何をやる**: Node.js HTTP server + Tailwind CDN + 素 JS + 10 named preset + 6 軸 hardcode で `hc-config.sh interactive` を Web UI 化、legacy TUI を env switch fallback で維持、Node.js install check を install.sh に追加
- **何ができる**: user が browser で preset 選択 → diff preview → 一括変更 → rollback 操作でき、74 key 個別調整 cost が解消され、project 立ち上げ時の品質レベル / FW 選択が 1 click 化

## Step 計画

詳細は draft `docs/draft/hc-config-web-ui.md` §5 参照。

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `hc-config.sh` wrapper 修正 (legacy env switch + node 起動 dispatcher) | 0.5h | — |
| 2 | 🔲 | `hc-config-web-server.js` 新規 (Node.js http server + API 7+ endpoint + bash subprocess) | 4h | Step 1 |
| 3 | 🔲 | `hc-config-web-ui/{index.html,app.js,style.css}` (Tailwind CDN + 素 JS、4 領域 UI) | 4h | Step 2 |
| 4 | 🔲 | `.claude/presets/*.yml` 10 named preset 定義 + server.js 内 6 軸 hardcode + preset 適用ロジック (batch cmd_set + rollback) | 2h | Step 2 |
| 5 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / pr-test-analyzer + code-reviewer + ui-designer [Web UI UX] + harness-optimizer) + iter cycle 収束 | 2h | Step 4 |
| 6 | 🔲 | (テスト合格) 新 smoke (server unit + API endpoint + preset apply atomic + legacy fallback) + 手動 Web UI 検証 (browser で preset 選択 / diff / apply / rollback) + 既存 smoke 35 regression 0 | 1.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) Node.js code 関数分割 / DRY / preset 軸定義の汎用化判定 / 3 観点 (持続可能性 / 汎用性 / 非冗長化) | 1h | Step 6 |

合計工数: 約 14h

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `.claude/scripts/lib/hc-config-web-server.js` (~400 LOC) / `.claude/scripts/lib/hc-config-web-ui/{index.html,app.js,style.css}` (~550 LOC) / `.claude/presets/*.yml` 10 件 (各 ~30 LOC = ~300 LOC) / `.claude/tests/hc-config-web-ui-smoke.sh` |
| 修正 file | `.claude/scripts/hc-config.sh` (cmd_interactive dispatcher 拡張、~40 LOC) / `install.sh` (Node.js install check 追加) / `.gitignore` (`.claude/.preset-history/` 除外) |
| 新規 env | `HC_HC_CONFIG_TUI_LEGACY` (`true` で task-60 TUI fallback、default Web UI) |
| 不変 | `.claude/scripts/lib/hc-config-metadata.sh` / `.claude/harness-config.yml` / 既存 smoke / task-46/48/60 commit |
| 互換性 | 既存 CLI args (`--list` / `--get` / `--set` / `--reset`) 不変、`interactive` のみ default 動作変更 (Web UI 起動、legacy env で TUI fallback) |
| Node.js 依存 | 標準 module のみ (`http` / `child_process` / `fs` / `path` / `os`)、npm dep 0 |
| Tailwind 依存 | CDN online 必須 (offline 時は warning + legacy TUI 案内) |
| consuming repo 影響 | 4 リポ全 Node.js install 必須化、install.sh で check + WARN |

## 派生 task / 次アクション候補

- task-60 Step 6/7 は legacy 維持で **skip 維持** (本 task 完遂後の TUI legacy retention 期間で必要なら別 task で対応)
- next-actions entry #60 (task-56 由来 3 key metadata 正規登録) は task-60 と独立、別 task で対応継続
- next-actions entry #61 (`harness_version` stamp 更新) は本 task PR merge 前に対応必要

## 関連

- 設計起源: [hc-config-web-ui.md](../draft/hc-config-web-ui.md)
- 前提 task: [task-60](task-60-hc-config-tui-2tier-navigation.md) / [task-48](task-48-hc-config-interactive-tui.md) / [task-46](task-46-config-yml-phase3-hc-config-script.md)
- 修正先: `.claude/scripts/hc-config.sh` (cmd_interactive dispatcher 拡張)
- 新規先: `.claude/scripts/lib/hc-config-web-server.js` + `.claude/scripts/lib/hc-config-web-ui/` + `.claude/presets/`
- smoke: `.claude/tests/hc-config-web-ui-smoke.sh` (新規)
- 採用 6 条: `.claude/rules/task-management.md` Layer A §採用 6 条

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-29 | 起案 | draft 起こし (subagent a9a409d69db838980 conf 0.87、387 行、Step 7、preset 6 軸 + 10 named preset + Node.js + Tailwind CDN + 素 JS) |
| 2026-05-29 | 承認 | user「承認します」発言、4 確認ポイント全 AI 推奨採用 (1) 10 named preset 軸組合せ classlab-weekly-news ≒ `production-typescript-personal` / (2) git_workflow 4 値 `none`/`unrestricted`/`main_protected`/`main_stg_protected` / (3) preset 軸定義 server.js 内 hardcode / (4) `.claude/.preset-history/` `.gitignore` 対象 |
| 2026-05-29 | task 化 | task-61 file 生成 + list.md row 61 append |
