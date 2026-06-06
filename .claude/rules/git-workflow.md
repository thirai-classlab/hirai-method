# Git Workflow Rules: ブランチ命名規約（harness 共通）

## 規約

```
<type>/<short-kebab-description>
```

- **type**: `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf` / `ci` / `hotfix`
- **description**: lowercase + 数字 + `-` のみ。3〜49 文字
- **`main`** は唯一の例外（プレフィックス不要）
- 例: `feat/proxy-rate-limit`, `fix/perm-401-loop`, `hotfix/gateway-token-rotation`

正規表現（SSoT）:

```
^(main|(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)/[a-z0-9][a-z0-9-]{2,48})$
```

## 二重ガード

| 層 | 場所 | 効果 | 既存ブランチへの影響 |
|---|---|---|---|
| ローカル | `.githooks/pre-push` | 新規作成 push 時のみ検証 | なし（update push は素通し） |
| サーバー | GitHub Rulesets (`.github/rulesets/branch-naming.json`) | 創設時 reject | なし（既存 ref には適用しない） |

両ファイルは consuming project 側で個別に配置する（harness 内には現状テンプレ未配布。プロジェクトの実装例: `openclaw-railway-deploy`）。

## セットアップ（プロジェクト側で 1 回）

### A. GitHub Rulesets（サーバー側・必須）

```bash
gh api --method POST \
  /repos/{OWNER}/{REPO}/rulesets \
  --input .github/rulesets/branch-naming.json
```

### B. ローカル pre-push hook（補助・推奨）

```bash
chmod +x .githooks/pre-push
git config core.hooksPath .githooks
```

クローンごとに 1 回。

## 変更時の同期義務

正規表現を変える場合は **3 箇所同時更新**（drift 禁止）:

1. このファイル
2. `.githooks/pre-push` の `ALLOWED_REGEX`
3. `.github/rulesets/branch-naming.json` の `parameters.pattern`

## 緊急バイパス

| 方法 | スコープ | 痕跡 |
|---|---|---|
| `git push --no-verify` | 1 push のみ（local 側のみ。Rulesets は依然 reject） | git log に痕跡なし |
| Rulesets 一時 disable | repo 全体 | GitHub audit log |

honor system: 緊急バイパス時は理由を commit message または PR description に明記。

## 関連

- Commit 規約: Conventional Commits（`<type>(<scope>): <desc>`）

---
> **project 固有の追補・override は `.claude/project-rules/git-workflow.md` に書く** (本 file は harness 所有、`install.sh --update` で上書きされる。project 固有編集は下記 import 先へ)。
@../project-rules/git-workflow.md
