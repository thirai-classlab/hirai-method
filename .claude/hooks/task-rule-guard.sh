#!/usr/bin/env bash
# task-rule-guard.sh — Task Management 強制 hook
#
# 役割:
#   delegation-guard.sh の弱い「draft が 1 つでもあれば通す」判定を補強し、
#   下記 4 ルールを Hook block で強制する:
#
#   1. ID 重複検知:
#      task-<id>-*.md / phase-<id>-*.md と同じ <id> が既存なら block
#   2. 対応 draft 名一致:
#      task-<id>-<slug>.md の Write は docs/draft/{<slug>.md, task-<slug>.md, <basename>} の
#      いずれかが存在することを要求
#   3. parking-lot.md 必須 7 項目（追加時のみ警告レベル）
#   4. テンプレ章立て（_TASK_TEMPLATE.md 準拠）— additionalContext 注入のみ
#
# Args: $1 = tool name (Edit|Write) — JSON tool_name 優先
# Stdin: PreToolUse JSON
#
# Bypass:
#   ECC_TASKGUARD=off                       # 全 OFF
#   /task-bypass <slug>                     # 1 ファイル分 pre-clear
#   ${taskguard_state_dir}/<slug>.cleared   # 上記の実体
#
# Subagent passthrough: delegation-guard と同じ多段検出。
#
# Config keys consumed (.claude/harness-config.yml):
#   task_dir / draft_dir       # 判定対象ディレクトリ
#   taskguard_state_dir        # bypass marker 保存場所
#   agent_marker_dir           # subagent passthrough 検出

set -u

# config 読み込み (HC_* 変数 export)
# shellcheck source=lib/config-loader.sh
source "$(dirname "$0")/lib/config-loader.sh"

# Phase β: F2 disable for SWE-bench grid evaluation (fail-open)
# ECC_F{1,2,3}_OFF env vars allow runner.py to bypass gates per-task
# while measuring gate effectiveness. Production usage MUST NOT set these.
if [ "${ECC_F2_OFF:-0}" = "1" ] || [ "${ECC_F2_OFF:-}" = "true" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -n '{decision:"approve", reason:"F2 (task-rule-guard) disabled via ECC_F2_OFF"}'
  else
    printf '{"decision":"approve","reason":"F2 (task-rule-guard) disabled via ECC_F2_OFF"}\n'
  fi
  exit 0
fi

# === 全 bypass ===
if [ "${ECC_TASKGUARD:-}" = "off" ]; then
  echo '{}'
  exit 0
fi

input=$(cat)

# === jq 必須 ===
if ! command -v jq >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

# === tool 取得 ===
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
if [ -z "$tool" ] || [ "$tool" = "null" ]; then
  tool="${1:-}"
fi

# === Edit / Write 以外は素通し ===
if [ "$tool" != "Edit" ] && [ "$tool" != "Write" ]; then
  echo '{}'
  exit 0
fi

# === subagent passthrough ===
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

# === target file 取得 ===
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
if [ -z "$file" ]; then
  echo '{}'
  exit 0
fi

# === ${draft_dir}/ 配下の Write は plan-first warn 判定 (block しない、honor system) ===
# task-33 Phase 3 規範化 (list-md-plan-first-normative.md §3 P5、task-36 Step 1 / Step 2):
#   新規 draft Write が発生した時点で list.md に対応 slug の 📝 行が不在なら warn 注入。
#   既存 task_glob filter (L下) より前に挿入する必要あり (filter で early-exit するため)。
#
# task-36 Step 2 iter2 fix:
#   F1: Write 限定 (Edit は素通り) — draft の既存 update 時に warn を出さない
#   F2: slug grep を col 限定 (awk) に変更 — 別 task の description/detail に slug が含まれる
#       false negative (warn 抑制) を防ぐ。false positive は許容。
#
# task-36 Step 2 iter3 fix:
#   F7: awk col 拡張 (MED-2、reviewer C) — 実 list.md 6 列 format
#       `| # | Status | Task | 概要 | 依存 | 詳細 |` (awk NF=8、$4=Task / $5=概要 / $6=依存 / $7=詳細)
#       で slug link が col 7 にある false negative を解消。概要列 ($5) のみ除外して
#       行全体で slug index 検索 (false positive 回避 + 5 列/6 列 両 format サポート)。
draft_glob_a="*/${HC_DRAFT_DIR}/*.md"
draft_glob_b="*/${HC_DRAFT_DIR}/*.mdx"
# shellcheck disable=SC2254  # 意図的な glob 展開 (case pattern として draft path 判定)
case "$file" in
  $draft_glob_a|$draft_glob_b)
    # F1: Write のみ判定 (Edit は素通り、既存 draft update に warn 不要)
    if [ "$tool" != "Write" ]; then
      echo '{}'
      exit 0
    fi
    # template (_DRAFT_TEMPLATE.md 等の underscore prefix) は exempt
    draft_basename=$(basename "$file")
    case "$draft_basename" in
      _*) echo '{}'; exit 0 ;;
    esac
    # slug 抽出 (basename から .md / .mdx を除去)
    draft_slug="${draft_basename%.md}"
    draft_slug="${draft_slug%.mdx}"
    # list.md path 算出 (draft path から root 推定)
    # shellcheck disable=SC2295  # 意図的: HC_DRAFT_DIR は literal path、glob 文字含まない前提
    draft_root="${file%/${HC_DRAFT_DIR}/*}"
    list_md_path="${draft_root}/${HC_TASK_DIR}/list.md"
    # list.md 不在なら silent pass (init 未完了)
    if [ ! -f "$list_md_path" ]; then
      echo '{}'
      exit 0
    fi
    # F7 (iter3): 📝 行検出を「概要列 ($5) のみ除外 + 行全体 index 検索」に変更
    # 対応する list.md 列構成:
    #   5 列 format (規範): | # | Status | Task | 概要 | 詳細 |              awk NF=7、$5=概要、slug link は $6
    #   6 列 format (実 list.md): | # | Status | Task | 概要 | 依存 | 詳細 | awk NF=8、$5=概要、slug link は $7
    #   将来 7 列拡張時も $5 概要列のみ除外 + 残列で検索 で対応可
    # false positive 回避: 概要列に偶然 slug substring が含まれるケースは $5 を空文字に置換して除外
    # awk 変数 injection 防止: draft_slug は basename 由来で英数字 + `.` + `-` のみ (kebab-case)、index() は literal 比較で安全
    # [OFS rewrite 副作用の設計メモ]
    # `$5 = ""` を実行すると awk は $0 を OFS (default: 空白) で再構築するため、
    # `|` 区切りが空白に置換される。ただし index($0, slug) は literal 文字列比較であり、
    # slug は kebab-case (英数字+ハイフンのみ) で空白を含まないため、誤検知ゼロで安全。
    # 5列 / 6列 / 7列 format 進化耐性のため列番号非依存設計。
    if awk -F'|' -v slug="$draft_slug" '
      $3 !~ /📝/ { next }
      {
        $5 = ""  # 概要列除外 ($0 が OFS=空白で再構築されるが index() slug 検出には影響なし)
        if (index($0, slug) > 0) { found = 1; exit }
      }
      END { exit (found ? 0 : 1) }
    ' "$list_md_path" 2>/dev/null; then
      # 既存 📝 行あり → pass (warn なし)
      echo '{}'
      exit 0
    fi
    # 📝 行不在 → warn 注入 (block しない)
    warn_msg="[task-rule-guard] 新規 draft '${draft_basename}' を Write 中ですが、list.md に対応 slug '${draft_slug}' の 📝 行が見当たりません。

batch planning (経路 B、N ≥ 3 task の一括計画) の場合は、先に list.md に 📝 行を先置きしてください。
単発 task (経路 A) なら本 warn は無視可。

詳細: .claude/rules/task-management.md §plan-first 行先置きフロー (batch planning)"
    jq -n --arg m "$warn_msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
    exit 0
    ;;
esac

# === ${task_dir}/ 配下のみ判定対象（${draft_dir}/ は通過） ===
task_glob="*/${HC_TASK_DIR}/*"
case "$file" in
  $task_glob) ;;
  *) echo '{}'; exit 0;;
esac

basename=$(basename "$file")
root="${file%/${HC_TASK_DIR}/*}"

# === index / template ファイルは exempt ===
case "$basename" in
  list.md|parking-lot.md|_TASK_TEMPLATE.md)
    # parking-lot.md の追加時に必須項目 hint を注入
    if [ "$basename" = "parking-lot.md" ] && [ "$tool" = "Edit" ]; then
      jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"[task-rule-guard] parking-lot.md 編集中。新規エントリは必須 7 項目（起案日 / 保留日 / 保留理由 / 設計書 / 実装状態 / 再検討トリガー / 代替現状）と ステータス（🧊 / 🔍 / ❌）を含めること。"}}'
      exit 0
    fi
    echo '{}'
    exit 0
    ;;
esac

# === slug 単位 bypass marker ===
mkdir -p "$HC_TASKGUARD_STATE_DIR" 2>/dev/null
slug_guess=$(printf '%s' "$basename" | sed -E 's/^(task|phase)-[A-Za-z0-9.]+-(.+)\.md$/\2/' )
if [ -f "${HC_TASKGUARD_STATE_DIR}/${slug_guess}.cleared" ]; then
  echo '{}'
  exit 0
fi

# === 命名規約判定 ===
# task-<id>-<slug>.md  または  phase-<id>-<slug>.md  のみ厳格 check
if ! printf '%s' "$basename" | grep -qE '^(task|phase)-[A-Za-z0-9.]+-.+\.md$'; then
  # 命名規約外 — 警告のみ
  jq -n --arg f "$basename" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[task-rule-guard] " + $f + " は task-<id>-<slug>.md / phase-<id>-<slug>.md 規約から外れています。意図的なら続行可、ただし list.md との対応を確認すること。")}}'
  exit 0
fi

prefix=$(printf '%s' "$basename" | sed -E 's/^(task|phase)-.*$/\1/')
id=$(printf '%s' "$basename" | sed -E 's/^(task|phase)-([A-Za-z0-9.]+)-.+\.md$/\2/')
slug=$(printf '%s' "$basename" | sed -E 's/^(task|phase)-[A-Za-z0-9.]+-(.+)\.md$/\2/')

# === Edit（既存編集）は status 同期注意のみ ===
if [ "$tool" = "Edit" ]; then
  jq -n --arg id "$id" --arg t "$HC_TASK_DIR" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[task-rule-guard] 既存タスク #" + $id + " を編集中。" + $t + "/list.md の同 ID 行と必ず同期更新すること。")}}'
  exit 0
fi

# === Write 時の厳格 check ===

# (1) ID 重複検知
shopt -s nullglob 2>/dev/null
existing=()
for f in "${root}/${HC_TASK_DIR}/${prefix}-${id}-"*.md; do
  [ -f "$f" ] || continue
  if [ "$f" != "$file" ]; then
    existing+=("$f")
  fi
done

if [ ${#existing[@]} -gt 0 ]; then
  list=$(printf '  - %s\n' "${existing[@]}")
  reason="[task-rule-guard] BLOCK: ID '${id}' の ${prefix}-* ファイルが既に存在します:
${list}
別 ID を割り当てるか、既存ファイルを Edit してください。
重複作成すると list.md との対応が壊れます。

Bypass: ECC_TASKGUARD=off / ${HC_TASKGUARD_STATE_DIR}/${slug}.cleared を touch"
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

# (2) 対応 draft 名一致 check
draft_dir="${root}/${HC_DRAFT_DIR}"
matched_draft=""
for candidate in "${slug}.md" "task-${slug}.md" "${basename}"; do
  if [ -f "${draft_dir}/${candidate}" ]; then
    matched_draft="${draft_dir}/${candidate}"
    break
  fi
done

if [ -z "$matched_draft" ]; then
  reason="[task-rule-guard] BLOCK: 対応する設計 draft が見つかりません。

期待される draft path（いずれか）:
  - ${draft_dir}/${slug}.md
  - ${draft_dir}/task-${slug}.md
  - ${draft_dir}/${basename}

設計→承認→タスク化フローを守ってください:
  1. /new-draft ${slug}             # 設計 draft 起こし
  2. <内容を埋めて user に承認依頼>
  3. /new-task ${id} ${slug}        # 承認後にタスク化

例外（hot fix 等）:
  - ECC_TASKGUARD=off               # 全 OFF
  - touch ${HC_TASKGUARD_STATE_DIR}/${slug}.cleared    # 1 ファイル分 bypass"
  jq -n --arg r "$reason" '{decision:"block", reason:$r}'
  exit 0
fi

# (3) Pass — list.md 同時更新の念押し
jq -n --arg d "$(basename "$matched_draft")" --arg id "$id" --arg t "$HC_TASK_DIR" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:("[task-rule-guard] OK: draft 一致 (" + $d + ")。次は " + $t + "/list.md に #" + $id + " 行を追加すること。片方のみ更新は禁止。")}}'
exit 0
