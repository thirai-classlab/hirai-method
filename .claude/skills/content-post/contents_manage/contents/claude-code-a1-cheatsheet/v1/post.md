---
title: "【claudeCode基礎学習】付録 A. 完全チートシート — 利用頻度ランキング＋網羅早見表"
slug: claude-code-a1-cheatsheet
type: tech_articles
subtype: deepdive
category: claude-code
thumbnail: ./images/chapters/A1-hero.png
author: "平井拓真"
source: "cc研修/A1-cheatsheet.md"
---

> **このページの位置づけ**
> 全章の **横断リファレンス**。「いま何を打てばいいか」をすぐ引き出せるよう、**利用頻度ランキング**（最初に押さえるべき Top）と **網羅早見表**（カンペ）の2段構成にしてあります。
> **印刷して机に貼っておくと地味に便利**。
>
> **対応バージョン**：Claude Code v2.1.x（2026年4月時点）
> 出典：Anthropic 公式 / [FlorianBruniaux Cheatsheet](https://github.com/FlorianBruniaux/claude-code-ultimate-guide) / [ykdojo/claude-code-tips](https://github.com/ykdojo/claude-code-tips)

**全部覚える必要はありません。** ランキングの Top 5 だけ覚えれば日々の作業の体感速度が一気に上がります。残りは「あれ、なんだっけ？」と思った瞬間にここに戻ってくれば OK。

---

## 0. 大前提：操作は「3種類」

| 種類 | どこに打つ | 始まり | 例 |
|---|---|---|---|
| スラッシュコマンド | Claude Code 入力欄（起動後） | `/` | `/clear` |
| 起動オプション | ターミナル（Claude 起動時） | `--` | `claude --resume` |
| キーボードショートカット | Claude Code 内 | キー組合せ | `Esc Esc` |

VSCode 拡張対応欄は ✅（対応）/ △（一部対応 or 要設定）/ ❌（非対応）で示します。

---

## 1. 利用頻度ランキング（まずここを見る）

### 1-1. スラッシュコマンド Top 12

> Claude Code 入力欄に打つコマンド。最頻順。

| 順位 | コマンド | どんなときに使う | VSCode拡張 |
|------|----------|------------------|------------|
| 1 | `/clear` | 長セッションで品質が落ちた／別タスクに切り替える | ✅ |
| 2 | `/compact` | コンテキスト窓が埋まってきたが続きを話したい | ✅ |
| 3 | `/resume` | 過去のセッションから再開したい | ✅ |
| 4 | `/context` | 今のトークン使用量・内訳を確認したい | ✅ |
| 5 | `/init` | 新規リポジトリに `CLAUDE.md` を作りたい | ✅ |
| 6 | `/review` | コードや差分にレビューをかけたい | ✅ |
| 7 | `/help` | コマンドを思い出したい | ✅ |
| 8 | `/cost` | これまでのトークン消費を確認したい | ✅ |
| 9 | `/effort` | 思考量を切替（**デフォルト = medium / 85**） | ✅ |
| 10 | `/voice` | 音声入力したい（Space 長押しで録音） | △（IDE依存） |
| 11 | `/model` | Opus／Sonnet／Haiku を切替 | ✅ |
| 12 | `/mcp` | MCP サーバを確認・管理 | ✅ |

#### `/clear` — 会話の頭を空にする

```claude-code
<prompt>/clear</prompt>
```

- **使う場面**：「セッションが長くて回答の質が落ちた」「全然違うタスクに切り替えたい」
- **動作**：会話履歴を**完全リセット**。再起動はせず、同じセッション内で継続
- **VSCode拡張**：対応

#### `/compact` — 会話を要約で詰め直す

```claude-code
<prompt>/compact</prompt>
```

- **使う場面**：コンテキスト使用率が 70〜80% を超えてきたが、**会話の続きはしたい**
- **動作**：これまでの会話を要約に置き換え、空きトークンを作る
- **VSCode拡張**：対応

#### `/resume` — 過去セッションから再開

```claude-code
<prompt>/resume</prompt>
```

- **使う場面**：昨日／先週の会話を続きから始めたい
- **動作**：現在のワークツリーのセッション一覧から選んで完全復元
- **VSCode拡張**：対応

#### `/context` — 何がトークンを食ってるか見る

```claude-code
<prompt>/context</prompt>
```

- **使う場面**：「最近重い」「`/compact` するか `/clear` するかの判断材料」
- **動作**：システムプロンプト／会話／ツール結果の内訳が出る
- **VSCode拡張**：対応

#### `/init` — プロジェクトに CLAUDE.md を作る

```claude-code
<prompt>/init</prompt>
```

- **使う場面**：新規リポジトリで初めて Claude Code を起動した直後
- **動作**：リポジトリを走査し、Claude が `CLAUDE.md` のドラフトを生成
- **VSCode拡張**：対応

#### `/review` — コードレビューをかける

```claude-code
<prompt>/review</prompt>
```

- **使う場面**：差分や PR にレビューを通したい
- **VSCode拡張**：対応

#### `/help` — コマンドの索引

```claude-code
<prompt>/help</prompt>
```

- **使う場面**：「あのコマンド何だっけ？」
- **VSCode拡張**：対応

#### `/cost` — トークン消費を確認

```claude-code
<prompt>/cost</prompt>
```

- **使う場面**：今日いくら使ったか／プラン上限が近そうなとき
- **VSCode拡張**：対応

#### `/effort` — 思考量ダイヤル（デフォルトは medium）

```claude-code
<prompt>/effort</prompt>
```

- **何をする設定か**：Claude が回答を出すまでに **どれだけ深く考えるか**（推論の深度 / reasoning depth）を切り替えるダイヤル。**回答前に内部で考える時間と量** が変わる
- **重要**：**2026年3月以降、デフォルトは `medium`（85）** に固定。「速度・コスト・知能」のバランスが一番良い点

##### 設定値ごとのトレードオフ

| 値 | 推論の深さ | 速度 | コスト | 出力品質 | こんな時 |
|---|---|---|---|---|---|
| `low` | 浅い | 速い | 低 | そこそこ | 軽い質問、定型処理 |
| `medium`（既定） | 中 | やや速 | 中 | 良 | 普段使い全般 |
| `high` | 深い | やや遅 | 高 | より良 | 設計・複雑なリファクタ |
| `xhigh` | より深い | 遅 | 高 | 高 | アーキ設計、難読コード読解 |
| `max` | 最深 | 最も遅 | 最大 | 最高 | 「ここぞ」の重要判断 |

> **覚え方**：上に行くほど **深く考えるが遅くて高い**。下に行くほど **速くて安いが浅い**。

- **やりがち失敗**：軽い質問に `max`（無駄）／重い設計に `low`（浅い推論で論理破綻）
- 個別指定：

```claude-code
<prompt>/effort high</prompt>
```

- **VSCode拡張**：対応

#### `/voice` — 音声入力（Push-to-talk）

```claude-code
<prompt>/voice</prompt>
```

- **使う場面**：手を動かさずに長文を口述したい
- **動作**：**Space キー長押しで録音、離して送信**。20言語対応
- **VSCode拡張**：△（マイク権限と Space キーバインド依存）

#### `/model` — モデル切替

```claude-code
<prompt>/model</prompt>
```

- **使う場面**：軽い作業に Haiku、重い設計に Opus
- **VSCode拡張**：対応

#### `/mcp` — MCP サーバ管理

```claude-code
<prompt>/mcp</prompt>
```

- **使う場面**：MCP（外部ツール連携、第8回参照）の状況確認・再接続
- **VSCode拡張**：対応

---

### 1-2. 起動オプション Top 7

> ターミナル（Mac の Terminal、Windows のコマンドプロンプト等）で `claude` の後ろに付ける。

| 順位 | オプション | どんなときに使う | VSCode拡張 |
|------|-------------|-------------------|------------|
| 1 | （なし） | 通常起動 | ✅（拡張から起動ボタン） |
| 2 | `--continue`（`-c`） | 直前の最後の会話を続ける | ✅ |
| 3 | `--resume`（`-r`） | 過去セッション一覧から選んで再開 | ✅ |
| 4 | `--plan` ／ `--permission-mode plan` | 読み取り専用プランモードで起動 | ✅ |
| 5 | `--upgrade` | Claude Code 自体を更新 | N/A |
| 6 | `--dangerously-skip-permissions` | **隔離環境**で全権限確認をスキップ | ❌ |
| 7 | `--ide` | 既存ターミナルから VSCode 拡張へ接続 | ✅ |

#### 通常起動

```text
$ claude
```

#### `--continue` — 直前の続きを一発で

```text
$ claude --continue
```

- **使う場面**：5分前にターミナルを閉じた／同じプロジェクトで作業を続ける
- **動作**：直前のセッションをそのまま開く（一覧を出さない）

#### `--resume` — 一覧から選んで再開

```text
$ claude --resume
```

- **使う場面**：複数セッションがあり、特定のものに戻りたい
- **動作**：セッション一覧 → 選択でチャット履歴・ツール結果・コード変更を完全復元

#### `--plan` ／ `--permission-mode plan` — プランモード起動

```text
$ claude --permission-mode plan
```

- **使う場面**：いきなり実装させず、**まず計画だけ出させたい**
- **動作**：書き込み・実行系を全部止めて、Plan を提示
- **注意**：`--dangerously-skip-permissions` と同時に渡すと、**プランモードが silently 上書きされて bypass が勝つ既知バグ** あり

#### `--upgrade` — Claude Code 本体の更新

```text
$ claude --upgrade
```

#### `--dangerously-skip-permissions` — 全権限スキップ（要注意）

```text
$ claude --dangerously-skip-permissions
```

- **使う場面**：**Docker / Sandbox / 専用 VM の隔離環境** で自動運転的に走らせたいとき**だけ**
- **動作**：本来確認が出る全操作を**問答無用で実行**。"dangerously" は文字通り
- **本番マシン・日常開発で使うのは禁忌**。`rm -rf ~/` 級の事故が一発で起きる
- **既知問題**：
  - `--permission-mode plan` と併用すると bypass が plan を上書き
  - `--resume` で復帰時にこのフラグは保持されない（再付与必要）
- **VSCode拡張**：拡張上では使わない／使えない

#### `--ide` — 既存ターミナルと VSCode 拡張をつなぐ

```text
$ claude --ide
```

- **使う場面**：ターミナルで動かしている Claude を、差分やプランは VSCode 拡張側で見たい
- **VSCode拡張**：対応（接続専用）

---

### 1-3. キーボードショートカット Top 10

> Claude Code の入力欄／チャット内で押すキーの組み合わせ。

| 順位 | キー | どんなときに使う | VSCode拡張 |
|------|------|------------------|------------|
| 1 | `Esc × 2` | 直前操作を巻き戻し | ✅ |
| 2 | `Ctrl+C × 2` | 実行中の処理を中断 | ✅ |
| 3 | `Shift+Tab` | 権限モード（Auto / Plan / Ask）切替 | ✅ |
| 4 | `Cmd+Enter` / `Ctrl+Enter` | （拡張）送信 | ✅ |
| 5 | `\+Enter` | 改行を入力 | ✅ |
| 6 | `Option+T` / `Alt+T` | 拡張思考のトグル | ✅ |
| 7 | `Option+P` / `Alt+P` | モデルピッカー | ✅ |
| 8 | `Ctrl+G` | 長文を外部エディタで編集 | △（CLI推奨） |
| 9 | `Ctrl+F × 2` | バックグラウンドエージェント全停止 | ✅ |
| 10 | `Ctrl+A` / `Ctrl+E` | 行頭／行末ジャンプ | ✅（入力欄内） |

各ショートカットの解説：

- **`Esc × 2`**：「ヤバ、待って！」の最強セーフティ。直前の Claude の操作（ファイル書き込み・コマンド実行）を巻き戻す
- **`Ctrl+C × 2`**：1回目で警告、2回目で確実に中断
- **`Shift+Tab`**：`Auto-accept` / `Plan` / `Ask` のサイクル切替
- **`Cmd+Enter` / `Ctrl+Enter`**：VSCode／JetBrains 拡張ではこれが標準の送信キー
- **`\+Enter`**：CLI 入力欄で `\` の直後に Enter を押すと改行（即送信されない）
- **`Option+T` / `Alt+T`**：Extended thinking の ON／OFF
- **`Option+P` / `Alt+P`**：モデル選択 UI を即時表示
- **`Ctrl+G`**：`$EDITOR`（vim / nano / VS Code 等）が起動。保存して閉じると入力欄に流し込まれる
- **`Ctrl+F × 2`**：1回目で警告、3秒以内にもう1回でバックグラウンドの全エージェントを kill
- **`Ctrl+A` / `Ctrl+E`**：Unix 流の行頭・行末ジャンプ

---

## 2. 起動オプション 網羅一覧

ランキング外も含めた **完全リスト**。よく使うやつから順に並べました。

### 基本

| コマンド | 説明 | VSCode拡張 |
|---|---|---|
| `claude` | インタラクティブセッション開始 | ✅ |
| `claude "<prompt>"` | プロンプトを与えて起動 | ✅ |
| `claude -p "<prompt>"` | 出力モード（パイプ向き） | ❌ |
| `claude --version` | バージョン表示 | N/A |
| `claude --help` | ヘルプ | N/A |

### セッション管理

| コマンド | 説明 | VSCode拡張 |
|---|---|---|
| `claude -c` | **直前のセッションを再開** | ✅ |
| `claude -r` | セッション一覧から選んで再開 | ✅ |
| `claude -r <session-id>` | ID指定で再開 | ✅ |
| `claude --resume` | `-r` と同じ | ✅ |
| `claude --teleport` | Web/モバイルで開始したセッションを引き継ぐ | △ |
| `claude --fork-session` | セッションを分岐 | ✅ |

### モデル / 思考量

| コマンド | 説明 | VSCode拡張 |
|---|---|---|
| `claude --model opus` | Opus で起動 | ✅ |
| `claude --model sonnet` | Sonnet で起動 | ✅ |
| `claude --model haiku` | Haiku で起動 | ✅ |
| `claude --model opusplan` | Plan = Opus / Exec = 別 | ✅ |
| `claude --effort max` | 最大思考モード | ✅ |

### モード切替

| コマンド | 説明 | VSCode拡張 |
|---|---|---|
| `claude --plan` | プランモードで起動 | ✅ |
| `claude --auto-edit` | 編集自動承認 | ✅ |
| `claude --dangerously-skip-permissions` | 全権限スキップ（**サンドボックス専用**） | ❌ |

> ⚠️ `--dangerously-skip-permissions` は名前の通り危険。**Docker などのサンドボックス環境以外では絶対に使わない**こと。

### スクリプト連携（パイプ）

`-p` をつけると、他のコマンドの結果を Claude に流し込めます。CI や自動化で頻出。

```text
$ cat error.log | claude -p "このログを分析"
$ git diff main --name-only | claude -p "変更ファイルをセキュリティ観点でレビュー"
$ tail -200 app.log | claude -p "Slack で通知すべき異常があれば教えて"
```

### 出力フォーマット

| コマンド | 説明 |
|---|---|
| `claude -p --output-format json` | JSON出力 |
| `claude -p --output-format text` | テキスト |
| `claude -p --output-format markdown` | Markdown |

---

## 3. セッション内 スラッシュコマンド 網羅一覧

セッション中に `/` から始めて打つ全コマンド。**全部覚える必要はゼロ**、必要になったときに調べて使えば十分です。

### 基本操作

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/help` | ヘルプ | ✅ |
| `/clear` | 履歴リセット | ✅ |
| `/exit` | 終了 | ✅ |
| `/init` | CLAUDE.md 初期化 | ✅ |
| `/status` | セッション状態 | ✅ |
| `/cost` | コスト確認 | ✅ |

### コンテキスト管理

会話が長くなって重くなってきたとき用。

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/context` | コンテキスト構成可視化 | ✅ |
| `/compact` | 履歴圧縮 | ✅ |
| `/branch` | セッション分岐 | ✅ |
| `/recap` | 休憩明けに要約を表示（v2.1.108+） | ✅ |

### モデル / モード

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/model` | モデル切替（sonnet/opus/opusplan） | ✅ |
| `/plan` | プランモード（変更しない） | ✅ |
| `/execute` | プランモード解除 | ✅ |
| `/ultraplan` | クラウドで計画策定（v2.1.91+） | ✅ |
| `/effort [low\|medium\|high\|xhigh\|max]` | 思考量制御（既定 medium、v2.1.111+） | ✅ |
| `/fast` | 高速モード（2.5×速・6×コスト） | ✅ |
| `/voice` | 音声入力 ON/OFF | △（IDE依存） |

### 設定 / 管理

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/config` | 設定変更 | ✅ |
| `/permissions` | 権限管理 | ✅ |
| `/memory` | メモリ確認 | ✅ |
| `/mcp` | MCP接続状態 | ✅ |
| `/agents` | サブエージェント一覧 | ✅ |
| `/skills` | スキル一覧 | ✅ |
| `/hooks` | フック一覧 | ✅ |

### サブエージェント / タスク

並行処理系。1人で複数の作業を回したいときに。

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/agents` | サブエージェント定義 | ✅ |
| `/tasks` | バックグラウンドタスク一覧 | ✅ |
| `/loop [interval] <prompt>` | ループ実行（v2.1.71+） | ✅ |
| `/batch <prompt>` | 並列ワークツリーで一括実行 | ✅ |
| `/btw <question>` | 一時的に脇道質問（履歴汚染なし） | ✅ |
| `/aside` | サイドクエスチョン | ✅ |

### リモート / モバイル

外出先からスマホで操作したい人向け。

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/remote-control` | スマホから操作（Pro/Max） | △ |
| `/rc` | `/remote-control` のエイリアス | △ |
| `/mobile` | モバイルアプリ DL リンク | ✅ |
| `/dispatch` | チャネル経由でタスク受信 | △ |
| `/teleport` | Web/モバイルセッションを引き継ぎ | △ |
| `/desktop` | デスクトップアプリへ移管 | △ |
| `/schedule` | スケジュール実行（クラウド） | ✅ |

### 出力 / ユーティリティ

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/copy` | 最後の応答をクリップボードへ | ✅ |
| `/rename <name>` | セッション名変更 | ✅ |
| `/stats` | 利用統計 | ✅ |
| `/insights` | 分析・最適化レポート | ✅ |
| `/simplify` | 過剰実装の検出と修正 | ✅ |
| `/debug` | 系統的デバッグ | ✅ |
| `/tui [fullscreen]` | TUI表示切替（v2.1.110+） | N/A |
| `/focus` | フォーカスビュー | ✅ |

### 学習 / ガイド

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/powerup` | インタラクティブレッスン | ✅ |
| `/release-notes` | リリースノート確認 | ✅ |

### Git / GitHub 連携

| コマンド | 動作 | VSCode拡張 |
|---|---|---|
| `/install-github-app` | GitHub アプリ連携 | ✅ |
| `/pr-comments` | PRコメント取得 | ✅ |
| `/review` | PR レビュー | ✅ |

---

## 4. キーボードショートカット 網羅一覧

**`Esc × 2`（巻き戻し）と `Shift+Tab`（モード切替）の2つだけは覚える価値あり** です。

### グローバル

| ショートカット | 動作 | VSCode拡張 |
|---|---|---|
| `Shift+Tab` | パーミッションモード循環 | ✅ |
| `Esc × 2` | 巻き戻し | ✅ |
| `Ctrl+C` | 中断 | ✅ |
| `Ctrl+C × 2` | 強制終了 | ✅ |
| `Ctrl+D` | 終了 | ✅ |
| `Ctrl+L` | 画面クリア（履歴保持） | ✅ |
| `Ctrl+R` | コマンド履歴検索 | ✅ |
| `Tab` | 自動補完 | ✅ |
| `Shift+Enter` | 改行 | ✅ |
| `Ctrl+B` | バックグラウンドタスク | ✅ |
| `Ctrl+F × 2` | バックグラウンドエージェント全停止 | ✅ |
| `Alt+T` | 思考モード ON/OFF | ✅ |
| `Ctrl+O` | 思考プロセス可視化 | ✅ |
| `Space`（長押し） | 音声入力（`/voice` 有効時） | △ |

### 入力ボックス内

メッセージを書いている最中の編集ショートカット。慣れると指がだいぶ楽になります。

| ショートカット | 動作 | VSCode拡張 |
|---|---|---|
| `Ctrl+A` | 行頭へ | ✅ |
| `Ctrl+E` | 行末へ | ✅ |
| `Option+←/→` | 単語単位移動 | ✅ |
| `Ctrl+W` | 直前の単語削除 | ✅ |
| `Ctrl+U` | カーソルから行頭まで削除 | ✅ |
| `Ctrl+K` | カーソルから行末まで削除 | ✅ |
| `Ctrl+G` | 外部エディタで編集 | △ |
| `\+Enter` | 改行入力 | ✅ |

### IDE 拡張の起動

| IDE | プラグイン起動 |
|---|---|
| VS Code | `Alt+K` |
| JetBrains | `Cmd+Option+K` |

---

## 5. 入力中の便利記法

メッセージの中で使える特別な記法。

| 記法 | 意味 | 例 | VSCode拡張 |
|---|---|---|---|
| `@path/to/file.ts` | ファイルを文脈に取り込む | `@src/auth.ts のバグを直して` | ✅ |
| `@agent-name` | サブエージェント呼び出し | `@reviewer を実行` | ✅ |
| `@browser` | ライブ Web デバッグ | `@browser でこのページを開いて` | ✅（拡張専用機能） |
| `!shell-command` | シェル実行 | `!git status` | ✅ |
| `$1`, `$2`, `$ARGUMENTS` | スラッシュコマンド内引数 | カスタムコマンドで使用 | ✅ |

---

## 6. パーミッション

パーミッション（権限の厳しさ）の設定方法。`settings.json` に書いておくと、毎回確認されるストレスが減ります。

### 評価順

```text
Deny → Ask → Allow
```

> 上から順にチェックされる。Deny に書いたものは絶対ブロック、Ask は確認、Allow は自動許可。**「禁止」が一番強い**。

### settings.json での書き方

```json
{
  "permissions": {
    "allow": [
      "Bash(npm test)",
      "Bash(npm run *)",
      "Bash(git status)",
      "Read(*)",
      "Edit(src/**)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(npm install:*)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Bash(rm -rf:*)",
      "Bash(sudo:*)",
      "Bash(git push --force:*)"
    ]
  }
}
```

### よくあるパターン

| パターン | 説明 |
|---|---|
| `Bash(git status)` | `git status` 完全一致 |
| `Bash(git status:*)` | `git status` で始まるすべて |
| `Read(./src/**)` | `src/` 以下の全ファイル読み込み |
| `Read(./.env*)` | `.env` で始まるファイル全部 |

---

## 7. 設定ファイルの場所

「あの設定どこに書くんだっけ？」と迷いがちなので、置き場所一覧。

| ファイル | スコープ | 主な内容 |
|---|---|---|
| `~/.claude/settings.json` | グローバル | キーバインド・テーマ・グローバル権限 |
| `~/.claude/CLAUDE.md` | グローバル指示 | 全プロジェクト共通の指示 |
| `<project>/.claude/settings.json` | プロジェクト共有 | チームで共有したいフック・MCP |
| `<project>/.claude/settings.local.json` | プロジェクト個人 | git-ignore 推奨 |
| `<project>/CLAUDE.md` | プロジェクト指示 | プロジェクト固有の指示 |
| `<project>/.mcp.json` | MCP 設定 | プロジェクトの MCP サーバー |
| `~/.claude/skills/` | グローバルスキル | |
| `<project>/.claude/skills/` | プロジェクトスキル | |
| `~/.claude/agents/` | グローバルエージェント | |
| `<project>/.claude/agents/` | プロジェクトエージェント | |
| `~/.claude/commands/` | グローバルコマンド | |
| `<project>/.claude/commands/` | プロジェクトコマンド | |
| `~/.claude/projects/` | セッション履歴 | |

---

## 8. 環境変数

環境変数（OSが持っている設定値）で挙動を変えられるやつ一覧。

| 変数 | 効果 |
|---|---|
| `ANTHROPIC_API_KEY` | API キー |
| `CLAUDE_AUTO_COMPACT_PERCENTAGE_OVERRIDE` | 自動圧縮の閾値 (0-100) |
| `DISABLE_AUTOUPDATER` | 自動更新を無効化（システムプロンプト削減） |
| `DISABLE_TELEMETRY` | テレメトリ無効化 |
| `MAX_THINKING_TOKENS` | 思考トークン上限 |
| `ENABLE_LSP_TOOL` | LSPツール有効化 |
| `ANTHROPIC_BEDROCK` | AWS Bedrock 使用 |
| `ANTHROPIC_VERTEX` | Google Vertex AI 使用 |
| `CLAUDE_CODE_USE_BEDROCK` | Bedrock 経由 |

---

## 9. MCP 管理

MCP（外部ツールとの接続規格）サーバーを追加・削除するときのコマンド。

```text
$ claude mcp add <name> <command> [-- <args>]
$ claude mcp add github -e GITHUB_TOKEN=ghp_xxx -- npx -y @modelcontextprotocol/server-github
$ claude mcp list
$ claude mcp remove <name>
```

接続確認は Claude Code の入力欄で:

```claude-code
<prompt>/mcp</prompt>
```

---

## 10. プラグイン管理

プラグイン（拡張機能パック）の操作コマンド。

```text
$ claude plugin marketplace add <owner/repo>
$ claude plugin install <plugin-name>
$ claude plugin list
$ claude plugin remove <plugin-name>
```

人気マーケットプレイス例：

- `ykdojo/claude-code-tips` — `dx@ykdojo`
- `anthropics/claude-skills` — 公式

---

## 11. skills.sh CLI

スキル（Claude に「こういうときはこうやって」と教える小さい指示集）を npm 経由で管理するツール。

```text
$ npx skills find <keyword>
$ npx skills add <owner/repo@skill> [-g] [-y]
$ npx skills list
$ npx skills check
$ npx skills update
$ npx skills init <skill-name>
```

---

## 12. 思考トリガーワード（プロンプト内で使う）

プロンプト本文に書くだけで、Claude の思考量（じっくり考えるか／サクッと答えるか）を変えられる魔法の単語。

| ワード | 思考量 |
|---|---|
| （何もなし） | 標準 |
| `think` | 中 |
| `think hard` | 多 |
| `think harder` | より多 |
| `ultrathink` | 最大 |

例：

```text
このアーキテクチャの問題点を ultrathink で分析してください
```

---

## 13. ホットな Tips ダイジェスト

知ってると地味にうれしい小ネタ集。

### 一言で覚える系

```text
# 過去会話を grep
$ grep -l -i "keyword" ~/.claude/projects/*/*.jsonl

# 5分おきにデプロイチェック → Claude Code の入力欄
/loop 5m check the deploy

# サンドボックスで全権限
$ docker run -it -v $(pwd):/work node:22 claude --dangerously-skip-permissions
```

### CLAUDE.md 育成系

- 3ヶ月に1回 `/dx:review-claudemd`
- 詳細は `docs/` に外出し → CLAUDE.md は薄く
- 固有名詞・ライブラリ名で具体化

### コンテキスト節約系

- `CLAUDE_AUTO_COMPACT_PERCENTAGE_OVERRIDE=65` で早めにコンパクト
- `DISABLE_AUTOUPDATER=1` でシステムプロンプト 50% 削減
- 不要 MCP は外す → `/mcp` で確認

---

## 14. VSCode 拡張で「何が動く」か（最終確認）

VSCode 拡張は 2026 年現在 GA（一般提供）済みで、**CLI 体験にかなり近い**ところまで来ています。

### 拡張で確実に動くもの

- スラッシュコマンド全般（`/clear` `/compact` `/resume` `/context` `/init` `/review` `/help` `/cost` `/effort` `/model` `/mcp` ほぼ全部）
- カスタムスラッシュコマンド（`.claude/commands/<name>.md` を置けば拡張側でも読み込まれる）
- `@` でファイル参照、`@browser` で**ライブ Web デバッグ**
- サイドバイサイド差分ビューア・複数会話タブ
- サブエージェント／MCP／Plan モード／Extended Thinking
- 拡張専用：`/install-github-app`（PR 自動レビュー連携）／`/ide`（既存ターミナルと接続）／`/terminal-setup`

### 拡張で「使わない／使えない」もの

- `--dangerously-skip-permissions` — 拡張上では基本的に出てこない／使うべきでない
- `Ctrl+G`（外部エディタ） — 拡張側はチャット欄が十分広いので、CLI ほど必要にならない
- `/voice` — マイク権限と Space キーのキーバインドの取り合いが OS／IDE 設定依存

---

## 出典

- 公式: <https://code.claude.com/docs/en/overview>
- CLI Reference: <https://code.claude.com/docs/en/cli-reference>
- Use Claude Code in VS Code: <https://code.claude.com/docs/en/vs-code>
- Permission Modes: <https://code.claude.com/docs/en/permission-modes>
- CHANGELOG: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- FlorianBruniaux Cheatsheet: <https://github.com/FlorianBruniaux/claude-code-ultimate-guide>
- ykdojo Tips: <https://github.com/ykdojo/claude-code-tips>

---

## ふりかえり

![](./images/outros/A1-outro.png)

繰り返しになりますが、**全部覚える必要は本当にありません**。よく使うのは結局 10〜15 個くらい。残りは「あったな、確かここに」と思い出せれば十分です。困ったらこのページに戻ってきてください。

最後にもう一度、3カテゴリの最頻 Top 3 を再掲します。

| カテゴリ | 最頻 Top 3 |
|---|---|
| スラッシュコマンド | `/clear` ／ `/compact` ／ `/resume` |
| 起動オプション | （なし）／ `claude --continue` ／ `claude --resume` |
| ショートカット | `Esc × 2` ／ `Ctrl+C × 2` ／ `Shift+Tab` |

これだけ頭に入っていれば、Claude Code を「使いこなしている人」のラインに乗っています。

---

## 関連する章（コマンドの背景を学ぶ）

- **`/context` `/compact` `/branch` の意味**：[第4回 コンテキスト管理](/articles/claude-code-04-context)
- **`/init` の中身**：[第4回 コンテキスト管理 §3 CLAUDE.md](/articles/claude-code-04-context)
- **スラッシュコマンド自作**：[第5回 スキル & スラッシュコマンド](/articles/claude-code-05-skills-and-commands)
- **`/agents` の意味**：[第6回 サブエージェント](/articles/claude-code-06-subagents)
- **`/hooks` の意味**：[第7回 フック](/articles/claude-code-07-hooks)
- **`/mcp` の意味**：[第8回 MCP](/articles/claude-code-08-mcp-tools)
- **`/effort` `/plan` `/ultraplan`**：[第9回 精度の高いアウトプット](/articles/claude-code-09-prompt-quality)

## 次へ

→ [付録 B. トラブルシューティング](/articles/claude-code-a2-troubleshooting)

| | |
|---|---|
| ⬅ 前へ | [第13回 役職別 学習パス](/articles/claude-code-14-role-based-paths) |
|  次へ | [付録 B. トラブルシューティング](/articles/claude-code-a2-troubleshooting) |
|  目次 | [全18記事インデックス](/articles/claude-code-complete-guide) |
