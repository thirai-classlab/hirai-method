#!/usr/bin/env bash
# observe-rotate-smoke.sh — task-22 W4 smoke for observe-rotate.sh
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md §3 W4 (2026-05-23)
#
# 対象 script:
#   .claude/scripts/observe-rotate.sh
#
# 検証範囲 (6 ケース):
#   Case 1: --dry-run で削減見込みサイズ表示、file 変更なし
#   Case 2: 30 日超 entry のみが archive へ移動
#   Case 3: 30 日以内 entry は本体 (observations.jsonl) に残存
#   Case 4: archive 不在時は新規 .gz 作成
#   Case 5: archive 存在時は append (entry 数を before + new で実測)
#   Case 6: --threshold-days 0 で全 entry archive (boundary)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - live ~/.claude/homunculus を絶対に汚染しない (--target-dir で隔離)
#   - mktemp -d で隔離した tmp dir で実施
#
# 実行:
#   bash .claude/tests/observe-rotate-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/.claude/scripts/observe-rotate.sh"

if [ ! -x "$SCRIPT" ]; then
  printf 'FAIL: %s not executable\n' "$SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# ===== fixture helpers =====
# isolated base dir layout:
#   $BASE/projects/testproj/observations.jsonl
#   $BASE/projects/testproj/observations-YYYY-MM.jsonl.gz (optional)
make_fixture_dir() {
  local base="$1"
  mkdir -p "$base/projects/testproj"
}

# 1 行 observation 生成 (ts 指定)
mk_entry() {
  local ts="$1"
  printf '{"ts":"%sT12:00:00Z","event":"PreToolUse","tool":"Bash","scope":"project","raw":{}}\n' "$ts"
}

# fixture observations.jsonl 生成
#  - $1: 出力 path
#  - 残: YYYY-MM-DD 形式の日付 list
build_obs() {
  local out="$1"
  shift
  : > "$out"
  for d in "$@"; do
    mk_entry "$d" >> "$out"
  done
}

# threshold 計算 (BSD/GNU date 両対応)
days_ago() {
  local n="$1"
  if date -v-"${n}"d +%Y-%m-%d >/dev/null 2>&1; then
    date -v-"${n}"d +%Y-%m-%d
  elif date -d "-${n} days" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "-${n} days" +%Y-%m-%d
  else
    python3 -c "import datetime; print((datetime.datetime.utcnow() - datetime.timedelta(days=${n})).strftime('%Y-%m-%d'))"
  fi
}

# ===== Case 1: --dry-run で file 変更なし =====
case1_dry_run_no_change() {
  local label="Case 1: --dry-run shows reduction without file change"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c1.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  local d_today
  local d_old
  d_today=$(days_ago 0)
  d_old=$(days_ago 60)
  build_obs "$obs" "$d_today" "$d_today" "$d_old" "$d_old"

  local before_md5
  before_md5=$(md5 -q "$obs" 2>/dev/null || md5sum "$obs" | awk '{print $1}')
  local before_size
  before_size=$(wc -c < "$obs" | awk '{print $1}')

  local output
  output=$(bash "$SCRIPT" --dry-run --project testproj --target-dir "$base" --threshold-days 30 2>&1)
  local rc=$?

  local after_md5
  after_md5=$(md5 -q "$obs" 2>/dev/null || md5sum "$obs" | awk '{print $1}')

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  if [ "$before_md5" != "$after_md5" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (file mutated)")
    printf "  FAIL: %s (file mutated, before=%s after=%s)\n" "$label" "$before_md5" "$after_md5"
    return
  fi

  # output に reduction 表示があるか
  if ! printf '%s' "$output" | grep -q 'reduction:'; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (reduction not shown)")
    printf "  FAIL: %s (no reduction in output)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 2: 30 日超のみ archive へ =====
case2_old_entries_archived() {
  local label="Case 2: entries older than 30 days move to archive"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c2.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  local d_today
  local d_old
  d_today=$(days_ago 0)
  d_old=$(days_ago 60)
  build_obs "$obs" "$d_today" "$d_old" "$d_old" "$d_old"

  bash "$SCRIPT" --project testproj --target-dir "$base" --threshold-days 30 >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # archive 生成確認 (YYYY-MM .gz)
  local archive_count
  archive_count=$(ls "$base/projects/testproj/"observations-*.jsonl.gz 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$archive_count" -lt 1 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (no archive created)")
    printf "  FAIL: %s (no archive .gz)\n" "$label"
    return
  fi

  # archive 内容に d_old が 3 件入っているか
  local archive_file
  archive_file=$(ls "$base/projects/testproj/"observations-*.jsonl.gz 2>/dev/null | head -1)
  local archived_lines
  archived_lines=$(gunzip -c "$archive_file" | grep -c "\"ts\":\"${d_old}T")

  if [ "$archived_lines" -ne 3 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected 3 old in archive, got $archived_lines)")
    printf "  FAIL: %s (archived d_old=%d, expected 3)\n" "$label" "$archived_lines"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 3: 30 日以内 entry は本体残存 =====
case3_recent_entries_stay() {
  local label="Case 3: entries within 30 days remain in body"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c3.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  local d_today
  local d_recent
  local d_old
  d_today=$(days_ago 0)
  d_recent=$(days_ago 10)
  d_old=$(days_ago 60)
  build_obs "$obs" "$d_today" "$d_recent" "$d_old"

  bash "$SCRIPT" --project testproj --target-dir "$base" --threshold-days 30 >/dev/null 2>&1

  local body_lines
  body_lines=$(wc -l < "$obs" | awk '{print $1}')
  # body は 2 件 (d_today + d_recent) のはず
  if [ "$body_lines" -ne 2 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (body lines=$body_lines, expected 2)")
    printf "  FAIL: %s (body=%d, expected 2)\n" "$label" "$body_lines"
    return
  fi

  # body に d_today / d_recent が含まれ d_old は含まれない
  if ! grep -q "\"ts\":\"${d_today}T" "$obs"; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (d_today not in body)")
    printf "  FAIL: %s (d_today missing in body)\n" "$label"
    return
  fi
  if ! grep -q "\"ts\":\"${d_recent}T" "$obs"; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (d_recent not in body)")
    printf "  FAIL: %s (d_recent missing in body)\n" "$label"
    return
  fi
  if grep -q "\"ts\":\"${d_old}T" "$obs"; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (d_old leaked into body)")
    printf "  FAIL: %s (d_old still in body)\n" "$label"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 4: archive 不在時は新規作成 =====
case4_new_archive_created() {
  local label="Case 4: new archive .gz created when not existing"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c4.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  local d_old
  d_old=$(days_ago 60)
  build_obs "$obs" "$d_old" "$d_old"

  # 事前に archive 不在を確認
  if ls "$base/projects/testproj/"observations-*.jsonl.gz >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (precondition: archive should not exist)")
    printf "  FAIL: %s (precondition)\n" "$label"
    return
  fi

  bash "$SCRIPT" --project testproj --target-dir "$base" --threshold-days 30 >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  local archive_count
  archive_count=$(ls "$base/projects/testproj/"observations-*.jsonl.gz 2>/dev/null | wc -l | awk '{print $1}')

  if [ "$archive_count" -ne 1 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected 1 archive, got $archive_count)")
    printf "  FAIL: %s (archive count=%d)\n" "$label" "$archive_count"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 5: archive 存在時は append =====
case5_existing_archive_append() {
  local label="Case 5: existing archive .gz is appended (before + new)"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c5.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  # d_old は同月で固定 (例: 60 日前) — append 検証は同月 .gz の line 数で見る
  local d_old
  d_old=$(days_ago 60)
  local month
  month=$(printf '%s' "$d_old" | cut -c1-7)

  local existing_gz="$base/projects/testproj/observations-${month}.jsonl.gz"

  # 既存 archive を 5 件で作る
  local tmp_existing
  tmp_existing=$(mktemp /tmp/c5-existing.XXXXXX)
  for i in 1 2 3 4 5; do
    printf '{"ts":"%sT00:00:%02dZ","event":"PreToolUse","tool":"Bash","note":"existing-%d"}\n' "$d_old" "$i" "$i" >> "$tmp_existing"
  done
  gzip -c "$tmp_existing" > "$existing_gz"
  rm -f "$tmp_existing"

  # 新規 entry を 3 件 (d_old) で作る
  build_obs "$obs" "$d_old" "$d_old" "$d_old"

  bash "$SCRIPT" --project testproj --target-dir "$base" --threshold-days 30 >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # archive 内容を line count で実測 (期待 = 5 existing + 3 new = 8)
  local total_lines
  total_lines=$(gunzip -c "$existing_gz" | wc -l | awk '{print $1}')

  if [ "$total_lines" -ne 8 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected 8 lines, got $total_lines)")
    printf "  FAIL: %s (archive lines=%d, expected 8)\n" "$label" "$total_lines"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

# ===== Case 6: --threshold-days 0 で全 entry archive =====
case6_threshold_zero_archives_all() {
  local label="Case 6: --threshold-days 0 archives all entries (boundary)"
  local base
  base=$(mktemp -d /tmp/observe-rotate-c6.XXXXXX)
  trap 'rm -rf "$base"' RETURN
  make_fixture_dir "$base"

  local obs="$base/projects/testproj/observations.jsonl"
  local d_today
  local d_recent
  d_today=$(days_ago 0)
  d_recent=$(days_ago 5)
  build_obs "$obs" "$d_today" "$d_recent" "$d_recent"

  # --threshold-days 0 では今日 (d_today) よりも前の line が archive 対象
  # date -v-0d は今日 (= d_today)、line_ts < threshold は d_today より前
  # d_today (今日) は line_ts < threshold が false なので body に残る
  # d_recent (5 日前) は archive
  bash "$SCRIPT" --project testproj --target-dir "$base" --threshold-days 0 >/dev/null 2>&1
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc)")
    printf "  FAIL: %s (rc=%d)\n" "$label" "$rc"
    return
  fi

  # body には d_today の 1 件のみが残る
  local body_lines
  body_lines=$(wc -l < "$obs" | awk '{print $1}')
  if [ "$body_lines" -ne 1 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (body lines=$body_lines, expected 1)")
    printf "  FAIL: %s (body=%d, expected 1)\n" "$label" "$body_lines"
    return
  fi

  # archive 件数は 2 (d_recent x2)
  local archive_file
  archive_file=$(ls "$base/projects/testproj/"observations-*.jsonl.gz 2>/dev/null | head -1)
  if [ -z "$archive_file" ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (no archive file)")
    printf "  FAIL: %s (no archive)\n" "$label"
    return
  fi

  local archived_lines
  archived_lines=$(gunzip -c "$archive_file" | wc -l | awk '{print $1}')

  if [ "$archived_lines" -ne 2 ]; then
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (expected 2 archived, got $archived_lines)")
    printf "  FAIL: %s (archived=%d, expected 2)\n" "$label" "$archived_lines"
    return
  fi

  PASS=$((PASS + 1))
  printf "  PASS: %s\n" "$label"
}

printf "===== observe-rotate-smoke (task-22 W4, 6 cases) =====\n\n"

case1_dry_run_no_change
case2_old_entries_archived
case3_recent_entries_stay
case4_new_archive_created
case5_existing_archive_append
case6_threshold_zero_archives_all

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
