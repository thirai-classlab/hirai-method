#!/usr/bin/env bash
# session-help-surface.sh — SessionStart hook
#
# 役割:
#   HIRAI ハーネスの主要 slash command 一覧 + onboarding hint を
#   SessionStart で簡潔に表示し、採用者の初期 UX を改善する。
#   `Hint や help コマンドについてもセッション開始時に記載してください`
#   (user ask 2026-05-13) を満たす実装。
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 環境変数:
#   HC_SESSION_HELP_ENABLED=false   ... 一時無効化
#   HC_SESSION_HELP_VERBOSE=true    ... 詳細版 (全 command 列挙)、default は要点のみ
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

# === 共通: 簡潔版 (default) ===
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

exit 0
