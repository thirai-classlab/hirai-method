#!/usr/bin/env bash
# .claude/scripts/hc-config.sh — task-46 Phase 3 hc-config 対話的 yml editor
#
# 目的:
#   harness-config.yml の全 key を対話 menu / CLI args で安全に編集する。
#   user は yml を直接編集せず、本 script 経由で:
#     - 全 key 一覧表示 (--list)
#     - 値取得 (--get <key>、env override 優先)
#     - 値設定 (--set <key>=<value>、型 validation + atomic + backup)
#     - feature toggle 一括 on/off (--feature <name>=<true|false>)
#     - default 復元 (--reset <key> / --reset-all)
#     - 差分表示 (--diff)
#     - validation only (--validate)
#     - 対話 menu (引数なし起動)
#
# 設計:
#   - shebang `#!/usr/bin/env bash` + `set -uo pipefail` (file-top errexit 外し、
#     feedback_set_e_in_sourced_libs 規範遵守)
#   - 既存 `.claude/hooks/lib/config-loader.sh` を source して env 解決ロジックを再利用
#   - atomic 操作: .bak.<timestamp> backup → .tmp.<pid> write → python yaml validate → mv
#   - 値型 validation: bool / int / float / array / string / path / csv
#   - 対話 menu: stdin から `q` / `5` / `0` で即終了 (smoke Case 7 対応)
#
# 制約:
#   - yml は flat key: value のみ対応 (config-loader.sh と同じ制約)
#   - 値内コメント許容 (parse 時に strip)
#   - tilde 展開 (~/foo) は config-loader.sh の HC_<NAME> env で運用、yml 値は raw 保持
#
# 起源:
#   task-46 Step 2 (TDD GREEN)、設計 draft: docs/draft/config-yml-phase3-hc-config-script.md
#   smoke: .claude/tests/hc-config-script-smoke.sh (7 cases)

set -uo pipefail

# === 設定 / 解決 ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_CONFIG="${REPO_ROOT}/.claude/harness-config.yml"

# --config <path> 引数で test isolation 対応 (smoke Case 3-6)
CONFIG_PATH=""

# === ユーティリティ ===

# stderr 出力
_err() {
  printf 'hc-config: %s\n' "$*" >&2
}

# stdout 出力
_out() {
  printf '%s\n' "$*"
}

# yml から key の raw 値を取得 (コメント strip / quote strip / 配列 inline 保持)
# $1: yml path
# $2: key
# 戻り: stdout に値 (key 不在なら空 + return 1)
_yml_get_raw() {
  local yml="$1"
  local key="$2"
  local line val
  line=$(grep -E "^${key}:" "$yml" 2>/dev/null | head -n 1) || true
  if [ -z "$line" ]; then
    return 1
  fi
  val="${line#${key}:}"
  # 行末コメント (#...) を strip (ただし行頭 # は yml では別行扱いなのでここでは出現しない)
  val="${val%%#*}"
  # 前後空白 trim
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  # 外側 quote strip
  if [ "${#val}" -ge 2 ]; then
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
  fi
  printf '%s' "$val"
  return 0
}

# yml から全 top-level key を抽出 (出現順保持)
# $1: yml path
_yml_list_keys() {
  local yml="$1"
  grep -E "^[a-z_][a-zA-Z0-9_]*:" "$yml" 2>/dev/null | sed -E 's/:.*$//' || true
}

# key → uppercase env name 変換 (config-loader.sh 同期)
_key_to_env() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]_' '_' | sed 's/_$//'
}

# 型推論 (key 名 + 値から推測)
# $1: key, $2: value
# 戻り: bool / int / float / array / path / string
_infer_type() {
  local key="$1"
  local val="$2"
  # 1. 配列 [a, b, c]
  case "$val" in
    \[*\]) printf 'array'; return ;;
  esac
  # 2. bool (true / false)
  case "$val" in
    true|True|TRUE|false|False|FALSE) printf 'bool'; return ;;
  esac
  # 3. key 名から推論
  case "$key" in
    *_threshold|*_ratio) printf 'float'; return ;;
    *_max|*_count|*_days|*_hours|*_sec|*_limit|*_min_*|*_max_*) printf 'int'; return ;;
    *_enabled|*_required) printf 'bool'; return ;;
    *_path|*_dir|*_root|*_sound) printf 'path'; return ;;
    review_min_count_*|review_max_count_*|review_iteration_max) printf 'int'; return ;;
  esac
  # 4. 値から推論
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    printf 'int'; return
  fi
  if [[ "$val" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf 'float'; return
  fi
  printf 'string'
}

# 値型 validation
# $1: key, $2: type, $3: value
# 戻り: 0 = valid / 1 = invalid (stderr に error)
_validate_value() {
  local key="$1"
  local type="$2"
  local val="$3"
  case "$type" in
    bool)
      case "$val" in
        true|True|TRUE|false|False|FALSE) return 0 ;;
        *)
          _err "invalid value for ${key} (expected: bool, got: '${val}')"
          return 1
          ;;
      esac
      ;;
    int)
      if [[ "$val" =~ ^[0-9]+$ ]]; then
        return 0
      fi
      _err "invalid value for ${key} (expected: int, got: '${val}')"
      return 1
      ;;
    float)
      if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        # confidence_threshold / context_budget_threshold は 0.0-1.0
        case "$key" in
          confidence_threshold|context_budget_threshold|*_ratio)
            # awk で範囲チェック
            if awk -v v="$val" 'BEGIN { if (v < 0.0 || v > 1.0) exit 1; exit 0 }'; then
              return 0
            else
              _err "invalid value for ${key} (expected: float 0.0-1.0, got: '${val}')"
              return 1
            fi
            ;;
          *)
            return 0
            ;;
        esac
      fi
      _err "invalid value for ${key} (expected: float, got: '${val}')"
      return 1
      ;;
    array)
      # [a, b, c] 形式のみ受け入れ
      case "$val" in
        \[*\]) return 0 ;;
        *)
          _err "invalid value for ${key} (expected: array '[a, b, c]', got: '${val}')"
          return 1
          ;;
      esac
      ;;
    path|string)
      # 空文字は path/string では許容
      return 0
      ;;
    *)
      # 不明な型は許容 (fail-open)
      return 0
      ;;
  esac
}

# yml backup 作成
# $1: yml path
# 戻り: stdout に backup path
_make_backup() {
  local yml="$1"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local bak="${yml}.bak.${ts}"
  cp "$yml" "$bak"
  printf '%s' "$bak"
}

# atomic yml 上書き
# $1: yml path
# $2: new content (stdin 経由でも OK だが引数渡し)
# python3 で yaml.safe_load してから mv (構文 invalid なら rollback)
_atomic_write() {
  local yml="$1"
  local new_content="$2"
  local tmp="${yml}.tmp.$$"

  printf '%s' "$new_content" > "$tmp"

  # python3 + PyYAML で yaml syntax 検証 (両方不在なら fallback で簡易 check)
  if command -v python3 >/dev/null 2>&1 \
    && python3 -c "import yaml" 2>/dev/null; then
    if ! python3 -c "import yaml; yaml.safe_load(open('$tmp'))" 2>/dev/null; then
      _err "yaml syntax invalid after edit, rolling back"
      rm -f "$tmp"
      return 1
    fi
  else
    # Fallback: top-level key 数が原 yml と大幅に乖離していないか簡易 check
    local orig_count new_count
    orig_count=$(grep -cE "^[a-z_][a-zA-Z0-9_]*:" "$yml" 2>/dev/null || printf '0')
    new_count=$(grep -cE "^[a-z_][a-zA-Z0-9_]*:" "$tmp" 2>/dev/null || printf '0')
    if [ "$new_count" -lt "$orig_count" ]; then
      _err "yaml structure check: key count decreased (${orig_count} → ${new_count}), rolling back"
      rm -f "$tmp"
      return 1
    fi
  fi

  mv "$tmp" "$yml"
  return 0
}

# yml の特定 key を新値で書き換える
# $1: yml path
# $2: key
# $3: new value (raw、yml 構文として valid な形)
# 戻り: 0 = success / 1 = key 不在 or atomic fail
_yml_set() {
  local yml="$1"
  local key="$2"
  local new_val="$3"
  local content
  # 既存 key 行の有無確認
  if ! grep -qE "^${key}:" "$yml"; then
    _err "key not found: ${key}"
    return 1
  fi
  # backup
  _make_backup "$yml" >/dev/null

  # 行頭コメント以外で `^key:` 行を新値で置換 (1 行のみ)
  # awk で in-place は避けて、stdout で新 content を構築 → atomic write
  content=$(awk -v k="$key" -v v="$new_val" '
    BEGIN { replaced = 0 }
    {
      if (!replaced && $0 ~ "^"k":") {
        # コメント保持: 元行に # コメントがあれば末尾に保持
        comment = ""
        if (match($0, /#.*$/)) {
          comment = "  " substr($0, RSTART)
        }
        printf "%s: %s%s\n", k, v, comment
        replaced = 1
      } else {
        print $0
      }
    }
  ' "$yml")

  _atomic_write "$yml" "$content"
}

# config-loader.sh を source して default 値を取得
# 注意: caller の env を汚染しないよう subshell 内で実行
# bash の `VAR=val source file` syntax は builtin に対しては「source script 内で見えない」ため、
# subshell 内で export してから source する (検証済、test 結果あり)。
_get_default() {
  local key="$1"
  local env_name
  env_name=$(_key_to_env "$key")
  (
    # 一時的に HC_<env_name> を unset して config-loader.sh の default を取得
    unset "HC_${env_name}"
    # config-loader.sh は env > yml > defaults の順なので、別の tmp yml (空) を渡せば
    # defaults が露出する。
    local empty_yml="/tmp/hc-config-empty.$$"
    : > "$empty_yml"
    export HC_CONFIG_PATH="$empty_yml"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.claude/hooks/lib/config-loader.sh" 2>/dev/null
    rm -f "$empty_yml"
    eval "printf '%s' \"\${HC_${env_name}:-}\""
  )
}

# 現在値を取得 (env > yml の優先順)
# config-loader.sh の env > yml > defaults logic を独立実装 (config-loader 内の
# Step 2 defaults assign が `${HC_<KEY>+set}` guard と干渉する制約を回避するため)。
#
# 解決順:
#   1. caller env HC_<KEY> が set されているか (export 済) → その値
#   2. yml に key が存在 → yml の raw 値
#   3. config-loader.sh の defaults → empty yml で source して取得
_get_current() {
  local key="$1"
  local env_name
  env_name=$(_key_to_env "$key")
  # Step 1: caller env が set されていれば優先
  local env_val env_is_set
  eval "env_is_set=\${HC_${env_name}+set}"
  if [ "${env_is_set:-}" = "set" ]; then
    eval "env_val=\$HC_${env_name}"
    printf '%s' "$env_val"
    return 0
  fi
  # Step 2: yml に存在すれば raw 値
  local raw
  if raw=$(_yml_get_raw "$CONFIG_PATH" "$key"); then
    printf '%s' "$raw"
    return 0
  fi
  # Step 3: config-loader.sh の defaults
  _get_default "$key"
}

# === コマンド実装 ===

# --list: 全 key 一覧表示 (key | current | default | type)
cmd_list() {
  printf '%-50s %-30s %-30s %-10s\n' "KEY" "CURRENT" "DEFAULT" "TYPE"
  printf '%s\n' "$(printf '%.0s-' {1..130})"
  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH")
  local key cur def type raw
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    raw=$(_yml_get_raw "$CONFIG_PATH" "$key" || printf '')
    cur=$(_get_current "$key")
    def=$(_get_default "$key" 2>/dev/null || printf '')
    type=$(_infer_type "$key" "$raw")
    # 出力長制限 (display のみ、改行含む配列値を1行にする)
    local cur_disp def_disp
    cur_disp=$(printf '%s' "$cur" | tr '\n' ',' | sed 's/,$//' | cut -c1-28)
    def_disp=$(printf '%s' "$def" | tr '\n' ',' | sed 's/,$//' | cut -c1-28)
    printf '%-50s %-30s %-30s %-10s\n' "$key" "$cur_disp" "$def_disp" "$type"
  done <<< "$keys"
}

# --get <key>: 値取得
cmd_get() {
  local key="$1"
  if [ -z "$key" ]; then
    _err "--get requires <key>"
    return 1
  fi
  if ! _yml_get_raw "$CONFIG_PATH" "$key" >/dev/null; then
    _err "key not found: ${key}"
    return 1
  fi
  _get_current "$key"
  printf '\n'
}

# --set <key>=<value>: 値設定
cmd_set() {
  local arg="$1"
  if [[ ! "$arg" =~ ^[a-z_][a-zA-Z0-9_]*=.+$ ]]; then
    _err "--set requires <key>=<value>"
    return 1
  fi
  local key="${arg%%=*}"
  local val="${arg#*=}"
  if ! _yml_get_raw "$CONFIG_PATH" "$key" >/dev/null; then
    _err "key not found: ${key}"
    return 1
  fi
  local raw
  raw=$(_yml_get_raw "$CONFIG_PATH" "$key" || printf '')
  local type
  type=$(_infer_type "$key" "$raw")
  if ! _validate_value "$key" "$type" "$val"; then
    return 1
  fi
  _yml_set "$CONFIG_PATH" "$key" "$val"
}

# --feature <name>=<true|false>: feature toggle shorthand
cmd_feature() {
  local arg="$1"
  if [[ ! "$arg" =~ ^[a-z_][a-zA-Z0-9_]*=.+$ ]]; then
    _err "--feature requires <name>=<true|false>"
    return 1
  fi
  local name="${arg%%=*}"
  local val="${arg#*=}"
  local key="feature_${name}_enabled"
  cmd_set "${key}=${val}"
}

# --reset <key>: default 復元
cmd_reset() {
  local key="$1"
  if [ -z "$key" ]; then
    _err "--reset requires <key>"
    return 1
  fi
  local def
  def=$(_get_default "$key")
  if [ -z "$def" ]; then
    _err "no default value found for ${key}"
    return 1
  fi
  # array 値は yml inline 形式に再構成 (改行 → カンマ区切り [a, b, c])
  # ただし default が改行区切りなら array、それ以外は scalar
  # bash 3.2 + BSD grep では `grep -q $'\n'` が常に MATCH を返す (空 pattern 扱い)
  # 不具合があるため、bash native の case glob で newline 検出する。
  case "$def" in
    *$'\n'*)
      local items
      items=$(printf '%s' "$def" | tr '\n' ',' | sed 's/,$//')
      def="[${items}]"
      ;;
  esac
  cmd_set "${key}=${def}"
}

# --reset-all: 全 key を default に戻す
cmd_reset_all() {
  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH")
  local key
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    cmd_reset "$key" 2>/dev/null || true
  done <<< "$keys"
}

# --diff: 現在値と default の差分
cmd_diff() {
  printf '%-50s %-30s %-30s\n' "KEY" "CURRENT" "DEFAULT"
  printf '%s\n' "$(printf '%.0s-' {1..120})"
  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH")
  local key cur def
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    cur=$(_get_current "$key")
    def=$(_get_default "$key" 2>/dev/null || printf '')
    if [ "$cur" != "$def" ]; then
      local cur_disp def_disp
      cur_disp=$(printf '%s' "$cur" | tr '\n' ',' | cut -c1-28)
      def_disp=$(printf '%s' "$def" | tr '\n' ',' | cut -c1-28)
      printf '%-50s %-30s %-30s\n' "$key" "$cur_disp" "$def_disp"
    fi
  done <<< "$keys"
}

# --validate: 全 key の型 validation のみ
cmd_validate() {
  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH")
  local key raw type errors=0
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    raw=$(_yml_get_raw "$CONFIG_PATH" "$key" || printf '')
    type=$(_infer_type "$key" "$raw")
    if ! _validate_value "$key" "$type" "$raw" 2>/dev/null; then
      _err "invalid: ${key} (type=${type}, value='${raw}')"
      errors=$((errors + 1))
    fi
  done <<< "$keys"
  if [ "$errors" -gt 0 ]; then
    _err "validation failed: ${errors} errors"
    return 1
  fi
  _out "validation OK: all keys valid"
  return 0
}

# --help
cmd_help() {
  cat <<'EOF'
hc-config — harness-config.yml interactive editor

USAGE:
  hc-config.sh                          引数なし: 対話 menu 起動
  hc-config.sh --list                   全 key 一覧表示
  hc-config.sh --get <key>              key の現在値取得 (env override 優先)
  hc-config.sh --set <key>=<value>      値設定 (型 validation + backup + atomic)
  hc-config.sh --feature <name>=<bool>  feature toggle 短縮 (feature_<name>_enabled の alias)
  hc-config.sh --reset <key>            key を default 値に戻す
  hc-config.sh --reset-all              全 key を default に戻す
  hc-config.sh --diff                   現在値と default の差分一覧
  hc-config.sh --validate               全 key の型 validation のみ実行
  hc-config.sh --config <path>          編集対象 yml path を override (test isolation 用)
  hc-config.sh --help                   本 help 表示

EXAMPLES:
  hc-config.sh --get feature_loop_mode_enforcement_enabled
  hc-config.sh --set review_iteration_max=3
  hc-config.sh --feature draft_flow_guard=false
  hc-config.sh --reset review_iteration_max

DESIGN:
  - atomic 操作: .bak.<ts> backup + .tmp.<pid> write + python yaml validate + mv
  - 値型 validation: bool / int / float / array / string / path
  - 環境変数 HC_<KEY> で yml 値を override 可能 (config-loader.sh 経由)

REFERENCE:
  - smoke test:  .claude/tests/hc-config-script-smoke.sh
  - config-loader: .claude/hooks/lib/config-loader.sh
  - 設計 draft:  docs/draft/config-yml-phase3-hc-config-script.md
EOF
}

# === 対話 menu ===
cmd_interactive() {
  while true; do
    cat <<'EOF'

=== hc-config interactive menu ===

  1) 全 key 一覧表示
  2) key 選択して編集
  3) feature toggle 一括 on/off
  4) reviewer 設定 quick edit (review_*)
  5) 終了

EOF
    printf 'choice [1-5/q]: '
    local choice
    if ! IFS= read -r choice; then
      # stdin EOF (e.g. pipe closed)
      printf '\nbye.\n'
      return 0
    fi
    case "$choice" in
      1)
        cmd_list
        ;;
      2)
        printf 'key name: '
        local k
        IFS= read -r k || return 0
        if [ -n "$k" ]; then
          printf 'current: '
          cmd_get "$k" 2>/dev/null || true
          printf 'new value (empty to skip): '
          local v
          IFS= read -r v || return 0
          if [ -n "$v" ]; then
            cmd_set "${k}=${v}"
          fi
        fi
        ;;
      3)
        printf 'feature name (without "feature_" prefix and "_enabled" suffix): '
        local fn
        IFS= read -r fn || return 0
        if [ -n "$fn" ]; then
          printf 'enable? [true/false]: '
          local fv
          IFS= read -r fv || return 0
          if [ -n "$fv" ]; then
            cmd_feature "${fn}=${fv}"
          fi
        fi
        ;;
      4)
        # reviewer 設定 quick edit: review_* keys を一覧表示
        local keys
        keys=$(_yml_list_keys "$CONFIG_PATH" | grep '^review_' || true)
        if [ -z "$keys" ]; then
          _out "no review_* keys found"
        else
          local k
          while IFS= read -r k; do
            [ -z "$k" ] && continue
            local cur
            cur=$(_get_current "$k")
            printf '%-40s = %s\n' "$k" "$cur"
          done <<< "$keys"
          printf '\nkey to edit (empty to skip): '
          local edk
          IFS= read -r edk || return 0
          if [ -n "$edk" ]; then
            printf 'new value: '
            local edv
            IFS= read -r edv || return 0
            if [ -n "$edv" ]; then
              cmd_set "${edk}=${edv}"
            fi
          fi
        fi
        ;;
      5|q|Q|0|quit|exit)
        _out "bye. (smoke test: bash .claude/tests/hc-config-script-smoke.sh)"
        return 0
        ;;
      *)
        _err "unknown choice: ${choice}"
        ;;
    esac
  done
}

# === arg parser ===

main() {
  # --config <path> を最初に処理 (他 cmd の前提)
  local args=("$@")
  local new_args=()
  local i=0
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
      --config)
        i=$((i + 1))
        CONFIG_PATH="${args[$i]}"
        ;;
      --config=*)
        CONFIG_PATH="${args[$i]#--config=}"
        ;;
      *)
        new_args+=("${args[$i]}")
        ;;
    esac
    i=$((i + 1))
  done
  # default config path
  if [ -z "$CONFIG_PATH" ]; then
    CONFIG_PATH="$DEFAULT_CONFIG"
  fi
  if [ ! -f "$CONFIG_PATH" ]; then
    _err "config not found: ${CONFIG_PATH}"
    return 1
  fi

  # 引数なし → 対話 menu
  if [ "${#new_args[@]}" -eq 0 ]; then
    cmd_interactive
    return $?
  fi

  # CLI args dispatch
  local cmd="${new_args[0]}"
  case "$cmd" in
    --list)
      cmd_list
      ;;
    --get)
      if [ "${#new_args[@]}" -lt 2 ]; then
        _err "--get requires <key>"
        return 1
      fi
      cmd_get "${new_args[1]}"
      ;;
    --set)
      if [ "${#new_args[@]}" -lt 2 ]; then
        _err "--set requires <key>=<value>"
        return 1
      fi
      cmd_set "${new_args[1]}"
      ;;
    --feature)
      if [ "${#new_args[@]}" -lt 2 ]; then
        _err "--feature requires <name>=<true|false>"
        return 1
      fi
      cmd_feature "${new_args[1]}"
      ;;
    --reset)
      if [ "${#new_args[@]}" -lt 2 ]; then
        _err "--reset requires <key>"
        return 1
      fi
      cmd_reset "${new_args[1]}"
      ;;
    --reset-all)
      cmd_reset_all
      ;;
    --diff)
      cmd_diff
      ;;
    --validate)
      cmd_validate
      ;;
    --help|-h)
      cmd_help
      ;;
    *)
      _err "unknown command: ${cmd}"
      _err "run 'hc-config.sh --help' for usage"
      return 1
      ;;
  esac
}

main "$@"
