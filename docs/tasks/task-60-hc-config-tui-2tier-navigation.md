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
| 2026-05-29 | task 化 | task-60 file 生成 + list.md row 60 append (subagent a18b63130835e010f conf 0.98、append mode、line 183) |
| 2026-05-29 | feature branch 切替 | `feat/hc-config-tui-2tier-navigation` 切替 + task 化 commit `761c1cd` (3 file +353 行、draft + task file + list.md row) |
| 2026-05-29 | list.md sub-row 7 件追加 | Step 1-7 の sub-row を list.md task-60 header row 直後に追加 (採用 6 条 6 構造遵守、Step 1 着手 = 🔄、Step 2-7 = 🔲) |
| 2026-05-29 | Step 1 着手 | subagent aa39c2d98aaab70f9 委譲、`_cmd_interactive_tui` → `_cmd_interactive_tui_flat` rename + `HC_HC_CONFIG_FLAT_NAVIGATION=true` env switch 追加、staging 戦略 (`/tmp/hc-config.sh` Edit + mv) + bash 3.2 互換維持 + 既存 smoke 21/21 + 14/14 regression 0 確認、Conventional Commits 1 commit |
| 2026-05-29 | Step 1 完了 | commit `7de5b9d` (+27/-1、`.claude/scripts/hc-config.sh` 1 file)、subagent aa39c2d98aaab70f9 conf 0.93、L1370 関数 rename + L1415-1438 wrapper 追加 (env switch + TODO comment)、smoke regression: script 21/21 PASS、tui 12/14 PASS (Case 1/2 baseline 既存 FAIL、git stash 検証で本変更起因 0 確認)、bash 3.2 互換 (`declare -g` / 連想配列 / `${var^^}` 不使用)、fallback 動作確認 (`HC_HC_CONFIG_FLAT_NAVIGATION=true` で flat 旧実装起動 + non-TTY で numeric menu 経路) |
| 2026-05-29 | Step 2 着手 | subagent 委譲、`_tui_render_category_menu` 関数新規追加 (6 category 一覧 + sel ハイライト + 1 階層 menu、bash 3.2 互換 + staging 戦略 + regression 0)、Conventional Commits 1 commit |
| 2026-05-29 | Step 2 完了 | commit `21fe83f` (+45/-0、L1311-1351、`.claude/scripts/hc-config.sh` 1 file)、subagent a8e4f696cd0939a44 conf 0.95、`_meta_count_by_category` (LOC 8) + `_tui_render_category_menu` (LOC 17) 新規追加、6 category count 実測 (保護パス=3 / ファイル配置=7 / state_dir=7 / Gate/Confidence=12 / feature_toggle=26 / reviewer_control=19 = 計 74、metadata lib `hc_metadata_keys_by_category` 一致、draft §3.2 旧数値 3/4/9/18/21/20=75 から metadata 進化)、smoke regression: script 21/21 + tui 12/14 baseline 維持、bash 3.2 互換 (local -a index array のみ、連想配列 / declare -g / ${var^^} 不使用) |
| 2026-05-29 | Step 3 着手 | subagent 委譲、`_tui_render_key_menu(cat_idx, key_sel)` 関数新規追加 (category 配下 key 一覧 + sel ハイライト + 下部 effect panel、bash 3.2 互換 + staging 戦略 + regression 0)、Conventional Commits 1 commit |
| 2026-05-29 | Step 3 完了 | commit `e34e3a8` (+63/-0、L1356-L1418、`.claude/scripts/hc-config.sh` 1 file)、subagent a661956c0a5242356 conf 0.93、`_tui_render_key_menu(cat_idx, key_sel)` LOC 63 新規追加 (inline effect panel `_tui_render_effect_panel` API 踏襲 `_yml_get_raw`/`_get_current`/`_get_default`/`_infer_type`/`_meta_desc`/`_meta_effect`)、key 取得 metadata lib `hc_metadata_keys_by_category` 経由 (lib 不在時 `(該当 key なし)` degrade)、描画テスト feature_toggle 26 key + 保護パス 3 key OK、smoke regression 0、bash 3.2 互換 (`local -a` index array のみ) |
| 2026-05-29 | Step 4 着手 | subagent 委譲、`_cmd_interactive_tui` wrapper non-flat path を 3-state machine (`category_menu` / `key_menu` / `effect_edit`) ループに書き換え (sel 位置記憶 scalar 7 var: `_tui_cat_sel` + `_tui_key_sel_0..5`、eval 合成、ESC/LEFT で 1 階層 back、q で quit)、staging 戦略 + bash 3.2 互換 + regression 0、Conventional Commits 1 commit |
| 2026-05-29 | Step 4 完了 | commit `e65c98d` (+172/-8、L1528-1685 `_cmd_interactive_tui_2tier` +158 LOC + L1687-1701 wrapper TODO 部分置換、`.claude/scripts/hc-config.sh` 1 file)、subagent a7079f6054e635418 conf 0.85、3-state machine 実装: category_menu → key_menu → effect_edit、sel 7 var (`_tui_cat_sel` + `_tui_key_sel_0..5`、eval 合成)、既存 `_tui_read_key` 再利用 (生 read より flat と統一)、`cmd_set "key=val"` 1 引数形式 (task 指示の 2 引数誤りを subagent が訂正)、`_tui_handle_enter` raw/canonical mode 切替パターン踏襲、smoke regression 0 (script 21/21 + tui 12/14 baseline) + bash 3.2 互換 (連想配列 / `declare -g` 不使用) + `HC_HC_CONFIG_FLAT_NAVIGATION=true` flat fallback 維持 + 非 TTY pipe → numeric fallback 動作維持 |
| 2026-05-29 | Step 5 iter 1 着手 | reviewer 6 名動的選定 (採用 6 条 4) 並列起動: base 4 (tdd-guide / test-automator / qa-expert / pr-test-analyzer) + domain 2 (code-reviewer = bash 3.2 互換 + state machine + edge cases / harness-optimizer = hc-config harness 整合 + 既存 hook 整合)、workflow.md §reviewer prompt 共通規約 5 必須項目遵守 (対象 Read / 観点 / findings format / confidence / プロジェクト整合性 + 他 task 影響確認)、iter 上限 5、収束条件 CRIT+HIGH+MED=0 |
| 2026-05-29 | Step 5 iter 1 完了 | 6/6 reviewer 完了 (subagent aa8f767443dbefe8f tdd-guide conf 0.82 / a06b3437dedcff597 test-automator conf 0.88 / ab3378cfe7f594f9f qa-expert conf 0.88 / ae0011d60b3390dd7 pr-test-analyzer conf 0.87 / a2206627f378174c7 code-reviewer conf 0.84 / a63da0543c8ec5eb8 harness-optimizer conf 0.88、median 0.875)、HIGH 累計 12 件 unique 5 critical: (1) ESC back QUIT 化 [3 reviewers cross-confirm、DoD 直結] / (2) `cat_names` DRY 3 箇所 [4 reviewers] / (3) effect panel inline 再実装 [code-reviewer 独自 H3] / (4) eval safety `_tui_cat_sel` sanitize [code-reviewer H1 独自] / (5) Case 1/2 root cause = task-56 由来 3 key metadata 未登録 [3 reviewers]、MED 19+ / LOW 10+、iter 2 続行 Yes 4 / No 2、code-reviewer 深い repro で H3+M1+H1 独自発見 (feedback `code-reviewer-deep-test-advantage` 再実証) |
| 2026-05-29 | Step 5 iter 2 着手 | hot fix H1-H5 統合 1 subagent (ad7a4dcb563416ab9) 委譲、5 件統合 1 commit: (H1) ESC back fix = `_cmd_interactive_tui_2tier` key_menu case `QUIT` → `state="category_menu"` (`_tui_read_key` 戻り値仕様変更回避、`_cmd_interactive_tui_flat` Case 11 baseline 維持) / (H2) `_TUI_CAT_NAMES_STR` 定数 1 箇所定義 + 3 関数で `IFS='\|' read -r -a cat_names` 展開 / (H3) `_tui_render_effect_panel_for_key(selected_key)` helper 抽出 + key_menu 内 1 行 call / (H4) eval 直前 `_tui_cat_sel` 数値 sanitize / (H5) smoke `HC_TUI_SMOKE_EXCLUDE_KEYS` 3 key exclude list (非侵襲的、別 task で正規登録予定)、M1 関数分割 147 LOC は Step 7 先送り、smoke 14/14 PASS 目標 |
| 2026-05-29 | Step 5 iter 2 完了 | commit `93edfef` (+100/-47、subagent ad7a4dcb563416ab9 conf 0.92、2 file: hc-config.sh + hc-config-tui-smoke.sh)、H1-H5 全 5 件統合実装完了、smoke script 21/21 + tui **14/14 PASS** (12/14 → 14/14、Case 1/2 exclude 効果) |
| 2026-05-29 | Step 5 iter 3 着手 | reviewer 6 名同構成 並列起動 (iter 2 fix 検証 focus + 残 M/L 整理 + iter 4 続行判定) |
| 2026-05-29 | Step 5 iter 3 完了 | 6/6 reviewer 完了 (a9e96631 tdd-guide conf 0.88 / adfaf623 test-automator conf 0.93 / aeae73bc qa-expert conf 0.88 / a2f39ad2 pr-test-analyzer conf 0.87 / a4cfdbca code-reviewer conf 0.93 / ac1e6c69 harness-optimizer conf 0.91、median 0.90)、iter 4 続行 Yes 2 / **No 4 (収束)**、CRIT+HIGH=0、新規 MED unique critical 1: **qa-expert M-new-1 = draft §3.1 仕様乖離 (iter 2 fix で `_tui_read_key` 戻り値仕様維持の代償、key_menu で `q` 押下が back に化け「q で全終了」喪失)** → memory `iter-approve-design-drift-user-verify` 教訓再発 pattern、その他 MED: M-new-2 (2tier seam test 未追加、Step 6 で吸収) / M5 (`_TUI_CAT_NAMES_STR` readonly 未化、Step 7) / M6 (167 LOC、Step 7 関数分割対象更新)、副産物 entry #60 (3 key metadata 正規登録) + #61 (`harness_version` stamp 更新) next-actions.md 追加 |
| 2026-05-29 | Step 5 iter 4 着手 | M-new-1 真の fix (scope 限定、1 subagent a8d31b6450c3092fc 委譲): (1) `_tui_read_key` 単独 ESC を `ESC` で返す (現状 QUIT) / (2) `_cmd_interactive_tui_2tier` key_menu case で `ESC\|LEFT` → back / `QUIT` (q) → 全終了に分離 (draft §3.1 完全充足) / (3) `_cmd_interactive_tui_flat` 側で `ESC\|QUIT` 互換 case (Case 11 baseline 維持) / (4-5) state machine コメント + L1553 旧仕様 sync、M5/M6/関数分割は Step 7 据置、smoke regression 0 で iter 5 reviewer skip → Step 5 収束予定 |
| 2026-05-29 | Step 5 iter 4 完了 | commit `3249ae7` (+47/-19、`.claude/scripts/hc-config.sh` 1 file)、subagent a8d31b6450c3092fc conf 0.92、5 件統合実装完了 (`_tui_read_key` L1207-1219 ESC return + `_cmd_interactive_tui_2tier` key_menu ESC/LEFT/QUIT 分離 + `_cmd_interactive_tui_flat` QUIT\|ESC 互換 + state machine コメント sync + key_max=0 path 分離)、smoke script 21/21 + tui 14/14 PASS、draft §3.1 完全充足 (`key_menu --q--> quit` / `key_menu --ESC/LEFT--> category_menu`) + `_cmd_interactive_tui_flat` Case 11 baseline 維持、**Step 5 収束達成 (CRIT+HIGH=0)** |
| 2026-05-29 | Step 6 着手 | smoke `hc-config-tui-smoke.sh` Case 15-19 拡張 1 subagent 委譲: Case 15 state machine 遷移 seam (`_cmd_interactive_tui_2tier` 非 TTY source + stdin pipe で q/ESC/Enter drive) / Case 16 `_tui_render_category_menu` + `_tui_render_key_menu` render seam (`_TUI_CAT_NAMES_STR` 展開 + sel ハイライト assert) / Case 17 `HC_HC_CONFIG_FLAT_NAVIGATION=true` flat 起動 seam / Case 18 `HC_TUI_SMOKE_EXCLUDE_KEYS=` 空時 negative test (Case 1 sanity) / Case 19 effect_edit y/N confirm path、既存 smoke 35 regression 0、手動 TTY 検証は DoD user 任意 |
| 2026-05-29 | **user 仕様変更受諾 + task-60 finalize** | user「UX 悪い、戻ったりできません。起動したら WebServer を起動して Web で変更する仕様に変更したい」+「設定に関してはあらかじめプリセットを作成して一括変更できるように。POC/production_service/inner_system などの品質レベルと開発フレームワークなどの軸を用意。あと Git の有無や直接 push 禁止など」発言、Web UI + preset 機能 仕様変更受諾。Step 6 subagent (aeffaadffe2047f5f) kill、Step 5 完遂状態で **finalize** (Step 6/7 skip 明示、legacy 用 nice-to-have で重要度低下)、TUI 実装 (Step 1-5 累計 7 commits) は legacy として保持。新 task task-61 `hc-config-web-ui` draft 起案 (subagent a9a409d69db838980 conf 0.87、387 行、Step 7、Node.js + Tailwind CDN + 素 JS + 10 named preset + 6 軸 hardcode)、user 承認 (4 確認ポイント全 AI 推奨採用)、`docs/tasks/task-61-hc-config-web-ui.md` 生成 + list.md row 61 append (subagent aea16bfb1b619b318 委譲)、feature branch `feat/hc-config-web-ui` 切替済 (task-60 7 commits を base) |
| 2026-05-29 | task-60 ✅ 完遂 | Step 1-5 達成、Step 6/7 skip with reason (user 仕様変更で legacy 化)、累計 7 commits on `feat/hc-config-tui-2tier-navigation` (`761c1cd` task 化 → `7de5b9d` Step 1 → `21fe83f` Step 2 → `e34e3a8` Step 3 → `e65c98d` Step 4 → `93edfef` Step 5 iter 2 → `3249ae7` Step 5 iter 4)、smoke 21/21 + 14/14 PASS、draft §3.1 完全充足、`feat/hc-config-web-ui` branch (task-61) 経由で 1 PR に統合予定 |
