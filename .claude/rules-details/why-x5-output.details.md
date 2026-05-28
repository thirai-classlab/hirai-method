---
paths: []
related: why-x5-output.md
---

# 「何のために何をやるのか」1 行出力ルール — 詳細版 (Layer B)

> Layer A: [`why-x5-output.md`](../rules/why-x5-output.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

本 file は Layer A の SSoT を補完する詳細解説。v1→v10 経緯 table (full、10 版分の改訂理由 + user 指摘) / SUPERSEDED 履歴 / 旧 version の format 例 / 関連 feedback memory 全件 list / v10 改訂の起源を含む。Read trigger 4 条件は Layer A 冒頭参照。

## 例詳細

### OK 例 (拡張)

- 「install.sh を smoke test するため、tmp dir に実 install を実行する」
- 「規範を v10 化するため、why-x5-output.md を全文書き換える」
- 「user に結果を報告するため、install 完了 summary を 1 行で返す」
- 「Layer A サイズ削減のため、v1→v10 経緯 table を Layer B に退避する」
- 「subagent 並列起動のため、Task tool を `run_in_background: true` で 3 件起動する」

### NG 例 (拡張、廃止 format 4 種)

- **v9 format (4 セクション分割、2026-05-23 廃止)**:
  ```
  【システムの存在意義】... 【whyN】... 【現在行っていること】... 【他の選択肢を取らない理由】...
  ```
  → 冗長で認知負荷が高く廃止。v10 で 1 行に集約。

- **v8 format (1 セクション混在、目的→中間→作業、2026-05-14 廃止)**:
  ```
  最終的なシステム目的: ハーネスの信頼性向上
  ↑ そのために規範を整備
  ↑ そのために why-x5-output.md を書き換え (現在の作業)
  ```
  → 多階層 + `↑` 記号で認知負荷高い、user 「冗長、不要」指摘。

- **v7-final format (1 セクション混在、作業→中間→目的、2026-05-14 廃止)**:
  ```
  why-x5-output.md を書き換え (現在の作業)
  ↓ そのために規範を整備
  ↓ そのためにハーネスの信頼性向上
  ```
  → 「最終的なシステム目的 → 必要な機能 に繋がっていません」指摘。

- **「何のため」省略 (例: 「install.sh を smoke test する」だけ)**:
  → ステップは可視化されるが、システム目的との接続が失われる。

- **「他の選択肢を取らない理由」を毎回 3 件矢印 format で書く (v9 廃止)**:
  → 代替案検討は思考ロジック内で完結、出力には書かない。

## v1→v10 経緯

再発防止用の取り違え履歴 (10 版分):

| 版 | 構造 / 並び | 指摘 | 廃止日 |
|---|---|---|---|
| v1 | 6 階層固定 | 「固定するな」 | 〜 |
| v2 | 3 要件固定 | 「3 要件も固定するな」 | 〜 |
| v3 | 全任意化 | 「現在行っていること・他の選択肢は必須」 | 〜 |
| v4 | 「○○のために○○を行っている」1 文 | 「ではないです、多階層で」 | 〜 |
| v5 | 多階層 + `↑` 記号 + ラベル | 「認知負荷高い」 | 〜 |
| v6 | markdown 表 + 視覚記号 | 「【現在行っていること】+【whyN】format で」 | 〜 |
| v7 | § 等装飾残存 | 「§は不要です」 | 〜 |
| v7-final | 1 セクション混在 (作業 → 中間 → 目的) | 「最終的なシステム目的 → 必要な機能 に繋がっていません」 | 2026-05-14 |
| v8 | 1 セクション混在 並び逆転 (目的 → 中間 → 作業) | 「一番上をシステム目的、一番下を現在の作業」 | 2026-05-14 |
| v9 | 4 セクション分割 + 思考ロジック (何 → 選択肢 → 選定) 強制 | 「冗長、不要」 | 2026-05-23 |
| **v10** | **1 行 format「<何のため> のため、<何をやる> を行う」** | 「何のために何をやるのかを 1 行で毎回出力に変更」 | (現行) |

## 関連 feedback memory (全件)

| memory | 状態 | 説明 |
|---|---|---|
| `feedback_why_x5_v10_one_liner.md` | 現行 (2026-05-23) | v10 改訂の起源、1 行 format への集約根拠 |
| `feedback_why_x5_once_per_turn.md` | 現行 | ターン冒頭 1 回 / ステップ単位 / 未来時制で書く運用補足 (v10 でも継続有効) |
| `feedback_skip_why_x5_for_mode_command.md` | 現行 | `/mode` 等 format 省略許可 command 規範 (v10 でも有効) |
| `feedback_why_x5_v9_four_sections.md` | **SUPERSEDED** (2026-05-23) | v9 4 セクション format、v10 で 1 行化、entry は経緯保持のみ |
| `feedback_why_x5_v8_top_purpose_bottom_work.md` | **SUPERSEDED** (2026-05-14) | v8 1 セクション混在、v9 で 4 セクション分割化、間接 supersede |
| `feedback_why_x5_v7_labeled_sections.md` | **SUPERSEDED** (2026-05-14) | v7-final 1 セクション混在 旧並び、v9 で間接 supersede |
| `feedback_why_x5_v7_link_to_system_purpose.md` | **SUPERSEDED** (2026-05-23) | v7 運用補足 (中間階層をシステム意義まで繋ぐ)、v10 で「何のため」に統合 |
| `feedback_why_x5_depth_and_requirement_link.md` | **SUPERSEDED** (2026-05-14) | Why × 5 因果連鎖、v9 で間接 supersede |

## 起源

- **v10 改訂起源 (2026-05-23)**: user 明示指摘「4 セクション format 不要、何のために何をやるのかを 1 行で毎回出力に変更」を反映。v9 (4 セクション分割: システム意義 / whyN / 現在の作業 / 他選択肢) は冗長で認知負荷が高く廃止。`feedback_why_x5_v10_one_liner.md` (memory) が起源
- **v1→v10 取り違え経緯**: 2025 年末 〜 2026-05 にかけて user との iter で format が 10 回変遷。各版の指摘は上記 table 参照。「固定するな」「全任意化するな」「多階層は冗長」「1 セクション混在で並び逆転」等の試行錯誤を経て v10 1 行 format に収束
- **思考ロジック 3 step (何のため / 何をやる / 代替案検討)**: v10 で 1 行出力に集約する代わりに、出力に書かない代替案検討を思考ロジック内で必須化。AI の判断品質を維持したまま出力認知負荷を下げる狙い
- **強制機構 `.claude/hooks/why-x5-reminder.sh`**: UserPromptSubmit hook で毎ターン本 rule への遵守を `<system-reminder>` として注入。v10 移行後も hook は継続稼働、注入内容のみ 1 行 format に更新
- **規範化経緯**: 各版の commit hash は git log で `why-x5-output.md` を辿る。v10 確定 commit は 2026-05-23 (`feedback_why_x5_v10_one_liner.md` memory 起こし日と同日)
- **task-51 Step 3 (2026-05-28)**: Layer A/B 2 層分割を実施。Layer A (~1.5K bytes) を SSoT として残し、v1→v10 経緯 table / SUPERSEDED 履歴 / 拡張例 / 全 feedback memory list を Layer B に退避。常時参照 (frontmatter 無し) の token 負荷を削減
