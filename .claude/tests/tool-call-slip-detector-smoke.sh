#!/usr/bin/env bash
# tool-call-slip-detector-smoke.sh
#
# tool-call-slip-detector.sh (Stop hook) の動作検証。
# 6 ケース: positive 2 (standalone call / parameter 漏れ) + negative 2
# (clean prose / fence 内引用) + bypass 1 (env) + feature toggle off 1。
#
# 各ケースは fake transcript JSONL を生成し、stdin JSON で transcript_path を
# 渡して hook を実行、stdout の decision:block 有無を assert する。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/tool-call-slip-detector.sh"
TMPDIR_SMOKE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_SMOKE"' EXIT

pass=0
fail=0

# assistant text を 1 行 transcript JSONL として書き出す
# $1: 出力 path, $2: assistant text (改行は \n リテラルで渡す)
write_transcript() {
  local path="$1" text="$2"
  jq -nc --arg t "$text" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}' > "$path"
}

# hook を実行し stdout を返す
run_hook() {
  local tpath="$1"
  jq -nc --arg p "$tpath" '{transcript_path:$p}' | bash "$HOOK" 2>/dev/null
}

assert_detected() {
  local name="$1" out="$2"
  if printf '%s' "$out" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    echo "PASS: $name (detected)"; pass=$((pass+1))
  else
    echo "FAIL: $name (expected detection, got: ${out:-<empty>})"; fail=$((fail+1))
  fi
}

assert_clean() {
  local name="$1" out="$2"
  if [ -z "$out" ]; then
    echo "PASS: $name (silent)"; pass=$((pass+1))
  else
    echo "FAIL: $name (expected silent, got: $out)"; fail=$((fail+1))
  fi
}

# --- Case 1: standalone `call` 行 (positive) ---
t1="$TMPDIR_SMOKE/t1.jsonl"
write_transcript "$t1" "B/C 両方完了。両者の実 file 反映を grep/git で統合検証する。
call
git commit -m \"feat: x\"
統合検証 commit"
out1="$(run_hook "$t1")"
assert_detected "Case1 standalone-call" "$out1"

# --- Case 2: parameter タグ漏れ (positive、fence 外) ---
t2="$TMPDIR_SMOKE/t2.jsonl"
write_transcript "$t2" "検証を実行する。
<parameter name=\"description\">B/C成果の統合grep検証</parameter>"
out2="$(run_hook "$t2")"
assert_detected "Case2 parameter-leak" "$out2"

# --- Case 3: clean prose (negative) ---
t3="$TMPDIR_SMOKE/t3.jsonl"
write_transcript "$t3" "commit 成功 (2283f41)。残りは Step 4 を subagent で続行します。次に進めます。"
out3="$(run_hook "$t3")"
assert_clean "Case3 clean-prose" "$out3"

# --- Case 4: markup を fence 内で引用 (negative、meta 議論) ---
t4="$TMPDIR_SMOKE/t4.jsonl"
write_transcript "$t4" "slip の例を示します:
\`\`\`
call
<parameter name=\"description\">例</parameter>
\`\`\`
この通り fence 内なので誤検出しないはずです。"
out4="$(run_hook "$t4")"
assert_clean "Case4 fenced-quote" "$out4"

# --- Case 5: bypass env (negative) ---
t5="$TMPDIR_SMOKE/t5.jsonl"
write_transcript "$t5" "call
git status"
out5="$(ECC_TOOL_CALL_SLIP_OFF=1 run_hook "$t5")"
assert_clean "Case5 bypass-env" "$out5"

# --- Case 6: feature toggle off (negative、no-op) ---
t6="$TMPDIR_SMOKE/t6.jsonl"
write_transcript "$t6" "call
git status"
out6="$(HC_FEATURE_TOOL_CALL_SLIP_DETECT_ENABLED=false run_hook "$t6")"
assert_clean "Case6 feature-toggle-off" "$out6"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
