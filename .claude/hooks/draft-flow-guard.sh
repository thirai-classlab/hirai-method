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
# 設計起源:
#   - docs/draft/system-reminder-attention-fix.md Wave 2.3 (2026-05-23)
#   - 観察証拠: recall_poc/docs/01-03 が draft 経由なしで docs/ 直下に
#     直接 Write された事案
#
# 監視対象:
#   - tool: Edit / Write
#   - path: <root>/docs/<basename>.md (深さ 1 のみ)
#   - 除外: <root>/docs/draft/** / <root>/docs/tasks/** / 深さ 2 以上
#   - 除外: 既存 file の Edit (新規 Write のみ)
#
# bypass:
#   - 対応する <root>/docs/draft/<basename>.md を先に作る (推奨)
#   - 環境変数 ECC_DRAFT_FLOW_GUARD_OVERRIDE=1 (一時)
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

# bypass env
if [ "${ECC_DRAFT_FLOW_GUARD_OVERRIDE:-0}" = "1" ]; then
  exit 0
fi

# tool_name 抽出
tool_name=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)
case "$tool_name" in
  Edit|Write) ;;
  *) exit 0 ;;
esac

# file_path 抽出
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# project root 解決
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# config (task_dir / draft_dir / whitelist) 読み込み
# shellcheck source=lib/config-loader.sh
if [ -f "$script_dir/lib/config-loader.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/config-loader.sh" >/dev/null 2>&1 || true
fi
task_dir="${HC_TASK_DIR:-docs/tasks}"
draft_dir="${HC_DRAFT_DIR:-docs/draft}"
whitelist_raw="${HC_DRAFT_FLOW_GUARD_WHITELIST:-}"

docs_root="$root/docs"

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

# 深さ判定 (docs/<sub>/ 以下は対象外)
rel="${file_path#$docs_root/}"
case "$rel" in
  */*) exit 0 ;;  # docs/<sub>/<file> は深さ 2 以上で対象外
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

設計起源: docs/draft/system-reminder-attention-fix.md Wave 2.3
EOF

exit 2
