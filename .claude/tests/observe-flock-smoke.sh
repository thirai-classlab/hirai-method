#!/usr/bin/env bash
# observe-flock-smoke.sh — task-53 (observe-sh-flock) 並行 append 排他化 smoke
#
# 設計起源:
#   docs/draft/harness-health-improvements.md §3 task-53 (C)
#   docs/draft/harness-health-7items-analysis.md §9 task-53 行
#
# 対象 script:
#   .claude/skills/continuous-learning-v2/hooks/observe.sh
#   (L211 付近の `printf '%s\n' "$obs" >> observations.jsonl` を排他化)
#
# 検証範囲 (3 ケース):
#   Case 1: N 並列 append で record 数 == 投入数 (lost write 0)
#   Case 2: N 並列 append で全 record が valid JSON (interleave corruption 0)
#   Case 3: 単発 append regression (lock 導入後も 1 record が正常 append)
#
# 真因 (classlab で 122 件 corruption 実証):
#   lock 無しの並行 `>>` append は record interleave で JSON 破損する。
#   大きい record は 1 write() に収まらず PIPE_BUF を超えて split されるため。
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - live ~/.claude/homunculus を絶対に汚染しない (HOMUNCULUS_DIR で隔離)
#   - mktemp -d で隔離した tmp dir で実施
#   - bash 3.2 互換 (wait -n / 連想配列を使わない)
#
# 実行:
#   bash .claude/tests/observe-flock-smoke.sh
#
# 終了コード:
#   0 = 3/3 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OBSERVE="$REPO_ROOT/.claude/skills/continuous-learning-v2/hooks/observe.sh"

# 並列数 (env で上書き可、interleave を誘発するため大きめ default)
N="${SMOKE_N:-48}"
# burst 回数 (同一 file へ R 回 burst して contention を蓄積、lock 無しなら高確率で corruption)
R="${SMOKE_R:-3}"

if [ ! -x "$OBSERVE" ]; then
  printf 'FAIL: %s not executable\n' "$OBSERVE" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

BASE=$(mktemp -d 2>/dev/null) || {
  printf 'FAIL: mktemp -d failed\n' >&2
  exit 1
}
trap 'rm -rf "$BASE"' EXIT

# observations.jsonl の path を解決 (project hash 経由で 1 つだけ存在するはず)
find_obs_file() {
  find "$BASE" -name 'observations.jsonl' -type f 2>/dev/null | head -1
}

reset_obs() {
  find "$BASE" -name 'observations.jsonl' -type f -delete 2>/dev/null || true
}

# 1 件の observe.sh を起動 (大きい content で interleave を誘発)
# $1 = marker (各 process を一意に識別する index)
run_one() {
  local marker="$1"
  # 約 8 KB の content (PIPE_BUF を超えるサイズで record split を誘発)
  local big
  big=$(printf 'X%.0s' $(seq 1 8192))
  local input
  input=$(jq -nc --arg m "$marker" --arg c "$big" \
    '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{content:$c,marker:$m}}')
  printf '%s' "$input" | HOMUNCULUS_DIR="$BASE" CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$OBSERVE"
}

# N 並列起動 → 全 child を wait (bash 3.2 互換: pid 配列を収集して個別 wait)
fire_parallel() {
  local n="$1"
  local pids=()
  local i
  for ((i = 1; i <= n; i++)); do
    run_one "$i" &
    pids+=("$!")
  done
  local p
  for p in "${pids[@]}"; do
    wait "$p" 2>/dev/null || true
  done
}

# ===== Case 1: N 並列 × R burst で record 数 == 投入数 (lost write 0) =====
# 同一 observations.jsonl へ R 回 burst (各 N 並列) を蓄積。
# lock 無しなら interleave/lost write が累積し record 数 != N*R になる。
EXPECTED_TOTAL=$((N * R))
case1() {
  reset_obs
  local r
  for ((r = 1; r <= R; r++)); do
    fire_parallel "$N"
  done

  local obs_file
  obs_file=$(find_obs_file)
  if [ -z "$obs_file" ] || [ ! -s "$obs_file" ]; then
    FAILED_CASES+=("Case 1: observations.jsonl が空 (N*R=$EXPECTED_TOTAL 投入したのに 0 件)")
    return 1
  fi

  local lines
  lines=$(wc -l < "$obs_file" | tr -d ' ')
  if [ "$lines" != "$EXPECTED_TOTAL" ]; then
    FAILED_CASES+=("Case 1: record 数不一致. got=$lines expected=$EXPECTED_TOTAL (lost write or interleave)")
    return 1
  fi

  return 0
}

# ===== Case 2: 全 record が valid JSON (interleave corruption 0) =====
case2() {
  # Case 1 で書いた obs_file をそのまま検証 (reset しない)
  local obs_file
  obs_file=$(find_obs_file)
  if [ -z "$obs_file" ] || [ ! -s "$obs_file" ]; then
    FAILED_CASES+=("Case 2: observations.jsonl が空")
    return 1
  fi

  # 各行を jq -e で検証、corruption 件数をカウント
  local corrupt=0
  local total=0
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    total=$((total + 1))
    if ! printf '%s' "$line" | jq -e '.tool' >/dev/null 2>&1; then
      corrupt=$((corrupt + 1))
    fi
  done < "$obs_file"

  if [ "$corrupt" -ne 0 ]; then
    FAILED_CASES+=("Case 2: corruption 検出. $corrupt / $total 行が invalid JSON (record interleave)")
    return 1
  fi

  return 0
}

# ===== Case 3: 単発 append regression =====
case3() {
  reset_obs
  local input='{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  printf '%s' "$input" | HOMUNCULUS_DIR="$BASE" CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$OBSERVE"

  local obs_file
  obs_file=$(find_obs_file)
  if [ -z "$obs_file" ] || [ ! -s "$obs_file" ]; then
    FAILED_CASES+=("Case 3: 単発 append で observations.jsonl が空")
    return 1
  fi

  local lines
  lines=$(wc -l < "$obs_file" | tr -d ' ')
  if [ "$lines" != "1" ]; then
    FAILED_CASES+=("Case 3: 単発 append で record 数 != 1 (got=$lines)")
    return 1
  fi

  local rec
  rec=$(tail -1 "$obs_file")
  if ! printf '%s' "$rec" | jq -e '.tool' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 3: 単発 record が jq-invalid")
    return 1
  fi

  local tool
  tool=$(printf '%s' "$rec" | jq -r '.tool')
  if [ "$tool" != "Bash" ]; then
    FAILED_CASES+=("Case 3: tool 不一致 (got=$tool)")
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

printf '=== observe-flock-smoke ===\n'
printf 'OBSERVE: %s\n' "$OBSERVE"
printf 'BASE: %s\n' "$BASE"
printf 'N (parallel): %s / R (bursts): %s / total: %s\n\n' "$N" "$R" "$((N * R))"

run_case "Case 1: N*R parallel append, record count == N*R" case1
run_case "Case 2: all records valid JSON (corruption 0)" case2
run_case "Case 3: single append regression" case3

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
