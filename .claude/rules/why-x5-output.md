# Why × N 出力ルール (v7-final、2026-05-14)

メインエージェントは、各作業ステップごとに以下の **2 セクション** を必須で応答に含める。

> **改訂履歴**: 2026-05-14、user 明示指摘 v1-v7 の累積取り違え (6 階層固定 / 3 要件固定 / 全任意 / 1 文 format / ↑ 記号 + ラベル / markdown 表 / § 装飾) を経て確定。format は **【現在行っていること】+【whyN】ラベル**、装飾記号なし、短文改行。`feedback_why_x5_v7_labeled_sections.md` (memory) が起源。
>
> **2026-05-13 改訂** (`feedback_why_x5_depth_and_requirement_link.md` 起源) は本 v7-final で **supersede**。

## 必須 2 セクション

### 1. 【現在行っていること】

1 セクション、短文を改行で並べる。**作業 → 中間 → システム目的** の自然な並び。

- **始点**: 今の直接作業 (具体 tool / 編集 file / 1 ステップ)
- **終点**: システムの目的 / 事業の存在理由
- **中間**: case-by-case (機能 / 課題 / 環境 / 設計など必要な数)
- 中間数は固定しない。3 行で足りるなら 3、7 行必要なら 7
- 1 行は読み手が一目で読める粒度
- 装飾記号 (`↑` / 矢印 / インデント) なし、ラベル ((直接作業) 等) なし、過剰内部用語列挙なし

### 2. 【why1】【why2】【whyN】

不採用にした代替案を 1 セクションずつ、**最低 2 件 (【why1】【why2】) 必須**。各 2 行。

- 1 行目: 代替案 (採らなかった選択肢を 1 行で)
- 2 行目: 非採用理由 (目的 / 副作用 / user 意図とのズレで具体に、generic 不可)

代替案がさらに多い場合は【why3】【why4】… と続ける。

## 適用範囲

- すべての作業ターン (雑談・確認応答も含む)
- 連続して同種の操作を行う場合も、ステップ毎に表示
- 例外: `feedback_skip_why_x5_for_mode_command.md` 該当 command のみ

## 強制機構

`.claude/hooks/why-x5-reminder.sh` (UserPromptSubmit hook) が、毎ターン本ルールへの遵守を `<system-reminder>` として注入する。

## 判定基準 (出力前 self-check)

- [ ] 【現在行っていること】が **作業 → システム目的** まで連鎖して辿れるか
- [ ] 各行が認知負荷低く読めるか (短文 / 記号なし / 過剰用語なし)
- [ ] 【whyN】が **最低 2 件** で各非採用理由が **具体** か (generic 不可)

## Anti-pattern

- 過剰装飾: `↑` 矢印 / `(直接作業)` ラベル / markdown 表 / § 記号 / 過剰インデント
- generic 終着: 「累積価値」「信頼性」「事業価値」「正確性」で止まる
- 紐づき欠落: 作業とシステム目的の因果が辿れない
- 代替案 1 件のみ: 【why1】のみで【why2】不在
- 非採用理由 generic: 「規範違反」「効率低下」のみ、user 要求や目的との具体的ズレ未記載

## サンプル (題材: 教訓 4 件を Serena memory `learning/` に永続化)

```
【現在行っていること】
教訓 4 件を `.serena/memories/learning/` に永続化
L4 学習層の検索 path 登録のため
次セッション以降の教訓再利用機能のため
HIRAI メソッドの再利用可能学習システム実現のため

【why1】
永続化 skip
L4 機能不全のまま放置、システム目的と乖離

【why2】
session/context のみに残す
learning/* 検索 path 外で L4 が拾えない

【why3】
CLAUDE.md に教訓を埋め込む
layer 違いで session 横断学習層と不整合
```

## v1→v7-final 経緯 (再発防止用の取り違え履歴)

| 版 | 構造 | 指摘 |
|---|---|---|
| v1 | 6 階層固定 (system → ... → 作業) | 「固定するな」 |
| v2 | 3 要件固定 (system / 作業 / 紐づき) | 「3 要件も固定するな」 |
| v3 | 全任意化 | 「現在行っていること・他の選択肢は必須」 |
| v4 | 「○○のために○○を行っている」1 文 | 「ではないです、多階層で」 |
| v5 | 多階層 + `↑` 記号 + ラベル | 「認知負荷高い」 |
| v6 | markdown 表 + 視覚記号 | 「【現在行っていること】+【whyN】format で」 |
| v7 | § 等装飾残存 | 「§は不要です」 |
| **v7-final** | **【現在行っていること】+【whyN】、装飾なし、短文改行** | (確定) |

## 一時無効化

雑談セッションや短い確認のみで一時的に off:

```bash
export HC_WHY_X5_DISABLE=1
```

通常運用では **無効化しない**。

## 関連 feedback memory

- `feedback_why_x5_v7_labeled_sections.md` (2026-05-14、本 rule v7-final 改訂の起源)
- `feedback_why_x5_depth_and_requirement_link.md` (2026-05-13、v7-final で supersede)
- `feedback_skip_why_x5_for_mode_command.md` (`/mode` 等 format 省略許可 command 規範)
