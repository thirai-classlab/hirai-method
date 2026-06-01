#!/usr/bin/env bash
# mode-session-start.sh — SessionStart hook
#
# 役割 (task-73 案 B で短文化):
#   - セッション開始時に harness の compact status 1 行を出力 (mode / preset / guards / resume / next)
#   - resume 検出時は 1 行で /resume-state 案内
#   - Loop / Normal モードの詳細は in-context rule (.claude/rules/modes.md) に委譲し、
#     mode-enforce.sh の 1 行 pointer で再宣言する (full reminder の二重出力を廃止)
#
# behavior-preserving: mode 判定 / context.md 検出 / feature gate / Normal モード挙動は保持、
#   出力テキストのみ短縮。
#
# 失敗時の挙動: exit 0 のみ。失敗してもセッションをブロックしない (全 status 取得は best-effort)。

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

# stdin は SessionStart hook では使わないが、念のため消費
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

# --- config-loader.sh (best-effort、HC_* env 解決 + is_feature_enabled) ---
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled mode_session_start; then
  exit 0
fi

# project root 解決 (status 取得用、best-effort)
ROOT="${HC_PROJECT_ROOT:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
fi

# --- compact status 各項目 (best-effort、取得失敗は省略して fail-open) ---
HC_SCRIPT="$SCRIPT_DIR/../scripts/hc-config.sh"
PRESET=""
GUARDS=""
if [ -f "$HC_SCRIPT" ]; then
  SUMMARY="$(bash "$HC_SCRIPT" --summary 2>/dev/null || true)"
  # 失敗時: hc-config --summary 取得不可なら guards=/preset= フィールドを省略 (fail-open)
  PRESET="$(printf '%s\n' "$SUMMARY" | awk '/^preset:/{print $2; exit}')"
  GUARDS="$(printf '%s\n' "$SUMMARY" | awk '/^totals:/{print $2"on/"$4"off"; exit}')"
fi

SESSION_CONTEXT_FILE="${ROOT:-.}/.serena/memories/session/context.md"
if [ -f "$SESSION_CONTEXT_FILE" ]; then
  RESUME="available"
else
  RESUME="none"
fi

NEXT=""
LIST_MD="${ROOT:-.}/docs/tasks/list.md"
if [ -f "$LIST_MD" ]; then
  NEXT="$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|.*(🔲|🔄)' "$LIST_MD" 2>/dev/null || true)"
fi

# compact status 1 行を組み立て (取得できた項目のみ)
STATUS="harness: mode=${MODE}"
[ -n "$PRESET" ] && STATUS="$STATUS preset=${PRESET}"
[ -n "$GUARDS" ] && STATUS="$STATUS guards=${GUARDS}"
STATUS="$STATUS resume=${RESUME}"
[ -n "$NEXT" ] && STATUS="$STATUS next=${NEXT}"
STATUS="$STATUS help=/resume-state /hc-config /mode"

{
  printf '<system-reminder>\n'
  printf '%s\n' "$STATUS"
  if [ "$RESUME" = "available" ]; then
    printf '前回 session state あり: /resume-state [loop] で継続、または新規 prompt で開始\n'
  fi
  if [ "$MODE" != "loop" ]; then
    printf 'Normal モード稼働中。長い実装は /mode loop で Loop モードへ切替可 (詳細 .claude/rules/modes.md)。\n'
  fi
  printf '</system-reminder>\n'
}

exit 0
