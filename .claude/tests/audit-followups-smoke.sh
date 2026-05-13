#!/usr/bin/env bash
# audit-followups-smoke.sh — task #9 smoke test
# 4 cases: W1 (F3 fail-open / F3 block) + W2 (Normal log / Loop block)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)。
#     subshell 関数化で局所化することで mode-loader.sh の SIGPIPE/exit 141 事故を防ぐ。
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行する。
#
# 実行:
#   bash .claude/tests/audit-followups-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIDENCE_HOOK="$PROJECT_ROOT/.claude/hooks/confidence-gate.sh"
AUTO_HOOK="$PROJECT_ROOT/.claude/hooks/autonomous-action-guard.sh"
TMP_DIR=$(mktemp -d "/tmp/audit-followups-smoke.XXXXXX")
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

# === Case 1: F3 fail-open (軽量 sidechain で confidence 不在) ===
# agent_type 空 + transcript なし → tool_response にも confidence なし
# 期待: HC_CONFIDENCE_MAJOR_AGENT_ONLY default (true) で fail-open ({}) で通る
case_1() {
  local transcript="$TMP_DIR/transcript-c1.jsonl"
  # transcript には assistant text あり (sidechain 模倣) だが confidence 記載なし
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"task done, no confidence here"}]}}' > "$transcript"
  local input
  input=$(jq -nc --arg t "$transcript" '{transcript_path:$t, agent_type:""}')
  local output
  output=$(printf '%s' "$input" | bash "$CONFIDENCE_HOOK" 2>/dev/null)
  # 期待: block 出力ではない (空 JSON {} で fail-open)
  if printf '%s' "$output" | grep -q '"decision":[[:space:]]*"block"'; then
    return 1
  fi
  return 0
}

# === Case 2: F3 block 維持 (general-purpose で confidence 不在) ===
# 期待: major subagent allowlist match のため block (現状動作維持)
case_2() {
  local transcript="$TMP_DIR/transcript-c2.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"completed task without confidence"}]}}' > "$transcript"
  local input
  input=$(jq -nc --arg t "$transcript" '{transcript_path:$t, agent_type:"general-purpose"}')
  local output
  output=$(printf '%s' "$input" | bash "$CONFIDENCE_HOOK" 2>/dev/null)
  # 期待: block (general-purpose は major subagent で confidence 必須)
  printf '%s' "$output" | grep -q '"decision":[[:space:]]*"block"'
}

# === Case 3: autonomous-action-guard Normal モード log ===
# Normal モードで禁止パターン (`git push`) → bypass.log に entry 追加
case_3() {
  local mode_file="$PROJECT_ROOT/.claude/mode.yml"
  local backup="$TMP_DIR/mode.yml.bak.c3"
  cp "$mode_file" "$backup"
  printf 'mode: normal\nasana_enabled: false\n' > "$mode_file"

  local log_file="$PROJECT_ROOT/.claude/.workflow-state/bypass.log"
  mkdir -p "$(dirname "$log_file")" 2>/dev/null
  local before_count=0
  [ -f "$log_file" ] && before_count=$(wc -l < "$log_file" | tr -d ' ')

  local input='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  CLAUDE_SESSION_ID="smoke-c3" \
    printf '%s' "$input" | bash "$AUTO_HOOK" >/dev/null 2>&1

  local after_count=0
  [ -f "$log_file" ] && after_count=$(wc -l < "$log_file" | tr -d ' ')

  # restore
  cp "$backup" "$mode_file"

  # 期待: line count が増えている + 末尾行に "mode-normal-restricted-cmd" を含む
  if [ "$after_count" -le "$before_count" ]; then
    return 1
  fi
  tail -n1 "$log_file" 2>/dev/null | grep -q "mode-normal-restricted-cmd"
}

# === Case 4: autonomous-action-guard Loop モード block 維持 ===
case_4() {
  local mode_file="$PROJECT_ROOT/.claude/mode.yml"
  local backup="$TMP_DIR/mode.yml.bak.c4"
  cp "$mode_file" "$backup"
  printf 'mode: loop\nasana_enabled: false\n' > "$mode_file"

  local input='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  local output
  output=$(printf '%s' "$input" | bash "$AUTO_HOOK" 2>/dev/null)

  # restore
  cp "$backup" "$mode_file"

  printf '%s' "$output" | grep -q '"decision":[[:space:]]*"block"'
}

printf '===== task #9 audit-followups smoke =====\n'
run_case 1 "F3 fail-open for minor sidechain (agent_type empty)" case_1
run_case 2 "F3 block maintained for general-purpose" case_2
run_case 3 "autonomous-action-guard Normal logs restricted cmd" case_3
run_case 4 "autonomous-action-guard Loop blocks restricted cmd" case_4

printf '\n===== Result =====\n'
printf 'PASS: %d / 4\n' "$PASS"
printf 'FAIL: %d / 4\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
