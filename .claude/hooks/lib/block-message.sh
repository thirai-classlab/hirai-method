#!/usr/bin/env bash
# .claude/hooks/lib/block-message.sh — BLOCK / WARN / INFO 統一 API (task-94 / P2-3 / I6)
#
# 役割:
#   全 hook 群 (PreToolUse × 5 / Stop × 1 / SubagentStop × 1) + self-doctor 等が
#   共通の 4 引数 API (why / fix_one_liner / bypass_env / docs_link) で
#   BLOCK / WARN / INFO を出力する。event 別 semantics ずれを実装層で排除するため、
#   BLOCK は 3 variant に分割:
#
#     emit_block_pretool  — PreToolUse hook 用 (JSON stdout + stderr 4 行)
#     emit_block_stop     — Stop hook 用 (stderr 4 行のみ、JSON stdout 非出力)
#     emit_block_subagent — SubagentStop hook 用 (JSON stdout + stderr 4 行)
#
#   emit_warn / emit_info は event 非依存 (stderr のみ)。
#
# 設計 SSoT:
#   docs/draft/lib-block-message-4args.md §3.1 (event 別契約 table) /
#   §3.4 (fail-open) / §3.5 (event × exit code 併存) /
#   §4.1 lib 構造 / §4.5 移行対象 hook 一覧
#
# 契約 (共通 4 引数、順序不変):
#   emit_block_* / emit_warn: <why> <fix_one_liner> <bypass_env> <docs_link>
#   emit_info                 : <why> <docs_link>
#
#   - 引数不足は空文字 default (silent fail しない)
#   - <docs_link> が空文字なら stderr の docs: 行を省略
#   - <bypass_env> が空文字なら stderr の silence: 行を省略
#   - 引数は改行 → 空白、pipe → カンマに sanitize (bypass-logger.sh HIGH-1 同型)
#
# fail-open (feedback_set_e_in_sourced_libs、CommonRules Critical Lessons):
#   - file-top に set -euo pipefail を書かない (caller shell への leak 防止)
#   - 各関数 body は subshell `( set -uo pipefail; ... )` で局所化
#   - jq 不在 → printf による JSON literal fallback
#
# exit code:
#   本 lib は exit を呼ばない。caller が event / 現行 exit code semantics に基づき
#   emit_block_* 実行後に明示的に `exit N` する (§3.5)。
#     PreToolUse (JSON 経路): exit 0
#     PreToolUse (stderr + exit 2 経路、draft-flow-guard / workflow-guard): exit 2
#     Stop (byproduct-discharge-guard): exit 2
#     SubagentStop (confidence-gate): exit 0
#
# 使い方 (caller 例):
#   source "$(dirname "$0")/lib/block-message.sh"
#   emit_block_pretool \
#     "First Edit to: $file — 事実材料要求" \
#     "grep -r 'import $file' src/" \
#     "ECC_GATEGUARD=off / /gate-bypass $file" \
#     "docs/CONFIDENCE-GATE.md#f1-gateguard"
#   exit 0

# Note: file-top に `set -uo pipefail` を書かない。caller (hook 全般) が source した
# 瞬間に pipefail が leak し `cmd | head -1` 等の SIGPIPE で exit 141 サイレント終了
# する事故を防ぐ (CLAUDE.md Critical Operational Lessons HIGH 準拠、
# bypass-logger.sh L37-41 と同規範)。

# ----------------------------------------------------------------------
# 内部 helper: 4 引数 sanitize (改行 → 空白、pipe → カンマ、CR strip)
#   bypass-logger.sh HIGH-1 と同型 (§3.1 (b) 契約準拠)。
#   stderr 4 行 label pattern の破壊 / 偽造防止 + audit trail 保全。
#   caller で multi-line context が必要な場合は fix / bypass_env に構造化して渡す。
# ----------------------------------------------------------------------
_bm_sanitize() (
  set -uo pipefail
  local s="${1-}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//|/,}"
  printf '%s' "$s"
)

# ----------------------------------------------------------------------
# 内部 helper: 共通 stderr 4 行出力 (why: / fix: / silence: / docs:)
#   sev_label = "" (BLOCK は default 無 label) | "WARN " | "INFO "
#   空文字の <bypass_env> / <docs_link> は該当行 skip (silent fail しない契約)
#
#   format 契約 (smoke test SSoT):
#     BLOCK: [block-message] why: ...        (no severity label)
#     WARN : [block-message] WARN why: ...   (severity 前置)
#     INFO : [block-message] INFO why: ...   (severity 前置)
# ----------------------------------------------------------------------
_bm_emit_stderr_4lines() (
  set -uo pipefail
  local sev_prefix="$1" why="$2" fix="$3" bypass_env="$4" docs_link="$5"
  {
    printf '[block-message] %swhy: %s\n' "$sev_prefix" "$why"
    if [ -n "$fix" ]; then
      printf '[block-message] %sfix: %s\n' "$sev_prefix" "$fix"
    fi
    if [ -n "$bypass_env" ]; then
      printf '[block-message] %ssilence: %s\n' "$sev_prefix" "$bypass_env"
    fi
    if [ -n "$docs_link" ]; then
      printf '[block-message] %sdocs: %s\n' "$sev_prefix" "$docs_link"
    fi
  } >&2
)

# ----------------------------------------------------------------------
# 内部 helper: BLOCK 用の連結 reason 文字列を組み立てる
#   JSON stdout の "reason" field と stderr 4 行の caller 用 concatenated string
#   の両方を単一 source から生成する (SSoT)。
# ----------------------------------------------------------------------
_bm_build_reason_text() (
  set -uo pipefail
  local why="$1" fix="$2" bypass_env="$3" docs_link="$4"
  local out="why: $why"
  if [ -n "$fix" ]; then
    out="$out"$'\n'"fix: $fix"
  fi
  if [ -n "$bypass_env" ]; then
    out="$out"$'\n'"silence: $bypass_env"
  fi
  if [ -n "$docs_link" ]; then
    out="$out"$'\n'"docs: $docs_link"
  fi
  printf '%s' "$out"
)

# ----------------------------------------------------------------------
# 内部 helper: JSON `{decision:"block", reason:"..."}` を stdout に emit
#   jq 不在時は printf による JSON literal escape で fallback
#   (gateguard.sh:32-36 同 pattern)
# ----------------------------------------------------------------------
_bm_emit_block_json() (
  set -uo pipefail
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    # printf fallback: " と \ を JSON escape (\\ → \\\\、" → \")、改行を \n literal 化
    local escaped="${reason//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//$'\n'/\\n}"
    escaped="${escaped//$'\r'/}"
    printf '{"decision":"block","reason":"%s"}\n' "$escaped"
  fi
)

# ======================================================================
# Public API — 5 関数
# ======================================================================

# emit_block_pretool <why> <fix_one_liner> <bypass_env> <docs_link>
#   PreToolUse hook 用 BLOCK: JSON stdout `{decision:"block",...}` + stderr 4 行
#   exit は caller 側 (JSON 経路: exit 0 / stderr + exit 2 経路: exit 2)
emit_block_pretool() (
  set -uo pipefail
  local why fix bypass_env docs_link reason
  why=$(_bm_sanitize "${1-}")
  fix=$(_bm_sanitize "${2-}")
  bypass_env=$(_bm_sanitize "${3-}")
  docs_link=$(_bm_sanitize "${4-}")
  reason=$(_bm_build_reason_text "$why" "$fix" "$bypass_env" "$docs_link")
  _bm_emit_block_json "$reason"
  _bm_emit_stderr_4lines "" "$why" "$fix" "$bypass_env" "$docs_link"
)

# emit_block_stop <why> <fix_one_liner> <bypass_env> <docs_link>
#   Stop hook 用 BLOCK: stderr 4 行のみ (JSON stdout **非出力** — Stop 系
#   `{decision:"block"}` の主 tool 停止阻止 semantic 誤発火を実装層で排除)
#   exit は caller 側 (byproduct-discharge-guard.sh は exit 2 を維持)
emit_block_stop() (
  set -uo pipefail
  local why fix bypass_env docs_link
  why=$(_bm_sanitize "${1-}")
  fix=$(_bm_sanitize "${2-}")
  bypass_env=$(_bm_sanitize "${3-}")
  docs_link=$(_bm_sanitize "${4-}")
  _bm_emit_stderr_4lines "" "$why" "$fix" "$bypass_env" "$docs_link"
)

# emit_block_subagent <why> <fix_one_liner> <bypass_env> <docs_link>
#   SubagentStop hook 用 BLOCK: JSON stdout `{decision:"block",...}` + stderr 4 行
#   subagent 完了阻止 semantic を維持 (confidence-gate.sh 現行動作)
#   exit は caller 側 (exit 0 を維持)
emit_block_subagent() (
  set -uo pipefail
  local why fix bypass_env docs_link reason
  why=$(_bm_sanitize "${1-}")
  fix=$(_bm_sanitize "${2-}")
  bypass_env=$(_bm_sanitize "${3-}")
  docs_link=$(_bm_sanitize "${4-}")
  reason=$(_bm_build_reason_text "$why" "$fix" "$bypass_env" "$docs_link")
  _bm_emit_block_json "$reason"
  _bm_emit_stderr_4lines "" "$why" "$fix" "$bypass_env" "$docs_link"
)

# emit_warn <why> <fix_one_liner> <bypass_env> <docs_link>
#   stderr 4 行のみ (JSON 非出力、exit なし = fail-open)
emit_warn() (
  set -uo pipefail
  local why fix bypass_env docs_link
  why=$(_bm_sanitize "${1-}")
  fix=$(_bm_sanitize "${2-}")
  bypass_env=$(_bm_sanitize "${3-}")
  docs_link=$(_bm_sanitize "${4-}")
  _bm_emit_stderr_4lines "WARN " "$why" "$fix" "$bypass_env" "$docs_link"
)

# emit_info <why> <docs_link>
#   stderr 1-2 行 (why + optional docs、JSON 非出力、exit なし)
emit_info() (
  set -uo pipefail
  local why docs_link
  why=$(_bm_sanitize "${1-}")
  docs_link=$(_bm_sanitize "${2-}")
  {
    printf '[block-message] INFO why: %s\n' "$why"
    if [ -n "$docs_link" ]; then
      printf '[block-message] INFO docs: %s\n' "$docs_link"
    fi
  } >&2
)
