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
#
# task-44 (2026-05-27): feature toggle 21 + review 13 = 新 34 key 追加。
# 各 key は yml 未設定でも本 file 内 defaults で fallback 動作可能 (backward compat)。
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
DOCS_APPROVED_DIR \
RULE_CHANGE_GUARD_ENABLED \
LOOP_CONFIRMATION_DETECTION_ENABLED \
LOOP_CONFIRMATION_PATTERNS \
FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED \
FEATURE_DRAFT_FLOW_GUARD_ENABLED \
FEATURE_TASK_RULE_GUARD_ENABLED \
FEATURE_DELEGATION_GUARD_ENABLED \
FEATURE_WORKFLOW_ENFORCEMENT_ENABLED \
FEATURE_CONFIDENCE_GATE_ENABLED \
FEATURE_GATEGUARD_ENABLED \
FEATURE_CONTEXT_BUDGET_ENABLED \
FEATURE_PARALLEL_SUBAGENT_REMINDER_ENABLED \
FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED \
FEATURE_BYPRODUCT_DISCHARGE_ENABLED \
FEATURE_WHY_X5_ENFORCEMENT_ENABLED \
FEATURE_SESSION_HELP_SURFACE_ENABLED \
FEATURE_IMPROVEMENT_PROPOSAL_ENABLED \
FEATURE_MODE_SESSION_START_ENABLED \
FEATURE_CHECK_SERENA_MCP_ENABLED \
FEATURE_CHECK_REQUIRED_ENV_ENABLED \
FEATURE_INIT_TASKS_ON_START_ENABLED \
FEATURE_NOTIFY_ENABLED \
FEATURE_CHECK_MD_MERMAID_ENABLED \
FEATURE_FAILURE_LOOP_DETECT_ENABLED \
FEATURE_HC_CONFIG_TUI_LEGACY_ENABLED \
REVIEW_REQUIRED_DESIGN \
REVIEW_MIN_COUNT_DESIGN \
REVIEW_MAX_COUNT_DESIGN \
REVIEW_REQUIRED_TEST \
REVIEW_MIN_COUNT_TEST \
REVIEW_MAX_COUNT_TEST \
REVIEW_REQUIRED_MODULE \
REVIEW_MIN_COUNT_MODULE \
REVIEW_MAX_COUNT_MODULE \
REVIEW_REQUIRED_SYSTEM \
REVIEW_MIN_COUNT_SYSTEM \
REVIEW_MAX_COUNT_SYSTEM \
REVIEW_REQUIRED_SECURITY \
REVIEW_MIN_COUNT_SECURITY \
REVIEW_ITERATION_MAX"

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

# --- Step 1b: 真の env preset key 名 set をスナップショット (task-55) ---
# 目的: 「env で genuine に設定された HC_* key」を Step 2 defaults / YAML load 値と
#       区別するため、source 時点で env に存在する全 HC_* key 名を space-delimited で保持する。
#
# 背景 (task-55 で判明した既存 bug):
#   旧 parse loop は env > YAML guard を `${HC_<KEY>+set}` の live check で行っていたが、
#   Step 2 defaults が全 known key を set 済にするため、known key の YAML 値が
#   defaults に上書き skip され「YAML を書いても効かない」状態だった
#   (docs_approved_dir / task_dir 等の project override が SSoT yml で効かなかった真因)。
#
# 修正方針:
#   parse guard は live value ではなく本 Step 1b で取った「genuine env preset set」
#   への所属判定で行う。これにより:
#     - Step 2 defaults は YAML / local.yml に上書きされる (期待動作)
#     - genuine env preset (known / 任意 key 問わず) は YAML / local.yml に勝つ
#   _HC_KNOWN_KEYS に無い任意 key (例: HC_FEATURE_FOO_ENABLED) も拾うため、
#   `env` / compgen ではなく POSIX 互換の `set` 出力 grep で HC_ 接頭辞 key を抽出する。
#
# 値解決の優先順 (高 → 低): env(HC_*) > local.yml > SSoT yml > hardcoded default
_HC_ENV_PRESET_SET=" "
while IFS='=' read -r _hc_envk _hc_envrest; do
  case "$_hc_envk" in
    HC_*)
      # `HC_` 接頭辞を除去し upper key 名のみ保持 (space で囲んで部分一致誤検出を防ぐ)
      _hc_envk="${_hc_envk#HC_}"
      case " $_HC_ENV_PRESET_SET " in
        *" $_hc_envk "*) ;;  # 既出なら skip
        *) _HC_ENV_PRESET_SET="${_HC_ENV_PRESET_SET}${_hc_envk} " ;;
      esac
      ;;
  esac
done <<EOF
$(set | grep '^HC_[A-Za-z0-9_]*=' 2>/dev/null || true)
EOF
unset _hc_envk _hc_envrest

# _hc_is_env_preset <UPPER_KEY> — genuine env preset への所属判定 (return 0 = preset)
_hc_is_env_preset() {
  case "$_HC_ENV_PRESET_SET" in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

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
# RULE_CHANGE_GUARD_ENABLED (task-40): draft-flow-guard.sh の .claude/rules/*.md 等への
# 規範変更 BLOCK 機構を on/off するスイッチ。default true (機械強制 BLOCK 有効)。
# false で task-40 拡張のみ完全停止 (docs/ 直下 block は維持)。
HC_RULE_CHANGE_GUARD_ENABLED="true"
# LOOP_CONFIRMATION_DETECTION_ENABLED (task-41): Stop hook loop-confirmation-detector.sh の
# Loop モード確認質問検出機構を on/off するスイッチ。default true。
# false で hook を完全停止 (Normal モードと等価動作)。
HC_LOOP_CONFIRMATION_DETECTION_ENABLED="true"
# LOOP_CONFIRMATION_PATTERNS (task-41): 確認質問検出 regex リスト (改行区切り)。
# 空文字なら hook 内 default 使用 (推奨)。env override 経由でのみ上書き可。
HC_LOOP_CONFIRMATION_PATTERNS=""

# --- Feature toggles (task-44 Phase 1、2026-05-27 追加) ---
# 機能単位 on/off スイッチ (21 件)。default true (全 feature 有効)。
# 各 feature は関連 hook 群を統括する上位 layer。
# 採用先 yml に key 不在でも本 defaults で fallback 動作 (backward compat)。
# env override: HC_FEATURE_<NAME>_ENABLED=false で個別 OFF 可能。
HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED="true"
HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED="true"
HC_FEATURE_TASK_RULE_GUARD_ENABLED="true"
HC_FEATURE_DELEGATION_GUARD_ENABLED="true"
HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED="true"
HC_FEATURE_CONFIDENCE_GATE_ENABLED="true"
HC_FEATURE_GATEGUARD_ENABLED="true"
HC_FEATURE_CONTEXT_BUDGET_ENABLED="true"
HC_FEATURE_PARALLEL_SUBAGENT_REMINDER_ENABLED="true"
HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED="true"
HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED="true"
HC_FEATURE_WHY_X5_ENFORCEMENT_ENABLED="true"
HC_FEATURE_SESSION_HELP_SURFACE_ENABLED="true"
HC_FEATURE_IMPROVEMENT_PROPOSAL_ENABLED="true"
HC_FEATURE_MODE_SESSION_START_ENABLED="true"
HC_FEATURE_CHECK_SERENA_MCP_ENABLED="true"
HC_FEATURE_CHECK_REQUIRED_ENV_ENABLED="true"
HC_FEATURE_INIT_TASKS_ON_START_ENABLED="true"
HC_FEATURE_NOTIFY_ENABLED="true"
HC_FEATURE_CHECK_MD_MERMAID_ENABLED="true"
HC_FEATURE_FAILURE_LOOP_DETECT_ENABLED="true"
# hc-config.sh interactive の TUI legacy fallback (task-61 Step 5 iter 4 D、
# config-loader.sh の対称性 + env override snapshot を確保。default false = Web UI 起動)
HC_FEATURE_HC_CONFIG_TUI_LEGACY_ENABLED="false"

# --- Reviewer 制御 (task-44 Phase 1、2026-05-27 追加) ---
# review_required_* (bool default true、security のみ false): false で当該 review command を skip
# review_min_count_* (int): reviewer 並列起動最低数 (採用 6 条 4 同期)
# review_max_count_* (int): reviewer 並列起動上限 (registry 件数で絞り込み)
# review_iteration_max: 反復上限 (default 5、超過時 user escalation)
HC_REVIEW_REQUIRED_DESIGN="true"
HC_REVIEW_MIN_COUNT_DESIGN="3"
HC_REVIEW_MAX_COUNT_DESIGN="7"
HC_REVIEW_REQUIRED_TEST="true"
HC_REVIEW_MIN_COUNT_TEST="5"
HC_REVIEW_MAX_COUNT_TEST="10"
HC_REVIEW_REQUIRED_MODULE="true"
HC_REVIEW_MIN_COUNT_MODULE="2"
HC_REVIEW_MAX_COUNT_MODULE="5"
HC_REVIEW_REQUIRED_SYSTEM="true"
HC_REVIEW_MIN_COUNT_SYSTEM="2"
HC_REVIEW_MAX_COUNT_SYSTEM="5"
HC_REVIEW_REQUIRED_SECURITY="false"
HC_REVIEW_MIN_COUNT_SECURITY="1"
HC_REVIEW_ITERATION_MAX="5"

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

# --- Step 3 helper: 1 つの YAML file を parse して HC_* に反映 ---
# _hc_parse_yaml_file <path>
#   file の各 key: value 行を HC_<UPPER>= に load する。
#   genuine env preset key (Step 1b の _HC_ENV_PRESET_SET 所属) は上書き skip
#   (env > file priority)。defaults / 先に load した別 file の値は上書きする
#   (これにより local.yml が SSoT yml に勝つ tier 関係を実現)。
#   存在しない file は no-op (graceful、SSoT 不在時のみ caller が WARN を出す)。
_hc_parse_yaml_file() {
  _hc_file="$1"
  [ -f "$_hc_file" ] || return 0
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
    # env > file priority guard (task-55 修正):
    # genuine env preset (Step 1b で snapshot した key) のみ上書き skip。
    # 旧実装は `${HC_<KEY>+set}` の live check だったが、Step 2 defaults が
    # 全 known key を set 済にするため YAML 値が defaults に負ける bug があった。
    # 本判定は env preset set への所属で行うため、defaults / 別 file の load 値は
    # 正しく上書きされる (local.yml > SSoT yml > defaults の tier が成立)。
    if _hc_is_env_preset "$_hc_key_upper"; then
      continue
    fi
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
  done < "$_hc_file"
}

# --- Step 3: SSoT YAML parse ---
# config 不在は warning のみ (fail-open)。
if [ ! -f "$HC_CONFIG_PATH" ]; then
  printf '[config-loader] WARN: %s not found, using defaults\n' "$HC_CONFIG_PATH" >&2
else
  _hc_parse_yaml_file "$HC_CONFIG_PATH"
fi

# --- Step 3.5: project 固有 override (harness-config.local.yml) parse (task-55) ---
# 役割:
#   project 固有の override 値を SSoT harness-config.yml とは別 file に置く。
#   この file は install.sh の rsync で除外される (settings.local.json と同じ扱い)
#   ため、`install.sh --update` で SSoT が上書きされても project override が温存される。
#
# 値解決の優先順 (高 → 低): env(HC_*) > local.yml > SSoT yml > hardcoded default
#   - local.yml は SSoT load 後に parse するため SSoT 値に勝つ
#   - genuine env preset には負ける (_hc_parse_yaml_file の env guard で skip)
#
# graceful degrade:
#   local.yml 不在環境は完全に現状通り (no-op)。`cp -r .claude` で即動く portability を維持。
#
# path 解決:
#   SSoT yml と同 dir の harness-config.local.yml を採用。
#   HC_LOCAL_CONFIG_PATH env で明示上書きも可 (test isolation 用)。
if [ -n "${HC_LOCAL_CONFIG_PATH:-}" ]; then
  _hc_local_config="$HC_LOCAL_CONFIG_PATH"
else
  _hc_config_dir=$(dirname "$HC_CONFIG_PATH")
  _hc_local_config="${_hc_config_dir}/harness-config.local.yml"
  unset _hc_config_dir
fi
# 不在なら no-op (graceful)。存在すれば SSoT 値を上書き parse。
_hc_parse_yaml_file "$_hc_local_config"
export HC_LOCAL_CONFIG_PATH="$_hc_local_config"
unset _hc_local_config
unset -f _hc_parse_yaml_file

# --- Step 4: env preset を復元 (env > local.yml > YAML > defaults) ---
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
unset _HC_ENV_PRESET_SET
unset -f _hc_is_env_preset
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
export HC_RULE_CHANGE_GUARD_ENABLED
export HC_LOOP_CONFIRMATION_DETECTION_ENABLED HC_LOOP_CONFIRMATION_PATTERNS

# Feature toggles (task-44 Phase 1)
export HC_FEATURE_LOOP_MODE_ENFORCEMENT_ENABLED HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED
export HC_FEATURE_TASK_RULE_GUARD_ENABLED HC_FEATURE_DELEGATION_GUARD_ENABLED
export HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED HC_FEATURE_CONFIDENCE_GATE_ENABLED
export HC_FEATURE_GATEGUARD_ENABLED HC_FEATURE_CONTEXT_BUDGET_ENABLED
export HC_FEATURE_PARALLEL_SUBAGENT_REMINDER_ENABLED HC_FEATURE_AUTONOMOUS_ACTION_GUARD_ENABLED
export HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED HC_FEATURE_WHY_X5_ENFORCEMENT_ENABLED
export HC_FEATURE_SESSION_HELP_SURFACE_ENABLED HC_FEATURE_IMPROVEMENT_PROPOSAL_ENABLED
export HC_FEATURE_MODE_SESSION_START_ENABLED HC_FEATURE_CHECK_SERENA_MCP_ENABLED
export HC_FEATURE_CHECK_REQUIRED_ENV_ENABLED HC_FEATURE_INIT_TASKS_ON_START_ENABLED
export HC_FEATURE_NOTIFY_ENABLED HC_FEATURE_CHECK_MD_MERMAID_ENABLED
export HC_FEATURE_FAILURE_LOOP_DETECT_ENABLED HC_FEATURE_HC_CONFIG_TUI_LEGACY_ENABLED

# Reviewer 制御 (task-44 Phase 1)
export HC_REVIEW_REQUIRED_DESIGN HC_REVIEW_MIN_COUNT_DESIGN HC_REVIEW_MAX_COUNT_DESIGN
export HC_REVIEW_REQUIRED_TEST HC_REVIEW_MIN_COUNT_TEST HC_REVIEW_MAX_COUNT_TEST
export HC_REVIEW_REQUIRED_MODULE HC_REVIEW_MIN_COUNT_MODULE HC_REVIEW_MAX_COUNT_MODULE
export HC_REVIEW_REQUIRED_SYSTEM HC_REVIEW_MIN_COUNT_SYSTEM HC_REVIEW_MAX_COUNT_SYSTEM
export HC_REVIEW_REQUIRED_SECURITY HC_REVIEW_MIN_COUNT_SECURITY
export HC_REVIEW_ITERATION_MAX

# --- 内部変数を unset (caller を汚染しない) ---
unset _hc_root _hc_top _hc_line _hc_stripped _hc_key _hc_key_upper
unset _hc_val _hc_inner _hc_inner_trim _hc_list _hc_items _hc_item _hc_norm _hc_p

# --- is_feature_enabled <feature_name> 共通関数 (task-44 Phase 1) ---
# 用途: hook 冒頭で `if ! is_feature_enabled <name>; then exit 0; fi` で feature OFF 即 skip
#
# 引数:
#   $1: feature 名 (lowercase、例: "loop_mode_enforcement" / "draft_flow_guard")
#       env / yml key は `HC_FEATURE_<UPPER>_ENABLED` / `feature_<lower>_enabled` を参照
#
# 戻り値:
#   0 = enabled (feature ON、hook 続行)
#   1 = disabled (feature OFF、hook skip)
#
# 値解決の優先順 (高 → 低):
#   1. 直接 export された env `HC_FEATURE_<UPPER>_ENABLED` (config-loader.sh Step 4 で復元済)
#   2. yml `feature_<lower>_enabled` の load 値 (Step 3 で eval 済)
#   3. 本 file 内 defaults "true" (Step 2 で設定済)
#
#   1〜3 はすべて同名 env として export 済なので、本関数は env を indirect read する。
#   bash 3.2 互換のため `${!var}` ではなく eval を使う。
#
# 値判定:
#   "false" / "False" / "FALSE" / "0" / "off" / "no" → disabled (return 1)
#   それ以外 (空文字含む) → enabled (return 0、backward compat for safety)
#
# 例:
#   if ! is_feature_enabled loop_mode_enforcement; then
#     exit 0  # feature OFF、hook を no-op skip
#   fi
is_feature_enabled() {
  local name="$1"
  if [ -z "$name" ]; then
    # 引数欠如は安全側 (enabled) で扱う、stderr WARN
    printf '[is_feature_enabled] WARN: feature name required\n' >&2
    return 0
  fi
  # lowercase → uppercase 化、非英数を _ に正規化 (config-loader 命名と同期)
  local upper
  upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_')
  upper="${upper%_}"
  # env indirect read (bash 3.2 互換: eval ベース)
  local value=""
  eval "value=\${HC_FEATURE_${upper}_ENABLED-}"
  # value lowercase 化して判定 (大小文字無視)
  local lc
  lc=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    false|0|off|no)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}
