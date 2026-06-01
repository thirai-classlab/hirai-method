#!/usr/bin/env bash
# reviewer-count-guard.sh — PreToolUse(Agent) hook (task-64 Step 5)
#
# 役割:
#   PreToolUse(Agent) で発火し、同一 session 内に起動された **review subagent** の
#   累計数をカウントする。count が `review_max_count_<推定 cat>` を超過したら
#   <system-reminder> で **warn** を注入する (BLOCK しない、fail-open)。
#
#   reviewer 数上限 (review_max_count_*) は honor-system (main が手で hc-config.sh
#   --get を読む) だけだと失念で超過する (task-63 Step 6 で 6 体起動 max 無視の実例)。
#   本 hook は採用 6 条 4 / W1-W3 review の数値上限を機械補強する。
#
# 設計起源:
#   - draft: docs/draft/reviewer-count-enforcement.md §3.3 (P2 強制 hook)
#   - task:  docs/tasks/task-64-reviewer-count-enforcement.md Step 5
#   - 既存類似 (state / lock / fail-open pattern): parallel-subagent-reminder.sh
#            (本 hook はその「review 版カウンタ」)
#   - root cause A (honor-system 不在) の機械化
#
# 判定ロジック:
#   1. tool_input.{description,prompt} を結合し review subagent か判定:
#        review keyword (テスト設計レビュー / test-design / design-review /
#        module-review / system-review / reviewer / レビュー 等) を含むか
#      → review でなければ count せず pass ({} 出力)
#   2. review category 推定 (keyword 優先順):
#        テスト設計レビュー / test-design / テスト設計 → test
#        design-review / 設計レビュー                  → design
#        module-review / モジュールレビュー            → module
#        system-review / システムレビュー              → system
#        (上記不一致だが reviewer/レビュー一般)        → unknown (max(全 max) を緩い上限に)
#   3. 同一 session の review 起動数を state file で increment (本起動含む count)
#   4. count > review_max_count_<cat> なら <system-reminder> で warn
#      (BLOCK しない、exit 0)。category 推定不確実のため過剰 block 回避。
#
# 制約:
#   - file-top に `set -euo pipefail` を書かない (CLAUDE.md Critical Lessons HIGH:
#     feedback_set_e_in_sourced_libs.md)。実装本体は subshell 関数化で局所化する。
#   - 全失敗経路 exit 0 (BLOCK しない、fail-open)。
#
# 環境変数 (env override > YAML > defaults):
#   HC_REVIEWER_COUNT_GUARD_ENABLED=false   guard 全停止 (bypass)
#   ECC_REVIEWER_COUNT_OFF=1                guard 全停止 (env 系統 bypass、bypass.log 記録)
#   HC_REVIEWER_COUNT_STATE_DIR=<path>     state dir override (test isolation 用)
#   HC_REVIEWER_COUNT_STATE_TTL_DAYS=<int> state prune 閾値 (日、default 7、<=0 で無効)
#   HC_REVIEW_MAX_COUNT_<CAT>=<int>        category 上限 override (config-loader 由来)
#   ECC_BYPASS_REASON=<text>               bypass 理由 (bypass.log に記録)
#
# Feature toggle:
#   feature_reviewer_count_guard_enabled: true  (yml)
#   → false なら冒頭で即 no-op exit 0
#
# State:
#   .claude/.reviewer-count-state/<session>.json
#     ... { "<cat>": <count>, ... } の累計 (session 単位、atomic-mkdir lock)
#   ※ HC_REVIEWER_COUNT_STATE_DIR で隔離可能。
#
# State prune (TTL、task-64 Step 6 F1):
#   session 単位 state file は放置すると無制限に蓄積する。本 hook は発火ごとに
#   best-effort prune を行う (HC_REVIEWER_COUNT_STATE_TTL_DAYS 日より古い *.json /
#   stale *.lock.d を削除)。prune 失敗で hook を止めない (fail-open 維持)。
#   HC_REVIEWER_COUNT_STATE_TTL_DAYS=<int>  prune 閾値 (default 7、0 以下で prune 無効)
#
# Stdin:  PreToolUse(Agent) JSON
# Stdout: 注入する system-reminder ({"hookSpecificOutput":{...,"additionalContext":...}})
#         または `{}` (注入なし)
# Exit:   常に 0 (fail-open)

set -u

# stdin を必ず消費して保持 (JSON 1 件想定)
input=$(cat 2>/dev/null || true)

# --- config 読み込み (best-effort) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# --- Feature toggle 参照 ---
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled reviewer_count_guard; then
    echo '{}'
    exit 0   # feature OFF で no-op
fi

# --- 早期 bypass (HC_REVIEWER_COUNT_GUARD_ENABLED=false / ECC_REVIEWER_COUNT_OFF=1) ---
# bypass.log に記録してから exit (parallel-subagent-reminder の流儀に合わせる)
_rcg_log_bypass() {
    local env_var="$1"
    if [ -f "$SCRIPT_DIR/lib/bypass-logger.sh" ]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/lib/bypass-logger.sh" 2>/dev/null || true
        if command -v log_bypass >/dev/null 2>&1; then
            log_bypass "reviewer-count-guard" "$env_var" \
                "${ECC_BYPASS_REASON:-(not provided)}" 2>/dev/null || true
            return 0
        fi
    fi
    # fallback: 直接 append (autonomous-action-guard.sh と同 pattern)
    local _repo_root_for_log="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    local _bypass_log_dir="${_repo_root_for_log}/.claude/.workflow-state"
    local _bypass_log_file="${_bypass_log_dir}/bypass.log"
    mkdir -p "$_bypass_log_dir" 2>/dev/null || true
    printf '%s | %s | reviewer-count-guard | %s | %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        "${CLAUDE_SESSION_ID:-unknown}" \
        "$env_var" \
        "${ECC_BYPASS_REASON:-(not provided)}" \
        >> "$_bypass_log_file" 2>/dev/null || true
}

if [ "${HC_REVIEWER_COUNT_GUARD_ENABLED:-true}" = "false" ]; then
    _rcg_log_bypass "HC_REVIEWER_COUNT_GUARD_ENABLED"
    echo '{}'
    exit 0
fi
if [ "${ECC_REVIEWER_COUNT_OFF:-0}" = "1" ]; then
    _rcg_log_bypass "ECC_REVIEWER_COUNT_OFF"
    echo '{}'
    exit 0
fi

# --- 依存チェック (jq 不在は silent skip) ---
if ! command -v jq >/dev/null 2>&1; then
    echo '{}'
    exit 0
fi

_rcg_main() (
    set -uo pipefail

    # --- state dir 決定 (parallel-subagent-reminder と同方式) ---
    local state_dir
    if [ -n "${HC_REVIEWER_COUNT_STATE_DIR:-}" ]; then
        state_dir="${HC_REVIEWER_COUNT_STATE_DIR}"
    else
        local repo_root=""
        if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
            repo_root="$CLAUDE_PROJECT_DIR"
        elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
            :
        else
            echo "[reviewer-count-guard] WARN: repo_root unresolved, skipping" >&2
            echo '{}'
            exit 0
        fi
        if [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; then
            echo "[reviewer-count-guard] WARN: invalid repo_root '$repo_root', skipping" >&2
            echo '{}'
            exit 0
        fi
        state_dir="${repo_root}/.claude/.reviewer-count-state"
    fi

    # session 単位 state file (session_id 不在時は固定名で fallback)
    local session_id="${CLAUDE_SESSION_ID:-unknown}"
    # session_id を file-safe に (英数 _ - のみ許可)
    session_id=$(printf '%s' "$session_id" | tr -c '[:alnum:]_-' '_')
    [ -z "$session_id" ] && session_id="unknown"
    local state_file="${state_dir}/${session_id}.json"
    mkdir -p "$state_dir" 2>/dev/null || { echo '{}'; exit 0; }

    # --- best-effort state prune (task-64 Step 6 F1) ---
    # session 単位 state file / stale lock を TTL 経過で削除。無制限蓄積を防ぐ。
    # fail-open: prune 失敗 (find 不在 / permission 等) で hook を止めない。
    # 現行 session の state_file は本起動で mtime 更新されるため prune されない
    # (write back が mtime を現在時刻にする。read-only 格下げ時も seed が新しければ残る)。
    local prune_days="${HC_REVIEWER_COUNT_STATE_TTL_DAYS:-7}"
    case "$prune_days" in
        ''|*[!0-9]*) prune_days=7 ;;
    esac
    if [ "$prune_days" -gt 0 ]; then
        # 古い state file (*.json) を削除
        find "$state_dir" -maxdepth 1 -name '*.json' -type f -mtime "+${prune_days}" -delete 2>/dev/null || true
        # stale な lock dir (*.lock.d) も古ければ rmdir (best-effort、中身が空のときのみ成功)
        # find -delete は非空 dir を消せないため、まず内部 file を消してから dir を消す。
        find "$state_dir" -maxdepth 1 -name '*.lock.d' -type d -mtime "+${prune_days}" \
            -exec rm -rf {} + 2>/dev/null || true
    fi

    # --- tool_input から description / prompt を抽出して結合 ---
    local description prompt task_desc
    description=$(printf '%s' "$input" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
    prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' 2>/dev/null || echo "")
    task_desc="${description}"$'\n'"${prompt}"

    # --- review subagent か判定 ---
    # review keyword: review 系 command 名 + 日本語 review 表現 + reviewer/レビュー 一般。
    # 日本語 (CJK) は word boundary 非対応のため `\b` を付けない。
    # 英語 review/reviewer は word boundary で preview / overview の誤検知を回避。
    local review_keywords='テスト設計レビュー|設計レビュー|モジュールレビュー|システムレビュー|レビュー|test-design|design-review|module-review|system-review|\breviewer\b|\breview\b'
    if ! printf '%s' "$task_desc" | grep -qE "$review_keywords" 2>/dev/null; then
        # review subagent でない → count せず pass
        echo '{}'
        exit 0
    fi

    # --- review category 推定 (優先順、最も具体的な keyword から) ---
    local cat="unknown"
    if printf '%s' "$task_desc" | grep -qE 'テスト設計レビュー|test-design|テスト設計' 2>/dev/null; then
        cat="test"
    elif printf '%s' "$task_desc" | grep -qE 'design-review|設計レビュー' 2>/dev/null; then
        cat="design"
    elif printf '%s' "$task_desc" | grep -qE 'module-review|モジュールレビュー' 2>/dev/null; then
        cat="module"
    elif printf '%s' "$task_desc" | grep -qE 'system-review|システムレビュー' 2>/dev/null; then
        cat="system"
    fi
    # cat=unknown は reviewer/レビュー 一般 (max(全 max) を緩い上限に)

    # --- 上限値解決 (config-loader export 由来、clean 数値前提) ---
    # category 別 review_max_count_<cat>。unknown は全 max の最大値を緩い上限に。
    local max_test max_design max_module max_system
    max_test="${HC_REVIEW_MAX_COUNT_TEST:-10}"
    max_design="${HC_REVIEW_MAX_COUNT_DESIGN:-7}"
    max_module="${HC_REVIEW_MAX_COUNT_MODULE:-5}"
    max_system="${HC_REVIEW_MAX_COUNT_SYSTEM:-5}"
    # 数値 sanitize (非数値は default に戻す)
    case "$max_test" in   ''|*[!0-9]*) max_test=10 ;; esac
    case "$max_design" in ''|*[!0-9]*) max_design=7 ;; esac
    case "$max_module" in ''|*[!0-9]*) max_module=5 ;; esac
    case "$max_system" in ''|*[!0-9]*) max_system=5 ;; esac

    local max_cat
    case "$cat" in
        test)   max_cat="$max_test" ;;
        design) max_cat="$max_design" ;;
        module) max_cat="$max_module" ;;
        system) max_cat="$max_system" ;;
        *)
            # unknown: 全 max の最大値を緩い上限に
            max_cat="$max_test"
            [ "$max_design" -gt "$max_cat" ] && max_cat="$max_design"
            [ "$max_module" -gt "$max_cat" ] && max_cat="$max_module"
            [ "$max_system" -gt "$max_cat" ] && max_cat="$max_system"
            ;;
    esac

    # --- atomic-mkdir lock で state file read-modify-write ---
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
        echo "[reviewer-count-guard] WARN: lock acquire failed (100 retries), skip write" >&2
    fi

    # --- state file 読み込み (object: { "<cat>": <count> }) ---
    local existing='{}'
    if [ -f "$state_file" ]; then
        existing=$(cat "$state_file" 2>/dev/null || echo '{}')
        if ! printf '%s' "$existing" | jq -e 'type == "object"' >/dev/null 2>&1; then
            existing='{}'
        fi
    fi

    # --- 本起動を増分 (本起動含む count) ---
    local count
    count=$(printf '%s' "$existing" | jq -r --arg c "$cat" '(.[$c] // 0) + 1' 2>/dev/null || echo 1)
    case "$count" in
        ''|*[!0-9]*) count=1 ;;
    esac

    # --- write back (lock 取得成功時のみ) ---
    local updated
    updated=$(printf '%s' "$existing" | jq -c --arg c "$cat" --argjson n "$count" '.[$c] = $n' 2>/dev/null || echo "$existing")
    if [ "$acquired" -eq 1 ]; then
        local tmp="${state_file}.tmp.$$"
        printf '%s' "$updated" > "$tmp" 2>/dev/null && mv -f "$tmp" "$state_file" 2>/dev/null
        rmdir "$lock_dir" 2>/dev/null || true
    fi

    # --- count > max_cat なら warn 注入 (BLOCK しない) ---
    if [ "$count" -le "$max_cat" ]; then
        # 上限内 → 注入なし
        echo '{}'
        exit 0
    fi

    local cat_label="$cat"
    [ "$cat" = "unknown" ] && cat_label="不明 (reviewer 一般、緩い上限 = max(全 cat))"

    local msg
    msg="[reviewer-count-guard] reviewer 数上限 warn:
- 本 session の review subagent 起動数が ${count} 体に達しました (推定 category: ${cat_label})。
- review_max_count_${cat} = ${max_cat} を超過しています。
- yml 範囲遵守を推奨: bash .claude/scripts/hc-config.sh --get review_max_count_${cat} で上限を確認し、
  並列起動数 N が min ≤ N ≤ max に収まるよう絞り込んでください (採用 6 条 4 / workflow.md)。
- 値解決順: env(HC_REVIEW_*) > harness-config.local.yml > harness-config.yml > default。
- これは warn です (BLOCK しません)。意図的な超過 (category 誤推定 / 再 review round 等) なら無視してください。
- bypass: HC_REVIEWER_COUNT_GUARD_ENABLED=false / ECC_REVIEWER_COUNT_OFF=1
"

    jq -n --arg ctx "$msg" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            additionalContext: $ctx
        }
    }' 2>/dev/null || echo '{}'
    exit 0
)

# fail-open: subshell が non-zero 終了でも親 shell の exit 0 で覆い隠す
_rcg_main "$@" || true
exit 0
