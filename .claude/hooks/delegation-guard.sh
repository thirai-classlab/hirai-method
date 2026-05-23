#!/usr/bin/env bash
# サブエージェント委譲ルール: メインエージェントは保護パス (既定 src/ tests/ scripts/) を直接操作できない。
# 保護パスのリスト・whitelist 位置・タスク管理 path 等は `.claude/harness-config.yml` で集中管理。
# Bash は原則禁止。`.claude/bash-whitelist.txt` に登録された prefix のみ実行可能。
# 申請フローは `.claude/bash-whitelist-requests/REQUEST_TEMPLATE.md` 参照。
#
# stdin から PreToolUse JSON を受け取り、stdout に hook 応答を返す。
# 引数: $1 = tool name (Edit|Write|Read|Grep|Glob|Bash)
#
# === サブエージェント検出 (多段フォールバック) ===
# Claude Code のバージョンにより subagent 識別フィールドが異なる/未提供のため、
# 以下を順に評価し、いずれかが立っていれば「サブエージェント実行中」と判定する。
#
# 1. 環境変数 CLAUDE_HARNESS_ROLE=subagent (user / Agent tool が明示)
# 2. 入力 JSON のいずれか: agent_type / subagent_type / parent_tool_use_id / agent_id
# 3. ${HC_AGENT_MARKER_DIR}/*.lock の存在 (PreToolUse:Agent hook が書き出す)
#
# デバッグ時は CLAUDE_HOOK_DEBUG=1 で /tmp/claude-hook-debug.log に入力 JSON を残す。

set -u

# config 読み込み (HC_* 変数 export)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"
# bypass logger (log_bypass 関数を提供)
# shellcheck source=lib/bypass-logger.sh
source "$(dirname "$0")/lib/bypass-logger.sh"

input=$(cat)
tool="${1:-}"

# task-22 W2: jq 不在環境では fail-open (hook 機能停止して継続)
# delegation-guard.sh は jq に重度依存 (16 箇所) のため、不在で crash する前に exit 0
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# --- debug ---
if [ "${CLAUDE_HOOK_DEBUG:-}" = "1" ]; then
  printf '[%s] tool=%s\n%s\n---\n' "$(date +%FT%T)" "$tool" "$input" \
    >> /tmp/claude-hook-debug.log
fi

# --- subagent detection ---
is_subagent="false"

if [ "${CLAUDE_HARNESS_ROLE:-}" = "subagent" ]; then
  is_subagent="true"
fi

if [ "$is_subagent" = "false" ]; then
  for field in agent_type subagent_type parent_tool_use_id agent_id; do
    v=$(printf '%s' "$input" | jq -r ".${field} // empty" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" != "null" ]; then
      is_subagent="true"
      break
    fi
  done
fi

if [ "$is_subagent" = "false" ] && [ -d "$HC_AGENT_MARKER_DIR" ]; then
  if ls "$HC_AGENT_MARKER_DIR"/*.lock >/dev/null 2>&1; then
    is_subagent="true"
  fi
fi

if [ "$is_subagent" = "true" ]; then
  echo '{}'
  exit 0
fi

# --- main agent path enforcement ---
# Bash deny / 委譲ガード block を受けた際の必須アクション (development-process.md §5)。
# 全 block message に共通フッタとして付与する。
reflex_footer=$'\n\n【次のアクション】\n1. Agent tool で subagent を起動 (run_in_background: true 必須)\n2. その subagent に本作業を委譲\n3. TaskCreate でタスク登録\n\nBash deny / whitelist 不在 / 委譲ガード block は loop 停止理由にしないこと (development-process.md §5)。'

# メッセージは harness-config.yml の protected_paths を反映 (例: "src/ tests/ scripts/")
block_path_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " を直接操作できません。Agent tool でサブエージェントに委譲してください。" + $f)}')
block_read_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " のファイルを直接読み取れません。Agent tool(Explore等)でサブエージェントに調査を委譲してください。" + $f)}')
block_search_msg=$(jq -nc --arg d "$HC_PROTECTED_DISPLAY" --arg f "$reflex_footer" \
  '{decision:"block", reason:("[サブエージェント委譲ルール] メインエージェントは " + $d + " を直接検索できません。Agent tool(Explore等)でサブエージェントに調査を委譲してください。" + $f)}')

# protected paths を case パターンに展開 (HC_PROTECTED_GLOB_FILE / HC_PROTECTED_GLOB_DIR)
# task 配下の絶対 path 部分一致パターン
task_glob="*/${HC_TASK_DIR}/*"

case "$tool" in
  Edit|Write)
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
    # protected_paths 判定 (動的 case eval)
    if [ -n "$f" ]; then
      eval "case \"\$f\" in $HC_PROTECTED_GLOB_FILE) echo \"\$block_path_msg\"; exit 0 ;; esac"

      # === task-26 W2: コード実装の保護パス (.claude/hooks/ .claude/skills/ .claude/scripts/) ===
      # メインからの code 実装直接編集を block し、Agent tool で subagent 委譲を強制する。
      # 判定: file_path が HC_PROTECTED_PATHS_CODE 配下 (部分一致) かつ
      #       拡張子が HC_CODE_FILE_EXTENSIONS のいずれかに該当
      # bypass: ECC_ALLOW_MAIN_CODE_EDIT=1 (1 セッション、bypass.log 記録)
      # 設計起源: docs/draft/delegation-code-enforcement.md W1+W2
      _code_block="false"
      _matched_code_path=""
      _matched_ext=""
      for _cp in $HC_PROTECTED_PATHS_CODE; do
        [ -z "$_cp" ] && continue
        case "$f" in
          */${_cp}/*|"${_cp}"/*)
            _ext="${f##*.}"
            # 拡張子が file 名と等しい (= ドットなし) なら skip
            if [ "$_ext" = "$f" ]; then
              continue
            fi
            for _ve in $HC_CODE_FILE_EXTENSIONS; do
              [ -z "$_ve" ] && continue
              if [ "$_ext" = "$_ve" ]; then
                _code_block="true"
                _matched_code_path="$_cp"
                _matched_ext="$_ext"
                break 2
              fi
            done
            ;;
        esac
      done

      if [ "$_code_block" = "true" ]; then
        if [ "${ECC_ALLOW_MAIN_CODE_EDIT:-}" = "1" ]; then
          # bypass 経路: bypass.log に記録して通過
          log_bypass "delegation-guard-code" "ECC_ALLOW_MAIN_CODE_EDIT" "main edit on $f ($_matched_code_path/*.$_matched_ext)"
          # context 注入だけ行い通過
          jq -nc --arg p "$f" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[code 保護 bypass] " + $p + " のメイン直接編集を ECC_ALLOW_MAIN_CODE_EDIT=1 で許可。bypass.log に記録済。")}}'
          exit 0
        fi
        _code_reason=$(printf '[サブエージェント委譲ルール / code 保護] .claude/hooks/ .claude/skills/ .claude/scripts/ 配下の code 実装はメイン直接編集禁止。Agent tool で subagent に委譲してください (staging 戦略: /tmp に Write → mv で install → chmod +x)。\n\n対象 file: %s\n一致 path: %s\n一致拡張子: %s\n\n【次のアクション】\n1. Agent tool で subagent を起動 (run_in_background: true 必須)\n2. その subagent に本作業を委譲 (staging 戦略を prompt に明記)\n3. TaskCreate でタスク登録\n\n緊急 bypass (1 セッション): export ECC_ALLOW_MAIN_CODE_EDIT=1 (.claude/.workflow-state/bypass.log に記録される)\n\n設計起源: docs/draft/delegation-code-enforcement.md' "$f" "$_matched_code_path" "$_matched_ext")
        jq -n --arg r "$_code_reason" '{decision:"block", reason:$r}'
        exit 0
      fi

      case "$f" in
        $task_glob)
          root="${f%/${HC_TASK_DIR}/*}"
          if [ "$tool" = "Write" ]; then
            if ls "$root/$HC_DRAFT_DIR/"*.md 1>/dev/null 2>&1; then
              jq -nc --arg t "$HC_TASK_DIR" --arg d "$HC_DRAFT_DIR" \
                '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[タスク管理ルール] " + $t + "/ に新規ファイル作成。設計(" + $d + "/)→承認→タスク追加のフローを遵守すること。list.md と個別ファイルと設計をセットで更新。")}}'
            else
              jq -nc --arg t "$HC_TASK_DIR" --arg d "$HC_DRAFT_DIR" \
                '{decision:"block", reason:($t + "/ への新規タスクファイル追加には " + $d + "/ に設計ドキュメントが必要です。先に設計を作成し、承認を得てください。")}'
            fi
          else
            jq -nc --arg t "$HC_TASK_DIR" --arg d "$HC_DRAFT_DIR" \
              '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[タスク管理ルール] " + $t + "/ の既存ファイルを編集中。新規タスク追加の場合は " + $d + "/ に設計を用意すること。既存タスクのステータス同期は OK。")}}'
          fi
          exit 0
          ;;
      esac
    fi
    ;;
  Read)
    f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
    if [ -n "$f" ]; then
      eval "case \"\$f\" in $HC_PROTECTED_GLOB_FILE) echo \"\$block_read_msg\"; exit 0 ;; esac"
    fi
    ;;
  Grep|Glob)
    p=$(printf '%s' "$input" | jq -r '.tool_input.path // empty')
    if [ -n "$p" ]; then
      eval "case \"\$p\" in $HC_PROTECTED_GLOB_DIR) echo \"\$block_search_msg\"; exit 0 ;; esac"
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')

    # --- inline env-var override 検出 (Hook バイパス封じ) ---
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:];&|])CLAUDE_(ALLOW_MAIN_PUSH|HARNESS_ROLE)='; then
      echo '{"decision":"block","reason":"[ハーネス保全] コマンド内に CLAUDE_ALLOW_MAIN_PUSH= / CLAUDE_HARNESS_ROLE= の inline 設定が含まれています。Hook のバイパスは禁止。承認が必要なら user に申請してください。"}'
      exit 0
    fi

    # --- git destructive deny (常時、Normal/Loop 両モード共通) ---
    # 破壊的 git 操作は user 明示承認なしに実行禁止 (data loss / history rewrite 不可逆)。
    # 設計起源: 2026-05-18 user 指示「mainAgentでgitコマンドは基本的(破壊的変更以外)に実行できるようにしてください」。
    # bypass: ECC_ALLOW_DESTRUCTIVE_GIT=1 (1 セッション)。
    if [ "${ECC_ALLOW_DESTRUCTIVE_GIT:-}" != "1" ]; then
      git_destructive_re='^git[[:space:]]+([^|;&]*[[:space:]])?('
      git_destructive_re="${git_destructive_re}push[[:space:]]+[^|;&]*--force"
      # Note: `-f` の検出は intervening args の有無を optional group で許容
      # (旧 regex `[^|;&]*[[:space:]]-f` は effectively 2-space required で
      # `git push -f` single-space を取りこぼした、`.claude/tests/git-destructive-deny-smoke.sh`
      # で発見、2026-05-18 修正)。
      git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?-f([[:space:]]|$)"
      git_destructive_re="${git_destructive_re}|reset[[:space:]]+([^|;&]*[[:space:]])?--hard"
      git_destructive_re="${git_destructive_re}|branch[[:space:]]+([^|;&]*[[:space:]])?-D"
      git_destructive_re="${git_destructive_re}|clean[[:space:]]+-[A-Za-z]*f"
      git_destructive_re="${git_destructive_re}|checkout[[:space:]]+--[[:space:]]"
      git_destructive_re="${git_destructive_re}|restore[[:space:]]+([^|;&]*[[:space:]])?(--worktree|--source)"
      git_destructive_re="${git_destructive_re}|stash[[:space:]]+(drop|clear)"
      git_destructive_re="${git_destructive_re}|tag[[:space:]]+([^|;&]*[[:space:]])?-[df]([[:space:]]|$)"
      git_destructive_re="${git_destructive_re}|reflog[[:space:]]+expire"
      git_destructive_re="${git_destructive_re}|gc[[:space:]]+--prune=now"
      git_destructive_re="${git_destructive_re})"

      if printf '%s' "$cmd" | grep -qE "$git_destructive_re"; then
        destructive_reason=$(printf '[git destructive guard] 破壊的 git 操作は禁止: %s\n\n破壊的操作の例:\n  - push --force / push -f (force push)\n  - reset --hard (history 破壊)\n  - branch -D <name> (force delete)\n  - clean -f / -fd / -fdx (untracked 削除)\n  - checkout -- <file> (file 復元)\n  - restore --worktree|--source (file 復元)\n  - stash drop|clear (stash 破壊)\n  - tag -d|-f (tag 削除/上書き)\n  - reflog expire (reflog 破壊)\n  - gc --prune=now (orphan commit gc)\n\nbypass (1 セッション): export ECC_ALLOW_DESTRUCTIVE_GIT=1\n\n設計起源: 2026-05-18 user 指示「mainAgentでgitコマンドは基本的(破壊的変更以外)に実行できるようにしてください」' "$cmd")
        jq -n --arg r "$destructive_reason" '{decision:"block", reason:$r}'
        exit 0
      fi
    fi

    # --- protected branch push deny (常時、Normal/Loop 両モード共通) ---
    # main / stg を含む branch への push は user 明示承認なしに禁止
    # (production-bound branch への暴発防止、レビュー未通過コードの production / staging 伝搬防止)。
    # 設計起源: 2026-05-18 user 指示「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」。
    # bypass: ECC_ALLOW_PROTECTED_BRANCH_PUSH=1 (1 セッション)。
    #
    # 検知パターン:
    #   1. 明示 refspec: `git push origin main` / `git push -u origin release/stg-prod` /
    #                    `git push origin HEAD:main` / `git push origin feat:refs/heads/stg-v1`
    #   2. refspec 省略: `git push` / `git push origin` (current branch を git rev-parse で解決し判定)
    #
    # 判定基準: refspec の dst basename が
    #   - `main` 完全一致 → block
    #   - `*stg*` 部分一致 → block (例: stg, stg-v1, release/stg-prod, feature/stg-test)
    if [ "${ECC_ALLOW_PROTECTED_BRANCH_PUSH:-}" != "1" ] && \
       printf '%s' "$cmd" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
      push_args=$(printf '%s' "$cmd" | sed -E 's|^git[[:space:]]+push[[:space:]]*||')
      protected_violation=""
      non_opt_token_count=0

      # shellcheck disable=SC2086
      for token in $push_args; do
        # option (--xxx, -x) は skip
        case "$token" in
          -*) continue ;;
        esac
        non_opt_token_count=$((non_opt_token_count + 1))

        # 最初の non-opt token は remote 名 (例: origin) なので skip
        if [ "$non_opt_token_count" -eq 1 ]; then
          continue
        fi

        # refspec 形式 `src:dst` なら dst を取る、それ以外はそのまま
        case "$token" in
          *:*) dst_part="${token##*:}" ;;
          *) dst_part="$token" ;;
        esac
        # `refs/heads/main` 等は basename を抽出
        dst_basename="${dst_part##*/}"
        # 先頭の + (force push の別形式、destructive deny で別途 catch されるが念のため除去)
        dst_basename="${dst_basename#+}"

        if [ "$dst_basename" = "main" ]; then
          protected_violation="$token (refspec dst = main)"
          break
        fi
        case "$dst_basename" in
          *stg*)
            protected_violation="$token (refspec dst '$dst_basename' contains 'stg')"
            break
            ;;
        esac
      done

      # refspec 省略 (`git push` / `git push <remote>` only) の場合は current branch を確認
      if [ -z "$protected_violation" ] && [ "$non_opt_token_count" -le 1 ]; then
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ "$current_branch" = "main" ]; then
          protected_violation="(no refspec) current branch = main"
        else
          case "$current_branch" in
            *stg*)
              protected_violation="(no refspec) current branch = $current_branch (contains 'stg')"
              ;;
          esac
        fi
      fi

      if [ -n "$protected_violation" ]; then
        protected_reason=$(printf '[protected branch push deny] main / stg を含む branch への push は禁止: %s\n\n違反 token: %s\n\n禁止対象 branch 例:\n  - main (完全一致)\n  - stg, stg-v1, release/stg-prod, feature/stg-test (stg を含む任意)\n\nbypass (1 セッション): export ECC_ALLOW_PROTECTED_BRANCH_PUSH=1\n\n推奨対応:\n  1. branch 切替後 push (git switch <branch> && git push -u origin <branch>)\n  2. PR 経由 (gh pr create で main / stg へは merge)\n\n設計起源: 2026-05-18 user 指示「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」' "$cmd" "$protected_violation")
        jq -n --arg r "$protected_reason" '{decision:"block", reason:$r}'
        exit 0
      fi
    fi

    # --- ホワイトリスト判定 ---
    # bash-whitelist の各行を正規表現として「コマンド先頭」でマッチさせる。
    # パイプ/&&/;/|| の連結を含む場合は最初のセグメントを抽出して判定し、
    # 残りのセグメントもすべて allow であることを要求する。
    whitelist_file="$HC_BASH_WHITELIST_PATH"
    if [ ! -f "$whitelist_file" ]; then
      jq -nc --arg p "$HC_BASH_WHITELIST_PATH" \
        '{decision:"block", reason:("[ハーネス保全] " + $p + " が存在しません。ハーネスが破損している可能性があります。")}'
      exit 0
    fi

    # 各セグメントを抽出 (; && || | で分割)
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
    segments=$(split_command_segments "$cmd")

    all_allowed="true"
    bad_segment=""
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

    is_exempt="false"
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
    ;;
esac

echo '{}'
