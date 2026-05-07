#!/usr/bin/env bash
# check-required-env.sh — SessionStart hook that warns about missing required env vars.
#
# 役割:
#   harness-config.yml の `required_env` を読み、未設定エントリを stderr に出して
#   ユーザーに通知する。fail-open: 未設定でも block せず exit 0 で続行する。
#
# 形式 (harness-config.yml):
#   required_env: ["NAME|severity|purpose", ...]
#   severity:
#     error → ❌ MISSING required env: <NAME> (<purpose>)
#     warn  → ⚠️  Recommended env not set: <NAME> (<purpose>)
#     info  → ℹ️  Optional env not set: <NAME> (<purpose>)
#
# Stdin: SessionStart hook JSON (read but unused for now)
# Stdout: 空 (statusMessage / decision JSON は不要 — fail-open)
# Stderr: 未設定エントリのリスト
# Exit:   常に 0 (fail-open)
#
# bash 3.2 互換 (macOS 標準) で動作する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh"

# stdin を捨てる (SessionStart JSON は使わない)
cat >/dev/null 2>&1 || true

[ -z "${HC_REQUIRED_ENV:-}" ] && exit 0

# entry list は newline 区切り (config-loader が `[a, b]` を改行区切りに正規化)。
# bash 3.2 互換のため while read で 1 件ずつ処理。
output=""

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  # entry: "NAME|severity|purpose"
  name="${entry%%|*}"
  rest="${entry#*|}"
  if [ "$rest" = "$entry" ]; then
    # `|` が無い不正フォーマット → skip
    continue
  fi
  severity="${rest%%|*}"
  purpose="${rest#*|}"
  if [ "$purpose" = "$rest" ]; then
    purpose=""
  fi

  # 前後空白 trim + severity を lowercase
  name="$(printf '%s' "$name" | tr -d '[:space:]')"
  severity="$(printf '%s' "$severity" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  # purpose は前後空白だけ trim (中身の空白は保持)
  purpose="${purpose#"${purpose%%[![:space:]]*}"}"
  purpose="${purpose%"${purpose##*[![:space:]]}"}"

  [ -z "$name" ] && continue

  # 未設定判定: bash 3.2 互換で eval を使う
  eval "_hc_value=\${$name:-}"
  if [ -n "${_hc_value:-}" ]; then
    continue
  fi

  case "$severity" in
    error)
      output="${output}[harness] \xe2\x9d\x8c MISSING required env: ${name} (${purpose})\n"
      ;;
    info)
      output="${output}[harness] \xe2\x84\xb9\xef\xb8\x8f  Optional env not set: ${name} (${purpose})\n"
      ;;
    *)
      # default = warn
      output="${output}[harness] \xe2\x9a\xa0\xef\xb8\x8f  Recommended env not set: ${name} (${purpose})\n"
      ;;
  esac
done <<EOF
$HC_REQUIRED_ENV
EOF

unset _hc_value

if [ -n "$output" ]; then
  printf "%b" "$output" >&2
  printf "[harness] Set them via shell rc, .env, or direnv. See docs/PORTABILITY.md\n" >&2
fi

exit 0
