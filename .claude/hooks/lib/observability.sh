#!/usr/bin/env bash
# .claude/hooks/lib/observability.sh — Hook 発火・BLOCK・bypass・silent failure 構造化 log 統一 API
#
# 役割 (task-99 / P3-2 / I5):
#   全 hook (PreToolUse × 5 / Stop × 1 / SubagentStop × 1) が
#   共通の 4-5 引数 API で「fire / block / bypass / silent_failure / (arbitrary) event」を
#   `.claude/observability/observations.jsonl` に append する。
#   30 日超え entry は `.claude/scripts/observability-gc.sh` で archive dir へ移動する。
#   fire 0 回 hook は `.claude/scripts/hook-fire-audit.sh` で検出する。
#
# 設計 SSoT:
#   docs/tasks/task-99-lib-observability-30d-gc.md
#   master roadmap install-immediately-usable-redesign-20260618 §3 I5 / §5 P3-2
#
# API (公開 5 関数):
#   log_event <event_kind> <hook_name> <reason> [payload_json]
#   log_block <hook_name> <reason> [payload_json]        # event_kind="block"
#   log_bypass <hook_name> <env_var> <reason> [payload_json]  # event_kind="bypass" (superset of bypass-logger)
#   log_fire <hook_name> <reason> [payload_json]         # event_kind="fire"
#   log_silent_failure <hook_name> <reason> [payload_json]  # event_kind="silent_failure"
#
#   引数:
#     event_kind : "fire" | "block" | "bypass" | "silent_failure" | 任意
#     hook_name  : "gateguard" 等 (unknown 時は "unknown")
#     reason     : 事象の説明 (untrusted 入力を含む可能性あり)
#     env_var    : (log_bypass のみ) trigger env 名 (例: "ECC_WORKFLOW_GUARD_OFF")
#     payload_json : (optional) JSON literal string (先頭 { or [)。default は "{}"
#
#   共通挙動:
#     - 引数不足は空文字 default (silent fail しない)
#     - 全 field で 改行 → 空白 / CR → 空白 sanitize (bypass-logger.sh HIGH-1 同型)
#     - payload_json が空 or 妥当な JSON でない疑いなら "{}" に置換 (defensive)
#     - jq 存在時は jq で JSON build、不在時は printf JSON literal escape で fallback
#     - 出力先 (default): $CLAUDE_PROJECT_DIR/.claude/observability/observations.jsonl
#     - env override: HC_OBSERVABILITY_LOG_PATH (絶対 path 指定可)
#     - dir 不在なら mkdir -p (best-effort)
#     - 失敗 (mkdir / write) は silent skip (fail-open)
#
# log_bypass 超集合契約 (bypass-logger.sh との共存):
#   observability.sh が source された時点で log_bypass は本 lib 版に上書きされる。
#   本版 log_bypass は下記 2 動作を実行 (existing hooks の signature 3-arg も受理):
#     1. .claude/.workflow-state/bypass.log に 1 行 append (bypass-logger.sh と同じ)
#     2. .claude/observability/observations.jsonl に event_kind="bypass" event 追加
#   したがって observability.sh を source する hook は bypass-logger.sh を追加 source しても
#   log_bypass 呼出は本版 (superset) が実行される。既存 3-arg 呼出は payload_json="" で pass。
#
# fail-open (feedback_set_e_in_sourced_libs、CommonRules Critical Lessons):
#   - file-top に set -euo pipefail を書かない (caller shell への leak 防止)
#   - 各関数 body は subshell `( set -uo pipefail; ... )` で局所化
#   - jq 不在 → printf による JSON literal fallback
#   - write 失敗 → silent, hook 本体を止めない
#
# feature toggle:
#   HC_FEATURE_OBSERVABILITY_ENABLED=false で全 log_* を no-op 化 (default enabled)
#   (harness-config.yml の feature_observability_enabled 経由でも制御可)

# Note: file-top に `set -uo pipefail` を書かない。caller (hook 全般) が source した
# 瞬間に pipefail が leak し `cmd | head -1` 等の SIGPIPE で exit 141 サイレント終了
# する事故を防ぐ (CLAUDE.md Critical Operational Lessons HIGH 準拠、
# bypass-logger.sh L37-41 と同規範)。

# ----------------------------------------------------------------------
# 内部 helper: field sanitize (改行 → 空白、CR → 空白)
#   bypass-logger.sh HIGH-1 同型 (audit trail 破壊防止)。
# ----------------------------------------------------------------------
_obs_sanitize() (
  set -uo pipefail
  local s="${1-}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  printf '%s' "$s"
)

# ----------------------------------------------------------------------
# 内部 helper: observability log file 解決
#   優先順: HC_OBSERVABILITY_LOG_PATH > $CLAUDE_PROJECT_DIR/.claude/observability/observations.jsonl
#   > $(pwd)/.claude/observability/observations.jsonl
# ----------------------------------------------------------------------
_obs_resolve_log_path() (
  set -uo pipefail
  if [ -n "${HC_OBSERVABILITY_LOG_PATH:-}" ]; then
    printf '%s' "$HC_OBSERVABILITY_LOG_PATH"
    return
  fi
  local root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  printf '%s/.claude/observability/observations.jsonl' "$root"
)

# ----------------------------------------------------------------------
# 内部 helper: feature toggle check
#   HC_FEATURE_OBSERVABILITY_ENABLED=false / 0 / off / no → disabled (return 1)
#   それ以外 (空文字含む) → enabled (return 0、backward compat safety)
# ----------------------------------------------------------------------
_obs_is_enabled() (
  set -uo pipefail
  local v="${HC_FEATURE_OBSERVABILITY_ENABLED-}"
  local lc
  lc=$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    false|0|off|no) return 1 ;;
  esac
  return 0
)

# ----------------------------------------------------------------------
# 内部 helper: JSON string escape (printf fallback、jq 不在時)
#   \\ → \\\\, " → \", newline → \\n, tab → \\t, CR strip
# ----------------------------------------------------------------------
_obs_json_escape() (
  set -uo pipefail
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
)

# ----------------------------------------------------------------------
# 内部 helper: payload_json defensive default
#   空文字 or 先頭が { / [ でないなら "{}" に置換 (JSON literal 保証)
# ----------------------------------------------------------------------
_obs_default_payload() (
  set -uo pipefail
  local p="${1-}"
  if [ -z "$p" ]; then
    printf '{}'
    return
  fi
  local first="${p:0:1}"
  if [ "$first" != "{" ] && [ "$first" != "[" ]; then
    printf '{}'
    return
  fi
  printf '%s' "$p"
)

# ======================================================================
# Public API: log_event <event_kind> <hook_name> <reason> [payload_json]
# ======================================================================
#   全 event の generic base。他 4 関数は本関数の specialized wrapper。
#   .claude/observability/observations.jsonl に 1 行 append (JSONL format)。
#
#   出力 schema:
#     {"ts":"<ISO-8601 UTC>",
#      "event_kind":"<kind>",
#      "hook_name":"<name>",
#      "reason":"<reason>",
#      "session_id":"<CLAUDE_SESSION_ID or unknown>",
#      "payload":<json>,
#      "_schema_version":1}
log_event() (
  set -uo pipefail
  # feature toggle: OFF なら no-op
  _obs_is_enabled || return 0

  local event_kind hook_name reason payload
  event_kind=$(_obs_sanitize "${1-}")
  hook_name=$(_obs_sanitize "${2-}")
  reason=$(_obs_sanitize "${3-}")
  payload=$(_obs_default_payload "${4-}")

  # default fallbacks
  [ -z "$event_kind" ] && event_kind="unknown"
  [ -z "$hook_name" ] && hook_name="unknown"

  local session_id
  session_id=$(_obs_sanitize "${CLAUDE_SESSION_ID:-unknown}")

  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  local log_path
  log_path=$(_obs_resolve_log_path)
  local log_dir
  log_dir=$(dirname "$log_path")
  mkdir -p "$log_dir" 2>/dev/null

  # JSON line 構築 (jq 存在時 jq、不在時 printf fallback)
  local json_line=""
  if command -v jq >/dev/null 2>&1; then
    # payload を jq に流し込む。妥当でない JSON の場合は fallback で "{}"
    if ! json_line=$(jq -nc \
      --arg ts "$ts" \
      --arg ek "$event_kind" \
      --arg hn "$hook_name" \
      --arg rs "$reason" \
      --arg sid "$session_id" \
      --argjson pl "$payload" \
      '{ts:$ts, event_kind:$ek, hook_name:$hn, reason:$rs, session_id:$sid, payload:$pl, _schema_version:1}' \
      2>/dev/null); then
      # payload 不正で jq 失敗 → payload={} で再試行
      json_line=$(jq -nc \
        --arg ts "$ts" \
        --arg ek "$event_kind" \
        --arg hn "$hook_name" \
        --arg rs "$reason" \
        --arg sid "$session_id" \
        '{ts:$ts, event_kind:$ek, hook_name:$hn, reason:$rs, session_id:$sid, payload:{}, _schema_version:1}' \
        2>/dev/null)
    fi
  fi

  if [ -z "$json_line" ]; then
    # printf fallback (jq 不在 or jq 失敗)
    local ek_esc hn_esc rs_esc sid_esc
    ek_esc=$(_obs_json_escape "$event_kind")
    hn_esc=$(_obs_json_escape "$hook_name")
    rs_esc=$(_obs_json_escape "$reason")
    sid_esc=$(_obs_json_escape "$session_id")
    # payload は既に JSON literal (default "{}")、そのまま埋め込む
    json_line=$(printf '{"ts":"%s","event_kind":"%s","hook_name":"%s","reason":"%s","session_id":"%s","payload":%s,"_schema_version":1}' \
      "$ts" "$ek_esc" "$hn_esc" "$rs_esc" "$sid_esc" "$payload")
  fi

  printf '%s\n' "$json_line" >> "$log_path" 2>/dev/null
)

# ======================================================================
# Public API: log_block <hook_name> <reason> [payload_json]
# ======================================================================
#   event_kind="block" を hardcode した specialized wrapper。
#   hook が BLOCK 応答 (exit 2 / decision:"block") を返す直前に呼ぶ。
log_block() (
  set -uo pipefail
  local hook_name="${1-}"
  local reason="${2-}"
  local payload="${3-}"
  log_event "block" "$hook_name" "$reason" "$payload"
)

# ======================================================================
# Public API: log_bypass <hook_name> <env_var> <reason> [payload_json]
# ======================================================================
#   bypass-logger.sh の log_bypass 超集合契約 (3-arg 既存 caller 互換 + payload 拡張):
#     1. .claude/.workflow-state/bypass.log に 1 行 append (audit trail 保持)
#     2. .claude/observability/observations.jsonl に event_kind="bypass" event 追加
#
#   observability.sh を source した hook は本版 log_bypass を優先取得する。
#   bypass-logger.sh も同時 source されても signature 3-arg 呼出は互換動作。
log_bypass() (
  set -uo pipefail
  local hook_name env_var reason payload
  hook_name=$(_obs_sanitize "${1:-unknown}")
  env_var=$(_obs_sanitize "${2:-unknown}")
  reason=$(_obs_sanitize "${3:-(not provided)}")
  payload="${4-}"

  # ---- (1) bypass.log 1 行 append (bypass-logger.sh 同型ロジック) ----
  local session_id
  session_id=$(_obs_sanitize "${CLAUDE_SESSION_ID:-unknown}")
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  # bypass-logger.sh 5-field format 破壊防止のため、pipe 文字を追加 sanitize
  hook_name="${hook_name//|/,}"
  env_var="${env_var//|/,}"
  local reason_pipe="${reason//|/,}"
  local session_pipe="${session_id//|/,}"
  local bypass_log_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.workflow-state"
  local bypass_log_file="${bypass_log_dir}/bypass.log"
  mkdir -p "$bypass_log_dir" 2>/dev/null
  printf '%s | %s | %s | %s | %s\n' \
    "$ts" "$session_pipe" "$hook_name" "$env_var" "$reason_pipe" \
    >> "$bypass_log_file" 2>/dev/null

  # ---- (2) observations.jsonl event append ----
  # payload に env_var を含めた JSON を組み立て
  local pl_payload
  if [ -z "$payload" ]; then
    # JSON literal で env_var を埋め込む
    local ev_esc
    ev_esc=$(_obs_json_escape "$env_var")
    pl_payload=$(printf '{"env_var":"%s"}' "$ev_esc")
  else
    pl_payload=$(_obs_default_payload "$payload")
  fi
  log_event "bypass" "$hook_name" "$reason" "$pl_payload"
)

# ======================================================================
# Public API: log_fire <hook_name> <reason> [payload_json]
# ======================================================================
#   event_kind="fire" specialized wrapper。
#   hook が invoke され、実処理を開始する時点で呼ぶ (subagent bypass / feature OFF
#   等で早期 exit した後には呼ばれない = 「本当に fire した」時のみ log)。
log_fire() (
  set -uo pipefail
  local hook_name="${1-}"
  local reason="${2-}"
  local payload="${3-}"
  log_event "fire" "$hook_name" "$reason" "$payload"
)

# ======================================================================
# Public API: log_silent_failure <hook_name> <reason> [payload_json]
# ======================================================================
#   event_kind="silent_failure" specialized wrapper。
#   hook が推奨 flow から外れて exit 0 (fail-open) する時、追跡可能にするために呼ぶ。
#   例: confidence-gate の "regex_no_match" / "extract_failed" / "file_not_found"、
#       gateguard の jq 不在 fail-open、workflow-guard の state 不在 fail-open 等。
log_silent_failure() (
  set -uo pipefail
  local hook_name="${1-}"
  local reason="${2-}"
  local payload="${3-}"
  log_event "silent_failure" "$hook_name" "$reason" "$payload"
)
