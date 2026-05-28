
## 目次

- [Hacker News](#hacker-news)
  - [1. ハードウェア・アテステーションは独占を加速させる](#1-ハードウェアアテステーションは独占を加速させる)
  - [2. ローカルAIこそが標準になるべき](#2-ローカルaiこそが標準になるべき)
  - [3. Bambu Lab がオープンソースの社会契約を破壊している](#3-bambu-lab-がオープンソースの社会契約を破壊している)
  - [4. TanStack npm サプライチェーン侵害 ポストモーテム](#4-tanstack-npm-サプライチェーン侵害-ポストモーテム)
  - [5. 私はコードを手書きに戻す](#5-私はコードを手書きに戻す)
  - [6. AIがコードを書く時代に、なぜPythonを使うのか](#6-aiがコードを書く時代になぜpythonを使うのか)
  - [7. Mythos が curl の脆弱性を発見](#7-mythos-が-curl-の脆弱性を発見)
  - [8. GitLab が人員削減と CREDIT バリューの撤回を発表](#8-gitlab-が人員削減と-credit-バリューの撤回を発表)
  - [9. Gmail 登録時に QR コードと SMS 送信が必須化](#9-gmail-登録時に-qr-コードと-sms-送信が必須化)
  - [10. ソフトウェアエンジニアリングはもはや終身キャリアではない](#10-ソフトウェアエンジニアリングはもはや終身キャリアではない)
- [Anthropic](#anthropic)
  - [11. Claude Opus 4.7 リリース](#11-claude-opus-47-リリース)
  - [12. Anthropic × SpaceX 300MW・22万 GPU 契約](#12-anthropic--spacex-300mw22万-gpu-契約)
  - [13. Anthropic が金融エージェント・テンプレート10種をリリース](#13-anthropic-が金融エージェントテンプレート10種をリリース)
  - [14. Claude Microsoft 365 連携 GA + Outlook ベータ](#14-claude-microsoft-365-連携-ga--outlook-ベータ)
  - [15. SAP × Anthropic Joule に Claude を組み込む戦略提携](#15-sap--anthropic-joule-に-claude-を組み込む戦略提携)
- [Claude Code リリースノート](#claude-code-リリースノート)
  - [16. v2.1.139 エージェントビューと /goal コマンドが登場](#16-v21139-エージェントビューと-goal-コマンドが登場)
  - [17. v2.1.140 subagent\_type マッチング改善とバグ修正](#17-v21140-subagent_type-マッチング改善とバグ修正)
  - [18. v2.1.136 autoMode.hard\_deny / OAuth 修正](#18-v21136-automodehard_deny--oauth-修正)
- [OpenAI リリースノート](#openai-リリースノート)
  - [19. OpenAI Realtime API 2（GPT-Realtime-2 / Translate / Whisper）GA](#19-openai-realtime-api-2gpt-realtime-2--translate--whispergా)
  - [20. GPT-5.5 Instant がデフォルトに](#20-gpt-55-instant-がデフォルトに)
  - [21. ChatGPT Excel / Google Sheets サイドバー](#21-chatgpt-excel--google-sheets-サイドバー)
  - [22. ChatGPT Fast answers ロールアウト](#22-chatgpt-fast-answers-ロールアウト)
- [Salesforce](#salesforce)
  - [23. Agentforce Operations でバックオフィスを分解](#23-agentforce-operations-でバックオフィスを分解)
  - [24. Summer '26 リリースと IT Service Domain Pack](#24-summer-26-リリースと-it-service-domain-pack)
  - [25. Q1 FY27 決算は 5月27日 発表](#25-q1-fy27-決算は-5月27日-発表)
- [Zoom Phone](#zoom-phone)
  - [26. Zoom Phone にリアルタイム字幕翻訳が登場](#26-zoom-phone-にリアルタイム字幕翻訳が登場)
- [GitHub トレンド（直近2ヶ月以内に作成）](#github-トレンド直近2ヶ月以内に作成)
  - [27. ultraworkers/claw-code](#27-ultraworkersclaw-code)
  - [28. JuliusBrussee/caveman](#28-juliusbrusseecaveman)
  - [29. MemPalace/mempalace](#29-mempalacemempalace)
  - [30. safishamsi/graphify](#30-safishamsigraphify)
  - [31. nexu-io/open-design](#31-nexu-ioopen-design)

---

## Hacker News

### 1. ハードウェア・アテステーションは独占を加速させる
- **原題**: Hardware Attestation as Monopoly Enabler
- **スコア**: 2150pt / コメント: 749件
- **URL**: https://grapheneos.social/@GrapheneOS/116550899908879585
- **要約**: GrapheneOS が、ハードウェアアテステーション（端末の真正性を OS とハード側で保証する仕組み）が Google/Apple の独占を強化し、サードパーティ OS や代替アプリストアを締め出す方向に使われていると警告。プラットフォーマーが「セキュリティ」を名目に競合排除する流れが続いていることを批判した内容。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFEアプリのリリース時に Android のSafetyNet/Play Integrity API への依存を最小化し、Webコンポーネント・PWA で代替可能なフローを残しておく。プラットフォーム規約変更で締め出されるリスクの予備分析を完了させる。

##### 3年以内
ライフライン契約代行のお客様向け本人確認・電子契約フローを、Apple Wallet/Google Wallet のような独占基盤にロックインしない設計に進化させる。eKYC ベンダーを複数化し代替可能性を仕組み化する。

##### 3年以上
独占型プラットフォーム上での集客依存（App Store・Google）を縮小し、引越し代行を入口にしたファーストパーティ顧客接点（メディア・LINEミニアプリ・SMS・自社アプリの直接配信）へ重心を移す事業ポートフォリオに転換する。
:::

---

### 2. ローカルAIこそが標準になるべき
- **原題**: Local AI needs to be the norm
- **スコア**: 1844pt / コメント: 735件
- **URL**: https://unix.foo/posts/local-ai-needs-to-be-norm/
- **要約**: 個人の生成AI利用が API 経由でクラウドに集中しているが、プライバシー・コスト・主権の観点でローカル実行（Ollama, llama.cpp 等）がデフォルトであるべきだという主張。手元GPUの能力向上と Llama 系オープンモデルの台頭で実用ラインに到達したと論じる。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コールセンター録音の文字起こしや、ライフライン申込書面の AI-OCR 後処理をクラウドではなく社内 GPU 上の Ollama / llama.cpp で完結させる PoC を実施する。Salesforce レコードに上げる前に個人情報をマスキングする前処理に当てる。

##### 3年以内
個人情報を含む業務（NW事業部の与信判定、CX事業部の通話モニタリング）はオンプレ LLM でリファレンス実装を統一し、API 通信を要件とする業務とそうでない業務を組織的に切り分ける標準を確立する。

##### 3年以上
不動産会社 4,000 社との連携モデルを「相手側に閉じたローカル AI を ClassLab. が配布する」形に進化させ、データを移動させずに業務協調できるエッジ AI プロトコルを業界標準として提案する。
:::

---

### 3. Bambu Lab がオープンソースの社会契約を破壊している
- **原題**: Bambu Lab is abusing the open source social contract
- **スコア**: 1124pt / コメント: 371件
- **URL**: https://www.jeffgeerling.com/blog/2026/bambu-lab-abusing-open-source-social-contract/
- **要約**: 大手 3D プリンタメーカー Bambu Lab が OSS コミュニティのスライサー実装を取り込みながら独自仕様で囲い込みを進め、コミュニティへの還元を怠っているという批判記事。OSSライセンスの「形式遵守」と「精神的契約」の乖離が議論を呼んだ。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内で利用している OSS（Salesforce Apex フレームワーク、Next.js、Claude Code プラグイン）の依存リストを棚卸しし、ライセンス順守と「コントリビューションで返す」の双方をエンジニア行動指針に明文化する。

##### 3年以内
自社で構築した AI-OCR 周辺ツールやライフライン業界向けユーティリティを部分 OSS 化し、業界内エコシステムを引き寄せる戦略をとる。Bambu Lab の反面教師としてガバナンスとライセンスの透明性を担保する。

##### 3年以上
ClassLab. が業界で OSS の旗振り役になり、不動産・引越し・ライフラインのエコシステム標準を握る位置取りを目指す。クローズドな独占を狙うのではなく、オープン基盤の上で運用力で勝つビジネスモデルに転換する。
:::

---

### 4. TanStack npm サプライチェーン侵害 ポストモーテム
- **原題**: Postmortem: TanStack NPM supply-chain compromise
- **スコア**: 1061pt / コメント: 446件
- **URL**: https://tanstack.com/blog/npm-supply-chain-compromise-postmortem
- **要約**: 人気 OSS の TanStack（React Query 等）の npm パッケージがメンテナのトークン漏えい経由で侵害されたインシデントの一次資料。フィッシング → 2FAバイパス → 公開トークン悪用という典型的な経路と、影響範囲・恒久対策（OIDC 公開、Trusted Publishers）を公開した。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/ad4ae5ba-dia-tanstack-supply-20260513-123541-1.png" alt="TanStack npm サプライチェーン侵害の侵入経路と対策" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内 Next.js/Node プロジェクトの依存ロックを厳密化し、`npm audit signatures` と Snyk による署名検証を CI に組み込む。Salesforce DX パッケージや RIRIFE iOS/Android アプリの SDK 依存を含めて棚卸する。

##### 3年以内
npm/PyPI/Maven の Trusted Publisher（OIDC ベース署名）導入をパッケージ公開時の標準にし、社内 OSS 化されるツール群はトークンを保管しない CI 構成に統一する。

##### 3年以上
ライフライン契約代行プラットフォームのソフトウェアサプライチェーンを SBOM 必須化し、不動産会社・電力会社・ガス会社との B2B 連携で「上流改ざんに耐える契約データ流通」を業界標準として整備する。
:::

---

### 5. 私はコードを手書きに戻す
- **原題**: I'm going back to writing code by hand
- **スコア**: 995pt / コメント: 601件
- **URL**: https://blog.k10s.dev/im-going-back-to-writing-code-by-hand/
- **要約**: AI コード生成に依存しすぎた結果、コードの理解度・設計眼・学習効果が落ちたと感じた開発者が、意図的に AI 補助を切って手書きに戻した体験談。AI を「使うべきフェーズ」と「使うべきでないフェーズ」を分ける運用ガイドが共感を呼んだ。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部内で「Claude Code を使うべき作業／使うべきでない作業」の運用ルールを 1 ページにまとめる。テストコードと既存リファクタは積極活用、新規ドメインモデリングは AI 抜きで初稿を書く、などのレーンを定義する。

##### 3年以内
ジュニアエンジニアの育成プログラムに「AI 補助なし期間」を必修化し、3 ヶ月 → 6 ヶ月で AI 解禁する段階設計に組み替える。Salesforce Apex / SOQL を手書きできるスキルレベルを採用基準にも反映する。

##### 3年以上
AI 開発支援が標準になった世界で「人が書いたコード」を品質ブランドとして打ち出す内製プロダクト戦略を検討する。OSS 公開ライブラリで「人が設計・テスト責任を持つ」明示ラベルを掲げる方向もあり得る。
:::

---

### 6. AIがコードを書く時代に、なぜPythonを使うのか
- **原題**: If AI writes your code, why use Python?
- **スコア**: 853pt / コメント: 916件
- **URL**: https://medium.com/@NMitchem/if-ai-writes-your-code-why-use-python-bf8c4ba1a055
- **要約**: AI が書きやすいから Python が選ばれるという建前が崩れたとき、Python の動的型・実行速度・パッケージング問題が浮き彫りになる、という挑発的な記事。LLM が型情報を活用しやすい Rust / Go / TypeScript への重心シフトを示唆。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
新規バッチ・スクリプト系（AI-OCR 後処理、Salesforce ETL）の言語選定を再評価し、TypeScript / Go を候補に加える。AI が出力するコードのレビュー負荷が下がる型付き言語の利点を数値化する。

##### 3年以内
データ分析・ML パイプライン以外の Python 資産（コーポレート部門の自動化、内部ツール）を TypeScript / Bun に段階移行する基準を設ける。Claude Code 等のエージェントとの組み合わせで「型 → テスト → 実装」のループが回せる言語に寄せる。

##### 3年以上
社内エンジニアリングの第一言語を TypeScript に統一しつつ、AI と人の役割分担を前提とした「型ファーストな業務 DSL」を内製する。ライフライン業界の取引データを型として表現することで、不動産会社との API 連携も安全化する。
:::

---

### 7. Mythos が curl の脆弱性を発見
- **原題**: Mythos Finds a Curl Vulnerability
- **スコア**: 681pt / コメント: 280件
- **URL**: https://daniel.haxx.se/blog/2026/05/11/mythos-finds-a-curl-vulnerability/
- **要約**: AI ベースのセキュリティ研究エージェント Mythos が curl に脆弱性を発見し、メンテナの Daniel Stenberg が一連の経緯と評価を公開。AI による真のバグハント（誤検知の山ではなく、再現可能で実害のある報告）の最初の実例に近いと業界が注目。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内で利用している OSS（curl / OpenSSL / Node ランタイム）の脆弱性ウォッチを Mythos のような AI セキュリティエージェント前提に切り替え、検知 → Slack 通知 → 自動 PR 作成までを Claude Code でつなぐ。

##### 3年以内
ライフライン申込フロー・コールセンター録音・顧客 PII を扱うアプリケーションに、AI セキュリティレビューを CI に組み込み、リリース前検査の必須項目にする。Salesforce のセキュリティ設定変更にも適用する。

##### 3年以上
AI が脆弱性を見つけ、AI が修正 PR を出し、別の AI がレビューするという三段構えのセキュリティ運用が標準化される時代に備え、社内に「AI セキュリティチーム」のロールを新設する。
:::

#### ハンズオン（ジュニアエンジニア向け）

curl のサプライチェーン信頼度を高めるための署名検証ハンズオン（所要時間: 10分）:

```bash
# Homebrew 経由で curl 最新版を入れ、依存を可視化する
brew install curl
# → 最新 curl がインストールされる。Apple 同梱版より新しい
brew deps --tree curl
# → curl の依存ツリーが出る。OpenSSL や c-ares などの上流が一覧できる

curl --version
# → libcurl のバージョン・対応プロトコル・SSL バックエンドが表示される

# 自社で使っている curl の HTTP/3 対応状況を確認
curl --http3 -I https://www.classlab.co.jp
# → サーバが HTTP/3 を返せば 200 系のステータスラインが返る
```

**活用例3選**:
1. 顧客向け Web フォーム（ライフライン申込）への HTTP/3 対応を確認し、3G/LTE 環境での遅延を改善
2. Salesforce REST API へのバッチ取り込みで TLS バックエンドのバージョンを揃え、暗号化スイートを統一
3. AI-OCR への画像アップロード経路で SSE-KMS 暗号化が curl 経由で通っているか診断

**エンジニアの業務改善**: 社内 CLI ツールの curl ベース実装を `--cacert` で証明書ピン留めし、MITM リスクを最小化できる。

**オフィスワーカー向け**: CX/NW 事業部向けに「Salesforce にデータが届かない」障害切り分けで `curl -v` の最小例を1ページ手順書化すると、エスカレ前の自己解決が増える。

**システム構築ノウハウ**: 上流 OSS の脆弱性は CVSS だけでなく「実害ある実装パスを通るか」で評価する。AI による発見はノイズが少ないため、CVE 採番前後の対応速度を見直す契機にする。

---

### 8. GitLab が人員削減と CREDIT バリューの撤回を発表
- **原題**: GitLab announces workforce reduction and end of their CREDIT values
- **スコア**: 674pt / コメント: 646件
- **URL**: https://about.gitlab.com/blog/gitlab-act-2/
- **要約**: GitLab が全社員規模のレイオフと、長年カルチャーの軸だった「CREDIT」バリュー（Collaboration, Results, Efficiency, Diversity, Iteration, Transparency）の刷新を発表。「Act 2」と銘打った戦略転換の背景に、AI コーディング時代の DevOps 競争激化がある。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ClassLab. のバリュー（行動指針）と評価制度を AI 前提に再点検する。AI を使った成果と使わない成果の評価軸を分け、システム事業部のグレード定義を Claude Code 利用前提に更新する。

##### 3年以内
GitHub Actions / GitLab CI / Vercel CI のように DevOps 基盤が AI エージェントに統合される流れを見越し、社内のリリースパイプラインをエージェント前提に作り直す。Salesforce DX のデプロイにも適用。

##### 3年以上
DevOps プラットフォームの寡占競争が決着するまでに、社内 CI/CD は「特定ベンダーに依存しない抽象化」を維持し、AI 開発支援だけでなく業務オートメーション全体を支配する基盤の選定権を握り続ける。
:::

---

### 9. Gmail 登録時に QR コードと SMS 送信が必須化
- **原題**: Gmail registration now requires scanning a QR code and sending a text message
- **スコア**: 618pt / コメント: 494件
- **URL**: https://discuss.privacyguides.net/t/google-account-registration-now-requires-sending-an-sms-via-phone-instead-of-receiving-an-sms/36082
- **要約**: Google アカウントの新規登録時、QR コード読み取り + ユーザー側からの SMS 送信（電話番号と端末の紐付け証明）が必須化された。匿名アカウントや使い捨てメールでの登録ハードルが上がり、プライバシー擁護派が反発。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
お客様用の Google アカウント / Workspace 管理プロセスを点検し、新規アカウント発行手順書（CX/NW 事業部向け）を SMS 必須前提に更新する。社内のセキュリティ研修にも反映する。

##### 3年以内
ライフライン申込フォームで Google ログインに依存していた箇所を Microsoft / LINE / Apple サインインへの多重化に進める。SMS 認証コストの増加を見越して認証経路をベンダーロックインから外す。

##### 3年以上
SMS / 電話番号がプラットフォーム本人確認の事実上の独占インフラ化することを前提に、自社のお客様 ID 戦略をマイナンバー連携やパスキー主軸に切り替える。引越し時の本人確認フローの再設計につなげる。
:::

---

### 10. ソフトウェアエンジニアリングはもはや終身キャリアではない
- **原題**: Software engineering may no longer be a lifetime career
- **スコア**: 472pt / コメント: 739件
- **URL**: https://www.seangoedecke.com/software-engineering-may-no-longer-be-a-lifetime-career/
- **要約**: AI コード生成と業界の人員圧縮で、エンジニアという職種が「40 代以降も続けやすい安定職」から「短中期で別キャリアへ転換することを前提とする職」に変質しつつある、というエッセイ。GitLab レイオフや Anthropic / OpenAI による生産性ジャンプの直後だけに反響が大きい。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部メンバーの 1on1 と評価面談に「AI を前提とした 3 年後の自分のスキル設計」を必須項目化する。プロダクトマネジメント・ドメイン専門性・運用設計など、AI が代替しにくい領域への横展開機会を提供する。

##### 3年以内
ライフライン業界知識・契約代行ドメインの専門性を持つエンジニアを意図的に育成する。CX/NW/EA 事業部とのジョブローテーションを制度化し、コーディングだけに依存しないキャリアパスを社内で示す。

##### 3年以上
「エンジニア × ライフライン業界専門家」「エンジニア × 経営」というハイブリッドキャリアを ClassLab. のブランドとして打ち出し、業界横展開（不動産・引越し・ユーティリティ）の人材輩出機関の側面を持つ会社を目指す。
:::

---

## Anthropic

### 11. Claude Opus 4.7 リリース
- **URL**: https://www.anthropic.com/news/claude-opus-4-7
- **要約**: Anthropic が最高性能モデル Claude Opus 4.7 を公開。価格は Opus 4.6 据え置きで入力 1Mトークン .00 / 出力 .00。Claude 製品群・API・Amazon Bedrock・Vertex AI・Microsoft Foundry で同時提供。金融業務向けの推論精度が大きく向上していると謳う。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/59e09ba1-dia-claude-opus-47-20260513-123539-1.png" alt="Claude Opus 4.7 が API・Bedrock・Vertex AI・Foundry で同時提供" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Salesforce 上のリード優先順位付け・解約予測・契約書要約バッチを Opus 4.7 へ切り替え、Sonnet との品質差を A/B 評価する。コスト感度の高い大量処理は Sonnet を残し、判断系のみ Opus に寄せる方針を確立する。

##### 3年以内
ライフライン申込のリスク判定（不渡り・解約離脱予測）や、CX 事業部の VOC 分析を Opus 4.7 / 4.8 系で標準化する。Claude API を裏側に持つ「ClassLab. の判断 AI」を社内向け API として提供する。

##### 3年以上
Claude Opus 系列の数年後（5.x / 6.x）の進化を前提に、社内データ基盤を「LLM が直接読みに来る前提」で設計し直す。Salesforce / Slack / ファイルストレージ・通話ログを統一的に LLM へ公開できるデータレイヤーを整備する。
:::

---

### 12. Anthropic × SpaceX 300MW・22万 GPU 契約
- **URL**: https://fortune.com/2026/05/05/anthropic-wall-street-financial-services-agents-jamie-dimon/
- **要約**: Anthropic が SpaceX と提携し、Colossus 1 データセンターの計算能力 300MW（NVIDIA GPU 22 万基超）を 1 ヶ月以内にフル確保するという衝撃発表。AWS への巨額コミット（先週発表）に続き、推論キャパシティの確保が AI 競争の主戦場となっていることが明確化。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/dd28fce6-dia-spacex-300mw-20260513-123510-1.png" alt="Anthropic と SpaceX が Colossus 1 で 300MW・22万 GPU を結ぶ" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Anthropic のキャパシティ拡張で Claude API のレート制限・レイテンシが緩和される見込みを織り込み、Salesforce トリガから Claude を呼ぶ同期処理（顧客対応中のリアルタイム要約など）を本番投入する判断基準を見直す。

##### 3年以内
推論キャパシティの供給増 → API 単価下落の中期トレンドを前提に、社内向け「Claude をフロー全体で呼ぶ」アーキテクチャに踏み切る。AI-OCR 後の判定だけでなく、入力前ガイド・後処理・通知すべてを LLM 化する。

##### 3年以上
クラウド AI の電力・GPU 競争が事業者ごとに格差を生む時代を見据え、Anthropic / OpenAI / Google それぞれに偏らないマルチプロバイダ抽象を社内 SDK として持つ。プロバイダ障害時に業務が止まらない構成を業界標準として提案する。
:::

---

### 13. Anthropic が金融エージェント・テンプレート10種をリリース
- **URL**: https://letsdatascience.com/news/anthropic-launches-ten-finance-agent-templates-for-claude-6516f048
- **要約**: ピッチブック生成・KYC スクリーニング・決算レビュー・月次決算など、金融機関の典型業務 10 種をすぐに走らせられる Agent Skills テンプレートを Claude 上に公開。ウォール街への本格進出と、JPMorgan の Jamie Dimon が AI エージェント導入を強く後押ししている文脈で発表された。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート事業部の月次決算・経費精算・契約レビューの自動化に、Anthropic 公開テンプレートを移植する PoC を実施。Salesforce / freee / 弥生のデータを Claude Managed Agents で結びつける構成を試す。

##### 3年以内
ライフライン業界版「契約代行エージェント・テンプレート」を ClassLab. が公開し、不動産会社 4,000 社に配布する戦略を取る。テンプレート提供で業務標準化と SaaS 化のハブになる。

##### 3年以上
金融機関と同じ深度のエージェント化（KYC、与信、解約予測、回収）をユーティリティ業界全体に持ち込み、ClassLab. を「ライフライン業界の業務基盤」として位置づける。
:::

---

### 14. Claude Microsoft 365 連携 GA + Outlook ベータ
- **URL**: https://www.anthropic.com/news
- **要約**: Excel / PowerPoint / Word の Claude アドインが GA に到達。Outlook 用は有料プランでパブリックベータ。複数アプリ間で会話コンテキストを保持し、開いているファイルへの編集を同期、Outlook 上で受信箱トリアージと返信ドラフトを行える。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート部門・EA 事業部の Word / Excel ベース業務（契約書ドラフト、決算資料、KPI 集計）を Claude アドインで効率化する。社内テンプレートに Claude 呼び出しサンプルを埋め込み、利用率を上げる。

##### 3年以内
Outlook トリアージを CX/NW 事業部のメール業務に展開し、Slack 上の Claude アクションと統合する。社内の「メール 1 通あたり処理時間」を KPI 化し、AI 利用の効果計測を仕組み化する。

##### 3年以上
Microsoft 365 + Claude が業務 OS 化することを前提に、ClassLab. の業務マニュアル・ナレッジを Office ファイルではなく Claude の Agent Skills に再構成する。ナレッジ＝コードという文化へ移行する。
:::

---

### 15. SAP × Anthropic Joule に Claude を組み込む戦略提携
- **URL**: https://news.sap.com/2026/05/sap-anthropic-to-bring-claude-sap-business-ai-platform/
- **要約**: SAP Sapphire で発表。SAP Business AI プラットフォームの中核（Joule および Joule Agents）の主要な推論エンジンとして Claude を採用。SAP の既存エンタープライズ顧客に Anthropic が一気にリーチする大型提携。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ClassLab. 内で SAP 利用はないが、お客様（不動産会社・電力会社）の SAP 環境で Claude が標準推論になる前提を見越し、Claude のレスポンス形式に合わせた連携 API 仕様（JSON Schema、Agent Skills 形式）を社内ドキュメントに整える。

##### 3年以内
Salesforce 中心の自社業務基盤と SAP / Oracle 中心の取引先業務基盤の間に、Claude を共通言語とする業務エージェント連携層を構築する。お客様の社内システム種別を問わない B2B 連携アーキテクチャを目指す。

##### 3年以上
業界基幹システム（SAP / Salesforce / Microsoft Dynamics）が「Claude 経由で会話する」時代に備え、ClassLab. の業務オントロジー（契約・住所・利用権・解約理由）を LLM が直接読める標準語彙として公開し、業界横断の交換規格を主導する。
:::

---

## Claude Code リリースノート

### 16. v2.1.139 エージェントビューと /goal コマンドが登場
- **リリース日**: 2026-05-11
- **URL**: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- **要約**: 大型機能追加。`claude agents` で全 Claude Code セッション（実行中・要対応・完了済み）を 1 画面で俯瞰できる「エージェントビュー」が Research Preview として登場。`/goal` コマンドで完了条件を宣言すれば、達成まで Claude が複数ターンを跨いで作業を継続する。`/scroll-speed` でホイール速度をライブ調整、`claude plugin details` でプラグインのコンポーネント内訳とトークンコスト見積もりが見られる。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/c1cae5c6-dia-claude-code-goal-20260513-123526-1.png" alt="/goal 宣言で Claude が自走しエージェントビューで全セッションを俯瞰" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部のエンジニア各人に対し、Claude Code を 1 日複数並列で起動する運用を解禁する。エージェントビューで進捗を俯瞰し、ブロックされたタスクを優先対応する人間オペレーションを標準化する。

##### 3年以内
`/goal` で完了条件を厳密に書く文化を社内に根付かせ、SOW（業務指示書）相当の粒度で Claude にゴール宣言する開発スタイルに移行する。プロジェクトマネジメントツール（Notion / Linear）の課題ステータスと `/goal` を自動連動させる。

##### 3年以上
社内のあらゆる業務（システム開発・コーポレート・CX・NW）に「ゴール駆動エージェント」を配置し、各人が複数のエージェントを管理する管理者的役割に変質する。組織図そのものを人 + AI エージェントの混成チームに再設計する。
:::

#### ハンズオン（ジュニアエンジニア向け）

`/goal` コマンドで Claude にゴールを宣言してみるハンズオン（所要時間: 10分）:

```bash
# Claude Code を最新版に更新
npm i -g @anthropic-ai/claude-code@latest
# → 2.1.139 以上が入る。`claude --version` で確認できる

# ターミナルで Claude Code を起動
claude
# → 通常のチャット UI が立ち上がる

# /goal でゴール宣言（チャット入力で打つ）
> /goal すべての関数に JSDoc を付け、`pnpm test` が通る状態にする
# → 上部にエージェント進捗パネルが表示される。経過時間・ターン数・トークン消費量が見える

# 別ターミナルでエージェント一覧を見る
claude agents
# → いま走っている全 Claude Code セッションのステータス（実行中／要対応／完了）が一覧で出る
```

**活用例3選**:
1. Salesforce Apex クラスのリファクタリングを `/goal "全 Apex メソッドのテストカバレッジを 85% 以上にする"` で実行
2. RIRIFE iOS/Android アプリの新機能を「画面実装 → ユニットテスト → スナップショットテスト全て緑」でゴール宣言
3. AI-OCR の Python パイプラインを「mypy エラーゼロ + pytest 全パス」をゴールに継続実行

**エンジニアの業務改善**: 「とりあえずタスク投げて寝る」が現実的になる。翌朝エージェントビューで止まったタスクだけ介入すればよい。

**オフィスワーカー向け**: 直接利用は少ないが、Slack 上で「あの自動化 Claude にお願いした？」のような Claude タスクの引き継ぎが自然になる。

**システム構築ノウハウ**: ゴールは「観測可能で機械検証できる形」に書く（テスト通る、リント通る、ベンチマーク超える）と効果が出る。あいまいなゴールは Claude が走り続けて課金が膨らむ。
---

### 17. v2.1.140 subagent_type マッチング改善とバグ修正
- **リリース日**: 2026-05-12
- **URL**: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- **要約**: Agent ツールの `subagent_type` マッチングが大文字小文字・セパレータに非対応だった問題を解消（`build-error-resolver` と `BuildErrorResolver` が同一視される等）。`/goal` が `disableAllHooks` / `allowManagedHooksOnly` の設定でハングする問題、`claude --bg` の接続エラー、シンボリックリンク設定のホットリロード回帰、リモート設定 401 リトライなどを修正。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内 Claude Code 設定のフックを `allowManagedHooksOnly` で運用していた場合は 2.1.140 に即時アップデートする。`subagent_type` の表記揺れによる「指定したのに違うサブエージェントが呼ばれた」事故を防ぐ。

##### 3年以内
社内エージェント名（custom subagent）の命名規約を kebab-case で統一し、表記揺れ前提のマッチングに頼らない設計にする。エージェントカタログを Notion で管理し、人が一意名を選択する UX を整える。

##### 3年以上
Claude Code 設定そのものを GitOps 化し、リモート管理設定の整合性検証を CI で自動化する。複数事業部でフォーク運用していたエージェント定義を統合管理体制に移す。
:::

---

### 18. v2.1.136 autoMode.hard_deny / OAuth 修正
- **リリース日**: 2026-05-08
- **URL**: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
- **要約**: `settings.autoMode.hard_deny` オプションで自動承認モード時の絶対拒否リストを定義可能に。`/clear` 後の MCP サーバー切断、OAuth トークン同時更新時の喪失、拡張思考後のリダクション処理エラーなどクリティカルなバグを解消。約 70 件の UI/UX 修正を含む大型メンテリリース。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
auto-accept-edits 運用をしているプロジェクトに `autoMode.hard_deny` を導入し、Salesforce 認証情報・本番 DB・課金 API キーへの書き込みを物理的に禁止する。事故防止の最後の砦として全リポジトリに展開。

##### 3年以内
MCP サーバーで Salesforce / GitHub / Slack を連携している社内構成に対し、`/clear` 後の自動再接続を前提とした運用に移行。MCP サーバー一覧を `.claude/mcp.json` で GitOps 管理する。

##### 3年以上
社内の Claude Code 利用全体を「ハード拒否ファースト」の設計思想で再構築する。デフォルト deny + ホワイトリスト承認のセキュリティモデルを、社内 PC・社内 SaaS のアクセス管理にまで一貫させる。
:::

---

## OpenAI リリースノート

### 19. OpenAI Realtime API 2（GPT-Realtime-2 / Translate / Whisper）GA
- **リリース日**: 2026-05-07
- **URL**: https://openai.com/index/introducing-gpt-realtime/
- **要約**: OpenAI が Realtime API v2 を一般提供開始し、音声系の新モデル 3 種を同時投入。GPT-Realtime-2 は GPT-5 級の推論と 128K コンテキスト（旧 32K）で長尺の音声エージェントに対応（入力 $32/M tok・出力 $64/M tok）。GPT-Realtime-Translate は 70 言語超のリアルタイム翻訳（$0.034/分）、GPT-Realtime-Whisper はストリーミング書き起こし（$0.017/分）。コールセンター・通訳・音声 UI の競争状況が一気に書き換わる発表。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
CX 事業部のコールセンター通話に GPT-Realtime-Whisper（ストリーミング書き起こし）と GPT-Realtime-Translate（70 言語翻訳）を組み合わせて適用する PoC を実施。文字起こし → Salesforce ケース自動添付 → スーパーバイザのリアルタイム監視まで一気通貫で構築する。

##### 3年以内
ライフライン申込の初回ヒアリングを Realtime-2 ベースの音声エージェントに置き換え、24 時間自動受付を実現。NW 事業部の電話受付業務を高付加価値（例外処理・契約クロージング）に集中させる構造に移行する。

##### 3年以上
音声 UI が業務インターフェースの標準になる前提で、ClassLab. の全サービス（RIRIFE、契約管理、社内システム）に音声入力・音声応答を横展開する。「電話 = 音声エージェントの呼び口」と再定義し、不動産会社や提携事業者からの問い合わせも音声 API 経由で受ける B2B 基盤を作る。
:::

#### ハンズオン（ジュニアエンジニア向け）

GPT-Realtime-Whisper でストリーミング書き起こしを試すハンズオン（所要時間: 15分）:

```bash
# 1. OpenAI Python SDK を最新化
pip install -U openai
# → realtime API 対応版がインストールされる

# 2. 環境変数に API キーを設定
export OPENAI_API_KEY=sk-xxx
# → 同シェル内で openai SDK が認証可能になる

# 3. マイク入力 → リアルタイム書き起こし（短縮版）
python3 -c "
import asyncio, os, json
from openai import AsyncOpenAI
client = AsyncOpenAI()

async def main():
    async with client.beta.realtime.connect(model='gpt-realtime-whisper') as conn:
        await conn.session.update(session={'input_audio_format': 'pcm16'})
        # → 16kHz PCM ストリーミングセッションが確立される
        print('セッション接続完了。マイク入力を流すと、書き起こしが標準出力に出る')

asyncio.run(main())
"
# → 上記接続テストが通れば、PyAudio 等でマイク入力を流すだけで部分書き起こしが返り続ける
```

**活用例3選**:
1. CX 事業部の通話録音バッチ後処理を、録音時のリアルタイム書き起こしに置き換え、応対品質のリアルタイム監視を可能にする
2. 外国籍顧客のライフライン申込電話を GPT-Realtime-Translate で日本語と母語を両表示し、通訳介在コストをゼロにする
3. システム事業部の Zoom ミーティング音声を Whisper でリアルタイム文字起こしし、Notion 議事録に自動投入する

**エンジニアの業務改善**: 自席で「タイピングの代わりに話す」開発体験が現実的になる。Claude Code への指示を音声で投げる試作が組める。

**オフィスワーカー向け**: コーポレート部門の電話応対メモを自動文字起こし。CX 事業部のフィードバック収集を「録音 → 手動転記」から「即時テキスト + 要約」に変える。

**システム構築ノウハウ**: Realtime API は WebSocket ベース・低レイテンシ前提なので、音声 I/O を伴うアーキテクチャでは「クライアント直接接続」または「自前 WebSocket リレー」のどちらにするかが設計の分岐点。Salesforce CTI 連携時はリレー方式が安全。

---

### 20. GPT-5.5 Instant がデフォルトに
- **URL**: https://help.openai.com/en/articles/6825453-chatgpt-release-notes
- **要約**: ChatGPT のデフォルトモデルが GPT-5.3 Instant から GPT-5.5 Instant に切り替わり、API では `chat-latest` で参照される。精度・文体の簡潔さ・画像 / STEM 補助・Web 検索利用が強化された。Plus / Pro 向けに過去チャット・ファイル・Gmail 連携を踏まえた応答が可能。GPT-5.3 Instant は 3 ヶ月の互換期間後に廃止予定。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/09d9183f-dia-gpt55-default-20260513-123519-1.png" alt="GPT-5.5 Instant がデフォルト化し過去チャット・Gmail・Sheets と連携" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート・EA 事業部の ChatGPT Plus / Team 利用者向けに、GPT-5.5 Instant への切替アナウンスと、過去チャット・Gmail 連携の活用ガイドを 1 ページで配布する。社内 Gmail 連携の許諾範囲を法務と整理する。

##### 3年以内
ChatGPT API（`chat-latest`）を裏に持つ社内アシスタント（営業先リサーチ、契約書要約）を本番化。社内では Claude API と OpenAI API を用途で使い分け、価格と品質のベンチマークを継続実施する。

##### 3年以上
GPT / Claude / Gemini の「デフォルトモデル」交代の頻度が四半期ごとになる未来を前提に、社内ナレッジ層がモデルに依存しない設計（ベクトル DB + 構造化メタデータ）を維持する。AI プロバイダ切替コストを低く保つ。
:::

---

### 21. ChatGPT Excel / Google Sheets サイドバー
- **URL**: https://help.openai.com/en/articles/6825453-chatgpt-release-notes
- **要約**: ChatGPT が Excel と Google Sheets のグローバルサイドバーを公開。トラッカー・予算・関数・複数タブ・シナリオ分析・データクレンジングをその場で構築・更新・解説できる。データを別ツールにエクスポートせず Sheets 内で完結する点が大きい。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート部門・EA 事業部の月次決算・予算管理 Sheets に ChatGPT サイドバーを公式運用し、関数説明・式エラー解析の問い合わせを情シスから ChatGPT に移管する。社内研修動画を 30 分で作る。

##### 3年以内
Salesforce レポートのエクスポート先 Google Sheets に ChatGPT サイドバー前提のテンプレートを整備し、CX/NW 事業部マネジメントが Sheets 上で AI に分析させる文化に移行する。BI ツール（Tableau / Looker）の利用範囲を縮小する選択肢を持つ。

##### 3年以上
Excel / Sheets 内で AI が直接データに触る世界では、ファイル＝データの境界が崩れる。社内のマスタデータ（顧客・契約・物件）を Sheets ではなく一次データベース（Salesforce / Postgres）に集約し、サイドバー AI からは API 経由でアクセスする設計に切り替える。
:::

---

### 22. ChatGPT Fast answers ロールアウト
- **URL**: https://help.openai.com/en/articles/6825453-chatgpt-release-notes
- **要約**: 情報検索系の質問に対して、確信度の高い詳細回答を素早く返す「Fast answers」を Web / iOS / Android にグローバル展開。Perplexity / Google の Generative Search との競争が一段深まった。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内検索（Notion / Slack / Salesforce）の代替として ChatGPT Fast answers を簡易ナレッジ問合せ口に位置づける。社内の典型 FAQ（「ライフラインの契約代行で水道は何社対応？」など）を ChatGPT に学習させた版を CX 事業部向けに整備する。

##### 3年以内
社内ナレッジ検索基盤を「LLM が即座に答える」前提に切り替え、Notion / Confluence へのアクセスを大幅に減らす。ライフラインオペレーションの SOP を AI ファースト形式で書き直す。

##### 3年以上
社内検索と社外検索の境界が消える時代を見据え、ClassLab. のお客様向け FAQ・ヘルプセンターを LLM ネイティブな形式（構造化 Q&A、JSON-LD、Markdown ファースト）で再構築する。SEO 戦略を AI 検索最適化（AISO）に転換する。
:::

---

## Salesforce

### 23. Agentforce Operations でバックオフィスを分解
- **URL**: https://www.salesforce.com/news/stories/agentforce-operations-announcement/
- **要約**: Salesforce が Summer '26 で「Agentforce Operations」を発表。属人化したバックオフィス業務を明確なタスク単位に分解し、専用エージェントがそれぞれを実行する構成。データ自動同期・Salesforce Flows 連携によるアクション発火が 5 月にベータ。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/b75d87c9-dia-agentforce-ops-20260513-123529-1.png" alt="Agentforce Operations が属人化バックオフィスを専用エージェントに分解" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
コーポレート事業部の経費承認・契約管理・新入社員オンボーディングを Agentforce Operations のベータで PoC 化する。Salesforce Flow ベースの既存自動化資産を活かせるため移行コストが低い。

##### 3年以内
CX/NW 事業部の毎月数千件のライフライン申込処理を Agentforce ベースに置き換え、人間のレビューが必要なケースのみキューに残す構成にする。Salesforce 上の業務 SOP を Agent Skill 化する。

##### 3年以上
業務オペレーションの大半が Agentforce 上で稼働する未来を見据え、ClassLab. の組織構造を「エージェント運用部門」と「ドメインエキスパート部門」の 2 層に再編する選択肢を持つ。
:::

---

### 24. Summer '26 リリースと IT Service Domain Pack
- **URL**: https://www.salesforce.com/news/stories/summer-2026-product-release-announcement/
- **要約**: Summer '26 では IT Service Domain Pack に 50 以上の専用 AI エージェントを同梱。Slack / Teams 上でそのまま動作し、社内 IT サポート業務（パスワードリセット、権限申請、ライセンス管理など）を AI 化。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内情シス窓口の 1 次対応を IT Service Domain Pack の Slack エージェントに置き換える PoC を実施。ServiceNow を持たない ClassLab. でも Salesforce Service Cloud 経由で IT サポートを統合できる。

##### 3年以内
コールセンター（CX 事業部）の IT 系問い合わせ（業務システムの使い方・障害切り分け）を Agentforce 化し、オペレータが本来の顧客対応に集中できる体制を作る。

##### 3年以上
IT サポートを完全 AI 化することで、情シス・社内ヘルプデスクのコスト構造を抜本的に変える。浮いたコストでドメインエキスパートとデータエンジニアに再投資する経営判断を可能にする。
:::

---

### 25. Q1 FY27 決算は 5月27日 発表
- **URL**: https://investor.salesforce.com/news/news-details/2026/Salesforce-Announces-Date-of-First-Quarter-Fiscal-2027-Earnings-Release-and-Webcast/default.aspx
- **要約**: Salesforce の FY27 Q1 決算が 5/27（PT 14:00 / ET 17:00）に発表されることを公式アナウンス。Agentforce の収益化状況、Slack の伸び、競合（Microsoft Copilot / ServiceNow Now Assist）との差が注目される。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
5/28（JST）に決算サマリを社内 Slack に投稿する仕組みを準備する。Agentforce のシート数増加・Slack 連携売上を社内導入判断に反映する。

##### 3年以内
Salesforce 製品ロードマップの収益化判断（Data Cloud、Agentforce 課金体系）を踏まえ、社内ライセンス計画と契約タイミングを最適化する。Salesforce 値上げ時の交渉カードを準備する。

##### 3年以上
Salesforce の事業構造変化を継続観察し、ClassLab. の業務基盤としての将来性を毎年棚卸する。代替候補（HubSpot / Microsoft Dynamics / 自社開発）への切替可能性を技術的にも維持する。
:::

---

## Zoom Phone

### 26. Zoom Phone にリアルタイム字幕翻訳が登場
- **URL**: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062333
- **要約**: Zoom Phone のライブ文字起こし機能に「リアルタイム字幕翻訳」が追加。通話中に各参加者が好きな言語で字幕を見られる。元の文字起こしは保持され、参加者ごとに翻訳言語を独立選択可能。アカウント・サイト・グループ・内線レベルで管理者が制御。5 月末までに段階展開。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/732f3b3c-dia-zoom-caption-20260513-123334-1.png" alt="Zoom Phone のリアルタイム字幕翻訳で参加者ごとに言語を選択" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン契約代行で外国人顧客（ベトナム・中国・ネパール籍など）対応中の CX 事業部に対し、Zoom Phone のリアルタイム翻訳をオンにする運用テストを実施。通訳介在コストを削減する。

##### 3年以内
コールセンターの多言語対応を Zoom Phone + Claude のハイブリッド構成で標準化し、文字起こし → 翻訳 → 要約 → Salesforce レコード自動更新までを一気通貫にする。

##### 3年以上
多言語顧客対応を競争優位にし、不動産会社からの「外国籍入居者のライフライン契約を ClassLab. に丸投げできる」というポジションを確立する。日本国内の人口動態変化（外国籍居住者の増加）を捉えた事業拡大の柱にする。
:::

---

## GitHub トレンド（直近2ヶ月以内に作成）

> 選定基準: GitHub Search API で `created:>2026-03-12 stars:>500` を取得し、stars 順上位から 5 件。期間内（または直近 1〜2 週間）に大幅な伸びが確認できるリポジトリのみ採用している。

### 27. ultraworkers/claw-code
- **言語**: Rust
- **created**: 2026-03-31
- **Stars**: 191K
- **URL**: https://github.com/ultraworkers/claw-code
- **要約**: 史上最速で 100K stars を突破した Rust 製コーディングエージェント。`oh-my-codex` をベースに、Claude Code / Codex 互換のスキル機構と高速 IPC を持つ。今週ロックが解除され OSS 公開、Discord コミュニティが一気に立ち上がった。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/5dbdc463-dia-claw-code-20260513-124719-1.png" alt="claw-code が Claude Code / Codex / Cursor と互換 IPC で繋がる構造" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部の希望メンバーで claw-code を試験導入し、Claude Code との応答レイテンシ・並列セッション数・コスト構造を比較する。Rust 製の軽さが Mac M1/M2 で体感差として出るかを実測する。

##### 3年以内
社内開発のエージェント・ランタイムを「Claude Code 一強」ではなく、claw-code / codex / claude-code のマルチランタイム前提に切り替える。タスクの性質（軽量バッチ・長尺リファクタ）でランタイムを使い分ける運用標準を作る。

##### 3年以上
コーディングエージェントの「ランタイム」が乱立する時代を見据え、ClassLab. の社内ツール（Salesforce DX 自動化・RIRIFE ビルド等）はランタイム抽象を介して呼び出す構成にしておく。特定ランタイム依存のロックインを避ける。
:::

---

### 28. JuliusBrussee/caveman
- **言語**: JavaScript
- **created**: 2026-04-04
- **Stars**: 59K
- **URL**: https://github.com/JuliusBrussee/caveman
- **要約**: 「why use many token when few token do trick」をモットーに、Claude Code の応答を原始人風の最小トークン構文に圧縮するスキル。実測 65% のトークン削減を主張し、Anthropic API コストの高騰に悩む開発者から急速にスター数を集めた。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/4c801585-dia-caveman-20260513-124910-1.png" alt="caveman スキルで応答を原始人構文に圧縮しトークンを 65% 削減" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内 Claude Code 利用者向けに caveman スキルの導入オプションを案内し、本人確認・コード解説などの大量問い合わせ系タスクでトークンコストを計測する。Anthropic 課金額の月次レポートで効果を可視化する。

##### 3年以内
プロンプト・応答の圧縮を社内 SDK レベルで標準化する。Claude / GPT / Gemini を呼ぶ全ての社内ツールが「トークン削減レイヤー」を経由する構造にし、AI ランニングコストを 30〜50% カットすることを目標にする。

##### 3年以上
LLM コストの長期的な低下と相まって、「自然言語の冗長性をマシン側で圧縮する」発想が標準になる。社内ナレッジ・ドキュメントを最初から圧縮志向で書く文化を整備し、AI ファースト時代のライティング基準を確立する。
:::

#### ハンズオン（ジュニアエンジニア向け）

caveman スキルを Claude Code に導入してトークン削減を体感するハンズオン（所要時間: 10分）:

```bash
# 1. プロジェクト直下にスキル設定ディレクトリを作る
mkdir -p .claude/skills
cd .claude/skills
# → Claude Code のローカルスキル配置先ができる

# 2. caveman を取得（プロジェクト個別 or グローバル）
git clone https://github.com/JuliusBrussee/caveman.git
# → caveman/SKILL.md が手元に来る

# 3. Claude Code を起動して効果確認
claude
> /caveman
# → スキル発火。以後の応答が原始人構文（短文・最小限）に切り替わる

# 4. 同じ質問を caveman ON/OFF で比較
> 「Salesforce の Apex で SOQL を発行するときの注意点を教えて」
# → ON 時は要点 5〜8 行で返り、OFF 時より大幅にトークン消費が減る
```

**活用例3選**:
1. CX 事業部の「Salesforce 操作 FAQ」社内 bot の応答を caveman 化して月次トークン費を圧縮
2. システム事業部のレビュー bot 応答を caveman で短文化し、PR コメントの可読性も同時に上げる
3. 営業支援チャット（NW 事業部）の AI 応答を caveman 化して、応答待ち時間を短縮

**エンジニアの業務改善**: API コスト削減と応答待ち短縮の両得。長い説明が必要な時だけ caveman OFF に切替える運用に。

**オフィスワーカー向け**: 短く要点だけ返ってくるため、Slack 上での AI 応答が読みやすくなる。

**システム構築ノウハウ**: Skills は「応答スタイルの DSL」として機能する。社内では caveman のフォーク版（日本語短文構文）を作ると効果がさらに出る。

---

### 29. MemPalace/mempalace
- **言語**: Python
- **created**: 2026-04-05
- **Stars**: 52K
- **URL**: https://github.com/MemPalace/mempalace
- **要約**: ベンチマーク最強を謳う OSS の AI メモリシステム。LLM エージェントが長期記憶を保持するためのストア・検索・要約・圧縮までを一貫して提供。Mem0 等の競合に対しベンチマーク優位を主張して急伸。

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-05-05-to-05-12/72f09044-dia-mempalace-20260513-124723-1.png" alt="MemPalace は長期記憶・要約・検索・ベクトル DB を 4 層で提供" width="1536" height="1024">

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリの「お客様プロフィール記憶」や、Salesforce ケース履歴をベースにしたエージェント応答に mempalace を組み込む PoC を実施。Mem0 採用を検討中だった案件を比較評価のうえ統合する。

##### 3年以内
ClassLab. の全 AI エージェント（CX・NW・コーポレート）共通の長期記憶層として mempalace（または同等技術）を採用。お客様 1 人ごとの過去の問い合わせ・契約変更・解約理由を、AI 横断で参照できる基盤を構築する。

##### 3年以上
顧客 LTV を「LLM が記憶できる文脈量」で再定義する時代に備え、ClassLab. の顧客ナレッジを構造化メモリとして外販する選択肢を持つ。不動産会社へのライセンス提供という新事業の芽になる。
:::

---

### 30. safishamsi/graphify
- **言語**: Python
- **created**: 2026-04-03
- **Stars**: 47K
- **URL**: https://github.com/safishamsi/graphify
- **要約**: コード・SQL スキーマ・R スクリプト・shell・ドキュメント・論文・画像・動画など雑多なフォルダを、クエリ可能なナレッジグラフに変換する CLI スキル。Claude Code / Codex / Cursor / Gemini CLI など主要エージェントから直接呼べる。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Salesforce オブジェクトモデル（Account / Opportunity / Property__c / Closed Won 等）と Apex / Flow / ApexTrigger のディレクトリを graphify でグラフ化し、システム事業部の新人オンボーディング期間を短縮する PoC を実施する。

##### 3年以内
社内コードベース・ドキュメント・SOP を全社グラフとして統合し、Claude が「Salesforce の Property__c に紐づく Flow と Apex トリガを教えて」のような構造的問い合わせに答えられる状態を作る。レガシー資産の棚卸し基盤として使う。

##### 3年以上
お客様（不動産会社・電力会社）の業務システムまで含めた業界グラフを ClassLab. が保有する戦略を取り、「ライフラインの業務ナレッジを最も詳しく構造化できる会社」というポジションを確立する。
:::

---

### 31. nexu-io/open-design
- **言語**: TypeScript
- **created**: 2026-04-28
- **Stars**: 38K
- **URL**: https://github.com/nexu-io/open-design
- **要約**: Anthropic の Claude Design に対するローカル・ファーストな OSS 代替。19 種類のスキルと 71 のブランドグレードなデザインシステムを同梱し、Web / デスクトップ / モバイルプロトタイプ・スライド・画像・動画を生成。サンドボックスプレビューと HTML/PDF/PPTX/MP4 エクスポートに対応。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ClassLab. の社内資料・お客様向けプロポーザル作成（コーポレート・EA 事業部）に open-design を試験導入。Claude Design のサブスクと比較してコスト効果を測る。

##### 3年以内
RIRIFE のランディングページ刷新・ライフライン申込フォームのデザイン改善を、open-design のテンプレートをベースにエージェント駆動で量産する体制に切り替える。デザイナーは「指示書を書く・最終整える」役割に集中する。

##### 3年以上
デザイン制作が「指示する → エージェントが組む」モデルに完全移行する世界で、ClassLab. の業界ブランド資産（ライフライン業界共通のデザイントークン）を OSS 公開してエコシステムの軸を握る。
:::
