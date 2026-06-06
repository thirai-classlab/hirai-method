<!--
2026-05-23 v10 確定: 1 行 format「<何のため> のため、<何をやる> を行う」に集約。
task-51 Step 3 (2026-05-28): Layer A/B 2 層分割。
task-67 (2026-06-01): details.md → 断片群 (why-x5-output/) に再構造化。
-->

# 「何のために何をやるのか」1 行出力ルール (v11、2026-06-01 緩和)

メインエージェントは、**各ターン冒頭に 1 回** 「何のために何をやるのか」を 1 行で先出しする。常時参照 (frontmatter 無し、毎セッション AI が読む)。

> **v11 緩和 (task-68 §3.3、research §11 F2-4/F3-3/F1-5)**: v10 の「tool 呼び出し前に毎回」を「**ターン冒頭 1 回**」へ緩和。同一ターン内の連続 tool 呼び出しごとの再掲は不要 (prose↔tool 往復頻度を下げ tool-call markup 崩れリスクを減らす)。**大きな方針転換 / 別 task への移行時のみ追加 1 行可**。思考ロジック (下記) は内部で毎ステップ踏む = 透明性は維持。memory [[feedback_why_x5_once_per_turn]] と整合。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: 各 § 末尾 pointer から該当断片を直リンク Read (断片群: [`../rules-details/why-x5-output/`](../rules-details/why-x5-output/))

## format

```
「<何のため (目的)> のため、<何をやる (今のステップ / tool / file)> を行う」
```

## 要件

- **ターン冒頭に 1 回** 先出し (v11 緩和)。同一ターン内の tool 呼び出しごとの再掲は不要
- 大きな方針転換 / 別 task 移行時のみ追加 1 行可 (それ以外は冒頭 1 行で当該ターンの作業群をカバー)
- 装飾 (見出し / 表 / 矢印列挙 / 連番セクション) は禁止、純粋な 1 行のみ
- 「何のため」と「何をやる」の **両方が含まれる**

## 思考ロジック (必須、頭の中で踏む)

可視化 (1 行出力) と同等以上に思考ロジックは重要。

1. **何のため (目的)** — システム意義 / ユーザ要求とどう繋がるか
2. **何をやる (今のステップ)** — どの tool / file / 1 ステップか
3. **代替案検討** — 出力には書かないが、必要なら別ステップとして 1 行追記

## 適用範囲

- すべての作業ターン冒頭 (雑談・短い確認応答も含む) に 1 回
- 同一ターン内で複数 tool / 複数 file を扱う場合も、冒頭 1 行でターン全体の目的×作業を表現 (個別 tool ごとの再掲不要)
- 例外: `feedback_skip_why_x5_for_mode_command.md` 該当 command (`/mode` 等) のみ

## 強制機構

`.claude/hooks/why-x5-reminder.sh` (SessionStart wrapper child) が **session 開始時に 1 度**本ルールの compact pointer を `<system-reminder>` で提示する。本 rule 全文は frontmatter-less 常時参照として **毎ターン context に load 済**のため、ターン冒頭 1 行の遵守はその in-context rule に基づく (hook の毎ターン注入には依存しない)。

> 起源・規範化経緯: [why-x5-output/origin.md](../rules-details/why-x5-output/origin.md)

## 判定基準 (出力前 self-check)

- [ ] 1 行 format か (改行 / 見出し / 連番セクションが無いか)
- [ ] 「何のため」と「何をやる」の両方が含まれているか
- [ ] ターン冒頭で先出しできているか (同一ターン内 tool ごとの過剰再掲をしていないか)

## OK 例

- 「install.sh を smoke test するため、tmp dir に実 install を実行する」
- 「規範を v10 化するため、why-x5-output.md を全文書き換える」
- 「user に結果を報告するため、install 完了 summary を 1 行で返す」

## NG 例

- 「【システムの存在意義】【whyN】【現在行っていること】【他の選択肢を取らない理由】」と 4 セクションで書く (v9 format、廃止)
- 「何をやる」だけ書いて「何のため」を省略 (例: 「install.sh を smoke test する」 — NG)
- 1 ステップで 2 行以上書く (例: 改行で目的と作業を分けて書く — NG)
- **(v11)** 同一ターン内で tool 呼び出しごとに毎回 why 行を再掲して冗長化 (ターン冒頭 1 行でカバー、方針転換時のみ追加)

> 拡張例 (廃止 format 4 種詳細): [why-x5-output/examples.md](../rules-details/why-x5-output/examples.md)

## 一時無効化

雑談セッションや短い確認のみで一時的に off:

```bash
export HC_WHY_X5_DISABLE=1
```

通常運用では **無効化しない**。

## 関連 feedback memory (代表)

- `feedback_why_x5_v10_one_liner.md` (2026-05-23、本 rule v10 改訂の起源)
- `feedback_why_x5_once_per_turn.md` (v10 でも継続有効、ターン冒頭 1 回 / ステップ単位 / 未来時制)
- `feedback_skip_why_x5_for_mode_command.md` (`/mode` 等 format 省略許可 command 規範、v10 でも有効)

> feedback memory 全件 (SUPERSEDED 含む): [why-x5-output/feedback-memory.md](../rules-details/why-x5-output/feedback-memory.md)
> v1→v10 経緯 table (full): [why-x5-output/v1-v10-history.md](../rules-details/why-x5-output/v1-v10-history.md)

---
> **project 固有の追補・override は `.claude/project-rules/why-x5-output.md` に書く** (本 file は harness 所有、`install.sh --update` で上書きされる。project 固有編集は下記 import 先へ)。
@../project-rules/why-x5-output.md
