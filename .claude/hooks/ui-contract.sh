#!/usr/bin/env bash
# ui-contract.sh — PostToolUse Edit/Write hook (task-98 / P3-1 / I4)
#
# 役割:
#   UI 拡張子 (.tsx / .jsx / .vue / .svelte / .html / .css / .scss) の Edit/Write
#   実行後に .claude/scripts/cross-file-contract-check.sh を呼び出し、
#   id / symbol / API 名の cross-file 契約乖離を advisory 検出する。
#
# 設計起源:
#   docs/tasks/task-98-ui-contract-hook-cross-file-check.md
#   docs/draft/install-immediately-usable-redesign-20260618.md §3 I4 / §5 P3-1
#   memory feedback_parallel_subagent_cross_file_contract_drift (task-63 main-panel↔view-container id mismatch)
#
# 動作:
#   1. tool_name が Edit/Write 以外 → PASS (empty JSON)
#   2. file_path の拡張子が UI extension でない → PASS
#   3. feature_ui_contract_enabled=false → PASS
#   4. bypass env ECC_UI_CONTRACT_OFF=1 → PASS (bypass.log 記録)
#   5. cross-file-contract-check.sh に file_path 渡し実行 → drift 検出時 stderr WARN
#   6. fail-open (script 不在 / エラー全て exit 0)
#
# 出力契約 (PostToolUse):
#   - stdout: `{}` (empty JSON、hook response 規約)
#   - stderr: drift 検出時のみ block-message.sh emit_warn 経由 4 行 WARN
#   - exit code: 常に 0 (fail-open、BLOCK しない = harness-dev preset の advisory 方針)
#
# bypass:
#   - ECC_UI_CONTRACT_OFF=1 (env、bypass.log 記録)
#   - harness-config.yml の feature_ui_contract_enabled: false (config)
#
# 検出対象 UI 拡張子 (env override 可: HC_UI_CONTRACT_EXTENSIONS=".tsx,.jsx,...")
#   .tsx / .jsx / .vue / .svelte / .html / .css / .scss

set -uo pipefail

# stdin 取得 (Hook JSON)
input=$(cat 2>/dev/null || true)

# jq 不在なら fail-open (empty JSON)
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config-loader (HC_* + is_feature_enabled)
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/lib/config-loader.sh" >/dev/null 2>&1 || true
fi

# Feature toggle (fail-open: is_feature_enabled 不在時は enabled 扱い)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled ui_contract; then
  echo '{}'
  exit 0
fi

# tool_name filter
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
case "$tool_name" in
  Edit|Write) ;;
  *) echo '{}'; exit 0 ;;
esac

# file_path 抽出
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // ""' 2>/dev/null)
[ -z "$file_path" ] && { echo '{}'; exit 0; }

# UI 拡張子判定 (env override 可、default 7 種)
ui_ext_raw="${HC_UI_CONTRACT_EXTENSIONS:-.tsx,.jsx,.vue,.svelte,.html,.css,.scss}"
is_ui=0
IFS=',' read -r -a ui_exts <<< "$ui_ext_raw"
for ext in "${ui_exts[@]}"; do
  ext_trim="${ext# }"
  ext_trim="${ext_trim% }"
  [ -z "$ext_trim" ] && continue
  case "$file_path" in
    *"$ext_trim") is_ui=1; break ;;
  esac
done
[ "$is_ui" -eq 0 ] && { echo '{}'; exit 0; }

# bypass env
if [ "${ECC_UI_CONTRACT_OFF:-0}" = "1" ]; then
  # bypass-logger (best-effort)
  # shellcheck source=lib/bypass-logger.sh
  if [ -f "$SCRIPT_DIR/lib/bypass-logger.sh" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/lib/bypass-logger.sh" >/dev/null 2>&1 || true
    if declare -f log_bypass >/dev/null 2>&1; then
      log_bypass "ui-contract" "ECC_UI_CONTRACT_OFF" "${ECC_BYPASS_REASON:-(not provided)} file=${file_path}"
    fi
  fi
  echo '{}'
  exit 0
fi

# project root 解決
# shellcheck source=lib/project-root.sh
if [ -f "$SCRIPT_DIR/lib/project-root.sh" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/lib/project-root.sh" >/dev/null 2>&1 || true
fi
if command -v resolve_project_root >/dev/null 2>&1; then
  root="$(resolve_project_root 2>/dev/null || pwd)"
else
  root="$(pwd)"
fi

check_script="$root/.claude/scripts/cross-file-contract-check.sh"
if [ ! -x "$check_script" ] && [ ! -f "$check_script" ]; then
  # script 不在 → fail-open (advisory 方針、hook 単独では BLOCK しない)
  echo '{}'
  exit 0
fi

# block-message lib (WARN 用)
# shellcheck source=lib/block-message.sh
if [ -f "$SCRIPT_DIR/lib/block-message.sh" ]; then
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/lib/block-message.sh" >/dev/null 2>&1 || true
fi

# cross-file-contract-check.sh を実行 (fail-open)
# 出力: drift 検出時 stdout に検出内容 (1 行/検出)、rc=1 で drift あり
check_output=""
check_rc=0
check_output=$(bash "$check_script" --file "$file_path" 2>&1) || check_rc=$?

if [ "$check_rc" -ne 0 ] && [ -n "$check_output" ]; then
  # drift 検出 → WARN 出力 (BLOCK しない、advisory)
  if declare -f emit_warn >/dev/null 2>&1; then
    emit_warn \
      "UI cross-file 契約乖離検出: $file_path" \
      "bash .claude/scripts/cross-file-contract-check.sh --file $file_path" \
      "ECC_UI_CONTRACT_OFF=1 / HC_FEATURE_UI_CONTRACT_ENABLED=false" \
      "docs/tasks/task-98-ui-contract-hook-cross-file-check.md"
    # 詳細内容も stderr に出す (advisory)
    printf '[ui-contract] drift detail:\n%s\n' "$check_output" >&2
  else
    # fallback: block-message lib 不在時の stderr 直接出力
    printf '[ui-contract] WARN: UI cross-file 契約乖離検出: %s\n%s\n' "$file_path" "$check_output" >&2
  fi
fi

echo '{}'
exit 0
