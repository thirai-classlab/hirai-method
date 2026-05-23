#!/usr/bin/env bash
# session-help-surface.sh — SessionStart hook
#
# 役割:
#   HIRAI ハーネスの主要 slash command 一覧 + onboarding hint を
#   SessionStart で簡潔に表示し、採用者の初期 UX を改善する。
#   `Hint や help コマンドについてもセッション開始時に記載してください`
#   (user ask 2026-05-13) を満たす実装。
#
#   Wave 1.6 (2026-05-23): 初回 session のみ表示。`.claude/.session-help-shown`
#   marker で再表示抑止 (attention dilution 削減)。
#   起源: docs/draft/system-reminder-attention-fix.md W1.6
#   env override:
#     HC_SESSION_HELP_FORCE=1            ... marker 無視で強制表示
#     HC_SESSION_HELP_FIRST_ONLY=false   ... 旧挙動 (毎回表示) に戻す
#     HC_SESSION_HELP_MARKER_PATH=<path> ... marker file path 上書き
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 環境変数:
#   HC_SESSION_HELP_ENABLED=false   ... 一時無効化
#   HC_SESSION_HELP_VERBOSE=true    ... 詳細版 (全 command 列挙)、default は要点のみ
#   HC_SESSION_HELP_FORCE=1         ... marker 無視で常時表示 (test / debug 用)
#   HC_SESSION_HELP_FIRST_ONLY=false ... 旧 default (毎回表示) に戻す
#   HC_SESSION_HELP_MARKER_PATH=... ... marker file path 上書き
#
# Stdin:  SessionStart hook JSON (読み捨て)
# Stdout: 主要 commands + hint の <system-reminder> ブロック
# Stderr: 未使用
# Exit:   常に 0
#
# 制約:
#   file-top に `set -euo pipefail` を書かない (feedback_set_e_in_sourced_libs 規範)。
#   `set -u` のみ採用 (caller shell flags への leak を防ぐ)。

set -u

# stdin 消費 (SessionStart JSON は使わない)
cat >/dev/null 2>&1 || true

# 無効化チェック
if [ "${HC_SESSION_HELP_ENABLED:-true}" = "false" ]; then
  exit 0
fi

VERBOSE="${HC_SESSION_HELP_VERBOSE:-false}"

# === Wave 1.6: 初回 session のみ表示 (marker check) ===
# marker file 位置の解決 (env override 可、default は .claude/.session-help-shown)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# project root: CLAUDE_PROJECT_DIR > script の 2 階層上 (.claude/hooks → repo root)
_project_root="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
MARKER_PATH="${HC_SESSION_HELP_MARKER_PATH:-${_project_root}/.claude/.session-help-shown}"

# first-only モード判定 (default true、旧挙動は HC_SESSION_HELP_FIRST_ONLY=false で復元)
FIRST_ONLY="${HC_SESSION_HELP_FIRST_ONLY:-true}"

# HC_SESSION_HELP_FORCE=1 なら marker 無視で強制表示
if [ "${HC_SESSION_HELP_FORCE:-0}" = "1" ] || [ "${HC_SESSION_HELP_FORCE:-}" = "true" ]; then
  : # marker check skip (force 表示)
elif [ "$FIRST_ONLY" != "false" ]; then
  # first-only モード: marker 存在なら silent skip
  if [ -f "$MARKER_PATH" ]; then
    exit 0
  fi
fi

# === stderr: terminal 直接表示 banner (Claude Code が SessionStart stderr を terminal に流す挙動を期待) ===
# stdout だけだと agent の first response 経由でしか visible にならず、
# 「何も入力しないと help が見えない」問題が生じる。stderr 経路で session 起動直後の
# terminal に直接 banner を流すことで、user 入力ゼロでも help が visible になる可能性を確保。
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
  再表示         : export HC_SESSION_HELP_FORCE=1  (or rm .claude/.session-help-shown)
═══════════════════════════════════════════════════════════════════

EOF

# === stdout: agent への context (MANDATORY embed directive 付き) ===
# stderr が claude-code で表示されない環境向けの fallback。
# stderr で表示されている場合でも agent が response 内に embed することで再確認可能。
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
> - 再表示 (Wave 1.6 以降は初回 session のみ表示): `export HC_SESSION_HELP_FORCE=1` または `rm .claude/.session-help-shown`
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
# force モード or 旧挙動 (FIRST_ONLY=false) では marker 不要
if [ "${HC_SESSION_HELP_FORCE:-0}" != "1" ] && [ "${HC_SESSION_HELP_FORCE:-}" != "true" ] && [ "$FIRST_ONLY" != "false" ]; then
  mkdir -p "$(dirname "$MARKER_PATH")" 2>/dev/null || true
  : > "$MARKER_PATH" 2>/dev/null || true
fi

exit 0
