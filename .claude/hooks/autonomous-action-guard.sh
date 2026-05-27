#!/usr/bin/env bash
# autonomous-action-guard.sh — PreToolUse Bash hook
#
# 役割:
#   Loop モード稼働中、modes.md 遵守事項 8 の自律禁止リスト (default 11
#   カテゴリ) に match する Bash コマンドを {"decision":"block"} で
#   BLOCK する。Normal モードでは context 注入のみ (block しない)。
#   準備フェーズ (draft / 実装 / ローカル commit) は対象外。
#
# 対象カテゴリ (default、env override 可):
#   - PR merge / リリース: gh pr merge / gh release / git tag push
#   - 本番 deploy: vercel --prod / supabase deploy / supabase db push|reset
#   - infra apply: kubectl apply / terraform apply|destroy
#   - 第三者リポ: gh repo (delete|transfer|archive)
#   - AWS 破壊操作: aws *-delete-*|terminate-*|destroy-*
#
# task-39 緩和 (2026-05-25、docs/draft/autonomous-action-guard-relaxation.md):
#   - git push 一般 pattern を削除 → protected-branch-push-deny
#     (delegation-guard.sh) に委譲。main/stg 以外は push 許可。
#   - gh pr create を削除 → user 要望で PR 作成は自律実行可。
#   - gh pr merge / gh release / git tag push は依然 block (本番影響大)。
#
# bypass:
#   ECC_AUTONOMOUS_ACTION_OVERRIDE=1   セッション全体 OFF + bypass.log 記録
#   HC_AUTONOMOUS_ACTION_ENABLED=false config レベル OFF + bypass.log 記録
#   HC_AUTONOMOUS_ACTION_PATTERNS=...  検出 regex 上書き (改行区切り)
#
# 設計起源:
#   docs/draft/loop-auto-progress-enforcement.md §3 W3
#   docs/tasks/task-6-loop-auto-progress-enforcement.md W3 詳細
#   docs/draft/autonomous-action-guard-relaxation.md §4 採用案 (task-39)
#
# Subagent からの操作は対象外 (delegation-guard.sh と同 pattern)。
# bash flags: set -u のみ。set -e leak 事故 (CB-verify 教訓) を避ける。

set -u

input=$(cat 2>/dev/null || true)

# --- subagent detection (delegation-guard.sh と同じ多段フォールバック) ---
is_subagent="false"

if [ "${CLAUDE_HARNESS_ROLE:-}" = "subagent" ]; then
  is_subagent="true"
fi

if [ "$is_subagent" = "false" ] && command -v jq >/dev/null 2>&1; then
  for field in agent_type subagent_type parent_tool_use_id agent_id; do
    v=$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" != "null" ]; then
      is_subagent="true"
      break
    fi
  done
fi

# agent marker dir は config-loader.sh の HC_AGENT_MARKER_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/config-loader.sh"
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled autonomous_action_guard; then
  echo '{}'
  exit 0   # feature OFF で no-op
fi

if [ "$is_subagent" = "false" ] && [ -n "${HC_AGENT_MARKER_DIR:-}" ] && [ -d "$HC_AGENT_MARKER_DIR" ]; then
  if ls "$HC_AGENT_MARKER_DIR"/*.lock >/dev/null 2>&1; then
    is_subagent="true"
  fi
fi

if [ "$is_subagent" = "true" ]; then
  echo '{}'
  exit 0
fi

# --- モード解決 ---
# shellcheck source=lib/mode-loader.sh
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  MODE=$(load_mode)
else
  MODE="normal"
fi

# --- bypass-logger 読み込み (best-effort) ---
# shellcheck source=lib/bypass-logger.sh
if [ -f "$SCRIPT_DIR/lib/bypass-logger.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/bypass-logger.sh"
fi

# --- bypass 判定 (env-level) ---
if [ "${ECC_AUTONOMOUS_ACTION_OVERRIDE:-0}" = "1" ] || [ "${ECC_AUTONOMOUS_ACTION_OVERRIDE:-}" = "true" ]; then
  if declare -f log_bypass >/dev/null 2>&1; then
    log_bypass "autonomous-action-guard" "ECC_AUTONOMOUS_ACTION_OVERRIDE" "${ECC_BYPASS_REASON:-(not provided)}"
  fi
  echo '{}'
  exit 0
fi

# --- bypass 判定 (config-level) ---
if [ "${HC_AUTONOMOUS_ACTION_ENABLED:-true}" = "false" ]; then
  if declare -f log_bypass >/dev/null 2>&1; then
    log_bypass "autonomous-action-guard" "HC_AUTONOMOUS_ACTION_ENABLED" "${ECC_BYPASS_REASON:-(config off)}"
  fi
  echo '{}'
  exit 0
fi

# --- 依存チェック ---
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# --- command 抽出 ---
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
if [ -z "$cmd" ]; then
  echo '{}'
  exit 0
fi

# --- 禁止パターン (default、env override 可) ---
# task-39 緩和 (2026-05-25):
#   - `git push` 一般 pattern: 削除済。protected-branch-push-deny
#     (delegation-guard.sh) に委譲。main/stg のみ block、それ以外は許可。
#   - `gh pr create`: 削除済。user 要望で PR 作成は自律実行可 (task-39)。
#   - `gh pr merge`: 維持。本番影響大の merge 操作は引き続き block。
DEFAULT_PATTERNS='^gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)
^gh[[:space:]]+release([[:space:]]|$)
^gh[[:space:]]+repo[[:space:]]+(delete|transfer|archive)([[:space:]]|$)
^git[[:space:]]+tag[[:space:]].+[[:space:]]+(origin|upstream)([[:space:]]|$)
^vercel([[:space:]].*)?--prod([[:space:]]|$)
^supabase[[:space:]]+db[[:space:]]+(push|reset)([[:space:]]|$)
^supabase[[:space:]]+deploy([[:space:]]|$)
^kubectl[[:space:]]+(apply|delete)([[:space:]]|$)
^terraform[[:space:]]+(apply|destroy)([[:space:]]|$)
^aws[[:space:]].*[[:space:]](delete-|terminate-|destroy-)'

PATTERNS="${HC_AUTONOMOUS_ACTION_PATTERNS:-$DEFAULT_PATTERNS}"

# segments split (delegation-guard.sh と同じ pattern)
# `&&` `||` `;` `|` で分割し、各 segment を pattern と照合
segments=$(printf '%s' "$cmd" | awk '
  BEGIN { RS=""; }
  {
    gsub(/&&|\|\||;|\|/, "\n", $0);
    print $0;
  }')

matched_pattern=""
matched_segment=""
while IFS= read -r seg; do
  seg_trim=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -z "$seg_trim" ] && continue

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    if printf '%s' "$seg_trim" | grep -qE "$pattern"; then
      matched_pattern="$pattern"
      matched_segment="$seg_trim"
      break 2
    fi
  done <<< "$PATTERNS"
done <<EOF
$segments
EOF

if [ -z "$matched_pattern" ]; then
  echo '{}'
  exit 0
fi

# --- match: モード分岐 ---
reason_loop="[autonomous-action-guard] Loop モード自律実行禁止コマンドを検出しました。

検出 segment: ${matched_segment}
match 正規表現: ${matched_pattern}

modes.md 遵守事項 8 (Loop モード自律実行禁止リスト) により、以下の操作は user の
明示承認が必要です。準備 (draft / 設計 / 実装 / ローカル commit) のみ自律可。

【ブロック対象カテゴリ (default、task-39 緩和後)】
- PR merge / リリース: gh pr merge / gh release / git tag push
- 第三者リポ: gh repo delete|transfer|archive
- 本番 deploy: vercel --prod / supabase deploy / supabase db push|reset
- infra apply: kubectl apply|delete / terraform apply|destroy
- AWS 破壊操作: aws *-delete-*|terminate-*|destroy-*

【task-39 緩和 (2026-05-25)】
- git push (一般): 緩和。main/stg 以外への push は許可
  (protected-branch-push-deny に委譲)
- gh pr create: 緩和。PR 作成は自律実行可

【bypass (user の明示承認下で)】
1. user に承認を求める (chat で明示)
2. user 承認後、以下のいずれか:
   - export ECC_AUTONOMOUS_ACTION_OVERRIDE=1
     export ECC_BYPASS_REASON='<理由>'
     再実行 (.claude/.workflow-state/bypass.log に記録)
   - config レベル: HC_AUTONOMOUS_ACTION_ENABLED=false

【代替】
- subagent 経由で実行 (本 hook 対象外)
- /mode normal で Loop モード解除"

reason_normal="[autonomous-action-guard] 注意: 自律実行禁止リストに該当するコマンドです。

検出 segment: ${matched_segment}
match 正規表現: ${matched_pattern}

Normal モードでは block しませんが、modes.md 遵守事項 8 により Loop モード時は
user の明示承認が必要なカテゴリです。実行前に意図を確認してください。

【参考】このまま実行: そのまま続行 / 中止: ESC 等で取消"

case "$MODE" in
  loop)
    jq -n --arg r "$reason_loop" '{decision:"block", reason:$r}'
    exit 0
    ;;
  *)
    # Normal モード: warning context 注入のみ。ただし禁止パターン match 時は
    # log_bypass で監査残し (W2, task #9)。「Loop 規律から外れた可能性ある cmd」を
    # bypass.log に記録し /harness-audit でトレース可能にする。
    # bypass: HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED=false で OFF。
    if [ "${HC_AUTONOMOUS_LOG_NORMAL_RESTRICTED:-true}" != "false" ]; then
      if declare -f log_bypass >/dev/null 2>&1; then
        log_bypass "autonomous-action-guard" "mode-normal-restricted-cmd" "matched=${matched_pattern} segment=${matched_segment}"
      fi
    fi
    jq -n --arg r "$reason_normal" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
    exit 0
    ;;
esac
