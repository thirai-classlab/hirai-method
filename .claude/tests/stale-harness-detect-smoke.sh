#!/usr/bin/env bash
# stale-harness-detect-smoke.sh — task-56 F + task-84 (stale-harness-detect)
#
# Cases:
#   1: marker 全在 + harness_version 正常 (今日)        → silent (exit 0, stdout/stderr 0 byte)
#   2: marker 欠落 (CommonRules.md 不在)                → WARN 発火 (<system-reminder> + 'stale harness')
#   3: harness_version stamp 異常 (非 YYYY-MM-DD)       → UNKNOWN 表示 + WARN
#   4: 未来日付 (>= 翌日)                                 → 別 WARN「stamp 異常 (future)」
#   5: 同一 session 2 回目実行                          → 重複抑制 (silent)
#   6: feature OFF (HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false) → no-op silent
#  --- task-84 registry 比較シナリオ (Cases 11-15) ---
#  11: stamp 古 + registry 新 (local http server)      → WARN「新版」「npx」「update」
#      + assert: system-reminder / block しません / 9.9.9 / 0.0.1 の 4 点
#  12: stamp == registry                               → silent
#  13: registry 取得失敗 (不正 base)                     → fail-open silent + exit 0
#  14: throttle — 2 回目は registry 取得せず skip        → silent
#  15: feature OFF → no-op exit 0
#   7: config 不在 (HC_CONFIG_PATH を bogus path)        → silent fail-open (exit 0)
#   8: marker list 未設定 (yml に stale_harness_markers 空) → silent fail-open
#   9: harness_version key 欠落 (yml に key 自体無し) + marker 全在 → WARN 「stamp 未設定」
#  --- task-84 追加 gap カバレッジ (Cases 16-19) ---
#  16: Gap-A throttle 境界 — last-check mtime が interval ちょうど前 → registry 取得走る
#  17: Gap-B fallback 経路 — cli_path 不在 (node fallback) → 同一 WARN 結果
#  18: Gap-C harness_npm_version 行不在 → fail-open silent (version 比較 skip)
#  19: Gap-D 不正 semver stamp (not-a-version) → fail-open silent
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lesson HIGH 遵守)
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップ
#   - 各 case は tmp dir を per-case 隔離して順序依存を排除
#
# 実行:
#   bash .claude/tests/stale-harness-detect-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$PROJECT_ROOT/.claude/hooks/stale-harness-detect.sh"

if [ ! -f "$HOOK" ]; then
    printf 'ERROR: hook not found: %s\n' "$HOOK" >&2
    exit 1
fi

TMP_BASE="$(mktemp -d /tmp/stale-harness-detect-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

_root_for() {
    local case_id="$1"
    printf '%s/root-%s' "$TMP_BASE" "$case_id"
}

run_case() {
    local case_id="$1"
    local desc="$2"
    local test_fn="$3"
    if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
        printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
        PASS=$((PASS+1))
    else
        printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
        FAIL=$((FAIL+1))
        FAILED_CASES+=("$case_id")
    fi
}

# ---- fixture builders ----

# layout_full <root> <harness_version> [marker_list_or_empty]
#   .claude/CommonRules.md + scripts/hc-config.sh + lib/hc-config-metadata.sh
#   + hooks/loop-confirmation-detector.sh + harness-config.yml 全在
#   harness_version stamp を yml に書き込み
_layout_full() {
    local root="$1"
    local hv="$2"
    local markers_line="${3:-stale_harness_markers: [CommonRules.md, scripts/hc-config.sh, hooks/lib/config-loader.sh, hooks/loop-confirmation-detector.sh]}"

    mkdir -p \
        "$root/.claude" \
        "$root/.claude/scripts" \
        "$root/.claude/hooks" \
        "$root/.claude/hooks/lib"

    : > "$root/.claude/CommonRules.md"
    : > "$root/.claude/scripts/hc-config.sh"
    : > "$root/.claude/hooks/lib/config-loader.sh"
    : > "$root/.claude/hooks/loop-confirmation-detector.sh"

    cat > "$root/.claude/harness-config.yml" <<EOF
# test fixture
harness_version: "${hv}"
${markers_line}
feature_stale_harness_detect_enabled: true
EOF
}

_state_dir_for() {
    local root="$1"
    printf '%s/.claude/.stale-harness-state' "$root"
}

# Today / future date helpers (BSD/GNU compat)
_today() {
    date -u +%Y-%m-%d
}
_future() {
    # +1 day
    if date -v +1d +%Y-%m-%d >/dev/null 2>&1; then
        date -u -v +1d +%Y-%m-%d
    else
        date -u -d "+1 day" +%Y-%m-%d
    fi
}

# === Case 1: marker 全在 + version 正常 → silent ===
case_1_silent_when_healthy() {
    local root
    root=$(_root_for 1)
    _layout_full "$root" "$(_today)"

    local out err
    out=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>/tmp/case1-err
    )
    err=$(cat /tmp/case1-err)
    rm -f /tmp/case1-err

    if [ -n "$out" ]; then
        printf 'expected stdout empty, got:\n%s\n' "$out" >&2
        return 1
    fi
    if [ -n "$err" ]; then
        printf 'expected stderr empty (healthy harness), got:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 2: marker 欠落 (CommonRules.md 不在) → WARN ===
case_2_warn_on_missing_marker() {
    local root
    root=$(_root_for 2)
    _layout_full "$root" "$(_today)"
    rm -f "$root/.claude/CommonRules.md"

    local err
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err" ]; then
        printf 'expected stderr WARN, got empty\n' >&2
        return 1
    fi
    if ! printf '%s' "$err" | grep -q 'system-reminder'; then
        printf 'missing system-reminder tag. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    if ! printf '%s' "$err" | grep -q 'stale harness'; then
        printf 'missing "stale harness" keyword. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    if ! printf '%s' "$err" | grep -q 'CommonRules.md'; then
        printf 'expected missing marker name (CommonRules.md) in warning. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    # 「bash install.sh --update」案内を含む
    if ! printf '%s' "$err" | grep -q 'install.sh --update'; then
        printf 'expected install.sh --update guidance. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 3: version stamp 異常 (非 YYYY-MM-DD) → UNKNOWN + WARN ===
case_3_sanitize_bad_version_stamp() {
    local root
    root=$(_root_for 3)
    _layout_full "$root" 'aaaa $(rm -rf /)'

    local err
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err" ]; then
        printf 'expected stderr WARN, got empty\n' >&2
        return 1
    fi
    if ! printf '%s' "$err" | grep -q 'UNKNOWN'; then
        printf 'expected UNKNOWN in warning (sanitize). stderr:\n%s\n' "$err" >&2
        return 1
    fi
    # injection attempt 文字列 (rm -rf /) が stderr に出てはいけない
    if printf '%s' "$err" | grep -qF 'rm -rf'; then
        printf 'SECURITY: bad input leaked to stderr. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 4: 未来日付 → 別 WARN「stamp 異常」===
case_4_warn_on_future_date() {
    local root
    root=$(_root_for 4)
    _layout_full "$root" "$(_future)"

    local err
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err" ]; then
        printf 'expected stderr WARN (future date), got empty\n' >&2
        return 1
    fi
    if ! printf '%s' "$err" | grep -qE 'future|未来'; then
        printf 'expected future-date warning. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 5: 同一 session 2 回目 → 重複抑制 ===
case_5_dedup_within_session() {
    local root
    root=$(_root_for 5)
    _layout_full "$root" "$(_today)"
    rm -f "$root/.claude/CommonRules.md"  # marker 欠落で WARN trigger

    # 1 回目: WARN 発火
    local err1
    err1=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err1" ]; then
        printf 'precondition: first run should fire WARN, got empty\n' >&2
        return 1
    fi

    # state file が作られたはず
    if ! ls "$(_state_dir_for "$root")"/*.fired >/dev/null 2>&1; then
        printf 'expected state file *.fired in %s\n' "$(_state_dir_for "$root")" >&2
        return 1
    fi

    # 2 回目: 同 root, 同 sha → silent
    local err2
    err2=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -n "$err2" ]; then
        printf 'expected silent on 2nd run (dedup), got:\n%s\n' "$err2" >&2
        return 1
    fi
    return 0
}

# === Case 6: feature OFF → no-op silent ===
case_6_feature_off_noop() {
    local root
    root=$(_root_for 6)
    _layout_full "$root" "$(_today)"
    rm -f "$root/.claude/CommonRules.md"  # 本来 WARN 出る

    local err
    err=$(
        HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false \
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -n "$err" ]; then
        printf 'expected silent (feature OFF), got:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 7: config 不在 → silent fail-open ===
case_7_silent_when_no_config() {
    local root
    root=$(_root_for 7)
    mkdir -p "$root"
    # yml も marker も無し
    local err rc
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/no-such-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'expected exit 0 (fail-open), got %d\n' "$rc" >&2
        return 1
    fi
    if [ -n "$err" ]; then
        printf 'expected silent (no config fail-open), got:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 8: marker list 未設定 → silent fail-open ===
case_8_silent_when_no_markers() {
    local root
    root=$(_root_for 8)
    # yml は存在するが stale_harness_markers が空配列
    mkdir -p "$root/.claude"
    cat > "$root/.claude/harness-config.yml" <<EOF
harness_version: "$(_today)"
stale_harness_markers: []
feature_stale_harness_detect_enabled: true
EOF
    local err rc
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'expected exit 0 (no markers fail-open), got %d\n' "$rc" >&2
        return 1
    fi
    if [ -n "$err" ]; then
        printf 'expected silent (no markers configured), got:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 9: version key 欠落 + marker 全在 → WARN「stamp 未設定」===
case_9_warn_on_missing_version_key() {
    local root
    root=$(_root_for 9)
    # marker 全在 layout、ただし yml に harness_version 行を含めない
    mkdir -p \
        "$root/.claude" \
        "$root/.claude/scripts" \
        "$root/.claude/hooks/lib"
    : > "$root/.claude/CommonRules.md"
    : > "$root/.claude/scripts/hc-config.sh"
    : > "$root/.claude/hooks/lib/config-loader.sh"
    : > "$root/.claude/hooks/loop-confirmation-detector.sh"
    cat > "$root/.claude/harness-config.yml" <<EOF
# harness_version key intentionally absent
stale_harness_markers: [CommonRules.md, scripts/hc-config.sh, hooks/lib/config-loader.sh, hooks/loop-confirmation-detector.sh]
feature_stale_harness_detect_enabled: true
EOF

    local err
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err" ]; then
        printf 'expected stderr WARN (missing version key), got empty\n' >&2
        return 1
    fi
    # UNKNOWN 表示で出ているはず
    if ! printf '%s' "$err" | grep -q 'UNKNOWN'; then
        printf 'expected UNKNOWN for missing version key. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# === Case 10: WARN 取込手順 strengthen (task-59 G2 連携) ===
# 規範: .claude/rules/development-process.md §「harness 取込チェックリスト」
# F の WARN 文に install.sh --update 案内 + 採用案内構造 (system-reminder / 対処 keyword)
# が含まれることを strengthen verify。Case 2 既存検証 (install.sh --update 含有) を
# 補強し、task-59 採用案 C ハイブリッドの「F WARN 連携」を smoke で固定化する。
case_10_warn_includes_proactive_sync_guidance() {
    local root
    root=$(_root_for 10)
    _layout_full "$root" "$(_today)"
    # marker 欠落で WARN を発火させる (Case 2 と同じ trigger だが verify 観点が異なる)
    rm -f "$root/.claude/CommonRules.md"

    local err
    err=$(
        unset HC_FEATURE_STALE_HARNESS_DETECT_ENABLED
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        bash "$HOOK" </dev/null 2>&1 >/dev/null
    )
    if [ -z "$err" ]; then
        printf 'expected stderr WARN (proactive sync guidance), got empty\n' >&2
        return 1
    fi
    # (1) install.sh --update 案内 (task-59 G2 case C: F WARN 連携の核心)
    if ! printf '%s' "$err" | grep -q 'install.sh --update'; then
        printf '[case 10/1] missing install.sh --update guidance. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    # (2) terminal 経路明示 (cross-repo write は user manual 必須、規範 §「cross-repo write 例外」連携)
    if ! printf '%s' "$err" | grep -qE 'terminal|user manual|手動'; then
        printf '[case 10/2] missing terminal/manual hint. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    # (3) system-reminder tag (Claude Code 注入経路、SessionStart hook の標準)
    if ! printf '%s' "$err" | grep -q 'system-reminder'; then
        printf '[case 10/3] missing system-reminder tag. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    # (4) bash prefix (実行コマンドであることを user に明示)
    if ! printf '%s' "$err" | grep -qE 'bash[[:space:]]+install\.sh'; then
        printf '[case 10/4] missing bash command prefix. stderr:\n%s\n' "$err" >&2
        return 1
    fi
    return 0
}

# =====================================================================
# task-84 registry 比較シナリオ (Cases 11-15)
# =====================================================================
# helper: python3 ベースの local http server を動的 port で起動し、
#         port を stdout の 1 行目に出力して serve_forever する。
#         引数 $1 = registry version (json "version" 値として返す)
# 注: bash 3.2 互換のため process substitution を使わず tmp file 経由。
#     trap は caller 側で管理 (server pid を 変数で受け取る)。

# _shd_ensure_registry_server_script — サーバースクリプトを $TMP_BASE/registry-server.py に配置
_shd_ensure_registry_server_script() {
    local script_path="${TMP_BASE}/registry-server.py"
    if [ ! -f "$script_path" ]; then
        cat > "$script_path" <<'PYEOF'
import http.server, socketserver, json, sys
ver = sys.argv[1] if len(sys.argv) > 1 else "1.0.0"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"version": ver}).encode())
    def log_message(self, *a): pass
with socketserver.TCPServer(("127.0.0.1", 0), H) as s:
    port = s.server_address[1]
    import sys as _sys; _sys.stdout.write(str(port)+"\n"); _sys.stdout.flush()
    s.serve_forever()
PYEOF
    fi
    printf '%s' "$script_path"
}

# _shd_start_registry_server <version> <port_file> — サーバー起動、PID を返す (echo)
# port_file に port が書き込まれるまで _shd_wait_server_port で待つ。
_shd_start_registry_server() {
    local ver="$1"
    local port_file="$2"
    local script_path
    script_path=$(_shd_ensure_registry_server_script)
    python3 "$script_path" "$ver" > "$port_file" &
    printf '%s' "$!"
}

# _shd_wait_server_port <port_file> [timeout_iterations] — port 書き込みを最大 iterations×0.1s 待つ
# timeout_iterations のデフォルトは 30 (= 3 秒)。sleep 0.1 ごとに elapsed を +1 するため
# 引数は「秒数」ではなく「イテレーション数」として扱う (HIGH flaky 修正 contract)。
_shd_wait_server_port() {
    local port_file="$1"
    local timeout_iterations="${2:-30}"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout_iterations" ]; do
        if [ -s "$port_file" ]; then
            head -1 "$port_file"
            return 0
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    return 1
}

# _shd_layout_npm <root> <npm_version> [markers_line]
# 既存 _layout_full に加えて harness_npm_version を yml に書く
_shd_layout_npm() {
    local root="$1"
    local npm_ver="$2"
    local markers_line="${3:-stale_harness_markers: [CommonRules.md, scripts/hc-config.sh, hooks/lib/config-loader.sh, hooks/loop-confirmation-detector.sh]}"

    mkdir -p \
        "$root/.claude" \
        "$root/.claude/scripts" \
        "$root/.claude/hooks" \
        "$root/.claude/hooks/lib"

    : > "$root/.claude/CommonRules.md"
    : > "$root/.claude/scripts/hc-config.sh"
    : > "$root/.claude/hooks/lib/config-loader.sh"
    : > "$root/.claude/hooks/loop-confirmation-detector.sh"

    cat > "$root/.claude/harness-config.yml" <<EOF
# test fixture (task-84)
harness_version: "$(_today)"
harness_npm_version: "${npm_ver}"
${markers_line}
feature_stale_harness_detect_enabled: true
stale_harness_check_interval_hours: 24
EOF
}

# === Case 11: stamp 古 + registry 新 → WARN (新版 / npx / update) ===
case_11_warn_when_stamp_older_than_registry() {
    local root
    root=$(_root_for 11)
    _shd_layout_npm "$root" "0.0.1"

    # state dir は隔離 (実 repo の .stale-harness-state を汚さない)
    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"
    # last-check なし (throttle スルー)

    # local registry server を起動
    local port_file="${TMP_BASE}/srv11-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    local combined
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    kill "$srv_pid" 2>/dev/null

    # WARN が出ていることを確認 (「新版」「npx」「update」の 3 keyword + 内容 assert 4 点)
    local ok=1
    if ! printf '%s' "$combined" | grep -q '新版'; then
        printf 'missing "新版" in output:\n%s\n' "$combined" >&2; ok=0
    fi
    if ! printf '%s' "$combined" | grep -q 'npx'; then
        printf 'missing "npx" in output:\n%s\n' "$combined" >&2; ok=0
    fi
    if ! printf '%s' "$combined" | grep -q 'update'; then
        printf 'missing "update" in output:\n%s\n' "$combined" >&2; ok=0
    fi
    # 内容 assert 4 点 (contract Case 11 WARN 内容 assert)
    # (1) system-reminder タグ
    if ! printf '%s' "$combined" | grep -q 'system-reminder'; then
        printf '[case11 assert1] missing system-reminder tag. output:\n%s\n' "$combined" >&2; ok=0
    fi
    # (2) block しません — 安全注記
    if ! printf '%s' "$combined" | grep -q 'block'; then
        printf '[case11 assert2] missing "block" safety note. output:\n%s\n' "$combined" >&2; ok=0
    fi
    # (3) registry version 9.9.9 が出力に含まれる
    if ! printf '%s' "$combined" | grep -q '9.9.9'; then
        printf '[case11 assert3] missing registry version "9.9.9". output:\n%s\n' "$combined" >&2; ok=0
    fi
    # (4) stamp version 0.0.1 が出力に含まれる
    if ! printf '%s' "$combined" | grep -q '0.0.1'; then
        printf '[case11 assert4] missing stamp version "0.0.1". output:\n%s\n' "$combined" >&2; ok=0
    fi
    [ "$ok" -eq 1 ]
}

# === Case 12: stamp == registry → silent ===
case_12_silent_when_same_version() {
    local root
    root=$(_root_for 12)
    _shd_layout_npm "$root" "1.2.3"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    local port_file="${TMP_BASE}/srv12-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "1.2.3" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    local combined
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    kill "$srv_pid" 2>/dev/null

    if [ -n "$combined" ]; then
        printf 'expected silent (same version), got:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

# === Case 13: registry 取得失敗 → fail-open silent + exit 0 ===
case_13_fail_open_on_registry_error() {
    local root
    root=$(_root_for 13)
    _shd_layout_npm "$root" "0.0.1"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    local combined rc
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:1" \
        bash "$HOOK" </dev/null 2>&1
    )
    rc=$?

    if [ "$rc" -ne 0 ]; then
        printf 'expected exit 0 (fail-open), got %d\n' "$rc" >&2
        return 1
    fi
    # WARN メッセージなし (fail-open silent)
    if printf '%s' "$combined" | grep -q 'stale-harness-detect.*新版'; then
        printf 'unexpected registry WARN on failure:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

# === Case 14: throttle — 2 回目は registry 取得せず skip ===
# 1 回目: last-check ファイルを作成 (registry WARN なし = silent or marker WARN)
# 2 回目: サーバーを落としても silent exit 0 (throttle が効いているため)
case_14_throttle_skips_registry_on_2nd_run() {
    local root
    root=$(_root_for 14)
    _shd_layout_npm "$root" "0.0.1"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    # 1 回目: サーバーあり → last-check が作られる
    local port_file="${TMP_BASE}/srv14-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    CLAUDE_PROJECT_DIR="$root" \
    HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
    HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
    HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
    bash "$HOOK" </dev/null >/dev/null 2>&1
    kill "$srv_pid" 2>/dev/null

    # last-check が作られたことを確認
    if [ ! -f "${state_dir}/last-check" ]; then
        printf 'expected last-check marker after 1st run, not found in %s\n' "$state_dir" >&2
        return 1
    fi

    # 2 回目: サーバーなし (port 1 = 接続拒否) でも throttle により silent
    local combined2 rc2
    combined2=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:1" \
        bash "$HOOK" </dev/null 2>&1
    )
    rc2=$?

    if [ "$rc2" -ne 0 ]; then
        printf 'expected exit 0 on throttled 2nd run, got %d\n' "$rc2" >&2
        return 1
    fi
    # 「新版」WARN は出ない (throttle で registry 未取得)
    if printf '%s' "$combined2" | grep -q '新版'; then
        printf 'unexpected registry WARN on throttled 2nd run:\n%s\n' "$combined2" >&2
        return 1
    fi
    return 0
}

# === Case 15: feature OFF → no-op exit 0 ===
case_15_feature_off_noop_registry() {
    local root
    root=$(_root_for 15)
    _shd_layout_npm "$root" "0.0.1"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    local combined rc
    combined=$(
        HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false \
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:1" \
        bash "$HOOK" </dev/null 2>&1
    )
    rc=$?

    if [ "$rc" -ne 0 ]; then
        printf 'expected exit 0 (feature OFF), got %d\n' "$rc" >&2
        return 1
    fi
    if [ -n "$combined" ]; then
        printf 'expected silent (feature OFF), got:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

# =====================================================================
# task-84 追加 gap カバレッジ (Cases 16-19)
# =====================================================================

# === Case 16: Gap-A throttle 境界 — last-check が interval ちょうど前 → registry 取得走る ===
# last-check の mtime を (interval_hours * 3600) 秒前に設定する。
# age_sec >= interval_sec となり throttle を抜けて registry 取得が走ることを確認。
case_16_throttle_boundary_fetches_registry() {
    local root
    root=$(_root_for 16)
    _shd_layout_npm "$root" "0.0.1"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    # local registry server を起動 (新版 9.9.9)
    local port_file="${TMP_BASE}/srv16-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    # last-check ファイルを interval ちょうど前に設定 (age_sec == interval_sec → fetch 走る)
    # stale_harness_check_interval_hours: 24 → 86400 秒前
    # touch -t でタイムスタンプを 86401 秒前に設定 (age_sec > interval_sec 確実)
    local last_check="${state_dir}/last-check"
    : > "$last_check"
    # BSD/GNU 両対応: 86401 秒前の時刻を YYYYMMDDHHMM.SS 形式で計算
    local ts_old
    if date -v -86401S +"%Y%m%d%H%M.%S" >/dev/null 2>&1; then
        ts_old=$(date -v -86401S +"%Y%m%d%H%M.%S")
    else
        ts_old=$(date -d "-86401 seconds" +"%Y%m%d%H%M.%S" 2>/dev/null || date -u +"%Y%m%d%H%M.%S")
    fi
    touch -t "$ts_old" "$last_check" 2>/dev/null || true

    local combined
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    kill "$srv_pid" 2>/dev/null

    # registry 取得が走り WARN が出るはず (throttle を抜けた証拠)
    if ! printf '%s' "$combined" | grep -q '新版'; then
        printf '[Gap-A] throttle boundary: expected WARN with "新版" (registry fetch ran), got:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

# === Case 17: Gap-B fallback 経路 — cli_path 不在で fallback semver 比較 → 同一 WARN 結果 ===
# bin/cli.js が存在しない (または node なし) 環境でも fallback 経路で WARN が出ることを確認。
# bin/cli.js を存在しない path にリダイレクトし、fallback _shd_semver_fallback が使われることを検証。
case_17_fallback_semver_same_warn() {
    local root
    root=$(_root_for 17)
    _shd_layout_npm "$root" "0.0.1"
    # bin/cli.js を作らない (存在しない → cli.js 経路スキップ → fallback 使用)

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    local port_file="${TMP_BASE}/srv17-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    local combined
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    kill "$srv_pid" 2>/dev/null

    # fallback でも同一の WARN が出るはず
    local ok=1
    if ! printf '%s' "$combined" | grep -q '新版'; then
        printf '[Gap-B] fallback path: missing "新版". output:\n%s\n' "$combined" >&2; ok=0
    fi
    if ! printf '%s' "$combined" | grep -q 'npx'; then
        printf '[Gap-B] fallback path: missing "npx". output:\n%s\n' "$combined" >&2; ok=0
    fi
    if ! printf '%s' "$combined" | grep -q '9.9.9'; then
        printf '[Gap-B] fallback path: missing registry version "9.9.9". output:\n%s\n' "$combined" >&2; ok=0
    fi
    [ "$ok" -eq 1 ]
}

# === Case 18: Gap-C harness_npm_version 行不在 → fail-open silent (version 比較 skip) ===
# yml に harness_npm_version キー自体が存在しない場合、registry 比較を skip して silent になる。
case_18_no_npm_version_key_silent() {
    local root
    root=$(_root_for 18)
    # _layout_full を使用 (harness_npm_version 行なし)
    _layout_full "$root" "$(_today)"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    # server を起動しても registry WARN が出ないことを確認 (harness_npm_version 不在 → skip)
    local port_file="${TMP_BASE}/srv18-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    local combined rc
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    rc=$?
    kill "$srv_pid" 2>/dev/null

    if [ "$rc" -ne 0 ]; then
        printf '[Gap-C] expected exit 0 (fail-open, no npm version key), got %d\n' "$rc" >&2
        return 1
    fi
    # registry WARN (新版 keyword) は出てはいけない
    if printf '%s' "$combined" | grep -q '新版'; then
        printf '[Gap-C] unexpected registry WARN when harness_npm_version absent:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

# === Case 19: Gap-D 不正 semver stamp (not-a-version) → fail-open silent ===
# harness_npm_version に不正な semver 文字列が設定されている場合、
# semver regex 不一致で exit 0 (fail-open) silent になることを確認。
case_19_invalid_semver_stamp_silent() {
    local root
    root=$(_root_for 19)
    _shd_layout_npm "$root" "not-a-version"

    local state_dir="${root}/.claude/.stale-harness-state"
    mkdir -p "$state_dir"

    local port_file="${TMP_BASE}/srv19-port.txt"
    local srv_pid
    srv_pid=$(_shd_start_registry_server "9.9.9" "$port_file")
    local port
    port=$(_shd_wait_server_port "$port_file") || {
        kill "$srv_pid" 2>/dev/null
        printf 'server did not start in time\n' >&2
        return 1
    }

    local combined rc
    combined=$(
        CLAUDE_PROJECT_DIR="$root" \
        HC_CONFIG_PATH="$root/.claude/harness-config.yml" \
        HC_STALE_HARNESS_DETECT_STATE_DIR="$state_dir" \
        HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:${port}" \
        bash "$HOOK" </dev/null 2>&1
    )
    rc=$?
    kill "$srv_pid" 2>/dev/null

    if [ "$rc" -ne 0 ]; then
        printf '[Gap-D] expected exit 0 (fail-open, invalid semver stamp), got %d\n' "$rc" >&2
        return 1
    fi
    # 不正 semver → registry 比較 skip → registry WARN なし
    if printf '%s' "$combined" | grep -q '新版'; then
        printf '[Gap-D] unexpected registry WARN for invalid semver stamp:\n%s\n' "$combined" >&2
        return 1
    fi
    return 0
}

printf '===== task-56 stale-harness-detect smoke =====\n'
run_case 1 'silent when healthy (markers + valid version)' case_1_silent_when_healthy
run_case 2 'WARN on missing marker (CommonRules.md absent)' case_2_warn_on_missing_marker
run_case 3 'sanitize bad version stamp -> UNKNOWN + WARN' case_3_sanitize_bad_version_stamp
run_case 4 'WARN on future-date stamp' case_4_warn_on_future_date
run_case 5 'dedup within same session (2nd run silent)' case_5_dedup_within_session
run_case 6 'feature OFF -> no-op silent' case_6_feature_off_noop
run_case 7 'no config -> silent fail-open' case_7_silent_when_no_config
run_case 8 'empty marker list -> silent fail-open' case_8_silent_when_no_markers
run_case 9 'missing version key -> WARN UNKNOWN' case_9_warn_on_missing_version_key
run_case 10 'WARN includes proactive sync guidance (task-59 G2)' case_10_warn_includes_proactive_sync_guidance
printf '\n--- task-84: registry 比較シナリオ ---\n'
run_case 11 'stamp older -> WARN (新版/npx/update)' case_11_warn_when_stamp_older_than_registry
run_case 12 'stamp == registry -> silent' case_12_silent_when_same_version
run_case 13 'registry fetch fail -> fail-open silent + exit 0' case_13_fail_open_on_registry_error
run_case 14 'throttle: 2nd run skips registry fetch' case_14_throttle_skips_registry_on_2nd_run
run_case 15 'feature OFF -> no-op exit 0 (registry path)' case_15_feature_off_noop_registry
printf '\n--- task-84: gap カバレッジ (Cases 16-19) ---\n'
run_case 16 'Gap-A throttle boundary: age>=interval -> registry fetch runs' case_16_throttle_boundary_fetches_registry
run_case 17 'Gap-B fallback semver: cli_path absent -> same WARN result' case_17_fallback_semver_same_warn
run_case 18 'Gap-C harness_npm_version absent -> fail-open silent' case_18_no_npm_version_key_silent
run_case 19 'Gap-D invalid semver stamp (not-a-version) -> fail-open silent' case_19_invalid_semver_stamp_silent

printf '\n===== Result =====\n'
TOTAL=$((PASS + FAIL))
printf 'PASS: %d / %d\n' "$PASS" "$TOTAL"
printf 'FAIL: %d / %d\n' "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
    exit 1
fi
exit 0
