#!/usr/bin/env bash
# check-serena-mcp-smoke.sh — task #10 W2 smoke test
#
# 4 cases:
#   Case 1: .mcp.json に serena entry 存在 → silent (出力なし)
#   Case 2: .mcp.json に serena entry 不在 → 警告出力 (Serena MCP 文言含む)
#   Case 3: .mcp.json 自体不在 → 警告出力 (`.mcp.json` 文言含む)
#   Case 4: HC_CHECK_SERENA_ENABLED=false → silent (env override)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#
# 実行:
#   bash .claude/tests/check-serena-mcp-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/check-serena-mcp.sh"
TMP_DIR=$(mktemp -d "/tmp/check-serena-mcp-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# run_case <id> <desc> <test_fn>
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

# 共通: fake PROJECT_ROOT を作って hook をコピーする
# hook は `SCRIPT_DIR/../..` を PROJECT_ROOT として解決するので
# fake_root/.claude/hooks/check-serena-mcp.sh に置けば fake_root が PROJECT_ROOT になる。
setup_fake_root() {
  local fake_root="$1"
  mkdir -p "$fake_root/.claude/hooks"
  cp "$HOOK" "$fake_root/.claude/hooks/check-serena-mcp.sh"
  chmod +x "$fake_root/.claude/hooks/check-serena-mcp.sh"
}

# === Case 1: .mcp.json に serena entry 存在 → silent ===
case_1() {
  local fake_root="$TMP_DIR/case1"
  setup_fake_root "$fake_root"
  cat > "$fake_root/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "serena": {
      "command": "uvx",
      "args": ["--from", "git+https://github.com/oraios/serena", "serena"]
    }
  }
}
JSON
  local output
  output=$(bash "$fake_root/.claude/hooks/check-serena-mcp.sh" </dev/null 2>/dev/null)
  # 期待: 出力なし
  if [ -n "$output" ]; then
    printf 'unexpected output: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

# === Case 2: .mcp.json に serena entry 不在 → 警告 ===
case_2() {
  local fake_root="$TMP_DIR/case2"
  setup_fake_root "$fake_root"
  cat > "$fake_root/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "github": {
      "command": "x"
    }
  }
}
JSON
  local output
  output=$(bash "$fake_root/.claude/hooks/check-serena-mcp.sh" </dev/null 2>/dev/null)
  # 期待: "Serena MCP" 文言を含む
  if ! printf '%s' "$output" | grep -q 'Serena MCP'; then
    printf 'expected Serena MCP warning, got: %s\n' "$output" >&2
    return 1
  fi
  # system-reminder ブロックであることも確認
  if ! printf '%s' "$output" | grep -q 'system-reminder'; then
    return 1
  fi
  return 0
}

# === Case 3: .mcp.json 自体不在 → 警告 ===
case_3() {
  local fake_root="$TMP_DIR/case3"
  setup_fake_root "$fake_root"
  # .mcp.json は作らない
  local output
  output=$(bash "$fake_root/.claude/hooks/check-serena-mcp.sh" </dev/null 2>/dev/null)
  # 期待: ".mcp.json" 文言を含む
  if ! printf '%s' "$output" | grep -q '\.mcp\.json'; then
    printf 'expected .mcp.json warning, got: %s\n' "$output" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q 'system-reminder'; then
    return 1
  fi
  return 0
}

# === Case 4: HC_CHECK_SERENA_ENABLED=false → silent ===
case_4() {
  local fake_root="$TMP_DIR/case4"
  setup_fake_root "$fake_root"
  # .mcp.json は意図的に作らない (本来なら Case 3 と同じ警告が出るところを env で抑制)
  local output
  output=$(HC_CHECK_SERENA_ENABLED=false bash "$fake_root/.claude/hooks/check-serena-mcp.sh" </dev/null 2>/dev/null)
  # 期待: 出力なし
  if [ -n "$output" ]; then
    printf 'unexpected output despite disable: %s\n' "$output" >&2
    return 1
  fi
  return 0
}

printf '===== task #10 W2 check-serena-mcp smoke =====\n'
run_case 1 'serena entry present -> silent' case_1
run_case 2 'serena entry missing -> warning' case_2
run_case 3 '.mcp.json missing -> warning' case_3
run_case 4 'HC_CHECK_SERENA_ENABLED=false -> silent' case_4

printf '\n===== Result =====\n'
printf 'PASS: %d / 4\n' "$PASS"
printf 'FAIL: %d / 4\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
