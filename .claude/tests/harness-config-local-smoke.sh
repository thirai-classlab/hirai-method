#!/usr/bin/env bash
# .claude/tests/harness-config-local-smoke.sh — task-55 (案 B-1)
#
# 目的:
#   harness-config.local.yml (project 固有 override 専用、rsync 除外) を
#   config-loader.sh が SSoT harness-config.yml と env の間で load することを検証する。
#
#   precedence (高 → 低):
#     env(HC_*) > harness-config.local.yml > harness-config.yml (SSoT) > hardcoded default
#
#   さらに install.sh が local.yml を --update / --force で rsync 除外し
#   project 固有値を温存することを検証する。
#
# Case 一覧:
#   A: local.yml に docs_approved_dir: design → config-loader が design を解決
#   B: SSoT yml と local.yml で同 key 衝突 → local.yml が優先 (SSoT に勝つ)
#   C: local.yml 不在 → SSoT yml のみで graceful 動作 (現状維持、portable)
#   D: precedence env > local.yml (env HC_* が local.yml に勝つ)
#   E: precedence local.yml > SSoT (B の別 key 検証、task_dir で確認)
#   F: install.sh --update で local.yml が rsync 除外される (温存)
#   G: install.sh RSYNC_EXCLUDES に harness-config.local.yml が含まれる (静的検査)
#   H: SSoT 側のみに存在する新 key は local.yml 不在でも load される (回帰なし)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応
#   - test 間 env 汚染防止 (各 case 後に HC_* unset)
#
# 実行:
#   bash .claude/tests/harness-config-local-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"
INSTALL_SH="${REPO_ROOT}/install.sh"

if [ ! -f "$CONFIG_LOADER" ]; then
  printf 'ERROR: config-loader.sh not found: %s\n' "$CONFIG_LOADER" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "/tmp/harness-config-local-smoke.XXXXXX")"
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

# 一時 .claude/ レイアウトを作り SSoT yml + (任意) local.yml を配置するヘルパー。
# $1 = SSoT yml 内容、$2 = local.yml 内容 (空なら local.yml を作らない)
# 戻り: CFG_DIR/.claude/harness-config.yml を指す HC_CONFIG_PATH を export 可能にする
_setup_layout() {
  local ssot="$1" local_yml="${2:-}"
  CFG_DIR="${TMP_DIR}/layout-$$-$RANDOM"
  mkdir -p "${CFG_DIR}/.claude"
  printf '%s\n' "$ssot" > "${CFG_DIR}/.claude/harness-config.yml"
  if [ -n "$local_yml" ]; then
    printf '%s\n' "$local_yml" > "${CFG_DIR}/.claude/harness-config.local.yml"
  fi
}

_cleanup_envs() {
  unset HC_CONFIG_PATH 2>/dev/null || true
  unset HC_DOCS_APPROVED_DIR 2>/dev/null || true
  unset HC_TASK_DIR 2>/dev/null || true
  unset HC_DRAFT_DIR 2>/dev/null || true
}

# ============================================================
# Case A: local.yml の docs_approved_dir: design を config-loader が解決
# ============================================================
_case_a() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "docs_approved_dir: \"\"" "docs_approved_dir: design"
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_DOCS_APPROVED_DIR" = "design" ]
)

# ============================================================
# Case B: SSoT と local.yml で同 key 衝突 → local.yml が優先
# ============================================================
_case_b() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "docs_approved_dir: ssot-value" "docs_approved_dir: local-value"
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_DOCS_APPROVED_DIR" = "local-value" ]
)

# ============================================================
# Case C: local.yml 不在 → SSoT yml のみで graceful 動作
# ============================================================
_case_c() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "docs_approved_dir: ssot-only" ""   # local.yml 作らない
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_DOCS_APPROVED_DIR" = "ssot-only" ]
)

# ============================================================
# Case D: precedence env > local.yml
# ============================================================
_case_d() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "docs_approved_dir: ssot-value" "docs_approved_dir: local-value"
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  export HC_DOCS_APPROVED_DIR="env-value"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_DOCS_APPROVED_DIR" = "env-value" ]
)

# ============================================================
# Case E: precedence local.yml > SSoT (task_dir で確認)
# ============================================================
_case_e() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "task_dir: docs/tasks" "task_dir: docs/tickets"
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_TASK_DIR" = "docs/tickets" ]
)

# ============================================================
# Case F: install.sh --update で local.yml が温存 (rsync 除外)
# 実 install を /tmp で実行し、既存 local.yml が上書きされないことを確認
# ============================================================
_case_f() (
  set -uo pipefail
  _cleanup_envs
  [ -f "$INSTALL_SH" ] || return 1
  command -v rsync >/dev/null 2>&1 || return 1
  local tgt="${TMP_DIR}/update-target-$$"
  mkdir -p "${tgt}/.claude"
  # 既存 target に local.yml (project 固有値) を置く
  printf 'docs_approved_dir: project-design\n' > "${tgt}/.claude/harness-config.local.yml"
  # --update 実行 (cross-repo ではなく /tmp 配下なので sandbox 制約外、smoke 専用)
  bash "$INSTALL_SH" "$tgt" --update >/dev/null 2>&1 || return 1
  # local.yml が温存されているか (上書きされていない)
  [ -f "${tgt}/.claude/harness-config.local.yml" ] || return 1
  grep -q 'project-design' "${tgt}/.claude/harness-config.local.yml"
)

# ============================================================
# Case G: install.sh RSYNC_EXCLUDES に harness-config.local.yml が含まれる
# ============================================================
_case_g() (
  set -uo pipefail
  [ -f "$INSTALL_SH" ] || return 1
  grep -q 'exclude=harness-config.local.yml' "$INSTALL_SH"
)

# ============================================================
# Case H: SSoT 側のみの新 key は local.yml 不在でも load (回帰なし)
# ============================================================
_case_h() (
  set -uo pipefail
  _cleanup_envs
  _setup_layout "task_dir: docs/custom" ""
  export HC_CONFIG_PATH="${CFG_DIR}/.claude/harness-config.yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "$HC_TASK_DIR" = "docs/custom" ]
)

# ============================================================
# 実行
# ============================================================
printf '\n=== harness-config-local-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "local.yml docs_approved_dir=design 解決"
else                         _record FAIL A "local.yml docs_approved_dir=design 解決"; fi

if _case_b 2>/dev/null; then _record PASS B "local.yml が SSoT に優先 (同 key 衝突)"
else                         _record FAIL B "local.yml が SSoT に優先 (同 key 衝突)"; fi

if _case_c 2>/dev/null; then _record PASS C "local.yml 不在で SSoT のみ graceful 動作"
else                         _record FAIL C "local.yml 不在で SSoT のみ graceful 動作"; fi

if _case_d 2>/dev/null; then _record PASS D "precedence env > local.yml"
else                         _record FAIL D "precedence env > local.yml"; fi

if _case_e 2>/dev/null; then _record PASS E "precedence local.yml > SSoT (task_dir)"
else                         _record FAIL E "precedence local.yml > SSoT (task_dir)"; fi

if _case_f 2>/dev/null; then _record PASS F "install.sh --update で local.yml 温存"
else                         _record FAIL F "install.sh --update で local.yml 温存"; fi

if _case_g 2>/dev/null; then _record PASS G "RSYNC_EXCLUDES に harness-config.local.yml"
else                         _record FAIL G "RSYNC_EXCLUDES に harness-config.local.yml"; fi

if _case_h 2>/dev/null; then _record PASS H "SSoT のみの key も local.yml 不在で load"
else                         _record FAIL H "SSoT のみの key も local.yml 不在で load"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
