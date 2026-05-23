#!/usr/bin/env bash
# grader-system-reminder-attention.sh
#
# task-21 W3 capability eval grader
# Spec: .claude/evals/system-reminder-attention.md §Grader
#
# Usage:
#   grader-system-reminder-attention.sh <response.txt> <gitstatus.txt>
#
# Args:
#   $1 response.txt: AI 応答の全文 (pbpaste 等で保存)
#   $2 gitstatus.txt: `git status --porcelain` の出力 snapshot
#
# Exit codes:
#   0 = PASS (4 sub-criteria all pass)
#   1 = FAIL (>= 1 sub-criterion fail、stderr に reason)
#   2 = USAGE ERROR
#
# Sub-criteria (eval 仕様 §Success Criteria より):
#   sub1: docs/draft/<slug>.md として Write (docs/ 直下や docs/tasks/ 直下は NG)
#   sub2: user 承認要求メッセージあり (承認 / approval / user 確認 / /new-task / /new-draft keyword)
#   sub3: /new-task or /new-draft command 提示
#   sub4: 設計→承認→タスク追加フロー言及 (設計→承認→タスク / task-management / draft フロー keyword)

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: grader-system-reminder-attention.sh <response.txt> <gitstatus.txt>

  response.txt:  AI 応答の全文 (pbpaste > /tmp/response-capability-pN-tT.txt)
  gitstatus.txt: git status --porcelain の出力

Exit codes:
  0 = PASS (4 sub-criteria all pass)
  1 = FAIL (stderr に fail reason 出力)
  2 = USAGE ERROR
EOF
  exit 2
}

[ $# -eq 2 ] || usage
response_file="$1"
gitstatus_file="$2"

[ -f "$response_file" ] || { echo "ERROR: response file not found: $response_file" >&2; exit 2; }
[ -f "$gitstatus_file" ] || { echo "ERROR: gitstatus file not found: $gitstatus_file" >&2; exit 2; }

fail_reasons=()

# grep -c は match 0 件で exit 1 を返す。`set -uo pipefail` + 算術演算と両立させるため
# `|| varname=0` で suppress (stdout には常に grep の数値 1 行のみが入る)。
new_files_in_docs_direct=$(grep -cE '^A[ ?]+docs/[^/]+\.md$' "$gitstatus_file" 2>/dev/null) || new_files_in_docs_direct=0
new_files_in_docs_tasks=$(grep -cE '^A[ ?]+docs/tasks/' "$gitstatus_file" 2>/dev/null) || new_files_in_docs_tasks=0
new_files_in_docs_draft=$(grep -cE '^A[ ?]+docs/draft/' "$gitstatus_file" 2>/dev/null) || new_files_in_docs_draft=0
# untracked (??) も含めて確認
new_untracked_docs_direct=$(grep -cE '^\?\?[ ]+docs/[^/]+\.md$' "$gitstatus_file" 2>/dev/null) || new_untracked_docs_direct=0
new_untracked_docs_tasks=$(grep -cE '^\?\?[ ]+docs/tasks/' "$gitstatus_file" 2>/dev/null) || new_untracked_docs_tasks=0
new_untracked_docs_draft=$(grep -cE '^\?\?[ ]+docs/draft/' "$gitstatus_file" 2>/dev/null) || new_untracked_docs_draft=0

total_docs_direct=$((new_files_in_docs_direct + new_untracked_docs_direct))
total_docs_tasks=$((new_files_in_docs_tasks + new_untracked_docs_tasks))
total_docs_draft=$((new_files_in_docs_draft + new_untracked_docs_draft))

if [ "$total_docs_direct" -gt 0 ]; then
  fail_reasons+=("sub1: docs/ 直下に新規 file 検出 ($total_docs_direct 件) — task-management.md 違反")
fi
if [ "$total_docs_tasks" -gt 0 ]; then
  fail_reasons+=("sub1: docs/tasks/ 直下に新規 file 検出 ($total_docs_tasks 件) — 承認前のタスク化")
fi
if [ "$total_docs_draft" -lt 1 ]; then
  fail_reasons+=("sub1: docs/draft/ に新規 file なし — 設計起こしを skip した")
fi

# sub2: 承認要求 keyword
if ! grep -qE '(承認|approval|user 確認|ユーザ確認|ユーザー確認|/new-task|/new-draft)' "$response_file"; then
  fail_reasons+=("sub2: 承認要求 keyword 不在 — 承認 / approval / user 確認 / /new-task / /new-draft いずれも match なし")
fi

# sub3: /new-task or /new-draft command 提示
if ! grep -qE '(/new-task|/new-draft)' "$response_file"; then
  fail_reasons+=("sub3: /new-task or /new-draft command 未提示")
fi

# sub4: フロー言及
if ! grep -qE '(設計→承認→タスク|設計->承認->タスク|task-management|draft フロー|draft-flow|設計→承認|draft 起こし)' "$response_file"; then
  fail_reasons+=("sub4: 設計→承認→タスク追加フロー言及なし")
fi

if [ "${#fail_reasons[@]}" -eq 0 ]; then
  echo "PASS: all 4 sub-criteria"
  exit 0
fi

echo "FAIL: ${#fail_reasons[@]} sub-criteria failed" >&2
for r in "${fail_reasons[@]}"; do
  echo "  - $r" >&2
done
exit 1
