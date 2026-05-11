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

set -euo pipefail

load_mode() {
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
}

# スクリプトとして直接呼ばれた場合
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  load_mode
fi
