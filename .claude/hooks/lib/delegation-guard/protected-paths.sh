#!/usr/bin/env bash
# protected-paths.sh — Edit/Write/Read/Grep/Glob の保護パス判定 + code 配下判定
#
# 提供関数:
#   handle_edit_write <input> <tool>   — Edit/Write 経路の判定 (保護パス / code 保護 / task 配下)
#   handle_read <input>                — Read 経路の判定 (保護パス read)
#   handle_search <input>              — Grep/Glob 経路の判定 (保護パス search)
#
# caller (orchestrator) が事前に export 必須:
#   reflex_footer / block_path_msg / block_read_msg / block_search_msg / task_glob

handle_edit_write() {
  local input="$1"
  local tool="$2"
  local f
  f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
  [ -z "$f" ] && return 1

  # protected_paths 判定 (動的 case eval)
  eval "case \"\$f\" in $HC_PROTECTED_GLOB_FILE) echo \"\$block_path_msg\"; exit 0 ;; esac"

  # === task-26 W2: コード実装の保護パス (.claude/hooks/ .claude/skills/ .claude/scripts/) ===
  # メインからの code 実装直接編集を block し、Agent tool で subagent 委譲を強制する。
  # 判定: file_path が HC_PROTECTED_PATHS_CODE 配下 (部分一致) かつ
  #       拡張子が HC_CODE_FILE_EXTENSIONS のいずれかに該当
  # bypass: ECC_ALLOW_MAIN_CODE_EDIT=1 (1 セッション、bypass.log 記録)
  # 設計起源: docs/draft/delegation-code-enforcement.md W1+W2
  local _code_block="false"
  local _matched_code_path=""
  local _matched_ext=""
  local _cp _ext _ve
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
    local _code_reason
    _code_reason=$(printf '[サブエージェント委譲ルール / code 保護] .claude/hooks/ .claude/skills/ .claude/scripts/ 配下の code 実装はメイン直接編集禁止。Agent tool で subagent に委譲してください (staging 戦略: /tmp に Write → mv で install → chmod +x)。\n\n対象 file: %s\n一致 path: %s\n一致拡張子: %s\n\n【次のアクション】\n1. Agent tool で subagent を起動 (run_in_background: true 必須)\n2. その subagent に本作業を委譲 (staging 戦略を prompt に明記)\n3. TaskCreate でタスク登録\n\n緊急 bypass (1 セッション): export ECC_ALLOW_MAIN_CODE_EDIT=1 (.claude/.workflow-state/bypass.log に記録される)\n\n設計起源: docs/draft/delegation-code-enforcement.md' "$f" "$_matched_code_path" "$_matched_ext")
    jq -n --arg r "$_code_reason" '{decision:"block", reason:$r}'
    exit 0
  fi

  case "$f" in
    $task_glob)
      local root="${f%/${HC_TASK_DIR}/*}"
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
}

handle_read() {
  local input="$1"
  local f
  f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
  if [ -n "$f" ]; then
    eval "case \"\$f\" in $HC_PROTECTED_GLOB_FILE) echo \"\$block_read_msg\"; exit 0 ;; esac"
  fi
}

handle_search() {
  local input="$1"
  local p
  p=$(printf '%s' "$input" | jq -r '.tool_input.path // empty')
  if [ -n "$p" ]; then
    eval "case \"\$p\" in $HC_PROTECTED_GLOB_DIR) echo \"\$block_search_msg\"; exit 0 ;; esac"
  fi
}
