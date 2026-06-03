#!/usr/bin/env bash
# statusline.sh — task-62 ステータスライン
#
# 役割: Claude Code の statusLine 機能から stdin で渡される session JSON を parse し、
#       2 行のステータスライン (絵文字なし / ANSI 色) を stdout に出力する。
#
# 設計 SSoT: docs/draft/statusline-construction.md §3 採用案
#
# 出力レイアウト (2 行、絵文字なし、ANSI 色):
#   行1: <model> · <branch> · ctx <N>%
#   行2: 5h <N>% · 7d <N>% · <mode> · settings: .claude/scripts/hc-config.sh
#
# 数値元 (stdin JSON):
#   model  = .model.display_name
#   ctx    = .context_window.used_percentage
#   5h 残  = 100 - .rate_limits.five_hour.used_percentage
#   7d 残  = 100 - .rate_limits.seven_day.used_percentage
#   branch = .workspace.repo.* (branch) — 不在時は $CWD で git 直問い
#   mode   = $cwd/.claude/mode.yml の mode: 値 (不在 normal)
#
# graceful fallback (必須):
#   - rate_limits 不在 (free tier / 初回 API 前) → "5h —" / "7d —"
#   - jq 不在 → plain 降格 (model + branch のみ)、非ゼロ exit を出さない
#   - mode.yml 不在 → normal
#
# bash 3.2 互換 (macOS)。statusLine 実行 script なので set は最小限 (status を壊さない)。
# stdin JSON が壊れていても exit 0 を返し statusLine 全体を破壊しない。
set -u

# === ANSI 色 (Claude Code 踏襲、絵文字なし) ===
# tput が無い / TERM 未設定環境でも生 escape で動かす。
ESC=$'\033'
RESET="${ESC}[0m"
DIM="${ESC}[2m"
BOLD="${ESC}[1m"
GREEN="${ESC}[32m"
YELLOW="${ESC}[33m"
RED="${ESC}[31m"
CYAN="${ESC}[36m"
MAGENTA="${ESC}[35m"

# 色出力を無効化する場合 (NO_COLOR 慣習 / 非 TTY パイプ先) — statusLine は色付き想定なので
# default は色 ON。HC_STATUSLINE_NO_COLOR=1 で全色を空文字化。
if [ "${HC_STATUSLINE_NO_COLOR:-}" = "1" ] || [ -n "${NO_COLOR:-}" ]; then
  RESET=""; DIM=""; BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; MAGENTA=""
fi

SEP="${DIM} · ${RESET}"

# === stdin JSON を読む ===
INPUT="$(cat 2>/dev/null || true)"

# === git branch fallback (workspace.repo に branch が無い / jq 不在時) ===
git_branch() {
  # HIGH-2: resolve_cwd 算出済の $CWD を尊重 (呼出時点で確定済)。
  git -C "${CWD:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null || true
}

# === cwd 抽出 (mode.yml 探索用) ===
# jq があれば JSON から .workspace.current_dir / .cwd を取得、無ければ $PWD。
resolve_cwd() {
  local cwd=""
  if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    cwd="$(printf '%s' "$INPUT" | jq -r '
      (.workspace.current_dir // .workspace.project_dir // .cwd // empty)
    ' 2>/dev/null || true)"
  fi
  if [ -z "$cwd" ] || [ "$cwd" = "null" ]; then
    cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  fi
  printf '%s' "$cwd"
}

# === mode.yml の mode: 値 (不在 / 読めない → normal) ===
read_mode() {
  local cwd="$1" mode_file mode_val=""
  mode_file="$cwd/.claude/mode.yml"
  if [ -f "$mode_file" ]; then
    # `mode: loop` 形式の最初の 1 行 (コメント # 行を除外)。bash 3.2 互換 grep/sed。
    mode_val="$(grep -E '^[[:space:]]*mode:[[:space:]]*' "$mode_file" 2>/dev/null \
      | head -1 | sed -E 's/^[[:space:]]*mode:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  fi
  case "$mode_val" in
    loop|normal) printf '%s' "$mode_val" ;;
    *) printf 'normal' ;;
  esac
}

# === 残り % を閾値で着色 (≥50 緑 / 20-49 黄 / <20 赤) ===
# 引数: ラベル(5h/7d) 残り値(整数 or "—")
colorize_remaining() {
  local label="$1" val="$2"
  if [ "$val" = "—" ]; then
    printf '%s%s —%s' "$DIM" "$label" "$RESET"
    return
  fi
  local color="$GREEN"
  if [ "$val" -lt 20 ] 2>/dev/null; then
    color="$RED"
  elif [ "$val" -lt 50 ] 2>/dev/null; then
    color="$YELLOW"
  fi
  printf '%s%s %s%%%s' "$color" "$label" "$val" "$RESET"
}

# === ctx % 着色 (使用率なので high が悪い: <50 緑 / 50-79 黄 / ≥80 赤) ===
colorize_ctx() {
  local val="$1"
  if [ "$val" = "—" ]; then
    printf '%sctx —%s' "$DIM" "$RESET"
    return
  fi
  local color="$GREEN"
  if [ "$val" -ge 80 ] 2>/dev/null; then
    color="$RED"
  elif [ "$val" -ge 50 ] 2>/dev/null; then
    color="$YELLOW"
  fi
  printf '%sctx %s%%%s' "$color" "$val" "$RESET"
}

# === mode 着色 (loop は強調 / normal は dim) ===
colorize_mode() {
  local mode="$1"
  if [ "$mode" = "loop" ]; then
    printf '%s%sloop%s' "$BOLD" "$MAGENTA" "$RESET"
  else
    printf '%snormal%s' "$DIM" "$RESET"
  fi
}

# 小数 / null を整数へ正規化 ("34.5" → "34"、"null"/"" → "—")
to_int_or_dash() {
  local v="$1"
  case "$v" in
    ""|null|None) printf '%s' "—"; return ;;
  esac
  # 小数点以下を切り捨て。数値でなければ "—"。
  v="${v%%.*}"
  case "$v" in
    ''|*[!0-9-]*) printf '%s' "—" ;;
    *)
      # 0-100 へ clamp (HIGH-1: used>100 で残り負値 / ctx 負値表示を防ぐ)。
      if [ "$v" -lt 0 ] 2>/dev/null; then v=0
      elif [ "$v" -gt 100 ] 2>/dev/null; then v=100
      fi
      printf '%s' "$v" ;;
  esac
}

# 残り % = 100 - used。used が "—" なら "—"。
remaining_from_used() {
  local used="$1"
  if [ "$used" = "—" ]; then
    printf '%s' "—"
  else
    printf '%s' "$((100 - used))"
  fi
}

CWD="$(resolve_cwd)"
MODE="$(read_mode "$CWD")"

# === jq 不在 → plain 降格 (model + branch のみ、非破壊) ===
if ! command -v jq >/dev/null 2>&1; then
  branch="$(git_branch)"
  [ -z "$branch" ] && branch="-"
  # 色なし plain (jq 不在環境は最小限の表示)。1 行で済ませる。
  printf 'Claude · %s\n' "$branch"
  exit 0
fi

# === jq あり: JSON を parse (壊れた JSON でも fallback) ===
MODEL="$(printf '%s' "$INPUT" | jq -r '.model.display_name // empty' 2>/dev/null || true)"
[ -z "$MODEL" ] && MODEL="Claude"

CTX_RAW="$(printf '%s' "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null || true)"
CTX="$(to_int_or_dash "$CTX_RAW")"

FIVEH_USED="$(printf '%s' "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null || true)"
SEVEND_USED="$(printf '%s' "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null || true)"
FIVEH_REMAIN="$(remaining_from_used "$(to_int_or_dash "$FIVEH_USED")")"
SEVEND_REMAIN="$(remaining_from_used "$(to_int_or_dash "$SEVEND_USED")")"

# branch: workspace.repo から取得を試み、無ければ git 直問い
BRANCH="$(printf '%s' "$INPUT" | jq -r '
  (.workspace.repo.branch // .workspace.repo.current_branch // .gitBranch // empty)
' 2>/dev/null || true)"
if [ -z "$BRANCH" ] || [ "$BRANCH" = "null" ]; then
  BRANCH="$(git_branch)"
fi
[ -z "$BRANCH" ] && BRANCH="-"

# === 行1: <model> · <branch> · ctx <N>% ===
LINE1="$(printf '%s%s%s%s%s%s%s' \
  "$CYAN" "$MODEL" "$RESET" \
  "$SEP" \
  "$BRANCH" \
  "$SEP" \
  "$(colorize_ctx "$CTX")")"

# === 行2: 5h <N>% · 7d <N>% · <mode> · settings: .claude/scripts/hc-config.sh ===
LINE2="$(printf '%s%s%s%s%s%s%ssettings: .claude/scripts/hc-config.sh%s' \
  "$(colorize_remaining "5h" "$FIVEH_REMAIN")" \
  "$SEP" \
  "$(colorize_remaining "7d" "$SEVEND_REMAIN")" \
  "$SEP" \
  "$(colorize_mode "$MODE")" \
  "$SEP" \
  "$DIM" "$RESET")"
# LOW-1: settings hint を dim 表示 (draft §3)。上の printf で末尾 $DIM ... $RESET が hint を包囲済。

printf '%s\n%s\n' "$LINE1" "$LINE2"
exit 0
