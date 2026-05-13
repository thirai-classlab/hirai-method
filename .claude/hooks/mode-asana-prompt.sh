#!/usr/bin/env bash
# mode-asana-prompt.sh — SessionStart hook
#
# 役割:
#   .claude/mode.yml の asana_enabled が未設定 (unset) の場合、user に 1 度だけ
#   「Asana 連携を利用しますか?」を <system-reminder> でヒアリングする。
#   true/false が既に設定されていれば no-op。
#
# 仕組み:
#   1. mode-loader.sh の load_asana_enabled で現値を取得
#   2. "true" / "false" なら何もせず exit 0
#   3. "unset" なら system-reminder を注入し user に /mode asana on|off を提案
#
# 失敗時の挙動: exit 0 のみ。セッション起動をブロックしない。

set -u

# stdin を消費 (SessionStart 入力 JSON があれば破棄)
cat > /dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mode-loader 読み込み
if [ -f "$SCRIPT_DIR/lib/mode-loader.sh" ]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/mode-loader.sh"
  ASANA=$(load_asana_enabled)
else
  ASANA="unset"
fi

# 設定済みなら何もしない
if [ "$ASANA" != "unset" ]; then
  exit 0
fi

cat <<'EOF'
<system-reminder>
**HIRAI メソッド: Asana 連携モード 未決定**

このプロジェクトの `.claude/mode.yml` で `asana_enabled` が未設定です。
Asana 連携 (Asana タスク文脈取得 / `docs/work.md` 自動生成 / Slack スレ取込) を利用するかを user に決定してもらう必要があります。

このセッションの最初の応答で、ユーザに **以下を必ず 1 度だけ提案** してください:

> 「このプロジェクトで Asana 連携を利用しますか?
>   - **利用する**: `/mode asana on` を実行 → 以降 `/work-init` 等の Asana 関連機能が有効化
>   - **利用しない**: `/mode asana off` を実行 → Asana 関連機能は OFF、それ以外の HIRAI メソッド機能はすべて利用可能
>   - 後で決める: `.claude/mode.yml` を直接編集してください」

ユーザの応答に従い `/mode asana <on|off>` を実行してください。
ユーザが「後で」と回答した場合、本セッションでは Asana 関連機能 (W6) は呼び出さないこと。

切替方法:
- `/mode asana on` / `/mode asana off` slash command
- `.claude/mode.yml` の `asana_enabled:` 行を直接編集 (`true` / `false`)
- 一時切替: `HC_ASANA_ENABLED=true` または `=false` 環境変数
</system-reminder>
EOF

exit 0
