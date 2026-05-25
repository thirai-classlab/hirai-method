#!/usr/bin/env bash
# list-md-plan-first-reminder.sh — SessionStart hook (task #35)
#
# 役割:
#   `docs/draft/*.md` ≥ 3 件 ∧ `docs/tasks/list.md` task エントリ行 == 0 を検出した時、
#   `<system-reminder>` で「list.md plan-first」keyword を含む warning を stderr に出力する。
#   batch planning 経路 B (task-management.md §plan-first) 不在事案を AI に強制注意し、
#   AI の判断ミス回避を hook 経由で構造的に補完する。
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 検出ロジック:
#   - task エントリ行: `grep -cE '^\| [0-9]' <list.md>`
#   - draft 件数:      `find <draft_dir> -maxdepth 1 -name "*.md" -not -name "_*" | wc -l`
#   - 条件:            task_count == 0 && draft_count >= 3
#
# fail-open guard:
#   - `docs/tasks/list.md` 不在環境 (新規採用 project / /init-tasks 未実行) → 何もせず exit 0
#   - `docs/draft/` 不在 → 同上
#
# 環境変数:
#   HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false  ... reminder 全停止 (bypass)
#   HC_TASK_DIR                                  ... default docs/tasks
#   HC_DRAFT_DIR                                 ... default docs/draft
#   CLAUDE_PROJECT_DIR                           ... Claude Code 注入の project root
#
# Stdin:  SessionStart hook JSON (使わない、念のため消費)
# Stdout: 未使用
# Stderr: 条件成立時に <system-reminder> ブロックを出力
# Exit:   常に 0 (fail-open)
#
# 制約:
#   file-top に `set -euo pipefail` を書かない (CLAUDE.md Critical Lesson HIGH
#   feedback_set_e_in_sourced_libs 規範遵守)。実装本体は subshell 関数化で局所化する。
#
# 起源:
#   - task #33 (list-md-plan-first-normative) 採用 6 条 supersede による分割で task #35 へ
#   - 設計起源: docs/draft/list-md-plan-first-normative.md §3 P3
#   - 規範:     .claude/rules/task-management.md §plan-first 経路 B

set -u

# stdin 消費 (SessionStart hook JSON は使わない)
cat >/dev/null 2>&1 || true

_lpfr_main() (
    set -uo pipefail

    # bypass check (env override 経由)
    if [ "${HC_LIST_PLAN_FIRST_REMINDER_ENABLED:-true}" = "false" ]; then
        exit 0
    fi

    # project root 解決
    # 優先順: CLAUDE_PROJECT_DIR > git toplevel > pwd
    local repo_root
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
        repo_root="$CLAUDE_PROJECT_DIR"
    elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        :
    else
        repo_root="$(pwd)"
    fi

    local task_dir="${HC_TASK_DIR:-docs/tasks}"
    local draft_dir_rel="${HC_DRAFT_DIR:-docs/draft}"
    local list_md="${repo_root}/${task_dir}/list.md"
    local draft_dir="${repo_root}/${draft_dir_rel}"

    # fail-open guard: 必須 path 不在で誤発火しない
    [ -f "$list_md" ] || exit 0
    [ -d "$draft_dir" ] || exit 0

    # task エントリ行カウント (`^| <number>` パターン)
    local task_count
    task_count=$(grep -cE '^\| [0-9]' "$list_md" 2>/dev/null || true)
    # grep -c 失敗時 (file 空 / 全行非 match) → 空文字 or 0 になる、空時は 0 に正規化
    task_count="${task_count:-0}"
    # 数値以外を弾く (defensive)
    case "$task_count" in
      ''|*[!0-9]*) task_count=0 ;;
    esac

    # 0 件以外なら何もしない
    [ "$task_count" -eq 0 ] || exit 0

    # draft 件数 (`_*` template 除外、深さ 1 のみ)
    local draft_count
    draft_count=$(find "$draft_dir" -maxdepth 1 -type f -name "*.md" -not -name "_*" 2>/dev/null | wc -l | tr -d ' ')
    draft_count="${draft_count:-0}"
    case "$draft_count" in
      ''|*[!0-9]*) draft_count=0 ;;
    esac

    # 3 件未満なら不発火 (N=2 が境界、N=3 から発火)
    [ "$draft_count" -ge 3 ] || exit 0

    # 条件成立 → stderr に <system-reminder> 出力
    cat >&2 <<EOF

<system-reminder>
[list.md plan-first] batch planning 経路 B 不在を検出しました:
- \`${draft_dir_rel}/*.md\` が ${draft_count} 件存在し、かつ \`${task_dir}/list.md\` に task エントリ行 (📝/🔲/🔄/✅) が 0 件です。
- master roadmap で N ≥ 3 task を一括計画する場合、\`.claude/rules/task-management.md\` §plan-first 経路 B に従い list.md に N 行 **📝 設計（未承認）** で先置きしてください (main 直接 Edit、task-rule-guard.sh 既存 exempt 通過)。
- 規範: \`.claude/rules/task-management.md\` §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」
- bypass: \`HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false\`
</system-reminder>
EOF
    exit 0
)

_lpfr_main "$@"
exit 0
