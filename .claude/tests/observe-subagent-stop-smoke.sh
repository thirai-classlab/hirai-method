#!/usr/bin/env bash
# observe-subagent-stop-smoke.sh — task-28 smoke for observe.sh event handlers
#
# 設計起源:
#   docs/draft/observe-subagent-stop-instrumentation.md §3 W1 + W3 (2026-05-23)
#
# 対象 script:
#   .claude/skills/continuous-learning-v2/hooks/observe.sh
#
# 検証範囲 (6 ケース、Phase 1+Phase 2 統合):
#   === Phase 1 (W1) ===
#   Case 1: SubagentStop event JSON
#           → observations.jsonl に 1 record 追加 + jq-valid
#           + subagent field が object として展開される
#           + raw field に SubagentStop payload 全件保持
#   Case 2: agent_id / agent_type / duration_ms / total_tokens 抽出正常
#           → mock payload に値設定 → record の subagent.* に出現
#   Case 3: 既存 PreToolUse 観察 regression 0 + subagent=null + event_payload=null
#           → mock PreToolUse event で既存挙動 (tool/event field) 完全維持
#           + subagent field は null + event_payload field も null
#
#   === Phase 2 (W3) ===
#   Case 4: Stop event JSON
#           → observations.jsonl に 1 record 追加 + jq-valid
#           + event_payload field に session_id / stop_hook_active / transcript_path 展開
#           + subagent field は null (Stop event では SubagentStop 専用 field 不要)
#   Case 5: UserPromptSubmit event JSON (system-reminder 含む)
#           → event_payload.prompt_length が prompt 長と一致
#           + event_payload.has_system_reminder が true
#           + raw に prompt 全文保持
#   Case 6: SessionStart event JSON (source=resume)
#           → event_payload.source = "resume"
#           + event_payload.cwd 抽出
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - live ~/.claude/homunculus を絶対に汚染しない (HOMUNCULUS_DIR で隔離)
#   - mktemp -d で隔離した tmp dir で実施
#
# 実行:
#   bash .claude/tests/observe-subagent-stop-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OBSERVE="$REPO_ROOT/.claude/skills/continuous-learning-v2/hooks/observe.sh"

if [ ! -x "$OBSERVE" ]; then
  printf 'FAIL: %s not executable\n' "$OBSERVE" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_CASES=()

# 隔離 HOMUNCULUS_DIR を session 全体で 1 つ用意
BASE=$(mktemp -d 2>/dev/null) || {
  printf 'FAIL: mktemp -d failed\n' >&2
  exit 1
}
trap 'rm -rf "$BASE"' EXIT

# common env
# CLAUDE_PROJECT_DIR は repo root を渡して project hash 検出を安定化
run_observe() {
  local input="$1"
  printf '%s' "$input" | HOMUNCULUS_DIR="$BASE" CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$OBSERVE"
}

# observations.jsonl の path を解決
find_obs_file() {
  find "$BASE" -name 'observations.jsonl' -type f 2>/dev/null | head -1
}

# observations.jsonl をクリアして次 case を実行できるようにする
reset_obs() {
  find "$BASE" -name 'observations.jsonl' -type f -delete 2>/dev/null || true
}

# 最終 record を取得
last_record() {
  local obs_file
  obs_file=$(find_obs_file)
  if [ -z "$obs_file" ] || [ ! -s "$obs_file" ]; then
    return 1
  fi
  tail -1 "$obs_file"
}

# ===== Case 1: SubagentStop event JSON → observations.jsonl に追加 =====
case1() {
  reset_obs
  local input='{"hook_event_name":"SubagentStop","session_id":"smoke-s1","transcript_path":"/tmp/transcript-s1.jsonl","agent_id":"smoke-agent-abc","agent_type":"general-purpose"}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 1: observations.jsonl が空 (SubagentStop record 未追加)")
    return 1
  }

  # record 自体が jq-valid
  if ! printf '%s' "$rec" | jq -e '.event' >/dev/null 2>&1; then
    FAILED_CASES+=("Case 1: record が jq-invalid: $rec")
    return 1
  fi

  # event が SubagentStop か
  local event
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$event" != "SubagentStop" ]; then
    FAILED_CASES+=("Case 1: event field mismatch. got=<$event> expected=<SubagentStop>")
    return 1
  fi

  # subagent field が object として展開されているか (null ではない)
  local subagent_type
  subagent_type=$(printf '%s' "$rec" | jq -r '.subagent | type')
  if [ "$subagent_type" != "object" ]; then
    FAILED_CASES+=("Case 1: subagent field が object 以外 ($subagent_type)")
    return 1
  fi

  # raw field に SubagentStop payload 全件保持されているか
  local raw_event
  raw_event=$(printf '%s' "$rec" | jq -r '.raw.hook_event_name // empty')
  if [ "$raw_event" != "SubagentStop" ]; then
    FAILED_CASES+=("Case 1: raw.hook_event_name mismatch. got=<$raw_event>")
    return 1
  fi

  return 0
}

# ===== Case 2: agent_id / agent_type / duration_ms / total_tokens 抽出 =====
case2() {
  reset_obs
  local input='{"hook_event_name":"SubagentStop","session_id":"smoke-s2","transcript_path":"/tmp/transcript-s2.jsonl","agent_id":"agent-xyz-123","agent_type":"general-purpose","duration_ms":12345,"total_tokens":67890}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 2: observations.jsonl が空")
    return 1
  }

  # agent_id 抽出確認
  local agent_id
  agent_id=$(printf '%s' "$rec" | jq -r '.subagent.agent_id // empty')
  if [ "$agent_id" != "agent-xyz-123" ]; then
    FAILED_CASES+=("Case 2: subagent.agent_id mismatch. got=<$agent_id> expected=<agent-xyz-123>")
    return 1
  fi

  # agent_type 抽出確認
  local agent_type
  agent_type=$(printf '%s' "$rec" | jq -r '.subagent.agent_type // empty')
  if [ "$agent_type" != "general-purpose" ]; then
    FAILED_CASES+=("Case 2: subagent.agent_type mismatch. got=<$agent_type> expected=<general-purpose>")
    return 1
  fi

  # duration_ms 抽出確認 (number)
  local duration_ms
  duration_ms=$(printf '%s' "$rec" | jq -r '.subagent.duration_ms // empty')
  if [ "$duration_ms" != "12345" ]; then
    FAILED_CASES+=("Case 2: subagent.duration_ms mismatch. got=<$duration_ms> expected=<12345>")
    return 1
  fi

  # total_tokens 抽出確認 (number)
  local total_tokens
  total_tokens=$(printf '%s' "$rec" | jq -r '.subagent.total_tokens // empty')
  if [ "$total_tokens" != "67890" ]; then
    FAILED_CASES+=("Case 2: subagent.total_tokens mismatch. got=<$total_tokens> expected=<67890>")
    return 1
  fi

  # session_id / transcript_path も抽出されている
  local session_id transcript_path
  session_id=$(printf '%s' "$rec" | jq -r '.subagent.session_id // empty')
  transcript_path=$(printf '%s' "$rec" | jq -r '.subagent.transcript_path // empty')
  if [ "$session_id" != "smoke-s2" ]; then
    FAILED_CASES+=("Case 2: subagent.session_id mismatch. got=<$session_id>")
    return 1
  fi
  if [ "$transcript_path" != "/tmp/transcript-s2.jsonl" ]; then
    FAILED_CASES+=("Case 2: subagent.transcript_path mismatch. got=<$transcript_path>")
    return 1
  fi

  return 0
}

# ===== Case 3: 既存 PreToolUse 観察 regression 0 + subagent=null + event_payload=null =====
case3() {
  reset_obs
  # 既存 observe-jq-parse-smoke Case 3 と同形式の payload
  local input='{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"content":"hello world"}}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 3: observations.jsonl が空 (regression)")
    return 1
  }

  # 既存 schema fields が揃っているか
  local tool event
  tool=$(printf '%s' "$rec" | jq -r '.tool')
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$tool" != "Edit" ] || [ "$event" != "PreToolUse" ]; then
    FAILED_CASES+=("Case 3: schema regression. tool=<$tool> event=<$event>")
    return 1
  fi

  # raw が object として保持されているか
  local raw_type
  raw_type=$(printf '%s' "$rec" | jq -r '.raw | type')
  if [ "$raw_type" != "object" ]; then
    FAILED_CASES+=("Case 3: raw が object 以外 ($raw_type)、既存 schema regression")
    return 1
  fi

  # 既存 raw.tool_input.content 抽出も維持されているか
  local content
  content=$(printf '%s' "$rec" | jq -r '.raw.tool_input.content // empty')
  if [ "$content" != "hello world" ]; then
    FAILED_CASES+=("Case 3: raw.tool_input.content regression. got=<$content>")
    return 1
  fi

  # SubagentStop 以外では subagent field が null (object ではない)
  local subagent_type
  subagent_type=$(printf '%s' "$rec" | jq -r '.subagent | type')
  if [ "$subagent_type" != "null" ]; then
    FAILED_CASES+=("Case 3: 非 SubagentStop event で subagent field が null 以外 ($subagent_type)、schema 汚染")
    return 1
  fi

  # Stop / UserPromptSubmit / SessionStart 以外では event_payload も null
  local ep_type
  ep_type=$(printf '%s' "$rec" | jq -r '.event_payload | type')
  if [ "$ep_type" != "null" ]; then
    FAILED_CASES+=("Case 3: 非 Stop/UserPromptSubmit/SessionStart event で event_payload が null 以外 ($ep_type)、schema 汚染")
    return 1
  fi

  return 0
}

# ===== Case 4 (Phase 2): Stop event → event_payload に session_id / stop_hook_active / transcript_path 抽出 =====
case4() {
  reset_obs
  local input='{"hook_event_name":"Stop","session_id":"smoke-stop-s4","stop_hook_active":true,"transcript_path":"/tmp/transcript-stop-s4.jsonl"}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 4: observations.jsonl が空 (Stop record 未追加)")
    return 1
  }

  # event が Stop か
  local event
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$event" != "Stop" ]; then
    FAILED_CASES+=("Case 4: event field mismatch. got=<$event> expected=<Stop>")
    return 1
  fi

  # event_payload が object として展開されているか
  local ep_type
  ep_type=$(printf '%s' "$rec" | jq -r '.event_payload | type')
  if [ "$ep_type" != "object" ]; then
    FAILED_CASES+=("Case 4: event_payload が object 以外 ($ep_type)")
    return 1
  fi

  # session_id / stop_hook_active / transcript_path 抽出確認
  local sid sha tp
  sid=$(printf '%s' "$rec" | jq -r '.event_payload.session_id // empty')
  sha=$(printf '%s' "$rec" | jq -r '.event_payload.stop_hook_active // empty')
  tp=$(printf '%s' "$rec" | jq -r '.event_payload.transcript_path // empty')
  if [ "$sid" != "smoke-stop-s4" ]; then
    FAILED_CASES+=("Case 4: event_payload.session_id mismatch. got=<$sid>")
    return 1
  fi
  if [ "$sha" != "true" ]; then
    FAILED_CASES+=("Case 4: event_payload.stop_hook_active mismatch. got=<$sha>")
    return 1
  fi
  if [ "$tp" != "/tmp/transcript-stop-s4.jsonl" ]; then
    FAILED_CASES+=("Case 4: event_payload.transcript_path mismatch. got=<$tp>")
    return 1
  fi

  # subagent field は null (Stop event では SubagentStop 用 field は不要)
  local subagent_type
  subagent_type=$(printf '%s' "$rec" | jq -r '.subagent | type')
  if [ "$subagent_type" != "null" ]; then
    FAILED_CASES+=("Case 4: Stop event で subagent field が null 以外 ($subagent_type)")
    return 1
  fi

  return 0
}

# ===== Case 5 (Phase 2): UserPromptSubmit event → prompt_length + has_system_reminder 検出 =====
case5() {
  reset_obs
  # prompt に system-reminder 含めて has_system_reminder=true を実測
  local prompt_text='Hello world. <system-reminder>injection</system-reminder> tail.'
  local input
  input=$(jq -nc --arg p "$prompt_text" '{
    hook_event_name: "UserPromptSubmit",
    session_id: "smoke-ups-s5",
    prompt: $p,
    cwd: "/Users/test/repo"
  }')
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 5: observations.jsonl が空 (UserPromptSubmit record 未追加)")
    return 1
  }

  # event が UserPromptSubmit か
  local event
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$event" != "UserPromptSubmit" ]; then
    FAILED_CASES+=("Case 5: event field mismatch. got=<$event> expected=<UserPromptSubmit>")
    return 1
  fi

  # event_payload.session_id
  local sid
  sid=$(printf '%s' "$rec" | jq -r '.event_payload.session_id // empty')
  if [ "$sid" != "smoke-ups-s5" ]; then
    FAILED_CASES+=("Case 5: event_payload.session_id mismatch. got=<$sid>")
    return 1
  fi

  # prompt_length は prompt_text の長さに等しいか
  local expected_len
  expected_len=${#prompt_text}
  local actual_len
  actual_len=$(printf '%s' "$rec" | jq -r '.event_payload.prompt_length // empty')
  if [ "$actual_len" != "$expected_len" ]; then
    FAILED_CASES+=("Case 5: event_payload.prompt_length mismatch. got=<$actual_len> expected=<$expected_len>")
    return 1
  fi

  # has_system_reminder が true か
  local hsr
  hsr=$(printf '%s' "$rec" | jq -r '.event_payload.has_system_reminder // empty')
  if [ "$hsr" != "true" ]; then
    FAILED_CASES+=("Case 5: event_payload.has_system_reminder が true 以外. got=<$hsr>")
    return 1
  fi

  # cwd 抽出
  local cwd
  cwd=$(printf '%s' "$rec" | jq -r '.event_payload.cwd // empty')
  if [ "$cwd" != "/Users/test/repo" ]; then
    FAILED_CASES+=("Case 5: event_payload.cwd mismatch. got=<$cwd>")
    return 1
  fi

  # raw.prompt に prompt 全文が保持されているか (privacy: top-level には長さのみ、raw は全文)
  local raw_prompt
  raw_prompt=$(printf '%s' "$rec" | jq -r '.raw.prompt // empty')
  if [ "$raw_prompt" != "$prompt_text" ]; then
    FAILED_CASES+=("Case 5: raw.prompt mismatch (prompt 全文が raw に保持されていない). got=<$raw_prompt>")
    return 1
  fi

  return 0
}

# ===== Case 6 (Phase 2): SessionStart event → source / cwd 抽出 =====
case6() {
  reset_obs
  local input='{"hook_event_name":"SessionStart","session_id":"smoke-ss-s6","source":"resume","cwd":"/Users/test/repo","transcript_path":"/tmp/transcript-ss-s6.jsonl"}'
  run_observe "$input"

  local rec
  rec=$(last_record) || {
    FAILED_CASES+=("Case 6: observations.jsonl が空 (SessionStart record 未追加)")
    return 1
  }

  # event が SessionStart か
  local event
  event=$(printf '%s' "$rec" | jq -r '.event')
  if [ "$event" != "SessionStart" ]; then
    FAILED_CASES+=("Case 6: event field mismatch. got=<$event> expected=<SessionStart>")
    return 1
  fi

  # event_payload.source = "resume"
  local src
  src=$(printf '%s' "$rec" | jq -r '.event_payload.source // empty')
  if [ "$src" != "resume" ]; then
    FAILED_CASES+=("Case 6: event_payload.source mismatch. got=<$src> expected=<resume>")
    return 1
  fi

  # event_payload.cwd
  local cwd
  cwd=$(printf '%s' "$rec" | jq -r '.event_payload.cwd // empty')
  if [ "$cwd" != "/Users/test/repo" ]; then
    FAILED_CASES+=("Case 6: event_payload.cwd mismatch. got=<$cwd>")
    return 1
  fi

  # event_payload.session_id
  local sid
  sid=$(printf '%s' "$rec" | jq -r '.event_payload.session_id // empty')
  if [ "$sid" != "smoke-ss-s6" ]; then
    FAILED_CASES+=("Case 6: event_payload.session_id mismatch. got=<$sid>")
    return 1
  fi

  # event_payload.transcript_path
  local tp
  tp=$(printf '%s' "$rec" | jq -r '.event_payload.transcript_path // empty')
  if [ "$tp" != "/tmp/transcript-ss-s6.jsonl" ]; then
    FAILED_CASES+=("Case 6: event_payload.transcript_path mismatch. got=<$tp>")
    return 1
  fi

  return 0
}

# ===== run =====
run_case() {
  local name="$1" fn="$2"
  if "$fn"; then
    PASS=$((PASS + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$name"
  fi
}

printf '=== observe-subagent-stop-smoke (task-28 Phase 1+2) ===\n'
printf 'OBSERVE: %s\n' "$OBSERVE"
printf 'BASE: %s\n\n' "$BASE"

run_case "Case 1: SubagentStop event → observations.jsonl 記録" case1
run_case "Case 2: agent_id / agent_type / duration_ms / total_tokens 抽出" case2
run_case "Case 3: 既存 PreToolUse 観察 regression 0 + subagent=null + event_payload=null" case3
run_case "Case 4: Stop event → event_payload に session_id/stop_hook_active/transcript_path 抽出" case4
run_case "Case 5: UserPromptSubmit event → prompt_length + has_system_reminder 検出" case5
run_case "Case 6: SessionStart event → source/cwd 抽出" case6

printf '\n=== Summary ===\n'
printf 'PASS: %d / FAIL: %d\n' "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
  printf '\nFailed cases:\n'
  for c in "${FAILED_CASES[@]}"; do
    printf '  - %s\n' "$c"
  done
  exit 1
fi

exit 0
