> Layer A: [`why-x5-output.md`](../../rules/why-x5-output.md) §強制機構 / §一時無効化 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 詳細 (Layer B)

- **v10 改訂起源 (2026-05-23)**: user 明示指摘「4 セクション format 不要、何のために何をやるのかを 1 行で毎回出力に変更」を反映。v9 (4 セクション分割: システム意義 / whyN / 現在の作業 / 他選択肢) は冗長で認知負荷が高く廃止。`feedback_why_x5_v10_one_liner.md` (memory) が起源
- **v1→v10 取り違え経緯**: 2025 年末 〜 2026-05 にかけて user との iter で format が 10 回変遷。各版の指摘は [`v1-v10-history.md`](./v1-v10-history.md) 参照。「固定するな」「全任意化するな」「多階層は冗長」「1 セクション混在で並び逆転」等の試行錯誤を経て v10 1 行 format に収束
- **思考ロジック 3 step (何のため / 何をやる / 代替案検討)**: v10 で 1 行出力に集約する代わりに、出力に書かない代替案検討を思考ロジック内で必須化。AI の判断品質を維持したまま出力認知負荷を下げる狙い
- **強制機構 `.claude/hooks/why-x5-reminder.sh`**: UserPromptSubmit hook で毎ターン本 rule への遵守を `<system-reminder>` として注入。v10 移行後も hook は継続稼働、注入内容のみ 1 行 format に更新
- **規範化経緯**: 各版の commit hash は git log で `why-x5-output.md` を辿る。v10 確定 commit は 2026-05-23 (`feedback_why_x5_v10_one_liner.md` memory 起こし日と同日)
- **task-51 Step 3 (2026-05-28)**: Layer A/B 2 層分割を実施。Layer A (~1.5K bytes) を SSoT として残し、v1→v10 経緯 table / SUPERSEDED 履歴 / 拡張例 / 全 feedback memory list を Layer B に退避。常時参照 (frontmatter 無し) の token 負荷を削減
