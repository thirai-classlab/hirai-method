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

# config 読み込み (HC_* 変数 + is_feature_enabled 関数 export、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled init_tasks_on_start; then
  exit 0   # feature OFF で no-op
fi

# プロジェクト直下で実行
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || true
fi

# init-tasks.sh が見つかれば実行
if [ -f .claude/scripts/init-tasks.sh ]; then
  bash .claude/scripts/init-tasks.sh --quiet 2>/dev/null || true
fi

exit 0
