#!/usr/bin/env bash
# effective-hook-matrix-smoke.sh — task-71 Step 8 S-D
#
# 目的:
#   settings.json / preview / manifest / yml feature の整合性を検証する。
#
# 重要注意 (cutover 済、task-71 Step 7 完了後):
#   - live settings.json は dispatcher 形式に cutover 済。これが SSoT。
#     generate-settings.sh --check live は OK を返す (live == generated)。
#   - したがって SD-4 は OK 期待。DRIFT (rc != 0) は FAIL とする
#     (cutover 後に live が generated と乖離 = 配線回帰なので検出すべき)。
#
#   本 smoke の検証項目:
#     SD-1: preview (settings.generated.preview.json) に対して --check → OK 期待
#     SD-2: manifest の全 hook_command path が実在する
#     SD-3: manifest 内の各 event/matcher が preview に 1 dispatcher として配線されている
#     SD-4: live settings.json に対して --check → OK 期待 (cutover 済、DRIFT なら FAIL)
#     SD-5: dispatcher scripts が実行可能 (755)
#
# 実行: bash .claude/tests/effective-hook-matrix-smoke.sh
# 終了: 0 = SD-1/2/3/4/5 全 PASS / 1 = FAIL
#
# bash 3.2 互換 (macOS)。
# 規約: file-top set -u + case 別 ( set -uo pipefail ) + run_case。

set -u

# --- root 解決 ---
_resolve_root() (
  set -uo pipefail
  if [ -n "${HC_PROJECT_ROOT:-}" ] && [ -d "${HC_PROJECT_ROOT}" ]; then
    printf '%s' "${HC_PROJECT_ROOT}"; return 0
  fi
  local _sdir
  _sdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if command -v git >/dev/null 2>&1; then
    local r
    r=$(git -C "$_sdir" rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r" ] && [ -d "$r" ] && { printf '%s' "$r"; return 0; }
  fi
  if command -v git >/dev/null 2>&1; then
    local r2
    r2=$(git rev-parse --show-toplevel 2>/dev/null)
    [ -n "$r2" ] && [ -d "$r2" ] && { printf '%s' "$r2"; return 0; }
  fi
  pwd
)

ROOT="$(_resolve_root)"
MANIFEST="${ROOT}/.claude/hooks/dispatcher-manifest.tsv"
PREVIEW="${ROOT}/.claude/settings.generated.preview.json"
LIVE="${ROOT}/.claude/settings.json"
GENERATE_SCRIPT="${ROOT}/.claude/scripts/generate-settings.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/hook-matrix-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0
WARN=0

ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
warn() { WARN=$((WARN+1)); printf '  WARN: %s\n' "$1"; }

# ------------------------------------------------------------------
printf "=== S-D: effective-hook-matrix-smoke ===\n\n"

# --- SD-1: preview に対して --check が OK ---
printf "SD-1: generate-settings.sh --check preview → OK\n"
run_sd1() ( set -uo pipefail
  local rc=0
  bash "$GENERATE_SCRIPT" --check "$PREVIEW" >/dev/null 2>/dev/null || rc=$?
  printf '%s\n' "$rc" > "${TMPBASE}/result-sd1"
)
if [ ! -f "$GENERATE_SCRIPT" ]; then
  bad "SD-1 generate-settings.sh not found: $GENERATE_SCRIPT"
elif [ ! -f "$PREVIEW" ]; then
  bad "SD-1 preview not found: $PREVIEW (run: bash $GENERATE_SCRIPT)"
elif ! command -v jq >/dev/null 2>&1; then
  warn "SD-1 jq not available, skip"
  ok "SD-1 skip (jq required)"
else
  run_sd1
  sd1_rc="$(cat "${TMPBASE}/result-sd1" 2>/dev/null | tr -d '[:space:]')"
  if [ "$sd1_rc" = "0" ]; then
    ok "SD-1 --check preview: OK (in sync)"
  else
    bad "SD-1 --check preview: DRIFT (rc=${sd1_rc}) — preview may be stale, re-run generate-settings.sh"
  fi
fi

# --- SD-2: manifest の全 hook_command path が実在 ---
printf "\nSD-2: all hook_command paths in manifest exist\n"
if [ ! -f "$MANIFEST" ]; then
  bad "SD-2 manifest not found: $MANIFEST"
else
  missing=0
  total=0
  # awk で TAB 区切りを正確にパース (bash IFS=TAB は連続 TAB で field ずれが発生するため)
  # hook_command (col 4) の先頭 token (space 前) = script path
  while IFS= read -r hook_script; do
    [ -z "$hook_script" ] && continue
    hook_path="${ROOT}/.claude/hooks/${hook_script}"
    total=$((total+1))
    if [ ! -f "$hook_path" ]; then
      printf '  MISSING: %s\n' "$hook_path"
      missing=$((missing+1))
    fi
  done < <(awk -F'\t' 'NR>1 && NF>=4 && $1!="" && $4!="" { split($4, a, " "); print a[1] }' "$MANIFEST")
  if [ "$missing" -eq 0 ]; then
    ok "SD-2 all ${total} hook_command paths exist"
  else
    bad "SD-2 ${missing}/${total} hook_command paths missing"
  fi
fi

# --- SD-3: preview 内の各 event が manifest の event と対応する (+ 逆方向 diff + feature_key 確認) ---
printf "\nSD-3: preview hooks entries match manifest (event/matcher coverage)\n"
if [ ! -f "$PREVIEW" ] || ! command -v jq >/dev/null 2>&1; then
  if ! command -v jq >/dev/null 2>&1; then
    warn "SD-3 jq not available"
    ok "SD-3 skip"
  else
    bad "SD-3 preview not found"
  fi
else
  # manifest から (event,matcher) pair を抽出 (awk で空 matcher も保持)
  manifest_pairs="$(
    awk -F'\t' '
      NR==1{next} NF<6{next} $1==""{next}
      {print $1 "|" $2}
    ' "$MANIFEST" | sort -u
  )"
  # preview から dispatcher entries を抽出 (event / matcher)
  preview_entries="$(
    jq -r '
      .hooks // {} | to_entries[] |
      .key as $event |
      .value[] |
      ( $event + "|" + (.matcher // "") )
    ' "$PREVIEW" | sort -u
  )"
  # 順方向: manifest → preview (manifest にあって preview にない)
  drift=0
  for pair in $manifest_pairs; do
    if ! printf '%s\n' "$preview_entries" | grep -qxF "$pair"; then
      printf '  MISSING in preview: event/matcher=%s\n' "$pair"
      drift=$((drift+1))
    fi
  done
  if [ "$drift" -eq 0 ]; then
    ok "SD-3 all manifest (event,matcher) pairs covered in preview (forward)"
  else
    bad "SD-3 ${drift} manifest pair(s) missing in preview (forward)"
  fi

  # MED: 逆方向 diff — preview にあって manifest にない event/matcher を WARN 検出
  # (preview が manifest と乖離している場合 = generator または manifest の設計乖離)
  printf "\n  SD-3-rev: reverse diff (preview → manifest)\n"
  rev_drift=0
  for entry in $preview_entries; do
    # dispatcher 形式の matcher は jq で取れるが event/matcher は manifest と比較
    if ! printf '%s\n' "$manifest_pairs" | grep -qxF "$entry"; then
      printf '  WARN: in preview but not in manifest: event/matcher=%s\n' "$entry"
      rev_drift=$((rev_drift+1))
    fi
  done
  if [ "$rev_drift" -eq 0 ]; then
    ok "SD-3-rev no extra entries in preview vs manifest (reverse ok)"
  else
    warn "SD-3-rev ${rev_drift} preview entry/entries not in manifest — generator と manifest が乖離の可能性"
    ok "SD-3-rev recorded (WARN のみ、hard fail しない)"
  fi
fi

# --- SD-3-fk: manifest feature_key が harness-config.yml に宣言済か確認 (飾り toggle 検出) ---
printf "\nSD-3-fk: manifest feature_key declared in harness-config.yml\n"
YML_CONFIG="${ROOT}/.claude/harness-config.yml"
if [ ! -f "$MANIFEST" ] || [ ! -f "$YML_CONFIG" ]; then
  warn "SD-3-fk manifest or yml not found, skip"
  ok "SD-3-fk skip"
else
  fk_undeclared=0
  fk_total=0
  # manifest の feature_key (col5) を抽出し、空でないものだけ確認
  # manifest の feature_key 形式: 短縮形 "autonomous_action_guard"
  # yml の feature toggle 形式: "feature_<key>_enabled" または "review_required_<key>"
  while IFS= read -r fk; do
    [ -z "$fk" ] && continue
    fk_total=$((fk_total+1))
    # 検索パターン: feature_<fk>_enabled または <fk> 直接マッチ (review_required_* 等) の 2 系統
    if grep -qE "^[[:space:]]*(feature_${fk}_enabled|${fk})[[:space:]]*:" "$YML_CONFIG"; then
      : # found
    else
      printf '  WARN: feature_key not declared in yml: %s (tried: feature_%s_enabled / %s)\n' "$fk" "$fk" "$fk"
      fk_undeclared=$((fk_undeclared+1))
    fi
  done < <(awk -F'\t' 'NR>1 && NF>=5 && $5!="" { print $5 }' "$MANIFEST" | sort -u)
  if [ "$fk_undeclared" -eq 0 ]; then
    ok "SD-3-fk all ${fk_total} feature_key(s) declared in harness-config.yml"
  else
    warn "SD-3-fk ${fk_undeclared}/${fk_total} feature_key(s) not declared in yml — 飾り toggle の可能性"
    ok "SD-3-fk recorded (WARN のみ、hard fail しない)"
  fi
fi

# --- SD-4: live settings に対して --check (cutover 済: OK 期待、DRIFT なら FAIL) ---
printf "\nSD-4: generate-settings.sh --check live (cutover complete → OK expected)\n"
run_sd4() ( set -uo pipefail
  local rc=0
  bash "$GENERATE_SCRIPT" --check "$LIVE" >/dev/null 2>/dev/null || rc=$?
  printf '%s\n' "$rc" > "${TMPBASE}/result-sd4"
)
if [ ! -f "$LIVE" ]; then
  bad "SD-4 live settings.json not found"
elif ! command -v jq >/dev/null 2>&1; then
  warn "SD-4 jq not available, skip"
  ok "SD-4 skip"
else
  run_sd4
  sd4_rc="$(cat "${TMPBASE}/result-sd4" 2>/dev/null | tr -d '[:space:]')"
  if [ "$sd4_rc" = "0" ]; then
    ok "SD-4 --check live: OK (cutover complete, live=generated)"
  else
    # cutover 済なので DRIFT は配線回帰 — FAIL
    bad "SD-4 --check live: DRIFT (rc=${sd4_rc}) — live settings.json diverged from generated. Re-run generate-settings.sh --out .claude/settings.json to re-sync."
  fi
fi

# --- SD-5: dispatcher scripts themselves are executable ---
printf "\nSD-5: all dispatcher scripts are executable (755)\n"
dispatcher_fail=0
for d in pre-tool-use-dispatcher.sh post-tool-use-dispatcher.sh stop-dispatcher.sh \
          subagent-stop-dispatcher.sh session-start-dispatcher.sh \
          user-prompt-submit-dispatcher.sh notification-dispatcher.sh; do
  p="${ROOT}/.claude/hooks/${d}"
  if [ ! -f "$p" ]; then
    printf '  MISSING dispatcher: %s\n' "$d"
    dispatcher_fail=$((dispatcher_fail+1))
  elif [ ! -x "$p" ]; then
    printf '  NOT EXECUTABLE: %s\n' "$p"
    dispatcher_fail=$((dispatcher_fail+1))
  fi
done
if [ "$dispatcher_fail" -eq 0 ]; then
  ok "SD-5 all 7 dispatcher scripts present and executable"
else
  bad "SD-5 ${dispatcher_fail} dispatcher script(s) missing or not executable"
fi

# ------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
printf "\n===== S-D Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
printf "WARN: %d\n" "$WARN"
printf "Note: cutover 済 — SD-4 は live==generated の OK を期待する。\n"
printf "      DRIFT なら配線回帰: generate-settings.sh --out .claude/settings.json で再生成する。\n"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
