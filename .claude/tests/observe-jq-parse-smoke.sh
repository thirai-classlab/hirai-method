#!/usr/bin/env bash
# observe-jq-parse-smoke.sh — task next-actions #18 W1 smoke for observe.sh
#
# 設計起源:
#   docs/draft/observe-jq-parse-fix.md §3 W1 (2026-05-23)
#
# 対象 script:
#   .claude/skills/continuous-learning-v2/hooks/observe.sh
#
# 検証範囲 (4 ケース):
#   Case 1: nested 改行 + escape quote を含む tool_input.content
#           → observations.jsonl record が jq-valid、raw.tool_input.content が原 string と一致
#   Case 2: unicode (絵文字 + 漢字) を含む tool_input.content
#           → jq-valid、content 一致
#   Case 3: 通常 payload (escape 不要)
#           → jq-valid、既存挙動と一致 (regression)
#   Case 4: 巨大 payload (10 KB +)
#           → jq-valid、truncation なし
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - live ~/.claude/homunculus を絶対に汚染しない (HOMUNCULUS_DIR で隔離)
#   - mktemp -d で隔離した tmp dir で実施
#
# 実行:
#   bash .claude/tests/observe-jq-parse-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OBSERVE="$REPO_ROOT/.claude/skills/continuous-learning-v2/hooks/observe.sh"

if [ ! -x "$OBSERVE" ]; then
  printf 'FAIL: %s not executable\n' "$OBSERVE" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# 隔離 HOMUNCULUS_DIR を session 全体で 1 つ用意
BASE=$(mktemp -d 2>/dev/null) || {
  printf 'FAIL: mktemp -d failed\n' >&2
  exit 1
}
trap 'rm -rf "$BASE"' EXIT

# common env
# CLAUDE_PROJECT_DIR は repo root を渡して project hash 検出を安定化
# (実 hook と同じ git remote 経由の project_id が生成される)
run_observe() {
  local input="$1"
  HOMUNCULUS_DIR="$BASE" \
  CLAUDE_PROJECT_DIR="$REPO_ROOT" \
  printf '%s' "$input" | HOMUNCULUS_DIR="$BASE" CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$OBSERVE"
}

# observations.jsonl の path を解決 (project hash 経由で 1 つだけ存在するはず)
find_obs_file() {
  find "$BASE" -name 'observations.jsonl' -type f 2>/dev/null | head -1
}

# observations.jsonl をクリアして次 case を実行できるようにする
reset_obs() {
  find "$BASE" -name 'observations.jsonl' -type f -delete 2>/dev/null || true
}

# 最終 record を取得
last_record() {
  local obs_file
  obs_file=$(find_obs_file)
  if [ -z "$obs_file" ] || [ ! -s "$obs_file" ]; then
    return 1
  fi
  tail -1 "$obs_file"
}

# ===== Case 1: nested 改行 + escape quote =====
case1() {
  reset_obs
  # tool_input.content: literal "line1\nline2\n\"escaped\"" (JSON escaped)
  local input='{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"content":"line1\nline2\n\"escaped\""}}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 1: observations.jsonl が空")
    return 1
  }

  # record 自体が jq-valid
  if ! printf '%s' "$rec" | jq -e '.tool' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 1: record が jq-invalid: $rec")
    return 1
  fi

  # raw.tool_input.content が原 string と一致
  local got
  got=$(printf '%s' "$rec" | jq -r '.raw.tool_input.content // empty' 2>/dev/null)
  local expected
  expected=$(printf 'line1\nline2\n"escaped"')
  if [ "$got" != "$expected" ]; then
    FAILED_CASES+=("Case 1: content mismatch. got=<$got> expected=<$expected>")
    return 1
  fi

  return 0
}

# ===== Case 2: unicode (絵文字 + 漢字) =====
case2() {
  reset_obs
  local input='{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"content":"✨ 設計 done"}}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 2: observations.jsonl が空")
    return 1
  }

  if ! printf '%s' "$rec" | jq -e '.tool' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 2: record が jq-invalid: $rec")
    return 1
  fi

  local got
  got=$(printf '%s' "$rec" | jq -r '.raw.tool_input.content // empty' 2>/dev/null)
  if [ "$got" != "✨ 設計 done" ]; then
    FAILED_CASES+=("Case 2: unicode content mismatch. got=<$got>")
    return 1
  fi

  return 0
}

# ===== Case 3: 通常 payload (regression) =====
case3() {
  reset_obs
  local input='{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 3: observations.jsonl が空")
    return 1
  }

  if ! printf '%s' "$rec" | jq -e '.tool' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 3: record が jq-invalid: $rec")
    return 1
  fi

  # 既存 schema fields が揃っているか
  local tool event
  tool=$(printf '%s' "$rec" | jq -r '.tool')
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$tool" != "Bash" ] || [ "$event" != "PostToolUse" ]; then
    FAILED_CASES+=("Case 3: schema regression. tool=<$tool> event=<$event>")
    return 1
  fi

  # raw が object として保持されているか (string ではない)
  local raw_type
  raw_type=$(printf '%s' "$rec" | jq -r '.raw | type')
  if [ "$raw_type" != "object" ]; then
    FAILED_CASES+=("Case 3: raw が object 以外 ($raw_type)、schema 互換性 NG")
    return 1
  fi

  local cmd
  cmd=$(printf '%s' "$rec" | jq -r '.raw.tool_input.command // empty')
  if [ "$cmd" != "ls -la" ]; then
    FAILED_CASES+=("Case 3: raw.tool_input.command mismatch. got=<$cmd>")
    return 1
  fi

  return 0
}

# ===== Case 4: 巨大 payload (10 KB +) =====
case4() {
  reset_obs
  # 10 KB +: 1024 byte * 12 ≈ 12 KB の content
  local big
  big=$(printf 'A%.0s' $(seq 1 12288))
  # JSON safe: A は escape 不要
  local input
  input=$(jq -nc --arg content "$big" '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{content:$content}}')
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 4: observations.jsonl が空")
    return 1
  }

  if ! printf '%s' "$rec" | jq -e '.tool' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 4: record が jq-invalid (large payload)")
    return 1
  fi

  local got_len
  got_len=$(printf '%s' "$rec" | jq -r '.raw.tool_input.content | length' 2>/dev/null)
  if [ "$got_len" != "12288" ]; then
    FAILED_CASES+=("Case 4: content length mismatch. got=$got_len expected=12288 (truncation suspected)")
    return 1
  fi

  return 0
}

# ===== run =====
run_case() {
  local name="$1" fn="$2"
  if "$fn"; then
    PASS=$((PASS + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$name"
  fi
}

printf '=== observe-jq-parse-smoke ===\n'
printf 'OBSERVE: %s\n' "$OBSERVE"
printf 'BASE: %s\n\n' "$BASE"

run_case "Case 1: nested newline + escape quote" case1
run_case "Case 2: unicode (emoji + kanji)" case2
run_case "Case 3: normal payload (regression)" case3
run_case "Case 4: large payload (12 KB)" case4

printf '\n=== Summary ===\n'
printf 'PASS: %d / FAIL: %d\n' "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf '\nFailed cases:\n'
  for c in "${FAILED_CASES[@]}"; do
    printf '  - %s\n' "$c"
  done
  exit 1
fi

exit 0
