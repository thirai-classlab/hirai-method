#!/usr/bin/env bash
# test-confidence-gate.sh — smoke tests for confidence-gate.sh transcript extraction
#
# Verifies the improvements documented in feat/harness-improvement-2026-05-04:
#   1. tail size 200 -> 500: confidence near transcript boundary still detected
#   2. sidechain detection: transcript with isSidechain:true reads directly (no parent traversal)
#   3. regex variants: "Confidence: 0.X" / "信頼度: 0.X" / "confidence_score: 0.X" all match
#   4. tool_response fallback: when transcript missing, hook input tool_response provides text
#   5. no-match detailed log: bypass.log records failure phase + detail
#
# 既存 test-gate-disable.sh と同居して run-tests.sh から自動で動く。

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/confidence-gate.sh"
PASS=0
FAIL=0

# Sandbox state dir
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HC_CONFIDENCE_STATE_DIR="$TMP/conf"
mkdir -p "$HC_CONFIDENCE_STATE_DIR"

# Force gate ON (env > YAML override) so we exercise the real extraction path
export HC_CONFIDENCE_REQUIRED=true
export HC_CONFIDENCE_THRESHOLD=0.6
unset ECC_CONFIDENCE_GATE
unset ECC_F3_OFF

assert_pass() {
  local name="$1"
  local out="$2"
  # pass = empty {} JSON (or any output without "decision":"block")
  local compact
  compact=$(printf '%s' "$out" | tr -d '[:space:]')
  if [[ "$compact" != *'"decision":"block"'* ]]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected pass, got block: %s\n" "$name" "$out"
    FAIL=$((FAIL + 1))
  fi
}

assert_block() {
  local name="$1"
  local out="$2"
  local compact
  compact=$(printf '%s' "$out" | tr -d '[:space:]')
  if [[ "$compact" == *'"decision":"block"'* ]]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected block, got: %s\n" "$name" "$out"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: build a transcript JSONL with N filler lines + tail entries
make_transcript() {
  local path="$1"
  local filler_count="$2"
  shift 2
  : > "$path"
  local i=0
  while [ "$i" -lt "$filler_count" ]; do
    printf '{"type":"user","message":{"role":"user","content":"filler %d"}}\n' "$i" >> "$path"
    i=$((i + 1))
  done
  for line in "$@"; do
    printf '%s\n' "$line" >> "$path"
  done
}

# === Case 1: tail size 200 -> 500. ===
# Place an assistant "confidence: 0.85" so it survives the 500-line tail.
# 350 filler lines push old 200-tail past the assistant message; 500-tail catches it.
T1="$TMP/t1.jsonl"
ASSISTANT_LINE='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Implementation complete. confidence: 0.85"}]}}'
TAIL_FILLER_COUNT=300
{
  printf '%s\n' "$ASSISTANT_LINE"
  i=0
  while [ "$i" -lt "$TAIL_FILLER_COUNT" ]; do
    printf '{"type":"user","message":{"role":"user","content":"trailing %d"}}\n' "$i"
    i=$((i + 1))
  done
} > "$T1"
INPUT="{\"transcript_path\":\"$T1\"}"
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_pass "Case1: confidence detected within 500-line tail (~300 trailing filler)" "$out"

# === Case 2: sidechain detection - path contains /subagents/ ===
# Place transcript inside a /subagents/ subdir; assistant text has confidence; expect pass.
SIDE_DIR="$TMP/projects/abc/subagents"
mkdir -p "$SIDE_DIR"
T2="$SIDE_DIR/agent-side.jsonl"
{
  printf '{"isSidechain":true,"type":"user","message":{"role":"user","content":"task"}}\n'
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. confidence: 0.9"}]}}'
} > "$T2"
INPUT="{\"transcript_path\":\"$T2\"}"
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_pass "Case2: sidechain transcript (/subagents/ path) read directly" "$out"

# === Case 3: regex variants ===
T3a="$TMP/t3a.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. Confidence: 0.75"}]}}' > "$T3a"
out=$(printf '%s' "{\"transcript_path\":\"$T3a\"}" | bash "$HOOK" 2>/dev/null)
assert_pass "Case3a: 'Confidence:' (capitalized) variant" "$out"

T3b="$TMP/t3b.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. confidence_score: 0.8"}]}}' > "$T3b"
out=$(printf '%s' "{\"transcript_path\":\"$T3b\"}" | bash "$HOOK" 2>/dev/null)
assert_pass "Case3b: 'confidence_score:' variant" "$out"

T3c="$TMP/t3c.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"完了。信頼度: 0.95"}]}}' > "$T3c"
out=$(printf '%s' "{\"transcript_path\":\"$T3c\"}" | bash "$HOOK" 2>/dev/null)
assert_pass "Case3c: '信頼度:' Japanese variant" "$out"

# === Case 4: tool_response fallback ===
# transcript_path missing entirely; tool_response.content holds confidence.
INPUT='{"tool_response":{"content":[{"type":"text","text":"Result. confidence: 0.7"}]}}'
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_pass "Case4a: tool_response fallback (array of text blocks)" "$out"

# tool_response as a plain string
INPUT='{"tool_response":"Done with high confidence. Confidence: 0.88"}'
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_pass "Case4b: tool_response fallback (string payload)" "$out"

# tool_response present but below threshold -> block
INPUT='{"tool_response":{"content":[{"type":"text","text":"shaky. confidence: 0.3"}]}}'
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_block "Case4c: tool_response fallback but below threshold blocks" "$out"

# === Case 5: no-match detailed log ===
# Provide transcript with assistant text that has NO confidence marker -> regex_no_match.
# Then bypass.log should have a "failed: regex_no_match" line.
T5="$TMP/t5.jsonl"
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"All done, looks great"}]}}' > "$T5"
INPUT="{\"transcript_path\":\"$T5\"}"
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
assert_block "Case5a: no confidence variant -> block" "$out"
if grep -q "failed: regex_no_match" "$HC_CONFIDENCE_STATE_DIR/bypass.log" 2>/dev/null; then
  printf "PASS: Case5b: bypass.log records 'failed: regex_no_match'\n"
  PASS=$((PASS + 1))
else
  printf "FAIL: Case5b: bypass.log missing 'failed: regex_no_match'\n  log: %s\n" \
    "$(cat "$HC_CONFIDENCE_STATE_DIR/bypass.log" 2>/dev/null)"
  FAIL=$((FAIL + 1))
fi

# Case 5c: file_not_found logged when transcript path absent on disk
INPUT='{"transcript_path":"/no/such/path.jsonl"}'
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>/dev/null)
if grep -q "failed: file_not_found" "$HC_CONFIDENCE_STATE_DIR/bypass.log" 2>/dev/null; then
  printf "PASS: Case5c: bypass.log records 'failed: file_not_found'\n"
  PASS=$((PASS + 1))
else
  printf "FAIL: Case5c: bypass.log missing 'failed: file_not_found'\n  log: %s\n" \
    "$(cat "$HC_CONFIDENCE_STATE_DIR/bypass.log" 2>/dev/null)"
  FAIL=$((FAIL + 1))
fi

printf "\n--- test-confidence-gate.sh: %d pass / %d fail ---\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
