#!/usr/bin/env bash
# hook-fire-audit-smoke.sh — task-99 smoke for .claude/scripts/hook-fire-audit.sh
#
# 設計起源:
#   docs/tasks/task-99-lib-observability-30d-gc.md Step 5 (3 case A-C)
#   master roadmap install-immediately-usable-redesign-20260618 §3 I5 / §5 P3-2
#
# 対象 script: .claude/scripts/hook-fire-audit.sh
#
# 検証範囲 (3 ケース):
#   A: fixture observations.jsonl (fire event 混在) から fire=0 hook が正しく列挙される
#   B: --json output が有効な JSON dict、fire=0 hook のみ含む
#   C: --days 閾値で cutoff 期間外 (古い fire) が対象外になる (期間外 fire 持ちも fire=0 判定)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 教訓)
#   - 独立 /tmp fixture で live observations.jsonl を汚染しない
#
# 実行:
#   bash .claude/tests/hook-fire-audit-smoke.sh
#
# 終了コード:
#   0 = 3/3 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/.claude/scripts/hook-fire-audit.sh"

if [ ! -f "$SCRIPT" ]; then
  printf 'FAIL: %s not found\n' "$SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# fixture 生成
make_fixture() {
  local path="$1"
  cat > "$path" <<EOF
{"ts":"$(_ts_recent 1)","event_kind":"fire","hook_name":"gateguard","reason":"r1","payload":{},"session_id":"s1","_schema_version":1}
{"ts":"$(_ts_recent 2)","event_kind":"fire","hook_name":"gateguard","reason":"r2","payload":{},"session_id":"s2","_schema_version":1}
{"ts":"$(_ts_recent 3)","event_kind":"fire","hook_name":"workflow-guard","reason":"r3","payload":{},"session_id":"s3","_schema_version":1}
{"ts":"$(_ts_recent 5)","event_kind":"block","hook_name":"gateguard","reason":"blocked","payload":{},"session_id":"s4","_schema_version":1}
{"ts":"$(_ts_recent 90)","event_kind":"fire","hook_name":"draft-flow-guard","reason":"old_fire","payload":{},"session_id":"s5","_schema_version":1}
EOF
}

# ISO-8601 UTC ts で N 日前を返す (portable)
_ts_recent() (
  set -uo pipefail
  local d="$1"
  # BSD date
  if date -u -v-"${d}"d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
  # GNU date
  if date -u -d "-${d} days" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
    return
  fi
  # python3 fallback
  python3 -c "
import datetime, sys
d = int(sys.argv[1])
now = datetime.datetime.utcnow()
c = now - datetime.timedelta(days=d)
print(c.strftime('%Y-%m-%dT%H:%M:%SZ'))
" "$d"
)

# =====================================================================
# Case A: table mode で fire=0 hook 列挙 (verbose なしで最低限のリスト)
# =====================================================================
caseA_table_lists_zero_fire() {
  local label="Case A: table mode lists fire=0 hooks"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/audit-smoke-A.XXXXXX)
  local target="$tmpdir/obs.jsonl"
  make_fixture "$target"

  local out
  out=$(bash "$SCRIPT" --target "$target" --days 30 2>&1)

  local ok=1
  # gateguard は fire=2 (直近 3 日) なので fire=0 リストに **含まれない** はず
  if printf '%s' "$out" | awk '/Fire count 0/,/^$/{print}' | grep -qE '^\s*-\s*gateguard\s*$'; then
    ok=0
  fi
  # draft-flow-guard は fire 1 件だが 90 日前 (30 日 cutoff 対象外) なので fire=0 リストに **含まれる**
  if ! printf '%s' "$out" | awk '/Fire count 0/,/^$/{print}' | grep -qE '^\s*-\s*draft-flow-guard\s*$'; then
    ok=0
  fi
  # 未接続 hook (context-budget 等) も fire=0 リストに含まれる
  if ! printf '%s' "$out" | awk '/Fire count 0/,/^$/{print}' | grep -qE '^\s*-\s*context-budget\s*$'; then
    ok=0
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (table output missing expected zero-fire entries)")
    printf "  FAIL: %s\n    out:\n%s\n" "$label" "$out"
  fi
}

# =====================================================================
# Case B: --json output が有効な JSON dict + fire=0 hook のみ
# =====================================================================
caseB_json_only_zero_hooks() {
  local label="Case B: --json output = valid dict, contains fire=0 hooks only (default)"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/audit-smoke-B.XXXXXX)
  local target="$tmpdir/obs.jsonl"
  make_fixture "$target"

  local out
  out=$(bash "$SCRIPT" --target "$target" --days 30 --json 2>/dev/null)

  local ok=1
  # JSON 有効性 + gateguard が含まれない (fire>0) + draft-flow-guard は含まれる (期間外 fire)
  if ! printf '%s' "$out" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert isinstance(d, dict)
# gateguard は含まれない (fire=2)
assert 'gateguard' not in d, f'gateguard should not appear (fire>0), got {d.get(\"gateguard\")}'
# draft-flow-guard は含まれる (30 日以内 fire=0)
assert 'draft-flow-guard' in d, f'draft-flow-guard should appear (fire=0 in window)'
# context-budget も含まれる (未接続 hook)
assert 'context-budget' in d
# 全 value が 0
for k, v in d.items():
    assert v == 0, f'{k}={v} should be 0 in default mode'
print('OK')
" 2>/dev/null | grep -q OK; then
    ok=0
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (JSON parse or content assert failed)")
    printf "  FAIL: %s\n    out:\n%s\n" "$label" "$out"
  fi
}

# =====================================================================
# Case C: --days で cutoff 変更、期間内 fire event が全て cutoff 内なら
#         verbose mode で正しい fire count を報告
# =====================================================================
caseC_days_threshold_effect() {
  local label="Case C: --days threshold correctly filters old fire events"
  local tmpdir
  tmpdir=$(mktemp -d /tmp/audit-smoke-C.XXXXXX)
  local target="$tmpdir/obs.jsonl"
  make_fixture "$target"

  # --days 180 で 90 日前 fire (draft-flow-guard) も対象内に入るので fire=1 になる
  local out_180
  out_180=$(bash "$SCRIPT" --target "$target" --days 180 --json --verbose 2>/dev/null)

  local ok=1
  if ! printf '%s' "$out_180" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# draft-flow-guard は 90 日前 fire を含むので --days 180 では fire=1
assert d.get('draft-flow-guard') == 1, f'draft-flow-guard should be 1 in --days 180, got {d.get(\"draft-flow-guard\")}'
# gateguard は 2 件 (1日/2日前) fire
assert d.get('gateguard') == 2, f'gateguard should be 2, got {d.get(\"gateguard\")}'
print('OK')
" 2>/dev/null | grep -q OK; then
    ok=0
  fi

  # --days 30 では draft-flow-guard の fire は cutoff 外 なので verbose mode でも fire=0
  local out_30
  out_30=$(bash "$SCRIPT" --target "$target" --days 30 --json --verbose 2>/dev/null)
  if ! printf '%s' "$out_30" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d.get('draft-flow-guard') == 0, f'draft-flow-guard should be 0 in --days 30, got {d.get(\"draft-flow-guard\")}'
print('OK')
" 2>/dev/null | grep -q OK; then
    ok=0
  fi

  rm -rf "$tmpdir"
  if [ "$ok" = "1" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (--days threshold behavior wrong)")
    printf "  FAIL: %s\n    out_180:\n%s\n    out_30:\n%s\n" "$label" "$out_180" "$out_30"
  fi
}

printf "===== hook-fire-audit-smoke (task-99, 3 cases A-C) =====\n\n"

caseA_table_lists_zero_fire
caseB_json_only_zero_hooks
caseC_days_threshold_effect

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf "Failed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
