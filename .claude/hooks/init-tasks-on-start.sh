#!/usr/bin/env bash
# init-tasks-on-start.sh — SessionStart hook
#
# 役割:
#   セッション開始時に docs/tasks/ docs/draft/ が未整備なら自動でテンプレ展開する。
#   既存ファイルは触らない。失敗してもセッションをブロックしない。
#
# 設計:
#   - quiet モードで init-tasks.sh を呼ぶ
#   - exit 0 を強制（fail-open）

set -u

# プロジェクト直下で実行
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
fi

# init-tasks.sh が見つかれば実行
if [ -f .claude/scripts/init-tasks.sh ]; then
  bash .claude/scripts/init-tasks.sh --quiet 2>/dev/null || true
fi

exit 0
