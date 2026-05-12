#!/usr/bin/env bash
# .claude/hooks/lib/next-actions-parser.sh
# Shared parser for docs/tasks/next-actions.md — extracts unprocessed entry counts
# by urgency (🔴 / 🟡 / 🟢) from the markdown table.
#
# 役割:
#   next-actions-surface.sh と byproduct-discharge-guard.sh の両方で使う
#   table 行 parse を共通化する。
#
# 設計:
#   - set -e は使わない (mode-loader.sh の CB-verify 教訓 - 5846925)
#   - awk で構造化 parse (grep の脆い regex chain を避ける)
#   - 未処理判定: 「処理結果」列 (= 7 列目, table の末尾 `|` を除く) が `—` (em dash)
#   - 列分割: `|` 区切り、各 cell の前後 whitespace trim
#   - 「## エントリ一覧」セクションのみ scope (履歴セクションは除外)
#
# 公開関数:
#   parse_next_actions <next_actions_md_path>
#     副作用: グローバル変数を設定する
#       NA_RED_COUNT      — 🔴 未処理 entry 数
#       NA_YELLOW_COUNT   — 🟡 未処理 entry 数
#       NA_GREEN_COUNT    — 🟢 未処理 entry 数
#       NA_RED_TITLES     — 🔴 未処理 entry のタイトル (改行区切り、最大 5 件)
#     返り値:
#       0 = parse 成功 (file 存在 / table 検出 OK)
#       1 = file 不在
#       2 = table セクション不在 (counts は全 0)

set -uo pipefail   # set -e 禁止 (mode-loader.sh 教訓)

# parse_next_actions <file>
parse_next_actions() {
  local md_file="${1:-}"

  # reset globals
  NA_RED_COUNT=0
  NA_YELLOW_COUNT=0
  NA_GREEN_COUNT=0
  NA_RED_TITLES=""

  if [ -z "$md_file" ] || [ ! -f "$md_file" ]; then
    return 1
  fi

  # awk: 「## エントリ一覧」〜「## 」(次の見出し) の間で
  #   - `| <num> | <date> | <title> | <source> | <urgency> | <action> | <result> |`
  #     形式の行を検出
  #   - 1 列目が数字、最終列 (処理結果) が「—」のものを未処理として集計
  #   - urgency に絵文字 🔴 🟡 🟢 を含むかで分類
  #
  # AWK 出力 (3 行):
  #   RED=<n>
  #   YELLOW=<n>
  #   GREEN=<n>
  # 続けて RED タイトルを最大 5 件、`RED_TITLE=<title>` 形式で出力
  local awk_output
  awk_output=$(awk '
    BEGIN {
      in_section = 0
      red = 0
      yellow = 0
      green = 0
      red_titles_count = 0
    }
    # セクション境界判定: 「## エントリ一覧」で開始、次の `## ` 見出しで終了
    /^## エントリ一覧[[:space:]]*$/ {
      in_section = 1
      next
    }
    /^## / {
      if (in_section == 1) {
        in_section = 0
      }
      next
    }
    in_section == 1 && /^\|/ {
      # split by `|`
      n = split($0, cells, "|")
      # cells[1] は先頭 `|` の前 (空文字)
      # 期待: | <num> | <date> | <title> | <source> | <urgency> | <action> | <result> |
      #       → n = 9 (両端の空 cell 込み)、index 2..8 が実 cell
      if (n < 8) next

      # trim helper (前後 whitespace 除去)
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[i])
      }

      num     = cells[2]
      title   = cells[4]
      urgency = cells[6]
      result  = cells[8]

      # ヘッダ行 / 区切り行を除外: num が数字でない or `---:` 等
      if (num !~ /^[0-9]+$/) next

      # 未処理判定: 処理結果が `—` (em dash U+2014)
      if (result != "—") next

      if (index(urgency, "🔴") > 0) {
        red++
        if (red_titles_count < 5) {
          print "RED_TITLE=" title
          red_titles_count++
        }
      } else if (index(urgency, "🟡") > 0) {
        yellow++
      } else if (index(urgency, "🟢") > 0) {
        green++
      }
    }
    END {
      print "RED=" red
      print "YELLOW=" yellow
      print "GREEN=" green
    }
  ' "$md_file" 2>/dev/null)

  if [ -z "$awk_output" ]; then
    return 2
  fi

  # parse awk output into shell vars
  local line
  while IFS= read -r line; do
    case "$line" in
      RED=*)
        NA_RED_COUNT="${line#RED=}"
        ;;
      YELLOW=*)
        NA_YELLOW_COUNT="${line#YELLOW=}"
        ;;
      GREEN=*)
        NA_GREEN_COUNT="${line#GREEN=}"
        ;;
      RED_TITLE=*)
        local t="${line#RED_TITLE=}"
        if [ -z "$NA_RED_TITLES" ]; then
          NA_RED_TITLES="$t"
        else
          NA_RED_TITLES="${NA_RED_TITLES}"$'\n'"$t"
        fi
        ;;
    esac
  done <<< "$awk_output"

  # 全て数字でないと壊れるので safety
  case "$NA_RED_COUNT" in ''|*[!0-9]*) NA_RED_COUNT=0 ;; esac
  case "$NA_YELLOW_COUNT" in ''|*[!0-9]*) NA_YELLOW_COUNT=0 ;; esac
  case "$NA_GREEN_COUNT" in ''|*[!0-9]*) NA_GREEN_COUNT=0 ;; esac

  return 0
}
