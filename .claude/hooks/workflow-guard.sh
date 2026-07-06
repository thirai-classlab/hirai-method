#!/usr/bin/env bash
# .claude/hooks/workflow-guard.sh
# PreToolUse(Bash) hook — /finish-task で .claude/.workflow-state/<slug>.json を検証
# 仕様: docs/draft/workflow-enforcement.md v2 §3 W4 + .claude/.workflow-state/SCHEMA.md
#
# 役割:
#   /finish-task <slug> 実行直前に下記 2 つを構造化判定する:
#     A. current_stage が workflow_stages_{new|modify} の最終 stage に達しているか
#     B. pending_findings.module_review / pending_findings.system_review が両方とも空配列か
#   どちらか fail なら BLOCK + stderr に問題内容 + 推奨アクションを出力。
#
# 重要制約 (round-2 review):
#   - grep / 文字列マッチ依存禁止。state JSON の構造化 parse のみで判定。
#   - stage 名で判定（step 番号は使わない）。
#
# Args: $1 = tool name (Bash) — JSON tool_name 優先
# Stdin: PreToolUse JSON
#
# Bypass:
#   ECC_WORKFLOW_GUARD_OFF=1               # 全 skip + bypass.log 記録
#   HC_WORKFLOW_GUARD_ENABLED=false        # 全 skip + bypass.log 記録 (config 系統)
#
# Bypass log path: .claude/.workflow-state/bypass.log (lib/bypass-logger.sh 経由で append)
#   <ISO-8601> | <session_id> | workflow-guard | <var> | <reason>

set -uo pipefail  # ⚠️ set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925 参照)

# === config 読み込み (HC_WORKFLOW_STAGES_NEW / _MODIFY 取得) ===
# shellcheck source=lib/config-loader.sh
source "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/config-loader.sh"

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled workflow_enforcement; then
  echo '{}'
  exit 0   # feature OFF で no-op
fi

# === bypass.log 共通ライブラリ ===
# shellcheck source=lib/bypass-logger.sh
source "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/bypass-logger.sh"

# === BLOCK message 統一 API (task-94 P2-3、docs/draft/lib-block-message-4args.md §3.1) ===
# shellcheck source=lib/block-message.sh
if [ -f "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/block-message.sh" ]; then
  # shellcheck disable=SC1091
  source "${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/hooks/lib/block-message.sh"
fi

# === workflow-state root (state file 解決に使用) ===
_workflow_state_root="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.workflow-state"

# === Bypass: ECC_WORKFLOW_GUARD_OFF ===
if [ "${ECC_WORKFLOW_GUARD_OFF:-0}" = "1" ] || [ "${ECC_WORKFLOW_GUARD_OFF:-}" = "true" ]; then
  log_bypass "workflow-guard" "ECC_WORKFLOW_GUARD_OFF" "${ECC_BYPASS_REASON:-(not provided)}"
  echo '{}'
  exit 0
fi

# === Bypass: HC_WORKFLOW_GUARD_ENABLED=false ===
if [ "${HC_WORKFLOW_GUARD_ENABLED:-true}" = "false" ]; then
  log_bypass "workflow-guard" "HC_WORKFLOW_GUARD_ENABLED" "${ECC_BYPASS_REASON:-(not provided)}"
  echo '{}'
  exit 0
fi

# === stdin 読み取り ===
input=$(cat)

# === jq 必須 (fallback: python3) ===
_has_jq=0
if command -v jq >/dev/null 2>&1; then
  _has_jq=1
fi
_has_py=0
if command -v python3 >/dev/null 2>&1; then
  _has_py=1
fi
if [ "$_has_jq" = "0" ] && [ "$_has_py" = "0" ]; then
  # parser 不在: fail-open
  echo '{}'
  exit 0
fi

# === JSON field 抽出 helper ===
# jq があれば jq、なければ python3
_json_get() {
  # $1 = JSON string
  # $2 = jq filter (e.g. ".tool_name")
  # $3 = python expression equivalent (e.g. "data.get('tool_name', '')")
  if [ "$_has_jq" = "1" ]; then
    printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
  else
    printf '%s' "$1" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    v = $3
    print(v if v is not None else '')
except Exception:
    print('')
" 2>/dev/null
  fi
}

# === tool name 取得 ===
tool=$(_json_get "$input" '.tool_name' "data.get('tool_name')")
if [ -z "$tool" ] || [ "$tool" = "null" ]; then
  tool="${1:-}"
fi

# === Bash 以外は素通し ===
if [ "$tool" != "Bash" ]; then
  echo '{}'
  exit 0
fi

# === command 取得 ===
cmd=$(_json_get "$input" '.tool_input.command' "data.get('tool_input', {}).get('command', '')")
if [ -z "$cmd" ]; then
  echo '{}'
  exit 0
fi

# === /finish-task or finish-task 検出 + slug 抽出 ===
# 許可: "/finish-task <slug>" / "finish-task <slug>"
# slug 規約: ^[a-z0-9][a-z0-9-]{2,48}$ (git branch 規約準拠)
slug=""
if printf '%s' "$cmd" | grep -qE '(^|[[:space:]])/?finish-task[[:space:]]+[a-z0-9][a-z0-9-]{2,48}([[:space:]]|$)'; then
  # extract: first non-space token after "finish-task"
  slug=$(printf '%s' "$cmd" | sed -nE 's/.*[[:space:]/]finish-task[[:space:]]+([a-z0-9][a-z0-9-]{2,48}).*/\1/p' | head -n1)
  # fallback if anchored at start
  if [ -z "$slug" ]; then
    slug=$(printf '%s' "$cmd" | sed -nE 's/^[[:space:]]*\/?finish-task[[:space:]]+([a-z0-9][a-z0-9-]{2,48}).*/\1/p' | head -n1)
  fi
fi

if [ -z "$slug" ]; then
  echo '{}'
  exit 0
fi

# === state JSON 不在: 旧 task 互換のため素通し ===
state_file="${_workflow_state_root}/${slug}.json"
if [ ! -f "$state_file" ]; then
  echo '{}'
  exit 0
fi

# === state JSON parse (workflow_type / current_stage / pending_findings) ===
if [ "$_has_jq" = "1" ]; then
  workflow_type=$(jq -r '.workflow_type // empty' "$state_file" 2>/dev/null)
  current_stage=$(jq -r '.current_stage // empty' "$state_file" 2>/dev/null)
  mr_count=$(jq -r '(.pending_findings.module_review // []) | length' "$state_file" 2>/dev/null)
  sr_count=$(jq -r '(.pending_findings.system_review // []) | length' "$state_file" 2>/dev/null)
else
  # python3 fallback
  _state_json=$(cat "$state_file" 2>/dev/null)
  workflow_type=$(printf '%s' "$_state_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('workflow_type', ''))
except Exception:
    print('')
" 2>/dev/null)
  current_stage=$(printf '%s' "$_state_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('current_stage', ''))
except Exception:
    print('')
" 2>/dev/null)
  mr_count=$(printf '%s' "$_state_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(len(d.get('pending_findings', {}).get('module_review', []) or []))
except Exception:
    print('0')
" 2>/dev/null)
  sr_count=$(printf '%s' "$_state_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(len(d.get('pending_findings', {}).get('system_review', []) or []))
except Exception:
    print('0')
" 2>/dev/null)
fi

# === workflow_type 別 stage 列取得 ===
if [ "$workflow_type" = "new" ]; then
  stages="$HC_WORKFLOW_STAGES_NEW"
elif [ "$workflow_type" = "modify" ]; then
  stages="$HC_WORKFLOW_STAGES_MODIFY"
else
  # workflow_type 不明: fail-open (旧 task 互換 / 想定外データ)
  echo '{}'
  exit 0
fi

# 最終 stage 取得 (改行区切り→最終行)
final_stage=$(printf '%s' "$stages" | awk 'NF{last=$0} END{print last}')
if [ -z "$final_stage" ]; then
  # config 不整合: fail-open
  echo '{}'
  exit 0
fi

# === 判定 A: current_stage が最終 stage に達しているか ===
stage_ok=0
if [ "$current_stage" = "$final_stage" ]; then
  stage_ok=1
fi

# === 判定 B: pending findings が両方とも空か ===
findings_ok=0
if [ "${mr_count:-0}" = "0" ] && [ "${sr_count:-0}" = "0" ]; then
  findings_ok=1
fi

# === pass: 両方 OK ===
if [ "$stage_ok" = "1" ] && [ "$findings_ok" = "1" ]; then
  echo '{}'
  exit 0
fi

# === BLOCK: 問題内容を組み立て ===
problems=""
recommendations=""

if [ "$stage_ok" = "0" ]; then
  problems="${problems}- current_stage='${current_stage}' が最終 stage='${final_stage}' (workflow_type=${workflow_type}) に達していません"$'\n'
  recommendations="${recommendations}- 残り stage を順次完了させてから /finish-task ${slug} を実行してください"$'\n'
fi

if [ "$findings_ok" = "0" ]; then
  problems="${problems}- pending_findings に未解決の指摘があります (module_review=${mr_count} / system_review=${sr_count})"$'\n'
  recommendations="${recommendations}- /module-review および /system-review の指摘事項を全て解決 (修正 or skip 承認) してから /finish-task ${slug} を実行してください"$'\n'
fi

reason="[workflow-guard] BLOCK: /finish-task ${slug} は workflow 完了条件を満たしません。

state file: ${state_file}
workflow_type: ${workflow_type}

問題:
${problems}
推奨アクション:
${recommendations}
Bypass (audit-logged):
  ECC_WORKFLOW_GUARD_OFF=1 ECC_BYPASS_REASON='<理由>' /finish-task ${slug}
  または HC_WORKFLOW_GUARD_ENABLED=false (harness-config.yml)"

# task-94 migration: PreToolUse BLOCK は emit_block_pretool 経由 (lib SSoT)
# 既存 hybrid (stderr + JSON stdout + exit 2) を lib で保持:
#   - emit_block_pretool は stderr 4 行 + JSON stdout を emit
#   - caller が exit 2 を明示 (§3.5、workflow-guard の後方互換 exit code)
if declare -f emit_block_pretool >/dev/null 2>&1; then
  emit_block_pretool "$reason" "" "" ""
else
  # fallback: lib source 失敗時は既存経路
  printf '%s\n' "$reason" >&2
  if [ "$_has_jq" = "1" ]; then
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  else
    # python3 fallback
    printf '%s' "$reason" | python3 -c "
import json, sys
r = sys.stdin.read()
print(json.dumps({'decision': 'block', 'reason': r}))
" 2>/dev/null
  fi
fi

exit 2
