#!/usr/bin/env bash
# self-doctor.sh — task-87 Step 1 (P1-3)
#
# 役割:
#   install 直後および consuming repo での随時再実行で、期待外 setup issue のみを
#   3 点提示 format (why / fix / silence) で検出・報告する。built-in `/doctor` の
#   proxy 検証層として harness 責務範囲 (D1-D8) をカバーする。
#
# 設計 SSoT:
#   docs/draft/install-self-doctor.md §3.1 (D1-D8 check + WARN/INFO 分類) /
#   §3.2 (3 点提示 format) / §3.3 (exit code 2 層 fail-open) / §3.5 (feature toggle) /
#   §3.6 Step 1
#
# 分類原則 (draft §3.1):
#   - install.sh の責務内で生成済のはずの成果物の欠落 / 破損 = WARN (期待外)
#   - user しか埋められない値 / user 手動 step 未了            = INFO (期待値内、absorb)
#
# 3 点提示 format (draft §3.2、第一原理 v2 §2.3 BLOCK 教育 3 点提示に整合):
#   [self-doctor] WARN D<N>: <title>
#     why: <理由>
#     fix: <復旧 1 行コマンド>
#     silence: <env 変数>
#
# exit code 2 層 fail-open (draft §3.3):
#   - 本 script 単体   : WARN >= 1 → exit 1、INFO のみ → exit 0
#   - install.sh 呼出側 : `|| true` で常に exit 0 (Step 2 で統合)
#
# usage:
#   self-doctor.sh                          # 全 check 実行
#   self-doctor.sh --help                   # usage 表示
#   self-doctor.sh --verbose                # INFO 詳細展開 (default: 件数のみ)
#   self-doctor.sh --no-color               # ANSI 色コード無効化 (現状は色未使用のため互換のみ)
#
# 環境変数 (silence / skip):
#   HC_FEATURE_SELF_DOCTOR_ENABLED=false    # 全 check skip + exit 0
#   HC_SELF_DOCTOR_D1_SKIP=1                # D1 (local.yml) skip
#   HC_SELF_DOCTOR_D2_SKIP=1                # D2 (settings.json 配線) skip
#   HC_SELF_DOCTOR_D3_SKIP=1                # D3 (harness_version stamp) skip
#   HC_SELF_DOCTOR_D4_SKIP=1                # D4 (harness_npm_version stamp) skip
#   HC_SELF_DOCTOR_D5_SKIP=1                # D5 (hooks 実行 bit) skip
#   HC_SELF_DOCTOR_D6_SKIP=1                # D6 (guard effective state) skip
#   HC_SELF_DOCTOR_D7_SKIP=1                # D7 (.mcp.json env 前提) skip
#   HC_SELF_DOCTOR_D8_SKIP=1                # D8 (settings.local.json 健全性) skip
#
# 制約 / 規範:
#   - file-top: `set -uo pipefail` (set -e 禁止、fail-open 契約、
#     feedback_set_e_in_sourced_libs 規範遵守)
#   - 全 WARN に why: / fix: / silence: の 3 行必須 (draft §3.2)
#   - INFO は件数集約 default、--verbose で個別展開
#   - config-loader.sh の PROJECT_ROOT 解決規約と同期
#     (env HC_PROJECT_ROOT > CLAUDE_PROJECT_DIR > git rev-parse > pwd)

set -uo pipefail

# ============================================================
# arg parse
# ============================================================
VERBOSE=false
NO_COLOR=false
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose|-v) VERBOSE=true; shift ;;
    --no-color)   NO_COLOR=true; shift ;;
    --help|-h)
      cat <<'HELP_EOF'
Usage: self-doctor.sh [--verbose] [--no-color] [--help]

install 直後および consuming repo での随時再実行で、期待外 setup issue のみを
3 点提示 format (why / fix / silence) で検出・報告する。

Checks (D1-D8):
  D1  harness-config.local.yml 生成済 check
  D2  settings.json dispatcher 配線 (generate-settings.sh --check 委譲)
  D3  harness_version stamp の存在と ISO-8601 format
  D4  harness_npm_version stamp の存在 (常時 INFO)
  D5  .claude/hooks/*.sh の 755 実行 bit 一括 check
  D6  guard effective state (hc-config.sh --summary 委譲、preset-aware)
  D7  .mcp.json env 前提 placeholder 一覧 (常時 INFO、check-required-env.sh 委譲)
  D8  settings.local.json 健全性 (JSON valid + 重複 key heuristic)

Options:
  --verbose, -v   INFO を件数集約せず 1 件ずつ展開表示
  --no-color      ANSI 色コード無効化 (現状 no-op、互換)
  --help, -h      本 usage 表示

Silence env vars:
  HC_FEATURE_SELF_DOCTOR_ENABLED=false    全 check skip + exit 0
  HC_SELF_DOCTOR_D<N>_SKIP=1              個別 check skip (D1/D2/D3/D4/D5/D6/D7/D8)

Exit codes:
  0  問題なし (WARN 0)
  1  WARN >= 1 検出 (install.sh 呼出側は `|| true` で吸収、install は常に exit 0)
HELP_EOF
      exit 0
      ;;
    *)
      printf '[self-doctor] ERROR: unknown arg: %s (see --help)\n' "$1" >&2
      exit 64
      ;;
  esac
done

# ============================================================
# PROJECT_ROOT 解決 (config-loader.sh Step 1/2 と同一規約)
# ============================================================
_resolve_project_root() {
  if [ -n "${HC_PROJECT_ROOT:-}" ]; then
    printf '%s' "$HC_PROJECT_ROOT"
    return 0
  fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "${CLAUDE_PROJECT_DIR}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"
    return 0
  fi
  if command -v git >/dev/null 2>&1; then
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$root" ] && [ -d "$root" ]; then
      printf '%s' "$root"
      return 0
    fi
  fi
  pwd
}

PROJECT_ROOT="$(_resolve_project_root)"

# ============================================================
# feature toggle (config-loader.sh 経由、fail-open)
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_LOADER="$PROJECT_ROOT/.claude/hooks/lib/config-loader.sh"
if [ -f "$CONFIG_LOADER" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER" 2>/dev/null || true
fi

# BLOCK message 統一 API (task-94 P2-3 initial caller、docs/draft/lib-block-message-4args.md §3.6)
# self-doctor は WARN / INFO 出力の initial caller として dogfood する。
# 4 args API (why / fix / silence / docs) を wrapper (_sd_warn / _sd_info) で
# 5-to-4 args migration し、self-doctor 固有の prefix ([self-doctor] WARN D<N>: <title>)
# は wrapper 側で吸収する (§3.6 の caller-side prefix 契約)。
BLOCK_MESSAGE_LIB="$PROJECT_ROOT/.claude/hooks/lib/block-message.sh"
if [ -f "$BLOCK_MESSAGE_LIB" ]; then
  # shellcheck source=/dev/null
  . "$BLOCK_MESSAGE_LIB" 2>/dev/null || true
fi

if command -v is_feature_enabled >/dev/null 2>&1; then
  if ! is_feature_enabled self_doctor; then
    exit 0
  fi
fi

# ============================================================
# state 集計
# ============================================================
WARN_COUNT=0
INFO_COUNT=0
INFO_LINES=""   # verbose 時に append (改行区切り)

# task-94 migration §3.6: 5-to-4 args (d_id / title は caller-side wrapper で prefix 吸収)
#
# emit_warn <d_id> <title> <why> <fix> <silence>  (5 args, self-doctor 固有 signature)
#   内部で lib の emit_warn (4 args: why / fix / bypass_env / docs_link) を呼出。
#   d_id / title は self-doctor 固有 prefix として header 行で emit。
#   docs_link は self-doctor 側では draft §11.2 pointer が未整備のため空を渡す (§3.6)。
emit_warn() {
  local d_id="$1" title="$2" why="$3" fix="$4" silence="$5"
  # self-doctor 固有 header 行 (backwards-compatible format 維持)
  printf '[self-doctor] WARN %s: %s\n' "$d_id" "$title"
  printf '  why: %s\n' "$why"
  printf '  fix: %s\n' "$fix"
  printf '  silence: %s\n' "$silence"
  WARN_COUNT=$((WARN_COUNT + 1))
}

# emit_info <d_id> <detail>
#   INFO は verbose mode で個別展開、default は件数集約。d_id / detail は
#   self-doctor 固有 label のため lib の emit_info (2 args: why / docs) とは
#   別 signature を維持 (§3.6 caller-side prefix 契約)。
emit_info() {
  local d_id="$1" detail="$2"
  INFO_COUNT=$((INFO_COUNT + 1))
  if $VERBOSE; then
    printf '[self-doctor] INFO %s: %s\n' "$d_id" "$detail"
  else
    # 集約 line 用に短縮 memo を残す (最終 summary 行で列挙)
    if [ -z "$INFO_LINES" ]; then
      INFO_LINES="$d_id ${detail}"
    else
      INFO_LINES="$INFO_LINES"$'\n'"$d_id ${detail}"
    fi
  fi
}

# ============================================================
# D1: harness-config.local.yml 生成済 check
# ============================================================
_check_d1() {
  if [ "${HC_SELF_DOCTOR_D1_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local local_yml="$PROJECT_ROOT/.claude/harness-config.local.yml"
  if [ -f "$local_yml" ]; then
    return 0
  fi
  # 不在: preset=harness-dev の self-install (harness 自身の dogfood repo) は INFO 降格。
  # self-install の runtime 検出は「PROJECT_ROOT/install.sh が存在」を heuristic として使う
  # (consuming repo は install.sh を持たず .claude/ のみ受領するため、install.sh 存在は
  #  harness source repo であることの強い signal)。default_preset=harness-dev との AND 条件で
  #  consuming repo (harness-config.yml の verbatim copy で harness-dev 表示だが install.sh 不在) を
  #  誤 INFO 化しない。
  local default_preset=""
  if command -v _get_default >/dev/null 2>&1; then
    default_preset=$(_get_default default_preset 2>/dev/null || printf '')
  fi
  if [ -z "$default_preset" ]; then
    default_preset=$(grep -E '^default_preset:' "$PROJECT_ROOT/.claude/harness-config.yml" 2>/dev/null \
      | head -1 | sed -E 's/^default_preset:[[:space:]]*"?([^"#[:space:]]+)"?.*/\1/' || true)
  fi
  if [ "$default_preset" = "harness-dev" ] && [ -f "$PROJECT_ROOT/install.sh" ]; then
    emit_info "D1" "local.yml 不在 (default_preset=harness-dev + install.sh 存在 = self-install dogfood 判定、正当)"
    return 0
  fi
  emit_warn "D1" "harness-config.local.yml 生成済でない" \
    "install.sh §6.4 preset bootstrap が生成する project 所有 config が不在 (consuming repo で main preset が harness-dev のまま解決され guard が全 disabled になる)" \
    "bash <harness>/install.sh . --update  (もしくは npx @takuma-hirai/hirai-method@latest update .)" \
    "HC_SELF_DOCTOR_D1_SKIP=1"
}

# ============================================================
# D2: settings.json dispatcher 配線 (3 分岐、draft §3.1 D2 SSoT)
# ============================================================
_check_d2() {
  if [ "${HC_SELF_DOCTOR_D2_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local settings="$PROJECT_ROOT/.claude/settings.json"
  local gen_script="$PROJECT_ROOT/.claude/scripts/generate-settings.sh"
  # (a) 不在 = INFO (期待値内: fresh install は rsync exclude で非配布、task-71 H2 設計)
  if [ ! -f "$settings" ]; then
    emit_info "D2" "settings.json 不在 (fresh install は task-71 H2 設計により rsync exclude、update 経路または seed 導入後に配線)"
    return 0
  fi
  # (c) jq 不在 = INFO (検証不能を正直に報告)
  if ! command -v jq >/dev/null 2>&1; then
    emit_info "D2" "jq 不在のため settings.json 配線 check 実行不能"
    return 0
  fi
  # (b) 存在 ∧ jq 有 ∧ --check DRIFT or invalid JSON = WARN
  if [ ! -x "$gen_script" ] && [ ! -f "$gen_script" ]; then
    emit_info "D2" "generate-settings.sh 不在のため配線 check 実行不能"
    return 0
  fi
  local check_output
  check_output=$( ( cd "$PROJECT_ROOT" && HC_PROJECT_ROOT="$PROJECT_ROOT" bash "$gen_script" --check "$settings" 2>&1 ) )
  local check_rc=$?
  if [ $check_rc -ne 0 ]; then
    emit_warn "D2" "settings.json が dispatcher manifest と drift" \
      "generate-settings.sh --check が非 0 (DRIFT 検出 or invalid JSON、rc=${check_rc})" \
      "bash .claude/scripts/generate-settings.sh --out .claude/settings.json" \
      "HC_SELF_DOCTOR_D2_SKIP=1"
  fi
}

# ============================================================
# D3: harness_version stamp 存在 + ISO-8601 format
# ============================================================
_check_d3() {
  if [ "${HC_SELF_DOCTOR_D3_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local hc="$PROJECT_ROOT/.claude/harness-config.yml"
  if [ ! -f "$hc" ]; then
    emit_warn "D3" "harness-config.yml が存在しない" \
      "install.sh の rsync が harness-config.yml を配置していない (install 失敗の疑い)" \
      "bash <harness>/install.sh . --update" \
      "HC_SELF_DOCTOR_D3_SKIP=1"
    return 0
  fi
  local stamp_line
  stamp_line=$(grep -E '^harness_version:' "$hc" 2>/dev/null | head -1 || true)
  if [ -z "$stamp_line" ]; then
    emit_warn "D3" "harness_version stamp が存在しない" \
      "install.sh §6.5 が stamp 行を書込むはずが不在 (install 途中失敗の疑い)" \
      "bash <harness>/install.sh . --update" \
      "HC_SELF_DOCTOR_D3_SKIP=1"
    return 0
  fi
  # ISO-8601 (YYYY-MM-DD) 形式 check
  local stamp_val
  stamp_val=$(printf '%s' "$stamp_line" | sed -E 's/^harness_version:[[:space:]]*"?([^"#[:space:]]+)"?.*/\1/')
  if ! printf '%s' "$stamp_val" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    emit_warn "D3" "harness_version stamp が ISO-8601 (YYYY-MM-DD) 形式でない" \
      "書込値 '${stamp_val}' は YYYY-MM-DD regex 不一致 (手動編集による破損の疑い)" \
      "bash <harness>/install.sh . --update  (stamp 再書込)" \
      "HC_SELF_DOCTOR_D3_SKIP=1"
  fi
}

# ============================================================
# D4: harness_npm_version stamp (常時 INFO、draft §3.1 D4 SSoT)
# ============================================================
_check_d4() {
  if [ "${HC_SELF_DOCTOR_D4_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local hc="$PROJECT_ROOT/.claude/harness-config.yml"
  if [ ! -f "$hc" ]; then
    return 0
  fi
  local npm_line
  npm_line=$(grep -E '^harness_npm_version:' "$hc" 2>/dev/null | head -1 || true)
  if [ -z "$npm_line" ]; then
    emit_info "D4" "harness_npm_version stamp 未書込 (package.json 不在 target で正当な skip、fail-safe)"
    return 0
  fi
  local npm_val
  npm_val=$(printf '%s' "$npm_line" | sed -E 's/^harness_npm_version:[[:space:]]*"?([^"#[:space:]]+)"?.*/\1/')
  emit_info "D4" "harness_npm_version = ${npm_val} (install / npx update 時に package.json .version から書込)"
}

# ============================================================
# D5: hooks / scripts 実行 bit
# ============================================================
_check_d5() {
  if [ "${HC_SELF_DOCTOR_D5_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local hooks_dir="$PROJECT_ROOT/.claude/hooks"
  local scripts_dir="$PROJECT_ROOT/.claude/scripts"
  local non_exec_hooks="" non_exec_scripts=""
  if [ -d "$hooks_dir" ]; then
    # lib/ は sourced 専用 (実行 bit 不要) のため maxdepth 1 のみに絞る (staging mv での bit 落ち検出用途)
    non_exec_hooks=$(find "$hooks_dir" -maxdepth 1 -type f -name '*.sh' ! -perm -u+x 2>/dev/null || true)
  fi
  if [ -d "$scripts_dir" ]; then
    non_exec_scripts=$(find "$scripts_dir" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \) ! -perm -u+x 2>/dev/null || true)
  fi
  local combined="$non_exec_hooks"$'\n'"$non_exec_scripts"
  # 空行 strip して件数計算 (grep -c は match 0 でも "0" を stdout する仕様、
  # || fallback を付けると grep rc=1 で fallback "0" が二重出力になり "0\n0" になるため
  # pipefail 下でも rc は無視して count のみ採取する)
  local count
  count=$(printf '%s\n' "$combined" | grep -c '.' || true)
  [ -z "$count" ] && count=0
  if [ "$count" -gt 0 ] 2>/dev/null; then
    local sample
    sample=$(printf '%s\n' "$combined" | grep '.' | head -3 | tr '\n' ',' | sed 's/,$//')
    emit_warn "D5" "hooks / scripts に実行 bit 落ちが ${count} 件検出" \
      "install.sh §6 chmod が反映されていない or staging mv 後の bit 落ち (feedback_subagent_staging_mv_exec_bit_loss)。sample: ${sample}" \
      "find .claude/hooks .claude/scripts -maxdepth 1 -type f \\( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \\) -exec chmod +x {} +" \
      "HC_SELF_DOCTOR_D5_SKIP=1"
  fi
}

# ============================================================
# D6: guard effective state (preset-aware、hc-config.sh --summary 委譲)
# ============================================================
_check_d6() {
  if [ "${HC_SELF_DOCTOR_D6_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local hc_config="$PROJECT_ROOT/.claude/scripts/hc-config.sh"
  if [ ! -f "$hc_config" ]; then
    emit_info "D6" "hc-config.sh 不在のため guard state 検証 skip"
    return 0
  fi
  # --summary の exit code が SSoT (UNDOCUMENTED mismatch で非 0)
  #
  # HC_ALLOW_EXTERNAL_CONFIG=1 propagation (task-87 S-42 fix, CRITICAL):
  #   hc-config.sh は default で「config path が REPO_ROOT / /tmp/ / /private/tmp/ /
  #   /var/folders/ 配下でない」時 exit 1 (path guard、_validate_config_path)。
  #   macOS `mktemp -d` は /var/folders/... を返し、`pwd -P` canonicalize で
  #   /private/var/folders/... となり case pattern 不一致で reject → self-doctor D6
  #   一次判定が UNDOCUMENTED mismatch WARN 誤発火する事案があった (draft §6 DoD 1/4)。
  #   self-doctor は同 repo 内の trusted caller として、自身の PROJECT_ROOT に対する
  #   guard state 検証 (D6) に限り境界 bypass を明示的に指示する (draft §3.1 D6 SSoT)。
  local summary_output rc
  summary_output=$( ( cd "$PROJECT_ROOT" && HC_PROJECT_ROOT="$PROJECT_ROOT" HC_ALLOW_EXTERNAL_CONFIG=1 bash "$hc_config" --summary 2>&1 ) )
  rc=$?
  # 二次 heuristic: preset ∈ {team-default, strict} ∧ enabled == 0 のみ WARN
  local preset totals_line enabled
  preset=$(printf '%s\n' "$summary_output" | awk '/^preset:/ {print $2; exit}' 2>/dev/null || printf '')
  totals_line=$(printf '%s\n' "$summary_output" | awk '/^totals:/ {print; exit}' 2>/dev/null || printf '')
  enabled=$(printf '%s' "$totals_line" | sed -E 's/^totals:[[:space:]]*([0-9]+)[[:space:]]+enabled.*/\1/' 2>/dev/null || printf '')
  if [ $rc -ne 0 ]; then
    # 一次判定: UNDOCUMENTED mismatch = matrix 側の documented 化で解消すべき実 mismatch
    emit_warn "D6" "hc-config.sh --summary が UNDOCUMENTED mismatch (docs=block だが実 disabled)" \
      "enforcement_matrix presets 期待値と feature toggle 実値が乖離 (preset=${preset}、rc=${rc})" \
      "\$EDITOR .claude/harness-config.local.yml  (現 preset の matrix 期待値に合わせ toggle を確認)" \
      "HC_SELF_DOCTOR_D6_SKIP=1"
    return 0
  fi
  # 二次: preset ∈ {team-default, strict} ∧ enabled == 0
  case "$preset" in
    team-default|strict)
      if [ -n "$enabled" ] && [ "$enabled" = "0" ]; then
        emit_warn "D6" "preset=${preset} だが有効 guard が 0 件 (subscbase-api 型全滅)" \
          "matrix presets 行では ${preset} は 8 guard 全 true 期待だが実 enabled = 0 (local.yml で意図しない toggle 上書きの疑い)" \
          "\$EDITOR .claude/harness-config.local.yml  (${preset} の matrix 期待値に合わせ 8 toggle true 確認)" \
          "HC_SELF_DOCTOR_D6_SKIP=1"
      fi
      ;;
    advisory|harness-dev)
      : # advisory / harness-dev の enabled == 0 は matrix 期待どおりの正当状態 (INFO 昇格しない、silent PASS)
      ;;
    *)
      : # 4 値外 preset は一次判定 (--summary exit) へ委譲済
      ;;
  esac
}

# ============================================================
# D7: .mcp.json env 前提 (常時 INFO、check-required-env.sh 委譲)
# ============================================================
_check_d7() {
  if [ "${HC_SELF_DOCTOR_D7_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local mcp_json="$PROJECT_ROOT/.mcp.json"
  if [ ! -f "$mcp_json" ]; then
    return 0
  fi
  # ${VAR_NAME} placeholder を全抽出
  local placeholders
  placeholders=$(grep -oE '\$\{[A-Z_]+\}' "$mcp_json" 2>/dev/null | sort -u | tr -d '${}' || true)
  if [ -z "$placeholders" ]; then
    return 0
  fi
  local unset_list=""
  local var value count=0 total=0
  while IFS= read -r var; do
    [ -z "$var" ] && continue
    total=$((total + 1))
    eval "value=\${${var}-}"
    if [ -z "$value" ]; then
      count=$((count + 1))
      if [ -z "$unset_list" ]; then
        unset_list="$var"
      else
        unset_list="${unset_list}, ${var}"
      fi
    fi
  done <<< "$placeholders"
  if [ "$count" -gt 0 ]; then
    emit_info "D7" ".mcp.json placeholder 未設定 ${count}/${total} 件 (secret は user 設定、check-required-env.sh 側で severity 制御): ${unset_list}"
  else
    emit_info "D7" ".mcp.json placeholder ${total} 件すべて env 設定済"
  fi
}

# ============================================================
# D8: settings.local.json 健全性 (JSON valid + 重複 key heuristic)
# ============================================================
_check_d8() {
  if [ "${HC_SELF_DOCTOR_D8_SKIP:-0}" = "1" ]; then
    return 0
  fi
  local sl="$PROJECT_ROOT/.claude/settings.local.json"
  if [ ! -f "$sl" ]; then
    # 不在は正常 (project ごとの opt-in)
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    emit_info "D8" "jq 不在のため settings.local.json 健全性 check 実行不能"
    return 0
  fi
  # invalid JSON check
  if ! jq empty "$sl" >/dev/null 2>&1; then
    emit_warn "D8" "settings.local.json が invalid JSON" \
      "jq empty パースに失敗 (heredoc 混入 / 末尾カンマ / 引用符欠落の疑い)" \
      "\$EDITOR .claude/settings.local.json  (JSON 構文修正、jq . file で整形確認)" \
      "HC_SELF_DOCTOR_D8_SKIP=1"
    return 0
  fi
  # 重複 key heuristic (subscbase-api ASANA_PAT 2 回事案)
  local dup_keys
  dup_keys=$(grep -oE '"[A-Z_]+"[[:space:]]*:' "$sl" 2>/dev/null | sort | uniq -d || true)
  if [ -n "$dup_keys" ]; then
    local dup_sample
    dup_sample=$(printf '%s\n' "$dup_keys" | head -3 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    emit_warn "D8" "settings.local.json に重複 key heuristic 検出 (手動確認要)" \
      "regex heuristic で同一 UPPER_SNAKE_KEY を複数箇所検出 (JSON 文字列値内の pattern 過検知の可能性あり、手動確認要)。sample: ${dup_sample}" \
      "\$EDITOR .claude/settings.local.json  (該当 key を手動 dedupe)" \
      "HC_SELF_DOCTOR_D8_SKIP=1"
  fi
}

# ============================================================
# main dispatch
# ============================================================
_check_d1
_check_d2
_check_d3
_check_d4
_check_d5
_check_d6
_check_d7
_check_d8

# ============================================================
# summary 出力 (draft §3.2)
# ============================================================
if [ "$INFO_COUNT" -gt 0 ] && ! $VERBOSE && [ -n "$INFO_LINES" ]; then
  # 集約行: "D<N> ..." を短縮 label のみで列挙
  info_labels=$(printf '%s\n' "$INFO_LINES" | awk '{print $1}' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  printf '[self-doctor] INFO %d 件 (期待値内、absorb、--verbose で展開): %s\n' "$INFO_COUNT" "$info_labels"
fi

if [ "$WARN_COUNT" -eq 0 ]; then
  printf '[self-doctor] result: WARN 0 / INFO %d — exit=0 all clean\n' "$INFO_COUNT"
  exit 0
else
  printf '[self-doctor] result: WARN %d / INFO %d — 期待外 issue %d 件 (fix 後に再実行: bash .claude/scripts/self-doctor.sh)\n' \
    "$WARN_COUNT" "$INFO_COUNT" "$WARN_COUNT"
  exit 1
fi
