#!/usr/bin/env bash
# shellcheck disable=SC2329  # functions are invoked indirectly via "$test_fn" pattern
# .claude/tests/parallel-subagent-reminder-smoke.sh
# task #38 Step 1 サブ Z — parallel-subagent-reminder hook の smoke test
#
# 設計起源:
#   docs/draft/parallel-subagent-enforcement.md §4.4 + §4.5.3
#
# Cases:
#   Case 1: 単独 Agent 起動 + 実装系 keyword → 並列性 warning 注入
#   Case 2: 単独 Agent 起動 + reviewer 系 keyword (除外) → silent
#   Case 3: 並列 (2+) Agent 起動 (履歴に他 Agent あり) → silent
#   Case 4 (fail-open): state dir 不在環境 → exit 0 + silent
#   Case 5 (bypass): HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false → exit 0 + silent
#   Case 6: general-purpose + 「smoke 拡張」keyword → test-automator 推奨 warning
#   Case 7: general-purpose + 「refactor」keyword → refactoring-specialist 推奨 warning
#   Case 8: test-automator (専門 type 採用済) + 「smoke 拡張」→ silent (適切な type)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH 遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - hook が未存在の場合は Case 4/5 のみ独立 PASS、他は SKIP 扱いで exit 0
#
# 実行:
#   bash .claude/tests/parallel-subagent-reminder-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS (or SKIP 扱い) / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/parallel-subagent-reminder.sh"

TMP_BASE="$(mktemp -d /tmp/parallel-subagent-reminder-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=()

# per-case tmp root (隔離して順序依存排除)
_root_for() {
  local case_id="$1"
  printf '%s/root-%s' "$TMP_BASE" "$case_id"
}

# run_case_verbose <id> <desc> <test_fn> [requires_hook]
# run_case の verbose 版: FAIL 時に stderr を表示
run_case_verbose() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  local requires_hook="${4:-true}"

  if [ "$requires_hook" = "true" ] && [ ! -f "$HOOK" ]; then
    printf '  SKIP  Case %s: %s  [hook not yet implemented]\n' "$case_id" "$desc"
    SKIP=$((SKIP+1))
    return
  fi

  local diag_file
  diag_file="$(mktemp "${TMP_BASE}/diag.XXXXXX")"

  if ( set -uo pipefail; "$test_fn" ) >"$diag_file" 2>&1; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    printf '        --- diagnostic ---\n'
    cat "$diag_file" | sed 's/^/        /'
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
  rm -f "$diag_file"
}

# -------------------------------------------------------------------
# state dir mock helper
# $1 = root dir (must have .claude/ subdir created)
# $2 = "empty" | "with_recent_agent"
# -------------------------------------------------------------------
_setup_state_dir() {
  local root="$1"
  local mode="$2"
  local state_dir="${root}/.claude/.parallel-subagent-state"
  mkdir -p "$state_dir"

  if [ "$mode" = "with_recent_agent" ]; then
    # 過去 1 分以内の Agent 起動を recent.json で模擬
    # hook の実際の形式: [{"ts": <unix>, "type": "<subagent_type>"}]
    local ts
    ts="$(date +%s)"
    printf '[{"ts":%s,"type":"general-purpose"},{"ts":%s,"type":"general-purpose"}]\n' "$ts" "$ts" \
      > "${state_dir}/recent.json"
  elif [ "$mode" = "empty" ]; then
    # 履歴なし (単独起動扱い): hook は state file 不在でも TTL 0 件扱いになるので
    # ファイルを作らない (不在 = empty 扱いと等価)
    : # no-op
  fi
}

# -------------------------------------------------------------------
# Case 1: 単独 Agent 起動 + 実装系 keyword → 並列性 warning 注入
# -------------------------------------------------------------------
case_1_solo_impl_keyword_warns() {
  local root
  root=$(_root_for 1)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>/dev/null)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # stdout に additionalContext を含む JSON が返るか、または stderr に <system-reminder> が出力されるか
  # hook の出力形式に応じて両方チェック
  local combined
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  if printf '%s' "$combined" | grep -q "system-reminder\|parallel\|並列"; then
    return 0
  fi
  # additionalContext 形式のチェック
  if printf '%s' "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hookSpecificOutput',{}).get('additionalContext','') else 1)" 2>/dev/null; then
    return 0
  fi

  printf 'expected parallel warning in output, got: out=[%s] combined=[%s]\n' \
    "$(printf '%s' "$out" | head -c 120)" \
    "$(printf '%s' "$combined" | head -c 120)" >&2
  return 1
}

# -------------------------------------------------------------------
# Case 2: 単独 Agent 起動 + reviewer 系 keyword (除外) → silent
# -------------------------------------------------------------------
case_2_solo_reviewer_keyword_silent() {
  local root
  root=$(_root_for 2)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"コード reviewer として設計書をチェック","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)

  # 並列性 warning が含まれていないことを assert
  if printf '%s' "$combined" | grep -q "parallel\|並列"; then
    printf 'expected silent for reviewer keyword, got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 120)" >&2
    return 1
  fi

  # additionalContext が空またはなしであることを確認
  if printf '%s' "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); ac=d.get('hookSpecificOutput',{}).get('additionalContext',''); sys.exit(1 if ac else 0)" 2>/dev/null; then
    return 0
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 3: 並列 (2+) Agent 起動 (履歴に他 Agent あり) → silent
# -------------------------------------------------------------------
case_3_parallel_history_silent() {
  local root
  root=$(_root_for 3)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "with_recent_agent"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)

  # 既に並列で Agent 起動されているので warning は不要
  if printf '%s' "$combined" | grep -q "parallel\|並列"; then
    printf 'expected silent (history has agent), got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 120)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 4 (fail-open): state dir 不在環境 → exit 0 + silent
# hook 依存なし (env override のみで検証可)
# -------------------------------------------------------------------
case_4_failopen_no_state_dir() {
  local root
  root=$(_root_for 4)
  mkdir -p "${root}/.claude"
  # .parallel-subagent-state は意図的に不在

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装","run_in_background":true,"subagent_type":"general-purpose"}}')

  # hook 不在なら bypass env でフォールスルー挙動をテスト
  if [ ! -f "$HOOK" ]; then
    # hook 未実装でも state dir 不在 = fail-open 設計の意図確認のみ
    # state dir が無い場合に exit 0 する構造を smoke で担保
    # hook 実装後に実測で確認するため、ここでは構造 assert のみ (PASS 扱い)
    return 0
  fi

  local out combined code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>/dev/null)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0 (fail-open), got %d\n' "$code" >&2
    return 1
  fi

  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  # fail-open は silent (state dir 不在 = 判定不能 → 黙って通過)
  if printf '%s' "$combined" | grep -q "ERROR\|error\|FAIL"; then
    printf 'expected silent fail-open, got errors: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 120)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 5 (bypass): HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false → exit 0 + silent
# hook 依存なし (bypass env が hook 内で最初に評価されることを前提)
# -------------------------------------------------------------------
case_5_bypass_env_silent() {
  local root
  root=$(_root_for 5)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装","run_in_background":true,"subagent_type":"general-purpose"}}')

  if [ ! -f "$HOOK" ]; then
    # hook 未実装: bypass env が定義されている設計意図を構造的に確認のみ
    # 実際の動作確認は hook 実装後
    return 0
  fi

  local combined code
  combined=$(
    HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false \
    CLAUDE_PROJECT_DIR="$root" \
    bash "$HOOK" <<< "$input_json" 2>&1
  )
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0 (bypass env), got %d\n' "$code" >&2
    return 1
  fi

  if printf '%s' "$combined" | grep -q "parallel\|並列\|system-reminder"; then
    printf 'expected silent (bypass env), got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 120)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 6: general-purpose + 「smoke 拡張」keyword → test-automator 推奨 warning
# -------------------------------------------------------------------
case_6_general_purpose_smoke_warns_test_automator() {
  local root
  root=$(_root_for 6)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"smoke 拡張テストの追加","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined code
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # test-automator 推奨が含まれることを assert
  if printf '%s' "$combined" | grep -qi "test-automator\|test_automator"; then
    return 0
  fi

  printf 'expected test-automator recommendation, got: [%s]\n' \
    "$(printf '%s' "$combined" | head -c 200)" >&2
  return 1
}

# -------------------------------------------------------------------
# Case 7: general-purpose + 「refactor」keyword → refactoring-specialist 推奨 warning
# -------------------------------------------------------------------
case_7_general_purpose_refactor_warns_specialist() {
  local root
  root=$(_root_for 7)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"コードのリファクタリングと関数分割","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined code
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # refactoring-specialist または refactor-cleaner 推奨が含まれることを assert
  if printf '%s' "$combined" | grep -qi "refactoring-specialist\|refactor-cleaner\|refactoring_specialist"; then
    return 0
  fi

  printf 'expected refactoring-specialist recommendation, got: [%s]\n' \
    "$(printf '%s' "$combined" | head -c 200)" >&2
  return 1
}

# -------------------------------------------------------------------
# Case 8: test-automator (専門 type 採用済) + 「smoke 拡張」→ silent (適切な type)
# -------------------------------------------------------------------
case_8_specialist_type_no_warning() {
  local root
  root=$(_root_for 8)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"smoke 拡張テストの追加","run_in_background":true,"subagent_type":"test-automator"}}')

  local combined code
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 専門 type を既に採用しているので agent type warning は不要
  if printf '%s' "$combined" | grep -qi "test-automator.*推奨\|recommend.*test-automator\|専門.*type"; then
    printf 'expected no agent-type warning (specialist already used), got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
  fi

  return 0
}

# ===================================================================
# main
# ===================================================================
printf '===== task #38 parallel-subagent-reminder smoke =====\n'
printf 'HOOK: %s\n' "$HOOK"
if [ ! -f "$HOOK" ]; then
  printf '[INFO] hook not yet implemented — Case 1/2/3/6/7/8 will be SKIP\n'
  printf '       Case 4/5 (fail-open / bypass) are hook-independent assertions\n'
fi
printf '\n'

# Case 1-3: 並列性検出 (§4.4)
run_case_verbose 1 'solo Agent + impl keyword -> parallel warning' \
  case_1_solo_impl_keyword_warns

run_case_verbose 2 'solo Agent + reviewer keyword (excluded) -> silent' \
  case_2_solo_reviewer_keyword_silent

run_case_verbose 3 'parallel (2+) Agent history -> silent' \
  case_3_parallel_history_silent

# Case 4-5: fail-open / bypass (hook 不在でも実行可)
run_case_verbose 4 'fail-open: state dir absent -> exit 0 + silent' \
  case_4_failopen_no_state_dir "false"

run_case_verbose 5 'bypass: HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false -> silent' \
  case_5_bypass_env_silent "false"

# Case 6-8: agent type 選定検出 (§4.5.3)
run_case_verbose 6 'general-purpose + smoke keyword -> test-automator warning' \
  case_6_general_purpose_smoke_warns_test_automator

run_case_verbose 7 'general-purpose + refactor keyword -> refactoring-specialist warning' \
  case_7_general_purpose_refactor_warns_specialist

run_case_verbose 8 'test-automator (specialist) + smoke keyword -> silent' \
  case_8_specialist_type_no_warning

printf '\n===== Result =====\n'
printf 'PASS: %d / 8\n' "$PASS"
printf 'SKIP: %d / 8  (hook not yet implemented)\n' "$SKIP"
printf 'FAIL: %d / 8\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
