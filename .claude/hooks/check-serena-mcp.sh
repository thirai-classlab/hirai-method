#!/usr/bin/env bash
# check-serena-mcp.sh — SessionStart hook
#
# 役割:
#   `.mcp.json` の `serena` entry 存在を SessionStart で確認する。
#   不在時は <system-reminder> を stdout に流して導入手順を提示する。
#   `/save-state` `/resume-state` `/pm-start` が Serena MCP を memory
#   backend として必須化したことに伴う警告。
#
# 失敗時の挙動: 常に exit 0 (fail-open — セッションをブロックしない)。
#
# 環境変数:
#   HC_CHECK_SERENA_ENABLED=false  ... 一時無効化 (Serena 不要環境向け)
#
# Stdin:  SessionStart hook JSON (読み捨て)
# Stdout: 警告 <system-reminder> ブロック (serena 不在時のみ)
# Stderr: 未使用
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
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled check_serena_mcp; then
  exit 0   # feature OFF で no-op
fi

# stdin 消費 (SessionStart JSON は使わない)
cat >/dev/null 2>&1 || true

# 無効化チェック
if [ "${HC_CHECK_SERENA_ENABLED:-true}" = "false" ]; then
  exit 0
fi

# shellcheck source=lib/project-root.sh
source "$SCRIPT_DIR/lib/project-root.sh"
PROJECT_ROOT=$(resolve_project_root)
MCP_JSON="$PROJECT_ROOT/.mcp.json"

# Case A: .mcp.json 自体が不在 → 警告 + 導入手順
if [ ! -f "$MCP_JSON" ]; then
  cat <<'EOF'
<system-reminder>
**HIRAI メソッド: Serena MCP 未設定の警告**

`.mcp.json` が見つかりません。`/save-state` `/resume-state` `/pm-start` は
Serena MCP を memory backend として必須とします。

**導入手順**:
1. プロジェクト root に `.mcp.json` を作成
2. 以下の `serena` entry を追加:
```json
{
  "mcpServers": {
    "serena": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/oraios/serena",
        "serena",
        "start-mcp-server",
        "--context",
        "ide-assistant"
      ]
    }
  }
}
```

警告を一時無効化: `export HC_CHECK_SERENA_ENABLED=false`
</system-reminder>
EOF
  exit 0
fi

# Case B: .mcp.json 存在 → `serena` entry 有無を確認
# jq があれば構造的 parse、無ければ grep で簡易検出 (silent fallback)。
has_serena=""
if command -v jq >/dev/null 2>&1; then
  has_serena=$(jq -r '.mcpServers.serena // empty' "$MCP_JSON" 2>/dev/null || echo "")
else
  has_serena=$(grep -E '"serena"[[:space:]]*:' "$MCP_JSON" 2>/dev/null || echo "")
fi

if [ -z "$has_serena" ]; then
  cat <<'EOF'
<system-reminder>
**HIRAI メソッド: Serena MCP 未登録の警告**

`.mcp.json` に `serena` entry が見つかりません。
`/save-state` `/resume-state` `/pm-start` は Serena MCP を memory backend
として必須とします。

**追加手順**: `.mcp.json` の `mcpServers` に以下を追加:
```json
"serena": {
  "command": "uvx",
  "args": [
    "--from",
    "git+https://github.com/oraios/serena",
    "serena",
    "start-mcp-server",
    "--context",
    "ide-assistant"
  ]
}
```

警告を一時無効化: `export HC_CHECK_SERENA_ENABLED=false`
</system-reminder>
EOF
fi

exit 0
