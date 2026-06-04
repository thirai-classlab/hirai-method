#!/usr/bin/env bash
# .claude/tests/statusline-smoke.sh — task-62 statusline.sh smoke test
#
# 目的: statusline.sh に sample JSON を投入し、採用案 (docs/draft/statusline-construction.md §3)
#       の出力仕様を機械検証する。
#
# 検証項目:
#   1. full JSON で 2 行出力
#   2. 行1 に model / branch / ctx を含む
#   3. 行2 に 5h / 7d / mode / settings hint を含む
#   4. rate_limits 不在 → "5h —" / "7d —" fallback
#   5. jq 不在 → plain 降格 (1 行 / "Claude" 含む) で exit 0
#   6. mode=loop 強調 / mode=normal で出力切替 (mode.yml 値反映)
#   7. used 値を直接表示 (used 28 → "5h 28% used")
#   8. ANSI escape 含有 (color ON 時)
#   9. 壊れた JSON でも exit 0 (status 非破壊)
#  10. 全ケースで非ゼロ exit を出さない
#
# 設計: subshell 関数 ( set -uo pipefail; ... ) で各 case 隔離
#       (feedback_set_e_in_sourced_libs: file-top strict mode の caller leak 回避)
# bash 3.2 互換 (macOS)。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUSLINE="${REPO_ROOT}/.claude/scripts/statusline.sh"

PASS=0
FAIL=0

ok()   { printf '  PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
ng()   { printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }

# 色を無効化して文字列 assert を安定化 (NO_COLOR)。
run_plain() {
  printf '%s' "$1" | HC_STATUSLINE_NO_COLOR=1 bash "$STATUSLINE" 2>/dev/null
}
run_color() {
  printf '%s' "$1" | bash "$STATUSLINE" 2>/dev/null
}

# sample inputs
FULL_JSON='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":34.2},"rate_limits":{"five_hour":{"used_percentage":28},"seven_day":{"used_percentage":45}},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'
NO_RATELIMITS_JSON='{"model":{"display_name":"Sonnet 4.6"},"context_window":{"used_percentage":12},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'
BROKEN_JSON='not json {{{ broken'
NORMAL_MODE_JSON='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":20},"rate_limits":{"five_hour":{"used_percentage":10},"seven_day":{"used_percentage":10}},"workspace":{"current_dir":"/tmp"}}'

echo "=== statusline-smoke ==="

# --- precondition ---
( set -uo pipefail
  [ -f "$STATUSLINE" ] || { echo "  FAIL: statusline.sh not found"; exit 1; }
  [ -x "$STATUSLINE" ] || { echo "  WARN: statusline.sh not executable (bash 経由実行のため非致命)"; }
) && ok "statusline.sh exists" || ng "statusline.sh exists"

# --- case 1: 2 行出力 ---
( set -uo pipefail
  out="$(run_plain "$FULL_JSON")"
  lines="$(printf '%s\n' "$out" | grep -c . )"
  [ "$lines" -eq 2 ]
) && ok "case1: 2 行出力" || ng "case1: 2 行出力 (got $(run_plain "$FULL_JSON" | grep -c .) lines)"

# --- case 2: 行1 に model / branch / ctx ---
( set -uo pipefail
  line1="$(run_plain "$FULL_JSON" | sed -n '1p')"
  printf '%s' "$line1" | grep -q 'Opus 4.8' \
    && printf '%s' "$line1" | grep -q 'feat/test-branch' \
    && printf '%s' "$line1" | grep -q 'context 34% used'
) && ok "case2: 行1 = model/branch/ctx" || ng "case2: 行1 = model/branch/ctx"

# --- case 3: 行2 に 5h / 7d / mode / settings hint ---
( set -uo pipefail
  line2="$(run_plain "$FULL_JSON" | sed -n '2p')"
  printf '%s' "$line2" | grep -q '5h ' \
    && printf '%s' "$line2" | grep -q '7d ' \
    && printf '%s' "$line2" | grep -q 'mode: ' \
    && printf '%s' "$line2" | grep -q 'settings: bash .claude/scripts/hc-config.sh'
) && ok "case3: 行2 = 5h/7d/mode/settings hint" || ng "case3: 行2 = 5h/7d/mode/settings hint"

# --- case 4: rate_limits 不在 → "5h —" / "7d —" ---
( set -uo pipefail
  out="$(run_plain "$NO_RATELIMITS_JSON")"
  printf '%s' "$out" | grep -q '5h —' && printf '%s' "$out" | grep -q '7d —'
) && ok "case4: rate_limits 不在 fallback (—)" || ng "case4: rate_limits 不在 fallback (—)"

# --- case 5: jq 不在 → plain 降格 (1 行 / Claude 含む) で exit 0 ---
( set -uo pipefail
  TMPD="$(mktemp -d)"
  for b in bash cat grep sed head git env printf; do
    src="$(command -v "$b" 2>/dev/null || true)"
    [ -n "$src" ] && ln -sf "$src" "$TMPD/$b"
  done
  # jq は意図的にリンクしない
  out="$(printf '%s' '{"model":{"display_name":"Opus 4.8"},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}' \
    | env -i PATH="$TMPD" "$TMPD/bash" "$STATUSLINE" 2>/dev/null)"
  rc=$?
  rm -rf "$TMPD"
  lines="$(printf '%s\n' "$out" | grep -c .)"
  [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q 'Claude'
) && ok "case5: jq 不在 plain 降格 (1 行 / exit 0)" || ng "case5: jq 不在 plain 降格"

# --- case 6a: mode=loop 反映 (本 repo mode.yml = loop) ---
( set -uo pipefail
  out="$(run_plain "$FULL_JSON")"
  printf '%s' "$out" | grep -q 'loop'
) && ok "case6a: mode=loop 反映 (本 repo mode.yml)" || ng "case6a: mode=loop 反映"

# --- case 6b: mode.yml 不在 (cwd=/tmp) → normal ---
( set -uo pipefail
  out="$(run_plain "$NORMAL_MODE_JSON")"
  printf '%s' "$out" | grep -q 'normal'
) && ok "case6b: mode.yml 不在 → normal" || ng "case6b: mode.yml 不在 → normal"

# --- case 7: used 値直接表示 (used 28 → 5h 28% used, used 45 → 7d 45% used) ---
( set -uo pipefail
  line2="$(run_plain "$FULL_JSON" | sed -n '2p')"
  printf '%s' "$line2" | grep -q '5h 28% used' && printf '%s' "$line2" | grep -q '7d 45% used'
) && ok "case7: used 値直接表示 (28 / 45)" || ng "case7: used 値直接表示"

# --- case 8: ANSI escape 含有 (color ON) ---
( set -uo pipefail
  out="$(run_color "$FULL_JSON")"
  printf '%s' "$out" | od -An -c 2>/dev/null | grep -q '033'
) && ok "case8: ANSI escape 含有 (color ON)" || ng "case8: ANSI escape 含有"

# --- case 8b: NO_COLOR で ANSI escape 不在 ---
( set -uo pipefail
  out="$(run_plain "$FULL_JSON")"
  ! printf '%s' "$out" | od -An -c 2>/dev/null | grep -q '033'
) && ok "case8b: NO_COLOR で ANSI escape 不在" || ng "case8b: NO_COLOR で ANSI escape 不在"

# --- case 9: 壊れた JSON でも exit 0 (status 非破壊) ---
( set -uo pipefail
  printf '%s' "$BROKEN_JSON" | HC_STATUSLINE_NO_COLOR=1 bash "$STATUSLINE" >/dev/null 2>&1
) && ok "case9: 壊れた JSON で exit 0" || ng "case9: 壊れた JSON で exit 0"

# --- case 10: 空 stdin でも exit 0 ---
( set -uo pipefail
  printf '' | HC_STATUSLINE_NO_COLOR=1 bash "$STATUSLINE" >/dev/null 2>&1
) && ok "case10: 空 stdin で exit 0" || ng "case10: 空 stdin で exit 0"

# edge inputs (HIGH-1 clamp / 欠落 fallback 検証用)
OVER100_JSON='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":34},"rate_limits":{"five_hour":{"used_percentage":150},"seven_day":{"used_percentage":45}},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'
NEGCTX_JSON='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":-5},"rate_limits":{"five_hour":{"used_percentage":28},"seven_day":{"used_percentage":45}},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'
NOCTX_JSON='{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":28},"seven_day":{"used_percentage":45}},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'
PARTIAL_RL_JSON='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":34},"rate_limits":{"five_hour":{"used_percentage":28}},"workspace":{"current_dir":"'"$REPO_ROOT"'","repo":{"branch":"feat/test-branch"}}}'

# --- case 11: used:150 clamp → 5h 100% used (HIGH-1) ---
( set -uo pipefail
  line2="$(run_plain "$OVER100_JSON" | sed -n '2p')"
  printf '%s' "$line2" | grep -q '5h 100% used'
) && ok "case11: used 150 clamp → 5h 100% used" || ng "case11: used 150 clamp → 5h 100% used (got: $(run_plain "$OVER100_JSON" | sed -n '2p'))"

# --- case 12: ctx:-5 clamp → ctx 0% (HIGH-1) ---
( set -uo pipefail
  line1="$(run_plain "$NEGCTX_JSON" | sed -n '1p')"
  printf '%s' "$line1" | grep -q 'context 0% used'
) && ok "case12: ctx -5 clamp → context 0% used" || ng "case12: ctx -5 clamp → context 0% used (got: $(run_plain "$NEGCTX_JSON" | sed -n '1p'))"

# --- case 13: context_window 欠落 → ctx — ---
( set -uo pipefail
  line1="$(run_plain "$NOCTX_JSON" | sed -n '1p')"
  printf '%s' "$line1" | grep -q 'context —'
) && ok "case13: context_window 欠落 → context —" || ng "case13: context_window 欠落 → context — (got: $(run_plain "$NOCTX_JSON" | sed -n '1p'))"

# --- case 14: rate_limits 片方のみ → もう片方 — ---
( set -uo pipefail
  line2="$(run_plain "$PARTIAL_RL_JSON" | sed -n '2p')"
  printf '%s' "$line2" | grep -q '5h 28% used' && printf '%s' "$line2" | grep -q '7d —'
) && ok "case14: rate_limits 片方のみ → もう片方 —" || ng "case14: rate_limits 片方のみ → もう片方 — (got: $(run_plain "$PARTIAL_RL_JSON" | sed -n '2p'))"

echo "=== result: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
