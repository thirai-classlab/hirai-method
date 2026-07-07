#!/usr/bin/env bash
# lib-observability-smoke.sh — task-99 smoke for .claude/hooks/lib/observability.sh
#
# 設計起源:
#   docs/tasks/task-99-lib-observability-30d-gc.md Step 5 (5 case A-E)
#   master roadmap install-immediately-usable-redesign-20260618 §3 I5 / §5 P3-2
#
# 対象 lib: .claude/hooks/lib/observability.sh
#
# 検証範囲 (5 ケース):
#   A: source 後に 5 公開 API (log_block / log_bypass / log_fire / log_silent_failure / log_event) が定義済
#   B: log_fire 呼出で observations.jsonl に event_kind="fire" JSONL 1 行 append
#   C: log_bypass 呼出で bypass.log にも 1 行 append (bypass-logger.sh superset 契約)
#   D: HC_FEATURE_OBSERVABILITY_ENABLED=false で全 log_* が no-op
#   E: jq 不在時に printf fallback で妥当な JSON を吐く (別 bash subprocess で command shadow)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 教訓)
#   - 独立 /tmp dir で live .claude/observability を汚染しない
#   - CLAUDE_PROJECT_DIR で log 出力先を隔離
#
# 実行:
#   bash .claude/tests/lib-observability-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/.claude/hooks/lib/observability.sh"

if [ ! -f "$LIB" ]; then
  printf 'FAIL: %s not found\n' "$LIB" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# =====================================================================
# Case A: 5 API 定義済 (subshell で env 汚染回避)
# =====================================================================
caseA_apis_defined() {
  local label="Case A: 5 public APIs defined after source"
  local count
  count=$(bash -c "source '$LIB' && declare -f log_block log_bypass log_fire log_silent_failure log_event >/dev/null 2>&1 && echo OK" 2>/dev/null)

  if [ "$count" = "OK" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (declare check failed)")
    printf "  FAIL: %s\n" "$label"
  fi
}

# =====================================================================
# Case B: log_fire → observations.jsonl append
# =====================================================================
caseB_log_fire_append() {
  local label="Case B: log_fire appends fire JSONL to observations.jsonl"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/lib-obs-smoke-B.XXXXXX)
  local log_file="$tmpdir/.claude/observability/observations.jsonl"

  bash -c "
    export CLAUDE_PROJECT_DIR='$tmpdir'
    unset HC_FEATURE_OBSERVABILITY_ENABLED
    source '$LIB'
    log_fire 'test-hook-B' 'test reason B' '{\"key\":\"val\"}'
  " 2>/dev/null

  local ok=1
  if [ ! -f "$log_file" ]; then
    ok=0
  else
    # Verify: JSONL の 1 行目が event_kind="fire" + hook_name="test-hook-B"
    if ! python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    line = f.readline().strip()
    d = json.loads(line)
    assert d['event_kind'] == 'fire', f'kind={d[\"event_kind\"]}'
    assert d['hook_name'] == 'test-hook-B', f'hook={d[\"hook_name\"]}'
    assert d['reason'] == 'test reason B', f'reason={d[\"reason\"]}'
    assert d['payload'] == {'key':'val'}, f'payload={d[\"payload\"]}'
    assert d['_schema_version'] == 1
" "$log_file" 2>/dev/null; then
      ok=0
    fi
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (JSONL parse/assert failed)")
    printf "  FAIL: %s\n" "$label"
  fi
}

# =====================================================================
# Case C: log_bypass → bypass.log AND observations.jsonl 両方 append (superset 契約)
# =====================================================================
caseC_log_bypass_superset() {
  local label="Case C: log_bypass appends to BOTH bypass.log and observations.jsonl"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/lib-obs-smoke-C.XXXXXX)
  local obs_file="$tmpdir/.claude/observability/observations.jsonl"
  local bypass_file="$tmpdir/.claude/.workflow-state/bypass.log"

  bash -c "
    export CLAUDE_PROJECT_DIR='$tmpdir'
    export CLAUDE_SESSION_ID='sess-C'
    unset HC_FEATURE_OBSERVABILITY_ENABLED
    source '$LIB'
    log_bypass 'workflow-guard' 'ECC_WORKFLOW_GUARD_OFF' 'test bypass reason'
  " 2>/dev/null

  local ok=1
  if [ ! -f "$obs_file" ] || [ ! -f "$bypass_file" ]; then
    ok=0
  else
    # Verify obs file: event_kind="bypass" + env_var payload
    if ! python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    line = f.readline().strip()
    d = json.loads(line)
    assert d['event_kind'] == 'bypass', f'kind={d[\"event_kind\"]}'
    assert d['hook_name'] == 'workflow-guard'
    assert d['payload'].get('env_var') == 'ECC_WORKFLOW_GUARD_OFF'
" "$obs_file" 2>/dev/null; then
      ok=0
    fi
    # Verify bypass.log format: <ts> | <sess> | <hook> | <env> | <reason>
    if ! grep -qE 'sess-C \| workflow-guard \| ECC_WORKFLOW_GUARD_OFF \| test bypass reason' "$bypass_file" 2>/dev/null; then
      ok=0
    fi
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (obs or bypass.log format check failed)")
    printf "  FAIL: %s\n" "$label"
  fi
}

# =====================================================================
# Case D: feature OFF で no-op
# =====================================================================
caseD_feature_off_noop() {
  local label="Case D: HC_FEATURE_OBSERVABILITY_ENABLED=false → all log_* no-op"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/lib-obs-smoke-D.XXXXXX)
  local obs_file="$tmpdir/.claude/observability/observations.jsonl"

  bash -c "
    export CLAUDE_PROJECT_DIR='$tmpdir'
    export HC_FEATURE_OBSERVABILITY_ENABLED=false
    source '$LIB'
    log_fire 'test-hook-D' 'should not appear' ''
    log_block 'test-hook-D' 'should not appear' ''
    log_event 'custom' 'test-hook-D' 'should not appear' ''
    log_silent_failure 'test-hook-D' 'should not appear' ''
  " 2>/dev/null

  # obs file が作成されていないか、または空
  local ok=1
  if [ -f "$obs_file" ] && [ -s "$obs_file" ]; then
    ok=0
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (obs.jsonl created despite feature OFF)")
    printf "  FAIL: %s\n" "$label"
  fi
}

# =====================================================================
# Case E: jq 不在時 printf fallback で妥当な JSON
# =====================================================================
caseE_jq_fallback() {
  local label="Case E: jq absent → printf fallback yields valid JSON"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/lib-obs-smoke-E.XXXXXX)
  local obs_file="$tmpdir/.claude/observability/observations.jsonl"

  # command builtin をシャドウして "jq" 存在確認を偽装する
  bash -c "
    export CLAUDE_PROJECT_DIR='$tmpdir'
    unset HC_FEATURE_OBSERVABILITY_ENABLED
    # command wrapper: jq を not found と偽装
    command() {
      if [ \"\$1\" = '-v' ] && [ \"\$2\" = 'jq' ]; then
        return 1
      fi
      builtin command \"\$@\"
    }
    export -f command
    source '$LIB'
    log_fire 'test-hook-E' 'quote \"and\" backslash \\\\ test' '{\"a\":1}'
  " 2>/dev/null

  local ok=1
  if [ ! -f "$obs_file" ]; then
    ok=0
  else
    if ! python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    line = f.readline().strip()
    d = json.loads(line)
    assert d['event_kind'] == 'fire', f'kind={d[\"event_kind\"]}'
    assert d['hook_name'] == 'test-hook-E'
    assert 'quote' in d['reason']
    assert d['_schema_version'] == 1
" "$obs_file" 2>/dev/null; then
      ok=0
    fi
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (fallback JSON invalid)")
    printf "  FAIL: %s\n" "$label"
  fi
}

printf "===== lib-observability-smoke (task-99, 5 cases A-E) =====\n\n"

caseA_apis_defined
caseB_log_fire_append
caseC_log_bypass_superset
caseD_feature_off_noop
caseE_jq_fallback

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
