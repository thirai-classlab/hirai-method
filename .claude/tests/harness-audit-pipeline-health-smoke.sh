#!/usr/bin/env bash
# harness-audit-pipeline-health-smoke.sh — task-32 Phase 3 Step 3-2 smoke test
# 7 cases for harness-audit.py の observation pipeline 健全性指標 (Phase 1 + Phase 2)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範遵守)。
#     subshell 関数化で局所化することで SIGPIPE/exit 141 事故を防ぐ。
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行する。
#   - production observations.jsonl を参照せず、fixture-based 完全隔離。
#     HOME env override + global fallback path (HOME/.claude/homunculus/observations.jsonl) を使用。
#
# 実行:
#   bash .claude/tests/harness-audit-pipeline-health-smoke.sh
#
# 終了コード:
#   0 = 7/7 PASS / 1 = 1 件以上 FAIL

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/scripts/harness-audit.py"
FIXTURE_DIR="$PROJECT_ROOT/.claude/tests/fixtures"
TMP_DIR=$(mktemp -d "/tmp/harness-audit-pipeline-health-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# 期待値 (採用 5 条 3 「Step 完了条件は再現可能 / 機械検証可能な事実」遵守)
readonly EXPECTED_CASCADE_THRESHOLD_DEFAULT=5
readonly EXPECTED_CASCADE_MAX_CONSEC=5
readonly EXPECTED_SCATTER_MAX_CONSEC=1

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

# audit_fixture <fake_home> <fixture_path> [extra_env...]
#   - fake_home 配下に .claude/homunculus/observations.jsonl として fixture を配置
#   - HOME=<fake_home> 環境で harness-audit.py を JSON 出力で実行
#   - stdout に JSON 出力、stderr/exit code は呼出側で trap
audit_fixture() {
  local fake_home="$1"
  local fixture_path="$2"
  shift 2
  mkdir -p "$fake_home/.claude/homunculus"
  cp "$fixture_path" "$fake_home/.claude/homunculus/observations.jsonl"
  # 子 process 隔離: HOME override + extra env、git remote 経由の project_hash 検出を回避するため
  # cwd は TMP_DIR 配下に (git repo でない場所) する
  ( cd "$fake_home" && env "$@" HOME="$fake_home" python3 "$SCRIPT" --json --window 100 --no-stale-drafts --no-settings-drift 2>/dev/null )
}

# audit_fixture_markdown — human format で取得 (markdown 検証用)
audit_fixture_markdown() {
  local fake_home="$1"
  local fixture_path="$2"
  shift 2
  mkdir -p "$fake_home/.claude/homunculus"
  cp "$fixture_path" "$fake_home/.claude/homunculus/observations.jsonl"
  ( cd "$fake_home" && env "$@" HOME="$fake_home" python3 "$SCRIPT" --window 100 --no-stale-drafts --no-settings-drift 2>/dev/null )
}

# generate_consecutive_broken_fixture <out_path> <broken_count> [trailing_valid:0|1]
#   broken 連続 N 行 + (optional) valid 1 行 を生成
generate_consecutive_broken_fixture() {
  local out_path="$1"
  local broken_count="$2"
  local trailing_valid="${3:-1}"
  : > "$out_path"
  local i
  for i in $(seq 1 "$broken_count"); do
    printf 'broken-line-%d-not-json\n' "$i" >> "$out_path"
  done
  if [ "$trailing_valid" = "1" ]; then
    printf '{"tool_name":"Read","raw":{"path":"/tmp/v"},"timestamp":"2026-05-24T00:00:00Z"}\n' >> "$out_path"
  fi
}

# generate_split_broken_fixture <out_path>
#   broken 5 + valid 1 + broken 3 構造、max_consec_skips=5 が後半 3 で上書きされない検証用
generate_split_broken_fixture() {
  local out_path="$1"
  : > "$out_path"
  local i
  for i in 1 2 3 4 5; do
    printf 'broken-pre-%d\n' "$i" >> "$out_path"
  done
  printf '{"tool_name":"Read","raw":{"path":"/tmp/v"},"timestamp":"2026-05-24T00:00:00Z"}\n' >> "$out_path"
  for i in 1 2 3; do
    printf 'broken-post-%d\n' "$i" >> "$out_path"
  done
}

# === Case 1: cascade-sample.jsonl で cascade_suspected=True / max_consec=5 ===
case_1() {
  local home_dir="$TMP_DIR/c1"
  local out
  out=$(audit_fixture "$home_dir" "$FIXTURE_DIR/cascade-sample.jsonl") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
assert h.get("cascade_suspected") is True, f"cascade_suspected expected True, got {h.get('"'"'cascade_suspected'"'"')}"
assert h.get("max_consecutive_skips") == 5, f"max_consec expected 5, got {h.get('"'"'max_consecutive_skips'"'"')}"
assert h.get("cascade_threshold") == 5, f"threshold expected 5 (default), got {h.get('"'"'cascade_threshold'"'"')}"
' >&2
}

# === Case 2: normal-broken-scatter.jsonl で cascade_suspected=False / max_consec=1 ===
case_2() {
  local home_dir="$TMP_DIR/c2"
  local out
  out=$(audit_fixture "$home_dir" "$FIXTURE_DIR/normal-broken-scatter.jsonl") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
assert h.get("cascade_suspected") is False, f"cascade_suspected expected False, got {h.get('"'"'cascade_suspected'"'"')}"
assert h.get("max_consecutive_skips") == 1, f"max_consec expected 1, got {h.get('"'"'max_consecutive_skips'"'"')}"
' >&2
}

# === Case 3: 境界値 threshold-1 (broken 4 連続) で cascade_suspected=False / max_consec=4 ===
case_3() {
  local home_dir="$TMP_DIR/c3"
  local fix="$TMP_DIR/c3-broken4.jsonl"
  generate_consecutive_broken_fixture "$fix" 4 1
  local out
  out=$(audit_fixture "$home_dir" "$fix") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
assert h.get("cascade_suspected") is False, f"cascade_suspected expected False, got {h.get('"'"'cascade_suspected'"'"')}"
assert h.get("max_consecutive_skips") == 4, f"max_consec expected 4, got {h.get('"'"'max_consecutive_skips'"'"')}"
' >&2
}

# === Case 4: 境界値 threshold (5 連続) で cascade_suspected=True (cascade-sample 再利用) ===
case_4() {
  local home_dir="$TMP_DIR/c4"
  local out
  out=$(audit_fixture_markdown "$home_dir" "$FIXTURE_DIR/cascade-sample.jsonl") || return 1
  # markdown 出力 で cascade warning + heading + parse-skipped 行を verify
  printf '%s' "$out" | grep -q "Observation Pipeline 健全性" || return 1
  printf '%s' "$out" | grep -q "CASCADE FAIL SUSPECTED" || return 1
  printf '%s' "$out" | grep -q "parse-skipped" || return 1
}

# === Case 5: max_consecutive_skips upholding (broken5 + valid + broken3) ===
case_5() {
  local home_dir="$TMP_DIR/c5"
  local fix="$TMP_DIR/c5-split.jsonl"
  generate_split_broken_fixture "$fix"
  local out
  out=$(audit_fixture "$home_dir" "$fix") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
# 前半 5 連続で cascade trigger、後半 3 連続では max_consec が 5 のまま (上書きされない)
assert h.get("max_consecutive_skips") == 5, f"max_consec expected 5 (upheld, not overwritten by 3), got {h.get('"'"'max_consecutive_skips'"'"')}"
assert h.get("cascade_suspected") is True, f"cascade_suspected expected True, got {h.get('"'"'cascade_suspected'"'"')}"
' >&2
}

# === Case 6: HC_CASCADE_THRESHOLD env override ===
case_6() {
  # 6a: threshold=3 で scatter (max_consec=1) → cascade=False
  local home_dir_a="$TMP_DIR/c6a"
  local out_a
  out_a=$(audit_fixture "$home_dir_a" "$FIXTURE_DIR/normal-broken-scatter.jsonl" HC_CASCADE_THRESHOLD=3) || return 1
  printf '%s' "$out_a" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
assert h.get("cascade_threshold") == 3, f"threshold expected 3, got {h.get('"'"'cascade_threshold'"'"')}"
assert h.get("cascade_suspected") is False, f"cascade_suspected expected False (max_consec=1 < threshold=3), got {h.get('"'"'cascade_suspected'"'"')}"
' >&2 || return 1

  # 6b: threshold=3 で broken 3 連続 fixture → cascade=True
  local home_dir_b="$TMP_DIR/c6b"
  local fix_b="$TMP_DIR/c6b-broken3.jsonl"
  generate_consecutive_broken_fixture "$fix_b" 3 1
  local out_b
  out_b=$(audit_fixture "$home_dir_b" "$fix_b" HC_CASCADE_THRESHOLD=3) || return 1
  printf '%s' "$out_b" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
h = d.get("observation_health", {})
assert h.get("cascade_threshold") == 3, f"threshold expected 3, got {h.get('"'"'cascade_threshold'"'"')}"
assert h.get("cascade_suspected") is True, f"cascade_suspected expected True (max_consec=3 >= threshold=3), got {h.get('"'"'cascade_suspected'"'"')}"
' >&2
}

# === Case 7: HC_CASCADE_THRESHOLD invalid env (abc / 0 / -1) で全件 default 5 にfallback ===
case_7() {
  # cascade-sample (max_consec=5) を 3 invalid 値で audit、cascade_suspected が default 動作 (True) と同じか
  local invalid_values=("abc" "0" "-1")
  local v
  for v in "${invalid_values[@]}"; do
    local home_dir="$TMP_DIR/c7-${v//[^a-zA-Z0-9]/_}"
    local out
    out=$(audit_fixture "$home_dir" "$FIXTURE_DIR/cascade-sample.jsonl" HC_CASCADE_THRESHOLD="$v") || return 1
    printf '%s' "$out" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
h = d.get('observation_health', {})
assert h.get('cascade_threshold') == 5, f'threshold expected 5 (fallback from invalid=$v), got {h.get(\"cascade_threshold\")}'
assert h.get('cascade_suspected') is True, f'cascade_suspected expected True (5 consec >= default 5), got {h.get(\"cascade_suspected\")}'
" >&2 || return 1
  done
}

printf '===== task-32 Phase 3 pipeline-health smoke =====\n'
run_case 1 "cascade-sample fixture → cascade_suspected=True / max_consec=5" case_1
run_case 2 "normal-broken-scatter fixture → cascade_suspected=False / max_consec=1" case_2
run_case 3 "境界値 threshold-1 (broken 4 連続) → cascade_suspected=False / max_consec=4" case_3
run_case 4 "境界値 threshold (5 連続) + markdown 出力 (heading/warning/parse-skipped)" case_4
run_case 5 "max_consec upholding (broken5+valid+broken3) → max_consec=5 維持" case_5
run_case 6 "HC_CASCADE_THRESHOLD=3 env override (scatter=False / broken3=True)" case_6
run_case 7 "HC_CASCADE_THRESHOLD invalid (abc/0/-1) → default 5 fallback" case_7

printf '\n===== Result =====\n'
printf 'PASS: %d / 7\n' "$PASS"
printf 'FAIL: %d / 7\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
