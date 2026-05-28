#!/usr/bin/env bash
# delegation-guard-search-whitelist-smoke.sh — Smoke test for the read-only search
# commands (grep / find / rg) added to the PATH-RESTRICTED section of
# .claude/bash-whitelist.txt (task-50 grep-whitelist-add).
#
# 設計起源:
#   - docs/draft/harness-health-improvements.md §3 task-50 (A): grep-whitelist-add
#   - docs/draft/harness-health-7items-analysis.md §9 task-50 行
#   - user 報告「Grep が使えない」 (問題 3): FleetView クライアントが Grep/Glob tool を
#     非提供 + bash grep も whitelist 外で二重に塞がる → bash grep を通せば
#     FleetView でも検索手段を確保できる。
#
# 対象:
#   .claude/bash-whitelist.txt の PATH-RESTRICTED セクションに追加した
#     ^grep( |$)
#     ^find( |$)
#     ^rg( |$)
#   これらは read-only な検索コマンドだが PATH-AWARE ではなく PATH-RESTRICTED に置く
#   ことで、src/ tests/ scripts/ を直接 inspect する形 (例: `grep pat src/foo.ts`) は
#   delegation-guard.sh 末尾の path-leak ガードで block され続ける (= 委譲原則を維持)。
#
# 検証範囲:
#   - whitelist 通過 (3 件): `grep pattern` / `find . -name x` / `rg pattern` が
#     decision != "block" (whitelist に登録され、かつ path-leak しないため通過)
#   - path-leak block (6 件): src/ tests/ scripts/ を直接引数に取る検索は
#     decision="block" + reason に "[サブエージェント委譲ルール]" を含むこと
#     (whitelist は通過するが path-leak ガードで block される = 委譲原則維持の実証)
#
# 重要制約:
#   - file-top に `set -euo pipefail` を書かない (caller leak 防止教訓
#     feedback_set_e_in_sourced_libs)
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE を明示的に unset する。
#
# 実行:
#   bash .claude/tests/delegation-guard-search-whitelist-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/delegation-guard.sh"

# subagent 短絡経路を確実に閉じる (main agent 文脈で hook を起動するため)
unset CLAUDE_HARNESS_ROLE

PASS=0
FAIL=0
FAILED_CASES=()

# tool_input.command を含む PreToolUse JSON を python3 で安全に組み立てる
json_input() {
  local cmd="$1"
  CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_input": {"command": os.environ["CMD"]}}))
'
}

# stdout から decision フィールドを抽出 (parse 失敗時は "parse_error")
extract_decision() {
  OUT_TEXT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT_TEXT"])
    print(d.get("decision", "none"))
except Exception:
    print("parse_error")
' 2>/dev/null
}

# stdout から reason フィールドを抽出
extract_reason() {
  OUT_TEXT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT_TEXT"])
    print(d.get("reason", ""))
except Exception:
    print("")
' 2>/dev/null
}

# pass 期待: decision != "block" ({} or allow JSON)
expect_pass() {
  local label="$1"
  local cmd="$2"
  local out decision

  out=$(json_input "$cmd" | bash "$HOOK" Bash 2>&1)
  decision=$(extract_decision "$out")

  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    cmd: %s\n    out: %s\n" "$label" "$cmd" "$out"
  fi
}

# path-leak block 期待: decision="block" + reason が
# "[サブエージェント委譲ルール]" を含むこと (path-leak ガードによる block)
expect_path_leak_block() {
  local label="$1"
  local cmd="$2"
  local out decision reason

  out=$(json_input "$cmd" | bash "$HOOK" Bash 2>&1)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q '\[サブエージェント委譲ルール\]'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    cmd: %s\n    decision: %s\n    out: %s\n" "$label" "$cmd" "$decision" "$out"
  fi
}

printf "===== delegation-guard-search-whitelist-smoke (task-50 grep-whitelist-add) =====\n\n"

printf "Whitelist pass cases (5):\n"
expect_pass "grep pattern"               "grep pattern"
expect_pass "grep -r pattern (no path)"  "grep -r pattern"
expect_pass "find . -name x"             "find . -name x"
expect_pass "rg pattern"                 "rg pattern"
expect_pass "rg -n pattern docs/"        "rg -n pattern docs/"

printf "\nPath-leak block cases (6):\n"
expect_path_leak_block "grep pat src/foo.ts"        "grep pat src/foo.ts"
expect_path_leak_block "grep -r pattern tests/"     "grep -r pattern tests/"
expect_path_leak_block "grep pat scripts/x.sh"      "grep pat scripts/x.sh"
expect_path_leak_block "find src/ -name x"          "find src/ -name x"
expect_path_leak_block "find tests/ -type f"        "find tests/ -type f"
expect_path_leak_block "rg pattern src/"            "rg pattern src/"

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf "\nFailed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  exit 1
fi
exit 0
