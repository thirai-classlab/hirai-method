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
#   - atomic 操作: .bak.<ts>.<pid> backup → .tmp.<pid> write → python yaml validate (stdin) → mv
#   - 値型 validation: bool / int / float / array / string / path / csv
#   - 対話 menu: stdin から `q` / `5` / `0` で即終了 (smoke Case 7 対応)
#
# 制約:
#   - yml は flat key: value のみ対応 (config-loader.sh と同じ制約)
#   - 値内コメント許容 (parse 時に strip)
#   - tilde 展開 (~/foo) は config-loader.sh の HC_<NAME> env で運用、yml 値は raw 保持
#
# iter 2 fixes:
#   CRIT F-01: yaml.safe_load を stdin 経由 (path quoting 同時解決)
#   CRIT F-02: Case 8 で真の rollback path 検証 (smoke 側)
#   HIGH H-01 test-auto: backup を ts+pid suffix で衝突回避
#   HIGH H-02 test-auto: --get defaults fallback 実装
#   HIGH H-01 code-rev: awk -v 廃止 (ENVIRON 経由で escape corruption 回避)
#   HIGH H-02 code-rev: string/path に minimal sanity check (改行 / 制御文字 / # 行頭禁止)
#   HIGH F-04 tdd: --config の REPO_ROOT 配下 / /tmp/ guard + HC_ALLOW_EXTERNAL_CONFIG bypass
#   MED M-2 harness: _get_default の tmp cleanup を EXIT trap で保証
#   MED M-01 security: --get / --reset の key format validation (regex)
#   MED M-02 security: .bak retention policy (最新 N=10 件保持)
#   MED M-03 test-auto: process group kill (smoke 側)
#   MED M-04 test-auto: env priority case (smoke 側)
#   MED M-01 code-rev: shellcheck SC2222 dead case 除去 (review_iteration_max を *_max にマージ)
#   MED M-03 code-rev: _make_backup cp 失敗を伝播
#   MED M-05 code-rev: review_iteration_max int range check (1..10)
#
# iter 3 fixes:
#   CRIT R-01 (tdd-guide): _atomic_write の python3 detection を多版本 loop 化
#     macOS Homebrew で `python3 -c "import yaml"` が subprocess で exit 1 になり
#     yaml.safe_load path 到達不能 → fallback 強化と共に
#     python3.13 → 3.12 → 3.11 → python3 の順で PyYAML 利用可能 version を探索。
#   HIGH (test-automator 中間コロン): fallback で
#     mid-value colon / 不完全 [bracket / 不完全 {brace を reject。
#   HIGH (code-rev UTF-8 false-reject): `tr -d '\11\40-\176'` を廃止し
#     bash pattern match で C0 / DEL のみ reject (UTF-8 multibyte 受理)。
#   HIGH (pr-test mid-value # silent data loss): _yml_get_raw の `${val%%#*}` で
#     mid-value `#` が read-back 時 truncation。書込み時点で reject + HC_ALLOW_HASH_IN_VALUE
#     bypass。
#   MED M-NEW-01 (code-rev) + L-03 (security): HC_BAK_RETENTION_COUNT validation
#     (0 / 負値 / 非数値 で全 backup 削除 = rollback 不能を回避、default 10 に fallback)。
#
# iter 4 fixes (本 commit、HIGH 3 件単一根原因 closure):
#   HIGH H3-01 (test-auto) + H-NEW-01 (pr-test) + H-NEW-01 (tdd-guide) 共通指摘:
#     iter 3 で HC_ALLOW_HASH_IN_VALUE=1 bypass を導入したが、bypass で書き込み成功した値は
#     `_yml_get_raw` の `val="${val%%#*}"` で `#` 以降が unconditional truncate されるため
#     read-back で silent data loss。bypass 使用者の URL fragment / git refspec 用途で破綻。
#   解法 (採用案: write 時 quote):
#     1. `_yml_set` で bypass + value に `#` 含む場合、yml に double-quote 形式
#        (`key: "foo#bar"`) で保存。内部 `"` は `\"` に escape、内部 `\` は `\\` に escape。
#     2. `_yml_get_raw` で bypass + 前後 `"` 検出時、行末 comment strip を skip し
#        quote 解除 + `\"` unescape のみ実施。
#     3. bypass 時 stderr に notice を 1 行出力 (operator visibility 確保)。
#   smoke Case 19b 更新 + Case 19c (round-trip 検証) + Case 19d (yml file format 検証) 追加。
#
# iter 5 fixes (code-reviewer iter 4 検出 CRIT 1 + HIGH 2 closure、データ corruption 3 surface 解消):
#   CRIT C-01 (再書込時 awk comment-preservation 干渉):
#     `_yml_set` の awk dispatch で matched-line も `match($0, /#.*$/)` で comment 抽出 + 新値後置
#     する構造のため、quoted literal (`docs_approved_dir: "foo#bar"`) を再 `--set baz#qux` すると
#     `#bar"` を comment 誤検知 → 新値に `  #bar"` 再付加 → `docs_approved_dir: "baz#qux"  #bar"`
#     corrupt 状態。matched-line では comment preservation を skip し新値で完全置換する。
#   HIGH H-01 (`\\` unescape 欠落):
#     `_yml_set` で `\` → `\\` escape するが、`_yml_get_raw` の unescape は `\"` → `"` のみ。
#     bypass で `a\b#c` set → yml に `"a\\b#c"` → read で `a\\b#c` 返却 (literal 二重 backslash)。
#     `\\` → `\` unescape を `\"` → `"` unescape より先に実施 (順序: 先に `\\`、後に `\"`)。
#   HIGH H-02 (read 時 env asymmetry):
#     `_yml_get_raw` の quote 解除条件が `HC_ALLOW_HASH_IN_VALUE=1 ∧ val が "..." 形式` の両 AND
#     条件のため、yml に `"foo#bar"` 保存後 bypass env 外して `--get` すると quote 解除 path に
#     入らず `val="${val%%#*}"` で `"foo` 返却 (broken partial)。`--list` / `--diff` / `--validate` 等
#     が corrupt 値を表示。read 側の quote 解除条件から `HC_ALLOW_HASH_IN_VALUE=1` を削除し、
#     前後 `"..."` 形式検出だけで quote 解除 + comment-strip-skip を発動。bypass env は write 側のみ
#     (mid-`#` reject の bypass 用途) で gate する非対称設計に変更。
#   smoke Case 19e (再書込 round-trip) + Case 19f (backslash round-trip + non-bypass read) 追加。
#
# Step 6 refactoring (task-46 Step 6): 全関数 < 50 LOC に分割
#   対象 6 関数を helper 分割:
#   - _validate_string_sanity: _validate_str_newline_ctrl + _validate_str_leading_chars
#     + _validate_str_mid_hash に 3 分割
#   - _validate_value: _validate_bool + _validate_int + _validate_float に 3 分割
#   - _atomic_write: _atomic_find_python_yaml + _atomic_yaml_validate_fallback に 2 分割
#   - _yml_set: _yml_set_escape_value に 1 helper 抽出
#   - cmd_interactive: _menu_opt_edit_key + _menu_opt_feature + _menu_opt_reviewer に 3 分割
#   - main: _main_require_arg + _main_dispatch に 2 helper 抽出、inline config parse
#
# 起源:
#   task-46 Step 2 (TDD GREEN) → iter 2 fix → iter 3 fix → iter 4 fix → iter 5 fix
#   → Step 6 refactoring (behavior-preserving function split)
#   設計 draft: docs/draft/config-yml-phase3-hc-config-script.md
#   smoke: .claude/tests/hc-config-script-smoke.sh (21 cases iter 5)

set -uo pipefail

# === 設定 / 解決 ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_CONFIG="${REPO_ROOT}/.claude/harness-config.yml"

# task-48 Step 3: key metadata lib を source (description / effect / category)。
# 不在環境でも fallback で動くよう存在確認後に source、引き helper も guard する。
HC_METADATA_LIB="${SCRIPT_DIR}/lib/hc-config-metadata.sh"
if [ -f "$HC_METADATA_LIB" ]; then
  # shellcheck disable=SC1090
  source "$HC_METADATA_LIB"
fi

# metadata 引き helper (lib 不在でも壊れないよう command -v guard)
# $1: key → description (不在なら空)
_meta_desc() {
  if command -v hc_metadata_description >/dev/null 2>&1; then
    hc_metadata_description "$1" 2>/dev/null || true
  fi
}
# $1: key → effect (不在なら空)
_meta_effect() {
  if command -v hc_metadata_effect >/dev/null 2>&1; then
    hc_metadata_effect "$1" 2>/dev/null || true
  fi
}
# $1: key → category (不在なら空)
_meta_category() {
  if command -v hc_metadata_category >/dev/null 2>&1; then
    hc_metadata_category "$1" 2>/dev/null || true
  fi
}

# --config <path> 引数で test isolation 対応 (smoke Case 3-6)
CONFIG_PATH=""

# .bak retention (最新 N 件保持、それより古い bak は自動削除)
# iter 3 MED M-NEW-01 (code-rev) + L-03 (security):
#   HC_BAK_RETENTION_COUNT=0 / 負値 / 非数値 で全 backup 削除 (rollback 不能) を防止。
#   positive int (>= 1) のみ受理、それ以外は default 10 に fallback + stderr warn。
BAK_RETENTION_COUNT="${HC_BAK_RETENTION_COUNT:-10}"
if ! [[ "$BAK_RETENTION_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'hc-config: invalid HC_BAK_RETENTION_COUNT: %q (must be positive int >= 1), using default 10\n' \
    "$BAK_RETENTION_COUNT" >&2
  BAK_RETENTION_COUNT=10
fi

# === ユーティリティ ===

# stderr 出力
_err() {
  printf 'hc-config: %s\n' "$*" >&2
}

# stdout 出力
_out() {
  printf '%s\n' "$*"
}

# key 名の format validation (security M-01)
# 受理: ^[a-z_][a-zA-Z0-9_]*$
_validate_key_format() {
  local key="$1"
  if [[ ! "$key" =~ ^[a-z_][a-zA-Z0-9_]*$ ]]; then
    _err "invalid key format: '${key}' (must match ^[a-z_][a-zA-Z0-9_]*\$)"
    return 1
  fi
  return 0
}

# 改行 / NUL / C0 制御文字 / DEL を reject (string sanity helper 1/3)
# iter 3 HIGH (code-rev UTF-8 false-reject) fix:
#   bash pattern match で C0 (\x01-\x08, \x0b-\x1f) + DEL (\x7f) のみ reject、
#   \x80-\xFF (UTF-8 multibyte) は touch しない。
_validate_str_newline_ctrl() {
  local key="$1"
  local val="$2"
  # 改行 (LF / CR) → yml 構造破壊
  case "$val" in
    *$'\n'*|*$'\r'*)
      _err "invalid value for ${key}: contains newline/CR"
      return 1
      ;;
  esac
  # C0 制御文字 / DEL を reject
  # 注意: bash で `$'\x00'` は empty string になり `*$'\x00'*` = `**` で全 match 誤爆するため、
  #       NUL pattern は意図的に除外 (どのみち bash variable に NUL は格納不可)。
  case "$val" in
    *$'\x01'*|*$'\x02'*|*$'\x03'*|*$'\x04'*|*$'\x05'*|*$'\x06'*|*$'\x07'*|*$'\x08'* \
    |*$'\x0b'*|*$'\x0c'*|*$'\x0e'*|*$'\x0f'*|*$'\x10'*|*$'\x11'*|*$'\x12'*|*$'\x13'* \
    |*$'\x14'*|*$'\x15'*|*$'\x16'*|*$'\x17'*|*$'\x18'*|*$'\x19'*|*$'\x1a'*|*$'\x1b'* \
    |*$'\x1c'*|*$'\x1d'*|*$'\x1e'*|*$'\x1f'*|*$'\x7f'*)
      _err "invalid value for ${key}: contains control characters"
      return 1
      ;;
  esac
  return 0
}

# 行頭 # / 行頭 : を reject (string sanity helper 2/3)
_validate_str_leading_chars() {
  local key="$1"
  local val="$2"
  # 行頭 # (yaml comment と混同) — 値全体が # から始まる場合のみ reject
  case "$val" in
    \#*)
      _err "invalid value for ${key}: starts with '#' (yaml comment confusion)"
      return 1
      ;;
  esac
  # yaml-confusing leading `:` (例: ": unexpected" は yml syntax を破壊)
  case "$val" in
    :*)
      _err "invalid value for ${key}: starts with ':' (yaml syntax confusion)"
      return 1
      ;;
  esac
  return 0
}

# mid-value # を reject (string sanity helper 3/3)
# iter 3 HIGH (pr-test mid-value # silent data loss) fix:
#   mid-value `#` は _yml_get_raw の `val="${val%%#*}"` で read-back 時に truncation。
#   URL #fragment 等の正規ユースケース向けに HC_ALLOW_HASH_IN_VALUE=1 bypass。
_validate_str_mid_hash() {
  local key="$1"
  local val="$2"
  if [ "${HC_ALLOW_HASH_IN_VALUE:-0}" != "1" ]; then
    case "$val" in
      *\#*)
        _err "invalid value for ${key}: contains '#' (yaml inline comment confusion, would be silently truncated on read-back)"
        _err "  use HC_ALLOW_HASH_IN_VALUE=1 to bypass (URL fragment etc.)"
        return 1
        ;;
    esac
  fi
  return 0
}

# string / path 値の minimal sanity check (HIGH H-02 code-rev + iter 3 fixes)
# 改行 / NUL / 制御文字 / 行頭 # / 行頭 : / mid-value # を reject、UTF-8 multibyte は受理
_validate_string_sanity() {
  local key="$1"
  local val="$2"
  _validate_str_newline_ctrl "$key" "$val" || return 1
  _validate_str_leading_chars "$key" "$val" || return 1
  _validate_str_mid_hash "$key" "$val" || return 1
  return 0
}

# yml から key の raw 値を取得 (コメント strip / quote strip / 配列 inline 保持)
# $1: yml path
# $2: key
# 戻り: stdout に値 (key 不在なら空 + return 1)
#
# iter 4 fix (HIGH 3 件単一根原因 closure、HC_ALLOW_HASH_IN_VALUE=1 round-trip 整合性):
#   bypass 時に `_yml_set` が double-quote escape で value を保存するため、
#   read 側も double-quoted literal を検出して quote 解除 + comment strip skip する。
#   通常 value (quote なし) は従来通り `${val%%#*}` で行末コメント strip。
#
#   検出条件 (両 AND):
#     1. HC_ALLOW_HASH_IN_VALUE=1
#     2. 前後 trim 後の val が `"` で始まり `"` で終わる (length >= 2)
#   → comment strip skip + leading/trailing quote 除去 + `\"` → `"` unescape
_yml_get_raw() {
  local yml="$1"
  local key="$2"
  local line val
  line=$(grep -E "^${key}:" "$yml" 2>/dev/null | head -n 1) || true
  if [ -z "$line" ]; then
    return 1
  fi
  val="${line#"${key}":}"
  # 前後空白 trim (quote 判定の前に実行、comment strip より前)
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"

  # iter 5 fix (HIGH H-01 + H-02 closure):
  #   - HIGH H-02 解消: quote 解除条件から HC_ALLOW_HASH_IN_VALUE=1 を削除し、
  #     前後 `"..."` 形式検出だけで quote 解除 + comment-strip-skip を発動。
  #   - HIGH H-01 解消: `\\` → `\` unescape を `\"` → `"` unescape より先に実施。
  # (round-trip 整合性: `_yml_set` が `"foo#bar"` で書き込んだ値を `foo#bar` で復元)
  if [ "${#val}" -ge 2 ] \
    && [ "${val:0:1}" = '"' ] \
    && [ "${val: -1}" = '"' ]; then
    # leading/trailing double-quote を 1 文字ずつ除去
    val="${val#\"}"
    val="${val%\"}"
    # unescape 順序: `\\` → `\` を先 (二段解釈防止)、`\"` → `"` を後
    val="${val//\\\\/\\}"
    val="${val//\\\"/\"}"
    printf '%s' "$val"
    return 0
  fi

  # 通常 path: 行末コメント (#...) を strip
  # (HC_ALLOW_HASH_IN_VALUE=1 でも non-quoted な既存 value (mid-`#` なし) は本 path)
  val="${val%%#*}"
  # comment strip 後の trailing 空白を再 trim
  val="${val%"${val##*[![:space:]]}"}"
  # 外側 quote strip (legacy single-quote 含む)
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
  # 3. key 名から推論 (review_iteration_max を *_max にマージし SC2222 dead case 解消)
  case "$key" in
    *_threshold|*_ratio) printf 'float'; return ;;
    *_max|*_count|*_days|*_hours|*_sec|*_limit|*_min_*|*_max_*) printf 'int'; return ;;
    *_enabled|*_required) printf 'bool'; return ;;
    *_path|*_dir|*_root|*_sound) printf 'path'; return ;;
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

# bool 型 validation (_validate_value helper 1/3)
_validate_bool() {
  local key="$1"
  local val="$2"
  case "$val" in
    true|True|TRUE|false|False|FALSE) return 0 ;;
    *)
      _err "invalid value for ${key} (expected: bool, got: '${val}')"
      return 1
      ;;
  esac
}

# int 型 validation (_validate_value helper 2/3)
_validate_int() {
  local key="$1"
  local val="$2"
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    # review_iteration_max は 1..10 の range
    case "$key" in
      review_iteration_max)
        if [ "$val" -lt 1 ] || [ "$val" -gt 10 ]; then
          _err "invalid value for ${key} (expected: int 1-10, got: '${val}')"
          return 1
        fi
        ;;
    esac
    return 0
  fi
  _err "invalid value for ${key} (expected: int, got: '${val}')"
  return 1
}

# float 型 validation (_validate_value helper 3/3)
_validate_float() {
  local key="$1"
  local val="$2"
  if [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    # confidence_threshold / context_budget_threshold は 0.0-1.0
    case "$key" in
      confidence_threshold|context_budget_threshold|*_ratio)
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
      _validate_bool "$key" "$val"
      ;;
    int)
      _validate_int "$key" "$val"
      ;;
    float)
      _validate_float "$key" "$val"
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
      # 空文字は path/string では許容 (空 path は default 復元等)
      if [ -z "$val" ]; then
        return 0
      fi
      _validate_string_sanity "$key" "$val"
      ;;
    *)
      # 不明な型でも sanity check は通す
      _validate_string_sanity "$key" "$val"
      ;;
  esac
}

# bak retention policy: 古い bak (最新 N 件超過) を削除 (security M-02)
# $1: yml path
_prune_old_backups() {
  local yml="$1"
  local base
  base=$(basename "$yml")
  local dir
  dir=$(dirname "$yml")
  # ls -t で新しい順、 N+1 件目以降を削除
  # shellcheck disable=SC2012
  ls -t "${dir}/${base}.bak."* 2>/dev/null \
    | awk -v n="$BAK_RETENTION_COUNT" 'NR > n' \
    | while IFS= read -r old; do
        rm -f "$old"
      done
}

# yml backup 作成 (HIGH H-01 test-auto: ts + pid suffix で衝突回避)
# $1: yml path
# 戻り: stdout に backup path, 失敗時 exit code != 0
_make_backup() {
  local yml="$1"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local bak="${yml}.bak.${ts}.$$"
  # 同一 PID 内で立て続けに backup する場合の衝突回避 (sub-second collision):
  # 既存なら nanosecond / counter suffix を試す
  if [ -e "$bak" ]; then
    local n=1
    while [ -e "${bak}.${n}" ] && [ "$n" -lt 1000 ]; do
      n=$((n + 1))
    done
    bak="${bak}.${n}"
  fi
  if ! cp "$yml" "$bak"; then
    _err "backup failed: cp '${yml}' '${bak}'"
    return 1
  fi
  # 古い backup を retention policy で prune (失敗は silent、本処理を block しない)
  _prune_old_backups "$yml" 2>/dev/null || true
  printf '%s' "$bak"
}

# PyYAML 利用可能な python3 実行可能ファイルを検出して stdout に出力
# 見つからない場合は空文字 + return 1
# _atomic_write helper 1/2
_atomic_find_python_yaml() {
  local py
  for py in python3.13 python3.12 python3.11 python3; do
    if command -v "$py" >/dev/null 2>&1 \
      && "$py" -c "import yaml" >/dev/null 2>&1; then
      printf '%s' "$py"
      return 0
    fi
  done
  return 1
}

# PyYAML 不在環境向け軽量 yaml 構造チェック (fallback)
# $1: orig yml path, $2: tmp yml path
# 戻り: 0 = OK / 1 = 構造異常 (tmp を呼び出し元で rm すること)
# _atomic_write helper 2/2
_atomic_yaml_validate_fallback() {
  local yml="$1"
  local tmp="$2"
  local orig_count new_count
  orig_count=$(grep -cE "^[a-z_][a-zA-Z0-9_]*:" "$yml" 2>/dev/null || printf '0')
  new_count=$(grep -cE "^[a-z_][a-zA-Z0-9_]*:" "$tmp" 2>/dev/null || printf '0')
  if [ "$new_count" -lt "$orig_count" ]; then
    _err "yaml structure check: key count decreased (${orig_count} → ${new_count}), rolling back"
    return 1
  fi
  # 行頭 `:` のみで始まる行 (= 値が ': xxx' で yml が壊れている兆候) を reject
  if grep -qE "^[a-z_][a-zA-Z0-9_]*: : " "$tmp" 2>/dev/null; then
    _err "yaml structure check: detected ': :' pattern (corrupted value), rolling back"
    return 1
  fi
  # iter 3 HIGH: mid-value `: <text>` を reject
  if grep -qE '^[a-z_][a-zA-Z0-9_]*:[[:space:]]+[^"'"'"'#[{[:space:]][^"'"'"'#]*:[[:space:]]' "$tmp" 2>/dev/null; then
    _err "yaml structure check: mid-value colon detected (structural corruption), rolling back"
    return 1
  fi
  # iter 3 HIGH: unclosed array bracket → reject
  if grep -qE '^[a-z_][a-zA-Z0-9_]*:[[:space:]]*\[[^]]*$' "$tmp" 2>/dev/null; then
    _err "yaml structure check: unclosed array bracket detected, rolling back"
    return 1
  fi
  # iter 3 HIGH: unclosed object brace → reject
  if grep -qE '^[a-z_][a-zA-Z0-9_]*:[[:space:]]*\{[^}]*$' "$tmp" 2>/dev/null; then
    _err "yaml structure check: unclosed object brace detected, rolling back"
    return 1
  fi
  return 0
}

# atomic yml 上書き
# $1: yml path
# $2: new content
#
# iter 2 fix: CRIT F-01 = yaml.safe_load を stdin 経由 (path quoting + alias 不在 python 対応)
#
# iter 3 fixes:
#   CRIT R-01 (tdd-guide): python3 detection を多版本 loop 化
#   HIGH (test-automator 中間コロン): fallback 強化
_atomic_write() {
  local yml="$1"
  local new_content="$2"
  local tmp="${yml}.tmp.$$"

  printf '%s' "$new_content" > "$tmp"

  local py_with_yaml
  if py_with_yaml=$(_atomic_find_python_yaml); then
    # CRIT F-01 fix: stdin 経由で path quoting 不要、alias 不在 python でも安全
    if ! "$py_with_yaml" -c "import yaml, sys; yaml.safe_load(sys.stdin.read())" < "$tmp" 2>/dev/null; then
      _err "yaml syntax invalid after edit, rolling back"
      rm -f "$tmp"
      return 1
    fi
  else
    # Fallback: 軽量 yaml syntax check (PyYAML 不在環境用)
    if ! _atomic_yaml_validate_fallback "$yml" "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
  fi

  mv "$tmp" "$yml"
  return 0
}

# HC_ALLOW_HASH_IN_VALUE=1 + value に `#` 含む場合の double-quote escape
# $1: new_val (raw)
# stdout: yml 書き込み用 write_val (escaped 済)
# 副作用: bypass 時 stderr に notice 出力
# _yml_set helper
_yml_set_escape_value() {
  local new_val="$1"
  if [ "${HC_ALLOW_HASH_IN_VALUE:-0}" = "1" ]; then
    case "$new_val" in
      *\#*)
        # 内部 `"` は `\"` に escape、内部 `\` も `\\` に escape して二重 escape 衝突を回避
        local escaped="${new_val//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        printf '%s' "\"${escaped}\""
        _err "note: HC_ALLOW_HASH_IN_VALUE=1 で # 含む値を yml に double-quote 保存します (round-trip 整合性確保のため)"
        return 0
        ;;
    esac
  fi
  printf '%s' "$new_val"
  return 0
}

# yml の特定 key を新値で書き換える
# $1: yml path
# $2: key
# $3: new value (raw、yml 構文として valid な形)
# 戻り: 0 = success / 1 = key 不在 or atomic fail
#
# iter 4 fix (HC_ALLOW_HASH_IN_VALUE=1 round-trip 整合性):
#   bypass 時 + value に `#` を含む場合は _yml_set_escape_value で double-quote escape して保存。
# iter 5 fix (CRIT C-01 closure):
#   matched-line では comment preservation を skip し新値で完全置換する。
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
  # backup (cp 失敗時は伝播、code-rev M-03)
  if ! _make_backup "$yml" >/dev/null; then
    return 1
  fi

  local write_val
  write_val=$(_yml_set_escape_value "$new_val")

  # 行頭コメント以外で `^key:` 行を新値で置換 (1 行のみ)
  # HIGH H-01 code-rev fix: awk -v は backslash sequence を解釈するため ENVIRON 経由で渡す。
  # iter 5 fix (CRIT C-01): matched-line は新値で完全置換 (元行の comment 保持 skip)。
  content=$(KEY="$key" VAL="$write_val" awk '
    BEGIN {
      k = ENVIRON["KEY"]
      v = ENVIRON["VAL"]
      replaced = 0
    }
    {
      if (!replaced && index($0, k ":") == 1) {
        printf "%s: %s\n", k, v
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
# MED M-2 fix: tmp cleanup を EXIT trap で保証
_get_default() {
  local key="$1"
  local env_name
  env_name=$(_key_to_env "$key")
  (
    # 一時的に HC_<env_name> を unset して config-loader.sh の default を取得
    unset "HC_${env_name}"
    # config-loader.sh は env > yml > defaults の順なので、別の tmp yml (空) を渡せば
    # defaults が露出する。
    local empty_yml
    empty_yml=$(mktemp "/tmp/hc-config-empty.XXXXXX") || return 1
    # EXIT trap で確実 cleanup (subshell 内のみ有効)
    trap 'rm -f "$empty_yml"' EXIT
    export HC_CONFIG_PATH="$empty_yml"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.claude/hooks/lib/config-loader.sh" 2>/dev/null
    eval "printf '%s' \"\${HC_${env_name}:-}\""
  )
}

# 現在値を取得 (env > yml > defaults の優先順)
#
# 解決順:
#   1. caller env HC_<KEY> が set されているか (export 済) → その値
#   2. yml に key が存在 → yml の raw 値
#   3. config-loader.sh の defaults → empty yml で source して取得 (HIGH H-02 test-auto fix)
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

# --config <path> の path validation (HIGH F-04 fix: path traversal guard)
# REPO_ROOT 配下 or /tmp/ 配下 or HC_ALLOW_EXTERNAL_CONFIG=1 のみ受理
_validate_config_path() {
  local path="$1"
  # bypass env (test isolation 用)
  if [ "${HC_ALLOW_EXTERNAL_CONFIG:-}" = "1" ]; then
    return 0
  fi
  # path canonicalize
  local canon
  canon=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")
  if [ -z "$canon" ] || [ "$canon" = "/" ]; then
    canon="$path"
  fi
  # REPO_ROOT 配下 or /tmp/ 配下
  case "$canon" in
    "${REPO_ROOT}"/*|/tmp/*|/private/tmp/*|/var/folders/*)
      return 0
      ;;
    *)
      _err "config path outside REPO_ROOT / /tmp/: ${canon}"
      _err "use HC_ALLOW_EXTERNAL_CONFIG=1 to bypass (test isolation only)"
      return 1
      ;;
  esac
}

# === コマンド実装 ===

# --list ヘッダー行を印字 (mode に応じてカラム数を変える)
# $1: show_default (0/1), $2: show_effect (0/1)
# cmd_list helper
_cmd_list_header() {
  local show_default="$1"
  local show_effect="$2"
  # ui-designer M3: default mode は説明列を cut で truncate して行幅暴走を抑える
  #   (最長 key=42 文字のため KEY 列 44、説明列を 30 文字に丸めて狭端末でも読める程度に)。
  #   --verbose / --show-default は情報密度優先で広端末向けと割り切る (header に注記)。
  if [ "$show_effect" -eq 1 ]; then
    printf '%-48s %-18s %-18s %-7s %-44s %s\n' "KEY" "CURRENT" "DEFAULT" "TYPE" "説明" "変更効果"
    printf '%s\n' "(--verbose は広端末向け: 全 6 列を truncate して表示。狭端末では --list 単体を推奨)"
  elif [ "$show_default" -eq 1 ]; then
    printf '%-48s %-22s %-22s %-7s %s\n' "KEY" "CURRENT" "DEFAULT" "TYPE" "説明"
    printf '%s\n' "(--show-default は広端末向け: DEFAULT 列を追加。狭端末では --list 単体を推奨)"
  else
    printf '%-44s %-22s %-7s %s\n' "KEY" "CURRENT" "TYPE" "説明"
  fi
  printf '%s\n' "$(printf '%.0s-' {1..106})"
}

# --list: 全 key 一覧表示
#
# task-48 Step 3: key metadata (説明 / 変更効果) を列に追加 + category 別グルーピング。
#   default      : KEY / CURRENT / TYPE / 説明 (DEFAULT 列を説明に置換)
#   --show-default: KEY / CURRENT / DEFAULT / TYPE / 説明 (DEFAULT 列復活)
#   --verbose    : KEY / CURRENT / DEFAULT / TYPE / 説明 / 変更効果 (6 列)
#
# 引数: $1 に "verbose" / "show-default" を渡すと該当 mode。空なら default mode。
cmd_list() {
  local mode="${1:-}"
  local show_default=0 show_effect=0
  case "$mode" in
    verbose)      show_default=1; show_effect=1 ;;
    show-default) show_default=1 ;;
  esac

  _cmd_list_header "$show_default" "$show_effect"

  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH")

  # category 別にグルーピングして出力 (metadata 不在時は単一グループ扱い)
  # iter2 CRIT 同種 leak 予防: for/while 本体内の `local cat_keys` / `local key` / `local cat_count`
  #   宣言を関数頭に集約し、ループ内は素の代入にして bash 3.2 cmdsubst stdout 漏洩を構造的に防ぐ。
  local categories="保護パス ファイル配置 state_dir Gate/Confidence feature_toggle reviewer_control"
  local printed_any=0
  local cat cat_keys key cat_count
  for cat in $categories; do
    cat_keys=""
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      if [ "$(_meta_category "$key")" = "$cat" ]; then
        cat_keys="${cat_keys}${key}"$'\n'
      fi
    done <<< "$keys"
    [ -z "$cat_keys" ] && continue
    cat_count=$(printf '%s' "$cat_keys" | grep -c '.')
    printf '\n=== %s (%s keys) ===\n' "$cat" "$cat_count"
    printf '%s' "$cat_keys" | _cmd_list_rows "$show_default" "$show_effect"
    printed_any=1
  done

  # metadata 不在 / 未分類 key があれば従来通り全 key を 1 グループで出力
  if [ "$printed_any" -eq 0 ]; then
    printf '%s\n' "$keys" | _cmd_list_rows "$show_default" "$show_effect"
  fi
}

# cmd_list の行出力 helper (stdin に key 改行区切り)
# $1: show_default (0/1), $2: show_effect (0/1)
_cmd_list_rows() {
  local show_default="$1"
  local show_effect="$2"
  # iter2 CRIT 同種 leak 予防: while 本体内の `local cur_disp` / `local def_disp` 宣言を
  #   関数頭に集約し、ループ内は素の代入にして bash 3.2 cmdsubst stdout 漏洩を構造的に防ぐ。
  local key cur def type raw desc effect cur_disp def_disp
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    raw=$(_yml_get_raw "$CONFIG_PATH" "$key" || printf '')
    cur=$(_get_current "$key")
    type=$(_infer_type "$key" "$raw")
    desc=$(_meta_desc "$key")
    cur_disp=$(printf '%s' "$cur" | tr '\n' ',' | sed 's/,$//' | cut -c1-24)
    if [ "$show_effect" -eq 1 ]; then
      def=$(_get_default "$key" 2>/dev/null || printf '')
      effect=$(_meta_effect "$key")
      def_disp=$(printf '%s' "$def" | tr '\n' ',' | sed 's/,$//' | cut -c1-16)
      printf '%-48s %-18s %-18s %-7s %-44s %s\n' \
        "$key" "$cur_disp" "$def_disp" "$type" "$(printf '%s' "$desc" | cut -c1-42)" "$effect"
    elif [ "$show_default" -eq 1 ]; then
      def=$(_get_default "$key" 2>/dev/null || printf '')
      def_disp=$(printf '%s' "$def" | tr '\n' ',' | sed 's/,$//' | cut -c1-20)
      printf '%-48s %-22s %-22s %-7s %s\n' \
        "$key" "$cur_disp" "$def_disp" "$type" "$desc"
    else
      # ui-designer M3: default mode は KEY 44 + CURRENT 22 + TYPE 7 + 説明 (30 文字 truncate) に丸めて
      #   行幅暴走を抑える (説明全文は --verbose / --show-default で確認)。
      printf '%-44s %-22s %-7s %s\n' \
        "$key" "$(printf '%s' "$cur_disp" | cut -c1-20)" "$type" "$(printf '%s' "$desc" | cut -c1-30)"
    fi
  done
}

# --get <key>: 値取得 (HIGH H-02 test-auto fix: defaults fallback 実装)
cmd_get() {
  local key="$1"
  if [ -z "$key" ]; then
    _err "--get requires <key>"
    return 1
  fi
  # key format validation (security M-01)
  if ! _validate_key_format "$key"; then
    return 1
  fi
  # 1) yml に存在 → _get_current で env > yml の順
  if _yml_get_raw "$CONFIG_PATH" "$key" >/dev/null 2>&1; then
    _get_current "$key"
    printf '\n'
    return 0
  fi
  # 2) yml に不在 → defaults fallback (defaults が空でなければ返す)
  local def
  def=$(_get_default "$key" 2>/dev/null || printf '')
  if [ -n "$def" ]; then
    printf '%s\n' "$def"
    return 0
  fi
  # 3) defaults も空 → key not found
  _err "key not found: ${key}"
  return 1
}

# --set <key>=<value>: 値設定
cmd_set() {
  local arg="$1"
  if [[ ! "$arg" =~ ^[a-z_][a-zA-Z0-9_]*=.*$ ]]; then
    _err "--set requires <key>=<value>"
    return 1
  fi
  local key="${arg%%=*}"
  local val="${arg#*=}"
  if ! _validate_key_format "$key"; then
    return 1
  fi
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
  # key format validation (security M-01)
  if ! _validate_key_format "$key"; then
    return 1
  fi
  # iter2 CRIT 同種 leak 予防: case 内 `local items` を関数頭に集約。
  local def items
  def=$(_get_default "$key")
  if [ -z "$def" ]; then
    _err "no default value found for ${key}"
    return 1
  fi
  # array 値は yml inline 形式に再構成 (改行 → カンマ区切り [a, b, c])
  case "$def" in
    *$'\n'*)
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
  # iter2 CRIT 同種 leak 予防: while 本体内 `local cur_disp def_disp` を関数頭に集約。
  local key cur def cur_disp def_disp
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    cur=$(_get_current "$key")
    def=$(_get_default "$key" 2>/dev/null || printf '')
    if [ "$cur" != "$def" ]; then
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
  hc-config.sh                          引数なし: 対話 menu 起動 (TTY=矢印キー TUI / 非TTY=番号選択)
  hc-config.sh --list                   全 key 一覧表示 (KEY/CURRENT/TYPE/説明、category 別)
  hc-config.sh --list --verbose         全 key 一覧 + DEFAULT + 変更効果 (6 列)
  hc-config.sh --list --show-default     全 key 一覧 + DEFAULT 列
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
  - atomic 操作: .bak.<ts>.<pid> backup + .tmp.<pid> write + python yaml validate (stdin) + mv
  - 値型 validation: bool / int / float / array / string / path (改行/制御文字/yaml syntax confusion を reject)
  - 環境変数 HC_<KEY> で yml 値を override 可能 (config-loader.sh 経由)
  - .bak retention: 最新 N=10 件保持 (HC_BAK_RETENTION_COUNT で override)
  - --config path は REPO_ROOT / /tmp/ 配下のみ (HC_ALLOW_EXTERNAL_CONFIG=1 で bypass)

REFERENCE:
  - smoke test:  .claude/tests/hc-config-script-smoke.sh
  - config-loader: .claude/hooks/lib/config-loader.sh
  - 設計 draft:  docs/draft/config-yml-phase3-hc-config-script.md
EOF
}

# === 対話 menu helpers ===

# option 2: key 選択して編集 (cmd_interactive helper 1/3)
_menu_opt_edit_key() {
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
}

# option 3: feature toggle 一括 on/off (cmd_interactive helper 2/3)
_menu_opt_feature() {
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
}

# option 4: reviewer 設定 quick edit (cmd_interactive helper 3/3)
_menu_opt_reviewer() {
  local keys
  keys=$(_yml_list_keys "$CONFIG_PATH" | grep '^review_' || true)
  if [ -z "$keys" ]; then
    _out "no review_* keys found"
    return 0
  fi
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
}

# === 対話 menu (番号選択、TTY fallback path) ===
#
# task-48 Step 3: 従来の番号選択 menu を _cmd_interactive_numeric に抽出。
#   非 TTY (Claude Code session / pipe / CI) では raw terminal が効かないため本 path に降格、
#   HC_HC_CONFIG_FORCE_NUMERIC=1 で TTY でも強制番号選択。

# 番号選択 menu のメニュー行と選択プロンプトを印字
# _cmd_interactive_numeric helper
_numeric_menu_print() {
  cat <<'EOF'

=== hc-config interactive menu ===

  1) 全 key 一覧表示
  2) key 選択して編集
  3) feature toggle 一括 on/off
  4) reviewer 設定 quick edit (review_*)
  5) 終了

EOF
  printf 'choice [1-5/q]: '
}

_cmd_interactive_numeric() {
  # H5: 非 TTY fallback の UX 断絶を埋める案内 (1 行)。
  #   pipe / CI / Claude Code session では raw terminal が効かないため番号選択に降格する。
  _out "(非 TTY 環境のため番号選択モード。TTY 起動で矢印キー TUI が使えます)"
  while true; do
    _numeric_menu_print
    local choice
    if ! IFS= read -r choice; then
      printf '\nbye.\n'
      return 0
    fi
    case "$choice" in
      1)
        cmd_list
        ;;
      2)
        _menu_opt_edit_key
        ;;
      3)
        _menu_opt_feature
        ;;
      4)
        _menu_opt_reviewer
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

# === 矢印キー TUI (task-48 Step 3、TTY 必須) ===
#
# category 一覧 → key 一覧 (選択行を `>` + reverse video ハイライト) → 下部に effect panel。
# ESC [A/[B/[C/[D を decode、Enter で決定、q で quit。
# bash 3.2 互換: declare -g / ${var^^} を避け case / tr で代替。
#
# 注意: 本 path は TTY 環境でのみ呼ばれる (cmd_interactive の dispatch 参照)。
#       自動 smoke は非 TTY pipe で番号選択に降格するため TUI 描画は手動検証 (Step 5)。

# ANSI escape sequence 定義
_TUI_RESET=$'\033[0m'
_TUI_REVERSE=$'\033[7m'
_TUI_DIM=$'\033[2m'
_TUI_BOLD=$'\033[1m'
_TUI_CLEAR=$'\033[2J\033[H'

# task-60 Step 5 iter 2 H2 fix (DRY 解消): category 一覧の SSoT 定数。
#   `_tui_render_category_menu` / `_tui_render_key_menu` / `_cmd_interactive_tui_2tier` の
#   3 関数で同じ array を local 宣言していたのを 1 箇所に集約。bash 3.2 では `declare -ar` 不可
#   かつ scope 外への array 露出を避けるため、`|` 区切り string で持ち、各関数で
#   `IFS='|' read -r -a cat_names <<< "$_TUI_CAT_NAMES_STR"` で展開する (bash 3.2 互換)。
#   順序は draft §3.2 の category 順 (保護パス → ファイル配置 → state_dir → Gate/Confidence →
#   feature_toggle → reviewer_control)。
_TUI_CAT_NAMES_STR="保護パス|ファイル配置|state_dir|Gate/Confidence|feature_toggle|reviewer_control"

# 1 文字キー入力を読み取り、矢印キーは UP/DOWN/RIGHT/LEFT に正規化して stdout 出力
# Enter → ENTER、q → QUIT、それ以外は raw 文字。
#
# iter1 C1 fix (bash 3.2 互換):
#   旧実装の `read -rsn2 -t 0.01 rest` は bash 3.2 (macOS 標準) で
#   "invalid timeout specification" になり ESC sequence が全て QUIT に化けて
#   矢印キー TUI が動作しなかった。小数 `-t` を完全に排除し、ESC sequence の
#   inter-byte 読取は端末側の min/time 設定 (`stty min 0 time 1`、_cmd_interactive_tui で
#   一時設定) に委ねる。`read -rsn2 rest` (タイムアウト指定なし) は端末タイムアウトで
#   「続きが来なければ空」を実現する。bash 3.2 / 5.x 両対応。
#   呼び出し元 (_cmd_interactive_tui) は既に raw/cbreak mode (stty -icanon -echo min 1 time 0)。
_tui_read_key() {
  local key rest
  IFS= read -rsn1 key 2>/dev/null || { printf 'QUIT'; return 0; }
  case "$key" in
    $'\x1b')
      # ESC sequence: 続く 2 文字を読む ([A 等)。
      # 端末を一時的に min 0 time 1 (0.1 秒 inter-byte timeout) にして
      # 単独 ESC でも block しないようにする。小数 read -t は使わない (bash 3.2 互換)。
      stty min 0 time 1 2>/dev/null || true
      IFS= read -rsn2 rest 2>/dev/null || rest=""
      stty min 1 time 0 2>/dev/null || true
      # task-60 Step 5 iter 4 真の fix (M-new-1、draft §3.1 仕様乖離解消):
      #   単独 ESC (rest="") は 'ESC' を返し、unknown sequence のみ 'QUIT' に fallback。
      #   呼出側 (`_cmd_interactive_tui_2tier` key_menu state) で ESC|LEFT → back、
      #   QUIT (= q キー、L1216 で正規化) → 全終了の分離を実現する。
      #   `_cmd_interactive_tui_flat` 側は ESC|QUIT 同義扱いで互換維持 (Case 11 baseline)。
      case "$rest" in
        '[A') printf 'UP' ;;
        '[B') printf 'DOWN' ;;
        '[C') printf 'RIGHT' ;;
        '[D') printf 'LEFT' ;;
        '')   printf 'ESC' ;;
        *)    printf 'QUIT' ;;
      esac
      ;;
    ''|$'\n'|$'\r') printf 'ENTER' ;;
    q|Q)            printf 'QUIT' ;;
    *)              printf '%s' "$key" ;;
  esac
}

# 全 key を category 順に並べ替えて改行区切りで stdout 出力 (H3: category グルーピング)
# metadata category 順 (保護パス → ファイル配置 → state_dir → Gate/Confidence →
# feature_toggle → reviewer_control) に並べ、未分類 key は末尾に回す。
# metadata 不在時 / 全 key 未分類時は入力順そのまま (fallback)。
# $1: 全 key 改行区切り (yml 出現順)
_tui_order_keys_by_category() {
  local all_keys="$1"
  local categories="保護パス ファイル配置 state_dir Gate/Confidence feature_toggle reviewer_control"
  local ordered="" key cat seen_cat=0
  # iter2 CRIT C-iter2-1 fix (bash 3.2 local+command-substitution leak 予防):
  #   while ループ本体内で `local kc` (代入なし宣言) → 直後に `kc=$(_meta_category)` する構造は
  #   特定の bash 3.2 ビルドで command-substitution 出力が関数 stdout に漏洩する。
  #   `local kc` をループ外 (関数頭) で 1 回だけ宣言し、ループ内は素の代入にして漏洩を構造的に防ぐ。
  local kc
  # category 順に key を集める
  for cat in $categories; do
    while IFS= read -r key; do
      [ -z "$key" ] && continue
      if [ "$(_meta_category "$key")" = "$cat" ]; then
        ordered="${ordered}${key}"$'\n'
        seen_cat=1
      fi
    done <<< "$all_keys"
  done
  # 未分類 key (metadata 不在 / category 空) を末尾に追加
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    kc=$(_meta_category "$key")
    case "$kc" in
      保護パス|ファイル配置|state_dir|Gate/Confidence|feature_toggle|reviewer_control) ;;
      *) ordered="${ordered}${key}"$'\n' ;;
    esac
  done <<< "$all_keys"
  # category 一致 0 件 (metadata 完全不在) なら入力順そのまま
  if [ "$seen_cat" -eq 0 ]; then
    printf '%s\n' "$all_keys"
    return 0
  fi
  printf '%s' "$ordered"
}

# key 一覧部分の描画 (category 境界区切り行 + 選択ハイライト)
# $1: all_keys (改行区切り), $2: sel (0-based)
# _tui_render helper 1/2
_tui_render_key_list() {
  local all_keys="$1"
  local sel="$2"
  # iter2 CRIT C-iter2-2 fix (bash 3.2 local+command-substitution leak 予防):
  #   `cat_count` `kc` を関数頭で 1 回だけ宣言し、ループ/subshell 内は素の代入にして漏洩を防ぐ。
  local idx=0 key prev_cat="" cur_cat cat_count kc
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    cur_cat=$(_meta_category "$key")
    [ -z "$cur_cat" ] && cur_cat="(未分類)"
    if [ "$cur_cat" != "$prev_cat" ]; then
      cat_count=$(printf '%s\n' "$all_keys" | while IFS= read -r k; do
        [ -z "$k" ] && continue
        kc=$(_meta_category "$k"); [ -z "$kc" ] && kc="(未分類)"
        [ "$kc" = "$cur_cat" ] && printf 'x\n'
      done | grep -c .)
      printf '%s=== %s (%s keys) ===%s\n' "$_TUI_DIM" "$cur_cat" "$cat_count" "$_TUI_RESET"
      prev_cat="$cur_cat"
    fi
    if [ "$idx" -eq "$sel" ]; then
      printf '%s> %-46s%s\n' "$_TUI_REVERSE" "$key" "$_TUI_RESET"
    else
      printf '  %-46s\n' "$key"
    fi
    idx=$((idx + 1))
  done <<< "$all_keys"
}

# 選択中 key の effect panel を描画
# $1: all_keys (改行区切り), $2: sel (0-based)
# _tui_render helper 2/2
# perf MED (defer): 毎 keypress で _get_default (mktemp + config-loader source) を呼ぶ。
#   キャッシュ化は別 task で実施 (behavior-preserving に defer)。
_tui_render_effect_panel() {
  local all_keys="$1"
  local sel="$2"
  local cur_key
  cur_key=$(printf '%s' "$all_keys" | sed -n "$((sel + 1))p")
  [ -z "$cur_key" ] && return 0
  _tui_render_effect_panel_for_key "$cur_key"
}

# task-60 Step 5 iter 2 H3 fix (DRY 解消): 1 引数版 effect panel 描画 helper。
# $1: 表示対象 key (空なら no-op)
# 標準出力: 区切り行 + key/説明/型/現在値/default/変更効果 6 行 (`_tui_render_effect_panel` と同じ描画規約)。
# Step 3 で `_tui_render_key_menu` 内に inline 完全再実装 (16 LOC) されていた effect panel を
# 抽出し、`_tui_render_effect_panel` (all_keys+sel 2 引数) からも本 helper を呼ぶ形に揃えた。
# bash 3.2 互換: local の単純宣言のみ。
_tui_render_effect_panel_for_key() {
  local selected_key="$1"
  [ -z "$selected_key" ] && return 0
  local cur type raw desc effect def
  raw=$(_yml_get_raw "$CONFIG_PATH" "$selected_key" || printf '')
  cur=$(_get_current "$selected_key")
  def=$(_get_default "$selected_key" 2>/dev/null || printf '')
  type=$(_infer_type "$selected_key" "$raw")
  desc=$(_meta_desc "$selected_key")
  effect=$(_meta_effect "$selected_key")
  printf '\n%s---------------------------------------------------------------%s\n' "$_TUI_DIM" "$_TUI_RESET"
  printf '%skey%s     : %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$selected_key"
  printf '%s説明%s    : %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$desc"
  printf '%s型%s      : %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$type"
  printf '%s現在値%s  : %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$(printf '%s' "$cur" | tr '\n' ',')"
  printf '%sdefault%s : %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$(printf '%s' "$def" | tr '\n' ',')"
  printf '%s変更効果%s: %s\n' "$_TUI_BOLD" "$_TUI_RESET" "$effect"
}

# task-60 Step 2 (2026-05-29): category 別 key 数を返す (lib 経由)
# $1: category 名 (保護パス / ファイル配置 / state_dir / Gate/Confidence / feature_toggle / reviewer_control)
# 戻り: stdout に key 数 (整数、lib 不在なら 0)
#
# `hc_metadata_keys_by_category` (.claude/scripts/lib/hc-config-metadata.sh) は category 完全一致の
# key 群を改行区切りで返すため `grep -c .` で個数化する。lib 不在環境では guard で 0 を返す
# (TUI 描画は壊さず "0 keys" 表示で degrade、_meta_* 系と同じ fallback 規律)。
_meta_count_by_category() {
  local cat="$1"
  if command -v hc_metadata_keys_by_category >/dev/null 2>&1; then
    hc_metadata_keys_by_category "$cat" 2>/dev/null | grep -c '.' || printf '0'
  else
    printf '0'
  fi
}

# task-60 Step 2 (2026-05-29): 3-state machine の category_menu state 用 menu 描画
# $1: 現在の category sel index (0-5、default 0)
# 標準出力:
#   - 画面クリア + header (=== hc-config TUI ===  (↑/↓ 選択, Enter 決定, q 終了))
#   - 6 category 一覧 (保護パス / ファイル配置 / state_dir / Gate/Confidence /
#     feature_toggle / reviewer_control 順、draft §3.2 順拠)
#   - 選択行は "> " prefix + reverse video、非選択は "  " prefix のみ
#   - 各 category の key count を "(N keys)" で表示 (_meta_count_by_category 経由)
#
# Step 4 で 3-state machine から呼出される。本 Step では関数定義のみ追加、呼出側は未配線。
# bash 3.2 互換: index array (local -a) のみ使用、連想配列 / declare -g 不使用。
_tui_render_category_menu() {
  local sel="${1:-0}"
  # task-60 Step 5 iter 2 H2 fix: cat_names は SSoT 定数 _TUI_CAT_NAMES_STR から展開 (DRY)。
  local -a cat_names
  IFS='|' read -r -a cat_names <<< "$_TUI_CAT_NAMES_STR"
  local i=0 cat count
  printf '%s' "$_TUI_CLEAR"
  printf '%s=== hc-config TUI ===%s  (↑/↓ 選択, Enter 決定, q 終了)\n\n' "$_TUI_BOLD" "$_TUI_RESET"
  while [ "$i" -lt 6 ]; do
    cat="${cat_names[$i]}"
    count=$(_meta_count_by_category "$cat")
    if [ "$i" = "$sel" ]; then
      printf '%s> %-20s (%s keys)%s\n' "$_TUI_REVERSE" "$cat" "$count" "$_TUI_RESET"
    else
      printf '  %-20s (%s keys)\n' "$cat" "$count"
    fi
    i=$((i + 1))
  done
}

# task-60 Step 3 (2026-05-29): 3-state machine の key_menu state 用 menu 描画
# $1: category index (0-5、`_tui_render_category_menu` の cat_names 順)
# $2: 現在の key sel index (0-based、category 内の key 連番)
# 標準出力:
#   - 画面クリア + header (=== hc-config TUI ===  category: <cat>  (ESC: 戻る, q: 終了))
#   - category 配下の全 key を hc_metadata_keys_by_category 経由で取得し改行区切りで列挙
#   - 選択行は "> " prefix + reverse video、非選択は "  " prefix
#   - 下部 effect panel (区切り行 + key/説明/型/現在値/default/変更効果) を _tui_render_effect_panel と同じ
#     描画規約で inline 実装 (panel 関数は all_keys+sel 前提のため category scope 用に新規実装)
#
# Step 4 で 3-state machine の key_menu state から呼出される。本 Step では関数定義のみ追加、呼出側は未配線。
# bash 3.2 互換: index array (local -a) のみ使用、連想配列 / declare -g 不使用。lib 不在時は (該当 key なし) で degrade。
_tui_render_key_menu() {
  local cat_idx="${1:-0}"
  local key_sel="${2:-0}"
  # task-60 Step 5 iter 2 H2 fix: cat_names は SSoT 定数 _TUI_CAT_NAMES_STR から展開 (DRY)。
  local -a cat_names
  IFS='|' read -r -a cat_names <<< "$_TUI_CAT_NAMES_STR"
  local cat="${cat_names[$cat_idx]}"

  printf '%s' "$_TUI_CLEAR"
  printf '%s=== hc-config TUI ===%s  category: %s  (ESC: 戻る, q: 終了)\n\n' "$_TUI_BOLD" "$_TUI_RESET" "$cat"

  # category 配下 key 一覧取得 (lib 不在なら空)
  local keys=""
  if command -v hc_metadata_keys_by_category >/dev/null 2>&1; then
    keys=$(hc_metadata_keys_by_category "$cat" 2>/dev/null || true)
  fi
  if [ -z "$keys" ]; then
    printf '  (該当 key なし)\n'
    return 0
  fi

  # key 一覧描画 (sel ハイライト) + 選択 key 捕捉
  local i=0 key selected_key=""
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if [ "$i" = "$key_sel" ]; then
      printf '%s> %-46s%s\n' "$_TUI_REVERSE" "$key" "$_TUI_RESET"
      selected_key="$key"
    else
      printf '  %-46s\n' "$key"
    fi
    i=$((i + 1))
  done <<< "$keys"

  # task-60 Step 5 iter 2 H3 fix (DRY 解消): inline 完全再実装を
  #   _tui_render_effect_panel_for_key (1 引数版 helper) 呼出 1 行に置換。
  _tui_render_effect_panel_for_key "$selected_key"
}

# key 一覧の選択画面 + effect panel を描画 (H3: category 境界に区切り行を挿入)
# $1: category 順に並んだ全 key 改行区切り (1 行 1 key), $2: 選択 index (0-based、key のみ counts)
# 区切り行 (=== <category> (N keys) ===) は選択対象外。sel は key の連番。
_tui_render() {
  local all_keys="$1"
  local sel="$2"
  printf '%s' "$_TUI_CLEAR"
  printf '%s=== hc-config TUI ===%s  (↑/↓ 選択, Enter 決定, q 終了)\n\n' "$_TUI_BOLD" "$_TUI_RESET"
  _tui_render_key_list "$all_keys" "$sel"
  _tui_render_effect_panel "$all_keys" "$sel"
}

# ENTER/RIGHT キーで key 選択 → 新値入力 → cmd_set を実行
# $1: all_keys (改行区切り), $2: sel (0-based), $3: _stty_saved (canonical 復帰用)
# 戻り: 0 = 処理完了 (raw mode は呼び出し元が復帰すること)
# _cmd_interactive_tui helper
_tui_handle_enter() {
  local all_keys="$1"
  local sel="$2"
  local stty_saved="$3"
  local cur_key
  cur_key=$(printf '%s' "$all_keys" | sed -n "$((sel + 1))p")
  [ -z "$cur_key" ] && return 0
  # H4 + C1: canonical mode に戻して行編集可能な入力を受ける
  [ -n "$stty_saved" ] && stty "$stty_saved" 2>/dev/null
  local effect
  effect=$(_meta_effect "$cur_key")
  # H4: 入力プロンプト直上に変更効果を再掲
  printf '%s\n\n%s変更効果:%s %s\n新値を入力 (空で skip): ' \
    "$_TUI_RESET" "$_TUI_BOLD" "$_TUI_RESET" "$effect"
  local newval
  IFS= read -r newval || newval=""
  if [ -n "$newval" ]; then
    printf '変更後の効果: %s\n続行? [y/N]: ' "$effect"
    local confirm
    IFS= read -r confirm || confirm=""
    case "$confirm" in
      y|Y|yes|YES)
        cmd_set "${cur_key}=${newval}" && _out "更新しました: ${cur_key}=${newval}"
        ;;
      *)
        _out "skip しました"
        ;;
    esac
    printf '(Enter で menu に戻る) '
    IFS= read -r _ || true
  fi
  return 0
}

# TUI 本体: 選択 → effect 確認 → 新値入力 → 確認 → cmd_set
#
# iter1 C1 fix (bash 3.2 互換 stty raw mode + trap 復元):
#   矢印キーを 1 文字ずつ受け取るため端末を raw/cbreak mode に設定する。
#   異常終了 (Ctrl-C / kill / pipe 断) でも端末が壊れないよう trap で復元 + 表示属性 reset。
#   trap EXIT は「関数 return」では発火しないため、正常 return 前にも明示復元する。
# iter1 H4 fix (effect panel が Enter 後に消える):
#   ENTER で新値入力に入る際、入力プロンプト直上に「変更効果: <effect>」を 1 行再掲。
#   ENTER 時は canonical mode へ戻して行編集 (backspace 等) を効かせ、入力後 raw に復帰。
#
# task-60 Step 1 (2026-05-29): 旧 1 階層 flat 実装を `_cmd_interactive_tui_flat` に rename。
#   新 `_cmd_interactive_tui` wrapper (本関数の直後) が `HC_HC_CONFIG_FLAT_NAVIGATION=true` env
#   による fallback switch を提供する。Step 4 で本 wrapper を 3-state machine (category_menu →
#   key_menu → effect_edit) に置換予定。Step 1 段階では env 有無に関わらず flat 動作を維持。
_cmd_interactive_tui_flat() {
  local all_keys
  all_keys=$(_yml_list_keys "$CONFIG_PATH")
  # H3: category 順に並べ替え (区切り行表示は _tui_render が担当)
  all_keys=$(_tui_order_keys_by_category "$all_keys")
  local total
  total=$(printf '%s' "$all_keys" | grep -c '.')
  if [ "$total" -eq 0 ]; then
    _err "no keys found in ${CONFIG_PATH}"
    return 1
  fi

  # C1: raw mode 設定 + trap 復元 (異常終了でも端末を壊さない)
  # qa/tdd 注記: Ctrl-C (INT) / SIGTERM (TERM) / 正常 EXIT 時の stty 復元を trap で保証する。
  #   非 TTY pipe では stty -g が空文字を返し raw mode 自体 no-op になるため smoke では再現不能。
  #   手動検証は Step 5 で実施済。
  local _stty_saved
  _stty_saved=$(stty -g 2>/dev/null) || _stty_saved=""
  # shellcheck disable=SC2064
  trap "[ -n \"$_stty_saved\" ] && stty \"$_stty_saved\" 2>/dev/null; printf '%s' \"$_TUI_RESET\"" EXIT INT TERM
  stty -icanon -echo min 1 time 0 2>/dev/null || true

  local sel=0
  while true; do
    _tui_render "$all_keys" "$sel"
    local k
    k=$(_tui_read_key)
    case "$k" in
      UP)    [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
      DOWN)  [ "$sel" -lt "$((total - 1))" ] && sel=$((sel + 1)) ;;
      QUIT|ESC)
        # 正常終了: canonical 復帰 + 表示属性 reset + trap 解除
        # task-60 Step 5 iter 4: `_tui_read_key` の戻り値に 'ESC' を追加 (M-new-1 真の fix)。
        #   flat 実装は ESC = QUIT 同義扱いで Case 11 baseline 14/14 PASS を維持する
        #   (旧挙動: 単独 ESC は QUIT に正規化されていた)。2tier 実装側で ESC vs QUIT 分離。
        [ -n "$_stty_saved" ] && stty "$_stty_saved" 2>/dev/null
        trap - EXIT INT TERM
        printf '%s\n' "$_TUI_RESET"; _out "bye."; return 0 ;;
      ENTER|RIGHT)
        _tui_handle_enter "$all_keys" "$sel" "$_stty_saved"
        # raw mode に復帰してループ継続
        stty -icanon -echo min 1 time 0 2>/dev/null || true
        ;;
      *) : ;;  # その他キーは無視 (区切り行は選択不可なので skip 不要)
    esac
  done
}

# task-60 Step 4 (2026-05-29): 3-state machine ループ (category_menu → key_menu → effect_edit)
#
# 2 階層 navigation 本体。Step 2 で追加した `_tui_render_category_menu` と Step 3 で追加した
# `_tui_render_key_menu` を呼び出し、`_tui_read_key` (UP/DOWN/LEFT/RIGHT/ENTER/QUIT を返す抽象)
# でキー入力を受ける。既存 flat 実装 (`_cmd_interactive_tui_flat`) と同じ raw mode + trap 復元
# パターンを踏襲し、effect_edit state では `_tui_handle_enter` の入力 / 確認フローを inline 再現
# (cmd_set "key=val" 形式必須、L1457 と同様)。
#
# state machine 遷移 (task-60 Step 5 iter 4 真の fix、draft §3.1 仕様完全準拠):
#   category_menu --ENTER--> key_menu
#   category_menu --q--> quit (全終了)
#   key_menu      --ENTER--> effect_edit
#   key_menu      --ESC/LEFT--> category_menu (back)
#   key_menu      --q--> quit (全終了、draft §3.1 `key_menu --q--> quit` 通り)
#   effect_edit   --完了/skip--> key_menu (自動戻り)
#
# sel 位置記憶 (bash 3.2 互換、scalar 7 var + eval 合成、連想配列 / declare -g 不使用):
#   _tui_cat_sel        — category sel (0-5)
#   _tui_key_sel_0..5   — 各 category 配下の key sel (0-based、最終回戻り時に復元)
_cmd_interactive_tui_2tier() {
  # sel 位置 (function-local、初期値 0、既存値は session 全体で持続させない)
  local _tui_cat_sel=0
  local _tui_key_sel_0=0
  local _tui_key_sel_1=0
  local _tui_key_sel_2=0
  local _tui_key_sel_3=0
  local _tui_key_sel_4=0
  local _tui_key_sel_5=0

  # raw mode + trap 復元 (flat 実装 L1499-1503 と同じパターン)
  local _stty_saved
  _stty_saved=$(stty -g 2>/dev/null) || _stty_saved=""
  # shellcheck disable=SC2064
  trap "[ -n \"$_stty_saved\" ] && stty \"$_stty_saved\" 2>/dev/null; printf '%s' \"$_TUI_RESET\"" EXIT INT TERM
  stty -icanon -echo min 1 time 0 2>/dev/null || true

  local state="category_menu"
  # task-60 Step 5 iter 2 H2 fix: cat_names は SSoT 定数 _TUI_CAT_NAMES_STR から展開 (DRY)。
  local -a cat_names
  IFS='|' read -r -a cat_names <<< "$_TUI_CAT_NAMES_STR"
  local k cur_key_sel key_max cat selected_key keys_list effect newval confirm

  # task-60 Step 5 iter 2 H4 fix (eval safety): `eval "_tui_key_sel_${_tui_cat_sel}=..."` の
  #   `_tui_cat_sel` が未定義 / 空文字 / 非数値に化けた場合、`eval "_tui_key_sel_=..."` で global
  #   var `_tui_key_sel_` を生成し汚染するリスクがある (raw mode + trap race 限定で実害再現可)。
  #   関数頭で数値 sanitize して 0-5 範囲外なら 0 に reset する。state 入口でも再 sanitize する。
  case "$_tui_cat_sel" in
    ''|*[!0-9]*) _tui_cat_sel=0 ;;
  esac
  if [ "$_tui_cat_sel" -lt 0 ] || [ "$_tui_cat_sel" -gt 5 ]; then
    _tui_cat_sel=0
  fi

  while :; do
    case "$state" in
      category_menu)
        _tui_render_category_menu "$_tui_cat_sel"
        k=$(_tui_read_key)
        case "$k" in
          UP)    [ "$_tui_cat_sel" -gt 0 ] && _tui_cat_sel=$((_tui_cat_sel - 1)) ;;
          DOWN)  [ "$_tui_cat_sel" -lt 5 ] && _tui_cat_sel=$((_tui_cat_sel + 1)) ;;
          ENTER|RIGHT)
            state="key_menu"
            ;;
          QUIT)
            [ -n "$_stty_saved" ] && stty "$_stty_saved" 2>/dev/null
            trap - EXIT INT TERM
            printf '%s\n' "$_TUI_RESET"
            _out "bye."
            return 0
            ;;
          *) : ;;
        esac
        ;;
      key_menu)
        # task-60 Step 5 iter 2 H4 fix (eval safety): state 入口で _tui_cat_sel を再 sanitize。
        case "$_tui_cat_sel" in
          ''|*[!0-9]*) _tui_cat_sel=0 ;;
        esac
        if [ "$_tui_cat_sel" -lt 0 ] || [ "$_tui_cat_sel" -gt 5 ]; then
          _tui_cat_sel=0
        fi
        # 現 category の key sel と key 数を取得 (eval で変数名合成、bash 3.2 互換)
        eval "cur_key_sel=\${_tui_key_sel_${_tui_cat_sel}:-0}"
        cat="${cat_names[$_tui_cat_sel]}"
        key_max=$(_meta_count_by_category "$cat" 2>/dev/null || printf '0')
        # key_max が空 or 非数値 → 0 に fallback
        case "$key_max" in
          ''|*[!0-9]*) key_max=0 ;;
        esac
        # sel が range 外なら 0 に reset
        if [ "$key_max" -eq 0 ]; then
          # 該当 key なし → 入力受付。
          # task-60 Step 5 iter 4 真の fix (M-new-1、draft §3.1 仕様準拠):
          #   ESC|LEFT|ENTER|RIGHT|その他 → category_menu へ back
          #   QUIT (q) のみ全終了 (draft §3.1 `key_menu --q--> quit` 通り)
          _tui_render_key_menu "$_tui_cat_sel" 0
          k=$(_tui_read_key)
          case "$k" in
            QUIT)
              [ -n "$_stty_saved" ] && stty "$_stty_saved" 2>/dev/null
              trap - EXIT INT TERM
              printf '%s\n' "$_TUI_RESET"
              _out "bye."
              return 0
              ;;
            *)
              state="category_menu"
              continue
              ;;
          esac
        fi
        if [ "$cur_key_sel" -ge "$key_max" ] || [ "$cur_key_sel" -lt 0 ]; then
          cur_key_sel=0
          eval "_tui_key_sel_${_tui_cat_sel}=0"
        fi

        _tui_render_key_menu "$_tui_cat_sel" "$cur_key_sel"
        k=$(_tui_read_key)
        case "$k" in
          UP)
            [ "$cur_key_sel" -gt 0 ] && cur_key_sel=$((cur_key_sel - 1))
            eval "_tui_key_sel_${_tui_cat_sel}=\${cur_key_sel}"
            ;;
          DOWN)
            [ "$cur_key_sel" -lt "$((key_max - 1))" ] && cur_key_sel=$((cur_key_sel + 1))
            eval "_tui_key_sel_${_tui_cat_sel}=\${cur_key_sel}"
            ;;
          ESC|LEFT)
            # task-60 Step 5 iter 4 真の fix (M-new-1、draft §3.1 仕様乖離解消):
            #   `_tui_read_key` が単独 ESC を 'ESC' で返すよう修正 (L1207-1219) されたため、
            #   ESC|LEFT を back trigger として直接扱える (iter 2 fix の QUIT 経由 reroute は廃止)。
            #   draft §3.1 `key_menu --ESC/LEFT--> category_menu` + DoD「key 一覧で ESC または
            #   LEFT で category 一覧に戻る」を満たす。
            state="category_menu"
            ;;
          ENTER|RIGHT)
            state="effect_edit"
            ;;
          QUIT)
            # task-60 Step 5 iter 4 真の fix (M-new-1、draft §3.1 仕様乖離解消):
            #   QUIT (= q キー、L1216 で正規化) を全終了として扱う (draft §3.1
            #   `key_menu --q--> quit (全終了)` 通り)。iter 2 fix では `_tui_read_key` の戻り値
            #   仕様を維持するため QUIT を back に reroute していたが、iter 4 で `_tui_read_key`
            #   が ESC を独立した戻り値として返すようになり ESC vs QUIT 分離が可能になった。
            [ -n "$_stty_saved" ] && stty "$_stty_saved" 2>/dev/null
            trap - EXIT INT TERM
            printf '%s\n' "$_TUI_RESET"
            _out "bye."
            return 0
            ;;
          *) : ;;
        esac
        ;;
      effect_edit)
        # task-60 Step 5 iter 2 H4 fix (eval safety): state 入口で _tui_cat_sel を再 sanitize。
        case "$_tui_cat_sel" in
          ''|*[!0-9]*) _tui_cat_sel=0 ;;
        esac
        if [ "$_tui_cat_sel" -lt 0 ] || [ "$_tui_cat_sel" -gt 5 ]; then
          _tui_cat_sel=0
        fi
        # 選択 key 取得 (key_menu と同じ計算)
        eval "cur_key_sel=\${_tui_key_sel_${_tui_cat_sel}:-0}"
        cat="${cat_names[$_tui_cat_sel]}"
        selected_key=""
        if command -v hc_metadata_keys_by_category >/dev/null 2>&1; then
          keys_list=$(hc_metadata_keys_by_category "$cat" 2>/dev/null || true)
          selected_key=$(printf '%s\n' "$keys_list" | sed -n "$((cur_key_sel + 1))p")
        fi
        if [ -z "$selected_key" ]; then
          # key 取得失敗 → key_menu に戻る (description: lib 不在 or category 空)
          state="key_menu"
          continue
        fi

        # canonical mode に戻して行編集可能な入力を受ける (flat _tui_handle_enter L1443 と同じパターン)
        [ -n "$_stty_saved" ] && stty "$_stty_saved" 2>/dev/null
        effect=$(_meta_effect "$selected_key" 2>/dev/null || printf '')
        printf '%s\n\n%s変更効果:%s %s\n新値を入力 (空で skip): ' \
          "$_TUI_RESET" "$_TUI_BOLD" "$_TUI_RESET" "$effect"
        newval=""
        IFS= read -r newval || newval=""
        if [ -n "$newval" ]; then
          printf '変更後の効果: %s\n続行? [y/N]: ' "$effect"
          confirm=""
          IFS= read -r confirm || confirm=""
          case "$confirm" in
            y|Y|yes|YES)
              cmd_set "${selected_key}=${newval}" && _out "更新しました: ${selected_key}=${newval}"
              ;;
            *)
              _out "skip しました"
              ;;
          esac
          printf '(Enter で menu に戻る) '
          IFS= read -r _ || true
        fi
        # raw mode に復帰して key_menu に戻る
        stty -icanon -echo min 1 time 0 2>/dev/null || true
        state="key_menu"
        ;;
    esac
  done
}

# === task-60 Step 1: flat fallback wrapper ===
#
# `_cmd_interactive_tui` は cmd_interactive (TTY menu dispatcher) から呼ばれる entry point。
#   - HC_HC_CONFIG_FLAT_NAVIGATION=true  → 明示的に旧 flat 実装 (`_cmd_interactive_tui_flat`) 起動
#   - 上記以外                            → Step 4 で配線した `_cmd_interactive_tui_2tier` (3-state machine)
#
# Step 4 (2026-05-29) で TODO comment 部分を `_cmd_interactive_tui_2tier` 呼出に置換完了。
_cmd_interactive_tui() {
  # task-60 Step 1: env fallback switch
  if [ "${HC_HC_CONFIG_FLAT_NAVIGATION:-}" = "true" ]; then
    _cmd_interactive_tui_flat
    return $?
  fi
  # task-60 Step 4: 3-state machine ループに配線
  _cmd_interactive_tui_2tier
  return $?
}

# === 対話 menu dispatcher (TTY check + fallback) ===
#
# task-48 Step 3: TTY なら矢印キー TUI、非 TTY (pipe / CI) or HC_HC_CONFIG_FORCE_NUMERIC=1 なら
#   番号選択 menu に降格。
cmd_interactive() {
  if [ -t 0 ] && [ -t 1 ] && [ "${HC_HC_CONFIG_FORCE_NUMERIC:-}" != "1" ]; then
    _cmd_interactive_tui
  else
    _cmd_interactive_numeric
  fi
}

# === arg parser ===

# cmd に引数 $2 が必要かチェック。不在なら error + return 1
# $1: cmd (例: --get), $2: 引数値 (省略可)
_main_require_arg() {
  local cmd="$1"
  local arg="${2:-}"
  if [ -z "$arg" ]; then
    _err "${cmd} requires an argument"
    return 1
  fi
  return 0
}

# CLI args dispatch
# $@: --config 除外済み引数
_main_dispatch() {
  local cmd="${1:-}"
  local arg="${2:-}"
  case "$cmd" in
    --list)
      # --list [--verbose|--show-default] (task-48 Step 3)
      case "$arg" in
        --verbose|-v)     cmd_list "verbose" ;;
        --show-default)   cmd_list "show-default" ;;
        ""|*)             cmd_list "" ;;
      esac
      ;;
    --get)       _main_require_arg "$cmd" "$arg" && cmd_get "$arg" ;;
    --set)       _main_require_arg "$cmd" "$arg" && cmd_set "$arg" ;;
    --feature)   _main_require_arg "$cmd" "$arg" && cmd_feature "$arg" ;;
    --reset)     _main_require_arg "$cmd" "$arg" && cmd_reset "$arg" ;;
    --reset-all) cmd_reset_all ;;
    --diff)      cmd_diff ;;
    --validate)  cmd_validate ;;
    --help|-h)   cmd_help ;;
    *)
      _err "unknown command: ${cmd}"
      _err "run 'hc-config.sh --help' for usage"
      return 1
      ;;
  esac
}

main() {
  # --config <path> を最初に処理 (他 cmd の前提)
  # インラインループで CONFIG_PATH を設定 (subshell 回避)
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
  if ! _validate_config_path "$CONFIG_PATH"; then
    return 1
  fi

  if [ "${#new_args[@]}" -eq 0 ]; then
    cmd_interactive
    return $?
  fi

  _main_dispatch "${new_args[@]}"
}

main "$@"
