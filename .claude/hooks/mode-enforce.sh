#!/usr/bin/env bash
# mode-enforce.sh — UserPromptSubmit hook
#
# 役割: Loop モード稼働中、毎ターンの応答に「停止指示まで AI 推奨で続行」ルールを
#       <system-reminder> として注入する。Normal モードでは no-op。
#
# 失敗時の挙動: exit 0 のみ。失敗してもユーザターンをブロックしない。

set -euo pipefail

# stdin を消費（pipeline block を避ける）
cat > /dev/null 2>&1 || true

# モードローダーを読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mode-loader.sh
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  MODE=$(load_mode)
else
  MODE="normal"
fi

if [ "$MODE" != "loop" ]; then
  # Normal モード: 何もしない
  exit 0
fi

cat <<'EOF'
<system-reminder>
**Loop モード稼働中** — このターンも以下を厳守:

- **ユーザ確認を取らない**: 「どちらにしますか?」「進めてよいですか?」等の確認質問は **禁止**
- **AI 推奨方法を即採用**: Why × 5 で評価し、最善案を直ちに実装に移す
- **自律分解と継続**: 大きなタスクは自分で分解し、最後まで一気通貫で通す
- **停止条件は 3 つのみ**: ユーザの明示的停止指示 / タスク完了 / 致命的エラー
- **Why × 5 表示は省略不可**: ユーザ確認は省くが、思考過程の透明性は維持

Loop モード解除には `/mode normal` を実行。
</system-reminder>
EOF

exit 0
