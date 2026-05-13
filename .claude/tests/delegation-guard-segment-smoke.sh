#!/usr/bin/env bash
# delegation-guard-segment-smoke.sh — task #8 smoke test
# 6 ケースで delegation-guard.sh の segment splitter (split_command_segments) を検証
# file-top に set -euo pipefail を書かない (feedback memory `set_e_in_sourced_libs` 規範)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/delegation-guard.sh"

# split_command_segments を hook script から抽出して実行する補助関数
extract_segments() (
  set -uo pipefail
  # hook の split_command_segments 関数定義を抽出して実行
  local fn_def
  fn_def=$(awk '/^    split_command_segments\(\) \(/,/^    \)$/' "$HOOK" | sed -E 's/^    //')
  if [ -z "$fn_def" ]; then
    echo "ERROR: split_command_segments function not found in $HOOK" >&2
    return 2
  fi
  # eval で関数を読み込んで実行
  eval "$fn_def"
  split_command_segments "$1"
)

# 期待 segments 数を比較
assert_segment_count() {
  local case_id="$1"
  local desc="$2"
  local input="$3"
  local expected_count="$4"

  local actual
  actual=$(extract_segments "$input" 2>/dev/null | grep -cE '\S' || true)
  if [ "$actual" = "$expected_count" ]; then
    echo "  PASS Case $case_id: $desc (expected=$expected_count, actual=$actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL Case $case_id: $desc (expected=$expected_count, actual=$actual)"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

PASS=0
FAIL=0
FAILED_CASES=()

echo "===== task #8 delegation-guard segment splitter smoke ====="

# Case 1-3: 基本セパレータ (既存挙動)
assert_segment_count 1 "&& separator" 'git status && git diff' 2
assert_segment_count 2 "; separator" 'git status ; git diff' 2
assert_segment_count 3 "| separator" 'git status | head -1' 2

# Case 4-5: クォート内保護 (core fix)
assert_segment_count 4 'double-quote | protected' 'git commit -m "table|cell|content"' 1
assert_segment_count 5 'single-quote || protected' "git commit -m 'A || B'" 1

# Case 6: escape 後の && 保護 + ; 分割
assert_segment_count 6 'escaped && + ; separator' 'echo \&& bar; echo foo' 2

echo ""
echo "===== Result ====="
echo "PASS: $PASS / 6"
echo "FAIL: $FAIL / 6"
if [ $FAIL -gt 0 ]; then
  echo "Failed cases: ${FAILED_CASES[*]}"
  exit 1
fi
exit 0
