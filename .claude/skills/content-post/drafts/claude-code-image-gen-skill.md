---
title: "Claude Code × Vercel AI Gateway で「画像生成スキル」を作って、最新モデルを学習コストゼロで使い回す"
type: knowledge
author: "平井拓真"
summary: "Claude Code で画像生成をするとき、モデルが変わるたびに使い方を覚え直すのが面倒。Vercel AI Gateway をラップした `/ai-image-gen` スキルを Claude 自身に作らせれば、モデル一覧は動的取得・APIキー1本で FLUX / Imagen / gpt-image / Seedream / Recraft などを横断的に呼べる。本記事ではスキル作成から実生成までの全手順と、実際に生成した RIRIFE 広告のサンプルを紹介する。"
thumbnail: ./article-thumb.png
---

# Claude Code × Vercel AI Gateway で「画像生成スキル」を作って、最新モデルを学習コストゼロで使い回す

> 📸 **サムネイル画像**: 記事冒頭に配置するヒーロー画像
> （`ai-image-gen` スキル自身で生成。生成済みの `article-thumb.png` を貼付）

---

## 解決したい課題

Claude Code で画像生成をしているエンジニアの「あるある」がこれです。

- **モデルが変わるたびに使い方を学習するのがだるい**
  画像生成 AI は数週間ごとに新モデルが出る。FLUX 2 が来た、Imagen 4 Ultra が来た、gpt-image-2 が来た。そのたびに API リファレンスを読み直し、SDK を入れ直し、認証を組み直す。
- **最新モデルをリリース当初に「学習コストゼロ」で気軽に試したい**
  業務でガッツリ使うわけじゃない。広告イラスト1枚、ブログのアイキャッチ1枚、社内資料の差し込み1枚。そのために毎回プロバイダの SDK を読み込みたくない。

この記事のゴールは、**「Claude Code から `/ai-image-gen "<指示>"` で最新モデルを叩ける」状態を 30 分で作る**ことです。

---

## 解決アプローチ — Vercel AI Gateway を Claude スキルでラップする

このアプローチを支える 2 つの Vercel プロダクトをまず押さえておきます。

### Vercel AI Gateway とは

[Vercel AI Gateway](https://vercel.com/docs/ai-gateway) は、**複数の AI プロバイダ（OpenAI / Google / Anthropic / BFL / xAI / ByteDance / Recraft …）のモデルを 1 本の API キー + OpenAI 互換エンドポイントで叩ける統一ゲートウェイ**です。

- プロバイダ毎の SDK 契約・キー管理が不要（Vercel に請求も集約）
- モデル切り替えは「リクエストの `model` フィールド」を書き換えるだけ
- 新プロバイダ・新モデルがゲートウェイに追加されると即日呼べる
- 月額 spending limit / レート制限 / observability も Vercel 側で完結

つまり「画像生成の **Cloudflare** や **Stripe** のような立ち位置」を担うレイヤーです。

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

> 📸 **キャプチャ①**: `ai-sdk` インストール完了画面
> （3 つの選択を済ませて成功メッセージが出ている状態）

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

Claude Code は `ai-sdk` スキルの知識を参照しながら、

- `scripts/gen.mjs`（CLI 本体）
- `SKILL.md`（スキル仕様）
- `.env.example`
- モデル一覧取得 / 画像生成 / 画像編集の3コマンド

を一気に作ってくれます。

> 📸 **キャプチャ②**: Claude Code がスキルを生成中 / 生成完了したターミナル画面
> （ファイル一覧と完了サマリが見える状態）

---

### Step 4 — Vercel で AI Gateway の API キーを発行

スキルが作られている**裏で並行作業**するのが効率的です。

1. [Vercel](https://vercel.com/) にアカウント作成（無料）
2. ダッシュボードから `AI Gateway` → `API Keys` へ
3. `Create Key` で `vck_xxxxxxx` 形式のキーを発行

> 📸 **キャプチャ③**: Vercel の AI Gateway 管理画面で API キーを発行した直後の画面
> （`vck_...` のキー値はマスク or 一部隠す）

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

> 📸 **キャプチャ④**: Claude Code に `/ai-image-gen` を実行している会話画面
> （プロンプト入力 → 生成完了の応答が見える状態）

---

## 成果物 — 実際に生成された RIRIFE 広告

たった上記のプロンプトから、こちらの広告イラストが生成されました。

> 📸 **画像⑤**: 生成された広告画像
> ファイルパス: `RIRIFE広告/output/rirife-ad-20260425-235436-1.png`
> （記事に貼り付ける）

要素を見てみると、

- 引越し直後の若いカップルが笑顔で新生活を楽しんでいる構図
- スマホ画面に RIRIFE アプリの UI モック（マップ・クーポン・記事タイル）
- 「新生活をもっと快適に」というキャッチコピー
- クーポン札 / マップピン / ナレッジアイコン / ハザードマップマーク
- App Store / Google Play のダウンロードバッジ

…と、**広告として必要な要素が一発で揃っています**。

これを Photoshop でゼロから作ったら半日コース、外注したら数万円。それが「サイトを読んで広告を作って」で完結します。

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

## まとめ — 画像生成モデルのトレンドが変わっても、最新モデルを常に Claude Code から触れる

この構成のキモは **「スキル自体を Claude に作らせる」** ことと、**「モデル一覧をゲートウェイから動的に引く」** こと。この 2 点を押さえると、

- 新モデルが出た日 → 即試せる
- プロバイダ仕様変更 → ゲートウェイ側が吸収
- 自分で書くコードは `.env` の 1 行だけ

という状態になります。

画像生成 AI のトレンドはこれからも変わり続けます。**追いかけるのではなく、追いかけなくていい仕組みを作る**のが最短ルートです。

---

## 関連リンク

- [Vercel AI Gateway 公式ドキュメント](https://vercel.com/docs/ai-gateway)
- [Claude Code Skills](https://docs.claude.com/en/docs/claude-code/skills)
- [Vercel AI SDK](https://sdk.vercel.ai/)
