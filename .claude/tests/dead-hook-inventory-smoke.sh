#!/usr/bin/env bash
# dead-hook-inventory-smoke.sh — task-95 Step 1 (Wave 1) smoke
#
# 目的:
#   死蔵 hook 3 件 (tool-call-slip-detector / mode-asana-prompt / mode-enforce)
#   の個別判定結果が SSoT (harness-config.yml enforcement_matrix + feature toggle
#   + fire log) に整合的に反映されていることを機械検証する。
#
# 判定内容 (draft §3.1):
#   H1 tool_call_slip_detect  — 温存 + matrix 登録 (docs_claim=advisory)
#   H2 asana_prompt           — feature toggle 3 点 set 新設 + matrix 登録
#   H3 loop_mode_enforcement  — 3 hook 共有 group を集合 1 entry + hooks_covered
#
# Case → Draft §3.3 mapping (task-95 Wave 1 review 強化後、7 case):
#   DHI-1: matrix に tool_call_slip_detect entry (guard top-level key) 存在
#   DHI-2: 3 guards × 4 required fields = 12 em_field validations
#          (feature_key / docs_claim / events / presets が 3 guard 全てで non-empty)
#   DHI-3: matrix に loop_mode_enforcement entry + hooks_covered sub-field 内容
#          (mode-enforce / loop-confirmation-detector / loop-auto-progress-reminder)
#   DHI-4: enforcement-mismatch-smoke.sh の required set (Case 2) に 3 新 guard
#          が含まれる (static grep)
#   DHI-5: hc-config.sh --summary の出力に 3 新 guard 名が表示される
#   DHI-6: enforcement-mismatch-smoke.sh subprocess PASS (exit 0)
#          — static grep (DHI-4) と実挙動 (subprocess exit) の 2 段検証
#   DHI-7: HC_FEATURE_ASANA_PROMPT_ENABLED=false で mode-asana-prompt.sh が
#          silent exit 0 (functional toggle-off test、Fix A + Fix B 依存)
#
# 設計:
#   - file-top `set -uo pipefail` (feedback_set_e_in_sourced_libs 準拠、errexit 外し)
#   - 全 case を subshell 関数 `_case_dhiN() ( ... )` で隔離 (scope leak 防止)
#   - PASS/FAIL/SKIP カウンタ + 全 PASS で exit 0
#   - DHI-6 は enforcement-mismatch-smoke.sh の subprocess exit code を検査
#     (weaker static grep から強化、task-95 Wave 1 review CRIT-3 対応)
#
# 起源: task-95 Step 1、設計 SSoT: docs/draft/dead-hook-inventory.md §3.1 + §3.3

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"
ASANA_HOOK="${REPO_ROOT}/.claude/hooks/mode-asana-prompt.sh"
ENFORCEMENT_SMOKE="${REPO_ROOT}/.claude/tests/enforcement-mismatch-smoke.sh"

# 新規 3 guard 名 (draft §3.1、Wave 1 判定)
NEW_GUARDS="tool_call_slip_detect asana_prompt loop_mode_enforcement"

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=""

_record() {
  local result="$1" case_id="$2" desc="$3"
  case "$result" in
    PASS) printf '  PASS  Case %s: %s\n' "$case_id" "$desc"; PASS=$((PASS + 1)) ;;
    SKIP) printf '  SKIP  Case %s: %s\n' "$case_id" "$desc"; SKIP=$((SKIP + 1)) ;;
    *)    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"; FAIL=$((FAIL + 1)); FAILED_CASES="${FAILED_CASES} ${case_id}" ;;
  esac
}

# enforcement_matrix 内の top-level guard 名を抽出 (enforcement-mismatch-smoke.sh と同 awk)
_matrix_guards() {
  awk '
    /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
    in_m && /^[^[:space:]]/ { in_m=0 }
    in_m && /^  [a-z_][a-zA-Z0-9_]*:[[:space:]]*$/ {
      line=$0; sub(/^  /,"",line); sub(/:.*$/,"",line); print line
    }
  ' "$HC_CONFIG_YML"
}

# 指定 guard の指定 field 値を抽出 (4-space indent `    <field>: <value>`)
# $1=guard, $2=field
_matrix_field() {
  local guard="$1" field="$2"
  awk -v g="$guard" -v f="$field" '
    /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
    in_m && /^[^[:space:]]/ { in_m=0 }
    in_m && $0 ~ "^  " g ":[[:space:]]*$" { in_g=1; next }
    in_m && in_g && /^  [a-z_]/ { in_g=0 }
    in_m && in_g && $0 ~ "^    " f ":" {
      line=$0; sub("^    " f ":[[:space:]]*","",line); print line; exit
    }
  ' "$HC_CONFIG_YML"
}

# ============================================================
# DHI-1: matrix に tool_call_slip_detect entry 存在
# ============================================================
_case_dhi1() (
  set -uo pipefail
  local guards
  guards="$(_matrix_guards)"
  if printf '%s\n' "$guards" | grep -qx 'tool_call_slip_detect'; then
    return 0
  else
    printf 'DHI-1: tool_call_slip_detect not found in enforcement_matrix\n' >&2
    return 1
  fi
)

# ============================================================
# DHI-2: 3 guards × 4 required fields = 12 em_field validations
#        3 新 guard (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) の
#        4 required field (feature_key / docs_claim / events / presets) が全て
#        matrix 内で non-empty であることを検証する。
#
#        note: disabled_reason は required に含めない (asana_prompt は preset 直交で
#              空 `{}` が意図的正常、feedback_config_value_needs_consumer_and_smoke)。
#              hooks_covered は loop_mode_enforcement 専用 sub-field で DHI-3 側で検証。
#
#        任意 1 field 不在 → 12 checks 中どれが FAIL したか診断出力 + return 1。
# ============================================================
_case_dhi2() (
  set -uo pipefail
  local guards="tool_call_slip_detect asana_prompt loop_mode_enforcement"
  local required_fields="feature_key docs_claim events presets"
  local matrix_guards g f v missing="" checked=0
  matrix_guards="$(_matrix_guards)"
  for g in $guards; do
    if ! printf '%s\n' "$matrix_guards" | grep -qx "$g"; then
      missing="${missing} ${g}:no-guard-entry"
      # guard 不在時は 4 field を skip (parse できないため)
      continue
    fi
    for f in $required_fields; do
      checked=$((checked + 1))
      v="$(_matrix_field "$g" "$f")"
      if [ -z "$v" ]; then
        missing="${missing} ${g}.${f}"
      fi
    done
  done
  if [ -n "$missing" ]; then
    printf 'DHI-2: em_field validations FAILED (%d checked, missing:%s)\n' "$checked" "$missing" >&2
    return 1
  fi
  printf 'DHI-2: 12/12 em_field validations passed (3 guards × 4 required fields)\n' >&2
  return 0
)

# ============================================================
# DHI-3: matrix に loop_mode_enforcement entry + hooks_covered sub-field
# ============================================================
_case_dhi3() (
  set -uo pipefail
  local guards hooks_covered
  guards="$(_matrix_guards)"
  if ! printf '%s\n' "$guards" | grep -qx 'loop_mode_enforcement'; then
    printf 'DHI-3: loop_mode_enforcement not found in enforcement_matrix\n' >&2
    return 1
  fi
  hooks_covered="$(_matrix_field loop_mode_enforcement hooks_covered)"
  if [ -z "$hooks_covered" ]; then
    printf 'DHI-3: hooks_covered sub-field missing under loop_mode_enforcement\n' >&2
    return 1
  fi
  # 期待: mode-enforce / loop-confirmation-detector / loop-auto-progress-reminder が
  #       hooks_covered value のいずれかに含まれる (list format is [a, b, c] YAML 記法)
  local missing=""
  for expected in 'mode-enforce' 'loop-confirmation-detector' 'loop-auto-progress-reminder'; do
    if ! printf '%s' "$hooks_covered" | grep -qF "$expected"; then
      missing="${missing} ${expected}"
    fi
  done
  if [ -n "$missing" ]; then
    printf 'DHI-3: hooks_covered value missing expected hooks:%s (got: %s)\n' "$missing" "$hooks_covered" >&2
    return 1
  fi
  return 0
)

# ============================================================
# DHI-4: enforcement-mismatch-smoke.sh の required set (Case 2) に 3 新 guard
#        が全て含まれる
# ============================================================
_case_dhi4() (
  set -uo pipefail
  if [ ! -f "$ENFORCEMENT_SMOKE" ]; then
    printf 'DHI-4: enforcement-mismatch-smoke.sh not found at %s\n' "$ENFORCEMENT_SMOKE" >&2
    return 1
  fi
  local required_line missing="" g
  # Case 2 の required="..." 行を抽出
  required_line="$(grep -E '^\s*required="' "$ENFORCEMENT_SMOKE" | head -n1)"
  if [ -z "$required_line" ]; then
    printf 'DHI-4: no required="..." line found in enforcement-mismatch-smoke.sh\n' >&2
    return 1
  fi
  for g in $NEW_GUARDS; do
    if ! printf '%s' "$required_line" | grep -qE "\\b${g}\\b"; then
      missing="${missing} ${g}"
    fi
  done
  if [ -n "$missing" ]; then
    printf 'DHI-4: required set does not include:%s\n' "$missing" >&2
    printf '        current line: %s\n' "$required_line" >&2
    return 1
  fi
  return 0
)

# ============================================================
# DHI-5: hc-config.sh --summary の出力に 3 新 guard 名が表示される
# ============================================================
_case_dhi5() (
  set -uo pipefail
  if [ ! -f "$HC_CONFIG_SCRIPT" ]; then
    printf 'DHI-5: hc-config.sh not found\n' >&2
    return 1
  fi
  local summary_out missing="" g
  summary_out="$(bash "$HC_CONFIG_SCRIPT" --summary 2>&1)"
  for g in $NEW_GUARDS; do
    if ! printf '%s\n' "$summary_out" | grep -qE "^\s+${g}:" ; then
      missing="${missing} ${g}"
    fi
  done
  if [ -n "$missing" ]; then
    printf 'DHI-5: --summary output does not show:%s\n' "$missing" >&2
    return 1
  fi
  return 0
)

# ============================================================
# DHI-6: enforcement-mismatch-smoke.sh subprocess exit 0
#        static grep (DHI-4) と 2 段で mismatch 実挙動を検証する
#        (task-95 Wave 1 review CRIT-3 で weaker static grep から強化)
# ============================================================
_case_dhi6() (
  set -uo pipefail
  if [ ! -f "$ENFORCEMENT_SMOKE" ]; then
    printf 'DHI-6: enforcement-mismatch-smoke.sh not found at %s\n' "$ENFORCEMENT_SMOKE" >&2
    return 1
  fi
  # subprocess として実行 (child shell、DHI-4 の static grep とは独立検証)
  # exit 0 = mismatch なし (required guards 全存在 + documented exception 網羅)
  if ! bash "$ENFORCEMENT_SMOKE" >/dev/null 2>&1; then
    printf 'DHI-6: enforcement-mismatch-smoke.sh exit non-zero (real mismatch detected)\n' >&2
    return 1
  fi
  printf 'DHI-6: enforcement-mismatch-smoke.sh exit 0 (no mismatch)\n' >&2
  return 0
)

# ============================================================
# DHI-7: HC_FEATURE_ASANA_PROMPT_ENABLED=false で silent exit 0
#        3-point set (yml key / config-loader default+export / hook 冒頭 check) の
#        機能的動作を検証する。config-loader.sh の default が missing でも env override
#        が優先されるため、yml 直接 stub は不要 (env HC_* は最優先解決順)。
#
#        期待:
#          exit code = 0
#          stdout    = empty (system-reminder を注入しない)
#
#        note: Fix A (config-loader.sh HC_FEATURE_ASANA_PROMPT_ENABLED 追加 +
#              mode-asana-prompt.sh gate) landing 前提。両 fix が未 landing の環境では
#              hook が既存 logic に進み <system-reminder> を出力するため FAIL する。
# ============================================================
_case_dhi7() (
  set -uo pipefail
  if [ ! -f "$ASANA_HOOK" ]; then
    printf 'DHI-7: mode-asana-prompt.sh not found at %s\n' "$ASANA_HOOK" >&2
    return 1
  fi
  local out_file rc
  out_file=$(mktemp /tmp/dhi7-asana-out.XXXXXX)
  # env override で toggle OFF、stdin 空、stdout capture
  HC_FEATURE_ASANA_PROMPT_ENABLED=false \
    bash "$ASANA_HOOK" < /dev/null > "$out_file" 2>/dev/null
  rc=$?
  local out_size
  out_size=$(wc -c < "$out_file" | tr -d ' ')
  out_size=${out_size:-0}
  if [ "$rc" -ne 0 ]; then
    printf 'DHI-7: exit=%d (expected 0), stdout size=%s\n' "$rc" "$out_size" >&2
    head -c 200 "$out_file" >&2 2>/dev/null
    rm -f "$out_file"
    return 1
  fi
  if [ "$out_size" -ne 0 ]; then
    printf 'DHI-7: silent exit expected but stdout %s bytes written (first 200 bytes):\n' "$out_size" >&2
    head -c 200 "$out_file" >&2 2>/dev/null
    rm -f "$out_file"
    return 1
  fi
  rm -f "$out_file"
  printf 'DHI-7: HC_FEATURE_ASANA_PROMPT_ENABLED=false → exit 0 + stdout empty (OK)\n' >&2
  return 0
)

# ============================================================
# Run
# ============================================================
printf '=== dead-hook-inventory smoke (task-95 Step 1 / Wave 1) ===\n'
printf 'repo: %s\n' "$REPO_ROOT"
printf 'yml : %s\n' "$HC_CONFIG_YML"

if _case_dhi1 2>&1; then _record PASS DHI-1 "matrix に tool_call_slip_detect entry 存在"; else _record FAIL DHI-1 "matrix に tool_call_slip_detect entry 存在"; fi
if _case_dhi2 2>&1; then _record PASS DHI-2 "3 guards × 4 required fields = 12 em_field validations"; else _record FAIL DHI-2 "3 guards × 4 required fields = 12 em_field validations"; fi
if _case_dhi3 2>&1; then _record PASS DHI-3 "matrix に loop_mode_enforcement + hooks_covered sub-field"; else _record FAIL DHI-3 "matrix に loop_mode_enforcement + hooks_covered sub-field"; fi
if _case_dhi4 2>&1; then _record PASS DHI-4 "enforcement-mismatch-smoke.sh required set に 3 新 guard"; else _record FAIL DHI-4 "enforcement-mismatch-smoke.sh required set に 3 新 guard"; fi
if _case_dhi5 2>&1; then _record PASS DHI-5 "hc-config.sh --summary に 3 新 guard 表示"; else _record FAIL DHI-5 "hc-config.sh --summary に 3 新 guard 表示"; fi
if _case_dhi6 2>&1; then _record PASS DHI-6 "enforcement-mismatch-smoke.sh subprocess exit 0 (no mismatch)"; else _record FAIL DHI-6 "enforcement-mismatch-smoke.sh subprocess exit 0 (no mismatch)"; fi
if _case_dhi7 2>&1; then _record PASS DHI-7 "HC_FEATURE_ASANA_PROMPT_ENABLED=false silent exit 0"; else _record FAIL DHI-7 "HC_FEATURE_ASANA_PROMPT_ENABLED=false silent exit 0"; fi

printf '\n=== Result: %d PASS, %d FAIL, %d SKIP ===\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES" >&2
  exit 1
fi
exit 0
