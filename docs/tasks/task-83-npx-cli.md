---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #83: hirai-method の npx CLI 化（public npm + `npx hirai-method check/install/update`）

> Status: **✅ 完了** (2026-06-07、smoke 43/43 + regression 0。reviewer 3 体 iter1 で CRIT2/HIGH6/MED 多数 → fix round1 で収束)
> 起案: 2026-06-07
> 関連: #82 (project-rules 保護 = 【1】), #84 (準自動 update = 【3】予定)
> 設計起源: [npx-cli.md](../draft/npx-cli.md)（2026-06-07 承認済）

## Task ゴール

`bin/cli.js` + 拡張済 `package.json` により `npx hirai-method check / install <dir> / update <dir>` が動作し、`check` が npm registry 最新版と version 比較、`install`/`update` が同梱 install.sh 経由で `.claude` を配布する（content-post 生成物を除外して package サイズ 15M 級）。npm publish 手順書（user manual）も整備される。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-82 | project-rules 保護（harness=update 追従 / project-rules=永続保護 の分離）が npx update の安全な前提。update が project 固有 rule を壊さない保証を継承する | [task-82-project-rules-protection.md](task-82-project-rules-protection.md) |

## Task 作業概要

- 既存 `package.json` を拡張（scoped `@<org>/hirai-method` 名 / `bin` / `publishConfig` / `files` allowlist + `.npmignore` で content-post 生成物 1.5G+ 除外）
- `bin/cli.js` 新設（shebang + 依存ゼロ arg parse、`check`/`install <dir>`/`update <dir>`/`--version`/`--help`、bash/rsync 事前チェック）
- `check` = `https://registry.npmjs.org/<pkg>/latest` と version 比較（fail-open）、`install`/`update` = 同梱 install.sh を child_process で起動（flag 透過）
- npm publish user manual（version ↔ harness_version 同期規約）整備
- smoke（`npm pack --dry-run` 同梱検証 / content-post 混入 0 / `check` version mock / `install <tmpdir>` 実配布）

## Task 完了条件 (DoD)

- [ ] `package.json` 拡張（`bin` + `publishConfig` + `files` allowlist）+ `bin/cli.js`（3 サブコマンド + `--version`/`--help`）実装
- [ ] `check` が registry 最新版と比較し stale/up-to-date 判定（network fail = fail-open WARN）
- [ ] `install <dir>` / `update <dir>` が同梱 install.sh 経由で `.claude` 配布（smoke 実証）
- [ ] `npm pack --dry-run` で同梱 file が allowlist 通り（**content-post 生成物 1.5G+ 混入 0** + transient 混入 0、tarball 15M 級）
- [ ] npm publish user manual（version/harness_version 同期規約含む）を docs に整備
- [ ] 既存 smoke regression 0
- [ ] CommonRules.md / development-process.md §harness 取込に npx 経路を追記
- [ ] commit 完了（npm publish 自体は user 実行 = modes.md 遵守事項 8 license/public カテゴリ、push は user manual）

## Task 概要欄 (list.md 用、3 要素規範)

clone 依存の手動配布と「最新版を知らない」stale 限界を解消するため hirai-method を public npm 化し `npx hirai-method check/install/update` を提供する。完成すれば採用 repo は clone 不要で 1 コマンド導入・更新でき、`check` の registry 比較が【3】準自動 update の前提となり、content-post 生成物を除外した 15M package として publish できる。

## 背景・目的

現状 harness 配布は `git clone` + `bash install.sh --update <dir>` の手動・repo ローカル経路のみで、最新版判定も自己整合性止まり（stale-harness-detection の限界）。npm registry を version SSoT とすることで配布 UX と stale 検出の両方を構造解決する。自動アップデート roadmap【2】（【1】project-rules 保護完了を受けた次段、【3】の前提）。

## 仕様（決定済）

### Q1: 配布実装方式

| 案 | 内容 | 評価 |
|---|---|---|
| **A** | Node CLI が install.sh をラップ（child_process spawn） | **採用**: 701 行の install.sh を 100% 再利用、SSoT 二重化なし |
| B | Node で install ロジック再実装（fs.cp） | 不採用: 二重 SSoT で drift リスク、harness 思想に反する |
| C | npm 薄公開 + GitHub から .claude 取得 | 不採用: ネットワーク 2 経路、version SSoT 分裂、オフライン不可 |

→ **案 A**。bash/rsync 前提（Windows 非対応 = YAGNI、採用者 Unix 系想定）。

### Q2: package 名

→ **scoped `@<org>/hirai-method`**（name 衝突回避 + signal 明確）+ `publishConfig:{access:public}`。org 名は Step 1 で user 確認。

## TDD 戦略

### RED（先に追加するテスト）
- `.claude/tests/npx-cli-smoke.sh`（新設）: `npm pack --dry-run` の同梱 file に content-post 生成物が **含まれない**こと / transient 除外 / `bin/cli.js` の shebang + 実行 bit / `check` の version 比較ロジック（registry mock）/ `install <tmpdir>` で `.claude` が配布されること

### GREEN（最小実装）
- `package.json` 拡張 + `bin/cli.js` 新設 + `.npmignore` 新設

### REFACTOR
- arg parse の共通化 / install.sh 呼出の DRY 化（3 観点判定）

## Step 計画

### Step 一覧 (サマリ表)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | ✅ | 既存 package.json 拡張（scoped name / bin / publishConfig / files allowlist）+ `.npmignore`（content-post 除外） | 0.5h | — |
| 2 | ✅ | `bin/cli.js`（shebang + arg parse + package root 解決 + bash/rsync 事前チェック） | 0.8h | Step 1 |
| 3 | ✅ | `check`（registry latest fetch → version 比較 → stale 案内、fail-open） | 0.6h | Step 2 |
| 4 | ✅ | `install <dir>` / `update <dir>`（同梱 install.sh を child_process 起動、flag 透過） | 0.6h | Step 2 |
| 5 | ✅ | npm publish user manual（docs/npx-publish-guide.md、version=semver / harness_version=日付 分離） | 0.3h | Step 1-4 |
| 6 | ✅ | (テスト設計レビュー) code-reviewer + security-reviewer + test-automator 3 体並列、iter1 CRIT2/HIGH6/MED 多数 → fix round1 で収束 | 0.4h | Step 5 |
| 7 | ✅ | (テスト合格) npx-cli-smoke.sh 43/43 PASS + regression 0 | 0.5h | Step 6 |
| 8 | ✅ | (リファクタリング) skip: 新規単一ファイル(<800行)・依存ゼロ・重複なし・code-reviewer 品質高評価、3観点該当なし | 0.2h | Step 7 |

合計工数: 約 3.9h

### Step 1: package.json 拡張 + .npmignore

**Step status**: 🔲

**作業概要**: 既存 package.json に `name`（scoped）/ `version`（harness_version 同期）/ `bin` / `publishConfig:{access:public}` / `files` allowlist を追加。`.npmignore` で content-post 生成物（`drafts/`・`contents_manage/images/`）+ transient を除外。

**完了条件**: `npm pack --dry-run` で content-post 生成物が同梱 file に **現れない**（grep 0 件）、tarball 15M 級。

### Step 2: bin/cli.js（骨格）

**Step status**: 🔲

**作業概要**: shebang + 依存ゼロ arg parse、package root 解決（`import.meta.url`/`__dirname`）、bash/rsync 存在事前チェック、`--version`/`--help`。

**完了条件**: `node bin/cli.js --version` / `--help` が動作、rsync 不在 mock で明確なエラー出力。

### Step 3: check サブコマンド

**Step status**: 🔲

**作業概要**: `https://registry.npmjs.org/<pkg>/latest` を fetch（timeout 付き）→ `.version` をローカル version と semver 比較 → stale なら `npx <pkg>@latest update` 案内。network fail は fail-open WARN（exit 0）。

**完了条件**: registry mock で stale/up-to-date を正しく判定、offline mock で fail-open（exit 0 + WARN）。

### Step 4: install / update サブコマンド

**Step status**: 🔲

**作業概要**: 同梱 install.sh を `child_process.spawn('bash', [installShPath, ...])` で起動、`--update`/`--force`/`--overwrite-all` flag 透過、stdout/stderr 透過。

**完了条件**: `node bin/cli.js install <tmpdir>` で tmpdir に `.claude` が配布される（smoke 実証）。

### Step 5: npm publish user manual

**Step status**: 🔲

**作業概要**: `docs/` に publish 手順（`npm login` → `npm version <x>` → harness_version stamp 同期 → `npm publish`）。agent は publish しない旨明記。

**完了条件**: docs に手順 + version 同期規約が記載、modes.md 遵守事項 8 参照あり。

### Step 6: (テスト設計レビュー)

**Step status**: 🔲

**作業概要**: メインが reviewer 動的選定（tdd-guide / test-automator / qa-expert / pr-test-analyzer + Node/CLI 観点 1+）、起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限確認、並列起動、収束まで反復（上限 `review_iteration_max`）。

**完了条件**: 全 reviewer approve / no objection、iter cycle 収束。

### Step 7: (テスト合格)

**Step status**: 🔲

**作業概要**: 非 UI（CLI）のため unit/integration smoke（`.claude/tests/npx-cli-smoke.sh`）。content-post 混入 0 / shebang / check version mock / install 実配布。

**完了条件**: `bash .claude/tests/npx-cli-smoke.sh` exit 0、既存 smoke regression 0。

### Step 8: (リファクタリング)

**Step status**: 🔲

**作業概要**: 持続可能性 / 汎用性 / 非冗長化 の 3 観点で見直す。

**完了条件 (or skip)**: refactor 実施なら指標 / 不要なら `skip: <理由>` 明示記録。

## 工数見積

約 3.9h（実装 Step1-5 約 2.8h + レビュー/テスト/refactor 約 1.1h）

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `package.json`（拡張）, `bin/cli.js`（新設）, `.npmignore`（新設）, `.claude/tests/npx-cli-smoke.sh`（新設）, `docs/`（publish manual）, `.claude/rules/development-process.md`（npx 経路追記） |
| migration | なし |
| 環境変数 | なし |
| 互換性 | 既存 install.sh は無変更（ラップのみ）、後方互換 |

## 再発防止

- npm publish は user manual（自律実行禁止カテゴリ遵守）
- content-post 除外を smoke で機械検証（除外漏れ = publish 不能の事前防止）

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-07 | 起案 | 設計 draft 起こし（npx-cli.md） |
| 2026-06-07 | 承認 | user 承認（scoped `@takuma-hirai`）、list.md に追加 |
| 2026-06-07 | 実装 | Step1-5 並列 subagent、smoke 15→43 ケース、reviewer 3 体 iter1 → fix round1 収束 |
| 2026-06-07 | 完了 | smoke 43/43 + regression 0、commit `<sha>` |

## 派生 task / 次アクション候補

- [ ] (🟢) task-84【3】準自動 update — stale-detect を npm registry 比較に拡張、本 task の `check` を再利用 → [stale-harness-detection.md](../draft/stale-harness-detection.md) 拡張予定

## 関連

- Draft: [npx-cli.md](../draft/npx-cli.md)
- 依存タスク: #82
- 派生タスク: #84（【3】準自動 update）
