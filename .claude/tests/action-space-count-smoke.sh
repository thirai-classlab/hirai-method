#!/usr/bin/env bash
# action-space-count-smoke.sh — task-72 Step 3/6 smoke test
#
# 目的:
#   (1) 退避検証 (regression guard): user 選択の 4 agent category + 11 skill が
#       discover path (.claude/agents/ , .claude/skills/) から消え archive へ移ったこと
#   (2) 能力喪失なし検証: 残す 6 category + keep-9 agent が discover path に残存すること
#   (3) count budget (warn のみ): agent / skill の現 discover 数を INFO 出力。
#       ≤25 目標は user 選択により未達 (76 agents) なので hard assert にしない。
#       退避が実際に起きたこと (count が退避前より減) のみ assert する。
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)。
#     各 case 関数は ( set -uo pipefail; ... ) でラップして実行する。
#
# 実行:
#   bash .claude/tests/action-space-count-smoke.sh
#
# 終了コード:
#   0 = 全 PASS / 1 = 1 件以上 FAIL (count budget warn は exit code に影響しない)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
ARCHIVE_AGENTS="$PROJECT_ROOT/.claude/archive/agents"
ARCHIVE_SKILLS="$PROJECT_ROOT/.claude/archive/skills"

# 退避前の discover 数 (移動前の実測値、count 減を検証する基準)
AGENTS_BEFORE=144
SKILLS_BEFORE=63
# count budget 目標 (warn のみ、hard fail でない)
AGENT_COUNT_TARGET=25

ARCHIVED_CATEGORIES=(02-language-specialists 05-data-ai 07-specialized-domains 08-business-product)
ARCHIVED_SKILLS=(document-docx document-pdf document-pptx document-xlsx image-enhancer slack-gif-creator video-downloader competitive-ads-extractor twitter-algorithm-optimizer developer-growth-analysis meeting-insights-analyzer)
KEEP_CATEGORIES=(01-core-development 03-infrastructure 04-quality-security 06-developer-experience 09-meta-orchestration 10-research-analysis)
KEEP_AGENTS=(qa-expert test-automator code-reviewer refactoring-specialist architect-reviewer ui-designer api-designer security-auditor debugger)

PASS=0
FAIL=0
FAILED_CASES=()

run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
    printf '  PASS  %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

# === Case A: 退避した 4 category が .claude/agents/ から消え archive にある ===
case_a() {
  local c
  for c in "${ARCHIVED_CATEGORIES[@]}"; do
    [ -d "$AGENTS_DIR/$c" ]   && return 1   # discover path に残っていたら FAIL
    [ -d "$ARCHIVE_AGENTS/$c" ] || return 1 # archive に無ければ FAIL
  done
  return 0
}

# === Case B: 退避した 11 skill が .claude/skills/ から消え archive にある ===
case_b() {
  local s
  for s in "${ARCHIVED_SKILLS[@]}"; do
    [ -d "$SKILLS_DIR/$s" ]    && return 1
    [ -d "$ARCHIVE_SKILLS/$s" ] || return 1
  done
  return 0
}

# === Case C: 残す 6 category が .claude/agents/ に残存 ===
case_c() {
  local c
  for c in "${KEEP_CATEGORIES[@]}"; do
    [ -d "$AGENTS_DIR/$c" ] || return 1
  done
  return 0
}

# === Case D: keep-9 agent が .claude/agents/ に残存 (能力喪失なし) ===
case_d() {
  local a f
  for a in "${KEEP_AGENTS[@]}"; do
    f=$(find "$AGENTS_DIR" -name "$a.md" 2>/dev/null | head -1)
    [ -n "$f" ] || return 1
  done
  return 0
}

# === Case E: 退避が実際に起きた (discover count が退避前より減) ===
case_e() {
  local agents skills
  agents=$(find "$AGENTS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  skills=$(find "$SKILLS_DIR" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$agents" -lt "$AGENTS_BEFORE" ] || return 1
  [ "$skills" -lt "$SKILLS_BEFORE" ] || return 1
  return 0
}

printf '===== task-72 action-space-count smoke =====\n'
run_case A "archived 4 categories absent from agents/ and present in archive/" case_a
run_case B "archived 11 skills absent from skills/ and present in archive/" case_b
run_case C "kept 6 categories remain in agents/" case_c
run_case D "keep-9 agents remain in agents/" case_d
run_case E "discover count decreased vs pre-archive baseline" case_e

# === count budget (INFO + warn のみ、exit code に影響しない) ===
AGENTS_NOW=$(find "$AGENTS_DIR" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
SKILLS_NOW=$(find "$SKILLS_DIR" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
printf '\n===== count budget (INFO) =====\n'
printf 'agents discover: %s (before archive: %s)\n' "$AGENTS_NOW" "$AGENTS_BEFORE"
printf 'skills discover: %s (before archive: %s)\n' "$SKILLS_NOW" "$SKILLS_BEFORE"
if [ "$AGENTS_NOW" -gt "$AGENT_COUNT_TARGET" ]; then
  printf 'WARN: agent count %s exceeds budget target %s (user 選択により許容、hard fail せず)\n' "$AGENTS_NOW" "$AGENT_COUNT_TARGET"
fi

printf '\n===== Result =====\n'
printf 'PASS: %d / %d\n' "$PASS" "$((PASS+FAIL))"
printf 'FAIL: %d / %d\n' "$FAIL" "$((PASS+FAIL))"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
