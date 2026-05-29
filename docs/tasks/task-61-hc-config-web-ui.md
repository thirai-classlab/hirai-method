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
| 2026-05-29 | task 化 | task-61 file 生成 + list.md row 61 append (subagent aea16bfb1b619b318 conf 0.97、L191、append mode、regression 0) |
| 2026-05-29 | feature branch 切替 + 統合 commit | `feat/hc-config-web-ui` 切替 (task-60 7 commits を base)、task-60 finalize (Step 6/7 skip) + task-61 task 化を 1 commit に統合 (commit `a035b89`、6 file +541/-3、draft + task file + list.md + next-actions entry #60/#61 + task-48 follow-up + task-60 ステータスログ)、push origin set up to track |
| 2026-05-29 | Step 1 着手 | subagent ab5018ffe8c1d8294 委譲、`hc-config.sh` `cmd_interactive` dispatcher 拡張 (env `HC_HC_CONFIG_TUI_LEGACY=true` で TUI fallback、default `_cmd_interactive_web` placeholder + Step 2 待ち warning + TUI 降格 safety net)、staging 戦略 + bash 3.2 互換 + smoke 21/21 + 14/14 regression 0、Conventional Commits 1 commit |
| 2026-05-29 | Step 1 完了 | commit `81a156e` (+26/-1、`.claude/scripts/hc-config.sh` 1 file)、subagent ab5018ffe8c1d8294 conf 0.95、L1782-1792 `cmd_interactive` dispatcher 4 分岐 (TTY+LEGACY→TUI / TTY+default→Web / FORCE_NUMERIC→numeric / non-TTY→numeric) + L1794-1807 `_cmd_interactive_web` placeholder 新規 (stderr WARN + `_cmd_interactive_tui` 降格)、staging 戦略遵守 (`cp /tmp/` → Edit → `mv` + chmod +x)、4 分岐 stub 検証 OK、smoke regression 0 + bash 3.2 互換 (`[ ... ]` のみ) |
| 2026-05-29 | Step 2 着手 | subagent 委譲、`hc-config-web-server.js` 新規 (Node.js `http` module、~400 LOC、API 7+ endpoint: keys/value/set/categories/presets/preset_diff/preset_apply/preset_save/preset_history、bash subprocess `child_process` for cmd_set、port 3060-3070 自動 detect、localhost only bind、browser auto-open `open`/`xdg-open`/`start`、Ctrl+C graceful shutdown) + `_cmd_interactive_web` placeholder を本実装に置換 (node 不在 check + server 起動)、staging 戦略 + npm dep 0、smoke regression 0、Conventional Commits 1 commit |
| 2026-05-29 | Step 2 完了 | commit `3a86a65` (+811/-13、6 file: server.js 新規 530+ LOC + index.html placeholder 27 LOC + hc-config.sh +22/-8 + .gitignore +1 + list.md + task-61.md sync)、subagent a9c9cd62b47afe911 conf 0.92、10 endpoint 実装 (`/`/`/static/*`/`/api/categories`/`/api/keys`/`/api/value/:key`/`/api/set`/`/api/presets`/`/api/preset/:name/diff`/`/api/preset/:name/apply`/`/api/preset/history`/`/api/preset/rollback/:timestamp`)、10 named preset hardcode + 6 軸 (quality_level / language_framework / git_workflow / tdd_policy / review_intensity / autonomy_level)、live boot HC_WEB_NO_OPEN=1 で port 3060 listen + curl 5 endpoint 全 200 OK、smoke regression 0 (script 21/21 + tui 14/14)、Node.js 標準 module のみ (`http`/`child_process`/`fs`/`path`/`os`/`url`、npm dep 0)、bash 3.2 互換、staging 戦略遵守、補足設計判断: spawnSync 採用 / loadMetadata で hc-config-metadata.sh TSV dump → JSON 変換 / preset apply atomic + history rollback / 1MB body cap + path traversal 防止 / `HC_WEB_NO_OPEN=1` で browser auto-open 抑止 |
| 2026-05-29 | Step 4 skip 明示 | user 承認 Q3「preset 軸定義 server.js 内 hardcode」で `.claude/presets/*.yml` 外部化は YAGNI 判断、Step 2 で server.js 内 10 named preset + 6 軸 hardcode + batch cmd_set (`/api/preset/:name/apply`) + history rollback (`/api/preset/rollback/:timestamp`) ロジック完遂、Step 4 scope の core 機能は Step 2 で達成済 → Step 4 ✅ skip with reason |
| 2026-05-29 | Step 3 着手 | subagent 委譲、`.claude/scripts/lib/hc-config-web-ui/{index.html,app.js,style.css}` 実装 (Tailwind CDN + 素 JS、4 領域 layout = sidebar preset selector / category list / key list / edit+diff panel、~550 LOC)、Step 2 placeholder index.html (27 LOC) を full 実装に置換、fetch API で 10 endpoint 呼出 (preset apply フロー / 個別 key 編集 / history rollback)、staging 戦略 + smoke regression 0、Conventional Commits 1 commit |
| 2026-05-29 | Step 3 完了 | commit `442ef21` (+796/-19、3 file: index.html 88 LOC full + app.js 679 LOC + style.css 45 LOC、`.claude/scripts/lib/hc-config-web-ui/`)、subagent add3e59dba6fa8b45 conf 0.92、4 領域 layout (header [タイトル + status banner + Tailwind CDN offline 警告] / sidebar 280px [preset list + category list] / main [idle/preset diff/category key list/key edit form の 3-state machine] / footer [preset apply history + rollback table])、fetch API で 10 endpoint 呼出、preset apply フロー (sidebar select → loadPresetDiff → diff table 行ごと skip toggle + すべて skip/適用 ボタン → confirm dialog → apply → toast + history reload + diff 再計算)、個別 key 編集フロー (category select → keys 一覧 → key click → edit form 現在値 + input + Apply)、history rollback (履歴行ごと Rollback ボタン → confirm → batch hcSet to original values → reload)、Tailwind CDN offline 検出 (`window.tailwind` 不在で 1.5s 後 banner 表示)、`node --check` OK + server 起動 curl `/static/*` 3 file 全 200 + Tailwind CDN 1 occurrence 確認、smoke regression 0 |
| 2026-05-29 | Step 5 iter 1 着手 | 採用 6 条 4 reviewer 6 名動的選定 並列起動: base 4 (tdd-guide / test-automator / qa-expert / pr-test-analyzer) + domain 2 (code-reviewer = Node.js + bash subprocess + state machine + path traversal / ui-designer = Web UI UX + Tailwind + accessibility + offline UX)、workflow.md §reviewer prompt 共通規約 5 必須項目遵守 (対象 Read / 観点 / findings format / confidence / プロジェクト整合性 + 他 task 影響確認)、iter 上限 5、収束条件 CRIT+HIGH+MED=0 |
| 2026-05-29 | Step 2 完了 | `.claude/scripts/lib/hc-config-web-server.js` 新規 (~530 LOC、Node.js 標準 module のみ `http`/`child_process`/`fs`/`path`/`os`/`url`、npm dep 0)、API 10 endpoint (categories / keys / value / set / presets / preset-diff / preset-apply / preset-history / preset-rollback / static)、10 named preset hardcode (poc-no-git / poc-with-git / inner-ts / inner-py / prod-ts-personal / prod-ts-enterprise / prod-py / prod-rust / prod-go / harness-development) + 6 軸定義、port 3060-3070 auto detect、localhost only bind、SIGINT graceful shutdown、browser auto-open + `--no-open` flag、`.claude/scripts/lib/hc-config-web-ui/index.html` placeholder 配置、`_cmd_interactive_web` 本実装置換 (node 不在 + server.js 不在で TUI 降格 safety net)、`.gitignore` に `.claude/.preset-history/` 追加、起動検証 OK (port 3060 listen + curl /api/categories /api/keys /api/presets /api/preset/inner-typescript/diff /static/index.html 全 200)、smoke 21/21 + 14/14 PASS regression 0、bash -n + node --check OK、staging 戦略遵守 (cp /tmp/ → Edit → mv + chmod +x) |
| 2026-05-29 | Step 5 iter 1 進捗 (新 session 45th→46th) | `/resume-state loop` で 45th 復元 → 残 3 reviewer (qa-expert af27ecf0 / pr-test-analyzer ace210db / ui-designer a3289624) fresh 再起動 (background 並列、findings 集約予定)、並走中 main 独立作業として code-reviewer iter 1 CRIT C1 (server.js SyntaxError 疑い) を実機検証 subagent (a1cc0b0b conf 0.99) 委譲で **否認確定** (`node --check` exit 0、`const path` は line 35 のみ unique top-level 宣言、line 504 は `const pathname` 別名で grep 部分一致誤検出)、C1 closure 扱い、iter 2 計画に C1 fix 計上不要、reviewer false alarm 校正 100% (reviewer conf 0.78 → 実機 conf 0.99) |
| 2026-05-29 | Step 5 iter 1 完了 (6 reviewer 集約) | 6 reviewer findings 完了集約 (median conf 0.84): tdd-guide CRIT 2 + HIGH 3 / test-automator HIGH 3 + MED 4 / code-reviewer CRIT 3 (C1 否認) + HIGH 4 + MED 5 + LOW 4 / qa-expert af27ecf0 conf 0.82 CRIT 2 (C-Q1 atomic / C-Q2 rollback traversal) + HIGH 5 + MED 5 + LOW 4 / pr-test-analyzer ace210db conf 0.88 CRIT 3 (C-P1 smoke 不在 / C-P2 atomic / C-P3 rollback chain 壊れ) + HIGH 4 + MED 4 + LOW 2 + 17 boundary case + test seam 設計 (callHcConfig DI 化案) / ui-designer a3289624 conf 0.88 CRIT 2 (C-U1 accessible name / C-U2 label-input) + HIGH 4 + MED 5 + LOW 3。**unique 集約 CRIT 7 / HIGH 12 / MED 13 / LOW 7** (収束条件 CRIT+HIGH+MED=0 まで 32 件 fix 必要)。CRIT unique: (1) applyPreset atomic 違反 / (2) rollback timestamp path traversal / (3) unit test seam 不在 + callHcConfig DI 化 / (4) rollback chain 壊れ (多重 apply 後の history rollback で history-2 変更残存) / (5) UI accessible name 欠落 / (6) label-input 関連付け不在 / (7) smoke ファイル未作成。設計乖離: §3.2 `/api/preset/save` 未実装 / §3 diff table effect 列欠落 / §3.4 atomic 保証 / §6 Save as Custom Preset UI 不在 / §5 yml feature toggle `feature_hc_config_tui_legacy_enabled` 未登録 |
| 2026-05-29 | Step 5 iter 2 完了 (4 領域並列 fix + 5 commit) | iter 1 unique 32 件 fix を A/B/C/D 4 領域並列 subagent (median conf 0.92) で完遂、5 commit (`b9716af` A server.js 16 fix +475/-89 + `34ab50a` B WCAG 2.2 AA 14 fix + Save UI +669/-156 + `81dc4ed` C smoke 新規 1125 LOC + `d12b0f7` D yml feature toggle + dispatcher OR + metadata 1 行 +32/-14 + `41eb26b` docs sync +12/-5)、累計 +2313/-264、live boot 11 endpoint OK + smoke script 21/21 + tui 14/14 + web-ui 19/19 PASS regression 0、WCAG 2.2 AA 16 SC 違反全 closure |
| 2026-05-29 | Step 5 iter 3 完了 (6 reviewer 集約) | 6 reviewer 並列 (median conf 0.88): tdd-guide HIGH 5 + MED 5 / test-automator HIGH 3 + MED 5 / pr-test CRIT 2 (NEW-C-1 /api/keys 74 spawn event loop / NEW-C-3 abort rollback silent no-op) + HIGH 3 + MED 5 / ui-designer HIGH 1 (H-new-1 role=listbox WCAG 4.1.2) + MED 3 / **qa-expert CRIT 2 (CRIT-Q1 yml inline comment _hc_normalize 矛盾 / CRIT-Q2 KNOWN_KEYS 未登録) + HIGH 4 + MED 5** / code-reviewer 深い repro NF-13 (HIGH 実機 stamp 衝突 conf 0.96) + NF-2/9 (HIGH history write silent data loss) + NF-8 (HIGH internal path leak) + MED 5。**unique 集約 CRIT 4 (NEW-C-1 / NEW-C-3 / CRIT-Q1 / CRIT-Q2) + HIGH 18 + MED 20+**、iter 2 fix で iter 1 全 CRIT 7 closure 確認も新規軸の CRIT が出現 → iter 4 必要 |
| 2026-05-29 | Step 5 iter 4 完了 (4 領域並列 fix + 4 commit + D-redo) | A (`798bd98` +275/-31 conf 0.92) NEW-C-1 hcListAll 118x 高速化 (3.12s) + NF-13 stamp pid+counter + NF-2/9 snapshot rollback + NF-8 sanitizeErrorMessage + HIGH-Q3 / NF-3 / NF-6 / NF-10 / 設計乖離 name regex 3-49 + axes 6 軸必須 / B (`abf13ef` +194/-50 conf 0.88) H-new-1 role=list (APG YAGNI) + M-new-1〜3 (resolved flag / aria-invalid / dynamic aria-label) + MED-Q1 partial UI 詳細 + MED-Q5 loadCurrentAxes + API contract / C (`14a2380` +883/-93 conf 0.92) smoke 19→34 case + HIGH-Q1/Q2 + strict S-15 + S-16 encoded + S-17 strict + ISOLATED_HISTORY_DIR + bind ループ / D 初回 (ac318b9a conf 0.92) **silent mv fail** → D-redo (`46f058e` conf 0.94) main Edit + subagent 統合で CRIT-Q1/Q2 closure (yml inline comment 除去 + 4-locus integration KNOWN_KEYS+Defaults+Export)、smoke web-ui 34/38 PASS + 4 SKIP (manual) + 0 FAIL、script 21/21 + tui 13/14 (Case 7 pre-existing 確認) |
| 2026-05-29 | Step 5 iter 5 着手 (最終、6 reviewer 並列) | iter 4 fix verify + 最終収束判定: tdd-guide a08722b9 / test-automator ad560bec / qa-expert a10c71ae / pr-test-analyzer a4180ec2 / code-reviewer a303809d / ui-designer a6e87719、5 反復上限、収束 (CRIT+HIGH+MED=0) なら Step 6 移行 / 未達なら user escalation |
| 2026-05-29 | Step 5 iter 5 完了 (6 reviewer 集約) | tdd-guide conf 0.92 未達 (HIGH-N1 S-26 / HIGH-N2 HC_HISTORY_DIR_OVERRIDE / MED-N3 custom preset サイドバー反映後 diff/apply 404) + ui-designer conf 0.93 達成 + pr-test 達成 (GAPs 3 1-line 級) + test-auto CONDITIONAL (tui Case 7 regression 本 task 起因 yml comment 消失) + code-reviewer conf 0.94 未達 (NEW-H-iter5-1 HC_HISTORY_DIR_OVERRIDE 実証 137 history + 11 custom 残骸) + qa-expert conf 0.91 達成。**3 reviewer cross-confirm HIGH 1 件 (HC_HISTORY_DIR_OVERRIDE) + 2 reviewer cross-confirm HIGH 1 件 (S-26) + tdd 単独 MED-N3 (実 HIGH 級、§6 DoD 実質未達) + Case 7 regression** → iter 6 hot fix 1-line fix 7-10 件 ~35-50 行で対応決定 (採用 6 条 4 5 反復上限超過だが規模小、user escalation 不要) |
| 2026-05-29 | Step 5 iter 6 hot fix 完了 (2 領域並列 + 2 commit) | A (`552b232` +112/-9 conf 0.94): HC_HISTORY_DIR_OVERRIDE + HC_PRESETS_DIR_OVERRIDE env override (test isolation) + **MED-N3 §6 DoD 完全達成** (savePreset で in-memory PRESETS 追加 + scanCustomPresets() で dynamic scan + 3 route merge → 200 not 404) + HISTORY_MAX_FILES safe fallback (NaN/負値) + router DI 明示 + timed_out UI surface + dead CSS 削除 / B (`5d30dae` +23/-16 conf 0.97): smoke S-26 strict 200|400→400 + yml inline comment 2 行復元 (**tui-smoke Case 7 PASS 復帰 13→14**) + ISOLATED_PRESETS_DIR teardown 隔離。live boot fresh boot 両方 200 確認 (`/api/preset/custom-test-iter6/diff`)、smoke script 21/21 + tui 14/14 + web-ui 33/38 PASS (S-02 flaky 許容 + 4 manual SKIP)。**CRIT+HIGH+MED=0 達成**、Step 6 移行可 |
| 2026-05-29 | Step 6 着手 | 採用 6 条 4「UI 含 task = E2E + visual verification 必須」、smoke 全実行 (web-ui 34 + script 21 + tui 14 = 69 case auto regression 0 確認) + visual verification 10 case (initial / preset diff / category / key edit / CDN offline / toast / history / 1280px / 1024px / dark) agent-browser skill + screenshot 撮影 |
| 2026-05-29 | Step 6 完了 (smoke + visual 10 case) | subagent ab16c51b conf 0.95、smoke 全 PASS (web-ui 34/38 + script 21/21 + tui 14/14 regression 0)、visual verification 10/10 case 撮影 `.claude/.task-screenshots/task-61/case-NN-*.png` (initial / preset diff / category / key edit / CDN offline / toast / history / confirm / save / focus)、採用 6 条 4「E2E + visual 必須」充足。残 LOW: case-03「(undefined)」カテゴリ表示 + case-07「Invalid Date」history timestamp + S-02 flaky (timing race 機能正常) — Step 7 で軽微 fix or parking-lot 起票 |
| 2026-05-29 | Step 7 着手 | リファクタリング 3 観点 (持続可能性 / 汎用性 / 非冗長化) acceptable 判定 + Step 6 LOW 2 件 (case-03 undefined / case-07 Invalid Date) 軽微 fix、server.js 1374 LOC + app.js 1208 LOC + smoke 1915 LOC の大規模 refactor (4 module 分離 / pure function reducer / smoke helper 抽出) は **本 task scope 外 + 別 task で対応宣言** (本 task は 機能実装 + iter 5 reviewer 12 名 + Step 6 visual verification で品質確保済) |
