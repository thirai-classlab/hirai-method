---
title: "【claudeCode基礎学習】第1回 環境構築 — 最大の難関を30分で越える完全ガイド"
slug: claude-code-01-environment
type: tech_articles
subtype: handson
category: claude-code
thumbnail: ./images/chapters/ch01-hero.png
author: "平井拓真"
source: "cc研修/01-environment.md"
---

> **この章のゴール**
> - ターミナル（パソコンに文字で命令を出す画面）が何をする道具か分かる
> - VSCode（コードを書く専用エディタ）を入れて、ターミナルから操作できるようになる
> - `claude` というコマンドが起動できる状態にする

**所要時間：約30分**

---

## はじめに：環境構築は最大の難関、その後はだいたい天国

正直に言うと、Claude Code を使い始めるとき、**一番つまずきやすいのが「環境構築」** なんですよ。

黒い画面が怖い、英語のコマンドが何を意味してるか分からない、ちゃんと入れたはずなのに動かない…ここで「もういいや」となる人、本当に多いです。

**でも安心してください。** ここさえ越えてしまえば、あとはほぼ天国です。なぜかというと、**Claude Code が動き始めた瞬間から、残りのこまかい設定はぜんぶ Claude Code 本人にお願いできるから**。「設定ファイルってどこにあるの？」とか「便利なショートカット教えて」みたいな質問も、起動してさえいれば全部やってくれます。

つまり、**環境構築は登山で言う「ベースキャンプ到着」**。ここまで来れたら、あとは Claude Code というシェルパ（道案内人）が先導してくれるんです。今日 30 分、頑張りましょう。

---

## 1. ターミナル超入門

### 1-1. ターミナルって何？

ひとことで言うと、**ターミナルは「パソコンの厨房に直接オーダーを通す窓口」** です。

普段の操作は「レストランの客席」と一緒で、メニュー（アイコン）を見て、ウェイター（マウス操作の画面）に「これください」と指さしで頼んでますよね。それで全然いいんです。ただ、慣れた料理人なら、厨房に直接「今日のおすすめ全部、塩多めで」と一言で済ませた方が圧倒的に速い。**それがターミナルです。**

![](./images/inline/ch01-m1.png)

ちなみに「ターミナル」「シェル」「コマンドライン」「コンソール」「黒い画面」、たぶん一度は耳にしたことあると思いますが、**最初のうちは全部だいたい同じものだと思ってOK** です。厳密には微妙に違うんですが、その違いを気にし始めるのは、もっと先の話。

### 1-2. なぜ Claude Code はターミナルから使うのか

「いやでも、画面ぽちぽちで使えた方が楽じゃん？」と思いますよね。わかります。でも、**Claude Code がターミナルから使うのにはちゃんと理由がある** んです。

- **速い** — マウスでカチカチやるより、文字でバーンと打った方が早い。慣れると本当に倍以上違います
- **記録が残る** — 何をしたかが文字で残るので、明日の自分が「あれ、昨日なに作業したっけ？」とならない
- **再利用しやすい** — 一度打ったコマンドはコピペで何度でも使える。あとで自動化（スクリプト化）もしやすい
- **Claude Code と相性がいい** — Claude Code はファイルを読み書きしたり、いろんな道具を呼んだりするのが本業なので、**最初からその「作業場」にいた方が話が早い** んですよ

### 1-3. 最低限これだけ覚えるコマンド

「コマンド」は要するに、**パソコンに文字で出す命令** のことです。最初は **6 個だけ** で十分。料理で言うと「包丁・まな板・フライパン・お湯・塩・コショウ」みたいなもの。これさえあれば、だいたい何とかなります。

| コマンド | やること | 例 |
|---|---|---|
| `pwd` | 「いま自分どこにいる？」を確認（print working directory） | `pwd` → `/Users/yourname/work` と表示される |
| `ls` | 「このフォルダに何が入ってる？」を見る（list） | `ls` |
| `cd` | フォルダを移動する（change directory） | `cd Documents`（中に入る）／ `cd ..`（一つ上へ戻る） |
| `mkdir` | 新しいフォルダを作る（make directory） | `mkdir my-project` |
| `cat` | このファイルの中身をのぞく | `cat README.md` |
| `clear` | 画面が散らかったので片付ける | `clear` |

 **試してみる**：ターミナルを開いて、`pwd` → `ls` → `cd Documents` → `ls` → `cd ..` を順に打ってみてください。**「今どこにいて、何があるか」を確認しながら歩く** イメージです。迷子になりかけたら `pwd` で現在地を確認。マップ的に使えます。

### 1-4. macOS と Windows での違い

ターミナルの開き方は OS（お使いのパソコン）によってちょっと違います。

| OS | ターミナルの開き方 |
|---|---|
| **macOS** | Spotlight（画面右上の虫眼鏡、`+Space`）で「ターミナル」と検索 → Enter |
| **Windows** | スタートメニューから「PowerShell」または「Windows Terminal」を起動 |
| **Linux** | `Ctrl+Alt+T`（みなさんは詳しいと思うので説明は省きます） |

 **おすすめのターミナルアプリ**：標準のものでもいいんですが、**ちょっといいやつに乗り換えると毎日のテンションが上がります**。プロ仕様の包丁を使うようなものです。

- **[Warp](https://www.warp.dev/)** — 補完が賢く、見た目もきれい。動画でもよく推奨されてます
- **[iTerm2](https://iterm2.com/)** （macOS用） — 定番。タブで複数画面に分けたり、左右に並べたりが得意
- **[Windows Terminal](https://aka.ms/terminal)** — Windows ならまずこれ

---

## 2. VSCode（Visual Studio Code）のインストール

VSCode は、Microsoft が無料で配ってる **エディタ（コードを書くためのソフト）** です。例えるなら **「カスタマイズし放題の作業デスク」**。何もない机で作業を始めることもできるんですが、引き出しを増やしたり、ライトを付けたり、付箋を貼ったりして、**自分仕様にどんどん化けさせていける机** だと思ってください。Claude Code とも相性抜群です。

>  **「メモ帳と何が違うの？」**：VSCode は、メモ帳のすごい版です。文字に色を付けてくれたり、間違いを指摘してくれたり、フォルダごとファイルをまとめて開けたり。**作業効率が体感で 5 倍くらい変わります**。

### 2-1. インストール手順

1. <https://code.visualstudio.com/download> にアクセス
2. お使いの OS 用のインストーラー（セットアップ用ファイル）をダウンロード
3. ダウンロードしたファイルをダブルクリック → 表示される指示通りに「次へ」を押していけばOK

「次へ」「次へ」「完了」。**ここは10分もかからないはず** です。

### 2-2. 初回起動時の設定

 **やっておくと幸せな設定**：これやっておかないと、あとで「なんでだー！」ってなりがちです。

| 項目 | 設定 |
|---|---|
| 日本語化 | 拡張機能（追加機能をインストールできるストア）で「Japanese Language Pack」を検索してインストール |
| ターミナル統合 | 上部メニュー `表示 → ターミナル` をクリック（または `Ctrl+\`` / `Cmd+\``）すると、VSCode の中にターミナルが出てくる |
| フォルダ単位で開く | プロジェクトはフォルダごと開く（`ファイル → フォルダーを開く...`） |

### 2-3. VSCode と Claude Code の関係

VSCode と Claude Code の関係は、**「作業デスク（VSCode）の上に、賢い助手（Claude Code）を呼んで一緒に作業する」** イメージです。机の上に書類を広げて、横で助手がメモを書いたり、書類を運んできたり、コーヒーを淹れたり（は、しません）。

![](./images/inline/ch01-m2.png)

**使い方の典型**：
1. VSCode で作業したいフォルダを開く
2. 内蔵ターミナル（VSCode の中にあるターミナル）で `claude` と打って起動
3. Claude Code が編集してくれた変更点が、差分表示（変更前と変更後を見比べる画面）として VSCode 上に出る
4. 横で別のファイルを開きながら確認できる

エディタとターミナルを行ったり来たりしなくていいので、**慣れるとこれ無しでは生きていけなくなります**。

---

## 3. Claude Code のインストール（ここが本日のラスボス）

さあ、ここが本日のメインイベント、**ラスボス戦** です。とは言っても、いまの Claude Code はインストーラー（セットアップ用ファイル）一発で入るのでだいぶ楽になりました。1年前はもっと険しかったんですよ…時代の進化に感謝。

### 3-1. 前提：Node.js を入れておく（おすすめ）

Node.js は、**たくさんのアプリの「土台」になっているプログラム実行環境（プログラムを動かすための仕組み）** です。Claude Code 本体には必須ではないんですが、**入れておくとトラブったときの逃げ道が増える** ので、入れておくのを強くおすすめします。**保険みたいなもの** です。

1. <https://nodejs.org/ja/download> にアクセス
2. **LTS 版**（Long Term Support の略。**長く安定して使える、いわゆる「無難な版」**）を選んでダウンロード
3. インストールが終わったら、ターミナルでちゃんと入ったか確認：
   ```bash
   node --version
   ```
   `v22.x.x` のような数字が表示されたら成功です。

`command not found`（そんなコマンド知らない、という意味のエラー）と言われた場合は、**ターミナルを一度閉じて開き直してから** もう一回試してください。パソコンが「あ、新しい道具が入ったんだ」と気づくのにタイムラグがあるんですよ。

### 3-2. Claude Code 本体のインストール

公式が推奨する方法を OS 別に紹介します。**自分の OS のところだけ読めばOK** です。

#### macOS /  Linux / WSL

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

> このコマンドは「公式サイトからセットアップ用ファイルをダウンロードして、そのまま実行する」という意味です。1行で済むよう公式が用意してくれた魔法の呪文だと思ってください。

または Homebrew（macOS でアプリをコマンド経由でインストール・管理できるツール）が入っていれば：
```bash
brew install --cask claude-code
```

#### Windows（PowerShell）

```powershell
irm https://claude.ai/install.ps1 | iex
```

または WinGet（Windows 公式のアプリ管理ツール）：
```powershell
winget install Anthropic.ClaudeCode
```

#### 確認

ちゃんと入ったかチェック：

```bash
claude --version
```

ここでバージョン番号がパッと表示されれば、**もう8割勝ったも同然** です。

>  **注：古い情報に注意**
> ネット検索すると `npm install -g @anthropic-ai/claude-code` という古い方法が出てくることがありますが、**今はおすすめしません**。Node.js のバージョンに振り回されるトラブルがあるので、上に書いた方法を使ってください。「2024年の情報」とか見たら、ちょっと疑った方がいい世界です（このツール、進化が早すぎるんですよ本当に）。

### 3-2-1. インストール出力の読み方と対処（macOS / zsh 実例）

実際にコピペで実行すると、ターミナルにずらずらと文字が流れてきて「これ大丈夫なやつ？」となりがちです。**1 行ずつ何が起きているか + 出たらどうするか** を解説します。

#### ① まず `claude` を叩いてみる → 「そんなコマンド知らない」と怒られる

```bash
$ claude
zsh: command not found: claude
```

**意味**: インストール前なので当然「`claude` というコマンドはこの PC のどこにも無い」と zsh が返してきます。**これは正常** です。慌てなくて大丈夫。

#### ② インストールスクリプトを実行する

```bash
$ curl -fsSL https://claude.ai/install.sh | bash
Setting up Claude Code...

✓ Claude Code successfully installed!

  Version: 2.1.119
  Location: ~/.local/bin/claude

  Next: Run claude --help to get started
```

**読み解き**:

| 行 | 意味 |
|---|---|
| `Setting up Claude Code...` | セットアップ進行中（数十秒待つ） |
| `✓ Claude Code successfully installed!` | **緑のチェックが出たら成功確定** |
| `Version: 2.1.119` | 入った Claude Code のバージョン番号 |
| `Location: ~/.local/bin/claude` | 本体の実行ファイルがどこに置かれたか（**この後の PATH 設定で重要**） |
| `Next: Run claude --help` | 次にやることのヒント |

#### ③ ⚠ Setup notes：PATH が通っていない警告が出たら必ず対処

```bash
⚠ Setup notes:
  ● Native installation exists but ~/.local/bin is not in your PATH. Run:

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**意味**: 「Claude Code は入ったが、ターミナルからは `claude` と打っても見つけられない」状態です。`~/.local/bin/claude` という置き場所を、**zsh の検索パス (PATH) に追加**する必要があります。

**そのまま貼り付けて実行すれば OK**:

```bash
$ echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**1 行コマンドの内訳**:

- `echo '...' >> ~/.zshrc` — zsh が起動するたびに読む設定ファイル `~/.zshrc` の **末尾に 1 行追記**
  - 追記内容: `export PATH="$HOME/.local/bin:$PATH"` =「PATH の先頭に `~/.local/bin` を足す」設定
- `&&` — 前のコマンドが成功したら次に進む
- `source ~/.zshrc` — **今開いているターミナルに即座に設定を反映**（普段は再ログインで反映されるところを、その場で読み込ませる）

> この警告が **出なかった場合は ③ の作業は不要** です。すでに PATH に入っているということ。

#### ④ もう一度 `claude` を実行 → ASCII アート + 初回セットアップが始まる

```bash
$ claude
Welcome to Claude Code v2.1.119
…
    *                                       █████▓▓░
                                 *         ███▓░     ░░
            ░░░░░░                        ███▓░
   ░░░░░░░░░░░░░░░░░░░    *
…

 Let's get started.
```

**ASCII アート（` █ ` で描かれたロゴ）が出たらインストール完全成功** です。これ以降は対話式のセットアップウィザード。

#### ⑤ テーマ選択（見た目を決める）

```bash
 Choose the text style that looks best with your terminal
 To change this later, run /theme

 ❯ 1. Auto (match terminal)
   2. Dark mode ✓
   3. Light mode
   4. Dark mode (colorblind-friendly)
   5. Light mode (colorblind-friendly)
   6. Dark mode (ANSI colors only)
   7. Light mode (ANSI colors only)
```

**選び方**:

- **迷ったら `1. Auto`**（ターミナル本体の配色に合わせてくれる、一番無難）
- ターミナルを暗い背景にしている人は `2. Dark mode`
- 色弱配慮版 (`4` / `5`) や、ANSI 16 色オンリー (`6` / `7`) も用意されている
- **あとから `/theme` コマンドで変更可能** なので、悩まず決めて OK

矢印キーで動かして Enter で確定。

#### ⑥ シンタックステーマの確認

```bash
  Syntax theme: Monokai Extended (ctrl+t to disable)
```

コードの色付け（シンタックスハイライト）が **Monokai Extended** で表示される、というお知らせ。**邪魔なら `Ctrl + T` でオフにできます**。デフォルト (Monokai) で問題ないので、特に何もしなくて OK。

#### ⑦ ログイン方法の選択（重要）

```bash
 Select login method:

 ❯ 1. Claude account with subscription · Pro, Max, Team, or Enterprise

   2. Anthropic Console account · API usage billing

   3. 3rd-party platform · Amazon Bedrock, Microsoft Foundry, or Vertex AI
```

**選び方ガイド**:

| 選択肢 | こんな人 |
|---|---|
| **1. Claude account with subscription** | **個人で Pro / Max / Team / Enterprise の月額プランに加入している人**（一番多い、迷ったらコレ） |
| **2. Anthropic Console account** | サブスクではなく **API 使用量で従量課金** したい人。Console (console.anthropic.com) で発行したクレジットから引かれる |
| **3. 3rd-party platform** | 会社が **AWS Bedrock / Microsoft Foundry / Google Vertex AI** 経由で Anthropic API を契約しているケース |

選んで Enter → ブラウザが開いてログイン → 自動でターミナルに戻ってくる。**ここまで来たら本当にゴール** です。

> ログインボタンを押したのにブラウザが開かない場合は、ターミナルに URL がコピペ用に表示されるので、それを手動でブラウザに貼り付けてください。

---

### 3-3. VSCode 拡張のインストール

VSCode と Claude Code をもっと連携させたいときの追加機能（拡張機能）です。

1. VSCode の左サイドバーにある **拡張機能** タブ（ブロック崩しっぽい四角いアイコン）をクリック
2. 上の検索欄に `Claude Code` と入力
3. **Anthropic 公式** のものをインストール（似たやつもあるので、必ず公式マークを確認してください）
4. インストールが終わったら、コマンドパレット（VSCode の中の検索メニュー、`Ctrl + Shift + P` または Mac は `Cmd + Shift + P` で出る）から「Claude Code: Open in New Tab」を選ぶ

### 3-4. JetBrains 系IDE（IntelliJ / PyCharm / WebStorm などの開発ソフト）

[JetBrains Marketplace](https://plugins.jetbrains.com/plugin/27310-claude-code-beta-) からプラグイン（追加機能）をインストール → IDE を再起動。**JetBrains 派の人もちゃんと対応されてます**、ご安心を。

---

## 4. ログインと初回起動

### 4-1. アカウント

Claude Code は **Anthropic アカウント**（Claude を作っている会社のアカウント）または **Claude.ai 有料プラン**（普段ブラウザで Claude と会話できるサービスの有料版）で使います。

| プラン | できること | 月額目安 |
|---|---|---|
| **Free / Pro ($20)** | 軽く試したい人向け | $0 / $20 |
| **Max ($100)** | 個人で日常的にしっかり使いたい人 | $100 |
| **Max 20× ($200)** | 一日中ぶん回したいヘビーユーザー | $200 |
| **API課金** | プログラムから自動で呼び出す用 | 使った分だけ |

>  **個人で使うときのおすすめ**：まず Pro で試して、本格化したら Max。**「ジムの月会費くらいで、毎日エンジニア一人分が手に入る」** と思えば、人によってはコスパ感がバグります。

### 4-2. 初回起動

```bash
# 練習用フォルダを作って、その中に入る
mkdir ~/work/cc-test && cd ~/work/cc-test

# Claude Code を起動
claude
```

> 上のコマンドの `&&`（前のコマンドが成功したら次もやって）と、`~`（チルダ。自分のホーム＝ユーザーフォルダを指す記号）はよく出てくるので覚えておくと便利です。

初回はブラウザが勝手に開いて「ログインしてね」と言われます。Anthropic アカウントでログインを完了すると、ターミナルにチャット画面が現れます。**ここまで来たらゴール目前**。

### 4-3. 動作確認

起動した状態で、まずはお決まりのあいさつから。

```text
このフォルダは何ですか?
```

```text
hello.txt というファイルを作って「Hello, Claude Code!」と書いてください
```

ファイルが作成されたら、**おめでとうございます、本日のラスボス撃破です** 。終了は **`Ctrl + D` キー** または `/exit` と打って Enter。

---

## 5. 環境構築チェックリスト

ここまで来たら、振り返りのチェックリスト。**全部  になったら、本当の意味で「天国編」スタート** です。

![](./images/inline/ch01-m3.png)

| | チェック項目 | 確認方法 |
|---|---|---|
|  | ターミナルが開ける | アプリを開けばOK |
|  | VSCode が起動する | アプリを開けばOK |
|  | Node.js が入っている | ターミナルで `node --version` |
|  | Claude Code が入っている | ターミナルで `claude --version` |
|  | ログインできた | `claude` で起動して質問できる |
|  | ファイル作成テスト OK | 「hello.txtを作って」が成功する |

---

## 6. つまずきポイント（あるあるFAQ）

ここからは「あ、それ俺もなった」をまとめておきます。**みんなだいたい同じところで詰まる**ので、安心してください。

| 症状 | 対処 |
|---|---|
| `command not found: claude` と出る | パスが通っていない（パソコンがまだ `claude` の居場所を覚えてない状態）です。**ターミナルを一度閉じて、新しく開き直す** だけで9割解決します |
| 日本語が文字化け | ターミナルの文字コード（文字を表示するときの規格）を **UTF-8**（世界共通の文字の書き方）に。Warp や Windows Terminal は最初から UTF-8 なので OK |
| Windows でうまく動かない | Git for Windows（Git というファイル履歴管理ツールの Windows 版）を入れる（`git-scm.com/download/win`）。それでもダメなら WSL2（Windows の中で Linux を動かす仕組み）を試す |
| 起動した瞬間落ちる | Node.js のバージョンが古すぎる説。**v22 LTS 以上に更新** してください |
| ログインで詰まる | ブラウザのポップアップブロック（小窓を勝手に開かないようにするブラウザの設定）を切る／シークレットウィンドウ（履歴を残さないモード）で再試行 |

それでも解決しない場合は [付録 B. トラブルシューティング](/articles/claude-code-a2-troubleshooting) に網羅してあります。

---

## ふりかえり

![](./images/outros/ch01-outro.png)

ここまで本当にお疲れさまでした。**冒頭にも書いた通り、これが一番きつい章です。** ここから先は、Claude Code が起動した状態で進めていきます。「設定ファイルってどこにあるの？」「Git を入れたい」みたいな細かい設定で詰まったら、**もう全部 Claude Code 本人に聞いちゃってください**。インストールが終わった瞬間から、Claude Code 自身があなたのアシスタントになります。**ベースキャンプ到着、おめでとうございます。** 山頂はもうすぐです。

## 関連する章

-  **エラーが出たら**：[付録 B. トラブルシューティング](/articles/claude-code-a2-troubleshooting)
-  **次のステップ**：[第2回 はじめてのセッション](/articles/claude-code-02-first-session)
-  **コマンド一覧**：[付録 A. チートシート](/articles/claude-code-a1-cheatsheet)

## 次へ

→ [第2回 はじめてのセッション](/articles/claude-code-02-first-session)

| | |
|---|---|
| ⬅ 前へ | [第00回 はじめに](/articles/claude-code-00-introduction) |
|  次へ | [第2回 はじめてのセッション](/articles/claude-code-02-first-session) |
|  目次 | [README.md](./README.md) |