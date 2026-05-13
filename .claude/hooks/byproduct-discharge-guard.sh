#!/usr/bin/env bash
# .claude/hooks/byproduct-discharge-guard.sh
# Stop hook — docs/tasks/next-actions.md の未処理副産物 entry を強制 discharge
#
# 役割:
#   セッション終了時 (Stop イベント) に未処理 entry を検証する:
#     - 🔴 (高) 未処理 1 件以上 → BLOCK (exit 2) — 「memory に流すだけ禁止」ルールを強制
#     - 🟡 (中) 未処理のみ → warning + exit 0
#     - すべて処理済 or 🟢 のみ → silent + exit 0
#
# 設計:
#   - 不在なら exit 0 silent (fail-open)
#   - parser 不在も exit 0 silent
#   - set -e 禁止 (mode-loader.sh の CB-verify 教訓 - 5846925)
#
# Bypass:
#   ECC_BYPASS_DISCHARGE_GUARD=1   # block を skip + bypass.log 記録
#
# 重要制約:
#   - source 系は set -uo pipefail のみ

set -uo pipefail   # set -e は使わない (mode-loader.sh 教訓)

# CLAUDE_PROJECT_DIR 解決
_project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# stdin 消費 (Stop hook の JSON は使わないが、caller 側で残ることがある)
cat > /dev/null 2>&1 || true

# === bypass-logger 読み込み (bypass / warning 両方で使う) ===
if [ -f "${_project_dir}/.claude/hooks/lib/bypass-logger.sh" ]; then
  # shellcheck source=lib/bypass-logger.sh
  source "${_project_dir}/.claude/hooks/lib/bypass-logger.sh"
fi

# === Bypass: ECC_BYPASS_DISCHARGE_GUARD ===
if [ "${ECC_BYPASS_DISCHARGE_GUARD:-0}" = "1" ] || [ "${ECC_BYPASS_DISCHARGE_GUARD:-}" = "true" ]; then
  # bypass log: session_id を含めて記録 (要件: reason 列に「{session_id}: discharge-guard bypass」と明記)
  _bypass_reason="${CLAUDE_SESSION_ID:-unknown}: discharge-guard bypass"
  if [ -n "${ECC_BYPASS_REASON:-}" ]; then
    _bypass_reason="${_bypass_reason} (${ECC_BYPASS_REASON})"
  fi
  if command -v log_bypass >/dev/null 2>&1; then
    log_bypass "byproduct-discharge-guard" "ECC_BYPASS_DISCHARGE_GUARD" "$_bypass_reason"
  fi
  exit 0
fi

# === parser library 読み込み ===
_parser_lib="${_project_dir}/.claude/hooks/lib/next-actions-parser.sh"
if [ ! -f "$_parser_lib" ]; then
  exit 0
fi
# shellcheck source=lib/next-actions-parser.sh
source "$_parser_lib"

# === next-actions.md 解析 ===
_md_file="${_project_dir}/docs/tasks/next-actions.md"

parse_next_actions "$_md_file"
_parse_rc=$?

if [ "$_parse_rc" != "0" ]; then
  # file 不在 or table 不在 → silent exit 0
  exit 0
fi

# === 判定 ===

# Case A: 🔴 未処理が 1 件以上 → BLOCK
if [ "${NA_RED_COUNT:-0}" -gt 0 ]; then
  _red_titles_joined=""
  if [ -n "${NA_RED_TITLES:-}" ]; then
    _red_titles_joined=$(printf '%s' "$NA_RED_TITLES" | awk 'BEGIN{first=1} {if(first){printf "%s",$0;first=0}else{printf ", %s",$0}}')
  fi

  {
    printf '[byproduct-discharge-guard] BLOCK: 🔴 (高) 未処理副産物 entry が %s 件残存しています。\n' "${NA_RED_COUNT}"
    printf '\n'
    printf '未処理 🔴 entry:\n'
    if [ -n "$_red_titles_joined" ]; then
      printf '  - %s\n' "$_red_titles_joined"
    fi
    printf '\n'
    printf '推奨アクション:\n'
    printf '  1. 各 🔴 entry について `/new-draft <slug>` で draft を起こす\n'
    printf '  2. user 承認後に `/new-task <id> <slug>` で list.md に移行\n'
    printf '  3. docs/tasks/next-actions.md の「処理結果」列に移行先を記入\n'
    printf '  4. 全 🔴 entry 処理後にセッション終了\n'
    printf '\n'
    printf 'Bypass (audit-logged):\n'
    printf '  ECC_BYPASS_DISCHARGE_GUARD=1 ECC_BYPASS_REASON="<理由>"\n'
    printf '  → .claude/.workflow-state/bypass.log に session_id 付きで記録される\n'
    printf '\n'
    printf '詳細: docs/tasks/next-actions.md / .claude/rules/development-process.md\n'
  } >&2

  exit 2
fi

# Case B: 🟡 のみ未処理 → warning + exit 0
if [ "${NA_YELLOW_COUNT:-0}" -gt 0 ]; then
  {
    printf '[byproduct-discharge-guard] WARN: 🟡 (中) 未処理副産物 entry が %s 件残存しています (block しません)。\n' "${NA_YELLOW_COUNT}"
    printf '  近日中に `/new-draft` で draft 起こし → tasking を推奨。\n'
    printf '  詳細: docs/tasks/next-actions.md\n'
  } >&2
  exit 0
fi

# Case C: 全て処理済 or 🟢 のみ → silent
exit 0
