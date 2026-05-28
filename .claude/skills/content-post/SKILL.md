---
name: content-post
description: ClassLab. Weekly News への記事投稿スキル (weekly_issues / tech_articles / knowledge)。markdown frontmatter から POST /api/ingest 経由で本リポに投入し、サムネイル生成 + augment-post Edge Function で embedding / 関連紐付け / 本文リンク / revalidate を非同期処理する。「記事を投稿」「ナレッジを追加」「weekly news を公開」「content-post」「ClassLab. サイトに投稿」「月次バッチを流す」などで起動する。
allowed-tools: Bash(npx tsx *), Bash(npm *), Bash(supabase *), Bash(cat *), Bash(ls *), Read, Write, Edit, Glob, Grep
---

# content-post スキル

Markdown ドラフトから ClassLab. Weekly News (`https://classlab-weekly-news.vercel.app`) への投稿までを一気通貫で実行する RAG 搭載スキル。

## Quick Start

```bash
cd ~/work/雑務/.claude/skills/content-post
export CLASSLAB_WEEKLY_NEWS_DIR=/Users/t.hirai/work/classlab-weekly-news
npm install                                  # postinstall でテンプレ + 型を同期
cp .env.example .env && $EDITOR .env         # AI_GATEWAY_API_KEY / INGEST_SECRET 等
npx tsx scripts/post.ts --file ./draft.md    # 対話モード（--auto-approve / --dry-run / --update --slug 等あり）
```

CLI フラグの **正ソースは `--help`**。docs は補助的な解説。

## 公開 URL パス（重要・憶測禁止）

投稿後の URL を user に伝える際は **必ず下表に従う**。frontmatter の `type` や内部 `kind` 値（`tech_article` 等の単数形）をそのまま URL path に使うとサイト側ルートが存在せず login redirect (307) になる。

| frontmatter `type` (＝ DB content_type) | 内部 `kind` 名 | 公開 URL | プレビュー URL |
|---|---|---|---|
| `tech_articles` | `tech_article` | `https://classlab-weekly-news.vercel.app/articles/<slug>` | `https://classlab-weekly-news.vercel.app/preview/articles/<slug>` |
| `knowledge` | `knowledge` | `https://classlab-weekly-news.vercel.app/knowledge/<slug>` | `https://classlab-weekly-news.vercel.app/preview/knowledge/<slug>` |
| `weekly_issues` | `weekly_issue` / `issue` | `https://classlab-weekly-news.vercel.app/issues/<slug>` | `https://classlab-weekly-news.vercel.app/preview/issues/<slug>` |

NG 例（過去に間違えた pattern、絶対に使わない）:
- ❌ `/tech-article/<slug>` ❌ `/tech_article/<slug>` ❌ `/tech_articles/<slug>` ❌ `/weekly_issues/<slug>` ❌ `/weekly-issues/<slug>` ❌ `/weekly/<slug>`
- ❌ `/preview/tech_article/<slug>` ❌ `/preview/tech-article/<slug>` ❌ `/preview/weekly_issues/<slug>`

URL を user 報告に含める場合は **上表のテンプレートを文字列置換で組み立てる**こと。`kind` や `type` から推測しない。

## mermaid → 画像 自動変換 (knowledge 専用・並列実行)

`content-type: knowledge` の記事に含まれる ` ```mermaid ` ブロックは、stage 04b でパイプライン中に **自動的に Isometric 2.5D 画像へ並列変換** され、本文の mermaid ブロックは `![alt](path)` に完全置換される。テーマは `~/cc研修/claude-image-pkg/IMAGE-PLAYBOOK.md` 準拠 (ivory beige + dotted grid + multi-pastel + Noto Sans JP)。

- `tech_articles` / `weekly_issues` では実行されない (mermaid は SVG レンダリングのまま)
- `--dry-run` でも skip (gpt-image-2 呼び出しを抑止)
- mermaid 構造は `flowchart` / `sequence` / `state` / `gantt` / `quadrant` / `mindmap` 等から 8 構造パターン (A 直線 / B 階層 / C 比較 / D 分岐 / E ハブ&スポーク / F グループ / G 循環 / H 並列) に分類してプロンプトを生成
- **並列実行が default**: `--concurrency` で並列数を指定可 (default 3、IMAGE-PLAYBOOK §5-2 では 6 が安定圏)
- **既存 PNG は自動 skip**: `mermaid-NN.png` が既に out-dir に存在すれば再生成しない (再投稿時の重複生成と無駄な API コールを抑止)
- **`--aspect 16:9` を必ず使う**: gen.mjs に `--final-size 1536x864` のみ渡すと default が letterbox になり「横方向に縮小 + 左右に白帯」される (1536x1024→1296x864→1536x864 padded)。`--aspect 16:9` ショートカットを使うことで `--final-mode crop` + safety-zone プロンプト注入が自動適用される。本スクリプトは内部で常に `--aspect 16:9` を渡している。新規に `gen.mjs` を呼び出す自作スクリプトを書くときは必ず同じ罠を踏まないこと
- スタンドアロンでも実行可能:
  ```bash
  node scripts/gen-mermaid-images.mjs \
    --file <md> --slug <slug> --out-dir <dir> --content-type knowledge \
    --in-place --concurrency 4
  ```

## 詳細ドキュメント / 関連リポ

- [`docs/SETUP.md`](./docs/SETUP.md) — 前提 / .env / postinstall / 初回投稿の最短手順 / トラブルシュート
- [`docs/USAGE.md`](./docs/USAGE.md) — モード / 設計思想 (日本語化) / frontmatter / リンクカード / コードブロック / 画像処理 (S3) / サムネイル (#32) / RAG / 月次バッチ / version 管理 (#41)
- 関連スキル: `~/work/雑務/.claude/skills/related-knowledge-create/` (Wave 11.3b-6)
- 本リポ: `docs/architecture-roles.md` / `docs/database-design.md` / `docs/operations/secret-rotation.md`
- mermaid 画像化のテーマ仕様: `~/cc研修/claude-image-pkg/IMAGE-PLAYBOOK.md`
