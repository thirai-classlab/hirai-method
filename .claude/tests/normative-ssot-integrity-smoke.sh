#!/usr/bin/env bash
# .claude/tests/normative-ssot-integrity-smoke.sh — task-103 Step 4
#
# 目的:
#   規範文書 SSoT 整合の機械検証。7 rule file + 2 template に preset pointer が
#   埋め込まれ、BLOCK 記述に preset aware badge が付与されている状態を検証する。
#
#   - Case A: 7 rule file 全てに preset pointer 1 行存在
#             (`grep -lE '現 effective preset は.*hc-config.sh --summary' | wc -l >= 7`)
#   - Case B: BLOCK 記述への preset aware badge 総数 >= 15
#             (`grep -cE 'BLOCK.*preset|preset aware|preset dependent' .claude/rules/*.md` の合計)
#   - Case C: `_TASK_TEMPLATE.md` + `_DRAFT_TEMPLATE.md` に preset pointer 存在
#
# 設計:
#   - SCRIPT_DIR / REPO_ROOT を BASH_SOURCE から解決 (どこから実行しても動く)
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0 / 1 件 FAIL で exit 1
#   - subshell 関数化 ( set -uo pipefail; ... ) で各 case を隔離
#
# 実行:
#   bash .claude/tests/normative-ssot-integrity-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用

# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RULES_DIR="${REPO_ROOT}/.claude/rules"
TEMPLATES_DIR="${REPO_ROOT}/.claude/templates/docs"

# 7 rule file (task-103 対象)
RULE_FILES=(
  "${RULES_DIR}/modes.md"
  "${RULES_DIR}/task-management.md"
  "${RULES_DIR}/workflow.md"
  "${RULES_DIR}/development-process.md"
  "${RULES_DIR}/self-improvement.md"
  "${RULES_DIR}/git-workflow.md"
  "${RULES_DIR}/why-x5-output.md"
)

# 2 template file
TEMPLATE_FILES=(
  "${TEMPLATES_DIR}/tasks/_TASK_TEMPLATE.md"
  "${TEMPLATES_DIR}/draft/_DRAFT_TEMPLATE.md"
)

# 前提 file 存在確認
for f in "${RULE_FILES[@]}" "${TEMPLATE_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    printf 'ERROR: expected file not found: %s\n' "$f" >&2
    exit 1
  fi
done

PASS=0
FAIL=0
FAILED_CASES=""

_record() {
  local result="$1"
  local case_id="$2"
  local desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# ============================================================
# Case A: 7 rule file 全てに preset pointer 1 行存在
# grep pattern: '現 effective preset は.*hc-config.sh --summary'
# ============================================================
_case_a() (
  set -uo pipefail
  local count
  count=0
  local f
  for f in "${RULE_FILES[@]}"; do
    if grep -qE '現 effective preset は.*hc-config.sh --summary' "$f"; then
      count=$((count + 1))
    else
      printf 'MISS: %s\n' "$f" >&2
    fi
  done
  if [ "$count" -lt 7 ]; then
    printf 'A: pointer count %d < 7\n' "$count" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case B: BLOCK 記述の preset aware badge 総数 >= 15
# 対象 pattern: 'BLOCK.*preset' or 'preset aware' or 'preset dependent'
# 対象範囲: .claude/rules/*.md (7 file + その他 rule file を含む)
# ============================================================
_case_b() (
  set -uo pipefail
  local total
  total=0
  local f
  # 全 rule file (7 file 対象 + 追加 rule も含める、task 記載通り .claude/rules/*.md)
  for f in "${RULES_DIR}"/*.md; do
    [ -f "$f" ] || continue
    local n
    n=$(grep -cE 'BLOCK.*preset|preset aware|preset dependent' "$f" 2>/dev/null || printf '0')
    total=$((total + n))
  done
  if [ "$total" -lt 15 ]; then
    printf 'B: preset aware badge total %d < 15\n' "$total" >&2
    return 1
  fi
  printf 'B: preset aware badge total = %d (>= 15)\n' "$total" >&2
  return 0
)

# ============================================================
# Case C: 2 template file に preset pointer 継承
# ============================================================
_case_c() (
  set -uo pipefail
  local f
  for f in "${TEMPLATE_FILES[@]}"; do
    if ! grep -qE '現 effective preset は.*hc-config.sh --summary' "$f"; then
      printf 'C: template missing pointer: %s\n' "$f" >&2
      return 1
    fi
  done
  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== normative-ssot-integrity-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "7 rule file に preset pointer 存在 (>=7)"
else                         _record FAIL A "7 rule file に preset pointer 存在 (>=7)"
fi

if _case_b 2>/dev/null; then _record PASS B "BLOCK 記述に preset aware badge (grep count >= 15)"
else                         _record FAIL B "BLOCK 記述に preset aware badge (grep count >= 15)"
fi

if _case_c 2>/dev/null; then _record PASS C "_TASK_TEMPLATE.md + _DRAFT_TEMPLATE.md に pointer 継承"
else                         _record FAIL C "_TASK_TEMPLATE.md + _DRAFT_TEMPLATE.md に pointer 継承"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  printf '\nHINT: task-103 の DoD を再確認してください。\n'
  printf '  - preset pointer format: "> **現 effective preset は** \\`bash .claude/scripts/hc-config.sh --summary\\` で確認。..."\n'
  printf '  - preset aware badge: BLOCK 記述に "⚠️ preset aware" or "preset dependent" を suffix\n'
  exit 1
fi

exit 0
