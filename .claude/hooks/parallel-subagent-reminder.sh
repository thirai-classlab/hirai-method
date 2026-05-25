#!/usr/bin/env bash
# parallel-subagent-reminder.sh — PreToolUse(Agent) hook (task #38 Step 1 サブ Y)
#
# 役割:
#   PreToolUse(Agent) で発火し、以下 2 観点で <system-reminder> を注入する
#   (BLOCK しない、fail-open):
#
#   (A) 並列性 reminder (Case 1-5):
#       直近 TTL (default 300sec) 内に他 Agent 起動なし、かつ task description に
#       並列性 keyword (実装/fix/refactor/設計/新設/拡張/改修) を含む場合、
#       「並列起動を検討せよ」warning を注入する。
#       除外: "reviewer" / "review" / "監査" / "audit" は skip。
#
#   (B) agent type 選定 reminder (Case 6-8):
#       tool_input.subagent_type == "general-purpose" かつ task description に
#       専門 type 適合 keyword 検出時、「専門 type 推奨」warning を注入する。
#       keyword → type mapping は本 file 内 hardcode default (採用者 yaml 編集不要、
#       draft §4.5.0 設定不要原則)。env HC_AGENT_TYPE_KEYWORD_MAPPING で任意 override。
#
# 起源:
#   - 設計 draft: docs/draft/parallel-subagent-enforcement.md §4.2-4.5
#   - 規範:       .claude/rules/development-process.md (parallel subagent 強制)
#   - task:       docs/tasks/task-38-parallel-subagent-enforcement.md Step 1
#   - 既存類似:   loop-auto-progress-reminder.sh / autonomous-action-guard.sh の
#                 JSON parse / fail-open pattern
#
# 制約:
#   - file-top に `set -euo pipefail` を書かない (CLAUDE.md Critical Lessons HIGH:
#     feedback_set_e_in_sourced_libs.md)。実装本体は subshell 関数化で局所化する。
#   - 全失敗経路 exit 0 (BLOCK しない、fail-open)。
#
# 環境変数 (env override > YAML > defaults):
#   HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false  reminder 全停止 (bypass)
#   HC_PARALLEL_SUBAGENT_TTL_SEC=300             state file TTL (秒)
#   HC_AGENT_TYPE_KEYWORD_MAPPING=...            keyword → type mapping override
#                                                (改行区切り "keyword|type" pair。
#                                                空 / 未設定なら hook 内 default 使用)
#
# State:
#   .claude/.parallel-subagent-state/recent.json   ... 直近 N=TTL 秒の起動履歴 (軽量 JSON 配列)
#
# Stdin:  PreToolUse(Agent) JSON
# Stdout: 注入する system-reminder ({"hookSpecificOutput":{...,"additionalContext":...}})
#         または `{}` (注入なし)
# Stderr: 未使用 (errornous diagnostics は silent)
# Exit:   常に 0 (fail-open)

set -u

# stdin を必ず消費して保持 (JSON 1 件想定)
input=$(cat 2>/dev/null || true)

# --- mode / config 読み込み (best-effort) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# --- 早期 bypass ---
if [ "${HC_PARALLEL_SUBAGENT_REMINDER_ENABLED:-true}" = "false" ]; then
    echo '{}'
    exit 0
fi

# --- 依存チェック (jq 不在は silent skip) ---
if ! command -v jq >/dev/null 2>&1; then
    echo '{}'
    exit 0
fi

_psr_main() (
    set -uo pipefail

    local ttl_sec="${HC_PARALLEL_SUBAGENT_TTL_SEC:-300}"
    case "$ttl_sec" in
      ''|*[!0-9]*) ttl_sec=300 ;;
    esac

    # state dir 決定
    local repo_root
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
        repo_root="$CLAUDE_PROJECT_DIR"
    elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        :
    else
        repo_root="$(pwd)"
    fi

    local state_dir="${repo_root}/.claude/.parallel-subagent-state"
    local state_file="${state_dir}/recent.json"
    mkdir -p "$state_dir" 2>/dev/null || { echo '{}'; exit 0; }

    # --- tool_input から subagent_type / description / prompt を抽出 ---
    local subagent_type description prompt task_desc
    subagent_type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null || echo "")
    description=$(printf '%s' "$input" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
    prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null || echo "")
    # description + prompt 両方を結合して keyword 検出 (verbose な prompt の長文 keyword も拾う)
    task_desc="${description}"$'\n'"${prompt}"

    # --- atomic-mkdir lock で recent.json read-modify-write ---
    # state file race 回避 (task-34 iter3 pattern 流用):
    # `<state_file>.lock.d` で mkdir-based atomic lock、100 retries x 50ms (合計 5sec 上限)
    local lock_dir="${state_file}.lock.d"
    local i=0
    while [ $i -lt 100 ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            break
        fi
        sleep 0.05
        i=$((i + 1))
    done
    # lock 取れなくても fail-open (recent.json read-only に格下げして続行)

    local now
    now=$(date +%s 2>/dev/null || echo 0)
    case "$now" in
      ''|*[!0-9]*) now=0 ;;
    esac

    # --- recent.json 読み込み + TTL filter ---
    # 形式: [{"ts": <unix>, "type": "<subagent_type>"}, ...]
    local recent_active_count=0
    local existing="[]"
    if [ -f "$state_file" ]; then
        existing=$(cat "$state_file" 2>/dev/null || echo "[]")
        # 不正 JSON 防御
        if ! printf '%s' "$existing" | jq -e 'type == "array"' >/dev/null 2>&1; then
            existing="[]"
        fi
    fi

    # TTL filter (now - ts < ttl_sec のもののみ残す) + 件数集計
    local cutoff=$((now - ttl_sec))
    local filtered
    filtered=$(printf '%s' "$existing" | jq --argjson cutoff "$cutoff" \
        '[.[] | select(.ts >= $cutoff)]' 2>/dev/null || echo "[]")
    recent_active_count=$(printf '%s' "$filtered" | jq 'length' 2>/dev/null || echo 0)
    case "$recent_active_count" in
      ''|*[!0-9]*) recent_active_count=0 ;;
    esac

    # --- 本起動を append + write back ---
    local new_entry
    new_entry=$(jq -nc --argjson ts "$now" --arg type "$subagent_type" \
        '{ts: $ts, type: $type}' 2>/dev/null || echo "{}")
    local updated
    updated=$(printf '%s' "$filtered" | jq --argjson e "$new_entry" '. + [$e]' 2>/dev/null || echo "$filtered")
    if [ -d "$lock_dir" ]; then
        # lock 保持中: atomic temp file + mv で書き込み
        local tmp="${state_file}.tmp.$$"
        printf '%s' "$updated" > "$tmp" 2>/dev/null && mv -f "$tmp" "$state_file" 2>/dev/null
    fi
    # lock 解放
    rmdir "$lock_dir" 2>/dev/null || true

    # --- (A) 並列性 reminder 判定 (Case 1-5) ---
    # 並列性 keyword 検出 (default、env override 可)
    local parallel_keywords='実装|fix|refactor|設計|新設|拡張|改修'
    local exclude_keywords='reviewer|review|監査|audit'

    local should_remind_parallel=0
    if [ "$recent_active_count" -le 1 ]; then
        # 直近 TTL 内に他 Agent 起動なし (本起動含めて 1 件以下 = 単発)
        if printf '%s' "$task_desc" | grep -qE "$parallel_keywords" 2>/dev/null; then
            # 除外 keyword 含むなら skip
            if ! printf '%s' "$task_desc" | grep -qE "$exclude_keywords" 2>/dev/null; then
                should_remind_parallel=1
            fi
        fi
    fi

    # --- (B) agent type 選定 reminder 判定 (Case 6-8) ---
    # default keyword → type mapping (hardcode、draft §4.5.0 設定不要原則)
    # 形式: "<keyword>|<recommended_type>" の改行区切り
    local default_mapping
    default_mapping='smoke 拡張|test-automator
test 追加|test-automator
test 修正|test-automator
regression test|test-automator
refactor|refactoring-specialist
関数分割|refactoring-specialist
cleanup|refactoring-specialist
dead code|refactoring-specialist
build error|build-error-resolver
compile error|build-error-resolver
type error|build-error-resolver
bash 品質|code-reviewer
shellcheck|code-reviewer
subshell|code-reviewer
設計レビュー|architect-reviewer
architecture review|architect-reviewer'

    local mapping="${HC_AGENT_TYPE_KEYWORD_MAPPING:-$default_mapping}"

    local should_remind_type=0
    local recommended_type=""
    local matched_keyword=""
    if [ "$subagent_type" = "general-purpose" ]; then
        # mapping を 1 行ずつ走査
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local kw="${line%%|*}"
            local typ="${line#*|}"
            [ -z "$kw" ] && continue
            [ "$kw" = "$line" ] && continue  # `|` 不在の不正行 skip
            if printf '%s' "$task_desc" | grep -qF "$kw" 2>/dev/null; then
                should_remind_type=1
                recommended_type="$typ"
                matched_keyword="$kw"
                break
            fi
        done <<< "$mapping"
    fi

    # --- system-reminder 生成 ---
    if [ "$should_remind_parallel" -eq 0 ] && [ "$should_remind_type" -eq 0 ]; then
        echo '{}'
        exit 0
    fi

    local msg=""
    if [ "$should_remind_parallel" -eq 1 ]; then
        msg+="[parallel-subagent-reminder] 並列性 hint:
- 直近 ${ttl_sec}sec 内に他 Agent 起動が検出されません (本起動が単発)。
- task description に並列性 keyword (実装/fix/refactor/設計/新設/拡張/改修) が含まれます。
- 独立 file 領域 / 独立 task に分割可能なら、複数 subagent を **同一 message 内で並列起動**
  (run_in_background: true) すると wall-clock を短縮できます。
- 規範: .claude/rules/development-process.md (parallel subagent)
- bypass: HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false
"
    fi

    if [ "$should_remind_type" -eq 1 ]; then
        if [ -n "$msg" ]; then
            msg+=$'\n'
        fi
        msg+="[parallel-subagent-reminder] agent type 選定 hint:
- subagent_type=general-purpose が指定されていますが、task description に keyword
  「${matched_keyword}」が検出されました。
- 推奨専門 type: **${recommended_type}**
- 専門 agent は domain 適合の prompt / 推奨 tool セットを持ち、general-purpose より
  深い検証が可能です。意図的に general-purpose を選んだ場合は無視してください。
- mapping override: HC_AGENT_TYPE_KEYWORD_MAPPING (改行区切り keyword|type)
- bypass: HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false
"
    fi

    # additionalContext として注入 (BLOCK しない、PreToolUse 標準形式)
    jq -n --arg ctx "$msg" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }' 2>/dev/null || echo '{}'
    exit 0
)

_psr_main "$@"
exit 0
