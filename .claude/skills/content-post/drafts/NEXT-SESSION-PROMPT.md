# 新セッション 初回プロンプト

以下を新セッションの最初の発言としてコピペしてください:

---

```
前回セッションの引き継ぎ資料を読んで、Salesforce 3記事の画像再生成を続けてください。

【引き継ぎ資料】
/Users/t.hirai/work/雑務/.claude/skills/content-post/drafts/HANDOVER-2026-04-30.md

【現状】
- 3記事の本文markdown修正は完了済み（sf-object-config-jr.md / sf-permission-training-jr.md / sf-reports-analytics-jr.md）
- sf-object-config-tech-jr の画像13枚を HTML+Playwright で再生成したが品質に問題あり（取消線・英語ラベル残存・トリミング不良）
- 残り2記事(sf-permission-tech-jr 15枚、sf-reports-analytics-tech-jr 12枚)は未着手

【次にやること】
1. ai-image-gen スキル(/Users/t.hirai/.claude/skills/ai-image-gen/) を使って画像を再生成
   - モデル候補: openai/gpt-image-2 (テキスト混在に強い) または bfl/flux-2-pro (手書きスケッチ風)
   - 参照スタイル: スケッチノート風 (https://d2f75plg0t6qwk.cloudfront.net/thumbnail-gallery/t374-sketchnote-20260426-061945-1.webp)
   - 内容は元PNGの設計を維持し、テキストは日本語SF UI公式表記のみ
   - 見切れ厳禁
2. まず sf-object-config-tech-jr の13枚から着手し、ユーザに1枚レビューしてもらってから残りを並列生成
3. 完了後、3記事すべてを post.ts --update で再投稿

【最初にやってほしいこと】
- 引き継ぎ資料を読んで現状を把握
- sf-object-config-tech-jr の 13 枚のうち最も簡単な「body-layers」(2560×1440 / 4段モデル) から、ai-image-gen で1枚試作
- 試作のプロンプト案を提示してから生成

注意事項:
- 大きな画像 (2560x1440 / 3072x1728) を Read で複数開くとコンテキスト制限にかかる。確認時は1-2枚ずつに留める
- サブエージェントを並列利用可（前回は3並列で作業した）
- ユーザのSalesforce日本語UIのこだわり: API値・固有名詞 (Apex/Lightning/Trailhead/__c) 以外は全て日本語表記
```

---

## 補足（このファイルは引き継ぎメモ用、新セッションには貼らなくてOK）

新セッションが正常にスタートしたら、以下の順で進めると効率的:

1. HANDOVER-2026-04-30.md を Read
2. drafts/sf-jp-glossary.md を Read（用語辞書）
3. ai-image-gen の SKILL.md を Read
4. 試作 1 枚（body-layers）→ ユーザレビュー
5. レビュー OK 後、サブエージェント 3 並列で残り 12 枚（sf-object-config-tech-jr 完了）
6. sf-permission-tech-jr 15 枚 → 同様に
7. sf-reports-analytics-tech-jr 12 枚 → 同様に
8. 3 記事すべて post.ts --update で再投稿

**サブエージェント並列起動時の注意**: ai-image-gen は API 課金がかかるため、まず 1 枚試作 → ユーザ承認 → 並列展開 のフローを徹底する。
