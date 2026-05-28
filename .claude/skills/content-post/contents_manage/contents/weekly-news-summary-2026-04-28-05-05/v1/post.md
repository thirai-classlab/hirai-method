
## 目次

- [Hacker News](#hacker-news)
  - [1. DeepSeek V4 — フロンティアモデルにあと一歩](#1-deepseek-v4--フロンティアモデルにあと一歩)
  - [2. DeepClaude — Claude Code のエージェントループを DeepSeek V4 Pro で動かす](#2-deepclaude--claude-code-のエージェントループを-deepseek-v4-pro-で動かす)
  - [3. Agentic Coding Is a Trap（エージェントコーディングは罠だ）](#3-agentic-coding-is-a-trapエージェントコーディングは罠だ)
  - [4. Bun の将来が心配だ](#4-bun-の将来が心配だ)
  - [5. メルセデス・ベンツが物理ボタン回帰を表明](#5-メルセデスベンツが物理ボタン回帰を表明)
  - [6. Microsoft Edge、未使用時もメモリにパスワードを平文で保持](#6-microsoft-edge未使用時もメモリにパスワードを平文で保持)
  - [7. 米国の医療マーケットプレイス、市民権・人種データを広告テックに共有](#7-米国の医療マーケットプレイス市民権人種データを広告テックに共有)
  - [8. EU、2027年からスマートフォンのバッテリー交換可能化を義務化](#8-eu2027年からスマートフォンのバッテリー交換可能化を義務化)
  - [9. GameStop が eBay に 555 億ドルの買収提案](#9-gamestop-が-ebay-に-555-億ドルの買収提案)
  - [10. ジムで 35 人の見知らぬ人と話してみた](#10-ジムで-35-人の見知らぬ人と話してみた)
- [Zoom Phone](#zoom-phone)
  - [11. Zoom Phone、シート数 1,000 万を突破（FY2026 年次報告）](#11-zoom-phoneシート数-1000-万を突破fy2026-年次報告)
  - [12. Zoom CX → Zoom Phone エージェント転送で会話サマリ自動連携](#12-zoom-cx--zoom-phone-エージェント転送で会話サマリ自動連携)
- [Salesforce](#salesforce)
  - [13. Agentforce Operations を発表 — バックオフィス自動化](#13-agentforce-operations-を発表--バックオフィス自動化)
  - [14. Salesforce、AI ロードマップを顧客と共創（クラウドソーシング）](#14-salesforceai-ロードマップを顧客と共創クラウドソーシング)
  - [15. Summer '26 リリース — Sandbox は 5/9 にアップグレード](#15-summer-26-リリース--sandbox-は-59-にアップグレード)
- [Anthropic](#anthropic)
  - [16. Claude Opus 4.7 が一般提供開始](#16-claude-opus-47-が一般提供開始)
  - [17. Claude Mythos Preview を発表（一般公開なし）](#17-claude-mythos-preview-を発表一般公開なし)
  - [18. Adobe・Autodesk・Blender などクリエイティブ系コネクタを追加](#18-adobeautodeskblender-などクリエイティブ系コネクタを追加)
  - [19. Claude Security パブリックベータ — Enterprise 顧客向け脆弱性スキャン](#19-claude-security-パブリックベータ--enterprise-顧客向け脆弱性スキャン)
- [GitHub トレンド](#github-トレンド)
  - [20. ruvnet/ruflo — Claude 用エージェントオーケストレーション](#20-ruvnetruflo--claude-用エージェントオーケストレーション)
  - [21. GitNexus — ブラウザ完結のナレッジグラフ + Graph RAG](#21-gitnexus--ブラウザ完結のナレッジグラフ--graph-rag)
  - [22. TauricResearch/TradingAgents — マルチエージェント金融トレーディング](#22-tauricresearchtradingagents--マルチエージェント金融トレーディング)
  - [23. D4Vinci/Scrapling — 適応型 Web スクレイピングフレームワーク](#23-d4vinciscrapling--適応型-web-スクレイピングフレームワーク)

---

## Hacker News

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-04-28-05-05/c62dac5d-sec-hn-20260505-155343-1.png" alt="Hacker News 週間ハイライト — DeepSeek V4 フロンティア、Claude Opus 4.7、Bun の不安、Mercedes 物理ボタン、Edge パスワード漏洩、EU バッテリー規制を象徴するピクセルアートシーン" width="1024" height="1024">

### 1. DeepSeek V4 — フロンティアモデルにあと一歩

- **原題**: DeepSeek V4 – almost on the frontier
- **スコア**: 659pt / コメント: 385件
- **URL**: https://simonwillison.net/2026/Apr/24/deepseek-v4/
- **要約**: Simon Willison による DeepSeek V4 のレビュー。コーディング・推論ベンチで GPT-5 / Claude Opus 4.7 にかなり肉薄しており、オープンウェイトかつ推論コストが圧倒的に安いため「フロンティアにあと一歩」と評価。MoE 構成と FP8 学習でコスト効率が高い。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン事業の不動産会社向けメール返信ドラフトや、コールセンターでの応対要約など、低リスク・大量処理のタスクに DeepSeek V4 を Claude のサブセットとして導入する PoC を実施し、トークンコストを 70% 以上削減できるか検証する。

##### 3年以内
モデル選定を「タスクの重要度別ルーティング」へ標準化し、定型処理は DeepSeek 系オープンウェイトをセルフホスト、複雑判断は Claude Opus というハイブリッド構成を社内 LLM ゲートウェイで運用する。

##### 3年以上
オープンウェイトモデルが商用フロンティアに追いついたとき、CRM・コールセンターの主要 AI ワークロードを完全に自社 GPU クラスタへ移行できる体制（MLOps・ガバナンス・データ統制）を整備する。
:::

#### ハンズオン（ジュニアエンジニア向け）

DeepSeek V4 を OpenRouter 経由で叩き、コスト感を体感する（所要時間: 15分）:

```bash
# OpenRouter にサインアップして API キーを取得（無料枠あり）
export OPENROUTER_API_KEY="sk-or-v1-xxxx"
# → 環境変数に API キーが入り、curl から呼び出せるようになる

curl https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek/deepseek-v4",
    "messages": [{"role": "user", "content": "RIRIFE アプリのプッシュ通知文面を3案作って"}]
  }'
# → DeepSeek V4 が JSON で返答する。Claude と同じプロンプトを投げて品質とコストを比較できる
```

**活用例3選**:
1. ServiceGuide__c の引越しプラン文章生成のバッチ処理を DeepSeek V4 へ寄せ、月次の LLM 課金を圧縮する
2. RIRIFE の暮らしのメディア記事タイトル候補生成を DeepSeek でドラフト→ Claude で最終調整する 2 段階フローにする
3. 営業 NW 事業部のメール下書き支援機能を DeepSeek で運用し、機微情報のみ Claude にエスカレーションする

**エンジニアの業務改善**: コードレビュー Bot のラフチェックや、Pull Request 要約は DeepSeek、深い設計レビューは Claude という使い分けで Claude API 利用枠を温存できる。

**オフィスワーカー向け**: 議事録要約・メール定型処理は社内ゲートウェイで自動的に DeepSeek へルーティングされるため、誰も「どのモデル？」を意識せず安価に AI を使える。

**システム構築ノウハウ**: LLM ゲートウェイ（LiteLLM 等）を 1 枚噛ませて「タスク分類 → モデル選択」を中央集権的に管理すると、モデル乗り換え時のコストが極小化される。

---

### 2. DeepClaude — Claude Code のエージェントループを DeepSeek V4 Pro で動かす

- **原題**: DeepClaude – Claude Code agent loop with DeepSeek V4 Pro
- **スコア**: 655pt / コメント: 275件
- **URL**: https://github.com/aattaran/deepclaude
- **要約**: Claude Code 互換のエージェントループを DeepSeek V4 Pro で実装した OSS。ツール呼び出し・ファイル編集・サブエージェントを DeepSeek だけで回し、Anthropic API の月額枠を消費せずに同等の開発体験を得ようという挑戦。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部のジュニアエンジニア向け学習環境として DeepClaude を導入し、Claude Code のサブスクリプション枠を本番開発に集中させつつ、教育用途のコストをゼロに近づける。

##### 3年以内
Claude Code と DeepClaude を抽象化レイヤで隠蔽し、レビューや実装フェーズに応じてエージェントエンジンを動的に切り替えられる「社内開発エージェント基盤」を整備する。

##### 3年以上
オープンウェイトベースのエージェントが Claude Code 同等のクオリティに達した段階で、機微コード（顧客契約 DB 周辺）はオンプレ DeepClaude、汎用コードは Claude Code というガバナンス分離を確立する。
:::

#### ハンズオン（ジュニアエンジニア向け）

DeepClaude をローカルで起動して簡単な依頼を投げる（所要時間: 25分）:

```bash
git clone https://github.com/aattaran/deepclaude
cd deepclaude
# → リポジトリがローカルに展開され、deepclaude/ ディレクトリで作業できる

pip install -e .
# → Python パッケージとしてインストールされ、deepclaude コマンドが使えるようになる

export DEEPSEEK_API_KEY="sk-xxxx"
deepclaude --task "README.md を読んで日本語で要約して docs/summary.md に保存して"
# → Claude Code と同様にエージェントループが回り、ファイルを読み込み、新規ファイルを書き出す
```

**活用例3選**:
1. classlab-weekly-news の microCMS 投稿スクリプトのリファクタを DeepClaude に下書きさせ、Claude Code でレビュー
2. RIRIFE iOS の Swift コード（軽微なバグ修正）を DeepClaude に投げて学習用 PR 草案を作る
3. AI-OCR の Python パイプラインを DeepClaude にメンテさせ、Claude Code の枠は新規プロダクトに振り向ける

**エンジニアの業務改善**: 1 つの Claude Code サブスクで全員が並行作業すると枠が足りなくなりがちだが、DeepClaude を併用すれば「実験ブランチは DeepClaude、main マージ前は Claude Code」と役割分担できる。

**オフィスワーカー向け**: 直接の利用想定は少ないが、社内で運用するレポーティング自動化（Notion → Slack）の実装を DeepClaude に寄せれば、エンジニア依存度を下げられる。

**システム構築ノウハウ**: 「エージェントループの抽象化」と「モデル切り替え可能な実装」は今後 1〜2 年のデファクトになる。今のうちにエージェント実装を Anthropic SDK に密結合させない設計にしておくと移行コストが小さい。

---

### 3. Agentic Coding Is a Trap（エージェントコーディングは罠だ）

- **原題**: Agentic Coding Is a Trap
- **スコア**: 429pt / コメント: 336件
- **URL**: https://larsfaye.com/articles/agentic-coding-is-a-trap
- **要約**: AI エージェントに丸投げする「エージェントコーディング」は、短期の生産性と引き換えに長期的な学習・保守性・所有感を失わせる、と警告するエッセイ。著者は「コーディングは思考の可視化であり、考えることを外注すると技術組織は空洞化する」と主張。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Claude Code を使う際の「人間がレビューすべき粒度」と「エージェントに任せて良いタスク」を明文化したガイドラインをシステム事業部で策定し、PR テンプレに組み込む。

##### 3年以内
新人〜中堅の育成カリキュラムに「AI を使わない週」を意図的に組み込み、設計判断の筋力を維持する。同時に、エージェントが書いたコードのレビュー眼を鍛えるレビュー研修を制度化する。

##### 3年以上
組織の知識資産（設計判断・トレードオフの履歴）をエージェントが書いたコードからも取り出せるように、ADR・設計ドキュメント・コミットメッセージを「AI のための設計記憶」として再設計する。
:::

---

### 4. Bun の将来が心配だ

- **原題**: I am worried about Bun
- **スコア**: 462pt / コメント: 310件
- **URL**: https://wwj.dev/posts/i-am-worried-about-bun/
- **要約**: Bun が機能を広げすぎて、ランタイム・パッケージマネージャ・テストランナー・バンドラ・サーバを 1 つの製品で抱え込んだ結果、開発リソースが分散し各機能の品質が劣化していると指摘。Node.js が Bun の機能を吸収しつつあるため、エコシステムへの賭け金として再評価が必要と論じている。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
classlab-weekly-news（Next.js）や社内ツールで Bun を本番採用しているプロジェクトを棚卸しし、Bun 依存度（package.json の bun 専用機能や bunfig.toml）を可視化する。

##### 3年以内
Bun と Node.js のどちらでも動く「ランタイム抽象化」を CI に組み込み、Bun が失速しても 1 日で Node.js に切り替えられる構成を標準化する。

##### 3年以上
JavaScript ランタイム選定を「速度」ではなく「エコシステムの持続可能性」で評価する文化を作り、新規プロダクトでは「採用するランタイムのコミット元・スポンサー・ガバナンス」を技術選定書に必ず記載する。
:::

---

### 5. メルセデス・ベンツが物理ボタン回帰を表明

- **原題**: Mercedes-Benz commits to bringing back physical buttons
- **スコア**: 842pt / コメント: 496件
- **URL**: https://www.drive.com.au/news/mercedes-benz-commits-to-bringing-back-phycial-buttons/
- **要約**: メルセデスが「タッチパネル一辺倒の UI を見直し、空調・走行モードなど頻用機能は物理ボタンへ戻す」と発表。視線移動と操作ミスの増加を裏付けるユーザー調査を引用し、業界全体に物理 UI 復権の流れが広がる可能性を示唆。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリと CX 事業部のコールセンター画面で「タップ階層が深すぎる頻出操作」を洗い出し、ホーム画面ショートカットや常設タブとして “物理ボタン的” に露出させる UX 改善 PoC を行う。

##### 3年以内
ライフライン契約の電話オペレータ向け業務画面を「常時表示の物理ボタン的レイアウト」に再設計し、平均処理時間（AHT）を削減する KPI を設定する。

##### 3年以上
全社プロダクトの UI ガイドラインに「重要操作は隠さない」原則を明文化し、業務システムにおける視認性と即応性を組織文化として継承する。
:::

---

### 6. Microsoft Edge、未使用時もメモリにパスワードを平文で保持

- **原題**: Microsoft Edge stores all passwords in memory in clear text, even when unused
- **スコア**: 498pt / コメント: 180件
- **URL**: https://twitter.com/L1v1ng0ffTh3L4N/status/2051308329880719730
- **要約**: セキュリティ研究者が、Microsoft Edge がパスワードマネージャに保存した認証情報をブラウザプロセスのメモリ上に平文で常駐させていることを報告。ローカル感染やメモリダンプで容易に抽出できる状態。Microsoft 側は対応を検討中とコメント。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内 PC（特に CX 事業部のコールセンター端末）で Edge をパスワードマネージャ代わりに使っているユーザーを特定し、1Password・Bitwarden 等の専用ツールへ強制移行する。

##### 3年以内
情報資産分類とブラウザ運用ポリシーを再設計し、業務システムへの認証情報を「ブラウザに保存しない」ことを技術的に強制する（DLP・ブラウザポリシー設定）。

##### 3年以上
クライアント端末の「ローカル平文保管」をゼロに近づけるため、SSO + ハードウェアキー（FIDO2）への完全移行を全社目標に据え、コスト・運用負荷の試算を始める。
:::

---

### 7. 米国の医療マーケットプレイス、市民権・人種データを広告テックに共有

- **原題**: US healthcare marketplaces shared citizenship and race data with ad tech giants
- **スコア**: 472pt / コメント: 154件
- **URL**: https://techcrunch.com/2026/05/04/us-healthcare-marketplaces-shared-citizenship-and-race-data-with-ad-tech-giants/
- **要約**: HealthCare.gov 等で、ユーザーの市民権・人種・所得などの機微情報が Google・Meta・LinkedIn のトラッキングタグに送信されていたと TechCrunch が報道。HIPAA 対象外のフォーム入力経路でデータ漏えいが起きており、政府インフラのプライバシー設計が問われている。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン契約フォームと RIRIFE の登録フローで、Google Tag Manager・Meta Pixel が機微情報（住所・契約世帯構成）を意図せず送信していないか緊急監査する。

##### 3年以内
個人情報保護法・改正電気通信事業法の「外部送信規律」を踏まえ、計測タグの設置を「データガバナンス委員会の承認制」とし、計測手段はサーバーサイドタグ（GTM Server-side）へ寄せる。

##### 3年以上
顧客の機微情報を扱う事業部（ライフライン・CX）について、計測・分析を完全自社基盤（CDP）で完結させ、第三者広告テックへの送信をゼロにする。
:::

---

### 8. EU、2027年からスマートフォンのバッテリー交換可能化を義務化

- **原題**: Removable batteries in smartphones will be mandatory in the EU starting in 2027
- **スコア**: 553pt / コメント: 499件
- **URL**: https://www.ecopv-eu.com/en/blog-en/replaceable-smartphone-batteries-2027-eu-regulation/
- **要約**: EU の新規制で、2027年以降に EU 域内で販売されるスマートフォンはエンドユーザーがバッテリー交換できる設計が義務化される。Apple・Samsung などはハードウェア再設計を迫られ、修理権運動が一段と前進。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリの動作要件・OS バージョン方針を「ユーザーが端末を長く使う前提」に更新し、5〜7 年前のミッドレンジ端末でも快適に動くパフォーマンスチューニングを優先課題化する。

##### 3年以内
端末寿命の長期化に対応し、暮らしのメディアで「修理・買い替え判断・サブスク」のコンテンツ系統を厚くして、メディア事業の SEO 流入を取りに行く。

##### 3年以上
電気・ガスと同様に「家電の長寿命化」を扱う循環型ライフライン事業として、家電修理・リファービッシュ斡旋を新規事業領域として検討する。
:::

---

### 9. GameStop が eBay に 555 億ドルの買収提案

- **原題**: GameStop makes $55.5B takeover offer for eBay
- **スコア**: 667pt / コメント: 638件
- **URL**: https://www.bbc.co.uk/news/articles/cn0p8yled1do
- **要約**: GameStop（GME）が eBay に対して 555 億ドル規模の買収を正式提案。リテール投資家の SNS が再加熱し、ミーム株コミュニティの組織力と既存テック企業の評価が試される歴史的ディール。eBay 取締役会は「精査中」とコメント。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
M&A 関連ニュースの社内速報フローを整備し、不動産・引越し業界の動向と組み合わせて NW 事業部の営業トーク材料に転用する仕組みを作る。

##### 3年以内
ライフライン事業の競合 M&A（電力・ガス小売、引越し代行）を継続的にウォッチする SaaS（CB Insights / Speeda）の導入を検討し、戦略企画部門の判断材料を厚くする。

##### 3年以上
「コミュニティ起点の経営圧力」が一般化することを前提に、株主・ユーザー・パートナーが SNS で連動する時代の IR / コーポレートコミュニケーション戦略を整備する。
:::

---

### 10. ジムで 35 人の見知らぬ人と話してみた

- **原題**: Talking to strangers at the gym
- **スコア**: 1297pt / コメント: 613件
- **URL**: https://thienantran.com/talking-to-35-strangers-at-the-gym/
- **要約**: 著者がジムで意識的に 35 人と短い雑談を試みた 1 ヶ月の記録。心理的ハードルの下げ方、相手のシグナルの読み取り方、雑談の終わらせ方を実体験ベースで整理。リモートワーク社会で減少した「弱い紐帯」の再構築に示唆を与える。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
リモート中心の社員が増えた状況を踏まえ、社内 Slack の雑談チャネルを「ランダム 1on1 Bot」で活性化し、部署横断の弱い紐帯を再生する施策を試す。

##### 3年以内
NW 事業部の不動産会社開拓・展示会対応において「初対面の雑談スクリプト」をパターン化し、新人の立ち上がり期間を短縮する営業育成プログラムを設計する。

##### 3年以上
顧客接点のすべて（コールセンター・店頭・アプリ）で「最初の 30 秒で信頼を獲得する」ためのコミュニケーション設計原則を、CX 事業部の標準オペレーションに組み込む。
:::

---

## Zoom Phone

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-04-28-05-05/f67c3120-sec-zoom-20260505-155116-1.png" alt="Zoom Phone 1,000 万シート突破とバーチャルエージェントから人間オペレータへの会話サマリ自動引き継ぎを表現したピクセルアート・コールセンター" width="1024" height="1024">

### 11. Zoom Phone、シート数 1,000 万を突破（FY2026 年次報告）

- **URL**: https://www.zoom.com/en/products/whats-new/
- **要約**: Zoom が会計年度 2026 の年次報告書で、Zoom Phone のシート数が 1,000 万を超えたと発表。Cisco・Microsoft Teams からのリプレース案件が増加。Zoom は「会議や通話を自動化された業務フローへ繋げる System of Action」へポジショニングを移していると説明。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
CX 事業部のコールセンター用 PBX を Zoom Phone 評価の俎上に載せ、現行の電話システムとの TCO 比較・通話品質・SLA を 3 ヶ月の PoC で検証する。

##### 3年以内
Zoom Phone と Salesforce Service Cloud の連携で、着信・通話メモ・要約を CRM に自動連携する「電話起点の自動化フロー」を運用標準化する。

##### 3年以上
電話と AI ワークフローが融合した「System of Action」を前提に、ライフライン契約のオペレーションを音声主導・自動文字起こし・自動 CRM 反映で完結させる体制を構築する。
:::

---

### 12. Zoom CX → Zoom Phone エージェント転送で会話サマリ自動連携

- **URL**: https://library.zoom.com/whats-new
- **要約**: Zoom CX のバーチャルエージェント（IVR/Bot）から Zoom Phone のヒューマンエージェントへ通話を転送する際、要約・抽出変数（顧客 ID・問い合わせ種別等）が自動で引き継がれるアップデートをリリース。「同じことを 2 度説明させる」CX 課題を直接的に解消する。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン入電の一次受け（電気契約・引越し日確定など）を Zoom CX のバーチャルエージェントに任せ、複雑案件のみオペレータへ要約付きで引き継ぐ PoC を試す。

##### 3年以内
要約データを Salesforce のケースに自動転記し、「電話 → CRM ケース → 後追い SMS」のフルオートメーションを CX 事業部の標準フローにする。

##### 3年以上
入電ハンドリングを完全に音声 AI 主導とし、ヒューマンエージェントは「クレーム対応」「契約確定の最終承認」など高付加価値業務に専念する組織設計に移行する。
:::

---

## Salesforce

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-04-28-05-05/9dfbbc32-sec-sf-20260505-155126-1.png" alt="Agentforce Operations のバックオフィス自動化、AI ロードマップ共創、Summer '26 Sandbox アップグレードを表現したピクセルアート・自動化ファクトリ" width="1024" height="1024">

### 13. Agentforce Operations を発表 — バックオフィス自動化

- **URL**: https://www.salesforce.com/news/stories/agentforce-operations-announcement/
- **要約**: Salesforce が 2026/4/29 に Agentforce Operations を発表。プロセス調整・データ照合・コンプライアンス確認などの定型バックオフィス業務を専門エージェントに委譲する仕組みで、サイクルタイムを 50〜70%、手入力エラーを 80% 改善できると主張。Flow との連携機能（auto-sync・Trigger Actions）は 5 月にベータ開始。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン契約後の「申し込み内容の事業者システムへの転記」「不動産仲介との進捗連携」を Agentforce Operations に置き換える PoC を実施し、CX 事業部の処理時間を 30% 削減する目標を立てる。

##### 3年以内
Agentforce + Flow による業務自動化を Salesforce 上の標準アーキテクチャに据え、人の介在は「例外処理」と「最終承認」のみに絞ったオペレーションに再設計する。

##### 3年以上
Agentforce が組織の実行レイヤを担う前提で、職務記述書・KPI 設計・教育体系を「人 × エージェントのチーム」に最適化する人事制度改革を進める。
:::

---

### 14. Salesforce、AI ロードマップを顧客と共創（クラウドソーシング）

- **URL**: https://techcrunch.com/2026/04/30/salesforce-is-crowdsourcing-its-ai-roadmap-with-customers/
- **要約**: Salesforce が AI ロードマップを「主要顧客と週次で議論しながらリアルタイムに調整」する方針を公表。従来の四半期ごとのリリースサイクルから、顧客フィードバック駆動の高速ループへ移行している。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
Salesforce のアカウントエグゼクティブと月次ロードマップレビューを設定し、ClassLab の業務要望（ServiceGuide__c の拡張、IsPersonAccount の運用課題）を上流で反映してもらう。

##### 3年以内
顧客起点ロードマップを社内にも展開し、自社プロダクト（RIRIFE・暮らしのメディア）でも「ヘビーユーザー会」を立ち上げて開発優先度を共創する文化を作る。

##### 3年以上
SaaS ベンダーとの関係を「購入者」から「共創パートナー」へ昇華させ、ベンダー側の R&D に ClassLab の業務知見を還流させる戦略パートナーシップを締結する。
:::

---

### 15. Summer '26 リリース — Sandbox は 5/9 にアップグレード

- **URL**: https://www.salesforceben.com/salesforce-summer-26-release-date-preview-information/
- **要約**: Summer '26 のプレビュー組織登録が 4/16 から開始、ほとんどの Sandbox は 2026/5/9 にアップグレードされる。本番環境は 5 月後半〜6 月にかけて段階的に適用予定。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
5/9 の Sandbox アップグレード前にリリースノートをシステム事業部でレビューし、ServiceGuide__c や Apex バッチの非互換変更を洗い出す回帰テストを実施する。

##### 3年以内
リリースノートのチェックを四半期ルーチンとして定型化し、ClassLab 専用の「Salesforce 影響度分析テンプレート」を整備する。

##### 3年以上
Salesforce のリリースサイクルに合わせた CI/CD パイプライン（SFDX + GitHub Actions）を成熟させ、新リリースのリスクを「読む前に検出」できる自動化基盤を確立する。
:::

---

## Anthropic

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-04-28-05-05/30886f3c-sec-anthropic-20260505-155125-1.png" alt="Claude Opus 4.7 GA、Mythos Preview、クリエイティブ系コネクタ、Claude Security を表現したピクセルアートのクロード・モナステリー" width="1024" height="1024">

### 16. Claude Opus 4.7 が一般提供開始

- **URL**: https://www.anthropic.com/news/claude-opus-4-7
- **要約**: Anthropic が Claude Opus 4.7 を GA。長尺コーディング・複雑な計画タスクで前世代を大きく上回り、画像入力の解像度も向上。Claude Code・Claude Platform・Bedrock で順次提供。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
システム事業部の主要開発機を Opus 4.6 → 4.7 へ移行する社内ガイダンスを発行し、長尺リファクタや複雑な PR レビューに 4.7 を優先採用する。

##### 3年以内
Opus 系列を「重い思考タスク用」、Sonnet/Haiku を「日常タスク用」と明確にレイヤ分けし、コスト感度の高いタスクは自動的に小型モデルへルーティングする社内 LLM ゲートウェイを整備する。

##### 3年以上
Opus 級モデルが組織の意思決定支援（経営会議の事前分析・市場調査）に常時関与する状態を前提に、AI 出力に対するガバナンス・監査ログ・人間レビューの仕組みを成熟させる。
:::

---

### 17. Claude Mythos Preview を発表（一般公開なし）

- **URL**: https://www.infoq.com/news/2026/04/anthropic-claude-mythos/
- **要約**: Anthropic が「最も高度なモデル」とする Claude Mythos のプレビューを発表。推論・コーディング・サイバーセキュリティで顕著な向上が見られるが、安全性評価が完了するまで一般公開は見送られる異例の対応。Anthropic の AI Safety Level（ASL）運用が一段厳格化した形。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
社内の AI 利用ポリシーに「フロンティアモデルは GA を待ってから業務利用」というルールを追加し、Mythos のような未公開モデルへの早期接触を統制する。

##### 3年以内
ASL に倣った社内 AI モデル評価基準を作り、生成 AI 採用時に「機密性・誤動作時の影響度・人命影響」の 3 軸でリスク分類する標準を運用する。

##### 3年以上
モデル提供元のセーフティ姿勢を契約評価項目に組み込み、SaaS / AI ベンダー選定における「セーフティガバナンス監査」を購買プロセスの必須項目とする。
:::

---

### 18. Adobe・Autodesk・Blender などクリエイティブ系コネクタを追加

- **URL**: https://www.testingcatalog.com/anthropic-rolls-out-claude-connectors-for-creative-platforms/
- **要約**: Claude が Adobe・Autodesk・Blender・Ableton・Splice・SketchUp・Resolume などクリエイティブ系ツールと直接連携できるコネクタを拡充。Claude が Photoshop のレイヤを直接操作したり、Blender でメッシュを生成したりすることが可能に。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
RIRIFE アプリ・暮らしのメディアのバナー・記事サムネイル制作で Claude × Photoshop コネクタを試し、デザイン業務の 30% を AI 補助化する PoC を行う。

##### 3年以内
メディア事業のクリエイティブ制作パイプライン（記事 → 画像 → 動画）を Claude 主導で半自動化し、編集者は方向性レビューに専念できる体制に移行する。

##### 3年以上
クリエイティブ・3D・音声を扱う AI コネクタが標準化された世界を前提に、自社プロダクトとクリエイティブツールを橋渡しするインハウス AI エージェントを内製する。
:::

---

### 19. Claude Security パブリックベータ — Enterprise 顧客向け脆弱性スキャン

- **URL**: https://platform.claude.com/docs/en/release-notes/overview
- **要約**: Anthropic が Claude Enterprise 顧客向けに Claude Security のパブリックベータを開始。Opus 4.7 ベースで、コードリポジトリの脆弱性スキャン・修正提案・優先度付けを自動化。Claude Platform 直接、または技術パートナー経由で利用可能。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン契約 API・RIRIFE バックエンドのリポジトリで Claude Security のスキャンを試行し、Snyk・GitHub Advanced Security との結果重なりとカバレッジ差分を比較する。

##### 3年以内
セキュリティスキャンを Claude Security へ集約し、修正 PR の自動起票・優先度付け・OWASP Top 10 マッピングまでを CI に組み込む。

##### 3年以上
全社のセキュアコーディング教育・脆弱性管理を AI 主導とし、人手での脆弱性対応は「クリティカル案件のレビュー」に絞り、対応リードタイムを大幅短縮する組織体制へ移行する。
:::

---

## GitHub トレンド

<img src="https://d2f75plg0t6qwk.cloudfront.net/issue/weekly-news-summary-2026-04-28-05-05/809f163e-sec-gh-20260505-155401-1.png" alt="GitHub トレンドのトロフィーホール — エージェント・スワーム ruflo、ナレッジグラフ GitNexus、トレーディング AI、Web スクレイピング Scrapling を表現したピクセルアート" width="1024" height="1024">

### 20. ruvnet/ruflo — Claude 用エージェントオーケストレーション

- **言語**: TypeScript
- **週間スター増**: +4,321
- **URL**: https://github.com/ruvnet/ruflo
- **要約**: Claude 向けのマルチエージェント・スワーム・オーケストレーションプラットフォーム。自律ワークフロー、会話 AI、エンタープライズ級アーキテクチャ、自己学習スワーム、RAG 統合、Claude Code ネイティブ統合を備える。社内エージェント基盤を作る際の参考実装として有用。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ruflo を雛形に、ClassLab 社内の Slack 通知・Salesforce 自動化・MarkdownViewer 投稿などを束ねる「業務エージェント・スワーム」の PoC を 2 週間で立ち上げる。

##### 3年以内
ruflo 由来のオーケストレーション層を本番運用に格上げし、各事業部（CX・NW・EA）固有のサブエージェント群を中央のスーパーバイザエージェントから制御する社内 PaaS を整備する。

##### 3年以上
オーケストレーション基盤を ClassLab 独自の業務 OS として育て、引越し・電力・通信などライフライン事業の意思決定支援にエージェント群が常駐する体制を作る。
:::

---

### 21. GitNexus — ブラウザ完結のナレッジグラフ + Graph RAG

- **言語**: TypeScript
- **週間スター増**: +5,423
- **URL**: https://github.com/topics/ai-2026
- **要約**: GitHub リポジトリや ZIP ファイルをブラウザにドロップすると、クライアントサイドだけで実行されるナレッジグラフが生成され、Graph RAG エージェントで対話できる OSS。サーバ側にコードを送らずに分析できるため、機微コードのセキュリティ要件を満たしやすい。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
ライフライン契約 API のリポジトリを GitNexus に投げ、引き継ぎや新人オンボーディングで「コードベースを質問して理解する」体験をジュニアエンジニアに提供する。

##### 3年以内
社内ナレッジ（コード・Notion・Salesforce ドキュメント）を統合した Graph RAG をクライアントサイドで動かす「セキュア社内検索」を整備する。

##### 3年以上
コード・ドキュメント・業務データを単一のグラフに統合し、組織知をグラフ構造で資産化する。新人〜役員までが同じグラフを介して意思決定できる「組織知ダッシュボード」を構築する。
:::

#### ハンズオン（ジュニアエンジニア向け）

GitNexus でリポジトリを可視化する（所要時間: 10分）:

```bash
# ブラウザで https://gitnexus.app を開く
# → ナレッジグラフ作成 UI が表示される

# 1. 自分が担当するリポジトリの ZIP を作る
git archive --format=zip HEAD > repo.zip
# → リポジトリのスナップショットが repo.zip に出力される

# 2. ブラウザの GitNexus にドラッグ&ドロップ
# → ローカルでファイルがパースされ、関数・クラス・依存関係のグラフが描画される

# 3. 右ペインの Graph RAG に「main 関数から順番に処理を説明して」と入力
# → コード全体を読まずに振る舞いの要約が得られる
```

**活用例3選**:
1. RIRIFE の iOS リポジトリを GitNexus にかけ、新規参画メンバーの初週オンボーディングに使う
2. classlab-weekly-news の Next.js コードベースを可視化し、microCMS 連携部分の依存関係を 1 枚絵で把握する
3. ライフライン契約 API を可視化して、解約・契約変更フローのドキュメント化漏れを発見する

**エンジニアの業務改善**: 大規模リポジトリのレビュー前に「全体地図」を 5 分で得られるため、PR ごとに何度もコードを読み返すコストを削減できる。

**オフィスワーカー向け**: 直接の利用想定は少ないが、エンジニアが業務担当者向けに「このリポジトリは何をしているか」を説明する際の図解ツールとして使える。

**システム構築ノウハウ**: クライアントサイド完結の Graph RAG はセキュリティ・コスト・スケーラビリティで優位。社内ツールを設計する際は「サーバを置かずに済む選択肢」を必ず一度評価する習慣を持つと良い。

---

### 22. TauricResearch/TradingAgents — マルチエージェント金融トレーディング

- **言語**: Python
- **Stars**: 65.3K
- **URL**: https://github.com/TauricResearch/TradingAgents
- **要約**: マルチエージェント LLM による金融トレーディングフレームワーク。アナリスト・リサーチャー・トレーダー・リスク管理など役割分担したエージェントが議論しながら売買判断を出す。エージェント協調パターンの実装例として参照価値が高い。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
TradingAgents の「役割分担エージェント」アーキテクチャを参考に、ライフライン契約の与信・乗り換え提案・最適プラン提示を分業する PoC エージェント群を組む。

##### 3年以内
役割分担エージェントを CRM・コールセンター・営業フォローのオペレーションに展開し、「複数エージェントが議論して 1 つの推奨を返す」社内意思決定支援を運用する。

##### 3年以上
ライフライン事業の根幹意思決定（プラン設計・卸電力調達・代理店配分）を、マルチエージェントが討議する半自律システムに段階的に置き換える将来像を描く。
:::

---

### 23. D4Vinci/Scrapling — 適応型 Web スクレイピングフレームワーク

- **言語**: Python
- **URL**: https://github.com/D4Vinci/Scrapling
- **要約**: 単発リクエストから大規模クロールまで、HTML 構造の変化に追従して自動的にセレクタを修復する適応型スクレイピングフレームワーク。Playwright・Requests を内部で使い分け、ボット対策回避もある程度サポート。

:::classlab-usage
#### Classlabでの活用

##### 1年以内
不動産会社サイトや競合ライフライン事業者の料金プランページを Scrapling で監視し、暮らしのメディアの記事ネタや NW 事業部の営業資料に自動で反映する PoC を行う。

##### 3年以内
価格・キャンペーン・規約変更を継続監視するスクレイピング基盤を運用標準化し、NW 事業部・EA 事業部が市場動向をダッシュボードで日次確認できる体制を作る。

##### 3年以上
Scrapling のような適応型スクレイパと LLM を組み合わせた「市場 OSINT 自動化基盤」を社内インフラとして育成し、競合分析・規制動向・ユーザートレンドを横断的に監視する経営計器盤を実現する。
:::
