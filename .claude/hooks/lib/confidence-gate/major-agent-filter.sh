#!/usr/bin/env bash
# major-agent-filter.sh — F3 major subagent only block の判定
#
# 役割:
#   SubagentStop hook は agent_type を問わず全 stop event で fire するため、
#   軽量 sidechain (Task tool query / tool-use only) で 96 件の regex_no_match
#   が累積する事故があった (/harness-audit 2026-05-13 観察)。
#   major subagent (general-purpose 等の allowlist or path_subagents) 以外は
#   fail-open で通過させ、major subagent only に confidence 自己評価を強制する。
#
# bypass: HC_CONFIDENCE_MAJOR_AGENT_ONLY=false で従来動作 (全 stop event で block 判定)。
#
# 提供関数:
#   classify_sidechain <transcript>     — transcript path / record から is_sidechain 判定
#                                          stdout: "path_subagents" / "record_isSidechain" / "no" / "unknown"
#   is_major_subagent <agent_type> <is_sidechain>
#                                       — major subagent 判定
#                                          stdout: "true" / "false"

# transcript path から sidechain 判定
classify_sidechain() {
  local transcript="$1"
  case "$transcript" in
    */subagents/*) printf 'path_subagents'; return ;;
  esac
  printf 'unknown'
}

# transcript file 内の record から sidechain 判定 (path 判定で unknown のとき)
refine_sidechain_from_records() {
  local current="$1"
  local transcript="$2"
  if [ "$current" = "unknown" ]; then
    if grep -q '"isSidechain"[[:space:]]*:[[:space:]]*true' "$transcript" 2>/dev/null; then
      printf 'record_isSidechain'
    else
      printf 'no'
    fi
    return
  fi
  printf '%s' "$current"
}

# === major subagent 判定 (W1, task #9) ===
# allowlist match (agent_type が general-purpose / Explore / Task) または
# is_sidechain==path_subagents なら major subagent (confidence 必須)。
# それ以外 (軽量 sidechain / Task tool query etc.) は extract_confidence 失敗時に fail-open。
is_major_subagent() {
  local agent_type="$1"
  local is_sidechain="$2"
  local result="false"
  case "$agent_type" in
    general-purpose|Explore|Task) result="true" ;;
  esac
  if [ "$is_sidechain" = "path_subagents" ]; then
    result="true"
  fi
  printf '%s' "$result"
}
