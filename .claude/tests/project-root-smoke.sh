#!/usr/bin/env bash
# project-root-smoke.sh — C #11 smoke test for resolve_project_root() fallback chain
#
# 検証する fallback 順序:
#   1. HC_PROJECT_ROOT          ... env override (HIRAI 固有、CI / test 用)
#   2. git rev-parse --toplevel ... 標準的な project root 解決
#   3. CLAUDE_PROJECT_DIR       ... Claude Code hook 標準注入 (C #11 で追加)
#   4. pwd                      ... fallback (上記全て不在時)
#
# dual-mode-portability-smoke.sh が HC_PROJECT_ROOT / git / pwd を既に網羅しているため、
# 本 smoke は CLAUDE_PROJECT_DIR 挿入による order 整合性を中心に検証する。
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - 各 case 関数は ( set -uo pipefail; ... ) で run_case が wrap する
#
# 実行:
#   bash .claude/tests/project-root-smoke.sh
#
# 終了コード: 0 = 全 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$PROJECT_ROOT/.claude/hooks/lib/project-root.sh"
TMP_DIR=$(mktemp -d "/tmp/project-root-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

# macOS /tmp -> /private/tmp の symlink 差を許容する比較
path_eq() {
  local expected="$1" actual="$2"
  [ "$expected" = "$actual" ] || [ "/private${expected}" = "$actual" ] || [ "$expected" = "/private${actual}" ]
}

# === Case 1: HC_PROJECT_ROOT が最優先 (CLAUDE_PROJECT_DIR より上) ===
case_1() {
  local fake_root="$TMP_DIR/case1-hc-root"
  local decoy="$TMP_DIR/case1-claude-decoy"
  mkdir -p "$fake_root" "$decoy"
  local actual
  actual=$(HC_PROJECT_ROOT="$fake_root" CLAUDE_PROJECT_DIR="$decoy" \
    bash -c "source '$LIB'; resolve_project_root")
  if ! path_eq "$fake_root" "$actual"; then
    printf 'expected %s, got %s\n' "$fake_root" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 2: HC 不在 + git repo 内 → git rev-parse 優先 (CLAUDE_PROJECT_DIR より上) ===
case_2() {
  local decoy="$TMP_DIR/case2-claude-decoy"
  mkdir -p "$decoy"
  local actual
  actual=$(cd "$PROJECT_ROOT" && unset HC_PROJECT_ROOT && \
    CLAUDE_PROJECT_DIR="$decoy" bash -c "source '$LIB'; resolve_project_root")
  if [ "$actual" != "$PROJECT_ROOT" ]; then
    printf 'expected %s, got %s\n' "$PROJECT_ROOT" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 3: HC / git 不在 + CLAUDE_PROJECT_DIR 有 → CLAUDE_PROJECT_DIR 採用 ===
case_3() {
  local nogit="$TMP_DIR/case3-nogit"
  local claude_dir="$TMP_DIR/case3-claude-root"
  mkdir -p "$nogit" "$claude_dir"
  local actual
  actual=$(cd "$nogit" && unset HC_PROJECT_ROOT && \
    CLAUDE_PROJECT_DIR="$claude_dir" bash -c "source '$LIB'; resolve_project_root")
  if ! path_eq "$claude_dir" "$actual"; then
    printf 'expected %s, got %s\n' "$claude_dir" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 4: 全部不在 → pwd fallback ===
case_4() {
  local nogit="$TMP_DIR/case4-nogit"
  mkdir -p "$nogit"
  local actual
  actual=$(cd "$nogit" && unset HC_PROJECT_ROOT && unset CLAUDE_PROJECT_DIR && \
    bash -c "source '$LIB'; resolve_project_root")
  if ! path_eq "$nogit" "$actual"; then
    printf 'expected %s, got %s\n' "$nogit" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 5: CLAUDE_PROJECT_DIR が指す path が不在 dir なら pwd へ skip ===
case_5() {
  local nogit="$TMP_DIR/case5-nogit"
  mkdir -p "$nogit"
  local bogus="/nonexistent/$$-claude-dir"
  local actual
  actual=$(cd "$nogit" && unset HC_PROJECT_ROOT && \
    CLAUDE_PROJECT_DIR="$bogus" bash -c "source '$LIB'; resolve_project_root")
  if ! path_eq "$nogit" "$actual"; then
    printf 'expected %s (pwd fallback), got %s\n' "$nogit" "$actual" >&2
    return 1
  fi
  return 0
}

printf '===== C #11 project-root CLAUDE_PROJECT_DIR fallback smoke =====\n'
run_case 1 'HC_PROJECT_ROOT が CLAUDE_PROJECT_DIR より優先' case_1
run_case 2 'git rev-parse が CLAUDE_PROJECT_DIR より優先' case_2
run_case 3 'HC/git 不在で CLAUDE_PROJECT_DIR 採用' case_3
run_case 4 '全部不在で pwd fallback' case_4
run_case 5 'CLAUDE_PROJECT_DIR が不在 dir なら pwd fallback' case_5

printf '\n===== Result =====\n'
printf 'PASS: %d / 5\n' "$PASS"
printf 'FAIL: %d / 5\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
