#!/usr/bin/env bash
# observe-rotate.sh — rotate observations.jsonl into monthly gzipped archives.
#
# 役割:
#   ~/.claude/homunculus/projects/<hash>/observations.jsonl から
#   threshold 日 (default 30) 超の entry を抽出し、
#   observations-YYYY-MM.jsonl.gz に append archive する。
#   本体 (observations.jsonl) は threshold 日以内のみ保持。
#
# 設計起源:
#   docs/draft/hook-reliability-uplift.md §3 W4 (2026-05-23)
#
# 起動経路:
#   - cron / 手動実行 (本 Wave では cron 設定は対象外)
#   - 将来: harness-audit subcommand --rotate-observations (task-22 W6 想定)
#
# 引数:
#   --dry-run                実行せず計測のみ
#   --project <hash>         project 指定 (default: git remote から自動検出 / global fallback)
#   --threshold-days N       閾値日数 (default 30)
#   --target-dir <path>      base dir override (default: ~/.claude/homunculus)
#                            (smoke test 隔離用、live dir を汚染しないため)
#   -h, --help               このヘルプ
#
# Exit code:
#   0 = success
#   1 = invalid arg
#   2 = observations.jsonl not found (fail-open)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lessons HIGH 準拠)
#   - command -v gzip / awk / jq guard (jq 不在環境では date 抽出を awk regex で fallback)
#   - 既存 entry 形式 (1 行 JSON、`ts` field ISO-8601) を破壊しない
#   - 同名 archive 存在時は gunzip → cat → gzip で append

set -uo pipefail

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

# ===== arg parse =====
DRY_RUN=0
PROJECT_OVERRIDE=""
THRESHOLD_DAYS=30
TARGET_DIR_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --project)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf '[observe-rotate] ERROR: --project requires a value\n' >&2
        exit 1
      fi
      PROJECT_OVERRIDE="$2"
      shift 2
      ;;
    --threshold-days)
      if [ $# -lt 2 ] || ! printf '%s' "$2" | grep -qE '^[0-9]+$'; then
        printf '[observe-rotate] ERROR: --threshold-days requires a non-negative integer\n' >&2
        exit 1
      fi
      THRESHOLD_DAYS="$2"
      shift 2
      ;;
    --target-dir)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf '[observe-rotate] ERROR: --target-dir requires a value\n' >&2
        exit 1
      fi
      TARGET_DIR_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[observe-rotate] ERROR: unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# ===== runtime dependency guard =====
if ! command -v gzip >/dev/null 2>&1; then
  printf '[observe-rotate] ERROR: gzip not found in PATH\n' >&2
  exit 1
fi
if ! command -v awk >/dev/null 2>&1; then
  printf '[observe-rotate] ERROR: awk not found in PATH\n' >&2
  exit 1
fi
# jq は optional (project hash 自動検出時の git URL hash 計算で sha1sum / shasum を使う)
HAS_JQ=0
if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
fi

# ===== target dir 解決 =====
BASE_DIR="${TARGET_DIR_OVERRIDE:-${HOME}/.claude/homunculus}"

if [ ! -d "$BASE_DIR" ]; then
  printf '[observe-rotate] ERROR: base dir not found: %s\n' "$BASE_DIR" >&2
  exit 2
fi

# ===== project hash 解決 =====
# 優先順: --project arg > git remote sha1 自動検出 > global fallback
resolve_project_hash() {
  if [ -n "$PROJECT_OVERRIDE" ]; then
    printf '%s\n' "$PROJECT_OVERRIDE"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    local url
    url=$(git remote get-url origin 2>/dev/null || true)
    if [ -n "$url" ]; then
      local hash_cmd=""
      if command -v sha1sum >/dev/null 2>&1; then
        hash_cmd="sha1sum"
      elif command -v shasum >/dev/null 2>&1; then
        hash_cmd="shasum -a 1"
      fi
      if [ -n "$hash_cmd" ]; then
        # 12 桁の hash prefix を取る (~/.claude/homunculus/projects/<12 char hash>/ と合わせる)
        printf '%s' "$url" | $hash_cmd | awk '{print substr($1,1,12)}'
        return 0
      fi
    fi
  fi

  printf 'global\n'
}

PROJECT_HASH=$(resolve_project_hash)

# global は base 直下、project は base/projects/<hash>/ 配下
if [ "$PROJECT_HASH" = "global" ]; then
  PROJECT_DIR="$BASE_DIR"
else
  PROJECT_DIR="$BASE_DIR/projects/$PROJECT_HASH"
fi

OBS_FILE="$PROJECT_DIR/observations.jsonl"

if [ ! -f "$OBS_FILE" ]; then
  printf '[observe-rotate] ERROR: observations.jsonl not found: %s\n' "$OBS_FILE" >&2
  exit 2
fi

# ===== threshold date (YYYY-MM-DD) を計算 =====
# BSD date (macOS) と GNU date (Linux) 両対応
compute_threshold_date() {
  local days="$1"
  # try BSD date (macOS)
  if date -v-"${days}"d +%Y-%m-%d >/dev/null 2>&1; then
    date -v-"${days}"d +%Y-%m-%d
    return 0
  fi
  # GNU date fallback
  if date -d "-${days} days" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "-${days} days" +%Y-%m-%d
    return 0
  fi
  # 完全 fallback: python3
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import datetime; print((datetime.datetime.utcnow() - datetime.timedelta(days=${days})).strftime('%Y-%m-%d'))"
    return 0
  fi
  printf '[observe-rotate] ERROR: cannot compute threshold date (no BSD/GNU date, no python3)\n' >&2
  return 1
}

THRESHOLD_DATE=$(compute_threshold_date "$THRESHOLD_DAYS")
if [ -z "$THRESHOLD_DATE" ]; then
  exit 1
fi

# ===== 1 pass で振り分け =====
# - 各 line から "ts":"YYYY-MM-DD" を awk regex で抽出
# - extracted_date < THRESHOLD_DATE → archive 用 (月別 tmp に append)
# - それ以外 → keep 用 tmp に append
# - ts 抽出失敗 line は keep 側に流す (safety: 未知形式を捨てない)
SCRATCH_DIR=$(mktemp -d /tmp/observe-rotate.XXXXXX)
trap 'rm -rf "$SCRATCH_DIR"' EXIT

KEEP_TMP="$SCRATCH_DIR/keep.jsonl"
ARCHIVE_DIR="$SCRATCH_DIR/archive"
mkdir -p "$ARCHIVE_DIR"

# awk で振り分け
# 出力:
#   keep.jsonl                  → threshold 以降 (本体に残す)
#   archive/<YYYY-MM>.jsonl     → 月別 archive 候補
# stdout に振り分け統計を出す (KEEP=N ARCHIVE=N OTHER=N)
STATS=$(awk -v threshold="$THRESHOLD_DATE" \
             -v keep_path="$KEEP_TMP" \
             -v archive_dir="$ARCHIVE_DIR" '
  BEGIN {
    keep_count = 0
    archive_count = 0
    other_count = 0
  }
  {
    # "ts":"YYYY-MM-DDTHH:MM:SSZ" の YYYY-MM-DD 部を抽出
    line_ts = ""
    if (match($0, /"ts":"[0-9]{4}-[0-9]{2}-[0-9]{2}/)) {
      # match 結果は RSTART, RLENGTH。"ts":" の 6 文字 skip
      line_ts = substr($0, RSTART + 6, 10)
    }

    if (line_ts == "") {
      # ts 抽出失敗 → keep 側 (未知形式は捨てない)
      print >> keep_path
      other_count++
      next
    }

    if (line_ts < threshold) {
      # archive 側 (月別)
      month = substr(line_ts, 1, 7)  # YYYY-MM
      print >> (archive_dir "/" month ".jsonl")
      archive_count++
    } else {
      # keep 側
      print >> keep_path
      keep_count++
    }
  }
  END {
    printf "KEEP=%d ARCHIVE=%d OTHER=%d\n", keep_count, archive_count, other_count
  }
' "$OBS_FILE")

KEEP_COUNT=$(printf '%s' "$STATS" | awk -F= '/KEEP=/{print $2}' | awk '{print $1}')
ARCHIVE_COUNT=$(printf '%s' "$STATS" | awk -F= '/ARCHIVE=/{print $2}' | awk '{print $1}')
OTHER_COUNT=$(printf '%s' "$STATS" | awk -F= '/OTHER=/{print $2}' | awk '{print $1}')

# サイズ計算 (bytes)
ORIG_SIZE=$(wc -c < "$OBS_FILE" | awk '{print $1}')
KEEP_SIZE=0
if [ -f "$KEEP_TMP" ]; then
  KEEP_SIZE=$(wc -c < "$KEEP_TMP" | awk '{print $1}')
fi

REDUCTION=$((ORIG_SIZE - KEEP_SIZE))

printf '[observe-rotate] target: %s\n' "$OBS_FILE"
printf '[observe-rotate] threshold: %s (-%d days)\n' "$THRESHOLD_DATE" "$THRESHOLD_DAYS"
printf '[observe-rotate] keep: %d entries (%d bytes)\n' "$KEEP_COUNT" "$KEEP_SIZE"
printf '[observe-rotate] archive: %d entries (will be merged into monthly .gz)\n' "$ARCHIVE_COUNT"
if [ "$OTHER_COUNT" -gt 0 ]; then
  printf '[observe-rotate] note: %d lines without parseable ts kept in body\n' "$OTHER_COUNT"
fi
printf '[observe-rotate] reduction: %d bytes\n' "$REDUCTION"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '[observe-rotate] dry-run: no file changes applied\n'
  exit 0
fi

# ===== archive 統合 (月別、既存 .gz に append) =====
if [ -d "$ARCHIVE_DIR" ]; then
  # for each YYYY-MM.jsonl in ARCHIVE_DIR
  for month_file in "$ARCHIVE_DIR"/*.jsonl; do
    [ -f "$month_file" ] || continue
    month=$(basename "$month_file" .jsonl)
    final_gz="$PROJECT_DIR/observations-${month}.jsonl.gz"

    if [ -f "$final_gz" ]; then
      # 既存 archive に append: gunzip 既存 → cat → gzip 上書き
      existing_tmp="$SCRATCH_DIR/existing-${month}.jsonl"
      if ! gunzip -c "$final_gz" > "$existing_tmp" 2>/dev/null; then
        printf '[observe-rotate] ERROR: failed to gunzip existing archive: %s\n' "$final_gz" >&2
        exit 1
      fi
      cat "$month_file" >> "$existing_tmp"
      if ! gzip -c "$existing_tmp" > "${final_gz}.tmp"; then
        printf '[observe-rotate] ERROR: failed to recompress archive: %s\n' "$final_gz" >&2
        exit 1
      fi
      mv "${final_gz}.tmp" "$final_gz"
      printf '[observe-rotate] archive appended: %s (+%d entries)\n' "$final_gz" "$(wc -l < "$month_file" | awk '{print $1}')"
    else
      # 新規 archive
      if ! gzip -c "$month_file" > "$final_gz"; then
        printf '[observe-rotate] ERROR: failed to create archive: %s\n' "$final_gz" >&2
        exit 1
      fi
      printf '[observe-rotate] archive created: %s (%d entries)\n' "$final_gz" "$(wc -l < "$month_file" | awk '{print $1}')"
    fi
  done
fi

# ===== 本体置換 (keep のみ) =====
# atomic rename: tmp → observations.jsonl
if [ -f "$KEEP_TMP" ]; then
  mv "$KEEP_TMP" "$OBS_FILE"
else
  # archive_count == total なら keep ファイルは空。empty file を作る
  : > "$OBS_FILE"
fi

printf '[observe-rotate] done\n'
exit 0
