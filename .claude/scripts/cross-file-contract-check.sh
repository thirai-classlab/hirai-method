#!/usr/bin/env bash
# cross-file-contract-check.sh — id / symbol / API cross-file contract verifier
# task-98 / P3-1 / I4
#
# 役割:
#   与えられた UI file (--file) または task file 一式 (--files) を対象に、
#   id / symbol / API 名の cross-file 参照整合性を assert する。
#   `.claude/contracts/*.yml` が存在すれば explicit SSoT として参照。
#   不在時は heuristic (git-based sibling file lookup + grep) で暗黙契約を検証。
#
# 設計起源:
#   docs/tasks/task-98-ui-contract-hook-cross-file-check.md
#   docs/draft/install-immediately-usable-redesign-20260618.md §3 I4 / §5 P3-1
#   memory feedback_parallel_subagent_cross_file_contract_drift (task-63)
#
# usage:
#   cross-file-contract-check.sh --file <path>            # 単一 UI file 起点
#   cross-file-contract-check.sh --files <p1> <p2> ...    # 複数 file 一括
#   cross-file-contract-check.sh --contracts-only         # .claude/contracts/*.yml のみ実行
#   cross-file-contract-check.sh --help
#
# 検出パターン (heuristic):
#   1. id="foo" / id='foo'       → 定義 side
#      querySelector("#foo") / getElementById("foo") / document.getElementById('foo')
#                                → 参照 side
#      不一致 = drift
#   2. export const/function/class Foo     → 定義 side
#      import { Foo } from './xxx'         → 参照 side
#      target file に export 定義なし = drift
#   3. `.claude/contracts/<name>.yml` の explicit contract:
#      producer: <file glob> defines: [id1, id2]
#      consumer: <file glob> uses:    [id1, id2]
#      producer 不在 or consumer 不在 = drift
#
# 出力:
#   drift 検出時: stdout に `[DRIFT] <detail>` 1 行/件、exit 1
#   drift なし  : stdout 空、exit 0
#   エラー時    : stderr WARN、exit 0 (fail-open)
#
# fail-open (advisory 方針、harness-dev preset):
#   - target file 不在 → exit 0
#   - grep / awk 失敗 → exit 0
#   - contracts dir 不在 → heuristic のみで判定続行

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

usage() {
  cat <<'EOF'
cross-file-contract-check.sh — id / symbol / API cross-file contract verifier

Usage:
  cross-file-contract-check.sh --file <path>
  cross-file-contract-check.sh --files <p1> <p2> ...
  cross-file-contract-check.sh --contracts-only
  cross-file-contract-check.sh --help

Exit codes:
  0 = drift なし (or fail-open エラー)
  1 = drift 検出
EOF
}

# --- 引数 parse -------------------------------------------------------

MODE=""
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      MODE="single"
      shift
      [ $# -gt 0 ] && FILES+=("$1") && shift
      ;;
    --files)
      MODE="multi"
      shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
        FILES+=("$1")
        shift
      done
      ;;
    --contracts-only)
      MODE="contracts"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      # unknown arg → fail-open (silent skip)
      shift
      ;;
  esac
done

if [ -z "$MODE" ]; then
  usage >&2
  exit 0
fi

# --- Repo root override (smoke test で tmp root を指定するため) --------

if [ -n "${HC_CONTRACT_CHECK_ROOT:-}" ] && [ -d "$HC_CONTRACT_CHECK_ROOT" ]; then
  REPO_ROOT="$HC_CONTRACT_CHECK_ROOT"
fi

CONTRACTS_DIR="${HC_CONTRACT_CONTRACTS_DIR:-$REPO_ROOT/.claude/contracts}"

# --- drift 出力バッファ (最終判定用) -----------------------------------
#
# 実装 note: `while ... | read` 構造の sub-shell 越え問題を回避するため、
# drift 件数は tmp file 経由で count する (bash 3.2 互換 + POSIX sh 互換)。
# emit_drift は stdout + tmp file 両方に書き込む。

DRIFT_FILE=$(mktemp 2>/dev/null || echo "/tmp/cross-file-contract-drift.$$")
trap 'rm -f "$DRIFT_FILE"' EXIT

emit_drift() {
  local line="[DRIFT] $1"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$DRIFT_FILE" 2>/dev/null || true
}

# --- helper: id 定義抽出 (target file 内の id="xxx" / id='xxx') --------

extract_ids_defined() {
  local file="$1"
  [ -f "$file" ] || return 0
  # id="foo" / id='foo' / :id="foo" (Vue) / id={`foo`} は除外
  # macOS/BSD grep 互換: -E で拡張正規表現
  grep -oE 'id=(["'"'"'])[a-zA-Z_][a-zA-Z0-9_-]*\1' "$file" 2>/dev/null \
    | sed -E "s/id=[\"']//; s/[\"']$//" \
    | sort -u
}

# --- helper: id 参照抽出 (querySelector('#foo') / getElementById('foo')) ---

extract_ids_referenced() {
  local file="$1"
  [ -f "$file" ] || return 0
  {
    # querySelector('#foo') / querySelector("#foo")
    grep -oE "querySelector\((\"|')#[a-zA-Z_][a-zA-Z0-9_-]*(\"|')\)" "$file" 2>/dev/null \
      | sed -E "s/querySelector\([\"']#//; s/[\"']\\)$//"
    # getElementById('foo') / getElementById("foo")
    grep -oE "getElementById\((\"|')[a-zA-Z_][a-zA-Z0-9_-]*(\"|')\)" "$file" 2>/dev/null \
      | sed -E "s/getElementById\([\"']//; s/[\"']\\)$//"
  } | sort -u
}

# --- helper: export symbol 抽出 ---------------------------------------

extract_exports() {
  local file="$1"
  [ -f "$file" ] || return 0
  {
    # export const Foo / export function Foo / export class Foo
    grep -oE 'export[[:space:]]+(const|function|class)[[:space:]]+[A-Z][a-zA-Z0-9_]*' "$file" 2>/dev/null \
      | awk '{print $NF}'
    # export { Foo, Bar }
    grep -oE 'export[[:space:]]+\{[^}]*\}' "$file" 2>/dev/null \
      | tr ',{}' '\n\n\n' \
      | grep -oE '[A-Z][a-zA-Z0-9_]*' 2>/dev/null
    # export default function Foo
    grep -oE 'export[[:space:]]+default[[:space:]]+(function|class)[[:space:]]+[A-Z][a-zA-Z0-9_]*' "$file" 2>/dev/null \
      | awk '{print $NF}'
  } | sort -u
}

# --- helper: import symbol 抽出 (from './xxx') ------------------------

extract_imports() {
  local file="$1"
  [ -f "$file" ] || return 0
  # import { Foo, Bar } from './xxx'
  grep -oE "import[[:space:]]+\{[^}]*\}[[:space:]]+from[[:space:]]+[\"'][^\"']*[\"']" "$file" 2>/dev/null \
    | sed -E "s/import[[:space:]]+\{//; s/\}[[:space:]]+from[[:space:]]+[\"']/|/; s/[\"']$//" \
    | while IFS='|' read -r symbols spec; do
        printf '%s\t%s\n' "$symbols" "$spec"
      done
}

# --- sibling file 探索 (heuristic) -----------------------------------

find_sibling_files() {
  local file="$1"
  local dir base stem
  dir=$(dirname "$file")
  base=$(basename "$file")
  # 拡張子除去 (最後の .xxx のみ)
  stem="${base%.*}"

  # 兄弟候補: 同 stem の別拡張子 + test/spec ペア + index.html
  local candidates=()
  local ext
  for ext in tsx jsx vue svelte html css scss ts js; do
    [ -f "$dir/$stem.$ext" ] && [ "$dir/$stem.$ext" != "$file" ] && candidates+=("$dir/$stem.$ext")
    [ -f "$dir/$stem.test.$ext" ] && candidates+=("$dir/$stem.test.$ext")
    [ -f "$dir/$stem.spec.$ext" ] && candidates+=("$dir/$stem.spec.$ext")
  done
  # 隣接 index.html (SPA entry) を追加
  [ -f "$dir/index.html" ] && [ "$dir/index.html" != "$file" ] && candidates+=("$dir/index.html")

  # 重複除去して出力 (bash 3.2 + set -u 互換: 空配列時は早期 return で ${arr[@]} unbound 回避)
  if [ "${#candidates[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${candidates[@]}" | sort -u
}

# --- id contract check (target file が UI file の場合) ----------------

check_id_contract() {
  local file="$1"
  local siblings ids_defined ids_referenced
  siblings=$(find_sibling_files "$file")
  [ -z "$siblings" ] && return 0

  ids_defined=$(extract_ids_defined "$file")

  # 参照 side: sibling file 内の querySelector('#foo') / getElementById('foo')
  local sibling
  local siblings_refs=""
  for sibling in $siblings; do
    local refs
    refs=$(extract_ids_referenced "$sibling")
    if [ -n "$refs" ]; then
      while IFS= read -r rid; do
        [ -z "$rid" ] && continue
        siblings_refs+="$sibling	$rid"$'\n'
      done <<< "$refs"
    fi
  done

  # 参照されている id が定義されていない → drift
  if [ -n "$siblings_refs" ]; then
    while IFS=$'\t' read -r ref_file rid; do
      [ -z "$rid" ] && continue
      if ! printf '%s\n' "$ids_defined" | grep -qFx "$rid"; then
        emit_drift "id '$rid' referenced in $ref_file but not defined in $file"
      fi
    done <<< "$siblings_refs"
  fi

  # 逆方向: target 内の querySelector('#foo') が sibling で定義されていない
  local self_refs
  self_refs=$(extract_ids_referenced "$file")
  if [ -n "$self_refs" ]; then
    while IFS= read -r rid; do
      [ -z "$rid" ] && continue
      local found=0
      for sibling in $siblings; do
        if extract_ids_defined "$sibling" | grep -qFx "$rid"; then
          found=1
          break
        fi
      done
      # target file 自身にあるかもチェック
      if [ "$found" -eq 0 ] && ! printf '%s\n' "$ids_defined" | grep -qFx "$rid"; then
        emit_drift "id '$rid' referenced in $file but not defined in sibling files"
      fi
    done <<< "$self_refs"
  fi
}

# --- symbol/export contract check (heuristic) -------------------------

check_symbol_contract() {
  local file="$1"
  # import 参照抽出: `import { Foo, Bar } from './xxx'`
  local imports
  imports=$(extract_imports "$file")
  [ -z "$imports" ] && return 0

  local file_dir
  file_dir=$(dirname "$file")

  while IFS=$'\t' read -r symbols_raw spec; do
    [ -z "$symbols_raw" ] && continue
    [ -z "$spec" ] && continue

    # relative import のみ対象 (`./` `../` で始まる)
    case "$spec" in
      ./*|../*) ;;
      *) continue ;;
    esac

    # 実 file path 解決 (拡張子推定)
    local target=""
    local base_path="$file_dir/$spec"
    for ext in "" .ts .tsx .js .jsx .vue .svelte; do
      if [ -f "${base_path}${ext}" ]; then
        target="${base_path}${ext}"
        break
      fi
      if [ -f "${base_path}/index${ext}" ]; then
        target="${base_path}/index${ext}"
        break
      fi
    done

    # target file 不在 → skip (path 解決失敗、fail-open)
    [ -z "$target" ] && continue

    # symbol 抽出 (カンマ区切り)
    local exports
    exports=$(extract_exports "$target")

    # symbols_raw の中身を 1 個ずつ検証
    printf '%s\n' "$symbols_raw" | tr ',' '\n' | while IFS= read -r sym; do
      # trim + as alias 除去 (Foo as Bar → Foo)
      sym=$(printf '%s' "$sym" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+as[[:space:]]+.*//')
      [ -z "$sym" ] && continue
      # default import は除外 (先頭 default キーワード + Type import は複雑なので skip)
      case "$sym" in
        default|type|"") continue ;;
      esac
      if ! printf '%s\n' "$exports" | grep -qFx "$sym"; then
        emit_drift "symbol '$sym' imported from '$spec' ($target) in $file but not exported"
      fi
    done
  done <<< "$imports"
}

# --- explicit contracts (.claude/contracts/*.yml) ---------------------

check_explicit_contracts() {
  local contracts_dir="$1"
  [ -d "$contracts_dir" ] || return 0

  local yml
  for yml in "$contracts_dir"/*.yml; do
    [ -f "$yml" ] || continue

    # 極めて簡易な YAML parser (nested 非対応、最小限):
    #   producer_file: <path relative to repo>
    #   consumer_file: <path relative to repo>
    #   ids: [id1, id2]
    local producer consumer ids_line
    producer=$(grep -E '^producer_file:[[:space:]]*' "$yml" 2>/dev/null | head -1 | sed -E 's/^producer_file:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')
    consumer=$(grep -E '^consumer_file:[[:space:]]*' "$yml" 2>/dev/null | head -1 | sed -E 's/^consumer_file:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')
    ids_line=$(grep -E '^ids:[[:space:]]*\[' "$yml" 2>/dev/null | head -1 | sed -E 's/^ids:[[:space:]]*\[//; s/\][[:space:]]*$//')

    [ -z "$producer" ] && continue
    [ -z "$consumer" ] && continue
    [ -z "$ids_line" ] && continue

    local producer_path="$REPO_ROOT/$producer"
    local consumer_path="$REPO_ROOT/$consumer"

    # id list をカンマ split して個別 assert
    local id
    printf '%s\n' "$ids_line" | tr ',' '\n' | while IFS= read -r id; do
      id=$(printf '%s' "$id" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^["'"'"']//; s/["'"'"']$//')
      [ -z "$id" ] && continue

      # producer file で id 定義されているか
      if [ ! -f "$producer_path" ]; then
        emit_drift "contract $yml: producer_file '$producer' 不在"
        continue
      fi
      if [ ! -f "$consumer_path" ]; then
        emit_drift "contract $yml: consumer_file '$consumer' 不在"
        continue
      fi

      if ! extract_ids_defined "$producer_path" | grep -qFx "$id"; then
        emit_drift "contract $yml: id '$id' not defined in producer '$producer'"
      fi
      if ! extract_ids_referenced "$consumer_path" | grep -qFx "$id"; then
        emit_drift "contract $yml: id '$id' not referenced in consumer '$consumer'"
      fi
    done
  done
}

# --- main -------------------------------------------------------------

case "$MODE" in
  contracts)
    check_explicit_contracts "$CONTRACTS_DIR"
    ;;
  single|multi)
    for f in "${FILES[@]}"; do
      [ -z "$f" ] && continue
      if [ ! -f "$f" ]; then
        # file 不在 → skip (fail-open)
        continue
      fi
      check_id_contract "$f"
      check_symbol_contract "$f"
    done
    # explicit contracts も併せて実行 (存在時のみ)
    check_explicit_contracts "$CONTRACTS_DIR"
    ;;
esac

# drift 件数を tmp file から count (sub-shell 越え対策)
DRIFT_COUNT=0
if [ -f "$DRIFT_FILE" ]; then
  DRIFT_COUNT=$(wc -l < "$DRIFT_FILE" 2>/dev/null | tr -d ' ' || echo 0)
fi

if [ "${DRIFT_COUNT:-0}" -gt 0 ]; then
  exit 1
fi
exit 0
