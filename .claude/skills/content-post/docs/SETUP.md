# content-post セットアップガイド

ゼロから初投稿までの最短手順。`.env` 作成 → 依存インストール → テンプレート同期 → 初回 dry-run → 本投稿。

## 前提

- Node.js ≥ 20（`engines.node` で enforce）
- 本リポ（`classlab-weekly-news`）を clone 済みで、Supabase が link 済み（`supabase link` 実行済み）
- Vercel AI Gateway のアカウントとクレジット登録済み（embedding/Haiku/Sonnet を AI Gateway 経由で呼び出すため必須）
- 本リポと共通の `INGEST_SECRET` / `BATCH_SECRET` / S3 credentials（後述）

## 1. 依存インストール

```bash
cd ~/work/雑務/.claude/skills/content-post
npm install
```

`npm install` 完了後に `postinstall` が自動で `scripts/postinstall.ts` を実行する（下記 §3 で詳述）。

## 2. 環境変数 (`.env`)

`.env.example` をコピーして実値を入れる:

```bash
cp .env.example .env
$EDITOR .env
```

### 必須変数

| 変数 | 取得元 | 備考 |
| --- | --- | --- |
| `SUPABASE_URL` | Supabase Dashboard → Project Settings → API | 本リポと同一プロジェクト `dlitnmseevxynwgpltcl` |
| `SUPABASE_ANON_KEY` | 同上 | RLS 越しの読み取り用 |
| `SUPABASE_SERVICE_ROLE_KEY` | 同上 (Reveal) | **スキル専用**、本リポには置かない。RLS をバイパス。`--update` モードで使用 |
| `AI_GATEWAY_API_KEY` | Vercel Dashboard → AI → Gateway | Haiku/Sonnet + `openai/text-embedding-3-large` (1024 次元) を AI Gateway 経由で呼び出す。`OPENAI_API_KEY` は不要 |
| `INGEST_SECRET` | 本リポ Vercel env | 新規投稿は `POST /api/ingest` 経由のため必須。本リポと同値。詳細は本リポ `docs/operations/secret-rotation.md` |
| `SITE_URL` | 本番 URL | `https://classlab-weekly-news.vercel.app` |
| `REVALIDATE_SECRET` | 本リポの Vercel env | 投稿後 ISR 再生成（augment-post Edge Function 側で利用） |

### 任意変数（用途別）

| 変数 | 用途 |
| --- | --- |
| `BATCH_SECRET` | `--publish` フラグで本リポ `POST /api/publish` を呼ぶときに必要。本リポ `BATCH_SECRET` と同値 |
| `CLASSLAB_WEEKLY_NEWS_API_URL` | デフォルト: `https://classlab-weekly-news.vercel.app`。preview 環境を叩く場合のみ上書き |
| `AWS_REGION` | デフォルト `ap-northeast-1`（画像処理用） |
| `AWS_S3_BUCKET` | デフォルト `classlab-weekly-news-content` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | 画像 S3 アップロードに必須。IAM user は本リポ共通の `classlab-weekly-news-uploader` |
| `CLOUDFRONT_DOMAIN` | デフォルト `d2f75plg0t6qwk.cloudfront.net` |
| `CLOUDFRONT_DISTRIBUTION_ID` | デフォルト `E19HM38I4166EC` |

> AWS credential が揃っていなくてもパイプラインは止まらない（warning のみ、画像はローカルパスのまま）。S3/CloudFront 関連の詳細は `docs/USAGE.md` の「画像処理」を参照。

> `.env` は gitignore 済み。`SUPABASE_SERVICE_ROLE_KEY` / `INGEST_SECRET` / `BATCH_SECRET` / `AWS_*` を誤ってコミットしないこと。secret ローテーション手順は本リポ `docs/operations/secret-rotation.md`。

### `.env` の読み込み

`scripts/post.ts` 冒頭で `import "dotenv/config"` しているため、カレントディレクトリの `.env` を自動で読む。別ディレクトリから実行する場合は `dotenv -e /path/to/.env -- npx tsx ...` 等で明示。

## 3. テンプレート同期 (postinstall)

本リポの `content-templates/*.yaml` と Supabase の型定義を、スキル側にコピーする。

```bash
export CLASSLAB_WEEKLY_NEWS_DIR=/Users/t.hirai/work/classlab-weekly-news

# npm install 時に自動実行されるが、テンプレート更新時は手動再実行も可
npm run sync
```

挙動:

- `content-templates/*.yaml` を本リポから `./content-templates/` へコピー（6 ファイル）
- `supabase gen types typescript --linked > src/types/database.ts`（CLI が PATH にあれば）
- 2 回目以降は内容ハッシュで差分検出 → 変更ないファイルは `skip` でログ

`CLASSLAB_WEEKLY_NEWS_DIR` が未設定の場合は warning のみ出して exit 0（`npm install` を止めない）。

## 4. サニティチェック

```bash
# CLI のフラグと help 出力を確認
npx tsx scripts/post.ts --help

# テスト一式が通るか
npx vitest run

# 型チェック
npm run typecheck
```

すべて通れば準備完了。

## 5. 初回投稿の最短手順

### 5-1. ドラフトを用意

適当なディレクトリに Markdown を置く:

```markdown
---
title: "Cache Components Gotchas"
type: "knowledge"
author: "平井拓真"
---

# Next.js 16 Cache Components 導入時にハマった点

本文...
```

frontmatter 必須は `title` / `type` / `author`。`type` は `knowledge` / `tech_articles` / `weekly_issues` のいずれか。詳細仕様は `docs/USAGE.md` の「frontmatter 規約」を参照。

### 5-2. dry-run で動作確認

```bash
npx tsx scripts/post.ts --file ./draft.md --dry-run --verbose
```

stdout に validate / slug / embedding / duplicate / category / tag / NER の各段階のログが出る。DB は更新されない。

### 5-3. 対話モードで本投稿

```bash
npx tsx scripts/post.ts --file ./draft.md
```

カテゴリとタグの候補が出たら確認して `Y` を押す。投稿は **デフォルト draft（非公開）** で完了する。プレビュー確認後に公開するには `scripts/publish.ts` を使う:

```bash
# プレビュー
open https://classlab-weekly-news.vercel.app/preview/knowledge/<slug>

# 単体公開
npx tsx scripts/publish.ts --slug <slug> --type knowledge
```

draft → publish フローの詳細は `docs/USAGE.md` の「投稿モード一覧」参照。

## 6. 開発（テスト + typecheck）

```bash
npm run test          # vitest run
npm run test:ui       # vitest UI モード
npm run typecheck     # tsc --noEmit
```

TDD 方針: `tests/` 下に対応する `.test.ts` を先に書いて RED を確認してから実装する。E2E は `tests/e2e/post-pipeline.test.ts` 参照。

## 7. 月次バッチのスケジューリング（任意）

`feedback-learn.ts` / `merge-duplicates.ts` / `merge-tags.ts` は月 1 回の定期実行を想定。詳しくは `docs/USAGE.md` の「月次バッチの運用」を参照。

## トラブル

セットアップで詰まった場合は `docs/USAGE.md` の「よくあるエラーと対処」を確認。
