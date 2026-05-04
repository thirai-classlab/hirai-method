#!/usr/bin/env bash
# confidence-gate.sh — SubagentStop hook (F3) — confidence threshold gate
#
# 役割:
#   サブエージェントが返す completion summary（最終 assistant text）に
#   `confidence: 0.X` の自己評価が含まれているかを検証する。
#   閾値未満 / 未記載なら block 判定を返し、メインエージェントが
#   「曖昧なまま /finish-task に進む」のを抑止する。
#
#   SuperClaude / OpenAI o1 系の self-confidence threshold パターンを模倣。
#
# Hook event: SubagentStop
# Stdin: SubagentStop JSON
#   {
#     "session_id": "...",
#     "transcript_path": "/path/to/.jsonl",
#     "agent_type": "general-purpose" / "Explore" / etc.,
#     ...
#   }
#
# Output:
#   pass  → exit 0 + `{}` （素通し）
#   block → exit 0 + `{"decision":"block","reason":"..."}` （SubagentStop block JSON）
#
# Bypass:
#   ECC_CONFIDENCE_GATE=off          # セッション全体で OFF（fail-open）
#   HC_CONFIDENCE_REQUIRED=false     # config 値レベルで OFF
#   /gate-bypass confidence <reason> # 1 回分の pass marker を touch
#
# Config keys consumed (.claude/harness-config.yml):
#   confidence_threshold       # 浮動小数（0.0〜1.0）
#   confidence_required        # true なら未記載で block、false なら pass
#   confidence_state_dir       # bypass marker / bypass.log の位置

set -u

# config を source する前に env 値を退避（config-loader.sh は YAML 値で
# 上書きしてしまうため、env による override を効かせるには事前 capture が必要）
_env_required="${HC_CONFIDENCE_REQUIRED-}"
_env_threshold="${HC_CONFIDENCE_THRESHOLD-}"
_env_state_dir="${HC_CONFIDENCE_STATE_DIR-}"

# config 読み込み (HC_* 変数 export)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

# env で明示指定された値で再上書き（env > YAML の優先順）
if [ -n "$_env_required" ];  then HC_CONFIDENCE_REQUIRED="$_env_required";   fi
if [ -n "$_env_threshold" ]; then HC_CONFIDENCE_THRESHOLD="$_env_threshold"; fi
if [ -n "$_env_state_dir" ]; then HC_CONFIDENCE_STATE_DIR="$_env_state_dir"; fi
unset _env_required _env_threshold _env_state_dir

# Phase β: F3 disable for SWE-bench grid evaluation (fail-open)
# ECC_F{1,2,3}_OFF env vars allow runner.py to bypass gates per-task
# while measuring gate effectiveness. Production usage MUST NOT set these.
if [ "${ECC_F3_OFF:-0}" = "1" ] || [ "${ECC_F3_OFF:-}" = "true" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{decision:"approve", reason:"F3 (confidence-gate) disabled via ECC_F3_OFF"}'
  else
    printf '{"decision":"approve","reason":"F3 (confidence-gate) disabled via ECC_F3_OFF"}\n'
  fi
  exit 0
fi

# === 全 bypass (env) ===
if [ "${ECC_CONFIDENCE_GATE:-}" = "off" ]; then
  echo '{}'
  exit 0
fi

# === config レベル OFF ===
if [ "${HC_CONFIDENCE_REQUIRED:-true}" = "false" ]; then
  echo '{}'
  exit 0
fi

input=$(cat)

# === jq 必須（無ければ fail-open）===
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# === bypass marker check（1 回 pass + re-arm）===
state_dir="${HC_CONFIDENCE_STATE_DIR:-.claude/.confidence-gate-state}"
mkdir -p "$state_dir" 2>/dev/null
bypass_marker="${state_dir}/bypass.cleared"
bypass_log="${state_dir}/bypass.log"

if [ -f "$bypass_marker" ]; then
  bypass_reason=""
  if [ -s "$bypass_marker" ]; then
    bypass_reason=$(cat "$bypass_marker" 2>/dev/null | head -c 200)
  fi
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '%s\tbypassed: %s\n' "$ts" "${bypass_reason:-(no reason given)}" >> "$bypass_log" 2>/dev/null
  rm -f "$bypass_marker" 2>/dev/null
  echo '{}'
  exit 0
fi

# === transcript path 取得 ===
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$transcript" ] || [ "$transcript" = "null" ] || [ ! -f "$transcript" ]; then
  # transcript なし → fail-open（hook 自体が無効化されないよう）
  echo '{}'
  exit 0
fi

# === 最終 assistant text を抽出 ===
# transcript は JSONL。末尾 200 行から assistant role のメッセージを集める。
# Claude Code transcript schema 新旧両対応:
#   旧: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
#   新: {"role":"assistant","content":[{"type":"text","text":"..."}]} 等
final_text=$(tail -n 200 "$transcript" 2>/dev/null | jq -rs '
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
          elif type == "string" then
            .
          else
            ""
          end
      )
  ]
  | join("\n")
' 2>/dev/null)

if [ -z "$final_text" ]; then
  # 抽出失敗 → fail-open
  echo '{}'
  exit 0
fi

# === confidence: 0.X を grep ===
# 大文字小文字無視、`confidence` の後に 0.0〜1.0 の数値を期待
match=$(printf '%s' "$final_text" | grep -ioE 'confidence[[:space:]]*:[[:space:]]*(0(\.[0-9]+)?|1(\.0+)?)' | tail -n 1)

threshold="${HC_CONFIDENCE_THRESHOLD:-0.6}"

emit_block() {
  local r="$1"
  jq -n --arg r "$r" '{decision:"block", reason:$r}'
}

if [ -z "$match" ]; then
  reason="[confidence-gate] サブエージェントの completion summary に confidence 自己評価が見つかりません。

期待 format:
  confidence: 0.X    （0.0〜1.0、現在の閾値 = ${threshold}）

confidence 算出基準:
  0.9-1.0  全条件を実測値で確認（build/test/grep の生 log 引用可）
  0.7-0.8  主要条件は確認、周辺は推定（一部 grep 未実行など）
  0.5-0.6  実装は完了したが検証が浅い、あるいは未確認の前提に依存
  0.0-0.4  方針が不明確、あるいは曖昧な仮実装

記載例:
  '実装完了。\$IMPL_FILE に 3 関数追加、5 件の unit test PASS、grep で caller 4 ファイル変更不要を確認。confidence: 0.85'

Bypass:
  /gate-bypass confidence <reason>     # 次回 1 回だけ pass
  ECC_CONFIDENCE_GATE=off              # セッション全体で OFF
  HC_CONFIDENCE_REQUIRED=false         # config レベル OFF"
  reason="${reason//\$\{threshold\}/$threshold}"
  emit_block "$reason"
  exit 0
fi

# === 数値抽出 + 閾値比較 ===
score=$(printf '%s' "$match" | sed -E 's/.*[Cc][Oo][Nn][Ff][Ii][Dd][Ee][Nn][Cc][Ee][[:space:]]*:[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')

# awk で浮動小数比較（bash native は浮動小数非対応）
ok=$(awk -v s="$score" -v t="$threshold" 'BEGIN { print (s+0 >= t+0) ? "1" : "0" }')

if [ "$ok" = "1" ]; then
  # pass
  echo '{}'
  exit 0
fi

# block — 閾値未満
reason="[confidence-gate] confidence ${score} が閾値 ${threshold} 未満です。

サブエージェントの自己評価が低い状態で完了宣言を返しています。
以下のいずれかで対処してください:

1. 不足している検証を追加実行し、confidence を再評価する
   - build/test の実測 log を取得
   - grep / Read で前提（caller, schema, env 等）を確認
   - 失敗ケース / edge case を 1 つでも実測

2. confidence を上げられない事情があれば、未解決事項を箇条書きで明示し
   /finish-task ではなく user に判断を仰ぐ

3. やむを得ず通過させる場合:
   /gate-bypass confidence <理由>      # 次回 1 回だけ pass
   ECC_CONFIDENCE_GATE=off              # セッション全体で OFF"

emit_block "$reason"
exit 0
