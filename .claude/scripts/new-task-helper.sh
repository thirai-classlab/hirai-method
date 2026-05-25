#!/usr/bin/env bash
# .claude/scripts/new-task-helper.sh
# task-33 Phase 2 Step 2.2: /new-task の 📝 → 🔲 update or append helper
# task-34 Step 4 iter2 fix: CRIT 3 + HIGH 8 件解消版
# task-34 Step 4 iter3 fix: MUST FIX 7 + SHOULD FIX 3 件解消版
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
# 設計原則 (iter2 + iter3 で追加):
#   - file-top に set -uo pipefail を書かない (CLAUDE.md Critical Lessons HIGH 遵守、H-06)
#   - 各関数で subshell 関数 `func() ( ... )` 化で局所化
#   - HC_TASK_DIR を config-loader 経由で参照 (Design Constraints 遵守、H-07)
#   - regex injection 防止: id / slug を escape (H-01)
#   - awk ENVIRON 経由で値受渡 (H-03 解消、backslash interpretation 回避)
#   - mktemp + trap cleanup (H-05 解消、tmp file race + leak 防止)
#   - printf '\n' EOL guard (H-04 解消、末尾改行欠落時の前行結合防止)
#   - UTF-8 multi-byte 回避: `grep -v "📝"` で 4-byte 絵文字 character class 問題 (H-02 解消)
#   - status 混在 conflict check (C-03 解消)
#   - slug 完全一致: `| <slug> |` の前後区切り照合 (C-02 substring 誤マッチ防止)
#
# iter3 追加 fix:
#   - QA-C01/H-RC-01: atomic-mkdir lock で parallel race condition 解消
#   - QA-C02: leading zero id 数値正規化 (10#$id で 8 進解釈防止)
#   - QA-H01: row_content 改行 input validation
#   - M-MV-01: tmp file を target_dir に配置 (cross-filesystem 非 atomic 回避)
#   - L-SC-01: shellcheck SC2016 disable comment
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
# file 末尾が改行で終わっていない場合、append 前に '\n' を挿入する。
# `od -An -c -N1 | tr -d ' \n'` で末尾 1 byte を取り、'\n' でなければ append.
_new_task_ensure_eol() (
    set -uo pipefail
    local file="$1"
    [ -s "$file" ] || return 0
    local last_byte
    last_byte=$(tail -c 1 "$file" | od -An -c -N1 2>/dev/null | tr -d ' ')
    if [ "$last_byte" != "\\n" ]; then
        printf '\n' >> "$file"
    fi
)

# --- メイン関数: update or append ---
# Arguments:
#   $1 id           — task id (numeric, leading zero 許容、内部で 10#$ 正規化)
#   $2 slug         — kebab-case slug
#   $3 row_content  — 完全な list.md row (`| id | 🔲 | ... |`)、改行不可
#   $4 list_md      — list.md path (省略時 ${HC_TASK_DIR:-docs/tasks}/list.md)
#
# Return codes:
#   0 = update or append 成功
#   1 = BLOCK (誤連番 / 重複起動 / status 混在 / 複数マッチ)
#   2 = usage error / file not found / lock timeout / invalid input
update_or_append_task_row() (
    set -uo pipefail

    local raw_id="${1:-}"
    local slug="${2:-}"
    local row_content="${3:-}"
    # config-loader が export 済なら HC_TASK_DIR を使う (H-07)。
    # 未 source の場合は default "docs/tasks"。
    local list_md="${4:-${HC_TASK_DIR:-docs/tasks}/list.md}"

    # input validation
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
    # 10 進数強制 (bash 構文、"08" を 8 進と解釈させない)。zero stripping して string 化
    local id
    id=$((10#$raw_id))

    # iter3 QA-H01: row_content 改行 input validation
    case "$row_content" in
        *$'\n'*)
            echo "ERROR: row_content に改行不可 (list.md 行数破壊防止)" >&2
            return 2
            ;;
    esac

    if [ ! -f "$list_md" ]; then
        echo "ERROR: list.md not found: $list_md" >&2
        return 2
    fi

    # iter3 QA-C01/H-RC-01: atomic-mkdir lock acquire (parallel race condition 解消)
    # lockdir は list.md と同じ dir に配置。flock 不使用 (macOS portable)
    local lockdir="${list_md}.lock.d"
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

    # tmp file 用変数 (trap 内で参照、初期化必須)
    local tmp=""
    # cleanup: lockdir 削除 + tmp 削除を EXIT で保証
    # shellcheck disable=SC2064 # 即時展開 (subshell exit 時の状態で実行)
    trap "rmdir '$lockdir' 2>/dev/null; [ -n \"\$tmp\" ] && rm -f \"\$tmp\"" EXIT INT TERM HUP

    # regex escape (H-01)
    local esc_id esc_slug
    esc_id=$(_new_task_escape_regex "$id")
    esc_slug=$(_new_task_escape_regex "$slug")

    # --- Step 1: 同 ID 行を全件取得 ---
    # grep -E は exit 1 を 0 件 match で返すので `|| true` で吸収
    local id_rows
    id_rows=$(grep -E "^\| ${esc_id} \|" "$list_md" 2>/dev/null || true)

    if [ -z "$id_rows" ]; then
        # 完全不在 → append (既存動作)
        _new_task_ensure_eol "$list_md"
        printf '%s\n' "$row_content" >> "$list_md"
        echo "APPEND: 末尾追加"
        return 0
    fi

    # --- Step 2: 同 ID 行を status (📝 / 非📝) と slug 一致で分類 ---
    # `grep -v "📝"` で 4-byte 絵文字 character class 問題を回避 (H-02)
    #
    # slug 一致照合 (C-02 substring 誤マッチ防止):
    #   list.md 行に slug が単独列として現れる保証はない。実態は:
    #     - link path 内: `[task-<id>-<slug>.md]` / `[<slug>.md]` 等
    #     - Task 名内: `**Task: <slug>**`
    #   よって kebab-word boundary 照合を採用: slug の前後が
    #   `[a-zA-Z0-9-]` 文字でなく (= 行頭/行末/非英数 - 区切り) 完全一致する場合のみ match。
    #   これにより slug=`foo` が `foo-bar` 行に誤マッチせず、`foo.md` `foo |` `foo$` 等には match。
    local rows_pending rows_other rows_same_slug rows_diff_slug_pending
    rows_pending=$(printf '%s\n' "$id_rows" | grep -F "📝" || true)
    rows_other=$(printf '%s\n' "$id_rows" | grep -vF "📝" || true)

    # kebab-word boundary 正規表現
    # 前後を否定 character class `[^a-zA-Z0-9-]` で囲み、行頭/行末も許容
    local slug_word_pat="(^|[^a-zA-Z0-9-])${esc_slug}([^a-zA-Z0-9-]|\$)"

    if [ -n "$rows_pending" ]; then
        rows_same_slug=$(printf '%s\n' "$rows_pending" | grep -E "$slug_word_pat" || true)
        rows_diff_slug_pending=$(printf '%s\n' "$rows_pending" | grep -vE "$slug_word_pat" || true)
    else
        rows_same_slug=""
        rows_diff_slug_pending=""
    fi

    # --- Step 3: BLOCK 判定 ---

    # (a) 同 ID + 別 slug + 📝 既存 → BLOCK (C-01 / H-08)
    # 規範 §3「ID + slug AND 一致必須」、誤連番 / slug typo の可能性
    if [ -n "$rows_diff_slug_pending" ]; then
        echo "BLOCK: 同 ID (${id}) で別 slug の 📝 行が既存。誤連番 / slug typo の可能性。" >&2
        echo "  既存 📝 行:" >&2
        printf '%s\n' "$rows_diff_slug_pending" | sed 's/^/    /' >&2
        return 1
    fi

    # (b) 同 ID + 同 slug + status 混在 (📝 + 🔲/🔄/✅) → BLOCK (C-03)
    # rows_other が 1 件以上、かつ rows_same_slug も既存なら混在状態
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
    local pending_match_count
    pending_match_count=$(printf '%s\n' "$rows_same_slug" | grep -c . || true)
    pending_match_count="${pending_match_count:-0}"
    if [ "$pending_match_count" -ge 2 ]; then
        echo "BLOCK: 同 ID + 同 slug の 📝 行が複数件 (${pending_match_count} 件)、list.md 手動修正必要。" >&2
        return 1
    fi

    # --- Step 4: UPDATE mode (同 ID + 同 slug + 📝 1 件) ---
    if [ "$pending_match_count" -eq 1 ]; then
        # iter3 M-MV-01: tmp を target_dir に配置 (cross-filesystem 非 atomic 回避)
        local target_dir
        target_dir=$(dirname "$list_md")
        tmp=$(mktemp "${target_dir}/.list.md.XXXXXX") || {
            echo "ERROR: mktemp failed in $target_dir" >&2
            return 2
        }

        # awk ENVIRON 経由で値受渡 (H-03 解消、backslash interpretation 回避)
        # 同 ID + 同 slug (kebab-word boundary) + 📝 にマッチする 1 行のみ row_content に置換
        # 注: row_content 内に `&` が含まれる場合の sed 干渉を完全回避するため awk を使う
        # ID_ESC / SLUG_ESC は呼出側で escape 済を渡す (regex injection 防止、H-01)
        ID_ESC="$esc_id" SLUG_ESC="$esc_slug" NEW_ROW="$row_content" awk '
            BEGIN {
                id_esc = ENVIRON["ID_ESC"]
                slug_esc = ENVIRON["SLUG_ESC"]
                new_row = ENVIRON["NEW_ROW"]
                replaced = 0
                # kebab-word boundary pattern (slug の前後が非英数 - で挟まれる完全一致)
                slug_pat = "(^|[^a-zA-Z0-9-])" slug_esc "([^a-zA-Z0-9-]|$)"
                # 行頭 `| <id> |` 一致
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

        # awk が空 output (input read 失敗 等) を出した場合の guard
        if [ ! -s "$tmp" ]; then
            echo "ERROR: awk rewrite produced empty output, aborting" >&2
            return 2
        fi

        # atomic install (target_dir 配置で必ず同一 filesystem)
        mv "$tmp" "$list_md"
        tmp=""  # trap での再削除防止
        echo "UPDATE: 📝 → 🔲 (id=${id}, slug=${slug})"
        return 0
    fi

    # --- Step 5: APPEND mode (同 ID 不在、ここには通常来ない、safety net) ---
    _new_task_ensure_eol "$list_md"
    printf '%s\n' "$row_content" >> "$list_md"
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
