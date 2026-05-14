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
# 関連:
#   - スクリプト: .claude/scripts/check-md-mermaid.mjs
#   - スキル定義: .claude/skills/check-md-mermaid/SKILL.md

set -u

input=$(cat)

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

# Run validator. Use local install if present, else fall back to npx.
if [ -d node_modules/mermaid ] && [ -d node_modules/jsdom ]; then
  output=$(node .claude/scripts/check-md-mermaid.mjs "$file_path" 2>&1)
  status=$?
else
  output=$(npx --yes --package=mermaid@11.13.0 --package=jsdom node \
    .claude/scripts/check-md-mermaid.mjs "$file_path" 2>&1)
  status=$?
fi

if [ "$status" -eq 0 ]; then
  echo '{}'
  exit 0
fi

reason=$(printf '[mermaid-check] %s に Mermaid 構文エラーが検出されました。修正してください。\n\n%s' \
  "$file_path" "$output")
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
