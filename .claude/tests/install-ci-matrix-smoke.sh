#!/usr/bin/env bash
# .claude/tests/install-ci-matrix-smoke.sh — task-93 (P2-2、Step 4)
#
# 目的:
#   install.sh §5.6 の `.github/workflows/harness-smoke.yml` create-if-absent 配布
#   (matrix 2 preset × 5 category) を検証する。
#   設計 SSoT: docs/draft/install-ci-matrix-distribute.md §4.5 (Case A-E)。
#
# Case 一覧 (5 件):
#   A: fresh install で `.github/workflows/harness-smoke.yml` 配置 + matrix 定義完全
#      (preset: [team-default, strict] grep)
#   B: 既存 `harness-smoke.yml` は verbatim 保持 (md5 前後一致 + 上書きしない)
#   C: matrix key 完全性 5 点 grep:
#      (a) preset: [team-default, strict]
#      (b) category: [parity, behavior, budget, portability, stale-det]
#      (c) fail-fast: false
#      (d) if: failure() upload
#      (e) HC_DEFAULT_PRESET= (`_OVERRIDE` suffix 無し、findings-1 fix 検証、NG-guard 付)
#   D: --dry-run 時に .github/workflows/ 非配置 (mutation 0)
#   E: run-all-smokes.sh の `_get_smoke_category()` に本 smoke が portability 登録
#      (MED-1 fix、自己整合 grep)
#
# 重要制約 (install-mcp-servers-smoke.sh 先例踏襲):
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - 各 case 実装は subshell 関数化 ( set -uo pipefail; ... ) で局所化
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下 target に対して行い、repo 本体を汚さない
#
# 実行:
#   bash .claude/tests/install-ci-matrix-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
CI_SRC="${REPO_ROOT}/.github/workflows/harness-smoke.yml"
RUN_ALL_SMOKES="${REPO_ROOT}/.claude/tests/run-all-smokes.sh"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if [ ! -f "$CI_SRC" ]; then
  printf 'ERROR: source harness-smoke.yml not found: %s\n' "$CI_SRC" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "/tmp/install-ci-matrix-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

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

# md5 portable helper: Linux (md5sum) / macOS (md5 -q) 両対応
_md5() {
  local f="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$f" 2>/dev/null
  else
    printf ''
  fi
}

# ============================================================
# Case A: fresh install で `.github/workflows/harness-smoke.yml` 配置 + matrix 定義完全
# ============================================================
_case_a() (
  set -uo pipefail
  local tgt
  tgt="$(mktemp -d "${TMPDIR:-/tmp}/hirai-ci-matrix-A.XXXXXX")"
  trap 'rm -rf "$tgt" 2>/dev/null || true' RETURN
  local log="${TMP_DIR}/case-a.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  # yml 配置確認
  [ -f "$tgt/.github/workflows/harness-smoke.yml" ] || return 1
  # matrix preset grep (2 preset SSoT)
  grep -qE 'preset:[[:space:]]*\[team-default,[[:space:]]*strict\]' \
    "$tgt/.github/workflows/harness-smoke.yml" || return 1
)

# ============================================================
# Case B: 既存 `harness-smoke.yml` は verbatim 保持 (md5 前後一致)
# ============================================================
_case_b() (
  set -uo pipefail
  local tgt
  tgt="$(mktemp -d "${TMPDIR:-/tmp}/hirai-ci-matrix-B.XXXXXX")"
  trap 'rm -rf "$tgt" 2>/dev/null || true' RETURN
  # 事前に既存 yml を配置 (project 保有シナリオ)
  mkdir -p "$tgt/.github/workflows"
  cat > "$tgt/.github/workflows/harness-smoke.yml" <<'EOF'
# Existing project harness-smoke.yml — must NOT be overwritten by install.sh
name: legacy-harness-smoke
on: {}
jobs:
  legacy: { runs-on: ubuntu-latest, steps: [{ run: "echo legacy" }] }
EOF
  local before
  before=$(_md5 "$tgt/.github/workflows/harness-smoke.yml")
  [ -n "$before" ] || return 1
  local log="${TMP_DIR}/case-b.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  local after
  after=$(_md5 "$tgt/.github/workflows/harness-smoke.yml")
  # md5 前後一致 (verbatim 保持)
  [ "$before" = "$after" ] || return 1
  # skip echo が出る (install.sh §5.6)
  grep -q 'harness-smoke.yml exists.*skip' "$log" || return 1
)

# ============================================================
# Case C: matrix key 完全性 5 点 grep + `_OVERRIDE` NG-guard
# ============================================================
_case_c() (
  set -uo pipefail
  local tgt
  tgt="$(mktemp -d "${TMPDIR:-/tmp}/hirai-ci-matrix-C.XXXXXX")"
  trap 'rm -rf "$tgt" 2>/dev/null || true' RETURN
  local log="${TMP_DIR}/case-c.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  local yml="$tgt/.github/workflows/harness-smoke.yml"
  [ -f "$yml" ] || return 1
  # (a) matrix preset = [team-default, strict]
  grep -qE 'preset:[[:space:]]*\[team-default,[[:space:]]*strict\]' "$yml" || return 1
  # (b) matrix category = 5 値 [parity, behavior, budget, portability, stale-det]
  grep -qE 'category:[[:space:]]*\[parity,[[:space:]]*behavior,[[:space:]]*budget,[[:space:]]*portability,[[:space:]]*stale-det\]' "$yml" || return 1
  # (c) fail-fast: false (10 job signal 独立)
  grep -q 'fail-fast:[[:space:]]*false' "$yml" || return 1
  # (d) if: failure() (artifact upload 条件)
  grep -q 'if:[[:space:]]*failure()' "$yml" || return 1
  # (e) HC_DEFAULT_PRESET= (config-loader.sh:353 SSoT)
  grep -q 'HC_DEFAULT_PRESET=' "$yml" || return 1
  # NG-guard: `_OVERRIDE` suffix は存在してはならない (findings-1 fix)
  ! grep -q 'HC_DEFAULT_PRESET_OVERRIDE' "$yml" || return 1
)

# ============================================================
# Case D: --dry-run 時に .github/workflows/ 非配置 (mutation 0)
# ============================================================
_case_d() (
  set -uo pipefail
  local tgt
  tgt="$(mktemp -d "${TMPDIR:-/tmp}/hirai-ci-matrix-D.XXXXXX")"
  trap 'rm -rf "$tgt" 2>/dev/null || true' RETURN
  local log="${TMP_DIR}/case-d.log"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-mcp --no-docs >"$log" 2>&1 || return 1
  # dry-run 契約: .github/workflows/ dir も harness-smoke.yml も配置されない
  [ ! -d "$tgt/.github/workflows" ] || return 1
  [ ! -f "$tgt/.github/workflows/harness-smoke.yml" ] || return 1
)

# ============================================================
# Case E: run-all-smokes.sh の `_get_smoke_category()` に本 smoke が portability 登録
#         (MED-1 fix、install.sh 経路 smoke と同分類、自己整合 grep)
#
#   注: 本 case は run-all-smokes.sh の _get_smoke_category() の portability arm に
#   `install-ci-matrix-smoke` が登録されていることを検証する。draft §4.5 案 3 参照。
# ============================================================
_case_e() (
  set -uo pipefail
  [ -f "$RUN_ALL_SMOKES" ] || return 1
  # --list output の portability セクションに本 smoke が現れる
  # 注: awk range `/A/,/B/` は同一行が両端に match すると 1 行に潰れる (`[portability]` が
  #     `^\[portability\]` と `^\[` の両方に match するため). state machine で block 抽出する.
  bash "$RUN_ALL_SMOKES" --list 2>/dev/null \
    | awk '/^\[portability\]/ { in_block=1; next } /^\[/ { in_block=0 } in_block' \
    | grep -q 'install-ci-matrix-smoke' || return 1
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-ci-matrix-smoke (task-93 Step 4) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "fresh install で harness-smoke.yml 配置 + preset SSoT grep"
else                         _record FAIL A "fresh install で harness-smoke.yml 配置 + preset SSoT grep"; fi

if _case_b 2>/dev/null; then _record PASS B "既存 harness-smoke.yml verbatim 保持 (md5 前後一致 + skip echo)"
else                         _record FAIL B "既存 harness-smoke.yml verbatim 保持 (md5 前後一致 + skip echo)"; fi

if _case_c 2>/dev/null; then _record PASS C "matrix key 5 点 grep (preset/category/fail-fast/if failure/HC_DEFAULT_PRESET) + _OVERRIDE NG-guard"
else                         _record FAIL C "matrix key 5 点 grep (preset/category/fail-fast/if failure/HC_DEFAULT_PRESET) + _OVERRIDE NG-guard"; fi

if _case_d 2>/dev/null; then _record PASS D "--dry-run で .github/workflows/ 非配置 (mutation 0)"
else                         _record FAIL D "--dry-run で .github/workflows/ 非配置 (mutation 0)"; fi

if _case_e 2>/dev/null; then _record PASS E "run-all-smokes.sh の portability カテゴリで本 smoke discover"
else                         _record FAIL E "run-all-smokes.sh の portability カテゴリで本 smoke discover"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
