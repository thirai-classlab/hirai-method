#!/usr/bin/env bash
# .claude/scripts/hook-fire-audit.sh — fire 0 回 hook 検出
#
# 役割 (task-99 / P3-2 / I5):
#   .claude/observability/observations.jsonl (+ optional archive/) を走査し、
#   最終 N 日間 (default 30 日) で event_kind="fire" が 0 回の hook を検出する。
#   task-95 の 3 死蔵 hook 判定 (tool_call_slip_detect / asana_prompt /
#   loop_mode_enforcement) の数値化根拠に用いる。
#
# 使い方:
#   bash .claude/scripts/hook-fire-audit.sh
#     → 直近 30 日で fire 0 回の hook を table で出力
#   bash .claude/scripts/hook-fire-audit.sh --days 60
#     → 閾値を 60 日に変更
#   bash .claude/scripts/hook-fire-audit.sh --json
#     → JSON output: {hook_name: fire_count, ...} (fire_count == 0 のみ)
#   bash .claude/scripts/hook-fire-audit.sh --verbose
#     → 全 hook の fire count table (fire > 0 も含む)
#   bash .claude/scripts/hook-fire-audit.sh --target /path/to/observations.jsonl
#     → target file 明示指定 (test 用)
#   bash .claude/scripts/hook-fire-audit.sh --include-archive
#     → archive/*.jsonl も集計対象に含める (default: 本体のみ)
#
# 出力 (default = table):
#   Hook fire audit (last 30 days)
#   ==============================
#   Fire count 0 (可能性死蔵、要判定):
#     - <hook_name_1>
#     - <hook_name_2>
#
#   Fire count > 0 (verbose のみ表示):
#     - gateguard: 42
#     - workflow-guard: 8
#     ...
#
# 出力 (--json):
#   {"tool_call_slip_detect": 0, "asana_prompt": 0}
#   (verbose 時は fire > 0 も含む)
#
# 設計:
#   - file 不在 / 空 → 全 hook を fire 0 として扱う (fail-safe、operator に通知)
#   - python3 必須 (JSON parse + ts filter)
#   - hook 名 registry は harness-config.yml + hooks/*.sh 実 file から自動収集
#     (env HC_HOOK_AUDIT_KNOWN_HOOKS で override 可、改行区切り)
#   - default known list は本 script 内 hardcode fallback (config-loader 未 source)
#
# fail-open:
#   - file-top set -uo pipefail (subshell に影響しない)
#   - set -e は使わない

set -uo pipefail

# ---- args ----
DAYS=30
MODE="table"          # table | json
VERBOSE=0
TARGET=""
INCLUDE_ARCHIVE=0
ARCHIVE_DIR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --days N              fire 集計期間 (default 30)
  --json                JSON 出力 ({hook_name: fire_count})
  --verbose             fire > 0 も含めた全 hook 出力
  --target PATH         observations.jsonl の path 明示指定
  --archive-dir DIR     archive dir 明示指定 (default: target 同 dir の archive/)
  --include-archive     archive/*.jsonl も集計対象に含める
  --help                このヘルプ
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --json) MODE="json"; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    --archive-dir) ARCHIVE_DIR="$2"; shift 2 ;;
    --include-archive) INCLUDE_ARCHIVE=1; shift ;;
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

# ---- known hooks registry ----
# harness-config.yml の feature_*_enabled 対象 hook + hooks/*.sh 実 file から派生。
# env override 可: HC_HOOK_AUDIT_KNOWN_HOOKS (改行区切り)
DEFAULT_KNOWN_HOOKS='gateguard
task-rule-guard
workflow-guard
autonomous-action-guard
confidence-gate
byproduct-discharge-guard
draft-flow-guard
delegation-guard
context-budget
parallel-subagent-reminder
tool-call-slip-detector
reviewer-count-guard
loop-auto-progress-reminder
loop-confirmation-detector
mode-enforce
mode-session-start
why-x5-reminder
why-x5-violation-detect
next-actions-surface
improvement-proposal
session-help-surface
check-serena-mcp
check-required-env
init-tasks-on-start
notify
stop
check-md-mermaid
failure-loop-detect
agent-router-suggest
mode-asana-prompt
self-doctor'

KNOWN_HOOKS="${HC_HOOK_AUDIT_KNOWN_HOOKS:-$DEFAULT_KNOWN_HOOKS}"

# ---- 閾値算出 (cutoff ts = now - DAYS days、ISO-8601 UTC) ----
compute_cutoff() (
  set -uo pipefail
  local days="$1"
  if date -u -v-"${days}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
  if date -u -d "-${days} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
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
  printf ''
)

CUTOFF=$(compute_cutoff "$DAYS")
if [ -z "$CUTOFF" ]; then
  printf '[hook-fire-audit] WARN: cutoff 算出失敗 (date/python3 不在)、exit 0\n' >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf '[hook-fire-audit] WARN: python3 不在、集計不能 (exit 0)\n' >&2
  exit 0
fi

# ---- 集計 (python3) ----
# 環境変数経由で target/known/cutoff/mode/verbose 渡し
export TARGET ARCHIVE_DIR CUTOFF DAYS MODE INCLUDE_ARCHIVE VERBOSE
export KNOWN_HOOKS_STR="$KNOWN_HOOKS"

python3 <<'PYEOF'
import json, os, sys, glob
from collections import defaultdict

target = os.environ['TARGET']
archive_dir = os.environ['ARCHIVE_DIR']
cutoff = os.environ['CUTOFF']
days = os.environ['DAYS']
mode = os.environ['MODE']
verbose = os.environ.get('VERBOSE', '0') == '1'
include_archive = os.environ.get('INCLUDE_ARCHIVE', '0') == '1'
known_str = os.environ.get('KNOWN_HOOKS_STR', '')

# VERBOSE は sh 側 flag が set されているか (shell から見えるように後で追加)

known_hooks = [h.strip() for h in known_str.split('\n') if h.strip()]
fire_counts = {h: 0 for h in known_hooks}
unknown_fire = defaultdict(int)  # observations 経由で見つかった未知 hook

def process_file(path):
    global fire_counts, unknown_fire
    if not os.path.isfile(path):
        return
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            for raw in f:
                raw = raw.rstrip('\n')
                if not raw:
                    continue
                try:
                    d = json.loads(raw)
                except Exception:
                    continue
                if d.get('event_kind') != 'fire':
                    continue
                ts = d.get('ts', '')
                if not ts or ts < cutoff:
                    continue  # 期間外
                hn = d.get('hook_name', 'unknown')
                if hn in fire_counts:
                    fire_counts[hn] += 1
                else:
                    unknown_fire[hn] += 1
    except Exception:
        # file open / read error → silent skip (fail-open)
        pass

process_file(target)

if include_archive and os.path.isdir(archive_dir):
    for path in sorted(glob.glob(os.path.join(archive_dir, '*.jsonl'))):
        process_file(path)

# 出力
zero_hooks = sorted([h for h, c in fire_counts.items() if c == 0])
nonzero_hooks = sorted([(h, c) for h, c in fire_counts.items() if c > 0], key=lambda x: (-x[1], x[0]))

if mode == 'json':
    # default: fire=0 のみ出力、verbose 時は全件
    out = {}
    if verbose:
        for h, c in fire_counts.items():
            out[h] = c
        for h, c in unknown_fire.items():
            out[h] = c
    else:
        for h in zero_hooks:
            out[h] = 0
    print(json.dumps(out, ensure_ascii=False, sort_keys=True))
    sys.exit(0)

# table mode
print(f"Hook fire audit (last {days} days, cutoff={cutoff})")
print(f"target: {target}")
if include_archive:
    print(f"archive: {archive_dir} (included)")
print("=" * 60)

if zero_hooks:
    print(f"Fire count 0 (可能性死蔵、要判定): {len(zero_hooks)} hooks")
    for h in zero_hooks:
        print(f"  - {h}")
else:
    print("Fire count 0: (none — 全 hook が fire しています)")

if verbose:
    print()
    if nonzero_hooks:
        print(f"Fire count > 0: {len(nonzero_hooks)} hooks")
        for h, c in nonzero_hooks:
            print(f"  - {h}: {c}")
    if unknown_fire:
        print()
        print(f"Unknown hooks (registry 外、observations 経由で検出): {len(unknown_fire)}")
        for h, c in sorted(unknown_fire.items()):
            print(f"  - {h}: {c}")

sys.exit(0)
PYEOF

exit $?
