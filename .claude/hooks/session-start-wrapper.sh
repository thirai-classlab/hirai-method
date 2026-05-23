#!/usr/bin/env bash
# session-start-wrapper.sh — SessionStart hook orchestrator (task-25 Sub-epic A2)
#
# 役割:
#   既存 SessionStart hooks を **並列実行** してセッション起動時間を短縮する。
#   各 hook は background で起動 + wait で同期、stdout は順序維持のため一時 buffer
#   経由で集約。stderr は tag prefix 付きで集約。
#
# 設計方針 (案 D 採用):
#   - 既存 hook 自体は無改変 (surgical changes、karpathy-guidelines 遵守)
#   - 各 hook は per-hook timeout (5s) で wrap、1 hook fail は全体に伝播しない (fail-open)
#   - stdout は file buffer → 起動順に concat で出力 (stable order)
#   - stderr は tag prefix 付き集約 ([hook-name] ...)
#   - wrapper 自体も fail-open (exit 0)
#
# 失敗時の挙動: 個別 hook 失敗 → tag 付き warn を stderr、wrapper exit 0 継続。
#
# 環境変数:
#   HC_SESSION_START_PARALLEL_TIMEOUT_SEC: per-hook timeout 秒 (default 5)
#   HC_SESSION_START_PARALLEL_ENABLED: false で全 hook をシリアル実行 (default true)
#   HC_SESSION_START_PARALLEL_HOOKS: コロン区切りで hook list 上書き (testing用)

set -uo pipefail  # CLAUDE.md Critical Lessons HIGH: file-top errexit 禁止

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# プロジェクト直下で実行
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
fi

# stdin は SessionStart hook では使わないが、念のため消費
STDIN_BUF=""
if [ ! -t 0 ]; then
  STDIN_BUF=$(cat 2>/dev/null || true)
fi

# Default hook list (順序は出力 stable order に使われる)
DEFAULT_HOOKS=(
  "init-tasks-on-start"
  "check-required-env"
  "improvement-proposal"
  "mode-session-start"
  "mode-enforce"
  "why-x5-reminder"
  "next-actions-surface"
  "mode-asana-prompt"
  "check-serena-mcp"
  "session-help-surface"
)

# Hook list は env で上書き可能 (testing)
if [ -n "${HC_SESSION_START_PARALLEL_HOOKS:-}" ]; then
  IFS=':' read -ra HOOKS <<< "$HC_SESSION_START_PARALLEL_HOOKS"
else
  HOOKS=("${DEFAULT_HOOKS[@]}")
fi

# Per-hook timeout (default 5s)
TIMEOUT_SEC="${HC_SESSION_START_PARALLEL_TIMEOUT_SEC:-5}"

# Parallel enabled (default true)
PARALLEL_ENABLED="${HC_SESSION_START_PARALLEL_ENABLED:-true}"

# Workspace for stdout/stderr buffers
WORK_DIR=$(mktemp -d -t "session-start-wrapper.XXXXXX" 2>/dev/null) || {
  # mktemp fail → silent serial fallback
  for hook in "${HOOKS[@]}"; do
    hook_path="$SCRIPT_DIR/${hook}.sh"
    [ -f "$hook_path" ] || continue
    echo "$STDIN_BUF" | bash "$hook_path" 2>/dev/null || true
  done
  exit 0
}

# Cleanup on exit
cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Detect timeout command (BSD/Linux compatibility)
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
fi

# run_hook: 1 hook を実行、stdout を $WORK_DIR/<hook>.out に、stderr を $WORK_DIR/<hook>.err に
run_hook() {
  local hook="$1"
  local hook_path="$SCRIPT_DIR/${hook}.sh"
  local out_file="$WORK_DIR/${hook}.out"
  local err_file="$WORK_DIR/${hook}.err"

  if [ ! -f "$hook_path" ]; then
    echo "[${hook}] hook file not found: $hook_path" > "$err_file"
    return 0
  fi

  local rc=0
  if [ -n "$TIMEOUT_CMD" ]; then
    echo "$STDIN_BUF" | "$TIMEOUT_CMD" "$TIMEOUT_SEC" bash "$hook_path" > "$out_file" 2> "$err_file"
    rc=$?
    if [ "$rc" -eq 124 ]; then
      # timeout の exit code (BSD/GNU 共通)
      echo "[${hook}] TIMEOUT (>${TIMEOUT_SEC}s)" >> "$err_file"
    fi
  else
    echo "$STDIN_BUF" | bash "$hook_path" > "$out_file" 2> "$err_file"
    rc=$?
  fi

  # fail-open: rc は常に 0 を返す
  return 0
}

# 並列 or シリアル実行
if [ "$PARALLEL_ENABLED" = "true" ]; then
  # 並列起動
  for hook in "${HOOKS[@]}"; do
    run_hook "$hook" &
  done
  wait
else
  # シリアル実行 (testing用 / fallback)
  for hook in "${HOOKS[@]}"; do
    run_hook "$hook"
  done
fi

# stdout 集約 (起動順 = $HOOKS 順) → stable order
for hook in "${HOOKS[@]}"; do
  out_file="$WORK_DIR/${hook}.out"
  if [ -f "$out_file" ] && [ -s "$out_file" ]; then
    cat "$out_file"
  fi
done

# stderr 集約 (tag prefix 付き)
for hook in "${HOOKS[@]}"; do
  err_file="$WORK_DIR/${hook}.err"
  if [ -f "$err_file" ] && [ -s "$err_file" ]; then
    # tag prefix が既に付いている entry はそのまま、それ以外は付与
    while IFS= read -r line; do
      if [[ "$line" == "[${hook}]"* ]]; then
        echo "$line" >&2
      else
        echo "[${hook}] $line" >&2
      fi
    done < "$err_file"
  fi
done

exit 0
