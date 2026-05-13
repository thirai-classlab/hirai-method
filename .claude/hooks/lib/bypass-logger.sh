#!/usr/bin/env bash
# .claude/hooks/lib/bypass-logger.sh
# Centralized bypass logging — 全 hook の env-var bypass を統一フォーマットで
# .claude/.workflow-state/bypass.log に記録する共通ライブラリ。
#
# 役割:
#   各 hook が env-var (例: ECC_WORKFLOW_GUARD_OFF / HC_WORKFLOW_GUARD_ENABLED=false)
#   で skip された際に audit log を 1 行 append する。
#   形式は .claude/.workflow-state/bypass.log.template と一致:
#     <ISO-8601> | <session_id> | <hook_name> | <env_var> | <reason>
#
# 設計:
#   - set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)
#   - 失敗しても hook 本体を止めない (mkdir / printf を best-effort)
#   - reason 未指定時は "(not provided)"
#   - session_id 未取得時は "unknown"
#
# 使い方:
#   source "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/bypass-logger.sh"
#   log_bypass "workflow-guard" "ECC_WORKFLOW_GUARD_OFF" "$ECC_BYPASS_REASON"
#
# Args:
#   $1 = hook_name  (例: "workflow-guard")
#   $2 = env_var    (例: "ECC_WORKFLOW_GUARD_OFF")
#   $3 = reason     (任意 — 未指定時は "(not provided)")

set -uo pipefail   # set -e は使わない (mode-loader.sh 教訓)

# log_bypass <hook_name> <env_var> <reason>
# 副作用: .claude/.workflow-state/bypass.log に 1 行 append
log_bypass() {
  local hook_name="${1:-unknown}"
  local env_var="${2:-unknown}"
  local reason="${3:-(not provided)}"
  local session_id="${CLAUDE_SESSION_ID:-unknown}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  local log_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.workflow-state"
  local log_file="${log_dir}/bypass.log"
  mkdir -p "$log_dir" 2>/dev/null
  printf '%s | %s | %s | %s | %s\n' \
    "$timestamp" "$session_id" "$hook_name" "$env_var" "$reason" \
    >> "$log_file" 2>/dev/null
}
