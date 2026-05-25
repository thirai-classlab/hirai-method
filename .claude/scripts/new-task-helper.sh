#!/usr/bin/env bash
# .claude/scripts/new-task-helper.sh
# task-33 Phase 2 Step 2.2: /new-task の 📝 → 🔲 update or append helper
#
# 役割:
#   list.md に対し、同 ID + slug の AND 一致 grep で既存 📝 行を検出し:
#     - 既存 1 件 → 📝 → 🔲 update (awk in-place rewrite)
#     - 不在      → 末尾 append
#     - 複数マッチ → BLOCK (return 1)
#     - 同 ID + 別 status (📝 以外) 既存 → BLOCK (return 1)
#
# 規範:
#   .claude/rules/task-management.md §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」
#
# 設計:
#   - set -uo pipefail (set -e なし、caller leak 防止、fail-open)
#   - awk in-place rewrite は tmp file 経由 atomic (BSD/GNU 互換)
#   - CLI entry point + source 両対応

set -uo pipefail

update_or_append_task_row() {
    local id="$1"
    local slug="$2"
    local row_content="$3"
    local list_md="${4:-docs/tasks/list.md}"

    # input validation
    if [ ! -f "$list_md" ]; then
        echo "ERROR: list.md not found: $list_md" >&2
        return 2
    fi

    # AND 一致 grep (📝 + ID + slug 全て一致)
    # grep -c は 0 件 match で exit 1 + stdout "0" を返すため、|| true で exit を吸収し stdout の "0" を採用
    local match_count
    match_count=$(grep -cE "^\| ${id} \| 📝 .*${slug}" "$list_md" 2>/dev/null || true)
    match_count="${match_count:-0}"

    # 複数マッチ check
    if [ "$match_count" -ge 2 ]; then
        echo "BLOCK: 同 ID + slug で複数マッチ (${match_count} 行)、list.md 修正必要" >&2
        return 1
    fi

    # update mode (既存 1 件)
    if [ "$match_count" -eq 1 ]; then
        local line_num
        line_num=$(grep -nE "^\| ${id} \| 📝 .*${slug}" "$list_md" | head -1 | cut -d: -f1)
        # awk で line_num を row_content に書き換え (BSD/GNU 互換、tmp file 経由 atomic)
        local tmp_file="${list_md}.tmp.$$"
        awk -v n="$line_num" -v new="$row_content" 'NR==n{print new; next}{print}' "$list_md" > "$tmp_file" \
            && mv "$tmp_file" "$list_md"
        echo "UPDATE: 📝 → 🔲 (line ${line_num})"
        return 0
    fi

    # 同 ID + 別 status conflict check (📝 以外 既存)
    local conflict_count
    conflict_count=$(grep -cE "^\| ${id} \| [^📝]" "$list_md" 2>/dev/null || true)
    conflict_count="${conflict_count:-0}"
    if [ "$conflict_count" -ge 1 ]; then
        echo "BLOCK: 同 ID (${id}) で 📝 以外 status 既存 (${conflict_count} 行)、重複 ID 修正必要" >&2
        return 1
    fi

    # append mode (完全不在)
    echo "$row_content" >> "$list_md"
    echo "APPEND: 末尾追加"
    return 0
}

# CLI entry (直接実行 or source 両対応)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ "$#" -lt 3 ]; then
        echo "Usage: $0 <id> <slug> <row_content> [list_md]" >&2
        echo "" >&2
        echo "Examples:" >&2
        echo "  $0 33 list-md-plan-first '| 33 | 🔲 | Phase 1 | 概要 | — | [link](task-33.md) |'" >&2
        echo "  $0 33 list-md-plan-first '<row>' docs/tasks/list.md" >&2
        exit 2
    fi
    update_or_append_task_row "$@"
fi
