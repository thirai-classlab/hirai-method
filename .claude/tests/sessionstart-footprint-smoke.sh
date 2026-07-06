#!/usr/bin/env bash
# sessionstart-footprint-smoke.sh — task-73 Step 1 (footprint hard cap + presence)
#                                   task-88 Step 3 (cap 2400 + FP-5/FP-6 summary 注入対応)
#
# 目的:
#   SessionStart 総出力 (session-start-dispatcher.sh stdout) の footprint を hard cap で
#   回帰検出する。sessionstart-budget-smoke.sh は warn ライン扱いだが、本 smoke は
#   **hard cap 2400B で FAIL 検出**する (cap の SSoT は本 smoke)。
#   task-88 (sessionstart-summary-injection) で hc-config.sh --summary 全文注入が加わり、
#   cap を 800 → 2400 に引上げた (根拠は FOOTPRINT_CAP の comment 参照)。
#
# 計測内容:
#   FP-1: Loop モード + session/context.md 存在の隔離環境で dispatcher stdout を測定。
#         <= 2400 bytes で PASS、超過で FAIL (task-73 当時は cap 800、TDD: 短縮前は 3257 で FAIL = RED)。
#   FP-2: presence assert (短くしても機能情報が残ることを保証):
#         - 出力に `mode=` (compact status 1 行) が含まれる
#         - 出力に resume 関連語が含まれる (context.md 存在時)
#         - 出力に why-x5 関連語が含まれる
#         - FP-2d: guards= / preset= / modes.md pointer が含まれる (loop reminder の構造保証)
#   FP-3: Normal モード + context.md 不在の隔離環境で footprint / mode=normal / resume=none を検証。
#   FP-4: Loop モード + HC_WHY_X5_DISABLE=1 で why-x5 signal が absent であること、
#         かつ footprint が FP-1 loop baseline より小さいことを検証 (kill-switch 回帰検出)。
#   FP-5: (task-88) FP-1 出力に `totals:` / `guards:` が含まれる (hc-config.sh --summary
#         全文注入の構造保証。値・行数 hardcode なし、FP-2d と同 style)。
#   FP-6: (task-88) Loop モード + HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false で
#         `totals:` absent + <system-reminder> 開閉タグ均衡 (閉じタグ健在 = hook 途中死なし)
#         + footprint < FP-1 baseline (FP-4 の kill-switch 検証 pattern 踏襲)。
#   FP-7: (task-97、next-actions #81 fold) hc-config.sh 不在 fixture で fail-open dedicated:
#         - dispatcher exit 0 (hook 途中死せず)
#         - <system-reminder> open==close (閉じタグ均衡、開閉数 >=1)
#         mutation probe: mode-session-start.sh の `SUMMARY=""` 初期化 or
#         `if [ -f "$HC_SCRIPT" ]` guard 削除 → set -u で printf 途中死 → 開閉不均衡で FAIL。
#         FP-6 は複合条件 (summary off + tags balanced + footprint 差) で捕捉不能な単独 M4
#         regression を FP-7 が dedicated に測る。
#   FP-5': (task-97、next-actions #81 fold) FP-5 label strictness 強化:
#         label のみ match から `totals: [0-9]+ enabled, [0-9]+ disabled` field 数検証へ強化。
#         `totals:` label はあるが数値欠落 (parse regression) を検出できる。
#
# 実行: bash .claude/tests/sessionstart-footprint-smoke.sh
# 終了: 0 = 全 case PASS / 1 = FAIL
#
# bash 3.2 互換 (macOS)。
# 規約: file-top set -u + case 別 ( set -uo pipefail ) + run_case。

set -u

# bytes hard cap (wc -c is bytes) — 超過で FAIL
# task-88 Step 3 (2026-07-05): hc-config.sh --summary 全文注入 (P1-4) 対応で 800 → 2400 に引上げ。
# task-97 Step 3 (2026-07-07): enforcement_matrix 全 hook 拡張で 11 → 23 guard に増加。
#   summary 出力に 12 新 guard 行が追加 (~50 bytes/entry = ~600B 増) するため 2400 → 3100 に引上げ。
#   - harness-dev worst (loop + ctx present、23 guard、日本語 disabled_reason 8 件): 実測 ~2,680B + 16% margin ≈ 3100
#   - consuming repo (team-default 全 enabled、23 guard、summary ~1050B): ~1,720B で十分収まる
#   - budget smoke (sessionstart-budget-smoke.sh) の hard-fail 5000 の内側に位置する 2 段構成
FOOTPRINT_CAP=3100

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
# FP-1: hard cap 2400B (Loop mode + context.md present)
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
# FP-5: summary full-text presence + field 数厳密化 (task-88 Step 3 + task-97 #81 fold)
#   FP-1 の loop 出力 (OUT_LOOP 再利用、dispatcher 追加起動なし) に
#   hc-config.sh --summary 全文注入の構造 signal が含まれること:
#   - `totals: [0-9]+ enabled, [0-9]+ disabled` (field 数厳密化、値だけ欠落 regression を捕捉)
#   - `guards:` (summary の guard 一覧 header 行。FP-2d の `guards=` compact field とは別物)
#   task-97 (next-actions #81) で label のみ match から field 数検証へ強化。
#   `totals:` label 存在で満足せず「N enabled, M disabled」の数値 pair を必須にする。
printf "\nFP-5: summary full-text presence + field strictness (totals: N enabled, M disabled / guards: in loop output)\n"
if printf '%s' "$OUT_LOOP" | grep -qE 'totals:[[:space:]]+[0-9]+[[:space:]]+enabled,[[:space:]]+[0-9]+[[:space:]]+disabled'; then
  ok "FP-5a 'totals: N enabled, M disabled' field-count verified (values present, not label-only)"
else
  bad "FP-5a 'totals: [0-9]+ enabled, [0-9]+ disabled' pattern missing — label のみ / 数値欠落 regression"
fi
if printf '%s' "$OUT_LOOP" | grep -q 'guards:'; then
  ok "FP-5b 'guards:' present (summary guard list injected)"
else
  bad "FP-5b 'guards:' missing — hc-config.sh --summary 全文注入が regress した可能性"
fi

# ------------------------------------------------------------------
# FP-6: summary toggle-off (task-88 Step 3、FP-4 kill-switch 検証 pattern 踏襲)
#   HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false で:
#   (a) summary 全文 signal (`totals:`) が absent
#   (b) <system-reminder> 開閉タグが均衡 (閉じタグ健在 = hook 途中死なしの構造保証)
#   (c) footprint が FP-1 loop baseline より小さい (summary block 省略の実測保証)
printf "\nFP-6: loop + HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false (summary absent + tags balanced + footprint < baseline)\n"
OUT_SUMOFF="$(measure_footprint "${ISOLATED_HOME}" "loop" "HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false")"
printf '%s' "$OUT_SUMOFF" > "${TMPBASE}/out_sumoff"
BYTES_SUMOFF=$(wc -c < "${TMPBASE}/out_sumoff" | tr -d '[:space:]')
printf "  INFO: loop+summary-off stdout = %s bytes (FP-1 baseline = %s bytes)\n" "$BYTES_SUMOFF" "$BYTES_LOOP"

# (a) totals: absent
if printf '%s' "$OUT_SUMOFF" | grep -q 'totals:'; then
  bad "FP-6a 'totals:' still present with HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false — feature gate regressed"
else
  ok "FP-6a 'totals:' absent (HC_FEATURE_SESSIONSTART_SUMMARY_ENABLED=false effective)"
fi

# (b) <system-reminder> 開閉タグ均衡 (閉じタグ健在)
#   閉じタグ `</system-reminder>` は substring `<system-reminder>` を含まないため
#   両者の grep -c は独立に数えられる (bash 3.2 / BSD grep 互換)。
OPEN_SUMOFF=$(grep -c '<system-reminder>' "${TMPBASE}/out_sumoff" 2>/dev/null || true)
CLOSE_SUMOFF=$(grep -c '</system-reminder>' "${TMPBASE}/out_sumoff" 2>/dev/null || true)
if [ "${CLOSE_SUMOFF:-0}" -ge 1 ] && [ "${OPEN_SUMOFF:-0}" = "${CLOSE_SUMOFF:-0}" ]; then
  ok "FP-6b system-reminder tags balanced (open=${OPEN_SUMOFF} close=${CLOSE_SUMOFF}) — 閉じタグ健在"
else
  bad "FP-6b system-reminder tags unbalanced (open=${OPEN_SUMOFF:-?} close=${CLOSE_SUMOFF:-?}) — hook 途中死 (閉じタグ欠落) の可能性"
fi

# (c) footprint < FP-1 loop baseline
if [ -z "$BYTES_SUMOFF" ] || [ -z "$BYTES_LOOP" ]; then
  bad "FP-6c byte count unavailable"
elif [ "$BYTES_SUMOFF" -lt "$BYTES_LOOP" ]; then
  ok "FP-6c footprint=${BYTES_SUMOFF} < baseline=${BYTES_LOOP} (summary block omitted)"
else
  bad "FP-6c footprint=${BYTES_SUMOFF} not less than baseline=${BYTES_LOOP} — summary block may not have been omitted"
fi

# ------------------------------------------------------------------
# FP-7: fail-open dedicated (task-97、next-actions #81 fold)
#   hc-config.sh 不在 fixture で mode-session-start.sh の M4 SUMMARY 初期化 fix が
#   fail-open として機能するかを dedicated に測る。
#   FP-6 は summary toggle off の複合条件で偶然通過する場合があり、単独 M4 regression
#   (=SUMMARY 未初期化 or file check 削除で set -u → printf 途中死 → 閉じタグ欠落) を
#   捕捉できない。本 case は複合条件を切り離し、hc-config.sh を fixture から物理的に
#   削除して:
#     (a) dispatcher exit 0 (hook 途中死せず fail-open 契約遵守)
#     (b) <system-reminder> open==close (閉じタグ均衡、開閉数 >=1 = 実出力あり)
#   mutation probe:
#     mode-session-start.sh L58 の `SUMMARY=""` 削除 → set -u nounset で
#     `if [ -n "$SUMMARY" ]` 参照時 printf 途中死 → 閉じタグ欠落 → FP-7b FAIL。
#     L59 の if guard のみ削除は `|| true` により exit 0 で死なないため FP-7 の
#     保護対象外 (M2 単独は無害、実験確認: SUMMARY は "" 初期化のまま維持される)。
#   fixture: cp -R .claude → tmp fixture、rm -f fixture/.claude/scripts/hc-config.sh。
printf "\nFP-7: fail-open dedicated (hc-config.sh absent fixture)\n"
FIXTURE_ROOT="${TMPBASE}/fixture-no-hcconfig"
mkdir -p "$FIXTURE_ROOT"

# .claude subtree を fixture に複製 (hooks + scripts + skills + templates + .workflow-state 等)。
# `cp -R` (BSD/GNU 互換) で symlink 追随 + mode 保持。dot-file (.gitignore 等) も
# `cp -R <src>/.claude <dst>/` で丸ごと含まれる (dir 単位のため中身の hidden も対象)。
if cp -R "${ROOT}/.claude" "${FIXTURE_ROOT}/" 2>/dev/null; then
  # hc-config.sh を除去 (mode-session-start.sh の `if [ -f "$HC_SCRIPT" ]` を false 化)
  rm -f "${FIXTURE_ROOT}/.claude/scripts/hc-config.sh" 2>/dev/null || true

  # 出力を独立 tmp file に保存 (前 case 変数 shadow を避ける)
  OUT_NOHC_FILE="${TMPBASE}/out_nohc"
  OUT_NOHC_EXIT=0
  # dispatcher は fixture 下の絶対 path を呼ぶ (SCRIPT_DIR は fixture へ解決される)
  measure_footprint "${ISOLATED_HOME}" "loop" "HC_PROJECT_ROOT=${FIXTURE_ROOT}" \
    > "${OUT_NOHC_FILE}" 2>/dev/null || OUT_NOHC_EXIT=$?
  # 注意: measure_footprint 内で bash "$DISPATCHER" を呼ぶが $DISPATCHER は REAL ROOT の path。
  # HC_PROJECT_ROOT=fixture の env を渡すことで resolve_project_root() が fixture を返し、
  # dispatcher-core.sh の manifest / child hook 解決も fixture 側 (hc-config.sh 削除済) を使う。

  # (a) exit 0 (fail-open 契約遵守)
  if [ "$OUT_NOHC_EXIT" = "0" ]; then
    ok "FP-7a dispatcher exit=0 with hc-config.sh absent (fail-open contract)"
  else
    bad "FP-7a dispatcher exit=${OUT_NOHC_EXIT} with hc-config.sh absent — fail-open regression (SUMMARY 未初期化 疑い)"
  fi

  # (b) <system-reminder> open==close balanced + open >= 1 (実出力あり)
  OPEN_NOHC=$(grep -c '<system-reminder>' "${OUT_NOHC_FILE}" 2>/dev/null || true)
  CLOSE_NOHC=$(grep -c '</system-reminder>' "${OUT_NOHC_FILE}" 2>/dev/null || true)
  if [ "${OPEN_NOHC:-0}" -ge 1 ] && [ "${OPEN_NOHC:-0}" = "${CLOSE_NOHC:-0}" ]; then
    ok "FP-7b system-reminder tags balanced (open=${OPEN_NOHC} close=${CLOSE_NOHC}) — 閉じタグ健在 (mode-session-start.sh SUMMARY 初期化 fix effective)"
  else
    bad "FP-7b system-reminder tags unbalanced (open=${OPEN_NOHC:-?} close=${CLOSE_NOHC:-?}) — hook 途中死 (SUMMARY 未初期化で set -u printf 死) の可能性"
  fi
else
  printf "  SKIP: FP-7 fixture setup (cp -R) failed\n"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== FP Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
printf "Footprint (loop baseline): %s bytes (cap: %d)\n" "${BYTES_LOOP:-unknown}" "$FOOTPRINT_CAP"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
