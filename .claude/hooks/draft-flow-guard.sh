#!/usr/bin/env bash
# draft-flow-guard.sh — PreToolUse Edit/Write hook
#
# 役割:
#   docs/ 直下 (docs/draft/ や docs/tasks/ 配下ではない直接子) への
#   **新規** 設計文書 Write を BLOCK。対応する docs/draft/<basename>.md が
#   存在する場合のみ通過させる。既存 file の Edit は無条件通過 (file 更新
#   を妨げない)。task-rule-guard.sh の鏡像版で、対象 path が docs/ 直下に
#   限定される。
#
#   task-40 拡張 (2026-05-26):
#     .claude/rules/*.md / .claude/commands/*.md / .claude/templates/docs/**/*.md
#     への新規 Write も block 対象に追加。対応 draft が存在し
#     frontmatter (HTML comment 内) で `approved_at:` が非空 (or
#     `retroactive: true`) なら pass。
#
#   task-40 Step 7 iter2 (2026-05-26) — HIGH 4 件 fix:
#     HIGH-A: bypass.log 記録追加 (audit trail)
#     HIGH-C: retroactive case の悪用検知 (bypass.log 記録 + JSON additionalContext で注意喚起)
#     HIGH-D: file_path canonical 化 (../ / symlink 経由 BLOCK 回避を防止)
#     HIGH-G: .claude/templates/** → .claude/templates/docs/** に縮小 (top-level 直下は対象外)
#
#   task-40 Step 7 iter3 (2026-05-26) — HIGH 4 + MEDIUM 2 + LOW 1 fix:
#     HIGH-2 (TA-H1 + SEC-H2 + LOW-1 内包):
#       canonicalize_path に realpath -m 2nd choice + python3/realpath 両不在時の
#       fail-open warn 化 + 呼び出し後の改行 reject (injection 疑い、NUL は bash 文字列で truncate される)。
#     HIGH-3 (SEC-H1):
#       retroactive=true 単独通過を悪用防止のため、approved_by 副次条件で厳格化。
#       approved_by が空なら blocked-retroactive-no-approved-by として block。
#     HIGH-5 (ARCH-H1):
#       L236-242 の dead code (noop ブロック + 5 行コメント) を削除、1 行コメントに圧縮。
#     MEDIUM-6 (SEC-MA):
#       ECC_RULE_CHANGE_GUARD_OFF / HC_RULE_CHANGE_GUARD_ENABLED=false の log を
#       path 評価前に集中、遅延 log block を廃止 (ECC_DRAFT_FLOW_GUARD_OVERRIDE と
#       timing 整合化)。
#     MEDIUM-8 (ARCH-M2):
#       retroactive warn の stderr + JSON additionalContext 2 経路を _retro_msg
#       単一変数で DRY 化。
#
#   task-40 Step 7 iter4 (2026-05-26) — security MEDIUM 2 件 fix:
#     MEDIUM-NEW-1 (SEC-iter4):
#       extract_frontmatter_value に leading whitespace trim を追加。
#       approved_by / approved_at / retroactive の whitespace-only 値による
#       retroactive bypass を構造的に防止 (SEC-H1 完全性向上)。
#     MEDIUM-NEW-2 (SEC-iter4):
#       awk frontmatter parser の `-->` 終端を行頭アンカー (`^-->`) に限定 +
#       `next` でフラグ切替行を skip。本文中の `foo --> bar` でコメントブロック
#       誤閉鎖を防ぐ + malformed frontmatter で本文中の偽 key 行が誤マッチ
#       する逆向き risk も解消。
#
# 設計起源:
#   - docs/draft/system-reminder-attention-fix.md Wave 2.3 (2026-05-23)
#   - 観察証拠: recall_poc/docs/01-03 が draft 経由なしで docs/ 直下に
#     直接 Write された事案
#   - docs/draft/taskmanagesystem-recovery.md Q2 (task-24 W3, 2026-05-23):
#     HC_DOCS_APPROVED_DIR で承認済 dir を harness-config から override 可能化
#   - docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40, 2026-05-26):
#     .claude/rules/*.md 等の規範文書も draft 経由必須化、機械強制 BLOCK
#
# 監視対象:
#   - tool: Edit / Write
#   - path1: <root>/docs/<basename>.md (深さ 1 のみ、既存挙動)
#   - path2 (task-40): <root>/.claude/rules/<basename>.md (深さ 1)
#   - path3 (task-40): <root>/.claude/commands/<basename>.md (深さ 1)
#   - path4 (task-40, iter2 縮小): <root>/.claude/templates/docs/**/<basename>.md
#                                    (深さ 2 以上、top-level 直下は対象外)
#   - 除外: <root>/docs/draft/** / <root>/docs/tasks/** / 深さ 2 以上
#   - 除外: 既存 file の Edit (新規 Write のみ)
#   - 除外 (task-24 W3): HC_DOCS_APPROVED_DIR 配下 (CSV 複数値対応)
#                        e.g. HC_DOCS_APPROVED_DIR=design で
#                             docs/design/foo.md は深さ 2 のみ PASS
#
# bypass:
#   - 対応する <root>/docs/draft/<basename>.md を先に作る (推奨)
#   - HC_DOCS_APPROVED_DIR=<dir>[,<dir>...] を harness-config / env で設定
#   - 環境変数 ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 (一時、両 path カバー)
#   - 環境変数 ECC_RULE_CHANGE_GUARD_OFF=1 (task-40 新 path のみ skip)
#   - HC_RULE_CHANGE_GUARD_ENABLED=false (task-40 config レベル、default true)
#   - harness-config.yml の draft_flow_guard_whitelist に basename 追加
#
# 失敗時:
#   - jq 不在 / project-root 解決失敗 → fail-open (exit 0)
#   - block 時 → exit 2 + stderr で BLOCK 理由表示

set -uo pipefail

# stdin 取得 (Hook JSON)
input=$(cat 2>/dev/null || true)

# jq 不在なら fail-open
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# project root 解決 (bypass-logger は project root 解決前に呼ばないため、
# 関連 source は env bypass 判定の **前** に行う必要がある)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# bypass-logger.sh source (best-effort、HIGH-A)
# shellcheck source=lib/bypass-logger.sh
if [ -f "$script_dir/lib/bypass-logger.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/bypass-logger.sh"
fi

# ----------------------------------------------------------------------
# MEDIUM-1 (task-40 Step 7 iter3): tool_name / file_path 抽出を bypass 判定前に前倒し
# 既存挙動 preserve:
#   - jq 不在は L65 で fail-open 済 (本ブロック到達時点で jq 必ず存在)
#   - tool_name が Edit/Write 以外なら早期 exit 0 (元 L88-92 と同じ動作)
#   - file_path が空でも tool_name filter は通過 (元動作と同じ、後段の空 check に委譲)
# OVERRIDE bypass log に file_path / tool_name を含めて audit trail 完全性を向上。
# ----------------------------------------------------------------------
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

file_path_raw=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# bypass env (既存 docs/ + 新 path 両方カバー)
# HIGH-A: bypass.log 記録追加
# MEDIUM-1: file_path / tool_name を reason に含める (audit trail 完全性)
if [ "${ECC_DRAFT_FLOW_GUARD_OVERRIDE:-0}" = "1" ]; then
  if declare -f log_bypass >/dev/null 2>&1; then
    log_bypass "draft-flow-guard" "ECC_DRAFT_FLOW_GUARD_OVERRIDE" "${ECC_BYPASS_REASON:-(not provided)} tool=${tool_name} file=${file_path_raw}"
  fi
  exit 0
fi

# file_path 空 check (元 L96 と同じ、tool_name filter 通過後)
[ -z "$file_path_raw" ] && exit 0

# ----------------------------------------------------------------------
# HIGH-D + HIGH-2 (iter3): file_path canonical 化
# `..` 含み path / symlink 経由 BLOCK 回避を防止する。
# macOS portable:
#   1st: python3 os.path.realpath (file 存在不要、symlink 解決)
#   2nd (ARCH-L1): realpath -m (coreutils 系、macOS GNU coreutils 等で利用可)
#   両不在: stderr WARN 出力 + raw のまま fallback (fail-open 維持、BLOCK 回避リスク
#           を operator に通知)
# ----------------------------------------------------------------------
canonicalize_path() {
  local _p="$1"
  local _result
  if command -v python3 >/dev/null 2>&1; then
    # sys.stdout.write で末尾改行なし出力 (NUL/改行 reject 後段との整合)
    _result=$(python3 -c "import os,sys; sys.stdout.write(os.path.realpath(sys.argv[1]))" "$_p" 2>/dev/null) && {
      printf '%s' "$_result"
      return
    }
  fi
  if command -v realpath >/dev/null 2>&1; then
    # realpath -m 末尾改行は command substitution で strip される
    _result=$(realpath -m "$_p" 2>/dev/null) && {
      printf '%s' "$_result"
      return
    }
  fi
  # 両 tool 不在 → raw 返却 (fail-open 維持、stderr warn 出力)
  printf '[draft-flow-guard] WARN: python3/realpath 不在、canonical 化 skip (BLOCK 回避リスクあり)\n' >&2
  printf '%s' "$_p"
}

file_path=$(canonicalize_path "$file_path_raw")

# HIGH-2 + LOW-1 (iter3): 改行 reject (injection 疑い)
# canonical 化後の file_path に改行文字が含まれていたら BLOCK。
# 通常の file_path には絶対に現れない文字列であり、含まれている場合は意図的な
# injection / hook 回避試行の可能性が高い。
# NOTE: NUL バイトは bash 文字列に格納された時点で truncate される
#       (jq 経由で受領した時点で実質 reject 済) ため、本 case では検査せず
#       改行のみ検査する。bash 3.2 で `*$'\0'*` glob pattern は何にでもマッチする
#       bug 様挙動があるため、明示的に除外している。
case "$file_path" in
  *$'\n'*)
    printf '[draft-flow-guard] BLOCK: file_path に改行文字 (injection 疑い)\n' >&2
    exit 2
    ;;
esac

# project root 解決
# shellcheck source=lib/project-root.sh
if [ -f "$script_dir/lib/project-root.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/project-root.sh"
fi
if command -v resolve_project_root >/dev/null 2>&1; then
  root="$(resolve_project_root 2>/dev/null || pwd)"
else
  root="$(pwd)"
fi
# root も canonical 化 (path 比較の安全性確保)
root=$(canonicalize_path "$root")

# config (task_dir / draft_dir / whitelist) 読み込み
# shellcheck source=lib/config-loader.sh
if [ -f "$script_dir/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/config-loader.sh" >/dev/null 2>&1 || true
fi
task_dir="${HC_TASK_DIR:-docs/tasks}"
draft_dir="${HC_DRAFT_DIR:-docs/draft}"
whitelist_raw="${HC_DRAFT_FLOW_GUARD_WHITELIST:-}"
approved_dir_raw="${HC_DOCS_APPROVED_DIR:-}"
rule_change_guard_enabled="${HC_RULE_CHANGE_GUARD_ENABLED:-true}"

docs_root="$root/docs"

# ----------------------------------------------------------------------
# MEDIUM-6 (iter3): ECC_RULE_CHANGE_GUARD_OFF / HC_RULE_CHANGE_GUARD_ENABLED
# の log を path_match 評価前に集中 (ECC_DRAFT_FLOW_GUARD_OVERRIDE と timing 整合化)。
# 元々 new path (.claude/rules/, .claude/commands/, .claude/templates/docs/) 配下なのに
# env で skip された場合のみ記録。
# ----------------------------------------------------------------------
_is_new_path_for_log=0
case "$file_path" in
  "$root/.claude/rules/"*|"$root/.claude/commands/"*|"$root/.claude/templates/docs/"*)
    _is_new_path_for_log=1
    ;;
esac
if [ "$_is_new_path_for_log" = "1" ]; then
  if [ "${ECC_RULE_CHANGE_GUARD_OFF:-0}" = "1" ]; then
    if declare -f log_bypass >/dev/null 2>&1; then
      log_bypass "draft-flow-guard" "ECC_RULE_CHANGE_GUARD_OFF" "${ECC_BYPASS_REASON:-(not provided)} file=${file_path}"
    fi
  elif [ "$rule_change_guard_enabled" = "false" ]; then
    if declare -f log_bypass >/dev/null 2>&1; then
      log_bypass "draft-flow-guard" "HC_RULE_CHANGE_GUARD_ENABLED" "${ECC_BYPASS_REASON:-(config off)} file=${file_path}"
    fi
  fi
fi

# ----------------------------------------------------------------------
# frontmatter parser: HTML comment 内の `key: value` を抽出 (jq 不要)
# 引数 1: draft_path
# 引数 2: key (e.g. approved_at / retroactive)
# stdout: value (trim 済、不在は空文字)
#
# iter4 MEDIUM-NEW-1 + MEDIUM-NEW-2 fix:
#   - awk `-->` 終端を行頭アンカー `^-->` に限定 + `next` でフラグ切替行 skip
#     (本文中の `foo --> bar` でコメントブロック誤閉鎖を防ぐ)
#   - sed pipeline に leading whitespace trim 追加
#     (approved_by 等の whitespace-only 値による retroactive bypass を防ぐ)
# ----------------------------------------------------------------------
extract_frontmatter_value() {
  local _draft_path="$1"
  local _key="$2"
  [ -f "$_draft_path" ] || { printf ''; return 0; }
  # <!-- ... --> ブロック内の最初の `<key>:` 行を抽出
  # awk で ^<!-- → ^--> 範囲を抽出 (行頭アンカー限定) + grep で key 行 + sed で value 取得 + leading/trailing trim
  awk '/^<!--/{flag=1; next} /^-->/{flag=0; next} flag' "$_draft_path" 2>/dev/null \
    | grep -E "^[[:space:]]*${_key}:" \
    | head -1 \
    | sed -E "s/^[[:space:]]*${_key}:[[:space:]]*//" \
    | sed -E 's/^[[:space:]]+//' \
    | sed -E 's/[[:space:]]+$//'
}

# ----------------------------------------------------------------------
# draft 検証:
#   - approved_at 非空                                  → "approved"
#   - retroactive: true ∧ approved_by 非空              → "retroactive"
#   - retroactive: true ∧ approved_by 空 (HIGH-3 iter3) → "blocked-retroactive-no-approved-by"
#   - それ以外 (draft 不在 / approved_at 空)            → "blocked"
# 引数 1: slug (basename without .md)
# stdout: status
# ----------------------------------------------------------------------
verify_draft_status() {
  local _slug="$1"
  local _draft_path="$root/$draft_dir/${_slug}.md"
  if [ ! -f "$_draft_path" ]; then
    printf 'blocked'
    return 0
  fi
  local _retroactive
  _retroactive=$(extract_frontmatter_value "$_draft_path" "retroactive")
  if [ "$_retroactive" = "true" ]; then
    # HIGH-3 (iter3): retroactive=true は approved_by 副次条件で厳格化。
    # 任意 draft で `retroactive: true` だけ書く悪用を防ぐ。
    # iter4 MEDIUM-NEW-1: extract_frontmatter_value の leading trim 強化により
    # whitespace-only 値も空判定される (`-n` で長さ 0 として扱われる)。
    local _approved_by
    _approved_by=$(extract_frontmatter_value "$_draft_path" "approved_by")
    if [ -n "$_approved_by" ]; then
      printf 'retroactive'
      return 0
    fi
    printf 'blocked-retroactive-no-approved-by'
    return 0
  fi
  local _approved_at
  _approved_at=$(extract_frontmatter_value "$_draft_path" "approved_at")
  if [ -n "$_approved_at" ]; then
    printf 'approved'
    return 0
  fi
  printf 'blocked'
}

# ----------------------------------------------------------------------
# task-40 新 path pattern 判定 (.claude/rules / .claude/commands / .claude/templates/docs)
# HIGH-G: .claude/templates/** → .claude/templates/docs/** に縮小
# ----------------------------------------------------------------------
rule_change_path_match=0
rule_change_category=""

if [ "$rule_change_guard_enabled" != "false" ] && [ "${ECC_RULE_CHANGE_GUARD_OFF:-0}" != "1" ]; then
  case "$file_path" in
    "$root/.claude/rules/"*)
      # 深さ 1 のみ (.claude/rules/<basename>.md)
      _sub="${file_path#$root/.claude/rules/}"
      case "$_sub" in
        */*) ;;  # 深さ 2 以上は対象外
        *.md|*.mdx)
          rule_change_path_match=1
          rule_change_category="rules"
          ;;
      esac
      ;;
    "$root/.claude/commands/"*)
      # 深さ 1 のみ (.claude/commands/<basename>.md)
      _sub="${file_path#$root/.claude/commands/}"
      case "$_sub" in
        */*) ;;  # 深さ 2 以上は対象外
        *.md|*.mdx)
          rule_change_path_match=1
          rule_change_category="commands"
          ;;
      esac
      ;;
    "$root/.claude/templates/docs/"*)
      # HIGH-G: 再帰だが templates/docs/ 配下に限定
      # (.claude/templates/foo.md のような top-level 直下は対象外)
      _sub="${file_path#$root/.claude/templates/docs/}"
      case "$_sub" in
        *.md|*.mdx)
          rule_change_path_match=1
          rule_change_category="templates"
          ;;
      esac
      ;;
  esac
fi

# HIGH-5 (iter3): rule_change_guard 対応 path への新規 Write 判定
# (env bypass の log は MEDIUM-6 で path 評価前に集中処理済)
if [ "$rule_change_path_match" = "1" ]; then
  # 既存 file の Edit は無条件通過 (新規 Write のみ block 対象)
  if [ -f "$file_path" ]; then
    exit 0
  fi

  basename_md=$(basename "$file_path")
  slug="${basename_md%.md}"
  slug="${slug%.mdx}"

  status=$(verify_draft_status "$slug")
  draft_path="$root/$draft_dir/${slug}.md"

  case "$status" in
    approved)
      exit 0
      ;;
    retroactive)
      # HIGH-C: retroactive case の悪用検知
      # - bypass.log に記録 (audit trail で誤用追跡)
      # - stderr warn + JSON additionalContext で main agent に強制注意喚起
      # MEDIUM-8 (iter3): stderr + JSON 2 経路を _retro_msg 単一変数で DRY 化
      if declare -f log_bypass >/dev/null 2>&1; then
        log_bypass "draft-flow-guard" "retroactive-pass" "category=${rule_change_category} file=${file_path} draft=${draft_path}"
      fi
      _retro_msg="[draft-flow-guard] retroactive=true 経由で通過 (category: ${rule_change_category})

  対象 file : ${file_path}
  対応 draft: ${draft_path}

retroactive は **緊急 retroactive リカバリ専用** です。誤用検知のため bypass.log に記録済。
次回以降は通常フローを遵守してください:
  1. /new-draft <slug>            # 先に設計を起こす
  2. user 承認 (approved_at 非空)
  3. /new-task <id> <slug>        # task 化してから着手

設計起源: docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40)"
      # stderr (interactive 用)
      printf '%s\n' "$_retro_msg" >&2
      # JSON additionalContext (main agent 用)
      jq -n --arg r "$_retro_msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$r}}'
      exit 0
      ;;
    blocked-retroactive-no-approved-by)
      # HIGH-3 (iter3): retroactive: true だけで approved_by 不在の draft は不正
      cat <<EOF >&2
[draft-flow-guard] BLOCK: retroactive draft に approved_by が必須

  対象 file : $file_path (category: $rule_change_category)
  対応 draft: $draft_path
  状態      : frontmatter retroactive: true は記載されているが approved_by が空

retroactive リカバリは緊急用途であり、誰が承認したかの監査痕跡が必要です。
draft frontmatter に approved_by: <承認者名 or 役割> を追記してください。

例:
  <!--
  approved_by: takuma hirai
  retroactive: true
  -->

または通常フロー (推奨):
  1. /new-draft $slug            # 先に設計を起こす
  2. user 承認 (approved_at 非空)
  3. /new-task <id> $slug        # task 化してから着手

bypass (一時、緊急時のみ):
  - ECC_RULE_CHANGE_GUARD_OFF=1 環境変数をセット (新 path のみ skip)
  - ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 環境変数をセット (両 path 全 skip)
  - HC_RULE_CHANGE_GUARD_ENABLED=false (config レベル、default true)

設計起源: docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40 Step 7 iter3 HIGH-3)
EOF
      exit 2
      ;;
    blocked)
      cat <<EOF >&2
[draft-flow-guard] BLOCK: $rule_change_category 直下への新規規範文書 Write を検出

  対象 file : $file_path
  対応 draft: $draft_path (不在 or approved_at 空)

「設計→承認→タスク追加」フロー (task-management.md) を尊重してください:

  1. /new-draft $slug            # docs/draft/${slug}.md を起こす
  2. user 承認を受ける (frontmatter に approved_at: YYYY-MM-DD 記入)
  3. /new-task <id> $slug        # docs/tasks/ に反映 + 承認版を配置

bypass (一時、緊急時のみ):
  - 先に touch $draft_path してから frontmatter approved_at を埋める
  - or 既存規範違反のリカバリなら frontmatter retroactive: true + approved_by を立てる
  - or ECC_RULE_CHANGE_GUARD_OFF=1 環境変数をセット (新 path のみ skip)
  - or ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 環境変数をセット (両 path 全 skip)
  - or HC_RULE_CHANGE_GUARD_ENABLED=false (config レベル、default true)

設計起源: docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md (task-40)
EOF
      exit 2
      ;;
  esac
fi

# ----------------------------------------------------------------------
# 既存 docs/ 直下判定 (回帰維持)
# ----------------------------------------------------------------------

# file_path が docs/ 配下か
case "$file_path" in
  "$docs_root"/*) ;;
  *) exit 0 ;;  # docs/ 外は対象外
esac

# docs/draft/** docs/tasks/** は対象外
case "$file_path" in
  "$root/$draft_dir"/*) exit 0 ;;
  "$root/$task_dir"/*) exit 0 ;;
esac

# 深さ判定 (docs/<sub>/ 以下は対象外、ただし HC_DOCS_APPROVED_DIR 配下の
# 深さ 2 (= approved_dir 直下) は許可)
rel="${file_path#$docs_root/}"
case "$rel" in
  */*)
    # 深さ 2 以上。HC_DOCS_APPROVED_DIR 配下の **深さ 2** (= approved_dir 直下
    # の file) のみ PASS、それ以上は元の挙動 (対象外 = exit 0) を保つ。
    if [ -n "$approved_dir_raw" ]; then
      # CSV 複数値対応: design,research → "design" "research"
      IFS=',' read -r -a approved_dirs <<< "$approved_dir_raw"
      for ad in "${approved_dirs[@]}"; do
        # trim spaces
        ad_trim="${ad# }"
        ad_trim="${ad_trim% }"
        [ -z "$ad_trim" ] && continue
        # rel が "<ad_trim>/<basename>" 形式 (approved_dir 直下) か
        case "$rel" in
          "$ad_trim"/*/*) ;;  # 深さ 3+ は対象外 (= exit 0、既存挙動と一致)
          "$ad_trim"/*)
            # approved_dir 直下 → .md/.mdx かどうか確認後 PASS
            sub="${rel#$ad_trim/}"
            case "$sub" in
              *.md|*.mdx) exit 0 ;;  # PASS: approved_dir 直下の .md/.mdx
            esac
            ;;
        esac
      done
    fi
    exit 0  # 既存挙動: docs/<sub>/<file> は深さ 2 以上で対象外
    ;;
esac

basename_md="$rel"

# .md / .mdx 以外は対象外 (画像 / json 等は通過)
case "$basename_md" in
  *.md|*.mdx) ;;
  *) exit 0 ;;
esac

# 既存 file の Edit は無条件通過 (新規 Write のみ block 対象)
if [ -f "$file_path" ]; then
  exit 0
fi

# whitelist 判定 (cmma-separated basename list)
if [ -n "$whitelist_raw" ]; then
  IFS=',' read -r -a whites <<< "$whitelist_raw"
  for w in "${whites[@]}"; do
    # trim spaces
    w_trim="${w# }"
    w_trim="${w_trim% }"
    if [ "$basename_md" = "$w_trim" ]; then
      exit 0
    fi
  done
fi

# 対応 draft 存在判定
draft_path="$root/$draft_dir/$basename_md"
if [ -f "$draft_path" ]; then
  exit 0  # pass: draft 経由
fi

# slug 抽出
slug="${basename_md%.md}"
slug="${slug%.mdx}"

# block
cat <<EOF >&2
[draft-flow-guard] BLOCK: docs/ 直下への新規設計文書 Write を検出

  対象 file : $file_path
  対応 draft: $draft_path (不在)

「設計→承認→タスク追加」フロー (task-management.md) を尊重してください:

  1. /new-draft $slug            # docs/draft/$basename_md を起こす
  2. user 承認を受ける
  3. /new-task <id> $slug        # docs/tasks/ に反映 + 承認版を docs/ に配置

bypass (一時、緊急時のみ):
  - 先に touch $draft_path してから再実行
  - or ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 環境変数をセット
  - or harness-config.yml の draft_flow_guard_whitelist に "$basename_md" 追加
  - or harness-config.yml の docs_approved_dir に承認済 dir を設定
    (e.g. docs_approved_dir: design で docs/design/$basename_md は許可)

設計起源: docs/draft/system-reminder-attention-fix.md Wave 2.3
         docs/draft/taskmanagesystem-recovery.md Q2 (task-24 W3)
EOF

exit 2
