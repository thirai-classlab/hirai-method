#!/usr/bin/env bash
# PostToolUse: Edit|Write 後に .md/.mdx の Mermaid ブロックを構文検証する。
#
# 入力 (stdin): PostToolUse JSON
# 出力 (stdout): hook 応答 JSON
#
# 動作:
#   - 拡張子が .md / .mdx 以外なら即 allow
#   - ファイル内に ```mermaid フェンスが無ければ即 allow
#   - パース失敗時は decision:"block" で Claude に修正を促す
#
# Mermaid library 解決順序 (task-25 A1):
#   1. project-local: ./node_modules/{mermaid,jsdom}
#   2. global install: $(npm root -g)/{mermaid,jsdom}
#   3. npx fallback: network 経由で mermaid@11.13.0 + jsdom を取得
#   いずれも失敗時は install hint を stderr に出して fail-open (hook 失敗で session 止めない)
#
# 関連:
#   - スクリプト: .claude/scripts/check-md-mermaid.mjs
#   - スキル定義: .claude/skills/check-md-mermaid/SKILL.md

set -u

# config 読み込み (HC_* 変数 + is_feature_enabled 関数 export、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled check_md_mermaid; then
  echo '{}'
  exit 0   # feature OFF で no-op (PostToolUse hook response 規約: empty JSON)
fi

input=$(cat)

# task-22 W2: jq 不在環境では fail-open (hook 機能停止して継続)
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if [ -z "$file_path" ]; then
  echo '{}'
  exit 0
fi

case "$file_path" in
  *.md|*.mdx) ;;
  *) echo '{}'; exit 0 ;;
esac

if [ ! -f "$file_path" ]; then
  echo '{}'
  exit 0
fi

# Quick skip: no mermaid fence -> nothing to validate
if ! grep -qE '^[[:space:]]*(\`{3,}|~{3,})[[:space:]]*mermaid' "$file_path" 2>/dev/null; then
  echo '{}'
  exit 0
fi

# Resolve project root (dual-mode portability: HC_PROJECT_ROOT > git > pwd)
script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/project-root.sh
source "$script_dir/lib/project-root.sh"
project_root=$(resolve_project_root)
cd "$project_root"

if [ ! -f .claude/scripts/check-md-mermaid.mjs ]; then
  echo '{}'
  exit 0
fi

# Resolve mermaid library install location (3-stage fallback).
#
# resolve_mermaid_runner echoes one of:
#   "local"   — node with NODE_PATH unset (cwd node_modules works by default)
#   "global"  — node with NODE_PATH=$(npm root -g)
#   "npx"     — npx --yes --package=mermaid@11.13.0 --package=jsdom node
#   ""        — none found, caller should fail-open with install hint
resolve_mermaid_runner() {
  if [ -d node_modules/mermaid ] && [ -d node_modules/jsdom ]; then
    echo "local"
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    local global_root
    global_root=$(npm root -g 2>/dev/null)
    if [ -n "$global_root" ] && [ -d "$global_root/mermaid" ] && [ -d "$global_root/jsdom" ]; then
      echo "global"
      return 0
    fi
  fi

  if command -v npx >/dev/null 2>&1; then
    echo "npx"
    return 0
  fi

  echo ""
  return 1
}

runner=$(resolve_mermaid_runner)

case "$runner" in
  local)
    output=$(node .claude/scripts/check-md-mermaid.mjs "$file_path" 2>&1)
    status=$?
    ;;
  global)
    global_root=$(npm root -g 2>/dev/null)
    output=$(NODE_PATH="$global_root" node .claude/scripts/check-md-mermaid.mjs "$file_path" 2>&1)
    status=$?
    ;;
  npx)
    output=$(npx --yes --package=mermaid@11.13.0 --package=jsdom node \
      .claude/scripts/check-md-mermaid.mjs "$file_path" 2>&1)
    status=$?
    ;;
  *)
    # No runner available. Fail-open with install hint (do not block on missing tooling).
    printf '[mermaid-check] node / npm / npx いずれも見つかりません。Mermaid 検証を skip しました。\n' >&2
    printf '[mermaid-check] 推奨: npm install -g @mermaid-js/mermaid-cli mermaid jsdom\n' >&2
    printf '[mermaid-check] または project-local: npm install --save-dev mermaid@11.13.0 jsdom\n' >&2
    echo '{}'
    exit 0
    ;;
esac

if [ "$status" -eq 0 ]; then
  echo '{}'
  exit 0
fi

reason=$(printf '[mermaid-check] %s に Mermaid 構文エラーが検出されました。修正してください。\n\n%s\n\n[hint] 検証が動かない場合は `npm install -g mermaid jsdom` (global) または `npm install --save-dev mermaid@11.13.0 jsdom` (project-local) で事前 install すると高速化・オフライン化できます。\n' \
  "$file_path" "$output")
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
