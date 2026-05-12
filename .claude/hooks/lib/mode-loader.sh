#!/usr/bin/env bash
# mode-loader.sh — 動作モード解決ユーティリティ
#
# 役割: `.claude/mode.yml` または環境変数 `HC_MODE` から現在のモードを読み取る。
# 値解決の優先順 (高 → 低): env(HC_MODE) > YAML > default(normal)
#
# 使い方:
#   source .claude/hooks/lib/mode-loader.sh
#   MODE=$(load_mode)
#
# 戻り値: stdout に "normal" または "loop" を出力。不正値は "normal" に正規化。
#
# bash flags の方針 (重要):
#   本ファイルを source する caller の shell options を汚染しないため、
#   ファイルトップでは `set -euo pipefail` を **使用しない**。
#   関数本体は subshell `( ... )` で囲み、その内側だけで strict mode を有効化する。
#   過去に context-budget.sh で `set -e` が source 経由で漏れ、後段の pipeline
#   (`... | jq | head -1`) が SIGPIPE で 141 終了し本体ロジック (state 書き込み /
#   <system-reminder> 注入) が一切実行されない事故があった。

load_mode() (
  set -euo pipefail
  local mode=""

  # 1) 環境変数優先
  if [ -n "${HC_MODE:-}" ]; then
    mode="$HC_MODE"
  else
    # 2) YAML 読み取り (`mode: <value>` 1 行)
    local cfg=".claude/mode.yml"
    if [ -f "$cfg" ]; then
      mode=$(grep -E '^[[:space:]]*mode[[:space:]]*:' "$cfg" \
        | head -1 \
        | sed -E 's/^[[:space:]]*mode[[:space:]]*:[[:space:]]*//' \
        | tr -d '"' | tr -d "'" \
        | awk '{print $1}')
    fi
  fi

  # 3) 正規化
  case "${mode:-normal}" in
    loop) echo "loop" ;;
    *)    echo "normal" ;;
  esac
)

# Asana 利用モード解決
# 戻り値: "true" / "false" / "unset"
# 優先順 (高 → 低): env(HC_ASANA_ENABLED) > YAML > unset
load_asana_enabled() (
  set -euo pipefail
  local v=""

  # 1) env 優先
  if [ -n "${HC_ASANA_ENABLED:-}" ]; then
    v="$HC_ASANA_ENABLED"
  else
    # 2) YAML 読み取り (`asana_enabled: <value>` 1 行)
    local cfg=".claude/mode.yml"
    if [ -f "$cfg" ]; then
      v=$(grep -E '^[[:space:]]*asana_enabled[[:space:]]*:' "$cfg" \
        | head -1 \
        | sed -E 's/^[[:space:]]*asana_enabled[[:space:]]*:[[:space:]]*//' \
        | tr -d '"' | tr -d "'" \
        | awk '{print $1}')
    fi
  fi

  # 3) 正規化
  case "${v}" in
    true|yes|on|1)   echo "true" ;;
    false|no|off|0)  echo "false" ;;
    *)               echo "unset" ;;
  esac
)

# スクリプトとして直接呼ばれた場合
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  load_mode
fi
