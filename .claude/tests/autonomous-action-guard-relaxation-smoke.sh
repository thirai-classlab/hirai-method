#!/usr/bin/env bash
# .claude/tests/autonomous-action-guard-relaxation-smoke.sh
#
# 目的:
#   autonomous-action-guard.sh の緩和効果 (task #39) を 7 ケースで検証する。
#
#   draft §4.1 採用案 C:
#     - `git push` 一般 pattern を DEFAULT_PATTERNS から削除 (feature branch push は通過)
#     - `gh pr create` を DEFAULT_PATTERNS から削除 (PR 作成は通過)
#     - `gh pr merge` は引き続き block
#
# 設計起源:
#   docs/draft/autonomous-action-guard-relaxation.md §4.4 新 smoke 5 cases
#   docs/tasks/task-39-autonomous-action-guard-relaxation.md Step 1 サブ C
#
# テストケース:
#   Case 1: Loop + `git push origin feat/foo` → 通過 (緩和効果、feature branch)
#   Case 2: Loop + `git push origin main`     → 通過 (autonomous-action-guard 単体検証、
#             delegation-guard 別 layer の block は本 smoke 対象外)
#   Case 3: Loop + `git push origin stg-v1`   → 通過 (autonomous-action-guard 単体検証、同上)
#   Case 4: Loop + `gh pr create --base main --head feat/foo` → 通過 (緩和効果、PR 作成許可)
#   Case 5: Loop + `gh pr merge --merge`      → block (user 明示承認必須維持)
#   Case 6: Normal + `git push origin feat/foo` → 通過 (Normal mode では元々 context inject のみ)
#   Case 7: Normal + `gh pr merge --merge`    → 通過 (Normal mode は block しない、context inject のみ)
#
# 補足:
#   Case 2/3 は本 smoke では autonomous-action-guard 単体の「通過」を assert する。
#   main/stg への実際の push block は delegation-guard-deny-layers-smoke.sh が担保済み。
#   Case 6/7 は mode 依存挙動の網羅性のため追加 (draft 5 cases → 7 cases)。
#
# 実行:
#   bash .claude/tests/autonomous-action-guard-relaxation-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   set -e は使わない (CB-verify 教訓 feedback_set_e_in_sourced_libs)

set -uo pipefail

# repo root に移動
cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1

REPO_ROOT="$(pwd)"
GUARD_HOOK="${REPO_ROOT}/.claude/hooks/autonomous-action-guard.sh"

# tmp harness root (per-run)
TMP_ROOT="$(mktemp -d "/tmp/autonomous-action-guard-relaxation-smoke.XXXXXX")"

# .claude/mode.yml backup (always restore on exit)
MODE_FILE="${REPO_ROOT}/.claude/mode.yml"
MODE_BACKUP="${TMP_ROOT}/mode.yml.bak"
if [ -f "$MODE_FILE" ]; then
  cp "$MODE_FILE" "$MODE_BACKUP"
fi

# global cleanup
# shellcheck disable=SC2329  # called via trap EXIT
_cleanup() {
  # restore mode.yml
  if [ -f "$MODE_BACKUP" ]; then
    cp "$MODE_BACKUP" "$MODE_FILE"
  fi
  rm -rf "$TMP_ROOT"
}
trap _cleanup EXIT

# tmp harness の .claude/ 構築 (real hooks / lib / harness-config.yml を symlink)
mkdir -p "${TMP_ROOT}/.claude"
ln -s "${REPO_ROOT}/.claude/hooks" "${TMP_ROOT}/.claude/hooks"
if [ -f "${REPO_ROOT}/.claude/harness-config.yml" ]; then
  ln -s "${REPO_ROOT}/.claude/harness-config.yml" "${TMP_ROOT}/.claude/harness-config.yml"
fi
mkdir -p "${TMP_ROOT}/.claude/.workflow-state"

PASS=0
FAIL=0
FAIL_CASES=""
RESULTS=""

# helpers ----------------------------------------------------------------------

# .claude/mode.yml を一時的に書き換え (loop / normal)
_set_mode() {
  local m="$1"
  cat > "$MODE_FILE" <<EOF
mode: ${m}
asana_enabled: false
EOF
}

# tmp の .workflow-state を空に reset
_reset_state_dir() {
  rm -rf "${TMP_ROOT}/.claude/.workflow-state"
  mkdir -p "${TMP_ROOT}/.claude/.workflow-state"
}

# run guard hook with stdin JSON (PreToolUse Bash format)
# sets LAST_OUT / LAST_ERR / LAST_CODE
# usage: _run_guard <stdin_json> [ENV=VAL]...
_run_guard() {
  local stdin_json="$1"
  shift
  local out_file err_file
  out_file="$(mktemp "${TMP_ROOT}/out.XXXXXX")"
  err_file="$(mktemp "${TMP_ROOT}/err.XXXXXX")"

  env -i \
    PATH="$PATH" \
    HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$TMP_ROOT" \
    "$@" \
    bash "$GUARD_HOOK" \
    <<< "$stdin_json" \
    > "$out_file" \
    2> "$err_file"
  LAST_CODE=$?
  LAST_OUT=$(cat "$out_file")
  cat "$err_file" >/dev/null  # stderr captured but not asserted in this smoke
  rm -f "$out_file" "$err_file"
}

_record() {
  local label="$1" status="$2" expected="$3" actual="$4"
  RESULTS="${RESULTS}${status}|${label}|${expected}|${actual}"$'\n'
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_CASES="${FAIL_CASES} ${label}"
  fi
}

# tests ------------------------------------------------------------------------

# Case 1: Loop + `git push origin feat/foo` → 通過 (autonomous-action-guard 緩和効果)
#
# 緩和前: DEFAULT_PATTERNS に `^git[[:space:]]+push([[:space:]]|$)` が存在し block。
# 緩和後: git push 一般 pattern を削除 → feature branch push は通過。
# 検証: exit=0 かつ stdout が {} (block JSON でない、context inject もなし = silent pass)
case1() {
  _reset_state_dir
  _set_mode "loop"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"git push origin feat/foo"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, stdout='{}' (feature branch push passes after relaxation)"
  local actual="exit=${LAST_CODE} stdout='${LAST_OUT}'"

  if [ "$LAST_CODE" = "0" ] \
     && [ "$LAST_OUT" = "{}" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 1: Loop+git push feat branch → pass (relaxation)" "PASS" "$expected" "$actual"
  else
    _record "Case 1: Loop+git push feat branch → pass (relaxation)" "FAIL" "$expected" "$actual"
  fi
}

# Case 2: Loop + `git push origin main` → 通過 (autonomous-action-guard 単体検証)
#
# 本 smoke は autonomous-action-guard 単体の挙動を test する。
# 緩和後: git push 一般 pattern 削除により、autonomous-action-guard は main push を block しない。
# 別 layer (delegation-guard.sh の protected-branch-push-deny) が main push を block するが、
# 本 smoke ではその layer を bypass env で除外し、autonomous-action-guard のみ検証する。
# 検証: exit=0 かつ stdout が {} (autonomous-action-guard は block しない)
case2() {
  _reset_state_dir
  _set_mode "loop"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, stdout='{}' (autonomous-action-guard does not block main push after relaxation; delegation-guard handles separately)"
  local actual="exit=${LAST_CODE} stdout='${LAST_OUT}'"

  if [ "$LAST_CODE" = "0" ] \
     && [ "$LAST_OUT" = "{}" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 2: Loop+git push main → autonomous-action-guard pass (relaxation)" "PASS" "$expected" "$actual"
  else
    _record "Case 2: Loop+git push main → autonomous-action-guard pass (relaxation)" "FAIL" "$expected" "$actual"
  fi
}

# Case 3: Loop + `git push origin stg-v1` → 通過 (autonomous-action-guard 単体検証)
#
# Case 2 と同じ設計意図。stg 系 branch も autonomous-action-guard では通過。
# 実際の block は delegation-guard.sh の protected-branch-push-deny が担当。
case3() {
  _reset_state_dir
  _set_mode "loop"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"git push origin stg-v1"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, stdout='{}' (autonomous-action-guard does not block stg push after relaxation)"
  local actual="exit=${LAST_CODE} stdout='${LAST_OUT}'"

  if [ "$LAST_CODE" = "0" ] \
     && [ "$LAST_OUT" = "{}" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 3: Loop+git push stg branch → autonomous-action-guard pass (relaxation)" "PASS" "$expected" "$actual"
  else
    _record "Case 3: Loop+git push stg branch → autonomous-action-guard pass (relaxation)" "FAIL" "$expected" "$actual"
  fi
}

# Case 4: Loop + `gh pr create --base main --head feat/foo` → 通過 (緩和効果)
#
# 緩和前: DEFAULT_PATTERNS に `^gh[[:space:]]+pr[[:space:]]+(create|merge)([[:space:]]|$)` で block。
# 緩和後: create を pattern から削除 → PR 作成は通過。
# 検証: exit=0 かつ stdout が {} (block でない)
case4() {
  _reset_state_dir
  _set_mode "loop"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"gh pr create --base main --head feat/foo"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, stdout='{}' (gh pr create passes after relaxation)"
  local actual="exit=${LAST_CODE} stdout='${LAST_OUT}'"

  if [ "$LAST_CODE" = "0" ] \
     && [ "$LAST_OUT" = "{}" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 4: Loop+gh pr create → pass (relaxation)" "PASS" "$expected" "$actual"
  else
    _record "Case 4: Loop+gh pr create → pass (relaxation)" "FAIL" "$expected" "$actual"
  fi
}

# Case 5: Loop + `gh pr merge --merge` → block (user 明示承認必須維持)
#
# 緩和後も `gh pr merge` は引き続き block する。
# draft §4.1 After: `^gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)` を維持。
# 検証: exit=0 かつ stdout に "decision":"block" を含む
case5() {
  _reset_state_dir
  _set_mode "loop"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"gh pr merge --merge"}}'

  _run_guard "$stdin_json"

  local expected='exit=0, stdout~"decision":"block" (gh pr merge still blocked after relaxation)'
  local actual
  actual="exit=${LAST_CODE} stdout_head='$(printf '%s' "$LAST_OUT" | head -c 80)'"

  if [ "$LAST_CODE" = "0" ] \
     && printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 5: Loop+gh pr merge → block (still restricted)" "PASS" "$expected" "$actual"
  else
    _record "Case 5: Loop+gh pr merge → block (still restricted)" "FAIL" "$expected" "$actual"
  fi
}

# Case 6: Normal + `git push origin feat/foo` → 通過 (Normal mode は block しない)
#
# Normal mode では autonomous-action-guard は block せず context inject のみを返す。
# 緩和後は git push pattern が削除されるため、Normal mode では完全 silent pass ({})。
# 検証: exit=0 かつ stdout が {} (緩和後 pattern 不在で context inject も発火しない)
case6() {
  _reset_state_dir
  _set_mode "normal"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"git push origin feat/foo"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, stdout='{}' (Normal mode, git push pattern removed, silent pass)"
  local actual="exit=${LAST_CODE} stdout='${LAST_OUT}'"

  if [ "$LAST_CODE" = "0" ] \
     && [ "$LAST_OUT" = "{}" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 6: Normal+git push feat branch → silent pass" "PASS" "$expected" "$actual"
  else
    _record "Case 6: Normal+git push feat branch → silent pass" "FAIL" "$expected" "$actual"
  fi
}

# Case 7: Normal + `gh pr merge --merge` → 通過 (Normal mode は block しない、context inject のみ)
#
# Normal mode では gh pr merge も block せず、hookSpecificOutput (context inject) のみ返す。
# (遵守事項 8 の対象として warn するが実行は止めない)
# 検証: exit=0 かつ stdout に "decision":"block" を含まない
case7() {
  _reset_state_dir
  _set_mode "normal"
  local stdin_json
  stdin_json='{"tool_name":"Bash","tool_input":{"command":"gh pr merge --merge"}}'

  _run_guard "$stdin_json"

  local expected="exit=0, no block (Normal mode, gh pr merge gets context inject not block)"
  local actual
  actual="exit=${LAST_CODE} stdout_head='$(printf '%s' "$LAST_OUT" | head -c 80)'"

  if [ "$LAST_CODE" = "0" ] \
     && ! printf '%s' "$LAST_OUT" | grep -q '"decision":[[:space:]]*"block"'; then
    _record "Case 7: Normal+gh pr merge → no block (context inject only)" "PASS" "$expected" "$actual"
  else
    _record "Case 7: Normal+gh pr merge → no block (context inject only)" "FAIL" "$expected" "$actual"
  fi
}

# === run all ===
case1
case2
case3
case4
case5
case6
case7

# === report ===
printf '\n=== autonomous-action-guard-relaxation smoke results ===\n'
printf 'Status | Case | Expected | Actual\n'
printf -- '-------+------+----------+-------\n'
printf '%s' "$RESULTS"
printf '\n=== summary: %d passed, %d failed ===\n' "$PASS" "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  printf 'FAIL cases:%s\n' "$FAIL_CASES" >&2
  exit 1
fi
exit 0
