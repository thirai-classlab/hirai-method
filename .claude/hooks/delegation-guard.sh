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

input=$(cat)
tool="${1:-}"

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
    # heredoc 本文 (<<EOF ... EOF) は単行解析の限界で未対応 (B フル parser 化で将来対応)。
    # 検証: .claude/tests/delegation-guard-segment-smoke.sh Case 1-6
    split_command_segments() (
      set -uo pipefail
      printf '%s' "$1" | awk '
        {
          cmd = $0
          out = ""
          i = 1
          in_single = 0
          in_double = 0
          escape = 0
          n = length(cmd)
          while (i <= n) {
            c = substr(cmd, i, 1)
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
