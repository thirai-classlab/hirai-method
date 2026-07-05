#!/usr/bin/env bash
# .claude/tests/hc-config-local-yml-smoke.sh — HOTFIX-2 hc-config.sh local.yml 読込 smoke
#
# 検証対象:
#   hc-config.sh --get / --summary が harness-config.local.yml override を
#   config-loader.sh Step 3.5 と同一 semantics (env > local.yml > SSoT yml > default) で
#   適用すること (「CLI 表示と hook runtime 実効値の真実が 2 つに分裂」する gap の regression 検出)。
#   設計: docs/draft/install-immediately-usable-redesign-20260618.md §9.1 HOTFIX-2 + §4.2
#
#   Case 6〜10 (task #86 Step 1、TDD RED → GREEN):
#     6: env > local parity (HC_DEFAULT_PRESET が CLI/runtime 双方で local に勝つ)
#     7: array key の CLI raw inline vs runtime parsed の semantic equivalence 固定
#     8: local-only key (typo) の --get WARN (stderr unknown_local_key、fail-open 維持)
#     9: --validate の local.yml 検証 (不正型で非 0 + invalid (local)、正常で exit 0)
#    10: --list / --diff の stdout 汚染 0 + stderr local notice + TUI marker 静的 grep
#   設計: docs/draft/hc-config-local-yml-integration.md §3 Step 1
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
  HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED HC_FEATURE_TASK_RULE_GUARD_ENABLED \
  HC_PROTECTED_PATHS HC_UNKNOWN_LOCAL_KEY_WARN 2>/dev/null || true

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
# $1=name $2=needle $3=haystack (固定文字列 不在 確認)
_not_contains() {
  if printf '%s' "$3" | grep -qF -- "$2"; then _ng "$1" "not-contains:$2" "$3"; else _ok "$1"; fi
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

# --- Case 6: env > local parity (env は local に勝つ、CLI と runtime 双方) ---
# 状態: local.yml = default_preset: team-default (Case 2)、SSoT = strict (Case 5c)。
# env HC_DEFAULT_PRESET=strict が local (team-default) に勝つことを CLI / runtime で固定。
actual="$(HC_DEFAULT_PRESET=strict bash "$HC" --get default_preset 2>/dev/null)"
_eq "Case 6a: env HC_DEFAULT_PRESET=strict が --get で local に勝つ" "strict" "$actual"

# runtime 側の env > local parity は known key (feature_draft_flow_guard_enabled) で検証する。
# 注意 (2026-07-05 task #86 Step 1 で発見した既存 bug、本 task scope 外 → 副産物 entry 化):
#   default_preset は config-loader.sh の _HC_KNOWN_KEYS に不在のため、env HC_DEFAULT_PRESET が
#   Step 2 hardcoded default (L353 harness-dev) に clobber され Step 4 restore 対象外
#   (かつ Step 1b guard で yml/local parse も skip) → runtime では env 値が失われる。
#   CLI (_get_current Step 1) は env が正しく勝つ (Case 6a)。loader 側修正は別 task。
runtime_env_flag="$(bash -c '
  set -uo pipefail
  export HC_CONFIG_PATH="$1"
  export HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED=false
  # shellcheck disable=SC1090
  source "$2" 2>/dev/null
  printf "%s" "${HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED:-}"
' _ "$MAIN_YML" "$LOADER")"
_eq "Case 6b: runtime (config-loader) でも env が local に勝つ (known key)" "false" "$runtime_env_flag"

# env set 時は _is_local_overridden が false → preset 行に marker 無し (hc-config.sh L785-787)
summary_env_out="$(HC_DEFAULT_PRESET=strict bash "$HC" --summary 2>/dev/null || true)"
preset_line_env="$(printf '%s\n' "$summary_env_out" | grep '^preset:' | head -n 1)"
_eq "Case 6c: env set 時 --summary preset 行に (local overridden) marker 無し" "preset: strict" "$preset_line_env"

# --- Case 7: array key — CLI raw inline vs runtime parsed の semantic equivalence 固定 ---
# 現挙動固定 (draft hc-config-local-yml-integration §2 案 A):
#   CLI --get は raw inline `[alpha, beta]`、runtime は改行区切り `alpha\nbeta`。
#   文字列表現は非対称のまま、正規化後の意味的一致を機械保証する。
cat > "$LOCAL_YML" <<'EOF'
default_preset: team-default
feature_draft_flow_guard_enabled: true
protected_paths: [alpha, beta]
EOF

cli_arr="$(bash "$HC" --get protected_paths 2>/dev/null)"
_eq "Case 7a: --get protected_paths は raw inline (現挙動固定)" "[alpha, beta]" "$cli_arr"

runtime_arr="$(bash -c '
  set -uo pipefail
  export HC_CONFIG_PATH="$1"
  # shellcheck disable=SC1090
  source "$2" 2>/dev/null
  printf "%s" "${HC_PROTECTED_PATHS:-}"
' _ "$MAIN_YML" "$LOADER")"
_eq "Case 7b: runtime HC_PROTECTED_PATHS は改行区切り parsed list" "$(printf 'alpha\nbeta')" "$runtime_arr"

# CLI raw を正規化 (`[]` 除去 + `,` 区切り → 改行 + 前後空白 trim) → runtime と意味的一致
cli_arr_inner="${cli_arr#\[}"
cli_arr_inner="${cli_arr_inner%\]}"
cli_arr_norm="$(printf '%s' "$cli_arr_inner" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
_eq "Case 7c: CLI raw 正規化 == runtime parsed (semantic equivalence)" "$runtime_arr" "$cli_arr_norm"

# --- Case 8: local-only key (typo) の --get WARN (fail-open 維持) ---
# runtime は config-loader Step 3.6 が unknown_local_key WARN を出す。CLI --get も同 body 文言で
# stderr WARN する (値返し + exit 0 は不変 = fail-open)。抑止 env は Step 3.6 と共用。
cat > "$LOCAL_YML" <<'EOF'
default_preset: team-default
feature_draft_flow_guard_enabled: true
feature_draft_flow_guard_enalbed: true
EOF

case8_err="${SBX}/case8.err"
case8_out="$(bash "$HC" --get feature_draft_flow_guard_enalbed 2>"$case8_err")"
case8_ec=$?
_eq "Case 8a: local-only key --get は値を返す (fail-open)" "true" "$case8_out"
_eq "Case 8b: local-only key --get は exit 0 (fail-open)" "0" "$case8_ec"
_contains "Case 8c: local-only key --get で stderr unknown_local_key WARN" \
  "unknown_local_key: feature_draft_flow_guard_enalbed" "$(cat "$case8_err")"

case8b_err="${SBX}/case8b.err"
HC_UNKNOWN_LOCAL_KEY_WARN=0 bash "$HC" --get feature_draft_flow_guard_enalbed >/dev/null 2>"$case8b_err"
_not_contains "Case 8d: HC_UNKNOWN_LOCAL_KEY_WARN=0 で WARN 消滅" \
  "unknown_local_key" "$(cat "$case8b_err")"

# --- Case 9: --validate の local.yml 検証 ---
# 不正型 (bool key に banana) で exit 非 0 + stderr `invalid (local): <key>`。
# 正常 local なら exit 0 + 既存成功行 `validation OK: all keys valid` 不変。
cat > "$LOCAL_YML" <<'EOF'
default_preset: team-default
feature_draft_flow_guard_enabled: banana
EOF

case9_err="$(bash "$HC" --validate 2>&1 >/dev/null)"
case9_ec=$?
if [ "$case9_ec" -ne 0 ]; then
  _ok "Case 9a: local 不正型 (bool=banana) で --validate exit 非 0"
else
  _ng "Case 9a: local 不正型 (bool=banana) で --validate exit 非 0" "exit!=0" "exit=${case9_ec}"
fi
_contains "Case 9b: --validate stderr に invalid (local) 行" \
  "invalid (local): feature_draft_flow_guard_enabled" "$case9_err"

cat > "$LOCAL_YML" <<'EOF'
default_preset: team-default
feature_draft_flow_guard_enabled: true
EOF

case9c_out="$(bash "$HC" --validate 2>/dev/null)"
case9c_ec=$?
_eq "Case 9c: local 正常値で --validate exit 0" "0" "$case9c_ec"
_contains "Case 9d: 成功行 'validation OK: all keys valid' 文言不変" \
  "validation OK: all keys valid" "$case9c_out"

# --- Case 10: --list / --diff の表示一貫性 (stdout 汚染 0 + stderr local notice) ---
# stdout 汚染 0: hc-config-key-parity-smoke.sh (L62-64) の key 抽出 regex
#   `^[a-z_][a-zA-Z0-9_]*[[:space:]]` + awk '{print $1}' で疑似 key `local` が混入しないこと。
# stderr notice: local.yml 存在時に 1 行 `note: harness-config.local.yml overrides applied to CURRENT ...`。
LOCAL_NOTICE="harness-config.local.yml overrides applied to CURRENT"

list_err="${SBX}/list.err"
list_out="$(bash "$HC" --list 2>"$list_err" || true)"
list_keys="$(printf '%s\n' "$list_out" | grep -E '^[a-z_][a-zA-Z0-9_]*[[:space:]]' | awk '{print $1}' || true)"
if printf '%s\n' "$list_keys" | grep -qx 'local'; then
  _ng "Case 10a: --list stdout に疑似 key 'local' 混入なし (parity regex 互換)" "no pseudo-key 'local'" "pseudo-key 'local' found"
else
  _ok "Case 10a: --list stdout に疑似 key 'local' 混入なし (parity regex 互換)"
fi
list_notice_count="$(grep -cF -- "$LOCAL_NOTICE" "$list_err" || true)"
_eq "Case 10b: --list stderr に local notice 1 行" "1" "$list_notice_count"

diff_err="${SBX}/diff.err"
diff_out="$(bash "$HC" --diff 2>"$diff_err" || true)"
diff_keys="$(printf '%s\n' "$diff_out" | grep -E '^[a-z_][a-zA-Z0-9_]*[[:space:]]' | awk '{print $1}' || true)"
if printf '%s\n' "$diff_keys" | grep -qx 'local'; then
  _ng "Case 10c: --diff stdout に疑似 key 'local' 混入なし" "no pseudo-key 'local'" "pseudo-key 'local' found"
else
  _ok "Case 10c: --diff stdout に疑似 key 'local' 混入なし"
fi
diff_notice_count="$(grep -cF -- "$LOCAL_NOTICE" "$diff_err" || true)"
_eq "Case 10d: --diff stderr に local notice 1 行" "1" "$diff_notice_count"

# TUI effect panel は TTY 専用で smoke 未発火 (task-48 前例) → 静的 grep assertion:
# _tui_render_effect_panel_for_key 関数 body に (local overridden) marker が存在すること
# (--summary L1184 と同 marker 文言、draft §3 Step 4-2)。
#
# task-86 findings HIGH (Mutation F 実証): 単純に function body 全体を grep すると、
# `local_mark=" (local overridden)"` assignment が削除されて "removed marker" 系コメント
# だけ残った dead-code cleanup 中間状態でも smoke が green のまま regression が漏れる。
# 対策 2 段:
#   10e-1 (loose): 従来の marker string 存在確認 (backward compat)
#   10e-2 (strict): comment 行を除外した本体に marker string があること (Mutation F 反証)
#   10e-3 (strict): `local_mark=" (local overridden)"` assignment 行 pattern の直接 assert
#     (実 refactor で assignment を消したら FAIL する最小十分条件)
tui_fn_body="$(awk '/^_tui_render_effect_panel_for_key\(\)/{f=1} f{print} f && /^\}/{exit}' "$HC")"
_contains "Case 10e-1: TUI effect panel 関数に (local overridden) marker (静的 grep loose)" \
  "(local overridden)" "$tui_fn_body"

# comment 行 (`^[[:space:]]*#`) を除外した code 行のみ grep
tui_fn_code="$(printf '%s\n' "$tui_fn_body" | grep -v '^[[:space:]]*#' || true)"
_contains "Case 10e-2: TUI effect panel 関数 code (comment 除外) に marker (Mutation F 反証)" \
  "(local overridden)" "$tui_fn_code"

# `local_mark=" (local overridden)"` assignment 行の直接 assert (最小十分条件)
if printf '%s\n' "$tui_fn_code" | grep -qE 'local_mark="[[:space:]]*\(local overridden\)[[:space:]]*"'; then
  _ok "Case 10e-3: TUI effect panel に local_mark 代入 pattern (strict assignment 実在確認)"
else
  _ng "Case 10e-3: TUI effect panel に local_mark 代入 pattern (strict assignment 実在確認)" \
    'local_mark=" (local overridden)"' "$tui_fn_code"
fi

printf '\n%d PASS, %d FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
