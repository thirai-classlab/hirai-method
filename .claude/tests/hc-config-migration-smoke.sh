#!/usr/bin/env bash
# .claude/tests/hc-config-migration-smoke.sh — task-69 Step 4 (local override warning + key migration) smoke
#
# 目的:
#   Step 4 で追加する 2 機構を検証する。
#   (1) config-loader.sh の unknown_local_key warning:
#       harness-config.local.yml にのみ存在し SSoT harness-config.yml に無い top-level key を
#       source 時に stderr へ `unknown_local_key` warning として表示する (誤字検出)。
#   (2) hc-config.sh の deprecated_keys table + `migrate` subcommand:
#       deprecated table に登録された old key を yml から検出 → new key に値を移行 → 移行ログを出力。
#       移行後も old key が残っていれば非0 exit (smoke fail trigger)。
#       Step1-2 の cmd_list (parity) を壊さないこと。
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - test isolation: /tmp に temp yml / local.yml を作り --config / HC_LOCAL_CONFIG_PATH で差し替える
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)
#
# 起源: task-69 Step 4、設計 SSoT: docs/draft/harness-review-remediation-plan.md §4.1
#       「local override の扱い」「migration の扱い」

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"

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

# temp 作業ディレクトリ (各 case が自前で mktemp -d する方が isolation しやすい)
_mk_tmpdir() {
  mktemp -d "/tmp/hc-config-migration-smoke.XXXXXX"
}

# ============================================================
# Case 1: unknown_local_key warning — local.yml にのみ存在する key を warning 表示
# ============================================================
_case_1() (
  set -uo pipefail
  local td
  td=$(_mk_tmpdir) || return 1
  # cleanup
  trap 'rm -rf "$td"' EXIT

  # SSoT yml (known key 1 件)
  printf 'task_dir: docs/tasks\n' > "${td}/harness-config.yml"
  # local.yml: known override 1 件 + unknown 1 件 (typo 想定)
  printf 'task_dir: docs/tickets\ntsak_dir: docs/oops\n' > "${td}/harness-config.local.yml"

  # config-loader.sh を source して stderr を捕捉
  local err
  err=$(
    HC_CONFIG_PATH="${td}/harness-config.yml" \
    HC_LOCAL_CONFIG_PATH="${td}/harness-config.local.yml" \
    bash -c "source '${CONFIG_LOADER}' >/dev/null" 2>&1
  )

  printf 'Case 1: stderr=%s\n' "$err" >&2

  # unknown_local_key warning に typo key 名 (tsak_dir) が含まれること
  case "$err" in
    *unknown_local_key*tsak_dir*|*tsak_dir*unknown_local_key*) return 0 ;;
    *) printf 'Case 1: unknown_local_key warning for tsak_dir not found\n' >&2; return 1 ;;
  esac
)

# ============================================================
# Case 2: known local key は warning を出さない (誤検知なし)
# ============================================================
_case_2() (
  set -uo pipefail
  local td
  td=$(_mk_tmpdir) || return 1
  trap 'rm -rf "$td"' EXIT

  printf 'task_dir: docs/tasks\ndraft_dir: docs/draft\n' > "${td}/harness-config.yml"
  # local.yml: known key のみ
  printf 'task_dir: docs/tickets\n' > "${td}/harness-config.local.yml"

  local err
  err=$(
    HC_CONFIG_PATH="${td}/harness-config.yml" \
    HC_LOCAL_CONFIG_PATH="${td}/harness-config.local.yml" \
    bash -c "source '${CONFIG_LOADER}' >/dev/null" 2>&1
  )

  printf 'Case 2: stderr=%s\n' "$err" >&2

  case "$err" in
    *unknown_local_key*) printf 'Case 2: false positive unknown_local_key for known key\n' >&2; return 1 ;;
    *) return 0 ;;
  esac
)

# ============================================================
# Case 3: local.yml 不在環境は no-op (warning なし、graceful)
# ============================================================
_case_3() (
  set -uo pipefail
  local td
  td=$(_mk_tmpdir) || return 1
  trap 'rm -rf "$td"' EXIT

  printf 'task_dir: docs/tasks\n' > "${td}/harness-config.yml"
  # local.yml は作らない

  local err
  err=$(
    HC_CONFIG_PATH="${td}/harness-config.yml" \
    HC_LOCAL_CONFIG_PATH="${td}/harness-config.local.yml" \
    bash -c "source '${CONFIG_LOADER}' >/dev/null" 2>&1
  )

  case "$err" in
    *unknown_local_key*) printf 'Case 3: unexpected unknown_local_key on missing local.yml\n' >&2; return 1 ;;
    *) return 0 ;;
  esac
)

# ============================================================
# Case 4: migrate — deprecated old key が yml に無ければ "no migration" + exit 0
# ============================================================
_case_4() (
  set -uo pipefail
  local td
  td=$(_mk_tmpdir) || return 1
  trap 'rm -rf "$td"' EXIT

  # deprecated old key を含まない yml
  printf 'task_dir: docs/tasks\n' > "${td}/harness-config.yml"

  local out rc
  out=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "${HC_CONFIG_SCRIPT}" --config "${td}/harness-config.yml" --migrate 2>&1)
  rc=$?

  printf 'Case 4: rc=%d out=%s\n' "$rc" "$out" >&2
  [ "$rc" -eq 0 ]
)

# ============================================================
# Case 5: migrate — old key 検出 → new key へ値移行 + 移行ログ + exit 0
# ============================================================
# deprecated_keys table に少なくとも 1 entry が存在する前提で、
# その old key を yml に注入して migrate が new key に値を移し old key を消すことを検証する。
_case_5() (
  set -uo pipefail
  local td
  td=$(_mk_tmpdir) || return 1
  trap 'rm -rf "$td"' EXIT

  # hc-config.sh が公開する deprecated mapping の先頭 entry を取得
  # (実装は `--migrate --dry-run` 不要、deprecated table を smoke から直接読めるよう
  #  hc-config.sh に `--list-deprecated` を持たせる。"old -> new" の行を期待。)
  # 注: --config <path> は file 存在を要求するため、先に dummy yml を作る。
  printf 'task_dir: docs/tasks\n' > "${td}/harness-config.yml"
  local dep_line old_key new_key
  dep_line=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "${HC_CONFIG_SCRIPT}" --config "${td}/harness-config.yml" --list-deprecated 2>/dev/null \
    | grep -E '\->' | head -n 1)
  if [ -z "$dep_line" ]; then
    printf 'Case 5: no deprecated_keys entry (table empty) — skip-as-pass (placeholder seed needed)\n' >&2
    # deprecated table が空でも実装としては正しい (将来の rename 用)。
    # ただし Step 4 では最低 1 seed entry を期待するため fail。
    return 1
  fi
  old_key=$(printf '%s' "$dep_line" | awk -F'->' '{gsub(/[[:space:]]/,"",$1); print $1}')
  new_key=$(printf '%s' "$dep_line" | awk -F'->' '{gsub(/[[:space:]]/,"",$2); print $2}')
  printf 'Case 5: deprecated %s -> %s\n' "$old_key" "$new_key" >&2

  # yml に old key を注入 (new key は存在しない状態)
  printf '%s: migrated_value_xyz\ntask_dir: docs/tasks\n' "$old_key" > "${td}/harness-config.yml"

  local out rc
  out=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "${HC_CONFIG_SCRIPT}" --config "${td}/harness-config.yml" --migrate 2>&1)
  rc=$?
  printf 'Case 5: rc=%d out=%s\n' "$rc" "$out" >&2

  # 移行後 yml: old key 消失 + new key に値が移っている
  local has_old has_new_val
  has_old=$(grep -cE "^${old_key}:" "${td}/harness-config.yml" || true)
  has_new_val=$(grep -E "^${new_key}:" "${td}/harness-config.yml" | grep -c 'migrated_value_xyz' || true)

  local ok=0
  [ "$rc" -ne 0 ] && { printf 'Case 5: migrate exit != 0\n' >&2; ok=1; }
  [ "$has_old" -ne 0 ] && { printf 'Case 5: old key %s still present after migrate\n' "$old_key" >&2; ok=1; }
  [ "$has_new_val" -eq 0 ] && { printf 'Case 5: new key %s did not receive migrated value\n' "$new_key" >&2; ok=1; }
  case "$out" in
    *migrat*) : ;;
    *) printf 'Case 5: migration log line not found in output\n' >&2; ok=1 ;;
  esac

  [ "$ok" -eq 0 ]
)

# ============================================================
# Case 6: migrate 後の parity 不変 — Step1-2 cmd_list を壊していない
# ============================================================
# real SSoT yml で --list が yml key set と一致し続けることを確認 (regression guard)。
_case_6() (
  set -uo pipefail
  local yml="${REPO_ROOT}/.claude/harness-config.yml"
  local yml_count list_count
  yml_count=$(grep -E '^[a-z_][a-zA-Z0-9_]*:' "$yml" | sed -E 's/:.*$//' | sort -u | grep -c .)
  list_count=$(bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null \
    | grep -E '^[a-z_][a-zA-Z0-9_]*[[:space:]]' | awk '{print $1}' | sort -u | grep -c .)
  printf 'Case 6: yml_count=%d list_count=%d\n' "$yml_count" "$list_count" >&2
  [ "$yml_count" -eq "$list_count" ]
)

# --- run ---
printf '=== hc-config migration / local-warning smoke ===\n'

_case_1 && _record PASS 1 "unknown_local_key warning (local 専用 key を検出)" \
       || _record FAIL 1 "unknown_local_key warning (local 専用 key を検出)"
_case_2 && _record PASS 2 "known local key は warning なし (誤検知なし)" \
       || _record FAIL 2 "known local key は warning なし (誤検知なし)"
_case_3 && _record PASS 3 "local.yml 不在は no-op (graceful)" \
       || _record FAIL 3 "local.yml 不在は no-op (graceful)"
_case_4 && _record PASS 4 "migrate: deprecated key 不在で no-op + exit 0" \
       || _record FAIL 4 "migrate: deprecated key 不在で no-op + exit 0"
_case_5 && _record PASS 5 "migrate: old key 検出 → new key 移行 + ログ + old 消失" \
       || _record FAIL 5 "migrate: old key 検出 → new key 移行 + ログ + old 消失"
_case_6 && _record PASS 6 "migrate 機構追加後も --list parity 不変 (regression)" \
       || _record FAIL 6 "migrate 機構追加後も --list parity 不変 (regression)"

printf '\n=== Result: %d PASS, %d FAIL ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
