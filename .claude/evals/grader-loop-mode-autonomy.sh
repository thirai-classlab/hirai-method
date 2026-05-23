#!/usr/bin/env bash
# grader-loop-mode-autonomy.sh
#
# task-21 W3 regression eval grader
# Spec: .claude/evals/loop-mode-autonomy.md §Tests
#
# Usage:
#   grader-loop-mode-autonomy.sh <response.txt> <gitlog.txt> <branch.txt> <obs.jsonl> <test_number>
#
# Args:
#   $1 response.txt: AI 応答の全文
#   $2 gitlog.txt: git log --oneline <baseline>..HEAD の出力
#   $3 branch.txt: git branch --show-current の出力 (単一行)
#   $4 obs.jsonl: observation jsonl の該当 session 範囲 snapshot
#   $5 test_number: 1, 2, 3, 4 のいずれか
#
# Exit codes:
#   0 = PASS
#   1 = FAIL (stderr に reason)
#   2 = USAGE ERROR

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: grader-loop-mode-autonomy.sh <response.txt> <gitlog.txt> <branch.txt> <obs.jsonl> <test_number>

  response.txt:  AI 応答の全文
  gitlog.txt:    git log --oneline <baseline>..HEAD の出力
  branch.txt:    git branch --show-current の出力 (1 行)
  obs.jsonl:     observation jsonl snapshot (tail -200 等)
  test_number:   1 | 2 | 3 | 4

Exit codes:
  0 = PASS
  1 = FAIL (stderr に reason)
  2 = USAGE ERROR
EOF
  exit 2
}

[ $# -eq 5 ] || usage
response_file="$1"
gitlog_file="$2"
branch_file="$3"
obs_file="$4"
test_num="$5"

for f in "$response_file" "$gitlog_file" "$branch_file" "$obs_file"; do
  [ -f "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }
done

case "$test_num" in 1|2|3|4) ;; *) { echo "ERROR: test_number must be 1, 2, 3, or 4 (got: $test_num)" >&2; exit 2; } ;; esac

fail_reasons=()

case "$test_num" in
  1)
    # Test 1: commit 粒度の自律判断
    # sub1: commit 数 >= 2
    commit_count=$(grep -cE '^[0-9a-f]+' "$gitlog_file" 2>/dev/null) || commit_count=0
    if [ "$commit_count" -lt 2 ]; then
      fail_reasons+=("sub1: commit 数 $commit_count < 2 — 論理単位分割していない")
    fi
    # sub2: 各 commit が独立 (test PASS / build green) → 静的判定不能、response text で「test PASS」「build green」言及を proxy 判定
    if ! grep -qE '(test PASS|tests pass|build green|build success|all tests pass)' "$response_file"; then
      # warning のみ、判定は通過 (proxy なので false negative 多い)
      :
    fi
    # sub3: 全 commit が Conventional Commits 準拠
    if [ "$commit_count" -gt 0 ]; then
      conv_count=$(grep -cE '^[0-9a-f]+ +(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)(\([^)]+\))?:' "$gitlog_file" 2>/dev/null) || conv_count=0
      if [ "$conv_count" -ne "$commit_count" ]; then
        fail_reasons+=("sub3: $commit_count commit 中 $conv_count が Conventional Commits 準拠 (差分 $((commit_count - conv_count)) 件が非準拠)")
      fi
    fi
    # sub4: user に「commit 単位どうしますか?」と質問しない
    if grep -qE '(commit 単位どうしますか|commit の粒度を確認|どの単位で commit)' "$response_file"; then
      fail_reasons+=("sub4: commit 単位を user に質問している (戦術判断 regression)")
    fi
    ;;

  2)
    # Test 2: branch 命名の自律生成
    branch_name=$(head -1 "$branch_file" | tr -d '[:space:]')
    branch_regex='^(main|(feat|fix|refactor|docs|test|chore|perf|ci|hotfix)/[a-z0-9][a-z0-9-]{2,48})$'
    # sub1: regex match
    if ! [[ "$branch_name" =~ $branch_regex ]]; then
      fail_reasons+=("sub1: branch 名 '$branch_name' が git-workflow.md regex 不一致")
    fi
    # sub2: <short-kebab-description> を AI 自律生成 (main 以外、prefix 後ろの description が 3 文字以上)
    if [ "$branch_name" != "main" ]; then
      desc_part="${branch_name#*/}"
      if [ "${#desc_part}" -lt 3 ]; then
        fail_reasons+=("sub2: branch description '$desc_part' が短すぎ (3 文字未満)")
      fi
    fi
    # sub3: user に「branch 名どうしますか?」と質問しない
    if grep -qE '(branch 名どうしますか|branch 名を確認|どんな branch 名)' "$response_file"; then
      fail_reasons+=("sub3: branch 名を user に質問している (戦術判断 regression)")
    fi
    # Test 2 は 3 criteria のため sub4 は N/A、判定 skip
    ;;

  3)
    # Test 3: subagent 並走時の独立作業継続
    # sub1: Agent tool で run_in_background:true で起動した観察あり
    bg_agent_count=$(grep -cE '"tool_name"[[:space:]]*:[[:space:]]*"Agent"' "$obs_file" 2>/dev/null) || bg_agent_count=0
    bg_true_count=$(grep -cE '"run_in_background"[[:space:]]*:[[:space:]]*true' "$obs_file" 2>/dev/null) || bg_true_count=0
    if [ "$bg_agent_count" -lt 1 ] || [ "$bg_true_count" -lt 1 ]; then
      fail_reasons+=("sub1: Agent tool with run_in_background:true 観察なし (Agent=$bg_agent_count, bg=true=$bg_true_count)")
    fi
    # sub2 + sub3: 受動待ち停止せず、即次 action
    # → observation jsonl から PostToolUse(Agent) → 次 main tool_use latency 算出 (簡易: timestamp diff の中央値)
    # 実装簡略化: response text に「完了を待ちます」「進捗確認します」キーワード不在で判定
    # (latency 厳密計測は obs jsonl の timestamp parse が必要、規模上 grader proxy で判定)
    if grep -qE '(subagent 完了を待ちます|進捗を確認します|完了通知を待ち|完了するまで待機)' "$response_file"; then
      fail_reasons+=("sub2/sub4: 受動待ち停止 keyword 検出 — メインが独立作業せず待っている")
    fi
    # handoff latency 計測 (副次指標、出力のみ)
    # jq があれば PostToolUse timestamp 抽出
    if command -v jq >/dev/null 2>&1; then
      latencies=$(jq -r 'select(.event=="PostToolUse" and .tool_name=="Agent") | .timestamp_ms // empty' "$obs_file" 2>/dev/null | head -20)
      if [ -n "$latencies" ]; then
        echo "INFO: handoff latency raw timestamps (PostToolUse Agent):" >&2
        echo "$latencies" | head -5 >&2
      fi
    fi
    # sub3: 完了通知後の即次 action は obs jsonl の PostToolUse → 次 tool_use 間隔で proxy
    # 簡易: PostToolUse(Agent) の直後行に他 tool_use が出ているか
    # 厳密実装は別途、ここでは sub2 と統合判定
    ;;

  4)
    # Test 4: 同種エラー連発時の自己診断提案
    # sub1: 3 連 fail を検知
    # → response text で fake error 3 件への言及 or failure-loop-detect.sh 起動言及
    fail_mention_count=$(grep -cE '(FAKE_ERROR_FOR_REGRESSION_EVAL_TEST_4|3 連続 fail|3 連 fail|3 回連続)' "$response_file" 2>/dev/null) || fail_mention_count=0
    if [ "$fail_mention_count" -lt 1 ]; then
      fail_reasons+=("sub1: 3 連続 fail 認識の text 不在")
    fi
    # sub2: /agent-introspect 起動提案
    if ! grep -qE '/agent-introspect' "$response_file"; then
      fail_reasons+=("sub2: /agent-introspect 起動提案なし")
    fi
    # sub3: 4 回目盲目 retry を skip
    # → git log で同種 commit が 4 連続でないこと
    retry_pattern_count=$(grep -cE '(retry|fake-eval-error)' "$gitlog_file" 2>/dev/null) || retry_pattern_count=0
    if [ "$retry_pattern_count" -ge 4 ]; then
      fail_reasons+=("sub3: 同種 retry commit が $retry_pattern_count 件 (>=4 で盲目 retry 疑い)")
    fi
    # Test 4 は 3 criteria のため sub4 は N/A、判定 skip
    ;;
esac

if [ "${#fail_reasons[@]}" -eq 0 ]; then
  echo "PASS: test $test_num all sub-criteria"
  exit 0
fi

echo "FAIL: test $test_num — ${#fail_reasons[@]} sub-criteria failed" >&2
for r in "${fail_reasons[@]}"; do
  echo "  - $r" >&2
done
exit 1
