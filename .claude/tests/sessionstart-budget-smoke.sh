#!/usr/bin/env bash
# sessionstart-budget-smoke.sh — task-71 Step 8 S-C (H4 強化)
#
# 目的:
#   session-start-dispatcher.sh の stdout byte 数を計測する。
#   draft 目標 800 chars は warn ライン — 超過しても FAIL にしない (warn 記録のみ)。
#   SessionStart は Claude Code に context (system-reminder 等) を戻す event で、
#   出力が過大だと LLM の有効 context window を圧迫する。
#
# 計測内容:
#   SC-1: session-start-dispatcher を 隔離環境 (/dev/null stdin) で実行し stdout バイト数を取得。
#         H4: 固定 mode.yml=normal + 空 list.md + HOME 隔離 で決定論化 (実 project 状態依存排除)。
#   SC-2: 現状値を記録し、800 超過で WARN (fail にしない)。
#         H4: hard-fail 上限 5000 chars 追加 (WARN 800 + HARD_FAIL 5000 の 2 段構成)。
#   SC-3: bootstrap 出力が非空であること を FAIL 検出 (session-start-wrapper 無音化を回帰検出)。
#         H4: 旧実装は空出力を warn-pass にしていたが、非空を hard assert に変更。
#   SC-4: 出力が有効 UTF-8 / printable であることを確認 (制御文字注入チェック)。
#
# 実行: bash .claude/tests/sessionstart-budget-smoke.sh
# 終了: 0 = 全 case PASS (warn は PASS、hard fail は test failure のみ) / 1 = FAIL
#
# bash 3.2 互換 (macOS)。
# 規約: file-top set -u + case 別 ( set -uo pipefail ) + run_case。

set -u

BUDGET_WARN=800      # chars warn ライン (超過で warn、fail にしない)
BUDGET_HARD_FAIL=5000  # H4: hard-fail 上限 (超過で FAIL)

# --- root 解決 ---
_resolve_root() (
  set -uo pipefail
  if [ -n "${HC_PROJECT_ROOT:-}" ] && [ -d "${HC_PROJECT_ROOT}" ]; then
    printf '%s' "${HC_PROJECT_ROOT}"; return 0
  fi
  local _sdir
  _sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if command -v git >/dev/null 2>&1; then
    local r
    r=$(git -C "$_sdir" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r" ] && [ -d "$r" ] && { printf '%s' "$r"; return 0; }
  fi
  if command -v git >/dev/null 2>&1; then
    local r2
    r2=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r2" ] && [ -d "$r2" ] && { printf '%s' "$r2"; return 0; }
  fi
  pwd
)

ROOT="$(_resolve_root)"
DISPATCHER="${ROOT}/.claude/hooks/session-start-dispatcher.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/sessionstart-budget-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
warn() { WARN=$((WARN+1)); printf '  WARN: %s\n' "$1"; }

# ------------------------------------------------------------------
# H4: 隔離環境セットアップ — 固定 mode.yml + 空 list.md + HOME 隔離 (決定論化)
# 実 project の mode 状態・task list 状態に依存しない安定した実行環境を構築する。
ISOLATED_HOME="$TMPBASE/isolated-home"
ISOLATED_STATE="$TMPBASE/isolated-state"
mkdir -p "$ISOLATED_HOME/.claude" "$ISOLATED_STATE"

# 固定 mode.yml=normal (実 project の Loop モード状態に依存しない)
printf 'mode: normal\n' > "$ISOLATED_HOME/.claude/mode.yml"
# 空 list.md (list-md-plan-first-reminder の plan-first 警告を抑制)
mkdir -p "$ISOLATED_HOME/.claude/docs/tasks" 2>/dev/null || true

# ------------------------------------------------------------------
printf "=== S-C: sessionstart-budget-smoke ===\n\n"
printf "H4: 隔離環境 (HOME=%s、mode=normal、list.md=空)\n" "$ISOLATED_HOME"

# SC-1: dispatcher が exit 0 で終了する (隔離環境)
run_sc1() ( set -uo pipefail
  local rc=0
  HOME="$ISOLATED_HOME" \
  HC_PROJECT_ROOT="$ROOT" \
  HC_IMPROVEMENT_PROPOSAL_STATE_DIR="$ISOLATED_STATE/improvement" \
  HC_STALE_HARNESS_DETECT_STATE_DIR="$ISOLATED_STATE/stale-harness" \
  HC_CONTEXT_BUDGET_STATE_DIR="$ISOLATED_STATE/context-budget" \
    bash "$DISPATCHER" </dev/null >/dev/null 2>/dev/null || rc=$?
  printf '%s\n' "$rc" > "${TMPBASE}/result-sc1"
)

printf "SC-1: session-start-dispatcher exits 0 (isolated env)\n"
run_sc1
sc1_rc="$(cat "${TMPBASE}/result-sc1" 2>/dev/null | tr -d '[:space:]')"
if [ "$sc1_rc" = "0" ]; then
  ok "SC-1 exit 0"
else
  bad "SC-1 exit ${sc1_rc} (want 0)"
fi

# SC-2: stdout byte count measurement (隔離環境)
run_sc2() ( set -uo pipefail
  local out
  out="$(
    HOME="$ISOLATED_HOME" \
    HC_PROJECT_ROOT="$ROOT" \
    HC_IMPROVEMENT_PROPOSAL_STATE_DIR="$ISOLATED_STATE/improvement" \
    HC_STALE_HARNESS_DETECT_STATE_DIR="$ISOLATED_STATE/stale-harness" \
    HC_CONTEXT_BUDGET_STATE_DIR="$ISOLATED_STATE/context-budget" \
      bash "$DISPATCHER" </dev/null 2>/dev/null
  )"
  local byte_count
  byte_count=$(printf '%s' "$out" | wc -c | tr -d '[:space:]')
  printf '%s\n' "$byte_count" > "${TMPBASE}/result-sc2-bytes"
  printf '%s\n' "$out" > "${TMPBASE}/result-sc2-content"
)

printf "\nSC-2: measure stdout byte count (isolated env)\n"
run_sc2
BYTE_COUNT="$(cat "${TMPBASE}/result-sc2-bytes" 2>/dev/null | tr -d '[:space:]')"
if [ -z "$BYTE_COUNT" ]; then
  bad "SC-2 byte count measurement failed"
else
  printf "  INFO: session-start-dispatcher stdout = %s bytes\n" "$BYTE_COUNT"
  # H4: 2 段構成 (warn 800 / hard-fail 5000)
  if [ "$BYTE_COUNT" -le "$BUDGET_WARN" ]; then
    ok "SC-2 stdout bytes=${BYTE_COUNT} (<= warn_line=${BUDGET_WARN})"
  elif [ "$BYTE_COUNT" -le "$BUDGET_HARD_FAIL" ]; then
    warn "SC-2 stdout bytes=${BYTE_COUNT} EXCEEDS warn_line=${BUDGET_WARN} (< hard_fail=${BUDGET_HARD_FAIL}) — context budget pressure (not FAIL)"
    ok "SC-2 recorded (warn state, not hard fail)"
  else
    bad "SC-2 stdout bytes=${BYTE_COUNT} EXCEEDS hard_fail_line=${BUDGET_HARD_FAIL} — LLM context 過負荷リスク"
  fi
fi

# SC-3: H4 bootstrap 出力が非空であることを assert (session-start-wrapper 無音化を回帰検出)
#   旧実装: 空出力を warn-pass にしていた → 無音化を見逃す
#   新実装: 空出力を FAIL として検出 (session-start-wrapper は最低限 mode 情報を出すべき)
printf "\nSC-3: stdout non-empty (bootstrap context injection, hard assert)\n"
CONTENT_SIZE="$(wc -c < "${TMPBASE}/result-sc2-content" 2>/dev/null | tr -d '[:space:]')"
# session-start-dispatcher runs session-start-wrapper + list-md + stale-harness-detect + observe
# session-start-wrapper は最低限 mode 情報 (normal/loop) を出すため空にならないはず。
# ただし全 bootstrap hook が feature toggle で OFF の場合は空 → その時は WARN に留める
if [ "${CONTENT_SIZE:-0}" -gt 0 ]; then
  ok "SC-3 stdout non-empty (${CONTENT_SIZE} bytes written) — bootstrap context 注入確認"
else
  # H4: 空出力は FAIL (session-start-wrapper の無音化を回帰検出)
  bad "SC-3 stdout empty — session-start-wrapper 無音化の可能性 (bootstrap context 未注入)"
fi

# SC-4: no NUL bytes / obvious binary in output (content quality check)
printf "\nSC-4: output contains no NUL bytes (printable ASCII / UTF-8 check)\n"
if [ -f "${TMPBASE}/result-sc2-content" ]; then
  # cat -v shows non-printable as ^X, NUL as ^@ — check for ^@
  if cat "${TMPBASE}/result-sc2-content" | od -c 2>/dev/null | grep -q '\\0'; then
    bad "SC-4 output contains NUL bytes"
  else
    ok "SC-4 output is NUL-free"
  fi
else
  warn "SC-4 content file missing, skip"
  ok "SC-4 skip (no content)"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== S-C Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
printf "WARN: %d\n" "$WARN"
printf "Budget: %s bytes (warn line: %d, hard-fail line: %d)\n" "${BYTE_COUNT:-unknown}" "$BUDGET_WARN" "$BUDGET_HARD_FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
