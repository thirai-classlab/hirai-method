#!/usr/bin/env bash
# UserPromptSubmit hook
#
# 各ターン応答で 【現在行っていること】+【whyN】format をメインエージェントに強制する。
# v7-final (2026-05-14)、装飾記号なし、短文改行。
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

set -euo pipefail

# stdin を必ず消費（消費しないと caller が pipe block する可能性がある）
cat > /dev/null 2>&1 || true

# 環境変数で無効化されている場合は何も出さない
if [ "${HC_WHY_X5_DISABLE:-0}" = "1" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
このターンの応答では、作業ステップごとに必ず以下の 2 セクションを明示してください。
省略・要約・「重要なものだけ表示」は不可。雑談・短い確認応答にも適用します。
詳細規範: `.claude/rules/why-x5-output.md` (v7-final, 2026-05-14)。

【現在行っていること】
- 短文を改行で並べる
- 作業 → 中間 → システム目的 の自然な並び
- 中間数 case-by-case (1 行一目粒度)
- 装飾記号 (↑ / 矢印 / ラベル / 表 / § / インデント) なし

【why1】【why2】【whyN】
- 不採用にした代替案を 1 セクションずつ
- 最低 2 件 (【why1】【why2】) 必須
- 各 2 行: 1 行目=代替案、2 行目=非採用理由 (目的 / user 意図とのズレで具体に、generic 不可)

出力前 self-check:
- [ ] 【現在行っていること】が 作業 → システム目的 まで連鎖して辿れるか
- [ ] 各行が短文 / 記号なし / 過剰用語なしで認知負荷低いか
- [ ] 【whyN】が最低 2 件で各非採用理由が具体か (generic 不可)

注意:
- ツール呼び出しの前にこの 2 セクションを必ず先出しすること (事後ではなく事前)
- 連続して同種の操作を行うときは、まとめてではなくステップ毎に表示すること
</system-reminder>
EOF

exit 0
