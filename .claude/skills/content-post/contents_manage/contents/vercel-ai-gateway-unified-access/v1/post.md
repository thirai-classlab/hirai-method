


## 1. これは何を解決するか

複数の AI プロバイダ（OpenAI / Google / Anthropic / BFL / xAI / ByteDance / Recraft …）を組み合わせて使うとき、ふつうは

- プロバイダごとに **個別 API キーの管理**
- プロバイダごとに **個別 SDK のセットアップ**
- プロバイダごとに **個別の請求・支払い**
- 新モデル追加のたびに **SDK バージョン更新・型定義書き換え**

が発生します。これがプロジェクトを増やすほど指数的に面倒になる。

[Vercel AI Gateway](https://vercel.com/docs/ai-gateway) は、**「1 本のゲートウェイ API キー + OpenAI 互換エンドポイント」だけで、上記すべてのプロバイダを横断的に叩ける**プロキシ型のレイヤーです。

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/vercel-ai-gateway-unified-access/d67ce174-architecture.png" alt="Vercel AI Gateway アーキテクチャ概念図" width="1536" height="1024">

---

## 2. 主要機能

### 2-1. 1 本のキーで全プロバイダ呼び出し

リクエストの `model` フィールドを `openai/gpt-image-2` から `bfl/flux-2-pro` に書き換えるだけで、別プロバイダのモデルに切り替わる。SDK の差し替えは不要。

```bash
curl https://ai-gateway.vercel.sh/v1/images/generations \
  -H "Authorization: Bearer $AI_GATEWAY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "openai/gpt-image-2", "prompt": "..."}'
```

### 2-2. モデル一覧の動的取得

```bash
GET /v1/models
```

で**ゲートウェイで現在叩けるモデル一覧**が返る。新プロバイダ追加 / 旧モデル削除がコード変更なしに反映される。

### 2-3. Observability（リクエストログ・レイテンシ監視）

Vercel ダッシュボード上でリクエスト数・トークン数・レイテンシ・エラー率を可視化。プロバイダ別にも分解できる。

### 2-4. レート制限 / Spending Limit

月額の最大支出を Vercel 側で設定可能。**意図しない高額請求を防げる**。

---

## 3. 課金モデル

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/vercel-ai-gateway-unified-access/9d1c7b72-pricing.png" alt="Vercel AI Gateway 課金モデル" width="1536" height="1024">

| 項目 | 課金 |
|------|------|
| AI Gateway 自体の利用料 | **無料** |
| 各プロバイダのモデル使用料 | **従量課金（プロバイダ料金そのまま）** |
| 月次無料枠 | **Hobby プランで $5/月相当**（参考値、最新は [Pricing](https://vercel.com/pricing) で確認） |
| 推奨プラン | **Pro プラン $20/月**（Spending Limit 設定推奨） |

> 💡 モデル毎の料金は [公式モデル一覧](https://vercel.com/docs/ai-gateway/models)で確認できる。例: `openai/gpt-image-2` は画像 1 枚あたり数セント、`bfl/flux-2-pro` は秒単位。

---

## 4. 対応プロバイダ（2026-04 時点）

- **OpenAI**: gpt-5 系 / gpt-image 系
- **Anthropic**: Claude 4.x 系
- **Google**: Gemini / Imagen 系
- **BFL (Black Forest Labs)**: FLUX 2 系 / Kontext 系
- **xAI**: Grok / Grok Imagine
- **ByteDance**: Seedream 系
- **Recraft**: v3 / v4 系
- **Prodia**: FLUX schnell 系

最新の対応プロバイダは `GET /v1/models` で動的取得すること。

---

## 5. 類似サービスとの比較

| サービス | 特徴 | 違い |
|----------|------|------|
| **Vercel AI Gateway** | OpenAI 互換 + Vercel エコシステム統合 | Vercel デプロイとの親和性が最高、画像生成も網羅 |
| **OpenRouter** | OSS 寄り、LLM 中心 | 画像生成プロバイダのカバレッジは Vercel が広い |
| **LiteLLM** | セルフホスト OSS、高カスタマイズ | 自前で運用する必要あり、observability は別途 |
| **Cloudflare AI Gateway** | キャッシュとログ寄り | プロバイダ集約より「リクエスト front」の役割 |

**判断基準**: Vercel にホストしている / これからホストする予定なら Vercel AI Gateway 一択。それ以外でも OpenAI 互換 API が欲しいだけなら最有力候補。

---

## 6. 向いてる / 向いてない

**向いてる**

- 個人・小規模チームのプロトタイピング
- Vercel デプロイのアプリで AI 機能を組み込む
- 複数プロバイダのモデルを比較・切替して試したい
- 画像生成で複数モデルを横断的に叩きたい
- spending を 1 箇所に集約してコスト管理したい

**向いてない**

- プロバイダ独自の高度な機能（OpenAI Realtime API のストリーミング音声など、ゲートウェイがまだ吸収していないもの）を最速で使いたい
- オンプレ / プライベートクラウドでセルフホストしたい
- ゲートウェイ自体の SLA より各プロバイダ直叩きの SLA を優先したい

---

## 7. 始め方の最短ルート

1. [Vercel](https://vercel.com/) にアカウント作成（無料）
2. ダッシュボード → AI Gateway → API Keys → `Create Key`
3. `vck_xxxxxxx` を `.env` に貼る
4. OpenAI 互換エンドポイント `https://ai-gateway.vercel.sh/v1/...` を叩くだけ

実装の具体例は関連記事「[【5分でできる】Claude Code × Vercel AI Gateway で「画像生成スキル」を作って、最新モデルを学習コストゼロで使い回す](/articles/claude-code-vercel-ai-gateway-image-generation)」を参照してください。

---

## 関連リンク

- [Vercel AI Gateway 公式ドキュメント](https://vercel.com/docs/ai-gateway)
- [対応モデル一覧](https://vercel.com/docs/ai-gateway/models)
- [Vercel AI SDK](https://sdk.vercel.ai/)
- [Vercel Pricing](https://vercel.com/pricing)
