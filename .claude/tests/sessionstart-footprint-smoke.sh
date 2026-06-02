#!/usr/bin/env bash
# sessionstart-footprint-smoke.sh — task-73 Step 1 (footprint hard cap + presence)
#
# 目的:
#   SessionStart 総出力 (session-start-dispatcher.sh stdout) を ~800B 以下に短縮した
#   状態を回帰検出する。sessionstart-budget-smoke.sh は 800 を warn ライン扱いだが、
#   本 smoke は task-73 短文化 (案 B) 後の状態を **hard cap 800B で FAIL 検出**する。
#
# 計測内容:
#   FP-1: Loop モード + session/context.md 存在の隔離環境で dispatcher stdout を測定。
#         <= 800 bytes で PASS、超過で FAIL (TDD: 短縮前は 3257 で FAIL = RED)。
#   FP-2: presence assert (短くしても機能情報が残ることを保証):
#         - 出力に `mode=` (compact status 1 行) が含まれる
#         - 出力に resume 関連語が含まれる (context.md 存在時)
#         - 出力に why-x5 関連語が含まれる
#         - FP-2d: guards= / preset= / modes.md pointer が含まれる (loop reminder の構造保証)
#   FP-3: Normal モード + context.md 不在の隔離環境で footprint / mode=normal / resume=none を検証。
#   FP-4: Loop モード + HC_WHY_X5_DISABLE=1 で why-x5 signal が absent であること、
#         かつ footprint が FP-1 loop baseline より小さいことを検証 (kill-switch 回帰検出)。
#
# 実行: bash .claude/tests/sessionstart-footprint-smoke.sh
# 終了: 0 = 全 case PASS / 1 = FAIL
#
# bash 3.2 互換 (macOS)。
# 規約: file-top set -u + case 別 ( set -uo pipefail ) + run_case。

set -u

FOOTPRINT_CAP=800   # bytes hard cap (wc -c is bytes)  — 超過で FAIL

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
  pwd
)

ROOT="$(_resolve_root)"
DISPATCHER="${ROOT}/.claude/hooks/session-start-dispatcher.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/sessionstart-footprint-smoke.XXXXXX")"

PASS=0
FAIL=0

ok()  { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

# ------------------------------------------------------------------
# context.md 退避/復元ヘルパー
# FP-3: context.md 不在を実測するため実ファイルを一時退避し trap で復元する。
# FP-1/2 用の fixture 生成 (CTX_CREATED) と組み合わせて cleanup を共有する。
CTX_FILE="${ROOT}/.serena/memories/session/context.md"
CTX_CREATED=0
CTX_HIDDEN=0

cleanup_ctx() {
  if [ "$CTX_CREATED" = "1" ]; then
    rm -f "$CTX_FILE" 2>/dev/null || true
  fi
  if [ "$CTX_HIDDEN" = "1" ] && [ -f "${TMPBASE}/context.md.bak" ]; then
    mv "${TMPBASE}/context.md.bak" "$CTX_FILE" 2>/dev/null || true
  fi
}
trap 'cleanup_ctx; rm -rf "$TMPBASE"' EXIT

# ------------------------------------------------------------------
# 隔離環境用変数・ディレクトリ (全 case で共有)
ISOLATED_HOME="${TMPBASE}/isolated-home"
ISOLATED_HOME_NORMAL="${TMPBASE}/isolated-home-normal"
ISOLATED_STATE="${TMPBASE}/isolated-state"
mkdir -p "${ISOLATED_HOME}/.claude" "${ISOLATED_HOME_NORMAL}/.claude" "${ISOLATED_STATE}"
printf 'mode: loop\n'   > "${ISOLATED_HOME}/.claude/mode.yml"
printf 'mode: normal\n' > "${ISOLATED_HOME_NORMAL}/.claude/mode.yml"

# FP-1/2 用: session/context.md 存在の隔離環境 (presence assert を発火させる)。
# 既存ファイルを壊さないため、不在時のみ生成し、test 終了時に除去する。
if [ ! -f "$CTX_FILE" ]; then
  mkdir -p "$(dirname "$CTX_FILE")" 2>/dev/null || true
  if printf 'smoke-fixture\n' > "$CTX_FILE" 2>/dev/null; then
    CTX_CREATED=1
  fi
fi

# ------------------------------------------------------------------
# measure_footprint <home_dir> <hc_mode> [extra env assignments...]
# 指定の HOME/mode で dispatcher を起動し出力を返すヘルパー。
# 追加 env は "KEY=VAL" 形式の引数として渡す。
measure_footprint() (
  set -uo pipefail
  local _home="$1" _mode="$2"
  shift 2
  # extra env args: eval each "KEY=VAL" as export
  local _env_args=""
  while [ $# -gt 0 ]; do
    _env_args="${_env_args} $1"
    shift
  done
  # shellcheck disable=SC2086
  env HOME="$_home" \
      HC_MODE="$_mode" \
      HC_PROJECT_ROOT="$ROOT" \
      HC_IMPROVEMENT_PROPOSAL_STATE_DIR="${ISOLATED_STATE}/improvement" \
      HC_STALE_HARNESS_DETECT_STATE_DIR="${ISOLATED_STATE}/stale-harness" \
      HC_CONTEXT_BUDGET_STATE_DIR="${ISOLATED_STATE}/context-budget" \
      $_env_args \
    bash "$DISPATCHER" </dev/null 2>/dev/null
)

printf "=== FP: sessionstart-footprint-smoke ===\n\n"
printf "env: HC_PROJECT_ROOT=%s\n" "$ROOT"
printf "     context.md=%s\n\n" "$([ -f "$CTX_FILE" ] && echo present || echo absent)"

# ------------------------------------------------------------------
# FP-1: hard cap 800B (Loop mode + context.md present)
printf "FP-1: stdout footprint <= %d bytes (loop + ctx=present)\n" "$FOOTPRINT_CAP"
OUT_LOOP="$(measure_footprint "${ISOLATED_HOME}" "loop")"
printf '%s' "$OUT_LOOP" > "${TMPBASE}/out_loop"
BYTES_LOOP=$(wc -c < "${TMPBASE}/out_loop" | tr -d '[:space:]')
printf "  INFO: session-start-dispatcher stdout = %s bytes\n" "$BYTES_LOOP"
if [ -z "$BYTES_LOOP" ]; then
  bad "FP-1 byte count measurement failed"
elif [ "$BYTES_LOOP" -le "$FOOTPRINT_CAP" ]; then
  ok "FP-1 footprint=${BYTES_LOOP} (<= cap=${FOOTPRINT_CAP})"
else
  bad "FP-1 footprint=${BYTES_LOOP} EXCEEDS cap=${FOOTPRINT_CAP} — SessionStart 出力が過大"
fi

# ------------------------------------------------------------------
# FP-2: presence assert (Loop mode + context.md present)
printf "\nFP-2: presence of mode= / resume / why-x5 / guards= / preset= / modes.md signals\n"
if printf '%s' "$OUT_LOOP" | grep -q 'mode='; then
  ok "FP-2a 'mode=' compact status present"
else
  bad "FP-2a 'mode=' compact status missing"
fi
if printf '%s' "$OUT_LOOP" | grep -qi 'resume'; then
  ok "FP-2b resume signal present"
else
  bad "FP-2b resume signal missing (context.md present だが resume 案内なし)"
fi
if printf '%s' "$OUT_LOOP" | grep -qi 'why-x5'; then
  ok "FP-2c why-x5 signal present"
else
  bad "FP-2c why-x5 signal missing"
fi

# FP-2d: Loop reminder に guards= / preset= / modes.md pointer の 3 つが存在すること。
#   guards= が空マッチ (totals 行 format 変更で awk 空) や modes.md pointer 欠落を回帰検出。
#   値はハードコードせず exists のみ assert。
printf "\nFP-2d: loop reminder structure (guards= / preset= / modes.md pointer)\n"
if printf '%s' "$OUT_LOOP" | grep -q 'guards='; then
  ok "FP-2d guards= present in loop output"
else
  bad "FP-2d guards= missing — totals awk extraction may have regressed"
fi
if printf '%s' "$OUT_LOOP" | grep -q 'preset='; then
  ok "FP-2d preset= present in loop output"
else
  bad "FP-2d preset= missing — hc-config.sh --summary parsing may have regressed"
fi
if printf '%s' "$OUT_LOOP" | grep -q 'modes\.md'; then
  ok "FP-2d modes.md pointer present in loop reminder"
else
  bad "FP-2d modes.md pointer missing — loop reminder truncated or format changed"
fi

# ------------------------------------------------------------------
# FP-3: Normal mode + context.md absent
#   context.md 不在のパスを検証するため実ファイルを一時退避する。
#   退避後は cleanup_ctx (trap) で必ず復元される。
printf "\nFP-3: normal mode + context.md=absent (resume=none / footprint)\n"
if [ -f "$CTX_FILE" ]; then
  mv "$CTX_FILE" "${TMPBASE}/context.md.bak" 2>/dev/null && CTX_HIDDEN=1
fi
if [ "$CTX_HIDDEN" = "1" ] || [ "$CTX_CREATED" = "0" -a ! -f "$CTX_FILE" ]; then
  # context.md が不在状態で計測
  OUT_NORMAL_NOCTX="$(measure_footprint "${ISOLATED_HOME_NORMAL}" "normal")"
  printf '%s' "$OUT_NORMAL_NOCTX" > "${TMPBASE}/out_normal_noctx"
  BYTES_NORMAL_NOCTX=$(wc -c < "${TMPBASE}/out_normal_noctx" | tr -d '[:space:]')
  printf "  INFO: normal+noctx stdout = %s bytes\n" "$BYTES_NORMAL_NOCTX"

  # (a) footprint <= cap
  if [ -z "$BYTES_NORMAL_NOCTX" ]; then
    bad "FP-3a byte count measurement failed"
  elif [ "$BYTES_NORMAL_NOCTX" -le "$FOOTPRINT_CAP" ]; then
    ok "FP-3a normal+noctx footprint=${BYTES_NORMAL_NOCTX} (<= cap=${FOOTPRINT_CAP})"
  else
    bad "FP-3a normal+noctx footprint=${BYTES_NORMAL_NOCTX} EXCEEDS cap=${FOOTPRINT_CAP}"
  fi

  # (b) mode=normal present
  if printf '%s' "$OUT_NORMAL_NOCTX" | grep -q 'mode=normal'; then
    ok "FP-3b 'mode=normal' present in normal mode output"
  else
    bad "FP-3b 'mode=normal' missing in normal mode output"
  fi

  # (c) resume=none present (context.md 不在パス)
  if printf '%s' "$OUT_NORMAL_NOCTX" | grep -q 'resume=none'; then
    ok "FP-3c 'resume=none' present (context.md absent path)"
  else
    bad "FP-3c 'resume=none' missing — context.md absent path not reflected in status"
  fi

  # context.md を復元 (trap でも行われるが早期復元で他 case への影響を最小化)
  if [ "$CTX_HIDDEN" = "1" ] && [ -f "${TMPBASE}/context.md.bak" ]; then
    mv "${TMPBASE}/context.md.bak" "$CTX_FILE" 2>/dev/null || true
    CTX_HIDDEN=0
  fi
else
  # context.md の退避/移動に失敗した場合は skip
  printf "  SKIP: FP-3 context.md hide failed (CTX_HIDDEN=%s CTX_CREATED=%s)\n" "$CTX_HIDDEN" "$CTX_CREATED"
fi

# ------------------------------------------------------------------
# FP-4: Loop mode + HC_WHY_X5_DISABLE=1 (kill-switch 回帰検出)
#   (a) why-x5 signal が absent
#   (b) footprint が FP-1 loop baseline より小さい
printf "\nFP-4: loop + HC_WHY_X5_DISABLE=1 (why-x5 absent + footprint < baseline)\n"
OUT_NOWHY="$(measure_footprint "${ISOLATED_HOME}" "loop" "HC_WHY_X5_DISABLE=1")"
printf '%s' "$OUT_NOWHY" > "${TMPBASE}/out_nowhy"
BYTES_NOWHY=$(wc -c < "${TMPBASE}/out_nowhy" | tr -d '[:space:]')
printf "  INFO: loop+no-why stdout = %s bytes (FP-1 baseline = %s bytes)\n" "$BYTES_NOWHY" "$BYTES_LOOP"

# (a) why-x5 signal absent
if printf '%s' "$OUT_NOWHY" | grep -qi 'why-x5'; then
  bad "FP-4a why-x5 signal still present with HC_WHY_X5_DISABLE=1 — kill-switch regressed"
else
  ok "FP-4a why-x5 signal absent (HC_WHY_X5_DISABLE=1 effective)"
fi

# (b) footprint < FP-1 loop baseline
if [ -z "$BYTES_NOWHY" ] || [ -z "$BYTES_LOOP" ]; then
  bad "FP-4b byte count unavailable"
elif [ "$BYTES_NOWHY" -lt "$BYTES_LOOP" ]; then
  ok "FP-4b footprint=${BYTES_NOWHY} < baseline=${BYTES_LOOP} (why-x5 block omitted)"
else
  bad "FP-4b footprint=${BYTES_NOWHY} not less than baseline=${BYTES_LOOP} — why-x5 block may not have been omitted"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== FP Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
printf "Footprint (loop baseline): %s bytes (cap: %d)\n" "${BYTES_LOOP:-unknown}" "$FOOTPRINT_CAP"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
