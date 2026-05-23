#!/usr/bin/env bash
# bypass.sh — confidence-gate の bypass marker 判定 + log_failure helper
#
# 提供関数:
#   init_bypass_paths             — state_dir / bypass_marker / bypass_log を設定
#   log_failure <phase> [detail]  — 失敗理由を bypass.log に構造化記録
#   handle_bypass_marker          — bypass.cleared 存在時に通過 + 1 回 re-arm
#
# caller (orchestrator) が事前に export 必須:
#   HC_CONFIDENCE_STATE_DIR (config-loader 経由で setup 済)
#
# 副作用:
#   handle_bypass_marker は bypass marker 検出時に jq '{}' echo + exit 0

init_bypass_paths() {
  state_dir="${HC_CONFIDENCE_STATE_DIR:-.claude/.confidence-gate-state}"
  mkdir -p "$state_dir" 2>/dev/null
  bypass_marker="${state_dir}/bypass.cleared"
  bypass_log="${state_dir}/bypass.log"
}

# bypass.log 拡張: 失敗理由を構造化ログ。
#   引数: $1 = phase (regex_no_match / no_transcript / file_not_found / extract_failed
#                     / below_threshold / below_threshold_via_tool_response)
#         $2 = detail (任意 free text、200 char 上限、改行/タブは空白に置換)
log_failure() {
  local phase="$1"
  local detail="${2:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  detail=$(printf '%s' "$detail" | tr '\n\t' '  ' | cut -c1-200)
  printf '%s\tfailed: %s\t%s\n' "$ts" "$phase" "$detail" >> "$bypass_log" 2>/dev/null
}

handle_bypass_marker() {
  if [ -f "$bypass_marker" ]; then
    local bypass_reason=""
    if [ -s "$bypass_marker" ]; then
      bypass_reason=$(cat "$bypass_marker" 2>/dev/null | head -c 200)
    fi
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\tbypassed: %s\n' "$ts" "${bypass_reason:-(no reason given)}" >> "$bypass_log" 2>/dev/null
    rm -f "$bypass_marker" 2>/dev/null
    echo '{}'
    exit 0
  fi
}
