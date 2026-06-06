---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #84: 準自動アップデート（SessionStart registry 比較 → `npx ... update` WARN 誘導）

> Status: **✅ 完了** (2026-06-07、smoke 19/19 3回安定 + regression 0。reviewer 3 体 iter1 HIGH1/MED5 → fix round1 収束)
> 起案: 2026-06-07
> 関連: #82 (project-rules 保護 = 【1】), #83 (npx CLI = 【2】、check 再利用)
> 設計起源: [npx-auto-update.md](../draft/npx-auto-update.md)（2026-06-07 承認済、案 A）

## Task ゴール

install.sh が consuming repo に `harness_npm_version`(semver) を stamp し、SessionStart の stale-detect が npm registry latest と比較して新版検出時に「`npx @takuma-hirai/hirai-method@latest update <dir>`」を WARN 誘導する（throttle + fail-open + feature toggle、適用は user 1 コマンド = 完全自動 push なし）。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-83 | `bin/cli.js` の `compareSemver`/`parseSemver`（module.exports 済）と `HIRAI_METHOD_REGISTRY_BASE` を本 task の registry 比較で再利用（SSoT） | [task-83-npx-cli.md](task-83-npx-cli.md) |
| task-82 | npx update が project-rules を壊さない保証（project-rules 保護）を継承 | [task-82-project-rules-protection.md](task-82-project-rules-protection.md) |

## Task 作業概要

- install.sh に `harness_npm_version`(semver) stamp 追加（既存 `harness_version` 日付と併存）
- `stale-harness-detect.sh`(SessionStart) 新設/拡張: throttle で registry latest 取得 → stamp と semver 比較 → 新版で WARN
- semver 比較は cli.js の compareSemver 再利用（hook 単独動作の fallback も担保）
- settings.json 配線 + feature toggle + throttle 間隔 yml key
- development-process.md §harness 取込 / publish guide に準自動検出動線追記

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: install.sh semver stamp / SessionStart registry 比較 WARN（throttle+fail-open）/ compareSemver 再利用 or fallback 明示 / feature OFF・bypass で no-op / smoke 5 シナリオ + regression 0 / docs 追記 / 完全自動 push なし（案 A 厳守）/ commit 完了。

## Task 概要欄 (list.md 用、3 要素規範)

旧 harness 稼働を検出しつつ更新動線を 1 コマンド化するため、install.sh が semver を stamp し SessionStart stale-detect が npm registry 比較で新版検出時に `npx ... update` を WARN 誘導する。完成すれば consuming repo は session 開始時に harness が最新か自動把握でき、1 コマンドで安全に更新でき、自動アップデート roadmap 3 機能が完結する。

## 設計

draft [npx-auto-update.md](../draft/npx-auto-update.md) §3 を SSoT（案 A 準自動、install.sh semver stamp + SessionStart registry 比較 + WARN 誘導）。stale-harness-detection.md（marker 欠落検出）の version 比較延期分を本 task で実現。

## TDD 戦略

### RED
- smoke: stamp 古→WARN / 同値→silent / network 失敗→fail-open / throttle 2 回目 skip / feature OFF→no-op

### GREEN
- install.sh semver stamp + stale-harness-detect.sh registry 比較

### REFACTOR
- compareSemver 再利用で重複排除 / throttle・fail-open の関数化

## Step 計画

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | install.sh §6.6 `harness_npm_version`(semver) stamp（既存日付 stamp と併存、argv 化） | 0.4h | — |
| 2 | ✅ | `stale-harness-detect.sh`(SessionStart) 拡張: throttle + registry 比較 + WARN（fail-open/subshell 局所化、既存 marker/date logic に +189 行） | 0.8h | 1 |
| 3 | ✅ | semver 比較 SSoT: cli.js compareSemver 再利用 + hook fallback、`HIRAI_METHOD_REGISTRY_BASE` 尊重 | 0.4h | 2 |
| 4 | ✅ | SessionStart 配線（dispatcher-manifest 既存 entry）+ feature toggle + throttle yml key + config-loader export | 0.2h | 2 |
| 5 | ✅ | development-process.md §harness 取込 / npx-publish-guide に準自動検出動線追記 | 0.2h | 2 |
| 6 | ✅ | (テスト設計レビュー) code-reviewer + security-reviewer + test-automator 3 体、iter1 HIGH1(flaky)/MED5 → fix round1 収束 | 0.4h | 5 |
| 7 | ✅ | (テスト合格) smoke 19/19 (既存10+registry5+Gap4) 3回安定 + regression 0 | 0.5h | 6 |
| 8 | ✅ | (リファクタリング) skip: 既存拡張 + cli.js SSoT 再利用、fallback semver の重複は standalone 動作のため意図的、reviewer 品質 approve、3観点該当なし | 0.2h | 7 |

合計工数: 約 3.1h

### Step 1: install.sh semver stamp
**Step status**: 🔲
**作業概要**: install.sh が package.json の version(semver) を読み consuming repo の harness-config.yml に `harness_npm_version` stamp（既存 `harness_version` 日付 stamp L506-540 付近に追加）。
**完了条件**: `bash install.sh --update <tmp>` 後、`<tmp>/.claude/harness-config.yml` に `harness_npm_version: "0.1.0"` が書かれる（smoke）。

### Step 2: stale-harness-detect.sh registry 比較
**Step status**: 🔲
**作業概要**: SessionStart hook が throttle（24h、cache marker）で registry latest 取得 → stamp と semver 比較 → 新版で `<system-reminder>` WARN「`npx @takuma-hirai/hirai-method@latest update <dir>`」。fail-open + feature toggle + bypass env + subshell 局所化。
**完了条件**: stamp 古 fixture で WARN 発火 / 同値で silent / network 失敗で fail-open（smoke）。

### Step 3: semver 比較 SSoT 再利用
**Step status**: 🔲
**作業概要**: hook が cli.js の compareSemver を `node -e` 経由で再利用。cli.js 不在環境向け fallback semver 比較も持つ。registry 取得は `HIRAI_METHOD_REGISTRY_BASE` 尊重（smoke で local server）。
**完了条件**: cli.js 経由比較 + fallback 双方が smoke で動作。

### Step 4: 配線 + toggle
**Step status**: 🔲
**作業概要**: settings.json SessionStart に wrapper 後配置、`feature_stale_harness_detect_enabled` + throttle 間隔 key を harness-config.yml に追加。
**完了条件**: feature OFF で no-op（smoke）。

### Step 5: docs 追記
**Step status**: 🔲
**作業概要**: development-process.md §harness 取込（取込タイミング 3 = F WARN）と npx-publish-guide に準自動検出 → `npx ... update` 動線を追記。
**完了条件**: 両 docs に動線記載（grep）。

### Step 6: (テスト設計レビュー)
**Step status**: 🔲
**作業概要**: reviewer 動的選定（tdd-guide / test-automator / qa-expert / pr-test-analyzer + harness-optimizer）、起動前に `hc-config.sh --get review_max_count_test` 確認、収束まで反復。
**完了条件**: 全 reviewer approve / no objection。

### Step 7: (テスト合格)
**Step status**: 🔲
**作業概要**: 非 UI のため smoke（stale-harness-detect-smoke.sh）5 シナリオ。
**完了条件**: smoke 全 PASS + 既存 regression 0。

### Step 8: (リファクタリング)
**Step status**: 🔲
**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点。
**完了条件 (or skip)**: refactor 実施なら指標 / 不要なら `skip: <理由>`。

## 工数見積

約 3.1h

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `install.sh`(semver stamp), `.claude/hooks/stale-harness-detect.sh`(新設/拡張), `.claude/settings.json`, `.claude/harness-config.yml`(feature+throttle key), `.claude/tests/stale-harness-detect-smoke.sh`(新設), `docs/`(動線追記) |
| migration | なし（旧 install の repo は stamp 不在 = fail-open silent） |
| 環境変数 | `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED` / throttle override |
| 互換性 | WARN のみ block しない、feature toggle OFF 可、完全自動 push なし |

## 再発防止

- 完全自動 push は実装しない（案 A 厳守、modes.md 遵守事項 8）
- semver 比較は cli.js SSoT 再利用で重複排除

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-07 | 起案 | draft 起こし（npx-auto-update.md） |
| 2026-06-07 | 承認 | user 承認（案 A）、list.md に追加 |
| 2026-06-07 | 実装 | P (install.sh stamp) + Q (hook+config+配線) 並列、Q クラッシュ→再実行、smoke 10→19 |
| 2026-06-07 | 完了 | reviewer 3 体 iter1 → fix round1 収束、smoke 19/19 3回安定 + regression 0、commit `<sha>` |

## 派生 task / 次アクション候補

- [ ] (🟢) stale-harness-detection.md（marker 欠落検出）との最終統合 or 役割分担確定 — Step 2 で判断、必要なら next-actions entry 化

## 関連

- Draft: [npx-auto-update.md](../draft/npx-auto-update.md)
- 依存タスク: #83, #82
- 統合元: [stale-harness-detection.md](../draft/stale-harness-detection.md)
