#!/usr/bin/env bash
# .claude/tests/hc-config-local-yml-smoke.sh — HOTFIX-2 hc-config.sh local.yml 読込 smoke
#
# 検証対象:
#   hc-config.sh --get / --summary が harness-config.local.yml override を
#   config-loader.sh Step 3.5 と同一 semantics (env > local.yml > SSoT yml > default) で
#   適用すること (「CLI 表示と hook runtime 実効値の真実が 2 つに分裂」する gap の regression 検出)。
#   設計: docs/draft/install-immediately-usable-redesign-20260618.md §9.1 HOTFIX-2 + §4.2
#
# sandbox 方式:
#   repo 本体の .claude/ を絶対に汚さないため cp -R で tmp dir に丸ごと copy して検証する。
#   hc-config.sh の path 解決は SCRIPT_DIR 相対のため sandbox 内で自己完結し、
#   _validate_config_path も /tmp / /private/tmp / /var/folders を whitelist 済。
#   (repo 内に一時 local.yml を作る方式は並行 process との race があるため禁止)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# caller env 汚染遮断 (config-loader.sh は source 時に HC_LOCAL_CONFIG_PATH を export するため、
# 同一 shell から連続実行される runner 環境では遮断しないと sandbox 外の local.yml を読む)
unset HC_LOCAL_CONFIG_PATH HC_CONFIG_PATH HC_DEFAULT_PRESET \
  HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED HC_FEATURE_TASK_RULE_GUARD_ENABLED 2>/dev/null || true

# sandbox は /tmp 配下に固定: macOS の mktemp -d default (/var/folders/...) は
# _validate_config_path の canon (pwd -P) で /private/var/folders/... となり
# whitelist (/var/folders/*) に一致せず reject されるため (/tmp は canon /private/tmp/* で通過)。
SBX="$(mktemp -d /tmp/hc-config-local-yml-smoke.XXXXXX)" || { printf 'FATAL: mktemp failed\n'; exit 1; }
trap 'rm -rf "$SBX"' EXIT

cp -R "${REPO_ROOT}/.claude" "${SBX}/.claude" 2>/dev/null \
  || { printf 'FATAL: sandbox copy failed\n'; exit 1; }
# sandbox は local.yml 不在状態から開始 (repo 実 local.yml が copy されていたら除去)
rm -f "${SBX}/.claude/harness-config.local.yml"

HC="${SBX}/.claude/scripts/hc-config.sh"
MAIN_YML="${SBX}/.claude/harness-config.yml"
LOCAL_YML="${SBX}/.claude/harness-config.local.yml"
LOADER="${SBX}/.claude/hooks/lib/config-loader.sh"

PASS=0
FAIL=0
_ok() { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$1"; }
_ng() { FAIL=$((FAIL + 1)); printf 'FAIL: %s (expected=%s actual=%s)\n' "$1" "$2" "$3"; }
# $1=name $2=expected $3=actual
_eq() { if [ "$2" = "$3" ]; then _ok "$1"; else _ng "$1" "$2" "$3"; fi; }
# $1=name $2=needle $3=haystack (固定文字列一致)
_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then _ok "$1"; else _ng "$1" "contains:$2" "$3"; fi
}

# SSoT yml から raw 値を抽出 (期待値 hardcode を避け repo yml 変更に追従)
# $1: key
_main_raw() {
  grep -E "^$1:" "$MAIN_YML" | head -n 1 \
    | sed -E "s/^$1:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//"
}

# --- Case 1: local.yml 不在 → --get default_preset は main yml 値 ---
expected="$(_main_raw default_preset)"
actual="$(bash "$HC" --get default_preset 2>/dev/null)"
_eq "Case 1: local.yml 不在で --get default_preset = main yml 値 (${expected})" "$expected" "$actual"

# --- Case 2: local.yml override → --get が local 値 / --summary に marker + path ---
cat > "$LOCAL_YML" <<'EOF'
# smoke 用 local override (sandbox 内のみ、trap cleanup で消える)
default_preset: team-default
feature_draft_flow_guard_enabled: true
EOF

actual="$(bash "$HC" --get default_preset 2>/dev/null)"
_eq "Case 2a: --get default_preset が local 値" "team-default" "$actual"

actual="$(bash "$HC" --get feature_draft_flow_guard_enabled 2>/dev/null)"
_eq "Case 2b: --get feature_draft_flow_guard_enabled が local 値" "true" "$actual"

# --summary は preset=team-default で undoc mismatch により非 0 exit がありうるため || true
summary_out="$(bash "$HC" --summary 2>/dev/null || true)"
_contains "Case 2c: --summary に (local overridden) marker" "(local overridden)" "$summary_out"
_contains "Case 2d: --summary 冒頭に local.yml path 明示" "local config: ${LOCAL_YML}" "$summary_out"

# mode-session-start.sh の awk '/^preset:/{print $2}' 互換 (marker 付与後も $2 は preset 値)
preset_field="$(printf '%s\n' "$summary_out" | awk '/^preset:/ { print $2; exit }')"
_eq "Case 2e: --summary preset 行 \$2 が local 値 (mode-session-start awk 互換)" "team-default" "$preset_field"

# --- Case 3: runtime parity (config-loader.sh source の HC_* == CLI --get) ---
runtime_preset="$(bash -c '
  set -uo pipefail
  export HC_CONFIG_PATH="$1"
  # shellcheck disable=SC1090
  source "$2" 2>/dev/null
  printf "%s" "${HC_DEFAULT_PRESET:-}"
' _ "$MAIN_YML" "$LOADER")"
cli_preset="$(bash "$HC" --get default_preset 2>/dev/null)"
_eq "Case 3a: runtime parity default_preset (loader=${runtime_preset})" "$runtime_preset" "$cli_preset"

runtime_flag="$(bash -c '
  set -uo pipefail
  export HC_CONFIG_PATH="$1"
  # shellcheck disable=SC1090
  source "$2" 2>/dev/null
  printf "%s" "${HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED:-}"
' _ "$MAIN_YML" "$LOADER")"
cli_flag="$(bash "$HC" --get feature_draft_flow_guard_enabled 2>/dev/null)"
_eq "Case 3b: runtime parity feature_draft_flow_guard_enabled (loader=${runtime_flag})" "$runtime_flag" "$cli_flag"

# --- Case 4: local.yml に無い key は main yml 値のまま ---
expected="$(_main_raw feature_task_rule_guard_enabled)"
actual="$(bash "$HC" --get feature_task_rule_guard_enabled 2>/dev/null)"
_eq "Case 4: local.yml に無い key は main yml 値のまま (${expected})" "$expected" "$actual"

# --- Case 5: --set は SSoT に書くが local override が実効値に残る (stderr note + --get 不変) ---
set_err="$(bash "$HC" --set default_preset=strict 2>&1 >/dev/null || true)"
_contains "Case 5a: --set 時に local override note (stderr)" "harness-config.local.yml overrides 'default_preset'" "$set_err"

actual="$(bash "$HC" --get default_preset 2>/dev/null)"
_eq "Case 5b: --set 後も --get は local 値 (runtime 実効値と一致)" "team-default" "$actual"

ssot_after="$(_main_raw default_preset)"
_eq "Case 5c: --set は SSoT yml には書けている" "strict" "$ssot_after"

printf '\n%d PASS, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
