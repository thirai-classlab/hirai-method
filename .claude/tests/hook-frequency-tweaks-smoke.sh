#!/usr/bin/env bash
# hook-frequency-tweaks-smoke.sh — task-21 W1.4/W1.5/W1.6 cross-cutting smoke
#
# 目的:
#   Wave 1.4 / 1.5 / 1.6 で導入した 3 hook の頻度間引きを cross-cut 検証する。
#   既存 smoke (context-budget-smoke / next-actions-hooks-smoke /
#   session-help-surface-smoke) との重複を避け、attention dilution 削減効果が
#   実測されることに focus する。
#
# 起源: docs/draft/system-reminder-attention-fix.md W1.4-1.6
#
# テストケース (8 件):
#   1. context-budget: 30% (低 ratio) で完全 silent
#   2. context-budget: 60% で fire (kill switch 通過)
#   3. context-budget: SILENT_BELOW_THRESHOLD=false で debug 出力 (stderr)
#   4. next-actions-surface: 🔴 あり → fire (default RED_ONLY=true)
#   5. next-actions-surface: 🟡 のみ → silent (W1.5 frequency filter)
#   6. next-actions-surface: 🟡 のみ + RED_ONLY=false → 旧挙動 fire (env override)
#   7. session-help-surface: 初回 (marker 未存在) → 表示
#   8. session-help-surface: 2 回目 (marker 既存) → silent + FORCE=1 で revive
#
# 重要制約:
#   - set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)
#   - 各 case は per-case tmp state で隔離 (順序依存排除)
#
# 実行:
#   bash .claude/tests/hook-frequency-tweaks-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

cd "$(cd "$(dirname "$0")/../.." && pwd)" || exit 1
REPO_ROOT="$(pwd)"

CB_HOOK="${REPO_ROOT}/.claude/hooks/context-budget.sh"
NAS_HOOK="${REPO_ROOT}/.claude/hooks/next-actions-surface.sh"
SHS_HOOK="${REPO_ROOT}/.claude/hooks/session-help-surface.sh"
FIXTURES_CB="${REPO_ROOT}/.claude/tests/fixtures"
FIXTURES_NA="${REPO_ROOT}/.claude/tests/fixtures/next-actions"

TMP_BASE="$(mktemp -d /tmp/hook-frequency-tweaks-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
FAILED=()

# helper: record result
_check() {
  local label="$1" actual_result="$2"
  if [ "$actual_result" = "0" ]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s\n' "$label"
    FAIL=$((FAIL+1))
    FAILED+=("$label")
  fi
}

# helper: create a per-case tmp project root with hooks/lib symlinked
_make_tmp_root() {
  local case_id="$1"
  local root="$TMP_BASE/root-$case_id"
  mkdir -p "$root/.claude"
  ln -s "${REPO_ROOT}/.claude/hooks" "$root/.claude/hooks"
  mkdir -p "$root/docs/tasks"
  printf '%s' "$root"
}

# helper: stub the transcript_path JSON for context-budget
_cb_input() {
  local transcript="$1" session="$2"
  printf '{"transcript_path":"%s","session_id":"%s"}' "$transcript" "$session"
}

# ----------------------------------------------------------------------
# Case 1: context-budget 30% (低 ratio) → 完全 silent (W1.4 kill switch)
# ----------------------------------------------------------------------
case_1_cb_low_ratio_silent() {
  # 50% fixture を使い、閾値 60% (default) なら silent
  local state_dir="$TMP_BASE/cb-case1"
  mkdir -p "$state_dir"
  local out
  out=$(_cb_input "${FIXTURES_CB}/transcript-50pct.jsonl" "case1" \
    | env HC_MODE=loop HC_CONTEXT_BUDGET_STATE_DIR="$state_dir" \
        bash "$CB_HOOK" 2>&1)
  local code=$?
  # stdout / stderr どちらにも system-reminder が無く、exit 0
  if [ "$code" = "0" ] && ! printf '%s' "$out" | grep -q "system-reminder"; then
    _check "Case 1: cb 50pct silent (below 60% threshold)" 0
  else
    _check "Case 1: cb 50pct silent (below 60% threshold)" 1
    printf '    output: %s\n' "$out" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 2: context-budget 60% → fire (kill switch 通過)
# ----------------------------------------------------------------------
case_2_cb_threshold_fires() {
  local state_dir="$TMP_BASE/cb-case2"
  mkdir -p "$state_dir"
  local out
  out=$(_cb_input "${FIXTURES_CB}/transcript-60pct.jsonl" "case2" \
    | env HC_MODE=loop HC_CONTEXT_BUDGET_STATE_DIR="$state_dir" \
        bash "$CB_HOOK" 2>&1)
  local code=$?
  if [ "$code" = "0" ] && printf '%s' "$out" | grep -q "system-reminder" \
     && printf '%s' "$out" | grep -q "NOTICE"; then
    _check "Case 2: cb 60pct fires (threshold crossed)" 0
  else
    _check "Case 2: cb 60pct fires (threshold crossed)" 1
    printf '    output: %s\n' "$out" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 3: context-budget SILENT_BELOW_THRESHOLD=false → stderr debug 出力
# ----------------------------------------------------------------------
case_3_cb_debug_below_threshold() {
  local state_dir="$TMP_BASE/cb-case3"
  mkdir -p "$state_dir"
  local out err
  err_file="$TMP_BASE/cb-case3.err"
  out=$(_cb_input "${FIXTURES_CB}/transcript-50pct.jsonl" "case3" \
    | env HC_MODE=loop HC_CONTEXT_BUDGET_STATE_DIR="$state_dir" \
          HC_CONTEXT_BUDGET_SILENT_BELOW_THRESHOLD=false \
        bash "$CB_HOOK" 2>"$err_file")
  local code=$?
  err=$(cat "$err_file" 2>/dev/null)
  # stdout に system-reminder 無し / stderr に "below threshold" / exit 0
  if [ "$code" = "0" ] \
     && ! printf '%s' "$out" | grep -q "system-reminder" \
     && printf '%s' "$err" | grep -q "below threshold"; then
    _check "Case 3: cb SILENT_BELOW_THRESHOLD=false → stderr debug" 0
  else
    _check "Case 3: cb SILENT_BELOW_THRESHOLD=false → stderr debug" 1
    printf '    stdout: %s\n    stderr: %s\n' "$out" "$err" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 4: next-actions 🔴 あり → fire (default RED_ONLY=true でも 🔴 で発火)
# ----------------------------------------------------------------------
case_4_na_red_fires() {
  local root
  root=$(_make_tmp_root "case4")
  cp "${FIXTURES_NA}/case-with-red.md" "$root/docs/tasks/next-actions.md"
  local err_file="$TMP_BASE/na-case4.err"
  env -i PATH="$PATH" HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$root" \
    bash "$NAS_HOOK" </dev/null >/dev/null 2>"$err_file"
  local code=$?
  local err
  err=$(cat "$err_file" 2>/dev/null)
  if [ "$code" = "0" ] && printf '%s' "$err" | grep -q "🔴 2"; then
    _check "Case 4: next-actions 🔴 あり → fire" 0
  else
    _check "Case 4: next-actions 🔴 あり → fire" 1
    printf '    stderr: %s\n' "$err" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 5: next-actions 🟡 のみ → silent (W1.5 frequency filter default)
# ----------------------------------------------------------------------
case_5_na_yellow_only_silent() {
  local root
  root=$(_make_tmp_root "case5")
  cp "${FIXTURES_NA}/case-with-yellow-only.md" "$root/docs/tasks/next-actions.md"
  local err_file="$TMP_BASE/na-case5.err"
  env -i PATH="$PATH" HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$root" \
    bash "$NAS_HOOK" </dev/null >/dev/null 2>"$err_file"
  local code=$?
  local err err_len
  err=$(cat "$err_file" 2>/dev/null)
  err_len=${#err}
  if [ "$code" = "0" ] && [ "$err_len" = "0" ]; then
    _check "Case 5: next-actions 🟡 のみ → silent (W1.5 default)" 0
  else
    _check "Case 5: next-actions 🟡 のみ → silent (W1.5 default)" 1
    printf '    code=%s stderr_len=%s stderr=%s\n' "$code" "$err_len" "$err" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 6: next-actions 🟡 + RED_ONLY=false → 旧挙動 fire
# ----------------------------------------------------------------------
case_6_na_yellow_red_only_false_fires() {
  local root
  root=$(_make_tmp_root "case6")
  cp "${FIXTURES_NA}/case-with-yellow-only.md" "$root/docs/tasks/next-actions.md"
  local err_file="$TMP_BASE/na-case6.err"
  env -i PATH="$PATH" HOME="$HOME" \
    CLAUDE_PROJECT_DIR="$root" \
    HC_NEXT_ACTIONS_SURFACE_RED_ONLY=false \
    bash "$NAS_HOOK" </dev/null >/dev/null 2>"$err_file"
  local code=$?
  local err
  err=$(cat "$err_file" 2>/dev/null)
  if [ "$code" = "0" ] && printf '%s' "$err" | grep -q "🟡 1" \
     && printf '%s' "$err" | grep -q "🔴 0"; then
    _check "Case 6: next-actions 🟡 + RED_ONLY=false → fire (旧挙動 revert)" 0
  else
    _check "Case 6: next-actions 🟡 + RED_ONLY=false → fire (旧挙動 revert)" 1
    printf '    stderr: %s\n' "$err" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 7: session-help-surface 初回 (marker 未存在) → 表示
# ----------------------------------------------------------------------
case_7_shs_first_session_shows() {
  local marker="$TMP_BASE/shs-case7-marker"
  rm -f "$marker"
  local out
  out=$(env -i PATH="$PATH" HOME="$HOME" \
        HC_SESSION_HELP_MARKER_PATH="$marker" \
        bash "$SHS_HOOK" </dev/null 2>/dev/null)
  local code=$?
  if [ "$code" = "0" ] && printf '%s' "$out" | grep -q "主要 slash commands" \
     && [ -f "$marker" ]; then
    _check "Case 7: shs 初回 (marker 未存在) → 表示 + marker 作成" 0
  else
    _check "Case 7: shs 初回 (marker 未存在) → 表示 + marker 作成" 1
    printf '    code=%s marker_exists=%s out_len=%s\n' "$code" \
      "$([ -f "$marker" ] && echo yes || echo no)" "${#out}" >&2
  fi
}

# ----------------------------------------------------------------------
# Case 8: session-help-surface 2 回目 (marker 既存) → silent + FORCE で revive
# ----------------------------------------------------------------------
case_8_shs_second_silent_then_force() {
  local marker="$TMP_BASE/shs-case8-marker"
  : > "$marker"  # marker 既存 (初回完了済)

  # 2 回目: silent のはず
  local out2
  out2=$(env -i PATH="$PATH" HOME="$HOME" \
        HC_SESSION_HELP_MARKER_PATH="$marker" \
        bash "$SHS_HOOK" </dev/null 2>/dev/null)
  local code2=$?

  # FORCE=1: revive
  local out3
  out3=$(env -i PATH="$PATH" HOME="$HOME" \
        HC_SESSION_HELP_MARKER_PATH="$marker" \
        HC_SESSION_HELP_FORCE=1 \
        bash "$SHS_HOOK" </dev/null 2>/dev/null)
  local code3=$?

  if [ "$code2" = "0" ] && [ -z "$out2" ] \
     && [ "$code3" = "0" ] && printf '%s' "$out3" | grep -q "主要 slash commands"; then
    _check "Case 8: shs 2 回目 silent + FORCE=1 で revive" 0
  else
    _check "Case 8: shs 2 回目 silent + FORCE=1 で revive" 1
    printf '    code2=%s out2_len=%s code3=%s out3_match=%s\n' \
      "$code2" "${#out2}" "$code3" \
      "$(printf '%s' "$out3" | grep -q '主要 slash commands' && echo yes || echo no)" >&2
  fi
}

# === run all ===
printf '===== task-21 W1.4/1.5/1.6 hook-frequency-tweaks smoke =====\n'
case_1_cb_low_ratio_silent
case_2_cb_threshold_fires
case_3_cb_debug_below_threshold
case_4_na_red_fires
case_5_na_yellow_only_silent
case_6_na_yellow_red_only_false_fires
case_7_shs_first_session_shows
case_8_shs_second_silent_then_force

printf '\n===== Result =====\n'
printf 'PASS: %d / 8\n' "$PASS"
printf 'FAIL: %d / 8\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases:\n'
  for c in "${FAILED[@]}"; do
    printf '  - %s\n' "$c"
  done
  exit 1
fi
exit 0
