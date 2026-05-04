#!/usr/bin/env bash
# config-loader.sh — pure-bash YAML loader for .claude/harness-config.yml
#
# 役割:
#   harness-config.yml を読み、shell 変数として export する。
#   外部依存 (yq / python / jq) ゼロ。
#
# 使い方:
#   source .claude/hooks/lib/config-loader.sh
#   echo "$HC_TASK_DIR"                  # docs/tasks
#   echo "$HC_PROTECTED_PATHS"           # 改行区切り: src\ntests\nscripts
#   for p in $HC_PROTECTED_PATHS; do ... done    # space split (改行→space で iterable)
#
# サポート YAML 形式:
#   key: value                  → HC_KEY="value"
#   key: "value"                → HC_KEY="value"   (quote 自動 strip)
#   key: 'value'                → HC_KEY="value"
#   key: [a, b, c]              → HC_KEY=$'a\nb\nc' (改行区切りリスト)
#   # comment                   → 行頭 # スキップ
#   (空行)                      → スキップ
#
# 非サポート (やらない):
#   - ネスト ("  child: value")
#   - 複数行値 (`|` `>`)
#   - YAML アンカー / リファレンス
#   - 行末コメント (例: `key: value # comment` → "value # comment" になる)
#
# tilde 展開:
#   `~` および `~/` で始まる値は $HOME に展開する (例: ~/.claude/homunculus → /Users/.../.claude/homunculus)。
#
# fail-open 設計:
#   - config 不在: WARN を stderr に出して既定値を export する
#   - parse 失敗 1 行: その行のみスキップ
#   - 必須キー欠如: 既定値 fallback (hook が動作不能にならないよう)

# --- 設定ファイルパス決定 ---
# 優先順:
#   1. HC_CONFIG_PATH (環境変数で明示指定)
#   2. CLAUDE_PROJECT_DIR/.claude/harness-config.yml (Claude Code 注入)
#   3. <pwd>/.claude/harness-config.yml ("ハーネスがサブディレクトリ" な構成への対応)
#   4. <git toplevel>/.claude/harness-config.yml
#   5. <pwd>/.claude/harness-config.yml (最終 fallback)
_hc_resolve_config() {
  if [ -n "${HC_CONFIG_PATH:-}" ]; then
    printf '%s' "$HC_CONFIG_PATH"
    return
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "${CLAUDE_PROJECT_DIR}/.claude/harness-config.yml" ]; then
    printf '%s' "${CLAUDE_PROJECT_DIR}/.claude/harness-config.yml"
    return
  fi
  if [ -f "$(pwd)/.claude/harness-config.yml" ]; then
    printf '%s' "$(pwd)/.claude/harness-config.yml"
    return
  fi
  if _hc_top=$(git rev-parse --show-toplevel 2>/dev/null); then
    if [ -f "${_hc_top}/.claude/harness-config.yml" ]; then
      printf '%s' "${_hc_top}/.claude/harness-config.yml"
      return
    fi
  fi
  # 最終 fallback (存在しなくても WARN だけ出して defaults で続行)
  printf '%s' "$(pwd)/.claude/harness-config.yml"
}

HC_CONFIG_PATH=$(_hc_resolve_config)
unset -f _hc_resolve_config

# --- 既定値 (fallback) ---
# config 不在時 / 該当 key 欠如時にこの値が採用される。
# 旧来の hardcode と同等の振る舞いを保つ。
HC_PROTECTED_PATHS=$'src\ntests\nscripts'
HC_TASK_DIR="docs/tasks"
HC_DRAFT_DIR="docs/draft"
HC_BASH_WHITELIST_PATH=".claude/bash-whitelist.txt"
HC_GATEGUARD_STATE_DIR=".claude/.gateguard-state"
HC_TASKGUARD_STATE_DIR=".claude/.taskguard-state"
HC_AGENT_MARKER_DIR=".claude/.agent-markers"
HC_FAILURE_WINDOW_DIR=".claude/.failure-window"
HC_HOMUNCULUS_ROOT="$HOME/.claude/homunculus"
HC_NOTIFY_SOUND="/System/Library/Sounds/Hero.aiff"
HC_STOP_SOUND="/System/Library/Sounds/Glass.aiff"
HC_CONFIDENCE_THRESHOLD="0.6"
HC_CONFIDENCE_REQUIRED="true"
HC_CONFIDENCE_STATE_DIR=".claude/.confidence-gate-state"

# --- 値整形 helper ---
# tilde 展開 + クォート strip + 前後空白 trim
_hc_normalize() {
  local v="$1"
  # 前後空白 trim
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  # 外側のクォート strip ('value' / "value")
  if [ "${#v}" -ge 2 ]; then
    case "$v" in
      \"*\") v="${v#\"}"; v="${v%\"}" ;;
      \'*\') v="${v#\'}"; v="${v%\'}" ;;
    esac
  fi
  # tilde 展開 (~/foo / ~ のみ。~user/foo は非対応)
  # 注: ${v#~/} は bash の tilde 展開が走り `/Users/.../~/...` になるので、
  # パターンは必ず `"~/"` のように引用符で囲む。
  case "$v" in
    "~")    v="$HOME" ;;
    "~/"*)  v="$HOME/${v#"~/"}" ;;
  esac
  printf '%s' "$v"
}

# --- 設定 parse ---
# config 不在は warning のみ (fail-open)。
if [ ! -f "$HC_CONFIG_PATH" ]; then
  printf '[config-loader] WARN: %s not found, using defaults\n' "$HC_CONFIG_PATH" >&2
else
  # bash の read を使う。IFS で分割しない (line 全体保持)。
  while IFS= read -r _hc_line || [ -n "$_hc_line" ]; do
    # 行頭空白 trim (CRLF も除去)
    _hc_line="${_hc_line%$'\r'}"
    _hc_stripped="${_hc_line#"${_hc_line%%[![:space:]]*}"}"
    # コメント / 空行
    case "$_hc_stripped" in
      ''|\#*) continue ;;
    esac
    # ネスト行 (先頭インデントあり) は非対応 → skip
    case "$_hc_line" in
      [[:space:]]*) continue ;;
    esac
    # `key:` 区切り判定
    case "$_hc_stripped" in
      *:*) ;;
      *) continue ;;
    esac
    _hc_key="${_hc_stripped%%:*}"
    _hc_val="${_hc_stripped#*:}"
    # key を大文字 + 非英数を _ に正規化
    _hc_key_upper=$(printf '%s' "$_hc_key" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_')
    _hc_key_upper="${_hc_key_upper%_}"  # 末尾 _ 除去
    # 値の前後空白 trim
    _hc_val="${_hc_val#"${_hc_val%%[![:space:]]*}"}"
    _hc_val="${_hc_val%"${_hc_val##*[![:space:]]}"}"
    # 配列構文 [a, b, c] 判定
    case "$_hc_val" in
      \[*\])
        _hc_inner="${_hc_val#\[}"
        _hc_inner="${_hc_inner%\]}"
        _hc_list=""
        # `,` で分割
        IFS=',' read -ra _hc_items <<< "$_hc_inner"
        for _hc_item in "${_hc_items[@]}"; do
          _hc_norm=$(_hc_normalize "$_hc_item")
          if [ -n "$_hc_norm" ]; then
            if [ -z "$_hc_list" ]; then
              _hc_list="$_hc_norm"
            else
              _hc_list="$_hc_list"$'\n'"$_hc_norm"
            fi
          fi
        done
        eval "HC_${_hc_key_upper}=\"\$_hc_list\""
        ;;
      *)
        _hc_norm=$(_hc_normalize "$_hc_val")
        eval "HC_${_hc_key_upper}=\"\$_hc_norm\""
        ;;
    esac
  done < "$HC_CONFIG_PATH"
fi

# --- protected_paths 派生値 ---
# delegation-guard が case glob で使うパターン (例: "*/src/*|*/tests/*|*/scripts/*")
HC_PROTECTED_GLOB_FILE=""
HC_PROTECTED_GLOB_DIR=""
HC_PROTECTED_LEAK_REGEX=""
while IFS= read -r _hc_p; do
  [ -z "$_hc_p" ] && continue
  if [ -z "$HC_PROTECTED_GLOB_FILE" ]; then
    HC_PROTECTED_GLOB_FILE="*/${_hc_p}/*"
  else
    HC_PROTECTED_GLOB_FILE="${HC_PROTECTED_GLOB_FILE}|*/${_hc_p}/*"
  fi
  # Grep/Glob 用 (path 末尾 = ディレクトリ指定も対象)
  if [ -z "$HC_PROTECTED_GLOB_DIR" ]; then
    HC_PROTECTED_GLOB_DIR="*/${_hc_p}/*|*/${_hc_p}"
  else
    HC_PROTECTED_GLOB_DIR="${HC_PROTECTED_GLOB_DIR}|*/${_hc_p}/*|*/${_hc_p}"
  fi
  # Bash path-leak 検査用 alternation (regex の OR)
  if [ -z "$HC_PROTECTED_LEAK_REGEX" ]; then
    HC_PROTECTED_LEAK_REGEX="${_hc_p}"
  else
    HC_PROTECTED_LEAK_REGEX="${HC_PROTECTED_LEAK_REGEX}|${_hc_p}"
  fi
done <<< "$HC_PROTECTED_PATHS"

# --- ヒューマンリーダブル形 (エラーメッセージ用) ---
# "src/ tests/ scripts/" のような表示文字列。
HC_PROTECTED_DISPLAY=""
while IFS= read -r _hc_p; do
  [ -z "$_hc_p" ] && continue
  if [ -z "$HC_PROTECTED_DISPLAY" ]; then
    HC_PROTECTED_DISPLAY="${_hc_p}/"
  else
    HC_PROTECTED_DISPLAY="${HC_PROTECTED_DISPLAY} ${_hc_p}/"
  fi
done <<< "$HC_PROTECTED_PATHS"

# --- export ---
# subshell でも参照できるよう export する。
export HC_CONFIG_PATH
export HC_PROTECTED_PATHS HC_PROTECTED_GLOB_FILE HC_PROTECTED_GLOB_DIR
export HC_PROTECTED_LEAK_REGEX HC_PROTECTED_DISPLAY
export HC_TASK_DIR HC_DRAFT_DIR
export HC_BASH_WHITELIST_PATH
export HC_GATEGUARD_STATE_DIR HC_TASKGUARD_STATE_DIR
export HC_AGENT_MARKER_DIR HC_FAILURE_WINDOW_DIR
export HC_HOMUNCULUS_ROOT
export HC_NOTIFY_SOUND HC_STOP_SOUND
export HC_CONFIDENCE_THRESHOLD HC_CONFIDENCE_REQUIRED HC_CONFIDENCE_STATE_DIR

# --- 内部変数を unset (caller を汚染しない) ---
unset _hc_root _hc_top _hc_line _hc_stripped _hc_key _hc_key_upper
unset _hc_val _hc_inner _hc_list _hc_items _hc_item _hc_norm _hc_p
