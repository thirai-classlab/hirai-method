#!/usr/bin/env bash
# why-x5-reminder.sh — SessionStart wrapper child (session-start-wrapper.sh DEFAULT_HOOKS)
#
# session 開始時に 1 度、「何のために何をやるのか」を **1 行** で出すルールの compact pointer を
# <system-reminder> として提示する (advisory)。
# v11 (2026-06-01, task-68 §3.3) — 「ターン冒頭 1 回」規範。
# task-73 案 B: full 説明を 1-2 行 pointer へ短縮。本 rule 全文は frontmatter-less 常時参照として
#   毎ターン context に load 済のため、ターン冒頭 1 行の遵守は in-context rule に基づく。
#
# 環境変数:
#   HC_WHY_X5_DISABLE=1  ... 一時無効化（雑談セッション等で off にする）
#
# 失敗時の挙動:
#   - exit 0 のみ。失敗してもセッションをブロックしない。

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

# config-loader.sh source (is_feature_enabled 関数取得用、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck source=lib/config-loader.sh
  source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2 + task-104 W1-8 child toggle)
# 親 (why_x5_enforcement) と子 (why_x5_reminder) の両方 check、どちらか OFF なら skip。
# 子 toggle は dispatcher-manifest SessionStart bootstrap feature_key 用 (finer-grained control)、
# 親 toggle は grouped feature 用 (why-x5-reminder + why-x5-violation-detect 一括制御)。
if command -v is_feature_enabled >/dev/null 2>&1; then
  if ! is_feature_enabled why_x5_enforcement; then
    exit 0   # 親 feature OFF で no-op
  fi
  if ! is_feature_enabled why_x5_reminder; then
    exit 0   # 子 feature OFF で no-op (task-104)
  fi
fi

# stdin を必ず消費（消費しないと caller が pipe block する可能性がある）
cat > /dev/null 2>&1 || true

# 環境変数で無効化されている場合は何も出さない
if [ "${HC_WHY_X5_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# task-73 案 B: 1-2 行 pointer 短縮 (full rule 本文は in-context)
cat <<'EOF'
<system-reminder>
why-x5: 各ターン冒頭に1行「<何のため>のため<何をやる>を行う」(目的×作業)。詳細 .claude/rules/why-x5-output.md
</system-reminder>
EOF

exit 0
