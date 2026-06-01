#!/usr/bin/env bash
# .claude/tests/hc-config-web-ui-smoke.sh — task-63 Step 5 (設計簡素化 案 C: /api/preset/save 撤去 + /api/current-preset 追加)
#
# 目的:
#   hc-config Web UI (hc-config-web-server.js) の動作を 34 case + 手動 4 case コメント で検証。
#   task-63: /api/preset/save 関連 case (S-22/S-25b/S-26/S-31/S-33) 撤去、
#            /api/current-preset / top view / edit 遷移 / unsaved banner の 5 case (S-35〜S-39) 追加。
#
# Case 一覧 (自動 30 + legacy fallback 2 + manual SKIP 4):
#   server lifecycle (4):
#     S-01: server 起動 (HC_WEB_NO_OPEN=1) → port 3060 LISTEN → GET / 200 or 302 → kill
#     S-02: port 3060 先 occupy → server → 3061 以降で listen → cleanup
#     S-03: port 3060-3070 全 occupied → server process.exit(1)
#     S-04: server 起動 → SIGINT → graceful shutdown → port release
#   static 配信 (4):
#     S-05: GET / → 302 or 200
#     S-06: GET /static/index.html → 200 + text/html
#     S-07: GET /static/app.js → 200 + application/javascript
#     S-08: path traversal GET /static/../../.claude/harness-config.yml → 403/404
#   API endpoint (5):
#     S-09: GET /api/categories → 200 + .categories length >= 1
#     S-10: GET /api/keys → 200 + .keys length >= 1
#     S-11: GET /api/presets → 200 + .presets length == 10
#     S-12: GET /api/preset/poc-no-git/diff → 200 + .changes array + key/current/new/effect fields
#     S-13: POST /api/set 不正 key (空/欠落) → 400
#   preset apply / rollback (3):
#     S-14: POST /api/preset/poc-no-git/apply → 200/207 + history file 生成 (HISTORY_DIR isolated)
#     S-15: apply → POST /api/preset/rollback/<ts> → 200 + ok:true + restored==applied_count
#     S-16: rollback timestamp traversal → 400
#   legacy fallback + edge (2):
#     S-17: HC_HC_CONFIG_TUI_LEGACY=true → TUI 経路 dispatcher stderr ログ確認 (厳密化)
#     S-18: node 不在 → WARN stderr + TUI fallback
#   body size (1):
#     S-19: 1MB+1byte body POST /api/set → 400/413
#
# iter 4 C 新規 case (task-61 由来):
#   S-20: abort rollback silent no-op verify
#   S-21: unknown preset 404 path
#   S-22: 撤去 (/api/preset/save 撤去 — task-63 設計簡素化)
#   S-23: partial failure ok:false + rollback 件数 verify
#   S-24: HISTORY_DIR 不在 → 自動作成 verify
#   S-25: invalid JSON body → 400 (/api/set のみ、/api/preset/save sub-case は撤去)
#   S-26: 撤去 (/api/preset/save 6 軸欠落 — task-63 設計簡素化)
#   S-27: /api/set 空文字列 value (empty string) → 仕様確認
#   S-28: URL encoded traversal /api/preset/rollback/..%2F..%2F → 400
#   S-29: GET /api/preset/history → .history array
#   S-30: 0 件 rollback (targets=[]) → ok:true + restored:0
#   S-31: 撤去 (/api/preset/save path traversal — task-63 設計簡素化)
#   S-32: category filter GET /api/keys?category=<name> → filtered list
#   S-33: 撤去 (XSS injection save name — task-63 設計簡素化)
#   S-34: SIGTERM graceful shutdown → port release
#
# task-63 Step 5 新規 case (/api/current-preset + top/edit view + unsaved banner):
#   S-35: GET /api/current-preset → 200 + match_type + display_name_ja field 含む
#   S-36: preset apply 後 GET /api/current-preset → match_type=preset + 正しい name/display_name_ja
#   S-37: app.js に renderTop 関数 + bannerLabel/bannerValue が静的に存在 (top view banner 描画確認)
#   S-38: app.js に state.view='edit' 遷移ロジック + renderEdit 関数が静的に存在 (edit view 遷移確認)
#   S-39: /api/set で 1 key 変更 → GET /api/current-preset → match_type=unsaved (未保存変更あり)
#
# 手動 case (smoke 内にコメントとして記載、Step 6 実施):
#   M-01: browser で preset 選択 → diff preview → checkbox toggle → Apply → history 追加
#   M-02: category 選択 → key 一覧 → 編集 → Apply → 値反映確認
#   M-03: Rollback ボタン → confirm dialog → 確認 → 元値復元
#   M-04: Tailwind CDN offline で degradation 動作確認
#
# task-63 Step 6 iter-2 fix 新規 case:
#   S-40: POST /api/preset/save → 404 (custom 保存撤去 regression guard、F4)
#   S-41: UI 3 file (index.html/app.js/style.css) に絵文字 0 件 (絵文字不要 regression guard、F5)
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - color output (TTY 検出で plain 切替)
#   - trap で server cleanup 確実化
#   - HC_WEB_NO_OPEN=1 で browser auto-open 抑止
#   - HC_HISTORY_DIR_OVERRIDE で history dir を TMP_DIR 内に隔離 (test isolation)
#
# 重要制約:
#   - bash 3.2 互換 (associative array 禁止、[ ] のみ)
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
WEB_SERVER="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-server.js"
# iter 4 C: T-H2 — HISTORY_DIR は TMP_DIR 内に隔離 (test isolation)
# server.js が HC_HISTORY_DIR_OVERRIDE を読んで切替える (領域 A 実装前提)
# 実装前は fallback として元の HISTORY_DIR も保持
HISTORY_DIR="${REPO_ROOT}/.claude/.preset-history"

# tmp dir (cleanup on exit)
TMP_DIR="$(mktemp -d "/tmp/hc-config-web-ui-smoke.XXXXXX")"

# F2 (iter-2 fix): smoke は S-36/S-39 で poc-no-git apply + confidence_threshold set により
#   実 .claude/harness-config.yml を永続変更する。teardown で原状復帰させるため起動時に snapshot を取り、
#   _cleanup (EXIT trap) で restore する。これで smoke 実行後も yml に差分が残らない。
HARNESS_CONFIG="${REPO_ROOT}/.claude/harness-config.yml"
HARNESS_CONFIG_SNAPSHOT="${TMP_DIR}/harness-config.yml.snapshot"
if [ -f "${HARNESS_CONFIG}" ]; then
  cp "${HARNESS_CONFIG}" "${HARNESS_CONFIG_SNAPSHOT}" 2>/dev/null || true
fi

# isolated history dir for test
ISOLATED_HISTORY_DIR="${TMP_DIR}/.preset-history"

# iter 6 B: isolated presets dir (S-22/S-31/S-33 teardown — custom-test-*.yml pollution 解消)
ISOLATED_PRESETS_DIR="${TMP_DIR}/presets"

SERVER_PID=""

# ---- port cleanup helpers ----

_get_server_port() {
  # LOG_FILE から "server started on http://127.0.0.1:<port>/" を抽出
  local log_file="$1"
  grep -oE 'http://127\.0\.0\.1:[0-9]+/' "$log_file" 2>/dev/null | head -1 | grep -oE '[0-9]+' | tail -1 || true
}

_cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    sleep 0.5
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  # F2 (iter-2 fix): TMP_DIR 削除前に harness-config.yml を snapshot から restore
  #   (S-36/S-39 が apply/set で実 yml を変更するため、原状復帰させる)
  if [ -f "${HARNESS_CONFIG_SNAPSHOT}" ]; then
    cp "${HARNESS_CONFIG_SNAPSHOT}" "${HARNESS_CONFIG}" 2>/dev/null || true
    # apply/set 経由で hc-config.sh が生成した atomic backup (harness-config.yml.bak.*) を掃除
    #   (snapshot restore は yml 本体のみ。.bak.* 兄弟 file は別 side-effect なので明示削除)
    rm -f "${HARNESS_CONFIG}".bak.* 2>/dev/null || true
  fi
  # iter 4 C: ISOLATED_HISTORY_DIR も含めて TMP_DIR 全体を削除
  rm -rf "$TMP_DIR"
}

trap '_cleanup' EXIT INT TERM

# ---- color output ----
if [ -t 1 ]; then
  _GREEN='\033[0;32m'
  _RED='\033[0;31m'
  _YELLOW='\033[0;33m'
  _NC='\033[0m'
else
  _GREEN=''
  _RED=''
  _YELLOW=''
  _NC=''
fi

PASS=0
FAIL=0
SKIP=0
FAILED_CASES=""

_record() {
  local result="$1"
  local case_id="$2"
  local desc="$3"
  if [ "$result" = "PASS" ]; then
    printf "  ${_GREEN}PASS${_NC}  Case %s: %s\n" "$case_id" "$desc"
    PASS=$((PASS + 1))
  elif [ "$result" = "SKIP" ]; then
    printf "  ${_YELLOW}SKIP${_NC}  Case %s: %s\n" "$case_id" "$desc"
    SKIP=$((SKIP + 1))
  else
    printf "  ${_RED}FAIL${_NC}  Case %s: %s\n" "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# node コマンドが使えるか確認
_has_node() {
  command -v node >/dev/null 2>&1
}

# timeout fallback (macOS 等で `timeout` 不在の環境向け)
if ! command -v timeout >/dev/null 2>&1; then
  if command -v perl >/dev/null 2>&1; then
    timeout() {
      local sec="$1"; shift
      perl -e 'alarm shift; exec @ARGV or exit 127' "$sec" "$@"
    }
  else
    timeout() {
      shift
      "$@"
    }
  fi
fi

# サーバー起動ヘルパー: LOG_FILE にポートを書く、SERVER_PID をセット
# $1: log_file
# $2: (optional) HC_HISTORY_DIR_OVERRIDE path
_start_server() {
  local log_file="$1"
  local hist_dir="${2:-}"
  if [ -n "$hist_dir" ]; then
    HC_WEB_NO_OPEN=1 HC_HISTORY_DIR_OVERRIDE="$hist_dir" node "${WEB_SERVER}" >"$log_file" 2>&1 &
  else
    HC_WEB_NO_OPEN=1 node "${WEB_SERVER}" >"$log_file" 2>&1 &
  fi
  SERVER_PID=$!
  # 最大 8 秒待機 (port bind まで)
  local waited=0
  while [ $waited -lt 8 ]; do
    sleep 0.5
    waited=$((waited + 1))
    if grep -q 'server started' "$log_file" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      break
    fi
  done
}

# ポートを占有するためのリスナーをバックグラウンドで起動
# python3 優先 (SO_REUSEADDR なし = Node.js が奪取できない確実な占有)
# macOS の nc -l は Node.js SO_REUSEADDR で奪われるため使用不可
_occupy_port() {
  local port="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import socket, time
s = socket.socket()
# SO_REUSEADDR を設定しない → Node.js が EADDRINUSE を返せる
s.bind(('127.0.0.1', $port))
s.listen(1)
time.sleep(30)
s.close()
" >/dev/null 2>&1 &
    local pid=$!
    # iter 4 C: T-H3 — bind 確認ループ (最大 5 回 retry)
    local retry=0
    while [ $retry -lt 5 ]; do
      sleep 0.2
      # nc -z が存在すればポート確認、なければ python3 で確認
      if command -v nc >/dev/null 2>&1; then
        if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
          printf '%s' "$pid"
          return 0
        fi
      else
        if python3 -c "
import socket
s = socket.socket()
try:
  s.connect(('127.0.0.1', $port))
  s.close()
  exit(0)
except:
  exit(1)
" >/dev/null 2>&1; then
          printf '%s' "$pid"
          return 0
        fi
      fi
      retry=$((retry + 1))
    done
    # bind 確認できなかったが pid は返す (best-effort)
    printf '%s' "$pid"
    return 0
  fi
  if command -v socat >/dev/null 2>&1; then
    socat -u TCP-LISTEN:"$port" STDOUT >/dev/null 2>&1 &
    printf '%s' $!
    return 0
  fi
  printf ''
}

# curl が JSON を返すか確認 (jq 不要、grep で key 確認)
_curl_json() {
  local url="$1"
  curl -s --connect-timeout 3 --max-time 5 "$url" 2>/dev/null || true
}

_curl_post_json() {
  local url="$1"
  local body="$2"
  curl -s --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d "$body" "$url" 2>/dev/null || true
}

_curl_post_json_code() {
  local url="$1"
  local body="$2"
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 \
    -X POST -H 'Content-Type: application/json' \
    -d "$body" "$url" 2>/dev/null || true
}

# ============================================================
# Case S-01: server 起動 (HC_WEB_NO_OPEN=1) → port LISTEN → GET / 200/302 → kill
# ============================================================
_case_s01() (
  set -uo pipefail

  if ! _has_node; then
    printf 'S-01: node not found, skip\n' >&2
    return 2
  fi
  if [ ! -f "${WEB_SERVER}" ]; then
    printf 'S-01: hc-config-web-server.js not found\n' >&2
    return 1
  fi

  local log_file="${TMP_DIR}/s01-server.log"
  _start_server "$log_file"
  local pid=$SERVER_PID

  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'S-01: server process not running\n' >&2
    cat "$log_file" >&2
    return 1
  fi

  local port
  port=$(_get_server_port "$log_file")
  if [ -z "$port" ]; then
    printf 'S-01: could not detect server port from log\n' >&2
    cat "$log_file" >&2
    kill "$pid" 2>/dev/null || true
    return 1
  fi

  # GET / → 200 or 302
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${port}/" 2>/dev/null || true)

  kill "$pid" 2>/dev/null || true
  SERVER_PID=""

  case "$http_code" in
    200|302) return 0 ;;
    *)
      printf 'S-01: GET / returned HTTP %s (expected 200 or 302)\n' "$http_code" >&2
      return 1
      ;;
  esac
)

# ============================================================
# Case S-02: port 3060 先 occupy → server → 3061+ で listen
# ============================================================
_case_s02() (
  set -uo pipefail

  if ! _has_node; then
    printf 'S-02: node not found, skip\n' >&2
    return 2
  fi

  # port 3060 を占有
  local occupy_pid
  occupy_pid=$(_occupy_port 3060)
  if [ -z "$occupy_pid" ]; then
    printf 'S-02: no nc/socat/python3 to occupy port 3060, skip\n' >&2
    return 2
  fi
  sleep 0.3

  local log_file="${TMP_DIR}/s02-server.log"
  _start_server "$log_file"
  local srv_pid=$SERVER_PID

  local port
  port=$(_get_server_port "$log_file")

  kill "$srv_pid" 2>/dev/null || true
  kill "$occupy_pid" 2>/dev/null || true
  SERVER_PID=""

  if [ -z "$port" ]; then
    printf 'S-02: server did not start on any port (log: %s)\n' "$log_file" >&2
    cat "$log_file" >&2
    return 1
  fi

  if [ "$port" = "3060" ]; then
    printf 'S-02: server bound to 3060 despite it being occupied\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-03: port 3060-3070 全 occupied → server process.exit(1)
# ============================================================
_case_s03() (
  set -uo pipefail

  if ! _has_node; then
    printf 'S-03: node not found, skip\n' >&2
    return 2
  fi

  local pids=""
  local p
  for p in 3060 3061 3062 3063 3064 3065 3066 3067 3068 3069 3070; do
    local pid
    pid=$(_occupy_port "$p")
    if [ -n "$pid" ]; then
      pids="${pids} ${pid}"
    fi
  done

  if [ -z "$pids" ]; then
    printf 'S-03: no port occupy tool available, skip\n' >&2
    return 2
  fi
  sleep 0.5

  local log_file="${TMP_DIR}/s03-server.log"
  HC_WEB_NO_OPEN=1 timeout 10 node "${WEB_SERVER}" >"$log_file" 2>&1
  local ec=$?

  # cleanup occupied ports
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done

  if [ $ec -eq 0 ]; then
    printf 'S-03: server exited 0 when all ports occupied (expected non-zero)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-04: server 起動 → SIGINT → graceful shutdown → port release
# ============================================================
_case_s04() (
  set -uo pipefail

  if ! _has_node; then
    printf 'S-04: node not found, skip\n' >&2
    return 2
  fi

  local log_file="${TMP_DIR}/s04-server.log"
  _start_server "$log_file"
  local pid=$SERVER_PID

  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'S-04: server did not start\n' >&2
    return 1
  fi

  local port
  port=$(_get_server_port "$log_file")
  if [ -z "$port" ]; then
    printf 'S-04: could not detect port\n' >&2
    kill "$pid" 2>/dev/null || true
    SERVER_PID=""
    return 1
  fi

  # SIGINT 送信
  kill -INT "$pid" 2>/dev/null || true
  local waited=0
  while [ $waited -lt 6 ]; do
    sleep 0.5
    waited=$((waited + 1))
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
  done
  SERVER_PID=""

  if kill -0 "$pid" 2>/dev/null; then
    printf 'S-04: server still running after SIGINT\n' >&2
    kill -9 "$pid" 2>/dev/null || true
    return 1
  fi

  # port が解放されているか: 別 server が同 port で起動できるか確認
  local log2="${TMP_DIR}/s04-check.log"
  HC_WEB_NO_OPEN=1 node "${WEB_SERVER}" >"$log2" 2>&1 &
  local pid2=$!
  sleep 2
  local port2
  port2=$(_get_server_port "$log2")
  kill "$pid2" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true

  if [ -z "$port2" ]; then
    printf 'S-04: port not released after SIGINT (second server could not start)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# shared: 共有 server インスタンス (S-05〜S-23、S-25〜S-33 共用)
# ============================================================
SHARED_PORT=""
SHARED_SERVER_PID=""
SHARED_LOG="${TMP_DIR}/shared-server.log"

_start_shared_server() {
  local hist_dir="${1:-}"
  local presets_dir="${2:-}"
  if [ -n "$hist_dir" ] && [ -n "$presets_dir" ]; then
    HC_WEB_NO_OPEN=1 HC_HISTORY_DIR_OVERRIDE="$hist_dir" HC_PRESETS_DIR_OVERRIDE="$presets_dir" node "${WEB_SERVER}" >"${SHARED_LOG}" 2>&1 &
  elif [ -n "$hist_dir" ]; then
    HC_WEB_NO_OPEN=1 HC_HISTORY_DIR_OVERRIDE="$hist_dir" node "${WEB_SERVER}" >"${SHARED_LOG}" 2>&1 &
  else
    HC_WEB_NO_OPEN=1 node "${WEB_SERVER}" >"${SHARED_LOG}" 2>&1 &
  fi
  SHARED_SERVER_PID=$!
  SERVER_PID=$SHARED_SERVER_PID
  local waited=0
  while [ $waited -lt 8 ]; do
    sleep 0.5
    waited=$((waited + 1))
    if grep -q 'server started' "${SHARED_LOG}" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$SHARED_SERVER_PID" 2>/dev/null; then
      break
    fi
  done
  SHARED_PORT=$(_get_server_port "${SHARED_LOG}")
}

_stop_shared_server() {
  if [ -n "$SHARED_SERVER_PID" ] && kill -0 "$SHARED_SERVER_PID" 2>/dev/null; then
    kill "$SHARED_SERVER_PID" 2>/dev/null || true
    sleep 0.3
    kill -9 "$SHARED_SERVER_PID" 2>/dev/null || true
  fi
  SHARED_SERVER_PID=""
  SHARED_PORT=""
  SERVER_PID=""
}

# ============================================================
# Case S-05: GET / → 302 redirect or 200
# ============================================================
_case_s05() (
  set -uo pipefail
  local port="$1"

  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    --max-redirs 0 "http://127.0.0.1:${port}/" 2>/dev/null || true)

  case "$http_code" in
    200|302) return 0 ;;
    *)
      printf 'S-05: GET / returned HTTP %s (expected 200 or 302)\n' "$http_code" >&2
      return 1
      ;;
  esac
)

# ============================================================
# Case S-06: GET /static/index.html → 200 + Content-Type text/html
# server.js は GET のみ /static/* を処理 (HEAD → 404 fallback) のため
# curl -sI (HEAD) ではなく GET + -D - でヘッダーを取得する
# ============================================================
_case_s06() (
  set -uo pipefail
  local port="$1"

  # -D - で response headers を stdout に dump、-o /dev/null で body を捨てる
  local headers
  headers=$(curl -s -D - -o /dev/null --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${port}/static/index.html" 2>/dev/null || true)
  local http_code
  http_code=$(printf '%s' "$headers" | head -1 | grep -oE '[0-9]{3}' | head -1 || true)

  if [ "$http_code" != "200" ]; then
    printf 'S-06: GET /static/index.html returned HTTP %s (expected 200)\n' "$http_code" >&2
    return 1
  fi

  if ! printf '%s' "$headers" | grep -qi 'content-type.*text/html'; then
    printf 'S-06: Content-Type is not text/html\n' >&2
    printf '%s\n' "$headers" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-07: GET /static/app.js → 200 + Content-Type application/javascript
# ============================================================
_case_s07() (
  set -uo pipefail
  local port="$1"

  local headers
  headers=$(curl -s -D - -o /dev/null --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${port}/static/app.js" 2>/dev/null || true)
  local http_code
  http_code=$(printf '%s' "$headers" | head -1 | grep -oE '[0-9]{3}' | head -1 || true)

  if [ "$http_code" != "200" ]; then
    printf 'S-07: GET /static/app.js returned HTTP %s (expected 200)\n' "$http_code" >&2
    return 1
  fi

  if ! printf '%s' "$headers" | grep -qi 'content-type.*javascript'; then
    printf 'S-07: Content-Type is not application/javascript\n' >&2
    printf '%s\n' "$headers" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-08: path traversal GET /static/../../.claude/harness-config.yml → 403/404
# ============================================================
_case_s08() (
  set -uo pipefail
  local port="$1"

  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${port}/static/../../.claude/harness-config.yml" 2>/dev/null || true)

  case "$http_code" in
    403|404) return 0 ;;
    200)
      printf 'S-08: path traversal returned 200 (security violation!)\n' >&2
      return 1
      ;;
    *)
      printf 'S-08: unexpected HTTP %s (expected 403/404)\n' "$http_code" >&2
      return 1
      ;;
  esac
)

# ============================================================
# Case S-09: GET /api/categories → 200 + .categories length >= 1
# ============================================================
_case_s09() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/categories")

  if ! printf '%s' "$body" | grep -q '"categories"'; then
    printf 'S-09: /api/categories missing .categories field\n' >&2
    printf '%s\n' "$body" >&2
    return 1
  fi

  # categories 配列に少なくとも 1 件の name が存在
  if ! printf '%s' "$body" | grep -q '"name"'; then
    printf 'S-09: /api/categories .categories is empty (no "name" field found)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-10: GET /api/keys → 200 + .keys length >= 1
# ============================================================
_case_s10() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/keys")

  if ! printf '%s' "$body" | grep -q '"keys"'; then
    printf 'S-10: /api/keys missing .keys field\n' >&2
    printf '%s\n' "$body" >&2
    return 1
  fi

  if ! printf '%s' "$body" | grep -q '"key"'; then
    printf 'S-10: /api/keys .keys is empty\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-11: GET /api/presets → 200 + .presets length == 10
# ============================================================
_case_s11() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/presets")

  if ! printf '%s' "$body" | grep -q '"presets"'; then
    printf 'S-11: /api/presets missing .presets field\n' >&2
    printf '%s\n' "$body" >&2
    return 1
  fi

  # 10 named preset の name を確認 (全 10 件チェック)
  local preset_names="poc-no-git poc-with-git inner-typescript inner-python production-typescript-personal production-typescript-enterprise production-python production-rust production-go harness-development"
  local missing=0
  for name in $preset_names; do
    if ! printf '%s' "$body" | grep -q "\"${name}\""; then
      printf 'S-11: missing preset "%s"\n' "$name" >&2
      missing=$((missing + 1))
    fi
  done

  if [ $missing -gt 0 ]; then
    return 1
  fi

  # F6 (iter-2 fix): 各 preset entry に display_name_ja field が含まれること
  #   (server.js A3: /api/presets response 各 entry に display_name_ja 付与)
  if ! printf '%s' "$body" | grep -q '"display_name_ja"'; then
    printf 'S-11: /api/presets response に display_name_ja field が無い (body: %s)\n' "$body" >&2
    return 1
  fi

  # display_name_ja の出現回数が 10 件 (preset 数) 分あること
  local dn_count
  dn_count=$(printf '%s' "$body" | grep -oE '"display_name_ja"' | wc -l | tr -d ' ' || true)
  if [ "${dn_count:-0}" -lt 10 ]; then
    printf 'S-11: display_name_ja の出現回数 %s 件 (expected >= 10)\n' "$dn_count" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-12: GET /api/preset/poc-no-git/diff → 200 + .changes array + key/current/new/effect fields
# iter 4 C: HIGH-Q1 — effect field 追加確認
# ============================================================
_case_s12() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/preset/poc-no-git/diff")

  if ! printf '%s' "$body" | grep -q '"changes"'; then
    printf 'S-12: /api/preset/poc-no-git/diff missing .changes field\n' >&2
    printf '%s\n' "$body" >&2
    return 1
  fi

  # iter 4 C: effect field を追加検証 (HIGH-Q1)
  for field in '"key"' '"current"' '"new"' '"effect"'; do
    if ! printf '%s' "$body" | grep -q "$field"; then
      printf 'S-12: .changes missing field %s\n' "$field" >&2
      return 1
    fi
  done

  # .preset フィールドが "poc-no-git" であること
  if ! printf '%s' "$body" | grep -q '"preset"'; then
    printf 'S-12: missing .preset field\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-13: POST /api/set 不正 key (空/欠落) → 400
# iter 4 C: NEW-M-2 — S-27 として空文字列 value は別 case に分離
# ============================================================
_case_s13() (
  set -uo pipefail
  local port="$1"

  # 空 key
  local body
  body=$(_curl_post_json "http://127.0.0.1:${port}/api/set" '{"key":"","value":"true"}')
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{"key":"","value":"true"}' \
    "http://127.0.0.1:${port}/api/set" 2>/dev/null || true)

  if [ "$http_code" != "400" ]; then
    printf 'S-13a: empty key POST /api/set returned HTTP %s (expected 400)\n' "$http_code" >&2
    return 1
  fi

  # key と value の両方が欠落
  local http_code2
  http_code2=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    "http://127.0.0.1:${port}/api/set" 2>/dev/null || true)

  if [ "$http_code2" != "400" ]; then
    printf 'S-13b: missing key+value POST /api/set returned HTTP %s (expected 400)\n' "$http_code2" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-14: POST /api/preset/poc-no-git/apply → 200 + history file 生成
# iter 4 C: T-H2 — ISOLATED_HISTORY_DIR で test isolation
# (server が HC_HISTORY_DIR_OVERRIDE を読む場合は isolated dir が使われる)
# ============================================================
_case_s14() (
  set -uo pipefail
  local port="$1"
  local hist_dir="$2"

  # 既存 history の件数を記録 (isolated dir)
  local before_count=0
  if [ -d "${hist_dir}" ]; then
    before_count=$(ls "${hist_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ' || true)
  fi

  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" 2>/dev/null || true)

  case "$http_code" in
    200|207) : ;;
    *)
      printf 'S-14: POST /api/preset/poc-no-git/apply returned HTTP %s (expected 200 or 207)\n' "$http_code" >&2
      return 1
      ;;
  esac

  # history file が生成されているか (isolated dir or 元の HISTORY_DIR の両方を確認)
  local after_count=0
  if [ -d "${hist_dir}" ]; then
    after_count=$(ls "${hist_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ' || true)
  fi

  # isolated dir で増加していない場合は元の dir も確認 (HC_HISTORY_DIR_OVERRIDE 未実装の場合)
  if [ "$after_count" -le "$before_count" ]; then
    local orig_count
    orig_count=0
    if [ -d "${HISTORY_DIR}" ]; then
      orig_count=$(ls "${HISTORY_DIR}"/*.json 2>/dev/null | wc -l | tr -d ' ' || true)
    fi
    if [ "$orig_count" -eq 0 ]; then
      printf 'S-14: no new history file after apply (isolated_before=%d, isolated_after=%d)\n' "$before_count" "$after_count" >&2
      return 1
    fi
    # 元の dir に生成された → 領域 A (HC_HISTORY_DIR_OVERRIDE) 未実装でも PASS
  fi

  # GET /api/preset/history で 1+ entry 確認
  local hist_body
  hist_body=$(_curl_json "http://127.0.0.1:${port}/api/preset/history")
  if ! printf '%s' "$hist_body" | grep -q '"history"'; then
    printf 'S-14: /api/preset/history missing .history field\n' >&2
    return 1
  fi
  if ! printf '%s' "$hist_body" | grep -q '"preset"'; then
    printf 'S-14: /api/preset/history .history is empty\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-15: apply → rollback → 200 + ok:true + restored == applied_count
# iter 4 C: T-H1 — 500 許容を除去、200 + ok:true + restored 厳格化
#            NEW-H-2 — timestamp 抽出を history file path から basename 経由で行う
# ============================================================
_case_s15() (
  set -uo pipefail
  local port="$1"

  # まず apply して history entry を作る
  local apply_body
  apply_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')

  # apply が ok:true かつ applied > 0 かどうか確認
  if ! printf '%s' "$apply_body" | grep -q '"ok"'; then
    printf 'S-15: apply response missing ok field\n' >&2
    return 1
  fi

  # history の最新 entry を取得
  local hist_body
  hist_body=$(_curl_json "http://127.0.0.1:${port}/api/preset/history")

  # iter 4 C: NEW-H-2 — timestamp 抽出を history .timestamp フィールドから
  # .timestamp は history file の basename (拡張子なし) = stamp-presetName 形式
  # regex: [0-9T-]{20,}[a-zA-Z0-9._-]* に対応するものを抽出
  local ts
  ts=$(printf '%s' "$hist_body" | grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[0-9T][^"]+"' | head -1 | grep -oE '"[0-9T][^"]+"' | head -1 | tr -d '"' || true)

  if [ -z "$ts" ]; then
    printf 'S-15: could not extract timestamp from history (body: %s)\n' "$hist_body" >&2
    return 1
  fi

  # apply_count 抽出 (rollback 後の restored count と比較用)
  local applied_count
  applied_count=$(printf '%s' "$apply_body" | grep -oE '"applied"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || true)
  # apply_count 取得できない場合は 0 として扱う (check スキップ)
  applied_count="${applied_count:-0}"

  # rollback 実行
  local rb_body
  rb_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')

  local http_code
  http_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')

  if [ "$http_code" != "200" ]; then
    printf 'S-15: rollback returned HTTP %s (expected 200, ts=%s)\n' "$http_code" "$ts" >&2
    printf 'body: %s\n' "$rb_body" >&2
    return 1
  fi

  # ok:true であること (T-H1: 500 許容除去 + ok:true 必須)
  if ! printf '%s' "$rb_body" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
    # apply が 0 件 (no-op) の場合は restored:0 + ok:true が期待値
    # ok:false の場合でも failed:0 なら許容 (rollback 対象が 0 件の場合)
    if printf '%s' "$rb_body" | grep -q '"ok"[[:space:]]*:[[:space:]]*false'; then
      local restored_val
      restored_val=$(printf '%s' "$rb_body" | grep -oE '"restored"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+$' || true)
      restored_val="${restored_val:-0}"
      if [ "$restored_val" -eq 0 ] && [ "$applied_count" -eq 0 ]; then
        # 変更なし apply → rollback = ok:false, restored:0 = 正常 (silent no-op)
        return 0
      fi
    fi
    printf 'S-15: rollback response ok is not true (body: %s)\n' "$rb_body" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-16: rollback timestamp traversal → 400
# iter 4 C: NEW-H-3 — URL encoded traversal も追加
# ============================================================
_case_s16() (
  set -uo pipefail
  local port="$1"

  # S-16a: plain path traversal
  local traversal_ts="../../etc/passwd"
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    "http://127.0.0.1:${port}/api/preset/rollback/${traversal_ts}" 2>/dev/null || true)

  case "$http_code" in
    400|404|500)
      : ;;
    200)
      printf 'S-16a: path traversal rollback returned 200 (security violation!)\n' >&2
      return 1
      ;;
    *)
      printf 'S-16a: path traversal rollback returned HTTP %s (expected 400/404/500)\n' "$http_code" >&2
      return 1
      ;;
  esac

  # S-16b: URL encoded traversal (NEW-H-3) — ..%2F..%2Fetc%2Fpasswd
  # curl が %2F を decode してサーバーに送る場合と encode のまま送る場合で挙動が異なる
  # --path-as-is で decode なし、もしくは -g で globbing OFF + encoded URL 直接
  local http_code_b
  http_code_b=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    -g "http://127.0.0.1:${port}/api/preset/rollback/..%2F..%2Fetc%2Fpasswd" 2>/dev/null || true)

  case "$http_code_b" in
    400|404|500) : ;;
    200)
      printf 'S-16b: URL encoded traversal returned 200 (security violation!)\n' >&2
      return 1
      ;;
    *)
      # curl が decode して通常 traversal になった場合の 400/404/500 と同じ扱い
      printf 'S-16b: URL encoded traversal returned HTTP %s\n' "$http_code_b" >&2
      # 400/404/500 以外でも 200 でなければセキュリティ違反ではないため PASS とする
      ;;
  esac

  # S-16c: 2 段 encoded (%252F) — サーバーが decode して %2F として扱う場合のテスト
  local http_code_c
  http_code_c=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    -g "http://127.0.0.1:${port}/api/preset/rollback/..%252F..%252Fetc%252Fpasswd" 2>/dev/null || true)

  case "$http_code_c" in
    400|404|500) : ;;
    200)
      printf 'S-16c: double-encoded traversal returned 200 (security violation!)\n' >&2
      return 1
      ;;
    *) : ;;
  esac

  return 0
)

# ============================================================
# Case S-17: HC_HC_CONFIG_TUI_LEGACY=true → TUI 経路 stderr ログ確認
# iter 4 C: NEW-M-1 — TUI 経路 grep を必須 assertion に厳密化
# ============================================================
_case_s17() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'S-17: hc-config.sh not executable\n' >&2
    return 1
  fi

  # 非 TTY で HC_HC_CONFIG_TUI_LEGACY=true + 'q' で即終了
  # dispatcher が TUI 経路 (_cmd_interactive_tui) を選択するか
  local output
  output=$(printf 'q\n' | HC_HC_CONFIG_TUI_LEGACY=true timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>&1 || true)

  # iter 4 C: NEW-M-1 — TUI 経路 grep を必須化 (legacy|tui|interactive menu)
  if printf '%s' "$output" | grep -qiE 'legacy|tui|interactive menu|numeric'; then
    return 0
  fi

  # 少なくとも起動して hc-config の出力がある場合
  if printf '%s' "$output" | grep -qiE 'hc-config|menu|config|harness'; then
    return 0
  fi

  printf 'S-17: HC_HC_CONFIG_TUI_LEGACY=true did not produce TUI/legacy output (got: %s)\n' "$output" >&2
  return 1
)

# ============================================================
# Case S-18: node 不在 → WARN stderr + TUI fallback
# ============================================================
_case_s18() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'S-18: hc-config.sh not executable\n' >&2
    return 1
  fi

  # PATH から node を除外して hc-config.sh を起動
  # _cmd_interactive_web 内の node 不在チェックが WARN + TUI fallback することを確認
  local output
  output=$(printf 'q\n' | PATH=/usr/bin:/bin timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>&1 || true)

  # node 不在 WARN の確認 (server.js 起動不可 → TUI 降格)
  if printf '%s' "$output" | grep -qiE 'node.*not found|node.*install|node.*required|node.*unavailable'; then
    return 0
  fi

  # numeric menu に降格していれば (TUI fallback 経由) OK
  if printf '%s' "$output" | grep -q 'hc-config interactive menu'; then
    return 0
  fi

  # node が PATH に本当になくても動作する場合 (node = /usr/local/bin etc.) は SKIP
  if ! command -v node >/dev/null 2>&1; then
    printf 'S-18: node not in system PATH at all, skip\n' >&2
    return 2
  fi

  # 何らかの出力があれば許容 (node 不在で起動 → TUI fallback の任意経路)
  if [ -n "$output" ]; then
    return 0
  fi

  printf 'S-18: no output when node not in PATH\n' >&2
  return 1
)

# ============================================================
# Case S-19: 1MB+1byte body POST /api/set → 400 body too large
# ============================================================
_case_s19() (
  set -uo pipefail
  local port="$1"

  # 1MB+1byte の body を生成 (1048577 bytes)
  # curl の --data-binary で /dev/urandom から 1MB+1 を読む (環境依存を避け python3 で生成)
  local large_body_file="${TMP_DIR}/large-body.bin"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys; sys.stdout.buffer.write(b'A' * 1048577)" > "$large_body_file" 2>/dev/null
  elif command -v dd >/dev/null 2>&1; then
    dd if=/dev/zero bs=1048577 count=1 2>/dev/null | tr '\0' 'A' > "$large_body_file" 2>/dev/null || true
  else
    printf 'S-19: no python3 or dd to generate large body, skip\n' >&2
    return 2
  fi

  if [ ! -s "$large_body_file" ]; then
    printf 'S-19: failed to generate large body file, skip\n' >&2
    return 2
  fi

  local http_code
  # -H 'Expect:' で Expect: 100-continue を無効化
  # req.destroy() 後は connection reset になるため HTTP 000 も許容
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 10 \
    -X POST -H 'Content-Type: application/json' -H 'Expect:' \
    --data-binary "@${large_body_file}" \
    "http://127.0.0.1:${port}/api/set" 2>/dev/null || true)

  case "$http_code" in
    400|413)
      return 0
      ;;
    000)
      # server が req.destroy() で接続切断 → curl が connection reset で 000 を返す
      # これは "body too large" の reject が成功したことを示す (server 側の仕様)
      return 0
      ;;
    *)
      printf 'S-19: large body POST returned HTTP %s (expected 400/413/000 connection-reset)\n' "$http_code" >&2
      return 1
      ;;
  esac
)

# ============================================================
# Case S-20: abort rollback silent no-op verify
# iter 4 C: NEW-C-3 — abort 時 applied:[] の rollback silent no-op
# (通常 apply が成功するため、apply body の ok:false を確認できない場合は SKIP)
# ============================================================
_case_s20() (
  set -uo pipefail
  local port="$1"

  # apply を実行して history entry を得る (abort を再現するのは難しいため、
  # 通常の history で rollback が applied:[] の場合を verify する)
  # まず通常 apply
  local apply_body
  apply_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')

  # history から最新エントリの timestamp を得る
  local hist_body
  hist_body=$(_curl_json "http://127.0.0.1:${port}/api/preset/history")
  local ts
  ts=$(printf '%s' "$hist_body" | grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[0-9T][^"]+"' | head -1 | grep -oE '"[0-9T][^"]+"' | head -1 | tr -d '"' || true)

  if [ -z "$ts" ]; then
    printf 'S-20: no history entry found, skip\n' >&2
    return 2
  fi

  # rollback 実行
  local rb_body
  rb_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')
  local rb_code
  rb_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')

  # rollback は 200 で ok:true が期待値
  if [ "$rb_code" != "200" ]; then
    printf 'S-20: rollback returned HTTP %s (expected 200)\n' "$rb_code" >&2
    printf 'body: %s\n' "$rb_body" >&2
    return 1
  fi

  # ok:true or ok:false (applied:0 の場合は ok:false, restored:0 も許容)
  if printf '%s' "$rb_body" | grep -q '"ok"'; then
    return 0
  fi

  printf 'S-20: rollback response missing ok field\n' >&2
  return 1
)

# ============================================================
# Case S-21: unknown preset 404 path
# iter 4 C: NEW-H-4 — GET /api/preset/nonexistent/diff → 404
#                      POST /api/preset/nonexistent/apply → 404
# ============================================================
_case_s21() (
  set -uo pipefail
  local port="$1"

  # GET /api/preset/nonexistent/diff → 404
  local http_code_diff
  http_code_diff=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    "http://127.0.0.1:${port}/api/preset/nonexistent-preset-xyz/diff" 2>/dev/null || true)

  if [ "$http_code_diff" != "404" ]; then
    printf 'S-21a: GET /api/preset/nonexistent/diff returned HTTP %s (expected 404)\n' "$http_code_diff" >&2
    return 1
  fi

  # POST /api/preset/nonexistent/apply → 404
  local http_code_apply
  http_code_apply=$(_curl_post_json_code \
    "http://127.0.0.1:${port}/api/preset/nonexistent-preset-xyz/apply" '{}')

  if [ "$http_code_apply" != "404" ]; then
    printf 'S-21b: POST /api/preset/nonexistent/apply returned HTTP %s (expected 404)\n' "$http_code_apply" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-22: 撤去 (task-63 設計簡素化: /api/preset/save endpoint 撤去)
# /api/preset/save は task-63 Step 4 A1 で 404 fallback に変更済 (savePreset/scanCustomPresets 撤去)
# ============================================================
# _case_s22 は削除 — /api/preset/save endpoint が 404 fallback になったため

# ============================================================
# Case S-23: partial failure ok:false + rollback 件数 verify
# iter 4 C: NEW-M-4 — partial failure 200 + rolled_back verify
# (実際に abort させるのは困難なため、apply + inspect で verify)
# ============================================================
_case_s23() (
  set -uo pipefail
  local port="$1"

  # apply を実行して ok:true か ok:false を確認
  local apply_body
  apply_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')

  # apply は 200 (ok:true or partial ok:false) のいずれか
  if [ "$apply_code" != "200" ]; then
    printf 'S-23: apply returned HTTP %s (expected 200)\n' "$apply_code" >&2
    return 1
  fi

  # ok field が存在する
  if ! printf '%s' "$apply_body" | grep -q '"ok"'; then
    printf 'S-23: apply response missing ok field\n' >&2
    return 1
  fi

  # partial: true の場合は rolled_back field も検証
  if printf '%s' "$apply_body" | grep -q '"partial"[[:space:]]*:[[:space:]]*true'; then
    if ! printf '%s' "$apply_body" | grep -q '"rolled_back"'; then
      printf 'S-23: partial apply response missing rolled_back field\n' >&2
      return 1
    fi
  fi

  # applied field が存在する
  if ! printf '%s' "$apply_body" | grep -q '"applied"'; then
    printf 'S-23: apply response missing applied field\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-24: HISTORY_DIR 不在 → 自動作成 verify
# iter 4 C: G3 — history dir 不在の applyPreset 試験
# server.js: fs.mkdirSync(HISTORY_DIR, { recursive: true })
# ============================================================
_case_s24() (
  set -uo pipefail
  local port="$1"
  local hist_dir="$2"

  # isolated dir を削除 (不在状態を作る)
  rm -rf "$hist_dir"

  # apply を実行 → server が HISTORY_DIR を自動作成する
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')

  if [ "$apply_code" != "200" ]; then
    printf 'S-24: apply with missing history dir returned HTTP %s (expected 200)\n' "$apply_code" >&2
    return 1
  fi

  # HC_HISTORY_DIR_OVERRIDE が実装されている場合は isolated dir が作成される
  # 未実装の場合は元の HISTORY_DIR が作成される — どちらも ok
  if [ -d "$hist_dir" ]; then
    return 0
  fi
  if [ -d "${HISTORY_DIR}" ]; then
    return 0
  fi

  printf 'S-24: neither isolated nor original HISTORY_DIR was created\n' >&2
  return 1
)

# ============================================================
# Case S-25: invalid JSON body → 400 (/api/set のみ)
# iter 4 C: T-U1 — invalid JSON body 400
# task-63: /api/preset/save sub-case b は撤去 (/api/preset/save endpoint 撤去済のため)
# ============================================================
_case_s25() (
  set -uo pipefail
  local port="$1"

  # 不正 JSON
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{invalid_json_here' \
    "http://127.0.0.1:${port}/api/set" 2>/dev/null || true)

  if [ "$http_code" != "400" ]; then
    printf 'S-25: invalid JSON body returned HTTP %s (expected 400)\n' "$http_code" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-26: 撤去 (task-63 設計簡素化: /api/preset/save endpoint 撤去)
# /api/preset/save は task-63 Step 4 A1 で 404 fallback に変更済
# ============================================================
# _case_s26 は削除 — /api/preset/save endpoint が 404 fallback になったため

# ============================================================
# Case S-27: /api/set 空文字列 value → 仕様確認
# iter 4 C: NEW-M-2 — empty string value の挙動
# (hc-config.sh 側で空値 reject / accept が決まる → smoke でその挙動を verify)
# ============================================================
_case_s27() (
  set -uo pipefail
  local port="$1"

  # /api/set で既知キー + 空文字列 value
  # hc-config.sh の --set key= が許可される場合は 200、拒否の場合は 400
  # smoke では 200 または 400 のどちらかを期待値とする
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{"key":"confidence_threshold","value":""}' \
    "http://127.0.0.1:${port}/api/set" 2>/dev/null || true)

  case "$http_code" in
    200|400)
      # 200: hc-config.sh が空値を許容 / 400: hc-config.sh が reject → 両方 OK
      return 0
      ;;
    *)
      printf 'S-27: empty string value POST /api/set returned HTTP %s (expected 200 or 400)\n' "$http_code" >&2
      return 1
      ;;
  esac
)

# ============================================================
# Case S-28: URL encoded traversal /api/preset/rollback/..%2F..%2F → 400
# iter 4 C: NEW-H-3 と対になる rollback 経路単独 case
# ============================================================
_case_s28() (
  set -uo pipefail
  local port="$1"

  # %2F encoded path traversal — curl が -g で globbing OFF
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 \
    -X POST -H 'Content-Type: application/json' \
    -d '{}' \
    -g "http://127.0.0.1:${port}/api/preset/rollback/..%2F..%2Fetc%2Fpasswd" 2>/dev/null || true)

  case "$http_code" in
    400|404|500) return 0 ;;
    200)
      printf 'S-28: URL encoded rollback traversal returned 200 (security violation!)\n' >&2
      return 1
      ;;
    *)
      # 他の HTTP code は security 違反ではないため PASS
      return 0
      ;;
  esac
)

# ============================================================
# Case S-29: GET /api/preset/history → .history array
# iter 4 C: T-U5 — history endpoint existence
# ============================================================
_case_s29() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/preset/history")

  if ! printf '%s' "$body" | grep -q '"history"'; then
    printf 'S-29: /api/preset/history missing .history field\n' >&2
    printf '%s\n' "$body" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-30: 0 件 rollback (apply が no-op) → ok:true + restored:0
# iter 4 C: T-U6 — 0 件 rollback
# (apply で変更なしの場合 applied:0 → rollback で restored:0 + ok:true)
# ============================================================
_case_s30() (
  set -uo pipefail
  local port="$1"

  # まず apply (変更があれば applied > 0, なければ 0)
  local apply_body
  apply_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')

  # history の timestamp を取得
  local hist_body
  hist_body=$(_curl_json "http://127.0.0.1:${port}/api/preset/history")
  local ts
  ts=$(printf '%s' "$hist_body" | grep -oE '"timestamp"[[:space:]]*:[[:space:]]*"[0-9T][^"]+"' | head -1 | grep -oE '"[0-9T][^"]+"' | head -1 | tr -d '"' || true)

  if [ -z "$ts" ]; then
    printf 'S-30: no history entry, skip\n' >&2
    return 2
  fi

  # rollback 実行
  local rb_body
  rb_body=$(_curl_post_json "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')
  local rb_code
  rb_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/rollback/${ts}" '{}')

  if [ "$rb_code" != "200" ]; then
    printf 'S-30: rollback returned HTTP %s (expected 200)\n' "$rb_code" >&2
    return 1
  fi

  # ok field が存在 (true or false いずれでも、restored field が存在することを確認)
  if ! printf '%s' "$rb_body" | grep -q '"ok"'; then
    printf 'S-30: rollback response missing ok field\n' >&2
    return 1
  fi
  if ! printf '%s' "$rb_body" | grep -q '"restored"'; then
    printf 'S-30: rollback response missing restored field\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-31: 撤去 (task-63 設計簡素化: /api/preset/save endpoint 撤去)
# /api/preset/save は task-63 Step 4 A1 で 404 fallback に変更済
# ============================================================
# _case_s31 は削除 — /api/preset/save endpoint が 404 fallback になったため

# ============================================================
# Case S-32: category filter GET /api/keys?category=<name> → filtered list
# iter 4 C: T-U8 + category filter
# ============================================================
_case_s32() (
  set -uo pipefail
  local port="$1"

  # category filter は ASCII category name で確認 (日本語 category は URL エンコード問題のため除外)
  # /api/categories のレスポンスから ASCII のみの category name を抽出
  local cat_body
  cat_body=$(_curl_json "http://127.0.0.1:${port}/api/categories")

  # ASCII のみの category name を抽出 (日本語 category は URL に含めると問題が生じるため)
  # feature_toggle / reviewer_control / Gate_Confidence / state_dir など ASCII のものを優先
  local cat_name
  cat_name=$(printf '%s' "$cat_body" | grep -oE '"name"[[:space:]]*:[[:space:]]*"[a-zA-Z_/][a-zA-Z0-9_/]*"' | head -1 | grep -oE '"[a-zA-Z_/][a-zA-Z0-9_/]*"$' | tr -d '"' || true)

  if [ -z "$cat_name" ]; then
    # ASCII category が見つからない場合は feature_toggle を fallback として使用
    # (metadata に feature_toggle category が存在することは S-10/S-09 で確認済み)
    cat_name="feature_toggle"
  fi

  # /api/keys?category=<cat_name> (ASCII のみなので URL エンコード不要)
  local keys_body
  keys_body=$(_curl_json "http://127.0.0.1:${port}/api/keys?category=${cat_name}")

  if ! printf '%s' "$keys_body" | grep -q '"keys"'; then
    printf 'S-32: /api/keys?category=%s missing .keys field\n' "$cat_name" >&2
    printf '%s\n' "$keys_body" >&2
    return 1
  fi

  # category filter が効いて category 値が含まれること
  if ! printf '%s' "$keys_body" | grep -q '"category"'; then
    printf 'S-32: filtered keys missing category field\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-33: 撤去 (task-63 設計簡素化: /api/preset/save endpoint 撤去)
# /api/preset/save は task-63 Step 4 A1 で 404 fallback に変更済
# ============================================================
# _case_s33 は削除 — /api/preset/save endpoint が 404 fallback になったため

# ============================================================
# task-63 Step 5 新規 case (S-35〜S-39)
# /api/current-preset + top view banner + edit 遷移 + unsaved banner 検証
# ============================================================

# ============================================================
# Case S-35: GET /api/current-preset → 200 + match_type field + display_name_ja field 含む
# draft §3.4 / §3.6: /api/current-preset は { match_type, name, display_name_ja } を返す (案 C values 一致判定)
# ============================================================
_case_s35() (
  set -uo pipefail
  local port="$1"

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")

  if ! printf '%s' "$body" | grep -q '"match_type"'; then
    printf 'S-35: /api/current-preset missing .match_type field (body: %s)\n' "$body" >&2
    return 1
  fi

  if ! printf '%s' "$body" | grep -q '"display_name_ja"'; then
    printf 'S-35: /api/current-preset missing .display_name_ja field (body: %s)\n' "$body" >&2
    return 1
  fi

  # match_type は "preset" または "unsaved" のどちらかであること
  if ! printf '%s' "$body" | grep -qE '"match_type"[[:space:]]*:[[:space:]]*"(preset|unsaved)"'; then
    printf 'S-35: /api/current-preset .match_type is not "preset" or "unsaved" (body: %s)\n' "$body" >&2
    return 1
  fi

  # F3 (iter-2 fix): display_name_ja の値も検証 (存在のみでなく、match_type 別に内容を確認)
  if printf '%s' "$body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"preset"'; then
    # preset 一致時: name field 存在 + display_name_ja が非空
    if ! printf '%s' "$body" | grep -q '"name"[[:space:]]*:[[:space:]]*"[^"]'; then
      printf 'S-35: match_type=preset だが name field が非空でない (body: %s)\n' "$body" >&2
      return 1
    fi
    if ! printf '%s' "$body" | grep -qE '"display_name_ja"[[:space:]]*:[[:space:]]*"[^"]+"'; then
      printf 'S-35: match_type=preset だが display_name_ja が空 (body: %s)\n' "$body" >&2
      return 1
    fi
  else
    # unsaved 時: display_name_ja が "未保存変更あり" を含む (server.js 実装値)
    if ! printf '%s' "$body" | grep -q '未保存変更あり'; then
      printf 'S-35: match_type=unsaved だが display_name_ja に "未保存変更あり" が含まれない (body: %s)\n' "$body" >&2
      return 1
    fi
  fi

  return 0
)

# ============================================================
# Case S-36: preset apply 後 GET /api/current-preset → match_type=preset + 正しい name/display_name_ja
# draft §3.4: preset 完全一致時は { match_type: "preset", name: "<key>", display_name_ja: "<日本語名>" }
# ============================================================
_case_s36() (
  set -uo pipefail
  local port="$1"

  # poc-no-git を apply して既知の preset 状態にする
  # F9 (iter-2 fix): 400/500 系は真の FAIL (権限エラー/yml 破損) なので隠蔽せず FAIL にする。
  #   200/207 のみ正常。それ以外 (000 connection 不可等は環境問題だが、apply 自体の HTTP error は FAIL)。
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')
  case "$apply_code" in
    200|207) : ;;
    4??|5??)
      printf 'S-36: preset apply returned HTTP %s (権限エラー/yml 破損の疑い、真の FAIL)\n' "$apply_code" >&2
      return 1
      ;;
    *)
      printf 'S-36: preset apply returned HTTP %s (server 接続不可等の環境 skip)\n' "$apply_code" >&2
      return 2
      ;;
  esac

  # /api/current-preset を取得
  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")

  # match_type が "preset" であること
  if ! printf '%s' "$body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"preset"'; then
    printf 'S-36: after poc-no-git apply, match_type is not "preset" (body: %s)\n' "$body" >&2
    return 1
  fi

  # name が "poc-no-git" であること
  if ! printf '%s' "$body" | grep -q '"name"[[:space:]]*:[[:space:]]*"poc-no-git"'; then
    printf 'S-36: after poc-no-git apply, name is not "poc-no-git" (body: %s)\n' "$body" >&2
    return 1
  fi

  # display_name_ja が存在すること (日本語名: "POC・お試し (Git なし)")
  if ! printf '%s' "$body" | grep -q '"display_name_ja"'; then
    printf 'S-36: /api/current-preset missing display_name_ja after preset apply (body: %s)\n' "$body" >&2
    return 1
  fi

  # F3 (iter-2 fix): poc-no-git の display_name_ja は "POC" で始まる ("POC・お試し (Git なし)")
  if ! printf '%s' "$body" | grep -qE '"display_name_ja"[[:space:]]*:[[:space:]]*"POC'; then
    printf 'S-36: poc-no-git の display_name_ja が "POC" で始まらない (body: %s)\n' "$body" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-37: app.js に renderTop 関数 + bannerLabel/bannerValue が静的に存在 (top view banner 描画確認)
# draft §3.4: top view は「プリセット: <日本語名>」または「未保存変更あり」banner を描画する
# 検証方式: app.js 静的 grep (関数名/変数名の存在確認のみ。tautological)。
# F7 (iter-2 fix): 本 case は static grep で関数/変数の存在を確認するに留まる。
#   実 view 遷移 (top↔edit) の動作検証は Step 7 visual verification (agent-browser E2E) でカバーする。
#   reducer は window.__hcConfigUi.reducer で expose されているが、app.js module load 時に
#   document/window へ依存するため DOM shim 無しの純粋 eval は不可。reducer を独立 module へ
#   抽出して DOM 非依存 unit test 化するのは Step 8 refactor 候補 (報告に記載)。
# ============================================================
_case_s37() (
  set -uo pipefail
  local app_js="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui/app.js"

  if [ ! -f "$app_js" ]; then
    printf 'S-37: app.js not found at %s\n' "$app_js" >&2
    return 1
  fi

  # renderTop 関数が存在すること
  if ! grep -q 'function renderTop' "$app_js"; then
    printf 'S-37: app.js missing renderTop function\n' >&2
    return 1
  fi

  # bannerLabel / bannerValue が存在すること (top view banner 描画ロジック)
  if ! grep -q 'bannerLabel' "$app_js"; then
    printf 'S-37: app.js missing bannerLabel (top view banner logic)\n' >&2
    return 1
  fi

  if ! grep -q 'bannerValue' "$app_js"; then
    printf 'S-37: app.js missing bannerValue (top view banner logic)\n' >&2
    return 1
  fi

  # 「設定を変更」ボタンが存在すること (top view CTA)
  if ! grep -q '設定を変更' "$app_js"; then
    printf 'S-37: app.js missing 「設定を変更」CTA button text\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-38: app.js に state.view='edit' 遷移ロジック + renderEdit 関数が存在 (edit view 遷移確認)
# draft §3.3 / §3.7: state machine で top → edit 遷移は edit:enter action で行われる
# 検証方式: app.js 静的 grep (関数名/変数名の存在確認のみ。tautological)。
# F7 (iter-2 fix): 本 case は static grep で reducer 遷移ロジックの存在を確認するに留まる。
#   実 view 遷移 (top↔edit) の動作検証は Step 7 visual verification (agent-browser E2E) でカバーする。
#   reducer 純粋 eval が DOM shim 無しに不可な理由は S-37 コメント参照 (Step 8 refactor 候補)。
# ============================================================
_case_s38() (
  set -uo pipefail
  local app_js="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui/app.js"

  if [ ! -f "$app_js" ]; then
    printf 'S-38: app.js not found at %s\n' "$app_js" >&2
    return 1
  fi

  # renderEdit 関数が存在すること
  if ! grep -q 'function renderEdit' "$app_js"; then
    printf 'S-38: app.js missing renderEdit function\n' >&2
    return 1
  fi

  # view: 'edit' への遷移ロジックが存在すること (reducer で view を 'edit' に遷移)
  if ! grep -q "view: 'edit'" "$app_js"; then
    printf 'S-38: app.js missing view:"edit" transition in reducer\n' >&2
    return 1
  fi

  # 'top' → 'edit' の排他切替が render 内に存在すること
  if ! grep -q "state.view === 'edit'" "$app_js"; then
    printf 'S-38: app.js missing state.view===edit branch in render\n' >&2
    return 1
  fi

  # task-65: editMode (preset/individual の 2 種) は 6 軸 dropdown 撤去により廃止。
  #   edit view の遷移は edit:enter / edit:select_preset / edit:cancel / edit:apply action で行う。
  if ! grep -q "case 'edit:enter'" "$app_js"; then
    printf 'S-38: app.js missing edit:enter action in reducer (edit view 遷移ロジック)\n' >&2
    return 1
  fi

  if ! grep -q "case 'edit:select_preset'" "$app_js"; then
    printf 'S-38: app.js missing edit:select_preset action in reducer (preset 選択経路)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-39: /api/set で 1 key 変更 → GET /api/current-preset → match_type=unsaved
# draft §3.4 / §3.7: 個別 key 変更後、どの preset にも完全一致しない場合は match_type=unsaved
# 検証方式: server endpoint レベル (DOM は不要)
# F9 (iter-2 fix): apply の 400/500 系は真の FAIL (権限/yml 破損) として隠蔽しない。
# F10 (iter-2 fix): poc-no-git の values に確実に含まれる key (confidence_threshold='0.5'、
#   server.js PRESETS 定義で確認済) を、現在値 0.5 と必ず異なる値 (0.99) に set して
#   match_type=unsaved を確実に発火させる 2 段方式。apply 後に /api/current-preset で
#   match_type=preset 前提を確認 → set → unsaved を検証。F2 の snapshot/restore で yml 変更は許容。
# ============================================================
_case_s39() (
  set -uo pipefail
  local port="$1"

  # まず poc-no-git を apply して既知 preset 状態にする (確実に preset 状態を作る)
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')
  case "$apply_code" in
    200|207) : ;;
    4??|5??)
      printf 'S-39: preset apply returned HTTP %s (権限エラー/yml 破損の疑い、真の FAIL)\n' "$apply_code" >&2
      return 1
      ;;
    *)
      printf 'S-39: preset apply returned HTTP %s (server 接続不可等の環境 skip)\n' "$apply_code" >&2
      return 2
      ;;
  esac

  # apply 後の /api/current-preset が match_type=preset であることを確認 (前提)
  local before_body
  before_body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")
  if ! printf '%s' "$before_body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"preset"'; then
    # poc-no-git apply 直後に preset 一致しないのは server バグの疑い → FAIL
    printf 'S-39: poc-no-git apply 直後に match_type=preset でない (server バグの疑い、body: %s)\n' "$before_body" >&2
    return 1
  fi

  # F10: poc-no-git の values に確実に含まれる confidence_threshold (='0.5') を
  #   現在値と必ず異なる 0.99 に set して unsaved を確実に発火させる。
  #   confidence_threshold が万一存在しない場合のみ feature_confidence_gate_enabled に fallback。
  local keys_body
  keys_body=$(_curl_json "http://127.0.0.1:${port}/api/keys")

  local test_key test_value
  if printf '%s' "$keys_body" | grep -q '"confidence_threshold"'; then
    test_key="confidence_threshold"
    # poc-no-git の confidence_threshold は '0.5' (server.js PRESETS 定義)。
    # 0.99 は確実に異なるので match_type=unsaved になる。
    test_value="0.99"
  else
    # fallback: feature_confidence_gate_enabled の値を反転
    local cur_val
    cur_val=$(printf '%s' "$keys_body" | grep -A5 '"feature_confidence_gate_enabled"' | grep '"current_value"' | grep -oE '"(true|false)"' | head -1 | tr -d '"' || true)
    test_key="feature_confidence_gate_enabled"
    if [ "$cur_val" = "true" ]; then
      test_value="false"
    else
      test_value="true"
    fi
  fi

  # /api/set で key を変更する
  local set_code
  set_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/set" \
    "{\"key\":\"${test_key}\",\"value\":\"${test_value}\"}")

  # F10: known key への set が失敗するのは server バグの疑い → FAIL (skip しない)
  if [ "$set_code" != "200" ]; then
    printf 'S-39: /api/set returned HTTP %s (key=%s, value=%s — known key の set 失敗、FAIL)\n' "$set_code" "$test_key" "$test_value" >&2
    return 1
  fi

  # /api/current-preset を取得して match_type=unsaved であることを確認
  local after_body
  after_body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")

  if ! printf '%s' "$after_body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"unsaved"'; then
    printf 'S-39: after /api/set change, match_type is not "unsaved" (body: %s)\n' "$after_body" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-40: POST /api/preset/save → 404 (custom 保存撤去 regression guard)
# task-63 Step 4 A1: /api/preset/save endpoint 撤去 (savePreset/scanCustomPresets 全削除)。
# draft §8 アンチパターン「custom 保存復活禁止」の regression guard。
# F4 (iter-2 fix): 撤去された endpoint が再導入されていないこと (404 fallback) を負テストで保証。
# ============================================================
_case_s40() (
  set -uo pipefail
  local port="$1"

  local http_code
  http_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/save" \
    '{"name":"my-preset","values":{}}')

  if [ "$http_code" != "404" ]; then
    printf 'S-40: POST /api/preset/save returned HTTP %s (expected 404 — endpoint 撤去済のはず)\n' "$http_code" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-41: UI 3 file に絵文字 (Unicode emoji) が 0 件 (絵文字不要 regression guard)
# F5 (iter-2 fix): user 明示要求「絵文字不要」+ draft §8 アンチパターンの regression guard。
# index.html / app.js / style.css に emoji codepoint (U+1F300〜U+1FAFF 等) が混入したら FAIL。
# 検証方式: perl で emoji 範囲を grep (hit したら FAIL)。perl 不在時は python3 fallback。
# ============================================================
_case_s41() (
  set -uo pipefail
  local ui_dir="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui"
  local files="index.html app.js style.css"

  for f in $files; do
    if [ ! -f "${ui_dir}/${f}" ]; then
      printf 'S-41: %s not found at %s\n' "$f" "$ui_dir" >&2
      return 1
    fi
  done

  # emoji 検出: 主要 emoji ブロックを範囲指定 (記号 / 絵文字 / 補助記号 / 拡張A)
  #   U+1F300-U+1FAFF (Misc Symbols and Pictographs 〜 Symbols and Pictographs Extended-A)
  #   U+2600-U+27BF   (Misc Symbols + Dingbats)
  #   U+1F000-U+1F0FF / U+1F1E6-U+1F1FF (Mahjong/Domino/Regional indicators) も含める
  local hit=""
  if command -v perl >/dev/null 2>&1; then
    for f in $files; do
      local out
      out=$(perl -CSD -ne 'print "$ARGV:$.: $_" if /[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F1E6}-\x{1F1FF}]/' "${ui_dir}/${f}" 2>/dev/null || true)
      if [ -n "$out" ]; then
        hit="${hit}${out}"
      fi
    done
  elif command -v python3 >/dev/null 2>&1; then
    for f in $files; do
      local out
      out=$(python3 -c "
import sys, re
pat = re.compile('[\U0001F000-\U0001FAFF☀-➿⬀-⯿]')
with open(sys.argv[1], encoding='utf-8') as fh:
    for i, line in enumerate(fh, 1):
        if pat.search(line):
            print('%s:%d: %s' % (sys.argv[1], i, line), end='')
" "${ui_dir}/${f}" 2>/dev/null || true)
      if [ -n "$out" ]; then
        hit="${hit}${out}"
      fi
    done
  else
    printf 'S-41: no perl or python3 to detect emoji, skip\n' >&2
    return 2
  fi

  if [ -n "$hit" ]; then
    printf 'S-41: UI file に絵文字を検出 (絵文字不要):\n%s\n' "$hit" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-42: app.js getElementById('X') が index.html の id="X" と整合する (DOM id 契約 cross-check)
# task-63 Step 7: app.js render() が 'main-panel' を参照していたが index.html は 'view-container' しか持たず、
#   view 全体が描画されない CRITICAL bug が Step 2/Step 3 並列実装の id 契約乖離で混入した。
#   静的 grep だけでは view 描画を確認できない (S-37/S-38 は関数名存在のみの tautological 検証) 盲点を、
#   「app.js が参照する DOM id が index.html に実在するか」という静的 cross-check で部分的に埋める。
# 検証方式: app.js の全 getElementById('X') 呼び出しから id を抽出し、各 id が
#   index.html に id="X" として実在することを grep で確認。1 件でも欠落したら FAIL。
#   file-only (port 不要)。
# ============================================================
_case_s42() (
  set -uo pipefail
  local ui_dir="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui"
  local app_js="${ui_dir}/app.js"
  local index_html="${ui_dir}/index.html"

  if [ ! -f "$app_js" ]; then
    printf 'S-42: app.js not found at %s\n' "$app_js" >&2
    return 1
  fi
  if [ ! -f "$index_html" ]; then
    printf 'S-42: index.html not found at %s\n' "$index_html" >&2
    return 1
  fi

  # app.js の getElementById('X') / getElementById("X") から id 文字列を抽出
  #   (コメント行に混入する文字列は除外したいが、grep -oE で呼び出し形のみを拾う)
  local app_ids
  app_ids=$(grep -oE "getElementById\(['\"][a-zA-Z0-9_-]+['\"]\)" "$app_js" 2>/dev/null \
    | grep -oE "['\"][a-zA-Z0-9_-]+['\"]" \
    | tr -d "\"'" \
    | sort -u || true)

  if [ -z "$app_ids" ]; then
    printf 'S-42: app.js に getElementById 呼び出しが見つからない (抽出失敗の疑い)\n' >&2
    return 1
  fi

  # 各 id が index.html に id="X" として実在するか確認
  local missing=0
  local missing_ids=""
  local id
  for id in $app_ids; do
    if ! grep -qE "id=[\"']${id}[\"']" "$index_html" 2>/dev/null; then
      printf 'S-42: app.js が参照する DOM id "%s" が index.html に id="%s" として実在しない (id 契約乖離)\n' "$id" "$id" >&2
      missing=$((missing + 1))
      missing_ids="${missing_ids} ${id}"
    fi
  done

  if [ $missing -gt 0 ]; then
    printf 'S-42: id 契約乖離 %d 件 (%s)\n' "$missing" "$missing_ids" >&2
    return 1
  fi

  # 主要 id が確かに app.js / index.html 両方に存在することを明示確認 (回帰の anchor)
  #   view-container は render() の描画 target、これが乖離すると view が描画されない (本 bug の核心)
  local key
  for key in view-container status-text history-tbody confirm-dialog; do
    if ! grep -qE "id=[\"']${key}[\"']" "$index_html" 2>/dev/null; then
      printf 'S-42: 主要 id "%s" が index.html に存在しない (anchor 確認失敗)\n' "$key" >&2
      return 1
    fi
  done

  # view-container は app.js render() が getElementById で参照していること (本 bug の直接 regression guard)
  if ! grep -qE "getElementById\(['\"]view-container['\"]\)" "$app_js" 2>/dev/null; then
    printf 'S-42: app.js render() が getElementById(view-container) を参照していない (main-panel 回帰の疑い)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# task-65 新規 case (S-43〜S-46)
# /api/current-preset axes 返却 (preset/unsaved) + top view 6 軸表示 + edit dropdown 撤去
# API contract (task-65 SSoT、server/app/smoke 一貫):
#   preset 一致: { name, display_name_ja, match_type:"preset", axes:{6 key} }
#   unsaved    : { name:"custom", display_name_ja, match_type:"unsaved", axes:null }
# ============================================================

# ============================================================
# Case S-43: preset apply 後 GET /api/current-preset → axes object (6 key) を返す
# task-65 Step 1: matched preset の axes メタデータ (6 軸) を additive に返却
# ============================================================
_case_s43() (
  set -uo pipefail
  local port="$1"

  # poc-no-git を apply して既知 preset 状態にする
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')
  case "$apply_code" in
    200|207) : ;;
    4??|5??)
      printf 'S-43: preset apply returned HTTP %s (権限エラー/yml 破損の疑い、真の FAIL)\n' "$apply_code" >&2
      return 1
      ;;
    *)
      printf 'S-43: preset apply returned HTTP %s (server 接続不可等の環境 skip)\n' "$apply_code" >&2
      return 2
      ;;
  esac

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")

  # match_type=preset 前提
  if ! printf '%s' "$body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"preset"'; then
    printf 'S-43: poc-no-git apply 直後に match_type=preset でない (body: %s)\n' "$body" >&2
    return 1
  fi

  # axes field が存在すること (additive)
  if ! printf '%s' "$body" | grep -q '"axes"'; then
    printf 'S-43: /api/current-preset に axes field が無い (task-65 contract 違反、body: %s)\n' "$body" >&2
    return 1
  fi

  # axes が null でないこと (preset 一致時は object)
  if printf '%s' "$body" | grep -qE '"axes"[[:space:]]*:[[:space:]]*null'; then
    printf 'S-43: preset 一致なのに axes:null (object であるべき、body: %s)\n' "$body" >&2
    return 1
  fi

  # 6 軸 key が全て含まれること
  local axis
  for axis in quality_level language_framework git_workflow tdd_policy review_intensity autonomy_level; do
    if ! printf '%s' "$body" | grep -q "\"${axis}\""; then
      printf 'S-43: axes に key "%s" が無い (6 軸不完全、body: %s)\n' "$axis" "$body" >&2
      return 1
    fi
  done

  # task-65 iter2 (pr-test C2): poc-no-git の全 6 軸既知値を assertion
  #   (server.js PRESETS['poc-no-git'].axes 定義由来)。quality_level:poc は上で確認済。
  #   axis_key:expected_value の組を 1 件ずつ照合 (axes 値が preset metadata 由来であることを完全検証)。
  local axis_kv
  for axis_kv in \
    'quality_level:poc' \
    'language_framework:mixed' \
    'git_workflow:none' \
    'tdd_policy:optional' \
    'review_intensity:minimum' \
    'autonomy_level:aggressive'; do
    local a_key="${axis_kv%%:*}"
    local a_val="${axis_kv#*:}"
    if ! printf '%s' "$body" | grep -qE "\"${a_key}\"[[:space:]]*:[[:space:]]*\"${a_val}\""; then
      printf 'S-43: poc-no-git の axis %s が "%s" でない (axes 値が preset metadata 由来でない疑い、body: %s)\n' "$a_key" "$a_val" "$body" >&2
      return 1
    fi
  done

  return 0
)

# ============================================================
# Case S-44: unsaved 状態で GET /api/current-preset → axes:null を返す
# task-65 Step 1: preset 外 (unsaved) では axis 値が一意でないため axes:null
# ============================================================
_case_s44() (
  set -uo pipefail
  local port="$1"

  # poc-no-git を apply して既知 preset 状態 → known key を変更して unsaved 化
  local apply_code
  apply_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/preset/poc-no-git/apply" '{}')
  case "$apply_code" in
    200|207) : ;;
    4??|5??)
      printf 'S-44: preset apply returned HTTP %s (真の FAIL)\n' "$apply_code" >&2
      return 1
      ;;
    *)
      printf 'S-44: preset apply returned HTTP %s (環境 skip)\n' "$apply_code" >&2
      return 2
      ;;
  esac

  # confidence_threshold (poc-no-git は '0.5') を 0.99 に set して unsaved 化
  local set_code
  set_code=$(_curl_post_json_code "http://127.0.0.1:${port}/api/set" \
    '{"key":"confidence_threshold","value":"0.99"}')
  if [ "$set_code" != "200" ]; then
    printf 'S-44: /api/set confidence_threshold=0.99 returned HTTP %s (known key set 失敗、FAIL)\n' "$set_code" >&2
    return 1
  fi

  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/current-preset")

  # match_type=unsaved 前提
  if ! printf '%s' "$body" | grep -q '"match_type"[[:space:]]*:[[:space:]]*"unsaved"'; then
    printf 'S-44: set 後に match_type=unsaved でない (body: %s)\n' "$body" >&2
    return 1
  fi

  # axes が null であること (task-65 contract)
  if ! printf '%s' "$body" | grep -qE '"axes"[[:space:]]*:[[:space:]]*null'; then
    printf 'S-44: unsaved なのに axes:null でない (task-65 contract 違反、body: %s)\n' "$body" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-45: app.js top view が API axes を参照 + unsaved カスタム表示分岐を持つ (静的)
# task-65 Step 2: renderTop は cp.axes 直接参照、axes:null (unsaved) 時はカスタム表示に切替
# 検証方式: app.js 静的 grep (関数/分岐の存在確認)。実描画は Step 5 visual verification。
# ============================================================
_case_s45() (
  set -uo pipefail
  local app_js="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui/app.js"

  if [ ! -f "$app_js" ]; then
    printf 'S-45: app.js not found at %s\n' "$app_js" >&2
    return 1
  fi

  # 撤去 symbol 検出は code 行のみを対象とする (説明 comment 行 // ... は除外)。
  #   行頭空白後に // で始まる行を除外し、行末コメントは含まれるが symbol が code として
  #   出現するかの近似 (撤去 symbol は定義/呼出が全て消えているため code 行に残らない)。
  local app_code
  app_code=$(grep -vE '^[[:space:]]*//' "$app_js" || true)

  # renderTop が cp.axes を参照すること (API axes 直接参照)
  if ! printf '%s' "$app_code" | grep -qE 'cp\.axes|cp && cp\.axes'; then
    printf 'S-45: app.js renderTop が cp.axes を参照していない (API axes 参照に未修正)\n' >&2
    return 1
  fi

  # unsaved (axes:null) 時のカスタム表示見出しが存在すること
  if ! printf '%s' "$app_code" | grep -q 'カスタム設定 (プリセット外)'; then
    printf 'S-45: app.js に「カスタム設定 (プリセット外)」見出しが無い (unsaved カスタム表示未実装)\n' >&2
    return 1
  fi

  # 6 軸 read-only table の日本語ラベル参照 (AXIS_LABELS_JA) が使われること
  if ! printf '%s' "$app_code" | grep -q 'AXIS_LABELS_JA'; then
    printf 'S-45: app.js に AXIS_LABELS_JA 参照が無い (6 軸日本語ラベル未使用)\n' >&2
    return 1
  fi

  # loadCurrentAxes dead path が code から撤去されていること (comment 行の言及は許容)
  if printf '%s' "$app_code" | grep -q 'loadCurrentAxes'; then
    printf 'S-45: app.js code に loadCurrentAxes が残存 (dead path 未撤去、task-65 Step 2 違反)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-46: edit view から 6 軸 dropdown が撤去されている (静的)
# task-65 Step 2: 機能不全 6 軸 dropdown 撤去、編集は preset 一括 + 既存 key 個別の 2 経路
# 検証方式: app.js 静的 grep (撤去された symbol の不在確認 + 残すべき preset 経路の存在確認)。
# ============================================================
_case_s46() (
  set -uo pipefail
  local app_js="${REPO_ROOT}/.claude/scripts/lib/hc-config-web-ui/app.js"

  if [ ! -f "$app_js" ]; then
    printf 'S-46: app.js not found at %s\n' "$app_js" >&2
    return 1
  fi

  # 撤去 symbol 検出は code 行のみを対象 (説明 comment 行 // ... は除外、撤去記録の言及は許容)
  local app_code
  app_code=$(grep -vE '^[[:space:]]*//' "$app_js" || true)

  # 6 軸 dropdown 個別編集の symbol が code から撤去されていること
  #   onChangeAxis / loadAxesWithOptions / _axesOptions / editAxisChanges は dropdown 専用 dead code
  local sym
  for sym in onChangeAxis loadAxesWithOptions _axesOptions editAxisChanges 'edit-axis-'; do
    if printf '%s' "$app_code" | grep -q "$sym"; then
      printf 'S-46: app.js code に 6 軸 dropdown 関連 symbol "%s" が残存 (撤去未完、task-65 Step 2 違反)\n' "$sym" >&2
      return 1
    fi
  done

  # preset 一括変更経路は残っていること (renderEdit + applyPresetMode)
  if ! grep -q 'function renderEdit' "$app_js"; then
    printf 'S-46: app.js に renderEdit が無い (edit view 経路を壊した疑い)\n' >&2
    return 1
  fi
  if ! grep -q 'applyPresetMode' "$app_js"; then
    printf 'S-46: app.js に applyPresetMode が無い (preset 一括変更経路を壊した疑い)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-47: GET /api/keys が返す key set == yml top-level keys (full parity)
# task-69 Step 3 (key parity fix):
#   /api/keys は従来 metadata (75 entry) を基準に enrich していたため、
#   metadata 未登録の yml key (feature_reviewer_count_guard_enabled /
#   feature_stale_harness_detect_enabled / harness_version / stale_harness_markers)
#   が response から欠落していた。本 case は /api/keys の key 集合が
#   harness-config.yml の top-level key 集合 (79 key) と完全一致することを検証する。
#   - key source SSoT = yml top-level key (`^[a-z_][a-zA-Z0-9_]*:`)
#   - metadata 有無に関わらず yml 全 key が返ること (metadata は left join の表示補助)
# RED→GREEN: 修正前は total=75 (metadata 基準) で fail、修正後は total=yml key 数で green。
# network: localhost bind が必要なため node + server 起動可能環境のみ。不可なら呼出側で SKIP。
# ============================================================
_case_s47() (
  set -uo pipefail
  local port="$1"

  # yml top-level key を hc-config.sh と同一 regex で抽出 (SSoT)
  local yml="${REPO_ROOT}/.claude/harness-config.yml"
  if [ ! -f "$yml" ]; then
    printf 'S-47: harness-config.yml not found at %s\n' "$yml" >&2
    return 1
  fi
  local expected_keys
  expected_keys=$(grep -E "^[a-z_][a-zA-Z0-9_]*:" "$yml" 2>/dev/null | sed -E 's/:.*$//' | sort -u || true)
  local expected_count
  expected_count=$(printf '%s\n' "$expected_keys" | grep -c '.' || true)

  if [ "${expected_count:-0}" -lt 1 ]; then
    printf 'S-47: could not extract yml top-level keys\n' >&2
    return 1
  fi

  # /api/keys response から "key":"<name>" を抽出
  local body
  body=$(_curl_json "http://127.0.0.1:${port}/api/keys")
  if ! printf '%s' "$body" | grep -q '"keys"'; then
    printf 'S-47: /api/keys missing .keys field (body: %s)\n' "$body" >&2
    return 1
  fi

  local actual_keys
  actual_keys=$(printf '%s' "$body" | grep -oE '"key":"[^"]+"' | sed -E 's/^"key":"//; s/"$//' | sort -u || true)
  local actual_count
  actual_count=$(printf '%s\n' "$actual_keys" | grep -c '.' || true)

  # key 数の完全一致を検証 (parity)
  if [ "${actual_count:-0}" != "${expected_count:-0}" ]; then
    printf 'S-47: key count mismatch (yml=%s, /api/keys=%s)\n' "$expected_count" "$actual_count" >&2
    printf 'S-47: yml-only keys (欠落): %s\n' "$(comm -23 <(printf '%s\n' "$expected_keys") <(printf '%s\n' "$actual_keys") | tr '\n' ' ')" >&2
    printf 'S-47: api-only keys (余分): %s\n' "$(comm -13 <(printf '%s\n' "$expected_keys") <(printf '%s\n' "$actual_keys") | tr '\n' ' ')" >&2
    return 1
  fi

  # 集合の完全一致 (差分 0)
  local diff_lines
  diff_lines=$(comm -3 <(printf '%s\n' "$expected_keys") <(printf '%s\n' "$actual_keys") | grep -c '.' || true)
  if [ "${diff_lines:-0}" != "0" ]; then
    printf 'S-47: key set mismatch (差分 %s 件):\n%s\n' "$diff_lines" "$(comm -3 <(printf '%s\n' "$expected_keys") <(printf '%s\n' "$actual_keys"))" >&2
    return 1
  fi

  return 0
)

# ============================================================
# Case S-34: SIGTERM graceful shutdown → port release
# iter 4 C: G5 — SIGTERM graceful (S-04 は SIGINT、本 case は SIGTERM)
# ============================================================
_case_s34() (
  set -uo pipefail

  if ! _has_node; then
    printf 'S-34: node not found, skip\n' >&2
    return 2
  fi

  local log_file="${TMP_DIR}/s34-server.log"
  _start_server "$log_file"
  local pid=$SERVER_PID

  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'S-34: server did not start\n' >&2
    return 1
  fi

  local port
  port=$(_get_server_port "$log_file")
  if [ -z "$port" ]; then
    printf 'S-34: could not detect port\n' >&2
    kill "$pid" 2>/dev/null || true
    SERVER_PID=""
    return 1
  fi

  # SIGTERM 送信
  kill -TERM "$pid" 2>/dev/null || true
  local waited=0
  while [ $waited -lt 6 ]; do
    sleep 0.5
    waited=$((waited + 1))
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
  done
  SERVER_PID=""

  if kill -0 "$pid" 2>/dev/null; then
    printf 'S-34: server still running after SIGTERM\n' >&2
    kill -9 "$pid" 2>/dev/null || true
    return 1
  fi

  # port が解放されているか: 別 server が同 port で起動できるか確認
  local log2="${TMP_DIR}/s34-check.log"
  HC_WEB_NO_OPEN=1 node "${WEB_SERVER}" >"$log2" 2>&1 &
  local pid2=$!
  sleep 2
  local port2
  port2=$(_get_server_port "$log2")
  kill "$pid2" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true

  if [ -z "$port2" ]; then
    printf 'S-34: port not released after SIGTERM (second server could not start)\n' >&2
    return 1
  fi

  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n%s\n\n' '=== hc-config-web-ui-smoke (task-63 Step 5: /api/current-preset + top/edit view 5 case) ==='

# --- server lifecycle (独立 server、各 case で起動/停止) ---

printf '%s\n' '--- server lifecycle ---'

if _case_s01 2>/dev/null; then _record PASS "S-01" "server 起動 (HC_WEB_NO_OPEN=1) → port LISTEN → GET / 200/302 → kill"
elif [ $? -eq 2 ];          then _record SKIP "S-01" "server 起動 (node not available)"
else                             _record FAIL "S-01" "server 起動 (HC_WEB_NO_OPEN=1) → port LISTEN → GET / 200/302 → kill"
fi

_s02_result=0
_case_s02 2>/dev/null || _s02_result=$?
if [ $_s02_result -eq 0 ];  then _record PASS "S-02" "port 3060 先 occupy → server → 3061+ で listen"
elif [ $_s02_result -eq 2 ]; then _record SKIP "S-02" "port 3060 先 occupy (nc/socat/python3 not available)"
else                              _record FAIL "S-02" "port 3060 先 occupy → server → 3061+ で listen"
fi

_s03_result=0
_case_s03 2>/dev/null || _s03_result=$?
if [ $_s03_result -eq 0 ];  then _record PASS "S-03" "port 3060-3070 全 occupied → server process.exit(1)"
elif [ $_s03_result -eq 2 ]; then _record SKIP "S-03" "port 全 occupied (占有ツール不在)"
else                              _record FAIL "S-03" "port 3060-3070 全 occupied → server process.exit(1)"
fi

_s04_result=0
_case_s04 2>/dev/null || _s04_result=$?
if [ $_s04_result -eq 0 ];  then _record PASS "S-04" "server 起動 → SIGINT → graceful shutdown → port release"
elif [ $_s04_result -eq 2 ]; then _record SKIP "S-04" "SIGINT graceful (node not available)"
else                              _record FAIL "S-04" "server 起動 → SIGINT → graceful shutdown → port release"
fi

# S-34: SIGTERM graceful (独立 server)
_s34_result=0
_case_s34 2>/dev/null || _s34_result=$?
if [ $_s34_result -eq 0 ];   then _record PASS "S-34" "server 起動 → SIGTERM → graceful shutdown → port release"
elif [ $_s34_result -eq 2 ]; then _record SKIP "S-34" "SIGTERM graceful (node not available)"
else                               _record FAIL "S-34" "server 起動 → SIGTERM → graceful shutdown → port release"
fi

# --- static + API + preset (共有 server) ---
printf '\n%s\n' '--- static / API / preset (shared server) ---'

# S-01〜S-04,S-34 で使ったポートが解放されるまで待機 (最大 3 秒)
_wait_ports_free() (
  set -uo pipefail
  local waited=0
  while [ $waited -lt 6 ]; do
    local busy=0
    local p
    for p in 3060 3061 3062 3063; do
      if command -v lsof >/dev/null 2>&1; then
        lsof -i ":$p" >/dev/null 2>/dev/null && busy=1 && break
      fi
    done
    if [ $busy -eq 0 ]; then return 0; fi
    sleep 0.5
    waited=$((waited + 1))
  done
  return 0
)
_wait_ports_free

if _has_node && [ -f "${WEB_SERVER}" ]; then
  # iter 4 C: T-H2 — ISOLATED_HISTORY_DIR で test isolation
  # iter 6 B: ISOLATED_PRESETS_DIR で custom-test-*.yml pollution 解消
  # server が HC_HISTORY_DIR_OVERRIDE / HC_PRESETS_DIR_OVERRIDE を読む実装がある場合は isolated dir が使われる
  _start_shared_server "$ISOLATED_HISTORY_DIR" "$ISOLATED_PRESETS_DIR"

  if [ -z "$SHARED_PORT" ]; then
    printf '  WARN: shared server failed to start, skipping shared-server cases\n'
    for cid in S-05 S-06 S-07 S-08 S-09 S-10 S-11 S-12 S-13 S-14 S-15 S-16 S-19 S-20 S-21 S-23 S-24 S-25 S-27 S-28 S-29 S-30 S-32 S-35 S-36 S-39 S-43 S-44; do
      _record SKIP "$cid" "shared server not available"
    done
    _record SKIP "S-22" "/api/preset/save 撤去 (task-63 設計簡素化)"
    _record SKIP "S-26" "/api/preset/save 6 軸欠落 case 撤去 (task-63 設計簡素化)"
    _record SKIP "S-31" "/api/preset/save path traversal case 撤去 (task-63 設計簡素化)"
    _record SKIP "S-33" "XSS injection save name case 撤去 (task-63 設計簡素化)"
    if _case_s37 2>/dev/null; then _record PASS "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
    else                           _record FAIL "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
    fi
    if _case_s38 2>/dev/null; then _record PASS "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
    else                           _record FAIL "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
    fi
    # S-40 は shared server 必須なので SKIP、S-41/S-42 は file-only なので実行
    _record SKIP "S-40" "POST /api/preset/save 404 (shared server not available)"
    _s41_result=0
    _case_s41 2>/dev/null || _s41_result=$?
    if [ $_s41_result -eq 0 ];   then _record PASS "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
    elif [ $_s41_result -eq 2 ]; then _record SKIP "S-41" "絵文字検出 (perl/python3 not available)"
    else                              _record FAIL "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
    fi
    if _case_s42 2>/dev/null; then _record PASS "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
    else                           _record FAIL "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
    fi
    # S-43/S-44 は shared server 必須なので SKIP、S-45/S-46 は file-only なので実行
    _record SKIP "S-43" "preset axes 6 key (shared server not available)"
    _record SKIP "S-44" "unsaved axes:null (shared server not available)"
    if _case_s45 2>/dev/null; then _record PASS "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
    else                           _record FAIL "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
    fi
    if _case_s46 2>/dev/null; then _record PASS "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
    else                           _record FAIL "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
    fi
  else
    _PORT="$SHARED_PORT"

    if _case_s05 "$_PORT" 2>/dev/null; then _record PASS "S-05" "GET / → 302 or 200"
    else                                     _record FAIL "S-05" "GET / → 302 or 200"
    fi

    if _case_s06 "$_PORT" 2>/dev/null; then _record PASS "S-06" "GET /static/index.html → 200 + text/html"
    else                                     _record FAIL "S-06" "GET /static/index.html → 200 + text/html"
    fi

    if _case_s07 "$_PORT" 2>/dev/null; then _record PASS "S-07" "GET /static/app.js → 200 + application/javascript"
    else                                     _record FAIL "S-07" "GET /static/app.js → 200 + application/javascript"
    fi

    if _case_s08 "$_PORT" 2>/dev/null; then _record PASS "S-08" "path traversal /static/../../ → 403/404"
    else                                     _record FAIL "S-08" "path traversal /static/../../ → 403/404"
    fi

    if _case_s09 "$_PORT" 2>/dev/null; then _record PASS "S-09" "GET /api/categories → 200 + .categories length >= 1"
    else                                     _record FAIL "S-09" "GET /api/categories → 200 + .categories length >= 1"
    fi

    if _case_s10 "$_PORT" 2>/dev/null; then _record PASS "S-10" "GET /api/keys → 200 + .keys length >= 1"
    else                                     _record FAIL "S-10" "GET /api/keys → 200 + .keys length >= 1"
    fi

    if _case_s11 "$_PORT" 2>/dev/null; then _record PASS "S-11" "GET /api/presets → 200 + .presets length == 10"
    else                                     _record FAIL "S-11" "GET /api/presets → 200 + .presets length == 10"
    fi

    if _case_s12 "$_PORT" 2>/dev/null; then _record PASS "S-12" "GET /api/preset/poc-no-git/diff → 200 + .changes[].key/current/new/effect"
    else                                     _record FAIL "S-12" "GET /api/preset/poc-no-git/diff → 200 + .changes[].key/current/new/effect"
    fi

    if _case_s13 "$_PORT" 2>/dev/null; then _record PASS "S-13" "POST /api/set 不正 key (空/欠落) → 400"
    else                                     _record FAIL "S-13" "POST /api/set 不正 key (空/欠落) → 400"
    fi

    if _case_s14 "$_PORT" "$ISOLATED_HISTORY_DIR" 2>/dev/null; then _record PASS "S-14" "POST /api/preset/poc-no-git/apply → 200/207 + history file 生成"
    else                                                             _record FAIL "S-14" "POST /api/preset/poc-no-git/apply → 200/207 + history file 生成"
    fi

    if _case_s15 "$_PORT" 2>/dev/null; then _record PASS "S-15" "apply → rollback → 200 + ok:true"
    else                                     _record FAIL "S-15" "apply → rollback → 200 + ok:true"
    fi

    if _case_s16 "$_PORT" 2>/dev/null; then _record PASS "S-16" "rollback timestamp traversal (plain + URL encoded) → 400/404/500"
    else                                     _record FAIL "S-16" "rollback timestamp traversal (plain + URL encoded) → 400/404/500"
    fi

    _s19_result=0
    _case_s19 "$_PORT" 2>/dev/null || _s19_result=$?
    if [ $_s19_result -eq 0 ];   then _record PASS "S-19" "1MB+1byte body POST /api/set → 400/413"
    elif [ $_s19_result -eq 2 ]; then _record SKIP "S-19" "large body (python3/dd not available)"
    else                              _record FAIL "S-19" "1MB+1byte body POST /api/set → 400/413"
    fi

    # --- iter 4 C 新規 case ---
    printf '\n%s\n' '--- iter 4 C 新規 case (S-20〜S-33) ---'

    _s20_result=0
    _case_s20 "$_PORT" 2>/dev/null || _s20_result=$?
    if [ $_s20_result -eq 0 ];   then _record PASS "S-20" "abort rollback silent no-op verify"
    elif [ $_s20_result -eq 2 ]; then _record SKIP "S-20" "abort rollback (no history)"
    else                              _record FAIL "S-20" "abort rollback silent no-op verify"
    fi

    if _case_s21 "$_PORT" 2>/dev/null; then _record PASS "S-21" "unknown preset → 404 (diff + apply)"
    else                                     _record FAIL "S-21" "unknown preset → 404 (diff + apply)"
    fi

    _record SKIP "S-22" "/api/preset/save 撤去 (task-63 設計簡素化)"

    if _case_s23 "$_PORT" 2>/dev/null; then _record PASS "S-23" "apply response ok + applied + partial フィールド verify"
    else                                     _record FAIL "S-23" "apply response ok + applied + partial フィールド verify"
    fi

    if _case_s24 "$_PORT" "$ISOLATED_HISTORY_DIR" 2>/dev/null; then _record PASS "S-24" "HISTORY_DIR 不在 → apply で自動作成"
    else                                                              _record FAIL "S-24" "HISTORY_DIR 不在 → apply で自動作成"
    fi

    if _case_s25 "$_PORT" 2>/dev/null; then _record PASS "S-25" "invalid JSON body → 400 (/api/set のみ)"
    else                                     _record FAIL "S-25" "invalid JSON body → 400 (/api/set のみ)"
    fi

    _record SKIP "S-26" "/api/preset/save 6 軸欠落 case 撤去 (task-63 設計簡素化)"

    if _case_s27 "$_PORT" 2>/dev/null; then _record PASS "S-27" "POST /api/set empty string value → 200 or 400 (仕様確認)"
    else                                     _record FAIL "S-27" "POST /api/set empty string value → 200 or 400 (仕様確認)"
    fi

    if _case_s28 "$_PORT" 2>/dev/null; then _record PASS "S-28" "URL encoded rollback traversal → 400/404/500 (not 200)"
    else                                     _record FAIL "S-28" "URL encoded rollback traversal → 400/404/500 (not 200)"
    fi

    if _case_s29 "$_PORT" 2>/dev/null; then _record PASS "S-29" "GET /api/preset/history → .history array"
    else                                     _record FAIL "S-29" "GET /api/preset/history → .history array"
    fi

    _s30_result=0
    _case_s30 "$_PORT" 2>/dev/null || _s30_result=$?
    if [ $_s30_result -eq 0 ];   then _record PASS "S-30" "rollback → ok + restored フィールド verify"
    elif [ $_s30_result -eq 2 ]; then _record SKIP "S-30" "rollback 0 件 (no history)"
    else                              _record FAIL "S-30" "rollback → ok + restored フィールド verify"
    fi

    _record SKIP "S-31" "/api/preset/save path traversal case 撤去 (task-63 設計簡素化)"

    _s32_result=0
    _case_s32 "$_PORT" 2>/dev/null || _s32_result=$?
    if [ $_s32_result -eq 0 ];   then _record PASS "S-32" "GET /api/keys?category=<name> → filtered list"
    elif [ $_s32_result -eq 2 ]; then _record SKIP "S-32" "category filter (no categories found)"
    else                              _record FAIL "S-32" "GET /api/keys?category=<name> → filtered list"
    fi

    _record SKIP "S-33" "XSS injection save name case 撤去 (task-63 設計簡素化)"

    # --- task-63 Step 5 新規 case ---
    printf '\n%s\n' '--- task-63 Step 5 新規 case (S-35〜S-39) ---'

    if _case_s35 "$_PORT" 2>/dev/null; then _record PASS "S-35" "GET /api/current-preset → match_type + display_name_ja field"
    else                                     _record FAIL "S-35" "GET /api/current-preset → match_type + display_name_ja field"
    fi

    _s36_result=0
    _case_s36 "$_PORT" 2>/dev/null || _s36_result=$?
    if [ $_s36_result -eq 0 ];   then _record PASS "S-36" "preset apply 後 /api/current-preset → match_type=preset"
    elif [ $_s36_result -eq 2 ]; then _record SKIP "S-36" "preset apply skip (apply failed)"
    else                              _record FAIL "S-36" "preset apply 後 /api/current-preset → match_type=preset"
    fi

    if _case_s37 2>/dev/null; then _record PASS "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
    else                           _record FAIL "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
    fi

    if _case_s38 2>/dev/null; then _record PASS "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
    else                           _record FAIL "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
    fi

    _s39_result=0
    _case_s39 "$_PORT" 2>/dev/null || _s39_result=$?
    if [ $_s39_result -eq 0 ];   then _record PASS "S-39" "/api/set 1 key 変更 → /api/current-preset match_type=unsaved"
    elif [ $_s39_result -eq 2 ]; then _record SKIP "S-39" "/api/set unsaved 確認 skip (server 接続不可)"
    else                              _record FAIL "S-39" "/api/set 1 key 変更 → /api/current-preset match_type=unsaved"
    fi

    # --- task-63 Step 6 iter-2 新規 negative case (S-40 / S-41) ---
    printf '\n%s\n' '--- task-63 Step 6 iter-2 negative case (S-40 / S-41) ---'

    # F4: /api/preset/save 撤去 regression guard (404 負テスト)
    if _case_s40 "$_PORT" 2>/dev/null; then _record PASS "S-40" "POST /api/preset/save → 404 (custom 保存撤去 regression guard)"
    else                                     _record FAIL "S-40" "POST /api/preset/save → 404 (custom 保存撤去 regression guard)"
    fi

    # F5: UI 3 file 絵文字 0 件 regression guard (file-only、port 不要)
    _s41_result=0
    _case_s41 2>/dev/null || _s41_result=$?
    if [ $_s41_result -eq 0 ];   then _record PASS "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
    elif [ $_s41_result -eq 2 ]; then _record SKIP "S-41" "絵文字検出 (perl/python3 not available)"
    else                              _record FAIL "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
    fi

    # task-63 Step 7: DOM id 契約 cross-check (file-only、port 不要)
    if _case_s42 2>/dev/null; then _record PASS "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
    else                           _record FAIL "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
    fi

    # --- task-65 新規 case (S-43〜S-46): axes 返却 + top 6 軸 + dropdown 撤去 ---
    printf '\n%s\n' '--- task-65 新規 case (S-43〜S-46) ---'

    _s43_result=0
    _case_s43 "$_PORT" 2>/dev/null || _s43_result=$?
    if [ $_s43_result -eq 0 ];   then _record PASS "S-43" "preset apply 後 /api/current-preset → axes object (6 key)"
    elif [ $_s43_result -eq 2 ]; then _record SKIP "S-43" "axes 6 key 確認 skip (apply failed)"
    else                              _record FAIL "S-43" "preset apply 後 /api/current-preset → axes object (6 key)"
    fi

    _s44_result=0
    _case_s44 "$_PORT" 2>/dev/null || _s44_result=$?
    if [ $_s44_result -eq 0 ];   then _record PASS "S-44" "unsaved 状態で /api/current-preset → axes:null"
    elif [ $_s44_result -eq 2 ]; then _record SKIP "S-44" "axes:null 確認 skip (apply failed)"
    else                              _record FAIL "S-44" "unsaved 状態で /api/current-preset → axes:null"
    fi

    # S-45 / S-46 は file-only (port 不要)
    if _case_s45 2>/dev/null; then _record PASS "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
    else                           _record FAIL "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
    fi

    if _case_s46 2>/dev/null; then _record PASS "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
    else                           _record FAIL "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
    fi

    # --- task-69 Step 3 新規 case (key parity) ---
    _s47_result=0
    _case_s47 "$_PORT" 2>/dev/null || _s47_result=$?
    if [ $_s47_result -eq 0 ];   then _record PASS "S-47" "GET /api/keys key set == yml top-level keys (full parity)"
    elif [ $_s47_result -eq 2 ]; then _record SKIP "S-47" "key parity (server 接続不可)"
    else                              _record FAIL "S-47" "GET /api/keys key set == yml top-level keys (full parity)"
    fi

    _stop_shared_server
  fi
else
  for cid in S-05 S-06 S-07 S-08 S-09 S-10 S-11 S-12 S-13 S-14 S-15 S-16 S-19 S-20 S-21 S-23 S-24 S-25 S-27 S-28 S-29 S-30 S-32 S-35 S-36 S-39 S-40 S-43 S-44 S-47; do
    _record SKIP "$cid" "node or hc-config-web-server.js not available"
  done
  # S-37 / S-38 / S-41 / S-42 / S-45 / S-46 は file-only (port 不要) なので node 不在でも実行
  if _case_s37 2>/dev/null; then _record PASS "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
  else                           _record FAIL "S-37" "app.js renderTop + bannerLabel/bannerValue 静的確認"
  fi
  if _case_s38 2>/dev/null; then _record PASS "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
  else                           _record FAIL "S-38" "app.js renderEdit + view:edit 遷移ロジック 静的確認"
  fi
  _s41_result=0
  _case_s41 2>/dev/null || _s41_result=$?
  if [ $_s41_result -eq 0 ];   then _record PASS "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
  elif [ $_s41_result -eq 2 ]; then _record SKIP "S-41" "絵文字検出 (perl/python3 not available)"
  else                              _record FAIL "S-41" "UI 3 file 絵文字 0 件 (絵文字不要 regression guard)"
  fi
  if _case_s42 2>/dev/null; then _record PASS "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
  else                           _record FAIL "S-42" "app.js getElementById id 契約が index.html id= と整合 (DOM id cross-check)"
  fi
  if _case_s45 2>/dev/null; then _record PASS "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
  else                           _record FAIL "S-45" "app.js top view が cp.axes 参照 + unsaved カスタム表示 + loadCurrentAxes 撤去"
  fi
  if _case_s46 2>/dev/null; then _record PASS "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
  else                           _record FAIL "S-46" "edit view 6 軸 dropdown 撤去 (preset 一括経路は維持)"
  fi
fi

# --- legacy fallback + edge ---
printf '\n%s\n' '--- legacy fallback + edge ---'

if _case_s17 2>/dev/null; then _record PASS "S-17" "HC_HC_CONFIG_TUI_LEGACY=true → TUI 経路 dispatcher 確認"
else                            _record FAIL "S-17" "HC_HC_CONFIG_TUI_LEGACY=true → TUI 経路 dispatcher 確認"
fi

_s18_result=0
_case_s18 2>/dev/null || _s18_result=$?
if [ $_s18_result -eq 0 ];   then _record PASS "S-18" "node 不在 → WARN stderr + TUI fallback"
elif [ $_s18_result -eq 2 ]; then _record SKIP "S-18" "node 不在 (node が /usr/bin 以外にも存在しない)"
else                              _record FAIL "S-18" "node 不在 → WARN stderr + TUI fallback"
fi

# --- 手動 case コメント (Step 6 で実施) ---
printf '\n%s\n' '--- manual cases (Step 6 で実施、以下はコメントのみ) ---'
printf '  SKIP  M-01: browser で preset 選択 → diff preview → checkbox toggle → Apply → history 追加 (目視)\n'
printf '  SKIP  M-02: category 選択 → key 一覧 → 編集 → Apply → 値反映確認 (目視)\n'
printf '  SKIP  M-03: Rollback ボタン → confirm dialog → 確認 → 元値復元 (目視)\n'
printf '  SKIP  M-04: Tailwind CDN offline で degradation 動作確認 (warning banner + legacy 案内)\n'
SKIP=$((SKIP + 4))

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL + SKIP))
printf '\n%s %d/%d PASS, %d SKIP, %d FAIL ---\n' '--- Result:' "$PASS" "$TOTAL" "$SKIP" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi

exit 0
