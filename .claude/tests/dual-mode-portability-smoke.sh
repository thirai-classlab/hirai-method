#!/usr/bin/env bash
# dual-mode-portability-smoke.sh — task #12 W4 smoke test
#
# 4 cases:
#   Case 1: HC_PROJECT_ROOT=/tmp/<fake>     → resolve_project_root returns /tmp/<fake>
#   Case 2: env unset + in git repo         → returns git rev-parse --show-toplevel
#   Case 3: env unset + non-git dir         → returns pwd
#   Case 4: hook simulated from user-level path + HC_PROJECT_ROOT
#           → hook resolves PROJECT_ROOT to env value (not SCRIPT_DIR/../..)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップ
#
# 実行:
#   bash .claude/tests/dual-mode-portability-smoke.sh
#
# 終了コード: 0 = 4/4 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$PROJECT_ROOT/.claude/hooks/lib/project-root.sh"
HOOK_CHECK_SERENA="$PROJECT_ROOT/.claude/hooks/check-serena-mcp.sh"
TMP_DIR=$(mktemp -d "/tmp/dual-mode-portability-smoke.XXXXXX")
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

# === Case 1: env override ===
case_1() {
  local fake_root="$TMP_DIR/case1-fake"
  mkdir -p "$fake_root"
  local actual
  actual=$(HC_PROJECT_ROOT="$fake_root" bash -c "source '$LIB'; resolve_project_root")
  if [ "$actual" != "$fake_root" ]; then
    printf 'expected %s, got %s\n' "$fake_root" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 2: git rev-parse (inside this repo) ===
case_2() {
  # Run unset env from PROJECT_ROOT itself; git rev-parse should yield PROJECT_ROOT.
  local actual
  actual=$(cd "$PROJECT_ROOT" && unset HC_PROJECT_ROOT && bash -c "source '$LIB'; resolve_project_root")
  # macOS /private/tmp symlink可能性は repo path には無いため strict 比較
  if [ "$actual" != "$PROJECT_ROOT" ]; then
    printf 'expected %s, got %s\n' "$PROJECT_ROOT" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 3: pwd fallback (non-git dir) ===
case_3() {
  local nogit="$TMP_DIR/case3-nogit"
  mkdir -p "$nogit"
  # Ensure no .git in ancestors of $nogit
  # /tmp 配下に .git は存在しない前提
  local actual
  actual=$(cd "$nogit" && unset HC_PROJECT_ROOT && bash -c "source '$LIB'; resolve_project_root")
  # macOS では /tmp が /private/tmp の symlink (pwd は /tmp を返すが realpath 違い)
  # 両許容: $nogit or /private<nogit>
  if [ "$actual" != "$nogit" ] && [ "$actual" != "/private${nogit}" ]; then
    printf 'expected %s (or /private prefix), got %s\n' "$nogit" "$actual" >&2
    return 1
  fi
  return 0
}

# === Case 4: hook executed from user-level-style path + HC_PROJECT_ROOT ===
# Simulate user-level install: copy hook + lib into a temp tree mimicking
# ${HOME}/.claude/hooks/ layout, then invoke with HC_PROJECT_ROOT pointing
# to a separate "project" dir. Expect PROJECT_ROOT inside the hook = env value.
case_4() {
  local user_install="$TMP_DIR/case4-user-install"
  local target_project="$TMP_DIR/case4-target-project"
  mkdir -p "$user_install/.claude/hooks/lib"
  mkdir -p "$target_project"
  cp "$HOOK_CHECK_SERENA" "$user_install/.claude/hooks/check-serena-mcp.sh"
  cp "$LIB" "$user_install/.claude/hooks/lib/project-root.sh"
  chmod +x "$user_install/.claude/hooks/check-serena-mcp.sh"
  # Create .mcp.json missing serena in target_project so hook emits warning;
  # warning content does not matter — what matters is hook completes (no
  # silent crash from missing lib / wrong PROJECT_ROOT resolution).
  printf '%s\n' '{"mcpServers": {}}' > "$target_project/.mcp.json"
  local output
  output=$(HC_PROJECT_ROOT="$target_project" bash "$user_install/.claude/hooks/check-serena-mcp.sh" </dev/null 2>/dev/null)
  # Expect Serena warning (entry missing) — proves hook read target_project/.mcp.json
  if ! printf '%s' "$output" | grep -q 'Serena MCP'; then
    printf 'expected Serena MCP warning, got: %s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'system-reminder'; then
    return 1
  fi
  return 0
}

printf '===== task #12 W4 dual-mode-portability smoke =====\n'
run_case 1 'HC_PROJECT_ROOT env override' case_1
run_case 2 'git rev-parse --show-toplevel' case_2
run_case 3 'pwd fallback (non-git dir)' case_3
run_case 4 'user-level hook path + HC_PROJECT_ROOT' case_4

printf '\n===== Result =====\n'
printf 'PASS: %d / 4\n' "$PASS"
printf 'FAIL: %d / 4\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
