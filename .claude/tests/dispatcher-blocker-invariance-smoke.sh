#!/usr/bin/env bash
# dispatcher-blocker-invariance-smoke.sh — task-71 Step 8 S-E (最重要)
#
# 目的:
#   golden 21 case の crafted 入力を「該当 dispatcher 経由」で流し、
#   exit code + block flag が golden (direct-hook) と完全一致するか照合する。
#   「dispatcher 化前後で blocker 検出力不変」の真の証明。
#
# Step 2 との違い:
#   Step 2 = 各 hook を直接呼んだ baseline。
#   本 smoke = 同 payload を dispatcher (<event>-dispatcher.sh <matcher>) 経由で流す。
#   全 21 case で dispatcher 結果 == golden が PASS 条件。1 件でも乖離 = FAIL (cutover 不可)。
#
# 設計上の注意 (dispatcher 順序対応):
#   PreToolUse Edit|Write 子の order:
#     1: delegation-guard (stdout-block)
#     2: gateguard (stdout-block)
#     3: task-rule-guard (stdout-block)
#     4: draft-flow-guard (exit2)
#   PreToolUse Bash 子の order:
#     1: autonomous-action-guard (stdout-block)
#     2: delegation-guard (stdout-block)
#     3: gateguard (stdout-block)
#     4: workflow-guard (exit2)
#
#   → 各 case の入力は「意図した子が最初に block する」よう先行子を OFF または
#     先行子が block しない安全 path を使う。feature flag は Step 2 と同条件 (強制 ON)。
#
#   C10-C12 (draft-flow-guard): file path を real root docs/ に設定し
#     先行子 (delegation-guard/gateguard/task-rule-guard) を OFF。
#
#   C15 (workflow-guard): 先行する autonomous-action-guard / delegation-guard を OFF。
#
#   C17 (check-md-mermaid): PostToolUse Edit|Write dispatcher 経由
#     (PostToolUse は check-md-mermaid のみ → 先行問題なし)。
#
# feature flag 強制 ON:
#   harness-dev preset では各 feature が false の場合があるため、
#   baseline 照合は HC_FEATURE_*_ENABLED=true で強制 ON した blocking 挙動を使用 (Step 2 同条件)。
#
# 実行: bash .claude/tests/dispatcher-blocker-invariance-smoke.sh
# 終了: 0 = 全 21 case golden 一致 / 1 = 1 件以上乖離 (cutover 不可)
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
GOLDEN_FILE="${ROOT}/.claude/tests/fixtures/task-71/blocker-baseline.tsv"

if [ ! -f "$GOLDEN_FILE" ]; then
  printf "ERROR: golden file not found: %s\n" "$GOLDEN_FILE" >&2
  printf "Run settings-dispatcher-baseline-smoke.sh --record first.\n" >&2
  exit 1
fi

# golden 破損検出: 期待行数 (24 cases) と一致しない場合は ERROR で終了 (block 変化と区別)
GOLDEN_EXPECTED_LINES=24
GOLDEN_ACTUAL_LINES=$(grep -c '' "$GOLDEN_FILE" 2>/dev/null || printf '0')
if [ "$GOLDEN_ACTUAL_LINES" -ne "$GOLDEN_EXPECTED_LINES" ]; then
  printf "ERROR: golden corrupted — expected %d lines, got %d. Re-run --record.\n" \
    "$GOLDEN_EXPECTED_LINES" "$GOLDEN_ACTUAL_LINES" >&2
  exit 1
fi

TMP_BASE="$(mktemp -d /tmp/blocker-invariance.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

# clean env
unset CLAUDE_HARNESS_ROLE 2>/dev/null || true

RESULT_FILE="${TMP_BASE}/result.txt"
PASS=0
FAIL=0
FAILED_CASES=()

# ------------------------------------------------------------------
# JSON builders (Step 2 から再利用)
# ------------------------------------------------------------------

_json_edit() {
  FP="$1" python3 -c '
import json,os
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":os.environ["FP"]}}))
'
}

_json_write() {
  FP="$1" python3 -c '
import json,os
print(json.dumps({"tool_name":"Write","tool_input":{"file_path":os.environ["FP"]}}))
'
}

_json_read() {
  FP="$1" python3 -c '
import json,os
print(json.dumps({"tool_name":"Read","tool_input":{"file_path":os.environ["FP"]}}))
'
}

_json_bash() {
  CMD="$1" python3 -c '
import json,os
print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))
'
}

# stdout に "decision":"block" または "permissionDecision":"deny" が含まれるか判定
# C1 修正: 単一 anchored grep で 2 形式を検出 (dispatcher-core.sh の _dc_is_block_stdout と判定基準一致)
_has_block() {
  if printf '%s' "$1" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    printf 'yes'
    return
  fi
  if printf '%s' "$1" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    printf 'yes'
    return
  fi
  printf 'no'
}

# dispatcher 呼び出し + RESULT_FILE に "exit\nblock" を書く
# 用途: stdout-block channel (exit 0 + decision JSON) および exit2 channel (rc >= 2)
# $1 = dispatcher script path、$2 = matcher arg (空文字可)、$3 = input JSON
# 残り = env KEY=VAL ...
_capture_dispatcher() {
  local disp="$1"
  local matcher="$2"
  local input="$3"
  shift 3
  local out rc=0
  if [ -n "$matcher" ]; then
    out=$(printf '%s' "$input" | env "$@" bash "$disp" "$matcher" 2>/dev/null) || rc=$?
  else
    out=$(printf '%s' "$input" | env "$@" bash "$disp" 2>/dev/null) || rc=$?
  fi
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
}

# Stop / SubagentStop dispatcher 用: stdin に JSON を渡す
_capture_dispatcher_stdin() {
  local disp="$1"
  local input="$2"
  shift 2
  local rc=0
  printf '%s' "$input" | env "$@" bash "$disp" 2>/dev/null >/dev/null || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
}

# golden から期待値を読む
_get_golden() {
  local case_id="$1"
  local golden_line
  golden_line=$(grep "^${case_id}	" "$GOLDEN_FILE" 2>/dev/null | head -1)
  if [ -z "$golden_line" ]; then
    printf 'NOTFOUND NOTFOUND'
    return
  fi
  local ex eb
  ex=$(printf '%s' "$golden_line" | cut -f4)
  eb=$(printf '%s' "$golden_line" | cut -f5)
  printf '%s %s' "$ex" "$eb"
}

# RESULT_FILE を読み golden と照合
_check_case() {
  local case_id="$1"
  local scenario="$2"

  local actual_exit actual_block
  if [ -f "$RESULT_FILE" ]; then
    actual_exit=$(head -1 "$RESULT_FILE" | tr -d '[:space:]')
    actual_block=$(tail -1 "$RESULT_FILE" | tr -d '[:space:]')
    rm -f "$RESULT_FILE"
  else
    actual_exit="ERR"
    actual_block="ERR"
  fi

  local golden
  golden="$(_get_golden "$case_id")"
  local expected_exit expected_block
  expected_exit=$(printf '%s' "$golden" | cut -d' ' -f1)
  expected_block=$(printf '%s' "$golden" | cut -d' ' -f2)

  if [ "$expected_exit" = "NOTFOUND" ]; then
    FAIL=$((FAIL+1))
    FAILED_CASES+=("${case_id}: golden not found")
    printf "  FAIL: %s — golden not found\n" "$case_id"
    return
  fi

  if [ "$actual_exit" = "$expected_exit" ] && [ "$actual_block" = "$expected_block" ]; then
    PASS=$((PASS+1))
    printf "  PASS: %s (exit=%s block=%s)\n" "$case_id" "$actual_exit" "$actual_block"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES+=("${case_id}: exit got=${actual_exit} want=${expected_exit} block got=${actual_block} want=${expected_block}")
    printf "  FAIL: %s — %s\n    exit: got=%s want=%s\n    block: got=%s want=%s\n" \
      "$case_id" "$scenario" "$actual_exit" "$expected_exit" "$actual_block" "$expected_block"
  fi
}

# ------------------------------------------------------------------
# Dispatcher paths
# ------------------------------------------------------------------
PRE_DISP="${ROOT}/.claude/hooks/pre-tool-use-dispatcher.sh"
POST_DISP="${ROOT}/.claude/hooks/post-tool-use-dispatcher.sh"
STOP_DISP="${ROOT}/.claude/hooks/stop-dispatcher.sh"
SUBAGENT_DISP="${ROOT}/.claude/hooks/subagent-stop-dispatcher.sh"

# ------------------------------------------------------------------
printf "=== S-E: dispatcher-blocker-invariance-smoke (golden: %s) ===\n\n" "$GOLDEN_FILE"

# --- C01: delegation-guard Edit protected src → Pre Edit|Write dispatcher ---
# delegation-guard は order=1 → そのまま block
run_e_c01() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c01.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" "$(_json_edit "${ROOT}/src/x.ts")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C01: delegation-guard Edit protected src path → block\n"
run_e_c01
_check_case "C01" "delegation-guard Edit protected"

# --- C02: delegation-guard Edit README.md → pass ---
run_e_c02() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c02.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" "$(_json_edit "${ROOT}/README.md")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C02: delegation-guard Edit README.md → pass\n"
run_e_c02
_check_case "C02" "delegation-guard Edit README.md pass"

# --- C03: delegation-guard Read protected src → Pre Read dispatcher ---
run_e_c03() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c03.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Read" "$(_json_read "${ROOT}/src/x.ts")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C03: delegation-guard Read protected src → block\n"
run_e_c03
_check_case "C03" "delegation-guard Read protected"

# --- C04: delegation-guard Bash git reset → Pre Bash dispatcher ---
# Pre Bash: order=1 autonomous-action-guard, order=2 delegation-guard
# git reset --hard HEAD: autonomous-action-guard はこのパターンを block しない
run_e_c04() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c04.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Bash" "$(_json_bash "git reset --hard HEAD")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    HC_MODE=loop \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    ECC_ALLOW_PROTECTED_BRANCH_PUSH=1
)
printf "C04: delegation-guard Bash git reset → block\n"
run_e_c04
_check_case "C04" "delegation-guard Bash git reset"

# --- C05: delegation-guard Bash git status → pass ---
run_e_c05() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c05.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Bash" "$(_json_bash "git status")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C05: delegation-guard Bash git status → pass\n"
run_e_c05
_check_case "C05" "delegation-guard Bash git status pass"

# --- C06: gateguard Edit fresh state → Pre Edit|Write dispatcher ---
# delegation-guard (order=1) must not block: /tmp path は delegation 対象外
run_e_c06() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c06.XXXXXX")"
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c06.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" \
    "$(_json_edit "/tmp/baseline-c06-disp-test.ts")" \
    HC_FEATURE_GATEGUARD_ENABLED=true \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_GATEGUARD_STATE_DIR="${STATE}" \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C06: gateguard Edit fresh state → first-edit block\n"
run_e_c06
_check_case "C06" "gateguard first-edit block"

# --- C07: gateguard feature OFF → no-op ---
run_e_c07() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c07.XXXXXX")"
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c07.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" \
    "$(_json_edit "/tmp/baseline-c07-disp-test.ts")" \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false \
    HC_GATEGUARD_STATE_DIR="${STATE}" \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C07: gateguard feature OFF → no-op\n"
run_e_c07
_check_case "C07" "gateguard feature OFF no-op"

# --- C08: task-rule-guard Write feature ON + no draft → block ---
# task-rule-guard is order=3. delegation-guard (1) + gateguard (2) must not block.
# File path in tmp dir: not in root/src → delegation won't block.
run_e_c08() ( set -uo pipefail
  TMP_TRG="$(mktemp -d "${TMP_BASE}/trg-c08.XXXXXX")"
  mkdir -p "${TMP_TRG}/docs/tasks" "${TMP_TRG}/docs/draft" \
           "${TMP_TRG}/.taskguard-state" "${TMP_TRG}/.agent-markers"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" \
    "$(_json_write "${TMP_TRG}/docs/tasks/task-99-no-draft-c08-disp.md")" \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_FEATURE_GATEGUARD_ENABLED=true \
    HC_TASK_DIR=docs/tasks \
    HC_DRAFT_DIR=docs/draft \
    HC_TASKGUARD_STATE_DIR="${TMP_TRG}/.taskguard-state" \
    HC_AGENT_MARKER_DIR="${TMP_TRG}/.agent-markers"
)
printf "C08: task-rule-guard Write no draft → block\n"
run_e_c08
_check_case "C08" "task-rule-guard no draft block"

# --- C09: task-rule-guard feature OFF → no-op ---
run_e_c09() ( set -uo pipefail
  TMP_TRG="$(mktemp -d "${TMP_BASE}/trg-c09.XXXXXX")"
  mkdir -p "${TMP_TRG}/docs/tasks" "${TMP_TRG}/docs/draft" \
           "${TMP_TRG}/.taskguard-state" "${TMP_TRG}/.agent-markers"
  _capture_dispatcher "$PRE_DISP" "Edit|Write" \
    "$(_json_write "${TMP_TRG}/docs/tasks/task-99-no-draft-c09-disp.md")" \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false \
    HC_TASK_DIR=docs/tasks \
    HC_DRAFT_DIR=docs/draft \
    HC_TASKGUARD_STATE_DIR="${TMP_TRG}/.taskguard-state" \
    HC_AGENT_MARKER_DIR="${TMP_TRG}/.agent-markers"
)
printf "C09: task-rule-guard feature OFF → no-op\n"
run_e_c09
_check_case "C09" "task-rule-guard feature OFF no-op"

# --- C10: draft-flow-guard Write docs/zzz-new.md no draft → exit 2 ---
# draft-flow-guard は order=4 (exit2 channel)。先行子 (1-3) を OFF。
# ファイルパスは real root docs/ を使う (draft-flow-guard は root 基準でパス判定)。
run_e_c10() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c10.XXXXXX")"
  local rc=0
  local out
  out=$(printf '%s' "$(_json_write "${ROOT}/docs/zzz-dispatcher-c10-test.md")" | \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=true \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    bash "$PRE_DISP" "Edit|Write" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
)
printf "C10: draft-flow-guard Write docs/zzz-new.md no draft → exit 2\n"
run_e_c10
_check_case "C10" "draft-flow-guard docs no draft exit2"

# --- C11: draft-flow-guard Write docs/draft/zzz-new.md → draft path pass ---
run_e_c11() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c11.XXXXXX")"
  local rc=0
  local out
  out=$(printf '%s' "$(_json_write "${ROOT}/docs/draft/zzz-dispatcher-c11-test.md")" | \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=true \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    bash "$PRE_DISP" "Edit|Write" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
)
printf "C11: draft-flow-guard Write docs/draft → draft path pass\n"
run_e_c11
_check_case "C11" "draft-flow-guard draft path pass"

# --- C12: draft-flow-guard feature OFF → no-op ---
run_e_c12() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c12.XXXXXX")"
  local rc=0
  local out
  out=$(printf '%s' "$(_json_write "${ROOT}/docs/zzz-dispatcher-c12-off-test.md")" | \
    HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    bash "$PRE_DISP" "Edit|Write" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
)
printf "C12: draft-flow-guard feature OFF → no-op\n"
run_e_c12
_check_case "C12" "draft-flow-guard feature OFF no-op"

# --- C13: autonomous-action-guard Loop + supabase db reset → block ---
# autonomous-action-guard は order=1 in Bash → そのまま block
run_e_c13() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c13.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Bash" "$(_json_bash "supabase db reset")" \
    HC_MODE=loop \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C13: autonomous-action-guard Loop supabase db reset → block\n"
run_e_c13
_check_case "C13" "autonomous-action-guard loop block"

# --- C14: autonomous-action-guard Normal supabase db reset → advisory (no block) ---
run_e_c14() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c14.XXXXXX")"
  _capture_dispatcher "$PRE_DISP" "Bash" "$(_json_bash "supabase db reset")" \
    HC_MODE=normal \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED=false \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C14: autonomous-action-guard Normal supabase db reset → advisory no block\n"
run_e_c14
_check_case "C14" "autonomous-action-guard normal no block"

# --- C15: workflow-guard /finish-task stage not final → exit 2 ---
# Pre Bash order: 1=autonomous-action-guard, 2=delegation-guard, 3=gateguard, 4=workflow-guard
# Disable first 3 so workflow-guard (order=4) can act
run_e_c15() ( set -uo pipefail
  TMP_WF="$(mktemp -d "${TMP_BASE}/wf-c15.XXXXXX")"
  mkdir -p "${TMP_WF}/.claude"
  ln -s "${ROOT}/.claude/hooks" "${TMP_WF}/.claude/hooks"
  ln -s "${ROOT}/.claude/harness-config.yml" "${TMP_WF}/.claude/harness-config.yml"
  mkdir -p "${TMP_WF}/.claude/.workflow-state"
  cp "${ROOT}/.claude/tests/fixtures/workflow-guard/case-2-mid.json" \
     "${TMP_WF}/.claude/.workflow-state/smoke-mid.json"
  local rc=0
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"/finish-task smoke-mid"}}' | \
    HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED=true \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    CLAUDE_PROJECT_DIR="${TMP_WF}" \
    bash "$PRE_DISP" "Bash" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)
printf "C15: workflow-guard /finish-task stage not final → exit 2\n"
run_e_c15
_check_case "C15" "workflow-guard finish-task not-final exit2"

# --- C16: workflow-guard feature OFF → no-op ---
run_e_c16() ( set -uo pipefail
  TMP_WF="$(mktemp -d "${TMP_BASE}/wf-c16.XXXXXX")"
  mkdir -p "${TMP_WF}/.claude"
  ln -s "${ROOT}/.claude/hooks" "${TMP_WF}/.claude/hooks"
  ln -s "${ROOT}/.claude/harness-config.yml" "${TMP_WF}/.claude/harness-config.yml"
  mkdir -p "${TMP_WF}/.claude/.workflow-state"
  cp "${ROOT}/.claude/tests/fixtures/workflow-guard/case-2-mid.json" \
     "${TMP_WF}/.claude/.workflow-state/smoke-mid.json"
  local rc=0
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"/finish-task smoke-mid"}}' | \
    HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED=false \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=false \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    CLAUDE_PROJECT_DIR="${TMP_WF}" \
    bash "$PRE_DISP" "Bash" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)
printf "C16: workflow-guard feature OFF → no-op\n"
run_e_c16
_check_case "C16" "workflow-guard feature OFF no-op"

# --- C17: check-md-mermaid PostToolUse Edit|Write → block (if mermaid avail) ---
run_e_c17() ( set -uo pipefail
  TMP_MD="$(mktemp "${TMP_BASE}/broken-mermaid.XXXXXX.md")"
  printf '# Test\n\n```mermaid\ngraph TD\n  A --> INVALID SYNTAX @@@@\n```\n' > "$TMP_MD"
  local input
  input=$(TOOL="Edit" FP="$TMP_MD" python3 -c '
import json,os
print(json.dumps({
  "tool_name": os.environ["TOOL"],
  "tool_input": {"file_path": os.environ["FP"]},
  "tool_response": {"content": "edited"}
}))
')
  _capture_dispatcher "$POST_DISP" "Edit|Write" "$input" \
    HC_FEATURE_CHECK_MD_MERMAID_ENABLED=true
)
printf "C17: check-md-mermaid broken mermaid → block (if mermaid avail)\n"
run_e_c17
_check_case "C17" "check-md-mermaid broken mermaid block"

# --- C18: byproduct-discharge-guard Stop 🔴 entry → exit 2 ---
run_e_c18() ( set -uo pipefail
  TMP_BD="$(mktemp -d "${TMP_BASE}/bd-c18.XXXXXX")"
  mkdir -p "${TMP_BD}/docs/tasks" "${TMP_BD}/.claude"
  ln -s "${ROOT}/.claude/hooks" "${TMP_BD}/.claude/hooks"
  ln -s "${ROOT}/.claude/harness-config.yml" "${TMP_BD}/.claude/harness-config.yml"
  cp "${ROOT}/.claude/tests/fixtures/next-actions/case-with-red.md" \
     "${TMP_BD}/docs/tasks/next-actions.md"
  local rc=0
  echo '{}' | \
    HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED=true \
    CLAUDE_PROJECT_DIR="${TMP_BD}" \
    bash "$STOP_DISP" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)
printf "C18: byproduct-discharge-guard Stop 🔴 → exit 2\n"
run_e_c18
_check_case "C18" "byproduct-discharge-guard red entry exit2"

# --- C19: byproduct-discharge-guard Stop clean → exit 0 ---
run_e_c19() ( set -uo pipefail
  TMP_BD="$(mktemp -d "${TMP_BASE}/bd-c19.XXXXXX")"
  mkdir -p "${TMP_BD}/docs/tasks" "${TMP_BD}/.claude"
  ln -s "${ROOT}/.claude/hooks" "${TMP_BD}/.claude/hooks"
  ln -s "${ROOT}/.claude/harness-config.yml" "${TMP_BD}/.claude/harness-config.yml"
  cp "${ROOT}/.claude/tests/fixtures/next-actions/case-clean.md" \
     "${TMP_BD}/docs/tasks/next-actions.md"
  local rc=0
  echo '{}' | \
    HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED=true \
    CLAUDE_PROJECT_DIR="${TMP_BD}" \
    bash "$STOP_DISP" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)
printf "C19: byproduct-discharge-guard Stop clean → exit 0\n"
run_e_c19
_check_case "C19" "byproduct-discharge-guard clean pass"

# --- C20: confidence-gate SubagentStop confidence 0.3 → block ---
run_e_c20() ( set -uo pipefail
  TMP_CG="$(mktemp -d "${TMP_BASE}/cg-c20.XXXXXX")"
  mkdir -p "${TMP_CG}/state"
  TMP_TRANSCRIPT="${TMP_CG}/case20.jsonl"
  python3 -c '
import json
rec={"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"途中まで完了。一部 test 未確認。confidence: 0.3"}]},"uuid":"c20-smoke"}
print(json.dumps(rec))
' > "$TMP_TRANSCRIPT"
  local input
  input=$(TP="$TMP_TRANSCRIPT" python3 -c '
import json,os
print(json.dumps({"session_id":"c20-smoke","transcript_path":os.environ["TP"],"agent_type":"general-purpose"}))
')
  _capture_dispatcher "$SUBAGENT_DISP" "" "$input" \
    HC_FEATURE_CONFIDENCE_GATE_ENABLED=true \
    HC_CONFIDENCE_STATE_DIR="${TMP_CG}/state" \
    HC_CONFIDENCE_THRESHOLD=0.6 \
    HC_CONFIDENCE_REQUIRED=true
)
printf "C20: confidence-gate SubagentStop 0.3 → block\n"
run_e_c20
_check_case "C20" "confidence-gate 0.3 block"

# --- C21: confidence-gate SubagentStop confidence 0.9 → pass ---
run_e_c21() ( set -uo pipefail
  TMP_CG="$(mktemp -d "${TMP_BASE}/cg-c21.XXXXXX")"
  mkdir -p "${TMP_CG}/state"
  TMP_TRANSCRIPT="${TMP_CG}/case21.jsonl"
  python3 -c '
import json
rec={"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"実装完了。全 build/test PASS。confidence: 0.9"}]},"uuid":"c21-smoke"}
print(json.dumps(rec))
' > "$TMP_TRANSCRIPT"
  local input
  input=$(TP="$TMP_TRANSCRIPT" python3 -c '
import json,os
print(json.dumps({"session_id":"c21-smoke","transcript_path":os.environ["TP"],"agent_type":"general-purpose"}))
')
  _capture_dispatcher "$SUBAGENT_DISP" "" "$input" \
    HC_FEATURE_CONFIDENCE_GATE_ENABLED=true \
    HC_CONFIDENCE_STATE_DIR="${TMP_CG}/state" \
    HC_CONFIDENCE_THRESHOLD=0.6 \
    HC_CONFIDENCE_REQUIRED=true
)
printf "C21: confidence-gate SubagentStop 0.9 → pass\n"
run_e_c21
_check_case "C21" "confidence-gate 0.9 pass"

# --- C22: delegation-guard Grep protected src path → Pre Grep dispatcher ---
run_e_c22() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c22.XXXXXX")"
  local json
  json=$(FP="${ROOT}/src/x.ts" python3 -c '
import json,os
print(json.dumps({"tool_name":"Grep","tool_input":{"path":os.environ["FP"]}}))
')
  _capture_dispatcher "$PRE_DISP" "Grep" "$json" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C22: delegation-guard Grep protected src path → block\n"
run_e_c22
_check_case "C22" "delegation-guard Grep protected"

# --- C23: delegation-guard Glob protected src path → Pre Glob dispatcher ---
run_e_c23() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c23.XXXXXX")"
  local json
  json=$(FP="${ROOT}/src/**" python3 -c '
import json,os
print(json.dumps({"tool_name":"Glob","tool_input":{"path":os.environ["FP"]}}))
')
  _capture_dispatcher "$PRE_DISP" "Glob" "$json" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)
printf "C23: delegation-guard Glob protected src path → block\n"
run_e_c23
_check_case "C23" "delegation-guard Glob protected"

# --- C24: gateguard Bash first destructive → Pre Bash dispatcher ---
# Pre Bash: order=1 autonomous-action-guard, order=2 delegation-guard, order=3 gateguard
# delegation OFF (git destructive が delegation でもブロックされるため) + autonomous OFF で
# gateguard (order=3 stdout-block) のみ block するよう設定。
run_e_c24() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c24.XXXXXX")"
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c24.XXXXXX")"
  local json
  json=$(CMD="git reset --hard HEAD" python3 -c '
import json,os
print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD"]}}))
')
  local out rc=0
  out=$(printf '%s' "$json" | \
    HC_FEATURE_GATEGUARD_ENABLED=true \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=false \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=false \
    HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED=false \
    HC_GATEGUARD_STATE_DIR="${STATE}" \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    bash "$PRE_DISP" "Bash" 2>/dev/null) || rc=$?
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
)
printf "C24: gateguard Bash first destructive → block (dispatcher, order=3)\n"
run_e_c24
_check_case "C24" "gateguard Bash destructive block"

# negative test (C1 false-positive 回帰防止):
# {"hookSpecificOutput":{"additionalContext":"I will block the decision"}} は block=no であることを確認
printf "NEG1: _has_block false-positive 回帰防止\n"
NEG_INPUT='{"hookSpecificOutput":{"additionalContext":"I will block the decision"}}'
NEG_RESULT="$(_has_block "$NEG_INPUT")"
if [ "$NEG_RESULT" = "no" ]; then
  PASS=$((PASS + 1))
  printf "  PASS: NEG1 false-positive block=no (C1 regression guard)\n"
else
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("NEG1: false-positive — _has_block returned '$NEG_RESULT' for non-block input")
  printf "  FAIL: NEG1 false-positive — _has_block returned '%s' for non-block input\n" "$NEG_RESULT"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== S-E Result (dispatcher blocker invariance) =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "\nFailed cases (dispatcher DRIFT from golden direct-hook):\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\n*** CUTOVER NOT SAFE: dispatcher changes blocker detection capability ***\n"
  exit 1
fi

printf "\n*** ALL 24 CASES + NEG MATCH GOLDEN: dispatcher is safe for cutover ***\n"
exit 0
