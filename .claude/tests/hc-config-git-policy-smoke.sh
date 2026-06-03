#!/usr/bin/env bash
# .claude/tests/hc-config-git-policy-smoke.sh — task-77 Step 1
#
# 目的:
#   git 統合ポリシー設定 key 基盤 (mainline_branch + mainline_integration_policy) の
#   hc-config.sh validation / 値解決 / config-loader env export を検証する。
#   設計 SSoT: docs/draft/git-integration-policy.md §3.1 / §3.4 / Step 1。
#
#   cases:
#   - Case 1: --get mainline_branch / mainline_integration_policy が default 値を返す
#   - Case 2: --set mainline_integration_policy=local-merge 成功、=yolo は非 0 reject
#   - Case 3: --set mainline_branch="bad name" (空白) reject、=develop / =release/1.0 成功
#   - Case 4: config-loader 経由で HC_MAINLINE_BRANCH / HC_MAINLINE_INTEGRATION_POLICY が
#             env export される (unknown-key warn が出ない)
#   - Case 5: 値解決順 env > yml > default (hc-config --get で env override が勝つ)
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離 (既存 script-smoke 慣習)
#   - 一時 yml は SSoT yml を /tmp/ に copy して破壊操作を本番 yml に波及させない
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - bash 3.2 (macOS) + Linux bash 5.x 両対応

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"

TMP_DIR="$(mktemp -d "/tmp/hc-config-git-policy-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=""

_record() {
  local result="$1" case_id="$2" desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# RED guard: hc-config.sh が未実装なら EXPECTED FAIL
_red_guard() {
  local case_id="$1"
  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case %s] EXPECTED FAIL: hc-config.sh not implemented yet (RED phase)\n' "$case_id" >&2
    return 1
  fi
  return 0
}

# 破壊操作用に SSoT yml を tmp に copy して返す (stdout に path)
# 注意: mktemp の suffix 付き template (XXX.yml) は macOS で衝突するため、
#       counter で衝突しない一意 path を組み立てて cp する。
_FRESH_YML_COUNTER=0
_fresh_yml() {
  _FRESH_YML_COUNTER=$((_FRESH_YML_COUNTER + 1))
  local f="${TMP_DIR}/cfg.$$.${_FRESH_YML_COUNTER}.yml"
  cp "$HC_CONFIG_YML" "$f"
  printf '%s' "$f"
}

# ============================================================
# Case 1: --get が default 値を返す
# ============================================================
_case_1() (
  set -uo pipefail
  _red_guard "1" || return 1
  local b p
  b="$(bash "${HC_CONFIG_SCRIPT}" --get mainline_branch 2>/dev/null)"
  p="$(bash "${HC_CONFIG_SCRIPT}" --get mainline_integration_policy 2>/dev/null)"
  if [ "$b" != "main" ]; then
    printf 'Case 1: mainline_branch expected "main", got "%s"\n' "$b" >&2
    return 1
  fi
  if [ "$p" != "pr-required" ]; then
    printf 'Case 1: mainline_integration_policy expected "pr-required", got "%s"\n' "$p" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 2: policy enum validation (local-merge OK / yolo reject)
# ============================================================
_case_2() (
  set -uo pipefail
  _red_guard "2" || return 1
  local yml; yml="$(_fresh_yml)"

  # local-merge / local-merge-push / pr-required は成功
  local v
  for v in pr-required local-merge local-merge-push; do
    if ! bash "${HC_CONFIG_SCRIPT}" --config "$yml" --set "mainline_integration_policy=${v}" >/dev/null 2>&1; then
      printf 'Case 2: --set mainline_integration_policy=%s expected success\n' "$v" >&2
      return 1
    fi
    if ! grep -q "^mainline_integration_policy: ${v}\$" "$yml"; then
      printf 'Case 2: yml not updated to %s\n' "$v" >&2
      return 1
    fi
  done

  # yolo は非 0 reject
  if bash "${HC_CONFIG_SCRIPT}" --config "$yml" --set "mainline_integration_policy=yolo" >/dev/null 2>&1; then
    printf 'Case 2: --set mainline_integration_policy=yolo expected reject (non-zero)\n' >&2
    return 1
  fi
  # reject 時 yml は直前の有効値 (local-merge-push) のまま
  if ! grep -q "^mainline_integration_policy: local-merge-push\$" "$yml"; then
    printf 'Case 2: reject altered yml value\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 3: mainline_branch charset validation
# ============================================================
_case_3() (
  set -uo pipefail
  _red_guard "3" || return 1
  local yml; yml="$(_fresh_yml)"

  # 空白含む値は reject
  if bash "${HC_CONFIG_SCRIPT}" --config "$yml" --set "mainline_branch=bad name" >/dev/null 2>&1; then
    printf 'Case 3: --set "mainline_branch=bad name" expected reject (space)\n' >&2
    return 1
  fi
  # reject 時 yml は default のまま
  if ! grep -q "^mainline_branch: main\$" "$yml"; then
    printf 'Case 3: reject altered mainline_branch\n' >&2
    return 1
  fi

  # develop は成功
  if ! bash "${HC_CONFIG_SCRIPT}" --config "$yml" --set "mainline_branch=develop" >/dev/null 2>&1; then
    printf 'Case 3: --set mainline_branch=develop expected success\n' >&2
    return 1
  fi
  if ! grep -q "^mainline_branch: develop\$" "$yml"; then
    printf 'Case 3: yml not updated to develop\n' >&2
    return 1
  fi

  # release/1.0 (slash + dot) は成功
  if ! bash "${HC_CONFIG_SCRIPT}" --config "$yml" --set "mainline_branch=release/1.0" >/dev/null 2>&1; then
    printf 'Case 3: --set mainline_branch=release/1.0 expected success\n' >&2
    return 1
  fi
  if ! grep -q "^mainline_branch: release/1.0\$" "$yml"; then
    printf 'Case 3: yml not updated to release/1.0\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 4: config-loader env export + unknown-key warn 不在
# ============================================================
_case_4() (
  set -uo pipefail
  if [ ! -f "$CONFIG_LOADER" ]; then
    printf 'Case 4: config-loader.sh not found: %s\n' "$CONFIG_LOADER" >&2
    return 1
  fi
  local warnfile="${TMP_DIR}/cl-warn.$$"
  local out
  out="$(
    unset HC_MAINLINE_BRANCH HC_MAINLINE_INTEGRATION_POLICY
    # shellcheck disable=SC1090
    source "$CONFIG_LOADER" 2>"$warnfile"
    printf '%s|%s' "${HC_MAINLINE_BRANCH:-UNSET}" "${HC_MAINLINE_INTEGRATION_POLICY:-UNSET}"
  )"
  if [ "$out" != "main|pr-required" ]; then
    printf 'Case 4: config-loader export expected "main|pr-required", got "%s"\n' "$out" >&2
    return 1
  fi
  # mainline / unknown 系 warn が出ていないこと
  if grep -iE "mainline|unknown_local_key" "$warnfile" >/dev/null 2>&1; then
    printf 'Case 4: unexpected warn for mainline keys:\n' >&2
    grep -iE "mainline|unknown_local_key" "$warnfile" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 5: 値解決順 env > yml > default (hc-config --get で env override が勝つ)
# ============================================================
_case_5() (
  set -uo pipefail
  _red_guard "5" || return 1
  local b p
  b="$(HC_MAINLINE_BRANCH=develop bash "${HC_CONFIG_SCRIPT}" --get mainline_branch 2>/dev/null)"
  p="$(HC_MAINLINE_INTEGRATION_POLICY=local-merge bash "${HC_CONFIG_SCRIPT}" --get mainline_integration_policy 2>/dev/null)"
  if [ "$b" != "develop" ]; then
    printf 'Case 5: env override mainline_branch expected "develop", got "%s"\n' "$b" >&2
    return 1
  fi
  if [ "$p" != "local-merge" ]; then
    printf 'Case 5: env override mainline_integration_policy expected "local-merge", got "%s"\n' "$p" >&2
    return 1
  fi
  return 0
)

# ============================================================
# runner
# ============================================================
if _case_1 2>&1; then _record PASS 1 "--get mainline_branch / policy が default を返す"
else                  _record FAIL 1 "--get mainline_branch / policy が default を返す"; fi

if _case_2 2>&1; then _record PASS 2 "policy enum validation (local-merge OK / yolo reject)"
else                  _record FAIL 2 "policy enum validation (local-merge OK / yolo reject)"; fi

if _case_3 2>&1; then _record PASS 3 "mainline_branch charset (space reject / develop / release/1.0)"
else                  _record FAIL 3 "mainline_branch charset (space reject / develop / release/1.0)"; fi

if _case_4 2>&1; then _record PASS 4 "config-loader env export + unknown-key warn 不在"
else                  _record FAIL 4 "config-loader env export + unknown-key warn 不在"; fi

if _case_5 2>&1; then _record PASS 5 "値解決順 env > yml > default (--get env override)"
else                  _record FAIL 5 "値解決順 env > yml > default (--get env override)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
