#!/usr/bin/env bash
# delegation-guard-segment-smoke.sh — task #8 smoke test (Case 1-6) + heredoc fix (Case 7-9, 2026-05-23)
# 9 ケースで delegation-guard.sh の segment splitter (split_command_segments) を検証
# file-top に set -euo pipefail を書かない (feedback memory `set_e_in_sourced_libs` 規範)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# split_command_segments は lib/delegation-guard/bash-whitelist.sh に分離 (task-25 C1.2)
HOOK_LIB="$PROJECT_ROOT/.claude/hooks/lib/delegation-guard/bash-whitelist.sh"
# 旧 path (大型 hook 内 inline 定義) からの fallback 抽出経路
HOOK="$PROJECT_ROOT/.claude/hooks/delegation-guard.sh"

# split_command_segments を hook script から抽出して実行する補助関数
extract_segments() (
  set -uo pipefail
  # lib 経由が default、source して関数を import
  if [ -f "$HOOK_LIB" ]; then
    # shellcheck source=/dev/null
    . "$HOOK_LIB"
    split_command_segments "$1"
    return
  fi
  # legacy: hook の split_command_segments 関数定義を抽出して実行 (旧 inline 定義)
  local fn_def
  fn_def=$(awk '/^    split_command_segments\(\) \(/,/^    \)$/' "$HOOK" | sed -E 's/^    //')
  if [ -z "$fn_def" ]; then
    echo "ERROR: split_command_segments function not found in $HOOK_LIB or $HOOK" >&2
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

echo "===== task #8 delegation-guard segment splitter smoke (9 cases) ====="

# Case 1-3: 基本セパレータ (既存挙動)
assert_segment_count 1 "&& separator" 'git status && git diff' 2
assert_segment_count 2 "; separator" 'git status ; git diff' 2
assert_segment_count 3 "| separator" 'git status | head -1' 2

# Case 4-5: クォート内保護 (core fix)
assert_segment_count 4 'double-quote | protected' 'git commit -m "table|cell|content"' 1
assert_segment_count 5 'single-quote || protected' "git commit -m 'A || B'" 1

# Case 6: escape 後の && 保護 + ; 分割
assert_segment_count 6 'escaped && + ; separator' 'echo \&& bar; echo foo' 2

# === Case 7-9: heredoc 対応 (2026-05-23 修正、heredoc-aware splitter) ===

# Case 7: heredoc 本文に日本語含む (実 use case: git commit -m "$(cat <<'EOF' ... 日本語 ... EOF)")
# 期待: 1 segment (heredoc 全体が string literal として保持される)
read -r -d '' case7_input <<'CASE7_EOF' || true
git commit -m "$(cat <<'EOF'
feat: 日本語コミット
EOF
)"
CASE7_EOF
assert_segment_count 7 'heredoc with japanese body' "$case7_input" 1

# Case 8: heredoc 本文に複数行 + 特殊文字 (| & ; || &&) 含む
# 期待: 1 segment (heredoc 中の | & ; などは segment separator として誤検知しない)
read -r -d '' case8_input <<'CASE8_EOF' || true
git commit -m "$(cat <<'EOF'
body|with|pipes
A && B
C || D
end;line
EOF
)"
CASE8_EOF
assert_segment_count 8 'heredoc with pipes and special chars' "$case8_input" 1

# Case 9: <<- (タブ ignore) 形式 — 先頭タブ付き delimiter line でも終了検出
# 期待: 1 segment
case9_input=$'git commit -m "$(cat <<-EOF\n\tindented body line\n\tEOF\n)"'
assert_segment_count 9 'heredoc dash form (<<- with tab-indented delim)' "$case9_input" 1

echo ""
echo "===== Result ====="
echo "PASS: $PASS / 9"
echo "FAIL: $FAIL / 9"
if [ $FAIL -gt 0 ]; then
  echo "Failed cases: ${FAILED_CASES[*]}"
  exit 1
fi
exit 0
