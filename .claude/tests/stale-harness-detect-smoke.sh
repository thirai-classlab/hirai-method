#!/usr/bin/env bash
# stale-harness-detect-smoke.sh — task-56 F (stale-harness-detect)
#
# Cases:
#   1: marker 全在 + harness_version 正常 (今日)        → silent (exit 0, stdout/stderr 0 byte)
#   2: marker 欠落 (CommonRules.md 不在)                → WARN 発火 (<system-reminder> + 'stale harness')
#   3: harness_version stamp 異常 (非 YYYY-MM-DD)       → UNKNOWN 表示 + WARN
#   4: 未来日付 (>= 翌日)                                 → 別 WARN「stamp 異常 (future)」
#   5: 同一 session 2 回目実行                          → 重複抑制 (silent)
#   6: feature OFF (HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false) → no-op silent
#   7: config 不在 (HC_CONFIG_PATH を bogus path)        → silent fail-open (exit 0)
#   8: marker list 未設定 (yml に stale_harness_markers 空) → silent fail-open
#   9: harness_version key 欠落 (yml に key 自体無し) + marker 全在 → WARN 「stamp 未設定」
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

printf '\n===== Result =====\n'
printf 'PASS: %d / 9\n' "$PASS"
printf 'FAIL: %d / 9\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
    exit 1
fi
exit 0
