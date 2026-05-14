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
#     "tool_response": { ... }   # optional, contains subagent reply payload
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

# config 読み込み (HC_* 変数 export)。
# config-loader.sh は呼び出し時に既に export されている HC_* env 値を
# preset として保持し、YAML 値より優先して再適用する (env > YAML > defaults)。
# したがって confidence-gate 側で個別の env preservation を行う必要は無い。
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

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

# bypass.log 拡張: 失敗理由を構造化ログ。
#   引数: $1 = phase (regex_no_match / no_transcript / file_not_found / extract_failed
#                     / below_threshold / below_threshold_via_tool_response)
#         $2 = detail (任意 free text、200 char 上限、改行/タブは空白に置換)
log_failure() {
  local phase="$1"
  local detail="${2:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  detail=$(printf '%s' "$detail" | tr '\n\t' '  ' | cut -c1-200)
  printf '%s\tfailed: %s\t%s\n' "$ts" "$phase" "$detail" >> "$bypass_log" 2>/dev/null
}

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

# === 抽出ヘルパー: confidence 数値を文字列から抜く ===
# 対応 variant:
#   confidence: 0.85
#   Confidence: 0.85
#   confidence_score: 0.85
#   confidence score: 0.85
#   信頼度: 0.85
#   信頼度 0.85
# 数値レンジ: 0(.0..) / 1(.0..)
# 区切り: 半角 ":" / 全角 "："（記号のみ env-portable な POSIX class で）
extract_confidence() {
  local text="$1"
  local m
  # 英語 variant — confidence / confidence_score / confidence score
  m=$(printf '%s' "$text" | grep -ioE '(confidence([_[:space:]]*score)?)[[:space:]]*[:：][[:space:]]*(0(\.[0-9]+)?|1(\.0+)?)' | tail -n 1)
  if [ -z "$m" ]; then
    # 日本語 variant — 信頼度: 0.X / 信頼度 0.X
    m=$(printf '%s' "$text" | grep -ioE '信頼度[[:space:]]*[:：]?[[:space:]]*(0(\.[0-9]+)?|1(\.0+)?)' | tail -n 1)
  fi
  printf '%s' "$m"
}

# === fallback: hook input の tool_response から最終 reply text を構築 ===
extract_tool_response_text() {
  printf '%s' "$1" | jq -r '
    (.tool_response // {})
    | if type == "string" then .
      elif type == "object" then
        (.content // .text // "")
        | if type == "array" then
            [ .[] | (.text // (if type == "string" then . else "" end)) ] | join("\n")
          elif type == "string" then .
          else "" end
      else "" end
  ' 2>/dev/null
}

# === agent_type 抽出 (W1, task #9) ===
# SubagentStop hook は agent_type を問わず全 stop event で fire するため、
# 軽量 sidechain (Task tool query / tool-use only) で 96 件の regex_no_match
# が累積する事故があった (/harness-audit 2026-05-13 観察)。
# major subagent (general-purpose 等の allowlist or path_subagents) 以外は
# fail-open で通過させ、major subagent only に confidence 自己評価を強制する。
agent_type=$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null)

# === transcript path 取得 ===
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# === subagent transcript 解決 ===
# SubagentStop hook に渡される transcript_path は親セッションの JSONL を指すことがある。
# 実際のサブエージェント応答は <parent_stem>/subagents/agent-<id>.jsonl に書かれる。
# agent_id が SubagentStop JSON に含まれる場合は subagent ファイルを優先して読む。
_cg_agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
if [ -n "$_cg_agent_id" ] && [ -n "$transcript" ] && [ "$transcript" != "null" ]; then
  # transcript_path の stem ディレクトリを基点に subagents/ を探す
  _cg_stem="${transcript%.jsonl}"
  _cg_subagent_file="${_cg_stem}/subagents/agent-${_cg_agent_id}.jsonl"
  if [ -f "$_cg_subagent_file" ]; then
    transcript="$_cg_subagent_file"
  fi
fi
unset _cg_agent_id _cg_stem _cg_subagent_file

# === sidechain 判定 ===
# Claude Code のサブエージェント transcript は path に "/subagents/" を含むか
# 各レコード内 "isSidechain": true を持つ。判定して bypass.log に記録するが、
# 動作上は: sidechain でも親 transcript でも、与えられた path をそのまま読む
# (= 親 transcript への遡上はしない)。
is_sidechain="unknown"
case "$transcript" in
  */subagents/*) is_sidechain="path_subagents" ;;
esac

# === major subagent 判定 (W1, task #9) ===
# allowlist match (agent_type が general-purpose / Explore / Task) または
# is_sidechain==path_subagents なら major subagent (confidence 必須)。
# それ以外 (軽量 sidechain / Task tool query etc.) は extract_confidence 失敗時に fail-open。
# bypass: HC_CONFIDENCE_MAJOR_AGENT_ONLY=false で従来動作 (全 stop event で block 判定)。
is_major_subagent="false"
case "$agent_type" in
  general-purpose|Explore|Task) is_major_subagent="true" ;;
esac
if [ "$is_sidechain" = "path_subagents" ]; then
  is_major_subagent="true"
fi

emit_block() {
  local r="$1"
  jq -n --arg r "$r" '{decision:"block", reason:$r}'
}

# transcript 不在 / null / 不存在 → tool_response fallback を試す
if [ -z "$transcript" ] || [ "$transcript" = "null" ] || [ ! -f "$transcript" ]; then
  fallback_text=$(extract_tool_response_text "$input")
  if [ -n "$fallback_text" ]; then
    fb_match=$(extract_confidence "$fallback_text")
    if [ -n "$fb_match" ]; then
      threshold="${HC_CONFIDENCE_THRESHOLD:-0.6}"
      score=$(printf '%s' "$fb_match" | sed -E 's/.*[:：][[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')
      ok=$(awk -v s="$score" -v t="$threshold" 'BEGIN { print (s+0 >= t+0) ? "1" : "0" }')
      if [ "$ok" = "1" ]; then
        echo '{}'
        exit 0
      fi
      log_failure "below_threshold_via_tool_response" "score=${score} threshold=${threshold}"
      reason_block="[confidence-gate] tool_response 経由で抽出した confidence ${score} が閾値 ${threshold} 未満です。"
      emit_block "$reason_block"
      exit 0
    fi
  fi

  if [ -z "$transcript" ] || [ "$transcript" = "null" ]; then
    log_failure "no_transcript" "transcript_path missing or null"
  else
    log_failure "file_not_found" "path=${transcript}"
  fi
  echo '{}'
  exit 0
fi

# === 最終 assistant text を抽出 ===
# transcript は JSONL。末尾 500 行から assistant role のメッセージを集める
# (元 200 行では subagent の長い summary が境界をまたぎ confidence を見落とす
# ケースが頻発したため拡大)。
# Claude Code transcript schema 新旧両対応:
#   旧: {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}
#   新: {"role":"assistant","content":[{"type":"text","text":"..."}]} 等
final_text=$(tail -n 500 "$transcript" 2>/dev/null | jq -rs '
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

# transcript 内の sidechain 判定補強 (path だけでは判別できない場合)
if [ "$is_sidechain" = "unknown" ]; then
  if grep -q '"isSidechain"[[:space:]]*:[[:space:]]*true' "$transcript" 2>/dev/null; then
    is_sidechain="record_isSidechain"
  else
    is_sidechain="no"
  fi
fi

if [ -z "$final_text" ]; then
  log_failure "extract_failed" "transcript=${transcript} sidechain=${is_sidechain}"
  # 抽出失敗 → fail-open
  echo '{}'
  exit 0
fi

# === confidence: 0.X を抽出 (variant 対応) ===
match=$(extract_confidence "$final_text")

threshold="${HC_CONFIDENCE_THRESHOLD:-0.6}"

if [ -z "$match" ]; then
  # === fallback: tool_response からの救済 ===
  # transcript には summary 全文があったが confidence variant が不在の場合、
  # hook input の tool_response (subagent 最終 reply) を最後にもう一度確認。
  fallback_text=$(extract_tool_response_text "$input")
  if [ -n "$fallback_text" ]; then
    match=$(extract_confidence "$fallback_text")
  fi
fi

if [ -z "$match" ]; then
  # === major subagent でなければ fail-open (W1, task #9) ===
  # 軽量 sidechain (Task tool query / tool-use only sidechain 等) は confidence
  # 自己評価を含めない設計のため、ここで block すると 96 件規模の noise が
  # bypass.log に堆積する (/harness-audit 2026-05-13 観察)。
  # bypass: HC_CONFIDENCE_MAJOR_AGENT_ONLY=false で従来動作復帰。
  if [ "$is_major_subagent" = "false" ] && [ "${HC_CONFIDENCE_MAJOR_AGENT_ONLY:-true}" != "false" ]; then
    log_failure "skipped_minor_sidechain" "agent_type=${agent_type} sidechain=${is_sidechain} transcript_chars=${#final_text}"
    echo '{}'
    exit 0
  fi

  log_failure "regex_no_match" "transcript_chars=${#final_text} sidechain=${is_sidechain}"
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
score=$(printf '%s' "$match" | sed -E 's/.*[:：][[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/')

# awk で浮動小数比較（bash native は浮動小数非対応）
ok=$(awk -v s="$score" -v t="$threshold" 'BEGIN { print (s+0 >= t+0) ? "1" : "0" }')

if [ "$ok" = "1" ]; then
  # pass
  echo '{}'
  exit 0
fi

# block — 閾値未満
log_failure "below_threshold" "score=${score} threshold=${threshold} sidechain=${is_sidechain}"
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
