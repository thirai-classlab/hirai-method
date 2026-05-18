#!/usr/bin/env bash
# git-destructive-deny-smoke.sh — Smoke test for the git destructive deny layer
# in .claude/hooks/delegation-guard.sh.
#
# 設計起源:
#   2026-05-18 user 指示「mainAgentでgitコマンドは基本的(破壊的変更以外)に
#   実行可能」を実装した commit b7eea6e (delegation-guard.sh L127-151) の
#   単体動作検証 smoke。next-actions entry #13。
#
# 対象 hook:
#   .claude/hooks/delegation-guard.sh の "git destructive deny" ブロック
#   (L127-L151 ぐらい、ECC_ALLOW_DESTRUCTIVE_GIT=1 で bypass)
#
# 検証範囲:
#   - Block cases (19): destructive git 操作が decision:"block" + reason に
#     "[git destructive guard]" を含むこと
#     (`git push -f` single space は 2026-05-18 hook fix で blockable 化:
#      regex を `push[[:space:]]+([^|;&]*[[:space:]])?-f([[:space:]]|$)` に修正)
#   - Pass cases (10): 非破壊 git 操作が block されないこと
#   - Bypass cases (3): ECC_ALLOW_DESTRUCTIVE_GIT=1 で block 解除されること
#
# 非対象:
#   - protected branch push deny (別 layer、commit ad2f7bc、本 smoke では
#     pass case の push を使わないことで切り分け)
#   - subagent context (delegation-guard 短絡経路、本 smoke は main agent
#     context で起動)
#
# 重要制約:
#   - file-top に `set -euo pipefail` を書かない (caller leak 防止教訓
#     `feedback_set_e_in_sourced_libs`)
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE を明示的に unset し、
#     marker dir に lock を作らない。
#
# 実行:
#   bash .claude/tests/git-destructive-deny-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/delegation-guard.sh"

# subagent 短絡経路を確実に閉じる (main agent 文脈で hook を起動するため)
unset CLAUDE_HARNESS_ROLE
unset ECC_ALLOW_DESTRUCTIVE_GIT

# 本 smoke は destructive deny layer 単体を検証する。
# protected branch push deny (別 layer、commit ad2f7bc) は同じ hook 内で動作し、
# `git push -f` 等の `-f` 形式 / refspec 省略時の current branch (main) も block する。
# layer 分離のため protected branch push を全 case で bypass する。
# pass cases に `git push origin <feature-branch>` 等を入れていないので bypass しても安全。
export ECC_ALLOW_PROTECTED_BRANCH_PUSH=1

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
# BrokenPipeError noise を抑制するため python3 で stdin を full read
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

# block 期待: decision="block" + reason が "[git destructive guard]" を含むこと
expect_block() {
  local label="$1"
  local cmd="$2"
  local out decision reason

  out=$(json_input "$cmd" | bash "$HOOK" Bash 2>&1)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")

  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -q '\[git destructive guard\]'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision)")
    printf "  FAIL: %s\n    cmd: %s\n    decision: %s\n    out: %s\n" "$label" "$cmd" "$decision" "$out"
  fi
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

# bypass 期待: env ECC_ALLOW_DESTRUCTIVE_GIT=1 で decision != "block"
expect_bypass_pass() {
  local label="$1"
  local cmd="$2"
  local out decision

  out=$(json_input "$cmd" | ECC_ALLOW_DESTRUCTIVE_GIT=1 bash "$HOOK" Bash 2>&1)
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

printf "===== git-destructive-deny-smoke (next-actions #13) =====\n\n"

printf "Block cases (19):\n"
expect_block "push --force"                    "git push --force"
# 2026-05-18 hook fix で blockable 化:
# 旧 regex `[^|;&]*[[:space:]]-f` は「push 直後の space と -f の前の space」の
# **2 space 要求**になっていたため `git push -f` (single space) が漏れていた。
# 新 regex `push[[:space:]]+([^|;&]*[[:space:]])?-f([[:space:]]|$)` で
# `-f` 前の optional segment 化により single / multi space 両対応に修正。
expect_block "push -f (single space)"          "git push -f"
expect_block "push origin main --force"        "git push origin main --force"
expect_block "reset --hard"                    "git reset --hard"
expect_block "reset --hard HEAD~1"             "git reset --hard HEAD~1"
expect_block "reset HEAD --hard"               "git reset HEAD --hard"
expect_block "branch -D feature-x"             "git branch -D feature-x"
expect_block "clean -f"                        "git clean -f"
expect_block "clean -fd"                       "git clean -fd"
expect_block "clean -fdx"                      "git clean -fdx"
expect_block "checkout -- src/foo.ts"          "git checkout -- src/foo.ts"
expect_block "restore --worktree src/"         "git restore --worktree src/"
expect_block "restore --source=HEAD --worktree src/" "git restore --source=HEAD --worktree src/"
expect_block "stash drop"                      "git stash drop"
expect_block "stash clear"                     "git stash clear"
expect_block "tag -d v1.0"                     "git tag -d v1.0"
expect_block "tag -f v1.0"                     "git tag -f v1.0"
expect_block "reflog expire --expire=now"      "git reflog expire --expire=now"
expect_block "gc --prune=now"                  "git gc --prune=now"

printf "\nPass cases (10):\n"
expect_pass  "status"                          "git status"
expect_pass  "diff"                            "git diff"
expect_pass  "log -5"                          "git log -5"
expect_pass  "add foo.txt"                     "git add foo.txt"
expect_pass  "commit -m"                       'git commit -m "msg"'
expect_pass  "branch -d (lowercase, merged delete)" "git branch -d feature-merged"
expect_pass  "rev-parse HEAD"                  "git rev-parse HEAD"
expect_pass  "show HEAD"                       "git show HEAD"
expect_pass  "fetch origin"                    "git fetch origin"
expect_pass  "pull origin feature/test"        "git pull origin feature/test"

printf "\nBypass cases (3, ECC_ALLOW_DESTRUCTIVE_GIT=1):\n"
expect_bypass_pass "push --force bypass"       "git push --force"
expect_bypass_pass "reset --hard bypass"       "git reset --hard"
expect_bypass_pass "clean -fdx bypass"         "git clean -fdx"

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
