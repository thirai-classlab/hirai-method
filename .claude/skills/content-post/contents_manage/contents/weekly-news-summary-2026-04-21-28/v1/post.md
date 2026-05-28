
# 週間ニュースまとめ（2026年4月21日〜4月28日）

## 目次

- [Hacker News](#hacker-news)
  - [1. 西側はモノづくりを忘れ、いまコードの書き方も忘れつつある](#1-西側はモノづくりを忘れいまコードの書き方も忘れつつある)
  - [2. Friendsterを3万ドルで買った――その活用計画](#2-friendsterを3万ドルで買ったその活用計画)
  - [3. AIは思考を置き換えるな、引き上げよ](#3-aiは思考を置き換えるな引き上げよ)
  - [4. AIエージェントが本番DBを削除した――その「告白」](#4-aiエージェントが本番dbを削除したその告白)
  - [5. MicrosoftとOpenAIが独占・収益分配契約を解消](#5-microsoftとopenaiが独占収益分配契約を解消)
  - [6. GitHub Copilotが使用量課金モデルへ移行](#6-github-copilotが使用量課金モデルへ移行)
  - [7. Mercorから4TB分の音声サンプルが流出（4万人のAI契約者）](#7-mercorから4tb分の音声サンプルが流出4万人のai契約者)
  - [8. Asahi Linux 7.0 進捗レポート](#8-asahi-linux-70-進捗レポート)
  - [9. SWE-bench Verifiedはもうフロンティアの指標ではない（OpenAI）](#9-swe-bench-verifiedはもうフロンティアの指標ではないopenai)
  - [10. 中国がMeta によるAIスタートアップManus買収をブロック](#10-中国がmeta-によるaiスタートアップmanus買収をブロック)
- [Zoom Phone](#zoom-phone)
  - [1. Zoom Phoneに通話のリアルタイム文字起こし＆翻訳が登場](#1-zoom-phoneに通話のリアルタイム文字起こし翻訳が登場)
  - [2. Zoom CX→Zoom Phone転送時に通話サマリと変数を自動受け渡し](#2-zoom-cxzoom-phone転送時に通話サマリと変数を自動受け渡し)
- [Salesforce](#salesforce)
  - [1. Summer '26 リリースノート公開（4月22日）](#1-summer-26-リリースノート公開4月22日)
  - [2. Agent Fabricの拡張：Agent Broker βとマルチベンダーAI統制](#2-agent-fabricの拡張agent-broker-βとマルチベンダーai統制)
- [Anthropic](#anthropic)
  - [1. NECが従業員3万人にClaudeを展開、日本最大級のAIエンジニアリング組織を構築](#1-necが従業員3万人にclaudeを展開日本最大級のaiエンジニアリング組織を構築)
  - [2. Claude CodeのProプラン除外騒動――24時間で撤回](#2-claude-codeのproプラン除外騒動24時間で撤回)
  - [3. シドニーオフィス開設、ANZ統括にTheo Hourmouzis就任](#3-シドニーオフィス開設anz統括にtheo-hourmouzis就任)
- [GitHub トレンド](#github-トレンド)
  - [1. forrestchang/andrej-karpathy-skills](#1-forrestchangandrej-karpathy-skills)
  - [2. hermes-agent](#2-hermes-agent)
  - [3. voicebox（オープンソースElevenLabs代替）](#3-voiceboxオープンソースelevenlabs代替)
  - [4. multica（マネージドエージェントプラットフォーム）](#4-multicaマネージドエージェントプラットフォーム)
  - [5. dirac-run/dirac（TerminalBenchトップのOSSエージェント）](#5-dirac-rundiractterminalbenchトップのossエージェント)

---

## Hacker News

### 1. 西側はモノづくりを忘れ、いまコードの書き方も忘れつつある

- **原題**: The West forgot how to make things, now it's forgetting how to code
- **スコア**: 1170pt / コメント: 833件
- **URL**: https://techtrenches.dev/p/the-west-forgot-how-to-make-things
- **要約**: 製造業の空洞化と同じ構造が、AI支援コーディングの普及によりソフトウェア開発でも進行している、という論考。デフォルトでAIに丸投げするとシニア層の暗黙知が継承されず、組織の「設計判断能力」が痩せ細っていくという警鐘。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部のClaude Code利用ガイドラインに「AIに任せていい範囲」と「人間がレビューすべき範囲」を明文化する。特にライフライン契約フローのトランザクション境界・支払い処理・個人情報取り扱い箇所はAI生成コードのまま採用しない運用ルールを敷く。
- 1年以上：ジュニアがAIに丸投げしないよう、設計レビュー（architect agent / 人間レビュー）を必須にした「AI併用TDD」を社内標準ワークフローとして整備。OJTの中で「AIが書いたコードのアンチパターン批評会」を月次で実施。
- 3年以上：採用基準を「AIを使いこなせるか」から「AIが間違ったときに気づけるか」へシフト。シニアエンジニアの育成投資を強化し、AIネイティブ世代に対しても設計力・運用力で差別化できる組織を作る。
:::

---

### 2. Friendsterを3万ドルで買った――その活用計画

- **原題**: I bought Friendster for $30k – Here's what I'm doing with it
- **スコア**: 1073pt / コメント: 588件
- **URL**: https://ca98am79.medium.com/i-bought-friendster-for-30k-heres-what-i-m-doing-with-it-d5e8ddb3991d
- **要約**: 元祖SNS「Friendster」のドメイン・商標を3万ドルで取得した著者が、ノスタルジー資産をどう再活用するかを語る記事。古いブランド資産の現代的な活用方法とドメイン取引の経済性が話題に。

:::classlab-usage
#### Classlabでの活用

- 1年未満：自社が保有する未使用ドメイン・旧サービス名を棚卸しし、SEO資産として活かせるものをライフライン申込LP・暮らしのメディアの記事LPに転用するか、売却する判断を行う。
- 1年以上：M&A/事業譲受の選択肢として「休眠ブランドの取得」を加える。例：地域密着の引越し系サービスや暮らし系メディアの休眠資産を取得し、ClassLab.のCRM基盤に乗せて再起動する。
- 3年以上：ノスタルジー・コミュニティ志向のSNS需要が再来した場合、RIRIFEの会員基盤を活かして「新生活コミュニティ」をブランド付きで立ち上げる選択肢を検討する。
:::

---

### 3. AIは思考を置き換えるな、引き上げよ

- **原題**: AI should elevate your thinking, not replace it
- **スコア**: 826pt / コメント: 575件
- **URL**: https://www.koshyjohn.com/blog/ai-should-elevate-your-thinking-not-replace-it/
- **要約**: AIに「答え」を求めるのではなく、自分の思考を磨く道具として使うべきだという提言。Cursor / Claude Code 全盛期に、考える力を維持するための具体的な使い方が議論されている。

:::classlab-usage
#### Classlabでの活用

- 1年未満：CX事業部のオペレーター教育で「ChatGPT回答をそのまま顧客に伝えない」「AIに対して反論する練習」を新人研修カリキュラムに組み込む。Slackの`#ai-tips`チャンネルで「AIに任せて失敗した事例」を共有する文化を作る。
- 1年以上：エンジニア・営業・企画職全員にAIプロンプティング研修を必修化し、「AIに考えさせる」のではなく「AIに自分の仮説を批判させる」運用を組織標準にする。
- 3年以上：ホリエモンAI学校の教育カリキュラムに「AIで思考を加速する」モジュールを追加し、ClassLab.が培った社内ノウハウを外販コンテンツに昇華する。
:::

---

### 4. AIエージェントが本番DBを削除した――その「告白」

- **原題**: An AI agent deleted our production database. The agent's confession is below
- **スコア**: 825pt / コメント: 985件
- **URL**: https://twitter.com/lifeof_jer/status/2048103471019434248
- **要約**: AIエージェントに本番環境への書き込み権限を渡した結果、誤って本番DBを削除した事例。エージェントが事後に「告白」する出力が公開され、エージェント運用のリスク管理が大きな議論に。

:::classlab-usage
#### Classlabでの活用

- 1年未満：Salesforce本番環境・microCMS・ライフライン契約DBへのAI/エージェント直接書き込みを禁止し、ステージング→人間レビュー→本番反映の三段階フローを徹底する。Claude Code利用時の`--dangerously-skip-permissions`を全社で禁則設定。
- 1年以上：エージェントが本番に触る業務（例：ServiceGuide__c自動更新、契約データクレンジング）にはdry-runモード必須・ロールバック手順必須・監査ログ必須の3点セットを技術ガバナンスに組み込む。
- 3年以上：エージェント運用の保険・SLA体系が業界で整備された際、ClassLab.は早期にエージェント運用責任分界点を契約書ベースで明確化し、不動産パートナーとのRPA/エージェント共同運用に展開する。
:::

#### ハンズオン（ジュニアエンジニア向け）

Claude CodeでDBを触るときの安全フロー（所要時間: 15分）:

```bash
# 1. プロジェクトの.claude/settings.jsonに本番DB保護を追加
cat > .claude/settings.json <<'EOF'
{
  "permissions": {
    "deny": [
      "Bash(psql*production*)",
      "Bash(*DROP TABLE*)",
      "Bash(*DELETE FROM*WHERE*)",
      "Bash(sf*--target-org*production*)"
    ]
  }
}
EOF
# → Claude Codeが本番DBに対するDROP/DELETEやSalesforce本番組織への破壊的操作を試みた瞬間に、ユーザーへ承認プロンプトを出して止まる

# 2. dry-runを強制するエイリアスを設定
alias sfp='echo "本番直接実行は禁止。--dry-runで確認してから@harashi.takumaに承認を取ってください"; false'
# → 誤って本番組織コマンドを叩いても即座に拒否されるため、思考の隙が事故にならない

# 3. 本番作業時はworktreeで隔離
git worktree add ../prod-fix release/prod
cd ../prod-fix
# → メインの作業ツリーから物理的に分離されるため、AIが「いま本番ブランチで作業中だ」と誤認しても他ブランチのファイルには影響を与えない
```

**活用例3選**:
1. ServiceGuide__cマスタ更新スクリプトを書く際、Salesforce本番組織コマンド（`sf data update record --target-org production`）を `permissions.deny` に登録し、AIに本番組織を直接触らせない
2. ライフライン申込テーブルのデータクレンジング時、Claude Codeに `--dry-run` フラグなしの実行を拒否させる事前フックを `.claude/hooks/PreToolUse` に設定
3. 暮らしのメディアのWordPress記事一括更新を依頼する際、`POST + X-HTTP-Method-Override: DELETE` の発火パターンを承認制にする

**エンジニアの業務改善**: システム事業部の本番作業ガイドラインに「破壊的操作はpermissions.deny必須」を追加。Git Flow運用と組み合わせ、`release/*` ブランチでのみ本番環境変数を読めるようにすれば、AIエージェントが誤ったブランチ・誤った環境を踏むリスクを構造的に潰せる。

**オフィスワーカー向け**: CX事業部・NW事業部がGenAIにSalesforceレポート抽出を依頼する場面で、必ず`Read`権限のあるDeveloper Sandbox/レポート専用ユーザーを使うように指示する運用を周知する。本番ユーザー権限のままAIに作業させない。

**システム構築ノウハウ**: 「破壊的操作にはhuman-in-the-loop」を技術原則として組み込む。具体的には、(1) deny-list、(2) dry-run必須、(3) 監査ログ強制、(4) 物理隔離（worktree/別アカウント）の4層防御を全プロジェクトの初期テンプレートに含める。

---

### 5. MicrosoftとOpenAIが独占・収益分配契約を解消

- **原題**: Microsoft and OpenAI end their exclusive and revenue-sharing deal
- **スコア**: 815pt / コメント: 695件
- **URL**: https://www.bloomberg.com/news/articles/2026-04-27/microsoft-to-stop-sharing-revenue-with-main-ai-partner-openai
- **要約**: MicrosoftとOpenAIが2019年以来の独占的パートナーシップ・収益分配契約を解消すると発表。OpenAIは他のクラウドにも自由にデプロイ可能になり、Microsoftも他のAIモデル（Anthropic等）への投資を拡大する見込み。

:::classlab-usage
#### Classlabでの活用

- 1年未満：Anthropic Claude／OpenAI／Google Gemini を併用する「マルチベンダーLLM運用」を前提にClaude Code・社内チャットの設計を見直す。Salesforce Einstein/Agentforce のバックエンドモデル選択肢が拡がる時期にあわせ、コスト・性能の比較表を四半期ごとに更新する。
- 1年以上：AI調達戦略を「OpenAIロックイン」から「LiteLLM/AI Gatewayでマルチベンダー切替可能」へ移行。AI-OCR・AIトレーナー・社内ツールでモデル単位で価格交渉できる体制を作る。
- 3年以上：日本市場でAnthropic（NEC連携）が伸びる前提で、ClassLab.の主要AI基盤を国内データレジデンシ要件に強いベンダーへ寄せる。金融・自治体向け事業に展開する際の前提として、AIサプライチェーンの透明性をパートナー契約に明記する。
:::

---

### 6. GitHub Copilotが使用量課金モデルへ移行

- **原題**: GitHub Copilot is moving to usage-based billing
- **スコア**: 597pt / コメント: 442件
- **URL**: https://github.blog/news-insights/company-news/github-copilot-is-moving-to-usage-based-billing/
- **要約**: GitHub Copilotが定額制から使用量ベースの課金モデルへ移行することが発表された。エージェント機能・モデル切替の高度化に伴い、月額固定では持続不可能になったとされる。Anthropic ClaudeのCode Pro削除騒動（4/21）と同時期で「AIの定額時代の終焉」が話題に。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部の各エンジニアが利用するCopilot/Claude Code/Cursorの月次利用量をダッシュボード化し、トークン課金体系への移行に備える。「AIに何を任せるかでコストが変わる」前提のコスト意識を全エンジニアに共有する。
- 1年以上：AI予算を「人数 × 定額」から「ユースケース × トークン量」へ会計区分を切り替える。プロジェクト別の原価管理にAI利用料を組み込み、ライフライン申込フォームの開発工数とAIコストの相関を可視化する。
- 3年以上：AI使用量に応じて社内チャージバックする運用を整え、AI効率の高い事業部・低い事業部を可視化。「AIで利益を出す部門」「AIに食われる部門」の構造をマネジメントレイヤーで把握する。
:::

---

### 7. Mercorから4TB分の音声サンプルが流出（4万人のAI契約者）

- **原題**: 4TB of voice samples just stolen from 40k AI contractors at Mercor
- **スコア**: 485pt / コメント: 175件
- **URL**: https://app.oravys.com/blog/mercor-breach-2026
- **要約**: AIラベリングプラットフォームMercorから、4万人の契約者の音声サンプル4TBが流出。声紋なりすまし詐欺・ボイスフィッシングのリスクが急増する中、AI学習データの取り扱い責任が改めて問われる。

:::classlab-usage
#### Classlabでの活用

- 1年未満：CX事業部のコールセンター録音データの保管ポリシーを再点検。録音→AI文字起こし→Salesforceケース紐付けのフローで、音声ファイルの暗号化・アクセスログ・保持期限を再設定する。
- 1年以上：ボイスフィッシング対策として「契約者本人確認は声紋に依存しない」運用を明記。引越し時のライフライン契約は新生活者の本人確認が肝なので、SMS/メール/書類のマルチファクタを義務化する。
- 3年以上：声紋なりすましが社会問題化する前提で、ClassLab.のAIトレーナー・AI-OCR等の事業がAI学習データの「セキュアラベリング基盤」として外販できる事業機会を探る。
:::

---

### 8. Asahi Linux 7.0 進捗レポート

- **原題**: Asahi Linux Progress Linux 7.0
- **スコア**: 642pt / コメント: 344件
- **URL**: https://asahilinux.org/2026/04/progress-report-7-0/
- **要約**: Apple SiliconでLinuxを動かすAsahi Linuxプロジェクトの最新進捗レポート。GPU加速・Thunderbolt・スリープ復帰など長年の宿題が大きく前進し、M3/M4世代でも実用レベルに到達。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部の検証環境として、Apple Silicon上の Asahi Linux で「macOSで動くがLinux環境必須のCI（Vercel preview の検証等）」をローカル再現できるか検証する。
- 1年以上：開発機の選択肢として「Mac本体 + Asahi Linuxの二刀流」を技術検証する。ライセンス・サポートコストを抑えつつLinuxネイティブな開発体験を提供できる可能性。
- 3年以上：Apple Silicon Linuxが業界標準化した場合、組み込み・エッジAI機器（AI-OCR用ローカル推論機等）でMac mini系をエッジサーバーとして使う選択肢が現実的になる。
:::

---

### 9. SWE-bench Verifiedはもうフロンティアの指標ではない（OpenAI）

- **原題**: SWE-bench Verified no longer measures frontier coding capabilities
- **スコア**: 339pt / コメント: 179件
- **URL**: https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/
- **要約**: OpenAIがSWE-bench Verified（実コーディングタスク評価）を「もはやフロンティアモデルの差を測れない」として今後の指標から外すと発表。LLMコーディング能力の伸びがベンチマークを超えた象徴的なニュース。

:::classlab-usage
#### Classlabでの活用

- 1年未満：社内のClaude/GPT選定基準を「SWE-bench」など対外ベンチマークではなく「ClassLab.の実タスク（ライフライン申込画面のフォーム生成、ServiceGuide__c更新スクリプト生成、暮らしのメディア記事チェック）」での実測ベンチマークに切り替える。
- 1年以上：自社ベンチマーク（ClassLab Bench）を整備し、四半期ごとにモデル切替判断の根拠データとして活用する。AIモデル選定が「営業トーク」から「データドリブン」になる体制を作る。
- 3年以上：自社ベンチマークの一部（個人情報を含まない汎用タスク）を業界共有OSSとして公開し、AI評価の中立的指標プロバイダーとしてのポジションを取りに行く。
:::

---

### 10. 中国がMeta によるAIスタートアップManus買収をブロック

- **原題**: China blocks Meta's acquisition of AI startup Manus
- **スコア**: 339pt / コメント: 228件
- **URL**: https://www.cnbc.com/2026/04/27/meta-manus-china-blocks-acquisition-ai-startup.html
- **要約**: 中国当局がMetaによる中国系AIスタートアップManus（自律エージェント領域）の買収を承認しないと判断。米中AI競争におけるM&A規制の最新事例で、グローバルAI調達戦略への影響が議論されている。

:::classlab-usage
#### Classlabでの活用

- 1年未満：使用しているAIサービス・ツールの母国・データレジデンシを棚卸し。中国系AIサービス（Manus・DeepSeek等）に依存する社内ツールがある場合、フォールバックとして日本／米国系の代替を準備する。
- 1年以上：地政学リスクを織り込んだAI調達ポリシーを策定。少なくともライフライン顧客データに触れるAI処理は日米のデータセンター内で完結することを契約書面に明記する。
- 3年以上：日本国内・国産AIプレイヤー（NEC×Anthropic, PFN等）との戦略的提携を視野に入れる。海外規制リスクから自社事業を守りつつ、国産AI市場の成長に乗る両構えを取る。
:::

---

## Zoom Phone

### 1. Zoom Phoneに通話のリアルタイム文字起こし＆翻訳が登場

- **URL**: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062333
- **要約**: 4月20日付で、Zoom PhoneにCall Live Transcription（通話リアルタイム文字起こし）とTranslation Services（通話翻訳）が有効化された。同時にメール配信リストへの通知転送、会議通話保留などの機能も追加され、コールセンター運用に直接効く強化が一括投入された。

:::classlab-usage
#### Classlabでの活用

- 1年未満：CX事業部（コールセンター）でCall Live Transcriptionを試験導入し、通話中のリアルタイムテキストをCRM（Salesforce ServiceCloud）に流し込んで「通話中スーパーバイザー支援」のPoCを実施。新人オペレーターの応対品質を即時にレビューする運用を作る。
- 1年以上：訪日外国人・在留外国人の引越しライフライン契約への対応として、Translation Servicesを電話受付の標準機能として組み込む。英語・中国語・ベトナム語の主要対応言語を整備し、不動産会社経由の外国人入居者をフォローする付加価値サービスに育てる。
- 3年以上：通話文字起こし＋AI要約＋Salesforceケース自動起票の完全自動化により、CXオペレーターの工数を大幅圧縮。コールセンターを「対応する組織」から「監督する組織」へ役割転換する。
:::

#### ハンズオン（ジュニアエンジニア向け）

Zoom PhoneのCall Live TranscriptionをSalesforceに連携する設計検討（所要時間: 20分）:

```bash
# 1. Zoom Phone APIで通話の文字起こし取得を有効化
# Zoom管理者設定 > Phone System Management > Phone Features > Call Recording & Transcription
#   - Live Transcription: ON
#   - Auto-save Transcription: Enabled
# → 通話終了後にtranscriptionが録音と同じストレージに保存される

# 2. Webhookで Salesforce にPOSTする最小サンプル
curl -X POST "https://api.zoom.us/v2/phone/users/{userId}/call_logs/subscriptions" \
  -H "Authorization: Bearer $ZOOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "phone.call_ended",
    "endpoint_url": "https://classlab.my.salesforce.com/services/apexrest/zoomCallHandler"
  }'
# → 通話終了イベントがSalesforce ApexRestエンドポイントに通知される

# 3. Salesforce側のApexRestで Case を起票（疑似コード）
@RestResource(urlMapping='/zoomCallHandler')
global class ZoomCallHandler {
    @HttpPost
    global static void handle() {
        // → 通話の文字起こし本文をCase.Description__cに、Zoom通話IDをCase.ZoomCallId__cに格納
        //   オペレーターのZoomユーザーIDからUserレコードを引き当ててOwnerIdに設定
    }
}
```

**活用例3選**:
1. 引越し時のライフライン契約相談電話で、契約者の希望（電気・ガス・水道・ネット）を通話文字起こしから抽出し、ServiceGuide__cの該当サービスに自動チェック
2. クレーム対応の通話で「金額」「契約番号」「日付」を正規表現＋AIで抽出し、Salesforceケースに自動転記
3. 不動産会社の担当者からの電話を文字起こし、Account__c（不動産会社）の対応履歴を自動更新

**エンジニアの業務改善**: システム事業部のSalesforce開発者は、Zoom Phone APIとApexRestの連携テンプレートを社内ライブラリ化することで、CX事業部の運用改善要望に2-3日で対応できるサイクルを作れる。

**オフィスワーカー向け**: CX事業部のオペレーターは、通話中のテキストが画面に表示されるため、聞き取りミスのリスクが減り、新人でも複雑な契約説明をリアルタイムでサポートツールと併用できる。SVは複数オペレーターの会話を文字で並列モニタリング可能。

**システム構築ノウハウ**: 「音声→テキスト→構造化データ→CRM」のパイプラインは、Zoom Phone API + Salesforce ApexRest + Salesforce Flow（Salesforce Sales/Service Cloud上の自動化機能）で完結できる。外部AI APIに音声を送る必要がないため、PIIリスクを抑えつつ社内に閉じた運用を構築できる。

---

### 2. Zoom CX→Zoom Phone転送時に通話サマリと変数を自動受け渡し

- **URL**: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062333
- **要約**: Zoom CX（バーチャルエージェント）からZoom Phoneのオペレーターに通話を転送する際、AIによる通話サマリと事前収集した変数（顧客名・契約番号など）が自動で受け渡される。「同じ説明を2回しなくていい」AIエージェント連携の本命機能。

:::classlab-usage
#### Classlabでの活用

- 1年未満：CX事業部の一次受付（FAQ・受電トリアージ）をZoom CXのバーチャルエージェントに置き換え、人間オペレーターには「サマリ＋変数を持った状態」でエスカレーションする運用をPoC。新生活者30万人の繁忙期（3月〜4月）の波対策として効果が大きい。
- 1年以上：Salesforce Agentforce（次セクション参照）と組み合わせ、「VA→Salesforce Agent→人間オペレーター」のハイブリッドフローを設計。問い合わせ種別ごとに最適なルーティングを自動化。
- 3年以上：問い合わせの90%以上がAIで完結する前提でCX事業部の役割を「対応」から「監督・改善」「複雑案件のみ対応」へ転換し、人件費構造を再設計する。
:::

---

## Salesforce

### 1. Summer '26 リリースノート公開（4月22日）

- **URL**: https://www.salesforceben.com/salesforce-summer-26-release-date-preview-information/
- **要約**: 4月22日にSummer '26のリリースノートが公開された。Sandbox反映が5月9日、本番反映が6月5日／12日／13日の週末。Agentforce強化・Flow強化・Web Console・新Field Accessタブが管理者向けの優先項目として挙がっている。

:::classlab-usage
#### Classlabでの活用

- 1年未満：5月9日のSandbox反映前に、Sandboxプレビュー組織でServiceGuide__c・引越し申込フローの主要シナリオをリグレッションテスト。Field Accessタブを使って権限の棚卸しを実施し、不要な権限プロファイルを整理する。
- 1年以上：Summer '26のFlow強化機能をもとに、ライフライン申込・契約締結フローのSalesforce Flow（Salesforce Sales/Service Cloud上の自動化機能）置き換えを段階的に進める。Apexトリガーが多い箇所をFlowに寄せて保守性を上げる。
- 3年以上：年3回のリリースサイクルを「自動回帰テスト＋AI差分レビュー」で消化できるよう、CI基盤にSandbox自動デプロイ＋Snapshot差分検出を組み込み、運用コストを下げる。
:::

#### ハンズオン（ジュニアエンジニア向け）

Summer '26 Sandboxプレビュー組織での回帰テスト準備（所要時間: 25分）:

```bash
# 1. Salesforce CLIでSandbox組織を認証
sf org login web --alias prod
# → ブラウザで本番組織にログインし、CLIに認証情報が保存される

# 2. PreviewのSandboxを作成（事前にUIで作成済みなら認証だけでOK）
sf org login web --alias preview-summer26 --instance-url https://test.salesforce.com
# → Preview Sandbox組織にCLIから接続できるようになる

# 3. メタデータをSandbox間で比較
sf project retrieve start --target-org prod --metadata Flow ApexClass
sf project retrieve start --target-org preview-summer26 --metadata Flow ApexClass
diff -r force-app-prod/ force-app-preview/
# → 本番とPreview Sandbox間のFlow・ApexClassの差分が見える。Summer '26で挙動が変わるFlowがあれば事前に検知できる

# 4. Apexテストを Preview で全件実行
sf apex run test --target-org preview-summer26 --code-coverage --result-format human
# → Preview組織でApexテストを全件走らせ、Summer '26で壊れるテストを早期発見できる
```

**活用例3選**:
1. ServiceGuide__cの一括更新Flowを Preview で実行し、Summer '26 のFlow Engine変更で発火条件が変わっていないか検証
2. AI-OCR読み取り後の自動ケース作成Flowを Preview で動かし、Field Accessタブの新仕様で不要な権限を発見
3. ライフライン契約の支払い処理Apexトリガーの単体テストカバレッジが Summer '26 でも維持できるか検証

**エンジニアの業務改善**: CI（GitHub Actions）に「毎週月曜にPreview Sandboxへ自動デプロイ＋Apexテスト全件実行」のジョブを追加すれば、Summer '26反映前に問題を週次で検知できる。

**オフィスワーカー向け**: NW事業部・EA事業部の管理者は、Field Accessタブを使って「現在の各プロファイルがどの項目を見られるか」を一覧で確認できるようになる。半年に一度の権限棚卸しが大幅に楽になる。

**システム構築ノウハウ**: Salesforceのリリース対応は、(1) リリースノート読み込み、(2) 自社の影響箇所マッピング、(3) Sandbox回帰テスト、(4) リスク高い箇所の機能フラグ化、の4ステップを定例化することで、年3回のリリースを安定消化できる。

---

### 2. Agent Fabricの拡張：Agent Broker βとマルチベンダーAI統制

- **URL**: https://www.salesforce.com/news/stories/agent-fabric-control-plane-announcement/
- **要約**: SalesforceがAgent Fabric（マルチベンダーAIエージェントの統制基盤）を拡張。Agent Brokerは4月にβ開始、6月にGA予定。Amazon Bedrock・Microsoft Foundry・GoDaddyのAgent Scanner対応も追加。マルチベンダーAIを「ガバナンスを効かせて使う」流れがエンタープライズで本格化。

:::classlab-usage
#### Classlabでの活用

- 1年未満：Agent Fabric β にウェイトリスト登録し、ServiceGuide__c更新エージェント・契約フォロー自動化エージェントの試験運用を計画。Slack Agent + Salesforce Agent + Anthropic Claudeのマルチエージェント連携シナリオをPoC化する。
- 1年以上：社内のAIエージェントを「Agent Fabric経由で統制」する標準を設定。エージェントの実行ログ・権限・モデル選択を一元管理し、CX/NW/EA事業部の独走による無秩序なAI乱立を防ぐ。
- 3年以上：不動産パートナー4,000社へのClassLab.独自エージェント提供（例：物件入居者の引越しライフライン手配を自動化するエージェント）を、Agent Fabric基盤に乗せて配信できる体制を整える。
:::

---

## Anthropic

### 1. NECが従業員3万人にClaudeを展開、日本最大級のAIエンジニアリング組織を構築

- **URL**: https://www.anthropic.com/news/anthropic-nec
- **要約**: 4月23日、NECとAnthropicが戦略提携を発表。NECは日本初のAnthropicグローバルパートナーとなり、3万人の従業員にClaudeを展開。金融・製造・自治体向けの業界特化AIソリューションを「Claude Cowork」を活用して共同開発する。日本市場でのAnthropic浸透を象徴する案件。

:::classlab-usage
#### Classlabでの活用

- 1年未満：NEC経由でAnthropicのエンタープライズサポートを受けられる可能性が出てきたため、商社系・大手SIer経由のClaudeエンタープライズ契約をRFP段階で比較検討。データレジデンシ・SLA・日本語サポートの観点で評価する。
- 1年以上：NEC×Anthropicが整備する「金融・自治体向けAIテンプレート」が出揃う前提で、ライフライン事業（特に公共系：自治体引越しワンストップサービス連携）でその成果物を再利用する戦略を準備する。
- 3年以上：日本のエンタープライズAI市場でAnthropicが標準ベンダー化する場合、ClassLab.のAI事業（AI-OCR、AIトレーナー、ホリエモンAI学校）はAnthropic公式パートナーエコシステムへの参画を視野に入れる。
:::

---

### 2. Claude CodeのProプラン除外騒動――24時間で撤回

- **URL**: https://www.wheresyoured.at/news-anthropic-removes-pro-cc/
- **要約**: 4月21日、Anthropicが$20/月のProプランからClaude Codeを除外する変更を実施したが、ユーザーの強い反発を受け24時間以内に撤回。Head of Growthが公式に「コミュニケーションエラー」を認めた。AI定額プランの収益構造の難しさが浮き彫りに。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部のClaude Code利用形態（Pro/Max/Team）を再点検。エンジニア個人課金からチーム契約へ移行できるか、コスト・ガバナンス両面で評価する。価格変更が短サイクルで起こり得る前提で四半期ごとに見直す運用を作る。
- 1年以上：AIサブスク／従量課金のミックス比率を「コア業務はTeamプラン」「アドホック業務は個別従量」と明確化し、社内予算編成のルールにする。
- 3年以上：AIベンダーの料金変更が事業計画に直結する前提で、契約交渉力を高めるため「使用量データの蓄積→ベンダーとの定期交渉」を社内プロセス化する。
:::

---

### 3. シドニーオフィス開設、ANZ統括にTheo Hourmouzis就任

- **URL**: https://www.anthropic.com/news
- **要約**: 4月27日、Anthropicがシドニーオフィスを正式オープン。Theo HourmouzisがオーストラリアおよびニュージーランドのGMに就任。アジア太平洋地域でのエンタープライズ展開（NEC日本、シドニーANZ）を矢継ぎ早に進めている。

:::classlab-usage
#### Classlabでの活用

- 1年未満：APACリージョンでのAnthropicエンタープライズ営業窓口が拡大する見込みなので、日本法人経由の問い合わせを早期に行いベンダーリレーションを作る。
- 1年以上：APAC市場進出（東南アジアでのライフライン関連事業展開等）を検討する際、Anthropicの地域パートナー網を活用できる土台ができつつある。
- 3年以上：日本→APACへのClassLab.事業展開時、AI基盤を地域内データレジデンシで揃えられる選択肢が広がる。
:::

---

## GitHub トレンド

### 1. forrestchang/andrej-karpathy-skills

- **言語**: Markdown
- **Stars**: +44K（今週）/ Total ~70K
- **URL**: https://github.com/forrestchang/andrej-karpathy-skills
- **要約**: Andrej KarpathyがX（旧Twitter）で発信した「LLMコーディングの落とし穴」（過剰実装、既存パターン無視、不要な依存追加など）を、1つの`CLAUDE.md`ファイルに蒸留したリポジトリ。今週のGitHub週間スター獲得No.1。「AIコーディングの行動規範を書く」ことが主流の開発アクションになったことを象徴。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部の各リポジトリの`CLAUDE.md`に、Karpathyスタイルの「禁止事項リスト」（不要な依存を追加しない／既存パターンを無視しない／過剰実装しない）をマージする。週次でAI生成PRの「アンチパターン違反」を計測する運用を始める。
- 1年以上：ClassLab.独自の`CLAUDE.md`テンプレートを作り、Salesforce／Next.js／Vercel の3スタックそれぞれで標準化する。新規プロジェクトの初期化時にbootstrapされる仕組みを整える。
- 3年以上：「AI行動規範」をエンジニア組織の文化的アセットとして外部公開し、採用ブランディング・技術発信に活用する（Qiita/Zenn/Devブログ等）。
:::

#### ハンズオン（ジュニアエンジニア向け）

自分のリポジトリにKarpathy CLAUDE.mdを取り入れる（所要時間: 5分）:

```bash
# 1. リポジトリのルートにダウンロード
curl -o CLAUDE.md https://raw.githubusercontent.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md
# → リポジトリルートにCLAUDE.mdが配置され、Claude Codeが起動時に自動で読み込んで「Karpathy流の作法」で動くようになる

# 2. 既存のCLAUDE.mdとマージ（手動 or sedで合流）
# 既存ルールと衝突する箇所だけ採用 / 不採用を決める
# → 自社のドメイン知識（ライフライン事業のメモ等）と、汎用的なAI作法ルールが共存する状態になる

# 3. Claude Code を再起動して動作確認
claude --resume
# → 起動時のCLAUDE.md再読み込みでKarpathyルールが効き始める。試しに「ボタンを追加して」と頼むと、不要な依存を追加せず既存スタイルに沿ったコードが返ってくる
```

**活用例3選**:
1. `weekly-news`スキルのリポジトリに導入し、AIが「不要なPython依存」を勝手に追加しないようにする
2. ライフライン申込フォーム（Next.js）リポジトリに導入し、AIが既存のCSSモジュールを無視して新しいCSS-in-JSを使い始めるのを防ぐ
3. Salesforce LWC開発リポジトリに導入し、AIが既存のApexメソッドを使わず新しいメソッドを乱立させるのを抑制

**エンジニアの業務改善**: 全社でCLAUDE.mdの「禁止事項」セクションをアップデートしていく文化を作ると、AI生成コードのレビュー時間が体感30〜50%短縮できる。

**オフィスワーカー向け**: 直接の利用シーンは限定的だが、「AIに何でも任せると質が落ちる」という発信が大企業エンジニアの間で広がっている事実は、AI導入を提案する社内稟議の説得材料として活用できる。

**システム構築ノウハウ**: AI Agentの行動制御は「プロンプトを毎回工夫する」から「リポジトリのCLAUDE.md/Skillsを整える」へとシフトしつつある。アーキテクチャとしてはコンテキスト駆動 → 構造化された制約駆動への進化と捉えられる。

---

### 2. hermes-agent

- **言語**: Python
- **Stars**: +30,630（今週）/ Total 100K突破
- **URL**: https://github.com/trending（Hermes Agentで検索）
- **要約**: 自己進化型エージェントHermes Agentが今週も+3万スターを獲得し、累計10万スターを突破。コンパニオン`hermes-agent-self-evolution`はDSPy + GEPAフレームワークを使ってスキル・プロンプト・コードを自動最適化し、OSS界隈で最も具体的な「エージェント自己改善ロードマップ」とされている。

:::classlab-usage
#### Classlabでの活用

- 1年未満：Hermes Agentの自己進化フレームワーク（DSPy + GEPA）を、社内のAIプロンプト改善PoCに使う。例：暮らしのメディア記事のSEOリライト用プロンプトを、ユーザー反応データを使って自動最適化するパイプラインを試作する。
- 1年以上：AI-OCRやAIトレーナーの精度改善ループを「人間チューニング」から「自己進化フレームワーク」に置き換える。改善コストを下げつつ精度を継続的に高める運用に移行する。
- 3年以上：自己進化エージェントの運用知見をClassLab.のAI事業の差別化ポイントに位置付け、AIトレーナーをホリエモンAI学校・社外向けSaaSとしてブランド化する。
:::

---

### 3. voicebox（オープンソースElevenLabs代替）

- **言語**: Python
- **Stars**: 急上昇中
- **URL**: https://github.com/trending（voiceboxで検索）
- **要約**: Qwen3-TTS・Whisper・MLXを基盤に、音声クローン・リアルタイム文字起こし・音声デザインを統合したOSS音声プラットフォーム。CUDAだけでなくApple Siliconでも動作。商用ElevenLabsの直接的な代替を狙う。

:::classlab-usage
#### Classlabでの活用

- 1年未満：CX事業部のIVR音声・自動応答の差し替え候補としてvoiceboxを評価。商用音声ライブラリのライセンス費を削減できないか検証する。
- 1年以上：暮らしのメディア記事の「音声記事化」（記事をTTSでpodcast化）を社内ツール化し、コンテンツの再利用度を上げる。MLX対応なのでM1/M2 Mac miniのオフライン処理で済むのが魅力。
- 3年以上：音声クローン技術の社会的リスクと表裏一体なので、活用と並行して「ボイスフィッシング検知」のディフェンス側技術にも投資し、CX事業部の電話応対基盤を強化する。
:::

---

### 4. multica（マネージドエージェントプラットフォーム）

- **言語**: TypeScript
- **Stars**: +7,009（今週）/ Total 18,471 / 2026-01-13作成
- **URL**: https://github.com/trending
- **要約**: 「アドホックなプロンプトでエージェントを動かす」のではなく、Issue Tracker（GitHub Issues / Linear等）にエージェントを統合し、タスクをアサイン・進捗トラッキング・スキル蓄積する開発体験を提供。コーディングエージェントを「チームメイト」として扱う設計思想。

:::classlab-usage
#### Classlabでの活用

- 1年未満：システム事業部のGitHub IssuesにmulticaをPoC導入し、「軽微な定型タスク（リファクタ、依存更新、テストカバレッジ向上）」をエージェントに自動アサインする運用を試す。
- 1年以上：エージェントへのタスク振り分けを Slack Workflow + GitHub Issues + Salesforce Tasks の三点で統合し、CX/NW/EA事業部の運用タスクの一部もエージェント実行に置き換える。
- 3年以上：「エージェントに仕事を任せる前提のプロセス設計」を組織標準化し、人間×エージェントのハイブリッドチーム編成を恒常化する。
:::

---

### 5. dirac-run/dirac（TerminalBenchトップのOSSエージェント）

- **言語**: Python（推定）
- **Stars**: HN 319pt / 急上昇中
- **URL**: https://github.com/dirac-run/dirac
- **要約**: Show HNで発表されたOSSコーディングエージェント。Gemini-3-flash-previewでTerminalBenchトップを獲得。軽量モデル＋エージェントハーネス設計でフロンティアモデルなしでも実用レベルに到達できることを示した。

:::classlab-usage
#### Classlabでの活用

- 1年未満：軽量モデル（Gemini Flash / Claude Haiku）でも工夫次第で実務に耐えるという証左として、コスト圧縮の選択肢に加える。社内RPA代替・スクリプト自動生成タスクで実証する。
- 1年以上：「ハイエンドモデル一択」から「タスクごとにモデルを選ぶ」アーキテクチャへ移行。AI Gateway／LiteLLMでルーティングし、コスト・性能・レイテンシのトレードオフを最適化する。
- 3年以上：自社で軽量モデル＋エージェントハーネスのノウハウを蓄積し、ライフライン事業の業務オペレーション自動化を「外部AI APIの呼び出し量」を最小化した設計で構築する。データプライバシ・コスト・レイテンシの全てで優位に立つ。
:::

---

## 編集後記

![CLAUDE.mdゲートと人間レビューを通って本番にコードが届く――AIに丸投げの終焉を表す16-bitピクセル絵](./output/weekly-2026-04-28/body-explain.png)

今週は **「AIコーディングの行動規範」** が複数のニュースに通底するテーマでした。Karpathy CLAUDE.mdの爆発的トレンド入り、AIエージェントによる本番DB削除事件、SWE-bench卒業宣言、Copilot使用量課金移行、Claude Code Pro除外騒動――いずれも「AIに丸投げする時代」から「AIを統制しながら使い倒す時代」への移行を示しています。

ClassLab.としては、システム事業部の`CLAUDE.md`整備、本番系へのpermissions.deny徹底、Salesforce Sandbox回帰テストCIの自動化、Zoom Phone文字起こし→Salesforceケース連携PoC、NEC×Anthropic経由のClaudeエンタープライズ評価、の5つを今期の重点アクションとして整理する価値があります。
