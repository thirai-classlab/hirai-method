
## この記事でできる成果物

最終的に、Claude Code でこう打つだけで画像が出力できるようになります。

```
/ai-image-gen
gpt-image2で高品質なRIRIFEのイラスト広告を作成してください。

classlabのサイトからサービスは理解してください。
```

すると、Claude が

1. ClassLab のサイトをフェッチして RIRIFE サービスの内容を理解
2. ターゲット・ブランドトーンに合わせたプロンプトを英語で組み立て
3. Vercel AI Gateway 経由で `openai/gpt-image-2` を叩く
4. ローカルに PNG を保存

を全部勝手にやってくれて、こちらが手に入ります。

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/9666f025-rirife-ad-result.png" alt="RIRIFE 広告イラスト（生成結果）" width="1024" height="1536">

引越し直後の若いカップル / RIRIFE アプリの UI モック / 「新生活をもっと快適に」キャッチ / クーポン札 / マップピン / ハザードマップ / App Store・Google Play バッジ — **広告として必要な要素が一発で揃った 1 枚が、入力 3 行から生成されました**。

これを Photoshop でゼロから作ったら半日コース、外注したら数万円。それが「サイトを読んで広告を作って」で完結する状態を、本記事ではこのあと **5 分のセットアップ** で作ります。

---

## 解決したい課題

Claude Code で画像生成をしているエンジニアの「あるある」がこれです。

- **モデルが変わるたびに使い方を学習するのがだるい**
  画像生成 AI は数週間ごとに新モデルが出る。FLUX 2 が来た、Imagen 4 Ultra が来た、gpt-image-2 が来た。そのたびに API リファレンスを読み直し、SDK を入れ直し、認証を組み直す。
- **最新モデルをリリース当初に「学習コストゼロ」で気軽に試したい**
  業務でガッツリ使うわけじゃない。広告イラスト1枚、ブログのアイキャッチ1枚、社内資料の差し込み1枚。そのために毎回プロバイダの SDK を読み込みたくない。

この記事のゴールは、**「Claude Code から `/ai-image-gen "<指示>"` で最新モデルを叩ける」状態を 5 分で作る**ことです。

---

## 解決アプローチ — Vercel AI Gateway を Claude スキルでラップする

このアプローチを支える 2 つの Vercel プロダクトをまず押さえておきます。

### Vercel AI Gateway とは

Vercel AI Gateway は、**複数の AI プロバイダ（OpenAI / Google / Anthropic / BFL / xAI / ByteDance / Recraft …）のモデルを 1 本の API キー + OpenAI 互換エンドポイントで叩ける統一ゲートウェイ**です。

詳細はこちらのナレッジにまとめています:

https://classlab-weekly-news.vercel.app/knowledge/vercel-ai-gateway-unified-access

- プロバイダ毎の SDK 契約・キー管理が不要（Vercel に請求も集約）
- モデル切り替えは「リクエストの `model` フィールド」を書き換えるだけ
- 新プロバイダ・新モデルがゲートウェイに追加されると即日呼べる
- 月額 spending limit / レート制限 / observability も Vercel 側で完結

つまり「画像生成の **Cloudflare** や **Stripe** のような立ち位置」を担うレイヤーです。

#### 課金について（重要）

Vercel AI Gateway は **AI Gateway 自体の利用料は無料**ですが、**ゲートウェイ経由で叩いた各プロバイダのモデル使用料は従量課金**で発生します。

- 課金単位は **モデルごとに異なる**（gpt-image-2 は画像 1 枚あたり数セント、FLUX 系は秒単位など。最新料金は [公式モデル一覧](https://vercel.com/docs/ai-gateway/models)を参照）
- 支払いは **Vercel 側に集約**される（プロバイダ個別契約の必要なし）
- **Hobby プラン無料枠 $5/月相当**（2026 年時点の参考値、最新値は Vercel の Pricing ページで確認）が付与され、軽い検証ならそこに収まる
- 本番運用や大量生成を行うなら **Pro プラン（$20/月）+ Spending Limit 設定**が推奨。ダッシュボードで月額上限を設定しておけば、想定外の高額請求を防げる

> 💡 「画像 1 枚生成して試してみたい」程度なら Hobby プラン無料枠で十分収まります。本記事の RIRIFE 広告生成 1 回も無料枠の範囲内です。

### Vercel AI SDK とは

[Vercel AI SDK](https://sdk.vercel.ai/) は、**LLM / 画像生成 / 音声などを TypeScript から叩くための統一クライアント SDK**。AI Gateway と組み合わせると、`generateText` や `generateImage` のような共通インタフェースに provider 文字列（例: `openai/gpt-image-2`）を渡すだけでプロバイダ横断の呼び出しが書けます。

今回は CLI（`scripts/gen.mjs`）から直接 OpenAI 互換エンドポイントを叩くシンプル構成ですが、Web アプリやエージェントに組み込む場合は AI SDK 側が便利です。Claude が今回のスキルを生成するときの **設計知識ソース**として `ai-sdk` 公式スキルを使います（後述 Step 2）。

### 上記に Claude Code の Skill を被せると

- モデル一覧は **ゲートウェイから動的取得** → 新モデルが追加されても即座に使える
- API キーは **`.env` に1本** → プロバイダごとの認証管理から解放
- スキル自体は **Claude に作らせる** → 自分で TypeScript を書かない

つまり「最新モデルが出た当日に、ゼロ学習コストで試せる」状態になります。

---

## 手順

### Step 1 — Skill.sh をインストール

Claude Code のスキル管理 CLI である `skill.sh` を入れます。

```bash
curl -fsSL https://skill.sh/install | bash
```

`skill.sh` の詳細（コマンド一覧 / インストール時の選択肢 / 運用上のコツ）はこちらのナレッジにまとめています:

https://classlab-weekly-news.vercel.app/knowledge/skillsh-claude-code-npx-skills-add-1-cli

---

### Step 2 — `ai-sdk` スキルをインストール

Vercel AI Gateway 連携の前提となる **公式スキル `ai-sdk`** を直接入れます。

```bash
npx skills add https://github.com/vercel/ai --skill ai-sdk
```

実行すると以下 3 つの対話プロンプトが順に出るので選択していきます。

| # | プロンプト | 選ぶもの | 補足 |
|---|-----------|---------|------|
| 1 | どのツールに入れるか | **Claude Code** | Cursor / Windsurf 等が並ぶが今回は Claude Code を選択 |
| 2 | スコープ（インストール先） | **Global** または **Project** | 普段使い回したいなら Global（`~/.claude/skills/`）。特定リポジトリだけで使うなら Project（`.claude/skills/`） |
| 3 | インストール方式 | **Symlink** | コピーではなく shimlink を張る方式。リポジトリ更新を `git pull` だけで反映できるので推奨 |

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/44c0f0e7-u9b3l2hd_image.png" alt="image" width="699" height="187">

---

### Step 3 — Claude にスキル本体を作ってもらう

ここが本記事の肝です。**自分で書きません。Claude に作らせます。**

Claude Code に以下のように指示します。

```
/ai-sdk
claudeスキルを作成してください。

vercel ai-gatewayを利用して画像生成を行うスキル
モデルは動的に使用可能
.envにAPIキーを設定します
```

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/a8038ff1-0tmgdbal_image.png" alt="image" width="640" height="155">

Claude Code は `ai-sdk` スキルの知識を参照しながら、

- `scripts/gen.mjs`（CLI 本体）
- `SKILL.md`（スキル仕様）
- `.env.example`
- モデル一覧取得 / 画像生成 / 画像編集の3コマンド

を一気に作ってくれます。

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/2446f1dd-wbry97mo_image.png" alt="image" width="883" height="372">
---

### Step 4 — Vercel で AI Gateway の API キーを発行

スキルが作られている**裏で並行作業**するのが効率的です。

1. [Vercel](https://vercel.com/) にアカウント作成（無料）
2. ダッシュボードから `AI Gateway` → `API Keys` へ
3. `Create Key` で `vck_xxxxxxx` 形式のキーを発行

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/ea5384b3-tnmbynse_image.png" alt="image" width="790" height="408">
*キーは削除済みです

---

### Step 5 — `.env` に API キーを設定

Step 3 で生成されたスキルフォルダ（例: `~/.claude/skills/ai-image-gen/`）の `.env` に貼ります。

```env
AI_GATEWAY_API_KEY=vck_xxxxxxxxxxxxxxxxxx
```

---

### Step 6 — 生成を試す

ここからが本番。Claude Code に話しかけるだけ。

```
/ai-image-gen
gpt-image2で高品質なRIRIFEのイラスト広告を作成してください。

classlabのサイトからサービスは理解してください。
```

スキルは内部で

1. `classlab.co.jp` を WebFetch して RIRIFE の特徴を理解
2. モデル一覧から `openai/gpt-image-2` を選択
3. プロンプトを最適化して生成
4. ローカルに PNG 保存

を全部やってくれます。

<img src="https://d2f75plg0t6qwk.cloudfront.net/tech_article/claude-code-vercel-ai-gateway-image-generation/12e65ba6-ygiphshk_image.png" alt="image" width="760" height="158">

実行結果は本記事冒頭で示した RIRIFE 広告のとおりです。

---

## なぜこの構成が強いのか

### 1. モデルが変わっても破綻しない

スキル本体は Vercel AI Gateway の **OpenAI 互換 `/v1/images/generations` エンドポイント**を叩いているだけです。

```bash
node scripts/gen.mjs models
```

を実行すれば、その瞬間にゲートウェイで使える全モデルが返ってきます。新モデルが追加されたら `--model <新ID>` を渡すだけ。**スキル本体の改修は不要**です。

### 2. プロバイダ認証から解放される

OpenAI / Google / BFL に個別契約してキーを管理する代わりに、**Vercel AI Gateway の1本のキー**で全プロバイダを横断できます。請求も Vercel に集約されます。

### 3. プロンプト設計を Claude に任せられる

「RIRIFE の広告を作って」と言うだけで、Claude が

- サービス内容を Web から理解
- ターゲットとブランドトーンを整理
- 英語の詳細プロンプトに翻訳
- モデル特性に合わせたパラメータ選択（`size`, `quality`）

までやってくれます。プロンプトエンジニアリングの学習コストもゼロです。

---

## 応用 — 自律的に 300 パターン生成してみた

`/ai-image-gen` を 1 枚生成だけで終わらせるのはもったいないので、**Claude Code に WebSearch とコンテキスト探索をさせて、自律的に 300 パターンほど生成させてみました**。

「業界・テーマ・テイスト」を切り替えながら、Claude が自分でプロンプトを組み立てて生成 → 保存 → 次のテーマへと連続実行する流れです。

生成結果のサムネイル一覧:

https://thumbnail-gallery-xi.vercel.app/

人手では発想しないテイストの組み合わせが大量に出てくるので、**「ブレストの広さを AI に任せて、選定だけ人間がやる」** というワークフローが現実的に回ることが確認できました。Vercel AI Gateway の課金は 300 枚でも数ドル程度に収まる範囲です。

---

## まとめ — 画像生成モデルのトレンドが変わっても、最新モデルを常に Claude Code から触れる

この構成のキモは **「スキル自体を Claude に作らせる」** ことと、**「モデル一覧をゲートウェイから動的に引く」** こと。この 2 点を押さえると、

- 新モデルが出た日 → 即試せる
- プロバイダ仕様変更 → ゲートウェイ側が吸収
- 自分で書くコードは `.env` の 1 行だけ

という状態になります。

画像生成 AI のトレンドはこれからも変わり続けます。**追いかけるのではなく、追いかけなくていい仕組みを作る**のが最短ルートです。

---

## 関連リンク

### 関連ナレッジ

https://classlab-weekly-news.vercel.app/knowledge/vercel-ai-gateway-unified-access

https://classlab-weekly-news.vercel.app/knowledge/skillsh-claude-code-npx-skills-add-1-cli

### 公式ドキュメント

https://vercel.com/docs/ai-gateway

https://docs.claude.com/en/docs/claude-code/skills

https://sdk.vercel.ai/
