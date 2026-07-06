#!/usr/bin/env bash
# .claude/tests/enforcement-mismatch-smoke.sh — task-70 Phase 2 (enforcement matrix) smoke test
#
# 目的:
#   docs / rules が「BLOCK」と説明する guard (enforcement_matrix.<guard>.docs_claim=block) と、
#   実 enforcement を制御する feature toggle (enforcement_matrix.<guard>.feature_key) の実値の
#   不一致 (mismatch) を検出する。mismatch は「モデルには必須と読ませるが実際の境界では
#   止めない」中間状態であり、最も危険。
#
#   ただし、mismatch があっても enforcement_matrix.<guard>.disabled_reason に現 preset
#   (default_preset) の理由が明記されていれば「意図的な緩和」として PASS とする。
#   disabled_reason が無い mismatch のみ FAIL にする。
#
#   対象 guard (draft §4.2): draft_flow_guard / task_rule_guard / workflow_guard / gateguard
#   + review_required_{design,test,module,system}。
#   task-95 Wave 1 (2026-07-06): 3 新 guard 追加 — tool_call_slip_detect / asana_prompt /
#   loop_mode_enforcement (draft dead-hook-inventory.md §3.1)。
#   task-97 Wave 3 (2026-07-06): 12 新 guard 追加 (draft enforcement-matrix-full-hook-expansion.md
#   §3、全 hook 拡張) — delegation_guard / confidence_gate / autonomous_action_guard /
#   byproduct_discharge / context_budget / parallel_subagent_reminder / reviewer_count_guard /
#   why_x5_enforcement / failure_loop_detect / stale_harness_detect / agent_router_suggest /
#   agent_router_llm_fallback (task-96 由来、Gate/Confidence カテゴリ)。
#   Case 2 semantics: 現状維持 = 最小必須 guard 存在確認 (matrix 実登録が期待 N 件以上を保証、
#   docs↔effective 検証の下限)。追加 guard の feature_key 実在は Case 4 で継続検証。
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離 (feedback_set_e_in_sourced_libs)
#   - matrix の parse は yml を直接 awk (flat parser は nested 値を読めないため)
#   - feature toggle 実値は hc-config.sh --get で取得 (env > local.yml > yml > default の解決を尊重)
#   - PASS/FAIL カウンタ + 全 PASS で exit 0
#
# 起源: task-70 Step 4、設計 SSoT: docs/draft/harness-review-remediation-plan.md §4.2

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"

# task-70 Step 7 (LOW-1 DRY): enforcement matrix parse lib を source。
# lib が存在すれば em_guards / em_field / em_disabled_reason を取り込む。
_EM_PARSE_LIB="${REPO_ROOT}/.claude/scripts/lib/enforcement-matrix-parse.sh"
if [ -f "$_EM_PARSE_LIB" ]; then
  # shellcheck disable=SC1090
  source "$_EM_PARSE_LIB"
fi

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

# enforcement_matrix block の guard 名一覧を yml から抽出。
# task-70 Step 7 (LOW-1 DRY): awk ロジックは lib/enforcement-matrix-parse.sh に SSoT 化。
# lib 存在時は em_guards を、不在時は直接 awk に fallback。
_matrix_guards() {
  if command -v em_guards >/dev/null 2>&1; then
    em_guards "$HC_CONFIG_YML"
  else
    awk '
      /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
      in_m && /^[^[:space:]]/ { in_m=0 }
      in_m && /^  [a-z_][a-zA-Z0-9_]*:[[:space:]]*$/ {
        line=$0; sub(/^  /,"",line); sub(/:.*$/,"",line); print line
      }
    ' "$HC_CONFIG_YML"
  fi
}

# 指定 guard の指定 field 値を抽出 (4-space インデント `    <field>: <value>`)。
# $1=guard, $2=field
_matrix_field() {
  if command -v em_field >/dev/null 2>&1; then
    em_field "$HC_CONFIG_YML" "$1" "$2"
  else
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
  fi
}

# 指定 guard の disabled_reason に指定 preset の理由があるか (0=あり / 1=なし)。
# $1=guard, $2=preset
# lib の em_disabled_reason は reason string を stdout に print + return 0 (理由あり)。
# 本関数は exit code のみを使うため stdout を /dev/null に捨てる。
_matrix_has_disabled_reason() {
  if command -v em_disabled_reason >/dev/null 2>&1; then
    em_disabled_reason "$HC_CONFIG_YML" "$1" "$2" >/dev/null
  else
    local guard="$1" preset="$2"
    awk -v g="$guard" -v p="$preset" '
      /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
      in_m && /^[^[:space:]]/ { in_m=0 }
      in_m && $0 ~ "^  " g ":[[:space:]]*$" { in_g=1; next }
      in_m && in_g && /^  [a-z_]/ { in_g=0; in_dr=0 }
      in_m && in_g && /^    disabled_reason:[[:space:]]*$/ { in_dr=1; next }
      in_m && in_g && /^    [a-z_]/ && !/^    disabled_reason:/ { in_dr=0 }
      in_m && in_g && in_dr && $0 ~ "^      " p ":" {
        val=$0; sub("^      " p ":[[:space:]]*","",val)
        gsub(/^[\"\x27]|[\"\x27][[:space:]]*$/,"",val)
        if (length(val) > 0) { found=1 }
      }
      END { exit (found ? 0 : 1) }
    ' "$HC_CONFIG_YML"
  fi
}

# feature toggle の実効値を取得 (env > local.yml > yml > default)。
_effective() {
  bash "$HC_CONFIG_SCRIPT" --get "$1" 2>/dev/null | head -n1
}

# ============================================================
# Case 1: enforcement_matrix が定義され guard を 1 件以上含む
# ============================================================
_case_1() (
  set -uo pipefail
  local guards count
  guards="$(_matrix_guards)"
  count=$(printf '%s\n' "$guards" | grep -c .)
  printf 'Case 1: matrix guards=%d (%s)\n' "$count" "$(printf '%s' "$guards" | tr '\n' ' ')" >&2
  [ "$count" -ge 4 ]
)

# ============================================================
# Case 2: 対象 23 guard が matrix に存在 (現状維持 semantics = 最小必須 guard 存在確認)
#   base 8: draft/task/workflow/gateguard + review_required_{design,test,module,system}
#   task-95 追加 3: tool_call_slip_detect / asana_prompt / loop_mode_enforcement
#   task-97 追加 12: delegation_guard / confidence_gate / autonomous_action_guard /
#                    byproduct_discharge / context_budget / parallel_subagent_reminder /
#                    reviewer_count_guard / why_x5_enforcement / failure_loop_detect /
#                    stale_harness_detect / agent_router_suggest / agent_router_llm_fallback
# ============================================================
_case_2() (
  set -uo pipefail
  local guards required missing g
  guards="$(_matrix_guards)"
  required="draft_flow_guard task_rule_guard workflow_guard gateguard review_required_design review_required_test review_required_module review_required_system tool_call_slip_detect asana_prompt loop_mode_enforcement delegation_guard confidence_gate autonomous_action_guard byproduct_discharge context_budget parallel_subagent_reminder reviewer_count_guard why_x5_enforcement failure_loop_detect stale_harness_detect agent_router_suggest agent_router_llm_fallback"
  missing=""
  for g in $required; do
    if ! printf '%s\n' "$guards" | grep -qx "$g"; then
      missing="${missing} ${g}"
    fi
  done
  if [ -n "$missing" ]; then
    printf 'Case 2: missing guards in matrix:%s\n' "$missing" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 3: docs_claim=block かつ feature 実値=false の mismatch は
#         現 preset の disabled_reason が無い限り FAIL
# ============================================================
_case_3() (
  set -uo pipefail
  local preset guards g fkey claim eff undoc_mismatch
  preset="$(_effective default_preset)"
  [ -z "$preset" ] && preset="harness-dev"
  guards="$(_matrix_guards)"
  undoc_mismatch=""
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    fkey="$(_matrix_field "$g" feature_key)"
    claim="$(_matrix_field "$g" docs_claim)"
    [ "$claim" = "block" ] || continue
    [ -z "$fkey" ] && continue
    eff="$(_effective "$fkey")"
    if [ "$eff" = "false" ]; then
      # mismatch: docs claims block but effectively disabled
      if ! _matrix_has_disabled_reason "$g" "$preset"; then
        undoc_mismatch="${undoc_mismatch} ${g}"
        printf 'Case 3: UNDOCUMENTED mismatch guard=%s feature_key=%s claim=block eff=%s preset=%s\n' \
          "$g" "$fkey" "$eff" "$preset" >&2
      else
        printf 'Case 3: documented exception guard=%s (preset=%s has disabled_reason)\n' "$g" "$preset" >&2
      fi
    fi
  done <<< "$guards"
  if [ -n "$undoc_mismatch" ]; then
    printf 'Case 3: undocumented mismatches:%s\n' "$undoc_mismatch" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 4: 各 guard の feature_key が yml top-level に実在する
#         (matrix が存在しない feature_key を参照していない)
# ============================================================
_case_4() (
  set -uo pipefail
  local guards g fkey bad
  guards="$(_matrix_guards)"
  bad=""
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    fkey="$(_matrix_field "$g" feature_key)"
    [ -z "$fkey" ] && { bad="${bad} ${g}:no-feature_key"; continue; }
    if ! grep -qE "^${fkey}:" "$HC_CONFIG_YML"; then
      bad="${bad} ${g}:${fkey}-not-in-yml"
    fi
  done <<< "$guards"
  if [ -n "$bad" ]; then
    printf 'Case 4: bad feature_key refs:%s\n' "$bad" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 5: docs_claim=block + 現 preset で false にする guard には必ず disabled_reason
#         (documented-exception の網羅性: matrix の self-consistency)
# ============================================================
_case_5() (
  set -uo pipefail
  local preset guards g claim presetval missing
  preset="$(_effective default_preset)"
  [ -z "$preset" ] && preset="harness-dev"
  guards="$(_matrix_guards)"
  missing=""
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    claim="$(_matrix_field "$g" docs_claim)"
    [ "$claim" = "block" ] || continue
    # presets line: {advisory: false, team-default: true, ...}
    presetval="$(_matrix_field "$g" presets)"
    # 現 preset が false 期待なら disabled_reason 必須
    if printf '%s' "$presetval" | grep -qE "${preset}:[[:space:]]*false"; then
      if ! _matrix_has_disabled_reason "$g" "$preset"; then
        missing="${missing} ${g}"
      fi
    fi
  done <<< "$guards"
  if [ -n "$missing" ]; then
    printf 'Case 5: preset=%s expects false but no disabled_reason:%s\n' "$preset" "$missing" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Run
# ============================================================
printf '=== enforcement mismatch smoke ===\n'

if _case_1 2>&1; then _record PASS 1 "enforcement_matrix に guard が 4 件以上定義されている"; else _record FAIL 1 "enforcement_matrix に guard が 4 件以上定義されている"; fi
if _case_2 2>&1; then _record PASS 2 "対象 23 guard (base 8 + task-95 追加 3 + task-97 追加 12) が matrix に存在"; else _record FAIL 2 "対象 23 guard が matrix に存在"; fi
if _case_3 2>&1; then _record PASS 3 "docs=block かつ実値=false の mismatch は disabled_reason 不在で fail"; else _record FAIL 3 "undocumented mismatch を検出 (disabled_reason 不在)"; fi
if _case_4 2>&1; then _record PASS 4 "全 guard の feature_key が yml top-level に実在"; else _record FAIL 4 "feature_key が yml に実在"; fi
if _case_5 2>&1; then _record PASS 5 "現 preset で false 期待の block guard に disabled_reason が網羅"; else _record FAIL 5 "現 preset false 期待 guard の disabled_reason 網羅"; fi

printf '\n=== Result: %d PASS, %d FAIL ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES" >&2
  exit 1
fi
exit 0
