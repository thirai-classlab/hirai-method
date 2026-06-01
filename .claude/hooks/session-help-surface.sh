#!/usr/bin/env bash
# session-help-surface.sh — SessionStart hook
#
# 役割:
#   HIRAI ハーネスの主要 slash command 一覧 + onboarding hint を SessionStart で表示する。
#
#   task-68 §3.2 (opt-in 化, 2026-06-01):
#     既定 (default) は **1 行 pointer** のみ注入 (attention dilution / context 消費削減)。
#     詳細な help 全文 (command 一覧 table + onboarding) は **opt-in** —
#     `HC_SESSION_HELP_FORCE=true` の時のみ表示する。
#     `HC_SESSION_HELP_VERBOSE=true` は FORCE 時の追加詳細版として従来通り機能。
#
#   Wave 1.6 (2026-05-23): 初回 session のみ表示の marker 抑止は維持。
#   起源: docs/draft/system-reminder-attention-fix.md W1.6
#         docs/draft/harness-design-fundamental-review.md §3.2 (task-68)
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 環境変数:
#   HC_SESSION_HELP_ENABLED=false    ... 全体無効化 (1 行 pointer も含め silent)
#   HC_SESSION_HELP_FORCE=1|true     ... 詳細 help 全文を opt-in 表示 (marker も無視)
#   HC_SESSION_HELP_VERBOSE=true     ... FORCE 時に更に詳細版 (全 command + workflow) を追加
#   HC_SESSION_HELP_FIRST_ONLY=false ... 旧挙動 (毎回表示) に戻す
#   HC_SESSION_HELP_MARKER_PATH=...  ... marker file path 上書き
#
# Stdin:  SessionStart hook JSON (読み捨て)
# Stdout: default=1 行 pointer / FORCE=詳細 help の <system-reminder>
# Stderr: FORCE 時のみ terminal banner
# Exit:   常に 0
#
# 制約:
#   file-top に `set -euo pipefail` を書かない (feedback_set_e_in_sourced_libs 規範)。
#   `set -u` のみ採用 (caller shell flags への leak を防ぐ)。

set -u

# config 読み込み (HC_* 変数 + is_feature_enabled 関数 export、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled session_help_surface; then
  exit 0   # feature OFF で no-op
fi

# stdin 消費 (SessionStart JSON は使わない)
cat >/dev/null 2>&1 || true

# 無効化チェック
if [ "${HC_SESSION_HELP_ENABLED:-true}" = "false" ]; then
  exit 0
fi

VERBOSE="${HC_SESSION_HELP_VERBOSE:-false}"

# FORCE 判定 (task-68 §3.2: 詳細 help の opt-in gate を兼ねる)
FORCE=0
if [ "${HC_SESSION_HELP_FORCE:-0}" = "1" ] || [ "${HC_SESSION_HELP_FORCE:-}" = "true" ]; then
  FORCE=1
fi

# === Wave 1.6: 初回 session のみ表示 (marker check) ===
_project_root="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MARKER_PATH="${HC_SESSION_HELP_MARKER_PATH:-${_project_root}/.claude/.session-help-shown}"
FIRST_ONLY="${HC_SESSION_HELP_FIRST_ONLY:-true}"

if [ "$FORCE" = "1" ]; then
  : # marker check skip (force 表示)
elif [ "$FIRST_ONLY" != "false" ]; then
  # first-only モード: marker 存在なら silent skip
  if [ -f "$MARKER_PATH" ]; then
    exit 0
  fi
fi

# === marker 書込ヘルパー (DRY: pointer 経路 / FORCE 経路で共通使用) ===
# FORCE モード or 旧挙動 (FIRST_ONLY=false) では marker 不要
_write_marker() {
  if [ "$FORCE" != "1" ] && [ "$FIRST_ONLY" != "false" ]; then
    mkdir -p "$(dirname "$MARKER_PATH")" 2>/dev/null || true
    : > "$MARKER_PATH" 2>/dev/null || true
  fi
}

# === task-68 §3.2: default は 1 行 pointer のみ ===
# 詳細 help 全文は FORCE=true の時だけ opt-in 表示。
if [ "$FORCE" != "1" ]; then
  cat <<'EOF'
<system-reminder>
HIRAI メソッド: slash command 一覧は `export HC_SESSION_HELP_FORCE=true` で表示できます。詳細は `README.md` Commands table / `docs/INVENTORY.md` 参照。
</system-reminder>
EOF
  # marker 作成 (1 行 pointer も初回のみ — first-only モード)
  _write_marker
  exit 0
fi

# === 以下 FORCE=true の opt-in 詳細 help ===

# === stderr: terminal 直接表示 banner ===
cat >&2 <<'EOF'

═══════════════════════════════════════════════════════════════════
  HIRAI メソッド — 主要 slash commands
═══════════════════════════════════════════════════════════════════
  Session 永続化 : /save-state  /resume-state  /pm-start  (Serena MCP 必須)
  タスク管理    : /init-tasks  /new-draft <slug>  /new-task <id> <slug>
                  /start-task <id>  /finish-task <id>
  Workflow 強制  : /test-design  /design-review  /module-review
                  /system-review  /new-feature  /modify-feature
  副産物         : /discharge-byproduct <entry>
  Mode           : /mode <normal|loop>
  Git / レビュー : /commit  /reviewpr  /verify
  監査           : /harness-audit
  自己改善       : /eval  /gan-design  /gan-build  /instinct-status
                  /learn  /promote  /agent-introspect
  GateGuard      : /gate-status  /gate-clear  /gate-bypass

  Onboarding     : CLAUDE.md  +  docs/INVENTORY.md  +  .claude/rules/development-process.md
  詳細版         : export HC_SESSION_HELP_VERBOSE=true
  抑制           : export HC_SESSION_HELP_ENABLED=false
  再表示         : export HC_SESSION_HELP_FORCE=true
═══════════════════════════════════════════════════════════════════

EOF

# === stdout: agent への context (MANDATORY embed directive 付き) ===
cat <<'EOF'
<system-reminder>
**HIRAI メソッド: 主要 slash commands + onboarding hint (採用者 UX)**

このセッションの **最初の応答で必ず以下の help 一覧を 1 度だけ user に embed (逐語表示) してください**。
embed なしの informational 扱いは禁止。再表示は不要。

> ---
> **HIRAI メソッド 主要 slash commands**
>
> | カテゴリ | command |
> |---|---|
> | Session 永続化 | `/save-state` `/resume-state` `/pm-start` (Serena MCP 必須) |
> | タスク管理 | `/init-tasks` `/new-draft <slug>` `/new-task <id> <slug>` `/start-task <id>` `/finish-task <id>` |
> | Workflow 強制 | `/test-design` `/design-review` `/module-review` `/system-review` `/new-feature` `/modify-feature` |
> | 副産物 discharge | `/discharge-byproduct <entry>` |
> | Mode | `/mode <normal\|loop>` |
> | Git / レビュー | `/commit` `/reviewpr` `/verify` |
> | 監査 | `/harness-audit` |
> | 自己改善 | `/eval` `/gan-design` `/gan-build` `/instinct-status` `/learn` `/promote` `/agent-introspect` |
> | GateGuard 制御 | `/gate-status` `/gate-clear` `/gate-bypass` |
>
> **Onboarding hint**:
> - 初回利用は `CLAUDE.md` + `docs/INVENTORY.md` + `.claude/rules/development-process.md` を読む
> - 詳細は `README.md` Commands table 参照
> - 詳細版表示: `export HC_SESSION_HELP_VERBOSE=true`
> - 警告抑制: `export HC_SESSION_HELP_ENABLED=false`
> ---

embed 完了後、user の prompt に通常応答してください。
</system-reminder>
EOF

# === 詳細版 (HC_SESSION_HELP_VERBOSE=true) ===
if [ "$VERBOSE" = "true" ]; then
  cat <<'EOF'
<system-reminder>
**詳細 commands (verbose)**

詳細・全件は `.claude/commands/*.md` 参照、または `README.md` Commands table 確認。

**典型 workflow**:
1. `/new-draft <slug>` → 設計 draft 起こし
2. user レビュー + 承認
3. `/new-task <id> <slug>` → タスク化 + list.md row 追加
4. `/start-task <id>` → branch 切替 + status in_progress
5. Agent tool で subagent 起動 (background + TaskCreate 必須)
6. `/finish-task <id>` → 完了検証 + done 化 + commit 提案

**Loop モード自律実行 + 安全網**:
- `/mode loop` で停止指示まで AI 推奨方法を即採用
- 自律実行禁止リスト (modes.md 遵守事項 8): `git push` / `gh pr create` / `vercel --prod` 等
- bypass path: mode 一時切替 (`.claude/mode.yml` を normal → 操作 → loop 復帰)

**Serena MCP 必須化**: `/save-state` `/resume-state` `/pm-start` は Serena 必須、
`.mcp.json` に serena entry 不在時は `check-serena-mcp.sh` が SessionStart で警告。
</system-reminder>
EOF
fi

# === Wave 1.6: marker 作成 (silent 失敗で fail-open) ===
_write_marker

exit 0
