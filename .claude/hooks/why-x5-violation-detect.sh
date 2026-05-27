#!/usr/bin/env bash
# why-x5-violation-detect.sh — PostToolUse hook
#
# 役割:
#   AI 直前応答 (transcript 末尾) を grep し、Why × 5 v10 format 違反 (4 セクション
#   format / 「【システムの存在意義】」「【whyN】」等の v9 残骸 / 「何のため」省略)
#   を検出した場合のみ、`<system-reminder>` で v10 1 行 format を再注入する。
#   違反未検出時は silent (exit 0)。
#
# 設計の根本変更 (task-21 W0.3, 2026-05-23):
#   旧 why-x5-reminder.sh は UserPromptSubmit で毎ターン全文 (~2 KB) 注入していたが、
#   AI は 1 度読めば理解しているため過剰だった。
#   本 hook が「実際に違反した時のみ」再注入することで attention dilution を解消。
#
# 簡略実装 (初期版):
#   transcript の末尾 50 行から最後の assistant text を抽出し、以下を grep:
#     - v9 残骸: "【システムの存在意義】" / "【whyN】" / "【現在行っていること】" / "【他の選択肢を取らない理由】"
#   検出時は <system-reminder> 出力、未検出時は silent。
#   将来精度向上の余地: 「何のため」省略の構文解析、装飾行 (見出し / 表) 検出など。
#
# 環境変数:
#   HC_WHY_X5_VIOLATION_ENABLED=false   ... 無効化
#
# 失敗時の挙動:
#   - exit 0 のみ。failure は fail-open。
#
# 設計起源:
#   docs/draft/system-reminder-attention-fix.md §2 W0.3
#   docs/tasks/task-21-system-reminder-attention-fix.md W0.3
#
# 共有 feature toggle group:
#   - グループ制御 toggle: `feature_why_x5_enforcement_enabled` (default: true)
#   - OFF にすると本 hook を含む同 group の全 hook が no-op
#   - 編集: `bash .claude/scripts/hc-config.sh --feature why_x5_enforcement=false`
#   - 同 group の他 hook: why-x5-reminder.sh

set -u

# config 読み込み (HC_* 変数 + is_feature_enabled 関数 export、task-45 Phase 2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
. "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled why_x5_enforcement; then
  echo '{}'
  exit 0   # feature OFF で no-op (PostToolUse hook response 規約: empty JSON)
fi

# stdin を必ず消費
input=$(cat 2>/dev/null || true)

# --- 早期 bypass ---
if [ "${HC_WHY_X5_VIOLATION_ENABLED:-true}" = "false" ]; then
  exit 0
fi

if [ "${HC_WHY_X5_DISABLE:-0}" = "1" ]; then
  exit 0
fi

# --- 依存チェック ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- transcript_path 抽出 ---
transcript_path=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  exit 0
fi

# --- 直前 assistant text 抽出 (末尾 50 行) ---
last_assistant=$(tail -n 50 "$transcript_path" 2>/dev/null | jq -rs '
  [
    .[]
    | select(
        ((.type // "") == "assistant")
        or ((.role // "") == "assistant")
        or (((.message // {}).role // "") == "assistant")
      )
    | (
        ((.message // .).content)
        | if type == "array" then
            [ .[] | (.text // "") ] | join("\n")
          elif type == "string" then .
          else "" end
      )
  ]
  | last // ""
' 2>/dev/null)

if [ -z "$last_assistant" ]; then
  exit 0
fi

# --- v9 4 セクション format 残骸検出 ---
# default パターン (env override 可、改行区切り)
DEFAULT_PATTERNS='【システムの存在意義】
【whyN】
【現在行っていること】
【他の選択肢を取らない理由】
【why1】
【why2】
【why3】'

PATTERNS="${HC_WHY_X5_VIOLATION_PATTERNS:-$DEFAULT_PATTERNS}"

matched=""
while IFS= read -r pat; do
  if [ -n "$pat" ] && printf '%s' "$last_assistant" | grep -qF "$pat"; then
    matched="$pat"
    break
  fi
done <<< "$PATTERNS"

if [ -z "$matched" ]; then
  exit 0
fi

# --- system-reminder 注入 ---
cat <<EOF
<system-reminder>
**Why × 5 v10 format 違反検出 (why-x5-violation-detect)**

直前応答に v9 残骸 (4 セクション format) が含まれています:
  matched pattern: \`${matched}\`

v10 format (2026-05-23 確定、\`.claude/rules/why-x5-output.md\`):

  「<何のため (目的)> のため、<何をやる (今のステップ / tool / file)> を行う」

要件:
- ステップごとに **1 行** (ツール呼び出し前 / 別ステップ移行時 / 別 file 編集時)
- 4 セクション format (システム意義 / whyN / 現在の作業 / 他選択肢) は **v10 で廃止**
- 装飾 (見出し / 表 / 矢印列挙) は禁止、純粋な 1 行のみ
- 「何のため」と「何をやる」の **両方** が含まれる

OK 例:
- 「install.sh を smoke test するため、tmp dir に実 install を実行する」
- 「規範を v10 化するため、why-x5-output.md を全文書き換える」

次の作業ステップから v10 1 行 format で出力してください。

**bypass**:
- \`HC_WHY_X5_VIOLATION_ENABLED=false\` で本検出 OFF
- \`HC_WHY_X5_DISABLE=1\` で Why × 5 規範全体 OFF (雑談セッション等)
</system-reminder>
EOF

exit 0
