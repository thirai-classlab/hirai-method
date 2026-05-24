#!/usr/bin/env bash
# harness-audit-pipeline-health-smoke.sh — task-32 Phase 3 Step 3-2 smoke test
# 8 cases for harness-audit.py の observation pipeline 健全性指標 (Phase 1 + Phase 2)
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
#   SMOKE_VERBOSE=1 bash ...   # 全 case の output を表示 (debug 用)
#
# 終了コード:
#   0 = 8/8 PASS / 1 = 1 件以上 FAIL
#
# iter4 fix:
#   - B-1 (PRT-4a): Case 1 に skipped_lines / total_lines / observation_health key 存在 assert
#   - B-2 (PRT-4b): Case 1 に raw_object_count / raw_object_rate assert
#   - B-3 (QA-9/N-2): FAIL 時 stderr/stdout 表示 + SMOKE_VERBOSE=1 で常時表示
#   - B-4 (N-3): grep multibyte locale dependency 解消 (ASCII-only に簡略化)
#   - B-5 (TDD-3): Case 8 として empty observations path を追加

# B-4 fix: grep multibyte locale dependency 解消のため LC_ALL を C.UTF-8 に固定 (default C は
# multibyte 日本語の grep が glibc 環境で失敗するため)。本 smoke は Case 4 の markdown 出力で
# 「Observation Pipeline」(ASCII) を検索する形に簡略化済だが、localized error message が混じる
# possibility を考えて defensive に固定する。
export LC_ALL=C.UTF-8

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$PROJECT_ROOT/.claude/scripts/harness-audit.py"
FIXTURE_DIR="$PROJECT_ROOT/.claude/tests/fixtures"
TMP_DIR=$(mktemp -d "/tmp/harness-audit-pipeline-health-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# 期待値 (採用 5 条 3 「Step 完了条件は再現可能 / 機械検証可能な事実」遵守)
readonly EXPECTED_CASCADE_THRESHOLD_DEFAULT=5
readonly EXPECTED_CASCADE_MAX_CONSEC=5
readonly EXPECTED_SCATTER_MAX_CONSEC=1
# Case 1 の cascade-sample.jsonl 構造 (9 lines):
#   L1, L2  = valid records (2 件)
#   L3-L7   = broken (5 件、cascade trigger)
#   L8, L9  = valid records (2 件)
# 合計: total=9 / skipped=5 / valid=4 / raw_object 全件 → rate=1.0
readonly EXPECTED_CASE1_TOTAL=9
readonly EXPECTED_CASE1_SKIPPED=5
readonly EXPECTED_CASE1_RAW_OBJECT=4
readonly EXPECTED_CASE1_RAW_RATE=1.0

PASS=0
FAIL=0
FAILED_CASES=()
TOTAL_CASES=8

# run_case <id> <desc> <test_fn>
#   B-3 fix: FAIL 時のみ stderr/stdout を表示 (SMOKE_VERBOSE=1 で常時表示)
#   旧実装は ">/dev/null 2>&1" で全 output を捨てていたため、CI 上でデバッグ困難だった。
run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  local output rc
  output=$( ( set -uo pipefail; "$test_fn" ) 2>&1 )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    if [ "${SMOKE_VERBOSE:-0}" = "1" ] && [ -n "$output" ]; then
      printf '    [output]\n%s\n' "$output" | sed 's/^/      /'
    fi
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s (exit %d)\n' "$case_id" "$desc" "$rc"
    if [ -n "$output" ]; then
      printf '    [output]\n%s\n' "$output" | sed 's/^/      /' >&2
    fi
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

# audit_empty <fake_home>
#   B-5 用: observations.jsonl が存在しない fake_home で audit を実行 (empty path)
audit_empty() {
  local fake_home="$1"
  shift
  mkdir -p "$fake_home/.claude/homunculus"
  # 意図的に observations.jsonl は配置しない
  ( cd "$fake_home" && env "$@" HOME="$fake_home" python3 "$SCRIPT" --json --window 100 --no-stale-drafts --no-settings-drift 2>/dev/null )
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

# === Case 1: cascade-sample.jsonl で cascade_suspected=True / max_consec=5 +
#             skipped_lines=5 / total_lines=9 / raw_object_rate=1.0 / raw_object_count=4 ===
case_1() {
  local home_dir="$TMP_DIR/c1"
  local out
  out=$(audit_fixture "$home_dir" "$FIXTURE_DIR/cascade-sample.jsonl") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
# B-1 (PRT-4a): observation_health key 存在 + skipped_lines / total_lines assert
assert "observation_health" in d, "observation_health key missing in JSON output"
h = d["observation_health"]
assert h.get("cascade_suspected") is True, f"cascade_suspected expected True, got {h.get('"'"'cascade_suspected'"'"')}"
assert h.get("max_consecutive_skips") == 5, f"max_consec expected 5, got {h.get('"'"'max_consecutive_skips'"'"')}"
assert h.get("cascade_threshold") == 5, f"threshold expected 5 (default), got {h.get('"'"'cascade_threshold'"'"')}"
assert h.get("skipped_lines") == 5, f"skipped_lines expected 5, got {h.get('"'"'skipped_lines'"'"')}"
assert h.get("total_lines") == 9, f"total_lines expected 9, got {h.get('"'"'total_lines'"'"')}"
# B-2 (PRT-4b): raw_object_rate / raw_object_count assert (valid 4 件全てが raw=dict)
obs = d.get("observations", {})
assert obs.get("raw_object_count") == 4, f"raw_object_count expected 4, got {obs.get('"'"'raw_object_count'"'"')}"
assert obs.get("raw_object_rate") == 1.0, f"raw_object_rate expected 1.0, got {obs.get('"'"'raw_object_rate'"'"')}"
assert obs.get("raw_present_count") == 4, f"raw_present_count expected 4, got {obs.get('"'"'raw_present_count'"'"')}"
'
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
'
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
'
}

# === Case 4: 境界値 threshold (5 連続) で cascade_suspected=True (cascade-sample 再利用) ===
case_4() {
  local home_dir="$TMP_DIR/c4"
  local out
  out=$(audit_fixture_markdown "$home_dir" "$FIXTURE_DIR/cascade-sample.jsonl") || return 1
  # markdown 出力 で cascade warning + heading + parse-skipped 行を verify
  # B-4 fix: ASCII-only に簡略化 (multibyte 日本語 grep 依存解消)
  printf '%s' "$out" | grep -q "Observation Pipeline" || return 1
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
'
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
' || return 1

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
'
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
" || return 1
  done
}

# === Case 8 (B-5 / TDD-3): empty observations path (observations.jsonl 不在) ===
#   total_lines=0 / cascade_suspected=False / observation_health key 存在 を確認
#   fmt_observation_health の early-return path (集計対象 line なし) を test 経路に含める
case_8() {
  local home_dir="$TMP_DIR/c8"
  local out
  out=$(audit_empty "$home_dir") || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
# observation_health key 存在 (path 不在でも default 構造で必ず生成される)
assert "observation_health" in d, "observation_health key missing for empty observations path"
h = d["observation_health"]
assert h.get("total_lines") == 0, f"total_lines expected 0 for empty path, got {h.get('"'"'total_lines'"'"')}"
assert h.get("skipped_lines") == 0, f"skipped_lines expected 0 for empty path, got {h.get('"'"'skipped_lines'"'"')}"
assert h.get("cascade_suspected") is False, f"cascade_suspected expected False for empty path, got {h.get('"'"'cascade_suspected'"'"')}"
assert h.get("max_consecutive_skips") == 0, f"max_consec expected 0, got {h.get('"'"'max_consecutive_skips'"'"')}"
# observations も empty summary 構造 (records=[] → empty literal return)
obs = d.get("observations", {})
assert obs.get("total") == 0, f"obs.total expected 0, got {obs.get('"'"'total'"'"')}"
assert obs.get("raw_present_count") == 0, f"raw_present_count expected 0, got {obs.get('"'"'raw_present_count'"'"')}"
# B-5: rate calc 不能 (raw_present=0) なら 0.0 を返す schema を確認 (docstring と整合)
assert obs.get("raw_object_rate") == 0.0, f"raw_object_rate expected 0.0 (no data), got {obs.get('"'"'raw_object_rate'"'"')}"
# iter4 PY-4 fix: tool_errors key が empty でも存在することを確認
assert "tool_errors" in obs, "tool_errors key missing in empty summary"
'
}

printf '===== task-32 Phase 3 pipeline-health smoke =====\n'
run_case 1 "cascade-sample fixture → cascade_suspected=True / max_consec=5 + skipped/total/raw asserts" case_1
run_case 2 "normal-broken-scatter fixture → cascade_suspected=False / max_consec=1" case_2
run_case 3 "境界値 threshold-1 (broken 4 連続) → cascade_suspected=False / max_consec=4" case_3
run_case 4 "境界値 threshold (5 連続) + markdown 出力 (heading/warning/parse-skipped)" case_4
run_case 5 "max_consec upholding (broken5+valid+broken3) → max_consec=5 維持" case_5
run_case 6 "HC_CASCADE_THRESHOLD=3 env override (scatter=False / broken3=True)" case_6
run_case 7 "HC_CASCADE_THRESHOLD invalid (abc/0/-1) → default 5 fallback" case_7
run_case 8 "empty observations path → total_lines=0 / cascade=False / raw_rate=0.0 (TDD-3)" case_8

printf '\n===== Result =====\n'
printf 'PASS: %d / %d\n' "$PASS" "$TOTAL_CASES"
printf 'FAIL: %d / %d\n' "$FAIL" "$TOTAL_CASES"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
