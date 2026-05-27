#!/usr/bin/env bash
# .claude/tests/hc-config-script-smoke.sh — task-46 Step 1 → iter 2
#
# 目的:
#   .claude/scripts/hc-config.sh の動作を 13+ ケースで検証する (iter 2 拡張)。
#
#   Original (RED → GREEN):
#   - Case 1: --list で全 key 一覧表示 (34+ key 確認)
#   - Case 2: --get <key> で値取得 (default + env override)
#   - Case 3: --set で yml 編集 + backup 作成 + 同一秒衝突回避 (iter 2)
#   - Case 4: 値型 validation (bool/int/float)
#   - Case 5: 型 validation による write-prevention (iter 2 コメント訂正)
#   - Case 6: --reset <key> で default 復元
#   - Case 7: 対話 menu (stdin redirect 経由)
#
#   iter 2 新規 (CRIT F-02 + HIGH 多数 + MED):
#   - Case 8: 真の rollback (path key に yaml syntax invalid 値 → _atomic_write reject)
#   - Case 9: --feature <name>=<bool>
#   - Case 10: --validate
#   - Case 11: --diff
#   - Case 12: --reset-all (key 数分の backup 作成)
#   - Case 13: path traversal --config /etc/passwd → reject
#   - Case 14: env override 優先順位 (env > yml > defaults)
#   - Case 15: awk -v escape corruption 修正検証 (`foo\bar` をそのまま保持)
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)
#   - 一時 yml は /tmp/ に作成、EXIT trap で cleanup

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"

# tmp dir (cleanup on exit)
TMP_DIR="$(mktemp -d "/tmp/hc-config-script-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=""

# --- helpers ---

_record() {
  local result="$1"
  local case_id="$2"
  local desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# RED guard: hc-config.sh が未実装なら EXPECTED FAIL を出力して return 1
_red_guard() {
  local case_id="$1"
  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case %s] EXPECTED FAIL: hc-config.sh not implemented yet (RED phase)\n' "$case_id" >&2
    return 1
  fi
  return 0
}

# md5sum portable (Linux md5sum + macOS md5)
_md5_of() {
  local f="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$f" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$f"
  else
    # last resort: shasum
    shasum "$f" | awk '{print $1}'
  fi
}

# timeout fallback (MED M-03 fix: process group kill)
if ! command -v timeout >/dev/null 2>&1; then
  timeout() {
    local sec="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$sec" 2>/dev/null; kill -9 $pid 2>/dev/null ) &
    local guard_pid=$!
    wait $pid 2>/dev/null
    local ec=$?
    # process group kill で orphan 回避 (best-effort)
    kill -9 $guard_pid 2>/dev/null || true
    kill -- -$guard_pid 2>/dev/null || true
    return $ec
  }
fi

# ============================================================
# Case 1: --list で全 key 一覧表示 (34+ key 確認)
# ============================================================
_case_1() (
  set -uo pipefail
  _red_guard "1" || return 1

  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null)"
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 1: --list returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  local keywords=(
    "feature_loop_mode_enforcement_enabled"
    "feature_draft_flow_guard_enabled"
    "feature_task_rule_guard_enabled"
    "confidence_threshold"
    "review_required_test"
    "review_min_count_test"
    "review_iteration_max"
    "context_budget_threshold"
    "parallel_subagent_reminder_enabled"
    "task_dir"
  )

  local missing=0
  for kw in "${keywords[@]}"; do
    if ! printf '%s' "$output" | grep -q "$kw"; then
      printf 'Case 1: missing key in --list output: %s\n' "$kw" >&2
      missing=$((missing + 1))
    fi
  done

  local line_count
  line_count="$(printf '%s\n' "$output" | grep -c '.' 2>/dev/null || echo 0)"
  if [ "$line_count" -lt 34 ]; then
    printf 'Case 1: --list output has only %d lines, expected 34+\n' "$line_count" >&2
    missing=$((missing + 1))
  fi

  [ $missing -eq 0 ]
)

# ============================================================
# Case 2: --get <key> で値取得 (default + env override)
# ============================================================
_case_2() (
  set -uo pipefail
  _red_guard "2" || return 1

  # 2a: default 値取得
  local default_val
  default_val="$(bash "${HC_CONFIG_SCRIPT}" --get feature_loop_mode_enforcement_enabled 2>/dev/null)"
  if [ "$default_val" != "true" ]; then
    printf 'Case 2a: expected "true", got "%s"\n' "$default_val" >&2
    return 1
  fi

  # 2b: env override
  local override_val
  override_val="$(HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false bash "${HC_CONFIG_SCRIPT}" --get feature_loop_mode_enforcement_enabled 2>/dev/null)"
  if [ "$override_val" != "false" ]; then
    printf 'Case 2b: env override expected "false", got "%s"\n' "$override_val" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 3: --set + backup + 同一秒衝突回避 (HIGH H-01 test-auto)
# ============================================================
_case_3() (
  set -uo pipefail
  _red_guard "3" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case3.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=3 \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 3: --set returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  local bak_count
  bak_count="$(ls "${TMP_DIR}"/test-harness-config-case3.yml.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$bak_count" -lt 1 ]; then
    printf 'Case 3: no backup file (.bak.<timestamp>) found\n' >&2
    return 1
  fi

  if ! grep -q 'review_iteration_max:.*3' "${tmp_yml}" 2>/dev/null; then
    printf 'Case 3: review_iteration_max not updated to 3 in yml\n' >&2
    return 1
  fi

  # 3b: 同一秒内 3 回連続 --set → bak 3+1=4 件 (or 4 件以上、衝突回避済)
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=4 --config "${tmp_yml}" 2>/dev/null
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=5 --config "${tmp_yml}" 2>/dev/null
  local bak_count_after
  bak_count_after="$(ls "${TMP_DIR}"/test-harness-config-case3.yml.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$bak_count_after" -lt 3 ]; then
    printf 'Case 3b: rapid --set should create 3+ backups (no collision), got %d\n' "$bak_count_after" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 4: 値型 validation (bool/int/float)
# ============================================================
_case_4() (
  set -uo pipefail
  _red_guard "4" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case4.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  if bash "${HC_CONFIG_SCRIPT}" --set feature_loop_mode_enforcement_enabled=notabool \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4a: expected error for invalid bool value, got exit 0\n' >&2
    return 1
  fi

  if bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=abc \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4b: expected error for invalid int value, got exit 0\n' >&2
    return 1
  fi

  if bash "${HC_CONFIG_SCRIPT}" --set confidence_threshold=2.5 \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4c: expected error for out-of-range float value, got exit 0\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 5: 型 validation による write-prevention (yml unchanged 確認)
# iter 2 訂正: これは _validate_value による pre-write block であり、
# _atomic_write の rollback path は Case 8 で別途検証する。
# ============================================================
_case_5() (
  set -uo pipefail
  _red_guard "5" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case5.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  local original_checksum
  original_checksum="$(_md5_of "${tmp_yml}")"

  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=abc \
    --config "${tmp_yml}" 2>/dev/null

  local after_checksum
  after_checksum="$(_md5_of "${tmp_yml}")"

  if [ "$original_checksum" != "$after_checksum" ]; then
    printf 'Case 5: yml was modified despite invalid value (validate write-prevention)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 6: --reset <key> で default 復元
# ============================================================
_case_6() (
  set -uo pipefail
  _red_guard "6" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case6.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # まず review_iteration_max を 9 (1-10 range 内) に変更
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=9 \
    --config "${tmp_yml}" 2>/dev/null

  local changed_val
  changed_val="$(bash "${HC_CONFIG_SCRIPT}" --get review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null)"
  if [ "$changed_val" != "9" ]; then
    printf 'Case 6: pre-reset value expected "9", got "%s"\n' "$changed_val" >&2
    return 1
  fi

  bash "${HC_CONFIG_SCRIPT}" --reset review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 6: --reset returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  local reset_val
  reset_val="$(bash "${HC_CONFIG_SCRIPT}" --get review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null)"
  if [ "$reset_val" != "5" ]; then
    printf 'Case 6: expected default "5" after reset, got "%s"\n' "$reset_val" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 7: 対話 menu (stdin redirect 経由)
# ============================================================
_case_7() (
  set -uo pipefail
  _red_guard "7" || return 1

  local exit_code=1

  if printf 'q\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
    exit_code=0
  fi

  if [ $exit_code -ne 0 ]; then
    if printf '5\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
      exit_code=0
    fi
  fi

  if [ $exit_code -ne 0 ]; then
    if printf '0\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
      exit_code=0
    fi
  fi

  return $exit_code
)

# ============================================================
# Case 8 (iter 2 新規 CRIT F-02): 真の rollback path
# path/string 型 key (task_dir) に yaml syntax invalid な値を渡し、
# _validate_string_sanity または _atomic_write の yaml.safe_load reject で
# yml が unchanged であることを確認
# ============================================================
_case_8() (
  set -uo pipefail
  _red_guard "8" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case8.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  local original_checksum
  original_checksum="$(_md5_of "${tmp_yml}")"

  # 8a: task_dir に ": unexpected" (yaml syntax confusion) を渡す → reject
  bash "${HC_CONFIG_SCRIPT}" --set 'task_dir=: unexpected' \
    --config "${tmp_yml}" 2>/dev/null
  local after_checksum
  after_checksum="$(_md5_of "${tmp_yml}")"
  if [ "$original_checksum" != "$after_checksum" ]; then
    printf 'Case 8a: yml modified after ": unexpected" value (rollback failed)\n' >&2
    return 1
  fi

  # 8b: task_dir に "# comment" を渡す → reject (yaml comment confusion)
  bash "${HC_CONFIG_SCRIPT}" --set 'task_dir=# comment' \
    --config "${tmp_yml}" 2>/dev/null
  local after_checksum2
  after_checksum2="$(_md5_of "${tmp_yml}")"
  if [ "$original_checksum" != "$after_checksum2" ]; then
    printf 'Case 8b: yml modified after "# comment" value (rollback failed)\n' >&2
    return 1
  fi

  # 8c: yml が yaml としてまだ parse 可能であること
  if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
    if ! python3 -c "import yaml, sys; yaml.safe_load(sys.stdin.read())" < "${tmp_yml}" 2>/dev/null; then
      printf 'Case 8c: yml is no longer parseable after rejection attempts\n' >&2
      return 1
    fi
  fi

  return 0
)

# ============================================================
# Case 9 (iter 2 新規): --feature <name>=<bool>
# ============================================================
_case_9() (
  set -uo pipefail
  _red_guard "9" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case9.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  bash "${HC_CONFIG_SCRIPT}" --feature loop_mode_enforcement=false \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?
  if [ $exit_code -ne 0 ]; then
    printf 'Case 9: --feature returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  local val
  val="$(bash "${HC_CONFIG_SCRIPT}" --get feature_loop_mode_enforcement_enabled \
    --config "${tmp_yml}" 2>/dev/null)"
  if [ "$val" != "false" ]; then
    printf 'Case 9: expected "false" after --feature, got "%s"\n' "$val" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 10 (iter 2 新規): --validate
# ============================================================
_case_10() (
  set -uo pipefail
  _red_guard "10" || return 1

  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --validate 2>/dev/null)"
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 10: --validate returned exit code %d (expected 0 for valid default yml)\n' "$exit_code" >&2
    return 1
  fi

  if ! printf '%s' "$output" | grep -qiE 'OK|valid'; then
    printf 'Case 10: --validate output missing OK/valid keyword: %s\n' "$output" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 11 (iter 2 新規): --diff
# ============================================================
_case_11() (
  set -uo pipefail
  _red_guard "11" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case11.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # まず review_iteration_max を 3 に変更
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=3 \
    --config "${tmp_yml}" 2>/dev/null

  # --diff で review_iteration_max が表示されることを確認
  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --diff --config "${tmp_yml}" 2>/dev/null)"

  if ! printf '%s' "$output" | grep -q 'review_iteration_max'; then
    printf 'Case 11: --diff output missing review_iteration_max (after --set)\n' >&2
    printf 'output:\n%s\n' "$output" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 12 (iter 2 新規): --reset-all
# ============================================================
_case_12() (
  set -uo pipefail
  _red_guard "12" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case12.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # 3 つの key を非 default 値に変更
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=3 --config "${tmp_yml}" 2>/dev/null
  bash "${HC_CONFIG_SCRIPT}" --set confidence_threshold=0.9 --config "${tmp_yml}" 2>/dev/null
  bash "${HC_CONFIG_SCRIPT}" --set task_dir=docs/foo --config "${tmp_yml}" 2>/dev/null

  # --reset-all
  bash "${HC_CONFIG_SCRIPT}" --reset-all --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 12: --reset-all returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # review_iteration_max が 5 (default) に戻っているか
  local val
  val="$(bash "${HC_CONFIG_SCRIPT}" --get review_iteration_max --config "${tmp_yml}" 2>/dev/null)"
  if [ "$val" != "5" ]; then
    printf 'Case 12: review_iteration_max should be 5 after --reset-all, got "%s"\n' "$val" >&2
    return 1
  fi

  # task_dir が docs/tasks に戻っているか
  local td
  td="$(bash "${HC_CONFIG_SCRIPT}" --get task_dir --config "${tmp_yml}" 2>/dev/null)"
  if [ "$td" != "docs/tasks" ]; then
    printf 'Case 12: task_dir should be docs/tasks after --reset-all, got "%s"\n' "$td" >&2
    return 1
  fi

  # backup が複数件作成されていること (set 3 + reset N、最低 4+)
  local bak_count
  bak_count="$(ls "${TMP_DIR}"/test-harness-config-case12.yml.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$bak_count" -lt 4 ]; then
    printf 'Case 12: expected 4+ backups, got %d\n' "$bak_count" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 13 (iter 2 新規 HIGH F-04): path traversal --config /etc/passwd → reject
# ============================================================
_case_13() (
  set -uo pipefail
  _red_guard "13" || return 1

  # HC_ALLOW_EXTERNAL_CONFIG が unset の状態で /etc/hosts (REPO_ROOT 外、/tmp/ 外) を渡す
  # /etc/passwd は file が壊れたら困るので /etc/hosts で代替 (read-only path 確認のみ)
  unset HC_ALLOW_EXTERNAL_CONFIG
  if bash "${HC_CONFIG_SCRIPT}" --list --config /etc/hosts 2>/dev/null; then
    printf 'Case 13: expected reject for /etc/hosts (outside REPO_ROOT / /tmp/), got exit 0\n' >&2
    return 1
  fi

  # HC_ALLOW_EXTERNAL_CONFIG=1 で bypass 可能なこと
  # (実際に /etc/hosts を yml として parse すると失敗するので、stderr のみ確認)
  local out
  out=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "${HC_CONFIG_SCRIPT}" --list --config /etc/hosts 2>&1 || true)
  # bypass された場合は path validation で reject されない (cmd_list の出力 or yml parse 結果)
  if printf '%s' "$out" | grep -q 'config path outside'; then
    printf 'Case 13b: HC_ALLOW_EXTERNAL_CONFIG=1 did not bypass path guard\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 14 (iter 2 新規 MED M-04): env priority (env > yml > defaults)
# yml=3, env=7 → env が勝つ
# ============================================================
_case_14() (
  set -uo pipefail
  _red_guard "14" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case14.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=3 --config "${tmp_yml}" 2>/dev/null

  local val
  val="$(HC_REVIEW_ITERATION_MAX=7 bash "${HC_CONFIG_SCRIPT}" --get review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null)"
  if [ "$val" != "7" ]; then
    printf 'Case 14: env override expected "7" (yml=3, env=7), got "%s"\n' "$val" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 15 (iter 2 新規 HIGH H-01 code-rev): awk -v escape corruption 修正検証
# `foo\bar` をそのまま保持 (旧 logic は `foo` に corrupt)
# ============================================================
_case_15() (
  set -uo pipefail
  _red_guard "15" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case15.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # docs_approved_dir に "foo\bar" (literal backslash + 'b') を渡す
  # 旧 awk -v VAL="$val" では \b が解釈され "fooar" に corrupt するバグ
  bash "${HC_CONFIG_SCRIPT}" --set 'docs_approved_dir=foo\bar' \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 15: --set with backslash returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # yml 中の値が "foo\bar" のままか確認 (awk -v escape 解釈バグなら "fooar" になる)
  local stored
  stored=$(grep '^docs_approved_dir:' "${tmp_yml}" | head -1)
  if printf '%s' "$stored" | grep -q 'fooar'; then
    printf 'Case 15: awk -v escape corruption detected: %s\n' "$stored" >&2
    return 1
  fi
  if ! printf '%s' "$stored" | grep -qF 'foo\bar'; then
    printf 'Case 15: backslash value not preserved: %s\n' "$stored" >&2
    return 1
  fi

  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== hc-config-script-smoke (iter 2: 15 cases) ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "--list で全 key 一覧表示 (34+ key 確認)"
else                         _record FAIL 1 "--list で全 key 一覧表示 (34+ key 確認)"
fi

if _case_2 2>/dev/null; then _record PASS 2 "--get で値取得 (default + env override)"
else                         _record FAIL 2 "--get で値取得 (default + env override)"
fi

if _case_3 2>/dev/null; then _record PASS 3 "--set で yml 編集 + backup 作成 + 同一秒衝突回避"
else                         _record FAIL 3 "--set で yml 編集 + backup 作成 + 同一秒衝突回避"
fi

if _case_4 2>/dev/null; then _record PASS 4 "値型 validation (bool/int/float の不正値で exit != 0)"
else                         _record FAIL 4 "値型 validation (bool/int/float の不正値で exit != 0)"
fi

if _case_5 2>/dev/null; then _record PASS 5 "型 validation による write-prevention (yml unchanged)"
else                         _record FAIL 5 "型 validation による write-prevention (yml unchanged)"
fi

if _case_6 2>/dev/null; then _record PASS 6 "--reset <key> で default 復元 (review_iteration_max → 5)"
else                         _record FAIL 6 "--reset <key> で default 復元 (review_iteration_max → 5)"
fi

if _case_7 2>/dev/null; then _record PASS 7 "対話 menu (stdin redirect で即終了、exit 0)"
else                         _record FAIL 7 "対話 menu (stdin redirect で即終了、exit 0)"
fi

if _case_8 2>/dev/null; then _record PASS 8 "真の rollback path (string sanity check + yaml.safe_load reject)"
else                         _record FAIL 8 "真の rollback path (string sanity check + yaml.safe_load reject)"
fi

if _case_9 2>/dev/null; then _record PASS 9 "--feature <name>=<bool> shorthand"
else                         _record FAIL 9 "--feature <name>=<bool> shorthand"
fi

if _case_10 2>/dev/null; then _record PASS 10 "--validate (正常 yml は exit 0 + OK 出力)"
else                          _record FAIL 10 "--validate (正常 yml は exit 0 + OK 出力)"
fi

if _case_11 2>/dev/null; then _record PASS 11 "--diff (--set 後の差分表示)"
else                          _record FAIL 11 "--diff (--set 後の差分表示)"
fi

if _case_12 2>/dev/null; then _record PASS 12 "--reset-all (全 key default 化 + N backup)"
else                          _record FAIL 12 "--reset-all (全 key default 化 + N backup)"
fi

if _case_13 2>/dev/null; then _record PASS 13 "path traversal --config /etc/* reject + bypass env"
else                          _record FAIL 13 "path traversal --config /etc/* reject + bypass env"
fi

if _case_14 2>/dev/null; then _record PASS 14 "env priority (yml=3 + env=7 → 7)"
else                          _record FAIL 14 "env priority (yml=3 + env=7 → 7)"
fi

if _case_15 2>/dev/null; then _record PASS 15 "awk -v escape corruption 修正 (foo\\\\bar 保持)"
else                          _record FAIL 15 "awk -v escape corruption 修正 (foo\\\\bar 保持)"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '\nHINT: hc-config.sh not found: %s\n' "${HC_CONFIG_SCRIPT}"
    printf '      RED phase: task-46 Step 2 で hc-config.sh 実装後に GREEN になります。\n'
  fi
  exit 1
fi

exit 0
