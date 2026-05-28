---
title: "【claudeCode基礎学習】Claude Code 完全学習ガイド — 全17記事の目次（基礎+応用）"
slug: claude-code-complete-guide
type: tech_articles
subtype: comparison
category: claude-code
thumbnail: ./images/chapters/INDEX-hero.png
author: "平井拓真"
source: "cc研修/INDEX.md"
---

> **この記事の位置づけ**：Claude Code の **基礎情報＋応用情報を全17記事にまとめました**。本記事はその **インデックス（目次）** です。
> **読み方**：第0回から順番に通読しても、必要な記事だけピンポイントで読んでも構いません。各章には「**どんなときに読むべきか**」を併記してあります。
> **対象**：非エンジニア / コードを触り始めた人 / Claude Code をこれから本格的に使いたい人
> **想定総時間**：通読で約11時間（順読み）。困ったときの拾い読みなら 1記事 10〜90分。
> **前提バージョン**：2026年4月時点の Claude Code（v2.1.x / Claude Sonnet 4.6 / Opus 4.7 世代対応）

---

## このガイドの構成

シリーズは **基礎4回 → 応用5回 → 設計4回 → 運用1回 + 付録3冊** の合計17記事で構成されています。

```text
全17記事
├─ Part 1（基礎）         第0〜3回   起動できる状態を作る
├─ Part 2（応用 / コア機能）第4〜8回   CLAUDE.md・スキル・フック・MCP
├─ Part 3（応用 / 精度と統合）第9〜12回 良いプロンプト・ハーネス設計
├─ Part 4（運用と展開）   第13回      役職別パス
└─ 付録 A・B・C                     完全チートシート・トラブル・注意事項
```

順番に読んでも、目次から必要な記事だけ拾い読みしてもOK。各章のリンクの下に **「どんなときに読むべきか」** を書いています。

---

## 全17記事 一覧（読むべきタイミング付き）

### Part 1：はじめての一歩（基礎・約4時間）

| # | タイトル | 所要 | どんなときに読む |
|---|---|---|---|
| **第0回** | [はじめに — なぜいま Claude Code なのか？AIエージェントの現在地](/articles/claude-code-00-introduction) | 10分 | LLM・AIエージェントの全体像を押さえたい |
| **第1回** | [環境構築 — 最大の難関を30分で越える完全ガイド](/articles/claude-code-01-environment) | 30分 | インストール・起動でつまずいた |
| **第2回** | [はじめてのセッション — 起動から終了まで4ステップで体験する基本ループ](/articles/claude-code-02-first-session) | 20分 | 最初の一回を動かしたい |
| **第3回** | [Claude Code を理解する — エージェントの正体・5つのサーフェス・モデル選び](/articles/claude-code-03-understanding) | 45分 | 仕組みとモデル選びに迷う |

---

### Part 2：コア機能を覚える（応用・約4〜5時間）

| # | タイトル | 所要 | どんなときに読む |
|---|---|---|---|
| **第4回** | [コンテキスト管理 — CLAUDE.md・Rules・メモリで「机の上」を整える](/articles/claude-code-04-context) | 60分 | 同じ指示を毎回打ちたくない |
| **第5回** | [スキル & スラッシュコマンド — 辞書とボタンを使い分ける](/articles/claude-code-05-skills-and-commands) | 60分 | 業務を半自動化したい |
| **第6回** | [サブエージェント — 専門家チームを編成して並列で動かす](/articles/claude-code-06-subagents) | 60分 | 大作業を並列で回したい |
| **第7回** | [フック（Hooks）— 校門の警備員に絶対ルールを守らせる](/articles/claude-code-07-hooks) | 60分 | 絶対ルールを強制させたい |
| **第8回** | [外部ツール連携 MCP — USB Type-C 1本で全外部サービスとつなぐ](/articles/claude-code-08-mcp-tools) | 60分 | 外部 SaaS／API と連携したい |

---

### Part 3：精度と統合（応用・約3〜4時間）

| # | タイトル | 所要 | どんなときに読む |
|---|---|---|---|
| **第9回** | [精度の高いアウトプット — 「美味しいやつ」を「豚バラ味噌炒め」に翻訳する](/articles/claude-code-09-prompt-quality) | 45分 | 出力の手戻りが多い |
| **第10回** | [ハーネス設計 — 8つの構成要素をシステムキッチンの引き出しに整理](/articles/claude-code-10-harness-design) | 90分 | ハーネスを設計したい |
| **第11回** | [12のエージェントハーネスパターン — レゴブロックと組立説明書](/articles/claude-code-11-harness-patterns) | 60分 | 業務シナリオに合うカタチを探す |
| **第12回** | [サンプルハーネス活用ガイド — IKEA ショールームで完成形を体験する](/articles/claude-code-12-sample-harness) | 30分 | 完成品を動かして触りたい |

---

### Part 4：運用と展開（任意・約1時間）

| # | タイトル | 所要 | どんなときに読む |
|---|---|---|---|
| **第13回** | [役職別 学習パス — 6コースのレストランメニューから自分用を選ぶ](/articles/claude-code-14-role-based-paths) | 任意 | どこから読むか迷った |

> **旧第13回（実践Tips集）は付録 A. 完全チートシートに統合されました**。コマンド・起動オプション・ショートカットの利用頻度ランキング＋網羅一覧は付録 A をご参照ください。

---

### 付録（リファレンス・3冊）

| # | タイトル | 用途 | どんなときに読む |
|---|---|---|---|
| **付録 A** | [完全チートシート — 利用頻度ランキング＋網羅早見表](/articles/claude-code-a1-cheatsheet) | 印刷推奨 | コマンド・起動オプション・ショートカットを頻度順／網羅で引きたい |
| **付録 B** | [トラブルシューティング — 詰まったときの病院問診票](/articles/claude-code-a2-troubleshooting) | 詰まったら | `claude` が動かない／挙動が変 |
| **付録 C** | [注意事項 — 包丁を握る前に知っておくべき予防マニュアル](/articles/claude-code-a3-cautions) | **学習前必読** | 学習開始前と最初のセッション前 |

---

## おすすめ学習パス（役職別）

「全部読まなきゃダメ?」と思ったら、自分にあったコースだけどうぞ。

| パス | 対象 | 所要 | 重点記事 |
|---|---|---|---|
| **非エンジニア** | 営業・CS・マーケ・PM | 4時間 | 第0〜4回 / 第13回 / 付録 A |
| **エンジニア初級** | 1〜3年目 | 8時間 | 第0〜8回 / 第12回 |
| **エンジニア中級** | 4〜10年目 | 11時間 | 全章 + 自分用ハーネス |
| **エンジニア上級** | 10年+ | 6時間 | 第9〜13回 / 自動化深掘り |
| **テックリード** | チームリーダー | 7時間 | 第4回 + 第8回 + 第13回 / チーム導入 |
| **CTO / VPoE** | 経営層 | 4時間 | 第0回 / 第13回 / 投資判断 |

詳細は [第13回 役職別 学習パス](/articles/claude-code-14-role-based-paths) を参照。

---

## 困ったときの早見表

| やりたいこと | 開く記事 |
|---|---|
| 起動コマンド・キーボードショートカットを調べたい | [付録 A. チートシート](/articles/claude-code-a1-cheatsheet) |
| `claude` が動かない | [付録 B. トラブル](/articles/claude-code-a2-troubleshooting) |
| 権限・機密情報・事故予防の確認 | [付録 C. 注意事項](/articles/claude-code-a3-cautions) |
| CLAUDE.md の書き方 | [第4回 コンテキスト管理](/articles/claude-code-04-context) |
| Rules（スコープ付きルール）を使いたい | [第4回 §4 Rules](/articles/claude-code-04-context) |
| 外部APIを叩きたい | [第8回 MCP](/articles/claude-code-08-mcp-tools) |
| プロンプトの精度を上げたい | [第9回 精度の高いアウトプット](/articles/claude-code-09-prompt-quality) |
| 既存スキルを探したい | [第5回 → skills.sh](/articles/claude-code-05-skills-and-commands) |
| フックを書きたい | [第7回 フック](/articles/claude-code-07-hooks) |
| 自分用ハーネスを作りたい | [第10回 構成要素](/articles/claude-code-10-harness-design) → [第12回 サンプル](/articles/claude-code-12-sample-harness) |
| 業務シナリオに合うパターンを探したい | [第11回 12パターン](/articles/claude-code-11-harness-patterns) |
| 役職別の最短ルート | [第13回 役職別パス](/articles/claude-code-14-role-based-paths) |

---

## 参考動画（3本）

このシリーズの内容は、以下の3本の動画にも大きく影響を受けています。**音声で聞きたい派の方はぜひ**。

### 1. ClaudeCodeを本気の徹底解説（まさおAI）

固有名詞・具体性が精度を上げる、という考え方の決定版。第9回「精度の高いアウトプット」に対応。

[【超有料級】ClaudeCodeを本気の徹底解説（まさおAI）](https://www.youtube.com/watch?v=WRbG_22RfeI)

<iframe width="560" height="315" src="https://www.youtube.com/embed/WRbG_22RfeI" title="ClaudeCodeを本気の徹底解説" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### 2. 12のエージェントハーネスパターン（まさやん）

第11回の12パターンの直接の元ネタ。現場で使える具体的なハーネス設計例が豊富。

[Claude Codeによる12のエージェントハーネスパターン（まさやん）](https://www.youtube.com/watch?v=FfABuQiDw8Q)

<iframe width="560" height="315" src="https://www.youtube.com/embed/FfABuQiDw8Q" title="Claude Codeによる12のエージェントハーネスパターン" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

### 3. ハーネスエンジニアリング基礎（数理の弾丸）

第10回「ハーネス設計」の理論的な背骨。「コンテキスト80%超えで精度急落」など、本書の数値もここから。

[Claude Codeハーネスエンジニアリング まず抑えるべき基礎知識（数理の弾丸）](https://www.youtube.com/watch?v=hxCEABf0Nfc)

<iframe width="560" height="315" src="https://www.youtube.com/embed/hxCEABf0Nfc" title="Claude Codeハーネスエンジニアリング まず抑えるべき基礎知識" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>

---

## 表記ルール

- **コマンド**：`claude` `npm` のように `code` で表記
- **ファイル名**：`CLAUDE.md` のように `code` 表記
- **クリック / 入力**：「**ファイル → 開く** をクリック」のように太字で
- **重要**：危険な操作・破壊的変更には注意書きを添える
- **日本語ファースト**：専門用語は日本語化して、必要に応じてカタカナ・英語併記

---

## 公式リソース

- [Claude Code 公式ドキュメント](https://code.claude.com/docs/en/overview)
- [Anthropic Engineering Blog](https://www.anthropic.com/engineering)
- [GitHub: anthropics/claude-code](https://github.com/anthropics/claude-code)
- [skills.sh — スキルマーケットプレイス](https://skills.sh/)

---

## 修了

![](./images/outros/INDEX-outro.png)

全17記事を完走したら、あなたは **Claude Code を業務に組み込む準備** ができています。

次のステップ：

1. **自分用ハーネスを構築する** — [第12回サンプル](/articles/claude-code-12-sample-harness) を雛形に
2. **チームに展開する** — [第13回テックリードパス](/articles/claude-code-14-role-based-paths)
3. **コマンドを引きながら使う** — [付録 A. 完全チートシート](/articles/claude-code-a1-cheatsheet)
4. **新機能をキャッチアップ** — [Claude Code 公式ドキュメント](https://code.claude.com/docs/en/overview)

---

> 詰まったら [付録 B. トラブルシューティング](/articles/claude-code-a2-troubleshooting) → それでも分からなければ `/help` を実行。
> 安全運用に不安があれば [付録 C. 注意事項](/articles/claude-code-a3-cautions) を再確認。
