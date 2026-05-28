---
title: "【claudeCode基礎学習】付録 B. トラブルシューティング — 詰まったときの病院問診票"
slug: claude-code-a2-troubleshooting
type: tech_articles
subtype: deepdive
category: claude-code
thumbnail: ./images/chapters/A2-hero.png
author: "平井拓真"
source: "cc研修/A2-troubleshooting.md"
---

> **このページの位置づけ**
> 詰まったら最初に開くページなんですよ。
> 症状 → 原因 → 解決策の順に並んでいるので、**病院の問診票** みたいに使ってください。

---

## よくあるトラブル早見表

まずは「自分はどのカテゴリで詰まってるのか」を切り分けましょう。下の図で当てはまりそうな枝をたどってください。

![](./images/inline/A2-m1.png)

---

## 1. インストール関連

**「あ、それなった」筆頭セクション**。インストールでつまずく人、本当に多いのでご安心を。**ターミナル開き直すだけで9割解決します**、という伝説のフレーズはここでも有効です。

### Q1-1. `command not found: claude`

**原因**:パスが通っていない(パソコンがまだ `claude` の居場所を覚えてない状態)/ インストールが完了していない、のどちらかです。

**解決**:
```bash
# 1. 新しいターミナルを開く
# 2. パス確認
echo $PATH

# 3. 再インストール(macOS/Linux)
curl -fsSL https://claude.ai/install.sh | bash

# 4. それでもダメなら手動でパス追加
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

まず **新しいターミナルを開き直す** のを試してください。これで直る人、めちゃくちゃ多いんですよ。

### Q1-2. `EACCES: permission denied`(Mac/Linux)

**原因**:npm のグローバルディレクトリ(全ユーザー共通の保存場所)の権限不足です。

**解決**:
```bash
# 推奨:ネイティブインストーラーに切り替える
curl -fsSL https://claude.ai/install.sh | bash

# やむを得ず npm を使う場合は npm prefix を変更
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
```

権限まわりで沼にハマるくらいなら、**素直にネイティブインストーラーに乗り換える** のが一番早いです。

### Q1-3. Windows でうまく動かない

**原因**:Git for Windows(Git というファイル履歴管理ツールの Windows 版)が無い / シェル(コマンド入力環境)違いです。

**解決**:
1. [Git for Windows](https://git-scm.com/download/win) をインストール
2. PowerShell から：
   ```powershell
   irm https://claude.ai/install.ps1 | iex
   ```
3. それでもダメなら WSL2(Windows の中で Linux を動かす仕組み)利用も検討してください

### Q1-4. `Node.js のバージョンが古い`

**原因**:Node 18 以下です。

**解決**:v22 LTS(長く安定して使える版)にアップデートしてください。
```bash
# nodebrew または nvm でアップデート
nvm install --lts
nvm use --lts
```

---

## 2. ログイン / API キー関連

ログインで詰まると、**スタート地点に立てない** ので焦りますよね。でもだいたいキーかブラウザの問題なので、落ち着いていきましょう。

### Q2-1. `Authentication failed`

**原因**:APIキー誤り / 残高ゼロ / IP制限のいずれかです。

**解決**:
- [console.anthropic.com](https://console.anthropic.com/) で残高確認
- API キーを再発行 → 環境変数(OS側に保存される設定値)を更新
- 先頭・末尾のスペースを削除して再設定

意外と多いのが **コピペで余計な空白が混入** しているパターン。**「目に見えない空白」が悪さしてる** こと、本当によくあります。

### Q2-2. ブラウザでログイン詰まる

**原因**:ポップアップブロッカー(小窓を勝手に開かないようにする設定)/ Cookieブロックです。

**解決**:
- ブラウザのポップアップ制限を一時解除
- シークレットモード(履歴を残さないモード)で再試行
- `claude logout && claude login` で再ログイン

### Q2-3. Bedrock / Vertex AI で認証エラー

**解決**:[公式 Bedrock / Vertex セットアップガイド](https://code.claude.com/docs/en/amazon-bedrock) を参照してください。AWS / GCP のクレデンシャル(認証情報)設定が必要です。

---

## 3. 動作関連

「なんか動きが変…」と感じたときのコーナーです。**故障診断モード** だと思ってください。

### Q3-1. 応答が遅い / 止まった

**原因候補**:
- Anthropic 側障害
- ネットワーク不安定
- コンテキスト満杯
- レート制限(使用量の上限)

**解決**:
1. [status.anthropic.com](https://status.anthropic.com/) で稼働状況確認
2. `Ctrl+C × 2` で中断 → 再実行
3. `/context` で状況確認、満杯なら `/compact`
4. `/status` でレート状況確認

まずは **自分のせいなのか、Anthropic 側のせいなのか** を切り分けるのが大事です。Status ページを最初にチェック、これクセにしてください。

### Q3-2. 突然 200K の体力ゲージが残ってるのに性能が落ちる

**原因**:80%超えると注意力低下する仕様なんですよ。

**解決**:
- `/compact` を実行(手動で65〜70%に下げる)
- 環境変数で自動圧縮閾値を下げる：
  ```json
  { "env": { "CLAUDE_AUTO_COMPACT_PERCENTAGE_OVERRIDE": "65" } }
  ```

ゲージが残ってても性能落ちる、これは仕様なんです。**「体力満タンに見えても疲れてる」** イメージですね。

### Q3-3. ループする / 同じ修正を繰り返す

**原因**:プロンプト(指示文)が曖昧 / コンテキストが汚染されています。

**解決**:
- `/clear` でリセット
- より具体的な指示で再依頼
- Plan Mode に切り替えて計画から見直す

同じ場所をぐるぐる回り始めたら、**いったん `/clear` で全部捨ててやり直す** のが結局一番早いです。

### Q3-4. ファイルが意図せず変更された

**解決**:
- `Esc × 2` で巻き戻し(直前なら)
- Git で `git restore <file>` または `git diff` で確認後 reset

---

## 4. コスト・レート関連

お金とレート制限の話。**カウンターをチラ見する習慣** が大事です。

### Q4-1. 急に「rate limited」と出る

**原因**:プランの上限到達です。

**解決**:
- `/cost` で使用状況確認
- Sonnet / Haiku に切り替えて節約
- プランをアップグレード(Pro → Max)

### Q4-2. API課金が高すぎる

**原因**:Opus 多用 / コンテキスト肥大が主犯です。

**解決**:
- サブエージェントに Haiku を使う
- スキルで段階的開示してコンテキスト圧縮
- 不要な MCP を外す
- `DISABLE_AUTOUPDATER=1` でシステムプロンプト50%削減

「**全部 Opus でやればいい**」は富豪しかできない発想なので、**用途に応じて Sonnet / Haiku を使い分ける** のが現実解です。

---

## 5. 出力関連

「なんか思った通りに動かない…」のコーナー。**だいたいプロンプトのせい**、なんですが、それだけじゃない場合もあります。

### Q5-1. 精度が低い / 期待と違う出力

**原因**:プロンプトが曖昧 / クセが出ているなどです。

**解決**:[第9回](/articles/claude-code-09-prompt-quality) を参照してください。
- 固有名詞を使う
- 「やってほしくないこと」も明示
- Plan Mode → 実行
- `ultrathink` を追加

### Q5:2. 暴走して大量にファイル変更

**原因**:パーミッション(操作権限)が甘い / Plan モードを使わなかった、です。

**解決**:
- `Esc × 2` で巻き戻し
- Git で reset
- 今後は Plan Mode から始める
- `permissions.deny` で危険操作を禁止

**やらかしたとき用の応急処置** をまず覚えておくと、心の余裕が違います。

### Q5-3. 文字化け

**原因**:ターミナルの文字コード(文字を表示するときの規格)です。

**解決**:
- ターミナルを UTF-8(世界共通の文字の書き方)に
- Warp / Windows Terminal なら標準でOK

---

## 6. CLAUDE.md / スキル関連

「設定したはずなのに効いてない」系トラブル。**ファイル名と置き場所** で詰まる人、多いんですよね。

### Q6-1. CLAUDE.md が読まれていない

**原因**:CLAUDE.md の場所が違うことが多いです。

**解決**:
- `/context` で「Memory Files」セクション確認
- プロジェクトルート直下に置いているか確認
- ファイル名のスペル(大文字小文字)を確認

`claude.md` と `CLAUDE.md` は別物として扱われるので、**大文字小文字も合わせる** のが大事です。

### Q6-2. スキルが呼ばれない

**原因**:description が曖昧 / トリガーが不明確、です。

**解決**:
- `description` を「いつ使うか」明確に書き直す
- スキル名を直接指定して呼ぶ
- `/skills` で一覧表示して確認

### Q6-3. サブエージェントが呼ばれない

**原因**:description / tools 設定不備です。

**解決**:
- `.claude/agents/<name>.md` の存在確認
- `description` に呼び出しトリガーを明記
- `@<agent-name>` で明示呼び出しテスト

---

## 7. フック関連

フックは **動かないときに無言** という特性があるので、デバッグが少し面倒なんですよ。

### Q7-1. フックが動かない

**原因**:パス / 権限 / JSON誤りのどれかです。

**解決**:
```bash
# 1. スクリプトに実行権限
chmod +x .claude/scripts/*.sh

# 2. ログを仕込んでデバッグ
echo "[hook] called" >> /tmp/claude-hook.log

# 3. settings.json をJSON validatorで検証
cat .claude/settings.json | jq .
```

**まずログを仕込む**、これがフックデバッグの鉄則です。「動いてないのか」「動いてるけど何かが違うのか」を切り分けましょう。

### Q7-2. フックがタイムアウト

**解決**:
- `timeout` を伸ばす(デフォルト 5秒)
- 処理を非同期化
- 重い処理は Stop 以外のタイミングへ

### Q7-3. PreToolUseが効かずブロックできない

**原因**:`matcher` ミス / exit code 違いです。

**解決**:
- ブロック時は `{"decision":"block","reason":"..."}` を stdout に
- `exit 2` でも可
- `matcher` の正規表現を確認

---

## 8. MCP 関連

MCP は **外部サーバーが絡む** ので、つながらないときは「自分側か、相手側か、間か」を疑っていきます。

### Q8-1. MCP サーバーが繋がらない

**原因**:起動失敗 / 認証 / コマンド誤りです。

**解決**:
```bash
# 接続状況確認
/mcp

# 手動で起動テスト
npx @modelcontextprotocol/server-github

# 環境変数を確認
echo $GITHUB_TOKEN
```

### Q8-2. MCP の追加で精度が落ちた

**原因**:ツール定義のトークン消費が増えたためです。

**解決**:
- 不要な MCP を外す
- Claude Code 標準ツールで代替できないか検討
- スキルで段階的開示に置き換える

「**入れれば便利になる**」と思って MCP を増やしすぎると、逆に頭が悪くなる、という現象が起きます。**必要なものだけ** が鉄則です。

---

## 9. セキュリティ関連

 **このセクションは緊急対応マニュアル** として読んでください。**やらかした瞬間の判断が一番大事** です。

### Q9-1.  機密情報を Claude が触ったかも

**緊急対応**:
1. 触れた可能性のあるファイル / シークレット(秘密の文字列)を **即時 rotate**(GitHub PAT、AWSキー、DB接続文字列など)
2. `~/.claude/projects/` のセッションログを確認・削除
3. `.gitignore` を見直して二度と入らないように
4. `permissions.deny` に該当パスを追加

**気づいた瞬間に rotate する**、これが最優先です。「あとでやろう」は無しでお願いします。

### Q9-2. `dangerously-skip-permissions` を本番で使ってしまった

**緊急対応**:
1. ターミナルを **すぐ閉じる**(`Ctrl+C × 2`)
2. 直近の変更を `git diff` で精査
3. 不要な変更は revert / restore
4. 今後は **Docker サンドボックス**(隔離された実験環境)や使い捨てVMでのみ使う

**本番でこのフラグを使った時点で「事故」** です。落ち着いて被害確認 → 環境分離、の順で動きましょう。

### Q9-3. プロンプトインジェクション疑惑

**症状**:Webから取り込んだコンテンツの後、Claudeの挙動がおかしいというパターンです。

**解決**:
- セッションを `/clear` してやり直し
- そのソースは信頼できないとマーク
- 今後は **読み取り権限を絞る** / サンドボックス利用

外部から取り込んだ文章に **悪意ある指示が混じっていた** 可能性があります。**「変だな」と思ったらいったん `/clear`**、が安全策です。

---

## 10. アップデート関連

### Q10-1. 古いバージョンを使い続けている

**解決**:
```bash
# ネイティブインストーラー版なら自動更新
# Homebrew版
brew upgrade claude-code

# WinGet版
winget upgrade Anthropic.ClaudeCode

# バージョン確認
claude --version
```

### Q10-2. アップデート後に動かなくなった

**解決**:
- リリースノート確認： `/release-notes`
- 一旦削除して再インストール
- 動画・記事は **古い情報** が混じっています。公式ドキュメントを優先してください

このツール、**進化が早すぎて 3ヶ月前の記事が陳腐化する** ことがザラなので、**公式ドキュメント最優先** で行きましょう。

---

## 11. その他のヘルプ

ここまで見ても解決しない場合の **最終手段ルート** です。

![](./images/inline/A2-m2.png)

### 公式情報源
- ドキュメント： <https://code.claude.com/docs/en/overview>
- ステータス： <https://status.anthropic.com/>
- CHANGELOG: <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>
- GitHub Issues: <https://github.com/anthropics/claude-code/issues>

### コミュニティ
- Reddit: r/ClaudeAI
- Discord: Anthropic公式
- 日本語： Zenn / Qiita / X

**「自分だけハマってる」と思っても、たいてい誰かが先にハマって解決策を残してくれてます**。GitHub Issue や Reddit で同じ症状を検索してみてください。

---

## ふりかえり

![](./images/outros/A2-outro.png)

トラブル時の問診票、ここまでお疲れさまでした。**詰まるのは恥ずかしいことではなく、みんな通る道** です。このページをブックマークしておいて、困ったらまずここに戻ってきてください。

## 関連する章(症状別ジャンプ)

-  **環境構築でつまずく**:[第1回 環境構築](/articles/claude-code-01-environment)
-  **コンテキスト関連**:[第4回 コンテキスト管理](/articles/claude-code-04-context)
-  **スキル/コマンドが呼ばれない**:[第5回 スキル & コマンド](/articles/claude-code-05-skills-and-commands)
-  **エージェントが動かない**:[第6回 サブエージェント](/articles/claude-code-06-subagents)
-  **フックが効かない**:[第7回 フック](/articles/claude-code-07-hooks)
-  **MCPが繋がらない**:[第8回 MCP](/articles/claude-code-08-mcp-tools)
-  **精度が上がらない**:[第9回 精度の高いアウトプット](/articles/claude-code-09-prompt-quality)
-  **コマンド一覧**:[付録 A. チートシート](/articles/claude-code-a1-cheatsheet)
-  **事故を未然に防ぐ**:[付録 C. 注意事項](/articles/claude-code-a3-cautions)

## 次へ

→ [付録 C. 注意事項](/articles/claude-code-a3-cautions) で事故が起きる前の予防策を確認しましょう。

| | |
|---|---|
| ⬅ 前へ | [付録 A. チートシート](/articles/claude-code-a1-cheatsheet) |
|  次へ | [付録 C. 注意事項](/articles/claude-code-a3-cautions) |
|  目次 | [README.md](./README.md) |