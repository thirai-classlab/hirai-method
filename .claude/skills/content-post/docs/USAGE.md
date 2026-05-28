# content-post 使い方ガイド

ClassLab. Weekly News への投稿スキルの CLI リファレンス + RAG 挙動解説 + コンテンツポリシー + 月次バッチ運用ガイド。

> **正ソースは CLI 自身**: フラグの最新仕様は必ず `npx tsx scripts/post.ts --help` で確認してください。このドキュメントは補助的な解説です。

## 目次

1. [設計思想](#設計思想)
2. [投稿モード一覧](#投稿モード一覧)
3. [draft → publish フロー](#draft--publish-フロー)
4. [frontmatter 規約](#frontmatter-規約)
5. [Markdown リンク記法](#markdown-リンク記法)
6. [コードブロック言語指定ガイドライン](#コードブロック言語指定ガイドライン)
7. [LLM モデル使い分け](#llm-モデル使い分け)
8. [画像処理（S3 + CloudFront）](#画像処理s3--cloudfront)
9. [サムネイル生成ポリシー（#32）](#サムネイル生成ポリシー32)
10. [本文内 解説画像 生成ポリシー](#本文内-解説画像-生成ポリシー)
11. [RAG 機能の挙動](#rag-機能の挙動)
12. [月次バッチの運用](#月次バッチの運用)
13. [version 管理（#41）](#version-管理41)
14. [よくあるエラーと対処](#よくあるエラーと対処)

---

## 設計思想

### 1. 日本語コンテンツは「本文も画像も完全日本語」が大原則

ClassLab. Weekly News は **日本語読者向け** の技術メディアである。日本語の本文を書いている時点で、対象読者は日本語UI・日本語ドキュメントで業務をしている。よって以下を **すべての投稿で必ず守る**:

- **本文内の用語は日本語版プロダクトUI公式表記** に揃える
  - Salesforce: `Closed Won` → 受注、`Page Layout` → ページレイアウト、`Validation Rule` → 入力規則
  - 日本語UIに公式訳がある用語は必ず日本語化（独自訳ではなく **公式訳** を調べる）
  - 用語辞書は記事カテゴリ別に `drafts/<topic>-glossary.md` として整備する
- **画像内のテキストも完全日本語**
  - ラベル・見出し・説明文・吹き出し・矢印注釈すべて日本語
  - 「日本語UIに公式訳がある英語をあえて画像に英字で残す」のは原則禁止（学習価値より混乱コストが上回る）
- **例外として英字を維持してよいのは固有名詞のみ**
  - プロダクト・サービス名: `Salesforce`, `Apex`, `Lightning`, `Trailhead`, `AWS S3`
  - API参照名・関数名・コード値: `Property__c`, `Stage__c`, `ISPICKVAL()`, `RecordType.DeveloperName`
  - 略号・規格名: `CSV`, `OWASP`, `RAG`, `MoE`, `__c`, `__x`
  - リリース名・エディション名: `Spring \'20`, `Enterprise Edition`
- **コード/数式内の API値 (`"Closed Won"` 等) は維持**
  - DBに保存されている値そのものなので、日本語化すると間違い
  - 説明文では「フェーズが受注になったら」、コード例では `ISPICKVAL(Stage__c, "Closed Won")` と使い分ける

### 2. 一般名詞・動詞・見出しの英訳併記は冗長

- ❌ `INPUT` / ✅ 入力
- ❌ `WHO WRITES WHAT` / ✅ 誰が書くか
- ❌ `所有者（Owner）` 連発 / ✅ 初出のみ「所有者」、以後単独表記
- ❌ 図中ラベル `Profile` / ✅ プロファイル

### 3. 内容（情報構造）と表現（テイスト）は分離する

画像を再生成する場合:
- **内容（何を伝える図か）** = 元の設計を維持する。改善する場合は事前に確認
- **表現（テイスト・色・フォント）** = 自由に変えてよい
- 「テイストだけ参照、中身は元のまま」がリファクタの基本

### 4. 公開記事の編集は「投稿後検証」で完結させる

- `post.ts --update --slug <slug>` で再投稿
- 画像は SHA-256 ハッシュが変われば自動で新キーで CDN にアップロード、旧キーを CloudFront で invalidate
- 公開URLを開いて目視確認するまでが1タスク

---

## 投稿モード一覧

`scripts/post.ts` は複数の動作モードを持つ。対象は `--file` (単一) または `--batch` (glob)。

### 1. 対話モード（デフォルト）

```bash
npx tsx scripts/post.ts --file ./draft.md
```

挙動:

1. frontmatter 検証 → Markdown → HTML 変換
2. slug 自動生成、embedding 生成
3. 重複検知 (`search_similar > 0.90` で block、`0.80-0.90` で警告)
4. カテゴリ / タグ候補を提示 → **ユーザーに y/n/edit 確認**
5. 確認が取れたら `POST /api/ingest` 経由で INSERT → 関連紐付け → 本文リンク挿入 → revalidate（augment-post Edge Function が非同期処理）

初投稿で運用フローを確認する場合はまずこのモード。**投稿は常に draft（非公開）で完了する**。公開には `--publish` か `scripts/publish.ts` を使う（後述）。

### 2. `--auto-approve`（CI / バッチ用途）

```bash
npx tsx scripts/post.ts --file ./draft.md --auto-approve
```

対話プロンプトをすべて「Y」として扱う。候補の信頼度が低くても承認されるため、`--batch` との組み合わせか、事前に `--dry-run` で確認済みのドラフトでのみ使うこと。

### 3. `--dry-run`

```bash
npx tsx scripts/post.ts --file ./draft.md --dry-run
```

全段階（validate / render / slug / embedding / duplicate / NER / category+tag 提案）を実行するが、**DB への INSERT/UPDATE/UPSERT/RPC は一切行わず、revalidate も呼ばれない**。何が起きるか確認するのに使う。

### 4. `--update --slug <slug>`

```bash
npx tsx scripts/post.ts --file ./updated.md --update --slug my-existing-article
```

既存レコードの `title` / `body` / `html` を差し替える。embedding は再生成して upsert する。カテゴリ / タグ / 関連紐付けは保持される（update モードでは再評価しない）。監査ログの `mode` は `update` で記録される。

> `--update` モードのみ Supabase 直接 UPDATE（`POST /api/ingest` を経由しない）。これは #41 snapshot/version パイプライン保護のため。

slug が存在しない場合は exit 1。事前 snapshot で本番データ喪失を防ぐ仕組みは「version 管理」セクション参照。

### 5. `--batch <glob>`

```bash
npx tsx scripts/post.ts --batch \'./drafts/2026-04-*.md\' --auto-approve
```

glob にマッチしたファイルを順次投入する。1 件失敗しても全体は継続する仕様（exit 0 で最後に `N ok / M failed / T total` のサマリを stdout に出す）。

### 主要フラグ早見表

| フラグ | 説明 |
| --- | --- |
| `--file <path>` | 単一 Markdown 投稿（必須 or `--batch`） |
| `--batch <glob>` | glob で複数投稿 |
| `--dry-run` | DB / revalidate を呼ばない |
| `--auto-approve` | 対話プロンプトをすべて承認 |
| `--update` | 既存更新モード（`--slug` と併用） |
| `--slug <slug>` | update 対象の slug |
| `--force` | duplicate=block でも投稿（exit 3 の回避） |
| `--verbose` | 詳細ログ（各段階の to/from 情報を逐次 stdout へ） |
| `--no-revalidate` | revalidate を呼ばない（DB 投入のみテストしたいとき） |
| `--no-link-check` | 本文の外部 URL 到達性チェックを skip |
| `--link-check-strict` | 壊れた外部リンクが 1 件でもあれば exit 5 で中断 |
| `--publish` | INSERT 後に POST /api/publish を呼んで公開する（draft → published） |
| `--no-auto-knowledge` | Stage 6+ の未知語自動ナレッジ生成をスキップ |
| `--auto-knowledge-publish` | 自動生成ナレッジも本体と同時に publish する |
| `--no-thumbnail-hearing` | サムネイル生成を完全 skip（thumbnail_url=null で投稿） |

### 終了コード

| code | 意味 |
| --- | --- |
| 0 | 成功（revalidate 失敗は warning のみ、exit は 0） |
| 1 | 環境変数欠損 / 引数不正 / validate 失敗 / update 対象なし |
| 2 | 未知の実行時エラー（#41 以降は `--update` snapshot 失敗で exit 2 強制中断） |
| 3 | duplicate=block かつ `--force` なし |
| 5 | リンクチェックで broken 検出（`--link-check-strict` 時のみ） |

---

## draft → publish フロー

投稿はデフォルトで **draft**（`published_at = NULL`）として保存される。公開するには `--publish` フラグか `scripts/publish.ts` を使う（Task #33 W4 以降）。

### 投稿時に同時公開

```bash
# 前提: .env に BATCH_SECRET と INGEST_SECRET を設定
npx tsx scripts/post.ts --file ./draft.md --auto-approve --publish
npx tsx scripts/post.ts --file ./draft.md --auto-approve --publish --no-auto-knowledge
```

### プレビュー確認後に公開

```bash
# 1. draft 投稿
npx tsx scripts/post.ts --file ./draft.md --auto-approve

# 2. プレビュー確認: https://classlab-weekly-news.vercel.app/preview/knowledge/<slug>

# 3. 単体公開
npx tsx scripts/publish.ts --slug <slug> --type knowledge

# 4. pending 一覧
npx tsx scripts/publish.ts --pending --type tech_article

# 5. pending 一括公開
npx tsx scripts/publish.ts --pending --type tech_article --confirm
```

### frontmatter 予約公開

`published_at: "2026-05-01T09:00:00.000Z"` を frontmatter に設定すると INSERT 時にその日時で公開済みとしてマークされる。省略時は NULL（draft）。

---

## frontmatter 規約

frontmatter 必須は `title` / `type` / `author`。`type` は `knowledge` / `tech_articles` / `weekly_issues` のいずれか。`content-templates/<type>.yaml` の `required_fields` も参照。

### weekly_issues（週間ニュース）

- `title` は全角カッコ「（）」+ 全角波ダッシュ「〜」で
  `週間ニュースまとめ（YYYY年M月D日〜M月D日）` 形式に統一する
- **本文先頭に `# h1` を書かない**。サイト側のページヘッダが
  frontmatter.title から記事タイトルを描画するため、本文側に同じ h1 を
  置くと記事ヘッダ直下にもう一度同じタイトルが出て二重表示になる。本文の
  最初の見出しは `## 目次` などの h2 から開始する
- `period_start` / `period_end` を ISO 日付 `YYYY-MM-DD` で指定する。
  `weekly_issues.period_start` / `period_end` カラムへ UPSERT される。
  省略すると `scripts/post.ts` は現在日時をフォールバックとして書き込むため、
  期間表示が壊れる

例:

```yaml
---
title: "週間ニュースまとめ（2026年4月14日〜4月21日）"
type: "weekly_issues"
author: "平井拓真"
period_start: 2026-04-14
period_end: 2026-04-21
---

## 目次

...
```

テンプレート詳細は `~/work/雑務/.claude/skills/weekly-news/skill.md`
（原稿生成エージェント側）を参照。

---

## Markdown リンク記法

### インラインリンク（現状維持）

本文中に書いた `[テキスト](https://example.com)` は通常の `<a>` タグとして出力される。

```md
詳細は [Supabase Docs](https://supabase.com/docs) を参照。
```

```html
<a href="https://supabase.com/docs" class="rich-source-link" target="_blank" rel="noopener noreferrer">Supabase Docs</a>
```

### リンクカード（URL 単独行）

段落が **URL 1 行のみ**（前後空行で囲まれ、URL 以外なし）の場合、リンクカードとして出力される。

```md
前の段落

https://example.com/article

次の段落
```

```html
<div class="link-card" data-url="https://example.com/article">https://example.com/article</div>
```

- `http://` も `https://` も対象
- `data-url` 属性に URL を保持（サイト側 CSS / JS で OG カードに昇格、Wave #39 W3 以降）
- 相対 URL や `[text](url)` 形式（text ≠ url）はインラインリンクのまま

---

## コードブロック言語指定ガイドライン

Markdown のコードフェンスには **必ず言語を指定** すること。本リポ classlab-weekly-news 側でシンタックスハイライト（shiki + catppuccin-mocha）と言語ラベル + コピーボタンが付加される（Task #48）。言語未指定でも data-raw は出力されるが、ハイライトと言語ラベルが付かないため読者体験が低下する。

### 完全対応言語リスト

#### プログラミング言語

| 言語 | フェンス指定 |
|:---|:---|
| TypeScript | `typescript` / `ts` |
| JavaScript | `javascript` / `js` |
| TSX / JSX | `tsx` / `jsx` |
| Python | `python` / `py` |
| Ruby | `ruby` / `rb` |
| PHP | `php` |
| Java | `java` |
| Kotlin | `kotlin` / `kt` |
| Swift | `swift` |
| Dart | `dart` |
| Go | `go` |
| Rust | `rust` / `rs` |
| C | `c` |
| C++ | `cpp` / `c++` |
| C# | `csharp` / `cs` |
| Scala | `scala` |
| Elixir | `elixir` / `ex` |
| Haskell | `haskell` / `hs` |
| Lua | `lua` |
| R | `r` |
| Salesforce APEX | `apex` |

#### シェル / コマンド

| 言語 | フェンス指定 |
|:---|:---|
| Bash | `bash` / `sh` / `shell` |
| Zsh | `zsh`（→ `bash` 扱い） |
| Fish | `fish`（→ `bash` 扱い） |
| Terminal | `terminal`（→ `shell` 扱い） |
| PowerShell | `powershell` / `ps` / `ps1` |
| Windows バッチ | `batch` / `cmd` |

#### データ / 設定 / DB

| 言語 | フェンス指定 |
|:---|:---|
| JSON | `json` |
| YAML | `yaml` / `yml` |
| TOML | `toml` |
| XML | `xml` |
| INI | `ini` |
| CSV | `csv` |
| SQL | `sql` |
| PL/SQL | `plsql`（→ `sql` 扱い） |

#### Web / UI

| 言語 | フェンス指定 |
|:---|:---|
| HTML | `html` |
| CSS | `css` |
| SCSS | `scss` |
| Sass | `sass` |
| Less | `less` |
| Vue | `vue` |
| Svelte | `svelte` |
| Astro | `astro` |

#### インフラ / DevOps

| 言語 | フェンス指定 |
|:---|:---|
| Dockerfile | `dockerfile` |
| Nginx | `nginx` |
| Apache | `apache` |
| Terraform / HCL | `hcl` / `terraform` |

#### ドキュメント

| 言語 | フェンス指定 |
|:---|:---|
| Markdown | `markdown` / `md` |
| MDX | `mdx` |
| LaTeX | `latex` |
| AsciiDoc | `asciidoc` |

#### その他

| 言語 | フェンス指定 |
|:---|:---|
| Diff | `diff` |
| Regex | `regex` |
| GraphQL | `graphql` |
| Protobuf | `protobuf` |
| Makefile | `makefile` |
| CMake | `cmake` |

#### 特殊（専用デザイン）

| 言語 | フェンス指定 | 備考 |
|:---|:---|:---|
| Claude Code | `claude-code`（alias: `claude` / `claude-prompt` / `cc`）| 黒背景 `#0a0a0a` + 白枠 1px + `❯` プロンプト。Claude Code 実物模写、ハイライトなし。**`<prompt>` / `<output>` タグで構造化必須**（後述） |
| Mermaid | `mermaid` | 別パイプラインで render |
| PlantUML | `plantuml` | 別パイプラインで render |

### 使い分けガイド

- **CLI 操作例**: `bash` / `terminal` を使用（シンタックスハイライト付き、`npm install` / `git commit` 等）
- **Claude Code 画面**: `claude-code` を使用（実物模写、ハイライトなし、スクリーンショット代わり）
- **Salesforce 関連**: `apex` を使用
- **PowerShell**: `powershell` / `ps` / `ps1` どれでも OK（自動展開）
- **言語不明 / プレーン**: 必ず `text` か `plaintext` を指定（空フェンス禁止）

### Claude Code ブロック (構造化必須・Wave 48.7)

`claude-code` 言語ブロックは **`<prompt>` `<output>` タグで構造化** する。プロンプト行（`❯` 白枠囲み）と出力行（プレーンテキスト）が視覚的に分離され、実 Claude Code UI を模写する。

````markdown
```claude-code
<prompt>このプロジェクトを reviewer エージェントでレビューしてください</prompt>
<output>レビュー開始...
✓ 完了しました</output>
```
````

- **複数交互可**: `<prompt>` `<output>` `<prompt>` `<output>` ... と並べると順序通りに分割される
- **タグなしの旧記法**は `<output>` 扱い + `console.warn` で警告（後方互換、新規記事では推奨しない）
- **HTML escape は自動**: タグ内テキストの `<` / `>` / `&` は雑務側で escape されるため、生のまま書いて OK
- **エイリアス**: `claude` / `claude-prompt` / `cc` も同等の構造化
- **出力 HTML**: `<div class="claude-line claude-line--prompt">` / `<div class="claude-line claude-line--output">` でサイト側 CSS が適用される

### 必須ルール

1. **空フェンスは使用禁止** — 必ず言語名を書く
2. **慣用エイリアスを優先** — `ts` / `sh` / `yml` などは shiki 側で自動展開される
3. **新言語追加時** は本リポ `src/lib/highlight.ts` の `SHIKI_LANGS` と `LANG_ALIAS` を確認
4. **`claude-code` は `<prompt>` / `<output>` タグで構造化** — 旧記法は警告 + 後方互換扱い

### data-raw 仕様（投稿側 → サイト側 契約）

`renderer.code()` は `<pre>` に以下の属性を付与する。サイト側 `CodeBlockEnhancer` がこれをデコードしてコピーボタンに渡す。

- `data-lang="<言語名>"` — 言語未指定時は属性なし
- `data-raw="<encoded>"` — コードの raw テキスト
- `data-raw-encoding="url"` — `<500 char` は `encodeURIComponent`
- `data-raw-encoding="base64"` — `>=500 char` は UTF-8 base64

詳細は本リポ `docs/task-48-code-block-enhancement-design.md` §C.4。

---

## LLM モデル使い分け

- **Haiku** (`claude-haiku-4-5`): 自動タグ / NER / slug 生成 / カテゴリ候補
- **Sonnet** (`claude-sonnet-4-6`): 自動リンク判定（曖昧時）/ WebSearch 要約 / 関連紐付け LLM 判定
- **OpenAI** (`text-embedding-3-large` / 1024 次元): embedding 専用

すべて Vercel AI Gateway 経由で呼び出し、月額 spending limit（$10）を設定。

---

## 画像処理（S3 + CloudFront）

markdown 内のローカル画像は自動的に AWS S3 にアップロードされ、CloudFront 経由で配信される。**サムネイル・本文画像ともに 16:9 にトリミングされる**（既に 16:9 ± 1% なら無加工）。

### 16:9 自動 center-crop (Wave aspect-letterbox-1)

`src/lib/image-processor.ts#processMarkdownImages` は S3 アップロード前に各画像を **macOS の `sips` で center-crop（中央切り抜き方式）で 16:9 に揃える**。挙動:

- 既に 16:9 ± 1% → 無加工
- SVG / GIF など対応外フォーマット → 無加工
- macOS 以外 → 1 度警告して以降スキップ（CI で実行する場合は注意）

> **方針**: 黒帯を加える letterbox は本文中で余白が目立つため、center-crop に統一。AI 生成時に「中央 70% に主要要素、上下 18% 余白」を担保することで端部見切れリスクを最小化する。

**生成時に「中央 70% に主要要素、上下に 18% 余白」を担保するため、`ai-image-gen` 側で `--aspect 16:9` を使うのが推奨**。プロンプトに余白指示が自動追記される。

```bash
# 推奨パス: 生成時から 16:9 設計
cd ~/.claude/skills/ai-image-gen
node scripts/gen.mjs generate "<プロンプト>" \
  --model openai/gpt-image-2 --aspect 16:9 \
  --out ~/work/雑務/.claude/skills/content-post/drafts/images/<slug>
```

### 動作

1. `runOne` が slug を決定した直後、`src/lib/image-processor.ts#processMarkdownImages` が原稿内の `![alt](./path)` を走査
2. ローカルファイルを読み、S3 key `<contentType>/<slug>/<sha256[0..8]>-<filename>` でアップロード
3. markdown の path を CloudFront URL に置換
4. 置換後の markdown で parse + render を再実行し、embedding・重複チェック・永続化される HTML すべてに CDN URL が反映

### 必要 env

`docs/SETUP.md` の AWS_* / CLOUDFRONT_* 参照。IAM user は本リポと共通の `classlab-weekly-news-uploader`。AWS credential が揃っていないと AWS SDK 呼び出しが失敗するが、`runOne` は `try/catch` で握り潰し警告のみ出力する（パイプライン停止しない）。

### スキップ条件

- `http(s)://` から始まる URL（外部 CDN で配信済み扱い）
- `data:` URL（インライン base64 画像）
- ローカルファイル不存在（markdown は書き換えず次の画像へ）
- `--dry-run` モード（S3 書き込みは一切行わない）

### --update モード

1. 既存 row の `body`（HTML）から CloudFront URL を抽出
2. 新しい画像を S3 upload 後、旧パスを `invalidateCloudFront` で CloudFront キャッシュから削除
3. 新画像と旧画像のハッシュが同一なら S3 上で同 key 上書き（invalidation は idempotent）

invalidation 失敗はパイプラインを止めず警告のみ。

---

## サムネイル生成ポリシー（#32）

ClassLab. Weekly News のサムネは **16:9 (1536×864)** に統一する。生成は
`scripts/gen-news-thumbnail.mjs` (gpt-image-2 + Haiku シーン抽出 + sharp 上端
16:9 クロップ) を child_process 経由で呼び出す。スキル内 self-contained で、
本リポ classlab-weekly-news への依存はない。

### 動作モード

| frontmatter.thumbnail | コンテンツタイプ | 挙動 |
|----------------------|------------------|------|
| 指定済み (ローカル/URL) | 任意 | ヒアリング skip → 既存パスで S3 upload (#30) |
| 未指定 | `weekly_issues` | ヒアリング skip → `categories.weekly_issues.patterns` を自動生成 (現状 T394 固定 1 枚) |
| 未指定 | `tech_articles` / `knowledge` | 対話ヒアリング (b: パターン → c: タイトル/見出し → d: スタイル) → 生成 → 承認ループ |
| 未指定 | 任意 + `--auto-approve` | ヒアリング skip → デフォルトパターン 1 件で生成 |
| 未指定 | 任意 + `--dry-run` | ヒアリングは行うが spawn しない (DB/S3 反映なし) |
| 未指定 | 任意 + `--no-thumbnail-hearing` | サムネ生成完全 skip (thumbnail_url=null で投稿) |

### 承認ループ (対話モード)

生成完了後に 4 択を提示:

- `y` (Enter) — 採用 → frontmatter.thumbnail に書き戻して S3 upload (#30) パスへ
- `r` — 同じヒアリング項目で再生成
- `p` — パターン選択からやり直し
- `n` — スキップ (採用しない、thumbnail_url=null)

### 必要 env

| 変数 | 必須? | 説明 |
|------|-------|------|
| `CLASSLAB_WEEKLY_NEWS_DIR` | 任意 | postinstall でのテンプレ同期にのみ必要、thumbnail 生成には不要 |
| `AI_GATEWAY_API_KEY` | 必須 | Haiku シーン抽出 + gpt-image-2 呼び出し。`~/.claude/skills/ai-image-gen/.env` から自動ロード（グローバル昇格済み） |

### パターンカタログ

- 定義: `scripts/thumbnail-patterns.json` (v2.0、スキル内 self-contained)
- `categories.<type>.patterns` にコンテンツタイプ別の許可リスト
- `patterns.<id>.category_lock` で別カテゴリへの誤用を防止 (例: T394 は `weekly_issues` 専用、K-* は `knowledge` 専用)
- 新パターン追加時はコード変更不要 — JSON 編集のみで反映

#### コンテンツタイプ別 テーマ方針

| カテゴリ | パターン | 視覚テーマ |
|---|---|---|
| `weekly_issues` | `T394` | 16-bit pixel-art RPG diorama (週刊ニュース固定) |
| `tech_articles` | `T363` / `T364` | Bento Grid (modern / structured) / Swiss International Minimalist。記事ごとにパターン選択でテーマが変わる |
| `knowledge` | `K-HERO` / `K-INLINE` / `K-OUTRO` | **claude-image-pkg 共通テーマ統一**: Isometric 2.5D vector / Stripe-Vercel marketing illustration / ivory beige + dotted grid / multi-pastel (sage green primary, peach, lavender, mustard yellow, dusty blue) / Noto Sans JP Bold 日本語タイポ。3 パターンは「用途別種別」のみ違う (hero / inline / outro)。テーマは `~/cc研修/claude-image-pkg/IMAGE-PLAYBOOK.md` を踏襲 |

**重要**: weekly_issues / tech_articles はパターン自体がテーマを定義する（例: T394 = pixel-art、T363 = bento）。ナレッジは逆で、3 パターン共通の Isometric 2.5D テーマを用途別 (hero=入口キービジュアル / inline=単発フォーカス / outro=ふりかえり) で使い分ける。

#### ナレッジ用 3 パターン

| パターン | 用途 | 構図 |
|---|---|---|
| `K-HERO` | 概念解説 / 全体像紹介 / シリーズ起点 | 中央メタファー + LEFT サイド (checklist / donut / hint) + RIGHT サイド (bullets / mini table) + 周辺小物 |
| `K-INLINE` | 単発トピック / 手順解説 / 図解中心 | 中央メタファーを大きく単独配置、サイドパネル最小 or なし |
| `K-OUTRO` | シリーズ完結 / Q&A まとめ / 振り返り | 中央メタファー (ミニ再掲) + 完了バッジ (sage green リボン) + 学んだことチェックリスト + 次のステップ + 紙吹雪 |

ヒアリング時のデフォルトは先頭の `K-HERO`。パターン番号 (1/2/3) または ID 直接入力で切り替え可能。

#### AI 自動選択 (Wave thumbnail-auto-select)

カテゴリ内に 2 つ以上のパターンが登録されている場合 (knowledge は 3、tech_articles は 2)、**`--auto-approve` または対話モードの Enter (空入力) で AI Gateway 経由の Haiku が記事メタデータからパターンを自動選択する**:

- 入力: `title` / 見出し (h1/h2) / 本文先頭 1200 文字
- 出力: `K-HERO` / `K-INLINE` / `K-OUTRO` (knowledge) または `T363` / `T364` (tech_articles) のいずれか 1 つ
- モデル: `thumbnail-patterns.json` の `llm_model` (デフォルト `anthropic/claude-haiku-4.5`)
- フォールバック: API キー欠落 / ネットワーク失敗 / 候補外応答 → 先頭 `default_count` 件 (knowledge なら `K-HERO`)

ログ例:
```
[thumbnail] AI 自動選択: pattern=K-INLINE (候補 K-HERO,K-INLINE,K-OUTRO)
```

意図しない選択が出たら、`--no-thumbnail-hearing` で完全 skip、または対話モードで番号/ID を明示入力して上書きできる。

---

## 本文内 解説画像 生成ポリシー

サムネとは別に、本文中に挿入する解説画像（概念図 / 図解 / アイコン並列 など）を AI 生成する場合のルール。

### 言語ポリシー（必須・最重要）

> 上部「設計思想」と整合。**日本語の本文を持つ記事には、日本語の画像しか入れない**。

- **画像内のラベル・見出し・説明文・吹き出し・注釈はすべて日本語で書く**
- **本文に対応する用語は日本語UI公式訳を使う**（独自訳・カタカナ直訳ではなく公式訳を確認）
  - Salesforce: `Closed Won` → 受注 / `Page Layout` → ページレイアウト / `Validation Rule` → 入力規則 / `Owner` → 所有者
  - 不明な場合は公式ヘルプ（日本語版）または既存の日本語ドキュメントで確認してから生成
- **例外として英字を維持してよいのは固有名詞のみ**
  - プロダクト名: `Salesforce`, `Apex`, `Lightning`, `Trailhead`, `AWS S3`
  - API参照名: `Property__c`, `Stage__c`, `__c`, `__x`
  - 略号: `CSV`, `OWASP`, `RAG`, `MoE`, `FK`, `DB`, `M:N`
- **一般名詞・動詞・見出しは英訳せず日本語のまま**
  - ❌ `IMPORT` / ✅ インポート
  - ❌ `WHO WRITES WHAT` / ✅ 誰が書くか
  - ❌ ラベル `Profile` / ✅ プロファイル
  - ❌ サブラベル `(Automation)` / ✅ サブラベル不要、または日本語のみ

### 「英字残し」の判定フローチャート

画像にある英字を見たとき:

```
日本語UIに公式訳があるか？
├─ Yes → 日本語化必須（例: Page Layout → ページレイアウト）
└─ No
    ├─ プロダクト名・固有名詞か？     → 英字維持OK（例: Apex, Salesforce）
    ├─ API値・関数名・コード断片か？  → 英字維持OK（例: ISPICKVAL, "Closed Won"）
    └─ 一般名詞・動詞・形容詞か？     → 適切な日本語訳を当てる
```

### 取消線・装飾の落とし穴

- **「削除されるレコード」を表現するのに `<del>` / `text-decoration: line-through` は使わない** — テキスト全体に取消線がかかると判読不能になる
- 削除を表現したいなら: ❌ アイコン、🗑 アイコン、矢印 + 「親削除 → 子も削除」のような明示的なテキスト

### モデル選定

| モデル | 用途 | 日本語描画 | 備考 |
|--------|------|-----------|------|
| **`openai/gpt-image-2`** | **第一選択** | 安定 | テキスト混在画像はこれ |
| `bfl/flux-2-flex` | テキスト重視 | 良好 | gpt-image-2 で文字化けする時の代替 |
| `bfl/flux-2-pro` | 写実・スケッチ | 不安定 | 日本語ラベル多用画像では避ける |
| `recraft/recraft-v4-pro` | ロゴ・ベクター | 安定 | アイコン中心の図に強い |

- **第一選択は `openai/gpt-image-2`**。flux-2-pro は文字が混ざる / 隣接ボックスのラベルが合体する事故が多い
- どうしても flux 系の画風が欲しい場合のみ `--ref` で参照画像を渡しつつ flux を使う

### サイズ・トリミング

- gpt-image-2 のネイティブ対応サイズ: `1024x1024` / `1024x1536` / `1536x1024`
- 16:9 が必要なら `--size 1536x1024 --final-size 1536x864` で macOS `sips` center-crop 後処理
- **トリミング時に重要な情報が見切れないよう、画像端から最低 60-80px の安全マージンを確保**するプロンプトを書く（「すべての主要要素は中央 80% に収める」など明示）

### 文字混合防止のためのプロンプトコツ

gpt-image-2 でも複数の独立ラベルが隣接するレイアウトでは合体事故が起きる。プロンプトには以下を明記する:

- 「ボックス N に **1 つだけ** 〇〇 と書く」のように **個数を断定**
- 「隣接ボックスとの **間隔を十分に空ける**」「**ラベルが混ざらないように**」を明記
- 「**日本語のラベルのみ、英字は固有名詞のみ**」を末尾に必ず入れる

### 生成例（このスキルから直接呼ぶ場合）

```bash
# ai-image-gen の .env を読み込んで gpt-image-2 で生成
cd ~/.claude/skills/ai-image-gen
set -a && source .env && set +a
node scripts/gen.mjs generate "<日本語プロンプト>" \
  --model openai/gpt-image-2 \
  --size 1024x1024 \
  --out ~/work/雑務/.claude/skills/content-post/drafts/images/<slug>
```

生成後は `drafts/images/<slug>/` に出力されるので、原稿の markdown 内で `![alt](./images/<slug>/file.png)` として参照する。

---

## RAG 機能の挙動

投稿時に自動で走る 4 つの機能。設計書の該当ロジックを実装している。

> Phase 11 W11.3a 以降、本体 INSERT 後の embedding 生成 / 関連紐付け / 本文リンク挿入 / revalidate は **サイト側 augment-post Edge Function** が非同期で処理する。post.ts は ingestViaApi の応答を待って終了する。

### 1. 自動タグ付け（Haiku）

- 本文から Haiku がタグ候補を 3-6 個提案
- 既存マスタと trigram 類似度で照合、閾値未満は新規候補扱い
- 対話モードでは候補リスト + confidence を提示し、`[y/n/edit]` で確定

### 2. 関連ナレッジ自動紐付け

- 投稿完了後、embedding の cosine 類似度で上位 N 件を候補化
- 候補が 2 件以下 or 閾値以下なら LLM（Sonnet）に「関連性あり/なし/prerequisite/extends」を判定させる
- 結果は `knowledge_relations` (自己参照) に INSERT

### 3. 本文リンク自動挿入

- HTML パース後、既存ナレッジのキーワードを検索
- 単純一致はそのまま、曖昧（同名タグが複数候補）な場合のみ Sonnet でコンテキスト判定
- **コードブロック内はスキップ**、**同じキーワードへのリンクは初出のみ**
- `<a class="rich-link" data-content-id="...">` を差し込んで HTML を UPDATE

### 4. 未知語自動ナレッジ生成（depth=0 制限付き）

- NER（Haiku）で本文から固有名詞を抽出
- 各エンティティを `search_hybrid` で既存検索
- 既存にヒットすれば紐付け、ヒットしなければ:
  1. WebSearch で 2-3 ソース取得
  2. Sonnet で要約
  3. `knowledge` に `auto_generated=true` + `source_urls[]` で INSERT
  4. 親投稿から紐付け
- 再帰しない（`depth=0` 固定）: 子ナレッジ生成中にさらに未知語があっても追加生成はしない
- `--no-auto-knowledge` でスキップ可

### dry-run での RAG 挙動

`--dry-run` では **NER / category / tag / duplicate check すべて走る** が、INSERT / UPDATE / revalidate / auto-knowledge-gen の副作用は **一切発生しない**。提案内容は stdout に出力される。

---

## 月次バッチの運用

投稿精度を長期運用で維持するための 3 バッチ。月初など定期実行する想定。

### `feedback-learn.ts` — 編集履歴 → Few-shot 学習

```bash
npx tsx scripts/feedback-learn.ts
# オプション: --since <ISO 日時>（デフォルト 30 日前）
#          --dry-run（upsert しない）
```

過去 N 日の `content_edits_log` から編集を収集し、`tag_added` / `tag_removed` / `body_revised` / `category_changed` の 4 分類で bucketize。Haiku で Few-shot 例に圧縮して `prompt_few_shots` テーブルに upsert する。

**判断基準**: 毎月 1 日に実行。`--dry-run` で出力を見て違和感があればスキップ。

### `merge-duplicates.ts` — 重複統合候補レポート

```bash
npx tsx scripts/merge-duplicates.ts --threshold 0.92 --output ./reports/dup-$(date +%Y%m).md
# オプション: --type knowledge|tech_articles|weekly_issues
```

`content_embeddings` 全件の pairwise cosine similarity を計算し、閾値以上のペアを Markdown レポート化する。**DB は更新しない**（レビュー用）。

**判断基準**: レポートを見て、統合すべきペアが出たら手動で片方を削除または `knowledge_relations` に `same_as` で紐付ける。自動マージはしない（情報損失のリスク）。

### `merge-tags.ts` — タグエイリアス候補

```bash
npx tsx scripts/merge-tags.ts --threshold 0.85
# 適用: --auto（term_aliases テーブル scope=\'tag\' へ upsert）
```

`tags` テーブルの trigram 類似度を計算、高使用頻度のタグを canonical、低頻度を alias として候補化。`--auto` なしでは dry-run（レポートのみ）。

> **Note (Phase 11):** 旧 `tag_aliases` テーブルは `term_aliases (scope=\'tag\')` に統合済み。`--auto` 適用時は `term`, `canonical`, `canonical_tag_id`, `scope=\'tag\'` の 4 列を upsert する（`onConflict: term,scope`）。

**判断基準**: 月 1 回 `--dry-run` で確認、明らかに同義語のみ `--auto` で適用。微妙なケースは手動判断。

### スケジューラ運用例

- **macOS launchd / cron**: 毎月 1 日 09:00 に 3 本順次実行
- **GitHub Actions (manual)**: workflow_dispatch で手動トリガー
- **Vercel Cron**（サイト側リポから叩くなら）: `/api/monthly-rag-batch` ルートを別途作って投げる

スケジューラ側で `.env` を source できる環境か、`VERCEL_TOKEN` + 環境変数経由で実行できること。

---

## version 管理（#41）

`--update --slug <slug>` モードは過去に本番データ喪失事故（markdown source 由来 HTML が body 全体上書き → 元 HTML の image embed 消失）を起こした。Wave #41 以降、以下の安全機構が実装されている:

- **事前 snapshot**: UPDATE 前に既存 row の `body` / `html` / `thumbnail_url` を `content_versions` テーブルへスナップショット
- **snapshot 失敗で fail-safe**: snapshot が失敗した場合は post.ts が exit 2 で **強制中断**（DB UPDATE は 0 件）
- **S3 image rescue**: 旧 body の CloudFront URL を抽出し、新 body に同 CloudFront URL が含まれない場合は invalidation 前に S3 で別 key 退避

`--update` 利用時は事前に DB / S3 のバックアップが取られていることを期待しないこと。fail-safe は最低限のガードでしかない。

---

## よくあるエラーと対処

### `[post] required env missing: ...`

`.env` が空または読み込まれていない。`cp .env.example .env` + 実値を入れて、プロジェクトディレクトリで実行しているか確認。詳しくは [SETUP.md](./SETUP.md)。

### `[post] validate failed: - title: title is required`

frontmatter に `title` が無い。`type` / `author` も必須。`content-templates/*.yaml` の `required_fields` 参照。

### `[post] duplicate block (use --force to override): ...`

高類似度 (> 0.90) の既存コンテンツあり。本当に別記事なら `--force` で上書き。同じ記事を直したいなら `--update --slug <slug>`。

### `[post] update target slug not found: ...`

指定した `--slug` が DB に無い。`ls drafts/` で過去の slug を確認するか、`select slug from knowledge` で検索。

### `[post] revalidate failed (continuing): ...`

DB には入ったが ISR 再生成が失敗した状態。`SITE_URL` / `REVALIDATE_SECRET` を確認。サイト側の `/api/revalidate` が 5xx を返している可能性。サイトを直接確認してキャッシュが古ければ手動で revalidate を叩き直す。

### `content-templates/ が空 / ファイルがない`

`postinstall` が走っていない。`CLASSLAB_WEEKLY_NEWS_DIR` を export して `npm run sync` を実行。詳しくは [SETUP.md](./SETUP.md)。

### `[post] /api/ingest 401 Unauthorized`

`INGEST_SECRET` が本リポと一致していない。本リポ Vercel env と `.env` を比較。secret rotate 直後の場合は本リポ `docs/operations/secret-rotation.md` の同期手順を確認。

### AI Gateway が 400 / 402 を返す

- 400: embedding に空文字を渡している可能性 → body が空の投稿は弾かれる
- 402: Vercel AI Gateway のクレカ未登録 or spending limit 到達 → Vercel ダッシュボードで確認

### `[post] update snapshot failed (exit 2)`

#41 の fail-safe が発動。`content_versions` への snapshot INSERT が失敗したため UPDATE は 0 件で中断された。原因は service_role_key の権限不足 or `content_versions` テーブル不在。本リポ migration 適用状況を確認。

### その他

- `npx vitest run` でユニット + E2E が全通するか確認
- `npm run typecheck` で型エラーが出ないか確認
- 問題が継続する場合は `--verbose` を付けて実行し、stdout の各段階を確認
