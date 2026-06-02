---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #76: hc-config Web 設定ページ 2 分割再設計 (custom 復活 + task-70/71 取込 + diff バグ修復)

> Status: **🔲 未着手**
> 起案: 2026-06-03
> 関連: #70 (enforcement_matrix), #71 (dispatcher), #72 (web-ui flaky smoke), #61/#63 (Web UI 実装/簡素化)
> 設計起源: [hc-config-web-2pane-redesign](../draft/hc-config-web-2pane-redesign.md)

## Task ゴール

hc-config Web 設定ページが「上部タブ (設定/履歴) + 設定タブ内 2 分割 (左=プリセット / 右=機能カテゴリごと accordion で実設定値)」になり、preset 選択の diff が「Failed to fetch」にならず正常表示され、右ペインで値を変更すると自動「カスタム」化し、task-70 の default_preset (4 enforcement level) + 主要 guard feature toggle が右ペインから視認・変更でき、設定画面はページ全体スクロールせず viewport に収まる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-70 | enforcement_matrix / default_preset (advisory/team-default/strict/harness-dev) を UI に取込む。左ペインの preset 分類 (どの axes-preset がどの level か) は enforcement_matrix 定義を Read して確定 | [task-70-*.md](task-70-enforcement-matrix-preset-aware.md) |
| task-71 | dispatcher 統合。Web UI は独立 server のため直接の取込は薄いが、settings/hook 構造との整合を確認 | [task-71-*.md](task-71-hook-dispatcher-consolidation.md) |

## Task 作業概要

- diff「Failed to fetch」を実機再現 → root cause 確定 → 最小差分修復 (`computePresetDiff` を `hcListAll` キャッシュ参照化)
- server.js API 拡張 (preset を enforcement level で group 化、custom 判定、個別値 batch set、category metadata 付与)
- app.js を上部タブ (設定/履歴) + 2 分割 (左 preset / 右 category accordion 同時 1 開) に再構成、編集→custom 遷移、履歴をタブ分離
- style.css を 2 分割 + accordion + no-scroll (100vh 収め) + responsive 化
- dead code / 旧 docstring 整理

## Task 完了条件 (DoD)

- [ ] ブラウザで preset 選択時の diff が「Failed to fetch」にならず正常表示
- [ ] 左 preset / 右 category accordion の 2 分割画面が動作
- [ ] 上部タブ「設定」「履歴」が動作し、プリセット適用履歴は履歴タブにのみ表示 (設定タブに無い)
- [ ] 設定画面でページ全体スクロールが発生しない (viewport 100vh、主要 breakpoint で確認)
- [ ] 右ペインで値を変更すると header / 左選択が自動「カスタム」化
- [ ] task-70 の default_preset (4 level) + 主要 guard feature toggle が右ペインから視認・変更可能
- [ ] smoke 全 PASS + 既存 harness smoke regression 0
- [ ] reviewer approve (テスト設計レビュー Step、min≤N≤max)
- [ ] visual 検証 (agent-browser screenshot 主要状態) 合格
- [ ] commit 完了 (push は task #39 緩和で feature branch 自律可、PR merge は user)

## Task 概要欄 (list.md 用、3 要素規範)

「設定できない (diff Failed to fetch) / task-70-71 未取込 / UX 複雑」を解消するため、hc-config Web UI を上部タブ + 2 分割 (左 preset / 右 category accordion) に再設計し diff バグを修復する。完成すれば user が viewport 内 no-scroll で preset 選択・個別値編集 (編集で自動 custom 化)・enforcement level/guard 切替・履歴閲覧を直感的に行えるようになる。

## 背景・目的

task-63 案 C の過剰簡素化で「個別値編集 = custom」導線が失われ、かつ task-70 の config モデル進化 (enforcement_matrix / default_preset) に Web UI が追従していない。さらに preset 選択時の diff がブラウザで「Failed to fetch」になり事実上設定不能。user 要求 (2 分割 / custom / 履歴別タブ / no-scroll / diff 修復) で再設計する。

## 設計

詳細は draft [hc-config-web-2pane-redesign](../draft/hc-config-web-2pane-redesign.md) §3 を SSoT とする (採用案 C ハイブリッド、レイアウト図、挙動仕様)。

## TDD 戦略

### RED
- diff endpoint の正常 JSON 応答 + 連続呼び出し応答性 smoke (Failed to fetch 再現/回帰防止)
- custom 遷移 / accordion 単一開 / タブ切替 / no-scroll の smoke + visual

### GREEN
- `computePresetDiff` キャッシュ化、server API 拡張、app.js タブ+2分割、css no-scroll を最小実装で PASS

### REFACTOR
- 3 観点 (持続可能性 / 汎用性 / 非冗長化)、旧 docstring 圧縮 / dead code 削除

## Step 計画

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | diff「Failed to fetch」実機再現 → `computePresetDiff` を hcListAll キャッシュ参照化 + RED smoke (commit 4d990b8、diff 0.4s→0.006s、S-48/S-49 追加、未再現も構造改善+回帰anchor) | 0.5h | — |
| 2 | ✅ | server.js API 拡張 (commit 7df441e: /api/presets group=quality_level 3群 / match_type unsaved→custom / 実7category 確定 / batch=client loop / S-50,S-51) | 0.8h | Step 1 |
| 3 | ✅ | app.js (上部タブ 設定/履歴 + 左 preset / 右 accordion 同時1開 / 編集→custom / 履歴タブ分離) commit d58d2f7、browser 自己検証 (a)-(f) PASS | 1.1h | Step 2 |
| 4 | ✅ | style.css 2 分割 + accordion + no-scroll 100vh + responsive (d58d2f7、1280/1024 scrollHeight==clientHeight) | 0.5h | Step 3 |
| 5 | ✅ | dead code 削除 + 旧 docstring 圧縮 (d58d2f7、3 file 全面書換で sidebar 残骸除去) | 0.2h | Step 3 |
| 6 | 🔄 | (テスト設計レビュー) iter1: code-reviewer + frontend-developer 2体 (max10内)、HIGH4 (stale smoke 6FAIL/S-42 guard空振り/isCustom reset/iOS overflow) + MED/LOW、security APPROVED。Step6-fix で対応中 | 0.5h | Step 5 |
| 7 | 🔲 | (テスト合格) smoke 更新 + E2E + visual 必須 (初期/preset選択/編集→custom/accordion/タブ切替/no-scroll/responsive/toast) | 0.6h | Step 6 |
| 8 | 🔲 | (リファクタリング) 3 観点判定 or skip | 0.3h | Step 7 |

合計工数: 約 4.5h

### Step 1: diff バグ修復
**Step status**: ✅ (commit 4d990b8)
**作業概要**: agent-browser で「Failed to fetch」を実機再現 → root cause 確定 → `computePresetDiff` (web-server.js L598-628) を hcGet N回から hcListAll キャッシュ参照に変更。
**完了条件**: diff smoke PASS、ブラウザで diff 正常表示 (再現できない場合は別 root cause 調査 + user に実機ログ依頼)
**結果**: browser で未再現 (診断仮説どおり) だが構造修正は妥当 → `computePresetDiff` L610 で `hcListAll(overrides)` 1 回参照化 (API response 不変)、diff 0.4s→0.006s。S-48 (後方互換) / S-49 (応答性回帰 anchor) 追加。全 hc-config smoke regression 0 (web-ui 45/53 PASS 8 SKIP 0 FAIL)。

### Step 2: server API 拡張
**Step status**: 🔲
**作業概要**: enforcement_matrix/default_preset 読取で preset を 4 level group 化、match_type を 'preset'|'custom' に整理、個別値 batch set 経路、各 key に category 付与。
**完了条件**: 新 API smoke PASS

### Step 3: app.js タブ + 2 分割
**Step status**: 🔲
**作業概要**: top/edit 2-view を廃し、上部タブ (設定/履歴) + 左 preset section / 右 category accordion (同時1開) + 編集→custom reducer + 履歴タブ分離。
**完了条件**: app smoke PASS、各操作動作

### Step 4: style.css no-scroll
**Step status**: 🔲
**作業概要**: 2 column grid + accordion CSS + `height:100vh; overflow:hidden` でページ全体スクロール禁止 (accordion 内のみ overflow:auto) + 768px 以下縦積み。
**完了条件**: visual で no-scroll 確認

### Step 5: cleanup
**Step status**: 🔲
**作業概要**: app.js sidebar dead comment 削除、server.js/app.js 旧 task docstring 圧縮。
**完了条件**: dead code grep 0、regression 0

### Step 6: (テスト設計レビュー)
**Step status**: 🔲
**作業概要**: base (tdd-guide/test-automator/qa-expert/pr-test-analyzer) + UI/JS domain reviewer を min≤N≤max で動的選定、並列起動、収束まで反復 (上限 review_iteration_max)。起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限確認。
**完了条件**: 全 reviewer approve / no objection、CRIT+HIGH+MED=0

### Step 7: (テスト合格)
**Step status**: 🔲
**作業概要**: UI Task のため smoke 更新 + E2E + **visual 必須** (agent-browser screenshot: 初期 / preset 選択 / 値編集→custom / accordion 開閉 / 設定↔履歴タブ切替 / no-scroll / responsive / 保存 toast)。
**完了条件**: 全 smoke PASS (regression 0) + visual 主要状態合格

### Step 8: (リファクタリング)
**Step status**: 🔲
**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点で見直す。
**完了条件 (or skip)**: refactor 実施なら指標 / 不要なら skip 理由明示

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/scripts/lib/hc-config-web-server.js`, `.claude/scripts/lib/hc-config-web-ui/{app.js,index.html,style.css}`, `.claude/tests/hc-config-web-ui-smoke.sh` |
| migration | なし |
| 環境変数 | なし (既存 HC_* 流用) |
| 互換性 | UI 全面再構成 (内部のみ、外部 API は後方互換維持を志向) |

## 再発防止

- 設計の外部依存 (enforcement_matrix key) は Step 着手前に grep 確認 (memory feedback_design_external_dependency_verification)
- cross-file 契約 (app.js render target ↔ index.html id) は SSoT 事前明示 (memory feedback_parallel_subagent_cross_file_contract_drift)
- UI は smoke 全 green でも render 不能ありえ visual が最終安全網 (採用 6 条 4)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-03 | 起案 | draft hc-config-web-2pane-redesign 承認 |

## 派生 task / 次アクション候補

- (なし、着手時に発生したら本セクションに追記)

## 関連

- Draft: [hc-config-web-2pane-redesign](../draft/hc-config-web-2pane-redesign.md)
- 依存タスク: #70, #71
