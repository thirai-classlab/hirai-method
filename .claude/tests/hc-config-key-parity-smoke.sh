#!/usr/bin/env bash
# .claude/tests/hc-config-key-parity-smoke.sh — task-69 (hc-config key parity) smoke test
#
# 目的:
#   `_yml_list_keys .claude/harness-config.yml` で抽出した YAML top-level key 集合と、
#   `bash hc-config.sh --list` が出力する key 集合が **完全一致** することを検証する。
#   SSoT は YAML top-level key (= harness-config.yml の `^[a-z_][a-zA-Z0-9_]*:`)。
#   metadata (lib/hc-config-metadata.sh) は表示補助であり key 存在判定の SSoT にしない。
#
#   現状 (task-69 着手前): metadata 75 key vs yml 79 key の差異で cmd_list() が
#   未分類 4 key (feature_reviewer_count_guard_enabled / feature_stale_harness_detect_enabled /
#   harness_version / stale_harness_markers) を出力できず fail していた (履歴)。
#   Step 1 (cmd_list 未分類 section) + Step 2 (metadata 4 key 追加) で揃え、
#   Step 8 (task-69 リファクタリング) でさらに slip key 追加により 80 key へ増加。
#   本 smoke の検証ロジック自体は yml key 数を動的計算するため hardcode を持たない。
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0
#   - 不一致時は set 差分 (yml にあって --list に無い / 逆) を生 log 出力
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)
#
# 起源: task-69 Step 1+2、設計 SSoT: docs/draft/harness-review-remediation-plan.md §4.1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"

PASS=0
FAIL=0
FAILED_CASES=""

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

# yml top-level key を抽出 (hc-config.sh の _yml_list_keys と同一 regex)
_yml_keys() {
  grep -E '^[a-z_][a-zA-Z0-9_]*:' "${HC_CONFIG_YML}" 2>/dev/null | sed -E 's/:.*$//'
}

# --list 出力から key を抽出。
#   行頭 `^<key> ` (key + 空白) の data 行を拾う。section header (=== ... ===) /
#   table header (KEY ...) / 空行は除外。
_list_keys() {
  bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null \
    | grep -E '^[a-z_][a-zA-Z0-9_]*[[:space:]]' \
    | awk '{print $1}'
}

# ============================================================
# Case 1: yml key set == --list key set (完全一致)
# ============================================================
_case_1() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 1: hc-config.sh not executable\n' >&2
    return 1
  fi
  if [ ! -f "${HC_CONFIG_YML}" ]; then
    printf 'Case 1: harness-config.yml not found\n' >&2
    return 1
  fi

  local yml_keys list_keys yml_count list_count
  yml_keys="$(_yml_keys | sort)"
  list_keys="$(_list_keys | sort -u)"
  yml_count=$(printf '%s\n' "$yml_keys" | grep -c .)
  list_count=$(printf '%s\n' "$list_keys" | grep -c .)

  printf 'Case 1: yml_count=%d list_count=%d\n' "$yml_count" "$list_count" >&2

  local missing_in_list extra_in_list
  missing_in_list="$(comm -23 <(printf '%s\n' "$yml_keys") <(printf '%s\n' "$list_keys"))"
  extra_in_list="$(comm -13 <(printf '%s\n' "$yml_keys") <(printf '%s\n' "$list_keys"))"

  local ok=0
  if [ -n "$missing_in_list" ]; then
    printf 'Case 1: in yml but NOT in --list output:\n%s\n' "$missing_in_list" >&2
    ok=1
  fi
  if [ -n "$extra_in_list" ]; then
    printf 'Case 1: in --list output but NOT in yml:\n%s\n' "$extra_in_list" >&2
    ok=1
  fi
  if [ "$yml_count" -ne "$list_count" ]; then
    printf 'Case 1: count mismatch yml=%d list=%d\n' "$yml_count" "$list_count" >&2
    ok=1
  fi

  [ "$ok" -eq 0 ]
)

# ============================================================
# Case 2: --list / --verbose / --show-default の全 mode で key set 不変
# ============================================================
# mode によって出力列は変わるが key 集合 (= 全 yml key) は不変であるべき。
_case_2() (
  set -uo pipefail

  local yml_count
  yml_count=$(_yml_keys | grep -c .)

  local mode count
  local ok=0
  for mode in "--list" "--list --verbose" "--list --show-default"; do
    # shellcheck disable=SC2086
    count=$(bash "${HC_CONFIG_SCRIPT}" $mode 2>/dev/null \
      | grep -E '^[a-z_][a-zA-Z0-9_]*[[:space:]]' | awk '{print $1}' | sort -u | grep -c .)
    if [ "$count" -ne "$yml_count" ]; then
      printf 'Case 2: mode "%s" key count=%d != yml=%d\n' "$mode" "$count" "$yml_count" >&2
      ok=1
    fi
  done

  [ "$ok" -eq 0 ]
)

# --- run ---
printf '=== hc-config key parity smoke ===\n'

_case_1 && _record PASS 1 "yml key set == --list key set (完全一致)" \
       || _record FAIL 1 "yml key set == --list key set (完全一致)"
_case_2 && _record PASS 2 "--list / --verbose / --show-default で key set 不変" \
       || _record FAIL 2 "--list / --verbose / --show-default で key set 不変"

printf '\n=== Result: %d PASS, %d FAIL ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
