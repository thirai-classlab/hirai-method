#!/usr/bin/env bash
# delegation-guard-readonly-filter-smoke.sh — task-68 Step 5 (§A 強化)
# (delegation-guard splitter 誤検知修正、read-only filter whitelist 追加).
#
# 設計起源:
#   - docs/draft/harness-design-fundamental-review.md §3.4 (delegation-guard splitter
#     の改行/pipe 誤検知修正、C4 対処)。
#   - user 報告: main の Bash を pipe (`| head`, `| tail`, `| wc`) で segment 分割 →
#     各 segment を whitelist 照合する現実装が、pipe 先の read-only filter を whitelist
#     不在で誤 BLOCK していた (本見直しセッション中だけで複数回発火)。
#
# 対象:
#   .claude/bash-whitelist.txt の PATH-RESTRICTED セクションに追加した read-only filter:
#     ^head( |$) / ^tail( |$) / ^wc( |$) / ^sort( |$) / ^uniq( |$)
#     ^nl( |$) / ^cut( |$) / ^tr( |$) / ^column( |$)
#   申請: .claude/bash-whitelist-requests/2026-06-01-readonly-filters.md
#
# 検証範囲:
#   A. whitelist pass (pipe 先 read-only filter): 旧 BLOCK → PASS になる新挙動 (7 件)
#   B. read-only filter 単体 / 非保護 path pass (13 件): 既存 8 件 + nl/tr/cut/column pipe/stdin 5 件
#   C1. 危険 git deny 不変 (destructive + pipe filter) (3 件)
#   C2. protected branch push deny 不変 (pipe filter 付き) (3 件: stg-preview 追加)
#   C3. read-only filter で保護パス inspect → path-leak block 不変 (6 件: tr/cut 追加)
#      ※ C3 は「保護パスへの直接 wc/head 等」と「tr/cut < src/ リダイレクト」両ケースで
#        [サブエージェント委譲ルール] が維持されることを確認する。
#   C4. 副作用系コマンドは whitelist 未追加で依然 BLOCK (委譲ルール) (6 件: sed/awk 追加)
#   C5. --force-with-lease boundary (2 件): feat と main 両方 [git destructive guard] でBLOCK
#
# 重要制約:
#   - file-top に `set -euo pipefail` を書かない (caller leak 防止教訓
#     feedback_set_e_in_sourced_libs)
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE を明示的に unset する。
#
# 実行:
#   bash .claude/tests/delegation-guard-readonly-filter-smoke.sh
#   cd /tmp && bash <repo_root>/.claude/tests/delegation-guard-readonly-filter-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/delegation-guard.sh"

# [code HIGH-1] cwd 非依存化: hook の HC_BASH_WHITELIST_PATH=.claude/bash-whitelist.txt を
# 解決するため、最初の test case 実行前に REPO_ROOT へ cd する。別 dir 実行時の false FAIL 解消。
cd "$REPO_ROOT" || exit 1

# subagent 短絡経路を確実に閉じる (main agent 文脈で hook を起動するため)
unset CLAUDE_HARNESS_ROLE
unset ECC_ALLOW_DESTRUCTIVE_GIT
unset ECC_ALLOW_PROTECTED_BRANCH_PUSH

PASS=0
FAIL=0
FAILED_CASES=()

json_input() {
  local cmd="$1"
  CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_input": {"command": os.environ["CMD"]}}))
'
}

extract_decision() {
  # stderr を捨てて stdout のみ parse (config-loader WARN 等の混入を防ぐ)
  OUT_TEXT="$1" python3 -c '
import os, json
try:
    d = json.loads(os.environ["OUT_TEXT"])
    print(d.get("decision", "none"))
except Exception:
    print("parse_error")
' 2>/dev/null
}

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
# stdout のみを取得 (2>/dev/null で config-loader WARN を除去)
expect_pass() {
  local label="$1"
  local cmd="$2"
  local out decision
  out=$(json_input "$cmd" | bash "$HOOK" Bash 2>/dev/null)
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

# block 期待: decision="block" + reason が指定 marker を含むこと
expect_block_marker() {
  local label="$1"
  local cmd="$2"
  local marker="$3"
  local out decision reason
  out=$(json_input "$cmd" | bash "$HOOK" Bash 2>/dev/null)
  decision=$(extract_decision "$out")
  reason=$(extract_reason "$out")
  if [ "$decision" = "block" ] && printf '%s' "$reason" | grep -qF "$marker"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (decision=$decision, marker='$marker')")
    printf "  FAIL: %s\n    cmd: %s\n    decision: %s\n    out: %s\n" "$label" "$cmd" "$decision" "$out"
  fi
}

printf "===== delegation-guard-readonly-filter-smoke (task-68 Step 5 §A) =====\n\n"

printf "A. pipe 先 read-only filter pass (旧 BLOCK → PASS、誤検知修正) (7):\n"
expect_pass "git push feature | tail -5"   "git push origin feat/x | tail -5"
expect_pass "git log | wc -l"              "git log --oneline | wc -l"
expect_pass "git log | head"               "git log | head"
expect_pass "git diff | head -20"          "git diff | head -20"
expect_pass "ls | sort | uniq"             "ls | sort | uniq"
expect_pass "git status | wc -l"           "git status | wc -l"
expect_pass "git log | head | tail"        "git log | head -5 | tail -2"

# [qa HIGH-1] 残り 4 コマンド nl/tr/cut/column の pipe 後段 + head 単体
printf "\nB. read-only filter 単体 / 非保護 path pass (13):\n"
expect_pass "head -20 docs/x.md"           "head -20 docs/x.md"
expect_pass "tail -5 docs/x.md"            "tail -5 docs/x.md"
expect_pass "wc -l docs/x.md"             "wc -l docs/x.md"
expect_pass "sort docs/x.md"              "sort docs/x.md"
expect_pass "uniq docs/x.md"              "uniq docs/x.md"
expect_pass "nl docs/x.md"               "nl docs/x.md"
expect_pass "cut -d: -f1 docs/x.md"       "cut -d: -f1 docs/x.md"
expect_pass "column -t docs/x.md"         "column -t docs/x.md"
expect_pass "head stdin (no path)"         "head"
expect_pass "git log --oneline | nl"       "git log --oneline | nl"
expect_pass "git log --oneline | tr ':' '-'"  "git log --oneline | tr ':' '-'"
expect_pass "git log --oneline | cut -d' ' -f1"  "git log --oneline | cut -d' ' -f1"
expect_pass "git log --oneline | column -t"  "git log --oneline | column -t"

printf "\nC1. 危険 git deny 不変 (destructive、pipe filter 付き) (3):\n"
expect_block_marker "push --force | head"        "git push --force | head"        "[git destructive guard]"
expect_block_marker "reset --hard | tail"        "git reset --hard | tail"        "[git destructive guard]"
expect_block_marker "clean -fdx | wc -l"         "git clean -fdx | wc -l"         "[git destructive guard]"

# [qa MED-5] stg-preview (stg 含み名) + pipe → protected branch push deny 維持
printf "\nC2. protected branch push deny 不変 (pipe filter 付き) (3):\n"
expect_block_marker "push origin main | tail"       "git push origin main | tail"       "[protected branch push deny]"
expect_block_marker "push origin stg | head"        "git push origin stg | head"        "[protected branch push deny]"
expect_block_marker "push origin stg-preview | head" "git push origin stg-preview | head" "[protected branch push deny]"

# [qa MED-5 + security/test MED-1] 保護パス直接 inspect は path-leak でBLOCK維持。
# wc/head/tail は non-protected path では pass (B セクション) だが、
# src/ tests/ scripts/ を引数に取ると [サブエージェント委譲ルール] が発動する。
# tr/cut の stdin リダイレクト (`< src/foo.ts`) も同様に path-leak で BLOCK。
printf "\nC3. read-only filter で保護パス inspect → path-leak block 不変 (6):\n"
expect_block_marker "head src/foo.ts"                 "head src/foo.ts"                "[サブエージェント委譲ルール]"
expect_block_marker "tail -5 tests/x.sh"              "tail -5 tests/x.sh"             "[サブエージェント委譲ルール]"
expect_block_marker "wc -l scripts/x.sh"              "wc -l scripts/x.sh"             "[サブエージェント委譲ルール]"
expect_block_marker "cat .claude/x | head; wc src/y"  "cat .claude/x | head ; wc -l src/y" "[サブエージェント委譲ルール]"
expect_block_marker "tr -d 'x' < src/foo.ts"          "tr -d 'x' < src/foo.ts"         "[サブエージェント委譲ルール]"
expect_block_marker "cut -f1 scripts/install.sh"      "cut -f1 scripts/install.sh"     "[サブエージェント委譲ルール]"

# [qa HIGH-2] C4 marker を `[Bash 委譲ルール] 未承認コマンド:` に具体化。
# [qa MED-3] sed / awk (処理系 pipe) も BLOCK 維持を確認。
printf "\nC4. 副作用系コマンドは whitelist 未追加で依然 BLOCK (委譲ルール) (6):\n"
expect_block_marker "rm via pipe target"         "git log | rm -rf x"             "[Bash 委譲ルール] 未承認コマンド:"
expect_block_marker "tee not whitelisted"        "git log | tee out.txt"          "[Bash 委譲ルール] 未承認コマンド:"
expect_block_marker "xargs not whitelisted"      "git log | xargs rm"             "[Bash 委譲ルール] 未承認コマンド:"
expect_block_marker "cat bare not whitelisted"   "git log | cat /etc/hosts"       "[Bash 委譲ルール] 未承認コマンド:"
expect_block_marker "sed pipe (processing) block"  "git log | sed 's/x/y/'"       "[Bash 委譲ルール] 未承認コマンド:"
expect_block_marker "awk pipe (processing) block"  "git log | awk '{print}'"      "[Bash 委譲ルール] 未承認コマンド:"

# [test MED-2] --force-with-lease boundary:
# 現行 hook は --force-with-lease も `push[[:space:]]+[^|;&]*--force` にマッチして
# [git destructive guard] でBLOCK (feat/x も main も同一扱い)。
# hook 本体無変更のため、実動作に合わせて両方 block として記録。
printf "\nC5. --force-with-lease boundary (git destructive guard でBLOCK) (2):\n"
expect_block_marker "force-with-lease feat/x | tail"  "git push --force-with-lease origin feat/x | tail"  "[git destructive guard]"
expect_block_marker "force-with-lease main | tail"    "git push --force-with-lease origin main | tail"    "[git destructive guard]"

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
