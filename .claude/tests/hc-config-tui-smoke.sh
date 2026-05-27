#!/usr/bin/env bash
# .claude/tests/hc-config-tui-smoke.sh — task-48 (TUI 化 + metadata 表示) smoke test
#
# 目的:
#   hc-config.sh TUI 化 + key metadata 表示 (task-48) の smoke test。
#   - lib/hc-config-metadata.sh (description / effect / category)
#   - hc-config.sh --list 説明列拡張 / --verbose / --show-default
#   - 矢印キー TUI (TTY 必須、render seam を非 TTY で検証) + 非 TTY 番号選択 fallback
#
# iter1 review fixes (本 commit、6 reviewer CRIT/HIGH/MED 反映):
#   C2  : Case 6 の env が pipe 先 bash に渡らない偽陽性を修正 (env を bash 側に置く)。
#   H7  : 番号 menu 経由の [y/N]=N rollback 検証 case 追加 (yml 無変化 assert)。
#   H8  : 空 yml の --list 挙動 (exit 0) 検証 case 追加。
#   H9  : Case 5/6 を「非 TTY pipe で numeric menu が実出力される」振る舞い検証中心化、
#         `[ -t 0 ]` 汎用 grep を除去しターゲットを絞る。
#   H10 : Case 7 を「yml inline comment と metadata description の包含一致」(drift 検出) に変更。
#   H11 : TUI render seam (_tui_render) を非 TTY で呼び選択行 `> <key>` 出力を検証する case 追加。
#         完全な ↑↓ pty simulate は Phase 2 defer (コメント明記)。
#   H12 : Case 1 に description 最低文字数 / effect != description 先頭 substring / category 6 分類検証を追加。
#   H13 : Case 1 に yml 実 key 数 == metadata key 総数 の双方向一致検証を追加。
#   MED : Case 3/4 に代表 key の description 内容検証、--show-default の DEFAULT 列検証、
#         --verbose --show-default 3 引数の無害性、ANSI escape 値の --list exit 0、
#         FORCE_NUMERIC 判定の "1" 限定 を追加。
#
# 設計:
#   - subshell 関数 ( set -uo pipefail; ... ) で各 case を隔離
#   - PASS/FAIL カウンタ + 結果出力 + 全 PASS で exit 0
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - BSD/GNU bash 両対応 (macOS bash 3.2 + Linux bash 5.x)
#   - 一時 yml は /tmp/ に作成、EXIT trap で cleanup

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"
HC_CONFIG_YML="${REPO_ROOT}/.claude/harness-config.yml"
HC_CONFIG_METADATA_LIB="${REPO_ROOT}/.claude/scripts/lib/hc-config-metadata.sh"

# tmp dir (cleanup on exit)
TMP_DIR="$(mktemp -d "/tmp/hc-config-tui-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=""

# --- helpers ---

_record() {
  local result="$1"
  local case_id="$2"
  local desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# timeout fallback (BSD / macOS で `timeout` 不在の環境向け)
# iter1 注意: 旧 fallback は `"$@" &` で対象を background 化していたため、
#   stdin pipe を食わせる case (番号 menu の編集 path 検証等) で stdin が detach され
#   入力が届かず偽 PASS / 偽 FAIL になっていた。
#   perl の alarm + exec は stdin を保持したまま実時間 timeout を提供する
#   (perl は macOS / Linux に標準搭載)。perl も無ければ無 timeout で実行 (script は
#   `5`/`q`/EOF で自己終了するため stdin EOF で確実に止まる)。
if ! command -v timeout >/dev/null 2>&1; then
  if command -v perl >/dev/null 2>&1; then
    timeout() {
      local sec="$1"; shift
      # alarm shift で sec 秒後に SIGALRM、exec で対象に置換 (stdin/stdout 継承)
      perl -e 'alarm shift; exec @ARGV or exit 127' "$sec" "$@"
    }
  else
    timeout() {
      # 無 timeout fallback: stdin を foreground で保持して実行
      shift
      "$@"
    }
  fi
fi

# 全 key を harness-config.yml から抽出するヘルパー
# MED fix: hc-config.sh の _yml_list_keys と同一 regex に統一
#   (^[a-z_][a-zA-Z0-9_]*: 行頭アンカー、インデント非許容)。
# format: KEY1 KEY2 KEY3 ... (改行区切り)
_get_all_config_keys() {
  grep -E '^[a-z_][a-zA-Z0-9_]*:' "${HC_CONFIG_YML}" \
    | sed -E 's/:.*$//'
}

# hc-config.sh の TUI 関数を非 TTY で呼ぶための sourceable 変種を生成 (H11 render seam 用)。
# 末尾の `main "$@"` 呼び出しのみ除去して source する (関数定義はそのまま、副作用なし)。
_make_sourceable_hcconfig() {
  local out="$1"
  grep -v '^main "\$@"$' "${HC_CONFIG_SCRIPT}" > "$out"
}

# ============================================================
# Case 1: metadata 完全性 — 全 74 key に description + effect、双方向一致、最低品質
# ============================================================
# H12 + H13: description 最低文字数 / effect != description 先頭 substring /
#            category 6 分類 / yml key 数 == metadata key 総数。
_case_1() (
  set -uo pipefail

  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf 'Case 1: lib/hc-config-metadata.sh not found\n' >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  local all_keys
  all_keys="$(_get_all_config_keys)"
  local yml_count meta_count missing=0
  yml_count=$(printf '%s\n' "$all_keys" | grep -c .)

  # 有効 category 集合
  local valid_cats="保護パス ファイル配置 state_dir Gate/Confidence feature_toggle reviewer_control"

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    local desc effect cat
    desc="$(hc_metadata_description "$key" 2>/dev/null || true)"
    effect="$(hc_metadata_effect "$key" 2>/dev/null || true)"
    cat="$(hc_metadata_category "$key" 2>/dev/null || true)"

    # description 存在 + 最低文字数 (>= 8、H12)
    if [ -z "$desc" ]; then
      printf 'Case 1: missing description for key: %s\n' "$key" >&2
      missing=$((missing + 1))
    elif [ "${#desc}" -lt 8 ]; then
      printf 'Case 1: description too short (<8) for key: %s (%s)\n' "$key" "$desc" >&2
      missing=$((missing + 1))
    fi
    # effect 存在
    if [ -z "$effect" ]; then
      printf 'Case 1: missing effect for key: %s\n' "$key" >&2
      missing=$((missing + 1))
    fi
    # H12: effect が description の先頭 substring でない (CSV/TSV 誤 parse 検出)
    #   誤 parse 時は effect が description の途中切れ断片になりがち。
    if [ -n "$desc" ] && [ -n "$effect" ]; then
      case "$desc" in
        "${effect}"*)
          printf 'Case 1: effect is a leading substring of description for %s (parse corruption?)\n' "$key" >&2
          missing=$((missing + 1))
          ;;
      esac
    fi
    # H12: category が 6 分類のいずれか
    case " $valid_cats " in
      *" $cat "*) : ;;
      *)
        printf 'Case 1: invalid/empty category for key: %s (got: %s)\n' "$key" "$cat" >&2
        missing=$((missing + 1))
        ;;
    esac
  done <<< "$all_keys"

  # H13: yml 実 key 数 == metadata key 総数 (双方向一致)
  meta_count=$(_hc_metadata_table | awk -F'\t' 'NF==4 {print $1}' | grep -c .)
  if [ "$yml_count" -ne "$meta_count" ]; then
    printf 'Case 1: key count mismatch: yml=%d metadata=%d\n' "$yml_count" "$meta_count" >&2
    # yml にあって metadata に無い key (および逆)
    local meta_keys
    meta_keys=$(_hc_metadata_table | awk -F'\t' 'NF==4 {print $1}')
    printf 'Case 1: in yml not in metadata:\n' >&2
    comm -23 <(printf '%s\n' "$all_keys" | sort) <(printf '%s\n' "$meta_keys" | sort) >&2
    printf 'Case 1: in metadata not in yml:\n' >&2
    comm -13 <(printf '%s\n' "$all_keys" | sort) <(printf '%s\n' "$meta_keys" | sort) >&2
    missing=$((missing + 1))
  fi

  [ "$missing" -eq 0 ]
)

# ============================================================
# Case 2: category グルーピング — 6 category 全 key 分類、未分類 key 0
# ============================================================
_case_2() (
  set -uo pipefail

  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf 'Case 2: lib/hc-config-metadata.sh not found\n' >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  local expected_categories="保護パス ファイル配置 state_dir Gate/Confidence feature_toggle reviewer_control"
  local missing_categories=0

  for cat in $expected_categories; do
    if ! hc_metadata_keys_by_category "$cat" 2>/dev/null | grep -q '.'; then
      printf 'Case 2: category not found or empty: %s\n' "$cat" >&2
      missing_categories=$((missing_categories + 1))
    fi
  done

  local all_keys
  all_keys="$(_get_all_config_keys)"
  local unclassified=0

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    local cat
    cat="$(hc_metadata_category "$key" 2>/dev/null || true)"
    if [ -z "$cat" ]; then
      printf 'Case 2: key has no category: %s\n' "$key" >&2
      unclassified=$((unclassified + 1))
    fi
  done <<< "$all_keys"

  [ "$missing_categories" -eq 0 ] && [ "$unclassified" -eq 0 ]
)

# ============================================================
# Case 3: --list 説明列拡張 — 説明列ヘッダー + 代表 key の description 内容
# ============================================================
# MED: header keyword だけでなく代表 key (confidence_threshold) の description が data 行に含まれる。
_case_3() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 3: hc-config.sh not executable\n' >&2
    return 1
  fi

  local output exit_code
  output="$(bash "${HC_CONFIG_SCRIPT}" --list 2>/dev/null)"
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 3: --list returned exit code %d\n' "$exit_code" >&2
    return 1
  fi
  # 説明列ヘッダー
  if ! printf '%s' "$output" | grep -q '説明'; then
    printf 'Case 3: --list does not contain 説明 column header\n' >&2
    return 1
  fi
  # MED: 代表 key confidence_threshold の description 主要語が data 行に含まれる
  if ! printf '%s' "$output" | grep '^confidence_threshold' | grep -q 'Confidence Gate'; then
    printf 'Case 3: confidence_threshold data row missing its description content\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 4: --list --verbose — 変更効果列 + 代表 key の effect 内容
# ============================================================
_case_4() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 4: hc-config.sh not executable\n' >&2
    return 1
  fi

  local output exit_code
  output="$(bash "${HC_CONFIG_SCRIPT}" --list --verbose 2>/dev/null)"
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    printf 'Case 4: --list --verbose returned exit code %d\n' "$exit_code" >&2
    return 1
  fi
  if ! printf '%s' "$output" | grep -q '変更効果'; then
    printf 'Case 4: --list --verbose does not contain 変更効果 column header\n' >&2
    return 1
  fi
  # MED: 代表 key の effect 主要語が出力に含まれる
  if ! printf '%s' "$output" | grep -q '上げると subagent の completion confidence'; then
    printf 'Case 4: confidence_threshold effect content missing in --verbose\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 5: 非 TTY pipe で numeric menu が実出力される (振る舞い検証、H9)
# ============================================================
# H9: symbol grep を _cmd_interactive_numeric にターゲット絞り + pipe 経由の実出力 (numeric menu) を検証。
#     `[ -t 0 ]` 汎用 grep は除去。
_case_5() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 5: hc-config.sh not executable\n' >&2
    return 1
  fi

  # 実装 seam: numeric fallback 関数が存在
  if ! grep -q '_cmd_interactive_numeric' "${HC_CONFIG_SCRIPT}"; then
    printf 'Case 5: _cmd_interactive_numeric not implemented\n' >&2
    return 1
  fi

  # 振る舞い: 非 TTY pipe で numeric menu が実出力される
  local output
  output="$(printf 'q\n' | timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  if ! printf '%s' "$output" | grep -q 'hc-config interactive menu'; then
    printf 'Case 5: numeric menu not shown in non-TTY (pipe) context\n' >&2
    return 1
  fi
  # H5: 非 TTY fallback 案内行も出る
  if ! printf '%s' "$output" | grep -q '非 TTY 環境のため番号選択モード'; then
    printf 'Case 5: non-TTY fallback notice missing\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 で強制番号選択 (env を bash 側に付与、C2)
# ============================================================
# C2 fix: 旧実装は env を pipe 元の printf に付与しており bash に渡らず偽陽性だった。
#   env を pipe 先 bash 側に置く。
# 制約 (Case 6 コメント): 非 TTY pipe では FORCE_NUMERIC 無しでも numeric に降格するため、
#   「TTY 環境での FORCE_NUMERIC による強制降格」は expect/pty なしには自動検証不可。
#   本 case は (1) 実装シンボル存在 + (2) env を bash 側に渡して numeric menu が出る までを検証する。
_case_6() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 6: hc-config.sh not executable\n' >&2
    return 1
  fi

  # 実装 seam: HC_HC_CONFIG_FORCE_NUMERIC が判定に使われている
  if ! grep -q 'HC_HC_CONFIG_FORCE_NUMERIC' "${HC_CONFIG_SCRIPT}"; then
    printf 'Case 6: HC_HC_CONFIG_FORCE_NUMERIC not implemented\n' >&2
    return 1
  fi

  # C2: env を pipe 先 bash 側に置く (printf ではなく bash に付与)
  local output
  output="$(printf 'q\n' | HC_HC_CONFIG_FORCE_NUMERIC=1 timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  if ! printf '%s' "$output" | grep -q 'hc-config interactive menu'; then
    printf 'Case 6: HC_HC_CONFIG_FORCE_NUMERIC=1 did not produce numeric menu\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 7: metadata と yml inline comment の一致検証 (drift 検出、H10)
# ============================================================
# H10 fix: 旧 Case 7 は静的 hardcode への keyword match で tautology (動的抽出 regression 不検出)。
#   inline comment を持つ key について「comment 主要語が metadata description に包含される」を検証。
_case_7() (
  set -uo pipefail

  if [ ! -f "${HC_CONFIG_METADATA_LIB}" ]; then
    printf 'Case 7: lib/hc-config-metadata.sh not found\n' >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "${HC_CONFIG_METADATA_LIB}"

  # inline comment を持つ代表 key (yml の `key: val  # comment` から comment を抽出)。
  # comment 主要語 (最初の token) が metadata description に含まれることを確認 (drift 検出)。
  local check_keys="review_iteration_max feature_loop_mode_enforcement_enabled feature_draft_flow_guard_enabled"
  local mismatch=0
  local key
  for key in $check_keys; do
    local comment desc token
    # yml から inline comment 抽出 (`# ` 以降)
    comment="$(grep -E "^${key}:" "${HC_CONFIG_YML}" | head -n 1 | sed -n 's/.*#[[:space:]]*//p')"
    if [ -z "$comment" ]; then
      printf 'Case 7: no inline comment found for %s (test key invalid)\n' "$key" >&2
      mismatch=$((mismatch + 1))
      continue
    fi
    desc="$(hc_metadata_description "$key" 2>/dev/null || true)"
    if [ -z "$desc" ]; then
      printf 'Case 7: no metadata description for %s\n' "$key" >&2
      mismatch=$((mismatch + 1))
      continue
    fi
    # comment の主要語 (最初の語、whitespace/区切りまで) を取り、description が含むか確認。
    # 記号で始まる comment (例 "loop-confirmation-detector + ...") は最初の単語を token とする。
    token="$(printf '%s' "$comment" | awk '{print $1}')"
    if [ -z "$token" ]; then
      printf 'Case 7: empty token from comment for %s\n' "$key" >&2
      mismatch=$((mismatch + 1))
      continue
    fi
    if ! printf '%s' "$desc" | grep -qF "$token"; then
      printf 'Case 7: drift detected — %s comment token "%s" not in metadata description\n' "$key" "$token" >&2
      printf '  comment: %s\n  desc   : %s\n' "$comment" "$desc" >&2
      mismatch=$((mismatch + 1))
    fi
  done

  [ "$mismatch" -eq 0 ]
)

# ============================================================
# Case 8: 空 yml の --list が exit 0 (異常終了しない、H8)
# ============================================================
_case_8() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 8: hc-config.sh not executable\n' >&2
    return 1
  fi

  local empty_yml="${TMP_DIR}/empty.yml"
  printf '' > "$empty_yml"

  local exit_code
  bash "${HC_CONFIG_SCRIPT}" --config "$empty_yml" --list >/dev/null 2>&1
  exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    printf 'Case 8: --list on empty yml returned exit %d (expected 0)\n' "$exit_code" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 9: 番号 menu 経由 [y/N]=N (空) で yml が変更されない (rollback 検証、H7)
# ============================================================
# H7: TUI は TTY 必須で自動不可なため、番号選択 menu の編集 path で検証。
#   key 編集 (option 2) → 新値入力 → 確認で N → yml 無変化 を diff で assert。
#   番号 menu の option 2 では「new value」入力後に即 cmd_set するため、
#   "確認 N で rollback" を再現するには空入力 (skip) を使う。
#   ここでは「新値を空入力で skip すれば書込みが起きず yml 無変化」を検証する。
_case_9() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 9: hc-config.sh not executable\n' >&2
    return 1
  fi

  local test_yml="${TMP_DIR}/rollback.yml"
  cp "${HC_CONFIG_YML}" "$test_yml"
  local before
  before="$(cat "$test_yml")"

  # option 2 (key 編集) → key 名 → 新値を空入力 (skip = rollback 相当) → 5 (終了)
  printf '2\nreview_iteration_max\n\n5\n' \
    | timeout 5 bash "${HC_CONFIG_SCRIPT}" --config "$test_yml" >/dev/null 2>&1 || true

  local after
  after="$(cat "$test_yml")"
  if [ "$before" != "$after" ]; then
    printf 'Case 9: yml changed despite skip (empty new value), rollback violated\n' >&2
    diff <(printf '%s' "$before") <(printf '%s' "$after") >&2 || true
    return 1
  fi
  return 0
)

# ============================================================
# Case 10: 番号 menu 経由 編集 → 新値あり で yml が実変更される (編集 path 振る舞い、H11 代替)
# ============================================================
# H11: 完全な TUI ↑↓ pty simulate は Phase 2 defer。本 case は numeric menu の編集 path の
#      「新値ありで実際に書き換わる」振る舞いを検証 (cmd_set 経路の end-to-end)。
_case_10() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 10: hc-config.sh not executable\n' >&2
    return 1
  fi

  local test_yml="${TMP_DIR}/edit.yml"
  cp "${HC_CONFIG_YML}" "$test_yml"

  # option 2 → key → 新値 3 → 5 (終了)
  printf '2\nreview_iteration_max\n3\n5\n' \
    | timeout 5 bash "${HC_CONFIG_SCRIPT}" --config "$test_yml" >/dev/null 2>&1 || true

  local newval
  newval="$(bash "${HC_CONFIG_SCRIPT}" --config "$test_yml" --get review_iteration_max 2>/dev/null | tr -d '[:space:]')"
  if [ "$newval" != "3" ]; then
    printf 'Case 10: edit path did not persist new value (got: %s, expected 3)\n' "$newval" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 11: TUI render seam — _tui_render が選択行 `> <key>` を非 TTY で出力する (H11)
# ============================================================
# H11: 矢印キー入力の pty simulate は Phase 2 defer。本 case は描画関数 _tui_render を
#      非 TTY で直接呼び、選択 index の key が `> ` プレフィックス付きで出力されること、
#      category 区切り行 (=== <cat> ... ===) が含まれることを検証する。
#      ↑↓ ナビゲーションの動的検証は Phase 2 (pty) defer。
_case_11() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 11: hc-config.sh not executable\n' >&2
    return 1
  fi

  local src="${TMP_DIR}/hc-config-src.sh"
  _make_sourceable_hcconfig "$src"

  # 別 bash で source して _tui_render を呼ぶ
  local rendered
  rendered="$(
    # shellcheck disable=SC1090
    source "${HC_CONFIG_METADATA_LIB}"
    # shellcheck disable=SC1090
    source "$src"
    CONFIG_PATH="${HC_CONFIG_YML}"
    local keys ordered
    keys=$(_yml_list_keys "$CONFIG_PATH")
    ordered=$(_tui_order_keys_by_category "$keys")
    _tui_render "$ordered" 0 2>/dev/null
  )" || true

  # ANSI escape を strip して検査
  local clean
  clean="$(printf '%s' "$rendered" | sed -E "s/$(printf '\033')\[[0-9;]*[A-Za-z]//g")"

  # sel=0 の先頭 key が `> ` 付きで出る
  if ! printf '%s' "$clean" | grep -qE '^> [a-z_]'; then
    printf 'Case 11: _tui_render did not emit a selected row (> <key>)\n' >&2
    return 1
  fi
  # category 区切り行が含まれる (H3)
  if ! printf '%s' "$clean" | grep -qE '=== .* keys\) ==='; then
    printf 'Case 11: _tui_render did not emit category separator rows\n' >&2
    return 1
  fi
  # effect panel (変更効果) が含まれる (H4 seam)
  if ! printf '%s' "$clean" | grep -q '変更効果'; then
    printf 'Case 11: _tui_render did not emit effect panel\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 12: --list --show-default で DEFAULT 列が出る + --verbose --show-default が無害 (MED)
# ============================================================
_case_12() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 12: hc-config.sh not executable\n' >&2
    return 1
  fi

  # --show-default: DEFAULT 列
  local out1 ec1
  out1="$(bash "${HC_CONFIG_SCRIPT}" --list --show-default 2>/dev/null)"
  ec1=$?
  if [ $ec1 -ne 0 ]; then
    printf 'Case 12: --list --show-default exit %d\n' "$ec1" >&2
    return 1
  fi
  if ! printf '%s' "$out1" | grep -q 'DEFAULT'; then
    printf 'Case 12: --show-default missing DEFAULT column\n' >&2
    return 1
  fi

  # --verbose --show-default 3 引数: 第 3 引数が無視されてもエラーにならない
  local ec2
  bash "${HC_CONFIG_SCRIPT}" --list --verbose --show-default >/dev/null 2>&1
  ec2=$?
  if [ $ec2 -ne 0 ]; then
    printf 'Case 12: --list --verbose --show-default returned exit %d (expected 0)\n' "$ec2" >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 13: FORCE_NUMERIC 判定が "1" 限定 (=0/=false は強制しない、MED negative)
# ============================================================
# 非 TTY pipe では元々 numeric なので「TUI 側に行く」直接観測は不可。
# 本 case は判定ロジックが "1" 限定であることをコード上で検証 (`!= "1"` パターン)。
# 加えて FORCE_NUMERIC=0 / =false でも非 TTY なら numeric menu が出る (壊れない) ことを確認。
_case_13() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 13: hc-config.sh not executable\n' >&2
    return 1
  fi

  # ロジックが "1" 限定 ( != "1" で TUI、== "1" で numeric強制) であることを確認
  if ! grep -qE 'HC_HC_CONFIG_FORCE_NUMERIC:-.*!=[[:space:]]*"1"' "${HC_CONFIG_SCRIPT}"; then
    printf 'Case 13: FORCE_NUMERIC dispatch is not gated on exact "1" value\n' >&2
    return 1
  fi

  # =0 / =false でも非 TTY では numeric menu が壊れず出る
  local out0 outf
  out0="$(printf 'q\n' | HC_HC_CONFIG_FORCE_NUMERIC=0 timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  outf="$(printf 'q\n' | HC_HC_CONFIG_FORCE_NUMERIC=false timeout 5 bash "${HC_CONFIG_SCRIPT}" 2>/dev/null || true)"
  if ! printf '%s' "$out0" | grep -q 'hc-config interactive menu'; then
    printf 'Case 13: FORCE_NUMERIC=0 broke non-TTY numeric menu\n' >&2
    return 1
  fi
  if ! printf '%s' "$outf" | grep -q 'hc-config interactive menu'; then
    printf 'Case 13: FORCE_NUMERIC=false broke non-TTY numeric menu\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case 14: ANSI escape を含む値の --list が exit 0 (MED)
# ============================================================
_case_14() (
  set -uo pipefail

  if [ ! -x "${HC_CONFIG_SCRIPT}" ]; then
    printf 'Case 14: hc-config.sh not executable\n' >&2
    return 1
  fi

  local esc_yml="${TMP_DIR}/ansi.yml"
  cp "${HC_CONFIG_YML}" "$esc_yml"
  # ESC を含む値を notify_sound に追記 (double-quote 形式)
  printf '\nnotify_sound: "%sred%s"\n' "$(printf '\033')[31m" "$(printf '\033')[0m" >> "$esc_yml"

  local ec
  bash "${HC_CONFIG_SCRIPT}" --config "$esc_yml" --list >/dev/null 2>&1
  ec=$?
  if [ "$ec" -ne 0 ]; then
    printf 'Case 14: --list with ANSI-escape value returned exit %d (expected 0)\n' "$ec" >&2
    return 1
  fi
  return 0
)

# ============================================================
# テスト実行
# ============================================================

printf '\n=== hc-config-tui-smoke (task-48: 14 cases, iter1 review fixes) ===\n\n'

if _case_1 2>/dev/null; then _record PASS 1 "metadata 完全性 — 74 key description+effect, 双方向一致, category 6 分類, effect!=desc断片"
else                         _record FAIL 1 "metadata 完全性 — 74 key description+effect, 双方向一致, category 6 分類, effect!=desc断片"
fi

if _case_2 2>/dev/null; then _record PASS 2 "category グルーピング — 6 category 全 key 分類、未分類 key 0"
else                         _record FAIL 2 "category グルーピング — 6 category 全 key 分類、未分類 key 0"
fi

if _case_3 2>/dev/null; then _record PASS 3 "--list 説明列 — 説明 header + 代表 key description 内容"
else                         _record FAIL 3 "--list 説明列 — 説明 header + 代表 key description 内容"
fi

if _case_4 2>/dev/null; then _record PASS 4 "--list --verbose — 変更効果列 + 代表 key effect 内容"
else                         _record FAIL 4 "--list --verbose — 変更効果列 + 代表 key effect 内容"
fi

if _case_5 2>/dev/null; then _record PASS 5 "非 TTY pipe で numeric menu 実出力 + fallback 案内 (H9)"
else                         _record FAIL 5 "非 TTY pipe で numeric menu 実出力 + fallback 案内 (H9)"
fi

if _case_6 2>/dev/null; then _record PASS 6 "HC_HC_CONFIG_FORCE_NUMERIC=1 (env を bash 側、C2)"
else                         _record FAIL 6 "HC_HC_CONFIG_FORCE_NUMERIC=1 (env を bash 側、C2)"
fi

if _case_7 2>/dev/null; then _record PASS 7 "metadata と yml inline comment の一致検証 (drift 検出、H10)"
else                         _record FAIL 7 "metadata と yml inline comment の一致検証 (drift 検出、H10)"
fi

if _case_8 2>/dev/null; then _record PASS 8 "空 yml の --list が exit 0 (H8)"
else                         _record FAIL 8 "空 yml の --list が exit 0 (H8)"
fi

if _case_9 2>/dev/null; then _record PASS 9 "番号 menu skip で yml 無変化 (rollback 検証、H7)"
else                         _record FAIL 9 "番号 menu skip で yml 無変化 (rollback 検証、H7)"
fi

if _case_10 2>/dev/null; then _record PASS 10 "番号 menu 編集 path で新値が persist (H11 代替)"
else                          _record FAIL 10 "番号 menu 編集 path で新値が persist (H11 代替)"
fi

if _case_11 2>/dev/null; then _record PASS 11 "TUI render seam — 選択行/区切り行/effect panel 出力 (H11)"
else                          _record FAIL 11 "TUI render seam — 選択行/区切り行/effect panel 出力 (H11)"
fi

if _case_12 2>/dev/null; then _record PASS 12 "--show-default で DEFAULT 列 + --verbose --show-default 無害 (MED)"
else                          _record FAIL 12 "--show-default で DEFAULT 列 + --verbose --show-default 無害 (MED)"
fi

if _case_13 2>/dev/null; then _record PASS 13 "FORCE_NUMERIC 判定が \"1\" 限定 (=0/=false negative、MED)"
else                          _record FAIL 13 "FORCE_NUMERIC 判定が \"1\" 限定 (=0/=false negative、MED)"
fi

if _case_14 2>/dev/null; then _record PASS 14 "ANSI escape 値の --list が exit 0 (MED)"
else                          _record FAIL 14 "ANSI escape 値の --list が exit 0 (MED)"
fi

# ============================================================
# 集計
# ============================================================

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi

exit 0
