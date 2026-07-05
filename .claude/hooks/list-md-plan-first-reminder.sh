#!/usr/bin/env bash
# list-md-plan-first-reminder.sh — SessionStart hook (task #35、task #91 Step 2 で 2-tier 化)
#
# 役割:
#   `docs/tasks/list.md` の task エントリ行 == 0 (台帳が空) を検出した時、
#   `<system-reminder>` で「list.md plan-first」keyword を含む warning を stderr に出力する。
#
# 2-tier 構成 (task #91 / docs/draft/list-md-actionable-header.md §3 Step 2):
#   tier A (現行維持): task_count == 0 ∧ draft_count >= 3
#     - batch planning 経路 B 不在 (task #35 起源) の full message を注入 (文面は 1 文字も変更しない)。
#     - source gating なし (全 source で発火、現行互換 — 経路 B 違反は resume 後も再注入に値する)。
#   tier B (新設):     task_count == 0 ∧ draft_count < 3
#     - bootstrap 期 (install 直後の空台帳、roadmap §4.8「reminder 不発」) 向けの短文注入。
#     - source gating: SessionStart stdin JSON の `source` field が startup / clear の
#       ときのみ発火、resume / compact は skip (Loop 長時間 session の騒がしさ抑制)。
#     - 抽出失敗 (stdin 空 / 非 JSON / field 不在) は startup 扱いで発火
#       (fail 方向 = reminder 機能維持)。
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 検出ロジック:
#   - task エントリ行: `grep -cE '^\| [0-9]' <list.md>`
#   - draft 件数:      `find <draft_dir> -maxdepth 1 -name "*.md" -not -name "_*" | wc -l`
#   - tier A 条件:     task_count == 0 && draft_count >= 3
#   - tier B 条件:     task_count == 0 && draft_count < 3 && source ∈ {startup, clear, 抽出失敗}
#
# fail-open guard:
#   - `docs/tasks/list.md` 不在環境 (新規採用 project / /init-tasks 未実行) → 何もせず exit 0
#   - `docs/draft/` 不在 → 同上
#
# 環境変数 (env override > YAML > defaults):
#   HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false  ... reminder 全停止 (bypass、tier A/B 共通)
#   HC_TASK_DIR                                  ... default docs/tasks
#   HC_DRAFT_DIR                                 ... default docs/draft
#   CLAUDE_PROJECT_DIR                           ... Claude Code 注入の project root
#   (task #91: 新 env / 新 yml key は追加しない — tier B 個別 OFF は YAGNI、
#    全体 toggle HC_LIST_PLAN_FIRST_REMINDER_ENABLED / list_plan_first_reminder_enabled で足りる)
#
# YAML 設定 (harness-config.yml):
#   list_plan_first_reminder_enabled: false      ... reminder 全停止 (env と同等動作)
#   config-loader.sh 経由で env として export される。
#   env override が優先 (env > YAML > defaults)。
#
# Stdin:  SessionStart hook JSON (tier B source gating 用に `source` field を jq 非依存で抽出。
#         dispatcher-core.sh の stdin replay により payload 全文が届く)
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
#   - 2-tier 化: docs/draft/list-md-actionable-header.md §3 Step 2 (task #91、roadmap P1-7 対策 C)
#   - 規範:     .claude/rules/task-management.md §plan-first 経路 B / §設計→承認→タスク追加フロー
#
# 共有 feature toggle group:
#   - グループ制御 toggle: `feature_task_rule_guard_enabled` (default: true)
#   - OFF にすると本 hook を含む同 group の全 hook が no-op
#   - 編集: `bash .claude/scripts/hc-config.sh --feature task_rule_guard=false`
#   - 同 group の他 hook: task-rule-guard.sh
#   - Step 5 refactor: harness-optimizer M-1 finding (YAML→hook 受渡し欠如) を解消
#     context-budget.sh L59-62 パターンを踏襲し、config-loader.sh source で
#     harness-config.yml の list_plan_first_reminder_enabled: false が hook に届くようにする。

set -u

# stdin 捕捉 (SessionStart hook JSON — tier B source gating 用に保持。
# task #91 Step 2 で旧「cat >/dev/null 破棄」から変更。read 失敗は空文字 = 抽出失敗 fallback)
_lpfr_stdin="$(cat 2>/dev/null || true)"

# session source 抽出 (jq 非依存、既存 hook 群の no-jq 方針踏襲)。
# 抽出失敗 (stdin 空 / 非 JSON / field 不在) → 空文字 → tier B では startup 扱いで発火。
_lpfr_session_source="$(printf '%s' "$_lpfr_stdin" \
    | grep -o '"source"[[:space:]]*:[[:space:]]*"[a-z]*"' 2>/dev/null \
    | head -n 1 \
    | sed 's/.*"\([a-z]*\)"$/\1/' 2>/dev/null || true)"

# --- config 読み込み ---
# harness-config.yml の list_plan_first_reminder_enabled を HC_LIST_PLAN_FIRST_REMINDER_ENABLED
# として export する。env override が優先される (config-loader.sh 仕様)。
# source 失敗時は || true で fail-open (caller への set flags leak を防止)。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled task_rule_guard; then
    exit 0
fi

_lpfr_main() (
    set -uo pipefail

    # bypass check (env override 経由 or YAML 経由、config-loader.sh で統一済)
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

    # 0 件以外なら何もしない (tier A/B 共通ゲート)
    [ "$task_count" -eq 0 ] || exit 0

    # draft 件数 (`_*` template 除外、深さ 1 のみ)
    local draft_count
    draft_count=$(find "$draft_dir" -maxdepth 1 -type f -name "*.md" -not -name "_*" 2>/dev/null | wc -l | tr -d ' ')
    draft_count="${draft_count:-0}"
    case "$draft_count" in
      ''|*[!0-9]*) draft_count=0 ;;
    esac

    if [ "$draft_count" -ge 3 ]; then
        # tier A (現行互換): batch planning 経路 B 不在 → full message、source gating なし
        cat >&2 <<EOF

<system-reminder>
[list.md plan-first] batch planning 経路 B 不在を検出しました:
- \`${draft_dir_rel}/*.md\` が ${draft_count} 件存在し、かつ \`${task_dir}/list.md\` に task エントリ行 (📝/🔲/🔄/✅) が 0 件です。
- master roadmap で N ≥ 3 task を一括計画する場合、\`.claude/rules/task-management.md\` §plan-first 経路 B に従い list.md に N 行 **📝 設計（未承認）** で先置きしてください (main 直接 Edit、task-rule-guard.sh 既存 exempt 通過)。
- 規範: \`.claude/rules/task-management.md\` §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」
- bypass: \`HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false\` または harness-config.yml \`list_plan_first_reminder_enabled: false\`
</system-reminder>
EOF
    else
        # tier B (task #91 新設): bootstrap 期 (draft < 3) → 短文注入。
        # source gating: startup / clear のみ発火 ("" = 抽出失敗 fallback は startup 扱い)、
        # resume / compact は skip。
        case "${_lpfr_session_source:-}" in
          startup|clear|"") : ;;
          *) exit 0 ;;
        esac
        cat >&2 <<'EOF'

<system-reminder>
[list.md plan-first] docs/tasks/list.md に task エントリ行が 0 件です (台帳が空)。
最初の作業を決めたら /new-draft <slug> で設計 draft を起案し、user 承認後に /new-task <id> <slug> で行を追加してください。
規範: .claude/rules/task-management.md §設計→承認→タスク追加フロー / bypass: HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false
</system-reminder>
EOF
    fi
    exit 0
)

_lpfr_main "$@"
exit 0
