
> ClassLab. エンジニア向け Railway リファレンス。「なぜ存在するか → 何ができるか → 自社でどう使うか」を 1 本で完結させる。Heroku の DX を継承しつつ、Functions / Buckets / Metal / Magic Config など 2026 新機能でモダン PaaS の最前線に立つ Jake Cooper 率いるスタートアップ。

---


> 「Push → URL」を最短化する agent-native の全部入りクラウド。Heroku の DX を継承しつつ、Functions / Buckets / Metal / Magic Config など 2026 新機能でモダン PaaS の最前線に立つ Jake Cooper 率いるスタートアップ。

---

## 0. TL;DR

### 一行サマリ

Railway は「ソースコードを push したら数秒で URL が返ってくる」体験を、フロントエンドから DB / Cron / Object Storage / 自社ハードウェアまで含めて 1 つの管理画面に集約した **agent-native cloud**。Vercel が「フロントエンドの Vercel」なら、Railway は「**バックエンドの Vercel**」のポジションを取りに来ている。

### 旧知識との差分（2025〜2026 に LLM 訓練データから陳腐化しやすい論点）

- **Series B $100M を 2026-01 に調達**。Redpoint / a16z を中心にラウンドを実施。「agent-native cloud」を新ビジョンとして打ち出した。
- **プラン体系刷新**: 旧 Developer/Team から **Trial / Hobby ($5/mo) / Pro ($20/seat/mo) / Enterprise ($2,000/mo 〜)** の 4 段に再編。
- **Railway Metal**（beta）— 既存ハイパースケーラのコモディティ層から離脱し、**Railway 自社設計の bare metal インフラ** で 30〜50% コスト削減を目指す独自ハードウェア戦略。
- **Railway Functions**（GA）— canvas 上で TypeScript を直接書いて **GitHub repo 不要で sub-second deploy**。cron / webhook / volume 対応。
- **Railpack**（GA）— Nixpacks 後継の次世代ビルダー。**ビルドサイズ 38〜77% 削減**、Node/Python/Go/Ruby/Rust/Elixir/Deno/PHP-Laravel など多言語対応。
- **Buckets**（GA, 2026）— S3 互換オブジェクトストレージが **全プランで利用可能**に。
- **Magic Config** — Haiku ベースの LLM が `railway.toml` 設定や Dockerfile を自動生成する AI 機能。
- **Enterprise Restricted Environments** — 本番環境への変更を承認制にする MFA + Review フロー（SOC 2 / HIPAA 対応の一環）。
- **Amsterdam EU リージョン追加**（2026-Q1）— 既存の US East / US West / Asia Southeast に EU が加わり、データレジデンシ要件にも対応開始。
- **Preview Environments** が「PR ごとに DB を含む全スタックを丸ごと複製」する形に進化。ブランチ単位の完全な動作検証が可能に。
- **Railway CLI v4** — Bun ベースに刷新、起動速度・cross-platform 配布の改善。

### 最大差別化点（競合 10 社との対比サマリ）

- **Render** に対しては「**従量課金で scale-to-zero が効く / Functions / Magic Config / Metal**」で勝つ。Render は逆に「月額固定の見積もりやすさ」が強み。
- **Fly.io** に対しては「**UI/UX と DB の自動プロビジョニング**」で勝つ。Fly.io は逆に「**35+ エッジリージョンと地理的分散**」が強み。
- **Vercel** に対しては「**バックエンド・Worker・DB のフルスタック完結**」で勝つ。Vercel はフロントエンド + AI SDK の体験で圧勝。
- **Heroku** に対しては「**価格・モダン UI・Functions・Metal**」で勝つ。Heroku は逆に「Salesforce 連携と既存資産の継承」が強み。
- **AWS App Runner** に対しては「**学習コストの低さと UX**」で勝つ。AWS は逆に「IAM / RDS / VPC など既存 AWS 資産との統合」が圧倒的。
- **Cloudflare Workers** に対しては「**フルコンテナ・任意 OSS DB の同居**」で勝つ。Cloudflare は「edge / D1 / R2 / KV のグローバル分散」が強み。
- **Netlify** に対しては「**バックエンド完結 / Long-running worker**」で勝つ。Netlify は静的サイト + Edge Functions に特化。
- **DigitalOcean App Platform** に対しては「**Preview Environment / Functions / Magic Config**」で勝つ。DO は VPS / k8s と統合 SKU で勝つ。
- **Northflank** に対しては「**コミュニティと template 数 / DX 完成度**」で勝つ。Northflank は **multi-cluster k8s / job runner / BYOC** で勝つ。
- **Coolify**（OSS 自社ホスト）に対しては「**マネージド運用 / SLA / DB 自動管理**」で勝つ。Coolify は「コスト 0 + 完全自己管理」で勝つ。

---

## 1. Railway とは何か — 理念とミッション

### 1.1 ミッション

公式表現（要旨）:

> *"Make infrastructure invisible, so software works with developers, not against them."* — インフラを見えなくし、ソフトウェアが開発者と戦うのではなく協働するようにする。

Jake Cooper（前 Bloomberg / Uber）は社内インタビューで「**activation energy to ship something to production should be near zero**」（本番に何かを送り出すまでの活性化エネルギーをほぼゼロにしたい）と繰り返している。

### 1.2 哲学

| 発言者 | 立場 | 哲学・要旨 |
|---|---|---|
| Jake Cooper（CEO / Founder）| Railway 創業者 | "Push code, get a URL, iterate. No Dockerfile, no Kubernetes manifests, no Ansible stacked on Ansible." |
| Jake Cooper | 同上 | "If I get it wrong this time, I'm gonna do it again. This is my life's mission." — 5 年以上同じビジョンで磨き込み続けている |
| Jake Cooper | 同上 | "Agent-native cloud" — エージェントがインフラをプロビジョン・運用することを前提に CLI / API / Functions を設計し直している |
| 公式 | プラットフォーム哲学 | "Remove friction from the entire software delivery process: deployment, databases, networking, observability, support, scaling, and now agent workflows." |
| 公式 | エンジニアリング哲学 | "**A canvas, not a dashboard.**" — Project 単位のキャンバスで Service / DB / Volume を視覚的に配線する UX を重視 |

### 1.3 なぜ存在するか

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/2b5a2e1d-r01.png" alt="なぜ存在するか" width="1536" height="864">

「ハイパースケーラの素材」を組み立てる労力 → ゼロへ。Heroku 全盛期の体験を、**コンテナと DB を分離せず canvas で配線できる UI** + **Functions で関数まで含めた agent-native API** で 10 年ぶりに再構築している。

### 1.4 エンジニアにとっての意味

| 立場 | Railway をどう使うか |
|---|---|
| フロントエンド | Vercel と並列で API/SSR サーバーをホスト。Preview Environment で UI と API を PR 単位に同期 |
| バックエンド | API + Postgres + Redis + Worker + Cron を 1 つの Project に置き、Service 間は private network で接続 |
| SRE / プラットフォーム | Metal beta / Volume / Healthcheck / Webhook / Audit Log で内製 PaaS 不要に。Restricted Environments で本番ガード |
| AI / ML エンジニア | Functions で LLM 呼び出し worker を瞬時に起動。Magic Config で Dockerfile を AI 生成。Bucket に成果物を保存 |
| プロジェクトマネージャ | Project 単位の使用量ダッシュボードでコスト可視化、Hobby/Pro/Enterprise の seat 課金で予算管理 |
| セキュリティ / コンプライアンス | SSO/SAML、Audit Log、Restricted Environments、Enterprise 限定の SOC 2 / HIPAA 対応 |
| QA / テスト | Preview Environment で PR ごとに DB を含む全スタック複製、E2E をフル経路で実行可能 |

---

## 2. 全体マップ（1 枚絵）

### 2.1 サービス全体俯瞰

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/0e35032d-r02.png" alt="サービス全体俯瞰" width="1536" height="864">

### 2.2 製品カテゴリ mindmap

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/2f9cf460-r03.png" alt="製品カテゴリ mindmap" width="1536" height="864">

---

## 3. プラン体系の前提知識

### 3.1 プラン概要表

| 観点 | Trial | Hobby | Pro | Enterprise |
|---|---|---|---|---|
| 価格 | $0（$5 一回限り credit / 30 日有効） | $5 / 月（$5 credit 込み） | $20 / seat / 月（$20 credit / seat 込み）| $2,000 / 月 〜（custom） |
| 対象 | お試し / 個人検証 | 個人開発 / 小規模 prod | チーム / 本番運用 | 大企業 / 規制業種 |
| Pay-as-you-go 超過課金 | 不可（credit 切れで停止） | あり | あり | 契約上限内で発生 |
| Seat 数 | 1 | 1 | 無制限 | 無制限 |
| サポート | コミュニティ | コミュニティ | チケット（営業日応答） | 専任 CSM + SLA |
| Region | US East / US West / Asia SE / EU Amsterdam | 同左 | 同左 | + 専用 region 相談可 |
| Volume / Bucket | 利用可 | 利用可 | 利用可 | 利用可 |
| Preview Environments | 利用可（数制限） | 利用可 | 利用可 | 利用可 |
| Restricted Environments | 不可 | 不可 | 制限あり（Beta） | 利用可 |
| SSO/SAML | 不可 | 不可 | 利用可（Pro+ Beta） | 利用可 |
| Audit Log | 不可 | 不可 | 制限あり（直近 30 日）| 利用可（無制限）|
| SOC 2 / HIPAA | 不可 | 不可 | 不可 | 利用可 |
| Railway Metal | 不可 | 不可 | 不可（Beta 招待制）| 利用可 |

### 3.2 課金モデルの考え方

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/5d2e5bd6-r04.png" alt="課金モデルの考え方" width="1536" height="864">

**4 軸の単価感**（2026-05 時点・Pro プラン基準・概算）:

- vCPU: $20 / vCPU / 月（active CPU 課金 = 実際に CPU を使った時間のみ）
- RAM: $10 / GB / 月
- Egress: $0.10 / GB（最初の 100 GB / project / 月は無料）
- Volume: $0.25 / GB / 月
- Bucket: $0.023 / GB / 月（保管）+ リクエスト数課金

Hobby/Pro/Enterprise はすべて **含まれている credit（$5 / $20 / 契約額）を超過した分のみ Pay-as-you-go**。

### 3.3 本ドキュメント内のプラン表記凡例

| 表記 | 意味 |
|---|---|
| 利用可 | そのプランで標準提供、追加料金なし（含み枠内） |
| 制限あり | 利用可だが、上限・条件・Beta などの制約あり（補足テキスト併記） |
| 不可 | そのプランでは提供されない |
| 従量課金 | 含み枠を超えた分は使用量に応じて課金 |

---

## 4. 機能カタログ

### 4.1 デプロイ・ビルド層

#### 4.1.1 Git Push Deploy（GitHub / GitLab 連携）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/a039a547-r05.png" alt="Git Push Deploy" width="1536" height="864">

GitHub / GitLab リポジトリを接続すると、main / 指定ブランチへの push を webhook で受け、**自動ビルド → 自動デプロイ → 自動 URL 発行** までを 1 ステップで実行。

**👨‍💻 エンジニアへの関係**

Heroku 後継の最大価値。`git push` で URL が出る体験を「特別な CI/CD 設定なし」で享受できる。PR ベースの Preview Environment（後述）と組み合わせると **PR ごとに本物の URL** が手に入る。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託開発の検証環境を案件 repo 直結で自動立ち上げ、お客様に共有
- 中長期: 内製ツール（社内 dashboard / bot / batch）を GitHub 中心の運用に揃え、Vercel と棲み分け

**🔥 差別化点**

- **Heroku** より速く・きれい・モダンな canvas UI
- **Render** と機能はほぼ同等、こちらは **monorepo の root path 指定がより柔軟**
- **Fly.io** は CLI 中心（fly launch / deploy）、GUI 派には Railway が圧勝

**🔍 深掘り**

- Root Directory / Watch Paths / Build Command / Start Command を Service 設定から override 可
- Auto Deploy on Push を OFF にして手動 promote も可能（Pro Environments の Production Branch とセットで）
- Branch 単位の environment 切替（PR → preview / main → production）

**⚠️ 注意点**

- Monorepo で「ルート以外の package.json」を指定する場合は Root Directory を明示する
- Build Logs に env が露出する設定にしないこと（既定でマスクされているが Custom Build Command で漏らせる）

---

#### 4.1.2 Railpack（次世代ビルダー）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/d3e74658-r06.png" alt="Railpack" width="1536" height="864">

Nixpacks 後継として 2026 リリースされた次世代ビルダー。**ビルドサイズ 38〜77% 削減**、キャッシュ精度向上、Node / Python / Go / Ruby / Rust / Elixir / Deno / PHP-Laravel など多言語ネイティブ対応。

**👨‍💻 エンジニアへの関係**

Dockerfile を書かなくても言語ランタイムを自動検出して最小化された OCI image を生成。Cold start とコールドキャッシュ時のビルド時間が大きく短縮された。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: Node / Python の社内 worker を Dockerfile 不要で速くデプロイ
- 中長期: PHP-Laravel 含めて Railpack で統一、内製テンプレに含める

**🔥 差別化点**

- **Render** の Buildpacks より圧倒的に高速 + 多言語対応
- **Fly.io** は Buildpacks か Dockerfile 二択、Railpack のような自動最適化は無い
- **Heroku Buildpacks** は安定だが進化が止まっており Railpack の世代が新しい

**🔍 深掘り**

- `railway.toml` で builder 選択（`railpack` / `nixpacks` / `dockerfile`）
- 言語別バージョン pin（Node 20 LTS / Python 3.12 など）
- Build cache は project 単位、Volume とは別領域

**⚠️ 注意点**

- 言語自動検出が誤判定するケースは少数だが、その時は `builder = "dockerfile"` で明示
- Railpack はまだ若いため、特殊な OS パッケージ依存は Dockerfile に逃げる方が確実

---

#### 4.1.3 Nixpacks（後方互換ビルダー）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/1e6ad426-r07.png" alt="Nixpacks" width="1536" height="864">

Railpack 登場前の主力ビルダー。Nix ベースで再現性は高い。新規 Project は Railpack 既定だが、既存 Project や Nixpacks 固有の設定を持つコードベースは継続利用可。

**👨‍💻 エンジニアへの関係**

「以前 Railway で動いていたが Railpack で謎の挙動」というケースの逃げ場所。`nixpacks.toml` で細かい OS パッケージ指定がある場合は Railpack より楽。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: Railpack で挙動が怪しい既存 repo の fallback として
- 中長期: 新規は Railpack に寄せ、Nixpacks は段階的に廃止

**🔥 差別化点**

- **Cloudflare Pages** や **Vercel** の Buildpacks より OS パッケージ追加が柔軟
- ただし Railpack の登場で Nixpacks 単独の優位性は薄れている

**🔍 深掘り**

- `nixpacks.toml` で `[phases.setup]` / `[start]` などフェーズ単位カスタマイズ
- `NIXPACKS_*` env で挙動制御

**⚠️ 注意点**

- 公式ドキュメントは Nixpacks → Railpack の移行を促す方向。中長期的には削減方向。

---

#### 4.1.4 Dockerfile ビルド

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/57fa9080-r08.png" alt="Dockerfile ビルド" width="1536" height="864">

`Dockerfile` を repo 直下（or 指定パス）に置けば、Railway は自動でそれを使ってビルド。フルコントロールが必要なときの逃げ道。

**👨‍💻 エンジニアへの関係**

特殊 OS、独自バイナリ同梱、multi-stage で artifact を細かく制御したい場合の標準。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: ライフライン業務の Python バッチで native binary（pdftotext 等）が必要な箱
- 中長期: 監査要件で OS 由来 CVE 管理が必要なら Dockerfile 強制運用

**🔥 差別化点**

- 任意 OSS DB やバイナリ込みで動く点は **Vercel / Netlify / Cloudflare Workers** と決定的に違う
- **Render / Fly.io** も Dockerfile 可。差はビルド速度と canvas UX

**🔍 深掘り**

- BuildKit cache mount, `--platform=linux/amd64` 強制、Multi-stage Build 推奨
- `railway.toml` の `[build] builder = "dockerfile"` で明示可

**⚠️ 注意点**

- Dockerfile 経由は Railpack より遅くなることが多い。**安易に Dockerfile 化しない**
- BuildKit cache を効かせないと再ビルドが毎回フルになる

---

#### 4.1.5 Functions（canvas TS デプロイ）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/1526df5f-r09.png" alt="Functions" width="1536" height="864">

GitHub repo を作らずに、Railway canvas 上で TypeScript を直接書いて関数として deploy できる。**sub-second deploy**、cron / webhook 起動、Volume mount まで対応。

**👨‍💻 エンジニアへの関係**

「LLM API を叩いて Slack に通知するだけの 30 行」を、repo 作成・CI 設定・Dockerfile なしで即起動できる。エージェント向けの「**マイクロ自動化**」基盤。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: ライフライン受注通知 Slack bot、Salesforce ↔ 内製 DB の細々した同期 job
- 中長期: Claude / Copilot からの API 呼び出しを Functions に集約して agent 用エンドポイントを社内整備

**🔥 差別化点**

- **Vercel Functions** はフロント repo に紐付くが、Railway Functions は **独立した関数単体** として canvas 配置できる
- **Cloudflare Workers** は edge 分散が強み、Railway Functions は単一 region だが Volume mount で永続化が効く
- **Netlify Functions / DO Functions** より起動速度・DX 双方で優位

**🔍 深掘り**

- TS のみ（v1）。Bun runtime ベース
- HTTP / Cron / Manual trigger
- 同 project 内の Service / DB を private network 経由で参照可
- Volume mount で永続データ扱える

**⚠️ 注意点**

- まだ若い機能、長時間 streaming やバイナリ実行は Service 側に寄せる
- 言語が TS のみ → Python ワーカーは引き続き Service で運用

---

### 4.2 ランタイム・スケーリング層

#### 4.2.1 Service（汎用コンテナ）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/7c6405e7-r10.png" alt="Service" width="1536" height="864">

Railway の最小実行単位。OCI image を 1 つ受け取り、コンテナとして起動・公開・スケールする汎用ランタイム。

**👨‍💻 エンジニアへの関係**

API / Worker / Web フロント / 任意 OSS（n8n, Plausible, MinIO 等）すべての受け皿。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件の API（Node/Express, FastAPI 等）ホスト
- 中長期: 業務システムのマイクロサービス分割を Service 単位で進める

**🔥 差別化点**

- **Render Web Service** より起動速度と canvas 視認性が高い
- **Fly.io machines** は CLI 必須、Railway は GUI/CLI 両対応
- **Cloudflare Workers** はコンテナ非対応、Railway Service は任意 OSS が動く

**🔍 深掘り**

- CPU / Memory は Auto Scale も Manual も可
- Replicas で水平スケール、Public URL は自動で load balance
- Healthcheck path / interval を Service 設定で指定

**⚠️ 注意点**

- Multi-region デプロイは現状未対応（Project の region は 1 つ固定）
- Long-running stateful service は Volume を確実に attach すること

---

#### 4.2.2 Auto Scale（CPU / Memory）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/e2bd7e64-r11.png" alt="Auto Scale" width="1536" height="864">

**👨‍💻 エンジニアへの関係**

トラフィックの波がある API / Worker で、手動チューニング不要に。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 制限あり（上限低） | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 月末集中のライフライン受付サーバーで上限のみ設定して自動拡縮
- 中長期: 業務システムの夜間バッチ縮退、業務時間帯拡張を auto に

**🔥 差別化点**

- **Render** はインスタンスサイズの段階切替、Railway は連続的（より細かい）
- **Heroku** の Performance Dyno より自動化されている

**🔍 深掘り**

- Service ごとに最小 / 最大の vCPU・Memory を設定
- スパイクでは反応遅延あり、事前 warming も検討

**⚠️ 注意点**

- 設定上限を低くしすぎると OOM / CPU throttle、高すぎるとコスト暴騰

---

#### 4.2.3 Replicas（水平スケール）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/e5c8133b-r12.png" alt="Replicas" width="1536" height="864">

**👨‍💻 エンジニアへの関係**

同じ Service を N コピー起動し、Railway LB が round-robin で振り分け。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 制限あり（少数） | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件の本番 API を最低 2 replica で冗長化
- 中長期: ライフライン本番に SLA 提案する際の標準構成

**🔥 差別化点**

- **Render Standard** は冗長 replica 対応、Hobby 互換性は Railway の方が緩い
- **Fly.io** は machines の数を直接指定、Railway は Replica パラメータ 1 つで完結

**🔍 深掘り**

- Stateless 前提。状態は DB / Volume / Bucket に寄せる
- Rolling deploy で順次切替

**⚠️ 注意点**

- WebSocket sticky session が必要な構成は別途実装
- DB connection pool 数 = replicas × per-instance pool で爆発しやすい、PgBouncer 等を挟む

---

#### 4.2.4 Cron Jobs

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/9f47650e-r13.png" alt="Cron Jobs" width="1536" height="864">

**👨‍💻 エンジニアへの関係**

Service / Function に対して cron 式で定期実行を仕掛ける。長時間バッチは Service、短時間は Function 側。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 業務 DB の日次集計、Salesforce 同期、レポート生成
- 中長期: ライフライン日次精算バッチを cron + idempotent 設計で

**🔥 差別化点**

- **Heroku Scheduler** は最小 10 分間隔、Railway は秒〜分単位の柔軟な cron
- **Vercel Cron** は serverless、Railway は long-running も可

**🔍 深掘り**

- cron 式は標準 5 フィールド
- 失敗時の retry / 上書き挙動は手動制御（idempotent 設計推奨）

**⚠️ 注意点**

- ロングランの cron は前回終了前に重複起動しないよう lock を実装
- TZ は UTC 既定、JST はオフセット計算が必要

---

#### 4.2.5 Railway Metal（自社ハードウェア・Beta）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/cca9b9cb-r14.png" alt="Railway Metal" width="1536" height="864">

ハイパースケーラ（AWS/GCP）からの脱依存を進める Railway 独自のハードウェアスタック。**30〜50% のコスト削減** + 高 IOPS を狙う。

**👨‍💻 エンジニアへの関係**

「同じワークロードがクラウド料金より大幅に安く動く」可能性を持つ将来の選択肢。今は Beta、Enterprise 限定。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 不可（招待制） | 利用可（Beta） |

**🏢 ClassLab.での活用**

- 短期: 様子見、本番は AWS / Railway 標準 region
- 中長期: 大規模 worker / DB で Metal 移行のコスト試算をする

**🔥 差別化点**

- 他 PaaS（Render / Fly.io / Heroku）は自前データセンターを持たず AWS / GCP / Equinix 経由
- **Vercel** も Edge は自前だが Compute は AWS 依存

**🔍 深掘り**

- AMD EPYC + NVMe local + 100Gbps NIC 構成（公式 blog より）
- Region は当面 US East のみ

**⚠️ 注意点**

- Beta、SLA 非公開
- 物理障害時の挙動・移行手順がまだ枯れていない

---

### 4.3 データベース層

#### 4.3.1 PostgreSQL（1-click）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/98e9a056-r15.png" alt="PostgreSQL" width="1536" height="864">

canvas で「+ Add Postgres」を選ぶだけで、SSL 有効・私設ネットワーク内の PostgreSQL が起動し、`DATABASE_URL` 環境変数が Service に自動注入される。

**👨‍💻 エンジニアへの関係**

Heroku Postgres / Render Postgres 相当の体験。pgAdmin / TablePlus 連携、Database View で SQL も叩ける。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 案件初期プロトの DB、社内ツール
- 中長期: 中規模 SaaS の主 DB、定期 backup と Restricted Environments で本番ガード

**🔥 差別化点**

- **Render Postgres** とほぼ同等 + 価格優位
- **Fly Postgres** は安いが運用は自前色強い、Railway は完全マネージド
- **Heroku Postgres** は安定だが価格高、Railway は半額程度

**🔍 深掘り**

- 既定 Postgres 17 系、`pg_dump` で backup 可、point-in-time restore は plan 依存
- pgvector 等の拡張は image を変えれば利用可

**⚠️ 注意点**

- Hobby はバックアップ手段が pg_dump 手動、自動 PITR は Pro 以上
- Volume 容量を最初から余裕持って取る（拡張は再起動が要）

---

#### 4.3.2 MySQL

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/30baa8cb-r16.png" alt="MySQL" width="1536" height="864">

PostgreSQL と同じ 1-click 体験で MySQL を提供。レガシー連携や WordPress 系で有用。

**👨‍💻 エンジニアへの関係**

PHP-Laravel / WordPress / 既存 MySQL 資産がある案件で、Postgres に寄せられないケースの受け皿。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託で「MySQL 縛り」の案件のホスティング先
- 中長期: 業務システムは Postgres を標準、MySQL は段階移行候補

**🔥 差別化点**

- **PlanetScale** ほどの vitess スケールは無いが、運用シンプル
- **Render** MySQL より UI と料金が良い

**🔍 深掘り**

- 既定 MySQL 8 系
- Volume backed、Backup は手動 / 自動 plan 依存

**⚠️ 注意点**

- Charset / Collation 設定はデフォルトで utf8mb4 を確認
- Hobby は backup が手薄

---

#### 4.3.3 Redis

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/69e1fbc8-r17.png" alt="Redis" width="1536" height="864">

セッション / キャッシュ / queue 用途の Redis を 1-click。

**👨‍💻 エンジニアへの関係**

BullMQ / Sidekiq / Rails cache / Next.js cache の裏側として使う標準構成。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: Bot / worker のレートリミットや短期キャッシュ
- 中長期: Job queue 基盤として複数 Service で共用

**🔥 差別化点**

- **Upstash** は serverless Redis で edge 強い、Railway は同一 region で低レイテンシ
- **Render Redis** とほぼ同等、価格優位

**🔍 深掘り**

- 既定 Redis 7 系
- Persistence は AOF / RDB 切替可

**⚠️ 注意点**

- Hobby は永続化ストレージが小、本番では Volume サイズを明示
- TLS は private network 内なら不要だが、外部公開時は要設定

---

#### 4.3.4 MongoDB

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/e5cf61f2-r18.png" alt="MongoDB" width="1536" height="864">

ドキュメント DB の代表として MongoDB を 1-click 提供。

**👨‍💻 エンジニアへの関係**

スキーマレスが向く案件（ログ・イベント・ユーザー生成データ）の主 DB。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: ログ集約や A/B 結果保存
- 中長期: MongoDB Atlas との二択になりがち。コスト次第で Railway 選択

**🔥 差別化点**

- **MongoDB Atlas** はフルマネージドの本家、運用は楽だが高価
- Railway は安く済むが backup / sharding は基本機能のみ

**🔍 深掘り**

- 既定 MongoDB 7 系
- Replica Set は基本構成、sharding は手動

**⚠️ 注意点**

- 大規模・analytics 用途は Atlas を選んだ方がよいケースが多い
- Backup は plan 依存

---

#### 4.3.5 Custom DB（Docker Image）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/e1183a96-r19.png" alt="Custom DB" width="1536" height="864">

公式テンプレ以外の DB（ClickHouse / SurrealDB / Cassandra / Qdrant / Weaviate 等）も Docker image を指定すれば動く。

**👨‍💻 エンジニアへの関係**

「Postgres / MySQL / Redis / Mongo では足りない」場合の救済策。Vector DB 等の AI 用途で重要。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 検証用 vector DB（Qdrant / Weaviate）
- 中長期: ライフライン分析用 ClickHouse、ナレッジ検索用 vector DB

**🔥 差別化点**

- **Render / Fly.io** も Docker image で同等可、Railway の差は canvas の見通しの良さ
- **マネージド対応の Postgres/MySQL/Redis/Mongo と同じ canvas に並ぶ** ので統合運用がしやすい

**🔍 深掘り**

- Template Marketplace に主要 OSS DB のレシピが揃う
- Volume mount で永続化、private network で接続

**⚠️ 注意点**

- マネージドではない（backup / failover / メジャーバージョン UP は自己責任）
- 本番運用は専用マネージド DB（Atlas / Aiven / etc）も比較検討

---

### 4.4 ストレージ・ネットワーク層

#### 4.4.1 Volumes（永続ボリューム）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/22c7582a-r20.png" alt="Volumes" width="1536" height="864">

Service にマウントできる永続ボリューム。コンテナが再起動しても残る。

**👨‍💻 エンジニアへの関係**

DB の data dir、アップロードファイル、ローカルキャッシュなどの保管先。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: PDF 生成 worker の作業ディスク
- 中長期: 内製 Docker DB の data 永続化

**🔥 差別化点**

- **Fly.io Volume** とほぼ同等、Railway は GUI で attach できる点が楽
- **Render Disk** より柔軟な size 変更

**🔍 深掘り**

- Size は後から拡張可（縮小は不可）
- Snapshot は plan 依存

**⚠️ 注意点**

- Volume は 1 Service 1 Volume が基本、複数マウントは制限あり
- Replica で水平スケールする Service との相性は悪い（state を持つため）

---

#### 4.4.2 Buckets（S3 互換オブジェクトストレージ・GA）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/293fb1ec-r21.png" alt="Buckets" width="1536" height="864">

2026 GA。S3 互換 API を持つオブジェクトストレージ。**全プランで利用可能**。

**👨‍💻 エンジニアへの関係**

ファイルアップロード、画像、generated artifact、log archive の標準保管先。`aws-sdk` / `@aws-sdk/client-s3` がそのまま使える。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件のユーザーアップロード画像保管
- 中長期: ライフライン書類スキャン保管、AI 出力 artifact

**🔥 差別化点**

- **Cloudflare R2** は egress 無料が強み、Railway は同一 region 内アクセスが高速・安価
- **AWS S3** より UI が canvas 統合で楽、IAM 設定不要
- **DO Spaces / Backblaze B2** より統合運用しやすい

**🔍 深掘り**

- S3 SDK 互換（endpoint / accessKey / secretKey を Bucket から取得）
- 同 project の Service から private network 経由でアクセス可

**⚠️ 注意点**

- 多 region 同期は未対応（単一 region 保管）
- 大量 small object の listing コストは事前確認

---

#### 4.4.3 Private Network

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/d15b13f3-r22.png" alt="Private Network" width="1536" height="864">

同 Project 内の Service / DB / Bucket は自動で private network に join され、`<service>.railway.internal` で互いに名前解決できる。

**👨‍💻 エンジニアへの関係**

API → DB → cache の社内通信は public 露出ゼロで、レイテンシも最小。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: API ↔ Postgres を private で繋ぐ標準構成
- 中長期: 業務システム複数 Service 構成での内部通信

**🔥 差別化点**

- **Render Private Service** より自動化が進む
- **Fly.io 6PN** とコンセプト類似、Railway は GUI で見やすい

**🔍 深掘り**

- DNS suffix: `*.railway.internal`
- IPv6 で内部解決、Public は IPv4

**⚠️ 注意点**

- Cross-project の private network は未対応
- DNS キャッシュで停止時の挙動に注意

---

#### 4.4.4 Custom Domain + TLS 自動

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/62b3a3e4-r23.png" alt="Custom Domain + TLS 自動" width="1536" height="864">

`*.up.railway.app` の標準 URL に加え、独自ドメインを CNAME で割り当て可。**Let's Encrypt 自動更新の TLS 証明書** つき。

**👨‍💻 エンジニアへの関係**

`api.example.com` などプロダクション URL を即時 HTTPS で公開できる。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 案件サブドメインを各 Service にマップ
- 中長期: classlab.co.jp 配下サブドメインを安全に発行

**🔥 差別化点**

- **Heroku** より速い証明書発行
- **Vercel** と同等の DX

**🔍 深掘り**

- Apex ドメインは ALIAS / A レコード対応の DNS が必要
- Wildcard 証明書は Pro+ 想定

**⚠️ 注意点**

- DNS propagation 待ちを考慮
- 既存 CDN（Cloudflare 等）を挟む場合の TLS 経路設計に注意

---

#### 4.4.5 Edge / CDN

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/07b3788b-r24.png" alt="Edge / CDN" width="1536" height="864">

静的アセットや GET レスポンスを Railway Edge にキャッシュ。

**👨‍💻 エンジニアへの関係**

API レスポンスや画像配信を加速。`Cache-Control` ヘッダを正しく設定して活用。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 制限あり | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 画像・JS/CSS bundle のキャッシュ
- 中長期: 重い計算系 API の short TTL キャッシュ

**🔥 差別化点**

- **Cloudflare** や **Vercel Edge** ほどグローバル PoP は多くない（Railway は限定的）
- ただし Service と同 region で integrated に動く

**🔍 深掘り**

- HTTP cache 標準ヘッダ準拠
- Purge は手動 or API

**⚠️ 注意点**

- グローバル分散が必要なら Cloudflare 等を前段に置く構成も検討
- 認証必須 API のキャッシュは事故源、明示的に no-cache

---

### 4.5 環境・コラボレーション層

#### 4.5.1 Environments（Production / Staging / Custom）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/202d6e24-r25.png" alt="Environments" width="1536" height="864">

Project 内に複数の環境（Production / Staging / 任意名）を持てる。**各環境ごとに独立した Service / DB / Volume / 環境変数** を持つ。

**👨‍💻 エンジニアへの関係**

「本番だけ別 DB / 別 API キー」を環境変数の上書きだけで実現。複数案件で標準構成にできる。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件で「お客様デモ env」を追加
- 中長期: 業務システムで本番 / staging / sandbox の 3 環境固定運用

**🔥 差別化点**

- **Vercel** Environments 相当だが、DB ごと分離できる点で完成度高い
- **Render** より柔軟（数の上限が緩い）

**🔍 深掘り**

- 環境間の env / DB をテンプレ化して複製可
- Branch deploy と組み合わせ可

**⚠️ 注意点**

- 環境数が増えると課金も増える、不要 env はこまめに削除
- 環境名の typo に注意（一度切ると追従しにくい）

---

#### 4.5.2 Preview Environments（PR 全スタックコピー）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/34919da4-r26.png" alt="Preview Environments" width="1536" height="864">

PR を開くと **Service / DB / Volume を含む環境一式が複製** され、一意な URL が PR コメントに自動投稿される。merge or close で自動破棄。

**👨‍💻 エンジニアへの関係**

「PR をレビューする際に、本物の DB と本物の API でレビュアーが触れる」体験。**Railway の最大級の差別化要素**。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 制限あり（数少） | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件で「PR 単位でお客様レビュー URL を出す」運用
- 中長期: ライフライン業務システムで仕様変更 PR ごとに完全動作確認

**🔥 差別化点**

- **Vercel Preview** はフロント・API レベル、Railway は DB ごと複製で本物のフルスタック
- **Render Preview Environment** とコンセプト類似、Railway の方が UI 完成度高
- **Fly.io** は手動構成、Railway は自動

**🔍 深掘り**

- DB シード（seed.sql / migration）を実行する hook を仕込める
- 本番データを base にした copy も可（個人情報マスキングは要設計）

**⚠️ 注意点**

- 本番 DB を直接コピーすると個人情報拡散リスク。マスキング seed を使う
- 数が増えるとコスト増、不要 PR の preview は自動破棄設定

---

#### 4.5.3 Restricted Environments（Enterprise）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/5df6a521-r27.png" alt="Restricted Environments" width="1536" height="864">

本番環境への変更を **MFA + 承認制** に固定する Enterprise 機能。SOC 2 / HIPAA 対応の核。

**👨‍💻 エンジニアへの関係**

監査要件が厳しい案件で「だれが・いつ・なぜ本番を変えたか」を強制記録できる。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 制限あり（Beta） | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 様子見
- 中長期: ライフライン業務システム本番に SOC 2 を提案する際の標準オプション

**🔥 差別化点**

- **Heroku Shield**、**AWS Control Tower** 級のガード機構を、シンプル UX で提供
- **Render / Fly.io** にはほぼ同等機能なし

**🔍 深掘り**

- 承認者数・MFA 種別・review TTL を設定可
- Audit Log と連動

**⚠️ 注意点**

- Beta 中の Pro 提供は機能上限あり
- 承認者の体制設計が必須（一人だけだと自己承認）

---

#### 4.5.4 Variables / Secrets 管理

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/1a95deb0-r28.png" alt="Variables / Secrets 管理" width="1536" height="864">

env / secret を canvas で設定、Service にビルド/起動時に注入。

**👨‍💻 エンジニアへの関係**

`DATABASE_URL` 等の DB 接続文字列、API キー、OAuth Secret の正規保管先。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: API キー類の Project ごと管理
- 中長期: 環境間で異なる Secret を Restricted Environments で保護

**🔥 差別化点**

- **Vercel** の env と類似、UI は Railway の方が canvas 配線で直感的
- **AWS SSM Parameter Store / Secrets Manager** ほど高機能ではないが PaaS 用途には十分

**🔍 深掘り**

- Variable Reference: 別 Service の env を参照する記法
- Shared Variables: project 全体で共有

**⚠️ 注意点**

- Build 時 env と Runtime env の区別を意識
- Logs に env を echo しない（漏洩源）

---

#### 4.5.5 Magic Config（AI 設定生成）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/09ca0610-r29.png" alt="Magic Config" width="1536" height="864">

Repo を Railway に接続すると、AI が `railway.toml` / Dockerfile / 環境変数の雛形を **自動提案**。

**👨‍💻 エンジニアへの関係**

新規 repo を持ってきたときの初期設定を AI に任せて 10 分→1 分。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件の初期セットアップ短縮
- 中長期: 案件テンプレと組み合わせて 1 クリック準備

**🔥 差別化点**

- 競合 PaaS でほぼ唯一の「AI ネイティブ初期設定」機能
- **Vercel** の auto framework detect の上位版

**🔍 深掘り**

- 提案は必ず承認制（自動適用しない）
- 多言語 / 複数 entry point の monorepo もサポート

**⚠️ 注意点**

- AI 提案は完璧ではない、レビュー前提
- セキュリティ的な落とし穴（root 実行など）はユーザー側でガード

---

### 4.6 観測性・運用層

#### 4.6.1 Logs（リアルタイム）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/32d7e2e5-r30.png" alt="Logs" width="1536" height="864">

`stdout` / `stderr` を canvas / CLI でリアルタイム閲覧。

**👨‍💻 エンジニアへの関係**

デバッグ初手、本番障害切り分けの基本ツール。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 案件初期のデバッグ
- 中長期: Sentry / Datadog 連携の前段として活用

**🔥 差別化点**

- **Render Logs** / **Heroku Logs** とほぼ同等
- 検索 UI が canvas 統合で速い

**🔍 深掘り**

- Filter / Search が UI で可、CLI でも `railway logs --filter`
- 保持期間は plan 依存（Hobby 短、Pro 長）

**⚠️ 注意点**

- 長期保管・全文検索は外部（Datadog / Better Stack）連携必須
- 個人情報を log に流さないこと

---

#### 4.6.2 Metrics（CPU / Memory / Network）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/1f56db5b-r31.png" alt="Metrics" width="1536" height="864">

CPU / Memory / Disk / Network 等の基本メトリクスを canvas にグラフ表示。

**👨‍💻 エンジニアへの関係**

スケール設計や OOM 検知の基礎データ。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 月末ピークの可視化
- 中長期: SLI / SLO 策定の元データ

**🔥 差別化点**

- **Render Metrics** とほぼ同等
- Prometheus / Datadog 連携は別途

**🔍 深掘り**

- 集約粒度 / 保持期間は plan 依存
- 外部監視には Webhook + 自前 export

**⚠️ 注意点**

- Application 内部メトリクス（事業 KPI）は別途仕込む
- 単一 Service の値で全体を判断しない

---

#### 4.6.3 Webhooks（Deploy Event）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/f3eb2535-r32.png" alt="Webhooks" width="1536" height="864">

deploy / build 完了 / 失敗イベントを任意 URL に POST。

**👨‍💻 エンジニアへの関係**

Slack 通知、内製 dashboard 連携、CI チェーンの起点。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: deploy 通知を Slack へ
- 中長期: deploy 完了で QA E2E を起動する pipeline

**🔥 差別化点**

- **Vercel Deploy Hook** / **Render Deploy Hook** とほぼ同等
- 即時 + 多イベント対応で柔軟性高

**🔍 深掘り**

- payload は JSON、署名検証可
- リトライポリシは公式 doc 参照

**⚠️ 注意点**

- 受け側がダウンしているとイベント欠落の可能性、idempotent 設計に
- secret token を確実に検証

---

#### 4.6.4 Healthchecks

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/822ef93a-r33.png" alt="Healthchecks" width="1536" height="864">

Service の health endpoint を Railway が定期 GET、失敗時は自動再起動。

**👨‍💻 エンジニアへの関係**

zero-downtime deploy + 不健全 instance 自動排除。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 標準 `/health` を全 Service で実装
- 中長期: DB / 外部依存も含めた deep healthcheck

**🔥 差別化点**

- **Render Health Check** とほぼ同等
- Replica と組み合わせて自動 LB 出し入れ

**🔍 深掘り**

- Path / interval / timeout / 失敗閾値を Service 設定で
- Restart policy も連動

**⚠️ 注意点**

- /health が DB アクセスを含むと連鎖障害源、軽量に保つ
- 起動時 grace period を確保

---

### 4.7 セキュリティ・コンプライアンス層

#### 4.7.1 SSO / SAML

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/5991c4cf-r34.png" alt="SSO / SAML" width="1536" height="864">

Google Workspace / Okta / Entra ID 等の SAML IdP と統合し、Railway team workspace への入退を一元管理。

**👨‍💻 エンジニアへの関係**

オフボーディング自動化、最小権限維持の基盤。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 利用可（Beta） | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 様子見、Pro Beta で評価
- 中長期: ライフライン本番管理権限を SAML で統制

**🔥 差別化点**

- **GitHub Enterprise** / **Vercel Enterprise** 級の SSO を Pro Beta から利用可
- **Render** は Enterprise 限定、Railway の方が早期 Pro 提供

**🔍 深掘り**

- IdP メタデータ XML / SAML Response 設定
- SCIM 連携は今後 Enterprise で予定

**⚠️ 注意点**

- SCIM はまだ限定、ユーザー手動追加が残る
- 緊急 break-glass account 設計を別途

---

#### 4.7.2 Audit Log

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/1aa7203c-r35.png" alt="Audit Log" width="1536" height="864">

誰が・いつ・何を変更したかを記録、検索・エクスポート可。

**👨‍💻 エンジニアへの関係**

監査対応、インシデント時の原因追跡。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 制限あり（直近 30 日） | 利用可（無制限） |

**🏢 ClassLab.での活用**

- 短期: Pro Audit を有効化
- 中長期: Enterprise で全量保管、SIEM 連携

**🔥 差別化点**

- **Render** / **Fly.io** 同等機能あり、Railway は UI 統合度が高い
- **AWS CloudTrail** よりライト

**🔍 深掘り**

- CSV / JSON export
- Webhook で外部 SIEM ストリーミング（Enterprise）

**⚠️ 注意点**

- 30 日上限を超える保管は Enterprise 必須
- 個人情報を含むイベントの取り扱い注意

---

#### 4.7.3 SOC 2 / HIPAA

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/c0abe0ab-r36.png" alt="SOC 2 / HIPAA" width="1536" height="864">

Restricted Environments + Audit Log + 暗号化を組み合わせた監査対応。Enterprise 限定で BAA / 監査レポート提供。

**👨‍💻 エンジニアへの関係**

医療・金融・公共系案件で必須。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 不可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 該当案件なら Enterprise 検討
- 中長期: ライフライン延長として医療系 SaaS の受託で活用可能性

**🔥 差別化点**

- **Heroku Shield** や **AWS** に並ぶ Compliance offering
- Railway は新しいが、Enterprise tier で本格対応進む

**🔍 深掘り**

- BAA 締結プロセス、Audit レポート（SOC 2 Type II）取得
- Restricted Env と Audit Log セット運用

**⚠️ 注意点**

- 契約・法務確認必須
- 自社運用ポリシも更新が必要

---

#### 4.7.4 IP Allowlist

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/480f611d-r37.png" alt="IP Allowlist" width="1536" height="864">

特定 IP / CIDR からのみ Service へのアクセスを許可。

**👨‍💻 エンジニアへの関係**

社内ツール、社内 VPN 経由のみアクセス可、外部からの侵入を物理的にブロック。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 不可 | 不可 | 制限あり | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 社内 dashboard を社内 IP のみに
- 中長期: ライフライン管理画面を VPN 限定に

**🔥 差別化点**

- **AWS Security Group** / **Cloudflare Access** ほど高機能ではないが PaaS としては標準
- **Render** にも類似機能

**🔍 深掘り**

- CIDR 範囲指定、複数許可可
- API endpoint 単位の制御は別途 application 層で

**⚠️ 注意点**

- VPN ゲートウェイの IP が変わる場合の運用追従
- IP では認証にならない、必ず auth と組み合わせ

---

### 4.8 API / CLI / 拡張層

#### 4.8.1 Railway CLI v4

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/0de07ba0-r38.png" alt="Railway CLI v4" width="1536" height="864">

`railway` CLI。Bun ベースに刷新（v4）。`railway up`（deploy）/ `railway run`（環境変数を引き継いでローカル実行）/ `railway logs` / `railway shell` / `railway link` 等。

**👨‍💻 エンジニアへの関係**

ローカル開発 → Railway へ scaffold、env 引き継ぎ、CI から deploy など。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: CI から `railway up` で deploy
- 中長期: 内製スクリプトに組み込み、定型 deploy を自動化

**🔥 差別化点**

- **Vercel CLI** / **Render CLI** より統合度が高い（DB / Service / Volume すべて操作可）
- **Fly.io CLI**（flyctl）は強力だが複雑、Railway は学習コスト低

**🔍 深掘り**

- `railway run npm test` でローカル env を Railway secret で実行
- `railway shell` で本番コンテナに入って即時調査

**⚠️ 注意点**

- `railway shell` は本番への作用に注意（read-only 運用が無難）
- 認証 token の取り扱い

---

#### 4.8.2 Public GraphQL API

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/63e085e2-r39.png" alt="Public GraphQL API" width="1536" height="864">

Railway の全機能を GraphQL で叩ける Public API。

**👨‍💻 エンジニアへの関係**

社内 dashboard 連携、CI 統合、Terraform 代替の独自スクリプト。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: deploy 状況を社内 chatbot で照会
- 中長期: 案件 lifecycle 管理を Railway API で自動化

**🔥 差別化点**

- 競合 PaaS で GraphQL Public API を持つのは少数
- **Vercel** は REST、Railway は GraphQL で query 効率が良い

**🔍 深掘り**

- Endpoint: `https://backboard.railway.com/graphql/v2`
- Authentication: API token（Project / User）

**⚠️ 注意点**

- Rate Limit あり
- destructive mutation は確認 step 推奨

---

#### 4.8.3 Template Marketplace

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/904040ed-r40.png" alt="Template Marketplace" width="1536" height="864">

OSS スタック / SaaS 風アプリの 1-click deploy テンプレ集。MinIO / Plausible / Ghost / n8n / Strapi / Supabase OSS 等。

**👨‍💻 エンジニアへの関係**

新規 OSS 評価を最短化。社内 PoC・採用判断の前段で活用。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: OSS 評価 PoC（n8n, Plausible, ...）
- 中長期: 内製テンプレを社内 marketplace 化（private template）

**🔥 差別化点**

- **Render Template Library** より数・更新頻度ともに優位
- **Cloudflare** にも一部あるが Railway のフルスタック性で勝つ

**🔍 深掘り**

- Public template は GitHub オープン、PR で改善可
- Private template で社内共有可

**⚠️ 注意点**

- Template の品質はまちまち、本番採用前に内部レビュー
- 後継メンテが止まっているものに注意

---

#### 4.8.4 GitHub App

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/e1d8a11b-r41.png" alt="GitHub App" width="1536" height="864">

Railway が公式提供する GitHub App。push / PR / status check を双方向連携。

**👨‍💻 エンジニアへの関係**

PR レビューに Railway preview の URL と status を自動表示、GitHub UI から離れず確認可。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 受託案件 repo に標準導入
- 中長期: GitHub 中心の社内開発標準フローに組み込む

**🔥 差別化点**

- **Vercel GitHub App** と類似 DX
- Railway は DB を含む preview の status まで返してくれる

**🔍 深掘り**

- Install 時に repo permission を最小化
- branch protection の必須 status に Railway を追加可

**⚠️ 注意点**

- App permission の付与範囲、organization 単位の見直し

---

#### 4.8.5 Terraform Provider（community）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/51d9df29-r42.png" alt="Terraform Provider" width="1536" height="864">

community メンテの Terraform Provider。Project / Service / Env / Volume を IaC で記述。

**👨‍💻 エンジニアへの関係**

複数 project の標準構成を再現可能にする。AWS Terraform と同じ感覚で Railway を IaC 管理。

**💳 利用可能プラン**

| Trial | Hobby | Pro | Enterprise |
|:-:|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 | 利用可 |

**🏢 ClassLab.での活用**

- 短期: 案件初期に terraform で雛形展開
- 中長期: 社内テンプレを IaC 化、deploy 標準化

**🔥 差別化点**

- 公式ではない（community）ため挙動の安定性は要確認
- **Vercel** や **Render** にも community Terraform Provider あり、機能網羅率は同等程度

**🔍 深掘り**

- リソース: project / service / variable / volume / custom_domain 等
- Authentication: API token

**⚠️ 注意点**

- 公式サポートではない（Railway 公式 issue 対応はベストエフォート）
- Schema drift / TF state 管理は通常通り注意

---

## 5. プラン早見表（全機能 × プラン マトリクス）

| カテゴリ | 機能 | Trial | Hobby | Pro | Enterprise |
|---|---|:-:|:-:|:-:|:-:|
| デプロイ | Git Push Deploy | 利用可 | 利用可 | 利用可 | 利用可 |
| デプロイ | Railpack | 利用可 | 利用可 | 利用可 | 利用可 |
| デプロイ | Nixpacks | 利用可 | 利用可 | 利用可 | 利用可 |
| デプロイ | Dockerfile | 利用可 | 利用可 | 利用可 | 利用可 |
| デプロイ | Functions | 利用可 | 利用可 | 利用可 | 利用可 |
| ランタイム | Service | 利用可 | 利用可 | 利用可 | 利用可 |
| ランタイム | Auto Scale | 制限あり (上限低) | 利用可 | 利用可 | 利用可 |
| ランタイム | Replicas | 不可 | 制限あり (少数) | 利用可 | 利用可 |
| ランタイム | Cron Jobs | 利用可 | 利用可 | 利用可 | 利用可 |
| ランタイム | Railway Metal | 不可 | 不可 | 不可（招待） | 利用可（Beta） |
| DB | PostgreSQL | 利用可 | 利用可 | 利用可 | 利用可 |
| DB | MySQL | 利用可 | 利用可 | 利用可 | 利用可 |
| DB | Redis | 利用可 | 利用可 | 利用可 | 利用可 |
| DB | MongoDB | 利用可 | 利用可 | 利用可 | 利用可 |
| DB | Custom DB (Docker) | 利用可 | 利用可 | 利用可 | 利用可 |
| ストレージ | Volumes | 利用可 | 利用可 | 利用可 | 利用可 |
| ストレージ | Buckets (S3 互換) | 利用可 | 利用可 | 利用可 | 利用可 |
| ネットワーク | Private Network | 利用可 | 利用可 | 利用可 | 利用可 |
| ネットワーク | Custom Domain + TLS | 利用可 | 利用可 | 利用可 | 利用可 |
| ネットワーク | Edge / CDN | 制限あり | 利用可 | 利用可 | 利用可 |
| 環境 | Environments | 利用可 | 利用可 | 利用可 | 利用可 |
| 環境 | Preview Environments | 制限あり (数少) | 利用可 | 利用可 | 利用可 |
| 環境 | Restricted Env | 不可 | 不可 | 制限あり (Beta) | 利用可 |
| 環境 | Variables/Secrets | 利用可 | 利用可 | 利用可 | 利用可 |
| 環境 | Magic Config | 利用可 | 利用可 | 利用可 | 利用可 |
| 観測性 | Logs | 利用可 | 利用可 | 利用可 | 利用可 |
| 観測性 | Metrics | 利用可 | 利用可 | 利用可 | 利用可 |
| 観測性 | Webhooks | 利用可 | 利用可 | 利用可 | 利用可 |
| 観測性 | Healthchecks | 利用可 | 利用可 | 利用可 | 利用可 |
| セキュリティ | SSO/SAML | 不可 | 不可 | 利用可 (Beta) | 利用可 |
| セキュリティ | Audit Log | 不可 | 不可 | 制限あり (30 日) | 利用可 (無制限) |
| セキュリティ | SOC 2 / HIPAA | 不可 | 不可 | 不可 | 利用可 |
| セキュリティ | IP Allowlist | 不可 | 不可 | 制限あり | 利用可 |
| API/拡張 | Railway CLI v4 | 利用可 | 利用可 | 利用可 | 利用可 |
| API/拡張 | Public GraphQL API | 利用可 | 利用可 | 利用可 | 利用可 |
| API/拡張 | Template Marketplace | 利用可 | 利用可 | 利用可 | 利用可 |
| API/拡張 | GitHub App | 利用可 | 利用可 | 利用可 | 利用可 |
| API/拡張 | Terraform Provider | 利用可 | 利用可 | 利用可 | 利用可 |

---

## 6. 料金体系の詳細

### 6.1 プラン別の含み枠と超過料金

| プラン | 月額 | 含まれる credit | 超過時 vCPU | 超過時 RAM | 超過時 Egress | Volume | Bucket |
|---|---|---|---|---|---|---|---|
| Trial | $0 | $5 / 一回 | 不可（credit 切れで停止） | 同左 | 同左 | 含み枠内 | 含み枠内 |
| Hobby | $5 | $5 | $20 / vCPU・月 | $10 / GB・月 | $0.10 / GB（100 GB 無料）| $0.25 / GB・月 | $0.023 / GB・月 |
| Pro | $20 / seat | $20 / seat | 同上 | 同上 | 同上 | 同上 | 同上 |
| Enterprise | $2,000 〜 / 月 | 契約額 | カスタム | カスタム | カスタム | カスタム | カスタム |

> **Active CPU 課金**: 実際に CPU を使っている時間のみ課金。アイドル時は CPU 0 円、メモリ確保分のみ。

### 6.2 競合との料金構造の違い

| プラットフォーム | 料金モデル | 月額固定 | 従量 | 含み枠 | 強み | 弱み |
|---|---|:-:|:-:|---|---|---|
| Railway | 月額 + 従量 | あり | あり | $5 / $20 / 契約額 | scale-to-zero と include 枠 | グローバル分散弱い |
| Render | 月額固定 | あり | 一部 | プランごとに instance 数 | コスト見積りやすい | scale-to-zero は限定 |
| Fly.io | 従量のみ | なし | あり | $5 / 月 free 枠 | リージョン分散 / 安い | 学習コスト |
| Vercel | プラン + 従量 | あり | あり | プランごと | フロントエンド体験 | バックエンドは高くつく |
| Heroku | Dyno 月額 | あり | なし | Dyno 数 | 安定 | 高価 / レガシー |
| AWS App Runner | 従量のみ | なし | あり | なし | AWS 資産統合 | 学習コスト高 |
| Cloudflare Workers | リクエスト数 + 時間 | あり (low) | あり | 100k req/日 free | edge 分散 / egress 無料 | コンテナ不可 |
| Netlify | プラン + 従量 | あり | あり | プランごと | 静的 + Edge | バック弱い |
| DO App Platform | インスタンス月額 | あり | あり | プランごと | DO 全体統合 | UX が古い |
| Northflank | プラン + 従量 | あり | あり | プランごと | k8s / job runner | コミュニティ小 |
| Coolify (OSS 自社ホスト) | サーバ実費 | なし | なし | なし | 完全自己管理 | 運用は自分 |

### 6.3 コスト最適化の勘所

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/c481dda3-r43.png" alt="Terraform Provider" width="1536" height="864">

**実務的なコスト下げ方トップ 5**:

1. **Active CPU 課金を理解する**: idle 時は CPU 課金されないので、API が常時 0〜10% で動くなら過剰スケールを避ける
2. **Egress > 100 GB は CDN を前段に**: Cloudflare 等を挟む / 画像は Bucket + signed URL
3. **不要 Preview Environments を自動破棄**: PR close で必ず破棄、長期 stale は monthly cron で削除
4. **Volume のサイズ過剰を避ける**: 拡張は容易、縮小は不可なので初期は控えめに
5. **Hobby → Pro の損益分岐**: 月 $20 を超える資源を使う見込みなら Pro 化（credit が seat ごとに $20 入る）

---

## 7. ClassLab. での活用ロードマップ（汎用例）

### 7.1 短期（〜3ヶ月）の活用候補

| 用途 | 業務領域 | Railway 構成 | 既存代替 | 効果 |
|---|---|---|---|---|
| 受託案件の検証環境 | 受託開発 | Service + Postgres + Preview Environments | Vercel + Render 個別 | PR 単位 URL でレビュー高速化 |
| 社内ツール（dashboard / bot） | 共通基盤 | Service + Postgres + Redis | AWS EC2 + RDS | 運用工数大幅減 |
| AI worker（Slack bot / 通知 bot）| AI ハイブリッド | Functions / Service | AWS Lambda | repo 不要・即時 deploy |
| OSS 評価 PoC | 共通基盤 | Template Marketplace | 自前 docker-compose | 評価開始まで 5 分 |
| ライフライン受注通知 bot | ライフライン事業 | Function + Slack | Zapier | 内製化、コスト最適化 |

### 7.2 中長期（3〜12ヶ月）の活用候補

| 用途 | 業務領域 | Railway 構成 | 移行候補 | 効果 |
|---|---|---|---|---|
| ライフライン staging | ライフライン事業 | 複数 Environments + Bucket | AWS staging | コスト削減・速度向上 |
| 業務システムマイクロサービス分割 | 業務システム | 複数 Service + private network | モノリス | 段階移行・独立 deploy |
| 案件テンプレ IaC 化 | 受託開発 | Terraform + Template | 手動セットアップ | 案件初期工数 50% 減 |
| AI agent API ゲートウェイ | AI ハイブリッド | Functions + Magic Config | 個別実装 | 統一窓口 / 再利用 |
| 監査要件あり案件 | 規制業種受託 | Restricted Env + Audit Log + SSO | AWS Control Tower | Enterprise 契約で対応 |

### 7.3 既存資産棚卸し（推奨アクション）

- **Vercel 上の API routes** → 長時間処理を要するものは Railway Service へ移行検討（Vercel Function の制約回避）
- **AWS EC2 上の社内 worker** → Railway Service + cron / Functions に置き換え検討
- **AWS RDS（小規模）** → Railway Postgres へ移行検討（コスト / 運用工数比較）
- **個別ホスティング先（受託案件で散在）** → Railway 標準テンプレに集約検討
- **Docker Compose 開発環境** → Railway Template でメンバー間共有可

---

## 8. 採用判断フロー

### 8.1 新規プロジェクトでの選択フロー

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/78e5c1b8-r44.png" alt="Terraform Provider" width="1536" height="864">

### 8.2 採用適性 Quadrant

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/railway-features-catalog-2026-05/3077622d-r45.png" alt="Terraform Provider" width="1536" height="864">

**ClassLab. 視点での中長期目標位置**: 受託 / 業務システムは Railway Pro 〜 Enterprise を活用、ライフライン本番でコンプラ要件が立ち上がれば Railway Enterprise + Restricted Environments + Audit Log、または並走で AWS。AI ハイブリッド系は Railway Functions に集約。

---

## 9. 公式リファレンス & Sources

### 9.1 公式ドキュメント（Top-level）

- [Railway 公式 features](https://railway.com/features)
- [Railway Docs ホーム](https://docs.railway.com/)
- [The Basics](https://docs.railway.com/overview/the-basics)
- [Pricing](https://railway.com/pricing)
- [Pricing Plans Docs](https://docs.railway.com/pricing/plans)

### 9.2 機能別ドキュメント

- [Railway Metal](https://docs.railway.com/platform/railway-metal)
- [Databases — Overview](https://docs.railway.com/databases)
- [PostgreSQL](https://docs.railway.com/databases/postgresql)
- [MySQL](https://docs.railway.com/databases/mysql)
- [Redis](https://docs.railway.com/databases/redis)
- [Database View](https://docs.railway.com/databases/database-view)
- [Build a Database Service (Custom DB)](https://docs.railway.com/databases/build-a-database-service)
- [Template Marketplace 例: OpenWA (Postgres+Redis+MinIO)](https://railway.com/deploy/openwa-w-postgres-redis-and-minio)

### 9.3 参照した Web Sources

- [Railway Series A — Redpoint Ventures](https://www.redpoint.com/content-hub/video/railway-series-a/)
- [Railway Raises $100M Series B (2026-01) — Yahoo Finance](https://finance.yahoo.com/news/railway-raises-100-million-series-140100124.html)
- [Railway $100M Series B 詳細 — SiliconANGLE](https://siliconangle.com/2026/01/22/intelligent-cloud-infrastructure-startup-railway-gets-100m-simplify-application-deployment/)
- [Railway: The Agent-Native Cloud — Jake Cooper (Latent Space)](https://www.latent.space/p/railway)
- [Jake Cooper on Railway's "Agent-Native Cloud" — StartupHub.ai](https://www.startuphub.ai/ai-news/technology/2026/jake-cooper-on-railway-s-agent-native-cloud)
- [Solving the Hardest Problems in Dev Tools — Jake Cooper](https://www.thespl.it/p/solving-the-hardest-problems-in-dev)
- [Railway Review 2026 — Scribe](https://scribehow.com/page/Railway_Review_2026_The_Cloud_Deployment_Platform_Developers_Are_Quietly_Switching_To__MWY5FbWoSFO2qF55Vz9bgQ)
- [Railway Review 2026 — srvrlss.io](https://www.srvrlss.io/provider/railway/)
- [Railway.app Review 2026 — ReviewAITool Blog](https://blog.reviewaitool.com/2026/04/08/railway-app-review-2026/)
- [Railway Reviews 2026 — G2](https://www.g2.com/products/railway/reviews)
- [Railway Free Tier 2026 — saaspricepulse](https://www.saaspricepulse.com/tools/railway)
- [Railway Pricing 2026 — thesoftwarescout](https://thesoftwarescout.com/railway-pricing-2026-plans-costs-is-it-worth-it/)
- [Railway Pricing 2026 — costbench](https://costbench.com/software/developer-tools/railway/)
- [Railway vs Render 比較 — Northflank Blog](https://northflank.com/blog/railway-vs-render)
- [Railway vs Render vs Fly.io for Solo Developers — devtoolpicks](https://devtoolpicks.com/blog/railway-vs-render-vs-fly-io-solo-developers-2026)
- [Railway vs Fly.io 2026 — saaspricepulse](https://www.saaspricepulse.com/compare/railway-vs-flyio-vs-render)
- [Heroku vs Railway vs Render vs Fly.io — thesoftwarescout](https://thesoftwarescout.com/heroku-vs-railway-vs-render-vs-fly-io-2026-which-platform-should-you-deploy-on/)
- [Fly.io vs Railway vs Render vs Coolify: 2026 — devtoolreviews](https://www.devtoolreviews.com/reviews/fly-io-vs-railway-vs-render-vs-coolify-2026)
- [Render vs Heroku vs Vercel vs Railway vs Fly.io vs AWS — Ritza](https://ritza.co/articles/gen-articles/render-vs-heroku-vs-vercel-vs-railway-vs-fly-io-vs-aws/)
- [Heroku vs Render vs Vercel vs Fly.io vs Railway — BoltOps](https://blog.boltops.com/2025/05/01/heroku-vs-render-vs-vercel-vs-fly-io-vs-railway-meet-blossom-an-alternative/)
- [Railway Release Notes — Releasebot](https://releasebot.io/updates/railway)
- [Introducing Railway Metal Beta — Railway Help Station](https://station.railway.com/feedback/introducing-railway-metal-beta-920458ce)
- [Best Railway Alternative — Out Plane](https://outplane.com/blog/railway-alternative)
