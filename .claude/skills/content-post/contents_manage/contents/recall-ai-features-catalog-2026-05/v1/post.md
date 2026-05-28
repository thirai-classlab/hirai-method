
> AI 企業が自社プロダクトに会議録画・トランスクリプトを **組込む** ための Meeting Bot Infrastructure。SaaS の完成品ではなく、開発者向けの "AWS for conversations"。

---

## 0. TL;DR

- Recall.ai は **Zoom / Google Meet / Microsoft Teams / Webex / Slack Huddles / GoTo** に対応した Meeting Bot API + Desktop / Mobile Recording SDK + Transcription API の統合プラットフォーム。
- 1 つのプラットフォームに統合すれば、6+ の会議ツール全てに対応した bot 機能を提供できる。
- **1000+ AI 企業が採用**、$38M Series B (Bessemer 主導)、創業者 David Gu (YC W20)。
- **旧知識との差分（LLM 訓練データを上書き）**
  - 2026 初頭に **$0.70 → $0.50/h** へ値下げ（Meeting Bot API + Desktop SDK 同一料金）。
  - **Desktop Recording SDK / Mobile Recording SDK** がラインナップ追加（Bot を会議に入れずに録画）。
  - **Calendar API が無料**（Google Calendar / Outlook 連携、競合は別料金が多い）。
  - **HIPAA 取得**（医療系統合可能）、SOC2 / ISO 27001:2022 / GDPR / CCPA 対応。
  - **Breakout Rooms 対応は Recall.ai のみ**。
  - 内蔵 transcription エンジン $0.15/h（旧: 必ず BYO だった）。Deepgram / AWS Transcribe / ElevenLabs 等の BYO も継続サポート。
  - **Real-time webhook サブ秒レイテンシ**、`prioritize_low_latency` / `prioritize_accuracy` の 2 モード。
  - "Recall 2.0" という名称の **別サービス**（学習アプリ）と混同注意 — 本ドキュメントの対象は recall.ai (API インフラ)。
- **最大差別化点**: Fireflies / Otter / MeetGeek は **完成 SaaS（UI ありの自己完結ツール）** に対し、Recall.ai は **API インフラ（自社プロダクトに組込む層）**。Symbl.ai と比較しても **6+ プラットフォーム横断対応 + Breakout Rooms** が独自。

---

## 1. Recall.ai とは何か — 理念とミッション

### 1.1 ミッション

> **"The common infrastructure for every company that needs to access and apply AI to conversations."**
> 会議データに AI を適用したい全ての企業のための共通インフラ。AWS が "クラウドの土台" になったように、Recall.ai は "会話 AI の土台" になる。

### 1.2 哲学

| 表現 | 意味 |
|---|---|
| **"AWS for conversations"** | 各社が会議統合を自前で実装するのは無駄。一度作って 1000 社に提供する。 |
| **"API, not UI"** | エンドユーザー向けのアプリは作らない。開発者向けの API だけを磨く。 |
| **"Drop-in infrastructure"** | 既存プロダクトに数日で組み込める粒度に分解された API。 |
| **"Build vs Buy" の Buy 側** | "会議録画 SaaS の機能の 80% を 1/10 のコストで自前プロダクトに" を実現。 |

### 1.3 なぜ存在するか

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/2acd356a-m01.png" alt="m01" width="1536" height="864">

David Gu と Amanda Zhu は University of Waterloo を 19 歳で中退、最初はリアルタイム翻訳ツールを作っていたが、**会議データへのアクセス自体が 1 番難しい** ことに気づき、ピボットして 2022 年に Recall.ai を立ち上げた。

### 1.4 エンジニアにとっての意味

| 立場 | Recall.ai が解くこと |
|---|---|
| AI / バックエンドエンジニア | Zoom/Meet/Teams 統合を 1 API に抽象化。会議統合の専門知識なしで AI プロダクトを作れる。 |
| プロダクト | "会議の AI 機能" を 1〜2 週で MVP 化、Fireflies と同等の機能を自社ブランドで提供できる。 |
| 営業オペレーション | 商談録画 → CRM 自動入力のパイプラインを自社制御できる（SaaS では困難）。 |
| カスタマーサクセス | 通話品質管理・コンプラ録音の独自フロー設計が可能。 |
| セキュリティ | HIPAA / SOC2 / GDPR / CCPA 取得済、医療・金融も統合可能。 |

---

## 2. 全体マップ（1 枚絵）

### 2.1 サービス全体俯瞰

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/a9da0602-m02.png" alt="m02" width="1536" height="864">

### 2.2 製品カテゴリ Mindmap

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/0a6a2cda-m03.png" alt="m03" width="1536" height="864">

---

## 3. プラン体系の前提知識

### 3.1 プラン概要表

| 軸 | **Pay As You Go** | **Launch** | **Enterprise** |
|---|---|---|---|
| 月額固定費 | $0 | カスタム | カスタム |
| 録画料金 | $0.50/h | ボリューム割引 | ボリューム割引 |
| 内蔵 Transcription | $0.15/h | $0.15/h or BYO | $0.15/h or BYO |
| Calendar API | 無料 | 無料 | 無料 |
| 課金単位 | 秒単位プロレート | 秒単位 | 秒単位 |
| サポート | チケット | Priority | 専用 + SLA |
| Compliance | SOC2/ISO/GDPR/CCPA | + HIPAA | + HIPAA + BAA |
| Volume Discount | 不可 | 利用可 | 利用可 |
| 適用シーン | PoC / 小〜中規模 | 月数千時間以上 | エンタープライズ |

### 3.2 課金モデル

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/ebe726d0-m04.png" alt="m04" width="1536" height="864">

- **秒単位プロレート**: 5 分会議 → $0.50 × 5/60 = $0.042 のように厳密計算。
- **アイドル時間に課金しない**: bot が会議室に入った瞬間〜退出までだけ。月額プラットフォーム手数料なし。

### 3.3 プラン表記凡例

| 記号 | 意味 |
|---|---|
| 利用可 | プラン標準で利用可能 |
| 制限あり | 制限付き / Beta / Volume 要件 |
| 不可 | 利用不可 |
| 従量課金 | 標準で含まれるが、超過は従量課金 |

---

## 4. 機能カタログ

### 4.1 Meeting Bot API（Zoom / Meet / Teams / Webex / Slack Huddles / GoTo）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/d096dcc6-m05.png" alt="m05" width="1536" height="864">

6+ の主要会議プラットフォームに統一 API で bot を投入。`meeting_url` を渡すだけ。

**👨‍💻 エンジニアへの関係**

- Zoom SDK / Google Meet API / Teams Graph API を **個別に学ぶ必要なし**。1 つのスキーマで全部済む。
- bot の表示名 / アバター画像 / 参加待機メッセージもカスタマイズ可能（ホワイトラベル運用）。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| $0.50/h | Volume Discount | Volume Discount |

**🏢 ClassLab. での活用**

- 短期: 営業/CS の Zoom 商談を自動録画し、AI 要約を Slack / SF に投稿する PoC。
- 中長期: 全社の社外会議を録画 → AI ナレッジベースに自動蓄積、検索可能化。

**🔥 差別化点**

| | Recall.ai | Fireflies / Otter | Symbl.ai | 自前実装 (Zoom SDK 直) |
|---|:-:|:-:|:-:|:-:|
| 6+ プラットフォーム横断 | 利用可 | (主要のみ) | 制限あり | (個別実装) |
| ホワイトラベル可能 | 利用可 | 不可 | 利用可 | 利用可 |
| **Breakout Rooms 対応** | 唯一 | 不可 | 不可 | 制限あり |
| 完成 UI 提供 | (API のみ) | 利用可 | 不可 | 不可 |
| 開発期間 | 1〜2 週 | 即日 (UI 利用) | 2〜4 週 | 3 ヶ月+ |

**🔍 深掘り**

```bash
curl -X POST https://us-west-2.recall.ai/api/v1/bot/ \
  -H "Authorization: Token YOUR_KEY" \
  -d '{
    "meeting_url": "https://zoom.us/j/...",
    "bot_name": "ClassLab. Notetaker",
    "transcription_options": { "provider": "recallai" },
    "real_time_transcription": {
      "destination_url": "https://your-server.com/hook",
      "transcription_mode": "prioritize_low_latency"
    }
  }'
```

**⚠️ 注意点**

- ホスト側で「外部参加者 / bot 入室許可」設定が必要な会議システムあり（Zoom / Teams）。事前に IT / 取引先と合意。

---

### 4.2 Desktop Recording SDK

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/2e12a932-m06.png" alt="m06" width="1536" height="864">

会議システムに **bot を入れずに**、ユーザの PC 上で画面 + 音声を直接キャプチャ。Mac / Windows 両対応。

**👨‍💻 エンジニアへの関係**

- bot を嫌がる組織（社外参加者対応や法務懸念）でも導入可能。
- 任意の会議システム（Zoom 等以外の社内ツール、SIer の独自システム等）も対象に。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| $0.50/h | 従量課金 | 従量課金 |

**🏢 ClassLab. での活用**

- 短期: 営業端末に組込み、対面商談 + Zoom 混在ケースを 1 つの仕組みで録画。
- 中長期: 全社 PC に標準展開、内製ナレッジ蓄積基盤。

**🔥 差別化点**

- Fireflies / Otter は基本的に bot 方式のみ。**Bot レス録画は Recall.ai の独自ライン**。
- Krisp / Read.ai もデスクトップ録画あるが、API インフラとしての提供は限定的。

**🔍 深掘り**

- Native binary (Electron / Tauri / Swift / WPF 等から呼出可能)。
- 各話者音声を **マイク / システム音声で分離** して記録、後で別話者と認識される。

**⚠️ 注意点**

- macOS の Screen Recording / Microphone 権限 UX 設計が肝。プロビジョニング時の同意フロー設計必須。

---

### 4.3 Mobile Recording SDK

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/2c09970d-m07.png" alt="m07" width="1536" height="864">

iOS / Android アプリに組み込んで、モバイル端末からの会議参加・電話通話を録画。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 従量課金 | 従量課金 | 従量課金 |

**🏢 ClassLab. での活用**

- 短期: 訪問営業の現場で端末から商談録音 → AI 要約。
- 中長期: フィールド業務（ライフライン現地調査等）の音声記録基盤。

**🔥 差別化点**

- **モバイル対応の Meeting Bot 系 SaaS は希少**。Otter にもモバイル収録あるが、SDK として組込配布は Recall.ai が先行。

---

### 4.4 Transcription（内蔵 + BYO）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/f8224687-m08.png" alt="m08" width="1536" height="864">

**内蔵エンジン $0.15/h** で十分品質。精度要件が厳しい場合は BYO API キーで Deepgram / AWS Transcribe / ElevenLabs / AssemblyAI 等に差替可能。

**👨‍💻 エンジニアへの関係**

- 1 つの transcription SaaS にロックインせずに済む。コスト / 言語 / 精度で柔軟に選択。
- Speaker Diarization は Recall.ai 側で処理されるので、provider に依存しない。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| $0.15/h (内蔵) | 従量課金 | 従量課金 |

**🏢 ClassLab. での活用**

- 短期: 日本語商談は Deepgram Nova-2 (BYO)、英語は内蔵を選ぶ等の運用。
- 中長期: 多言語顧客向けに provider 自動切替パイプライン。

**🔥 差別化点**

- AssemblyAI / Deepgram は単体で transcription のみ。Recall.ai は **会議統合 + transcription の組合せ最適化** が独自。

**🔍 深掘り**

- BYO 時は環境変数で各 provider の API key を Recall.ai に保管、リクエストパラメータで切替。

---

### 4.5 Real-time Streaming（WebSocket / Webhook）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/a8f8d21e-m09.png" alt="m09" width="1536" height="864">

`prioritize_low_latency`（1〜3 秒）と `prioritize_accuracy`（3〜10 分）の 2 モード。WebSocket / Webhook の好きな方で受信。

**👨‍💻 エンジニアへの関係**

- ライブキャプション / リアルタイム AI 応答型のプロダクトを設計可能（例: 商談中に AI が次の質問を提案）。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 |

**🏢 ClassLab. での活用**

- 短期: 商談中に LLM が「未確認情報」をハイライト → 営業に通知。
- 中長期: 顧客対応中のコンプライアンス即時チェック（NG ワード検知）。

**🔥 差別化点**

- Symbl.ai のリアルタイムも有名だが、**Recall.ai は会議 bot + リアルタイムが一体**で、bot の参加待機〜退出までのライフサイクル全体を 1 つの API で扱える。

---

### 4.6 Calendar API（無料）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/47692474-m10.png" alt="m10" width="1536" height="864">

Google Calendar / Outlook と OAuth 連携。指定条件の会議へ **自動的に bot を投入**。Calendar 情報を録画メタデータに付与。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| **無料** | **無料** | **無料** |

**🏢 ClassLab. での活用**

- 短期: 営業の Google Calendar を連携し、外部参加者あり会議だけを自動録画。
- 中長期: 全社 Calendar 連携 → ナレッジベース化を ZeroTouch で実現。

**🔥 差別化点**

- **多くの競合は別料金**（Fireflies の Calendar 連携は有料プラン限定）。Recall.ai は全プラン無料。

---

### 4.7 Speaker Diarization & Breakout Rooms 分離

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/a4712a6a-m11.png" alt="m11" width="1536" height="864">

各話者の音声を **別トラックで取得**。同時発話があっても誰が何を言ったか正確に判別。**Breakout Rooms 分離は Recall.ai 唯一**。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 |

**🏢 ClassLab. での活用**

- 短期: 多拠点同時参加会議の議事録を、参加者ごとに分けて検索可能化。
- 中長期: 教育系ワークショップで Breakout 内の会話を分析、グループごとに AI 講評。

**🔥 差別化点**

- **Breakout Rooms 録画は他社 0**。研修・教育・ワークショップ向けの決定打。

---

### 4.8 Media Output（Bot からの音声・動画出力）

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/3ef641f6-m12.png" alt="m12" width="1536" height="864">

Bot を「リスナー」だけでなく「発話者」として使える。AI 音声を会議に流し込む等。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 |

**🏢 ClassLab. での活用**

- 短期: 「不在者の代理 AI が会議に出席して質問」のような実験。
- 中長期: 顧客対応の自動応答エージェント（音声 AI が顧客と会議で対話）。

**🔥 差別化点**

- **音声出力ができる meeting bot SaaS は希少**。AI Agent と組合せた次世代 UX 開発に必須。

---

### 4.9 Recording Output（mp4 / mp3 / Per-speaker）

**🎯 概要**

| 形式 | 用途 |
|---|---|
| `mp4` (gallery view) | ZIP で全員映像 |
| `mp4` (speaker view) | 発話者切替の標準動画 |
| `mp3` (mixed) | 音声単独、軽量 |
| **Per-speaker tracks** | 個別話者の音声/映像 = 詳細分析向け |

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 |

**🏢 ClassLab. での活用**

- 短期: 商談録画を mp4 で保管、AI 分析は per-speaker で実施。
- 中長期: 教育系では各受講者の発話量・割合を per-speaker 分析。

---

### 4.10 Compliance

| 認証 / 規制 | Pay As You Go | Launch | Enterprise |
|---|:-:|:-:|:-:|
| SOC 2 | 利用可 | 利用可 | 利用可 |
| ISO 27001:2022 | 利用可 | 利用可 | 利用可 |
| GDPR | 利用可 | 利用可 | 利用可 |
| CCPA | 利用可 | 利用可 | 利用可 |
| **HIPAA** | 不可 | 制限あり | + BAA |
| 専用リージョン | 不可 | 不可 | 利用可 |
| 専用 DPA / SLA | 不可 | 制限あり | 利用可 |

**🏢 ClassLab. での活用**

- 短期: 通常業務利用は SOC2 / ISO で十分。
- 中長期: 医療系統合（ライフライン顧客の高齢者対応含む）は HIPAA + BAA 契約検討。

---

### 4.11 Webhooks / Async Job 管理

**🎯 概要**

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/4f6feaf8-m13.png" alt="m13" width="1536" height="864">

Bot のライフサイクル全てを webhook で通知。`bot.status_change` / `transcript.data` / `recording.done` 等を購読。

**💳 利用可能プラン**

| Pay As You Go | Launch | Enterprise |
|:-:|:-:|:-:|
| 利用可 | 利用可 | 利用可 |

**🏢 ClassLab. での活用**

- 短期: webhook で SF / Slack 自動通知。
- 中長期: 状態管理を独自 DB に同期し、社内ダッシュボード化。

---

## 5. プラン早見表（全機能 × プラン）

| カテゴリ | 機能 | Pay As You Go | Launch | Enterprise |
|---|---|:-:|:-:|:-:|
| Capture | Meeting Bot API | $0.50/h | Volume | Volume |
| Capture | Desktop Recording SDK | $0.50/h | 従量課金 | 従量課金 |
| Capture | Mobile Recording SDK | 従量課金 | 従量課金 | 従量課金 |
| Capture | Breakout Rooms 録画 | 利用可 | 利用可 | 利用可 |
| Transcription | 内蔵エンジン | $0.15/h | 従量課金 | 従量課金 |
| Transcription | BYO (Deepgram / AWS / ElevenLabs / AssemblyAI) | 利用可 | 利用可 | 利用可 |
| Real-time | Webhook / WebSocket | 利用可 | 利用可 | 利用可 |
| Real-time | `prioritize_low_latency` / `prioritize_accuracy` | 利用可 | 利用可 | 利用可 |
| Calendar | Google Calendar / Outlook | 無料 | 無料 | 無料 |
| Data | Per-speaker audio tracks | 利用可 | 利用可 | 利用可 |
| Data | Speaker Diarization | 利用可 | 利用可 | 利用可 |
| Data | Recording (mp4 / mp3 / per-speaker) | 利用可 | 利用可 | 利用可 |
| Output | Bot からの音声/動画出力 | 利用可 | 利用可 | 利用可 |
| Compliance | SOC2 / ISO 27001 / GDPR / CCPA | 利用可 | 利用可 | 利用可 |
| Compliance | HIPAA + BAA | 不可 | 制限あり | 利用可 |
| Platform | Volume Discount | 不可 | 利用可 | 利用可 |
| Platform | Priority Support | 不可 | 利用可 | 利用可 |
| Platform | 専用 SLA / DPA | 不可 | 制限あり | 利用可 |

---

## 6. 料金体系の詳細

### 6.1 プラン別含み枠 & 超過料金

**Pay As You Go**: 月額固定費 $0

| 項目 | 単価 |
|---|---|
| Meeting Bot API 録画 | $0.50 / h |
| Desktop Recording SDK | $0.50 / h |
| Mobile Recording SDK | $0.50 / h |
| 内蔵 Transcription | $0.15 / h |
| Calendar API | $0 (無料) |
| BYO Transcription | $0 (各 provider に直接支払) |

- **秒単位プロレート**。月額ミニマム / 起動料なし。
- PoC や小規模利用に最適。

**Launch**: カスタム月額 + ボリューム割引

- 月数千時間以上の利用で単価が下がる契約。
- Priority Support / HIPAA オプション。

**Enterprise**: カスタム

- 専用リージョン / SLA / BAA / DPA。
- カスタム機能要望対応。

### 6.2 競合との料金構造の違い

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/a951d7b6-m14.png" alt="m14" width="1536" height="864">

### 6.3 コスト最適化の勘所

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/65b0f89f-m15.png" alt="m15" width="1536" height="864">

---

## 7. ClassLab. での活用ロードマップ（汎用例）

### 7.1 短期（〜3 ヶ月）

| テーマ | 機能 | 想定効果 |
|---|---|---|
| 営業商談録画 & AI 要約 PoC | Meeting Bot + Calendar | Zoom 商談から自動的に SF への要約投入 |
| 社内会議の議事録自動化 | Meeting Bot + Real-time webhook | 全社会議の議事録作成工数を削減 |
| 内蔵 transcription の品質検証 | Transcription | 日本語精度を Deepgram / AssemblyAI / 内蔵で比較 |
| Calendar 連携 PoC | Calendar API (無料) | 営業の Google Calendar 自動 bot 投入 |
| Slack 連携 | Webhooks | 商談終了 → Slack 要約自動投稿 |

### 7.2 中長期（3〜12 ヶ月）

| テーマ | 機能 | 想定効果 |
|---|---|---|
| 顧客接点の知識化 | Meeting Bot + Transcript + Vector DB | 全商談・サポート対応を検索可能化、CS 提案高度化 |
| コールセンター品質管理 | Desktop SDK + Real-time | NG ワード検知・コンプラ即時アラート |
| 教育プロダクト | Meeting Bot + Breakout Rooms + Speaker Diarization | グループワーク内の参加度・発話量を可視化 |
| 訪問営業録音 | Mobile SDK | 現地調査内容を端末から録音 → AI 要約 |
| 高齢者顧客対応 | Meeting Bot + HIPAA Enterprise | ライフライン契約で高齢者向け医療相談を統合 |
| AI エージェント発話 | Media Output | 不在者代理 AI が会議に応答 |

### 7.3 既存資産棚卸し（汎用枠）

| 既存 | 移行候補 |
|---|---|
| Zoom Phone 通話の手動議事録化 | Recall.ai 経由で自動化 |
| 商談録画の手動 SF 入力 | Meeting Bot + Webhook で自動投入 |
| 個別の transcription SaaS 契約 | Recall.ai 内蔵 or BYO 統合 |
| 各営業 PC のローカル録音 | Desktop SDK で標準化 |
| Calendar 別ツール統合 | Recall.ai Calendar API（無料） |

---

## 8. 採用判断フロー

### 8.1 新規プロジェクト選択フロー

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/aa43388e-m16.png" alt="m16" width="1536" height="864">

### 8.2 採用適性 Quadrant

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/recall-ai-features-catalog-2026-05/97badcd2-m17.png" alt="m17" width="1536" height="864">

> 右上に近いほど Recall.ai が最適。左下は完成 SaaS（Fireflies / Otter）が早い。

---

## 9. 公式リファレンス & Sources

### 公式ドキュメント

- 全体: https://docs.recall.ai/
- Getting Started: https://docs.recall.ai/docs/getting-started
- Meeting Bot API: https://www.recall.ai/product/meeting-bot-api
- Desktop Recording SDK: https://www.recall.ai/product/desktop-recording-sdk
- Transcription API: https://www.recall.ai/product/transcription-api
- Real-time Transcription: https://docs.recall.ai/docs/real-time-transcription
- Transcription Overview: https://docs.recall.ai/docs/transcription
- Calculating Usage: https://docs.recall.ai/docs/calculating-usage
- Desktop SDK Changelog: https://docs.recall.ai/docs/dsdk-changelog
- 料金: https://www.recall.ai/pricing
- ブログ: https://www.recall.ai/blog
- GitHub: https://github.com/recallai

### Web Sources

- [Recall.ai - The API for Meeting Recording](https://www.recall.ai/)
- [Meeting Bot API](https://www.recall.ai/product/meeting-bot-api)
- [New Recall.ai Pricing for 2026: $0.50 per Hour](https://www.recall.ai/blog/new-recall-ai-pricing-for-2026)
- [Recall.ai Series B (The API for Meeting Recording)](https://www.recall.ai/blog/recall-ai-series-b-the-api-for-meeting-recording)
- [Recall.ai Transcription](https://docs.recall.ai/docs/recallai-transcription)
- [Real-Time Transcription](https://docs.recall.ai/docs/real-time-transcription)
- [Tracking and Calculating Usage](https://docs.recall.ai/docs/calculating-usage)
- [Inside David Gu's $38M Raise (Founders in Arms)](https://foundersinarms.substack.com/p/inside-david-gus-38m-raise-the-pivot)
- [API for meeting bots — David Gu (Krisp Voice AI Newsletter)](https://voice-ai-newsletter.krisp.ai/p/api-for-meeting-bots-david-gu-co)
- [YC-backed Recall.ai $10M Series A (TechCrunch)](https://techcrunch.com/2024/05/16/yc-backed-recall-ai-gets-10m-series-a-to-help-companies-utilize-virtual-meeting-data/)
- [Recall AI Alternative: Best Open Source Meeting Bot 2026](https://screenapp.io/blog/recall-ai-alternative-open-source-meeting-bot)
- [Recall.ai vs MeetingBaas](https://www.recall.ai/recall-ai-vs-meetingbaas)
- [Recall.ai meeting-bot reference (GitHub)](https://github.com/recallai/meeting-bot)
- [Zoom real-time transcription API blog](https://www.recall.ai/blog/zoom-real-time-transcription-api)
