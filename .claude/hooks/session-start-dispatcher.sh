#!/usr/bin/env bash
# session-start-dispatcher.sh — task-71 Step 4-6 dispatcher (thin wrapper)
# 実行 script (sourced lib ではない) → set -uo pipefail は OK (errexit 外す)。
# event 名は固定 literal で run_dispatch に渡す。matcher は $1 (matcher 無し event は空)。
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dispatcher-core.sh
source "$DIR/lib/dispatcher-core.sh"
run_dispatch "SessionStart" "${1:-}"
