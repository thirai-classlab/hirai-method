#!/usr/bin/env bash
# bash-whitelist.sh — Bash 経路の whitelist 照合 + segment splitter + path leak guard
#
# 提供関数:
#   split_command_segments <cmd>       — quote/heredoc aware なコマンド分割 (Case 1-9 検証済)
#   check_bash_inline_override <cmd>   — CLAUDE_ALLOW_MAIN_PUSH= etc. inline override 検出
#   check_bash_whitelist <cmd>         — whitelist 照合 + path leak guard

# --- inline env-var override 検出 (Hook バイパス封じ) ---
check_bash_inline_override() {
  local cmd="$1"
  if printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])CLAUDE_(ALLOW_MAIN_PUSH|HARNESS_ROLE)='; then
    echo '{"decision":"block","reason":"[ハーネス保全] コマンド内に CLAUDE_ALLOW_MAIN_PUSH= / CLAUDE_HARNESS_ROLE= の inline 設定が含まれています。Hook のバイパスは禁止。承認が必要なら user に申請してください。"}'
    exit 0
  fi
}

# === segment splitter ===
# Bash コマンドを &&, ||, ;, | で分割して各セグメントを whitelist 照合する。
# quote-aware 実装: シングル/ダブルクォート内 + escape (\\) 後の特殊文字を保護。
# heredoc 本文 (<<EOF / <<-EOF / <<'EOF' / <<"EOF") は 1 つの string literal として
# 扱い、segment splitter から除外する (2026-05-23 修正、Case 7-9 で検証)。
#
# 出力は segment 間を \n、segment 内部の改行 (heredoc 本文等) はそのまま保持する。
# 外側読み取り側は heredoc 内改行も別 segment として扱わない実装にする必要があるが、
# 本実装では splitter 出力時に「heredoc/quoted 内の改行を space に置換」する shortcut で
# 単純化する。whitelist は line-start prefix match なので、各 segment の最初の token
# (例: `git`, `npm`) さえ正しく取れれば照合可能。
#
# 検証: .claude/tests/delegation-guard-segment-smoke.sh Case 1-9
split_command_segments() (
  set -uo pipefail
  # awk に入力全体を 1 つの record として渡す (RS で paragraph mode、改行を含む multiline cmd 対応)
  printf '%s' "$1" | awk 'BEGIN { RS = "\x00" } {
      cmd = $0
      out = ""
      i = 1
      in_single = 0
      in_double = 0
      escape = 0
      in_heredoc = 0
      heredoc_delim = ""
      heredoc_dash = 0
      n = length(cmd)
      while (i <= n) {
        c = substr(cmd, i, 1)

        # === heredoc 本文中の処理 ===
        # heredoc 本文は segment splitter / quote tracker を適用しない。
        # 改行は " " (space) に置換して segment splitter (外側 \n 区切り) に
        # 誤検出されないようにする。delimiter 行を見たら heredoc 終了。
        if (in_heredoc) {
          if (c == "\n") {
            # 次行 (line_end まで) を抽出して delimiter 判定
            next_line_end = index(substr(cmd, i+1), "\n")
            if (next_line_end == 0) {
              next_line = substr(cmd, i+1)
              next_line_len = length(next_line)
            } else {
              next_line = substr(cmd, i+1, next_line_end - 1)
              next_line_len = next_line_end - 1
            }
            # <<-EOF 形式は先頭タブを strip して比較
            check_line = next_line
            if (heredoc_dash) {
              sub(/^\t+/, "", check_line)
            }
            if (check_line == heredoc_delim) {
              # delimiter 行: 改行を space に置換、delimiter 行はそのまま追記、heredoc 終了
              # delimiter 行直後に続く文字 (例: `\n)\"`) は実 bash では heredoc の
              # コマンド置換 ($(...)) 内とみなされるが、本 parser は $() を追えないので
              # 「delimiter 直後の改行も heredoc 続きの一部」として空白に置換し、
              # segment splitter が誤反応しないようにする (簡略実装、Case 7-9 で検証)。
              out = out " " next_line
              i += 1 + next_line_len
              in_heredoc = 0
              heredoc_delim = ""
              heredoc_dash = 0
              # delimiter 行直後の改行 (もしあれば) も space に置換
              if (i <= n && substr(cmd, i, 1) == "\n") {
                out = out " "
                i++
              }
              continue
            }
            # 通常の本文行: 改行を space に置換して継続
            out = out " "
            i++
            continue
          }
          # 本文中の普通の文字: そのまま追記 (| & ; 等の特殊文字も literal 扱い)
          out = out c
          i++
          continue
        }

        # === heredoc 外: 通常 parser ===
        if (escape) {
          out = out c
          escape = 0
          i++
          continue
        }
        if (c == "\\" && in_single == 0) {
          out = out c
          escape = 1
          i++
          continue
        }
        if (c == "\x27" && in_double == 0) {
          in_single = 1 - in_single
          out = out c
          i++
          continue
        }
        if (c == "\"" && in_single == 0) {
          in_double = 1 - in_double
          out = out c
          i++
          continue
        }

        # === heredoc 開始 marker 検出 ===
        # `<<EOF` / `<<-EOF` / `<<'\''EOF'\''` / `<<"EOF"` 全形式を検出。
        # 注: 厳密 bash 仕様では quote 内 `<<` は heredoc にならないが、本 parser は
        # $() / ``などのコマンド置換スコープを追えないため、quote 状態に関係なく検出する。
        # これは `git commit -m "$(cat <<'\''EOF'\'' ... EOF)"` 形式を救うために必要。
        # 文字列内に literal で `<<WORD` が出現するケースは極稀で実害は小さい。
        if (c == "<" && substr(cmd, i+1, 1) == "<") {
          # `<<<` (here-string) は除外
          if (substr(cmd, i+2, 1) == "<") {
            out = out c
            i++
            continue
          }
          # `<<` を out に追記
          out = out "<<"
          j = i + 2
          # `<<-` 形式 (tab strip)
          dash = 0
          if (substr(cmd, j, 1) == "-") {
            dash = 1
            out = out "-"
            j++
          }
          # delimiter 抽出: optional 空白 + quoted/unquoted word
          while (j <= n && (substr(cmd, j, 1) == " " || substr(cmd, j, 1) == "\t")) {
            out = out substr(cmd, j, 1)
            j++
          }
          if (j > n) {
            # delimiter なし、invalid
            i = j
            continue
          }
          qc = substr(cmd, j, 1)
          delim = ""
          if (qc == "\x27" || qc == "\"") {
            # quoted delimiter
            quote_char = qc
            out = out qc
            j++
            while (j <= n && substr(cmd, j, 1) != quote_char) {
              delim = delim substr(cmd, j, 1)
              out = out substr(cmd, j, 1)
              j++
            }
            if (j <= n) {
              out = out quote_char
              j++
            }
          } else {
            # unquoted delimiter: word char (英数 + _) が続く間
            while (j <= n) {
              ch = substr(cmd, j, 1)
              if (ch ~ /[A-Za-z0-9_]/) {
                delim = delim ch
                out = out ch
                j++
              } else {
                break
              }
            }
          }
          if (delim != "") {
            in_heredoc = 1
            heredoc_delim = delim
            heredoc_dash = dash
          }
          i = j
          continue
        }

        if (in_single == 0 && in_double == 0) {
          if (c == "&" && substr(cmd, i+1, 1) == "&") {
            out = out "\n"
            i += 2
            continue
          }
          if (c == "|" && substr(cmd, i+1, 1) == "|") {
            out = out "\n"
            i += 2
            continue
          }
          if (c == ";" || c == "|") {
            out = out "\n"
            i++
            continue
          }
        }
        out = out c
        i++
      }
      print out
    }'
)

# whitelist 照合 + path leak guard
# 入力: $1 = cmd
# 副作用: block 時は jq 出力して exit 0
check_bash_whitelist() {
  local cmd="$1"
  local whitelist_file="$HC_BASH_WHITELIST_PATH"
  if [ ! -f "$whitelist_file" ]; then
    jq -nc --arg p "$HC_BASH_WHITELIST_PATH" \
      '{decision:"block", reason:("[ハーネス保全] " + $p + " が存在しません。ハーネスが破損している可能性があります。")}'
    exit 0
  fi

  # 各セグメントを抽出 (; && || | で分割)
  local segments
  segments=$(split_command_segments "$cmd")

  local all_allowed="true"
  local bad_segment=""
  local seg seg_trim matched pattern
  while IFS= read -r seg; do
    seg_trim=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -z "$seg_trim" ] && continue

    matched="false"
    while IFS= read -r pattern; do
      # コメント / 空行スキップ
      case "$pattern" in
        ''|\#*) continue ;;
      esac
      if printf '%s' "$seg_trim" | grep -qE "$pattern"; then
        matched="true"
        break
      fi
    done < "$whitelist_file"

    if [ "$matched" = "false" ]; then
      all_allowed="false"
      bad_segment="$seg_trim"
      break
    fi
  done <<EOF
$segments
EOF

  if [ "$all_allowed" = "false" ]; then
    local reason
    reason=$(printf '[Bash 委譲ルール] 未承認コマンド: %q\n\nメインエージェントは Bash 実行が原則禁止。承認済 prefix は %s を参照。\n\n【次のアクション】\n1. Agent tool で subagent を起動 (run_in_background: true 必須) — subagent は本ルール対象外\n2. その subagent に本コマンドを委譲\n3. TaskCreate でタスク登録\n\nBash deny / whitelist 不在 / 委譲ガード block は loop 停止理由にしないこと (development-process.md §5)。\n\n**whitelist 1 行追加が妥当な場合の申請手順 (subagent 委譲を試した上で user 検討):**\n1. .claude/bash-whitelist-requests/YYYY-MM-DD-<slug>.md を REQUEST_TEMPLATE.md に従い作成\n2. user 承認 → %s に追記' "$bad_segment" "$HC_BASH_WHITELIST_PATH" "$HC_BASH_WHITELIST_PATH")
    jq -n --arg r "$reason" '{decision:"block", reason:$r}'
    exit 0
  fi

  # --- ホワイトリスト通過後も path 検査は維持 ---
  # 例: `git diff src/foo.ts` は git は許可されているが src/ 直接 inspect は禁止
  # ただし PATH-AWARE セクションのコマンド (git/npm run/pnpm/yarn/vercel/supabase/gh など)
  # の引数として src/ を扱うのは許可 (これらは本来の用途として src を指すのが普通のため)
  #
  # === W1.2: PATH-AWARE 例外リストを bash-whitelist.txt から動的生成 ===
  # whitelist の `# === PATH-AWARE ===` セクション内の正規表現から literal prefix を抽出。
  # 例: `^git (status|...)` -> `git`、`^npm run( |$)` -> `npm run`
  local exempt_prefixes
  exempt_prefixes=$(awk '
    /^# === PATH-AWARE ===/ { active=1; next }
    /^# === [A-Z]/ { if (active) { active=0 } }
    active && /^\^/ {
      s = substr($0, 2)
      n = length(s)
      end = n + 1
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "(" || c == "\\" || c == "*" || c == "$" || c == "[" || c == "?" || c == "+" || c == "{" || c == "|") {
          end = i
          break
        }
      }
      prefix = substr(s, 1, end - 1)
      sub(/[[:space:]]+$/, "", prefix)
      if (prefix != "") print prefix
    }
  ' "$whitelist_file")

  local is_exempt="false"
  local prefix
  while IFS= read -r prefix; do
    [ -z "$prefix" ] && continue
    case "$cmd" in
      "$prefix"|"$prefix "*)
        is_exempt="true"
        break
        ;;
    esac
  done <<EOF
$exempt_prefixes
EOF

  if [ "$is_exempt" = "false" ]; then
    # path-leak guard: 「プロジェクトルート直下の保護パス」のみ block。
    # 区切り文字に `/` を含めると `.claude/scripts/` のような harness 内部パスまで
    # 誤検知するため、空白 / `=` / `$` / `(` のみを許容する。
    # 検査対象 path 群は HC_PROTECTED_LEAK_REGEX (例: "src|tests|scripts")。
    if printf '%s' "$cmd" | grep -qE "(^|[[:space:]=\$\(])(${HC_PROTECTED_LEAK_REGEX})/"; then
      jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
        '{decision:"block", reason:("[サブエージェント委譲ルール] Bash で " + $d + " のファイルを直接 read/edit/inspect できません。Agent tool でサブエージェントに委譲してください。" + $f)}'
      exit 0
    fi
  fi
}
