#!/usr/bin/env bash
# .claude/tests/config-feature-toggles-smoke.sh — task-44 Step 3
#
# 目的:
#   config-loader.sh の is_feature_enabled 関数 + 行末コメント strip (task-64 Step 1) を 10 ケースで検証する。
#
#   - Case 1: feature toggle ON (yml default true + env unset) で exit 0
#   - Case 2: feature toggle OFF (HC_FEATURE_*_ENABLED=false) で exit 1
#   - Case 3: 新 key 未設定 (yml に該当 key 不在) で default ON (exit 0)
#   - Case 4: env override 優先 (yml false + env HC_FEATURE_*_ENABLED=true) で exit 0
#   - Case 5: case insensitive (HC_FEATURE_FOO_ENABLED=False) で exit 1
#   - Case 6: 関数存在確認 (declare -f is_feature_enabled で定義を確認)
#   - Case 7: 行末コメント strip → clean export (`key: 10  # comment` → HC=10、task-64)
#   - Case 8: double-quote 値内 `#` 保護 (`key: "url#frag"` → url#frag 保持、task-64)
#   - Case 9: inline array + 行末コメント strip 不変 (`[a, b]  # c` → a,b、task-64)
#   - Case 10: stale_harness_detect default true export + env false で disable (task-71 M2)
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
# sets TMP_YML (path) に書き込む
_write_tmp_yml() {
  local content="$1"
  TMP_YML="${TMP_DIR}/test-harness-config-$$.yml"
  printf '%s\n' "$content" > "$TMP_YML"
}

# env 汚染防止: HC_FEATURE_* 系をすべて unset
_cleanup_feature_envs() {
  unset HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED 2>/dev/null || true
  unset HC_FEATURE_FOO_ENABLED 2>/dev/null || true
  unset HC_FEATURE_BAR_ENABLED 2>/dev/null || true
  unset HC_FEATURE_NONEXISTENT_FEATURE_ENABLED 2>/dev/null || true
  unset HC_FEATURE_X_ENABLED 2>/dev/null || true
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
  _write_tmp_yml "feature_loop_mode_enforcement_enabled: true"
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
  _write_tmp_yml "feature_loop_mode_enforcement_enabled: true"
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
  _write_tmp_yml "task_dir: docs/tasks"
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
  _write_tmp_yml "feature_x_enabled: false"
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
  _write_tmp_yml "feature_foo_enabled: true"
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
  _write_tmp_yml "task_dir: docs/tasks"
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  declare -f is_feature_enabled >/dev/null 2>&1
)

# ============================================================
# Case 7 (task-64 Step 1): 行末コメント strip → clean export
# `review_max_count_test: 10  # comment` を読み HC_REVIEW_MAX_COUNT_TEST が
# comment なしの clean `10` で export されることを確認 (root cause B 回帰防止)。
# 旧挙動では "10             # default..." と comment 込みで export され数値比較が壊れた。
# ============================================================
_case_7() (
  set -uo pipefail
  _cleanup_feature_envs
  _write_tmp_yml "review_max_count_test: 10             # default registry 全件、上限指定"
  export HC_CONFIG_PATH="$TMP_YML"
  unset HC_REVIEW_MAX_COUNT_TEST 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  # comment が strip され clean `10` であること (前後空白 / # 混入を許さない)
  if [ "$HC_REVIEW_MAX_COUNT_TEST" != "10" ]; then
    printf 'expected [10], got [%s]\n' "$HC_REVIEW_MAX_COUNT_TEST" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 8 (task-64 Step 1): 値内 `#` 保護 (double-quote 値)
# `key: "https://x/#frag"` を読み HC が `#frag` を保持して export することを確認。
# double-quote で囲んだ値は comment strip を skip し値内 `#` を保護する
# (hc-config.sh _yml_get_raw と同一挙動、URL fragment 等の正規ユースケース)。
# ============================================================
_case_8() (
  set -uo pipefail
  _cleanup_feature_envs
  unset HC_DOCS_APPROVED_DIR 2>/dev/null || true
  _write_tmp_yml 'docs_approved_dir: "https://example.com/page#section"'
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if [ "$HC_DOCS_APPROVED_DIR" != "https://example.com/page#section" ]; then
    printf 'expected [https://example.com/page#section], got [%s]\n' "$HC_DOCS_APPROVED_DIR" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 9 (task-64 Step 1): inline array が行末コメント strip で壊れない
# `protected_paths: [src, tests, scripts]  # comment` を読み、3 要素 array が
# comment 除去後も改行区切りで正しく load されることを確認。
# ============================================================
_case_9() (
  set -uo pipefail
  _cleanup_feature_envs
  unset HC_PROTECTED_PATHS 2>/dev/null || true
  _write_tmp_yml "protected_paths: [src, tests, scripts]    # 保護パス comment"
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  # 期待: $'src\ntests\nscripts' (comment が array 要素に混入しないこと)
  local expected
  expected=$'src\ntests\nscripts'
  if [ "$HC_PROTECTED_PATHS" != "$expected" ]; then
    printf 'expected [%s], got [%s]\n' "$expected" "$HC_PROTECTED_PATHS" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 10 (task-71 M2): stale_harness_detect default + env override
# config-loader.sh に feature_stale_harness_detect_enabled の default(true)+export を
# 追加した回帰防止。(a) yml/env 未設定でも HC_FEATURE_STALE_HARNESS_DETECT_ENABLED が
# default "true" で export され is_feature_enabled stale_harness_detect が exit 0、
# (b) env HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false で exit 1 (toggle が効く)。
# default 不在だと (a) の export が空になり、--summary / bypass 案内が機能しない。
# ============================================================
_case_10() (
  set -uo pipefail
  _cleanup_feature_envs
  unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED 2>/dev/null || true
  # yml に該当 key 不在 (default に依存させる)
  _write_tmp_yml "task_dir: docs/tasks"
  export HC_CONFIG_PATH="$TMP_YML"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  if ! declare -f is_feature_enabled >/dev/null 2>&1; then
    printf 'SKIP: is_feature_enabled not found\n' >&2
    return 1
  fi
  # (a) default true が export されていること (空でないこと = M2 の本丸)
  if [ "${HC_FEATURE_STALE_HARNESS_DETECT_ENABLED:-}" != "true" ]; then
    printf 'expected default export [true], got [%s]\n' "${HC_FEATURE_STALE_HARNESS_DETECT_ENABLED:-<unset>}" >&2
    return 1
  fi
  if ! is_feature_enabled "stale_harness_detect"; then
    printf 'default should be ON (exit 0)\n' >&2
    return 1
  fi
  # (b) env false で OFF (exit 1) になること
  if HC_FEATURE_STALE_HARNESS_DETECT_ENABLED="false" is_feature_enabled "stale_harness_detect"; then
    printf 'env false should disable (exit 1)\n' >&2
    return 1
  fi
  return 0
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

if _case_7 2>/dev/null; then _record PASS 7 "task-64: 行末コメント strip → clean export (10)"
else                         _record FAIL 7 "task-64: 行末コメント strip → clean export (10)"
fi

if _case_8 2>/dev/null; then _record PASS 8 "task-64: double-quote 値内 # 保護 (URL fragment)"
else                         _record FAIL 8 "task-64: double-quote 値内 # 保護 (URL fragment)"
fi

if _case_9 2>/dev/null; then _record PASS 9 "task-64: inline array + 行末コメント strip 不変"
else                         _record FAIL 9 "task-64: inline array + 行末コメント strip 不変"
fi

if _case_10 2>/dev/null; then _record PASS 10 "task-71 M2: stale_harness_detect default true export + env false disables"
else                          _record FAIL 10 "task-71 M2: stale_harness_detect default true export + env false disables"
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
