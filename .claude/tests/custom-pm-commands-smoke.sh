#!/usr/bin/env bash
# custom-pm-commands-smoke.sh — task #7 smoke test
# 6 ケースで /save-state /resume-state /pm-start + W2 hook を検証
#
# 注意: file-top に `set -euo pipefail` を書かない。
# caller (CI / 手実行) の shell flags に leak すると `cmd | head` で
# SIGPIPE → pipefail → errexit → 141 サイレント終了するため。
# 各 test 関数を `( set -uo pipefail; ... )` の subshell で起動して
# strict mode を test 内に局所化する。

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
FAILED_CASES=()

run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"

  if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
    echo "  PASS Case $case_id: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL Case $case_id: $desc"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

# Case 1: save-state.md が write_memory("session/context", ...) を mention
case_1() {
  grep -q 'write_memory("session/context"' "$PROJECT_ROOT/.claude/commands/save-state.md"
}

# Case 2: resume-state.md が read_memory("session/context") を mention + 復元レポート 4 項目
case_2() {
  grep -q 'read_memory("session/context")' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q '前回' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q '進捗' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q '次回' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q '課題' "$PROJECT_ROOT/.claude/commands/resume-state.md"
}

# Case 3: 3 command 全てに Serena 不在時 graceful error 案内が存在
case_3() {
  grep -q 'Serena MCP' "$PROJECT_ROOT/.claude/commands/save-state.md" && \
  grep -q 'Serena MCP' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q 'Serena MCP' "$PROJECT_ROOT/.claude/commands/pm-start.md"
}

# Case 4: mode-session-start.sh が memory file 存在チェック + /resume-state 言及
case_4() {
  local hook="$PROJECT_ROOT/.claude/hooks/mode-session-start.sh"
  grep -q '.serena/memories/session/context.md' "$hook" && \
  grep -q '/resume-state' "$hook"
}

# Case 5: 残存 /sc:(save|load|pm) が 「draft / task spec / list.md / 後継 command 自身 / .serena memories / workflow.md predecessor 記述 / rules-details/workflow/origin.md 歴史参照 / README migration doc / case-5-followup draft 逐語引用」 のみ
# task-74: anchor bug 修正 — grep -rl は cwd 相対で `./` prefix なし path を出力するため
# `^\./README\.md` 等の `^\./` anchor が match せず bleed していた。`(^\./)?` で prefix optional 化。
case_5() {
  local found
  found=$(cd "$PROJECT_ROOT" && grep -rlE '/sc:(save|load|pm)' \
    --include='*.md' --include='*.sh' --include='*.yml' . 2>/dev/null | \
    grep -vE '(docs/draft/custom-pm-commands\.md|docs/tasks/task-7-custom-pm-commands\.md|docs/tasks/list\.md|\.claude/commands/(save-state|resume-state|pm-start)\.md|\.claude/rules/workflow\.md|\.claude/rules-details/workflow/origin\.md|(^\./)?\.serena/|(^\./)?README\.md|(^\./)?docs/draft/custom-pm-case-5-followup\.md)' || true)
  [ -z "$found" ]
}

# Case 6: 3 command 全てに activate_project (onboarding 検知統合) Phase 1 必須実行
case_6() {
  grep -q 'activate_project' "$PROJECT_ROOT/.claude/commands/save-state.md" && \
  grep -q 'activate_project' "$PROJECT_ROOT/.claude/commands/resume-state.md" && \
  grep -q 'activate_project' "$PROJECT_ROOT/.claude/commands/pm-start.md"
}

echo "===== task #7 custom-pm-commands smoke test ====="
run_case 1 "save-state.md mentions write_memory(session/context)" case_1
run_case 2 "resume-state.md mentions read_memory + 4 report items" case_2
run_case 3 "3 commands mention Serena MCP graceful error" case_3
run_case 4 "mode-session-start.sh checks memory file + /resume-state" case_4
run_case 5 "grep /sc:(save|load|pm) zero (excl. allowed files)" case_5
run_case 6 "3 commands mandate activate_project (with onboarding check)" case_6

echo ""
echo "===== Result ====="
echo "PASS: $PASS / 6"
echo "FAIL: $FAIL / 6"
if [ $FAIL -gt 0 ]; then
  echo "Failed cases: ${FAILED_CASES[*]}"
  exit 1
fi
exit 0
