#!/usr/bin/env bash
# サブエージェント委譲ルール: メインエージェントは保護パス (既定 src/ tests/ scripts/) を直接操作できない。
# 保護パスのリスト・whitelist 位置・タスク管理 path 等は `.claude/harness-config.yml` で集中管理。
# Bash は原則禁止。`.claude/bash-whitelist.txt` に登録された prefix のみ実行可能。
# 申請フローは `.claude/bash-whitelist-requests/REQUEST_TEMPLATE.md` 参照。
#
# Orchestrator: env load + subagent detect + tool dispatch to lib/*。
# 個別ルール logic は lib/delegation-guard/ に分割:
#   - subagent-detect.sh   — subagent 検出 (多段フォールバック)
#   - protected-paths.sh   — Edit/Write/Read/Grep/Glob 保護パス + code 保護 + task glob
#   - git-deny.sh          — git destructive 10 patterns + protected branch push
#   - bash-whitelist.sh    — whitelist 照合 + segment splitter + path leak guard
#
# stdin から PreToolUse JSON を受け取り、stdout に hook 応答を返す。
# 引数: $1 = tool name (Edit|Write|Read|Grep|Glob|Bash)

set -u

# config 読み込み (HC_* 変数 export)
SCRIPT_DIR="$(dirname "$0")"
# shellcheck source=lib/config-loader.sh
source "$SCRIPT_DIR/lib/config-loader.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled delegation_guard; then
  exit 0   # feature OFF で no-op
fi

# bypass logger (log_bypass 関数を提供)
# shellcheck source=lib/bypass-logger.sh
source "$SCRIPT_DIR/lib/bypass-logger.sh"

# Observability 構造化 log API (task-99 P3-2、observations.jsonl)
# bypass-logger.sh の log_bypass は observability.sh の super-set 版で上書きされる
# (bypass.log 1 行 append + observations.jsonl event 追加を両立)。
# shellcheck source=lib/observability.sh
if [ -f "$SCRIPT_DIR/lib/observability.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/observability.sh"
fi
# shellcheck source=lib/delegation-guard/subagent-detect.sh
source "$SCRIPT_DIR/lib/delegation-guard/subagent-detect.sh"
# shellcheck source=lib/delegation-guard/protected-paths.sh
source "$SCRIPT_DIR/lib/delegation-guard/protected-paths.sh"
# shellcheck source=lib/delegation-guard/git-deny.sh
source "$SCRIPT_DIR/lib/delegation-guard/git-deny.sh"
# shellcheck source=lib/delegation-guard/bash-whitelist.sh
source "$SCRIPT_DIR/lib/delegation-guard/bash-whitelist.sh"

input=$(cat)
tool="${1:-}"

# task-22 W2: jq 不在環境では fail-open (hook 機能停止して継続)
# delegation-guard.sh は jq に重度依存 (16 箇所) のため、不在で crash する前に exit 0
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- debug ---
if [ "${CLAUDE_HOOK_DEBUG:-}" = "1" ]; then
  printf '[%s] tool=%s\n%s\n---\n' "$(date +%FT%T)" "$tool" "$input" \
    >> /tmp/claude-hook-debug.log
fi

# --- subagent detection ---
is_subagent=$(detect_subagent "$input")

if [ "$is_subagent" = "true" ]; then
  echo '{}'
  exit 0
fi

# --- main agent path enforcement ---
# Bash deny / 委譲ガード block を受けた際の必須アクション (development-process.md §5)。
# 全 block message に共通フッタとして付与する。
reflex_footer=$'\n\n【次のアクション】\n1. Agent tool で subagent を起動 (run_in_background: true 必須)\n2. その subagent に本作業を委譲\n3. TaskCreate でタスク登録\n\nBash deny / whitelist 不在 / 委譲ガード block は loop 停止理由にしないこと (development-process.md §5)。'

# メッセージは harness-config.yml の protected_paths を反映 (例: "src/ tests/ scripts/")
block_path_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " を直接操作できません。Agent tool でサブエージェントに委譲してください。" + $f)}')
block_read_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " のファイルを直接読み取れません。Agent tool(Explore等)でサブエージェントに調査を委譲してください。" + $f)}')
block_search_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " を直接検索できません。Agent tool(Explore等)でサブエージェントに調査を委譲してください。" + $f)}')

# task 配下の絶対 path 部分一致パターン (protected-paths.sh が参照)
task_glob="*/${HC_TASK_DIR}/*"

# hook fire log (task-99): main agent path enforcement 分岐に到達した時点で log_fire
# (subagent bypass はすでに上で通過済み)。
if declare -f log_fire >/dev/null 2>&1; then
  log_fire "delegation-guard" "processing main agent tool=$tool" ""
fi

case "$tool" in
  Edit|Write)
    handle_edit_write "$input" "$tool"
    ;;
  Read)
    handle_read "$input"
    ;;
  Grep|Glob)
    handle_search "$input"
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    check_bash_inline_override "$cmd"
    check_git_destructive "$cmd"
    check_protected_branch_push "$cmd"
    check_bash_whitelist "$cmd"
    ;;
esac

echo '{}'
