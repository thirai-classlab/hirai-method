#!/usr/bin/env bash
# 平井メソッド (hirai-method) — robust installer
#
# Usage:
#   ./install.sh <target-project-dir> [--update] [--force] [--dry-run] [--no-mcp] [--no-docs]
#
# Modes:
#   (default)  : 新規 install。既存 .claude / CLAUDE.md は .bak タイムスタンプ付きで退避。
#                CLAUDE.md は CLAUDE.md.template として配置（user が <...> placeholder を埋める）。
#   --update   : 既存 .claude/ を退避せず rsync で増分上書き。state dir / settings.local.json は保持。
#                CLAUDE.md / .mcp.json / .gitignore は触らない (既存保護)。
#   --force    : 既存 .claude / CLAUDE.md を backup せず上書き。CLAUDE.md は placeholder 入りで上書き。
#   --dry-run  : 実行内容を表示するのみ (rsync -n + 各 cp / mkdir を echo)。
#   --no-mcp   : .mcp.json を配置しない (Serena 不要な project)。
#   --no-docs  : docs/tasks/, docs/draft/ の templates 配置を skip。
#
# Exclude (state / user-local):
#   .gateguard-state/ .taskguard-state/ .confidence-gate-state/ .failure-window/
#   .agent-markers/ .context-budget-state/ .improvement-proposal-state/ .workflow-state/
#   settings.local.json settings.local.example.json bash-whitelist-requests/ worktrees/
#
# Dependencies: rsync, bash 4+
#
# ============================================================
# WARNING: cross-repo execution restriction
# ============================================================
# This script is a cross-repo write operation
# (writes from this repo into an external target project directory).
# Claude Code agent context cannot execute this — sandbox + delegation-guard
# 二重制約 により cross-repo write は denied される。
#
# **user manual (terminal) 実行のみ可能** です。
# (agent / subagent / hook bypass env いずれも回避不可)
#
# 同様に `--update <target>` mode (既存 .claude/ への増分上書き) も
# user manual (terminal) 実行のみ可能 です。
#
# 詳細: .claude/rules/development-process.md §「cross-repo write 例外」を参照
# ============================================================

set -euo pipefail

# ============================================================
# arg parse
# ============================================================
TARGET=""
MODE="install"          # install / update / force
DRY_RUN=false
WITH_MCP=true
WITH_DOCS=true

for arg in "$@"; do
  case "$arg" in
    --update)   MODE="update" ;;
    --force)    MODE="force"  ;;
    --dry-run)  DRY_RUN=true  ;;
    --no-mcp)   WITH_MCP=false ;;
    --no-docs)  WITH_DOCS=false ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    -*)
      echo "[install] unknown option: $arg" >&2
      exit 64
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$arg"
      else
        echo "[install] too many positional args: $arg" >&2
        exit 64
      fi
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "usage: ./install.sh <target-project-dir> [--update|--force|--dry-run|--no-mcp|--no-docs]" >&2
  exit 64
fi

if [[ ! -d "$TARGET" ]]; then
  echo "[install] error: '$TARGET' is not a directory" >&2
  exit 64
fi

# absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "$TARGET" && pwd)"

if [[ "$SCRIPT_DIR" == "$TARGET" ]]; then
  echo "[install] error: target equals source ($SCRIPT_DIR). Run from harness repo, install into another dir." >&2
  exit 64
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "[install] error: rsync not found. Install rsync first (macOS: brew install rsync, Debian: apt install rsync)." >&2
  exit 69
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
echo "[install] source : $SCRIPT_DIR"
echo "[install] target : $TARGET"
echo "[install] mode   : $MODE  (dry-run=$DRY_RUN, with-mcp=$WITH_MCP, with-docs=$WITH_DOCS)"
echo ""

# helper: run or echo (dry-run aware)
run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# ============================================================
# rsync excludes (state / user-local)
# ============================================================
RSYNC_EXCLUDES=(
  --exclude=.gateguard-state/
  --exclude=.taskguard-state/
  --exclude=.confidence-gate-state/
  --exclude=.failure-window/
  --exclude=.agent-markers/
  --exclude=.context-budget-state/
  --exclude=.improvement-proposal-state/
  --exclude=.workflow-state/
  --exclude=settings.local.json
  --exclude=settings.local.example.json
  --exclude=bash-whitelist-requests/
  --exclude=worktrees/
)

# ============================================================
# 1. .claude/ install
# ============================================================
case "$MODE" in
  install)
    if [[ -d "$TARGET/.claude" ]]; then
      echo "[install] existing .claude detected → backup to .claude.bak.$STAMP"
      run "mv '$TARGET/.claude' '$TARGET/.claude.bak.$STAMP'"
    fi
    echo "[install] rsync .claude/ → $TARGET/.claude/"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  update)
    if [[ ! -d "$TARGET/.claude" ]]; then
      echo "[install] error: --update requires existing $TARGET/.claude. Use default mode for fresh install." >&2
      exit 64
    fi
    echo "[install] rsync (increment) .claude/ → $TARGET/.claude/  (preserving state dirs / settings.local.json)"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  force)
    if [[ -d "$TARGET/.claude" ]]; then
      echo "[install] WARN: --force will OVERWRITE existing .claude (no backup)"
      run "rm -rf '$TARGET/.claude'"
    fi
    echo "[install] rsync .claude/ → $TARGET/.claude/"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
esac

# ============================================================
# 2. CLAUDE.md (template として配置、既存は保護)
# ============================================================
if [[ "$MODE" == "update" ]]; then
  echo "[install] (update mode) CLAUDE.md は触らない"
else
  if [[ -f "$TARGET/CLAUDE.md" ]]; then
    if [[ "$MODE" == "force" ]]; then
      echo "[install] WARN: --force overwriting $TARGET/CLAUDE.md (no backup)"
      run "cp '$SCRIPT_DIR/CLAUDE.md' '$TARGET/CLAUDE.md'"
    else
      echo "[install] existing CLAUDE.md → backup to CLAUDE.md.bak.$STAMP, install as CLAUDE.md.template"
      run "mv '$TARGET/CLAUDE.md' '$TARGET/CLAUDE.md.bak.$STAMP'"
      run "cp '$SCRIPT_DIR/CLAUDE.md' '$TARGET/CLAUDE.md.template'"
    fi
  else
    echo "[install] copying CLAUDE.md → $TARGET/CLAUDE.md.template (edit <...> placeholders then rename to CLAUDE.md)"
    run "cp '$SCRIPT_DIR/CLAUDE.md' '$TARGET/CLAUDE.md.template'"
  fi
fi

# ============================================================
# 3. .mcp.json (Serena MCP は /save-state /pm-start に必須)
# ============================================================
if $WITH_MCP; then
  if [[ -f "$TARGET/.mcp.json" ]]; then
    echo "[install] existing .mcp.json detected → keep as-is (manual merge if you need harness defaults)"
  else
    echo "[install] copying .mcp.json → $TARGET/.mcp.json"
    run "cp '$SCRIPT_DIR/.mcp.json' '$TARGET/.mcp.json'"
  fi
else
  echo "[install] (--no-mcp) skip .mcp.json"
fi

# ============================================================
# 4. .gitignore (既存があれば merge、無ければ新規)
# ============================================================
if [[ -f "$TARGET/.gitignore" ]]; then
  # 既存に harness state 除外行が無ければ追記
  if grep -q '.claude/.gateguard-state' "$TARGET/.gitignore" 2>/dev/null; then
    echo "[install] $TARGET/.gitignore already contains harness state ignores → skip"
  else
    echo "[install] appending harness state ignores to existing $TARGET/.gitignore"
    if $DRY_RUN; then
      echo "[dry-run] cat >> $TARGET/.gitignore  (harness state block)"
    else
      cat >> "$TARGET/.gitignore" <<'GITIGNORE_HARNESS'

# === HIRAI Method harness state (auto-appended by install.sh) ===
.claude/.gateguard-state/
.claude/.taskguard-state/
.claude/.confidence-gate-state/
.claude/.failure-window/
.claude/.confidence-bypass.cleared
.claude/.confidence-bypass.log
.claude/.agent-markers/
.claude/.context-budget-state/
.claude/.improvement-proposal-state/
.claude/.workflow-state/
.claude/settings.local.json
.claude/worktrees/
.claude/bash-whitelist-requests/
GITIGNORE_HARNESS
    fi
  fi
else
  echo "[install] copying .gitignore → $TARGET/.gitignore"
  run "cp '$SCRIPT_DIR/.gitignore' '$TARGET/.gitignore'"
fi

# ============================================================
# 5. docs/tasks/ docs/draft/ (templates から初期化、既存は保護)
# ============================================================
if $WITH_DOCS; then
  run "mkdir -p '$TARGET/docs/tasks' '$TARGET/docs/draft'"
  for f in list.md parking-lot.md _TASK_TEMPLATE.md; do
    src="$SCRIPT_DIR/.claude/templates/docs/tasks/$f"
    dst="$TARGET/docs/tasks/$f"
    if [[ -f "$dst" ]]; then
      echo "[install] $dst exists → skip"
    elif [[ -f "$src" ]]; then
      echo "[install] copy template $f → docs/tasks/"
      run "cp '$src' '$dst'"
    fi
  done
  src="$SCRIPT_DIR/.claude/templates/docs/draft/_DRAFT_TEMPLATE.md"
  dst="$TARGET/docs/draft/_DRAFT_TEMPLATE.md"
  if [[ -f "$dst" ]]; then
    echo "[install] $dst exists → skip"
  elif [[ -f "$src" ]]; then
    echo "[install] copy template _DRAFT_TEMPLATE.md → docs/draft/"
    run "cp '$src' '$dst'"
  fi
else
  echo "[install] (--no-docs) skip docs/tasks/ docs/draft/ templates"
fi

# ============================================================
# 6. hook 実行権限 (rsync -a で保持されるが、念のため)
# ============================================================
if [[ "$MODE" != "update" ]] || true; then
  if $DRY_RUN; then
    echo "[dry-run] chmod +x .claude/hooks/*.sh .claude/scripts/*.{sh,py,mjs}"
  else
    find "$TARGET/.claude/hooks" -maxdepth 2 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
    find "$TARGET/.claude/scripts" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \) -exec chmod +x {} + 2>/dev/null || true
  fi
fi

# ============================================================
# 7. 検証 (config-loader 動作確認)
# ============================================================
if ! $DRY_RUN; then
  echo ""
  echo "[install] verifying config-loader.sh..."
  if ( cd "$TARGET" && bash -c 'source .claude/hooks/lib/config-loader.sh && [[ -n "$HC_PROTECTED_PATHS" ]] && [[ -n "$HC_TASK_DIR" ]]' ); then
    echo "[install] config-loader OK (HC_PROTECTED_PATHS / HC_TASK_DIR loaded)"
  else
    echo "[install] WARN: config-loader.sh did not export expected vars. Check $TARGET/.claude/harness-config.yml" >&2
  fi
fi

# ============================================================
# 8. summary
# ============================================================
cat <<EOF

[install] DONE ($MODE mode).

Counts at target:
  agents:   $(find "$TARGET/.claude/agents" -maxdepth 2 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  skills:   $(find "$TARGET/.claude/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  commands: $(find "$TARGET/.claude/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  hooks:    $(find "$TARGET/.claude/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
  rules:    $(find "$TARGET/.claude/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

Next steps:
  1. cd $TARGET
  2. \$EDITOR .claude/harness-config.yml         # protected_paths / task_dir / ... を project に合わせる
  3. \$EDITOR .claude/bash-whitelist.txt         # 使う CLI (pnpm/poetry/cargo/...) を追記
  4. mv CLAUDE.md.template CLAUDE.md && \$EDITOR CLAUDE.md   # <...> placeholders を埋める
  5. (recommended) git init                                  # observe.sh の project hash 検出を有効化
  6. Claude Code session 起動 → /init-tasks → /mode loop

Documentation:
  - README.md         (採用 5 ステップ)
  - docs/INVENTORY.md (全構成要素の Path 表)
  - docs/PORTABILITY.md (他リポへの移植仕様)
  - docs/SELF_IMPROVEMENT.md (F1-F3 + L1-L5)
EOF
