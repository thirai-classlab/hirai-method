#!/usr/bin/env bash
# harness-audit-compare-smoke.sh — task-25 B3 smoke test
# 6 cases for /harness-audit --compare cross-repo drift detection
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)。
#     subshell 関数化で局所化することで SIGPIPE/exit 141 事故を防ぐ。
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行する。
#
# 実行:
#   bash .claude/tests/harness-audit-compare-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/scripts/harness-audit.py"
TMP_DIR=$(mktemp -d "/tmp/harness-audit-compare-smoke.XXXXXX")
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

# fake-harness 生成 helper: minimal .claude/ tree with 3 files in 3 categories
# args: $1 = root path
make_fake_harness() {
  local root="$1"
  mkdir -p "$root/.claude/hooks" "$root/.claude/rules" "$root/.claude/commands"
  printf '#!/bin/sh\necho hello\n' > "$root/.claude/hooks/test-hook.sh"
  printf '# Test rule\nThis is a test rule file.\n' > "$root/.claude/rules/test-rule.md"
  printf '# /test-cmd\nTest command doc.\n' > "$root/.claude/commands/test-cmd.md"
  printf '{"hooks": {}}\n' > "$root/.claude/settings.json"
}

# === Case 1: same .claude tree → drift 0, clean = source count ===
case_1() {
  local src="$TMP_DIR/c1-src"
  local tgt="$TMP_DIR/c1-tgt"
  make_fake_harness "$src"
  make_fake_harness "$tgt"

  local output
  output=$(cd "$src" && python3 "$SCRIPT" --compare "$tgt" --compare-format json 2>/dev/null)

  # 期待: total_drift == 0, total_missing_target == 0, total_missing_source == 0,
  #       total_clean == 4 (hook + rule + cmd + settings.json)
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d["total_drift"] == 0, "drift expected 0, got %d" % d["total_drift"]
assert d["total_missing_target"] == 0, "missing_target expected 0"
assert d["total_missing_source"] == 0, "missing_source expected 0"
assert d["total_clean"] == 4, "clean expected 4, got %d" % d["total_clean"]
' >&2
}

# === Case 2: target missing 1 file → missing_in_target == 1, clean == n-1 ===
case_2() {
  local src="$TMP_DIR/c2-src"
  local tgt="$TMP_DIR/c2-tgt"
  make_fake_harness "$src"
  make_fake_harness "$tgt"
  rm "$tgt/.claude/hooks/test-hook.sh"

  local output
  output=$(cd "$src" && python3 "$SCRIPT" --compare "$tgt" --compare-format json 2>/dev/null)

  printf '%s' "$output" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d["total_missing_target"] == 1, "missing_target expected 1, got %d" % d["total_missing_target"]
assert d["total_drift"] == 0
assert d["total_clean"] == 3, "clean expected 3, got %d" % d["total_clean"]
assert "hooks/test-hook.sh" in d["missing_in_target"]
' >&2
}

# === Case 3: same path but different content → content_drift == 1 ===
case_3() {
  local src="$TMP_DIR/c3-src"
  local tgt="$TMP_DIR/c3-tgt"
  make_fake_harness "$src"
  make_fake_harness "$tgt"
  printf '#!/bin/sh\necho hello modified\nexit 0\n' > "$tgt/.claude/hooks/test-hook.sh"

  local output
  output=$(cd "$src" && python3 "$SCRIPT" --compare "$tgt" --compare-format json 2>/dev/null)

  printf '%s' "$output" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d["total_drift"] == 1, "drift expected 1, got %d" % d["total_drift"]
assert d["total_clean"] == 3, "clean expected 3"
assert d["total_missing_target"] == 0
assert d["total_missing_source"] == 0
drift_paths = [x["path"] for x in d["content_drift"]]
assert "hooks/test-hook.sh" in drift_paths, "drift paths: %s" % drift_paths
' >&2
}

# === Case 4: --compare without arg → argparse error (exit != 0) ===
case_4() {
  local rc=0
  python3 "$SCRIPT" --compare >/dev/null 2>&1 || rc=$?
  # argparse は --compare 単独だと "expected one argument" で exit 2
  [ "$rc" -ne 0 ]
}

# === Case 5: --compare with non-existent path → error + exit 2 ===
case_5() {
  local src="$TMP_DIR/c5-src"
  make_fake_harness "$src"

  local rc=0
  local output
  output=$(cd "$src" && python3 "$SCRIPT" --compare "/tmp/this-path-does-not-exist-zzz-$$" 2>&1) || rc=$?
  # 期待: rc != 0 + stderr に "error" 含む
  [ "$rc" -ne 0 ] && printf '%s' "$output" | grep -qi "error"
}

# === Case 6: --compare-format json で summary keys 検証 + summary mode で human format ===
case_6() {
  local src="$TMP_DIR/c6-src"
  local tgt="$TMP_DIR/c6-tgt"
  make_fake_harness "$src"
  make_fake_harness "$tgt"
  # 1 file drift + 1 missing in target で混在 diff を作る
  printf 'modified\n' > "$tgt/.claude/rules/test-rule.md"
  rm "$tgt/.claude/hooks/test-hook.sh"

  # JSON mode 検証
  local json_out
  json_out=$(cd "$src" && python3 "$SCRIPT" --compare "$tgt" --compare-format json 2>/dev/null)
  printf '%s' "$json_out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
required = ["source_path","target_path","source_count","target_count","source_kb","target_kb",
            "missing_in_target","missing_in_source","content_drift","clean",
            "total_clean","total_drift","total_missing_target","total_missing_source","includes"]
for k in required:
    assert k in d, f"missing key: {k}"
assert d["total_drift"] == 1
assert d["total_missing_target"] == 1
' >&2

  # summary mode human readable 検証
  local sum_out
  sum_out=$(cd "$src" && python3 "$SCRIPT" --compare "$tgt" --compare-format summary 2>/dev/null)
  printf '%s' "$sum_out" | grep -q "\[harness-audit --compare\]" \
    && printf '%s' "$sum_out" | grep -q "Missing in target" \
    && printf '%s' "$sum_out" | grep -q "Content drift" \
    && printf '%s' "$sum_out" | grep -q "Summary"
}

printf '===== task-25 B3 harness-audit --compare smoke =====\n'
run_case 1 "identical .claude trees → drift=0, clean=4" case_1
run_case 2 "target missing 1 file → missing_in_target=1" case_2
run_case 3 "content drift (modified file) → drift=1" case_3
run_case 4 "--compare without argument → argparse error" case_4
run_case 5 "--compare with non-existent path → exit 2 + error msg" case_5
run_case 6 "JSON format keys + summary human format" case_6

printf '\n===== Result =====\n'
printf 'PASS: %d / 6\n' "$PASS"
printf 'FAIL: %d / 6\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
