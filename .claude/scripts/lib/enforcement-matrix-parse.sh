# .claude/scripts/lib/enforcement-matrix-parse.sh — task-70 Step 7 (DRY 抽出)
#
# shellcheck shell=bash
#
# 目的:
#   harness-config.yml の enforcement_matrix block を awk parse する 3 ヘルパーの SSoT。
#   flat parser (_yml_get_raw) では nested block (2/4/6-space インデント) が読めないため
#   yml を直接 awk で読む。
#
#   抽出前は以下の 2 ファイルに character-identical なロジックが重複していた:
#     - .claude/scripts/hc-config.sh       (_em_guards / _em_field / _em_disabled_reason)
#     - .claude/tests/enforcement-mismatch-smoke.sh (_matrix_guards / _matrix_field / _matrix_has_disabled_reason)
#
# 公開 interface:
#   em_guards <yml>                   → guard 名を 1 行ずつ stdout (2-space インデント guard: 行)
#   em_field <yml> <guard> <field>    → 指定 field の値を stdout (4-space インデント)
#   em_disabled_reason <yml> <guard> <preset>
#                                     → disabled_reason 内の preset の理由文字列を stdout
#                                       (理由あり: print + return 0 / なし: return 1)
#
# 使い方:
#   source "${SCRIPT_DIR}/lib/enforcement-matrix-parse.sh"
#   guards="$(em_guards "$YML_PATH")"
#   fkey="$(em_field "$YML_PATH" "$guard" feature_key)"
#   em_disabled_reason "$YML_PATH" "$guard" "$preset"  # stdout に理由文字列
#   em_disabled_reason "$YML_PATH" "$guard" "$preset" >/dev/null  # exit code のみ
#
# 設計:
#   - source 専用 lib (shebang なし、set -euo pipefail なし — feedback_set_e_in_sourced_libs 規範)
#   - 引数として yml path を受け取る (caller の変数名に依存しない)
#   - bash 3.2 互換
#
# 起源: task-70 Step 7 リファクタリング (architect-reviewer LOW-1 DRY 指摘)
#   設計 draft: docs/draft/harness-review-remediation-plan.md §2.1

# enforcement_matrix block の guard 名一覧 (2-space インデント `  <guard>:`)。
# $1: yml path
em_guards() {
  awk '
    /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
    in_m && /^[^[:space:]]/ { in_m=0 }
    in_m && /^  [a-z_][a-zA-Z0-9_]*:[[:space:]]*$/ {
      line=$0; sub(/^  /,"",line); sub(/:.*$/,"",line); print line
    }
  ' "$1"
}

# 指定 guard の指定 field 値 (4-space `    <field>: <value>`)。
# $1=yml, $2=guard, $3=field
em_field() {
  awk -v g="$2" -v f="$3" '
    /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
    in_m && /^[^[:space:]]/ { in_m=0 }
    in_m && $0 ~ "^  " g ":[[:space:]]*$" { in_g=1; next }
    in_m && in_g && /^  [a-z_]/ { in_g=0 }
    in_m && in_g && $0 ~ "^    " f ":" {
      line=$0; sub("^    " f ":[[:space:]]*","",line); print line; exit
    }
  ' "$1"
}

# 指定 guard の disabled_reason に指定 preset の理由文字列を返す。
# $1=yml, $2=guard, $3=preset
# 理由あり: stdout に理由文字列を print + return 0
# 理由なし: return 1 (stdout には何も出力しない)
em_disabled_reason() {
  awk -v g="$2" -v p="$3" '
    /^enforcement_matrix:[[:space:]]*$/ { in_m=1; next }
    in_m && /^[^[:space:]]/ { in_m=0 }
    in_m && $0 ~ "^  " g ":[[:space:]]*$" { in_g=1; next }
    in_m && in_g && /^  [a-z_]/ { in_g=0; in_dr=0 }
    in_m && in_g && /^    disabled_reason:[[:space:]]*$/ { in_dr=1; next }
    in_m && in_g && /^    [a-z_]/ && !/^    disabled_reason:/ { in_dr=0 }
    in_m && in_g && in_dr && $0 ~ "^      " p ":" {
      val=$0; sub("^      " p ":[[:space:]]*","",val)
      gsub(/^[\"\x27]|[\"\x27][[:space:]]*$/,"",val)
      if (length(val) > 0) { print val; found=1 }
    }
    END { exit (found ? 0 : 1) }
  ' "$1"
}
