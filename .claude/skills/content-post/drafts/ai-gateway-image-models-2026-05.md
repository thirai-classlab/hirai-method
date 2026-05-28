---
title: "Vercel AI Gateway 画像生成モデル横断ガイド（2026年5月版）"
type: knowledge
author: "平井拓真"
---

Vercel AI Gateway 経由でアクセスできる画像生成モデルは、2026年5月時点で BFL FLUX 系、OpenAI gpt-image 系、Google Nano Banana 系、ByteDance Seedream 系、Recraft、xAI Grok など多岐にわたる。本ガイドではエンドポイント構造、モデル特性、用途別の選定基準、実装アーキテクチャを整理する。

## 1. エンドポイント二系統の整理

AI Gateway は画像生成に **2 つのエンドポイント** を持つ。スキル `ai-image-gen-pro` の実装方針はこの分岐を理解することから始まる。

![AI Gateway 画像生成のエンドポイント二系統と主要モデルマップ](./images/ai-gateway-image-models-2026/01-endpoints.png)

| エンドポイント | レスポンス形式 | 主な用途 |
|---|---|---|
| `/v1/images/generations` (image-only) | `data[].b64_json` または `data[].url` | 純粋な text-to-image、image-to-image |
| `/v1/chat/completions` (multimodal) | `choices[].message.images[]` または tool result | 対話的編集、reasoning 付き生成、文章+画像 |

---

## 2. モデル一覧（2026年5月時点）

### 2.1 image-only モデル（テキスト→画像専用）

| Provider | Model ID | 価格 | 入力画像 | アスペクト/サイズ | 特徴・主用途 |
|---|---|---|---|---|---|
| BFL | `bfl/flux-2-pro` | ~$0.05/img | **multi-ref 最大 9 MP** | 多様、最大 4 MP | **価格性能比トップ**、汎用第一候補。10 秒以下生成、品質バランス最強 |
| BFL | `bfl/flux-2-max` | TBD | 編集対応 | 多様、4 MP | プロ向け production-ready 最高品質、印刷物にも耐える |
| BFL | `bfl/flux-2-flex` | TBD | **multi-ref 最大 10 枚 / 14 MP** | カスタマイズ可 | **infographics / typography 特化**、UI モック・図解・複雑構成タイポ |
| BFL | `bfl/flux-2-klein-4b` | TBD | 編集統合 | 標準 | 4B 軽量、高速ラフ案出し |
| BFL | `bfl/flux-2-klein-9b` | TBD | 編集統合 | 標準 | **<1 秒生成**、ムードボード・プロンプト探索専用 |
| BFL | `bfl/flux-kontext-max` | $0.08/img | 単一参照 | 標準 | **キャラ一貫性編集の絶対王者**、6 連続編集後も cosine 0.92+ |
| BFL | `bfl/flux-kontext-pro` | $0.04/img | 単一参照 | 標準 | Kontext Max と同系、価格半額。画質はほぼ同等 |
| BFL | `bfl/flux-pro-1.0-fill` | $0.05/img | **画像+mask 必須（inpaint）** | 標準 | **inpainting 専用**、部分修正・オブジェクト除去 |
| BFL | `bfl/flux-pro-1.1` | $0.04/img | なし（T2I 専用） | 標準 | T2I の標準、~2 秒生成 |
| BFL | `bfl/flux-pro-1.1-ultra` | $0.06/img | なし | 4 MP | **4 MP 出力**、印刷物・大判ポスターの本命 |
| OpenAI | `openai/gpt-image-1` | input $5/M、output $40/M | あり（multimodal native） | 1024² 系 | gpt-image 系のオリジナル、透過 PNG 対応 |
| OpenAI | `openai/gpt-image-1-mini` | input $2/M、output $8/M | あり | 1024² 系 | **最も安い OpenAI 系**、プロト用 |
| OpenAI | `openai/gpt-image-1.5` | input $5/M、output $32/M | あり | 1536×1024 まで | gpt-image-2 の廉価版、**透過 PNG 必要なときの残し**、テキスト 90-95% |
| OpenAI | `openai/gpt-image-2` | input $5/M、output $30/M | **あり、input_fidelity=high 固定** | **4096×4096、16:9 ネイティブ対応** | **日本語タイポ 99%+**、Thinking mode でレイアウト計画、迷ったら第一候補 |
| ByteDance | `bytedance/seedream-4.0` | $0.03/img | text/single/multi-image | 標準 | 汎用 T+I 入力、コスパ重視 |
| ByteDance | `bytedance/seedream-4.5` | $0.04/img | **multi-image 強化** | 4K 対応、**最低 2K 必須** | **人物フォトリアル 9.4/10**、毛穴・キャッチライト・歯。EC 商品写真の本命 |
| ByteDance | `bytedance/seedream-5.0-lite` | $0.035/img | 参照画像 + Web検索 | 標準、**最低 2K** | 4.5 比 **2-3× 高速**、Web 検索統合で時事性のある画像生成 |
| Recraft | `recraft/recraft-v4.1-pro` | $0.25/img（vector $0.30） | なし | 1024² | **SVG ベクター直接出力**、ロゴ・アイコンの本命、レイヤー構造保持 |
| Recraft | `recraft/recraft-v4.1` | $0.04/img（vector $0.08） | なし | 1024² | コスパ良いベクター、推奨デフォルト |
| Recraft | `recraft/recraft-v4.1-utility-pro` | $0.25/img | なし | 1024² | フラットライティング、シンプル UI 制御シーン特化 |
| Recraft | `recraft/recraft-v4-pro` | $0.25/img | なし | 1024² | 前世代 Pro、Mode 安定性で v4.1-pro より好まれるケースあり |
| Recraft | `recraft/recraft-v4` | $0.04/img | なし | 1024² | 前世代基本、v4.1 と性能差小 |
| Recraft | `recraft/recraft-v3` | $0.04/img | なし | 1024² | **テキスト位置指定可（唯一）**、ER 図・ラベル多用に強い |
| Recraft | `recraft/recraft-v2` | $0.022/img | なし | 1024² | 最安 Recraft、軽量プロト用 |
| xAI | `xai/grok-imagine-image` | $0.02/img | なし | aspectRatio 指定（size 不可） | **$0.02 で最安、多言語テキスト編集**。size 不可、aspectRatio のみ |
| Prodia | `prodia/flux-fast-schnell` | ~$0.001/img | なし | 標準（高速専用） | **190ms 超高速**、大量バッチ・UI モック用 |

### 2.2 Multimodal LLM（chat-completions 経由で画像出力）

| Provider | Model ID | 価格 | 入力画像上限 | 解像度 | 特徴・主用途 |
|---|---|---|---|---|---|
| Google | `google/gemini-3-pro-image`（Nano Banana Pro） | $0.1344/img（1K/2K）、$0.24（4K） | **最大 14 枚、7 MB/枚** | 1K、2K、4K | **日本語 85%**、多ターン編集に強い、studio-level controls、14 枚 multi-ref で LLM ベース統合 |
| Google | `google/gemini-3.1-flash-image-preview`（Nano Banana 2） | TBD | 14 枚 | 標準〜2K | Nano Banana 2、Pro 比で **高速版**（~3 秒）、preview ステータス |
| Google | `google/gemini-2.5-flash-image`（Nano Banana 旧） | $0.039/img | 多枚 | 標準 | 旧世代だが **$0.039 で最安の Gemini**、汎用 multimodal 用 |
| OpenAI | `openai/gpt-5.4` 等 + `image_generation` tool | tool 経由で gpt-image-* 課金 | tool 経由 | gpt-image-2 仕様 | GPT-5.x の **agentic 文脈で画像生成**、reasoning + 画像出力をワンショット |

---

## 3. 特徴ベンチマーク（用途別）

### 3.1 日本語タイポグラフィ得意度

![日本語タイポグラフィ精度ランキング 棒グラフ](./images/ai-gateway-image-models-2026/02-ranking-japanese.png)

| ランク | モデル | 根拠 |
|---|---|---|
| 1 | `openai/gpt-image-2` | 内部テスト 99%+、CJK/RTL 明確サポート、Thinking mode でレイアウト計画 |
| 2 | `google/gemini-3-pro-image` | 日本語（漢字+ひらがな+カタカナ）85%、複雑構成可 |
| 3 | `bfl/flux-2-flex` | タイポ・インフォグラフィック特化、複雑テキストで Pro 超え |
| 4 | `openai/gpt-image-1.5` | テキスト 90-95%、非ラテンも改善 |
| 5 | `recraft/recraft-v4.1` | 多言語短文/中文の位置制御可（v3 は唯一テキスト位置指定可） |

### 3.2 人物画・フォトリアル

![人物画・フォトリアル精度ランキング 棒グラフ](./images/ai-gateway-image-models-2026/03-ranking-photoreal.png)

| ランク | モデル | 特徴 |
|---|---|---|
| 1 | `bytedance/seedream-4.5` | **close-up realism 9.4/10**、自然な毛穴・キャッチライト・歯、Flux Pro / Midjourney v6.1 超え |
| 2 | `bytedance/seedream-5.0-lite` | 4.5 比で 2-3× 高速だがスキンテクスチャは 4.5 が上 |
| 3 | `bfl/flux-2-max` | プロ向け最高品質、production-ready |
| 4 | `bfl/flux-2-pro` | 価格性能比トップ、10 秒以下生成 |
| 5 | `openai/gpt-image-2` | 黄色被り解消、リアル写真らしさ |
| 6 | `google/gemini-3-pro-image` | スタジオ品質、studio-level controls |

### 3.3 キャラクター一貫性（character consistency）

![キャラクター一貫性ランキング cosine類似度スコア](./images/ai-gateway-image-models-2026/04-ranking-character.png)

| ランク | モデル | スコア |
|---|---|---|
| 1 | `bfl/flux-kontext-max` | **6 連続編集後も cosine 類似度 0.92+**（競合は 0.80 まで低下） |
| 2 | `bfl/flux-kontext-pro` | Kontext Max と同系、価格半額 |
| 3 | `bytedance/seedream-4.5` | multi-image での顔の一貫性が安定 |
| 4 | `google/gemini-3-pro-image` | 多ターン編集に強い |
| 5 | `bfl/flux-2-pro` | multi-ref 最大 9 MP でレファレンス保持 |

### 3.4 イラスト・ベクター・ロゴ

![イラスト・ベクター・ロゴ生成ランキング 棒グラフ](./images/ai-gateway-image-models-2026/05-ranking-vector.png)

| ランク | モデル | 特徴 |
|---|---|---|
| 1 | `recraft/recraft-v4.1-pro` | **SVG ベクター直接出力**、レイヤー構造保持、ロゴ・アイコン用 |
| 2 | `recraft/recraft-v4.1-utility-pro` | フラットライティング、シンプル制御シーン |
| 3 | `recraft/recraft-v4.1` | コスパ良好なイラスト生成 |
| 4 | `bfl/flux-2-flex` | UI モックアップ、インフォグラフィック |
| 5 | `google/gemini-3-pro-image` | 多様な編集スタイル |

### 3.5 multi-reference 画像入力対応

| モデル | 上限 | 用途 |
|---|---|---|
| `bfl/flux-2-flex` | **最大 10 枚 / 合計 14 MP** | 最強の multi-ref。タイポ + 参照画像合成 |
| `bfl/flux-2-pro` | **最大 9 MP 合計** | 標準的な multi-ref ワークフロー |
| `bfl/flux-2-max` | 編集対応 | プロ品質の multi-ref |
| `bytedance/seedream-4.5` | multi-image 強化 | キャラ一貫性 + 構図合成 |
| `bytedance/seedream-4.0` | 複数枚対応 | text + single/multi image |
| `google/gemini-3-pro-image` | **最大 14 枚 / 7 MB/枚** | LLM ベースで対話的に統合 |
| `google/gemini-3.1-flash-image-preview` | 14 枚 | 高速 multi-image |
| `bfl/flux-kontext-max/pro` | 単一参照のみ | キャラ一貫性編集 |
| `openai/gpt-image-2` | 単一参照（input_fidelity=high） | 高忠実度編集 |
| `bfl/flux-pro-1.0-fill` | 画像 + mask | inpainting 専用 |

---

### 3.6 実出力比較（同じお題を 2 モデルで生成）

ランキング表だけでは「何がどう違うか」は伝わりにくい。同一プロンプトを A（特徴で勝るとされるモデル）と B（比較対象）で実際に生成し、出力差を 12 カテゴリ並べる。各カテゴリで「強み根拠」「画像で見るべき違い」「実務選定の判断軸」を 3 段で解説する。

> 注: Google Nano Banana 系（`google/gemini-*-image`）は `/v1/images/generations` 経由では呼べない（`chat-completions` 専用）。本比較では B 側を `gpt-image-2` / `flux-2-flex` / `flux-pro-1.1-ultra` / `recraft-v4.1` などに差し替えている。`gemini-3-pro-image` の出力を見るには AI SDK v6 の `generateText` + `messages` 経由で呼ぶ必要がある（§4.4 参照）。

### 3.6.1 日本語タイポ精度 — `openai/gpt-image-2` vs `bfl/flux-2-pro`

お題プロンプト: 「店頭 A 型看板ポスター、白背景に大きな日本語キャッチコピー『春の新生活応援セール 全品 30%OFF』、その下に小さく『3 月 31 日まで』、Noto Sans JP Bold、暖色アクセント」

**A: `openai/gpt-image-2`**

![A: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c01-a-gpt-image-2.png)

**B: `bfl/flux-2-pro`**

![B: bfl/flux-2-pro](./images/ai-gateway-image-models-2026/compare/c01-b-flux-2-pro.png)

- **強み根拠**: gpt-image-2 は CJK 文字を学習段階で明示サポートし、内部テストで日本語含む 99%+ の精度を公表。Thinking mode 相当の前計画でレイアウトを決めてからレンダリングするため、漢字の偏旁・濁点・促音のような細部が崩れにくい。flux-2-pro は英語タイポは強いが、日本語の特定文字（「応」「援」など画数の多い漢字）でグリフが崩れる事例が多い。
- **画像で見るべき違い**: 「援」「応」「品」など画数の多い漢字、「%」「OFF」など英数混在、「3 月 31 日」の数字 + 単位の組み合わせを拡大して見る。flux 側は漢字の偏旁が一部潰れる、または別字に置換されるケースが見える。
- **実務選定の判断軸**: 日本語キャッチコピー入りの広告バナー / SNS サムネ / 印刷物プレビューは **gpt-image-2 一択**。flux-2-pro を使う場合は OCR でテキストを後段で差し替えるパイプラインが現実的。

---

### 3.6.2 人物クローズアップ・フォトリアル — `bytedance/seedream-4.5` vs `openai/gpt-image-2`

お題プロンプト: 「窓辺で本を読む 20 代女性のポートレート、午後の自然光、close-up、毛穴・キャッチライト・歯のディテール、shallow depth of field」

**A: `bytedance/seedream-4.5`**

![A: bytedance/seedream-4.5](./images/ai-gateway-image-models-2026/compare/c02-a-seedream-4.5.png)

**B: `openai/gpt-image-2`**

![B: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c02-b-gpt-image-2.png)

- **強み根拠**: seedream-4.5 は close-up realism ベンチで 9.4/10、Flux Pro / Midjourney v6.1 を上回るスコア。毛穴・産毛・歯のエッジ・瞳のキャッチライトといった「ミクロな質感」の学習サンプルが多い。gpt-image-2 は黄被りが改善されたが、肌は「整いすぎる」傾向で、リアル写真感では一歩譲る。
- **画像で見るべき違い**: 鼻先や頬の **毛穴の不均一性**、唇のハイライト、髪 1 本 1 本の解像感、瞳のリングライト。seedream 側は皮膚のミクロテクスチャが粒子レベルで再現される。
- **実務選定の判断軸**: 化粧品 / 美容 / アパレル EC の人物画は **seedream-4.5**。広告クリエイティブで「肌キレイすぎ」が許容される場合や、人物 + 日本語タイポ複合なら gpt-image-2。

---

### 3.6.3 キャラ一貫性（T2I 単発・2 シーン同一人物） — `bfl/flux-2-pro` vs `openai/gpt-image-2`

> 注: 本来「キャラ一貫性」は `flux-kontext-max` の連続編集（image-to-image）で評価する特徴。本比較では `/v1/images/generations` で 2 シーンを 1 枚に描く T2I 単発タスクとして実施したため、Kontext 系の真価（6 連続編集後も cosine 0.92+）は別途参照画像入りで検証してほしい。

お題プロンプト: 「横長 2 シーン構成、左半分は雪の夜の街角に立つ黒髪ショート + 赤マフラー + ベージュコートの少女、右半分は同じ少女がカフェのカウンターで湯気のマグカップを持つ。表情と顔立ちは完全に同じ」

**A: `bfl/flux-2-pro`**

![A: bfl/flux-2-pro](./images/ai-gateway-image-models-2026/compare/c03-a-flux-2-pro.png)

**B: `openai/gpt-image-2`**

![B: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c03-b-gpt-image-2.png)

- **強み根拠**: flux-2-pro は multi-ref 最大 9 MP のレファレンス保持機構が単発生成内でも効き、「同一画像内の 2 シーン」では構図的に顔の特徴ベクトルを共有しやすい。gpt-image-2 はストーリー性 / 構図のロジックは強いが、左右で別キャラを描き分ける誘惑が出やすい。
- **画像で見るべき違い**: 左右の **顔立ち（目の間隔、鼻の形、輪郭）**、**髪型（前髪・揉み上げ）**、**マフラーの色味・編み目**。flux 側はキャラの「同一性」、gpt 側は「シーンの説得力」を優先する傾向。
- **実務選定の判断軸**: シリーズ漫画 / コミック / VTuber 立ち絵バリエは **flux-kontext-max（image2image）一択**。本記事の T2I 単発比較は参考程度に、本番では Kontext 系で参照画像 + 編集プロンプトを使うこと。

---

### 3.6.4 ロゴ・ベクター — `recraft/recraft-v3` vs `bfl/flux-2-flex`

> 注: `recraft-v4.1-pro` と `recraft-v4-pro` は本検証中（2026-05-22）に AI Gateway 経由で `400 Bad Request` を返したため、テキスト位置指定が可能な `recraft-v3` に差し替えた。recraft 系は API ゲートウェイ仕様変更が頻繁、最新の動作モデルは事前に `models` コマンドで確認すること。

お題プロンプト: 「ミニマルな SaaS ロゴ『Lumen』、青系グラデ、フラットベクター、明快な幾何形、白背景、SVG クリーンな輪郭」

**A: `recraft/recraft-v3`**

![A: recraft/recraft-v3](./images/ai-gateway-image-models-2026/compare/c04-a-recraft-v3.png)

**B: `bfl/flux-2-flex`**

![B: bfl/flux-2-flex](./images/ai-gateway-image-models-2026/compare/c04-b-flux-2-flex.png)

- **強み根拠**: recraft 系は学習データの大半がベクター / ロゴ / アイコンで、輪郭がアンチエイリアス前提のクリーンなパスとして出る。`recraft-v4.1-pro` は `+$0.05` で **SVG 直接出力**（ラスタライズ前のパス情報）も取得できる。flux-2-flex は infographics 寄りで、ロゴでは細部のラスタライズ感（境界のノイズ）が残る。
- **画像で見るべき違い**: ロゴアイコンの **輪郭線の鋭利さ**、文字 `Lumen` の **カーニングと字面の整い**、グラデの **バンディング**。recraft 側は SVG 由来のクリーンエッジが見える。
- **実務選定の判断軸**: ブランドロゴ / アプリアイコン / プリント用ベクターは **recraft-v4.1-pro（SVG オプション付き）**。ヒーローのワンタイム挿絵やマーケサイトのアイキャッチなら flux-2-flex も十分使える。

---

### 3.6.5 インフォグラフィック（クラウド 3 層図） — `bfl/flux-2-flex` vs `openai/gpt-image-2`

お題プロンプト: 「CDN / Edge → Functions → Database の 3 層を角丸ボックスで表現、各層にアイコン、矢印で接続、淡いブルーとセージグリーン、英字＋日本語ラベル」

**A: `bfl/flux-2-flex`**

![A: bfl/flux-2-flex](./images/ai-gateway-image-models-2026/compare/c05-a-flux-2-flex.png)

**B: `openai/gpt-image-2`**

![B: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c05-b-gpt-image-2.png)

- **強み根拠**: flux-2-flex は infographics / typography 特化チューニングで、複数ボックス + ラベル + 矢印の「構造を保ったまま再現する」能力が高い。gpt-image-2 はラベル文字は綺麗だが、層数や矢印方向を入れ替えるなど **構造のドリフト** が出ることがある。
- **画像で見るべき違い**: **3 層が上下に正しく並ぶか**、**矢印の向き**、**ラベル位置とボックスの対応**。flux 側は構造の忠実性、gpt 側はラベルテキストの読みやすさで勝る。
- **実務選定の判断軸**: テックブログのアーキ図 / プレゼン資料 / READMEのバナー図は **flux-2-flex**。プレゼン資料で日本語の細かい説明文を入れたければ gpt-image-2、または Mermaid 等のコードベース図を AI に通さず使う。

---

### 3.6.6 高速プロトタイピング — `bfl/flux-2-klein-9b` vs `bfl/flux-pro-1.1-ultra`

お題プロンプト: 「ファンタジー風の小さな焚き火、夕暮れの山中、橙赤の炎と紫の空、シルエットの木々」

**A: `bfl/flux-2-klein-9b（高速・低品質）`**

![A: bfl/flux-2-klein-9b（高速・低品質）](./images/ai-gateway-image-models-2026/compare/c06-a-flux-2-klein-9b.png)

**B: `bfl/flux-pro-1.1-ultra（4 MP・高品質）`**

![B: bfl/flux-pro-1.1-ultra（4 MP・高品質）](./images/ai-gateway-image-models-2026/compare/c06-b-flux-pro-1.1-ultra.png)

- **強み根拠**: flux-2-klein-9b は **1 秒未満**で生成完了、ラフカンプ / ムードボード / プロンプト探索に最適。flux-pro-1.1-ultra は 4 MP 出力（最大 2048×2048 相当）で印刷物にも使えるディテール。同じ「絵柄の方向性確認」目的でも、用途が全く違う。
- **画像で見るべき違い**: 細部の **解像感（薪の質感、葉のシルエット、炎のエッジ）**、**色の階調の滑らかさ**、**全体のコンセプト完成度**。klein は粗いがコンセプトは伝わる、ultra は印刷品質。
- **実務選定の判断軸**: 「20 案出して 1 案選ぶ」プロト段階は **flux-2-klein-9b** で 1 案 $0.001-0.005、最終納品 1 枚は **flux-pro-1.1-ultra** に切り替えるパイプラインがコスト最適。

---

### 3.6.7 4K 高解像度・風景パノラマ — `openai/gpt-image-2` vs `bfl/flux-pro-1.1-ultra`

> 注: 本来は `gemini-3-pro-image`（4K 対応の最高位）との比較だったが、image-only API 非対応のため `flux-pro-1.1-ultra`（4 MP）に差し替え。

お題プロンプト: 「富士山と満開の桜並木を俯瞰した風景パノラマ、4K 想定の超細密ディテール、葉と花びらが個別判別できる解像感」

**A: `openai/gpt-image-2（4096² 対応）`**

![A: openai/gpt-image-2（4096² 対応）](./images/ai-gateway-image-models-2026/compare/c07-a-gpt-image-2.png)

**B: `bfl/flux-pro-1.1-ultra（4 MP・2K 16:9 ネイティブ）`**

![B: bfl/flux-pro-1.1-ultra（4 MP・2K 16:9 ネイティブ）](./images/ai-gateway-image-models-2026/compare/c07-b-flux-pro-1.1-ultra.png)

- **強み根拠**: gpt-image-2 はネイティブ 4096×4096、16:9（3840×2160）が公式サポート。遠景の小オブジェクトまで解像感を保つ。flux-pro-1.1-ultra は 4 MP（例: 2752×1456 等）で、印刷物用の解像度には十分だが gpt-image-2 ほどの「画素密度」はない。
- **画像で見るべき違い**: **遠景の村の家・田畑のディテール**、**桜の花びら 1 枚 1 枚**、**雪冠の凹凸**。等倍で見ると gpt 側の方が「拡大しても破綻しない」。
- **実務選定の判断軸**: A2 ポスター / イベント大判印刷 / Web の Retina ヒーロー画像は **gpt-image-2 4K モード**。SNS / 通常解像度の Web 用なら flux-pro-1.1-ultra で十分（コストが約半額）。

---

### 3.6.8 浮世絵・日本画スタイル — `openai/gpt-image-2` vs `bfl/flux-2-pro`

お題プロンプト: 「葛飾北斎風の浮世絵、大波と漁船、富士山遠景、藍・白・墨の伝統色、版画の輪郭線、和紙の質感」

**A: `openai/gpt-image-2`**

![A: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c08-a-gpt-image-2.png)

**B: `bfl/flux-2-pro`**

![B: bfl/flux-2-pro](./images/ai-gateway-image-models-2026/compare/c08-b-flux-2-pro.png)

- **強み根拠**: gpt-image-2 は「神奈川沖浪裏」を含む浮世絵作品の典型構図・色彩・線質を強く学習している。スタイル指示語（"ukiyo-e"、"wood-block print"）への追従性が高い。flux-2-pro はテクスチャは豊富だが、版画特有の「平面的な色面 + 輪郭線」よりも陰影付きの絵画的表現に流れがち。
- **画像で見るべき違い**: **波の白い泡の様式化**、**輪郭線の太さと均一性**、**色数の制限（伝統的に 3〜5 色）**、**和紙の繊維感**。
- **実務選定の判断軸**: 和テイストのアートワーク / インバウンド観光素材 / 文化財紹介ビジュアルは **gpt-image-2**。flux-2-pro は「日本画 × 現代風」のミックスや、独自の絵画解釈を求めるアートディレクションで活きる。

---

### 3.6.9 商品写真・物撮り — `bytedance/seedream-4.5` vs `openai/gpt-image-2`

お題プロンプト: 「黒磁器のコーヒーカップ、湯気が立つホットコーヒー、白背景スタジオ、ハイライトと影、上から斜め 45 度」

**A: `bytedance/seedream-4.5`**

![A: bytedance/seedream-4.5](./images/ai-gateway-image-models-2026/compare/c09-a-seedream-4.5.png)

**B: `openai/gpt-image-2`**

![B: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c09-b-gpt-image-2.png)

- **強み根拠**: 3.6.2 と同じく seedream-4.5 のフォトリアル系学習が物撮りでも効く。**素材の質感（磁器の艶 / 液体の表面張力 / 蒸気の透明感）** の再現が一段上。gpt-image-2 はライティングと構図はプロ級だが、液体表面のミクロな揺らぎは整いすぎ。
- **画像で見るべき違い**: **カップの曲面の光の反射の歪み**、**コーヒー表面のクレマの粒度**、**湯気の透過と背景のボケ方**。
- **実務選定の判断軸**: EC の商品撮影代替（バリエ撮影が高コストな少量在庫品など）は **seedream-4.5**。広告のシズル感が欲しい場合は seedream で生成 → Photoshop でディテール追加が王道。

---

### 3.6.10 アニメ・イラスト風 — `bfl/flux-2-pro` vs `recraft/recraft-v4.1`

> 注: 本来は `gemini-3-pro-image` との比較だったが、image-only API 非対応のため `recraft-v4.1` に差し替え。

お題プロンプト: 「アニメ風の図書館の少女、本棚に囲まれた机で本を読む、繊細な線画 + 淡い水彩風、ジブリ風の温かみ」

**A: `bfl/flux-2-pro`**

![A: bfl/flux-2-pro](./images/ai-gateway-image-models-2026/compare/c10-a-flux-2-pro.png)

**B: `recraft/recraft-v4.1`**

![B: recraft/recraft-v4.1](./images/ai-gateway-image-models-2026/compare/c10-b-recraft-v4.1.png)

- **強み根拠**: flux-2-pro は anime / illustration スタイル指示への追従性が高く、線の繊細さ（特に髪の毛・睫毛）が安定する。recraft-v4.1 はデザインフラットな塗りに寄せやすく、ジブリ風よりも教科書・絵本イラストに近い表現。
- **画像で見るべき違い**: **線画の細さ・抑揚**、**塗りのグラデーション（水彩風 vs フラット）**、**斜光の質感**。
- **実務選定の判断軸**: アニメ / 漫画 / ライトノベル系の挿絵は **flux-2-pro**。フラットイラスト・教育コンテンツ・パワポ用イラストは **recraft-v4.1**。

---

### 3.6.11 多ラベル ER 図 — `recraft/recraft-v3` vs `bfl/flux-2-flex`

お題プロンプト: 「データベース ER 図、5 テーブル（users / orders / products / categories / payments）、各テーブル 3-5 フィールド、外部キー矢印、FK/PK 注釈」

**A: `recraft/recraft-v3`**

![A: recraft/recraft-v3](./images/ai-gateway-image-models-2026/compare/c11-a-recraft-v3.png)

**B: `bfl/flux-2-flex`**

![B: bfl/flux-2-flex](./images/ai-gateway-image-models-2026/compare/c11-b-flux-2-flex.png)

- **強み根拠**: recraft-v3 は **テキスト位置を明示的に指定可能**な唯一系統で、ラベルが多数並ぶ図解で文字が崩れずに整列する。flux-2-flex はインフォグラフィック特化だが、「同種のラベル文字列が大量に並ぶ」ケースでは位置がズレる / 隣接ラベルが合体する事故が出やすい。
- **画像で見るべき違い**: **各テーブルのフィールド名の判読性**、**矢印の起点 / 終点の正確性**、**FK/PK 注釈の位置**。
- **実務選定の判断軸**: 技術ドキュメントの ER 図 / フロー図 / シーケンス図は **本来は Mermaid / PlantUML / Excalidraw でコードベース管理が正解**。AI 生成は「ラフ案」または「読者向け装飾図」までに留め、構造の正確性は人手レビュー必須。

---

### 3.6.12 多言語混在バナー（CJK + ラテン） — `openai/gpt-image-2` vs `bfl/flux-2-flex`

> 注: 本来は `gemini-3-pro-image` との比較だったが、image-only API 非対応のため `flux-2-flex` に差し替え（記事ランキング 3 位の代替）。

お題プロンプト: 「イベントバナー、日本語 + 英字混在『東京 AI Summit 2026 / Tokyo AI Summit 2026』、日付・場所も日英併記、青と白のグラデ」

**A: `openai/gpt-image-2`**

![A: openai/gpt-image-2](./images/ai-gateway-image-models-2026/compare/c12-a-gpt-image-2.png)

**B: `bfl/flux-2-flex`**

![B: bfl/flux-2-flex](./images/ai-gateway-image-models-2026/compare/c12-b-flux-2-flex.png)

- **強み根拠**: gpt-image-2 は CJK + ラテンの**混在レイアウト**を学習しており、両言語の **フォントサイズバランス・行間・余白** を統一して描ける。flux-2-flex はタイポ強いが、CJK と英字を「別パスで」描く傾向があり、混在時に行揃え / バランスがずれる。
- **画像で見るべき違い**: **日本語と英字の行揃え**、**フォントのウェイトの統一感**、**数字 `2026` のグリフ**、**スラッシュ `/` の文字幅**。
- **実務選定の判断軸**: インバウンド向け広告 / 国際カンファレンス / 多言語 EC バナーは **gpt-image-2**。日本語のみ → 日本語タイポ ✕ gpt-image-2 が依然ベスト。

---

## 4. API パラメータ仕様

### 4.1 image-only エンドポイントの共通仕様

```bash
POST https://ai-gateway.vercel.sh/v1/images/generations
```

```json
{
  "model": "bfl/flux-2-pro",
  "prompt": "...",
  "n": 1,
  "size": "1024x1024",
  "response_format": "b64_json",
  "providerOptions": {
    "blackForestLabs": {
      "outputFormat": "jpeg",
      "safetyTolerance": 2
    }
  }
}
```

### 4.2 プロバイダ別 `providerOptions`

| Provider | キー | パラメータ例 |
|---|---|---|
| Black Forest Labs | `blackForestLabs` | `outputFormat`（jpeg/png）、`safetyTolerance`（0-6） |
| Google Vertex（Imagen） | `googleVertex` | `aspectRatio`（'1:1' 等）、`safetyFilterLevel`（'block_some' 等） |
| OpenAI | （top-level） | `quality`、`style`、`background` |
| xAI | （size 不可） | `aspectRatio` 必須 |

### 4.3 multimodal（chat-completions）経由の画像入出力

```json
{
  "model": "google/gemini-3-pro-image",
  "modalities": ["text", "image"],
  "messages": [{
    "role": "user",
    "content": [
      { "type": "text", "text": "次の参照画像を 16:9 に合成して..." },
      { "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } },
      { "type": "image_url", "image_url": { "url": "data:image/png;base64,..." } }
    ]
  }]
}
```

レスポンスは `choices[0].message.images[].image_url.url` に data: URI 形式で返る。

### 4.4 AI SDK v6 経由（推奨インターフェース）

```typescript
// image-only モデル
import { experimental_generateImage as generateImage } from 'ai';
const { images } = await generateImage({
  model: 'bfl/flux-2-pro',
  prompt: '...',
  n: 2,
  aspectRatio: '16:9',
});

// multimodal LLM（Nano Banana 系）
import { generateText } from 'ai';
const result = await generateText({
  model: 'google/gemini-3-pro-image',
  messages: [{
    role: 'user',
    content: [
      { type: 'text', text: '...' },
      { type: 'image', image: imageBuffer1 },
      { type: 'image', image: imageBuffer2 },
    ],
  }],
});
const imageFiles = result.files.filter(f => f.mediaType?.startsWith('image/'));
```

---

## 5. ユースケース → モデル選定マトリクス

![ユースケース → 推奨モデル 判定フロー](./images/ai-gateway-image-models-2026/06-usecase-flow.png)

### 詳細マトリクス

| ユースケース | 1 位 | 2 位 | 3 位 | 備考 |
|---|---|---|---|---|
| 日本語タイポ広告 | `gpt-image-2` | `gemini-3-pro-image` | `flux-2-flex` | 4096² + 16:9 ネイティブ |
| 日本語サムネ（SNS） | `gemini-3-pro-image` | `gpt-image-2` | `flux-2-pro` + プロンプト工夫 | Nano Banana Pro の日本語 85% |
| 商品写真・人物 | `seedream-4.5` | `flux-2-max` | `gpt-image-2` | 毛穴・スキン |
| キャラ立ち絵連続 | `flux-kontext-max` | `seedream-4.5` | `gemini-3-pro-image` | 6 連続編集で 0.92+ |
| ロゴ・アイコン（SVG） | `recraft-v4.1-pro` | `recraft-v4.1` | `flux-2-flex` | recraft はベクター直出力 |
| インフォグラフィック | `flux-2-flex` | `gemini-3-pro-image` | `gpt-image-2` | Flex は infographics 特化 |
| multi-ref ムードボード | `flux-2-flex` | `gemini-3-pro-image` | `flux-2-pro` | Flex 10 枚/14MP |
| inpainting（部分修正） | `flux-pro-1.0-fill` | `flux-kontext-max` | `gpt-image-2`（edit） | Fill はマスク必須 |
| 高速プロトタイピング | `flux-2-klein-9b` | `flux-pro-1.1` | `gemini-3.1-flash-image-preview` | 1 秒未満 |
| 4K 出力 | `gpt-image-2`（4096²） | `gemini-3-pro-image`（4K） | `flux-pro-1.1-ultra`（4MP） | |
| ukiyo-e / 日本画風 | `gpt-image-2` | `seedream-4.5` | `flux-2-pro` | プロンプト精度依存 |

## 6. モデル選定の実務ガイド（コスト・速度・制約）

ベンチマーク順位だけでは「現場で何を選ぶか」は決まらない。本章では月次予算 / レイテンシ / プロバイダ制約という 3 軸を 1 枚ずつ整理し、最後にチェックリスト形式で選定フローをまとめる。

### 6.1 1000 枚生成時の総コスト比較（D1）

![1000 枚生成時の総コスト ランキング棒グラフ](./images/ai-gateway-image-models-2026/d1-cost-1000.png)

| ランク | モデル | 1 枚単価 | 1000 枚総額 | 価格根拠 |
|---|---|---|---|---|
| 1 | `prodia/flux-fast-schnell` | ~$0.001 | $1〜 | プロト・大量バッチ向け |
| 2 | `xai/grok-imagine-image` | $0.02 | $20 | aspectRatio 指定のみ・サイズ不可 |
| 3 | `openai/gpt-image-1-mini` | $0.03 | $30 | gpt-image-1 系の軽量版 |
| 4 | `bytedance/seedream-5.0-lite` | $0.035 | $35 | 4.5 比 2-3× 高速 |
| 5 | `google/gemini-2.5-flash-image` | $0.039 | $39 | Nano Banana 旧、chat-completions 経由 |
| 5 | `bytedance/seedream-4.5` | $0.04 | $40 | 人物リアル最高水準 |
| 5 | `bfl/flux-kontext-pro` | $0.04 | $40 | キャラ一貫性編集 |
| 5 | `recraft/recraft-v4.1` | $0.04 | $40 | ベクター・コスパ良 |
| 9 | `bfl/flux-2-pro` | ~$0.05 | ~$50 | 価格性能比トップ |
| 10 | `bfl/flux-pro-1.1-ultra` | $0.06 | $60 | 4 MP 出力 |
| 11 | `bfl/flux-kontext-max` | $0.08 | $80 | キャラ一貫性最高位 |
| 12 | `openai/gpt-image-2` | ~$0.10 | ~$100 | 日本語タイポ・4K |
| 13 | `google/gemini-3-pro-image` | $0.1344 (1K/2K), $0.24 (4K) | $134〜$240 | Nano Banana Pro |
| 14 | `recraft/recraft-v4.1-pro` | $0.25 (vector $0.30) | $250〜$300 | SVG 直接出力 |

> **注意**: `openai/gpt-image-*` は input/output token 単価制（input $5/M、output $30-40/M）。1 枚あたりの実費はプロンプト長と出力品質設定で揺れる。上表は典型ケースの近似。

### 6.2 品質 × コスト 4 象限散布図（D2）

![品質 × コスト 4象限プロット 散布図](./images/ai-gateway-image-models-2026/d2-quality-cost-scatter.png)

象限の読み方:

- **左上「コスパ最強」ゾーン** — `xai/grok-imagine-image` / `seedream-5.0-lite` / `gemini-2.5-flash-image`。$50/月以下で品質 8.0-8.7 を得たいときの第一候補。
- **中央上「バランス型」ゾーン** — `seedream-4.5` / `flux-2-pro` / `flux-kontext-pro` / `gpt-image-1.5`。$40-$60 帯で品質 8.5-9.4、本記事の **標準推奨ゾーン**。
- **右上「最高品質」ゾーン** — `gpt-image-2` / `gemini-3-pro-image` / `recraft-v4.1-pro` / `flux-kontext-max`。$80-$250 だが用途特化（日本語 / SVG / 編集）で代替不可な強みを持つ。
- **左下「ドラフト用」ゾーン** — `prodia/flux-fast-schnell`。$1 で 1000 枚、プロンプト探索専用。

### 6.3 用途 × 予算 推奨モデル マトリクス（D3）

![用途 × 予算 推奨モデル マトリクス](./images/ai-gateway-image-models-2026/d3-budget-matrix.png)

| 月次予算 | 日本語タイポ | 人物・商品写真 | ロゴ・SVG | インフォグラフィック | キャラ一貫性編集 |
|---|---|---|---|---|---|
| **低（〜$30/月）** | `gpt-image-1.5` | `seedream-5.0-lite` | `recraft-v4.1` | `flux-2-flex` | `flux-kontext-pro` |
| **中（$30〜$100/月）** | `gpt-image-2` | `seedream-4.5` | `recraft-v4.1` | `flux-2-flex` | `flux-kontext-pro` |
| **高（$100超/月）** | `gpt-image-2` + Thinking | `seedream-4.5` + 後処理 | `recraft-v4.1-pro` (SVG) | `flux-2-flex` / `gpt-image-2` | `flux-kontext-max` |

> 想定: 月 100 枚程度の運用。バッチ生成（>500 枚/月）では Provider 別の Volume 割引交渉も視野に入る。

### 6.4 「100 枚運用」シナリオ別 月額試算（D4）

実務で多い 5 シナリオを月 100 枚で試算した。社内コスト承認の根拠資料としてそのまま流用可能。

| シナリオ | 推奨モデル | 1 枚単価 | 100 枚月額 | 注釈 |
|---|---|---|---|---|
| 日本語 SNS サムネ（Twitter/X） | `gpt-image-2` | $0.08 | **$8** | 1024² で十分、Thinking off |
| 日本語広告バナー（印刷 4K） | `gpt-image-2`（4K） | $0.15 | **$15** | 4096² 出力で 1.5-2× 課金 |
| 人物商品写真（EC バリエ撮影代替） | `seedream-4.5` | $0.04 | **$4** | 2K 必須・letterbox は後処理 |
| ロゴ・アイコン納品（SVG） | `recraft-v4.1-pro` (vector) | $0.30 | **$30** | SVG パス + PNG 同時納品 |
| シリーズキャラ立ち絵（6 ターン編集） | `flux-kontext-max` | $0.08 × 6 | **$48** | 1 キャラ × 6 シーン編集 |
| インフォグラフィック（ブログ図解） | `flux-2-flex` | ~$0.04 | **$4** | テックブログ 1 記事 1 図 |

> ROI 目安: 外注デザイナーで同等品質を発注した場合、SNS サムネ 100 枚で $200-$500、ロゴ 1 件で $300-$2000。**月 $50 のクラウド画像生成予算で、デザイン外注の 1-2 案件分が内製化** できる計算になる。

### 6.5 モデル制約 早見表（D5）

API 仕様の差分は実装段階で必ずハマる。以下を `models.json` 形式で持っておくと CLI ラッパで自動分岐できる。

| モデル | 最小解像度 | 最大解像度 | アスペクト指定 | 透過 PNG | SVG 出力 | API |
|---|---|---|---|---|---|---|
| `openai/gpt-image-2` | 1024² | 4096² | size 指定 | ❌ | ❌ | image-only |
| `openai/gpt-image-1.5` | 1024² | 1536×1024 | size 指定 | ✅ | ❌ | image-only |
| `openai/gpt-image-1` / `-mini` | 1024² | 1024² | size 指定 | ✅ | ❌ | image-only |
| `bfl/flux-2-pro` | 標準 | 4 MP | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-2-max` | 標準 | 4 MP | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-2-flex` | 標準 | カスタム | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-2-klein-*` | 標準 | 標準 | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-kontext-max/pro` | 標準 | 標準 | size 指定 | ❌ | ❌ | image-only（image2image） |
| `bfl/flux-pro-1.1` | 標準 | 標準 | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-pro-1.1-ultra` | 標準 | 4 MP | size 指定 | ❌ | ❌ | image-only |
| `bfl/flux-pro-1.0-fill` | 標準 | 標準 | size 指定 | ❌ | ❌ | image-only（要 mask） |
| `bytedance/seedream-4.0` / `4.5` | **2K（≥3,686,400 px）** | 4K | size 指定 | ❌ | ❌ | image-only |
| `bytedance/seedream-5.0-lite` | **2K** | 標準 | size 指定 | ❌ | ❌ | image-only |
| `recraft/recraft-v4.1-pro` | 1024² | 1024² 系 | size 指定 | ❌ | **✅** | image-only（仕様変動あり） |
| `recraft/recraft-v4.1` / `v4` / `v3` | 1024² | 1024² 系 | size 指定 | ❌ | ❌ | image-only |
| `recraft/recraft-v2` | 1024² | 1024² | size 指定 | ❌ | ❌ | image-only |
| `xai/grok-imagine-image` | — | — | **aspectRatio のみ** | ❌ | ❌ | image-only |
| `prodia/flux-fast-schnell` | 標準 | 標準 | size 指定 | ❌ | ❌ | image-only |
| `google/gemini-3-pro-image` | 1K | **4K** | 内部 | ❌ | ❌ | **chat-completions 専用** |
| `google/gemini-3.1-flash-image-preview` | 1K | 2K | 内部 | ❌ | ❌ | **chat-completions 専用** |
| `google/gemini-2.5-flash-image` | 標準 | 標準 | 内部 | ❌ | ❌ | **chat-completions 専用** |

### 6.6 ハマりやすい失敗パターン（D6）

本記事の比較画像 24 枚を生成する過程で実際に踏んだ落とし穴。次に同じ穴に落ちる時間を省く目的でメモする。

1. **`Seedream-4.5` / `4.0` で `size=1536x1024` → `400 size must be at least 3686400 pixels`** — Seedream 系は **最低 3,686,400 px（= 2K 16:9 = 2560×1440）必須**。1536×1024 = 1,572,864 px はピクセル数不足で弾かれる。`--size 2560x1440` または `--size 2048x1840` 以上を指定する。
2. **`google/gemini-3-pro-image` で `/v1/images/generations` → `400 Model is a language model, not an image model`** — Nano Banana 系は **`chat-completions` 専用**。`generateText({ model: 'google/gemini-3-pro-image', messages: [...] })` で呼び、レスポンスの `result.files` から image を取り出す。`experimental_generateImage` では呼べない。
3. **`recraft/recraft-v4.1-pro` で `400 Bad Request`（詳細メッセージなし）** — recraft 系は AI Gateway 経由で **仕様変動が頻繁**。本検証中（2026-05-22）に `v4.1-pro` / `v4-pro` がいずれも 400 を返した。`recraft/recraft-v3` までフォールバックすると通った。本番ワークフローでは **モデル可用性のヘルスチェック** を毎日叩いておくと事故を防げる。
4. **`xai/grok-imagine-image` で `size=1536x1024` → エラー** — xAI は **`size` パラメータを受け付けない**、`aspectRatio: '16:9'` を `providerOptions` に渡す。
5. **`bfl/flux-*` の `safety_tolerance` 範囲がモデル毎に違う** — `flux-2-*` は 1-5、`flux-kontext-*` / `flux-pro-1.*` は 0-6。範囲外を渡すと 400。モデル毎にバリデーション必要。
6. **`gpt-image-2` で `input_fidelity=high` 固定** → 編集コストが 2-3× ベースラインに跳ねる。透過 PNG が必要な編集タスクなら `gpt-image-1.5` を残すべき。
7. **multi-ref 画像の渡し方がプロバイダごとに違う** — `image[]`（Seedream）、`image_prompts[]`（BFL）、`image`（OpenAI 単一）、`messages[].content[]` の `type: image_url`（Gemini）と統一されていない。**統一ラッパを 1 枚作っておく** のが先。

### 6.7 エンドポイント別 SDK 呼び分けサンプル（D7）

AI SDK v6 で image-only と multimodal を 1 ファイルでハンドルする最小例。

```typescript
// 統一ラッパ: モデル ID を見て分岐
import {
  experimental_generateImage as generateImage,
  generateText,
} from 'ai';

const MULTIMODAL_MODELS = new Set([
  'google/gemini-3-pro-image',
  'google/gemini-3.1-flash-image-preview',
  'google/gemini-2.5-flash-image',
]);

export async function generateOne(opts: {
  model: string;
  prompt: string;
  refs?: Buffer[]; // 参照画像
  aspectRatio?: string;
}) {
  const { model, prompt, refs = [], aspectRatio = '16:9' } = opts;

  if (MULTIMODAL_MODELS.has(model)) {
    // chat-completions 経由（Nano Banana 系）
    const result = await generateText({
      model,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: prompt },
          ...refs.map((image) => ({ type: 'image' as const, image })),
        ],
      }],
    });
    const files = result.files.filter((f) => f.mediaType?.startsWith('image/'));
    return files[0].uint8Array;
  }

  // image-only 経由（FLUX / gpt-image / Seedream / Recraft / xAI）
  const { images } = await generateImage({
    model,
    prompt,
    n: 1,
    aspectRatio,
    providerOptions: model.startsWith('bfl/')
      ? { blackForestLabs: { outputFormat: 'jpeg', safetyTolerance: 2 } }
      : model.startsWith('xai/')
      ? { xai: { aspectRatio } }
      : undefined,
  });
  return images[0].uint8Array;
}
```

### 6.8 モデル選定 5 ステップ チェックリスト（D8）

新規画像生成パイプラインを設計するとき、上から順に確認すれば 30 分でモデルが決まる。

1. **生成物の主用途は何か？** — 日本語タイポ / 人物 / ロゴ / インフォグラ / キャラ連続 / プロトのいずれか → §3.6 の該当ペアを参照。
2. **月次バジェットの上限は？** — $30 以下なら §7.3 の「低」列、$30-$100 なら「中」列、それ以上は「高」列。
3. **特殊要件はあるか？** — 透過 PNG が必要 → `gpt-image-1.5`、SVG パス必要 → `recraft-v4.1-pro`、4K 必要 → `gpt-image-2` / `gemini-3-pro-image` / `flux-pro-1.1-ultra`。
4. **API 制約を許容できるか？** — Gemini を使うなら chat-completions パスの実装が必要、xAI を使うなら `size` 不可、Seedream を使うなら最低 2K 出力。
5. **失敗時のフォールバック先は？** — 同カテゴリの 2 位 / 3 位を `failover` 配列に入れておき、404/400/429 で自動切り替え（AI SDK v6 / AI Gateway の `failover` 機能を使う）。

### 6.9 生成速度（レイテンシ）ランキング（D9）

![生成速度ランキング 1 枚あたり概算秒数 棒グラフ](./images/ai-gateway-image-models-2026/d9-latency-ranking.png)

| ランク | モデル | 1 枚生成時間 | 用途 |
|---|---|---|---|
| 1 | `prodia/flux-fast-schnell` | ~190ms | 大量プロト、UI モック |
| 2 | `bfl/flux-2-klein-9b` | <1 秒 | 案出し、ムードボード |
| 3 | `bfl/flux-pro-1.1` | ~2 秒 | T2I の標準 |
| 4 | `google/gemini-3.1-flash-image-preview` | ~3 秒 | multimodal の高速版 |
| 5 | `bytedance/seedream-5.0-lite` | ~3 秒 | リアル画像の高速版 |
| 6 | `bytedance/seedream-4.5` | ~6 秒 | フォトリアル本番 |
| 7 | `bfl/flux-2-pro` | ~8 秒 | 価格性能比のトップ |
| 8 | `bfl/flux-pro-1.1-ultra` | ~10 秒 | 4 MP 印刷品質 |
| 9 | `google/gemini-3-pro-image` | ~12 秒 | 4K + multimodal |
| 10 | `openai/gpt-image-2` | ~15 秒 | 日本語タイポ・4K |
| 11 | `recraft/recraft-v4.1-pro` | ~20 秒 | SVG ベクター |

> インタラクティブ UI（ユーザーが結果を待つ）では 5 秒以下が限界。10 秒を超える場合はストリーミング進捗表示か、`generateImage` を bg job に出して webhook で完了通知する設計が必要。

### 6.10 各モデル「強み 1 行サマリ」テーブル（D10）

| モデル | 1 行サマリ |
|---|---|
| `openai/gpt-image-2` | 日本語タイポ 99%、4K 16:9 ネイティブ、迷ったら第一候補 |
| `openai/gpt-image-1.5` | gpt-image-2 の廉価版、透過 PNG 必要なときの残し |
| `openai/gpt-image-1-mini` | 最も安い OpenAI 系、プロト用 |
| `bfl/flux-2-pro` | $0.05/枚で品質バランス最強、価格性能比トップ |
| `bfl/flux-2-max` | プロ向け production-ready、印刷物にも耐える |
| `bfl/flux-2-flex` | infographics / typography 特化、multi-ref 10 枚/14 MP |
| `bfl/flux-2-klein-9b` | <1 秒生成、プロト・ムードボード専用 |
| `bfl/flux-kontext-max` | キャラ一貫性編集の絶対王者、6 連続編集で cosine 0.92+ |
| `bfl/flux-kontext-pro` | Kontext Max の価格半額版、画質は同等 |
| `bfl/flux-pro-1.0-fill` | inpainting 専用、画像 + mask で部分修正 |
| `bfl/flux-pro-1.1` | $0.04 T2I、高速 |
| `bfl/flux-pro-1.1-ultra` | 4 MP 出力、印刷物の本命 |
| `bytedance/seedream-4.5` | 人物フォトリアル 9.4/10、毛穴・キャッチライト・歯 |
| `bytedance/seedream-5.0-lite` | 4.5 比 2-3× 高速、参照画像 + Web 検索 |
| `bytedance/seedream-4.0` | text + single/multi-image、汎用 |
| `recraft/recraft-v4.1-pro` | SVG ベクター直接出力、ロゴ・アイコンの本命 |
| `recraft/recraft-v4.1` | コスパ良いベクター、推奨デフォルト |
| `recraft/recraft-v3` | テキスト位置指定可、ER 図・ラベル多用に強い |
| `google/gemini-3-pro-image` | Nano Banana Pro、日本語 85% + 4K、chat-completions 専用 |
| `google/gemini-3.1-flash-image-preview` | Nano Banana 2、高速版 |
| `google/gemini-2.5-flash-image` | Nano Banana 旧、$0.039 で安価 |
| `xai/grok-imagine-image` | $0.02/枚、aspectRatio のみ、size 不可 |
| `prodia/flux-fast-schnell` | $0.001/枚、190ms、大量バッチ |

---

## 7. 参考リンク

### 公式

https://vercel.com/docs/ai-gateway/capabilities/image-generation

https://vercel.com/docs/ai-gateway/capabilities/image-generation/openai

https://vercel.com/docs/ai-gateway/capabilities/image-generation/ai-sdk

https://docs.bfl.ml/flux_2/flux2_overview

https://bfl.ai/models/flux-2

https://deepmind.google/models/gemini-image/pro/

https://ai.google.dev/gemini-api/docs/gemini-3

https://www.recraft.ai/blog/recraft-v4-1-more-beautiful-by-nature

https://www.byteplus.com/en/product/Seedream

### ベンチマーク / 解説

https://www.fotomanyagi.com/en/blog/flux-2-models-guide

https://picsart.com/blog/flux-models-comparison/

https://arxiv.org/html/2506.15742v2

https://help.apiyi.com/en/gpt-image-2-vs-gpt-image-1-5-upgrade-8-features-en.html

https://z-image.ai/blog/seedream-4-5-benchmark

https://www.aifreeapi.com/en/posts/nano-banana-pro-capabilities

https://www.renderforest.com/blog/seedream-4-5-ai-images-launch-renderforest

https://llm-stats.com/leaderboards/best-ai-for-image-generation

---

## 8. モデル ID クイックリファレンス

```text
# 日本語タイポ
openai/gpt-image-2
google/gemini-3-pro-image
bfl/flux-2-flex

# 人物・フォトリアル
bytedance/seedream-4.5
bfl/flux-2-max

# キャラ一貫性編集
bfl/flux-kontext-max
bfl/flux-kontext-pro

# multi-ref（10 枚〜）
bfl/flux-2-flex
google/gemini-3-pro-image

# ロゴ・SVG
recraft/recraft-v4.1-pro
recraft/recraft-v4.1

# inpaint
bfl/flux-pro-1.0-fill

# 高速
bfl/flux-2-klein-9b
bfl/flux-pro-1.1
prodia/flux-fast-schnell
```
