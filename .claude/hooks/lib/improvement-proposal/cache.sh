#!/usr/bin/env bash
# cache.sh — improvement-proposal の TTL 1h cache layer (task-22 W5)
#
# 役割:
#   集計結果を TTL 1h で cache し SessionStart 時間を短縮する。
#   cache 不在 / 期限切れ → 集計実行 → cache 保存 → stderr
#   cache hit → cache の payload を stderr に流して exit 0
#   空集計も cache する (JSONL 不在環境で都度 fullscan を防ぐ)
#
# 入力 (caller が事前に export):
#   ABS_STATE_DIR             — state dir 絶対 path
#   CACHE_TTL_SECONDS         — TTL 秒数 (default 3600、整数値検証済)
#   CACHE_FILE                — cache.json の絶対 path
#   CACHE_ENABLED             — true/false (HC_IMPROVEMENT_PROPOSAL_CACHE_ENABLED)
#
# 提供関数:
#   _file_mtime <path>        — stat の cross-platform 互換 mtime 取得
#   _cache_hit                — cache hit なら return 0
#   _write_cache              — 集計結果を CACHE_FILE に書き込む

# stat の cross-platform 互換 (macOS: -f %m / Linux: -c %Y)
_file_mtime() {
  local f="$1"
  local m
  m=$(stat -f %m "$f" 2>/dev/null) || m=$(stat -c %Y "$f" 2>/dev/null) || m=""
  printf '%s' "$m"
}

# cache hit 判定 (jq 不在環境では cache skip, fail-open で再集計)
_cache_hit() {
  case "$CACHE_ENABLED" in
    false|False|FALSE|0|no|off) return 1 ;;
  esac
  command -v jq >/dev/null 2>&1 || return 1
  [ -f "$CACHE_FILE" ] || return 1

  local mtime now age
  mtime=$(_file_mtime "$CACHE_FILE")
  [ -n "$mtime" ] || return 1
  now=$(date +%s)
  age=$((now - mtime))
  [ "$age" -lt "$CACHE_TTL_SECONDS" ] || return 1

  # JSON validity 確認 (corrupt なら fallback)
  jq -e '.payload' "$CACHE_FILE" >/dev/null 2>&1 || return 1
  return 0
}

# cache 書き込み (集計結果を保存、空集計も含めて TTL 1h で fullscan を防ぐ)
# caller が事前に export 必須: CACHE_TMP (集計 stderr 内容の tmp file)
#                              HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE
_write_cache() {
  case "$CACHE_ENABLED" in
    false|False|FALSE|0|no|off) return 0 ;;
  esac
  command -v jq >/dev/null 2>&1 || return 0
  [ -d "$ABS_STATE_DIR" ] || mkdir -p "$ABS_STATE_DIR" 2>/dev/null || return 0

  local payload generated_at obs_count obs_count_int
  payload=$(cat "$CACHE_TMP" 2>/dev/null || printf '')
  generated_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  obs_count=$(cat "$HC_IMPROVEMENT_PROPOSAL_OBS_COUNT_FILE" 2>/dev/null || printf '0')
  # obs_count を整数化 (jq --argjson は数値必須、空文字 / 非数字なら 0)
  case "$obs_count" in
    ''|*[!0-9]*) obs_count_int=0 ;;
    *) obs_count_int="$obs_count" ;;
  esac

  local tmp_out
  tmp_out="$ABS_STATE_DIR/.cache.json.tmp.$$"
  jq -n \
    --arg ga "$generated_at" \
    --argjson ttl "$CACHE_TTL_SECONDS" \
    --arg pl "$payload" \
    --argjson oc "$obs_count_int" \
    '{generated_at: $ga, ttl_seconds: $ttl, payload: $pl, source_observations_count: $oc}' \
    > "$tmp_out" 2>/dev/null && mv "$tmp_out" "$CACHE_FILE" 2>/dev/null || rm -f "$tmp_out" 2>/dev/null
}
