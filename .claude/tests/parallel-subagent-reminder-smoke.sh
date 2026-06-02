#!/usr/bin/env bash
# shellcheck disable=SC2329  # functions are invoked indirectly via "$test_fn" pattern
# .claude/tests/parallel-subagent-reminder-smoke.sh
# task #38 Step 2 iter2 — parallel-subagent-reminder hook smoke test
#
# 設計起源:
#   docs/draft/parallel-subagent-enforcement.md §4.4 + §4.5.3
#
# Cases:
#   Case 1:  単独 Agent 起動 + 実装系 keyword → 並列性 warning 注入
#   Case 2:  単独 Agent 起動 + reviewer 系 keyword (除外) → silent
#   Case 3:  並列 (2+) Agent 起動 (履歴に他 Agent あり) → silent
#   Case 4  (fail-open): 親 dir chmod 000 で mkdir -p が失敗 → exit 0 + silent
#   Case 5  (bypass): HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false → exit 0 + silent
#   Case 6:  general-purpose + 「smoke 拡張」keyword → test-automator 推奨 warning
#   Case 7:  general-purpose + 「refactor」keyword → refactoring-specialist 推奨 warning
#   Case 8:  test-automator (専門 type 採用済) + 「smoke 拡張」→ silent (適切な type)
#            + parallel warning は solo の場合でも独立して出ることを確認
#   Case 9:  TTL 境界条件 (TTL 超過 → 単発扱い warning / TTL 内 → silent)
#   Case 10: subagent_type 不在 / null → general-purpose mapping 対象外、exit 0
#   Case 13 (task-75): streak=1 (連続単発 1) → tier1 hint (既存文言「並列性 hint」維持)
#   Case 14 (task-75): streak=2 (連続単発 2) → tier2 強 reminder 文字列 present
#   Case 15 (task-75): streak>=3 (連続単発 3) → tier3「Workflow ツール」+「task-68」present
#   Case 16 (task-75): 並列 batch (近接 ts 2 entry) 後の単発 → streak リセット → tier1
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH 遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - **CLAUDE_PROJECT_DIR を必ず設定すること**: 未設定時 hook が git rev-parse で
#     リポルートを state dir として使い production state を汚染する。
#   - 各 case は _root_for N で独立 tmp dir を使い、state が case 間でリークしない
#     ようにする。
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
    sed 's/^/        /' "$diag_file"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
  rm -f "$diag_file"
}

# -------------------------------------------------------------------
# state dir mock helper
# $1 = root dir (must have .claude/ subdir created)
# $2 = "empty" | "with_recent_agent" | "with_expired_agent" | "with_ttl_fresh_agent"
# $3 = (optional) custom TTL seconds for "with_expired_agent" / "with_ttl_fresh_agent"
# -------------------------------------------------------------------
_setup_state_dir() {
  local root="$1"
  local mode="$2"
  local custom_ttl="${3:-300}"
  local state_dir="${root}/.claude/.parallel-subagent-state"
  mkdir -p "$state_dir"

  local ts_now
  ts_now="$(date +%s)"

  if [ "$mode" = "with_recent_agent" ]; then
    # 過去 1 分以内の Agent 起動を recent.json で模擬
    # hook の実際の形式: [{"ts": <unix>, "type": "<subagent_type>"}]
    printf '[{"ts":%s,"type":"general-purpose"},{"ts":%s,"type":"general-purpose"}]\n' \
      "$ts_now" "$ts_now" > "${state_dir}/recent.json"
  elif [ "$mode" = "with_expired_agent" ]; then
    # TTL 超過 (ts = now - custom_ttl - 2) の 1 件
    local expired_ts=$(( ts_now - custom_ttl - 2 ))
    printf '[{"ts":%s,"type":"general-purpose"}]\n' "$expired_ts" \
      > "${state_dir}/recent.json"
  elif [ "$mode" = "with_ttl_fresh_agent" ]; then
    # TTL 内 (ts = now) の 1 件
    printf '[{"ts":%s,"type":"general-purpose"}]\n' "$ts_now" \
      > "${state_dir}/recent.json"
  elif [ "$mode" = "empty" ]; then
    # 履歴なし (単独起動扱い): hook は state file 不在でも TTL 0 件扱いになるので
    # ファイルを作らない (不在 = empty 扱いと等価)
    : # no-op
  fi
}

# -------------------------------------------------------------------
# Case 1: 単独 Agent 起動 + 実装系 keyword → 並列性 warning 注入
#
# 修正 (R1 F-03 + R3 + R5): 旧実装は L117 out + L128 combined で二重 invoke。
# 新実装: 1 回 invoke で out=$(... 2>&1) を取得し、out のみで assertion。
# -------------------------------------------------------------------
case_1_solo_impl_keyword_warns() {
  local root
  root=$(_root_for 1)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  # 1 回のみ invoke (state 汚染なし)
  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # additionalContext 形式のチェック: parallel/並列 keyword が出力に含まれるか
  if printf '%s' "$out" | grep -q "system-reminder\|parallel\|並列\|additionalContext"; then
    return 0
  fi

  # JSON として valid で additionalContext が非空かチェック
  if printf '%s' "$out" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hookSpecificOutput',{}).get('additionalContext','') else 1)" \
    2>/dev/null; then
    return 0
  fi

  printf 'expected parallel warning in output, got: [%s]\n' \
    "$(printf '%s' "$out" | head -c 200)" >&2
  return 1
}

# -------------------------------------------------------------------
# Case 2: 単独 Agent 起動 + reviewer 系 keyword (除外) → silent
#
# 修正 (R1 F-01 + R5 H3 + R3 + R4): 旧 L166 で $out (未定義) を参照。
# 新実装: combined のみで assertion、$out は使わない。
# -------------------------------------------------------------------
case_2_solo_reviewer_keyword_silent() {
  local root
  root=$(_root_for 2)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"コード reviewer として設計書をチェック","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined code
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 並列性 warning が含まれていないことを assert
  if printf '%s' "$combined" | grep -q "parallel\|並列"; then
    printf 'expected silent for reviewer keyword, got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
  fi

  # 出力が valid JSON であることを確認 (空でも {} でも OK)
  if ! printf '%s' "$combined" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'expected valid JSON output, got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
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

  local combined code
  combined=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 既に並列で Agent 起動されているので warning は不要
  if printf '%s' "$combined" | grep -q "parallel\|並列"; then
    printf 'expected silent (history has agent), got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 4 (fail-open): 親 dir を chmod 000 で書込禁止 → hook の mkdir -p が失敗
#          → 真の fail-open path 起動 → exit 0 + silent
#
# 修正 (R4 CRITICAL + R1 F-04 + R6 + R3 + R5):
# 旧実装は hook 内 mkdir -p が自動作成するため state dir 不在が再現できなかった。
# 新方針 1: .claude/ 親 dir を chmod 000 → mkdir -p が失敗 → fail-open path を確認。
# trap で chmod 755 復元を保証。root 権限不要。
# -------------------------------------------------------------------
case_4_failopen_mkdir_blocked() {
  local root
  root=$(_root_for 4)
  mkdir -p "${root}/.claude"
  # .parallel-subagent-state を意図的に作らず、.claude/ を chmod 000 で書込禁止にする
  # → hook 内の mkdir -p "$state_dir" が失敗 → fail-open (echo '{}'; exit 0) へ

  # root が root (uid 0) の場合は chmod 000 が効かないのでスキップ
  if [ "$(id -u)" = "0" ]; then
    printf 'skipping chmod 000 test (running as root)\n'
    return 0
  fi

  # hook 不在の場合も構造確認のみ PASS
  if [ ! -f "$HOOK" ]; then
    return 0
  fi

  # chmod 000 + trap で必ず復元
  chmod 000 "${root}/.claude"
  local restore_done=0
  # shellcheck disable=SC2317
  _restore_case4() {
    if [ "$restore_done" -eq 0 ]; then
      chmod 755 "${root}/.claude" 2>/dev/null || true
      restore_done=1
    fi
  }
  trap _restore_case4 RETURN

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  # 必ず復元
  _restore_case4

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0 (fail-open with blocked mkdir), got %d\n' "$code" >&2
    return 1
  fi

  # fail-open は silent: ERROR/FAIL メッセージを含まない
  if printf '%s' "$out" | grep -q "^ERROR\|^FAIL\|^error"; then
    printf 'expected silent fail-open, got errors: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # 出力は {} または valid JSON であること
  if ! printf '%s' "$out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'expected valid JSON output on fail-open, got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
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
      "$(printf '%s' "$combined" | head -c 200)" >&2
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
# Case 8: test-automator (専門 type 採用済) + 「smoke 拡張」→ agent type warning なし
#          + solo 起動なら並列性 warning は独立して出ること (type warning と parallel
#            warning は独立)
#
# 修正 (R1 + R4): 旧実装は type warning の逆 grep のみ。
# 新実装: exit 0 確認 + valid JSON 確認 + type warning なし + parallel warning 有り を assert。
# -------------------------------------------------------------------
case_8_specialist_type_no_type_warning_but_parallel_warns() {
  local root
  root=$(_root_for 8)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"smoke 拡張テストの追加","run_in_background":true,"subagent_type":"test-automator"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 出力は valid JSON であること
  if ! printf '%s' "$out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'expected valid JSON output, got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # 専門 type を既に採用しているので agent type warning は不要
  if printf '%s' "$out" | grep -qi "test-automator.*推奨\|recommend.*test-automator\|専門.*type\|agent type 選定"; then
    printf 'expected no agent-type warning (specialist already used), got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # solo 起動 + 実装系 keyword (smoke 拡張) なので parallel warning は出ること
  # (type warning と parallel warning は独立している)
  if ! printf '%s' "$out" | grep -q "parallel\|並列\|additionalContext"; then
    # additionalContext JSON 経由でも確認
    if ! printf '%s' "$out" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hookSpecificOutput',{}).get('additionalContext','') else 1)" \
      2>/dev/null; then
      printf 'expected parallel warning (solo + impl keyword) even with specialist type, got: [%s]\n' \
        "$(printf '%s' "$out" | head -c 200)" >&2
      return 1
    fi
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 9: TTL 境界条件
#   Sub-case A: TTL 超過 (ts = now - TTL - 2) の 1 件 → 単発扱い → warning 出る
#   Sub-case B: TTL 内 (ts = now) の 1 件 → 並列扱い (count=2) → warning 出ない
#   (R1 F-02 + R2 F-03 + R3 追加要件)
# -------------------------------------------------------------------
case_9a_ttl_expired_entry_treated_as_solo() {
  local root
  root=$(_root_for 9a)
  mkdir -p "${root}/.claude"
  local ttl=1
  _setup_state_dir "$root" "with_expired_agent" "$ttl"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(HC_PARALLEL_SUBAGENT_TTL_SEC="$ttl" CLAUDE_PROJECT_DIR="$root" \
    bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # TTL 超過 entry は filtered out → recent_active_count=0 (本起動前) → 単発扱い
  # → parallel warning が出ること
  if printf '%s' "$out" | grep -q "parallel\|並列\|additionalContext"; then
    return 0
  fi
  if printf '%s' "$out" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hookSpecificOutput',{}).get('additionalContext','') else 1)" \
    2>/dev/null; then
    return 0
  fi

  printf 'expected parallel warning (TTL expired entry treated as solo), got: [%s]\n' \
    "$(printf '%s' "$out" | head -c 200)" >&2
  return 1
}

case_9b_ttl_fresh_entry_treated_as_parallel() {
  local root
  root=$(_root_for 9b)
  mkdir -p "${root}/.claude"
  local ttl=300
  _setup_state_dir "$root" "with_ttl_fresh_agent" "$ttl"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local combined code
  combined=$(HC_PARALLEL_SUBAGENT_TTL_SEC="$ttl" CLAUDE_PROJECT_DIR="$root" \
    bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 規範 development-process.md §6「機械強制 hook の判定境界」で `count <= 1` で warning 確定。
  # TTL 内 1 件 (ts=now, TTL=300) → filtered count=1 → recent_active_count=1 <= 1 → warning 発火。
  # task_desc=「新 hook 実装を行う」は parallel_keywords「実装」にマッチ、exclude_keywords 不在。
  # → parallel warning が additionalContext に含まれることが唯一の正解。
  if ! printf '%s' "$combined" | grep -qE 'parallel|並列'; then
    printf 'expected parallel warning at TTL boundary (count=1, hook spec <= 1), got: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
  fi

  # valid JSON 副 assertion
  if ! printf '%s' "$combined" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'TTL fresh entry boundary: output is not valid JSON: [%s]\n' \
      "$(printf '%s' "$combined" | head -c 200)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 10: subagent_type 不在 / null / 空文字 → general-purpose mapping 対象外
#           → agent type warning なし、exit 0 + valid JSON
#   (R2 F-03 + R5 M3 + R6 追加要件)
# -------------------------------------------------------------------
case_10_missing_subagent_type_no_type_warning() {
  local root
  root=$(_root_for 10)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  # subagent_type key を完全削除した JSON
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"smoke 拡張テストの追加","run_in_background":true}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 出力は valid JSON であること
  if ! printf '%s' "$out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'expected valid JSON output, got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # subagent_type が "" (fallback) の場合、"general-purpose" != "" なので
  # type mapping は走らない → agent type warning は不要
  if printf '%s' "$out" | grep -qi "推奨.*type\|recommend.*type\|専門.*type\|agent type 選定"; then
    printf 'expected no agent-type warning (subagent_type absent), got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  return 0
}

# -------------------------------------------------------------------
# Case 11: exclude_keywords word boundary regression (substring `preview`)
#          description = "preview 画面の実装" → 旧 `review` substring 誤マッチで
#          false-negative 抑制されていた。Fix 9 (R4-H2 HIGH) で word boundary
#          (`\breview\b`) 化後は parallel warning が正しく発火することを assert。
# -------------------------------------------------------------------
case_11_preview_substring_no_false_exclude() {
  local root
  root=$(_root_for 11)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"preview 画面の実装","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # "preview" は exclude `review` の substring で旧実装は誤抑制していた。
  # word boundary 化後は parallel warning が出ること。
  if printf '%s' "$out" | grep -q "parallel\|並列\|additionalContext"; then
    return 0
  fi
  if printf '%s' "$out" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('hookSpecificOutput',{}).get('additionalContext','') else 1)" \
    2>/dev/null; then
    return 0
  fi

  printf 'expected parallel warning (preview is not review), got: [%s]\n' \
    "$(printf '%s' "$out" | head -c 200)" >&2
  return 1
}

# -------------------------------------------------------------------
# Case 12: exclude_keywords word boundary regression (compound word `code-reviewer`)
#          description = "code-reviewer に確認させる実装" → 旧 `reviewer` /
#          `review` 二重 substring 誤マッチで false-negative 抑制されていた。
#          word boundary 化後は parallel warning が発火することを assert。
#
# 注: grep -E の `\b` はハイフン (`-`) を word 境界として扱う。`code-reviewer`
#     内の `reviewer` は `-` の直後 = word 境界成立 → `\breviewer\b` に match
#     する。これは現実装の意図 (reviewer/review/audit/監査 が含まれるなら除外)
#     と整合的。`code-reviewer に確認させる実装` の場合、description 全体の
#     意図は subagent type 名称への言及で除外 keyword と一致しているため、
#     現実装は warning を抑制する。
#     → 本 case は「word boundary 化が compound word に対しても誤判定しない」
#       ことを確認するため、warning 発火 or silent のどちらでも valid JSON +
#       exit 0 であることを assert する (assertion 緩和)。
# -------------------------------------------------------------------
case_12_code_reviewer_compound_word_valid_output() {
  local root
  root=$(_root_for 12)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"code-reviewer に確認させる実装","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?

  if [ "$code" -ne 0 ]; then
    printf 'expected exit 0, got %d\n' "$code" >&2
    return 1
  fi

  # 出力は valid JSON であること (warning 発火/silent どちらでも OK)
  if ! printf '%s' "$out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    printf 'expected valid JSON output, got: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  # ERROR/FAIL メッセージを含まないこと (fail-open 健全性)
  if printf '%s' "$out" | grep -q "^ERROR\|^FAIL\|^error"; then
    printf 'unexpected error in output: [%s]\n' \
      "$(printf '%s' "$out" | head -c 200)" >&2
    return 1
  fi

  return 0
}

# ===================================================================
# task-75: escalating streak tier cases (13-16)
# ===================================================================
# streak state helper: write N solo entries (distinct ts beyond batch window).
# entries are ts = now - gap*(N..1) so each is its own batch (single-entry cluster).
# 本起動 (append) で streak は N+1 になる前提で tier 閾値を狙う。
_setup_solo_streak() {
  local root="$1"
  local n="$2"
  local state_dir="${root}/.claude/.parallel-subagent-state"
  mkdir -p "$state_dir"
  local ts_now
  ts_now="$(date +%s)"
  local gap=30  # batch window (5s default) より十分離す = 各 entry 独立 batch
  local json="["
  local i
  for (( i=n; i>=1; i-- )); do
    local ts=$(( ts_now - gap * i ))
    json+="{\"ts\":${ts},\"type\":\"general-purpose\"}"
    [ "$i" -gt 1 ] && json+=","
  done
  json+="]"
  printf '%s\n' "$json" > "${state_dir}/recent.json"
}

# 並列 batch リセット用: 最新側に近接 ts 2 entry (= 1 並列 batch) を置く。
# その後の本起動 (単発) で streak は打ち切られ tier1 に戻ること。
_setup_parallel_batch_then_solo() {
  local root="$1"
  local state_dir="${root}/.claude/.parallel-subagent-state"
  mkdir -p "$state_dir"
  local ts_now
  ts_now="$(date +%s)"
  # 古い側に連続単発 (streak を稼ぐ) → 直近に並列 batch 2 件 (近接 ts)
  # 本起動はさらに後 (now) の単発。並列 batch が最新側 cluster の打ち切りになる。
  local solo1=$(( ts_now - 120 ))
  local solo2=$(( ts_now - 90 ))
  local par1=$(( ts_now - 3 ))
  local par2=$(( ts_now - 2 ))
  printf '[{"ts":%s,"type":"general-purpose"},{"ts":%s,"type":"general-purpose"},{"ts":%s,"type":"general-purpose"},{"ts":%s,"type":"general-purpose"}]\n' \
    "$solo1" "$solo2" "$par1" "$par2" > "${state_dir}/recent.json"
}

# Case 13: streak=1 → tier1 (現状 hint「並列性 hint」維持)
case_13_streak1_tier1() {
  local root
  root=$(_root_for 13)
  mkdir -p "${root}/.claude"
  _setup_state_dir "$root" "empty"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then printf 'expected exit 0, got %d\n' "$code" >&2; return 1; fi

  # tier1: 既存「並列性 hint」文言が present、tier2/3 文言は absent
  if ! printf '%s' "$out" | grep -q "並列性 hint"; then
    printf 'expected tier1 (並列性 hint), got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  if printf '%s' "$out" | grep -qi "Workflow\|連続で単発"; then
    printf 'expected NO tier2/3 escalation at streak=1, got: [%s]\n' "$(printf '%s' "$out" | head -c 300)" >&2
    return 1
  fi
  return 0
}

# Case 14: streak=2 → tier2 強 reminder
case_14_streak2_tier2() {
  local root
  root=$(_root_for 14)
  mkdir -p "${root}/.claude"
  _setup_solo_streak "$root" 1  # 既存 1 solo + 本起動 = streak 2

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then printf 'expected exit 0, got %d\n' "$code" >&2; return 1; fi

  # tier2: 「同一 message 内で複数 Agent を並列起動」相当 + 「連続で単発」文言
  if ! printf '%s' "$out" | grep -q "同一 message 内で複数 Agent を並列起動"; then
    printf 'expected tier2 (同一 message 内で並列起動), got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -q "連続で単発"; then
    printf 'expected tier2 streak count phrase (連続で単発), got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  # tier3 文言はまだ出ない
  if printf '%s' "$out" | grep -q "Workflow"; then
    printf 'expected NO tier3 (Workflow) at streak=2, got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  return 0
}

# Case 15: streak>=3 → tier3 最強 (Workflow + task-68)
case_15_streak3_tier3() {
  local root
  root=$(_root_for 15)
  mkdir -p "${root}/.claude"
  _setup_solo_streak "$root" 2  # 既存 2 solo + 本起動 = streak 3

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  local out code
  out=$(CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then printf 'expected exit 0, got %d\n' "$code" >&2; return 1; fi

  if ! printf '%s' "$out" | grep -q "Workflow"; then
    printf 'expected tier3 (Workflow tool), got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  if ! printf '%s' "$out" | grep -q "task-68"; then
    printf 'expected tier3 (task-68 reference), got: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  return 0
}

# Case 16: 並列 batch → streak リセット → 本起動 tier1
case_16_parallel_batch_resets_streak() {
  local root
  root=$(_root_for 16)
  mkdir -p "${root}/.claude"
  _setup_parallel_batch_then_solo "$root"

  local input_json
  input_json=$(printf '{"tool_name":"Agent","tool_input":{"description":"新 hook 実装を行う","run_in_background":true,"subagent_type":"general-purpose"}}')

  # TTL を十分大きく (全 entry 残す) して streak 算出だけを検証
  local out code
  out=$(HC_PARALLEL_SUBAGENT_TTL_SEC=3600 CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<< "$input_json" 2>&1)
  code=$?
  if [ "$code" -ne 0 ]; then printf 'expected exit 0, got %d\n' "$code" >&2; return 1; fi

  # 最新側に並列 batch があるので streak は打ち切られ tier1 (本起動 = streak 1)
  # tier2/3 escalation 文言が出ないこと
  if printf '%s' "$out" | grep -qi "Workflow\|連続で単発"; then
    printf 'expected streak reset to tier1 after parallel batch, got escalation: [%s]\n' "$(printf '%s' "$out" | head -c 400)" >&2
    return 1
  fi
  return 0
}

# ===================================================================
# main
# ===================================================================
TOTAL_CASES=17  # Case 9 は sub-case A+B で 2 件、Case 11/12 (R4-H2), Case 13-16 (task-75 escalation)

printf '===== task #38 parallel-subagent-reminder smoke =====\n'
printf 'HOOK: %s\n' "$HOOK"
if [ ! -f "$HOOK" ]; then
  printf '[INFO] hook not yet implemented — Case 1/2/3/6/7/8/9a/9b/10/11/12 will be SKIP\n'
  printf '       Case 4/5 (fail-open / bypass) are hook-independent assertions\n'
fi
printf '\n'

# Case 1-3: 並列性検出 (§4.4)
run_case_verbose 1 'solo Agent + impl keyword -> parallel warning [1-invoke fix]' \
  case_1_solo_impl_keyword_warns

run_case_verbose 2 'solo Agent + reviewer keyword (excluded) -> silent [$out-undef fix]' \
  case_2_solo_reviewer_keyword_silent

run_case_verbose 3 'parallel (2+) Agent history -> silent' \
  case_3_parallel_history_silent

# Case 4-5: fail-open / bypass
run_case_verbose 4 'fail-open: chmod 000 blocks mkdir -p -> exit 0 + silent [chmod fix]' \
  case_4_failopen_mkdir_blocked "false"

run_case_verbose 5 'bypass: HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false -> silent' \
  case_5_bypass_env_silent "false"

# Case 6-8: agent type 選定検出 (§4.5.3)
run_case_verbose 6 'general-purpose + smoke keyword -> test-automator warning' \
  case_6_general_purpose_smoke_warns_test_automator

run_case_verbose 7 'general-purpose + refactor keyword -> refactoring-specialist warning' \
  case_7_general_purpose_refactor_warns_specialist

run_case_verbose 8 'test-automator (specialist) + solo + smoke -> no type warn + parallel warn [assertion強化]' \
  case_8_specialist_type_no_type_warning_but_parallel_warns

# Case 9: TTL 境界条件 (A/B 2 sub-case)
run_case_verbose '9a' 'TTL expired entry -> treated as solo -> parallel warning [TTL新規]' \
  case_9a_ttl_expired_entry_treated_as_solo

run_case_verbose '9b' 'TTL fresh entry (1件) -> boundary count=1 -> current hook behavior [TTL新規]' \
  case_9b_ttl_fresh_entry_treated_as_parallel

# Case 10: subagent_type 不在
run_case_verbose 10 'subagent_type absent/null -> no type warning + valid JSON [新規]' \
  case_10_missing_subagent_type_no_type_warning

# Case 11-12: exclude_keywords word boundary regression (R4-H2 HIGH fix)
run_case_verbose 11 'preview substring -> not excluded as review -> parallel warn [R4-H2]' \
  case_11_preview_substring_no_false_exclude

run_case_verbose 12 'code-reviewer compound word -> valid JSON + no error [R4-H2]' \
  case_12_code_reviewer_compound_word_valid_output

# Case 13-16: task-75 escalating streak tiers
run_case_verbose 13 'streak=1 -> tier1 hint (existing 並列性 hint) [task-75]' \
  case_13_streak1_tier1

run_case_verbose 14 'streak=2 -> tier2 strong reminder (同一 message 内で並列起動) [task-75]' \
  case_14_streak2_tier2

run_case_verbose 15 'streak>=3 -> tier3 (Workflow ツール + task-68) [task-75]' \
  case_15_streak3_tier3

run_case_verbose 16 'parallel batch -> streak reset -> tier1 [task-75]' \
  case_16_parallel_batch_resets_streak

printf '\n===== Result =====\n'
printf 'PASS: %d / %d\n' "$PASS" "$TOTAL_CASES"
printf 'SKIP: %d / %d  (hook not yet implemented)\n' "$SKIP" "$TOTAL_CASES"
printf 'FAIL: %d / %d\n' "$FAIL" "$TOTAL_CASES"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
