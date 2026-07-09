#!/usr/bin/env bash
# .claude/hooks/next-actions-surface.sh
# SessionStart hook — docs/tasks/next-actions.md の未処理副産物 entry を強制 surface
#
# 役割:
#   セッション開始時に未処理 entry を <system-reminder> で stderr に出力し、
#   メインが見落とすことを構造的に防ぐ。
#
# 設計:
#   - 不在なら exit 0 silent (fail-open、新規 repo を block しない)
#   - 未処理 entry 0 件なら silent (noise 削減)
#   - 🔴 entry がある時のみ注入 (Wave 1.5、🟡 / 🟢 のみは silent)
#     起源: docs/draft/system-reminder-attention-fix.md W1.5
#     env override で旧挙動に戻せる: HC_NEXT_ACTIONS_SURFACE_RED_ONLY=false
#   - 🔴 entry のタイトルを最大 5 件まで stderr に列挙
#   - 必ず exit 0 (SessionStart は block しない設計)
#
# Bypass:
#   ECC_NEXT_ACTIONS_SURFACE_OFF=1   # silent skip + bypass.log 記録
#
# 重要制約:
#   - set -e 禁止 (mode-loader.sh の CB-verify 教訓 - 5846925)
#   - source 系は set -uo pipefail のみ
#
# 共有 feature toggle group:
#   - グループ制御 toggle: `feature_byproduct_discharge_enabled` (default: true)
#   - OFF にすると本 hook を含む同 group の全 hook が no-op
#   - 編集: `bash .claude/scripts/hc-config.sh --feature byproduct_discharge=false`
#   - 同 group の他 hook: byproduct-discharge-guard.sh

set -uo pipefail   # set -e は使わない (mode-loader.sh 教訓)

# project root 解決 (dual-mode portability: HC_PROJECT_ROOT > git > pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/project-root.sh
source "$SCRIPT_DIR/lib/project-root.sh"
# 後方互換: CLAUDE_PROJECT_DIR が明示設定されている場合はそれを優先
_project_dir="${CLAUDE_PROJECT_DIR:-$(resolve_project_root)}"

# config-loader.sh source (is_feature_enabled 関数取得用、task-45 Phase 2)
if [ -f "${_project_dir}/.claude/hooks/lib/config-loader.sh" ]; then
  # shellcheck source=lib/config-loader.sh
  source "${_project_dir}/.claude/hooks/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2 + task-104 W1-8 child toggle)
# 親 (byproduct_discharge) と子 (next_actions_surface) の両方 check、どちらか OFF なら skip。
# 子 toggle は dispatcher-manifest SessionStart bootstrap feature_key 用 (finer-grained control)、
# 親 toggle は grouped feature 用 (next-actions-surface + byproduct-discharge-guard 一括制御)。
if command -v is_feature_enabled >/dev/null 2>&1; then
  if ! is_feature_enabled byproduct_discharge; then
    exit 0   # 親 feature OFF で no-op
  fi
  if ! is_feature_enabled next_actions_surface; then
    exit 0   # 子 feature OFF で no-op (task-104)
  fi
fi

# stdin を消費 (SessionStart hook は使わないが、消費しないと caller 側で残ることがある)
cat > /dev/null 2>&1 || true

# === Bypass ===
if [ "${ECC_NEXT_ACTIONS_SURFACE_OFF:-0}" = "1" ] || [ "${ECC_NEXT_ACTIONS_SURFACE_OFF:-}" = "true" ]; then
  # bypass-logger 読み込み
  if [ -f "${_project_dir}/.claude/hooks/lib/bypass-logger.sh" ]; then
    # shellcheck source=lib/bypass-logger.sh
    source "${_project_dir}/.claude/hooks/lib/bypass-logger.sh"
    log_bypass "next-actions-surface" "ECC_NEXT_ACTIONS_SURFACE_OFF" "${ECC_BYPASS_REASON:-(not provided)}"
  fi
  exit 0
fi

# === parser library 読み込み ===
_parser_lib="${_project_dir}/.claude/hooks/lib/next-actions-parser.sh"
if [ ! -f "$_parser_lib" ]; then
  # parser 不在: fail-open
  exit 0
fi
# shellcheck source=lib/next-actions-parser.sh
source "$_parser_lib"

# === next-actions.md 解析 ===
_md_file="${_project_dir}/docs/tasks/next-actions.md"

# parser 関数呼び出し (file 不在 / table 不在は silent skip)
parse_next_actions "$_md_file"
_parse_rc=$?

if [ "$_parse_rc" != "0" ]; then
  # file 不在 or table 不在 → silent exit 0
  exit 0
fi

# === 未処理 0 件なら silent ===
if [ "${NA_RED_COUNT:-0}" = "0" ] && [ "${NA_YELLOW_COUNT:-0}" = "0" ] && [ "${NA_GREEN_COUNT:-0}" = "0" ]; then
  exit 0
fi

# === Wave 1.5 frequency filter: 🔴 entry がある時のみ注入 ===
# 🟡 / 🟢 のみは attention dilution 削減のため completely silent (env で revert 可)
# 起源: docs/draft/system-reminder-attention-fix.md W1.5
# env override:
#   HC_NEXT_ACTIONS_SURFACE_RED_ONLY=false  ... 旧挙動 (🟡 / 🟢 でも発火) に戻す
if [ "${HC_NEXT_ACTIONS_SURFACE_RED_ONLY:-true}" != "false" ]; then
  if [ "${NA_RED_COUNT:-0}" = "0" ]; then
    exit 0
  fi
fi

# === <system-reminder> 構築 ===
# 🔴 タイトル列を「, 」区切りで join (最大 5 件、parser 側で truncate 済)
_red_titles_joined=""
if [ -n "${NA_RED_TITLES:-}" ]; then
  # 改行→「, 」変換
  _red_titles_joined=$(printf '%s' "$NA_RED_TITLES" | awk 'BEGIN{first=1} {if(first){printf "%s",$0;first=0}else{printf ", %s",$0}}')
fi

# 推奨処理メッセージ (🔴 件数で内容を切替)
if [ "${NA_RED_COUNT:-0}" -gt 0 ]; then
  _action_msg="推奨処理: \`/new-draft <slug>\` で draft 起こし → user 承認 → \`/new-task\` で list.md 移行"
else
  _action_msg="推奨処理: 緊急度 🟡 / 🟢 は近日 / 任意対応。詳細は docs/tasks/next-actions.md を確認"
fi

# 🔴 タイトル行 (存在する場合のみ)
_red_line=""
if [ -n "$_red_titles_joined" ]; then
  _red_line="優先対応 (🔴): ${_red_titles_joined}"$'\n'
fi

# stderr に出力 (SessionStart の <system-reminder> 規約に沿う)
{
  printf '<system-reminder>\n'
  printf '[next-actions-surface] 未処理副産物 entry: 🔴 %s 件 / 🟡 %s 件 / 🟢 %s 件\n' \
    "${NA_RED_COUNT}" "${NA_YELLOW_COUNT}" "${NA_GREEN_COUNT}"
  if [ -n "$_red_line" ]; then
    printf '%s' "$_red_line"
  fi
  printf '%s\n' "$_action_msg"
  printf '詳細: docs/tasks/next-actions.md\n'
  printf '</system-reminder>\n'
} >&2

exit 0
