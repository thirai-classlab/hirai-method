#!/usr/bin/env bash
# .claude/tests/config-feature-toggles-smoke.sh — task-44 Step 3 + iter 2
#
# 目的:
#   config-loader.sh に追加される is_feature_enabled 関数の動作を 9 ケースで検証する。
#
#   - Case 1: feature toggle ON (yml default true + env unset) で exit 0
#   - Case 2: feature toggle OFF (HC_FEATURE_*_ENABLED=false) で exit 1
#   - Case 3: 新 key 未設定 (yml に該当 key 不在) で default ON (exit 0)
#   - Case 4: env override 優先 (yml false + env HC_FEATURE_*_ENABLED=true) で exit 0
#   - Case 5: case insensitive (HC_FEATURE_FOO_ENABLED=False) で exit 1
#   - Case 6: 関数存在確認 (declare -f is_feature_enabled で定義を確認)
#   - Case 7: (iter 2 追加) yml false + env unset で OFF
#             production feature 名 loop_mode_enforcement 使用 (CRITICAL-1 regression 検出)
#   - Case 8: (iter 2 追加) review_* key 動作確認 (yml override で int 値 + bool 値 load)
#   - Case 9: (iter 2 追加) 引数なし呼び出し `is_feature_enabled ""` で safe default ON
#
# 設計:
#   - 一時 yml file を /tmp/ に Write してテスト用 yml として使用
#   - HC_* env を一時 export + unset で cleanup しテスト間の汚染防止
#   - HC_CONFIG_PATH で config-loader.sh が読む yml path を差し替え (env override)
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0 / 1 件 FAIL で exit 1
#
# 依存前提:
#   subagent B (config-loader.sh 拡張) が完了し is_feature_enabled 関数が存在すること。
#   関数未実装の場合は全 case が FAIL し、その旨を最終行に表示する。
#
# 実行:
#   bash .claude/tests/config-feature-toggles-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)
#   - test 間 env 汚染防止 (各 case 後に HC_FEATURE_* unset)

# shellcheck disable=SC2030,SC2031
# SC2030/SC2031: HC_CONFIG_PATH export は各 case の subshell 内で意図的に行う (test isolation)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"

# smoke 実行前に config-loader.sh が存在するか確認
if [ ! -f "$CONFIG_LOADER" ]; then
  printf 'ERROR: config-loader.sh not found: %s\n' "$CONFIG_LOADER" >&2
  exit 1
fi

# tmp dir (cleanup on exit)
TMP_DIR="$(mktemp -d "/tmp/config-feature-toggles-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=""

# --- helpers ---

# PASS/FAIL を記録して結果行を出力
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

# 一時 yml を作成して HC_CONFIG_PATH を設定するヘルパー
# $1 = yml content string
# $2 = case id (file 名 衝突回避用、default = "default")
# sets TMP_YML (path) に書き込む
_write_tmp_yml() {
  local content="$1"
  local case_id="${2:-default}"
  TMP_YML="${TMP_DIR}/test-harness-config-${case_id}-$$.yml"
  printf '%s\n' "$content" > "$TMP_YML"
}

# env 汚染防止: HC_FEATURE_* 系 + HC_REVIEW_* 系をすべて unset
_cleanup_feature_envs() {
  unset HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED 2>/dev/null || true
  unset HC_FEATURE_FOO_ENABLED 2>/dev/null || true
  unset HC_FEATURE_BAR_ENABLED 2>/dev/null || true
  unset HC_FEATURE_NONEXISTENT_FEATURE_ENABLED 2>/dev/null || true
  unset HC_FEATURE_X_ENABLED 2>/dev/null || true
  # iter 2 追加 (Case 8 review_* 系)
  unset HC_REVIEW_REQUIRED_DESIGN 2>/dev/null || true
  unset HC_REVIEW_MIN_COUNT_TEST 2>/dev/null || true
  unset HC_CONFIG_PATH 2>/dev/null || true
}

# ============================================================
# Case 1: feature toggle ON (yml default true + env unset)
# yml に feature_loop_mode_enforcement_enabled: true を置き、
# env 未設定で is_feature_enabled loop_mode_enforcement が exit 0 を返すか確認
# ============================================================
_case_1() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "feature_loop_mode_enforcement_enabled: true" "case1"
  export HC_CONFIG_PATH="$TMP_YML"
  unset HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED 2>/dev/null || true
  # config-loader を source して関数 load
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  # 関数存在確認 (subagent B 未完了時はここで失敗)
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found (subagent B not complete)\n' >&2
    return 1
  fi
  is_feature_enabled "loop_mode_enforcement"
)

# ============================================================
# Case 2: feature toggle OFF (HC_FEATURE_*_ENABLED=false env)
# yml は true でも env override false で exit 1 を返すか確認
# ============================================================
_case_2() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "feature_loop_mode_enforcement_enabled: true" "case2"
  export HC_CONFIG_PATH="$TMP_YML"
  export HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED="false"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # env override false なので exit 1 を期待 → 反転して確認
  if is_feature_enabled "loop_mode_enforcement"; then
    # exit 0 は予期しない (false が無視されている)
    return 1
  fi
  return 0
)

# ============================================================
# Case 3: 新 key 未設定 (yml に該当 key 不在 + env unset)
# → default ON (backward compat) で is_feature_enabled が exit 0 を返すか確認
# ============================================================
_case_3() (
  set -uo pipefail
  _cleanup_feature_envs
  # yml に feature_nonexistent_feature_enabled は含まない (空 yml)
  _write_tmp_yml "task_dir: docs/tasks" "case3"
  export HC_CONFIG_PATH="$TMP_YML"
  unset HC_FEATURE_NONEXISTENT_FEATURE_ENABLED 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # 未設定 key は default ON (exit 0) を期待
  is_feature_enabled "nonexistent_feature"
)

# ============================================================
# Case 4: env override 優先 (yml false + env HC_FEATURE_X_ENABLED=true)
# yml に feature_x_enabled: false を置き、env true で exit 0 を返すか確認
# ============================================================
_case_4() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "feature_x_enabled: false" "case4"
  export HC_CONFIG_PATH="$TMP_YML"
  export HC_FEATURE_X_ENABLED="true"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # env true が yml false より優先されるので exit 0 を期待
  is_feature_enabled "x"
)

# ============================================================
# Case 5: case insensitive (HC_FEATURE_FOO_ENABLED=False 大文字混在)
# → false と同様に扱い exit 1 を返すか確認
# ============================================================
_case_5() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "feature_foo_enabled: true" "case5"
  export HC_CONFIG_PATH="$TMP_YML"
  export HC_FEATURE_FOO_ENABLED="False"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # "False" は false 扱いなので exit 1 を期待
  if is_feature_enabled "foo"; then
    return 1
  fi
  return 0
)

# ============================================================
# Case 6: 関数存在確認 (declare -f is_feature_enabled で定義を確認)
# ============================================================
_case_6() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "task_dir: docs/tasks" "case6"
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  declare -f is_feature_enabled >/dev/null 2>&1
)

# ============================================================
# Case 7 (iter 2 追加): yml false + env unset で OFF
# production feature 名 loop_mode_enforcement を使用、CRITICAL-1 regression を検出。
# Step 2 defaults で HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED="true" が set 済の状態で
# yml の false が正しく上書きできるか確認。
# 旧実装 (Step 2 後の env を check) では BUG (yml false が無視されて enabled に判定)。
# iter 2 fix (_HC_PRESET_KEYS snapshot ベース) で yml false が反映されて disabled になる。
# ============================================================
_case_7() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "feature_loop_mode_enforcement_enabled: false" "case7"
  export HC_CONFIG_PATH="$TMP_YML"
  unset HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # yml false が反映されて disabled (exit 1) を期待 → 反転して確認
  if is_feature_enabled "loop_mode_enforcement"; then
    # exit 0 は予期しない (CRITICAL-1 regression、yml false が無視されている)
    return 1
  fi
  return 0
)

# ============================================================
# Case 8 (iter 2 追加): review_* key 動作確認
# yml で review_required_design=false + review_min_count_test=3 を設定し、
# それぞれ HC_REVIEW_REQUIRED_DESIGN="false" / HC_REVIEW_MIN_COUNT_TEST="3" として
# 正しく load されることを確認する (env 値が yml から書き込まれていることを確認)。
# ============================================================
_case_8() (
  set -uo pipefail
  _cleanup_feature_envs
  # yml で bool false と int 3 を override
  _write_tmp_yml "$(printf '%s\n%s' 'review_required_design: false' 'review_min_count_test: 3')" "case8"
  export HC_CONFIG_PATH="$TMP_YML"
  unset HC_REVIEW_REQUIRED_DESIGN 2>/dev/null || true
  unset HC_REVIEW_MIN_COUNT_TEST 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  # 値検証 (yml から書き込まれた値が export されているか)
  [ "${HC_REVIEW_REQUIRED_DESIGN:-}" = "false" ] || return 1
  [ "${HC_REVIEW_MIN_COUNT_TEST:-}" = "3" ] || return 1
  return 0
)

# ============================================================
# Case 9 (iter 2 追加): 引数なし呼び出しで safe default ON
# is_feature_enabled "" or 引数なしで safe side (exit 0 = enabled) + stderr WARN
# (test-automator MEDIUM-3、防御的プログラミング検証)
# ============================================================
_case_9() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "task_dir: docs/tasks" "case9"
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # 引数なし or 空文字 で exit 0 (safe default ON) を期待 (stderr WARN は許容)
  is_feature_enabled "" 2>/dev/null
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== config-feature-toggles-smoke ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "feature toggle ON (yml true + env unset) → exit 0"
else                         _record FAIL 1 "feature toggle ON (yml true + env unset) → exit 0"
fi

if _case_2 2>/dev/null; then _record PASS 2 "feature toggle OFF (env false) → exit 1"
else                         _record FAIL 2 "feature toggle OFF (env false) → exit 1"
fi

if _case_3 2>/dev/null; then _record PASS 3 "new key absent → default ON (exit 0)"
else                         _record FAIL 3 "new key absent → default ON (exit 0)"
fi

if _case_4 2>/dev/null; then _record PASS 4 "env override priority (yml false + env true → exit 0)"
else                         _record FAIL 4 "env override priority (yml false + env true → exit 0)"
fi

if _case_5 2>/dev/null; then _record PASS 5 "case insensitive (False → exit 1)"
else                         _record FAIL 5 "case insensitive (False → exit 1)"
fi

if _case_6 2>/dev/null; then _record PASS 6 "is_feature_enabled function exists (declare -f)"
else                         _record FAIL 6 "is_feature_enabled function exists (declare -f)"
fi

if _case_7 2>/dev/null; then _record PASS 7 "yml false + env unset → OFF (CRITICAL-1 regression check)"
else                         _record FAIL 7 "yml false + env unset → OFF (CRITICAL-1 regression check)"
fi

if _case_8 2>/dev/null; then _record PASS 8 "review_* yml override (bool false + int 3)"
else                         _record FAIL 8 "review_* yml override (bool false + int 3)"
fi

if _case_9 2>/dev/null; then _record PASS 9 "empty arg → safe default ON (exit 0)"
else                         _record FAIL 9 "empty arg → safe default ON (exit 0)"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  # is_feature_enabled が見つからない場合のヒント
  if ! bash -c ". '${CONFIG_LOADER}' && declare -f is_feature_enabled" >/dev/null 2>&1; then
    printf '\nHINT: is_feature_enabled not found in %s\n' "$CONFIG_LOADER"
    printf '      subagent B (config-loader.sh 拡張) の完了を確認してください。\n'
  fi
  exit 1
fi

exit 0
