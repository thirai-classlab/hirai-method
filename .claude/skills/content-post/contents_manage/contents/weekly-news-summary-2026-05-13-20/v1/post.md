
## 目次

- [Hacker News 注目記事](#hacker-news-注目記事)
  - [1. Andrej Karpathy が Anthropic に参画](#1-andrej-karpathy-が-anthropic-に参画)
  - [2. Elon Musk が OpenAI / Sam Altman への提訴で敗訴](#2-elon-musk-が-openai--sam-altman-への提訴で敗訴)
  - [3. Simon Willison「直近6か月の LLM 動向を5分で」](#3-simon-willison直近6か月の-llm-動向を5分で)
  - [4. Files.md — Obsidian のオープンソース代替](#4-filesmd--obsidian-のオープンソース代替)
  - [5. Bitwarden の静かな全面リノベーション](#5-bitwarden-の静かな全面リノベーション)
  - [6. Apple、新アクセシビリティ機能群を発表](#6-applename新アクセシビリティ機能群を発表)
  - [7. Google 検索ボックスを刷新](#7-google-検索ボックスを刷新)
  - [8. OpenBSD 7.9 リリース](#8-openbsd-79-リリース)
  - [9. CISA 管理者が GitHub に AWS GovCloud キーを流出](#9-cisa-管理者が-github-に-aws-govcloud-キーを流出)
  - [10. Mini Shai-Hulud 再来 — npm パッケージ 314 件が侵害](#10-mini-shai-hulud-再来--npm-パッケージ-314-件が侵害)
- [Anthropic](#anthropic)
  - [11. Anthropic が Stainless を買収](#11-anthropic-が-stainless-を買収)
  - [12. Claude for Small Business 発表](#12-claude-for-small-business-発表)
  - [13. Gates Foundation と 2 億ドル提携](#13-gates-foundation-と-2-億ドル提携)
- [Claude Code リリースノート](#claude-code-リリースノート)
  - [14. Claude Code v2.1.141 〜 v2.1.145 まとめ](#14-claude-code-v21141--v21145-まとめ)
- [OpenAI](#openai)
  - [15. OpenAI Codex Sandbox for Windows 公開](#15-openai-codex-sandbox-for-windows-公開)
- [Google](#google)
  - [16. Gemini 3.5 Flash 発表](#16-gemini-35-flash-発表)
- [Zoom Phone](#zoom-phone)
  - [17. Zoom Workplace 5月リリースに Phone 関連機能](#17-zoom-workplace-5月リリースに-phone-関連機能)
- [Salesforce](#salesforce)
  - [18. Agentforce Operations × Flows Beta（5月開始）](#18-agentforce-operations--flows-beta5月開始)
- [GitHub トレンド](#github-トレンド)
  - [19. safishamsi/graphify — コード資産をナレッジグラフ化](#19-safishamsigraphify--コード資産をナレッジグラフ化)
  - [20. MemPalace/mempalace — オープンソース AI メモリ基盤](#20-mempalacemempalace--オープンソース-ai-メモリ基盤)
  - [21. VoltAgent/awesome-design-md — DESIGN.md コレクション](#21-voltagentawesome-design-md--designmd-コレクション)
  - [22. JuliusBrussee/caveman — トークン65%削減 Claude Code スキル](#22-juliusbrusseecaveman--トークン65削減-claude-code-スキル)
  - [23. openai/codex-plugin-cc — Claude Code から Codex を呼ぶ公式プラグイン](#23-openaicodex-plugin-cc--claude-code-から-codex-を呼ぶ公式プラグイン)

---

## Hacker News 注目記事

### 1. Andrej Karpathy が Anthropic に参画

- **原題**: I've joined Anthropic
- **スコア**: 1,205pt / コメント: 500件
- **発表日**: 2026-05-19
- **URL**: https://twitter.com/karpathy/status/2056753169888334312
- **要約**: 元 Tesla AI ディレクター・OpenAI 創業メンバーで、教育系YouTube「Andrej Karpathy」でも著名な Karpathy が Anthropic 参画を発表。同週の Stainless 買収と合わせ、Anthropic の人材・基盤の急速な強化が鮮明になった。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内の Claude Code / Claude Agent SDK 活用方針をさらに前進させる根拠データになる。Karpathy が公開する LLM 教育コンテンツ（zero-to-hero 等）は、システム事業部とホリエモンAI学校の両方の教材として直接転用できる。

##### 3年以内
Anthropic 一極集中のリスクと恩恵を経営層で議論する材料。Claude 依存度が高い既存システム（AI-OCR・AIトレーナー・コールセンターPRJ）について、契約・料金・データ取扱い条件を Anthropic と直接交渉できる関係構築を狙う。

##### 3年以上
LLM ベンダの寡占構造（OpenAI / Anthropic / Google）が確定する可能性が高まる。ライフライン事業の根幹データ（不動産送客・契約履歴）の格納と推論の主権をどう確保するか、自社モデルの fine-tune 余地を含めた長期方針が必要。
:::

---

### 2. Elon Musk が OpenAI / Sam Altman への提訴で敗訴

- **原題**: Elon Musk has lost his lawsuit against Sam Altman and OpenAI
- **スコア**: 1,067pt / コメント: 567件
- **発表日**: 2026-05-18
- **URL**: https://techcrunch.com/2026/05/18/elon-musk-has-lost-his-lawsuit-against-sam-altman-and-openai/
- **要約**: 「OpenAI が非営利の創業合意に反した」とした Musk の主張を裁判所が退けた。OpenAI の営利化路線と xAI・Tesla との競合関係に法的な追い風が出た一方、AI 業界の統治構造を巡る議論は続く。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
OpenAI の営利化路線が確定したことで、ChatGPT Business / API の SLA・データ取扱いがより明確化される。RIRIFE アプリの問い合わせ自動応答や AI-OCR で OpenAI API を併用する判断がしやすくなる。

##### 3年以内
AI ベンダ各社が「営利を前提とした顧客契約」へ揃いつつある。CX 事業部のコールセンター業務に LLM を組み込む際、ベンダ単独依存ではなく Anthropic / OpenAI / Google を契約レベルで使い分ける調達ポリシーを整える。

##### 3年以上
AI 産業の規制論議（営利化・寡占・データ取得）が司法レベルで方向づけられていく。新生活プラットフォームとして取り扱う個人情報（入居者・送客）の取り扱い方針を、AI 各社の規約変動に追随できる契約フレームに組み直しておく。
:::

---

### 3. Simon Willison「直近6か月の LLM 動向を5分で」

- **原題**: The last six months in LLMs in five minutes
- **スコア**: 740pt / コメント: 565件
- **発表日**: 2026-05-19
- **URL**: https://simonwillison.net/2026/May/19/5-minute-llms/
- **要約**: Datasette 創設者で LLM 評論の第一人者 Simon Willison が、2025年末〜2026年5月までの主要モデル（GPT-5.5、Claude Opus 4.7、Gemini 3.x、Llama 5 等）と技術潮流（agentic coding、long-context、マルチモーダル）を 5 分の動画と記事で総括。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部・EA2 のメンバー全員にこの 5 分動画を共有し、Claude / GPT / Gemini の選定根拠を共通言語にする。RIRIFE・AI-OCR・コールセンターPRJ の月次レビューで「直近 N か月の業界比較」項目を定例化する。

##### 3年以内
LLM トレンドを四半期ごとに古屋敷代表へ要約するレポート枠を設置し、技術投資判断のスピードを上げる。Willison のような「短く・継続的に・1次情報を引いて」発信するスタイルを社内テックブログにも適用する。

##### 3年以上
LLM が業界標準として安定したあと、ClassLab. 独自の評価軸（電力契約成約率予測・FAX OCR 精度・コールセンター応対品質）でモデル比較を継続できる内部ベンチを保持する。外部トレンドに振り回されない自社指標を持っているかが競争力になる。
:::

---

### 4. Files.md — Obsidian のオープンソース代替

- **原題**: Show HN: Files.md – Open-source alternative to Obsidian
- **スコア**: 693pt / コメント: 338件
- **発表日**: 2026-05-18
- **URL**: https://github.com/zakirullin/files.md
- **要約**: ローカルの Markdown ファイル群をそのままナレッジベースとして扱える OSS。Obsidian 同等のグラフビュー・タグ・全文検索を備えつつ、独自フォーマットや課金プラグインに依存しない設計。

#### ハンズオン（ジュニアエンジニア向け）

ローカル Markdown を Files.md でナレッジベース化（所要時間: 10 分）:

```bash
git clone https://github.com/zakirullin/files.md
# → リポジトリがカレントディレクトリに clone される
cd files.md && npm install
# → 依存パッケージがインストールされ、ローカルで起動可能になる
npm run dev -- --root ~/Documents/notes
# → 指定したフォルダの .md を読み込み、ブラウザでナレッジベースが開く
```

**活用例3選**:
1. システム事業部の `~/.claude/memory/` 配下や `.claude/skills/*/SKILL.md` をローカル一覧化し、スキル依存関係を可視化する
2. CX 事業部のトークスクリプト改訂履歴を Markdown 化し、AIトレーナーの教材として横断検索する
3. NW 事業部の不動産会社別営業ノート（Markdown 出力したもの）をタグ付け・全文検索する

**エンジニアの業務改善**: コードリポジトリ内の README / docs / ADR を Files.md でツリー＋グラフ表示し、新人オンボーディング時の「どこに何があるか」をワンクリックで提示できる。

**オフィスワーカー向け**: Notion / Confluence のサブセットとしてローカルで完結。退職者のローカルノートを引き継ぐ際に有効。

**システム構築ノウハウ**: ナレッジ管理は「データを所有する」「フォーマット中立」が長期的にロックインを避ける鉄則。OSS Markdown ベースを基盤に SaaS は薄く重ねる設計が再評価されている。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ホリエモンAI学校の教材（240本+動画 + 補足資料）を Markdown 一元化し、Files.md で学生・社員共通の閲覧基盤として配信する。

##### 3年以内
ServiceGuide__c や Inquiry__c の運用ナレッジを Markdown 化して全社共通ベースに統合し、Salesforce / Slack / Files.md の三層構成で「業務知識のフォーマット中立化」を進める。

##### 3年以上
SaaS ロックインの議論が業界全体で進む。RIRIFE のコンテンツ（暮らしメディア・クーポン情報・地域データ）の最終的な保存形式を、独自 DB ではなく Markdown + 構造化メタデータで持つ設計に揃え、AI への入力資産にもする。
:::

---

### 5. Bitwarden の静かな全面リノベーション

- **原題**: The quiet renovation at Bitwarden
- **スコア**: 687pt / コメント: 307件
- **発表日**: 2026-05-16
- **URL**: https://blog.ppb1701.com/the-quiet-renovation-at-bitwarden
- **要約**: 大手 OSS パスワードマネージャ Bitwarden が、UI 刷新・パスキー対応強化・サーバサイドの大規模リファクタを段階的に進めている、という第三者ブログによる詳細レビュー。エンタープライズ機能の競争激化が背景。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内のパスワード管理ポリシーを再確認するきっかけ。150名規模での Bitwarden / 1Password 利用状況をシステム事業部から横断ヒアリングし、パスキー移行ロードマップをコーポレート事業部と握る。

##### 3年以内
RIRIFE アプリのログイン体験をパスキー前提に移行する。ユーザの「引越し時に複数サービスのアカウントを一気に作る」シーンを、パスキー＋ライフライン連携 ID で短縮できる。

##### 3年以上
パスワードレスが標準化したあとの本人確認設計。不動産会社・電力会社との API 連携時に求められる「人＋契約者＋住所」の同一性証明をパスキー＋公的個人認証で標準化することを目指す。
:::

---

### 6. Apple、新アクセシビリティ機能群を発表

- **原題**: Apple unveils new accessibility features
- **スコア**: 612pt / コメント: 314件
- **発表日**: 2026-05-19
- **URL**: https://www.apple.com/newsroom/2026/05/apple-unveils-new-accessibility-features-and-updates-with-apple-intelligence/
- **要約**: 視覚・聴覚・運動機能・認知のすべてで Apple Intelligence を活用する新機能を発表（On-device LLM による画面読み上げ強化、ライブキャプション多言語化等）。WWDC2026 前哨戦の位置づけ。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリ（iOS）のアクセシビリティ対応を Apple Intelligence 機能と整合させる優先度を上げる。多言語対応の文脈で、視覚補助・字幕補助も同時に検証する。

##### 3年以内
ライフライン事業の多言語10言語対応を、Apple のライブキャプション API と連携してリアルタイム翻訳通話に拡張。コールセンターでの外国人入居者対応スピードを底上げする。

##### 3年以上
高齢者・障害のある入居者層が増える社会変化に対し、ライフライン申込導線を「アクセシビリティ前提で設計された UI」として標準化することが事業継続の要件になる。
:::

---

### 7. Google 検索ボックスを刷新

- **原題**: Google changes its search box
- **スコア**: 401pt / コメント: 575件
- **発表日**: 2026-05-19
- **URL**: https://blog.google/products-and-platforms/products/search/search-io-2026/
- **要約**: I/O 2026 にあわせ、Google 検索のホーム UI を AI 回答中心に再設計。従来のリンク10件型から「AI が回答→引用元リンク提示」型へ完全移行する第一段階。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
classlab.co.jp / RIRIFE 関連コンテンツの SEO 戦略を「AI Overviews に引用される構造化データ」前提に書き直す。EA1 のオウンドメディア「暮らしのメディア」記事構成を、設問→回答→根拠の3段構成へ整える。

##### 3年以内
広告主企業 300 社の集客導線が AI 検索経由に変わる。広告主向け資料・指標を「リファラ別」から「AI 引用回数別」へシフトし、メディア事業の説明責任を再設計する。

##### 3年以上
検索からの直接流入が縮小し、AI アシスタント経由のサービス連携（Action / Skill）が事業流入の中核になる。RIRIFE をライフライン契約用の AI Action として登録する準備を進める。
:::

---

### 8. OpenBSD 7.9 リリース

- **原題**: OpenBSD 7.9
- **スコア**: 378pt / コメント: 270件
- **発表日**: 2026-05-19
- **URL**: https://www.openbsd.org/79.html
- **要約**: セキュリティ重視の Unix 系 OS、OpenBSD 7.9 がリリース。ARM64 サポート拡充、pf 強化、暗号ライブラリ更新が中心。エッジ・ファイアウォール・VPN 基盤として広く採用されている。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内ネットワークの境界に OpenBSD ベースの pf ルールセットを採用しているかをシステム事業部で棚卸し。Salesforce REST API 経由のアクセスログ取得や Slack 連携の VPN 中継点で OpenBSD 7.9 の利用余地を確認。

##### 3年以内
ライフライン事業のオンプレ側ネットワーク基盤を OpenBSD ベースの構成へ揃え、コーポレート事業部の情報セキュリティ監査の標準環境にする。

##### 3年以上
セキュリティを「枯れた OS の運用力」で担保する基本路線は、クラウド依存が深まる業界で逆に差別化要因になる。重要インフラ事業者（電力・通信）から預かるデータの取扱いポリシーを満たすための基盤として継続採用を検討。
:::

---

### 9. CISA 管理者が GitHub に AWS GovCloud キーを流出

- **原題**: CISA Admin Leaked AWS GovCloud Keys on GitHub
- **スコア**: 410pt / コメント: 168件
- **発表日**: 2026-05-19
- **URL**: https://krebsonsecurity.com/2026/05/cisa-admin-leaked-aws-govcloud-keys-on-github/
- **要約**: 米サイバーセキュリティ・社会インフラセキュリティ庁（CISA）の管理者が、AWS GovCloud のキーを含む `.env` 相当のファイルをパブリックリポジトリにコミット。Krebs on Security が報じた。「秘密のスキャンが間に合わない」典型例。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/d98b71ab-dia-cisa-leak-20260520-121502-1.png" alt="CISA 管理者の `.env` ファイル誤コミットから GovCloud 漏洩までの経路図" width="1820" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
全リポジトリで GitHub Secret Scanning + gitleaks の pre-commit hook を必須化する。Salesforce 接続情報（OAuth client secret、API トークン）が `.env` や `notebooks/` に紛れ込んでいないか棚卸す。

##### 3年以内
社内 IdP（SSO）＋短命クレデンシャル＋ AWS / Salesforce のロール引受けに統一し、ファイル化された長期キーをゼロにする。AI 各社 API キーも同じ仕組みに乗せる。

##### 3年以上
重要インフラ（電力・通信）と連携する事業者として、第三者監査（SOC2 等）と整合する「シークレット流出ゼロ」運用を制度化。AI エージェントが書き換える対象リポジトリでも同水準を維持する設計が必要。
:::

---

### 10. Mini Shai-Hulud 再来 — npm パッケージ 314 件が侵害

- **原題**: Mini Shai-Hulud Strikes Again: 314 npm Packages Compromised
- **スコア**: 364pt / コメント: 278件
- **発表日**: 2026-05-19
- **URL**: https://safedep.io/mini-shai-hulud-strikes-again-314-npm-packages-compromised/
- **要約**: 2025 年に大規模被害を出したワーム型サプライチェーン攻撃 Shai-Hulud の縮小版が再発。314 個の npm パッケージが侵害され、postinstall スクリプトで GitHub / AWS / NPM トークンを窃取しリポジトリを自動生成する挙動を確認。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/4acb8f62-dia-shai-hulud-20260520-121441-1.png" alt="Mini Shai-Hulud のサプライチェーン感染フロー（npm install → 314 件感染 → トークン窃取）" width="1820" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE フロントエンドや社内ツールの依存ツリーを `npm ls` / `pnpm audit` で全数チェックし、ロックファイルを最新化。`npm install --ignore-scripts` をデフォルト化し、CI ビルドでも postinstall を許可制にする。

##### 3年以内
依存導入の社内ガバナンスを定める。新規パッケージ採用時は週次レビュー、Renovate / Dependabot の auto-merge は「テスト + SAST + 公開後 7 日経過」を満たすもののみへ。

##### 3年以上
オープンソース依存リスクは「クラウド依存」と並ぶ事業継続リスクとして経営アジェンダ化。社内基盤に SBOM 必須化、Salesforce アプリも AppExchange パッケージのバンドル監査を年次で実施する体制へ進化させる。
:::

---

## Anthropic

### 11. Anthropic が Stainless を買収

- **発表日**: 2026-05-18
- **URL**: https://www.anthropic.com/news/anthropic-acquires-stainless
- **要約**: Anthropic が OpenAPI 仕様から SDK / CLI / MCP サーバを自動生成する Stainless を買収。Anthropic 自身の公式 SDK は 2022 年の設立以来 Stainless 製。「エージェントは接続先の数だけ役に立つ」という Anthropic の言葉どおり、エコシステム拡大を取り込む構図。買収条件は非公開。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/99edfb7a-dia-stainless-20260520-121539-1.png" alt="Anthropic Stainless 買収の Before/After（手書き SDK 保守 → OpenAPI 仕様から自動生成）" width="1820" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内 API（Salesforce 連携、ライフライン契約 API、AI-OCR）の OpenAPI 仕様を整備し、Stainless 由来のテンプレートで TS/Python SDK と MCP サーバを 1 ソースから自動生成する PoC を行う。Claude Code から社内 API を直接叩く動線が一気に短くなる。

##### 3年以内
電力・ガス・ネット各社の API 連携を MCP サーバとして抽象化し、Claude エージェントが入居者属性に応じて最適商品を自動提案する基盤を構築する。新規キャリア追加が「OpenAPI 仕様 1 本」で完結する世界を目指す。

##### 3年以上
ライフライン業界全体に「MCP 経由でエージェントが契約代行する」標準が広がる可能性。ClassLab. を MCP サーバ提供側として位置づけ、不動産会社・コールセンター運営会社が自社エージェントから ClassLab. の契約代行機能を呼び出せる事業モデルへの転換を視野に入れる。
:::

---

### 12. Claude for Small Business 発表

- **発表日**: 2026-05-13
- **URL**: https://www.anthropic.com/news
- **要約**: QuickBooks、PayPal、HubSpot、Canva、Docusign、Google Workspace、Microsoft 365 に Claude を組み込んだ中小企業向けプランを発表。給与計算・請求書発行・売上管理・月次決算の即時実行ワークフローを内蔵。米国 10 都市での無料半日トレーニングツアーも並走。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート事業部の経理・人事業務（請求書発行・経費精算・契約書管理）に Claude for Small Business 級のワークフローを Salesforce + Slack で内製する優先度を上げる。150 名規模だからこそ「業務 SaaS の上に直接エージェント」が現実的。

##### 3年以内
新生活企業（不動産会社 4,000 社）向けに、ClassLab. 経由でライフライン契約・入居者管理・SaaS 設定がワンストップでできる「中小不動産会社向け AI 業務パッケージ」をメディア事業のサブブランドとして展開する。

##### 3年以上
日本市場でも中小企業向け AI 業務パッケージの覇権争いが本格化する。ClassLab. が培ってきた「不動産・ライフライン特化の業務知識」を AI ワークフローとして資産化し、Anthropic / OpenAI / 国内 SI 各社のパッケージへ OEM 供給する事業の柱を作る。
:::

---

### 13. Gates Foundation と 2 億ドル提携

- **発表日**: 2026-05-14
- **URL**: https://www.anthropic.com/news
- **要約**: Anthropic と Bill & Melinda Gates Foundation が 2 億ドル規模の戦略提携を発表。グローバル ヘルス・教育・農業分野で Claude を活用する大規模プログラムを立ち上げる。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社会課題領域で Anthropic が積極的に Claude を提供する流れを社内事業企画に取り込む。ホリエモンAI学校の助成金スキーム（年間最大 24 万円/人）と接続し、行政・財団系の助成パートナーへの提案資料に活用する。

##### 3年以内
ライフライン事業の社会的役割（外国人入居者支援・低所得世帯のインフラ手続き支援）を Anthropic / Gates Foundation 系プログラムと連携できる NPO スキームとして整理する。

##### 3年以上
日本の社会インフラ事業者として「AI を使った社会包摂」の実績を蓄積。電力・ガスの自由化・脱炭素対応とも連動した、新生活インフラの公共性を再定義する事業設計に進む。
:::

---

## Claude Code リリースノート

### 14. Claude Code v2.1.141 〜 v2.1.145 まとめ

- **公開日**: 2026-05-13 〜 2026-05-19（週5バージョンリリース）
- **URL**: https://github.com/anthropics/claude-code/releases
- **要約**: バックグラウンドセッション、プラグイン、エージェント運用周辺の改善が集中。`claude agents --json` で稼働中セッションを構造化出力できるようになり、tmux-resurrect やステータスバー、セッションピッカーへの組み込みが容易に。Fast mode の既定モデルが Opus 4.7 に格上げ、OTEL span に `agent_id` / `parent_agent_id` 追加、`ANTHROPIC_WORKSPACE_ID` でワークロード ID 連携をサポート。`/plugin` browse で機能と推定コンテキスト消費を事前確認可能。

| バージョン | 日付 | 主な変更 |
|---|---|---|
| 2.1.141 | 05-13 | `terminalSequence` hook 出力、`CLAUDE_CODE_PLUGIN_PREFER_HTTPS`、`ANTHROPIC_WORKSPACE_ID`、`claude agents --cwd` |
| 2.1.142 | 05-14 | `claude agents` の `--model` `--effort` 等の引数追加、Fast mode 既定が Opus 4.7 へ、ルート `SKILL.md` をスキルとして認識 |
| 2.1.143 | 05-15 | プラグイン依存関係の disable ガード、`/plugin` で予測コンテキストコスト表示、`worktree.bgIsolation: "none"` |
| 2.1.144 | 05-19 | バックグラウンドセッションの `/resume` 対応、`api.anthropic.com` 到達不能時の 75 秒ハング修正、`/model` のセッション限定切替 |
| 2.1.145 | 05-19 | `claude agents --json`、OTEL span に `agent_id`/`parent_agent_id`、Status line に GitHub Repo/PR 情報、`/plugin` 内訳事前表示 |

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/a97801f5-dia-claude-code-releases-20260520-122356-1.png" alt="Claude Code v2.1.141-145 リリース週の新機能まとめ図" width="1820" height="1024">

#### ハンズオン（ジュニアエンジニア向け）

`claude agents --json` をステータスバーに統合する（所要時間: 15 分）:

```bash
claude --version
# → 2.1.145 以上が表示されることを確認
claude agents --json | head
# → 稼働中の Claude セッションが JSON 配列で出力される。idle / awaiting_input / running などの状態が分かる
claude agents --json | jq '.[] | select(.state=="awaiting_input") | .session_id'
# → ユーザ入力待ちのセッション ID のみ抽出される
```

tmux のステータスバーに「awaiting_input 件数」を出す:

```bash
echo 'set -g status-right "#(claude agents --json | jq "[.[] | select(.state==\"awaiting_input\")] | length") awaiting"' >> ~/.tmux.conf
# → tmux ステータスバー右側に Claude が応答待ちのセッション数が常に表示される
tmux source-file ~/.tmux.conf
# → 設定が即反映され、画面右に件数が出る
```

**活用例3選**:
1. システム事業部内で「Claude を起動しっぱなしのバックグラウンドジョブが今いくつあるか」を全員のターミナルに見える化する
2. CI 上のジョブ監視に組み込み、長時間 awaiting_input のセッションを Slack に通知する
3. AI-OCR バッチ処理を Claude Code バックグラウンドセッションで回す際の進捗ダッシュボードに使う

**エンジニアの業務改善**: Fast mode が Opus 4.7 へ格上げされたため、簡易タスクでも品質が一段向上。`/plugin` のコンテキストコスト事前表示で、大型プラグインによる予期せぬコンテキスト圧迫を防げる。

**オフィスワーカー向け**: 直接の影響は薄いが、`/feedback` で 24 時間 / 7 日のセッションを添付できるようになったため、エンジニアからの不具合報告品質が上がる。

**システム構築ノウハウ**: ローカル CLI の出力を JSON にする・OTEL に乗せる・ステータス情報をフックで露出する、というのは AI 開発ツール全般の標準パターンになりつつある。社内 CLI 設計の参考に。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内エンジニアの Claude Code 運用ルールに「2.1.145 以上、Fast mode は Opus 4.7」を明記。`ANTHROPIC_WORKSPACE_ID` を組織で発行してワークスペース単位の請求・ガバナンスを成立させる。

##### 3年以内
OTEL span を Datadog / New Relic 側へ集約し、AI エージェント稼働時間・トークンコスト・タスク成功率を BI ダッシュボード化する。AIプロジェクト 4 本（AIコールセンター・AIオペレーション自動化・AIコミュニケーション・AIコールインサイト改善）の効果測定の共通基盤にする。

##### 3年以上
Claude Code を含む AI 開発ツールが社内の「開発インフラ」になることを前提に、エージェントの権限管理・監査ログ・SBOM・データ持ち出し制御を制度として完成させる。
:::

---

## OpenAI

### 15. OpenAI Codex Sandbox for Windows 公開

- **発表日**: 2026-05-13 〜 14
- **URL**: https://help.openai.com/en/articles/6825453-chatgpt-release-notes
- **要約**: OpenAI Codex に Windows 専用のサンドボックス実行環境を追加。ファイアウォール経由のネットワーク遮断、書込み可能ファイルの制限、専用 runner バイナリを備え、Windows 上でも macOS / Linux 同等のエージェントコーディング体験を提供。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Windows メインのオフィスメンバー（CX / NW / EA / コーポレート）に Codex / Claude Code を配るときの環境準備が一段楽になる。AI-OCR の前後処理を Windows 端末で安全に試す環境として活用可能。

##### 3年以内
社内 Windows / Mac 混在環境に共通の「サンドボックス実行プロファイル」を定義し、生成された AI コードが直接社内ネットへ出ない構成を標準化する。

##### 3年以上
コーディング外の業務（Excel マクロ生成、PowerPoint 資料生成、業務 RPA）でもサンドボックス前提が当たり前になる。社員 1 人ごとに「安全に AI を動かせる箱」が配布される世界に向けたデバイス調達計画を進める。
:::

---

## Google

### 16. Gemini 3.5 Flash 発表

- **発表日**: 2026-05-19
- **URL**: https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-5/
- **要約**: Google I/O 2026 にあわせて Gemini 3.5 Flash を発表。Gemini 3 系の「速度・低コスト」レーンを強化したモデルで、長文 / マルチモーダル / agentic 用途のレイテンシを大幅短縮。Vertex AI / AI Studio で即提供開始。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/da667921-dia-gemini-35-20260520-121433-1.png" alt="2026年5月時点の LLM モデル勢力図（速度×品質マップ）に Gemini 3.5 Flash を配置" width="1820" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE の「物件周辺レビュー要約」「ハザード解説」など読み込み量の多い処理を Gemini 3.5 Flash で試し、現在の Claude Haiku / GPT-4.1 mini とコスト・品質比較する。

##### 3年以内
コールセンターのリアルタイム文字起こし要約に Flash 系を採用し、応対直後の「次の一手アクション提案」までを 1 秒以内に返すレベルに引き上げる。AIコールインサイト改善PRJ の中核モデルに据える候補にする。

##### 3年以上
モデル選定が「ベンダ単独」から「タスク × コスト × レイテンシ」のマッピングで自動ルーティングされる時代になる。AI Gateway 的なルーティング基盤を内製し、Anthropic / OpenAI / Google を並列で使い分ける運用を本流化する。
:::

---

## Zoom Phone

### 17. Zoom Workplace 5月リリースに Phone 関連機能

- **発表日**: 2026-05-18（当初 5/11 予定が 1 週間延期）
- **URL**: https://library.zoom.com/whats-new
- **要約**: Zoom Workplace 5 月版で、Zoom Phone のリアルタイム字幕翻訳・Cellular companion 課金連携（モバイル端末経由通話の課金統合）・Zoom Virtual Agent の不在着信通話サマリーが追加。また AI Companion サイドパネルがグローバルナビからプロダクト別配置へ移行。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン事業の多言語10言語対応コールに Zoom Phone のリアルタイム字幕翻訳を当て、外国人入居者対応を「電話＋翻訳字幕」で同時運用する PoC を CX 事業部と組む。Virtual Agent の不在着信サマリーは AIコールインサイト改善PRJ と直接相性が良い。

##### 3年以内
コールセンターのオペレータ画面に AI Companion のサイドパネルを常設し、トークスクリプト推奨・FAQ 検索・顧客情報サマリーを 1 画面で完結させる。AIトレーナーの応対評価データを Zoom 側のサマリーと突合し品質改善ループに乗せる。

##### 3年以上
電話業務が「人＋ AI ハイブリッド」前提の設計に標準化される。コールセンター事業を、人員規模ではなく「AI に渡せるシナリオ数」で評価する KPI 体系に組み替える。
:::

---

## Salesforce

### 18. Agentforce Operations × Flows Beta（5月開始）

- **発表日**: 2026-04-29 の Agentforce Operations 一般提供開始に続き、2026-05 中に Salesforce Flows との自動同期 / アクション起動 Beta が開始
- **URL**: https://www.salesforce.com/news/stories/agentforce-operations-announcement/
- **要約**: Agentforce Operations は非構造化な手順書・図表を「デジタルブループリント」に変換し、専門エージェントがプロセス調整・データ検証・コンプラ確認・承認追跡を横断的に自動実行する仕組み。サイクルタイム最大 70%短縮、手作業最大 80%削減を謳う。5月から既存 Salesforce Flow との自動連携 Beta が始まり、製造・銀行・保険・社内 IT 用途で本格採用が始まる。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-13-20/2dc6e165-dia-agentforce-ops-20260520-121502-1.png" alt="Agentforce Operations の Before/After（部署横断の手作業 → 4 種の専門エージェントが自動連携）" width="1820" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ServiceGuide__c（入居者）→ Inquiry__c（問い合わせ）→ Account（不動産会社）を横断する手作業（FAX 受領→入力→確認→承認）を Agentforce Operations のデジタルブループリント候補としてリストアップし、Salesforce Flow との Beta 連携で小規模 PoC を行う。

##### 3年以内
ライフライン契約代行の業務工程（電気・ガス・ネット契約 → 各社 API → 入居者通知）を専門エージェントごとに分担する設計へ移行。コールセンター稼働を「単純処理 → 例外対応集中」に組み替え、CX 事業部の処理能力を 1.5〜2 倍へ。

##### 3年以上
不動産会社・電力会社・通信会社の業務をまたぐエージェント連携が当たり前になる。ClassLab. が「業界横断のエージェント・オーケストレータ」の立ち位置で、Agentforce Operations 上の標準ブループリント供給者になることを目指す。
:::

---

## GitHub トレンド

### 19. safishamsi/graphify — コード資産をナレッジグラフ化

- **言語**: Python / **Stars**: 49.7K（2026-04-03 作成）
- **URL**: https://github.com/safishamsi/graphify
- **要約**: 任意のフォルダ（コード、SQL スキーマ、R スクリプト、シェル、ドキュメント、論文、画像、動画）をクエリ可能なナレッジグラフ化する Claude Code / Codex / Cursor 等のスキル。アプリコード＋ DB スキーマ＋インフラ定義を 1 グラフに統合できるのが特徴。

#### ハンズオン（ジュニアエンジニア向け）

社内リポジトリをグラフ化してエージェントから問い合わせる（所要時間: 20 分）:

```bash
pip install graphify
# → graphify CLI がインストールされる
graphify init ./classlab-mono
# → 指定フォルダ配下のコード／SQL／ドキュメントをスキャンし .graphify/ にグラフを構築する
graphify query "ServiceGuide__c に依存している関数は何があるか？"
# → エンティティ間関係を辿り、依存関数と参照ファイルが一覧表示される
```

**活用例3選**:
1. Salesforce カスタムオブジェクト（ServiceGuide__c、Employee__c、Inquiry__c、Account）と社内コードの参照関係を 1 つのグラフで横断検索する
2. AI-OCR / AIトレーナーの学習データ・前処理コード・モデル定義を統合グラフ化し、依存変更時の影響範囲を即時可視化
3. ホリエモンAI学校の教材コード / Notebook / 動画スクリプトを横断検索可能にして、学生からの質問対応を自動化する

**エンジニアの業務改善**: 「この関数を消しても良いか」「この SQL を変更したら何が壊れるか」を秒で答えられる。リファクタ・移行プロジェクトの認知負荷が大幅に下がる。

**オフィスワーカー向け**: 業務マニュアル（PDF/Word）と Salesforce 定義を同じグラフに入れると、「この帳票はどの項目から生成されているか」を社員が直接問い合わせられる。

**システム構築ノウハウ**: コード以外の資産（SQL、ノート、画像、動画）まで含めた統合グラフは、RAG の正答率を大きく押し上げる。Graph RAG の本流。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部のモノレポ＋ Salesforce 定義＋運用ドキュメント（cleath.space ドメイン47文書）を graphify でグラフ化し、ジュニアエンジニアのオンボーディング期間短縮を狙う。

##### 3年以内
graphify を基盤にした社内 RAG を CX / NW / EA 各部署にも展開し、「業務知識質問 → コード根拠付き回答」を全社員に提供する。

##### 3年以上
業界全体のナレッジ統合プラットフォームへ拡張。不動産会社・電力会社の業務知識を含む「ライフライン業界グラフ」を ClassLab. が運営し、業界エージェントの推論基盤として外販する事業を視野に入れる。
:::

---

### 20. MemPalace/mempalace — オープンソース AI メモリ基盤

- **言語**: Python / **Stars**: 52.5K（2026-04-05 作成）
- **URL**: https://github.com/MemPalace/mempalace
- **要約**: ベンチマーク上位の OSS AI メモリ基盤。エージェントの長期記憶（ユーザー情報・会話履歴・タスク履歴）を構造化保存し、複数モデル / アプリ間で共通して再利用できる。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリのユーザー対話履歴（引越し前後の暮らし相談、クーポン利用履歴）を mempalace で永続化する PoC を行い、複数の AI セッション間で「あなたは先月引越したばかり」という前提を保持できるか検証する。

##### 3年以内
コールセンターの応対履歴を mempalace に集約し、Salesforce ServiceGuide__c の延長として AI が即参照できる「入居者メモリ」を構築。再連絡時の前提共有を機械化する。

##### 3年以上
新生活プラットフォームとしての価値は「ユーザの暮らしを覚えていること」に集約される。メモリ層をベンダ非依存の OSS に持ち、LLM ベンダ切替時もユーザ体験が断絶しない構造を確立する。
:::

---

### 21. VoltAgent/awesome-design-md — DESIGN.md コレクション

- **言語**: なし（ドキュメント） / **Stars**: 81.4K（2026-03-31 作成）
- **URL**: https://github.com/VoltAgent/awesome-design-md
- **要約**: 著名ブランドのデザインシステムにインスパイアされた `DESIGN.md` 集。プロジェクトに 1 つ放り込むと、コーディングエージェント（Claude Code / Codex 等）がブランドに沿った UI を一貫生成するための前提知識として利用できる。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリと classlab.co.jp の `DESIGN.md` を整備し、システム事業部の全リポジトリに配布。AI に「ClassLab. らしい UI を作って」と頼んだときの結果のばらつきをなくす。

##### 3年以内
広告主企業 300 社向け資料生成（LP・ピッチ資料・キャンペーンクリエイティブ）も `DESIGN.md` ベースのテンプレートで自動化し、メディア事業の制作スピードを底上げする。

##### 3年以上
ブランドのデジタル資産は「デザインファイル」ではなく「AI が読める設計仕様」に集約される。ClassLab. のブランド体験を `DESIGN.md` で正典化し、不動産パートナー側に展開できる「共同ブランド」運用へ広げる。
:::

---

### 22. JuliusBrussee/caveman — トークン65%削減 Claude Code スキル

- **言語**: JavaScript / **Stars**: 62.4K（2026-04-04 作成）
- **URL**: https://github.com/JuliusBrussee/caveman
- **要約**: 「why use many token when few token do trick」というキャッチコピーで、Claude Code 上で意図的に「原始人語」風に応答させることで出力トークンを 65% 削減するスキル。バズ要素は強いが、トークン削減のために出力フォーマットを工夫するという考え方そのものは正攻法。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内の Claude Code 利用で「短く・要点のみ」を強制するスキルとしてフォーマット改善のヒントに使う。caveman 自体をそのまま使う必要はないが、出力テンプレ統一によるコスト削減の検証は今すぐ可能。

##### 3年以内
社内 4 本の AI プロジェクトすべてで、応答テンプレ・要約レベル別のトークンコストを計測し、固定費削減のチューニングプロセスを定型化する。

##### 3年以上
LLM コストが下がる一方で総量は増え続ける。社内の AI 利用コスト管理を、現在のクラウド予算管理と同じ厳密さで運用する財務オペレーションに進化させる。
:::

---

### 23. openai/codex-plugin-cc — Claude Code から Codex を呼ぶ公式プラグイン

- **言語**: JavaScript / **Stars**: 19.1K（2026-03-30 作成、push: 2026-04-18）
- **URL**: https://github.com/openai/codex-plugin-cc
- **要約**: OpenAI 公式の「Claude Code から Codex を子エージェントとして呼び出す」プラグイン。コードレビューや特定タスクの委譲を Codex に任せ、メイン作業は Claude Code が続ける構成。両陣営の協調を象徴する公式リリース。

#### ハンズオン（ジュニアエンジニア向け）

Claude Code から Codex に PR レビューを委譲（所要時間: 10 分）:

```bash
claude /plugin install openai/codex-plugin-cc
# → プラグインがインストールされ /codex コマンドが使えるようになる
claude /codex review --pr 123
# → 指定 PR のレビューを Codex に委譲し、結果を Claude Code 側に返す
```

**活用例3選**:
1. Claude Code で書いた Salesforce 連携コードを Codex にセキュリティ観点でレビューさせ、双方の指摘を統合する
2. AI-OCR の前処理スクリプトを Claude Code で開発し、テスト生成だけ Codex に任せる
3. ホリエモンAI学校の教材コード添削を、複数モデルの意見を並列で取って学生に提示

**エンジニアの業務改善**: モデル間の得意分野（推論深さ vs 速度 vs コスト）を 1 プロジェクトで併用できる。「セカンドオピニオン」を秒で取れる。

**オフィスワーカー向け**: 直接の影響は薄いが、エンジニア側のレビュー品質と速度が上がる結果として、社内 AI ツールの改善ペースが上がる。

**システム構築ノウハウ**: 「メインエージェント＋専用サブエージェント委譲」は今後の AI 開発の標準構成。社内 AI システムも単独モデルではなく、ルーティング前提で設計するのが既定路線。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部のレビュー文化に組み込む。Claude Code でのコード生成→ Codex 経由でセカンドレビュー→人間がマージ判断、という 3 段プロセスを試す。

##### 3年以内
AI プロジェクト 4 本それぞれで、推論を Claude、定型作業を Codex / Gemini Flash、出力安定性を Sonnet で分担するマルチモデル運用を定型化する。

##### 3年以上
モデル選択をエンジニアが意識しない「ルーティング層」を社内基盤として確立。各部署はタスクを投げ、最適モデルがコスト最適に分配される運用に到達する。
:::
