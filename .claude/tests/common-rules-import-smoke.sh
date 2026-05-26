#!/usr/bin/env bash
# common-rules-import-smoke.sh — task-42 Step 5 iter2
# 設計起源: docs/draft/common-rules-extraction.md §4 (TDD 戦略 RED)
#
# 確認: CommonRules.md 存在 + CLAUDE.md @import + project 固有 retain + 共通規範削除 + 追加検証
#
# Case 一覧 (6 cases):
#   Case 1: .claude/CommonRules.md 存在 + 7 section 全件 grep + 各 section sentinel keyword
#   Case 2: CLAUDE.md に @.claude/CommonRules.md が count==1 行存在
#   Case 3: CLAUDE.md に project 固有 section retain
#   Case 4a: CLAUDE.md から共通規範 7 section 全件削除済
#   Case 4b: install.sh の rsync exclude pattern に CommonRules が含まれない (間接検証)
#   Case 5: CLAUDE.md 行数 upper bound (template として 120 行以下)
#   Case 6: CLAUDE.md の @import 行が L15 以内
#
# 実行:
#   bash .claude/tests/common-rules-import-smoke.sh
#
# 終了コード:
#   0 = 全 PASS / 1 = 1 件以上 FAIL
#
# 注意: subagent A (CommonRules.md 新設) / B (CLAUDE.md slim 化) 完了後に全 PASS を期待。
#       両 subagent 完了前の単独実行では fail 許容。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
FAILED_CASES=()

_record_pass() { PASS=$((PASS + 1)); printf "  PASS: %s\n" "$1"; }
_record_fail() {
  FAIL=$((FAIL + 1)); FAILED_CASES+=("$1")
  printf "  FAIL: %s\n" "$1"
}

# ===== Case 1: .claude/CommonRules.md 存在 + 7 section 全件 grep + sentinel keyword =====
case1_commonrules_7_sections() {
  local label="Case 1: CommonRules.md 7 section + sentinel keyword 全件 grep"
  local f="${PROJECT_ROOT}/.claude/CommonRules.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CommonRules.md not found at $f)"; return
  fi
  local missing=()
  # section heading keywords
  for kw in \
    "## Development Policy" \
    "## Autonomous Progression" \
    "## Rules" \
    "## ハーネス組み込みスラッシュコマンド" \
    "## Design Constraints" \
    "## Critical Operational Lessons" \
    "## ハーネスドキュメント" \
    "tdd-guide" \
    "Wave N 完了" \
    "development-process.md" \
    "/init-tasks" \
    "単独で portable" \
    "並列 subagent" \
    "INVENTORY.md"; do
    if ! grep -qF "$kw" "$f"; then missing+=("$kw"); fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    _record_pass "$label"
  else
    _record_fail "$label (missing keywords: ${missing[*]})"
  fi
}

# ===== Case 2: CLAUDE.md に @.claude/CommonRules.md が count==1 行存在 =====
case2_claude_md_import_line() {
  local label="Case 2: CLAUDE.md に @.claude/CommonRules.md が count==1 行存在"
  local f="${PROJECT_ROOT}/CLAUDE.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CLAUDE.md not found at $f)"; return
  fi
  local count
  count=$(grep -cE '^@\.claude/CommonRules\.md' "$f" || true)
  if [ "$count" -eq 1 ]; then
    _record_pass "$label (count=${count})"
  elif [ "$count" -eq 0 ]; then
    _record_fail "$label (no @import line found in CLAUDE.md)"
  else
    _record_fail "$label (duplicate @import lines found: count=${count})"
  fi
}

# ===== Case 3: CLAUDE.md に project 固有 section retain =====
case3_claude_md_project_specific_retain() {
  local label="Case 3: CLAUDE.md に project 固有 section retain"
  local f="${PROJECT_ROOT}/CLAUDE.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CLAUDE.md not found at $f)"; return
  fi
  local missing=()
  for kw in "## Tech Stack" "## Architecture" "## Implementation Status"; do
    if ! grep -qF "$kw" "$f"; then missing+=("$kw"); fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    _record_pass "$label"
  else
    _record_fail "$label (missing sections: ${missing[*]})"
  fi
}

# ===== Case 4a: CLAUDE.md から共通規範 7 section 全件削除済 =====
case4a_claude_md_common_rules_removed() {
  local label="Case 4a: CLAUDE.md から共通規範 7 section 全件削除済"
  local f="${PROJECT_ROOT}/CLAUDE.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CLAUDE.md not found at $f)"; return
  fi
  local present=()
  for kw in \
    "## Development Policy" \
    "## Autonomous Progression" \
    "## ハーネス組み込みスラッシュコマンド" \
    "## Design Constraints" \
    "## Critical Operational Lessons" \
    "## ハーネスドキュメント"; do
    if grep -qF "$kw" "$f"; then present+=("$kw"); fi
  done
  # "## Rules" は project 固有 section "## Rules" と区別のため見出し+後続で判定
  # CommonRules.md に移動済なら CLAUDE.md には "## Rules（`.claude/rules/`）" 相当が不在のはず
  if grep -qE '^## Rules' "$f"; then present+=("## Rules (top-level heading)"); fi
  if [ ${#present[@]} -eq 0 ]; then
    _record_pass "$label"
  else
    _record_fail "$label (still present in CLAUDE.md: ${present[*]})"
  fi
}

# ===== Case 4b: install.sh の rsync exclude に CommonRules が含まれない =====
case4b_install_sh_commonrules_not_excluded() {
  local label="Case 4b: install.sh が CommonRules.md を rsync exclude していない"
  local f="${PROJECT_ROOT}/install.sh"
  if [ ! -f "$f" ]; then
    _record_fail "$label (install.sh not found at $f)"; return
  fi
  if grep -E "exclude.*CommonRules" "$f" 2>/dev/null; then
    _record_fail "$label (CommonRules が exclude pattern に存在)"
  else
    _record_pass "$label"
  fi
}

# ===== Case 5: CLAUDE.md 行数 upper bound (template として 120 行以下) =====
case5_claude_md_line_count_upper_bound() {
  local label="Case 5: CLAUDE.md 行数 upper bound (template として 120 行以下)"
  local f="${PROJECT_ROOT}/CLAUDE.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CLAUDE.md not found at $f)"; return
  fi
  local lines
  lines=$(wc -l < "$f")
  if [ "$lines" -le 120 ]; then
    _record_pass "$label (${lines} lines)"
  else
    _record_fail "$label (${lines} lines > 120)"
  fi
}

# ===== Case 6: CLAUDE.md の @import 行が L15 以内 =====
case6_claude_md_import_line_position() {
  local label="Case 6: CLAUDE.md の @import 行が L15 以内"
  local f="${PROJECT_ROOT}/CLAUDE.md"
  if [ ! -f "$f" ]; then
    _record_fail "$label (CLAUDE.md not found at $f)"; return
  fi
  local line_num
  line_num=$(grep -nE '^@\.claude/CommonRules\.md' "$f" | head -1 | cut -d: -f1)
  if [ -z "$line_num" ]; then
    _record_fail "$label (@import 行不在)"
  elif [ "$line_num" -le 15 ]; then
    _record_pass "$label (L${line_num})"
  else
    _record_fail "$label (L${line_num} > 15)"
  fi
}

printf "===== common-rules-import-smoke (task-42 Step 5 iter2, 6 cases) =====\n\n"

case1_commonrules_7_sections
case2_claude_md_import_line
case3_claude_md_project_specific_retain
case4a_claude_md_common_rules_removed
case4b_install_sh_commonrules_not_excluded
case5_claude_md_line_count_upper_bound
case6_claude_md_import_line_position

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
