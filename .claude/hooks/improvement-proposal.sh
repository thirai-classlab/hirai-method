#!/usr/bin/env bash
# improvement-proposal.sh — SessionStart hook that surfaces self-improvement hints.
#
# Orchestrator: env load + kill switch + cache check + Python aggregate dispatch + output flush.
# 集計 / cache / heuristics logic は lib/improvement-proposal/ に分割。
#
# 設計原則:
#   - fail-open: jq / python3 が無くても、または読み取り失敗でも exit 0
#   - noisy にしない: 提案 0 件なら何も出さない、dedup で同提案を 24h 以内に再表示しない
#   - data 駆動: heuristics は Python 側に集約 (lib/improvement-proposal/aggregate.py)
#   - cache: 集計結果を TTL 1h で cache し SessionStart 時間を短縮 (lib/improvement-proposal/cache.sh)
#   - kill switch:
#       ECC_IMPROVEMENT_PROPOSAL=off          → 全 skip
#       HC_IMPROVEMENT_PROPOSAL_ENABLED=false → 全 skip
#       HC_IMPROVEMENT_PROPOSAL_CACHE_ENABLED=false → cache skip (常に再集計)
#
# Stdin:  SessionStart hook JSON（読むが現状未使用）
# Stdout: 空
# Stderr: 提案行 + フッター 1 行（提案 1+ 件のときのみ）
# Exit:   常に 0

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled improvement_proposal; then
  exit 0   # feature OFF で no-op
fi

# shellcheck source=lib/improvement-proposal/cache.sh
. "$SCRIPT_DIR/lib/improvement-proposal/cache.sh"

# stdin を捨てる
cat >/dev/null 2>&1 || true

# kill switch (env > config)
if [ "${ECC_IMPROVEMENT_PROPOSAL:-}" = "off" ]; then
  exit 0
fi
case "${HC_IMPROVEMENT_PROPOSAL_ENABLED:-true}" in
  false|False|FALSE|0|no|off) exit 0 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# project root を決定（CLAUDE_PROJECT_DIR > git toplevel > pwd）
PROJ_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJ_ROOT" ] || [ ! -d "$PROJ_ROOT" ]; then
  PROJ_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# state dir 解決（config 相対パスを project root に基づき絶対化）
STATE_DIR="${HC_IMPROVEMENT_PROPOSAL_STATE_DIR:-.claude/.improvement-proposal-state}"
case "$STATE_DIR" in
  /*) ABS_STATE_DIR="$STATE_DIR" ;;
  *)  ABS_STATE_DIR="$PROJ_ROOT/$STATE_DIR" ;;
esac

mkdir -p "$ABS_STATE_DIR" 2>/dev/null || true

# === cache layer (task-22 W5) =================================================
# cache TTL は秒指定 (default 3600 = 1h)。テスト用に env で短縮可能。
CACHE_TTL_SECONDS="${HC_IMPROVEMENT_PROPOSAL_CACHE_TTL:-3600}"
# 整数値検証 (非数値なら default 3600 に fallback)
case "$CACHE_TTL_SECONDS" in
  ''|*[!0-9]*) CACHE_TTL_SECONDS=3600 ;;
esac
CACHE_FILE="$ABS_STATE_DIR/cache.json"
CACHE_ENABLED="${HC_IMPROVEMENT_PROPOSAL_CACHE_ENABLED:-true}"

# cache hit → payload を stderr に流して exit 0 (集計 skip)
if _cache_hit; then
  jq -r '.payload' "$CACHE_FILE" >&2 2>/dev/null || true
  exit 0
fi

# === 集計実行 (cache miss or expired or corrupt) ==============================
# Python 側に集計を委譲（標準ライブラリのみ使用、lib/improvement-proposal/aggregate.py）
# 環境変数経由で設定を渡す
export HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS
export HC_IMPROVEMENT_PROPOSAL_MAX_COUNT
export HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS
export HC_GATEGUARD_STATE_DIR
export HC_TASKGUARD_STATE_DIR
export HC_FAILURE_WINDOW_DIR
export HC_CONFIDENCE_STATE_DIR
export HC_HOMUNCULUS_ROOT
export ECC_IMPROVEMENT_PROPOSAL_TEST_NOW
export ABS_STATE_DIR
export PROJ_ROOT

# Python の stderr を一旦 tmp に捕捉、終了後に cache 書き込み + stderr に流す。
CACHE_TMP="$(mktemp 2>/dev/null || printf '%s' "$ABS_STATE_DIR/.cache.tmp.$$")"
# observations count を Python 側から拾うための tmp path (cache metadata 用)
export HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE="$ABS_STATE_DIR/.obs-count.tmp.$$"

python3 "$SCRIPT_DIR/lib/improvement-proposal/aggregate.py" 2>"$CACHE_TMP"

_write_cache

# 集計結果 stderr を実際に流す (cache hit 時と同じ挙動を保証)
cat "$CACHE_TMP" >&2 2>/dev/null || true

# クリーンアップ
rm -f "$CACHE_TMP" "$HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE" 2>/dev/null || true

exit 0
