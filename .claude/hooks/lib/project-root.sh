#!/usr/bin/env bash
# project-root.sh — Unified project root resolver
#
# 役割: hook script が project root を確実に取得するための helper。
#       hook の物理位置 (project-level / user-level) に関わらず
#       同じ logic で project root を resolve できる。
#
# 使用例:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/project-root.sh
#   source "$SCRIPT_DIR/lib/project-root.sh"
#   PROJECT_ROOT=$(resolve_project_root)
#
# 優先順位:
#   1. ${HC_PROJECT_ROOT}              ... env override (CI / test 用)
#   2. git rev-parse --show-toplevel   ... 標準的な project root 解決
#   3. ${CLAUDE_PROJECT_DIR}           ... Claude Code hook 標準注入 (git 管理外でも有効)
#   4. pwd                             ... fallback (上記全て不在時)
#
# bash flags の方針 (重要):
#   本ファイルを source する caller の shell options を汚染しないため、
#   ファイルトップでは `set -euo pipefail` を **使用しない**。
#   関数本体は subshell `( ... )` で囲み、その内側だけで strict mode を有効化する。
#   過去に context-budget.sh で `set -e` が source 経由で漏れ、後段の pipeline
#   が SIGPIPE で 141 終了し本体ロジックが実行されない事故があった
#   (feedback_set_e_in_sourced_libs 規範)。

resolve_project_root() (
  set -uo pipefail

  # 1. env override (HIRAI 固有、CI / test 用)
  if [ -n "${HC_PROJECT_ROOT:-}" ]; then
    printf '%s' "$HC_PROJECT_ROOT"
    return 0
  fi

  # 2. git rev-parse (標準的な project root 解決)
  if command -v git >/dev/null 2>&1; then
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$root" ] && [ -d "$root" ]; then
      printf '%s' "$root"
      return 0
    fi
  fi

  # 3. CLAUDE_PROJECT_DIR (Claude Code hook 標準注入、git 管理外 / submodule 内でも有効)
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi

  # 4. pwd fallback (git 不在 / git 管理外 / CLAUDE_PROJECT_DIR 不在)
  pwd
)

# スクリプトとして直接呼ばれた場合 (manual smoke check 用)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  resolve_project_root
fi
