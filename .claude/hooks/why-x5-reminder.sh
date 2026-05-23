#!/usr/bin/env bash
# UserPromptSubmit hook
#
# 各ターン応答の冒頭で「何のために何をやるのか」を **1 行** で出力するよう強制する。
# v10 (2026-05-23) — v9 の 4 セクション format を廃止し、1 行 format に統合。
#
# 仕組み:
#   - Claude Code の UserPromptSubmit hook は stdin に { "prompt": "..." } を受け取り、
#     stdout に出力したテキストをユーザプロンプトに追加コンテキストとして注入する。
#   - 本 hook は stdin を破棄し、固定の <system-reminder> を出力するだけの単純実装。
#
# 環境変数:
#   HC_WHY_X5_DISABLE=1  ... 一時無効化（雑談セッション等で off にする）
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもユーザターンをブロックしない。

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

# stdin を必ず消費（消費しないと caller が pipe block する可能性がある）
cat > /dev/null 2>&1 || true

# 環境変数で無効化されている場合は何も出さない
if [ "${HC_WHY_X5_DISABLE:-0}" = "1" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
このターンの応答では、作業ステップごとに **「何のために何をやるのか」を 1 行** で先出ししてください。
詳細規範: `.claude/rules/why-x5-output.md` (v10, 2026-05-23)。

format:
  「<何のため (目的)> のため、<何をやる (今のステップ / tool / file)> を行う」

要件:
- ステップごとに 1 行 (ツール呼び出し前 / 別ステップ移行時 / 別 file 編集時)
- 同種の連続操作はまとめて 1 行で良い
- 4 セクション format (システム意義 / whyN / 現在の作業 / 他選択肢) は **v10 で廃止**
- 装飾 (見出し / 表 / 矢印列挙) は禁止、純粋な 1 行のみ

思考ロジック (必須、頭の中で踏む):
1. 何のため (目的) — システム / ユーザ要求とどう繋がるか
2. 何をやる (今のステップ) — どの tool / file / 1 ステップか
3. 代替案検討 — 出力には書かないが、必要なら別ステップとして 1 行追記

例:
- 「install.sh を smoke test するため、tmp dir に実 install を実行する」
- 「規範を v10 化するため、why-x5-output.md を全文書き換える」

NG 例:
- 4 セクション (システム意義 / whyN / 現在の作業 / 他選択肢) を全部書く
- 「何のため」を省略して「何をやる」だけ書く
- 1 ステップで 2 行以上書く

注意:
- ツール呼び出しの前にこの 1 行を必ず先出しすること
- 雑談・短い確認応答も同様 (例: 「user に install 完了を報告するため、結果サマリを返す」)
</system-reminder>
EOF

exit 0
