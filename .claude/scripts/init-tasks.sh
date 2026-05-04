#!/usr/bin/env bash
# init-tasks.sh — docs/tasks/ と docs/draft/ をテンプレートから自動初期化
#
# 役割:
#   - docs/tasks/list.md, parking-lot.md, _TASK_TEMPLATE.md
#   - docs/draft/_DRAFT_TEMPLATE.md
#   を **既存ファイルを壊さずに** 不足分のみ作成する。
#
# 使い方:
#   bash .claude/scripts/init-tasks.sh           # 不足分のみ作成
#   bash .claude/scripts/init-tasks.sh --quiet   # 出力なし（hook 用）
#   bash .claude/scripts/init-tasks.sh --force   # 全テンプレを上書き（破壊的、確認必須）
#
# 設計:
#   - 既存ファイルは絶対に上書きしない（--force 指定時のみ）
#   - テンプレ source は `.claude/templates/docs/...` 配下
#   - サブエージェント中でも安全（冪等）
#   - jq / git に依存しない（純 bash）

set -u

QUIET=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

log() {
  if [ "$QUIET" -eq 0 ]; then
    printf '%s\n' "$1"
  fi
}

# 自分のスクリプト位置からプロジェクトルートを推定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ ! -d "$TEMPLATES_DIR" ]; then
  log "[init-tasks] ❌ templates ディレクトリが見つかりません: $TEMPLATES_DIR"
  exit 1
fi

cd "$PROJECT_ROOT" || exit 1

# config 読み込み (HC_TASK_DIR / HC_DRAFT_DIR 等)
if [ -f .claude/hooks/lib/config-loader.sh ]; then
  # shellcheck source=../hooks/lib/config-loader.sh
  source .claude/hooks/lib/config-loader.sh
else
  # 旧来 fallback
  HC_TASK_DIR="docs/tasks"
  HC_DRAFT_DIR="docs/draft"
fi

mkdir -p "$HC_TASK_DIR" "$HC_DRAFT_DIR" 2>/dev/null

copy_if_missing() {
  local src="$1"
  local dst="$2"
  local label="$3"

  if [ -f "$dst" ] && [ "$FORCE" -eq 0 ]; then
    log "[init-tasks] = 既存温存: $dst ($label)"
    return 0
  fi

  if [ ! -f "$src" ]; then
    log "[init-tasks] ❌ template 不在: $src"
    return 1
  fi

  cp "$src" "$dst"
  if [ "$FORCE" -eq 1 ]; then
    log "[init-tasks] ⚠ 上書き: $dst ($label)"
  else
    log "[init-tasks] ✓ 作成: $dst ($label)"
  fi
}

created=0

if [ ! -f "$HC_TASK_DIR/list.md" ] || [ "$FORCE" -eq 1 ]; then
  copy_if_missing "$TEMPLATES_DIR/docs/tasks/list.md" "$HC_TASK_DIR/list.md" "タスク台帳"
  created=$((created+1))
fi

if [ ! -f "$HC_TASK_DIR/parking-lot.md" ] || [ "$FORCE" -eq 1 ]; then
  copy_if_missing "$TEMPLATES_DIR/docs/tasks/parking-lot.md" "$HC_TASK_DIR/parking-lot.md" "Parking Lot"
  created=$((created+1))
fi

if [ ! -f "$HC_TASK_DIR/_TASK_TEMPLATE.md" ] || [ "$FORCE" -eq 1 ]; then
  copy_if_missing "$TEMPLATES_DIR/docs/tasks/_TASK_TEMPLATE.md" "$HC_TASK_DIR/_TASK_TEMPLATE.md" "個別タスクひな型"
  created=$((created+1))
fi

if [ ! -f "$HC_DRAFT_DIR/_DRAFT_TEMPLATE.md" ] || [ "$FORCE" -eq 1 ]; then
  copy_if_missing "$TEMPLATES_DIR/docs/draft/_DRAFT_TEMPLATE.md" "$HC_DRAFT_DIR/_DRAFT_TEMPLATE.md" "設計 draft ひな型"
  created=$((created+1))
fi

if [ "$created" -eq 0 ]; then
  log "[init-tasks] 既に整備済（4 ファイル全て存在）"
else
  log "[init-tasks] 完了（$created 件処理）"
fi

exit 0
