# npx CLI publish ガイド (user manual)

> hirai-method を public npm package として公開し `npx @takuma-hirai/hirai-method <cmd>` で配布するための手順。
> **npm publish は user が terminal で実行する**（agent は実行しない = `.claude/rules/modes.md` 遵守事項 8「license / public」カテゴリ）。
> 設計: [`docs/draft/npx-cli.md`](draft/npx-cli.md) / task: [`docs/tasks/task-83-npx-cli.md`](tasks/task-83-npx-cli.md)

## 配布物の概要

| 項目 | 値 |
|---|---|
| package 名 | `@takuma-hirai/hirai-method`（scoped public） |
| bin | `hirai-method`（`bin/cli.js`） |
| 同梱 | `bin/` + `.claude/` + `install.sh` + `CLAUDE.md` + `docs/INVENTORY.md`（`files` allowlist） |
| 除外 | content-post 生成物（drafts/images、1.5G+）+ transient state（`.npmignore`） |
| サイズ | content-post 除外後 15M 級（`npm pack --dry-run` で実測） |

## サブコマンド

```bash
npx @takuma-hirai/hirai-method@latest check            # 現 version vs npm registry 最新版を比較
npx @takuma-hirai/hirai-method@latest install <dir>    # <dir> に harness を新規導入 (install.sh ラップ)
npx @takuma-hirai/hirai-method@latest update <dir>     # <dir> の harness を最新へ更新 (install.sh --update ラップ)
```

- `install` / `update` は `--force` / `--overwrite-all` / `--no-mcp` / `--no-docs` を install.sh へ透過。
- **`@latest` を必ず付ける**（npx cache staleness 回避、npm/cli#7838）。
- 前提: 実行環境に **bash + rsync**（Unix 系。Windows 非対応）。cli.js が事前チェックして不在なら明示エラー。

### `check` の fail-open 運用注意（CI）

`check` は network 失敗・timeout・non-200 時に **fail-open**（stderr に WARN、exit 0）する（開発を止めないため）。CI でオフライン / sandbox の場合、`check` は常に exit 0 を返し「stale でも気づかない」状態になりうる。CI で stale 検出を確実にしたい場合は **exit code ではなく stderr の `WARN: registry 最新版を取得できませんでした` を grep して扱う**こと。

## version 規約（重要）

**npm の `package.json` version（semver）と `harness_version`（日付）は別概念**:

| 概念 | 形式 | 用途 | 更新者 |
|---|---|---|---|
| `package.json` の `version` | semver `x.y.z` | npm registry の version SSoT。`check` の比較対象 | publish 時に user が `npm version` で bump |
| `.claude/harness-config.yml` の `harness_version` | `YYYY-MM-DD` | consuming repo が「いつ sync したか」の stamp。stale-detect（【3】）用 | install.sh が `--init`/`--update` 時に書込 |

両者は同期しない（型が違う）。`check` は **semver 同士**を比較する。

## publish 手順

```bash
# 1. npm にログイン (初回 + 2FA)
npm login

# 2. publish 前検証 (同梱 file + サイズ + content-post 混入 0 を確認)
npm pack --dry-run 2>&1 | grep -c 'content-post/drafts'      # → 0 であること
npm pack --dry-run 2>&1 | tail -20                            # tarball サイズ確認 (15M 級)

# 3. version bump (semver)
npm version patch     # or minor / major

# 4. public publish (scoped は --access public 必須。package.json の publishConfig で自動)
npm publish

# 5. 公開確認
npm view @takuma-hirai/hirai-method version
```

## 初回 publish 前のチェックリスト

- [ ] npm account に `@takuma-hirai` scope が存在する（個人 username scope は自動、org は事前作成）
- [ ] `npm pack --dry-run` で content-post 生成物が **同梱されない**（grep 0）
- [ ] tarball が 15M 級（1G+ でない）
- [ ] `bin/cli.js` に実行 bit（publish 時に npm が付与、`files` 同梱必須）
- [ ] `node bin/cli.js --version` / `--help` がローカルで動作（`npm link` で実機確認推奨）

## ローカル実機確認（publish 前）

```bash
npm link                          # グローバルに symlink
hirai-method --version            # 動作確認
hirai-method check                # registry 比較 (未 publish なら 404 → fail-open WARN)
hirai-method install /tmp/test-harness   # 配布確認
npm unlink -g @takuma-hirai/hirai-method # 後始末
```

## 準自動アップデート（task-84、【3】）

consuming repo は SessionStart で harness が最新か自動チェックされる:

1. `install.sh --update` 時に `harness_npm_version`(semver) が consuming repo の `harness-config.yml` に stamp される（npm package version の記録）。
2. SessionStart hook `stale-harness-detect.sh` が **throttle（既定 24h 1 回）** で npm registry latest を取得し、stamp と semver 比較する。
3. 新版があれば `<system-reminder>` で **「`npx @takuma-hirai/hirai-method@latest update <dir>` で更新」を WARN**（block しない、適用は user の 1 コマンド = 完全自動 push なし）。
4. network 失敗・stamp 不在は **fail-open**（silent、開発を止めない）。

| 設定 (harness-config.yml) | 既定 | 役割 |
|---|---|---|
| `feature_stale_harness_detect_enabled` | `true` | 機能 ON/OFF（env `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED`） |
| `stale_harness_check_interval_hours` | `24` | registry 再チェック間隔 |

一時無効化: `HC_STALE_HARNESS_DETECT_ENABLED=false`。

## 関連

- 【3】準自動 update（task-84）: 上記「準自動アップデート」セクション。設計: [`docs/draft/npx-auto-update.md`](draft/npx-auto-update.md)
- `.claude/rules/development-process.md` §harness 取込チェックリスト（npx 経路）
