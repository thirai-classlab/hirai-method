#!/usr/bin/env bash
# .claude/tests/hc-config-tui-smoke.sh — task-48 Step 1 (TDD RED)
#
# 目的:
#   hc-config.sh TUI 化 + key metadata 表示 (task-48) の smoke test。
#   Step 2 (lib/hc-config-metadata.sh 新設) と Step 3 (矢印キー TUI + --list 拡張) を
#   実装する前に RED 状態 (7/7 EXPECTED FAIL) を確立する。
#
# 7 cases:
#   Case 1: metadata 完全性 — 全 74 key に description + effect が存在
#   Case 2: category グルーピング — 6 category 全 key 分類、未分類 key 0
#   Case 3: --list 説明列拡張 — 説明列が出力に含まれる
#   Case 4: --list --verbose — 変更効果列が出力に含まれる
#   Case 5: TTY fallback 明示実装 — pipe 経由で番号選択 menu に降格 (実装フラグ検証)
#   Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 で強制番号選択
#   Case 7: inline comment 抽出 — harness-config.yml の comment が metadata に反映される
#
# RED 設計方針:
#   - 新機能 (lib/hc-config-metadata.sh) が未実装なので metadata 系 case は構造的に FAIL
#   - --list 説明列 / --verbose は出力 keyword がないので FAIL
#   - TTY fallback / HC_HC_CONFIG_FORCE_NUMERIC は Step 3 での明示実装が必要で FAIL
#   - inline comment 抽出は metadata 実装後に GREEN になる
#   - 各 case 冒頭の RED marker コメントで "EXPECTED FAIL" を明示
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
HC_CONFIG_METADATA_LIB="${REPO_ROOT}/.claude/scripts/lib/hc-config-metadata.sh"

# tmp dir (cleanup on exit)
TMP_DIR="$(mktemp -d "/tmp/hc-config-tui-smoke.XXXXXX")"
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

# timeout fallback (BSD compatible)
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

# 全 key を harness-config.yml から抽出するヘルパー
# format: KEY1 KEY2 KEY3 ... (space-separated)
_get_all_config_keys() {
  grep -E '^\s*[a-zA-Z_][a-zA-Z0-9_]*:' "${HC_CONFIG_YML}" \
    | sed 's/:.*//' \
    | tr -d ' \t'
}

# ============================================================
# Case 1: metadata 完全性 — 全 74 key に description + effect が存在
# ============================================================
# RED marker: lib/hc-config-metadata.sh が未実装なので EXPECTED FAIL
_case_1() (
  set -uo pipefail

  # RED guard: metadata lib が存在しなければ EXPECTED FAIL
  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf '[Case 1] EXPECTED FAIL: lib/hc-config-metadata.sh not implemented yet (RED phase)\n' >&2
    return 1
  fi

  # metadata lib を source して全 key のカバレッジ確認
  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  local all_keys
  all_keys="$(_get_all_config_keys)"
  local missing=0

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    # description が定義されているか確認
    # hc_metadata_description <key> or metadata table lookup
    local desc=""
    if command -v hc_metadata_description >/dev/null 2>&1; then
      desc="$(hc_metadata_description "$key" 2>/dev/null || true)"
    fi
    if [ -z "$desc" ]; then
      printf 'Case 1: missing description for key: %s\n' "$key" >&2
      missing=$((missing + 1))
    fi
    # effect が定義されているか確認
    local effect=""
    if command -v hc_metadata_effect >/dev/null 2>&1; then
      effect="$(hc_metadata_effect "$key" 2>/dev/null || true)"
    fi
    if [ -z "$effect" ]; then
      printf 'Case 1: missing effect for key: %s\n' "$key" >&2
      missing=$((missing + 1))
    fi
  done <<< "$all_keys"

  [ $missing -eq 0 ]
)

# ============================================================
# Case 2: category グルーピング — 6 category 全 key 分類、未分類 key 0
# ============================================================
# RED marker: lib/hc-config-metadata.sh が未実装なので EXPECTED FAIL
_case_2() (
  set -uo pipefail

  # RED guard: metadata lib が存在しなければ EXPECTED FAIL
  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf '[Case 2] EXPECTED FAIL: lib/hc-config-metadata.sh not implemented yet (RED phase)\n' >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  # 6 category が存在するか確認
  local expected_categories="保護パス ファイル配置 state_dir Gate/Confidence feature_toggle reviewer_control"
  local missing_categories=0

  for cat in $expected_categories; do
    if ! (command -v hc_metadata_keys_by_category >/dev/null 2>&1 && \
          hc_metadata_keys_by_category "$cat" 2>/dev/null | grep -q '.'); then
      printf 'Case 2: category not found or empty: %s\n' "$cat" >&2
      missing_categories=$((missing_categories + 1))
    fi
  done

  # 未分類 key が 0 であること
  local all_keys
  all_keys="$(_get_all_config_keys)"
  local unclassified=0

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    local cat=""
    if command -v hc_metadata_category >/dev/null 2>&1; then
      cat="$(hc_metadata_category "$key" 2>/dev/null || true)"
    fi
    if [ -z "$cat" ]; then
      printf 'Case 2: key has no category: %s\n' "$key" >&2
      unclassified=$((unclassified + 1))
    fi
  done <<< "$all_keys"

  [ $missing_categories -eq 0 ] && [ $unclassified -eq 0 ]
)

# ============================================================
# Case 3: --list 説明列拡張 — 説明列が出力に含まれる
# ============================================================
# RED marker: Step 3 実装前は --list が説明列を出力しないので EXPECTED FAIL
_case_3() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case 3] EXPECTED FAIL: hc-config.sh not found (RED phase)\n' >&2
    return 1
  fi

  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null)"
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 3: --list returned exit code %d\n' "$exit_code" >&2
    return 1
  fi

  # RED phase: 「説明」列ヘッダー or 代表 key の description keyword が出力に含まれるか確認
  # 現行 --list は KEY/CURRENT/DEFAULT/TYPE の 4 列のみで「説明」列は未実装
  # Step 3 実装後: "説明" ヘッダー or description コンテンツが出力に含まれる
  if ! printf '%s' "$output" | grep -q '説明'; then
    printf '[Case 3] EXPECTED FAIL: --list does not contain 説明 column (not implemented yet, RED phase)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 4: --list --verbose — 変更効果列が出力に含まれる
# ============================================================
# RED marker: Step 3 実装前は --list --verbose が変更効果列を出力しないので EXPECTED FAIL
_case_4() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case 4] EXPECTED FAIL: hc-config.sh not found (RED phase)\n' >&2
    return 1
  fi

  local output
  output="$(bash "${HC_CONFIG_SCRIPT}" --list --verbose 2>/dev/null)"
  local exit_code=$?

  # --list --verbose が未実装なら exit non-0 か「変更効果」が出力に含まれないかで FAIL
  # 現行は --list のみ実装 (--verbose オプション未対応、おそらく exit 1 or 4 列出力)
  if [ $exit_code -ne 0 ]; then
    printf '[Case 4] EXPECTED FAIL: --list --verbose not implemented yet (exit code %d, RED phase)\n' "$exit_code" >&2
    return 1
  fi

  # --verbose option が通っても「変更効果」列が未実装なら FAIL
  if ! printf '%s' "$output" | grep -q '変更効果'; then
    printf '[Case 4] EXPECTED FAIL: --list --verbose does not contain 変更効果 column (not implemented yet, RED phase)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 5: TTY fallback 明示実装 — pipe 経由で番号選択 menu に降格 (実装フラグ検証)
# ============================================================
# RED marker: 現行 hc-config.sh は TTY fallback 機構を "明示的に" 実装していない。
#   現行でも pipe 経由で番号 menu が出るが、それは TTY check なしの fallback の「副作用」に過ぎない。
#   Step 3 実装後: [ -t 0 ] && [ -t 1 ] による明示的な TTY check + NUMERIC fallback path が存在する。
#   本 Case は HC_HC_CONFIG_TTY_FALLBACK_IMPLEMENTED マーカー or 実装済みシンボルで判定する。
# ============================================================
_case_5() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case 5] EXPECTED FAIL: hc-config.sh not found (RED phase)\n' >&2
    return 1
  fi

  # Step 3 実装後の確認: hc-config.sh に TTY check コードが存在するか
  # grep で "[ -t 0 ]" または "_cmd_interactive_numeric" または "FORCE_NUMERIC" シンボルを確認
  if ! grep -q '_cmd_interactive_numeric\|HC_HC_CONFIG_FORCE_NUMERIC\|\[ -t 0 \]' "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
    printf '[Case 5] EXPECTED FAIL: TTY fallback (_cmd_interactive_numeric / HC_HC_CONFIG_FORCE_NUMERIC / [ -t 0 ]) not implemented yet (RED phase)\n' >&2
    return 1
  fi

  # TTY fallback が実装済みなら、pipe 経由で番号 menu が出ることを確認
  local output
  output="$(printf 'q\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  if ! printf '%s' "$output" | grep -q 'hc-config interactive menu'; then
    printf 'Case 5: numeric menu not shown in non-TTY (pipe) context\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 で強制番号選択
# ============================================================
# RED marker: HC_HC_CONFIG_FORCE_NUMERIC env が未認識 (Step 3 で実装予定) なので EXPECTED FAIL
_case_6() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf '[Case 6] EXPECTED FAIL: hc-config.sh not found (RED phase)\n' >&2
    return 1
  fi

  # Step 3 実装後の確認: HC_HC_CONFIG_FORCE_NUMERIC が hc-config.sh に実装済みか
  if ! grep -q 'HC_HC_CONFIG_FORCE_NUMERIC' "${HC_CONFIG_SCRIPT}" 2>/dev/null; then
    printf '[Case 6] EXPECTED FAIL: HC_HC_CONFIG_FORCE_NUMERIC not implemented yet (RED phase)\n' >&2
    return 1
  fi

  # 実装済みなら: TTY 環境でも HC_HC_CONFIG_FORCE_NUMERIC=1 で番号 menu が出ることを確認
  local output
  output="$(HC_HC_CONFIG_FORCE_NUMERIC=1 printf 'q\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  if ! printf '%s' "$output" | grep -q 'hc-config interactive menu'; then
    printf 'Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 did not force numeric menu\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case 7: inline comment 抽出 — harness-config.yml の comment が metadata に反映される
# ============================================================
# RED marker: lib/hc-config-metadata.sh が未実装なので EXPECTED FAIL
# 代表 key: review_iteration_max (inline comment: "default 5 (採用 6 条 4 で 5 回上限)")
_case_7() (
  set -uo pipefail

  # RED guard: metadata lib が存在しなければ EXPECTED FAIL
  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf '[Case 7] EXPECTED FAIL: lib/hc-config-metadata.sh not implemented yet (RED phase)\n' >&2
    return 1
  fi

  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  # review_iteration_max の inline comment が description に反映されているか確認
  # harness-config.yml: review_iteration_max: 5  # default 5 (採用 6 条 4 で 5 回上限)
  local desc=""
  if command -v hc_metadata_description >/dev/null 2>&1; then
    desc="$(hc_metadata_description "review_iteration_max" 2>/dev/null || true)"
  fi

  if [ -z "$desc" ]; then
    printf 'Case 7: review_iteration_max has no description in metadata\n' >&2
    return 1
  fi

  # inline comment のキーワードが description に含まれるか確認
  # "採用 6 条" or "5 回上限" or "反復" 等の語が含まれるなら inline comment 抽出成功
  if ! printf '%s' "$desc" | grep -qE '採用|反復|iteration|上限'; then
    printf 'Case 7: review_iteration_max description does not contain inline comment keywords\n' >&2
    printf '  description: %s\n' "$desc" >&2
    return 1
  fi

  # 追加: feature_loop_mode_enforcement_enabled の inline comment も確認
  # harness-config.yml: feature_loop_mode_enforcement_enabled: true  # loop-confirmation-detector + ...
  local desc2=""
  if command -v hc_metadata_description >/dev/null 2>&1; then
    desc2="$(hc_metadata_description "feature_loop_mode_enforcement_enabled" 2>/dev/null || true)"
  fi

  if [ -z "$desc2" ]; then
    printf 'Case 7b: feature_loop_mode_enforcement_enabled has no description in metadata\n' >&2
    return 1
  fi

  if ! printf '%s' "$desc2" | grep -qE 'loop|confirmation|detector'; then
    printf 'Case 7b: feature_loop_mode_enforcement_enabled description does not contain inline comment keywords\n' >&2
    printf '  description: %s\n' "$desc2" >&2
    return 1
  fi

  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== hc-config-tui-smoke (task-48 Step 1: 7 cases, TDD RED phase) ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "metadata 完全性 — 全 74 key に description + effect が存在"
else                         _record FAIL 1 "metadata 完全性 — 全 74 key に description + effect が存在"
fi

if _case_2 2>/dev/null; then _record PASS 2 "category グルーピング — 6 category 全 key 分類、未分類 key 0"
else                         _record FAIL 2 "category グルーピング — 6 category 全 key 分類、未分類 key 0"
fi

if _case_3 2>/dev/null; then _record PASS 3 "--list 説明列拡張 — 説明列が出力に含まれる"
else                         _record FAIL 3 "--list 説明列拡張 — 説明列が出力に含まれる"
fi

if _case_4 2>/dev/null; then _record PASS 4 "--list --verbose — 変更効果列が出力に含まれる"
else                         _record FAIL 4 "--list --verbose — 変更効果列が出力に含まれる"
fi

if _case_5 2>/dev/null; then _record PASS 5 "TTY fallback 明示実装 — pipe 経由で番号選択 menu に降格 (実装シンボル確認)"
else                         _record FAIL 5 "TTY fallback 明示実装 — pipe 経由で番号選択 menu に降格 (実装シンボル確認)"
fi

if _case_6 2>/dev/null; then _record PASS 6 "HC_HC_CONFIG_FORCE_NUMERIC=1 で強制番号選択"
else                         _record FAIL 6 "HC_HC_CONFIG_FORCE_NUMERIC=1 で強制番号選択"
fi

if _case_7 2>/dev/null; then _record PASS 7 "inline comment 抽出 — harness-config.yml の comment が metadata に反映される"
else                         _record FAIL 7 "inline comment 抽出 — harness-config.yml の comment が metadata に反映される"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  printf '\nHINT: RED phase (task-48 Step 1):\n'
  printf '  Cases 1,2,7: lib/hc-config-metadata.sh not yet implemented (Step 2)\n'
  printf '  Cases 3,4:   --list 説明列 / --verbose 未実装 (Step 3)\n'
  printf '  Cases 5,6:   TTY fallback / HC_HC_CONFIG_FORCE_NUMERIC 未実装 (Step 3)\n'
  printf '  GREEN になるのは Step 2 + Step 3 実装完了後です。\n'
  exit 1
fi

exit 0
