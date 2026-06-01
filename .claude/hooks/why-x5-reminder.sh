#!/usr/bin/env bash
# UserPromptSubmit hook
#
# 各ターン応答の冒頭で「何のために何をやるのか」を **1 行** で出力するよう促す (advisory)。
# v11 (2026-06-01, task-68 §3.3) — v10 「tool 前に毎回」を「ターン冒頭 1 回」へ緩和。
#   さらに注入文を pointer 短縮 (full rule 本文の長文注入をやめ、短い 1 行 reminder + 参照に)。
#
# 仕組み:
#   - UserPromptSubmit hook は stdin に { "prompt": "..." } を受け取り、
#     stdout に出力したテキストをユーザプロンプトに追加コンテキストとして注入する。
#   - 本 hook は stdin を破棄し、短い <system-reminder> pointer を出力するだけの単純実装。
#
# 環境変数:
#   HC_WHY_X5_DISABLE=1  ... 一時無効化（雑談セッション等で off にする）
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもユーザターンをブロックしない。

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

# config-loader.sh source (is_feature_enabled 関数取得用、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck source=lib/config-loader.sh
  source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled why_x5_enforcement; then
  exit 0   # feature OFF で no-op
fi

# stdin を必ず消費（消費しないと caller が pipe block する可能性がある）
cat > /dev/null 2>&1 || true

# 環境変数で無効化されている場合は何も出さない
if [ "${HC_WHY_X5_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# v11: pointer 短縮注入 (full rule 本文は注入しない)。
# format「<何のため> のため、<何をやる> を行う」をターン冒頭 1 回出す、のみ promote。
cat <<'EOF'
<system-reminder>
このターンの冒頭で「何のために何をやるのか」を **1 行** 先出ししてください (v11)。
format: 「<何のため (目的)> のため、<何をやる (今のステップ / tool / file)> を行う」
- ターン冒頭 1 回でよい (同一ターン内の連続 tool ごとの再掲は不要)。大きな方針転換 / 別 task 移行時のみ追加 1 行可。
- 思考ロジック (目的 → 作業 → 代替案検討) は内部で毎ステップ踏む = 透明性は維持。
詳細規範: `.claude/rules/why-x5-output.md` (v11, 2026-06-01)。
</system-reminder>
EOF

exit 0
