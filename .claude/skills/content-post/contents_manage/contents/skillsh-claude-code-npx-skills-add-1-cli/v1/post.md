

## 1. これは何を解決するか

Claude Code の **Skill** は強力ですが、配布と管理に課題があります。

- 公開スキルが GitHub にあっても、**手動で clone → `~/.claude/skills/` に配置 → 設定を直書き**するのは面倒
- スキルの更新（`git pull`）や削除（rmrf）も都度コマンドが必要
- Claude Code / Cursor / Windsurf など **複数のツールに同じスキルを入れる**ときに二重管理になる
- Project スコープと Global スコープの **使い分けが曖昧**になりがち

[skill.sh](https://skill.sh) は、これら全部を `npx skills <command>` の 1 行で解決する CLI です。

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/skillsh-claude-code-npx-skills-add-1-cli/7996834c-flow.png" alt="skill.sh インストールフロー" width="1536" height="1024">

---

## 2. インストール

```bash
npx skills add <github-repo-url> --skill <skill-name>
```

例: Vercel 公式の `ai-sdk` スキルを入れる:

```bash
npx skills add https://github.com/vercel/ai --skill ai-sdk
```

`npx` 経由なのでグローバルに何も追加せず実行できる（毎回最新版が走る）。

---

## 3. 実行時の対話プロンプト

`npx skills add` を叩くと、以下 3 つの選択を順に求められます。

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/skillsh-claude-code-npx-skills-add-1-cli/d6aa8c33-prompts.png" alt="インストール時の3段階プロンプト" width="1536" height="1024">

| # | プロンプト | 選択肢 | 推奨 |
|---|-----------|-------|------|
| 1 | どのツールに入れるか | Claude Code / Cursor / Windsurf 等 | **Claude Code** |
| 2 | スコープ | **Global** / **Project** | 普段使いは Global、リポジトリ専用なら Project |
| 3 | インストール方式 | **Symlink** / Copy | **Symlink**（`git pull` で更新が即反映） |

### スコープの使い分け

| スコープ | インストール先 | 用途 |
|----------|---------------|------|
| **Global** | `~/.claude/skills/` | どのプロジェクトでも使う汎用スキル（content-post / ai-image-gen 等） |
| **Project** | `<repo>/.claude/skills/` | そのリポ固有のドメイン知識を含むスキル（社内マスタ依存等） |

### Symlink を選ぶ理由

- Symlink: 中身は GitHub clone した dir への参照のみ → `git pull` で全環境一括更新
- Copy: その時点のスナップショットを物理コピー → 更新時は再インストールが必要

短期検証なら Copy でも可。継続運用なら **Symlink 一択**。

---

## 4. 主要コマンド

```bash
# インストール
npx skills add <github-url> --skill <name>

# 一覧
npx skills list

# 更新（symlink なら git pull で済むが、明示的に走らせたい時）
npx skills update <name>

# 削除
npx skills remove <name>
```

> 💡 詳細サブコマンドは `npx skills --help` で最新を確認。

---

## 5. 運用上のコツ

### 5-1. Project スコープの skill は `.gitignore` に入れない

`.claude/skills/` を gitignore に入れてしまうとチーム間で共有できない。**Project スキルは積極的にコミット**するのが正解。

### 5-2. `.env` はスキルフォルダに直接置く

API キーが必要なスキル（content-post / ai-image-gen 等）は、スキルフォルダ直下の `.env` に書く。Claude Code はそれを自動で読み込む。

### 5-3. Symlink で入れた後の自作改造は upstream に PR

Symlink なので skill フォルダを直接編集するとリポジトリに変更が出る。気に入ったら upstream に PR する文化が望ましい。

---

## 6. 類似ツールとの比較

| ツール | 特徴 | skill.sh との違い |
|--------|------|-------------------|
| **手動 clone** | 直接 `~/.claude/skills/` に置く | 全部自分でやる。複数ツール対応・スコープ管理がない |
| **npm install** | npm パッケージとして配布 | npm レジストリ経由なので公開ハードルが高く、Claude Code 専用機能（hooks 等）と相性が悪い |
| **skill.sh** | GitHub 直接 + 対話インストール | Claude Code / Cursor / Windsurf を横断、Global/Project 切替、Symlink/Copy 選択 |

---

## 7. 向いてる / 向いてない

**向いてる**
- 公開スキルを試したい / 自作スキルを配布したい
- Claude Code と Cursor 両方で使うチーム
- Global と Project でスコープを切り分けたい
- Symlink で複数環境に同一バージョンを保ちたい

**向いてない**
- ネット接続なしのオフライン環境（npm レジストリ + GitHub に到達できる必要あり）
- 完全プライベートな社内専用パッケージレジストリで配布したい場合（GitHub Enterprise 等は対応するが要設定）

---

## 8. 関連リンク

- [skill.sh 公式](https://skill.sh)
- [Claude Code Skills 公式ドキュメント](https://docs.claude.com/en/docs/claude-code/skills)
- 関連記事: [【5分でできる】Claude Code × Vercel AI Gateway で「画像生成スキル」を作って、最新モデルを学習コストゼロで使い回す](/articles/claude-code-vercel-ai-gateway-image-generation)
- 関連ナレッジ: [Vercel AI Gateway とは — 1本のキーで全AIプロバイダを横断する統一ゲートウェイ](/knowledge/vercel-ai-gateway-unified-access)
