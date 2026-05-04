#!/usr/bin/env bash
# observe.sh — PreToolUse / PostToolUse hook for continuous-learning v2.1
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

# プロジェクト検出
project_id=""
project_name=""
project_root=""

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
if [ -n "$project_id" ]; then
  obs_dir="$HOMUNCULUS_DIR/projects/$project_id"
  scope="project"
else
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

# raw が壊れていても落ちないよう --argjson の代替で string 化
raw_safe=$(printf '%s' "$input" | jq -c '.' 2>/dev/null || echo '{}')

obs=$(jq -nc \
  --arg ts "$ts" \
  --arg event "$event" \
  --arg tool "$tool" \
  --arg pid "$project_id" \
  --arg pname "$project_name" \
  --arg scope "$scope" \
  --argjson raw "$raw_safe" \
  '{
     ts: $ts,
     event: $event,
     tool: $tool,
     project_id: $pid,
     project_name: $pname,
     scope: $scope,
     raw: $raw
   }' 2>/dev/null) || obs=""

if [ -n "$obs" ]; then
  printf '%s\n' "$obs" >> "$obs_dir/observations.jsonl" 2>/dev/null
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
