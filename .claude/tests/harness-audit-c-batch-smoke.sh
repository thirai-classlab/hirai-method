#!/usr/bin/env bash
# harness-audit-c-batch-smoke.sh — task-25 C2+C3+C4 smoke
#
# 検証対象:
#   - .claude/scripts/harness-audit.py  (C2 stale_drafts_summary / C3 settings_drift_check)
#   - .claude/skills/continuous-learning-v2/hooks/observe.sh  (C4 unknown-cwd-<hash> fallback)
#
# 検証範囲 (6 ケース):
#   Case 1: stale draft 90 日超 detection (mock dir で 100 日前 draft を作って検出)
#   Case 2: stale drafts 0 件 → silent (recent draft のみ)
#   Case 3: settings.local.json drift detection (main と diff のある local で検出)
#   Case 4: settings.local.json 不在 → drift 検証 skip
#   Case 5: observe.sh project_id fallback が `unknown-cwd-<hash>` (git remote 不在 dir)
#   Case 6: 既存 project_id 解決 (git remote あり) regression 0
#
# 重要制約 (feedback_set_e_in_sourced_libs):
#   - file-top に set -euo pipefail を書かない
#   - 各 case 関数は ( set -uo pipefail; ... ) でラップして実行
#   - live ~/.claude/homunculus を絶対に汚染しない (HOMUNCULUS_DIR で隔離)
#
# 実行:
#   bash .claude/tests/harness-audit-c-batch-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AUDIT="$REPO_ROOT/.claude/scripts/harness-audit.py"
OBSERVE="$REPO_ROOT/.claude/skills/continuous-learning-v2/hooks/observe.sh"

if [ ! -f "$AUDIT" ]; then
  printf 'FAIL: %s not found\n' "$AUDIT" >&2
  exit 1
fi
if [ ! -x "$OBSERVE" ]; then
  printf 'FAIL: %s not executable\n' "$OBSERVE" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

TMP_DIR=$(mktemp -d "/tmp/harness-audit-c-batch-smoke.XXXXXX") || {
  printf 'FAIL: mktemp -d failed\n' >&2
  exit 1
}
trap 'rm -rf "$TMP_DIR"' EXIT

run_case() {
  local case_id="$1"
  local desc="$2"
  local test_fn="$3"
  if ( set -uo pipefail; "$test_fn" ) >/dev/null 2>&1; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS+1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL+1))
    FAILED_CASES+=("$case_id")
  fi
}

# fake-root 生成 helper: 最小限の docs/draft/ + .claude/settings.json
make_fake_root() {
  local root="$1"
  mkdir -p "$root/docs/draft" "$root/.claude"
  printf '{"hooks":{}}\n' > "$root/.claude/settings.json"
}

# === Case 1: stale draft 90 日超 detection ===
case_1() {
  local root="$TMP_DIR/c1-root"
  make_fake_root "$root"
  # 100 日前 mtime の draft (frontmatter で approval_required: true, approved_at: 空)
  local draft="$root/docs/draft/old-feature.md"
  cat > "$draft" <<'EOF'
<!--
approval_required: true
approved_at:
approved_by:
-->

# Old Feature draft

未承認のまま放置されている設計。
EOF
  # mtime を 100 日前にセット
  touch -t "$(date -v-100d +%Y%m%d%H%M 2>/dev/null || date -d '100 days ago' +%Y%m%d%H%M)" "$draft"

  local out
  out=$(cd "$root" && python3 "$AUDIT" --json 2>/dev/null)
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
sd = d.get("stale_drafts", {})
total = sd.get("total")
assert total == 1, "expected 1 stale draft, got %r" % total
paths = [x["path"] for x in sd.get("drafts", [])]
assert any("old-feature.md" in p for p in paths), "paths: %r" % paths
days = sd["drafts"][0]["days_old"]
assert days >= 90, "days_old: %r" % days
' >&2
}

# === Case 2: stale drafts 0 件 → silent (recent draft のみ) ===
case_2() {
  local root="$TMP_DIR/c2-root"
  make_fake_root "$root"
  # 今日 mtime の draft (未承認だが新しい)
  local draft="$root/docs/draft/recent-feature.md"
  cat > "$draft" <<'EOF'
<!--
approval_required: true
approved_at:
-->

# Recent feature draft
EOF

  local out
  out=$(cd "$root" && python3 "$AUDIT" --json 2>/dev/null)
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
sd = d.get("stale_drafts", {})
total = sd.get("total")
assert total == 0, "expected 0 stale drafts, got %r" % total
assert sd.get("draft_dir_present") is True
' >&2
}

# === Case 3: settings.local.json drift detection ===
case_3() {
  local root="$TMP_DIR/c3-root"
  make_fake_root "$root"
  # main: {"hooks":{},"env":{"DEBUG":"false"}}
  printf '%s\n' '{"hooks":{},"env":{"DEBUG":"false"}}' > "$root/.claude/settings.json"
  # local: {"hooks":{},"env":{"DEBUG":"true"},"permissions":{"allow":["Bash(npm)"]}}
  printf '%s\n' '{"hooks":{},"env":{"DEBUG":"true"},"permissions":{"allow":["Bash(npm)"]}}' > "$root/.claude/settings.local.json"

  local out
  out=$(cd "$root" && python3 "$AUDIT" --json 2>/dev/null)
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
sd = d.get("settings_drift", {})
assert sd.get("local_present") is True
dc = sd.get("drift_count", 0)
assert dc >= 2, "expected >=2 drifts, got %r" % dc
local_only_paths = [x["path"] for x in sd.get("local_only", [])]
assert any("permissions" in p for p in local_only_paths), "local_only paths: %r" % local_only_paths
mod_paths = [x["path"] for x in sd.get("modified", [])]
assert any("env.DEBUG" in p for p in mod_paths), "modified paths: %r" % mod_paths
' >&2
}

# === Case 4: settings.local.json 不在 → drift skip ===
case_4() {
  local root="$TMP_DIR/c4-root"
  make_fake_root "$root"
  # local file は作らない
  [ ! -f "$root/.claude/settings.local.json" ] || return 1

  local out
  out=$(cd "$root" && python3 "$AUDIT" --json 2>/dev/null)
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
sd = d.get("settings_drift", {})
lp = sd.get("local_present")
assert lp is False, "local_present should be False, got %r" % lp
assert sd.get("drift_count") == 0
' >&2
}

# === Case 5: observe.sh project_id fallback = unknown-cwd-<hash> (git remote 不在) ===
case_5() {
  local cwd_no_git="$TMP_DIR/c5-no-git"
  local home_iso="$TMP_DIR/c5-home"
  mkdir -p "$cwd_no_git" "$home_iso"

  # mock cwd は git repo ではない (git remote 取得失敗)
  # CLAUDE_PROJECT_DIR を渡さず、cwd で実行
  local input='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/foo"}}'

  HOMUNCULUS_DIR="$home_iso" \
    bash -c "cd '$cwd_no_git' && printf '%s' '$input' | HOMUNCULUS_DIR='$home_iso' bash '$OBSERVE'"

  # observations.jsonl を探す
  local obs_files
  obs_files=$(find "$home_iso" -name 'observations.jsonl' -type f 2>/dev/null)
  if [ -z "$obs_files" ]; then
    return 1
  fi

  # path に "unknown-cwd-" が含まれるかチェック
  local found=0
  while IFS= read -r f; do
    case "$f" in
      *unknown-cwd-*) found=1; break ;;
    esac
  done <<< "$obs_files"
  [ "$found" -eq 1 ] || return 1

  # record の project_id field でも検証
  local rec
  rec=$(tail -1 "$(echo "$obs_files" | head -1)")
  printf '%s' "$rec" | jq -e '.project_id | startswith("unknown-cwd-")' >/dev/null 2>&1 || return 1
  # scope も unknown-cwd であること
  local scope
  scope=$(printf '%s' "$rec" | jq -r '.scope')
  [ "$scope" = "unknown-cwd" ] || return 1
}

# === Case 6: 既存 git remote 解決 (regression) ===
case_6() {
  local home_iso="$TMP_DIR/c6-home"
  mkdir -p "$home_iso"

  # repo root を CLAUDE_PROJECT_DIR で渡す (git remote あり)
  local input='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/bar"}}'
  HOMUNCULUS_DIR="$home_iso" \
  CLAUDE_PROJECT_DIR="$REPO_ROOT" \
    bash -c "printf '%s' '$input' | HOMUNCULUS_DIR='$home_iso' CLAUDE_PROJECT_DIR='$REPO_ROOT' bash '$OBSERVE'"

  local obs_files
  obs_files=$(find "$home_iso" -name 'observations.jsonl' -type f 2>/dev/null)
  if [ -z "$obs_files" ]; then
    return 1
  fi

  # path に "unknown-cwd-" は含まれない (git remote 解決成功なので普通の hash)
  local has_unknown=0
  while IFS= read -r f; do
    case "$f" in
      *unknown-cwd-*) has_unknown=1; break ;;
    esac
  done <<< "$obs_files"
  [ "$has_unknown" -eq 0 ] || return 1

  # record の project_id が hex 12 文字 (sha256short)
  local rec
  rec=$(tail -1 "$(echo "$obs_files" | head -1)")
  printf '%s' "$rec" | jq -e '.project_id | test("^[0-9a-f]{12}$")' >/dev/null 2>&1 || return 1
  # scope は project (unknown-cwd ではない)
  local scope
  scope=$(printf '%s' "$rec" | jq -r '.scope')
  [ "$scope" = "project" ] || return 1
}

printf '===== task-25 C2+C3+C4 batch smoke =====\n'
run_case 1 "stale draft 90+ days unapproved → detected" case_1
run_case 2 "recent draft only → 0 stale drafts" case_2
run_case 3 "settings.local.json drift (modified + local_only) → detected" case_3
run_case 4 "settings.local.json absent → drift check skipped silently" case_4
run_case 5 "observe.sh project_id fallback = unknown-cwd-<hash>" case_5
run_case 6 "observe.sh git remote → 12-char hex project_id (regression)" case_6

printf '\n===== Result =====\n'
printf 'PASS: %d / 6\n' "$PASS"
printf 'FAIL: %d / 6\n' "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Failed cases: %s\n' "${FAILED_CASES[*]}"
  exit 1
fi
exit 0
