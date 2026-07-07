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
#   task-40 拡張 (2026-05-26) — 2026-05-28 user 指示で緩和 (撤廃):
#     旧 task-40 拡張は .claude/rules/*.md / .claude/commands/*.md /
#     .claude/templates/docs/**/*.md への **新規 Write** も block 対象とし、
#     対応 draft で approved_at 非空 (or retroactive: true) を要求していた。
#     2026-05-28 user 指示「既存 rules file の Edit は PASS (新規 Write のみ
#     BLOCK) → 書き込みも許容してください」により、これらの規範文書 path は
#     **新規 Write / 既存 Edit とも PASS** に緩和。本 hook はもはや
#     .claude/rules/ / .claude/commands/ / .claude/templates/docs/ を一切
#     監視しない (docs/ 直下の新規設計文書 block 機能のみ維持)。
#     関連 bypass env (ECC_RULE_CHANGE_GUARD_OFF / HC_RULE_CHANGE_GUARD_ENABLED)
#     は dead path となるが、後方互換のため残置 (set しても無害な no-op)。
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
#   - 除外: <root>/docs/draft/** / <root>/docs/tasks/** / 深さ 2 以上
#   - 除外: 既存 file の Edit (新規 Write のみ)
#   - 除外 (task-24 W3): HC_DOCS_APPROVED_DIR 配下 (CSV 複数値対応)
#                        e.g. HC_DOCS_APPROVED_DIR=design で
#                             docs/design/foo.md は深さ 2 のみ PASS
#   - 監視対象外 (2026-05-28 緩和): .claude/rules/ / .claude/commands/ /
#                        .claude/templates/docs/ は新規 Write / Edit とも PASS
#                        (旧 task-40 拡張を撤廃)
#
# bypass:
#   - 対応する <root>/docs/draft/<basename>.md を先に作る (推奨)
#   - HC_DOCS_APPROVED_DIR=<dir>[,<dir>...] を harness-config / env で設定
#   - 環境変数 ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 (一時、docs/ block を skip)
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

# BLOCK message 統一 API (task-94 P2-3、docs/draft/lib-block-message-4args.md §3.1)
# shellcheck source=lib/block-message.sh
if [ -f "$script_dir/lib/block-message.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/block-message.sh" >/dev/null 2>&1 || true
fi

# Observability 構造化 log API (task-99 P3-2、observations.jsonl)
# shellcheck source=lib/observability.sh
if [ -f "$script_dir/lib/observability.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/observability.sh" >/dev/null 2>&1 || true
fi

# Feature toggle 参照 (task-45 Phase 2)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled draft_flow_guard; then
  exit 0
fi

task_dir="${HC_TASK_DIR:-docs/tasks}"
draft_dir="${HC_DRAFT_DIR:-docs/draft}"
whitelist_raw="${HC_DRAFT_FLOW_GUARD_WHITELIST:-}"
approved_dir_raw="${HC_DOCS_APPROVED_DIR:-}"

docs_root="$root/docs"

# ----------------------------------------------------------------------
# task-40 拡張は 2026-05-28 user 指示で撤廃 (緩和)。
# .claude/rules/ / .claude/commands/ / .claude/templates/docs/ への
# 新規 Write / 既存 Edit はいずれも block しない (本 hook では一切監視しない)。
# 旧 frontmatter parser (extract_frontmatter_value / verify_draft_status) +
# 新 path pattern 判定 + retroactive 厳格化ロジックは併せて削除した。
# bypass env (ECC_RULE_CHANGE_GUARD_OFF / HC_RULE_CHANGE_GUARD_ENABLED) は
# 後方互換のため caller が set しても無害な no-op として残置 (本 hook は参照しない)。
# 以降は docs/ 直下の新規設計文書 block 機能 (task-40 以前の元機能) のみ。
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# docs/ 直下判定 (元機能、task-40 以前から不変)
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

# hook fire log (task-99): 全 exemption / bypass を通過し、実 block 判定に到達した時点で log_fire
if declare -f log_fire >/dev/null 2>&1; then
  log_fire "draft-flow-guard" "processing docs/ direct Write: $file_path" ""
fi

# block — task-94 migration: PreToolUse BLOCK は emit_block_pretool 経由 (lib SSoT)
# 既存 stderr multi-line format を full why arg として渡し、他 3 arg 空
# (msg 内に fix / bypass / 起源が inline 済)。caller が exit 2 を維持 (§3.5)。
_dfg_reason="[draft-flow-guard] BLOCK: docs/ 直下への新規設計文書 Write を検出

  対象 file : $file_path
  対応 draft: $draft_path (不在)

「設計→承認→タスク追加」フロー (task-management.md) を尊重してください:

  1. /new-draft $slug            # docs/draft/$basename_md を起こす
  2. user 承認を受ける
  3. /new-task <id> $slug        # docs/tasks/ に反映 + 承認版を docs/ に配置

bypass (一時、緊急時のみ):
  - 先に touch $draft_path してから再実行
  - or ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 環境変数をセット
  - or harness-config.yml の draft_flow_guard_whitelist に \"$basename_md\" 追加
  - or harness-config.yml の docs_approved_dir に承認済 dir を設定
    (e.g. docs_approved_dir: design で docs/design/$basename_md は許可)

設計起源: docs/draft/system-reminder-attention-fix.md Wave 2.3
         docs/draft/taskmanagesystem-recovery.md Q2 (task-24 W3)"

if declare -f log_block >/dev/null 2>&1; then
  log_block "draft-flow-guard" "docs/ direct Write BLOCK: $file_path" ""
fi
if declare -f emit_block_pretool >/dev/null 2>&1; then
  emit_block_pretool "$_dfg_reason" "" "" ""
else
  # fallback: lib source 失敗時は既存 stderr 経路 (behavior-preserving)
  printf '%s\n' "$_dfg_reason" >&2
fi

exit 2
