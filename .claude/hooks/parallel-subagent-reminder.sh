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
#   - task:       docs/tasks/task-38-parallel-subagent-enforcement.md Step 1-2
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
#   HC_PARALLEL_SUBAGENT_STATE_DIR=<path>        state dir override
#                                                (production state 汚染回避用、
#                                                 未設定なら repo_root/.claude/.parallel-subagent-state/)
#   HC_AGENT_TYPE_KEYWORD_MAPPING=...            keyword → type mapping override
#                                                (改行区切り "keyword|type" pair。
#                                                空 / 未設定なら hook 内 default 使用)
#   ECC_BYPASS_REASON=<text>                     bypass 理由 (bypass.log に記録)
#
# State:
#   .claude/.parallel-subagent-state/recent.json   ... 直近 N=TTL 秒の起動履歴 (軽量 JSON 配列)
#   ※ production state 汚染は HC_PARALLEL_SUBAGENT_STATE_DIR で隔離可能。
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

# --- 早期 bypass (HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false) ---
# Fix 2 (R2 F-01 + R6 H-2): bypass.log に記録してから exit
if [ "${HC_PARALLEL_SUBAGENT_REMINDER_ENABLED:-true}" = "false" ]; then
    # bypass-logger.sh が存在すれば helper 使用、なければ inline で記録
    if [ -f "$SCRIPT_DIR/lib/bypass-logger.sh" ]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/lib/bypass-logger.sh" 2>/dev/null || true
        if command -v log_bypass >/dev/null 2>&1; then
            log_bypass "parallel-subagent-reminder" \
                "HC_PARALLEL_SUBAGENT_REMINDER_ENABLED" \
                "${ECC_BYPASS_REASON:-(not provided)}" 2>/dev/null || true
        fi
    else
        # fallback: 直接 append (autonomous-action-guard.sh と同 pattern)
        _repo_root_for_log="${CLAUDE_PROJECT_DIR:-$(pwd)}"
        _bypass_log_dir="${_repo_root_for_log}/.claude/.workflow-state"
        _bypass_log_file="${_bypass_log_dir}/bypass.log"
        mkdir -p "$_bypass_log_dir" 2>/dev/null || true
        printf '%s | %s | parallel-subagent-reminder | HC_PARALLEL_SUBAGENT_REMINDER_ENABLED | %s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
            "${CLAUDE_SESSION_ID:-unknown}" \
            "${ECC_BYPASS_REASON:-(not provided)}" \
            >> "$_bypass_log_file" 2>/dev/null || true
    fi
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

    # --- state dir 決定 ---
    # Fix 5 (R3): production state 汚染対策
    #   - HC_PARALLEL_SUBAGENT_STATE_DIR が設定済なら最優先採用 (production と test の隔離可能)
    #   - 次に CLAUDE_PROJECT_DIR (Claude 公式の project root)
    #   - 最後に git rev-parse でフォールバック
    #   - すべて失敗時は fail-open (silent + warn stderr + exit 0)
    local state_dir
    if [ -n "${HC_PARALLEL_SUBAGENT_STATE_DIR:-}" ]; then
        state_dir="${HC_PARALLEL_SUBAGENT_STATE_DIR}"
    else
        local repo_root=""
        if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
            repo_root="$CLAUDE_PROJECT_DIR"
        elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
            :
        else
            # 解決失敗: fail-open (stderr に diagnostic、state 汚染を避けるため exit)
            echo "[parallel-subagent-reminder] WARN: repo_root unresolved, skipping" >&2
            echo '{}'
            exit 0
        fi
        # repo_root が妥当な dir か最終 sanity check
        if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
            echo "[parallel-subagent-reminder] WARN: invalid repo_root '$repo_root', skipping" >&2
            echo '{}'
            exit 0
        fi
        state_dir="${repo_root}/.claude/.parallel-subagent-state"
    fi

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
    # Fix 1 (R5 H1): lock 取得失敗時の data loss + 他者 lock 破壊事故を防止
    #   - acquired=0 を初期化、mkdir 成功時のみ acquired=1
    #   - 100 retries (50ms x 100 = 5sec 上限) 失敗時は acquired=0 のまま break
    #   - acquired=0 なら write back を skip + warn stderr
    #   - 終了時 acquired=1 の場合のみ rmdir で解放 (所有判定)
    local lock_dir="${state_file}.lock.d"
    local acquired=0
    local i=0
    while [ $i -lt 100 ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            acquired=1
            break
        fi
        sleep 0.05
        i=$((i + 1))
    done
    if [ "$acquired" -eq 0 ]; then
        echo "[parallel-subagent-reminder] WARN: lock acquire failed (100 retries), skip write" >&2
        # write back せず、判定のみ進める (read-only 格下げ)
    fi

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
    # Fix 3 (R5 H4): jq schema 不正時の偽 entry 混入を防止
    #   - new_entry が空文字 / 不正 JSON / ts キー欠落なら append せず filtered のみ write back
    #   - 検出: jq 'has("ts")' で ts キーの存在検証
    local new_entry
    new_entry=$(jq -nc --argjson ts "$now" --arg type "$subagent_type" \
        '{ts: $ts, type: $type}' 2>/dev/null || echo "")
    local entry_valid=0
    if [ -n "$new_entry" ]; then
        if [ "$(printf '%s' "$new_entry" | jq -r 'has("ts")' 2>/dev/null)" = "true" ]; then
            entry_valid=1
        fi
    fi

    local updated
    if [ "$entry_valid" -eq 1 ]; then
        updated=$(printf '%s' "$filtered" | jq --argjson e "$new_entry" '. + [$e]' 2>/dev/null || echo "$filtered")
    else
        # new_entry 不正: filtered のみで上書き (偽 entry 混入を防ぐ)
        updated="$filtered"
    fi

    # write back は lock 取得成功時のみ
    if [ "$acquired" -eq 1 ]; then
        local tmp="${state_file}.tmp.$$"
        printf '%s' "$updated" > "$tmp" 2>/dev/null && mv -f "$tmp" "$state_file" 2>/dev/null
    fi
    # Fix 1 続き: 所有 lock のみ解放 (acquired=1 のとき)
    if [ "$acquired" -eq 1 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
    fi

    # --- (A) 並列性 reminder 判定 (Case 1-5) ---
    # Fix 7 (R5 M2): `fix` keyword に word boundary `\b` を付与し、prefix/affix 等の
    #                English word 内一致による誤検知を防ぐ。同様に `refactor` も `\b` で括る。
    # 注: 日本語 keyword は word boundary 不要 (CJK は word boundary が機能しない)。
    # Fix 8 (R4 M / R5 M1): `リファクタリング` (日本語長 word) を default mapping ではなく
    #                並列性 keyword 側にも追加 (refactor の日本語表記)。
    local parallel_keywords='実装|\bfix\b|\brefactor\b|リファクタリング|設計|新設|拡張|改修'
    # Fix 9 (R4-H2 HIGH): exclude_keywords に word boundary `\b` を付与。
    # 旧 `review` (boundary なし) は `preview` / `code-reviewer` 等の substring に
    # 誤マッチし、正当な並列性 warning を false-negative で抑制していた。
    # `reviewer` と `review` 両方を併記する理由: `reviewer` の `review` 部分は
    # 末尾境界 `\b` (e の後 r、word 境界不一致) を持たないため `\breview\b` 単独だと
    # `reviewer` を取りこぼす。両方明記で確実に除外する。
    # 日本語 (監査) は CJK で word boundary が機能しないため `\b` 不要。
    local exclude_keywords='\breviewer\b|\breview\b|監査|\baudit\b'

    local should_remind_parallel=0
    # --- 境界値 recent_active_count -le 1 の意図 (Fix 4: R2 F-03 + R5 + R6) ---
    # 判定: TTL filter 後の他 Agent 起動数が 1 件以下 → 単独起動扱い (本起動を含む count)
    #   count=0: 完全初回起動 (本起動の append 後 0 になるケースは lock 失敗で write skip 時のみ)
    #   count=1: 直前 TTL 内に 1 件 (本起動が初回 or 2 件目だが保守的に warning 出す)
    #   count>=2: 並列起動済み、warning 不要
    # 注: 本判定は append 前の recent_active_count を参照する (filtered で計算済み)。
    if [ "$recent_active_count" -le 1 ]; then
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
    # Fix 8 (R4 M / R5 M1): `リファクタリング` を default mapping に追加 (日本語長 word)
    local default_mapping
    default_mapping='smoke 拡張|test-automator
test 追加|test-automator
test 修正|test-automator
regression test|test-automator
refactor|refactoring-specialist
リファクタリング|refactoring-specialist
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
- task description に並列性 keyword (実装/fix/refactor/設計/新設/拡張/改修/リファクタリング) が含まれます。
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

# Fix 6 (R5 H2): fail-open subshell exit code 統一
#   - subshell が non-zero 終了でも親 shell の exit 0 で覆い隠す契約を明示
#   - これにより hook 全体が常に exit 0 (BLOCK しない、fail-open) を保証
_psr_main "$@" || true
exit 0
