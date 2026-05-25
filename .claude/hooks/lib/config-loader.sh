#!/usr/bin/env bash
# config-loader.sh — pure-bash YAML loader for .claude/harness-config.yml
#
# 役割:
#   harness-config.yml を読み、shell 変数として export する。
#   外部依存 (yq / python / jq) ゼロ。
#
# 値解決の優先順 (高 → 低):
#   1. 呼び出し時に既に export されている `HC_*` 環境変数  (env override)
#   2. `.claude/harness-config.yml` の値                    (YAML)
#   3. 本ファイル内のハードコード defaults                 (fallback)
#
#   これにより、プロジェクト切替は `.env` / shell rc / direnv で
#     export HC_TASK_DIR=docs/tickets
#     export HC_PROTECTED_PATHS=$'app\nlib\nscripts'
#   と書くだけで完結する (yaml を編集する必要が無い)。
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
#   env override 経由で渡す場合も同様に展開される (`HC_HOMUNCULUS_ROOT=~/foo` → `$HOME/foo`)。
#
# fail-open 設計:
#   - config 不在: WARN を stderr に出して既定値を export する
#   - parse 失敗 1 行: その行のみスキップ
#   - 必須キー欠如: 既定値 fallback (hook が動作不能にならないよう)
#
# bash 互換性:
#   bash 3.2 (macOS 標準) でも動作する。`declare -g` `${var:-}` 等の
#   bash 4+ 機能は使用しない。env preserve は eval ベースで実装。

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

# --- 既知キー一覧 (env override の対象) ---
# YAML の key を _ 区切り大文字化したものを並べる。
# ここに無いキーは YAML から動的に load されるが、env override は適用されない
# (= 既存の挙動: env で先行設定してあっても YAML が上書きする)。
# 新規キーを追加した場合は本リストにも追加すること。
_HC_KNOWN_KEYS="\
TASK_DIR \
DRAFT_DIR \
PROTECTED_PATHS \
BASH_WHITELIST_PATH \
GATEGUARD_STATE_DIR \
TASKGUARD_STATE_DIR \
AGENT_MARKER_DIR \
FAILURE_WINDOW_DIR \
HOMUNCULUS_ROOT \
NOTIFY_SOUND \
STOP_SOUND \
CONFIDENCE_THRESHOLD \
CONFIDENCE_REQUIRED \
CONFIDENCE_STATE_DIR \
REQUIRED_ENV \
IMPROVEMENT_PROPOSAL_ENABLED \
IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS \
IMPROVEMENT_PROPOSAL_MAX_COUNT \
IMPROVEMENT_PROPOSAL_STATE_DIR \
IMPROVEMENT_PROPOSAL_DEDUP_HOURS \
CONTEXT_BUDGET_ENABLED \
CONTEXT_BUDGET_LIMIT \
CONTEXT_BUDGET_THRESHOLD \
CONTEXT_BUDGET_STATE_DIR \
LIST_PLAN_FIRST_REMINDER_ENABLED \
PARALLEL_SUBAGENT_REMINDER_ENABLED \
PARALLEL_SUBAGENT_TTL_SEC \
PARALLEL_SUBAGENT_STATE_DIR \
AGENT_TYPE_KEYWORD_MAPPING \
REVIEWER_REGISTRY_DESIGN \
REVIEWER_REGISTRY_SECURITY \
REVIEWER_REGISTRY_TEST \
REVIEWER_REGISTRY_IMPL \
WORKFLOW_STAGES_NEW \
WORKFLOW_STAGES_MODIFY \
DOCS_APPROVED_DIR"

# --- Step 1: 呼び出し時 env をスナップショット ---
# bash 3.2 互換のため eval を使う (declare -g / ${!var} はあるが eval が最も安全)。
# preset key 一覧は _HC_PRESET_KEYS に保持し、step 4 で復元時に参照する。
_HC_PRESET_KEYS=""
for _hc_k in $_HC_KNOWN_KEYS; do
  eval "_hc_v=\${HC_${_hc_k}-}"
  eval "_hc_set=\${HC_${_hc_k}+set}"
  # 「未設定」 と 「空文字列で設定済」 を区別するため `+set` を使う。
  # env で `export HC_FOO=""` しているケースは「空で上書きしたい」意図とみなし
  # YAML 値より優先する (YAML 側もシンプルに defaults へ戻すには unset すべき)。
  if [ "$_hc_set" = "set" ]; then
    _HC_PRESET_KEYS="$_HC_PRESET_KEYS $_hc_k"
    eval "_HC_PRESET_${_hc_k}=\$_hc_v"
  fi
done
unset _hc_k _hc_v _hc_set

# --- Step 2: 既定値 (fallback) ---
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
HC_REQUIRED_ENV=""
HC_IMPROVEMENT_PROPOSAL_ENABLED="true"
HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS="7"
HC_IMPROVEMENT_PROPOSAL_MAX_COUNT="3"
HC_IMPROVEMENT_PROPOSAL_STATE_DIR=".claude/.improvement-proposal-state"
HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS="24"
HC_CONTEXT_BUDGET_ENABLED="true"
HC_CONTEXT_BUDGET_LIMIT="1000000"
HC_CONTEXT_BUDGET_THRESHOLD="0.60"
HC_CONTEXT_BUDGET_STATE_DIR=".claude/.context-budget-state"
HC_LIST_PLAN_FIRST_REMINDER_ENABLED="true"
HC_PARALLEL_SUBAGENT_REMINDER_ENABLED="true"
HC_PARALLEL_SUBAGENT_TTL_SEC="300"
# PARALLEL_SUBAGENT_STATE_DIR: 空文字なら hook 内 fallback (`$repo_root/.claude/.parallel-subagent-state/`) を使用。
# テスト isolation 用に上書きしたい場合のみ設定 (例: env `HC_PARALLEL_SUBAGENT_STATE_DIR=/tmp/foo`)。
HC_PARALLEL_SUBAGENT_STATE_DIR=""
# AGENT_TYPE_KEYWORD_MAPPING: hook 内 hardcode default を採用 (draft §4.5.0 設定不要原則)。
# 空文字が default、env override 経由でのみ上書き可。yaml 経由の multi-line value は
# config-loader.sh 単行 parser の制約で flat 1 行構文 (例: "keyword1|type1,keyword2|type2") 推奨。
HC_AGENT_TYPE_KEYWORD_MAPPING=""
HC_REVIEWER_REGISTRY_DESIGN=$'architect\narchitect-reviewer\ncode-architect'
HC_REVIEWER_REGISTRY_SECURITY=$'security-auditor\nsecurity-reviewer'
HC_REVIEWER_REGISTRY_TEST=$'tdd-guide\ntest-automator\nqa-expert'
HC_REVIEWER_REGISTRY_IMPL=$'code-reviewer\nrefactoring-specialist'
HC_WORKFLOW_STAGES_NEW=$'requirements\nbasic-design\ndetailed-design\ntest-design\ndesign-review\nuser-approval\ntask-creation\ntdd\nmodule-review\nlocal-test\nsystem-review\nci-cd\nscenario-test\nfinish'
HC_WORKFLOW_STAGES_MODIFY=$'branch-decision\ncheckout\nrecover-design\npre-test\nredesign\nretest-design\ntdd\nmodule-review\nfull-test\nsystem-review'
HC_DOCS_APPROVED_DIR=""

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

# --- Step 3: YAML parse ---
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
        # 空配列 `[]` は中身なしで eval (set -u 下で _hc_items[@] unbound を回避)
        # 内側を trim して空判定
        _hc_inner_trim="${_hc_inner#"${_hc_inner%%[![:space:]]*}"}"
        _hc_inner_trim="${_hc_inner_trim%"${_hc_inner_trim##*[![:space:]]}"}"
        if [ -n "$_hc_inner_trim" ]; then
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
        fi
        eval "HC_${_hc_key_upper}=\"\$_hc_list\""
        ;;
      *)
        _hc_norm=$(_hc_normalize "$_hc_val")
        eval "HC_${_hc_key_upper}=\"\$_hc_norm\""
        ;;
    esac
  done < "$HC_CONFIG_PATH"
fi

# --- Step 4: env preset を復元 (env > YAML > defaults) ---
# Step 1 で snapshot した preset key について、env 値を強制適用する。
# tilde 展開は env override 値に対しても適用する (homunculus_root 等で
# `~/foo` を export している場合に展開される)。
for _hc_k in $_HC_PRESET_KEYS; do
  eval "_hc_v=\$_HC_PRESET_${_hc_k}"
  _hc_v=$(_hc_normalize "$_hc_v")
  eval "HC_${_hc_k}=\$_hc_v"
done

# --- Step 5: preset 一時変数を unset (caller を汚染しない) ---
for _hc_k in $_HC_PRESET_KEYS; do
  unset "_HC_PRESET_${_hc_k}"
done
unset _HC_PRESET_KEYS _HC_KNOWN_KEYS
unset _hc_k _hc_v

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
export HC_REQUIRED_ENV
export HC_IMPROVEMENT_PROPOSAL_ENABLED HC_IMPROVEMENT_PROPOSAL_LOOKBACK_DAYS
export HC_IMPROVEMENT_PROPOSAL_MAX_COUNT HC_IMPROVEMENT_PROPOSAL_STATE_DIR
export HC_IMPROVEMENT_PROPOSAL_DEDUP_HOURS
export HC_CONTEXT_BUDGET_ENABLED HC_CONTEXT_BUDGET_LIMIT
export HC_CONTEXT_BUDGET_THRESHOLD HC_CONTEXT_BUDGET_STATE_DIR
export HC_LIST_PLAN_FIRST_REMINDER_ENABLED
export HC_PARALLEL_SUBAGENT_REMINDER_ENABLED HC_PARALLEL_SUBAGENT_TTL_SEC
export HC_PARALLEL_SUBAGENT_STATE_DIR
export HC_AGENT_TYPE_KEYWORD_MAPPING
export HC_REVIEWER_REGISTRY_DESIGN HC_REVIEWER_REGISTRY_SECURITY
export HC_REVIEWER_REGISTRY_TEST HC_REVIEWER_REGISTRY_IMPL
export HC_WORKFLOW_STAGES_NEW HC_WORKFLOW_STAGES_MODIFY
export HC_DOCS_APPROVED_DIR

# --- 内部変数を unset (caller を汚染しない) ---
unset _hc_root _hc_top _hc_line _hc_stripped _hc_key _hc_key_upper
unset _hc_val _hc_inner _hc_inner_trim _hc_list _hc_items _hc_item _hc_norm _hc_p
