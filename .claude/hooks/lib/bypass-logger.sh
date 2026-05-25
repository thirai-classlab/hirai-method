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
#   - file-top に set を書かない (CLAUDE.md Critical Lessons HIGH 準拠、caller への
#     shell flags leak 防止。pipefail leak → SIGPIPE → exit 141 サイレント終了の根絶)
#   - set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)
#   - 各関数 body 内で set -uo pipefail を subshell `( ... )` 形式で局所化
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

# Note: file-top に `set -uo pipefail` を書かない。caller hook (autonomous-action-guard /
# confidence-gate / parallel-subagent-reminder 等) が source した瞬間に pipefail flag が
# leak し、`cmd | head -1` 等の SIGPIPE で exit 141 サイレント終了する事故を防ぐ
# (CLAUDE.md Critical Operational Lessons HIGH 準拠)。各関数は subshell `( ... )`
# 形式で定義し、内部で `set -uo pipefail` を局所適用する。

# log_bypass <hook_name> <env_var> <reason>
# 副作用: .claude/.workflow-state/bypass.log に 1 行 append
# subshell 関数化 ( ... ): 内部の set -uo pipefail は caller の shell flags に leak しない
log_bypass() (
  set -uo pipefail
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
)
