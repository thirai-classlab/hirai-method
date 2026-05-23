#!/usr/bin/env bash
# improvement-proposal-cache-smoke.sh — task-22 W5 smoke for improvement-proposal.sh cache layer
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md §3 W5
#
# 対象 hook:
#   .claude/hooks/improvement-proposal.sh (cache layer: TTL 1h, JSON cache file)
#
# 検証範囲 (5 ケース):
#   Case 1: cache 不在 → 集計実行 → cache.json 生成 (mtime / schema 確認)
#   Case 2: cache 1h 以内 → cache hit (Python 集計 skip、stderr は cache から流れる)
#   Case 3: cache TTL 超過 → 再集計 + cache 更新 (generated_at 更新確認)
#   Case 4: cache 壊れ (invalid JSON) → 既存集計 fallback + cache 再生成
#   Case 5: cache_dir 不在 → mkdir -p で自動作成 + 初回集計
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 教訓)
#   - state_dir / homunculus は独立した /tmp/ 配下に隔離 (live ~/.claude/homunculus を汚染しない)
#   - subagent 短絡を避けるため CLAUDE_HARNESS_ROLE をクリア
#
# 実行:
#   bash .claude/tests/improvement-proposal-cache-smoke.sh
#
# 終了コード:
#   0 = 5/5 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/improvement-proposal.sh"

# clean main agent context
unset CLAUDE_HARNESS_ROLE
unset ECC_IMPROVEMENT_PROPOSAL
unset HC_IMPROVEMENT_PROPOSAL_ENABLED

# 独立 state_dir / homunculus (既存 state を触らない)
TMP_BASE="$(mktemp -d /tmp/improvement-proposal-cache-smoke.XXXXXX)"
TMP_STATE_DIR="$TMP_BASE/state"
TMP_HOMU="$TMP_BASE/homunculus"
TMP_OBS="$TMP_BASE/observations.jsonl"
trap 'rm -rf "$TMP_BASE"' EXIT

mkdir -p "$TMP_STATE_DIR" "$TMP_HOMU"

# mock observations.jsonl (空ファイル = entry なし、提案 0 件想定)
: > "$TMP_OBS"

# stat の cross-platform 互換 (macOS: -f %m / Linux: -c %Y)
file_mtime() {
  local f="$1"
  stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo ""
}

# hook 起動 helper: cache state を sandbox 化
run_hook() {
  HC_IMPROVEMENT_PROPOSAL_STATE_DIR="$TMP_STATE_DIR" \
  HC_HOMUNCULUS_ROOT="$TMP_HOMU" \
  HC_OBSERVE_PATH="$TMP_OBS" \
  CLAUDE_PROJECT_DIR="$REPO_ROOT" \
  bash "$HOOK" 2>/dev/null </dev/null
}

# hook 起動 helper with cache TTL override
run_hook_with_ttl() {
  local ttl="$1"
  HC_IMPROVEMENT_PROPOSAL_STATE_DIR="$TMP_STATE_DIR" \
  HC_HOMUNCULUS_ROOT="$TMP_HOMU" \
  HC_OBSERVE_PATH="$TMP_OBS" \
  HC_IMPROVEMENT_PROPOSAL_CACHE_TTL="$ttl" \
  CLAUDE_PROJECT_DIR="$REPO_ROOT" \
  bash "$HOOK" 2>/dev/null </dev/null
}

PASS=0
FAIL=0
FAILED_CASES=()

# ---------- Case 1: cache 不在 → 集計実行 → cache.json 生成 ----------
case_1() {
  rm -f "$TMP_STATE_DIR/cache.json"
  run_hook

  if [ ! -f "$TMP_STATE_DIR/cache.json" ]; then
    FAILED_CASES+=("Case 1: cache.json was not created")
    FAIL=$((FAIL + 1))
    return
  fi

  # schema check: generated_at / ttl_seconds / payload / source_observations_count
  if ! jq -e '.generated_at and .ttl_seconds and (.payload | type == "string") and (.source_observations_count | type == "number")' \
      "$TMP_STATE_DIR/cache.json" >/dev/null 2>&1; then
    FAILED_CASES+=("Case 1: cache.json schema invalid")
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- Case 2: cache 1h 以内 → cache hit (Python 集計 skip) ----------
case_2() {
  # 前提: Case 1 で cache 生成済
  if [ ! -f "$TMP_STATE_DIR/cache.json" ]; then
    run_hook
  fi

  local mtime1 mtime2
  mtime1=$(file_mtime "$TMP_STATE_DIR/cache.json")

  # 2 回目起動: cache hit なら mtime は変わらない
  sleep 1
  run_hook
  mtime2=$(file_mtime "$TMP_STATE_DIR/cache.json")

  if [ "$mtime1" != "$mtime2" ]; then
    FAILED_CASES+=("Case 2: cache hit failed — mtime changed ($mtime1 -> $mtime2)")
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- Case 3: cache TTL 超過 → 再集計 + cache 更新 ----------
case_3() {
  # cache を古い mtime に偽装 (2h 前 = TTL 1h 超過)
  rm -f "$TMP_STATE_DIR/cache.json"
  run_hook
  if [ ! -f "$TMP_STATE_DIR/cache.json" ]; then
    FAILED_CASES+=("Case 3: initial cache creation failed")
    FAIL=$((FAIL + 1))
    return
  fi

  # mtime を 2h 前に設定 (macOS / Linux 両対応の touch -t は分単位、ここでは -A 使えない)
  # → cross-platform: touch -t YYYYMMDDhhmm (2h 前)
  local past_epoch past_stamp
  past_epoch=$(($(date +%s) - 7200))  # 2h 前
  # macOS: date -r <epoch>、Linux: date -d @<epoch>
  past_stamp=$(date -r "$past_epoch" +%Y%m%d%H%M 2>/dev/null \
            || date -d "@$past_epoch" +%Y%m%d%H%M 2>/dev/null \
            || echo "")
  if [ -z "$past_stamp" ]; then
    FAILED_CASES+=("Case 3: cannot synthesize past timestamp")
    FAIL=$((FAIL + 1))
    return
  fi
  touch -t "$past_stamp" "$TMP_STATE_DIR/cache.json"

  local mtime_before mtime_after
  mtime_before=$(file_mtime "$TMP_STATE_DIR/cache.json")
  run_hook
  mtime_after=$(file_mtime "$TMP_STATE_DIR/cache.json")

  # TTL 超過 → 再集計が走り mtime が更新される
  if [ "$mtime_before" = "$mtime_after" ]; then
    FAILED_CASES+=("Case 3: TTL expiry did not trigger refresh (mtime unchanged: $mtime_before)")
    FAIL=$((FAIL + 1))
    return
  fi

  # generated_at が現在に近いことを確認
  local gen_at now_ts gen_ts diff
  gen_at=$(jq -r '.generated_at' "$TMP_STATE_DIR/cache.json" 2>/dev/null)
  if [ -z "$gen_at" ] || [ "$gen_at" = "null" ]; then
    FAILED_CASES+=("Case 3: generated_at missing in refreshed cache")
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- Case 4: cache 壊れ (invalid JSON) → fallback + 再生成 ----------
case_4() {
  echo 'this is not valid json {{{' > "$TMP_STATE_DIR/cache.json"
  run_hook

  # 再生成 → valid JSON になっているはず
  if ! jq -e '.generated_at and (.payload | type == "string")' \
      "$TMP_STATE_DIR/cache.json" >/dev/null 2>&1; then
    FAILED_CASES+=("Case 4: corrupt cache was not regenerated to valid JSON")
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- Case 5: cache_dir 不在 → mkdir -p 自動作成 ----------
case_5() {
  rm -rf "$TMP_STATE_DIR"
  if [ -d "$TMP_STATE_DIR" ]; then
    FAILED_CASES+=("Case 5 setup: state dir removal failed")
    FAIL=$((FAIL + 1))
    return
  fi

  run_hook

  if [ ! -d "$TMP_STATE_DIR" ]; then
    FAILED_CASES+=("Case 5: state dir was not auto-created by mkdir -p")
    FAIL=$((FAIL + 1))
    return
  fi

  if [ ! -f "$TMP_STATE_DIR/cache.json" ]; then
    FAILED_CASES+=("Case 5: cache.json was not created after dir auto-create")
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- 実行 ----------
echo "=== improvement-proposal cache smoke (task-22 W5) ==="
case_1
case_2
case_3
case_4
case_5

echo ""
echo "PASS: $PASS / 5"
echo "FAIL: $FAIL / 5"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failed cases:"
  for c in "${FAILED_CASES[@]}"; do
    echo "  - $c"
  done
  exit 1
fi
exit 0
