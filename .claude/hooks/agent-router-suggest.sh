#!/usr/bin/env bash
# agent-router-suggest.sh — UserPromptSubmit hook.
#
# Reads the freshly submitted user prompt from stdin (Claude Code passes
# {"prompt": "..."} as JSON), runs the agent-router skill, and emits an
# additionalContext suggestion when the router has high confidence in a
# named specialist. Fail-open: any error returns 0 with no context injection
# so the user prompt continues unchanged.
#
# Activation:
#   Wired via .claude/hooks/dispatcher-manifest.tsv (UserPromptSubmit, advisory
#   channel), gated by feature toggle feature_agent_router_suggest_enabled
#   (default ON). Disable per-repo with `hc-config.sh --feature
#   agent_router_suggest=false` or env HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false.
#   Confidence threshold (suggest vs stay quiet) defaults to 0.5; set
#   AGENT_ROUTER_SUGGEST_THRESHOLD in env to override.
#
# Phase 2 — Hybrid mode (task #96 P2-5、yml 3 key SSoT + env 互換層):
#   yml SSoT (harness-config.yml):
#     feature_agent_router_llm_fallback_enabled  (default false = OFF)
#     agent_router_llm_budget_usd_per_day        (default 0.1)
#     agent_router_llm_similarity_threshold      (default 0.7)
#   env 互換層 (既存 env は保持、明示 set は yml より優先):
#     AGENT_ROUTER_LLM_FALLBACK      on/1/true/yes で opt-in
#     AGENT_ROUTER_LLM_THRESHOLD     env 未 set かつ yml ON なら HC_ 値を export
#     AGENT_ROUTER_LLM_MODEL         router.py が env 継承 (hook 透過)
#     AGENT_ROUTER_LLM_TIMEOUT       同上
#     AGENT_ROUTER_LLM_MAX_ATTEMPTS  同上
#     AGENT_ROUTER_LLM_BUDGET_USD    同上 (per-call cap、per-day 集計とは別軸)
#   env 制御 mechanism は export のみ (unset / inline prefix は禁止、drift 予防)。
#   env 反映は explicit subshell `( export ...; python3 ... )` で行い、
#   hook プロセス shell の env を汚染しない。
#
# Debug options (task #96 iter fix、smoke assertion 用 — draft §3.3 補遺):
#   HC_AGENT_ROUTER_DEBUG_ENV=1
#     subshell 内で python3 起動直前に AGENT_ROUTER_LLM_FALLBACK / _THRESHOLD の
#     effective 値を stderr に 1 行 dump ("[agent-router debug] subshell ..." 形式)。
#     smoke が subshell 内 export 契約 (yml opt-in wiring / budget 強制 disable / threshold
#     override) を tautology 無しで直接検証するために使う。default OFF (production 静音)。
#   HC_AGENT_ROUTER_DEBUG_BUDGET=1
#     budget 集計直後に _budget_used / _budget_limit / effective_on / fallback_export を
#     stderr に 1 行 dump ("[agent-router debug] budget_used=..." 形式)。
#     smoke が hook 内 awk filter (`NF>0 && $1 ~ /^[0-9]+(\.[0-9]+)?$/`) の drift を検出
#     するために使う (smoke 側で awk 式を複製すると tautology 化する pitfall を回避)。
#
# Notes:
#   - This hook is OPTIONAL. The router skill works without it; the hook
#     just removes one round-trip for the main agent.
#   - The hook does NOT rewrite tool inputs — that requires a SubagentStart
#     hook which Claude Code does not currently expose. The hook only adds
#     a contextual hint.

set -uo pipefail  # task-22 W1: errexit 外し SIGPIPE 141 サイレント死を防止 (CLAUDE.md Critical Lessons HIGH)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- feature gate (task-81、3 点セット規範) ---
# config-loader.sh は is_feature_enabled / HC_* を提供 (fail-open 設計)。
# dispatcher も manifest feature_key で gate するが、直接起動経路でも OFF を保証するため
# hook 冒頭でも gate する。OFF なら stdin を消費せず即 no-op exit 0。
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh"
fi
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled agent_router_suggest; then
    exit 0   # feature OFF で no-op
fi

# --- LLM fallback child toggle + env 互換層 (task #96 Step 1、draft §3.3) ---
# 4 分岐決定木 (yml × env) で最終 effective 状態と export 予定を決める。
# 判定は変数の宣言有無 (${VAR+x}) を軸にし、値の空/非空とは区別する。
#
#   yml=false + env 未 set → 何もしない (default OFF、既存動作)
#   yml=false + env set    → env 保持、stderr WARN 1 行 (env 互換層)
#   yml=true  + env 未 set → subshell で export AGENT_ROUTER_LLM_FALLBACK=on
#   yml=true  + env set    → env 保持 (env 優先、WARN なし)
_llm_yml_on=0
if command -v is_feature_enabled >/dev/null 2>&1 && is_feature_enabled agent_router_llm_fallback; then
    _llm_yml_on=1
fi

_llm_env_set=0
if [ -n "${AGENT_ROUTER_LLM_FALLBACK+x}" ]; then
    _llm_env_set=1
fi

# subshell への export 予定値 (空文字なら export しない、drift 予防で 1 mechanism 固定)
_llm_fallback_export=""
if [ "$_llm_yml_on" = "1" ] && [ "$_llm_env_set" = "0" ]; then
    _llm_fallback_export="on"
elif [ "$_llm_yml_on" = "0" ] && [ "$_llm_env_set" = "1" ]; then
    printf '[agent-router] WARN: yml=false but env AGENT_ROUTER_LLM_FALLBACK=%s takes precedence (env 互換層)\n' "${AGENT_ROUTER_LLM_FALLBACK}" >&2
fi

# effective state (下流の threshold / budget check 用)
_llm_effective_on=0
if [ "$_llm_env_set" = "1" ]; then
    # env 明示 set 済 — 値の truthy 判定 (router.py _env_truthy と整合)
    _lc="$(printf '%s' "${AGENT_ROUTER_LLM_FALLBACK}" | tr '[:upper:]' '[:lower:]')"
    case "$_lc" in
        on|1|true|yes) _llm_effective_on=1 ;;
        *)             _llm_effective_on=0 ;;
    esac
    unset _lc
elif [ "$_llm_yml_on" = "1" ]; then
    _llm_effective_on=1
fi

# threshold override: env 未 set かつ effective ON → HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD
# env 既 set は上書きしない (env 優先、既存動作維持)
_llm_threshold_export=""
if [ "$_llm_effective_on" = "1" ] \
   && [ -z "${AGENT_ROUTER_LLM_THRESHOLD+x}" ] \
   && [ -n "${HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD-}" ]; then
    _llm_threshold_export="$HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD"
fi

# --- budget 累積 check (draft §3.3 step 3) ---
# effective ON かつ HC_AGENT_ROUTER_LLM_BUDGET_USD_PER_DAY > 0 → 当日累積を集計
# 超過なら fallback を強制 OFF (cost gate は env priority より上位、cost 保護のため)
_budget_dir="$SCRIPT_DIR/../.workflow-state/agent-router-llm-budget"
_budget_today=""
_budget_file=""
_budget_limit="${HC_AGENT_ROUTER_LLM_BUDGET_USD_PER_DAY:-0}"
if [ "$_llm_effective_on" = "1" ] \
   && awk -v v="$_budget_limit" 'BEGIN{exit !(v+0 > 0)}'; then
    _budget_today="$(date -u +%Y-%m-%d 2>/dev/null || echo unknown)"
    _budget_file="$_budget_dir/$_budget_today.usd"
    _budget_used="0"
    if [ -f "$_budget_file" ]; then
        # valid numeric line のみ合計 (fail-open: 空行 / 非数値行は silent skip、
        # under-counting 側に drift しないよう filter で strict 数値判定)
        _budget_used="$(awk 'NF>0 && $1 ~ /^[0-9]+(\.[0-9]+)?$/ {sum+=$1} END{printf "%.6f\n", sum+0}' "$_budget_file" 2>/dev/null || echo 0)"
    fi
    if awk -v u="$_budget_used" -v l="$_budget_limit" 'BEGIN{exit !(u+0 >= l+0)}'; then
        printf '[agent-router] WARN: daily budget $%s/$%s exceeded, LLM fallback disabled for today\n' "$_budget_used" "$_budget_limit" >&2
        # cost 保護のため env 優先を上回って強制 off (draft §3.3 step 3 注記)
        _llm_fallback_export="off"
        _llm_effective_on=0
        _llm_threshold_export=""   # fallback off なら threshold export も無効化
    fi
    # debug dump: budget_used / limit / effective_on / fallback_export を stderr に 1 行
    # (smoke が hook 内 awk filter drift を検出するため、tautology 無しで直接検証する経路)。
    if [ "${HC_AGENT_ROUTER_DEBUG_BUDGET:-0}" = "1" ]; then
        printf '[agent-router debug] budget_used=%s limit=%s effective_on=%s fallback_export=%s\n' \
            "$_budget_used" "$_budget_limit" "$_llm_effective_on" "$_llm_fallback_export" >&2
    fi
    unset _budget_used
fi

# --- 既存経路 (prompt 抽出 → router.py 起動 → suggestion 出力) ---
THRESHOLD="${AGENT_ROUTER_SUGGEST_THRESHOLD:-0.5}"
ROUTER_PY="${SCRIPT_DIR}/../skills/agent-router/router.py"

if [[ ! -f "${ROUTER_PY}" ]]; then
    # Skill not installed — silently no-op.
    exit 0
fi

# Read stdin (Claude Code JSON payload). If python isn\'t available, no-op.
if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

PAYLOAD="$(cat)"

PROMPT="$(printf '''%s''' "${PAYLOAD}" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get('''prompt''', ''''''), end='''''')
except Exception:
    pass
")"

if [[ -z "${PROMPT}" ]]; then
    exit 0
fi

# Build router args. The router itself reads AGENT_ROUTER_LLM_FALLBACK and
# friends from env, so we forward them via explicit subshell export
# (parent hook shell not polluted, drift 予防で export 1 mechanism 固定)。
ROUTER_ARGS=(--stdin --no-record)

# Route the prompt inside a subshell. The subshell isolates env exports so
# they cannot leak to the hook shell or its parent (Claude Code). The router
# itself fails open (exit 2 on error) → `|| echo '{"fallback": true}'` covers it.
ROUTING="$(
    (
        if [ -n "$_llm_fallback_export" ]; then
            export AGENT_ROUTER_LLM_FALLBACK="$_llm_fallback_export"
        fi
        if [ -n "$_llm_threshold_export" ]; then
            export AGENT_ROUTER_LLM_THRESHOLD="$_llm_threshold_export"
        fi
        # debug dump: subshell 内の effective env を stderr に 1 行
        # (smoke が subshell 内 export 契約 = yml opt-in wiring / budget 強制 disable /
        # threshold override を tautology 無しで直接検証するため。process 境界越しでは
        # env leak を assertion 不能である事の代替検証経路)。
        if [ "${HC_AGENT_ROUTER_DEBUG_ENV:-0}" = "1" ]; then
            printf '[agent-router debug] subshell AGENT_ROUTER_LLM_FALLBACK=%s AGENT_ROUTER_LLM_THRESHOLD=%s\n' \
                "${AGENT_ROUTER_LLM_FALLBACK:-unset}" "${AGENT_ROUTER_LLM_THRESHOLD:-unset}" >&2
        fi
        printf '''%s''' "${PROMPT}" | python3 "${ROUTER_PY}" "${ROUTER_ARGS[@]}" 2>/dev/null || echo '''{"fallback": true}'''
    )
)"

# --- budget 累積 append (draft §3.3 step 4) ---
# router.py が llm_used=true を返した場合、当日 file に llm_cost_usd を 1 行 append。
# effective_on の判定は event 時点の状態 (budget 超過で off に落ちた場合はここに到達しない)。
if [ "$_llm_effective_on" = "1" ] && [ -n "$_budget_today" ] && [ -n "$_budget_file" ]; then
    _llm_cost="$(printf '''%s''' "$ROUTING" | python3 -c "
import json, sys
try:
    r = json.loads(sys.stdin.read())
    if r.get('''llm_used'''):
        c = float(r.get('''llm_cost_usd''', 0.0) or 0.0)
        if c > 0:
            print(c)
except Exception:
    pass
" 2>/dev/null || echo "")"
    if [ -n "$_llm_cost" ] && awk -v v="$_llm_cost" 'BEGIN{exit !(v+0 > 0)}'; then
        mkdir -p "$_budget_dir" 2>/dev/null || true
        printf '%s\n' "$_llm_cost" >> "$_budget_file" 2>/dev/null || true
    fi
    unset _llm_cost
fi

# Decide whether to suggest. Stay quiet on fallback or low confidence.
SUGGESTION="$(printf '''%s''' "${ROUTING}" | python3 -c "
import json, sys, os
threshold = float(os.environ.get('''AGENT_ROUTER_SUGGEST_THRESHOLD''', '''0.5'''))
try:
    r = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
if r.get('''fallback'''):
    sys.exit(0)
conf = float(r.get('''confidence''', 0.0))
if conf < threshold:
    sys.exit(0)
agent = r.get('''agent''', '''''')
matched = ''', '''.join(r.get('''matched_keywords''', [])) or r.get('''reason''', '''''')
extra = ''''''
if r.get('''llm_used'''):
    extra = f''' [hybrid: llm-selector confirmed]'''
if r.get('''cycle_broken'''):
    extra += ''' [cycle-broken]'''
print(
    f'''[agent-router suggestion] This prompt looks like a job for the '''
    f'''"{agent}" subagent (confidence={conf:.2f}, matched: {matched}){extra}. '''
    f'''Consider Agent(subagent_type="{agent}", ...) instead of general-purpose.'''
)
")"

if [[ -n "${SUGGESTION}" ]]; then
    # additionalContext is the canonical channel for UserPromptSubmit hooks
    # to inject context into the model\'s working set.
    printf '''%s\n''' "${SUGGESTION}"
fi

exit 0
