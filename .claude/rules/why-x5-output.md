<!--
2026-05-23 v10 確定: 1 行 format「<何のため> のため、<何をやる> を行う」に集約。
task-51 Step 3 (2026-05-28): Layer A/B 2 層分割。
-->

# 「何のために何をやるのか」1 行出力ルール (v10、2026-05-23)

メインエージェントは、各作業ステップごとに **「何のために何をやるのか」を 1 行** で先出しする。常時参照 (frontmatter 無し、毎セッション AI が読む)。

> **Layer B (詳細版) Read trigger** (4 条件):
> 1. **違反検出時**: hook BLOCK / warn 注入受領 / regex 不一致
> 2. **規範変更時**: rule 編集 / draft 起案 / 採用 N 条改定
> 3. **新規事案**: 初遭遇 keyword / 例外パターン疑い
> 4. **学習 / dogfood**: task 着手前依存先必読 / harness audit / 副産物整理
>
> 通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。
> 詳細: [why-x5-output.details.md](../rules-details/why-x5-output.details.md)

## format

```
「<何のため (目的)> のため、<何をやる (今のステップ / tool / file)> を行う」
```

## 要件

- ステップごとに 1 行 (ツール呼び出し前 / 別ステップ移行時 / 別 file 編集時)
- 同種の連続操作はまとめて 1 行で良い
- 装飾 (見出し / 表 / 矢印列挙 / 連番セクション) は禁止、純粋な 1 行のみ
- 「何のため」と「何をやる」の **両方が含まれる**

## 思考ロジック (必須、頭の中で踏む)

可視化 (1 行出力) と同等以上に思考ロジックは重要。

1. **何のため (目的)** — システム意義 / ユーザ要求とどう繋がるか
2. **何をやる (今のステップ)** — どの tool / file / 1 ステップか
3. **代替案検討** — 出力には書かないが、必要なら別ステップとして 1 行追記

## 適用範囲

- すべての作業ターン (雑談・短い確認応答も含む)
- 連続して同種の操作を行う場合も、ステップ毎に 1 行表示
- 例外: `feedback_skip_why_x5_for_mode_command.md` 該当 command (`/mode` 等) のみ

## 強制機構

`.claude/hooks/why-x5-reminder.sh` (UserPromptSubmit hook) が、毎ターン本ルールへの遵守を `<system-reminder>` として注入する。

## 判定基準 (出力前 self-check)

- [ ] 1 行 format か (改行 / 見出し / 連番セクションが無いか)
- [ ] 「何のため」と「何をやる」の両方が含まれているか
- [ ] ステップ単位で先出しできているか (tool 呼び出しの前)

## OK 例

- 「install.sh を smoke test するため、tmp dir に実 install を実行する」
- 「規範を v10 化するため、why-x5-output.md を全文書き換える」
- 「user に結果を報告するため、install 完了 summary を 1 行で返す」

## NG 例

- 「【システムの存在意義】【whyN】【現在行っていること】【他の選択肢を取らない理由】」と 4 セクションで書く (v9 format、廃止)
- 「何をやる」だけ書いて「何のため」を省略 (例: 「install.sh を smoke test する」 — NG)
- 1 ステップで 2 行以上書く (例: 改行で目的と作業を分けて書く — NG)

> **例詳細 / 旧 version の format 例**: [why-x5-output.details.md §例詳細](../rules-details/why-x5-output.details.md#例詳細)

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

> **v1→v10 経緯 table (full) / SUPERSEDED 履歴 / 起源詳細**: [why-x5-output.details.md §v1-v10-経緯](../rules-details/why-x5-output.details.md#v1v10-経緯)
