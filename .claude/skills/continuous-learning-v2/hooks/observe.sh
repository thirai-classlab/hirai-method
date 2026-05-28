#!/usr/bin/env bash
# observe.sh — PreToolUse / PostToolUse / SubagentStop / Stop / UserPromptSubmit / SessionStart hook for continuous-learning v2.1
#
# 役割:
#   - Hook JSON を stdin から受け取り、ローカルに観察記録を蓄積
#   - プロジェクトコンテキスト（git remote / repo path）を検出して project-scoped storage に振り分け
#   - 必ず exit 0 で抜ける（agent flow をブロックしない）
#
# 設計原則:
#   - fail-open: jq/git が無くても crash しない
#   - low-overhead: ≤100ms 目標、3秒 timeout 内
#   - privacy-first: 送信せず、homunculus 配下に永続化のみ
#
# 環境変数:
#   HOMUNCULUS_DIR (default: $HOME/.claude/homunculus)
#   CLAUDE_PROJECT_DIR (Claude Code が注入する project root)
#   CLAUDE_OBSERVE_DEBUG=1  → /tmp/claude-observe-debug.log にダンプ
#   OBSERVE_LOCK_TIMEOUT_MS (default: 2000) → append lock 取得の最大待ち時間 (ms)
#
# 拡張履歴:
#   - 2026-05-23 task-28 W1 (Phase 1): SubagentStop event 配線追加
#     - subagent 完了 metric (agent_id / agent_type / duration_ms / total_tokens) を
#       top-level の subagent field に抽出
#     - 既存 PreToolUse / PostToolUse の挙動は完全維持 (behavior-preserving)
#     - 起源: docs/draft/observe-subagent-stop-instrumentation.md §3 W1
#     - 目的: task-21 W3 採用判定基準 4 (true handoff latency 秒オーダー) の真値計測 unblock
#   - 2026-05-23 task-28 W3 (Phase 2): Stop / UserPromptSubmit / SessionStart 3 event 追加配線
#     - Stop event: session 終了時の最終状態 (session_id / stop_hook_active / transcript_path)
#     - UserPromptSubmit event: user prompt 到来 (prompt 内容長 / system_reminder 検出 / session_id)
#     - SessionStart event: session 開始 (source = startup/resume/clear、cwd、mode)
#     - 既存 SubagentStop / PreToolUse / PostToolUse の挙動は完全維持
#     - 起源: docs/draft/observe-subagent-stop-instrumentation.md §3 W3
#     - 目的: session lifecycle 全 event 捕捉 + Loop モード規律後追い分析 + 注入数 audit
#   - 2026-05-28 task-53 (observe-sh-flock): observations.jsonl append の排他化
#     - 並行 subagent が同時 append しても record interleave (JSON 破損) が起きないよう
#       flock (利用可能時) / mkdir lock (flock 不在の macOS 等) で append を排他化
#     - fail-open: lock 取得失敗でも観察を落とさず lock 無し append にフォールバック
#     - 起源: docs/draft/harness-health-improvements.md §3 task-53 (classlab で 122 件 corruption 実証)

set -u

HOMUNCULUS_DIR="${HOMUNCULUS_DIR:-$HOME/.claude/homunculus}"

# stdin 取得（hook JSON）
input=$(cat 2>/dev/null || true)

# debug
if [ "${CLAUDE_OBSERVE_DEBUG:-}" = "1" ]; then
  printf '[%s] %s\n---\n' "$(date -u +%FT%TZ)" "$input" >> /tmp/claude-observe-debug.log 2>/dev/null
fi

# 必須コマンド欠如時はサイレント終了
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# === task-53: append 排他化ヘルパ ===
#
# observations.jsonl への並行 append を排他化する。lock 無しの `>>` 並行 append は
# record interleave で JSON 破損する (大 record は 1 write() に収まらず PIPE_BUF を
# 超えて split されるため、classlab で 122 件 corruption 実証)。
#
# 戦略:
#   1. flock があれば flock -x で排他 (Linux 等)
#   2. flock 不在 (macOS 標準) は mkdir atomic lock + retry/timeout で fallback
#   3. lock 取得失敗 (timeout) でも観察を落とさず lock 無し append にフォールバック (fail-open)
#
# fail policy: caller の shell flags へ leak させないため subshell 関数化
# (`do_xxx() ( set -uo pipefail; ... )`、CLAUDE.md HIGH 教訓 SIGPIPE/leak 回避)。
#
# 使い方: append_locked "<line>" "<jsonl_path>"

# flock 経由 append (利用可能時のみ呼ばれる)。subshell 局所化。
_append_with_flock() (
  set -uo pipefail
  local line="$1" target="$2" lockfile="$3" timeout_sec="$4"
  # fd 9 を lockfile に割り当て、flock -w で timeout 付き排他取得
  exec 9>"$lockfile" 2>/dev/null || return 1
  if flock -x -w "$timeout_sec" 9 2>/dev/null; then
    printf '%s\n' "$line" >> "$target" 2>/dev/null
    # fd close で lock 自動解放
    exec 9>&- 2>/dev/null || true
    return 0
  fi
  exec 9>&- 2>/dev/null || true
  return 1
)

# mkdir atomic lock 経由 append (flock 不在環境)。subshell 局所化。
_append_with_mkdir_lock() (
  set -uo pipefail
  local line="$1" target="$2" lockdir="$3" timeout_ms="$4"
  local waited_ms=0
  local step_ms=20
  local acquired=0
  # trap で必ず lockdir 解放 (subshell EXIT 局所、caller へ leak しない)
  trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
  while [ "$waited_ms" -lt "$timeout_ms" ]; do
    if mkdir "$lockdir" 2>/dev/null; then
      acquired=1
      break
    fi
    # 20ms sleep (perl/sleep 不要、bash 組込みで近似)
    sleep 0.02 2>/dev/null || true
    waited_ms=$((waited_ms + step_ms))
  done
  if [ "$acquired" -ne 1 ]; then
    return 1
  fi
  printf '%s\n' "$line" >> "$target" 2>/dev/null
  return 0
)

# 排他 append の本体。lock 取得失敗時は lock 無し append にフォールバック (fail-open)。
append_locked() {
  local line="$1" target="$2"
  local timeout_ms="${OBSERVE_LOCK_TIMEOUT_MS:-2000}"
  local lockfile="$target.lock"

  if command -v flock >/dev/null 2>&1; then
    # flock は秒単位 (小数許容)。ms → sec へ変換 (整数丸めで下限 1s 確保)
    local timeout_sec=$((timeout_ms / 1000))
    [ "$timeout_sec" -lt 1 ] && timeout_sec=1
    if _append_with_flock "$line" "$target" "$lockfile" "$timeout_sec"; then
      return 0
    fi
  else
    if _append_with_mkdir_lock "$line" "$target" "$lockfile.d" "$timeout_ms"; then
      return 0
    fi
  fi

  # fail-open: lock 取得に失敗しても観察を落とさない (最悪 lock 無し append)
  printf '%s\n' "$line" >> "$target" 2>/dev/null
  return 0
}

# プロジェクト検出
project_id=""
project_name=""
project_root=""
scope=""

# 優先順: CLAUDE_PROJECT_DIR > git remote > git toplevel > global fallback
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
  project_root="$CLAUDE_PROJECT_DIR"
  cd "$project_root" 2>/dev/null || true
fi

if command -v git >/dev/null 2>&1; then
  if remote=$(git remote get-url origin 2>/dev/null); then
    # remote URL を正規化（末尾 .git 除去・https↔ssh 統一）
    canon=$(printf '%s' "$remote" | sed -E 's|^git@([^:]+):|https://\1/|; s|\.git$||')
    project_id=$(printf '%s' "$canon" | shasum -a 256 2>/dev/null | cut -c1-12)
    project_name=$(printf '%s' "$canon" | sed 's|^.*/||')
  elif toplevel=$(git rev-parse --show-toplevel 2>/dev/null); then
    project_id=$(printf '%s' "$toplevel" | shasum -a 256 2>/dev/null | cut -c1-12)
    project_name=$(basename "$toplevel")
    project_root="$toplevel"
  fi
fi

# 保存先決定
#
# task-25 C4: project_id 未解決時の global pool 流入を防ぐため
# `unknown-cwd-<sha256short(cwd)>` を fallback として使用。
# git remote 不在 + 複数 dir で観察した場合の混線を解消し、
# 各 dir が独立 project_id を持つ。
if [ -z "$project_id" ]; then
  cwd_for_hash="${project_root:-$PWD}"
  cwd_hash=$(printf '%s' "$cwd_for_hash" | shasum -a 256 2>/dev/null | cut -c1-12)
  if [ -n "$cwd_hash" ]; then
    project_id="unknown-cwd-$cwd_hash"
    project_name="unknown-cwd"
    scope="unknown-cwd"
  fi
fi

if [ -n "$project_id" ]; then
  obs_dir="$HOMUNCULUS_DIR/projects/$project_id"
  # scope は project (上の C4 block 内で unknown-cwd が代入されていればそのまま)
  scope="${scope:-project}"
else
  # shasum 未利用環境 (極稀) の保険
  obs_dir="$HOMUNCULUS_DIR"
  scope="global"
fi

# ディレクトリ作成（mkdir -p は冪等・高速）
mkdir -p "$obs_dir/instincts/personal" "$obs_dir/instincts/inherited" \
         "$obs_dir/evolved/skills" "$obs_dir/evolved/commands" "$obs_dir/evolved/agents" 2>/dev/null

# 観察レコード生成
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
event=$(printf '%s' "$input" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)
tool=$(printf '%s' "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null)

# === task-28 W1: SubagentStop 固有 payload 抽出 ===
#
# SubagentStop event の場合、subagent 完了の metric を top-level field に抽出する。
# 既存 raw field (全 payload) との二重持ちで観察 / 検索の柔軟性を確保する。
#
# 抽出 fields:
#   - agent_id: subagent の ID (handoff latency 計測 + 個別 subagent 追跡用)
#   - agent_type: subagent_type (e.g., "general-purpose" / "Explore" / "Task")
#   - duration_ms: subagent 起動から完了までの実時間 (available なら)
#   - total_tokens: subagent が消費した token 数 (available なら)
#   - session_id / transcript_path: 後続 cross-reference 用
#
# default は null literal (jq object form)。SubagentStop 以外の event では
# top-level subagent field が null になるため既存 schema 互換を保てる。
subagent_payload="null"
if [ "$event" = "SubagentStop" ]; then
  subagent_payload=$(printf '%s' "$input" | jq -c '{
    agent_id: (.agent_id // .subagent_id // null),
    agent_type: (.agent_type // .subagent_type // null),
    duration_ms: (.duration_ms // null),
    total_tokens: (.total_tokens // null),
    session_id: (.session_id // null),
    transcript_path: (.transcript_path // null)
  }' 2>/dev/null || echo 'null')
fi

# === task-28 W3 (Phase 2): Stop / UserPromptSubmit / SessionStart 固有 payload 抽出 ===
#
# 既存 SubagentStop と同パターン: event 固有 metric を top-level field に抽出し
# raw との二重持ちで観察柔軟性を確保。default は null literal。
#
# event_payload 抽出 schema:
#   - Stop: session_id / stop_hook_active / transcript_path
#       (session 終了時の最終状態、Loop モード遵守事項 7 違反の後追い分析素材)
#   - UserPromptSubmit: session_id / prompt_length / has_system_reminder / cwd
#       (注入数 audit 用、has_system_reminder で system-reminder 注入数集計)
#       prompt_length は content の長さ (privacy: 内容そのものは raw に保持、抽出は長さのみ)
#   - SessionStart: session_id / source / cwd / transcript_path
#       (source = "startup" / "resume" / "clear"、resume 比率分析素材)
#
# Stop / UserPromptSubmit / SessionStart 以外の event では event_payload が null literal で
# 既存 schema 互換維持。
event_payload="null"
case "$event" in
  Stop)
    event_payload=$(printf '%s' "$input" | jq -c '{
      session_id: (.session_id // null),
      stop_hook_active: (.stop_hook_active // null),
      transcript_path: (.transcript_path // null)
    }' 2>/dev/null || echo 'null')
    ;;
  UserPromptSubmit)
    # prompt 内容自体は raw に保持。top-level には privacy 配慮で長さ + system-reminder 検出のみ。
    event_payload=$(printf '%s' "$input" | jq -c '{
      session_id: (.session_id // null),
      prompt_length: ((.prompt // "") | length),
      has_system_reminder: (((.prompt // "") | contains("<system-reminder>"))),
      cwd: (.cwd // null)
    }' 2>/dev/null || echo 'null')
    ;;
  SessionStart)
    event_payload=$(printf '%s' "$input" | jq -c '{
      session_id: (.session_id // null),
      source: (.source // null),
      cwd: (.cwd // null),
      transcript_path: (.transcript_path // null)
    }' 2>/dev/null || echo 'null')
    ;;
esac

# raw は --rawfile 経由で安全に passthrough する。
# --argjson は nested string escape (literal control char / parse 失敗 raw_safe) で
# 56% の records が破損していた (docs/draft/observe-jq-parse-fix.md §1)。
# --rawfile は string として読み込み、jq 側で fromjson? で再解釈することで
# schema 互換 (raw が object のまま) を保ちつつ全 payload を保護する。
raw_safe=$(printf '%s' "$input" | jq -c '.' 2>/dev/null || echo '{}')

obs=$(jq -nc \
  --arg ts "$ts" \
  --arg event "$event" \
  --arg tool "$tool" \
  --arg pid "$project_id" \
  --arg pname "$project_name" \
  --arg scope "$scope" \
  --argjson subagent "$subagent_payload" \
  --argjson event_payload "$event_payload" \
  --rawfile raw <(printf '%s' "$raw_safe") \
  '{
     ts: $ts,
     event: $event,
     tool: $tool,
     project_id: $pid,
     project_name: $pname,
     scope: $scope,
     subagent: $subagent,
     event_payload: $event_payload,
     raw: ($raw | fromjson? // {})
   }' 2>/dev/null) || obs=""

if [ -n "$obs" ]; then
  # task-53: flock / mkdir lock で排他 append (並行 subagent の record interleave 防止)
  append_locked "$obs" "$obs_dir/observations.jsonl"
fi

# project レジストリ更新（global 1ヶ所）
if [ -n "$project_id" ]; then
  reg="$HOMUNCULUS_DIR/projects.json"
  mkdir -p "$HOMUNCULUS_DIR" 2>/dev/null
  if [ ! -f "$reg" ]; then
    echo '{}' > "$reg" 2>/dev/null
  fi
  if [ -f "$reg" ]; then
    tmp=$(mktemp 2>/dev/null) || tmp=""
    if [ -n "$tmp" ]; then
      jq --arg id "$project_id" \
         --arg name "$project_name" \
         --arg root "$project_root" \
         --arg ts "$ts" \
         '.[$id] = ((.[$id] // {}) + {name: $name, root: $root, last_seen: $ts})' \
         "$reg" > "$tmp" 2>/dev/null && mv "$tmp" "$reg" 2>/dev/null
      rm -f "$tmp" 2>/dev/null
    fi
  fi

  # project.json を mirror
  pjson="$obs_dir/project.json"
  jq -n --arg id "$project_id" \
        --arg name "$project_name" \
        --arg root "$project_root" \
        --arg ts "$ts" \
        '{id:$id, name:$name, root:$root, last_seen:$ts}' \
        > "$pjson" 2>/dev/null
fi

# 必ず exit 0
exit 0
