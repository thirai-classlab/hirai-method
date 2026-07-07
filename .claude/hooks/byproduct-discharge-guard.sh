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

# project root 解決 (dual-mode portability: HC_PROJECT_ROOT > git > pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project-root.sh
source "$SCRIPT_DIR/lib/project-root.sh"
# 後方互換: CLAUDE_PROJECT_DIR が明示設定されている場合はそれを優先
_project_dir="${CLAUDE_PROJECT_DIR:-$(resolve_project_root)}"

# stdin 消費 (Stop hook の JSON は使わないが、caller 側で残ることがある)
cat > /dev/null 2>&1 || true

# === bypass-logger 読み込み (bypass / warning 両方で使う) ===
if [ -f "${_project_dir}/.claude/hooks/lib/bypass-logger.sh" ]; then
  # shellcheck source=lib/bypass-logger.sh
  source "${_project_dir}/.claude/hooks/lib/bypass-logger.sh"
fi

# === config-loader.sh (best-effort、HC_* env 解決 + is_feature_enabled) ===
if [ -f "${_project_dir}/.claude/hooks/lib/config-loader.sh" ]; then
  # shellcheck source=lib/config-loader.sh
  # shellcheck disable=SC1091
  source "${_project_dir}/.claude/hooks/lib/config-loader.sh" 2>/dev/null || true
fi

# === BLOCK message 統一 API (task-94 P2-3、docs/draft/lib-block-message-4args.md §3.1) ===
# Stop hook のため emit_block_stop を利用 (JSON stdout 非出力、停止阻止 semantic 誤発火防止)。
if [ -f "${_project_dir}/.claude/hooks/lib/block-message.sh" ]; then
  # shellcheck source=lib/block-message.sh
  # shellcheck disable=SC1091
  source "${_project_dir}/.claude/hooks/lib/block-message.sh" 2>/dev/null || true
fi

# === Observability 構造化 log API (task-99 P3-2、observations.jsonl) ===
if [ -f "${_project_dir}/.claude/hooks/lib/observability.sh" ]; then
  # shellcheck source=lib/observability.sh
  # shellcheck disable=SC1091
  source "${_project_dir}/.claude/hooks/lib/observability.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled byproduct_discharge; then
  exit 0
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

# hook fire log (task-99): bypass / feature OFF / parser 不在 / parse fail を全て
# 通過し、実 next-actions.md 判定に到達した時点で log_fire。
if declare -f log_fire >/dev/null 2>&1; then
  log_fire "byproduct-discharge-guard" "processing Stop event: red=${NA_RED_COUNT:-0} yellow=${NA_YELLOW_COUNT:-0}" ""
fi

# === 判定 ===

# Case A: 🔴 未処理が 1 件以上 → BLOCK
if [ "${NA_RED_COUNT:-0}" -gt 0 ]; then
  _red_titles_joined=""
  if [ -n "${NA_RED_TITLES:-}" ]; then
    _red_titles_joined=$(printf '%s' "$NA_RED_TITLES" | awk 'BEGIN{first=1} {if(first){printf "%s",$0;first=0}else{printf ", %s",$0}}')
  fi

  # task-94 migration: Stop hook BLOCK は emit_block_stop 経由 (JSON stdout 非出力、§3.1)。
  # exit 2 (現状維持、§3.5 event × exit code table) は caller で明示。
  _bdg_why="[byproduct-discharge-guard] BLOCK: 🔴 (高) 未処理副産物 entry が ${NA_RED_COUNT} 件残存しています。未処理 🔴 entry: ${_red_titles_joined}"
  _bdg_fix="各 🔴 entry について /new-draft <slug> で draft 起こし → user 承認 → /new-task <id> <slug> で list.md 移行 → next-actions.md の「処理結果」列に移行先を記入"
  _bdg_silence='ECC_BYPASS_DISCHARGE_GUARD=1 ECC_BYPASS_REASON="<理由>" (audit-logged: .claude/.workflow-state/bypass.log)'
  _bdg_docs="docs/tasks/next-actions.md / .claude/rules/development-process.md"

  if declare -f log_block >/dev/null 2>&1; then
    log_block "byproduct-discharge-guard" "🔴 unresolved: ${NA_RED_COUNT}" ""
  fi
  if declare -f emit_block_stop >/dev/null 2>&1; then
    emit_block_stop "$_bdg_why" "$_bdg_fix" "$_bdg_silence" "$_bdg_docs"
  else
    # fallback: lib source 失敗時は既存 stderr 経路 (behavior-preserving)
    {
      printf '%s\n' "$_bdg_why"
      printf '\n'
      printf '推奨アクション: %s\n' "$_bdg_fix"
      printf '\n'
      printf 'Bypass (audit-logged): %s\n' "$_bdg_silence"
      printf '\n'
      printf '詳細: %s\n' "$_bdg_docs"
    } >&2
  fi

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
