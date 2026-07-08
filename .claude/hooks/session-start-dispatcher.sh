#!/usr/bin/env bash
# session-start-dispatcher.sh — task-71 Step 4-6 dispatcher (thin wrapper)
#                              + task-104 W1-8 parallel fan-out for bootstrap channel
# 実行 script (sourced lib ではない) → set -uo pipefail は OK (errexit 外す)。
# event 名は固定 literal で run_dispatch に渡す。matcher は $1 (matcher 無し event は空)。
#
# task-104 W1-8 parallel fan-out (default ON to preserve wrapper legacy parallel behavior):
#   HC_SESSION_START_PARALLEL=false で無効化して従来 dispatcher-core.sh 逐次実行に fallback。
#   default (未設定 or true): bootstrap channel の 10 hook を background 並列実行 (< 3s 実測)。
#   並列時も stdout / stderr は tmp file 経由で order 保持、first-block-wins は失われる可能性あるが
#   SessionStart bootstrap channel は非 block 用途のため実務上問題なし。
#   HC_SESSION_START_PARALLEL_JOBS: 並列度 (default 6、range 4-8 推奨)。
#   HC_SESSION_START_PARALLEL_TIMEOUT_SEC: per-hook timeout (default 5)。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dispatcher-core.sh
source "$DIR/lib/dispatcher-core.sh"

# --- task-104 parallel fan-out branch (default ON for < 3s startup) ---
_sd_parallel="${HC_SESSION_START_PARALLEL:-true}"
_sd_parallel_lc=$(printf '%s' "$_sd_parallel" | tr '[:upper:]' '[:lower:]')
case "$_sd_parallel_lc" in
  false|0|no|off) _sd_parallel_on=0 ;;
  *) _sd_parallel_on=1 ;;
esac

if [ "$_sd_parallel_on" != "1" ]; then
  # default: 逐次実行 (dispatcher-core.sh の従来動作)
  run_dispatch "SessionStart" "${1:-}"
  exit $?
fi

# --- 並列 fan-out mode (bootstrap channel、非 block 用途) ---
# manifest から SessionStart bootstrap 行を抽出し、feature toggle enabled のみ background 起動。
# 各子 stdout/stderr は tmp file 経由で保存、wait 後 order 順に集約出力。
_sd_jobs="${HC_SESSION_START_PARALLEL_JOBS:-6}"
case "$_sd_jobs" in
  ''|*[!0-9]*) _sd_jobs=6 ;;
  *)
    [ "$_sd_jobs" -lt 4 ] && _sd_jobs=4
    [ "$_sd_jobs" -gt 8 ] && _sd_jobs=8
    ;;
esac
_sd_timeout="${HC_SESSION_START_PARALLEL_TIMEOUT_SEC:-5}"

# project-root.sh のみ source (config-loader は 1.1s 掛かるため parallel path では skip、
# 各 hook が自前で source して feature gate する = 二重 source 回避)。
# shellcheck source=lib/project-root.sh
. "$DIR/lib/project-root.sh" 2>/dev/null || true

_sd_root="$(resolve_project_root 2>/dev/null || pwd)"
_sd_manifest="$_sd_root/.claude/hooks/dispatcher-manifest.tsv"

if [ ! -f "$_sd_manifest" ]; then
  # manifest 不在 → sequential fallback
  run_dispatch "SessionStart" "${1:-}"
  exit $?
fi

_sd_workdir=$(mktemp -d -t "session-start-parallel.XXXXXX" 2>/dev/null) || {
  # mktemp fail → sequential fallback
  run_dispatch "SessionStart" "${1:-}"
  exit $?
}
trap 'rm -rf "$_sd_workdir" 2>/dev/null || true' EXIT

# stdin (payload) を 1 度読んで全子に replay
_sd_payload="$(cat)"

# manifest から SessionStart bootstrap 行を order 順に抽出
_sd_rows="$(
  awk -F'\t' '
    NR == 1 { next }
    NF < 6 { next }
    $1 == "SessionStart" {
      printf "%s\034%s\034%s\034%s\n", $3, $4, $5, $6
    }
  ' "$_sd_manifest" | sort -t "$(printf '\034')" -k1,1n
)"

if [ -z "$_sd_rows" ]; then
  exit 0
fi

# timeout command detection (BSD/GNU compat)
_sd_timeout_cmd=""
if command -v timeout >/dev/null 2>&1; then
  _sd_timeout_cmd="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _sd_timeout_cmd="gtimeout"
fi

# 各 bootstrap 行を background で起動 (feature toggle enabled かつ file 存在時のみ)
_sd_active_count=0
_sd_pids=""
_sd_order_list=""

# IFS 制御用
_sd_FS="$(printf '\034')"

while IFS="$_sd_FS" read -r _sd_order _sd_cmd _sd_feature _sd_channel; do
  [ -z "$_sd_cmd" ] && continue
  # bootstrap channel 以外 (observer 等) は sequential dispatcher に任せるため skip
  # ここでは bootstrap channel のみ並列化
  [ "$_sd_channel" = "bootstrap" ] || continue

  # feature gate は各 hook が自前で行うため dispatcher parallel path では skip
  # (config-loader source cost 1.1s を避けるため)。dispatcher-core sequential path
  # では従来通り feature gate 適用。

  # hook_command → script + arg (最大 1)
  _sd_script="${_sd_cmd%% *}"
  if [ "$_sd_cmd" = "$_sd_script" ]; then
    _sd_arg=""
  else
    _sd_arg="${_sd_cmd#* }"
  fi
  _sd_hook_path="$_sd_root/.claude/hooks/$_sd_script"
  [ -f "$_sd_hook_path" ] || continue

  # background 起動 (per-hook timeout 適用)
  _sd_out="$_sd_workdir/${_sd_order}.out"
  _sd_err="$_sd_workdir/${_sd_order}.err"
  if [ -n "$_sd_timeout_cmd" ]; then
    if [ -n "$_sd_arg" ]; then
      ( printf '%s' "$_sd_payload" | "$_sd_timeout_cmd" "$_sd_timeout" bash "$_sd_hook_path" "$_sd_arg" > "$_sd_out" 2> "$_sd_err" ) &
    else
      ( printf '%s' "$_sd_payload" | "$_sd_timeout_cmd" "$_sd_timeout" bash "$_sd_hook_path" > "$_sd_out" 2> "$_sd_err" ) &
    fi
  else
    if [ -n "$_sd_arg" ]; then
      ( printf '%s' "$_sd_payload" | bash "$_sd_hook_path" "$_sd_arg" > "$_sd_out" 2> "$_sd_err" ) &
    else
      ( printf '%s' "$_sd_payload" | bash "$_sd_hook_path" > "$_sd_out" 2> "$_sd_err" ) &
    fi
  fi
  _sd_pids="$_sd_pids $!"
  _sd_order_list="$_sd_order_list $_sd_order"
  _sd_active_count=$((_sd_active_count + 1))
  # bootstrap channel は非 block / fail-open 用途のため、全 hook を同時 background 起動する。
  # task spec の 4-8 並列は cap 上限 (advisory)、hook 数が少ない SessionStart では full 並列でも安全。
  # SessionStart hook 数が将来 20+ に増えた場合は _sd_jobs で throttle 可能 (以下 comment out):
  # if [ "$_sd_jobs" -gt 0 ] && [ "$_sd_active_count" -ge "$_sd_jobs" ]; then
  #   _sd_first_pid="${_sd_pids# }"; _sd_first_pid="${_sd_first_pid%% *}"
  #   _sd_pids=" ${_sd_pids#" ${_sd_first_pid}"}"
  #   [ -n "$_sd_first_pid" ] && wait "$_sd_first_pid" 2>/dev/null
  #   _sd_active_count=$((_sd_active_count - 1))
  # fi
done <<EOF
$_sd_rows
EOF

# 残 pids を wait
for _sd_p in $_sd_pids; do
  wait "$_sd_p" 2>/dev/null || true
done

# stdout / stderr を order 順に集約出力
# _sd_order_list は起動順で埋まっているが、実際は manifest order == 起動順なので sort 不要
for _sd_o in $_sd_order_list; do
  _sd_out="$_sd_workdir/${_sd_o}.out"
  if [ -f "$_sd_out" ] && [ -s "$_sd_out" ]; then
    cat "$_sd_out"
  fi
done
for _sd_o in $_sd_order_list; do
  _sd_err="$_sd_workdir/${_sd_o}.err"
  if [ -f "$_sd_err" ] && [ -s "$_sd_err" ]; then
    cat "$_sd_err" >&2
  fi
done

# bootstrap 以外の row (observer 等) を background で追加起動 (順序 don't-care、fail-open)
# observer channel の hook (skills/continuous-learning-v2/hooks/observe.sh) は telemetry のみで
# 出力 / block 判定を行わない (dispatcher-core.sh 不変条件 6: fail-open、原則無出力)。
_sd_observer_rows="$(
  awk -F'\t' '
    NR == 1 { next }
    NF < 6 { next }
    $1 == "SessionStart" && $6 != "bootstrap" {
      printf "%s\034%s\034%s\034%s\n", $3, $4, $5, $6
    }
  ' "$_sd_manifest" | sort -t "$(printf '\034')" -k1,1n
)"
if [ -n "$_sd_observer_rows" ]; then
  while IFS="$_sd_FS" read -r _sd_order _sd_cmd _sd_feature _sd_channel; do
    [ -z "$_sd_cmd" ] && continue
    _sd_script="${_sd_cmd%% *}"
    if [ "$_sd_cmd" = "$_sd_script" ]; then _sd_arg=""
    else _sd_arg="${_sd_cmd#* }"; fi
    _sd_hook_path="$_sd_root/.claude/hooks/$_sd_script"
    [ -f "$_sd_hook_path" ] || continue
    # observer channel は fail-open で無出力 → background で実行 (main を止めない)
    if [ -n "$_sd_arg" ]; then
      ( printf '%s' "$_sd_payload" | bash "$_sd_hook_path" "$_sd_arg" >/dev/null 2>&1 ) &
    else
      ( printf '%s' "$_sd_payload" | bash "$_sd_hook_path" >/dev/null 2>&1 ) &
    fi
  done <<EOF
$_sd_observer_rows
EOF
  # observer は telemetry 用途で main を待たせない (fire-and-forget)
fi

exit 0
