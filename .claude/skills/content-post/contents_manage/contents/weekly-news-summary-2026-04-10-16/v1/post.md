
# 週間ニュースまとめ（2026年4月10日〜4月16日）

## 目次

- [Hacker News トップニュース](#hacker-news-トップニュース)
  - [1. Googleがプライバシーの約束を破り、ICEにデータを渡した](#1-googleがプライバシーの約束を破りiceにデータを渡した)
  - [2. 30個のWordPressプラグインが買収され、全てにバックドアが仕込まれた](#2-30個のwordpressプラグインが買収され全てにバックドアが仕込まれた)
  - [3. DaVinci Resolve — Photo（写真編集機能）](#3-davinci-resolve--photo写真編集機能)
  - [4. Flock監視カメラネットワークに対する反対運動「Stop Flock」](#4-flock監視カメラネットワークに対する反対運動stop-flock)
  - [5. Googleが「戻るボタン乗っ取り」に対する新スパムポリシーを発表](#5-googleが戻るボタン乗っ取りに対する新スパムポリシーを発表)
  - [6. Fiverr がユーザーのファイルを公開状態で検索可能にしていた](#6-fiverr-がユーザーのファイルを公開状態で検索可能にしていた)
  - [7. Claude Code Routines — 自動化ワークフロー機能](#7-claude-code-routines--自動化ワークフロー機能)
  - [8. ローカルLLMエコシステムにOllamaは不要](#8-ローカルllmエコシステムにollamaは不要)
  - [9. サイバーセキュリティはProof of Workになった](#9-サイバーセキュリティはproof-of-workになった)
  - [10. IPv6トラフィックが50%を突破](#10-ipv6トラフィックが50を突破)
- [Anthropic / Claude ニュース](#anthropic--claude-ニュース)
  - [1. Claude Sonnet 4.6 リリース](#1-claude-sonnet-46-リリース)
  - [2. Claude Code デスクトップアプリ刷新 & Routines](#2-claude-code-デスクトップアプリ刷新--routines)
  - [3. Claude Mythos Preview & Project Glasswing](#3-claude-mythos-preview--project-glasswing)
  - [4. Claude パフォーマンス低下問題](#4-claude-パフォーマンス低下問題)
- [Salesforce ニュース](#salesforce-ニュース)
  - [1. Experience Cloud セキュリティ攻撃（ShinyHunters）](#1-experience-cloud-セキュリティ攻撃shinyhunters)
  - [2. Summer '26 Preview Org 公開](#2-summer-26-preview-org-公開)
  - [3. FY26 Q4 決算 — 過去最高の四半期業績](#3-fy26-q4-決算--過去最高の四半期業績)
- [Zoom Phone ニュース](#zoom-phone-ニュース)
  - [1. Zoom Workplace 7.0 リリースとトラブル](#1-zoom-workplace-70-リリースとトラブル)
  - [2. Zoom CX × Virtual Agent のZoom Phone連携強化](#2-zoom-cx--virtual-agent-のzoom-phone連携強化)
- [GitHub トレンド](#github-トレンド)
  - [1. NousResearch/hermes-agent — 自己改善型AIエージェント](#1-nousresearchhermes-agent--自己改善型aiエージェント)
  - [2. MemPalace/mempalace — AIの長期記憶システム](#2-mempalacemempalace--aiの長期記憶システム)
  - [3. google/adk-python — Google Agent Development Kit](#3-googleadk-python--google-agent-development-kit)
  - [4. openai/codex — ターミナルベースのコーディングエージェント](#4-openaicodex--ターミナルベースのコーディングエージェント)
  - [5. safishamsi/graphify — コードをナレッジグラフ化するスキル](#5-safishamigraphify--コードをナレッジグラフ化するスキル)
  - [6. shanraisshan/claude-code-best-practice — Claude Code ベストプラクティス集](#6-shanraisshanClaude-code-best-practice--claude-code-ベストプラクティス集)

---

## Hacker News トップニュース

### 1. Googleがプライバシーの約束を破り、ICEにデータを渡した
- **原題**: Google broke its promise to me – now ICE has my data
- **スコア**: 1,555pt / コメント: 671件
- **URL**: https://www.eff.org/deeplinks/2026/04/google-broke-its-promise-me-now-ice-has-my-data
- **要約**: EFF（電子フロンティア財団）が、Googleがプライバシー保護の約束に反してユーザーデータをICE（米国移民税関捜査局）に提供したと告発。テック企業のプライバシーポリシーの信頼性に大きな疑問を投げかけている。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 自社のプライバシーポリシー・個人情報取扱規程を再点検する。特にSalesforceに蓄積された入居者データ（ServiceGuide__c）のアクセス権限を監査する |
| 1年以上 | 30万人の新生活者データを扱う企業として、データガバナンス体制を構築。外部パートナー（イタンジ等）とのデータ共有契約を見直す |
| 3年以上 | プライバシー・バイ・デザインを全サービスに組み込み、RIRIFE/ライフライン事業で「信頼される新生活プラットフォーム」としてのブランド価値を確立する |

---

### 2. 30個のWordPressプラグインが買収され、全てにバックドアが仕込まれた
- **原題**: Someone bought 30 WordPress plugins and planted a backdoor in all of them
- **スコア**: 1,182pt / コメント: 337件
- **URL**: https://anchor.host/someone-bought-30-wordpress-plugins-and-planted-a-backdoor-in-all-of-them/
- **要約**: 何者かが30のWordPressプラグインを買収し、すべてにバックドアを仕込んだ。サプライチェーン攻撃の手法として、正規のプラグインを買収して悪意あるコードを注入するケースが増加している。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | classlab.co.jp/rirife/ 等のWordPressサイトで使用中のプラグインを全棚卸し。開発元が変更されたプラグインがないか確認する。SiteGuard Lite WAFのルールを最新化する |
| 1年以上 | WordPressプラグインの依存関係監視を自動化（Dependabot等）。サプライチェーンセキュリティのチェックリストを整備する |
| 3年以上 | WordPressに依存しないヘッドレスCMS化や、自社メディア基盤の内製化を検討。外部依存のリスクを構造的に減らす |

#### ハンズオン（ジュニアエンジニア向け）

自社WordPressサイトのプラグイン監査（所要時間: 15分）:

```bash
# WordPress CLIでインストール済みプラグイン一覧を取得
wp plugin list --format=csv
# → プラグイン名、バージョン、ステータス（有効/無効）、更新有無がCSVで表示される

# 各プラグインの詳細情報（作者、最終更新日）を確認
wp plugin list --fields=name,version,author,update_version --format=table
# → 作者が変わっている or 長期間更新されていないプラグインを特定できる
```

**活用例3選**:
1. classlab.co.jp/rirife/（暮らしのメディア）のプラグイン棚卸しレポートを作成
2. classlab.co.jp/engineer（エンジニア採用サイト）のElementor含む全プラグインのセキュリティチェック
3. WordPress REST API経由の記事投稿スキルで使用しているプラグインの依存関係確認

**エンジニアの業務改善**: CI/CDパイプラインにプラグインバージョン監視ステップを追加し、未知の更新があった場合にSlack通知する仕組みを構築

**オフィスワーカー向け**: WordPress管理画面でプラグイン更新通知が来たら、すぐに更新せず、変更内容を確認してからシステム事業部に報告するフローを徹底

**システム構築ノウハウ**: プラグインの自動更新は無効化し、ステージング環境で検証後に本番反映する運用パターンが重要

---

### 3. DaVinci Resolve — Photo（写真編集機能）
- **原題**: DaVinci Resolve – Photo
- **スコア**: 1,128pt / コメント: 293件
- **URL**: https://www.blackmagicdesign.com/products/davinciresolve/photo
- **要約**: Blackmagic Designが動画編集ソフトDaVinci Resolveに本格的な写真編集機能を追加。Adobe Lightroomの競合となる無料の写真編集ツールとして注目を集めている。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | RIRIFEアプリやメディア記事用の画像編集にDaVinci Resolve Photoを試用。Adobe Creative Cloud費用の削減可能性を検証する |
| 1年以上 | EA事業部・コーポレートのマーケティング素材制作ワークフローに無料ツールを組み込み、外注コストを削減 |
| 3年以上 | 新生活者向けコンテンツ（動画/写真）の内製制作体制を強化。DaVinci Resolveの動画+写真一体型ワークフローでメディア事業の生産性を向上 |

---

### 4. Flock監視カメラネットワークに対する反対運動「Stop Flock」
- **原題**: Stop Flock
- **スコア**: 958pt / コメント: 293件
- **URL**: https://stopflock.com
- **要約**: Flock Safetyの自動ナンバープレート読取（ALPR）カメラネットワークが米国で急拡大しており、住民の同意なく全車両の移動を追跡する監視インフラに対する市民運動が活発化。プライバシー権との衝突が大きな議論を呼んでいる。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 入居者データを扱うサービスとして、監視技術の社会的議論を社内勉強会で共有。プライバシーファーストの企業姿勢を社内浸透させる |
| 1年以上 | RIRIFEアプリの位置情報・行動データ利用ポリシーを策定。ユーザーに透明性を担保した設計にする |
| 3年以上 | 「信頼される新生活プラットフォーム」としてプライバシー保護を差別化要因にする。不動産業界全体のデータ倫理基準策定に参画 |

---

### 5. Googleが「戻るボタン乗っ取り」に対する新スパムポリシーを発表
- **原題**: A new spam policy for "back button hijacking"
- **スコア**: 901pt / コメント: 509件
- **URL**: https://developers.google.com/search/blog/2026/04/back-button-hijacking
- **要約**: Googleが、ブラウザの戻るボタンを乗っ取ってユーザーを同じページに留まらせる手法をスパムとして正式に認定。検索ランキングからの除外対象となる。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | classlab.co.jp、rirife.jpの全ページでブラウザバック挙動を検証。外部広告タグやサードパーティスクリプトが戻るボタンを阻害していないか確認する |
| 1年以上 | SEO監視ルーティンにブラウザバック挙動チェックを追加。新しい広告パートナー導入時の技術審査基準に含める |
| 3年以上 | Google検索ポリシーの厳格化トレンドを踏まえ、メディア事業のSEO戦略をユーザー体験重視型に完全シフト |

#### ハンズオン（ジュニアエンジニア向け）

自社サイトの戻るボタン挙動チェック（所要時間: 10分）:

```bash
# Puppeteerでブラウザバック挙動を自動テスト
npx puppeteer-cli screenshot --url "https://classlab.co.jp" --output before.png
# → classlab.co.jpのスクリーンショットが保存される
```

```javascript
// Chrome DevToolsコンソールで確認
// 1. 対象ページを開く
// 2. DevTools > Console で以下を実行
window.history.length
// → 通常は1-2。異常に大きい数値なら履歴操作の可能性あり
```

**活用例3選**:
1. classlab.co.jp/rirife/（暮らしのメディア）の全広告タグのブラウザバック影響を検証
2. merchant.rirife.jp（加盟店登録）のフォーム離脱時の挙動確認
3. エンジニア採用サイト（classlab.co.jp/engineer）のSEO影響チェック

**エンジニアの業務改善**: Lighthouse CIにカスタム監査（history.pushState乱用チェック）を追加し、PRマージ前に自動検出

**オフィスワーカー向け**: 広告パートナーから提供されるタグの導入前にシステム事業部へ技術レビューを依頼するフローを明確化

**システム構築ノウハウ**: SPAのルーティングでhistory.pushStateを使う場合、不要な履歴エントリが生成されていないか注意。Next.jsのApp Routerなら標準で安全

---

### 6. Fiverr がユーザーのファイルを公開状態で検索可能にしていた
- **原題**: Tell HN: Fiverr left customer files public and searchable
- **スコア**: 810pt / コメント: 230件
- **URL**: https://news.ycombinator.com/item?id=47769796
- **要約**: フリーランスプラットフォームFiverrが顧客のファイル（納品物、個人情報含む）を外部から検索・アクセス可能な状態で放置していたことが発覚。S3バケットの設定ミスに起因するデータ漏洩の典型例。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 自社のクラウドストレージ（GCS/S3）のパブリックアクセス設定を即時監査。AI-OCRで処理するFAX画像の保管先のアクセス権限を確認する |
| 1年以上 | クラウドストレージのセキュリティ監査を四半期ごとに実施する運用を確立。外部委託先にも同等のセキュリティ基準を要求 |
| 3年以上 | ゼロトラストアーキテクチャを全社システムに適用。ファイルストレージはデフォルト非公開+最小権限の原則を徹底 |

---

### 7. Claude Code Routines — 自動化ワークフロー機能
- **原題**: Claude Code Routines
- **スコア**: 705pt / コメント: 403件
- **URL**: https://code.claude.com/docs/en/routines
- **要約**: Anthropicが Claude Code に「Routines」機能を発表。スケジュール実行・API トリガー・GitHub イベント連携で、コーディング作業を自動化できる。ローカルPCがオフラインでもクラウド上で動作する。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Claude Code Routinesで以下を自動化: ①毎週のニュースまとめ生成 ②PRレビューの自動トリアージ ③Salesforceデータの定期監査レポート生成 |
| 1年以上 | 開発ワークフロー全体をRoutinesで自動化。デプロイ検証、ドキュメント更新検知、アラートトリアージをClaude Codeに委任 |
| 3年以上 | AI駆動のDevOpsパイプラインを構築。コードレビュー→テスト→デプロイ→監視→改善のサイクルをRoutinesで半自動化 |

#### ハンズオン（ジュニアエンジニア向け）

Claude Code Routinesの設定（所要時間: 15分）:

```bash
# Claude Codeを最新版に更新
claude update
# → Claude Code CLIが最新バージョンに更新される

# Routineの作成（Claude Code Desktop or CLI）
# 1. Claude Code Desktopを開く
# 2. 左サイドバーの「Routines」タブをクリック
# 3. 「+ New Routine」で新規作成
# → プロンプト、リポジトリ、トリガー（スケジュール/API/GitHub）を設定する画面が表示される
```

**活用例3選**:
1. 毎朝9時にSalesforceの ServiceGuide__c の未処理レコード数をSlackに通知するRoutine
2. GitHub PRが作成されたらコードレビュー＋セキュリティチェックを自動実行するRoutine
3. 毎週金曜にweekly-newsスキルを自動実行して下書きを生成するRoutine

**エンジニアの業務改善**: 定型的なレビュー・テスト・レポート業務をRoutinesに委任し、創造的な開発業務に集中できる時間を確保

**オフィスワーカー向け**: API トリガーを使えば、Slackのスラッシュコマンドからデータ集計やレポート生成をClaude Codeに依頼できる仕組みが作れる

**システム構築ノウハウ**: Routinesはクラウド実行のため、機密データへのアクセスには注意。Salesforce OAuthトークン等は環境変数経由で安全に渡す設計にする

---

### 8. ローカルLLMエコシステムにOllamaは不要
- **原題**: The local LLM ecosystem doesn't need Ollama
- **スコア**: 546pt / コメント: 166件
- **URL**: https://sleepingrobots.com/dreams/stop-using-ollama/
- **要約**: Ollamaが過度に推奨されているが、llama.cppやvLLM等を直接使う方が柔軟で効率的だという主張。ローカルLLM実行のアーキテクチャ選択に関する議論。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | AI-OCRやAIトレーナーで使用するモデルの推論基盤を比較検証。Ollama vs llama.cpp vs vLLMのベンチマークを実施 |
| 1年以上 | 社内AIインフラの推論基盤を標準化。コスト・レイテンシ・運用負荷のバランスで最適な構成を決定 |
| 3年以上 | オンプレミスLLM推論基盤の構築により、入居者データを外部に送信しない完全プライベートAI環境を実現 |

---

### 9. サイバーセキュリティはProof of Workになった
- **原題**: Cybersecurity looks like proof of work now
- **スコア**: 471pt / コメント: 174件
- **URL**: https://www.dbreunig.com/2026/04/14/cybersecurity-is-proof-of-work-now.html
- **要約**: 現代のサイバーセキュリティは、実際のリスク軽減よりもコンプライアンスチェックリストを埋める「Proof of Work」（作業証明）になっているという批判。形式的なセキュリティ対策と実効性のギャップを指摘。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 現在のセキュリティ施策（SiteGuard Lite WAF等）が「チェックリスト消化」になっていないか実効性を評価する |
| 1年以上 | 形式的なセキュリティチェックから、実際の脅威シナリオに基づくリスクベースのセキュリティ戦略へ転換 |
| 3年以上 | 30万人の個人情報を扱う企業として、セキュリティをコスト部門ではなく信頼のブランド資産として位置づける経営判断 |

---

### 10. IPv6トラフィックが50%を突破
- **原題**: IPv6 traffic crosses the 50% mark
- **スコア**: 442pt / コメント: 266件
- **URL**: https://www.google.com/intl/en/ipv6/statistics.html
- **要約**: Googleの統計によると、IPv6トラフィックが全体の50%を超えた。インターネットインフラの世代交代が着実に進んでいることを示す歴史的なマイルストーン。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | classlab.co.jp、rirife.jpのIPv6対応状況を確認。CDN/ロードバランサーのIPv6設定を有効化する |
| 1年以上 | 社内ネットワーク・VPNのIPv6対応計画を策定。外部API連携先（電力会社REST API等）のIPv6対応状況を確認 |
| 3年以上 | IPv4枯渇を見据えた全システムのデュアルスタック対応完了 |

---

## Anthropic / Claude ニュース

### 1. Claude Sonnet 4.6 リリース
- **URL**: https://releasebot.io/updates/anthropic/claude
- **要約**: Anthropicが最新のSonnet 4.6をリリース。コーディング、コンピュータ操作、長文脈推論、エージェント計画、知識作業、デザインの全領域で改善。1Mトークンのコンテキストウィンドウをベータ提供。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Claude Code での開発生産性向上を即座に享受。1Mコンテキストを活用してSalesforceの大規模コードベース全体を一括レビュー |
| 1年以上 | Sonnet 4.6のエージェント計画能力を活かし、複雑な業務フロー（入居者情報→契約代行→報告）の自動化エージェントを構築 |
| 3年以上 | AI-first開発体制の確立。コーディング能力の向上に伴い、少人数エンジニアチームでも大規模システム開発が可能な体制を構築 |

---

### 2. Claude Code デスクトップアプリ刷新 & Routines
- **URL**: https://siliconangle.com/2026/04/14/anthropics-claude-code-gets-automated-routines-desktop-makeover/
- **要約**: 4月14日、Claude Codeデスクトップアプリ（Mac/Windows）の完全リデザインとRoutines機能のリサーチプレビューを同時発表。統合ターミナル、高速diffビューア、アプリ内ファイルエディタ、拡張プレビューエリアを搭載。Routinesはスケジュール・API・GitHubイベントをトリガーとした自動化実行が可能。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | チーム全員のClaude Code Desktopを最新版に更新。統合ターミナルにより開発環境の切り替え回数を削減。Routinesで週次ニュース生成を自動化 |
| 1年以上 | RoutinesのGitHubトリガーを活用し、PR作成→レビュー→テスト→マージのCI/CDパイプラインにAIを組み込む |
| 3年以上 | AI駆動の開発プロセスオートメーション。人間はアーキテクチャ設計と意思決定に集中し、実装・テスト・デプロイはAIが担う体制 |

---

### 3. Claude Mythos Preview & Project Glasswing
- **URL**: https://red.anthropic.com/2026/mythos-preview/
- **要約**: Anthropicが新モデル「Claude Mythos Preview」を発表。コンピュータセキュリティタスクに特化した能力を持つ汎用言語モデル。同時に「Project Glasswing」を始動し、Mythos Previewを使って世界の重要ソフトウェアのセキュリティ確保を目指す。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Mythos Previewが一般提供された際に、自社コードベースのセキュリティ監査に活用するPoCを計画 |
| 1年以上 | AI駆動のセキュリティ監視体制を構築。入居者データを扱うSalesforce連携コードの脆弱性検出を自動化 |
| 3年以上 | AIセキュリティエンジニアの概念が定着。専任セキュリティ人材が不足していても、AIで高度なセキュリティ水準を維持 |

---

### 4. Claude パフォーマンス低下問題
- **URL**: https://fortune.com/2026/04/14/anthropic-claude-performance-decline-user-complaints-backlash-lack-of-transparency-accusations-compute-crunch/
- **要約**: 開発者やユーザーからClaudeのパフォーマンス低下の報告が相次いでいる。指示への追従精度が下がり、ミスが増えているとの指摘。Anthropicがデフォルトの「effort」レベルを下げてトークン処理を効率化していることが原因とみられる。4月15日には大規模な障害も発生。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Claude依存度の高いワークフロー（AI-OCR、コード生成等）にフォールバック戦略を策定。重要なタスクではextended thinkingや明示的なeffortレベル指定を活用 |
| 1年以上 | 特定のAIプロバイダーへの過度な依存を避けるマルチLLM戦略を検討。用途ごとに最適なモデルを使い分ける体制 |
| 3年以上 | AI品質の変動リスクを織り込んだシステム設計。SLA定義、自動品質モニタリング、プロバイダー切り替え機構の標準装備 |

---

## Salesforce ニュース

### 1. Experience Cloud セキュリティ攻撃（ShinyHunters）
- **URL**: https://www.salesforceben.com/shinyhunters-breach-400-companies-via-salesforce-experience-cloud/
- **要約**: ハッカーグループ ShinyHunters が Salesforce Experience Cloud のゲストユーザー設定の甘い組織を標的に、300〜400社のデータを窃取。修正版Aura Inspectorツールで公開サイトを大量スキャンし、名前・電話番号等を抽出。Snowflake、Okta、Sony等の大企業も被害。Salesforce自体の脆弱性ではなく、顧客側の設定不備が原因。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | **最優先**: ClassLabのSalesforce環境（classlab2.lightning.force.com）のExperience Cloudゲストユーザー設定を即座に監査。ServiceGuide__c等の個人情報オブジェクトへのゲストアクセスが無効であることを確認する |
| 1年以上 | Salesforceのセキュリティ健全性チェックを四半期ごとに実施するルーティンを確立。Salesforce Security Health Checkスコアの定期モニタリング |
| 3年以上 | CRMのセキュリティアーキテクチャをゼロトラスト原則で再設計。外部連携ポイント（イタンジ、電力会社API等）含めた包括的なセキュリティフレームワーク |

#### ハンズオン（ジュニアエンジニア向け）

Salesforce Experience Cloudゲストユーザー設定の確認（所要時間: 10分）:

```
1. Salesforce Setup > Sites > 該当サイトの「Public Access Settings」を開く
   - → ゲストユーザープロファイルの権限設定画面が表示される

2. 「Object Settings」で各オブジェクトのアクセス権限を確認
   - → ServiceGuide__c, Employee__c 等のオブジェクトにRead権限がないことを確認

3. Setup > Security > Health Check を開く
   - → セキュリティ設定のスコア（0-100）と改善推奨事項が表示される
```

**活用例3選**:
1. ServiceGuide__c（入居者情報）へのゲストアクセスが完全にブロックされているか確認
2. Account（不動産会社情報）の公開範囲が最小限に制限されているか検証
3. Salesforce Security Health Checkの結果を基にセキュリティ改善タスクを起票

**エンジニアの業務改善**: Salesforce CLI（sf）でゲストユーザープロファイルの権限をメタデータとしてGit管理し、設定変更の追跡・レビューを可能にする

**オフィスワーカー向け**: CX/NW事業部のメンバーが新しいレポートやダッシュボードを共有する際、ゲストユーザーに意図せずアクセス権が付与されないよう注意

**システム構築ノウハウ**: Experience Cloudを使う場合はゲストユーザープロファイルのOWD（組織のデフォルトアクセス）をPrivateに設定。共有ルールでの例外許可は最小限に

---

### 2. Summer '26 Preview Org 公開
- **URL**: https://www.salesforce.com/news/stories/fy26-q3-highlights/
- **要約**: Salesforce Summer '26のPreview Orgが利用可能に。新機能のプレビューテストが開始されている。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Preview Orgで Summer '26 の新機能（特にAgentforce関連）を検証。ClassLabのカスタムオブジェクトとの互換性を確認 |
| 1年以上 | リリースサイクルに合わせたSalesforce機能検証プロセスを標準化。Preview → Sandbox → 本番のデプロイフローを確立 |
| 3年以上 | Salesforceの進化方向（AI-first CRM）に合わせた自社システムのロードマップ策定 |

---

### 3. FY26 Q4 決算 — 過去最高の四半期業績
- **URL**: https://investor.salesforce.com/news/news-details/2026/Salesforce-Delivers-Record-Fourth-Quarter-Fiscal-2026-Results/default.aspx
- **要約**: SalesforceがFY26 Q4で過去最高の四半期業績を達成。配当金は1株あたり$0.44（前年比5.8%増）、4月23日に支払い予定。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Salesforceの好業績はプラットフォームの安定性と継続投資を示唆。現行CRM基盤への信頼を維持しつつ、新機能の活用を推進 |
| 1年以上 | Salesforceの成長領域（Agentforce, Data Cloud）への投資動向を注視し、ClassLabのCRM戦略に反映 |
| 3年以上 | SaaS型CRM vs 内製CRMの長期コスト比較を定期的に実施。事業規模の拡大に伴うライセンスコスト増への備え |

---

## Zoom Phone ニュース

### 1. Zoom Workplace 7.0 リリースとトラブル
- **URL**: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0061222
- **要約**: Zoom Workplace 7.0.0がリリースされたが、北米ユーザーに影響するバグが発生し一時ダウンロード停止。4月3日にhotfix版7.0.2で復旧。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 社内Zoom Workplaceのバージョンを7.0.2以降に更新。CXコールセンターの通話品質に影響がないか確認 |
| 1年以上 | Zoom大型アップデート時の社内展開プロセスを整備。IT管理者がステージング的に検証してから全社展開する仕組み |
| 3年以上 | UCaaS（統合コミュニケーション）の選定基準として安定性・障害復旧速度を重視した評価フレームワークを確立 |

---

### 2. Zoom CX × Virtual Agent のZoom Phone連携強化
- **URL**: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062333
- **要約**: Zoom CXがバーチャルエージェント通話からZoom Phoneエージェントへの転送時に、通話サマリーと変数を自動引き継ぎ可能に。バーチャルエージェントの通話録音・自動文字起こし機能もCX Analyticsに統合。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | CX事業部のコールセンター運用にZoom CX Virtual Agentを検証導入。入電の一次応対をAIが行い、複雑な案件のみ人間オペレーターに転送する仕組みをPoCする |
| 1年以上 | AIトレーナー（既存の研修AI）とZoom CX Virtual Agentを連携。研修→実務→品質評価のサイクルをシームレスに |
| 3年以上 | コールセンターの完全AI化。定型的なライフライン契約代行はVirtual Agentが処理し、人間は複雑な相談・クレーム対応に特化 |

#### ハンズオン（ジュニアエンジニア向け）

Zoom CX Virtual Agent の設定確認（所要時間: 20分）:

```
1. Zoom管理者ポータル > Phone System Management > Auto Receptionist を開く
   - → 自動応答のルーティング設定画面が表示される

2. 「Virtual Agent」タブでAIエージェントの設定を確認
   - → 応対シナリオ、転送条件、録音設定が表示される

3. CX Analytics > Recordings で録音・文字起こし結果を確認
   - → バーチャルエージェントの応対内容がテキストで閲覧できる
```

**活用例3選**:
1. 電気・ガスの契約代行の初期ヒアリング（住所・契約種別）をVirtual Agentに移管
2. 多言語対応（10言語）の一次応対をAIで処理し、人間オペレーターの負荷を軽減
3. 通話録音データをAIトレーナーの研修教材として活用

**エンジニアの業務改善**: Zoom CX APIを使って、通話サマリーをSalesforce ServiceGuide__cに自動連携するインテグレーションを構築

**オフィスワーカー向け**: CX事業部のオペレーターは、Virtual Agentから引き継がれた通話サマリーを確認してから応対開始することで、顧客への繰り返し質問を減らせる

**システム構築ノウハウ**: Zoom CX → Salesforce連携は Webhook + Zoom API + Salesforce REST API の構成。通話メタデータの自動同期で、Salesforce側のServiceGuide__cレコードに通話履歴を紐づける

---

## GitHub トレンド

### 1. NousResearch/hermes-agent — 自己改善型AIエージェント
- **言語**: Python
- **Stars**: 87.6K+
- **URL**: https://github.com/NousResearch/hermes-agent
- **要約**: Nous Researchが開発した自己改善型AIエージェント。使用するたびにスキルを学習し、過去の会話を検索し、ユーザーのモデルを深化させる。v0.9.0（4月13日リリース）で16プラットフォーム対応、Termux/Android、iMessage/WeChat連携、ローカルWebダッシュボードを搭載。$5 VPSからGPUクラスターまで任意のインフラで動作。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | hermes-agentを社内検証環境にデプロイし、ライフライン事業の定型業務（入居者情報確認、契約状況照会）をエージェント化するPoCを実施 |
| 1年以上 | Telegram/Slack連携を活用し、NW事業部の営業担当がモバイルからhermes-agent経由でSalesforceデータを照会できる仕組みを構築 |
| 3年以上 | 自己改善型エージェントをコールセンター業務に導入。AIトレーナーで研修したナレッジをエージェントに蓄積し、対応品質が継続的に向上するシステムを構築 |

#### ハンズオン（ジュニアエンジニア向け）

hermes-agentのローカルセットアップ（所要時間: 15分）:

```bash
# リポジトリのクローン
git clone https://github.com/NousResearch/hermes-agent.git
# → hermes-agentのソースコードがローカルにダウンロードされる

cd hermes-agent

# 依存パッケージのインストール
pip install -e .
# → Python環境にhermes-agentとその依存ライブラリがインストールされる

# 設定ファイルの作成（Anthropic APIキーを使用する例）
cp config.example.yaml config.yaml
# → 設定テンプレートがコピーされる。エディタでAPIキーを設定する

# エージェントの起動
hermes start
# → ローカルWebダッシュボードが起動し、ブラウザからエージェントと対話できる
```

**活用例3選**:
1. Salesforce APIと連携させ、「今日の未処理案件は？」とSlackで聞くと集計結果を返すエージェント
2. 不動産会社からのFAX受信をトリガーに、AI-OCR結果をエージェントが自動確認・補正
3. 新人オペレーター向けのQ&Aボットとして、過去のトークスクリプトから回答を生成

**エンジニアの業務改善**: hermes-agentのスキル学習機能を使い、コードベース固有のパターン（Salesforce Apexの書き方等）を学習させたペアプロ補助エージェントを育成

**オフィスワーカー向け**: Telegram経由で「〇〇不動産の今月の送客数は？」のような自然言語クエリでSalesforceデータにアクセスできるUIを提供

**システム構築ノウハウ**: MITライセンスで商用利用可。モデルはNous Portal/OpenRouter/OpenAI/自前エンドポイントから選択可能。本番運用時はAPIキーの環境変数管理とアクセスログの記録を必須とする

---

### 2. MemPalace/mempalace — AIの長期記憶システム
- **言語**: Python
- **Stars**: 23K+（4月6日リリース後2日で達成）
- **URL**: https://github.com/MemPalace/mempalace
- **要約**: LLMに永続的なクロスセッション記憶を与えるオープンソースシステム。会話履歴をテキストで保存し、セマンティック検索で呼び出す。「記憶の宮殿」メタファーでwing（人物/プロジェクト）→hall（記憶タイプ）→room（具体的アイデア）の構造で整理。LongMemEvalベンチマークで96.6%（ハイブリッド100%）の最高スコアを主張するが、テストセットへの過学習が指摘されて議論中。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Claude Codeの既存メモリ機能との比較検証。MemPalaceの構造化記憶アプローチが、複雑な事業ドメイン知識（ライフライン業界構造等）の保持に有効か評価 |
| 1年以上 | AIアシスタントの長期記憶基盤として導入。オペレーターごとの対応ノウハウをAIが記憶し、異動時にも知識が引き継がれる仕組み |
| 3年以上 | 組織のナレッジマネジメント基盤としてAI記憶システムを活用。暗黙知の形式知化を自動的に行う体制 |

---

### 3. google/adk-python — Google Agent Development Kit
- **言語**: Python / TypeScript / Go / Java
- **Stars**: 8.2K+
- **URL**: https://github.com/google/adk-python
- **要約**: Googleが開発したマルチエージェントシステム構築フレームワーク。コードファーストでエージェントのロジック・ツール・オーケストレーションをPythonで定義。Gemini最適化だがモデル非依存。複数の専門エージェントを階層構造で組み合わせるモジュラー設計。Cloud RunやVertex AI Agent Engineにデプロイ可能。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | ADKを使ってライフライン事業のマルチエージェントPoCを構築: ①入居者情報取得エージェント ②契約プラン比較エージェント ③申込手続きエージェント の3体連携 |
| 1年以上 | ADKベースの業務自動化プラットフォームを構築。各事業部ごとに専門エージェントを配置し、オーケストレーションエージェントが連携を管理 |
| 3年以上 | AIエージェントの階層構造で組織全体の業務を支援するフレームワークを確立。新規事業立ち上げ時にエージェントをアタッチするだけで業務が回る体制 |

#### ハンズオン（ジュニアエンジニア向け）

Google ADKで簡単なエージェントを作成（所要時間: 20分）:

```bash
# ADKのインストール
pip install google-adk
# → Python環境にADKパッケージがインストールされる

# プロジェクトの初期化
adk init my-first-agent
# → エージェントのテンプレートディレクトリが作成される

cd my-first-agent
```

```python
# agent.py の例
from google.adk import Agent, Tool

@Tool
def get_weather(city: str) -> str:
    """指定都市の天気を返す"""
    return f"{city}の天気は晴れです"

agent = Agent(
    name="weather_agent",
    tools=[get_weather],
    model="gemini-2.5-flash"
)
```

```bash
# エージェントの実行
adk run
# → ローカルでエージェントが起動し、対話型プロンプトが表示される
```

**活用例3選**:
1. Salesforce APIをToolとして登録し、入居者情報の検索・更新を自然言語で実行するエージェント
2. 電力会社のプラン比較APIをToolに組み込み、最適プラン提案エージェントを構築
3. Slack Toolを追加して、CX事業部への自動エスカレーション通知エージェントを作成

**エンジニアの業務改善**: ADKのモジュラー設計を活かし、共通ツール（Salesforce接続、Slack通知等）をパッケージ化して全エージェントで再利用

**オフィスワーカー向け**: 完成したエージェントをSlackボットとして公開すれば、プログラミング不要で自然言語でSalesforceデータにアクセス可能

**システム構築ノウハウ**: ADKはGemini最適化だが、Anthropic/OpenAIモデルも利用可能。本番ではVertex AI Agent Engineにデプロイすることでスケーリングとモニタリングが容易

---

### 4. openai/codex — ターミナルベースのコーディングエージェント
- **言語**: Rust
- **Stars**: 5.8K+
- **URL**: https://github.com/openai/codex
- **要約**: OpenAIが開発したオープンソースのコーディングエージェント。ターミナルで動作し、コードの読み取り・変更・実行が可能。サブエージェントによる並列タスク処理、MCP（Model Context Protocol）対応、Web検索機能を搭載。Rustで構築されており高速。ChatGPT Plus/Pro/Businessアカウントまたは自前のAPIキーで利用可能。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Claude Code との比較検証。特にSalesforce Apex開発やPython AI開発において、どちらのエージェントが生産性が高いか評価 |
| 1年以上 | 開発チーム内でClaude Code + Codex CLIのハイブリッド運用を確立。タスクの性質に応じて最適なツールを使い分け |
| 3年以上 | AIコーディングエージェントの標準化。複数のAIツールを統合したIDE環境で、エンジニアの生産性を10倍化する開発基盤 |

#### ハンズオン（ジュニアエンジニア向け）

OpenAI Codex CLIのセットアップ（所要時間: 10分）:

```bash
# npmでインストール
npm install -g @openai/codex
# → codex コマンドがグローバルに利用可能になる

# または Homebrew（macOS）
brew install --cask codex
# → Codex CLIがインストールされる

# 認証設定（OpenAI APIキーを使用）
export OPENAI_API_KEY="your-api-key"
# → 環境変数にAPIキーが設定される

# プロジェクトディレクトリで起動
codex
# → インタラクティブなCLIが起動し、自然言語でコーディング指示を出せる
```

**活用例3選**:
1. Salesforce Apexクラスのユニットテスト生成を Codex CLI で自動化
2. AI-OCRのPythonコードリファクタリングをCodexに依頼
3. CI/CDパイプラインのYAML設定ファイル生成

**エンジニアの業務改善**: Claude CodeとCodex CLIを併用し、それぞれの得意領域（Claude: 長文脈理解、Codex: 高速実行）を使い分ける

**オフィスワーカー向け**: 直接的な利用は難しいが、エンジニアの開発効率向上により、社内ツール改善リクエストへの対応速度が上がる

**システム構築ノウハウ**: MCP対応により、Salesforce MCPサーバーやGitHub MCPサーバーを接続して、外部サービスとの連携タスクを自然言語で実行可能

---

### 5. safishamsi/graphify — コードをナレッジグラフ化するスキル
- **言語**: Python
- **Stars**: トレンド急上昇中
- **URL**: https://github.com/safishamsi/graphify
- **要約**: コード・ドキュメント・論文・画像・動画をクエリ可能なナレッジグラフに変換するAIコーディングアシスタントスキル。Claude Code、Codex、Cursor、Gemini CLI等の主要AIツールで `/graphify` コマンドとして利用可能。フォルダ全体を解析してシンボル間の関係性をグラフ構造で可視化する。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | Salesforce Apexコードベースをgraphifyでナレッジグラフ化し、オブジェクト間の依存関係を可視化。新メンバーのオンボーディングを加速 |
| 1年以上 | 全社のコードベース（Salesforce + フロントエンド + AIシステム）を統合ナレッジグラフとして管理。アーキテクチャの全体像把握を容易に |
| 3年以上 | コードとドキュメントの関係をAIが自動で維持管理。「このAPIを変更したら影響範囲は？」の問いにAIが即答できる体制 |

#### ハンズオン（ジュニアエンジニア向け）

graphifyでコードベースを解析（所要時間: 10分）:

```bash
# graphifyのインストール
pip install graphifyy
# → Python環境にgraphifyパッケージがインストールされる

# Claude Codeスキルとしてインストール
claude skill install graphify
# → Claude Code で /graphify コマンドが使えるようになる

# コードベースの解析
# Claude Code内で以下を実行:
# /graphify
# → 現在のディレクトリ全体がスキャンされ、ナレッジグラフが生成される
```

**活用例3選**:
1. Salesforce Apexのトリガー・クラス間の依存関係をグラフで可視化
2. AI-OCRシステムのモジュール構成を新人エンジニアに説明する資料として活用
3. リファクタリング前に影響範囲を特定するためのコード関係性分析

**エンジニアの業務改善**: 大規模なコードベースの全体像を短時間で把握でき、変更の影響範囲を事前に特定してバグの早期発見につなげる

**オフィスワーカー向け**: 直接的な利用は難しいが、エンジニアがシステムの構造を素早く理解できることで、機能追加やバグ修正の対応速度が向上

**システム構築ノウハウ**: 生成されたナレッジグラフをGitリポジトリに保存しておくと、PRレビュー時に変更箇所の文脈理解が容易になる

---

### 6. shanraisshan/claude-code-best-practice — Claude Code ベストプラクティス集
- **言語**: Markdown
- **Stars**: 43.5K+
- **URL**: https://github.com/shanraisshan/claude-code-best-practice
- **要約**: Claude Codeの効果的な使い方をまとめたベストプラクティス集。CLAUDE.md の書き方、プロンプトエンジニアリング、ワークフロー最適化のノウハウを体系化。コミュニティ主導で急速に成長し、4万スター超を獲得。

#### ClassLabでの活用可能性

| スパン | 活用案 |
|--------|--------|
| 1年未満 | 社内のCLAUDE.mdを本リポジトリのベストプラクティスに基づいて改善。開発生産性を即座に向上させる |
| 1年以上 | Claude Codeの社内利用ガイドラインを策定し、チーム全体のAI活用レベルを底上げ |
| 3年以上 | AIコーディングツールの組織的活用ノウハウを蓄積し、エンジニア採用時の差別化要因にする |

---

*Generated by Claude Code weekly-news skill on 2026-04-16*
