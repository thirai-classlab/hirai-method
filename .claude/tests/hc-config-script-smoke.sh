#!/usr/bin/env bash
# .claude/tests/hc-config-script-smoke.sh — task-46 Step 1 (TDD RED)
#
# 目的:
#   .claude/scripts/hc-config.sh の動作を 7 ケースで検証する。
#   本 smoke は TDD RED フェーズ用: impl 未実装 (hc-config.sh 不在) のため
#   各 case は "EXPECTED FAIL (RED phase)" を出力して FAIL する。
#
#   - Case 1: --list で全 key 一覧表示 (34+ key 確認、grep で keyword 存在 check)
#   - Case 2: --get <key> で値取得 (default 値 + env override 両方をテスト)
#   - Case 3: --set <key>=<value> で yml 編集 + backup 作成 (.bak.<timestamp> 存在確認)
#   - Case 4: 値型 validation (bool/int/float/array、不正値で exit code != 0)
#   - Case 5: 構文 invalid な値で error + rollback (yml unchanged 確認)
#   - Case 6: --reset <key> で default 復元
#   - Case 7: 対話 menu (stdin redirect 経由、最小 case = menu 起動 + 即終了)
#
# 設計:
#   - 各 case 冒頭で hc-config.sh 不在を検出し "[Case N] EXPECTED FAIL (RED phase)" 出力
#   - これにより「impl が無くて FAIL」と「smoke 自体のロジック誤りで FAIL」を区別できる
#   - TDD GREEN (Step 2) で hc-config.sh 実装後、各 case の RED guard が外れて実テストが走る
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0 / 1 件 FAIL で exit 1
#
# 依存前提:
#   .claude/scripts/hc-config.sh が存在することが GREEN の前提。
#   impl 未実装の場合は全 case が FAIL し、RED phase である旨を最終行に表示する。
#
# 実行:
#   bash .claude/tests/hc-config-script-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
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
# $1 = case_id (例: "1")
_red_guard() {
  local case_id="$1"
  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case %s] EXPECTED FAIL: hc-config.sh not implemented yet (RED phase)\n' "$case_id" >&2
    return 1
  fi
  return 0
}

# ============================================================
# Case 1: --list で全 key 一覧表示 (34+ key 確認)
# hc-config.sh --list の stdout に harness-config.yml の主要 key が含まれるか確認
# ============================================================
_case_1() (
  set -uo pipefail
  _red_guard "1" || return 1

  # --list の出力に代表的な key が含まれるか確認
  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null)"
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 1: --list returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # 34+ key のうち代表 10 件を確認
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

  # 行数が 34 以上あるか確認 (34+ key)
  local line_count
  line_count="$(printf '%s\n' "$output" | grep -c '.' 2>/dev/null || echo 0)"
  if [ "$line_count" -lt 34 ]; then
    printf 'Case 1: --list output has only %d lines, expected 34+\n' "$line_count" >&2
    missing=$((missing + 1))
  fi

  [ $missing -eq 0 ]
)

# ============================================================
# Case 2: --get <key> で値取得 (default 値 + env override 両方)
# feature_loop_mode_enforcement_enabled の default true を取得 +
# HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false env override も確認
# ============================================================
_case_2() (
  set -uo pipefail
  _red_guard "2" || return 1

  # 2a: default 値取得 (yml から)
  local default_val
  default_val="$(bash "${HC_CONFIG_SCRIPT}" --get feature_loop_mode_enforcement_enabled 2>/dev/null)"
  if [ "$default_val" != "true" ]; then
    printf 'Case 2a: expected "true", got "%s"\n' "$default_val" >&2
    return 1
  fi

  # 2b: env override (HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false)
  local override_val
  override_val="$(HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED=false bash "${HC_CONFIG_SCRIPT}" --get feature_loop_mode_enforcement_enabled 2>/dev/null)"
  if [ "$override_val" != "false" ]; then
    printf 'Case 2b: env override expected "false", got "%s"\n' "$override_val" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 3: --set <key>=<value> で yml 編集 + backup 作成
# 一時 yml copy に --set を実行し、.bak.<timestamp> が作成されること +
# yml 中の値が変更されていることを確認
# ============================================================
_case_3() (
  set -uo pipefail
  _red_guard "3" || return 1

  # 一時 yml を作成 (元 yml の copy)
  local tmp_yml="${TMP_DIR}/test-harness-config-case3.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # --set で review_iteration_max を 3 に変更
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=3 \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 3: --set returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # backup file (.bak.<timestamp>) が存在するか確認
  local bak_count
  bak_count="$(ls "${TMP_DIR}"/test-harness-config-case3.yml.bak.* 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$bak_count" -lt 1 ]; then
    printf 'Case 3: no backup file (.bak.<timestamp>) found\n' >&2
    return 1
  fi

  # yml 中の review_iteration_max が 3 に変更されているか確認
  if ! grep -q 'review_iteration_max:.*3' "${tmp_yml}" 2>/dev/null; then
    printf 'Case 3: review_iteration_max not updated to 3 in yml\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 4: 値型 validation (bool/int/float/array、不正値で exit code != 0)
# bool key に非 bool 値 / int key に非整数 / float key に範囲外値を渡して
# exit code != 0 が返ることを確認
# ============================================================
_case_4() (
  set -uo pipefail
  _red_guard "4" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case4.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # 4a: bool key (feature_loop_mode_enforcement_enabled) に "notabool" を渡す → error
  if bash "${HC_CONFIG_SCRIPT}" --set feature_loop_mode_enforcement_enabled=notabool \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4a: expected error for invalid bool value, got exit 0\n' >&2
    return 1
  fi

  # 4b: int key (review_iteration_max) に "abc" を渡す → error
  if bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=abc \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4b: expected error for invalid int value, got exit 0\n' >&2
    return 1
  fi

  # 4c: float key (confidence_threshold) に "2.5" を渡す (範囲 0.0-1.0 外) → error
  if bash "${HC_CONFIG_SCRIPT}" --set confidence_threshold=2.5 \
    --config "${tmp_yml}" 2>/dev/null; then
    printf 'Case 4c: expected error for out-of-range float value, got exit 0\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 5: 構文 invalid な値で error + rollback (yml unchanged 確認)
# --set に YAML 的に invalid な値 (例: float key に "abc") を渡した場合、
# yml が変更されないこと (rollback) を確認
# ============================================================
_case_5() (
  set -uo pipefail
  _red_guard "5" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case5.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # 元 yml の checksum を取得
  local original_checksum
  original_checksum="$(md5sum "${tmp_yml}" 2>/dev/null | awk '{print $1}')"
  if [ -z "$original_checksum" ]; then
    # macOS では md5 コマンド
    original_checksum="$(md5 -q "${tmp_yml}" 2>/dev/null)"
  fi

  # 無効な値で --set (int key に "abc") → error を期待
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=abc \
    --config "${tmp_yml}" 2>/dev/null
  # exit code は non-zero 期待だが、ここではロールバック確認が主眼

  # yml の checksum が変化していないこと (rollback) を確認
  local after_checksum
  after_checksum="$(md5sum "${tmp_yml}" 2>/dev/null | awk '{print $1}')"
  if [ -z "$after_checksum" ]; then
    after_checksum="$(md5 -q "${tmp_yml}" 2>/dev/null)"
  fi

  if [ "$original_checksum" != "$after_checksum" ]; then
    printf 'Case 5: yml was modified despite invalid value (no rollback)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 6: --reset <key> で default 復元
# tmp yml で review_iteration_max を変更した後、--reset で元の値に戻ることを確認
# ============================================================
_case_6() (
  set -uo pipefail
  _red_guard "6" || return 1

  local tmp_yml="${TMP_DIR}/test-harness-config-case6.yml"
  cp "${HC_CONFIG_YML}" "${tmp_yml}"

  # まず review_iteration_max を 99 に変更
  bash "${HC_CONFIG_SCRIPT}" --set review_iteration_max=99 \
    --config "${tmp_yml}" 2>/dev/null

  # 変更後の値確認
  local changed_val
  changed_val="$(bash "${HC_CONFIG_SCRIPT}" --get review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null)"
  if [ "$changed_val" != "99" ]; then
    printf 'Case 6: pre-reset value expected "99", got "%s"\n' "$changed_val" >&2
    return 1
  fi

  # --reset で default に戻す
  bash "${HC_CONFIG_SCRIPT}" --reset review_iteration_max \
    --config "${tmp_yml}" 2>/dev/null
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 6: --reset returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # default 値 5 に戻っているか確認
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
# Case 7: 対話 menu (stdin redirect 経由、最小 case = menu 起動 + 即終了)
# stdin に "q\n" (quit/終了 選択) を渡して menu が exit 0 で終了することを確認
# ============================================================
_case_7() (
  set -uo pipefail
  _red_guard "7" || return 1

  # stdin に "q" (または "5" = 終了選択) を渡して menu を即終了させる
  # hc-config.sh の対話 menu では "q" または選択肢の最後 (例: "5") が終了
  # 複数の終了候補を試して、いずれかで exit 0 なら PASS
  #
  # `timeout` が PATH に無い環境 (macOS default) のため、bash 関数で fallback を提供。
  # 5 秒経過で SIGKILL する簡易実装。stdin EOF 後すぐに exit するため、
  # 通常は timeout する前に正常終了する。
  if ! command -v timeout >/dev/null 2>&1; then
    timeout() {
      local sec="$1"; shift
      "$@" &
      local pid=$!
      ( sleep "$sec" 2>/dev/null; kill -9 $pid 2>/dev/null ) &
      local guard_pid=$!
      wait $pid 2>/dev/null
      local ec=$?
      kill -9 $guard_pid 2>/dev/null || true
      return $ec
    }
  fi

  local exit_code=1

  # 試行 1: "q" で終了
  if printf 'q\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
    exit_code=0
  fi

  # 試行 2: "5" で終了 (終了選択肢が 5 番目の場合)
  if [ $exit_code -ne 0 ]; then
    if printf '5\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
      exit_code=0
    fi
  fi

  # 試行 3: "0" で終了 (終了選択肢が 0 番目の場合)
  if [ $exit_code -ne 0 ]; then
    if printf '0\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
      exit_code=0
    fi
  fi

  return $exit_code
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== hc-config-script-smoke ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "--list で全 key 一覧表示 (34+ key 確認)"
else                         _record FAIL 1 "--list で全 key 一覧表示 (34+ key 確認)"
fi

if _case_2 2>/dev/null; then _record PASS 2 "--get で値取得 (default + env override)"
else                         _record FAIL 2 "--get で値取得 (default + env override)"
fi

if _case_3 2>/dev/null; then _record PASS 3 "--set で yml 編集 + backup 作成 (.bak.<timestamp>)"
else                         _record FAIL 3 "--set で yml 編集 + backup 作成 (.bak.<timestamp>)"
fi

if _case_4 2>/dev/null; then _record PASS 4 "値型 validation (bool/int/float の不正値で exit != 0)"
else                         _record FAIL 4 "値型 validation (bool/int/float の不正値で exit != 0)"
fi

if _case_5 2>/dev/null; then _record PASS 5 "構文 invalid 値で error + rollback (yml unchanged)"
else                         _record FAIL 5 "構文 invalid 値で error + rollback (yml unchanged)"
fi

if _case_6 2>/dev/null; then _record PASS 6 "--reset <key> で default 復元 (review_iteration_max → 5)"
else                         _record FAIL 6 "--reset <key> で default 復元 (review_iteration_max → 5)"
fi

if _case_7 2>/dev/null; then _record PASS 7 "対話 menu (stdin redirect で即終了、exit 0)"
else                         _record FAIL 7 "対話 menu (stdin redirect で即終了、exit 0)"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  # hc-config.sh が見つからない場合のヒント
  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '\nHINT: hc-config.sh not found: %s\n' "${HC_CONFIG_SCRIPT}"
    printf '      RED phase: task-46 Step 2 で hc-config.sh 実装後に GREEN になります。\n'
    printf '      各 case の stderr に "[Case N] EXPECTED FAIL (RED phase)" が出力されています。\n'
  fi
  exit 1
fi

exit 0
