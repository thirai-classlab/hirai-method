#!/usr/bin/env bash
# .claude/scripts/observability-gc.sh — observations.jsonl 30 日 GC
#
# 役割 (task-99 / P3-2 / I5):
#   .claude/observability/observations.jsonl を走査し、`ts` field が閾値 (default 30 日)
#   を超えた entry を .claude/observability/archive/YYYY-MM.jsonl に移動する。
#   30 日以内の entry は本体に残す。archive file は entry の ts 属する年月で振り分け。
#
# 使い方:
#   bash .claude/scripts/observability-gc.sh --dry-run
#     → 30 日超え entry を stdout に列挙 (件数 + サンプル 3 件)、file 変更なし
#   bash .claude/scripts/observability-gc.sh --apply
#     → archive dir へ移動 (本体は 30 日以内のみ残る)
#   bash .claude/scripts/observability-gc.sh --days 60 --dry-run
#     → 閾値を 60 日に変更 (default 30)
#   bash .claude/scripts/observability-gc.sh --target /path/to/observations.jsonl --apply
#     → target file を明示指定 (test / project 隔離用)
#
# 出力先:
#   .claude/observability/archive/YYYY-MM.jsonl (entry ts が該当する年月で振り分け)
#
# 設計:
#   - file 不在 / 空 → silent exit 0 (fail-open)
#   - jq 存在時は jq で ts parse、不在時は python3 fallback
#   - dry-run はサマリ + 3 件サンプルを stdout に (file は触らない)
#   - apply は atomic に:
#     1. temp file に「本体に残す entry」を書き出し
#     2. archive 各 file に「archive 対象 entry」を append
#     3. temp file を本体に置換 (mv -f)
#   - archive dir 不在なら mkdir -p
#   - 空 archive file は作成しない (0 件年月は skip)
#
# fail-open:
#   - file-top set -uo pipefail (subshell に影響しない)
#   - set -e は使わない (CB-verify 教訓)
#
# 起源: docs/tasks/task-99-lib-observability-30d-gc.md

set -uo pipefail

# ---- args ----
MODE="dry-run"
DAYS=30
TARGET=""
ARCHIVE_DIR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run|--apply] [--days N] [--target PATH] [--archive-dir DIR]

Options:
  --dry-run           30 日超え entry を stdout に列挙 (default)
  --apply             archive dir へ移動 + 本体を pruning
  --days N            閾値日数 (default 30)
  --target PATH       observations.jsonl の path 明示指定
                      (default: \$CLAUDE_PROJECT_DIR/.claude/observability/observations.jsonl)
  --archive-dir DIR   archive dir 明示指定 (default: target file と同 dir の archive/)
  --help              このヘルプ
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --days) DAYS="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --archive-dir) ARCHIVE_DIR="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# ---- resolve target ----
if [ -z "$TARGET" ]; then
  ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  TARGET="${ROOT}/.claude/observability/observations.jsonl"
fi
if [ -z "$ARCHIVE_DIR" ]; then
  ARCHIVE_DIR="$(dirname "$TARGET")/archive"
fi

# ---- file 不在 / 空 → silent exit ----
if [ ! -f "$TARGET" ]; then
  printf '[observability-gc] target not found: %s (skipped, exit 0)\n' "$TARGET"
  exit 0
fi
if [ ! -s "$TARGET" ]; then
  printf '[observability-gc] target empty: %s (skipped, exit 0)\n' "$TARGET"
  exit 0
fi

# ---- 閾値算出 (cutoff ts = now - DAYS days、ISO-8601 UTC) ----
# macOS date と GNU date を portable に処理する。python3 fallback あり。
compute_cutoff() (
  set -uo pipefail
  local days="$1"
  # BSD date: date -u -v-30d
  if date -u -v-"${days}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
  # GNU date: date -u -d "-30 days"
  if date -u -d "-${days} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
  # python3 fallback
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import datetime, sys
d = int(sys.argv[1])
now = datetime.datetime.utcnow()
c = now - datetime.timedelta(days=d)
print(c.strftime('%Y-%m-%dT%H:%M:%SZ'))
" "$days"
    return
  fi
  # 全 tool 不在 → 空返却 (fail-open で GC skip)
  printf ''
)

CUTOFF=$(compute_cutoff "$DAYS")
if [ -z "$CUTOFF" ]; then
  printf '[observability-gc] WARN: cutoff 算出失敗 (date/python3 不在)、skip\n' >&2
  exit 0
fi

# ---- 走査 ----
# 各 entry を分類 (keep / archive)、archive は月別に振り分け
# python3 で JSONL 一括処理 (portable、jq でも可能だが month 判定が煩雑)
if ! command -v python3 >/dev/null 2>&1; then
  printf '[observability-gc] WARN: python3 不在、GC 実施不能 (skip)\n' >&2
  exit 0
fi

# python3 で分類 + dry-run/apply 分岐
export TARGET ARCHIVE_DIR CUTOFF MODE DAYS

python3 <<'PYEOF'
import json, os, sys, tempfile, shutil
from collections import defaultdict

target = os.environ['TARGET']
archive_dir = os.environ['ARCHIVE_DIR']
cutoff = os.environ['CUTOFF']
mode = os.environ['MODE']
days = os.environ['DAYS']

keep_lines = []
archive_by_month = defaultdict(list)
malformed = 0
total = 0

with open(target, 'r', encoding='utf-8', errors='replace') as f:
    for raw in f:
        raw = raw.rstrip('\n')
        if not raw:
            continue
        total += 1
        try:
            d = json.loads(raw)
            ts = d.get('ts', '')
            if not ts or ts >= cutoff:
                # keep (30 日以内 or ts 不在は保持)
                keep_lines.append(raw)
            else:
                # archive 対象、月 key で振り分け
                # ts format: 2026-07-07T02:24:47Z → year_month = "2026-07"
                ym = ts[:7] if len(ts) >= 7 else 'unknown'
                archive_by_month[ym].append(raw)
        except Exception:
            malformed += 1
            # malformed は本体に残す (data loss 防止、operator 対処に委ねる)
            keep_lines.append(raw)

archive_count = sum(len(v) for v in archive_by_month.values())
keep_count = len(keep_lines)

print(f"[observability-gc] target: {target}")
print(f"[observability-gc] cutoff: {cutoff} (days={days})")
print(f"[observability-gc] total: {total} entry (malformed: {malformed})")
print(f"[observability-gc] keep:  {keep_count} entry (本体に残す)")
print(f"[observability-gc] archive: {archive_count} entry (30 日超え)")

if archive_count > 0:
    print(f"[observability-gc] archive breakdown:")
    for ym in sorted(archive_by_month.keys()):
        print(f"  - {ym}.jsonl : {len(archive_by_month[ym])} entry")

if mode == 'dry-run':
    print(f"[observability-gc] mode=dry-run (no file changes)")
    if archive_count > 0:
        print(f"[observability-gc] sample archive entries (up to 3):")
        sample_count = 0
        for ym in sorted(archive_by_month.keys()):
            for line in archive_by_month[ym][:3]:
                if sample_count >= 3:
                    break
                print(f"  {line}")
                sample_count += 1
            if sample_count >= 3:
                break
    sys.exit(0)

# apply mode
if archive_count == 0:
    print(f"[observability-gc] no entry to archive (skipped)")
    sys.exit(0)

os.makedirs(archive_dir, exist_ok=True)

# archive files: append
for ym, lines in archive_by_month.items():
    if ym == 'unknown':
        continue
    ar_path = os.path.join(archive_dir, f'{ym}.jsonl')
    with open(ar_path, 'a', encoding='utf-8') as af:
        for line in lines:
            af.write(line + '\n')

# main file: atomic replace
target_dir = os.path.dirname(target)
fd, tmp_path = tempfile.mkstemp(prefix='.obs-gc-', dir=target_dir)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as tf:
        for line in keep_lines:
            tf.write(line + '\n')
    shutil.move(tmp_path, target)
except Exception as e:
    print(f"[observability-gc] ERROR: atomic replace failed: {e}", file=sys.stderr)
    try:
        os.unlink(tmp_path)
    except Exception:
        pass
    sys.exit(1)

print(f"[observability-gc] applied: {archive_count} entry archived, {keep_count} kept in main")
PYEOF

exit $?
