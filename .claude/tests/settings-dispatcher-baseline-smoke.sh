#!/usr/bin/env bash
# .claude/tests/settings-dispatcher-baseline-smoke.sh
#
# task-71 Step 2 — blocker exit code baseline smoke
#
# 目的:
#   settings.json の dispatcher 化 (Step 3-8) の前後で blocker hook の検出力
#   (exit code + stdout decision) が完全不変であることを保証する safety net。
#
#   本 Step では「化前 (現状) の golden baseline」を記録し、
#   Step 10 で「化後」を同 smoke の --verify で照合する。
#
# 使い方:
#   bash settings-dispatcher-baseline-smoke.sh --record   # golden を fixtures に書く (化前に 1 回)
#   bash settings-dispatcher-baseline-smoke.sh --verify    # 現挙動を golden と diff
#   bash settings-dispatcher-baseline-smoke.sh             # default = --verify
#
# golden 行 format (TSV):
#   case_id<TAB>hook<TAB>scenario<TAB>expected_exit<TAB>expected_block(yes/no)
#
# blocker channel:
#   exit 2 channel: draft-flow-guard / workflow-guard / byproduct-discharge-guard
#   stdout decision channel: delegation-guard / gateguard / task-rule-guard /
#                            autonomous-action-guard / check-md-mermaid / confidence-gate
#
# feature flag 強制 ON:
#   harness-dev preset では各 feature が false (no-op) の場合があるため、
#   baseline は HC_FEATURE_*_ENABLED=true で強制 ON した blocking 挙動を記録する。
#
# 重要制約:
#   - file-top set -u のみ (set -e 禁止、feedback_set_e_in_sourced_libs)
#   - 各 case は関数内 ( set -uo pipefail; ... ) subshell 隔離
#   - stateful hook は HC_*_STATE_DIR=$(mktemp -d) 隔離 + trap cleanup
#   - resolve_project_root() で repo root 解決
#
# 実行:
#   bash .claude/tests/settings-dispatcher-baseline-smoke.sh [--record|--verify]
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

# repo root を確実に解決
# 優先順: HC_PROJECT_ROOT env > BASH_SOURCE ベース git > cwd ベース git > cwd
_resolve_root() (
  set -uo pipefail
  # 1. env override (CI / test 用)
  if [ -n "${HC_PROJECT_ROOT:-}" ] && [ -d "${HC_PROJECT_ROOT}" ]; then
    printf '%s' "${HC_PROJECT_ROOT}"
    return 0
  fi
  # 2. BASH_SOURCE[0] が .claude/tests/<smoke>.sh にある場合は 2 階層上
  local _script_abs
  _script_abs="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local _script_dir
  _script_dir="$(dirname "$_script_abs")"
  if command -v git >/dev/null 2>&1; then
    local r
    r=$(git -C "$_script_dir" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$r" ] && [ -d "$r" ]; then
      printf '%s' "$r"
      return 0
    fi
  fi
  # 3. cwd ベース git (smoke を repo root から bash で呼ぶ標準的使い方)
  if command -v git >/dev/null 2>&1; then
    local r2
    r2=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$r2" ] && [ -d "$r2" ]; then
      printf '%s' "$r2"
      return 0
    fi
  fi
  # 4. fallback: cwd
  pwd
)

ROOT="$(_resolve_root)"
GOLDEN_DIR="${ROOT}/.claude/tests/fixtures/task-71"
GOLDEN_FILE="${GOLDEN_DIR}/blocker-baseline.tsv"

# mode: record or verify
MODE="verify"
if [ "${1:-}" = "--record" ]; then
  MODE="record"
fi

# clean env — subagent 短絡防止
unset CLAUDE_HARNESS_ROLE

# 一時ディレクトリ (per-run)
TMP_BASE="$(mktemp -d /tmp/baseline-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

# 結果受け渡し用ファイル (subshell → main scope)
RESULT_FILE="${TMP_BASE}/result.txt"

PASS=0
FAIL=0
FAILED_CASES=()

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

# JSON input builders
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

# stdout に "decision":"block" または "permissionDecision":"deny" が含まれるか判定 → yes/no
# C1 修正: 単一 anchored grep で 2 形式を検出。旧実装 (2 separate grep) は
#   {"additionalContext":"I will block the decision"} で false-positive、
#   かつ permissionDecision:deny を検出できないバグがあった。
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

# stdout-decision channel 用: hook 呼び出し + RESULT_FILE に "exit\nblock" を書く
# 使い方: _capture_decision_hook <hook_path> <tool_arg_or_empty> <input_json> [env_KEY=VAL ...]
# tool_arg_or_empty: delegation-guard.sh 等は $1 にツール名が必要、不要なら ""
_capture_decision_hook() {
  local hook_path="$1"
  local tool_arg="$2"
  local input="$3"
  shift 3
  local out rc=0
  if [ -n "$tool_arg" ]; then
    out=$(printf '%s' "$input" | env "$@" bash "$hook_path" "$tool_arg" 2>/dev/null) || rc=$?
  else
    out=$(printf '%s' "$input" | env "$@" bash "$hook_path" 2>/dev/null) || rc=$?
  fi
  printf '%s\n%s\n' "$rc" "$(_has_block "$out")" > "$RESULT_FILE"
}

# exit-code channel 用: hook 呼び出し + RESULT_FILE に "exit\nno" を書く
# 使い方: _capture_exit_hook <hook_path> <input_json> [env_KEY=VAL ...]
_capture_exit_hook() {
  local hook_path="$1"
  local input="$2"
  shift 2
  local rc=0
  printf '%s' "$input" | env "$@" bash "$hook_path" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
}

# Stop hook 用: stdin='{}' + RESULT_FILE 書き込み
# 使い方: _capture_stop_hook <hook_path> [env_KEY=VAL ...]
_capture_stop_hook() {
  local hook_path="$1"
  shift
  local rc=0
  echo '{}' | env "$@" bash "$hook_path" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
}

# record/verify helper — RESULT_FILE から読み取って process
_process_case() {
  local case_id="$1"
  local hook_name="$2"
  local scenario="$3"

  local actual_exit actual_block
  if [ -f "$RESULT_FILE" ]; then
    actual_exit=$(head -1 "$RESULT_FILE" | tr -d '[:space:]')
    actual_block=$(tail -1 "$RESULT_FILE" | tr -d '[:space:]')
    rm -f "$RESULT_FILE"
  else
    actual_exit="ERR"
    actual_block="ERR"
  fi

  if [ "$MODE" = "record" ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$case_id" "$hook_name" "$scenario" "$actual_exit" "$actual_block" \
      >> "$GOLDEN_FILE"
    printf "  [RECORD] %s: exit=%s block=%s\n" "$case_id" "$actual_exit" "$actual_block"
    PASS=$((PASS + 1))
  else
    local golden_line expected_exit expected_block
    golden_line=$(grep "^${case_id}	" "$GOLDEN_FILE" 2>/dev/null | head -1)
    if [ -z "$golden_line" ]; then
      FAIL=$((FAIL + 1))
      FAILED_CASES+=("${case_id}: golden entry not found")
      printf "  FAIL: %s — golden not found\n" "$case_id"
      return
    fi
    expected_exit=$(printf '%s' "$golden_line" | cut -f4)
    expected_block=$(printf '%s' "$golden_line" | cut -f5)

    if [ "$actual_exit" = "$expected_exit" ] && [ "$actual_block" = "$expected_block" ]; then
      PASS=$((PASS + 1))
      printf "  PASS: %s (exit=%s block=%s)\n" "$case_id" "$actual_exit" "$actual_block"
    else
      FAIL=$((FAIL + 1))
      FAILED_CASES+=("${case_id}: exit got=${actual_exit} want=${expected_exit} block got=${actual_block} want=${expected_block}")
      printf "  FAIL: %s\n    exit: got=%s want=%s\n    block: got=%s want=%s\n" \
        "$case_id" "$actual_exit" "$expected_exit" "$actual_block" "$expected_block"
    fi
  fi
}

# ------------------------------------------------------------------
# Setup golden dir
# ------------------------------------------------------------------

if [ "$MODE" = "record" ]; then
  mkdir -p "$GOLDEN_DIR"
  : > "$GOLDEN_FILE"
  printf "=== recording golden baseline to %s ===\n\n" "$GOLDEN_FILE"
else
  if [ ! -f "$GOLDEN_FILE" ]; then
    printf "ERROR: golden file not found: %s\n" "$GOLDEN_FILE" >&2
    printf "Run with --record first.\n" >&2
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
  printf "=== verifying against golden: %s ===\n\n" "$GOLDEN_FILE"
fi

# ------------------------------------------------------------------
# Case definitions (functions) — each writes result to RESULT_FILE
# ------------------------------------------------------------------

run_c01() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c01.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Edit" "$(_json_edit "${ROOT}/src/x.ts")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c02() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c02.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Edit" "$(_json_edit "${ROOT}/README.md")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c03() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c03.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Read" "$(_json_read "${ROOT}/src/x.ts")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c04() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c04.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Bash" "$(_json_bash "git reset --hard HEAD")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}" \
    ECC_ALLOW_PROTECTED_BRANCH_PUSH=1
)

run_c05() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c05.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Bash" "$(_json_bash "git status")" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c06() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c06.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/gateguard.sh" \
    "Edit" "$(_json_edit "/tmp/baseline-c06-test.ts")" \
    HC_FEATURE_GATEGUARD_ENABLED=true \
    HC_GATEGUARD_STATE_DIR="${STATE}"
)

run_c07() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c07.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/gateguard.sh" \
    "Edit" "$(_json_edit "/tmp/baseline-c07-test.ts")" \
    HC_FEATURE_GATEGUARD_ENABLED=false \
    HC_GATEGUARD_STATE_DIR="${STATE}"
)

run_c08() ( set -uo pipefail
  TMP_TRG="$(mktemp -d "${TMP_BASE}/trg-c08.XXXXXX")"
  mkdir -p "${TMP_TRG}/docs/tasks" "${TMP_TRG}/docs/draft" \
           "${TMP_TRG}/.taskguard-state" "${TMP_TRG}/.agent-markers"
  _capture_decision_hook "${ROOT}/.claude/hooks/task-rule-guard.sh" \
    "Write" "$(_json_write "${TMP_TRG}/docs/tasks/task-99-no-draft-c08.md")" \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=true \
    HC_TASK_DIR=docs/tasks \
    HC_DRAFT_DIR=docs/draft \
    HC_TASKGUARD_STATE_DIR="${TMP_TRG}/.taskguard-state" \
    HC_AGENT_MARKER_DIR="${TMP_TRG}/.agent-markers"
)

run_c09() ( set -uo pipefail
  TMP_TRG="$(mktemp -d "${TMP_BASE}/trg-c09.XXXXXX")"
  mkdir -p "${TMP_TRG}/docs/tasks" "${TMP_TRG}/docs/draft" \
           "${TMP_TRG}/.taskguard-state" "${TMP_TRG}/.agent-markers"
  _capture_decision_hook "${ROOT}/.claude/hooks/task-rule-guard.sh" \
    "Write" "$(_json_write "${TMP_TRG}/docs/tasks/task-99-no-draft-c09.md")" \
    HC_FEATURE_TASK_RULE_GUARD_ENABLED=false \
    HC_TASK_DIR=docs/tasks \
    HC_DRAFT_DIR=docs/draft \
    HC_TASKGUARD_STATE_DIR="${TMP_TRG}/.taskguard-state" \
    HC_AGENT_MARKER_DIR="${TMP_TRG}/.agent-markers"
)

run_c10() ( set -uo pipefail
  TMP_DFG="$(mktemp -d "${TMP_BASE}/dfg-c10.XXXXXX")"
  mkdir -p "${TMP_DFG}/.git" "${TMP_DFG}/docs/draft" "${TMP_DFG}/docs/tasks"
  local rc=0
  (
    cd "${TMP_DFG}" || exit 99
    printf '%s' "$(_json_write "${TMP_DFG}/docs/zzz-new.md")" | \
      HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=true \
      HC_PROJECT_ROOT="${TMP_DFG}" \
      bash "${ROOT}/.claude/hooks/draft-flow-guard.sh" >/dev/null 2>&1
  ) || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c11() ( set -uo pipefail
  TMP_DFG="$(mktemp -d "${TMP_BASE}/dfg-c11.XXXXXX")"
  mkdir -p "${TMP_DFG}/.git" "${TMP_DFG}/docs/draft" "${TMP_DFG}/docs/tasks"
  local rc=0
  (
    cd "${TMP_DFG}" || exit 99
    printf '%s' "$(_json_write "${TMP_DFG}/docs/draft/zzz-new.md")" | \
      HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=true \
      HC_PROJECT_ROOT="${TMP_DFG}" \
      bash "${ROOT}/.claude/hooks/draft-flow-guard.sh" >/dev/null 2>&1
  ) || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c12() ( set -uo pipefail
  TMP_DFG="$(mktemp -d "${TMP_BASE}/dfg-c12.XXXXXX")"
  mkdir -p "${TMP_DFG}/.git" "${TMP_DFG}/docs/draft" "${TMP_DFG}/docs/tasks"
  local rc=0
  (
    cd "${TMP_DFG}" || exit 99
    printf '%s' "$(_json_write "${TMP_DFG}/docs/zzz-disabled.md")" | \
      HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false \
      HC_PROJECT_ROOT="${TMP_DFG}" \
      bash "${ROOT}/.claude/hooks/draft-flow-guard.sh" >/dev/null 2>&1
  ) || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c13() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c13.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/autonomous-action-guard.sh" \
    "" "$(_json_bash "supabase db reset")" \
    HC_MODE=loop \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c14() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c14.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/autonomous-action-guard.sh" \
    "" "$(_json_bash "supabase db reset")" \
    HC_MODE=normal \
    HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED=true \
    HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED=false \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

run_c15() ( set -uo pipefail
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
    CLAUDE_PROJECT_DIR="${TMP_WF}" \
    bash "${ROOT}/.claude/hooks/workflow-guard.sh" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c16() ( set -uo pipefail
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
    CLAUDE_PROJECT_DIR="${TMP_WF}" \
    bash "${ROOT}/.claude/hooks/workflow-guard.sh" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c17() ( set -uo pipefail
  # C17 環境依存対応 (C17 mermaid golden 修正):
  # mermaid CLI (mmdc) / node が不在の環境では check-md-mermaid が fail-open (exit 0, block=no) になる。
  # --record モードでは実挙動をそのまま golden に書く (環境依存は golden に吸収)。
  # --verify モードでは golden と照合するので環境差分で FAIL しない。
  # ただし mmdc が不在の場合、npx fallback でネットワーク接続が必要になるため、
  # mmdc または node を持たない CI 環境では check が SKIP (fail-open) となる点を docstring に明示。
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
  _capture_decision_hook "${ROOT}/.claude/hooks/check-md-mermaid.sh" \
    "" "$input" \
    HC_FEATURE_CHECK_MD_MERMAID_ENABLED=true
)

run_c18() ( set -uo pipefail
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
    bash "${ROOT}/.claude/hooks/byproduct-discharge-guard.sh" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c19() ( set -uo pipefail
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
    bash "${ROOT}/.claude/hooks/byproduct-discharge-guard.sh" >/dev/null 2>&1 || rc=$?
  printf '%s\nno\n' "$rc" > "$RESULT_FILE"
)

run_c20() ( set -uo pipefail
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
  _capture_decision_hook "${ROOT}/.claude/hooks/confidence-gate.sh" \
    "" "$input" \
    HC_FEATURE_CONFIDENCE_GATE_ENABLED=true \
    HC_CONFIDENCE_STATE_DIR="${TMP_CG}/state" \
    HC_CONFIDENCE_THRESHOLD=0.6 \
    HC_CONFIDENCE_REQUIRED=true
)

run_c21() ( set -uo pipefail
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
  _capture_decision_hook "${ROOT}/.claude/hooks/confidence-gate.sh" \
    "" "$input" \
    HC_FEATURE_CONFIDENCE_GATE_ENABLED=true \
    HC_CONFIDENCE_STATE_DIR="${TMP_CG}/state" \
    HC_CONFIDENCE_THRESHOLD=0.6 \
    HC_CONFIDENCE_REQUIRED=true
)

# C22: delegation-guard Grep protected src path → block (C2 新規 case)
run_c22() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c22.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Grep" "$(FP="${ROOT}/src/x.ts" python3 -c '
import json,os
print(json.dumps({"tool_name":"Grep","tool_input":{"path":os.environ["FP"]}}))
')" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

# C23: delegation-guard Glob protected src path → block (C2 新規 case)
run_c23() ( set -uo pipefail
  MARKER="$(mktemp -d "${TMP_BASE}/marker-c23.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/delegation-guard.sh" \
    "Glob" "$(FP="${ROOT}/src/**" python3 -c '
import json,os
print(json.dumps({"tool_name":"Glob","tool_input":{"path":os.environ["FP"]}}))
')" \
    HC_FEATURE_DELEGATION_GUARD_ENABLED=true \
    HC_AGENT_MARKER_DIR="${MARKER}"
)

# C24: gateguard Bash first destructive → block (C2 新規 case、manifest order=3)
# Pre Bash: order=1 autonomous-action-guard, order=2 delegation-guard, order=3 gateguard
# delegation と autonomous を OFF にして gateguard (order=3) のみ block する設定で直接呼び出し。
# (dispatcher 経由はinvariance で別途検証)
run_c24() ( set -uo pipefail
  STATE="$(mktemp -d "${TMP_BASE}/gstate-c24.XXXXXX")"
  _capture_decision_hook "${ROOT}/.claude/hooks/gateguard.sh" \
    "Bash" "$(_json_bash "git reset --hard HEAD")" \
    HC_FEATURE_GATEGUARD_ENABLED=true \
    HC_GATEGUARD_STATE_DIR="${STATE}"
)

# ------------------------------------------------------------------
# Run all cases
# ------------------------------------------------------------------

printf "C01: delegation-guard Edit protected src path → block\n"
run_c01
_process_case "C01" "delegation-guard.sh" "Edit protected src path (block)"

printf "C02: delegation-guard Edit README.md → non-protected pass\n"
run_c02
_process_case "C02" "delegation-guard.sh" "Edit README.md (non-protected pass)"

printf "C03: delegation-guard Read protected src path → block\n"
run_c03
_process_case "C03" "delegation-guard.sh" "Read protected src path (block)"

printf "C04: delegation-guard Bash git reset --hard HEAD → destructive block\n"
run_c04
_process_case "C04" "delegation-guard.sh" "Bash git reset --hard HEAD (destructive block)"

printf "C05: delegation-guard Bash git status → whitelist pass\n"
run_c05
_process_case "C05" "delegation-guard.sh" "Bash git status (whitelist pass)"

printf "C06: gateguard Edit feature ON + fresh state → first-edit block\n"
run_c06
_process_case "C06" "gateguard.sh" "Edit fresh state (first-edit block, feature ON)"

printf "C07: gateguard Edit feature OFF → no-op\n"
run_c07
_process_case "C07" "gateguard.sh" "Edit feature OFF (no-op)"

printf "C08: task-rule-guard Write feature ON + no draft → block\n"
run_c08
_process_case "C08" "task-rule-guard.sh" "Write new task no draft (block, feature ON)"

printf "C09: task-rule-guard Write feature OFF → no-op\n"
run_c09
_process_case "C09" "task-rule-guard.sh" "Write feature OFF (no-op)"

printf "C10: draft-flow-guard Write feature ON + docs/zzz-new.md no draft → exit 2\n"
run_c10
_process_case "C10" "draft-flow-guard.sh" "Write docs/zzz-new.md no draft (exit 2, feature ON)"

printf "C11: draft-flow-guard Write docs/draft/zzz-new.md → draft path pass\n"
run_c11
_process_case "C11" "draft-flow-guard.sh" "Write docs/draft/zzz-new.md (draft path pass)"

printf "C12: draft-flow-guard Write feature OFF → no-op\n"
run_c12
_process_case "C12" "draft-flow-guard.sh" "Write feature OFF (no-op)"

printf "C13: autonomous-action-guard Bash Loop + supabase db reset → block\n"
run_c13
_process_case "C13" "autonomous-action-guard.sh" "Loop supabase db reset (block)"

printf "C14: autonomous-action-guard Bash Normal + supabase db reset → advisory (no block)\n"
run_c14
_process_case "C14" "autonomous-action-guard.sh" "Normal supabase db reset (advisory, no block)"

printf "C15: workflow-guard feature ON + /finish-task + stage not final → exit 2\n"
run_c15
_process_case "C15" "workflow-guard.sh" "/finish-task stage not final (exit 2, feature ON)"

printf "C16: workflow-guard feature OFF + /finish-task → no-op\n"
run_c16
_process_case "C16" "workflow-guard.sh" "/finish-task feature OFF (no-op)"

printf "C17: check-md-mermaid Edit .md broken mermaid → block (if mermaid avail)\n"
run_c17
_process_case "C17" "check-md-mermaid.sh" "Edit .md broken mermaid (block if mermaid avail)"

printf "C18: byproduct-discharge-guard Stop 🔴 entry → exit 2\n"
run_c18
_process_case "C18" "byproduct-discharge-guard.sh" "Stop with red entry (exit 2)"

printf "C19: byproduct-discharge-guard Stop clean next-actions → exit 0\n"
run_c19
_process_case "C19" "byproduct-discharge-guard.sh" "Stop clean next-actions (exit 0)"

printf "C20: confidence-gate SubagentStop confidence 0.3 → block\n"
run_c20
_process_case "C20" "confidence-gate.sh" "SubagentStop confidence 0.3 (block)"

printf "C21: confidence-gate SubagentStop confidence 0.9 → pass\n"
run_c21
_process_case "C21" "confidence-gate.sh" "SubagentStop confidence 0.9 (pass)"

printf "C22: delegation-guard Grep protected src path → block\n"
run_c22
_process_case "C22" "delegation-guard.sh" "Grep protected src path (block)"

printf "C23: delegation-guard Glob protected src path → block\n"
run_c23
_process_case "C23" "delegation-guard.sh" "Glob protected src path (block)"

printf "C24: gateguard Bash first destructive → block (gateguard direct)\n"
run_c24
_process_case "C24" "gateguard.sh" "Bash first destructive (block, feature ON)"

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
  FAILED_CASES+=("NEG1: false-positive detected block='$NEG_RESULT' for non-block input")
  printf "  FAIL: NEG1 false-positive — _has_block returned '%s' for non-block input\n" "$NEG_RESULT"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== Result (%s mode) =====\n" "$MODE"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "\nFailed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  exit 1
fi

if [ "$MODE" = "record" ]; then
  printf "\ngolden saved: %s\n" "$GOLDEN_FILE"
  printf "Run --verify to confirm baseline is consistent.\n"
fi

exit 0
