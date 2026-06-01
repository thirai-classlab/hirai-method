#!/usr/bin/env bash
# settings-generation-feature-pruning-smoke.sh — task-71 Step 8 S-A
#
# 目的:
#   disabled feature の子が dispatcher 内で skip (spawn せず) されることを実証する。
#   feature ON: 意図した子が block する。
#   feature OFF: 同じ payload でも block しない (子が spawn されないため)。
#   この差分で「dispatcher が feature gate を経由して子を skip している」ことを間接証明する。
#
# 対象 guard: draft-flow-guard (feature_draft_flow_guard_enabled) を例として使用。
#   - PreToolUse Edit|Write dispatcher の order=4 に配線 (exit2 channel)。
#   - feature ON: docs/zzz-new.md への Write で exit 2 (block)。
#   - feature OFF: 同 payload で exit 0 (skip)。
#   - delegation-guard / gateguard / task-rule-guard は OFF して draft-flow-guard の先行 block を防止。
#
# 実行: bash .claude/tests/settings-generation-feature-pruning-smoke.sh
# 終了: 0 = 全 case PASS / 1 = 1 件以上 FAIL
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

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/feature-pruning-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

_has_block() {
  printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' && printf 'yes' || printf 'no'
}

# --- SA-1: feature ON → draft-flow-guard blocks docs/zzz-new.md ---
run_sa1() ( set -uo pipefail
  INPUT=$(python3 -c "
import json,sys
# docs/ 直下 (root の docs/) への Write で draft-flow-guard が exit 2
fp = sys.argv[1] + '/docs/zzz-sa1-pruning-test.md'
print(json.dumps({'tool_name':'Write','tool_input':{'file_path':fp}}))
" "${ROOT}")
  local rc=0
  local out
  # 先行子 (delegation-guard / gateguard / task-rule-guard) を OFF にし
  # draft-flow-guard のみ ON にして exit 2 を取得
  out=$(printf '%s' "$INPUT" | \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=true \
    bash "$DISPATCHER" "Edit|Write" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sa1"
)

# --- SA-2: feature OFF → 同じ payload で no block (子が skip) ---
run_sa2() ( set -uo pipefail
  INPUT=$(python3 -c "
import json,sys
fp = sys.argv[1] + '/docs/zzz-sa2-pruning-test.md'
print(json.dumps({'tool_name':'Write','tool_input':{'file_path':fp}}))
" "${ROOT}")
  local rc=0
  local out
  # 全子 OFF → dispatcher は no-op exit 0 (子が spawn されない)
  out=$(printf '%s' "$INPUT" | \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false \
    bash "$DISPATCHER" "Edit|Write" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sa2"
)

# --- SA-3: autonomous-action-guard feature ON in Loop → blocks supabase db reset ---
run_sa3() ( set -uo pipefail
  INPUT=$(python3 -c "
import json
print(json.dumps({'tool_name':'Bash','tool_input':{'command':'supabase db reset'}}))
")
  local rc=0
  local out
  out=$(printf '%s' "$INPUT" | \
    HC_MODE=loop \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    bash "$DISPATCHER" "Bash" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sa3"
)

# --- SA-4: autonomous-action-guard feature OFF → no block ---
run_sa4() ( set -uo pipefail
  INPUT=$(python3 -c "
import json
print(json.dumps({'tool_name':'Bash','tool_input':{'command':'supabase db reset'}}))
")
  local rc=0
  local out
  out=$(printf '%s' "$INPUT" | \
    HC_MODE=loop \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED=false \
    bash "$DISPATCHER" "Bash" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "${TMPBASE}/result-sa4"
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
printf "=== S-A: settings-generation-feature-pruning-smoke ===\n\n"

printf "SA-1: draft-flow-guard feature ON → exit 2 (block)\n"
run_sa1
read -r sa1_rc sa1_block <<< "$(_read_result sa1)"
if [ "$sa1_rc" = "2" ] && [ "$sa1_block" = "no" ]; then
  ok "SA-1 feature ON: rc=2, block=no (exit2 channel, expected)"
else
  bad "SA-1 feature ON: rc=${sa1_rc} (want 2), block=${sa1_block} (want no)"
fi

printf "SA-2: draft-flow-guard feature OFF → exit 0 (skip)\n"
run_sa2
read -r sa2_rc sa2_block <<< "$(_read_result sa2)"
if [ "$sa2_rc" = "0" ] && [ "$sa2_block" = "no" ]; then
  ok "SA-2 feature OFF: rc=0, block=no (pruned, not spawned)"
else
  bad "SA-2 feature OFF: rc=${sa2_rc} (want 0), block=${sa2_block} (want no)"
fi

printf "SA-3: autonomous-action-guard ON (Loop) → block supabase db reset\n"
run_sa3
read -r sa3_rc sa3_block <<< "$(_read_result sa3)"
if [ "$sa3_rc" = "0" ] && [ "$sa3_block" = "yes" ]; then
  ok "SA-3 autonomous-action-guard ON: rc=0, block=yes"
else
  bad "SA-3 autonomous-action-guard ON: rc=${sa3_rc} (want 0), block=${sa3_block} (want yes)"
fi

printf "SA-4: autonomous-action-guard OFF → no block\n"
run_sa4
read -r sa4_rc sa4_block <<< "$(_read_result sa4)"
if [ "$sa4_rc" = "0" ] && [ "$sa4_block" = "no" ]; then
  ok "SA-4 autonomous-action-guard OFF: rc=0, block=no (pruned)"
else
  bad "SA-4 autonomous-action-guard OFF: rc=${sa4_rc} (want 0), block=${sa4_block} (want no)"
fi

# ON/OFF 差分検証 (draft-flow-guard)
printf "\nSA-diff: draft-flow-guard ON(rc=%s) vs OFF(rc=%s) → differ: " "$sa1_rc" "$sa2_rc"
if [ "$sa1_rc" != "$sa2_rc" ]; then
  ok "SA-diff feature ON/OFF produces different dispatcher exit code"
else
  bad "SA-diff feature ON/OFF exit code is same — feature gate NOT working"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== S-A Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
