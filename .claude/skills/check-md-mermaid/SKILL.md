---
name: check-md-mermaid
description: Markdown ファイル内の ```mermaid``` ブロックを mermaid@11.13.0 のパーサーで構文検証する。.md/.mdx を作成・編集した直後に PostToolUse フックで自動実行されるが、手動でディレクトリ全体を検査したい場合にも使用する。
---

# Mermaid Markdown Syntax Check

`.md` / `.mdx` ファイル内のすべての ```mermaid``` フェンスコードブロックが mermaid@11.13.0 でパースできることを検証する。

## When to use

- `.md` / `.mdx` を編集・作成した直後（PostToolUse フックで自動実行）
- 既存ドキュメント全体の構文監査（CI 前ゲート）
- Mermaid 図が本番で表示されない原因調査

## Run

```bash
npx --yes --package=mermaid@11.13.0 --package=jsdom node \
  .claude/scripts/check-md-mermaid.mjs "<glob>" [<glob> ...]
```

例:
- `... "docs/**/*.md"` — docs 配下全体
- `... path/to/single.md` — 単一ファイル
- `... "docs/**/*.md" "**/*.mdx"` — 複数 glob

## Exit codes

| code | 意味 |
|:----:|:----|
| 0 | すべてのブロックがパース成功 |
| 1 | 1 つ以上のブロックでパース失敗（file:line と原因を stderr に出力） |
| 2 | セットアップエラー（mermaid / jsdom が import できない） |

## 仕組み

1. 引数の glob を `node:fs/promises` の `glob()` で展開（Node 22+）
2. ファイルから ```mermaid``` フェンスを抽出（行番号付き）
3. `mermaid.parse(code, { suppressErrors: false })` で 1 ブロックずつ検証
4. mermaid@11 は parse 中に `DOMPurify.addHook` を呼ぶため、jsdom で `window` / `document` / `navigator` 等を shim しておく

## Hooks 連携

`.claude/settings.json` の PostToolUse:`Edit|Write` で `.claude/hooks/check-md-mermaid.sh` が起動。

- 拡張子が `.md` / `.mdx` 以外なら即終了
- ファイル内に ```mermaid``` が無ければ即終了
- 失敗時は `decision: "block"` で Claude に修正を促す

## よくある構文エラー

- ノードラベルにスラッシュ: `API[/api/foo]` → `API["/api/foo"]` のようにクォート
- `flowchart` 内で日本語の `|` 区切りラベルにスペース欠落
- `subgraph` の閉じ忘れ
- 未対応ダイアグラムタイプ（バージョンによる差異）

## 関連

- スクリプト本体: `.claude/scripts/check-md-mermaid.mjs`
- フック: `.claude/hooks/check-md-mermaid.sh`
- 投稿側 fixture との同期: 必要に応じて姉妹リポにも同スクリプトをポート
