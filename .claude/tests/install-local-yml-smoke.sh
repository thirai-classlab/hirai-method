#!/usr/bin/env bash
# .claude/tests/install-local-yml-smoke.sh — HOTFIX-1 (install-immediately-usable-redesign-20260618 §9.1 / §4.1 対策 B)
#
# 目的:
#   install.sh §6.4 consuming repo preset bootstrap を検証する。
#   consuming repo への install 時に harness-config.local.yml が create-if-absent
#   生成され (default_preset: team-default + guard toggle 8 件 individual true =
#   feature 4 + review_required 4)、既存 local.yml は verbatim 保持される (冪等)
#   ことを確認する。review_required 4 件は enforcement_matrix の team-default 期待
#   (presets.team-default: true) との自己矛盾防止に必須 (欠くと consuming repo で
#   enforcement-mismatch-smoke Case 3 が UNDOCUMENTED mismatch FAIL する)。
#
# Case 一覧:
#   A: 空 target に新規 install → local.yml 生成 + team-default + 8 toggle true
#   B: A の target に --update 再実行 → local.yml が byte 単位で不変 (冪等)
#   C: custom 内容の local.yml を事前配置 → --update 後も verbatim 保持
#   D: --dry-run では local.yml が生成されない (mutation ゼロ)
#   E: install.sh §6.4 に self-install guard (物理 path 比較) が存在する (静的検査)
#   F: 生成済 local.yml を config-loader.sh が実際に load し guard toggle が true 化
#   G: 生成 local.yml 下で target の enforcement-mismatch-smoke.sh が全 PASS
#      (preset=team-default と実効 toggle の自己矛盾なし = HOTFIX-1 regression 防止)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下の target に対して行い、repo 本体を汚さない
#
# 実行:
#   bash .claude/tests/install-local-yml-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh 前提依存)\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "/tmp/install-local-yml-smoke.XXXXXX")"
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

# config-loader 検証 case 用: 外側 session の HC_* env 残留が
# genuine env preset として local.yml を打ち消すのを防ぐ
_cleanup_envs() {
  unset HC_CONFIG_PATH 2>/dev/null || true
  unset HC_LOCAL_CONFIG_PATH 2>/dev/null || true
  unset HC_DEFAULT_PRESET 2>/dev/null || true
  unset HC_FEATURE_TASK_RULE_GUARD_ENABLED 2>/dev/null || true
  unset HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED 2>/dev/null || true
  unset HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED 2>/dev/null || true
  unset HC_FEATURE_GATEGUARD_ENABLED 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_DESIGN 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_TEST 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_MODULE 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_SYSTEM 2>/dev/null || true
}

# Case A/B は同一 target を共用する (A: 新規 install → B: --update 冪等)。
# B は A の成果物に依存するため実行順を A → B に固定する。
TGT_AB="${TMP_DIR}/target-ab"

# ============================================================
# Case A: 空 target に新規 install → local.yml 生成 + 内容 assert
# ============================================================
_case_a() (
  set -uo pipefail
  mkdir -p "$TGT_AB"
  bash "$INSTALL_SH" "$TGT_AB" --no-mcp --no-docs >/dev/null 2>&1 || return 1
  local yml="${TGT_AB}/.claude/harness-config.local.yml"
  [ -f "$yml" ] || return 1
  grep -q '^default_preset: team-default$' "$yml" || return 1
  grep -q '^feature_task_rule_guard_enabled: true$' "$yml" || return 1
  grep -q '^feature_draft_flow_guard_enabled: true$' "$yml" || return 1
  grep -q '^feature_workflow_enforcement_enabled: true$' "$yml" || return 1
  grep -q '^feature_gateguard_enabled: true$' "$yml" || return 1
  # review_required 4 件: 欠くと enforcement-mismatch-smoke Case 3 FAIL (team-default 自己矛盾)
  grep -q '^review_required_design: true$' "$yml" || return 1
  grep -q '^review_required_test: true$' "$yml" || return 1
  grep -q '^review_required_module: true$' "$yml" || return 1
  grep -q '^review_required_system: true$' "$yml"
)

# ============================================================
# Case B: --update 再実行 → local.yml が byte 単位で不変 (冪等)
# ============================================================
_case_b() (
  set -uo pipefail
  local yml="${TGT_AB}/.claude/harness-config.local.yml"
  [ -f "$yml" ] || return 1
  local ref="${TMP_DIR}/case-b-ref.yml"
  cp "$yml" "$ref"
  bash "$INSTALL_SH" "$TGT_AB" --update >/dev/null 2>&1 || return 1
  cmp -s "$ref" "$yml"
)

# ============================================================
# Case C: custom local.yml を事前配置 → --update 後も verbatim 保持
# ============================================================
_case_c() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-c"
  mkdir -p "${tgt}/.claude"
  local yml="${tgt}/.claude/harness-config.local.yml"
  printf '# project custom override (smoke)\ndefault_preset: strict\ndocs_approved_dir: design\n' > "$yml"
  local ref="${TMP_DIR}/case-c-ref.yml"
  cp "$yml" "$ref"
  bash "$INSTALL_SH" "$tgt" --update >/dev/null 2>&1 || return 1
  cmp -s "$ref" "$yml"
)

# ============================================================
# Case D: --dry-run では local.yml 生成されない (mutation ゼロ)
# ============================================================
_case_d() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-d"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-mcp --no-docs >/dev/null 2>&1 || return 1
  [ ! -f "${tgt}/.claude/harness-config.local.yml" ]
)

# ============================================================
# Case E: install.sh §6.4 に self-install guard が存在 (静的検査)
# 実 self-install は L128 die + backup mv がある為 /tmp 外で再現不可、
# 物理 path 比較 (pwd -P) と bootstrap skip の存在を grep で保証する
# ============================================================
_case_e() (
  set -uo pipefail
  grep -q 'consuming repo preset bootstrap' "$INSTALL_SH" || return 1
  grep -q 'pwd -P' "$INSTALL_SH" || return 1
  grep -q 'preset bootstrap skip' "$INSTALL_SH"
)

# ============================================================
# Case F: 生成済 local.yml を config-loader が load → toggle true 化
# ============================================================
_case_f() (
  set -uo pipefail
  [ -f "$CONFIG_LOADER" ] || return 1
  local yml="${TGT_AB}/.claude/harness-config.yml"
  [ -f "$yml" ] || return 1
  _cleanup_envs
  export HC_CONFIG_PATH="$yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "${HC_DEFAULT_PRESET:-}" = "team-default" ] || return 1
  [ "${HC_FEATURE_TASK_RULE_GUARD_ENABLED:-}" = "true" ] || return 1
  [ "${HC_FEATURE_GATEGUARD_ENABLED:-}" = "true" ] || return 1
  # review_required も local.yml override で runtime true 化されること
  [ "${HC_REVIEW_REQUIRED_TEST:-}" = "true" ] || return 1
  [ "${HC_REVIEW_REQUIRED_DESIGN:-}" = "true" ]
)

# ============================================================
# Case G: 生成 local.yml 下で target の enforcement-mismatch-smoke が全 PASS
# team-default 宣言と実効 toggle の自己矛盾 (docs_claim=block ∧ 実効 false ∧
# team-default disabled_reason 不在 = Case 3 UNDOCUMENTED mismatch) を検出する。
# harness sync checklist は consuming repo に smoke 全 PASS を要求するため、
# install 直後にこれが FAIL する regression を本 case で恒久防止する。
# ============================================================
_case_g() (
  set -uo pipefail
  local smoke="${TGT_AB}/.claude/tests/enforcement-mismatch-smoke.sh"
  [ -f "$smoke" ] || return 1
  _cleanup_envs
  bash "$smoke" >/dev/null 2>&1
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-local-yml-smoke (HOTFIX-1) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "新規 install で local.yml 生成 (team-default + 8 toggle true)"
else                         _record FAIL A "新規 install で local.yml 生成 (team-default + 8 toggle true)"; fi

if _case_b 2>/dev/null; then _record PASS B "--update 再実行で local.yml byte 不変 (冪等)"
else                         _record FAIL B "--update 再実行で local.yml byte 不変 (冪等)"; fi

if _case_c 2>/dev/null; then _record PASS C "custom local.yml 事前配置 → --update 後も verbatim 保持"
else                         _record FAIL C "custom local.yml 事前配置 → --update 後も verbatim 保持"; fi

if _case_d 2>/dev/null; then _record PASS D "--dry-run で local.yml 生成されない"
else                         _record FAIL D "--dry-run で local.yml 生成されない"; fi

if _case_e 2>/dev/null; then _record PASS E "install.sh §6.4 に self-install guard 存在 (静的)"
else                         _record FAIL E "install.sh §6.4 に self-install guard 存在 (静的)"; fi

if _case_f 2>/dev/null; then _record PASS F "config-loader が生成 local.yml を load (toggle true 化)"
else                         _record FAIL F "config-loader が生成 local.yml を load (toggle true 化)"; fi

if _case_g 2>/dev/null; then _record PASS G "target の enforcement-mismatch-smoke 全 PASS (team-default 自己矛盾なし)"
else                         _record FAIL G "target の enforcement-mismatch-smoke 全 PASS (team-default 自己矛盾なし)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
