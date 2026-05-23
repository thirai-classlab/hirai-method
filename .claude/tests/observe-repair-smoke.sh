#!/usr/bin/env bash
# observe-repair-smoke.sh — task-27 W2 smoke for observe-repair.sh
#
# 設計起源:
#   docs/draft/observe-jq-parse-fix.md §3 W2 (2026-05-23)
#
# 対象 script:
#   .claude/scripts/observe-repair.sh
#
# 検証範囲 (6 ケース):
#   Case 1: 100% valid jsonl → repair 0 件、jsonl 不変 (md5 一致)
#   Case 2: 50% invalid jsonl (literal control char) → repair で valid 化、backup 生成
#   Case 3: 完全破壊行 (修復不能) → `_invalid: true` marker 付与
#   Case 4: --dry-run → 修復候補数 report、jsonl 不変
#   Case 5: --in-place で lock 取得失敗 (mock active session) → skip 警告
#   Case 6: backup file 内容 = 原 jsonl 完全一致 (data integrity)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - live ~/.claude/homunculus を絶対に汚染しない (--target-dir で隔離)
#   - mktemp -d で隔離した tmp dir で実施
#
# 実行:
#   bash .claude/tests/observe-repair-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/.claude/scripts/observe-repair.sh"

if [ ! -x "$SCRIPT" ]; then
  printf 'FAIL: %s not executable\n' "$SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# ===== fixture helpers =====
make_fixture_dir() {
  local base="$1"
  mkdir -p "$base/projects/testproj"
}

# md5 (BSD/GNU 両対応)
md5_of() {
  local f="$1"
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$f"
  else
    md5sum "$f" | awk '{print $1}'
  fi
}

# valid record (1 行 JSON)
mk_valid() {
  local note="$1"
  printf '{"ts":"2026-05-23T12:00:00Z","event":"PreToolUse","tool":"Bash","scope":"project","note":"%s"}\n' "$note"
}

# invalid record (literal newline in nested string で fail)
# Python で生成: tool_input.command に literal \n を埋め込む
mk_invalid_repairable() {
  local note="$1"
  python3 -c "
import sys
# literal newline を nested string に埋め込む (Python の \\n は実 newline)
import json
# まず valid object を作る
obj = {
  'ts': '2026-05-23T12:00:00Z',
  'event': 'PreToolUse',
  'tool': 'Bash',
  'scope': 'project',
  'note': '$note',
  'raw': {
    'command': 'echo line1\nline2'  # literal newline 入り
  }
}
# ensure_ascii=False + strict=False で literal newline を保持して出力
# json.dumps は default で \\n に escape するため、置換が必要
s = json.dumps(obj, ensure_ascii=False)
# 'echo line1\\nline2' → 'echo line1<literal-newline>line2' に置換
s = s.replace(r'echo line1\\nline2', 'echo line1' + chr(10) + 'line2')
sys.stdout.write(s)
sys.stdout.write('\n')
"
}

# 完全破壊行 (修復不能)
mk_unrepairable() {
  # JSON ですらない gibberish
  printf '{this is not json at all <<<>>>\n'
}

# ===== Case 1: 100% valid jsonl → 不変 =====
case1_all_valid_unchanged() {
  local label="Case 1: all-valid jsonl is unchanged after --in-place"
  local base
  base=$(mktemp -d /tmp/observe-repair-c1.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_valid "rec2"
    mk_valid "rec3"
  } > "$obs"

  local before_md5
  before_md5=$(md5_of "$obs")

  bash "$SCRIPT" --in-place --target-dir "$base" >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  local after_md5
  after_md5=$(md5_of "$obs")

  # content は不変 (但し backup file が生まれている)
  if [ "$before_md5" != "$after_md5" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (content changed before=$before_md5 after=$after_md5)")
    printf "  FAIL: %s (md5 mismatch)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 2: 50% invalid jsonl → repair で valid 化 + backup 生成 =====
case2_repair_invalid_with_backup() {
  local label="Case 2: invalid records are repaired and backup is created"
  local base
  base=$(mktemp -d /tmp/observe-repair-c2.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_invalid_repairable "rec2"
    mk_valid "rec3"
    mk_invalid_repairable "rec4"
  } > "$obs"

  # 事前 fixture invariant 検証:
  # jq の stream parse は literal control char で fail し以降を読まない (count 不正確)。
  # Python の json.JSONDecoder.raw_decode loop で正確に 4 record あることを確認する。
  local before_total
  before_total=$(python3 -c "
import json
with open('$obs', 'rb') as f:
    text = f.read().decode('utf-8', errors='replace')
dec = json.JSONDecoder(strict=False)
i, n, total = 0, len(text), 0
while i < n:
    while i < n and text[i] in (' ', '\t', '\n', '\r'):
        i += 1
    if i >= n: break
    try:
        _, end = dec.raw_decode(text, idx=i)
        total += 1
        i = end
    except Exception:
        nb = text.find('{', i+1)
        i = n if nb == -1 else nb
        total += 1
print(total)
")
  if [ "$before_total" -ne 4 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (fixture invariant: before_total=$before_total, expected 4)")
    printf "  FAIL: %s (fixture has %d records, expected 4)\n" "$label" "$before_total"
    return
  fi

  bash "$SCRIPT" --in-place --target-dir "$base" >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # 修復後: 全 4 record valid (strict JSON、1 record per physical line)
  local after_lines
  after_lines=$(wc -l < "$obs" | awk '{print $1}')
  local after_valid
  after_valid=$(jq -c -e 'type == "object"' "$obs" 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$after_valid" -ne 4 ] || [ "$after_lines" -ne 4 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (after_valid=$after_valid lines=$after_lines, expected 4)")
    printf "  FAIL: %s (after %d valid / %d lines, expected 4)\n" "$label" "$after_valid" "$after_lines"
    return
  fi

  # backup file が生成されている
  local bak_count
  bak_count=$(ls "$base/projects/testproj/"observations.jsonl.bak-* 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$bak_count" -lt 1 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (no backup created)")
    printf "  FAIL: %s (backup missing)\n" "$label"
    return
  fi

  # 修復された record に _repaired_at marker
  local marker_count
  marker_count=$(jq -c 'select(._repaired_at)' "$obs" 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$marker_count" -lt 2 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (_repaired_at markers=$marker_count, expected >=2)")
    printf "  FAIL: %s (markers=%d, expected >=2)\n" "$label" "$marker_count"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 3: 完全破壊行 → _invalid: true marker =====
case3_unrepairable_marked() {
  local label="Case 3: unrepairable records get _invalid: true marker"
  local base
  base=$(mktemp -d /tmp/observe-repair-c3.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_unrepairable
    mk_valid "rec3"
  } > "$obs"

  bash "$SCRIPT" --in-place --target-dir "$base" >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # 修復後の jsonl は全行 jq-valid (marker line も valid JSON object)
  local after_valid
  after_valid=$(jq -c -e 'type == "object"' "$obs" 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$after_valid" -ne 3 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (after_valid=$after_valid, expected 3)")
    printf "  FAIL: %s (after has %d valid, expected 3)\n" "$label" "$after_valid"
    return
  fi

  # _invalid: true marker line が 1 件
  local invalid_marker_count
  invalid_marker_count=$(jq -c 'select(._invalid == true)' "$obs" 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$invalid_marker_count" -ne 1 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (_invalid markers=$invalid_marker_count, expected 1)")
    printf "  FAIL: %s (invalid markers=%d, expected 1)\n" "$label" "$invalid_marker_count"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 4: --dry-run で file 不変 =====
case4_dry_run_no_change() {
  local label="Case 4: --dry-run reports candidates without changing file"
  local base
  base=$(mktemp -d /tmp/observe-repair-c4.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_invalid_repairable "rec2"
    mk_valid "rec3"
  } > "$obs"

  local before_md5
  before_md5=$(md5_of "$obs")

  local output
  output=$(bash "$SCRIPT" --dry-run --target-dir "$base" 2>&1)
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  local after_md5
  after_md5=$(md5_of "$obs")

  if [ "$before_md5" != "$after_md5" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (file mutated)")
    printf "  FAIL: %s (file mutated in dry-run)\n" "$label"
    return
  fi

  # output に invalid: count / repaired: count summary
  if ! printf '%s' "$output" | grep -q 'invalid (pre-W1):'; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (summary missing)")
    printf "  FAIL: %s (no summary in output)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 5: lock 取得失敗 → skip 警告 =====
case5_lock_skip() {
  local label="Case 5: existing lock causes skip with warning"
  local base
  base=$(mktemp -d /tmp/observe-repair-c5.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_invalid_repairable "rec2"
  } > "$obs"

  local before_md5
  before_md5=$(md5_of "$obs")

  # 事前に lock を作る (active session simulate)
  mkdir "${obs}.lock"

  local output
  output=$(bash "$SCRIPT" --in-place --target-dir "$base" 2>&1)
  local rc=$?

  # cleanup lock
  rmdir "${obs}.lock" 2>/dev/null || true

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  local after_md5
  after_md5=$(md5_of "$obs")

  if [ "$before_md5" != "$after_md5" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (file mutated despite lock)")
    printf "  FAIL: %s (file mutated despite lock)\n" "$label"
    return
  fi

  # output に SKIP warning
  if ! printf '%s' "$output" | grep -qi 'skip'; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (no skip warning)")
    printf "  FAIL: %s (no skip warning in output)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 6: backup 内容 = 原 jsonl 完全一致 =====
case6_backup_integrity() {
  local label="Case 6: backup file matches original jsonl exactly"
  local base
  base=$(mktemp -d /tmp/observe-repair-c6.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  {
    mk_valid "rec1"
    mk_invalid_repairable "rec2"
    mk_valid "rec3"
  } > "$obs"

  local original_md5
  original_md5=$(md5_of "$obs")

  bash "$SCRIPT" --in-place --target-dir "$base" >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # backup file 取得
  local bak
  bak=$(ls "$base/projects/testproj/"observations.jsonl.bak-* 2>/dev/null | head -1)

  if [ -z "$bak" ] || [ ! -f "$bak" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (backup not found)")
    printf "  FAIL: %s (no backup)\n" "$label"
    return
  fi

  local bak_md5
  bak_md5=$(md5_of "$bak")

  if [ "$original_md5" != "$bak_md5" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (backup mismatch original=$original_md5 backup=$bak_md5)")
    printf "  FAIL: %s (backup md5 mismatch)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

printf "===== observe-repair-smoke (task-27 W2, 6 cases) =====\n\n"

case1_all_valid_unchanged
case2_repair_invalid_with_backup
case3_unrepairable_marked
case4_dry_run_no_change
case5_lock_skip
case6_backup_integrity

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
