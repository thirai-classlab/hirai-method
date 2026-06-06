#!/usr/bin/env bash
# 平井メソッド (hirai-method) — robust installer
#
# Usage:
#   ./install.sh <target-project-dir> [--update|--force|--overwrite-all] [--dry-run] [--no-mcp] [--no-docs]
#
# Modes (--update / --force / --overwrite-all are mutually exclusive):
#   (default)  : 新規 install。既存 .claude / CLAUDE.md は .bak タイムスタンプ付きで退避。
#                CLAUDE.md は CLAUDE.md.template として配置（user が <...> placeholder を埋める）。
#   --update   : 既存 .claude/ を退避せず rsync で増分上書き。state dir / settings.local.json は保持。
#                CLAUDE.md / .mcp.json / .gitignore は触らない (既存保護)。
#                完了時に sync 変更 file 一覧 + 分離 commit 案内を出力 (task-58 G1)。
#   --commit   : (--update と併用、opt-in) sync 対象 .claude/ path のみ git add + chore(harness): sync で
#                自動 commit する。project file (root README.md 等) は触らない。git reset 禁止 (HIGH 教訓)。
#                非 git target なら commit skip + WARN (task-58 G1)。
#   --force    : 既存 .claude / CLAUDE.md を backup せず上書き。CLAUDE.md は placeholder 入りで上書き。
#   --overwrite-all : (task-79) drift した target を SSoT へ強制リセットする全上書き mode。
#                既存 .claude/ を rsync で上書きするが **settings.local.json のみ** 温存し、それ以外
#                (settings.json / harness-config.local.yml / state dir 群 / worktrees) も source で上書き。
#                `--delete` は使わない (= 上書きのみ、target 独自 file は残す)。CLAUDE.md / .mcp.json /
#                .gitignore は --force 準拠。注意: target の local override は失われる (settings.local.json のみ残る)。
#   --dry-run  : 実行内容を表示するのみ (rsync -n + 各 cp / mkdir を echo)。
#   --no-mcp   : .mcp.json を配置しない (Serena 不要な project)。
#   --no-docs  : docs/tasks/, docs/draft/ の templates 配置を skip。
#
# Exclude (state / user-local):
#   .gateguard-state/ .taskguard-state/ .confidence-gate-state/ .failure-window/
#   .agent-markers/ .context-budget-state/ .improvement-proposal-state/ .workflow-state/
#   settings.local.json settings.local.example.json bash-whitelist-requests/ worktrees/ project-rules/ (task-82, project-owned)
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
# 同様に `--update` / `--overwrite-all <target>` mode (既存 .claude/ への上書き) も
# user manual (terminal) 実行のみ可能 です。
#
# 詳細: .claude/rules/development-process.md §「cross-repo write 例外」を参照
# ============================================================

set -euo pipefail

# ============================================================
# arg parse
# ============================================================
TARGET=""
MODE="install"          # install / update / force / overwrite-all
DRY_RUN=false
WITH_MCP=true
WITH_DOCS=true
COMMIT_AFTER_SYNC=false  # --commit flag (task-58 G1, opt-in for --update only)

# M-1: detect conflicting mode flags. --update / --force / --overwrite-all each set
# MODE; specifying more than one (or repeating one) would silently last-wins into an
# unintended mode (e.g. --update --force → force rm -rf). Track whether MODE was
# already chosen and abort instead of guessing. (task-79: --overwrite-all joins the
# 3-way mutual exclusion.)
MODE_SET=false
for arg in "$@"; do
  case "$arg" in
    --update|--force|--overwrite-all)
      if $MODE_SET; then
        echo "[install] error: conflicting mode flags (--update / --force / --overwrite-all are mutually exclusive — give at most one)" >&2
        exit 64
      fi
      MODE_SET=true
      case "$arg" in
        --update)        MODE="update" ;;
        --force)         MODE="force" ;;
        --overwrite-all) MODE="overwrite-all" ;;
      esac
      ;;
    --commit)   COMMIT_AFTER_SYNC=true ;;
    --dry-run)  DRY_RUN=true  ;;
    --no-mcp)   WITH_MCP=false ;;
    --no-docs)  WITH_DOCS=false ;;
    -h|--help)
      # L-2: print the full header comment block including the cross-repo WARNING
      # (ends at the closing ===== of the WARNING box before `set -euo pipefail`;
      # task-79 added 4 mode-doc lines so the box now ends at line 48).
      sed -n '2,48p' "$0"
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
  echo "usage: ./install.sh <target-project-dir> [--update [--commit]|--force|--overwrite-all|--dry-run|--no-mcp|--no-docs]" >&2
  exit 64
fi

# --commit は --update mode 専用 (task-58 G1)
if $COMMIT_AFTER_SYNC && [[ "$MODE" != "update" ]]; then
  echo "[install] error: --commit requires --update mode" >&2
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

# ============================================================
# dirty-tree safety: --update / --force / --overwrite-all 前に target の未 commit 変更を warn
# (task-55: user 無警告で上書き rsync する事故を防ぐ。block ではなく warn のみ)
# (task-79: --overwrite-all は local override も上書きするため warn は特に重要)
# ============================================================
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  if command -v git >/dev/null 2>&1 && [[ -d "$TARGET/.git" ]]; then
    DIRTY=$(cd "$TARGET" && git status --short 2>/dev/null | head -20)
    if [[ -n "$DIRTY" ]]; then
      echo "[install] WARN: target has uncommitted changes (showing up to 20 lines):"
      echo "$DIRTY" | sed 's/^/  /'
      echo "[install] WARN: rsync is about to overwrite .claude/ — review or commit/stash first."
      echo "[install] WARN: continuing in 3s (Ctrl-C to abort)..."
      sleep 3 || true
    fi
  fi
fi

# ============================================================
# migration helper: project 固有 override が SSoT yml に直接書かれている場合の案内
# (task-55: docs_approved_dir 等が SSoT yml に書かれていると --update で巻き戻る潜在事故。
#  自動移動はしない、案内のみ。違反が見つかったら user が手で local.yml へ移行する)
# (task-79: --overwrite-all は最も破壊的な mode (local override も上書き) なので、
#  SSoT drift 案内が出ない非対称を解消するため対象に含める。案内のみで自動移動はしない。)
# ============================================================
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  TARGET_SSOT="$TARGET/.claude/harness-config.yml"
  SRC_SSOT="$SCRIPT_DIR/.claude/harness-config.yml"
  if [[ -f "$TARGET_SSOT" && -f "$SRC_SSOT" ]]; then
    # 比較対象 key (project 固有 override が起こりやすい代表例)
    for key in docs_approved_dir task_dir draft_dir protected_paths; do
      # `|| true` で fail-open: target yml に該当 key が不在で grep exit 1 → pipefail
      # で script abort する事故を防ぐ (task-42 後発見、2026-05-28、classlab-weekly-news
      # 同期失敗を契機)。key 不在は「project 固有 override なし」を意味するため、空文字で
      # 続行が正しい挙動 (該当 if 文は -n "$tgt_val" で空時 skip される)。
      tgt_val=$(grep -E "^${key}:" "$TARGET_SSOT" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*$//" || true)
      src_val=$(grep -E "^${key}:" "$SRC_SSOT" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*$//" || true)
      if [[ -n "$tgt_val" && "$tgt_val" != "$src_val" ]]; then
        echo "[install] MIGRATE: $TARGET_SSOT has project-specific '$key: $tgt_val' (SSoT default: '$src_val')."
        echo "[install] MIGRATE: --update will overwrite SSoT yml. Move this value to .claude/harness-config.local.yml to preserve it across updates."
      fi
    done
    unset key tgt_val src_val
  fi
  unset TARGET_SSOT SRC_SSOT
fi


# helper: run or echo (dry-run aware)
# H-1: array-based exec — no eval/word-split/glob re-expansion. Each arg passed
# verbatim, safe for paths containing spaces / quotes / $ / glob chars.
# dry-run prints %q-quoted form so the displayed command is copy-paste safe.
run() {
  if $DRY_RUN; then
    printf '[dry-run]'
    printf ' %q' "$@"
    echo
  else
    "$@"
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
  --exclude=settings.json
  --exclude=settings.local.json
  --exclude=settings.local.example.json
  --exclude=harness-config.local.yml
  --exclude=bash-whitelist-requests/
  --exclude=worktrees/
  --exclude=project-rules/
)

# RSYNC_EXCLUDES_MINIMAL (task-79、--overwrite-all 専用):
# 「全上書き」mode 用。machine-local な settings.local.json **のみ** を温存し、
# それ以外 (settings.json / harness-config.local.yml / state dir 群 / worktrees) は
# すべて source の状態で上書きする (drift した target を SSoT へ強制リセットする用途)。
# `--delete` は使わない (= 上書きのみ、target にしかない file は残す)。
RSYNC_EXCLUDES_MINIMAL=(
  --exclude=settings.local.json
  --exclude=project-rules/
)

# NOTE (task-82): `.claude/project-rules/<name>.md` は **project 所有** (consuming repo の
# harness rule override / 追補)。harness 7 rule (`.claude/rules/*.md`) から `@import` され、
# rsync で上書きすると project 固有編集が消失するため両 exclude set に project-rules/ を含める
# (overwrite-all でも project-rules は守る = project の override は drift リセット対象外)。
# 不在 target には下記「project-rules create-if-absent」block が空テンプレを配置する。

# NOTE (task-71 H2、2026-06-02): `settings.json` は exclude する。task-71 で settings.json は
# permissions verbatim 同梱の generated artifact (harness 本体は harness-dev preset の
# permissions + dispatcher 配線) になったため、rsync で配布すると consuming repo の repo 固有
# permissions / preset を上書きする回帰になる。dispatcher 機能本体 (wrapper 群 / manifest /
# generate-settings.sh / dispatcher-core.sh) は `.claude/` 配下なので引き続き配布される。
# consuming repo は `bash .claude/scripts/generate-settings.sh --out .claude/settings.json` で
# 自リポの permissions + 配布済 manifest から settings.json を再生成して dispatcher 配線を採用する。

# NOTE (task-51 A 案、2026-05-28): `.claude/rules-details/` (Layer B 詳細規範) は
# 意図的に exclude していない。Claude Code は `.claude/rules/` のみを startup 注入する
# (公式 doc: code.claude.com/docs/en/memory.md) ため、Layer B を別 dir に置くことで
# context bloat を回避する設計。rsync -a で `.claude/rules-details/` 配下も自動同期
# されるため 4 リポでも Layer A↔B link が保たれる。SSoT: `.claude/rules-details/README.md`。

# ============================================================
# 1. .claude/ install
# ============================================================
case "$MODE" in
  install)
    if [[ -d "$TARGET/.claude" ]]; then
      echo "[install] existing .claude detected → backup to .claude.bak.$STAMP"
      run mv "$TARGET/.claude" "$TARGET/.claude.bak.$STAMP"
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
      run rm -rf "$TARGET/.claude"
    fi
    echo "[install] rsync .claude/ → $TARGET/.claude/"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  overwrite-all)
    # task-79: 全上書き mode。settings.local.json のみ温存し、それ以外 (settings.json /
    # harness-config.local.yml / state dir / worktrees) も source で上書きする。
    # `--delete` は使わない → target にしかない file は残す (上書きのみ)。
    if [[ ! -d "$TARGET/.claude" ]]; then
      echo "[install] error: --overwrite-all requires existing $TARGET/.claude. Use default mode for fresh install." >&2
      exit 64
    fi
    echo "[install] WARN: --overwrite-all overwrites ALL local overrides (settings.json / harness-config.local.yml / state dirs)"
    echo "[install] WARN: only settings.local.json is preserved. No --delete (target-only files are kept)."
    echo "[install] rsync (overwrite-all) .claude/ → $TARGET/.claude/  (preserving settings.local.json only)"
    if $DRY_RUN; then
      # `| head -30` closes the pipe early; under set -euo pipefail rsync's SIGPIPE
      # (exit 141) would propagate and abort the script (CLAUDE.md HIGH lesson:
      # SIGPIPE → pipefail → errexit → silent death). `|| true` keeps dry-run preview
      # tolerant when the change set exceeds 30 lines (e.g. state dirs under overwrite-all).
      rsync -an "${RSYNC_EXCLUDES_MINIMAL[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30 || true
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES_MINIMAL[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
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
    if [[ "$MODE" == "force" || "$MODE" == "overwrite-all" ]]; then
      echo "[install] WARN: --$MODE overwriting $TARGET/CLAUDE.md (no backup)"
      run cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
    else
      echo "[install] existing CLAUDE.md → backup to CLAUDE.md.bak.$STAMP, install as CLAUDE.md.template"
      run mv "$TARGET/CLAUDE.md" "$TARGET/CLAUDE.md.bak.$STAMP"
      run cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md.template"
    fi
  else
    echo "[install] copying CLAUDE.md → $TARGET/CLAUDE.md.template (edit <...> placeholders then rename to CLAUDE.md)"
    run cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md.template"
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
    run cp "$SCRIPT_DIR/.mcp.json" "$TARGET/.mcp.json"
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
.claude/settings.generated.preview.json
.claude/worktrees/
.claude/bash-whitelist-requests/
GITIGNORE_HARNESS
    fi
  fi
else
  echo "[install] copying .gitignore → $TARGET/.gitignore"
  run cp "$SCRIPT_DIR/.gitignore" "$TARGET/.gitignore"
fi

# ============================================================
# 5. docs/tasks/ docs/draft/ (templates から初期化、既存は保護)
# ============================================================
if $WITH_DOCS; then
  run mkdir -p "$TARGET/docs/tasks" "$TARGET/docs/draft"
  for f in list.md parking-lot.md _TASK_TEMPLATE.md; do
    src="$SCRIPT_DIR/.claude/templates/docs/tasks/$f"
    dst="$TARGET/docs/tasks/$f"
    if [[ -f "$dst" ]]; then
      echo "[install] $dst exists → skip"
    elif [[ -f "$src" ]]; then
      echo "[install] copy template $f → docs/tasks/"
      run cp "$src" "$dst"
    fi
  done
  src="$SCRIPT_DIR/.claude/templates/docs/draft/_DRAFT_TEMPLATE.md"
  dst="$TARGET/docs/draft/_DRAFT_TEMPLATE.md"
  if [[ -f "$dst" ]]; then
    echo "[install] $dst exists → skip"
  elif [[ -f "$src" ]]; then
    echo "[install] copy template _DRAFT_TEMPLATE.md → docs/draft/"
    run cp "$src" "$dst"
  fi
else
  echo "[install] (--no-docs) skip docs/tasks/ docs/draft/ templates"
fi

# ============================================================
# 5.5. project-rules/ create-if-absent (task-82、全 mode 共通、project 所有保護)
# ============================================================
# `.claude/project-rules/<name>.md` は consuming repo の harness rule override / 追補を書く
# **project 所有** file。harness 7 rule (`.claude/rules/*.md`) から `@import` され、harness
# rule の後に結合 load される。RSYNC_EXCLUDES / RSYNC_EXCLUDES_MINIMAL の `--exclude=project-rules/`
# により rsync では一切 touch しない (= 既存 project 編集を上書きしない、保護)。
# ここで「なければ空テンプレを配置・あれば skip」する冪等 cp で初回雛形を提供する
# (docs/tasks templates と同じ create-if-absent ロジック)。全 mode (install/update/force/
# overwrite-all) で適用 — project-rules は project 所有のため force/overwrite-all でも上書きしない。
PROJECT_RULES_SRC="$SCRIPT_DIR/.claude/project-rules"
PROJECT_RULES_DST="$TARGET/.claude/project-rules"
if [[ -d "$PROJECT_RULES_SRC" ]]; then
  run mkdir -p "$PROJECT_RULES_DST"
  for src in "$PROJECT_RULES_SRC"/*.md; do
    [[ -e "$src" ]] || continue   # nullglob 非依存 (no-match で literal glob を skip)
    base="$(basename "$src")"
    dst="$PROJECT_RULES_DST/$base"
    if [[ -f "$dst" ]]; then
      echo "[install] project-rules/$base exists → skip (project-owned, protected)"
    else
      echo "[install] copy project-rules template $base → .claude/project-rules/"
      run cp "$src" "$dst"
    fi
  done
  unset src base dst
fi
unset PROJECT_RULES_SRC PROJECT_RULES_DST

# ============================================================
# 6. hook 実行権限 (rsync -a で保持されるが、念のため)
# ============================================================
# L-4: chmod runs in ALL modes (install / update / force). The previous
# `if [[ "$MODE" != "update" ]] || true` was always true (dead condition); we want
# exec bits restored even on --update since rsync can drop them via staging, so the
# guard is removed and chmod is unconditional.
if $DRY_RUN; then
  echo "[dry-run] chmod +x .claude/hooks/*.sh .claude/scripts/*.{sh,py,mjs}"
else
  find "$TARGET/.claude/hooks" -maxdepth 2 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
  find "$TARGET/.claude/scripts" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \) -exec chmod +x {} + 2>/dev/null || true
fi

# ============================================================
# 6.3. settings.json 自動再生成 (statusLine / dispatcher 配線同期、task-80)
# ============================================================
# task-71 H2 で settings.json は rsync exclude (repo 固有 permissions 保護) になったため、
# statusLine / dispatcher 配線が consuming repo に同期されない問題があった (user 報告)。
# sync mode (update / force / overwrite-all) で rsync 後に generate-settings.sh を自動実行し、
# 既存 settings.json の permissions を verbatim 保持したまま statusLine / dispatcher を再配線する。
# fail-open: jq 不在 / generate-settings.sh 不在 / 既存 settings.json 不在 / 再生成失敗は
# WARN or NOTE + skip で install 自体は継続する (permissions 喪失 / die を回避)。
# CLAUDE.md HIGH 教訓: 再生成は subshell ( cd ...; bash ... ) で実行し caller の shell flags
# (set -e 等) に影響させない。
# L-1 保険: subshell に HC_PROJECT_ROOT="$TARGET" を明示注入する。generate-settings.sh の
# resolve_project_root は HC_PROJECT_ROOT を最優先 key とするため、TARGET が git 未 init かつ
# 環境に CLAUDE_PROJECT_DIR が残っている場合でも ROOT が TARGET に固定される (取り違え防止)。
# 挙動不変: 通常 path も ROOT=TARGET のまま (cd "$TARGET" 後の git/pwd も TARGET を指す)。
# mode 別の permissions 帰結 (M-1):
#   update       : 既存 settings.json の permissions を verbatim 保持して再配線。
#   force         : rm -rf .claude で破壊的リセット + settings.json は rsync exclude のため
#                   再生成時には既存不在 → fail-open skip (permissions 保持の前提は成立しない)。
#   overwrite-all : settings.json も source で上書き済のため、ここで保持される permissions は
#                   source 由来 (consuming repo の permissions は失われる = task-79 既定)。
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  GEN_SETTINGS="$TARGET/.claude/scripts/generate-settings.sh"
  LIVE_SETTINGS="$TARGET/.claude/settings.json"
  if ! command -v jq >/dev/null 2>&1; then
    echo "[install] WARN: jq 不在のため settings.json 自動再生成 skip。手動: bash .claude/scripts/generate-settings.sh --out .claude/settings.json" >&2
  elif [[ ! -f "$GEN_SETTINGS" ]]; then
    echo "[install] WARN: generate-settings.sh 不在、settings.json 自動再生成 skip" >&2
  elif [[ ! -f "$LIVE_SETTINGS" ]]; then
    echo "[install] NOTE: 既存 settings.json 不在のため自動再生成 skip (permissions 喪失回避)。新規は手動生成要" >&2
  else
    if ( cd "$TARGET" && HC_PROJECT_ROOT="$TARGET" bash .claude/scripts/generate-settings.sh --out .claude/settings.json ); then
      echo "[install] settings.json 再生成済 (statusLine / dispatcher 配線同期、permissions 保持)"
    else
      echo "[install] WARN: settings.json 自動再生成 失敗 (install は継続)。手動再生成を検討" >&2
    fi
  fi
  unset GEN_SETTINGS LIVE_SETTINGS
fi

# ============================================================
# 6.5. harness_version stamp 書込 (task-56 F)
# ============================================================
# stale-harness-detect.sh (SessionStart hook) が読む同期 stamp。
# `bash install.sh --update <repo>` 実行日 (UTC) を YYYY-MM-DD で
# target の harness-config.yml に書き込む (in-place、portable sed -i 互換)。
# 既存 `harness_version:` 行があれば差し替え、無ければ追記。
# fail-open: stamp 書込失敗は WARN のみで install 自体は継続。
if ! $DRY_RUN; then
  TARGET_HC="$TARGET/.claude/harness-config.yml"
  if [[ -f "$TARGET_HC" ]]; then
    NEW_STAMP="$(date -u +%Y-%m-%d)"
    if grep -qE '^harness_version:' "$TARGET_HC" 2>/dev/null; then
      # 既存 line を置換 (BSD sed / GNU sed 両対応: -i '' / -i バックアップ拡張子なし)
      TMP_HC="$(mktemp /tmp/harness-config.XXXXXX.yml)"
      sed -E "s|^harness_version:.*|harness_version: \"${NEW_STAMP}\"|" "$TARGET_HC" > "$TMP_HC" 2>/dev/null \
        && mv "$TMP_HC" "$TARGET_HC" \
        && echo "[install] harness_version stamp updated -> $NEW_STAMP" \
        || echo "[install] WARN: failed to update harness_version stamp (install continues)" >&2
      rm -f "$TMP_HC" 2>/dev/null || true
    else
      # 未設定なら top に append (insert at top of file)
      {
        echo "# === Harness Version Stamp (task-56 F, install.sh が書込) ==="
        echo "harness_version: \"${NEW_STAMP}\""
        echo ""
        cat "$TARGET_HC"
      } > "${TARGET_HC}.tmp" 2>/dev/null \
        && mv "${TARGET_HC}.tmp" "$TARGET_HC" \
        && echo "[install] harness_version stamp inserted -> $NEW_STAMP" \
        || echo "[install] WARN: failed to insert harness_version stamp (install continues)" >&2
    fi
    unset NEW_STAMP TMP_HC
  fi
  unset TARGET_HC
fi

# ============================================================
# 6.6. harness_npm_version stamp 書込 (task-84 Step 1)
# ============================================================
# stale-harness-detect.sh (SessionStart hook) が npm registry latest と
# semver 比較するための同期 stamp。install.sh 自身の package.json の
# `.version` (semver x.y.z) を target の harness-config.yml に書き込む。
# 既存 `harness_npm_version:` 行があれば差し替え、無ければ追記。
# 既存 date stamp (harness_version) とは独立に併存する。
# fail-safe: package.json 不在 / version 取得不能なら stamp を skip
#            (既存挙動を壊さない)。stamp 書込失敗は WARN のみで install 継続。
if ! $DRY_RUN; then
  TARGET_HC_NPM="$TARGET/.claude/harness-config.yml"
  SRC_PKG="$SCRIPT_DIR/package.json"
  NPM_VER=""
  if [[ -f "$SRC_PKG" ]]; then
    if command -v node >/dev/null 2>&1; then
      # L-2 (task-84 fix): path を JS 文字列へ直接埋め込まず argv 経由で渡す
      # (path injection 回避)。$SRC_PKG にメタ文字が含まれても安全。
      NPM_VER="$(node -e 'try{process.stdout.write(String(require(process.argv[1]).version||""))}catch(e){}' "$SRC_PKG" 2>/dev/null || true)"
    fi
    # node 不在 / 取得失敗時の fallback: grep/sed で "version": "x.y.z" を抽出
    if [[ -z "$NPM_VER" || "$NPM_VER" == "undefined" ]]; then
      NPM_VER="$(grep -E '"version"[[:space:]]*:' "$SRC_PKG" 2>/dev/null \
        | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    fi
  fi
  if [[ -f "$TARGET_HC_NPM" && -n "$NPM_VER" && "$NPM_VER" != "undefined" ]]; then
    if grep -qE '^harness_npm_version:' "$TARGET_HC_NPM" 2>/dev/null; then
      TMP_HC_NPM="$(mktemp /tmp/harness-config-npm.XXXXXX.yml)"
      sed -E "s|^harness_npm_version:.*|harness_npm_version: \"${NPM_VER}\"|" "$TARGET_HC_NPM" > "$TMP_HC_NPM" 2>/dev/null \
        && mv "$TMP_HC_NPM" "$TARGET_HC_NPM" \
        && echo "[install] harness_npm_version stamp updated -> $NPM_VER" \
        || echo "[install] WARN: failed to update harness_npm_version stamp (install continues)" >&2
      rm -f "$TMP_HC_NPM" 2>/dev/null || true
    else
      {
        echo "# === Harness NPM Version Stamp (task-84, install.sh が書込) ==="
        echo "harness_npm_version: \"${NPM_VER}\""
        echo ""
        cat "$TARGET_HC_NPM"
      } > "${TARGET_HC_NPM}.tmp" 2>/dev/null \
        && mv "${TARGET_HC_NPM}.tmp" "$TARGET_HC_NPM" \
        && echo "[install] harness_npm_version stamp inserted -> $NPM_VER" \
        || echo "[install] WARN: failed to insert harness_npm_version stamp (install continues)" >&2
    fi
  elif [[ -f "$TARGET_HC_NPM" ]]; then
    echo "[install] NOTE: package.json version 取得不能のため harness_npm_version stamp skip (fail-safe)" >&2
  fi
  unset TARGET_HC_NPM SRC_PKG NPM_VER TMP_HC_NPM
fi

# ============================================================
# 6.7. sync drift 案内 + --commit による分離 commit (task-58 G1)
# ============================================================
# install.sh --update が SSoT を同期した直後、target 側 .claude/ 配下の
# git diff を検出して user に「分離 commit せよ」案内 + 変更 file 一覧を出力。
# --commit flag 併用時のみ harness-sync 対象 path のみ git add + 単独 commit。
# project file (root README.md 等) は完全に触らない。git reset 禁止 (HIGH 教訓)。
# 設計: docs/draft/harness-sync-uncommitted-drift.md (採用案 C ハイブリッド)
if [[ "$MODE" == "update" ]] && ! $DRY_RUN; then
  if command -v git >/dev/null 2>&1 && [[ -d "$TARGET/.git" ]]; then
    # .claude/ 配下の変更 path を git status --porcelain で安全に列挙
    # (rename 検出は対象外、付属 path のみ抽出)
    SYNC_CHANGES=$(cd "$TARGET" && git status --porcelain -- .claude/ 2>/dev/null | awk '{
      # XY status (2 char) + space + path. rename は " -> " で arrow 後ろを採用
      sub(/^.. /, "")
      if (match($0, / -> /)) {
        print substr($0, RSTART + 4)
      } else {
        print
      }
    }')
    if [[ -n "$SYNC_CHANGES" ]]; then
      SYNC_COUNT=$(printf '%s\n' "$SYNC_CHANGES" | wc -l | tr -d ' ')
      echo ""
      echo "[install] === harness sync drift detected ==="
      echo "[install] ${SYNC_COUNT} file(s) under .claude/ changed by this --update:"
      printf '%s\n' "$SYNC_CHANGES" | sed 's/^/  - /'
      echo ""
      if $COMMIT_AFTER_SYNC; then
        # 安全な git add (specific paths only、CLAUDE.md HIGH 教訓: git reset 禁止)
        # path に space を含む場合に備えて while-read + git add 個別
        echo "[install] --commit: staging ${SYNC_COUNT} synced file(s) (project files untouched)"
        ADDED=0
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          if (cd "$TARGET" && git add -- "$p" 2>/dev/null); then
            ADDED=$((ADDED + 1))
          else
            echo "[install] WARN: git add skipped: $p" >&2
          fi
        done <<<"$SYNC_CHANGES"
        if [[ "$ADDED" -gt 0 ]]; then
          # commit 対象が staging にあるか最終確認 (空 commit 防止)
          if (cd "$TARGET" && git diff --cached --quiet); then
            echo "[install] WARN: nothing staged after git add — skip commit" >&2
          else
            COMMIT_MSG="chore(harness): sync .claude/ from hirai-method $(date -u +%Y-%m-%d)"
            if (cd "$TARGET" && git commit -q -m "$COMMIT_MSG"); then
              COMMIT_SHA=$(cd "$TARGET" && git rev-parse --short HEAD)
              echo "[install] committed harness sync: ${COMMIT_SHA} (${ADDED} file(s))"
            else
              echo "[install] WARN: git commit failed (manual commit needed)" >&2
            fi
          fi
        else
          echo "[install] WARN: no files staged — skip commit" >&2
        fi
        unset ADDED COMMIT_MSG COMMIT_SHA
      else
        # default 案内 (honor system、user に分離 commit を促す)
        echo "[install] HINT: commit these as a SEPARATE commit, e.g.:"
        echo "  cd $TARGET"
        echo "  git add .claude/"
        echo "  git commit -m 'chore(harness): sync .claude/ from hirai-method'"
        echo "[install] HINT: or rerun with '--commit' to auto-commit harness sync only:"
        echo "  bash install.sh $TARGET --update --commit"
        echo "[install] NOTE: keeping harness-sync separate from project work helps revert / blame."
      fi
      unset SYNC_COUNT
    fi
    unset SYNC_CHANGES
  else
    if $COMMIT_AFTER_SYNC; then
      echo "[install] WARN: --commit requested but target is not a git repo — skip commit"
      echo "[install] HINT: initialize git first: cd $TARGET && git init"
    fi
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
  2. project 固有 override (docs_approved_dir / protected_paths 追加分 等) は
     \$EDITOR .claude/harness-config.local.yml     # ←ココに書く (install.sh --update で温存される)
     (SSoT .claude/harness-config.yml は触らない — --update で SSoT 値が上書きされる)
  3. \$EDITOR .claude/bash-whitelist.txt           # 使う CLI (pnpm/poetry/cargo/...) を追記
  4. mv CLAUDE.md.template CLAUDE.md && \$EDITOR CLAUDE.md   # <...> placeholders を埋める
  5. (recommended) git init                                  # observe.sh の project hash 検出を有効化
  6. Claude Code session 起動 → /init-tasks → /mode loop

settings.json について (task-71 H2 / task-80):
  - settings.json 本体は rsync exclude (repo 固有 permissions / preset を守る)。
  - sync mode (--update / --force / --overwrite-all) では rsync 後に
    generate-settings.sh で settings.json を **自動再生成済** (statusLine / dispatcher 配線同期、
    permissions は verbatim 保持)。手動実行は不要 (失敗時のみ下記を手動実行):
      bash .claude/scripts/generate-settings.sh --out .claude/settings.json
  - mode 別の permissions 帰結 (意味が異なる):
      --update       : 既存 settings.json の permissions を verbatim 保持して再配線。
      --force         : .claude を破壊的リセット + settings.json は exclude のため再生成時は
                        既存不在 → fail-open skip (permissions 保持の前提は成立しない)。
      --overwrite-all : settings.json も source で上書き済のため、保持される permissions は
                        **source 由来** (consuming repo の permissions は失われる = task-79 既定)。
  - 自動再生成 skip 条件: jq 不在 / generate-settings.sh 不在 / 既存 settings.json 不在
    (いずれも WARN/NOTE + install 継続)。新規 install (default mode) は settings.json を
    配布しないため対象外。
  - 注意: 手編集した独自トップレベル key / 独自 hook は manifest 由来に置換され脱落する。
    独自 hook は dispatcher-manifest.tsv に登録すること (再生成で配線が保たれる)。

--overwrite-all について (task-79):
  - drift した target を SSoT へ強制リセットする全上書き mode。
  - settings.local.json **のみ** 温存し、それ以外 (settings.json / harness-config.local.yml /
    state dir 群 / worktrees) も source で上書きする = target の local override は失われる。
  - settings.json も上書きされるため、consuming repo は実行後
      bash .claude/scripts/generate-settings.sh --out .claude/settings.json
    で repo 固有 permissions から再生成すること (task-71 dispatcher 配線復元)。
  - --delete は使わないため target にしかない file は残る (上書きのみ)。
  - 用途は drift リセット専用。日常の harness 取込は --update を使うこと (local 設定を温存)。

project-rules/ について (task-82):
  - .claude/project-rules/<name>.md は **project 所有** (update 免除)。harness 7 rule
    (.claude/rules/*.md) から @import され、harness rule の後に結合 load される。
  - harness rule の override / 追補はここに書く (7 harness rule 本体は触らない)。
    update/force/overwrite-all いずれの mode でも rsync exclude + create-if-absent で保護
    (なければ空テンプレ配置・あれば skip、既存編集は上書きされない)。

Override precedence (高 → 低):
  env(HC_*) > .claude/harness-config.local.yml > .claude/harness-config.yml (SSoT) > hardcoded default

Documentation:
  - README.md         (採用 5 ステップ)
  - docs/INVENTORY.md (全構成要素の Path 表)
  - docs/PORTABILITY.md (他リポへの移植仕様)
  - docs/SELF_IMPROVEMENT.md (F1-F3 + L1-L5)
EOF
