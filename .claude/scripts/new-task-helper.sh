#!/usr/bin/env bash
# .claude/scripts/new-task-helper.sh
# task-33 Phase 2 Step 2.2: /new-task の 📝 → 🔲 update or append helper
# task-34 Step 4 iter2 fix: CRIT 3 + HIGH 8 件解消版
# task-34 Step 4 iter3 fix: MUST FIX 7 + SHOULD FIX 3 件解消版
# task-34 Step 4 iter4 fix: CR-001 (id overflow) + MED-001 (CR validation) 解消版
# task-34 Step 5 refactor: 3 観点 (持続可能性 / 汎用性 / 非冗長化) 改修版
#   - update_or_append_task_row を 5 関数に分割 (MED-002、持続可能性)
#   - _new_task_ensure_eol を tail -c 1 ベースに簡素化 (MED-003、持続可能性)
#   - behavior-preserving (外部 API 不変、内部 restructure のみ)
#
# 役割:
#   list.md に対し、同 ID + 同 slug の AND 一致 grep で既存 📝 行を検出し:
#     - 同 ID + 同 slug + 📝 既存 1 件      → 📝 → 🔲 update (行数増えず)
#     - 同 ID + 同 slug + 📝 既存 複数      → BLOCK (return 1)
#     - 同 ID + 同 slug + status 混在 (📝/🔲/✅) → BLOCK (C-03 解消)
#     - 同 ID + 別 slug + 📝 既存           → BLOCK (誤連番警告、C-01 / H-08 解消)
#     - 同 ID + 別 status (🔲/🔄/✅)        → BLOCK (重複起動 / 完了済 上書き防止)
#     - 完全不在                            → 末尾 append
#
# 規範:
#   .claude/rules/task-management.md §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」
#
# 設計原則:
#   - file-top に set -uo pipefail を書かない (CLAUDE.md Critical Lessons HIGH 遵守、H-06)
#   - 各関数で subshell 関数 `func() ( ... )` 化で局所化
#   - HC_TASK_DIR を config-loader 経由で参照 (Design Constraints 遵守、H-07)
#   - regex injection 防止: id / slug を escape (H-01)
#   - awk ENVIRON 経由で値受渡 (H-03 解消、backslash interpretation 回避)
#   - mktemp + trap cleanup (H-05 解消、tmp file race + leak 防止)
#   - printf '\n' EOL guard (H-04 解消、末尾改行欠落時の前行結合防止)
#   - UTF-8 multi-byte 回避: `grep -v "📝"` で 4-byte 絵文字 character class 問題 (H-02 解消)
#   - status 混在 conflict check (C-03 解消)
#   - slug 完全一致: kebab-word boundary `(^|[^a-zA-Z0-9-])slug([^a-zA-Z0-9-]|$)` (C-02 substring 誤マッチ防止)
#   - atomic-mkdir lock で parallel race condition 解消 (QA-C01/H-RC-01)
#   - leading zero id 数値正規化 (10#$id で 8 進解釈防止、QA-C02)
#   - row_content 改行 (LF/CR) input validation (QA-H01 + MED-001)
#   - tmp file を target_dir に配置 (cross-filesystem 非 atomic 回避、M-MV-01)
#   - id 18 桁超 reject で signed 64-bit overflow 防止 (CR-001)
#
# CLI entry point + source 両対応:
#   - source して `update_or_append_task_row` 関数を call
#   - 直接実行 `bash new-task-helper.sh update_or_append_task_row <id> <slug> <row_content> [list_md]`
#   - 互換: 旧 API `bash new-task-helper.sh <id> <slug> <row_content> [list_md]` も継続サポート

# --- regex escape (sed の BRE metachar) ---
# id / slug を grep -E / awk regex に渡す前に必ず escape する (H-01)
_new_task_escape_regex() (
    set -uo pipefail
    # shellcheck disable=SC2016 # sed '&' is regex backref, not shell variable
    printf '%s' "$1" | sed 's/[][\.*+?^$(){}|/\\]/\\&/g'
)

# --- list.md 末尾改行 guard (H-04) ---
# tail -c 1 は trailing newline を strip するため:
#   - non-empty 出力 → 末尾が non-LF → LF 追加必要
#   - empty 出力     → 末尾が LF → そのまま
# (Refactor 2 MED-003: od + tr 経由の脆い文字列比較を tail -c 1 性質に簡素化)
_new_task_ensure_eol() (
    set -uo pipefail
    local file="$1"
    [ -s "$file" ] || return 0
    local last_byte
    last_byte=$(tail -c 1 "$file")
    if [ -n "$last_byte" ]; then
        printf '\n' >> "$file"
    fi
)

# --- Refactor 1-1: 入力検証 (MED-002) ---
# raw_id / slug / row_content の validation を 1 関数に集約。
# stdout に正規化済 id (echo)、stderr に error message、exit 0/2
_new_task_validate_input() (
    set -uo pipefail
    local raw_id="$1" slug="$2" row_content="$3"

    # required check
    if [ -z "$raw_id" ] || [ -z "$slug" ] || [ -z "$row_content" ]; then
        echo "ERROR: id / slug / row_content は必須" >&2
        return 2
    fi

    # iter3 QA-C02: id 数値正規化 (leading zero 許容 → silent duplicate 防止)
    # 非数値文字を含む場合は error
    case "$raw_id" in
        ''|*[!0-9]*)
            echo "ERROR: id '$raw_id' は非負整数のみ (leading zero 許容、非数値文字不可)" >&2
            return 2
            ;;
    esac

    # iter4 CR-001: signed 64-bit overflow 防止
    # bash の $((10#X)) は signed 64-bit、上限 ~9.22e18 (19 桁) で overflow → 負数化 silent corruption
    # 例: "99999999999999999999999999" (26 桁) → $((10#$raw_id)) = -2537764290115403777
    # 対策: leading zero strip 後の長さで判定 (18 桁以下なら確実に 64-bit 範囲内)
    local stripped
    stripped=$(printf '%s' "$raw_id" | sed 's/^0*//')
    stripped="${stripped:-0}"
    if [ "${#stripped}" -gt 18 ]; then
        echo "ERROR: id '$raw_id' は 18 桁 (signed 64-bit 上限) を超える非対応値 (overflow 防止)" >&2
        return 2
    fi

    # iter3 QA-H01 + iter4 MED-001: row_content 改行 (LF/CR) input validation
    case "$row_content" in
        *$'\n'*|*$'\r'*)
            echo "ERROR: row_content に改行 (LF/CR) 不可 (list.md 行数破壊 / 表示破損 防止)" >&2
            return 2
            ;;
    esac

    # 10 進数強制 (bash 構文、"08" を 8 進と解釈させない)
    local id
    id=$((10#$raw_id))
    printf '%s' "$id"
    return 0
)

# --- Refactor 1-2: lock 取得 (MED-002) ---
# atomic-mkdir lock 100×50ms timeout (5 秒)
# 取得成功: exit 0、timeout: exit 2
_new_task_acquire_lock() (
    set -uo pipefail
    local lockdir="$1"
    local tries=0
    local max_tries=100  # 100 retries × 50ms = 5 秒 timeout
    while ! mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries+1))
        if [ "$tries" -gt "$max_tries" ]; then
            echo "ERROR: lock timeout (${lockdir}、${max_tries} retries × 50ms = 5 秒)" >&2
            return 2
        fi
        sleep 0.05
    done
    return 0
)

# --- Refactor 1-3: 同 ID 行を status と slug で 4 分類 (MED-002) ---
# stdout (4 行、TAB 区切り labeled) で分類結果を返す:
#   ID_ROWS=...
#   PENDING_ROWS=...
#   SAME_SLUG_ROWS=...
#   DIFF_SLUG_PENDING_ROWS=...
# 値が複数行を含む場合は NUL (\0) 区切りで埋め込み、caller 側で復元
# 簡素化のため env-passing 方式は不採用、caller が再度 grep する設計
_new_task_classify_rows() (
    set -uo pipefail
    local list_md="$1" esc_id="$2" esc_slug="$3"

    # --- 同 ID 行を全件取得 ---
    local id_rows
    id_rows=$(grep -E "^\| ${esc_id} \|" "$list_md" 2>/dev/null || true)

    # 完全不在 (空) なら呼出側で append 判定
    if [ -z "$id_rows" ]; then
        # 4 行の空 result を返す
        printf '\n\n\n\n'
        return 0
    fi

    # --- status (📝 / 非📝) で分類 ---
    # `grep -v "📝"` で 4-byte 絵文字 character class 問題を回避 (H-02)
    local rows_pending rows_other rows_same_slug rows_diff_slug_pending
    rows_pending=$(printf '%s\n' "$id_rows" | grep -F "📝" || true)
    rows_other=$(printf '%s\n' "$id_rows" | grep -vF "📝" || true)

    # kebab-word boundary 照合 (C-02 substring 誤マッチ防止)
    # slug の前後が `[a-zA-Z0-9-]` 文字でなく (= 行頭/行末/非英数 - 区切り) 完全一致する場合のみ match
    local slug_word_pat="(^|[^a-zA-Z0-9-])${esc_slug}([^a-zA-Z0-9-]|\$)"

    if [ -n "$rows_pending" ]; then
        rows_same_slug=$(printf '%s\n' "$rows_pending" | grep -E "$slug_word_pat" || true)
        rows_diff_slug_pending=$(printf '%s\n' "$rows_pending" | grep -vE "$slug_word_pat" || true)
    else
        rows_same_slug=""
        rows_diff_slug_pending=""
    fi

    # 4 result を NUL 区切りで返す (各 result 内の改行を保持)
    printf '%s\0%s\0%s\0%s\0' \
        "$id_rows" "$rows_pending" "$rows_other" "$rows_diff_slug_pending"

    # 使われない変数 (shellcheck 抑止)
    : "${rows_same_slug:=}"
)

# --- Refactor 1-4: BLOCK 判定 (MED-002) ---
# Arguments:
#   $1 id              — 表示用 (numeric 正規化済)
#   $2 slug            — 表示用
#   $3 id_rows         — 同 ID 全 row
#   $4 rows_pending    — 📝 全 row
#   $5 rows_other      — 📝 以外 全 row
#   $6 rows_same_slug  — 📝 + 同 slug row
#   $7 rows_diff_slug_pending — 📝 + 別 slug row
#   $8 pending_match_count    — 📝 + 同 slug 件数
# return: 0 = pass / 1 = BLOCK (stderr に message)
_new_task_check_blocks() (
    set -uo pipefail
    local id="$1" slug="$2"
    local id_rows="$3"
    local rows_pending="$4"
    local rows_other="$5"
    local rows_same_slug="$6"
    local rows_diff_slug_pending="$7"
    local pending_match_count="$8"

    # (a) 同 ID + 別 slug + 📝 既存 → BLOCK (C-01 / H-08)
    if [ -n "$rows_diff_slug_pending" ]; then
        echo "BLOCK: 同 ID (${id}) で別 slug の 📝 行が既存。誤連番 / slug typo の可能性。" >&2
        echo "  既存 📝 行:" >&2
        printf '%s\n' "$rows_diff_slug_pending" | sed 's/^/    /' >&2
        return 1
    fi

    # (b) 同 ID + 同 slug + status 混在 (📝 + 🔲/🔄/✅) → BLOCK (C-03)
    if [ -n "$rows_other" ] && [ -n "$rows_same_slug" ]; then
        echo "BLOCK: 同 ID (${id}) + 同 slug (${slug}) で status 混在 (📝 と 🔲/🔄/✅)。重複起動 or 完了済 task の上書き可能性。" >&2
        echo "  既存行:" >&2
        printf '%s\n' "$id_rows" | sed 's/^/    /' >&2
        return 1
    fi

    # (c) 同 ID + 別 status (🔲/🔄/✅) のみ既存 → BLOCK (重複起動防止)
    if [ -n "$rows_other" ] && [ -z "$rows_same_slug" ] && [ -z "$rows_diff_slug_pending" ]; then
        echo "BLOCK: 同 ID (${id}) で 📝 以外 status 既存 (重複 ID 修正必要)。" >&2
        echo "  既存行:" >&2
        printf '%s\n' "$rows_other" | sed 's/^/    /' >&2
        return 1
    fi

    # (d) 同 ID + 同 slug + 📝 複数件 → BLOCK
    if [ "$pending_match_count" -ge 2 ]; then
        echo "BLOCK: 同 ID + 同 slug の 📝 行が複数件 (${pending_match_count} 件)、list.md 手動修正必要。" >&2
        return 1
    fi

    # 使われない変数 (shellcheck 抑止)
    : "${rows_pending:=}"
    return 0
)

# --- Refactor 1-5: UPDATE 実行 (MED-002) ---
# 同 ID + 同 slug + 📝 1 件にマッチする行のみ row_content に置換 (awk ENVIRON 経由)
# Arguments:
#   $1 list_md
#   $2 esc_id
#   $3 esc_slug
#   $4 row_content
# return: 0 = update 成功 / 2 = awk 失敗
_new_task_perform_update() (
    set -uo pipefail
    local list_md="$1" esc_id="$2" esc_slug="$3" row_content="$4"

    # M-MV-01: tmp を target_dir に配置 (cross-filesystem 非 atomic 回避)
    local target_dir tmp
    target_dir=$(dirname "$list_md")
    tmp=$(mktemp "${target_dir}/.list.md.XXXXXX") || {
        echo "ERROR: mktemp failed in $target_dir" >&2
        return 2
    }

    # cleanup trap: subshell exit 時に tmp 残存なら削除
    # shellcheck disable=SC2064
    trap "[ -f '$tmp' ] && rm -f '$tmp'" EXIT INT TERM HUP

    # awk ENVIRON 経由で値受渡 (H-03 解消、backslash interpretation 回避)
    ID_ESC="$esc_id" SLUG_ESC="$esc_slug" NEW_ROW="$row_content" awk '
        BEGIN {
            id_esc = ENVIRON["ID_ESC"]
            slug_esc = ENVIRON["SLUG_ESC"]
            new_row = ENVIRON["NEW_ROW"]
            replaced = 0
            slug_pat = "(^|[^a-zA-Z0-9-])" slug_esc "([^a-zA-Z0-9-]|$)"
            id_pat = "^\\| " id_esc " \\|"
        }
        {
            if (!replaced) {
                if ($0 ~ id_pat && index($0, "📝") > 0 && $0 ~ slug_pat) {
                    print new_row
                    replaced = 1
                    next
                }
            }
            print $0
        }
    ' "$list_md" > "$tmp"

    # awk が空 output を出した場合の guard
    if [ ! -s "$tmp" ]; then
        echo "ERROR: awk rewrite produced empty output, aborting" >&2
        return 2
    fi

    # atomic install (target_dir 配置で必ず同一 filesystem)
    mv "$tmp" "$list_md"
    return 0
)

# --- Refactor 1-6: APPEND 実行 (MED-002) ---
_new_task_perform_append() (
    set -uo pipefail
    local list_md="$1" row_content="$2"
    _new_task_ensure_eol "$list_md"
    printf '%s\n' "$row_content" >> "$list_md"
    return 0
)

# --- メイン関数: update or append (採用 6 条 Step 5 refactor 後) ---
# Arguments:
#   $1 id           — task id (numeric, leading zero 許容、内部で 10#$ 正規化、最大 18 桁)
#   $2 slug         — kebab-case slug
#   $3 row_content  — 完全な list.md row (`| id | 🔲 | ... |`)、改行 (LF/CR) 不可
#   $4 list_md      — list.md path (省略時 ${HC_TASK_DIR:-docs/tasks}/list.md)
#
# Return codes:
#   0 = update or append 成功
#   1 = BLOCK (誤連番 / 重複起動 / status 混在 / 複数マッチ)
#   2 = usage error / file not found / lock timeout / invalid input (overflow / CR 含む)
update_or_append_task_row() (
    set -uo pipefail

    local raw_id="${1:-}"
    local slug="${2:-}"
    local row_content="${3:-}"
    local list_md="${4:-${HC_TASK_DIR:-docs/tasks}/list.md}"

    # --- Step 1: 入力検証 + id 正規化 ---
    local id
    id=$(_new_task_validate_input "$raw_id" "$slug" "$row_content") || return $?

    if [ ! -f "$list_md" ]; then
        echo "ERROR: list.md not found: $list_md" >&2
        return 2
    fi

    # --- Step 2: lock 取得 (parallel race 防止) ---
    local lockdir="${list_md}.lock.d"
    _new_task_acquire_lock "$lockdir" || return $?
    # shellcheck disable=SC2064
    trap "rmdir '$lockdir' 2>/dev/null" EXIT INT TERM HUP

    # --- Step 3: regex escape (H-01) ---
    local esc_id esc_slug
    esc_id=$(_new_task_escape_regex "$id")
    esc_slug=$(_new_task_escape_regex "$slug")

    # --- Step 4: 同 ID 行を取得 ---
    local id_rows
    id_rows=$(grep -E "^\| ${esc_id} \|" "$list_md" 2>/dev/null || true)

    # 完全不在 → append (既存動作)
    if [ -z "$id_rows" ]; then
        _new_task_perform_append "$list_md" "$row_content"
        echo "APPEND: 末尾追加"
        return 0
    fi

    # --- Step 5: 同 ID 行を 4 分類 ---
    local rows_pending rows_other rows_same_slug rows_diff_slug_pending
    rows_pending=$(printf '%s\n' "$id_rows" | grep -F "📝" || true)
    rows_other=$(printf '%s\n' "$id_rows" | grep -vF "📝" || true)

    local slug_word_pat="(^|[^a-zA-Z0-9-])${esc_slug}([^a-zA-Z0-9-]|\$)"
    if [ -n "$rows_pending" ]; then
        rows_same_slug=$(printf '%s\n' "$rows_pending" | grep -E "$slug_word_pat" || true)
        rows_diff_slug_pending=$(printf '%s\n' "$rows_pending" | grep -vE "$slug_word_pat" || true)
    else
        rows_same_slug=""
        rows_diff_slug_pending=""
    fi

    # 同 slug + 📝 件数
    local pending_match_count
    pending_match_count=$(printf '%s\n' "$rows_same_slug" | grep -c . || true)
    pending_match_count="${pending_match_count:-0}"

    # --- Step 6: BLOCK 判定 ---
    _new_task_check_blocks \
        "$id" "$slug" \
        "$id_rows" "$rows_pending" "$rows_other" \
        "$rows_same_slug" "$rows_diff_slug_pending" \
        "$pending_match_count" || return $?

    # --- Step 7: UPDATE mode (同 ID + 同 slug + 📝 1 件) ---
    if [ "$pending_match_count" -eq 1 ]; then
        _new_task_perform_update "$list_md" "$esc_id" "$esc_slug" "$row_content" || return $?
        echo "UPDATE: 📝 → 🔲 (id=${id}, slug=${slug})"
        return 0
    fi

    # --- Step 8: APPEND mode (safety net、通常 Step 4 で return 済) ---
    _new_task_perform_append "$list_md" "$row_content"
    echo "APPEND: 末尾追加"
    return 0
)

# --- CLI dispatcher (直接実行 or source 両対応) ---
# 旧 API 互換: 引数 3-4 件で関数名指定なしの場合 update_or_append_task_row を call
# 新 API:      第 1 引数が関数名 (例: update_or_append_task_row) なら subcommand 形式
_new_task_main() (
    set -uo pipefail

    if [ "$#" -lt 1 ]; then
        cat <<'EOF' >&2
Usage:
  bash new-task-helper.sh update_or_append_task_row <id> <slug> <row_content> [list_md]
  bash new-task-helper.sh <id> <slug> <row_content> [list_md]  (旧 API 互換)

Examples:
  bash new-task-helper.sh update_or_append_task_row 33 list-md-plan-first '| 33 | 🔲 | ... |'
  bash new-task-helper.sh 33 list-md-plan-first '| 33 | 🔲 | ... |' docs/tasks/list.md
EOF
        return 2
    fi

    case "$1" in
        update_or_append_task_row)
            shift
            update_or_append_task_row "$@"
            ;;
        *)
            # 旧 API 互換: 第 1 引数が id (関数名でない) なら旧 API 経路
            update_or_append_task_row "$@"
            ;;
    esac
)

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    _new_task_main "$@"
    exit $?
fi
