#!/usr/bin/env bash
# hook-cwd-robustness-smoke.sh — task-71 Step 8 S-B
#
# 目的:
#   repo root 以外の cwd から dispatcher を実行しても正常に動作することを実証する。
#   resolve_project_root の fallback 機構 (HC_PROJECT_ROOT env / git rev-parse / CLAUDE_PROJECT_DIR)
#   が cwd 非依存で機能することを確認する。
#
# ケース:
#   SB-1: mktemp -d の cwd (repo root 以外) から dispatcher を実行 → CLAUDE_PROJECT_DIR なし、HC_PROJECT_ROOT あり
#   SB-2: mktemp -d の cwd + CLAUDE_PROJECT_DIR=<root> で実行 (CLAUDE_PROJECT_DIR fallback 実証)
#   SB-3: CLAUDE_PROJECT_DIR unset + HC_PROJECT_ROOT unset、git rev-parse で解決 (cwd=repo subdir から)
#   SB-4: 非 repo dir cwd + HC_PROJECT_ROOT で解決 → blocker 判定が repo root 基準で正常
#
# bash 3.2 互換 (macOS)。
# 規約: file-top set -u + case 別 ( set -uo pipefail ) + run_case。

set -u

# --- root 解決 ---
_resolve_root() (
  set -uo pipefail
  if [ -n "${HC_PROJECT_ROOT:-}" ] && [ -d "${HC_PROJECT_ROOT}" ]; then
    printf '%s' "${HC_PROJECT_ROOT}"; return 0
  fi
  local _sdir
  _sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if command -v git >/dev/null 2>&1; then
    local r
    r=$(git -C "$_sdir" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r" ] && [ -d "$r" ] && { printf '%s' "$r"; return 0; }
  fi
  if command -v git >/dev/null 2>&1; then
    local r2
    r2=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r2" ] && [ -d "$r2" ] && { printf '%s' "$r2"; return 0; }
  fi
  pwd
)

ROOT="$(_resolve_root)"
DISPATCHER="${ROOT}/.claude/hooks/pre-tool-use-dispatcher.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/cwd-robustness-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

_has_block() {
  printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' && printf 'yes' || printf 'no'
}

# --- SB-1: 非 repo cwd + HC_PROJECT_ROOT → blocker 判定が正常 ---
run_sb1() ( set -uo pipefail
  local unrelated_dir
  unrelated_dir="$(mktemp -d "${TMPBASE}/unrelated-cwd.XXXXXX")"
  local marker_dir
  marker_dir="$(mktemp -d "${TMPBASE}/marker-sb1.XXXXXX")"
  # src/x.ts は delegation-guard が block するはずのパス
  INPUT=$(python3 -c "
import json,sys
print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]+'/src/x.ts'}}))
" "${ROOT}")
  local out rc=0
  # cd して unrelated dir から dispatcher を実行
  out=$(
    cd "$unrelated_dir"
    printf '%s' "$INPUT" | \
      HC_PROJECT_ROOT="${ROOT}" \
      HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
      HC_AGENT_MARKER_DIR="${marker_dir}" \
      bash "$DISPATCHER" "Edit|Write" 2>/dev/null
  ) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sb1"
)

# --- SB-2: 非 repo cwd + CLAUDE_PROJECT_DIR → fallback で root 解決 ---
run_sb2() ( set -uo pipefail
  local unrelated_dir
  unrelated_dir="$(mktemp -d "${TMPBASE}/unrelated-cwd2.XXXXXX")"
  local marker_dir
  marker_dir="$(mktemp -d "${TMPBASE}/marker-sb2.XXXXXX")"
  INPUT=$(python3 -c "
import json,sys
print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]+'/src/x.ts'}}))
" "${ROOT}")
  local out rc=0
  # CLAUDE_PROJECT_DIR fallback (HC_PROJECT_ROOT unset)
  out=$(
    cd "$unrelated_dir"
    unset HC_PROJECT_ROOT
    printf '%s' "$INPUT" | \
      CLAUDE_PROJECT_DIR="${ROOT}" \
      HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
      HC_AGENT_MARKER_DIR="${marker_dir}" \
      bash "$DISPATCHER" "Edit|Write" 2>/dev/null
  ) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sb2"
)

# --- SB-3: git subdir cwd → git rev-parse が root を解決 ---
run_sb3() ( set -uo pipefail
  # repo 内の .claude/hooks subdir から実行 → git がある場合は rev-parse で root 解決
  local subdir="${ROOT}/.claude/hooks"
  local marker_dir
  marker_dir="$(mktemp -d "${TMPBASE}/marker-sb3.XXXXXX")"
  INPUT=$(python3 -c "
import json,sys
print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]+'/src/x.ts'}}))
" "${ROOT}")
  local out rc=0
  out=$(
    cd "$subdir"
    unset HC_PROJECT_ROOT
    unset CLAUDE_PROJECT_DIR 2>/dev/null || true
    printf '%s' "$INPUT" | \
      HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
      HC_AGENT_MARKER_DIR="${marker_dir}" \
      bash "$DISPATCHER" "Edit|Write" 2>/dev/null
  ) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sb3"
)

# --- SB-4: 非 repo cwd + stop-dispatcher (exit2 channel) → exit code 正常伝播 ---
run_sb4() ( set -uo pipefail
  local unrelated_dir
  unrelated_dir="$(mktemp -d "${TMPBASE}/unrelated-cwd4.XXXXXX")"
  # byproduct-discharge-guard via stop-dispatcher から、非 repo cwd で exit 2 が出るか
  local tmp_bd
  tmp_bd="$(mktemp -d "${TMPBASE}/bd-sb4.XXXXXX")"
  mkdir -p "${tmp_bd}/docs/tasks" "${tmp_bd}/.claude"
  ln -s "${ROOT}/.claude/hooks" "${tmp_bd}/.claude/hooks"
  ln -s "${ROOT}/.claude/harness-config.yml" "${tmp_bd}/.claude/harness-config.yml"
  cp "${ROOT}/.claude/tests/fixtures/next-actions/case-with-red.md" \
     "${tmp_bd}/docs/tasks/next-actions.md"
  local rc=0
  (
    cd "$unrelated_dir"
    echo '{}' | \
      HC_PROJECT_ROOT="${ROOT}" \
      HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED=true \
      CLAUDE_PROJECT_DIR="${tmp_bd}" \
      bash "${ROOT}/.claude/hooks/stop-dispatcher.sh" >/dev/null 2>&1
  ) || rc=$?
  printf '%s\nno\n' "$rc" > "${TMPBASE}/result-sb4"
)

_read_result() {
  local f="${TMPBASE}/result-$1"
  if [ -f "$f" ]; then
    printf '%s %s' "$(head -1 "$f" | tr -d '[:space:]')" "$(tail -1 "$f" | tr -d '[:space:]')"
  else
    printf 'ERR ERR'
  fi
}

# ------------------------------------------------------------------
printf "=== S-B: hook-cwd-robustness-smoke ===\n\n"

printf "SB-1: non-repo cwd + HC_PROJECT_ROOT → delegation-guard block\n"
run_sb1
read -r sb1_rc sb1_block <<< "$(_read_result sb1)"
if [ "$sb1_rc" = "0" ] && [ "$sb1_block" = "yes" ]; then
  ok "SB-1 HC_PROJECT_ROOT fallback: rc=0, block=yes"
else
  bad "SB-1 HC_PROJECT_ROOT fallback: rc=${sb1_rc} (want 0), block=${sb1_block} (want yes)"
fi

printf "SB-2: non-repo cwd + CLAUDE_PROJECT_DIR (unset HC_PROJECT_ROOT) → block\n"
run_sb2
read -r sb2_rc sb2_block <<< "$(_read_result sb2)"
if [ "$sb2_rc" = "0" ] && [ "$sb2_block" = "yes" ]; then
  ok "SB-2 CLAUDE_PROJECT_DIR fallback: rc=0, block=yes"
else
  bad "SB-2 CLAUDE_PROJECT_DIR fallback: rc=${sb2_rc} (want 0), block=${sb2_block} (want yes)"
fi

printf "SB-3: repo subdir cwd + git rev-parse → block\n"
run_sb3
read -r sb3_rc sb3_block <<< "$(_read_result sb3)"
if [ "$sb3_rc" = "0" ] && [ "$sb3_block" = "yes" ]; then
  ok "SB-3 git rev-parse fallback: rc=0, block=yes"
else
  bad "SB-3 git rev-parse fallback: rc=${sb3_rc} (want 0), block=${sb3_block} (want yes)"
fi

printf "SB-4: non-repo cwd + stop-dispatcher exit2 propagation\n"
run_sb4
read -r sb4_rc sb4_block <<< "$(_read_result sb4)"
if [ "$sb4_rc" = "2" ]; then
  ok "SB-4 cwd-agnostic stop-dispatcher: rc=2 (exit2 propagated)"
else
  bad "SB-4 cwd-agnostic stop-dispatcher: rc=${sb4_rc} (want 2)"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== S-B Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
