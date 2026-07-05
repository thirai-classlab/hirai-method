#!/usr/bin/env bash
# .claude/tests/self-doctor-smoke.sh — task-87 Step 3
#
# 目的:
#   .claude/scripts/self-doctor.sh (D1-D8 check + WARN/INFO 分類 + 3 点提示 format) と
#   install.sh §7.5 self-doctor 呼出 (fail-open 2 層) の設計 SSoT
#   docs/draft/install-self-doctor.md §3.6 Step 3 に対応する Case A-J 10 件を検証する。
#
# Case 一覧 (draft §3.6 Step 3 + task-87 review S-42 追加 K/L):
#   A: clean install で WARN 0 (D2 は fresh install 非配布のため分岐 (a) INFO 側)
#   B: local.yml 削除で D1 WARN + exit 1
#   C: hook exec bit 落し (chmod 644) で D5 WARN + exit 1
#   D: settings.local.json 重複 key で D8 WARN + exit 1
#   E: env 未設定は INFO のみ exit 0 (D7 placeholder 集約が INFO 出力に含まれる)
#   F: install.sh --no-doctor で self-doctor 非実行 (install 出力に [self-doctor] 行なし)
#   G: script 不在でも install.sh exit 0 (fail-open silent skip + NOTE 出力、
#      静的 grep + runtime §7.5 block simulate 2 段実測)
#   H: HC_FEATURE_SELF_DOCTOR_ENABLED=false で no-op + exit 0 (出力なし)
#   I: local.yml を default_preset=harness-dev + 8 toggle false に置換で D6 WARN なし
#      (matrix harness-dev disabled_reason で --summary rc=0、二次 heuristic 非発火)
#   J: manifest 乖離 settings.json ({"hooks":{}} valid JSON) 配置で D2 分岐 (b) WARN + exit 1
#   K: (S-42 review HIGH #4) install fail-open DoD runtime 実測 —
#      D8 WARN 状態で install.sh --update → install exit 0 + [self-doctor] WARN D8 +
#      [install] DONE を実 runtime で assert (§7.5 の `|| true` fail-open guard の
#      機械 regression 検出契約を確立)
#   L: (S-42 review HIGH #3) D6 UNDOCUMENTED-mismatch 一次判定 branch runtime coverage —
#      team-default preset で feature_draft_flow_guard_enabled=false に人工 mismatch
#      (matrix presets.team-default=true 期待、disabled_reason 未記載 = UNDOCUMENTED) →
#      hc-config.sh --summary rc=1 → self-doctor D6 一次 branch WARN 発火を assert。
#      HC_ALLOW_EXTERNAL_CONFIG=1 は self-doctor.sh L361 で内側 hc-config.sh 呼出に
#      伝播 (task-87 S-42 CRITICAL fix)、path guard bypass 済 = UNDOCUMENTED 検出のみ発火。
#
# 3 点提示 format assert:
#   全 WARN case (B/C/D/J/L) で why: / fix: / silence: の 3 行がすべての WARN 種に付随し
#   `grep -c 'fix:'` >= WARN 数 が成立することを個別 case 内で assert する
#   (draft §3.2 + 第一原理 v2 §2.3 BLOCK 教育 3 点提示に整合)。
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下の target に対して行い、repo 本体を汚さない
#   - existing install 系 smoke pattern (install-local-yml-smoke.sh) 踏襲
#
# 実行:
#   bash .claude/tests/self-doctor-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh 前提依存)\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/self-doctor-smoke.XXXXXX")" || {
  printf 'ERROR: mktemp failed\n' >&2
  exit 1
}
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
FAILED_CASES=""

_record() {
  local result="$1" case_id="$2" desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# 環境変数の外側 leak を防ぐ (D1-D8 skip env + feature toggle)
_cleanup_envs() {
  unset HC_FEATURE_SELF_DOCTOR_ENABLED 2>/dev/null || true
  unset HC_SELF_DOCTOR_D1_SKIP HC_SELF_DOCTOR_D2_SKIP HC_SELF_DOCTOR_D3_SKIP 2>/dev/null || true
  unset HC_SELF_DOCTOR_D4_SKIP HC_SELF_DOCTOR_D5_SKIP HC_SELF_DOCTOR_D6_SKIP 2>/dev/null || true
  unset HC_SELF_DOCTOR_D7_SKIP HC_SELF_DOCTOR_D8_SKIP 2>/dev/null || true
  unset HC_CONFIG_PATH HC_LOCAL_CONFIG_PATH HC_DEFAULT_PRESET 2>/dev/null || true
}

# self-doctor 実行 helper: target dir で HC_PROJECT_ROOT を渡し実 script を呼ぶ。
# stdout+stderr を out log に落とし、rc は $? で拾う。
# args: $1=target dir / $2=out log path / [$3..]=self-doctor args (--verbose 等)
#
# HC_ALLOW_EXTERNAL_CONFIG=1: smoke tmp target isolation 用 safety valve
#   hc-config.sh は default で「config path が REPO_ROOT 配下でない」時 exit 1
#   (test 汚染防止 gate)。smoke は harness repo とは別 root の /tmp/target で走らせるため、
#   self-doctor 内 D6 (hc-config.sh --summary 委譲) がこの gate に引っかかり誤
#   UNDOCUMENTED mismatch WARN を出す。実運用の consuming repo では self-repo root ==
#   config path root で boundary check を通過するため env 不要 (smoke 特有の isolation
#   artifact、Step 1 self-doctor.sh の設計 SSoT §3.1 D6 判定ロジックの意図と整合)。
_run_doctor() (
  set -uo pipefail
  local tgt="$1" out="$2"
  shift 2
  ( cd "$tgt" \
      && HC_PROJECT_ROOT="$tgt" HC_ALLOW_EXTERNAL_CONFIG=1 \
         bash "$tgt/.claude/scripts/self-doctor.sh" "$@" ) \
    > "$out" 2>&1
)

# fresh install helper: --no-mcp / --no-docs で最小配布 (Case A の期待値 stability に沿う)
# args: $1=target dir / [$2..]=install.sh extra args
_do_install() (
  set -uo pipefail
  local tgt="$1"
  shift
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs "$@" >/dev/null 2>&1
)

# 3 点提示 format assert (draft §3.2)
# args: $1=out log / $2=期待 WARN 数
#
# grep -c は match 0 でも "0" を stdout するが exit 1 になる仕様のため、
# `|| printf '0'` の fallback を組むと "0" が二重発火して "0\n0" が変数に入る事故がある。
# `|| true` で exit 1 のみ吸収し stdout の "0" を単独で採取する (bash 3.2/5.x 互換)。
_assert_triplet() {
  local out="$1" expected_warns="$2"
  local warn_count fix_count why_count silence_count
  warn_count=$(grep -c '^\[self-doctor\] WARN ' "$out" 2>/dev/null || true)
  fix_count=$(grep -c '^  fix: ' "$out" 2>/dev/null || true)
  why_count=$(grep -c '^  why: ' "$out" 2>/dev/null || true)
  silence_count=$(grep -c '^  silence: ' "$out" 2>/dev/null || true)
  # 念のため空文字 fallback (grep が stdout を出さない極端環境の防波堤)
  warn_count=${warn_count:-0}
  fix_count=${fix_count:-0}
  why_count=${why_count:-0}
  silence_count=${silence_count:-0}
  [ "$warn_count" -eq "$expected_warns" ] || return 1
  [ "$fix_count" -ge "$warn_count" ] || return 1
  [ "$why_count" -ge "$warn_count" ] || return 1
  [ "$silence_count" -ge "$warn_count" ] || return 1
  return 0
}

# ============================================================
# Case A: clean install で WARN 0
# fresh install で target には harness-config.local.yml + harness_version stamp 生成、
# settings.json は非配布 (task-71 H2、rsync exclude)。self-doctor は D2 分岐 (a) INFO
# + D4 stamp INFO で WARN 0 exit 0 になる。
# ============================================================
# TGT_A: Case A/E/H で共有 (untouched pristine install)
# Case B/C/D/J/K は rsync -a で fork copy を作り isolate する (S-42 review HIGH #2 fix、
# 過去は TGT_ABCDE を共有し Case B 復元 step 失敗で D/E/H に cascade FAIL していた)
TGT_A="${TMP_DIR}/target-a"

# _fork_target <src> <dst>: rsync -a で完全 copy (permission / hidden files 込み)
_fork_target() (
  set -uo pipefail
  local src="$1" dst="$2"
  rm -rf "$dst" 2>/dev/null || true
  mkdir -p "$dst" || return 1
  # trailing slash で directory contents を丸ごと copy (rsync -a 保持: perm / time / symlink)
  rsync -a "$src/" "$dst/" >/dev/null 2>&1
)

_case_a() (
  set -uo pipefail
  _cleanup_envs
  _do_install "$TGT_A" || return 1
  local out="${TMP_DIR}/case-a-out.log"
  _run_doctor "$TGT_A" "$out"
  local rc=$?
  # WARN 0 line + exit 0
  grep -q '^\[self-doctor\] result: WARN 0 / INFO ' "$out" || return 1
  [ "$rc" -eq 0 ] || return 1
  # WARN 種 0 件 = triplet assert (expected=0 は fix/why/silence >= 0 の意)
  _assert_triplet "$out" 0 || return 1
  return 0
)

# ============================================================
# Case B: local.yml 削除で D1 WARN + exit 1
# ============================================================
# S-42 HIGH #2 fix: 独立 target dir (TGT_A の rsync -a fork) を使用し
# 復元 step 失敗の cascade risk を排除。
_case_b() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-b"
  _fork_target "$TGT_A" "$tgt" || return 1
  [ -f "${tgt}/.claude/harness-config.local.yml" ] || return 1
  rm -f "${tgt}/.claude/harness-config.local.yml" || return 1
  local out="${TMP_DIR}/case-b-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  # D1 WARN が出ていること
  grep -q '^\[self-doctor\] WARN D1: ' "$out" || return 1
  [ "$rc" -eq 1 ] || return 1
  # 3 点提示 format: D1 WARN 1 件で why/fix/silence 各 >= 1
  _assert_triplet "$out" 1 || return 1
  return 0
)

# ============================================================
# Case C: hook exec bit 落し (chmod 644) で D5 WARN + exit 1
# ============================================================
# S-42 HIGH #2 fix: 独立 target dir で isolate。
_case_c() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-c"
  _fork_target "$TGT_A" "$tgt" || return 1
  # hooks/ 配下の 1 つの .sh を選び 644 に落とす (maxdepth 1)
  local victim
  victim=$(find "${tgt}/.claude/hooks" -maxdepth 1 -type f -name '*.sh' 2>/dev/null | head -1)
  [ -n "$victim" ] || return 1
  chmod 644 "$victim" || return 1
  local out="${TMP_DIR}/case-c-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  grep -q '^\[self-doctor\] WARN D5: ' "$out" || return 1
  [ "$rc" -eq 1 ] || return 1
  _assert_triplet "$out" 1 || return 1
  return 0
)

# ============================================================
# Case D: settings.local.json 重複 key で D8 WARN + exit 1
# heredoc で valid JSON を書く: env と permissions.env の 2 箇所に同一 UPPER_SNAKE key
# ("ASANA_PAT":) が出現 → jq empty PASS + regex heuristic で重複検出
# ============================================================
# S-42 HIGH #2 fix: 独立 target dir で isolate。
_case_d() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-d"
  _fork_target "$TGT_A" "$tgt" || return 1
  local sl="${tgt}/.claude/settings.local.json"
  printf '{\n  "env": {\n    "ASANA_PAT": "a"\n  },\n  "dup_block": {\n    "ASANA_PAT": "b"\n  }\n}\n' > "$sl"
  local out="${TMP_DIR}/case-d-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  if ! command -v jq >/dev/null 2>&1; then
    # jq 不在環境では D8 は INFO で skip される仕様 (fail-open 契約遵守)
    grep -q 'jq 不在' "$out" || return 1
    [ "$rc" -eq 0 ] || return 1
    return 0
  fi
  grep -q '^\[self-doctor\] WARN D8: ' "$out" || return 1
  [ "$rc" -eq 1 ] || return 1
  _assert_triplet "$out" 1 || return 1
  return 0
)

# ============================================================
# Case E: env 未設定は INFO のみ exit 0 (D7 集約行に INFO 表示 or .mcp.json 不在で silent)
# fresh install は --no-mcp のため .mcp.json 非配布 = D7 silent、
# よって全体 D2 (a) + D4 の 2 件 INFO 集約 + WARN 0 + exit 0 の Case A 同型を確認しつつ
# 「WARN 0 かつ exit 0」を E 独自の assert で強化する (D7 が INFO 出力される場合も許容)。
# ============================================================
# TGT_A は Case B/C/D が独立 dir を使用するため untouched 保証、pristine state 前提で assert 可。
_case_e() (
  set -uo pipefail
  _cleanup_envs
  local out="${TMP_DIR}/case-e-out.log"
  _run_doctor "$TGT_A" "$out"
  local rc=$?
  [ "$rc" -eq 0 ] || return 1
  # WARN 0 は必須
  grep -q '^\[self-doctor\] result: WARN 0 / INFO ' "$out" || return 1
  # 期待外 WARN 0 (WARN 種は 1 件も出ない)
  ! grep -q '^\[self-doctor\] WARN ' "$out" || return 1
  return 0
)

# ============================================================
# Case F: install.sh --no-doctor で self-doctor 非実行
# install 出力に [self-doctor] 行が 1 件もない + install exit 0
# ============================================================
_case_f() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-f"
  mkdir -p "$tgt"
  local out="${TMP_DIR}/case-f-out.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs --no-doctor >"$out" 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || return 1
  ! grep -q '\[self-doctor\] ' "$out" || return 1
  return 0
)

# ============================================================
# Case G: script 不在でも install.sh exit 0 (fail-open silent skip)
# 既 install target から self-doctor.sh を削除して --update 再実行、
# stderr に「[install] NOTE: self-doctor.sh 不在」 + install exit 0
# ============================================================
# S-42 HIGH #1 fix: 従来は 2 行の静的 grep のみ (source 文字列存在) で runtime 検証 0%。
# `install.sh --update` は rsync で self-doctor.sh を再配布するため fail-open 分岐に到達不能。
# 対策として install.sh §7.5 の呼出 block を sed で verbatim 抽出し、rm 後 subshell で
# eval して runtime fail-open path を実際に通す (`|| true` の効果 + NOTE 文字列 stderr
# 出力を実測)。静的 grep も規範 (draft §3.4) 存在確認として残す。
_case_g() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-g"
  _do_install "$tgt" || return 1
  # (a) 静的 grep: install.sh source に NOTE 文字列 + `|| true` fail-open guard 存在確認
  grep -q 'self-doctor.sh 不在' "$INSTALL_SH" || return 1
  grep -q 'self-doctor.sh.*|| true' "$INSTALL_SH" || return 1
  # (b) runtime 実測 §7.5 block simulate (S-42 HIGH #1 fake test fix):
  #   §7.5 の block を install.sh から sed で verbatim 抽出し、self-doctor.sh 削除後の
  #   target に対して subshell で eval 実行 → fail-open path (`else echo NOTE`) が
  #   実際に発火し subshell rc=0 + stderr に NOTE 文字列を assert する。
  local block
  block=$(sed -n '/^if \$WITH_DOCTOR && ! \$DRY_RUN; then$/,/^fi$/p' "$INSTALL_SH")
  [ -n "$block" ] || return 1
  rm -f "${tgt}/.claude/scripts/self-doctor.sh" || return 1
  local sim_out="${TMP_DIR}/case-g-sim.log"
  local sim_err="${TMP_DIR}/case-g-sim.err"
  (
    # 抽出 block が参照する install.sh 変数を復元
    WITH_DOCTOR=true
    DRY_RUN=false
    TARGET="$tgt"
    eval "$block"
  ) > "$sim_out" 2> "$sim_err"
  local sim_rc=$?
  [ "$sim_rc" -eq 0 ] || return 1
  # NOTE 文字列 stderr 実測 (fail-open path 到達確認)
  grep -q 'self-doctor.sh 不在' "$sim_err" || return 1
  # (c) 実 install --update で exit 0 (rsync 再配布で self-doctor.sh 復活後の正常経路回帰)
  local out="${TMP_DIR}/case-g-out.log"
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs >"$out" 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || return 1
  return 0
)

# ============================================================
# Case H: HC_FEATURE_SELF_DOCTOR_ENABLED=false で no-op + exit 0
# 既 install target で env 上書き self-doctor 実行 → 出力なし + exit 0
# ============================================================
# TGT_A を使用 (Case B/C/D が独立 dir に fork したため pristine 保証)。
_case_h() (
  set -uo pipefail
  _cleanup_envs
  local out="${TMP_DIR}/case-h-out.log"
  ( cd "$TGT_A" && HC_PROJECT_ROOT="$TGT_A" HC_FEATURE_SELF_DOCTOR_ENABLED=false \
      bash "${TGT_A}/.claude/scripts/self-doctor.sh" ) >"$out" 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || return 1
  # 出力なし (空 file、または 0 byte)
  [ ! -s "$out" ] || return 1
  return 0
)

# ============================================================
# Case I: --preset=harness-dev 新規 install → D6 WARN なし
# matrix presets の harness-dev は 8 guard disabled_reason 記載済 (--summary rc=0)、
# 二次 heuristic は preset ∈ {team-default, strict} 限定のため harness-dev では非発火。
# 期待: WARN D6 の出力なし + 全体 exit 0
# ============================================================
_case_i() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-i"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --preset=harness-dev --no-mcp --no-docs >/dev/null 2>&1 || return 1
  # local.yml が harness-dev で生成されたことを sanity check
  grep -q '^default_preset: harness-dev$' "${tgt}/.claude/harness-config.local.yml" || return 1
  local out="${TMP_DIR}/case-i-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  # D6 WARN が出ていないこと (他 D で WARN が出た場合は本 case のスコープ外だが preset drift 誤検知として fail)
  ! grep -q '^\[self-doctor\] WARN D6: ' "$out" || return 1
  [ "$rc" -eq 0 ] || return 1
  return 0
)

# ============================================================
# Case J: manifest 乖離 settings.json 配置で D2 分岐 (b) WARN + exit 1
# 既 install target に {"hooks":{}} (valid JSON、jq empty PASS) を配置。
# generate-settings.sh --check が dispatcher manifest 由来生成結果との drift を検出 → D2 WARN
# jq / generate-settings.sh 不在環境では skip (INFO で fail-open) されるため PASS 扱い。
# ============================================================
# S-42 HIGH #2 fix: 独立 target dir で isolate。
_case_j() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-j"
  _fork_target "$TGT_A" "$tgt" || return 1
  local settings="${tgt}/.claude/settings.json"
  printf '{"hooks":{}}\n' > "$settings"
  local out="${TMP_DIR}/case-j-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  # jq or generate-settings.sh 不在時は INFO で skip されるため事前判定
  if ! command -v jq >/dev/null 2>&1; then
    grep -q 'jq 不在' "$out" || return 1
    [ "$rc" -eq 0 ] || return 1
    return 0
  fi
  if [ ! -f "${tgt}/.claude/scripts/generate-settings.sh" ]; then
    grep -q 'generate-settings.sh 不在' "$out" || return 1
    [ "$rc" -eq 0 ] || return 1
    return 0
  fi
  # 通常経路: D2 WARN + exit 1 + 3 点提示
  grep -q '^\[self-doctor\] WARN D2: ' "$out" || return 1
  [ "$rc" -eq 1 ] || return 1
  _assert_triplet "$out" 1 || return 1
  return 0
)

# ============================================================
# Case K: install fail-open DoD runtime 実測 (S-42 review HIGH #4 新設)
# 既 install target に D8 WARN 状態 (settings.local.json 重複 key) を pre-arrange し、
# install.sh --update を runtime 実行 → §7.5 self-doctor が WARN D8 を吐く実状態で
# install が exit 0 + [install] DONE 到達を assert する。
# `|| true` fail-open guard の regression 検出契約を確立する (draft §6 DoD 最重要契約)。
#
# なぜ D8 か:
#   D1 (local.yml 不在) は --update §6.4 で自動再生成される。
#   D5 (chmod 644) は --update §6 の chmod +x で強制復元される。
#   D2 (settings.json drift) も --update で自動再生成される (task-71 H2 sync mode)。
#   D8 (settings.local.json 重複 key) は rsync exclude で --update に温存され、
#   §7.5 到達時に確実に WARN 発火する唯一の pre-arrange 経路。
# jq / generate-settings.sh 不在時は D8 が INFO 経路 (fail-open) になるため
# WARN assert を skip し install exit 0 のみ確認する fallback を組む。
# ============================================================
_case_k() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-k"
  _fork_target "$TGT_A" "$tgt" || return 1
  # pre-arrange D8 WARN state (Case D と同 heredoc format、valid JSON + 重複 UPPER_SNAKE key)
  local sl="${tgt}/.claude/settings.local.json"
  printf '{\n  "env": {\n    "ASANA_PAT": "a"\n  },\n  "dup_block": {\n    "ASANA_PAT": "b"\n  }\n}\n' > "$sl"
  local out="${TMP_DIR}/case-k-out.log"
  # runtime 実測: --update 経路で §7.5 self-doctor が WARN D8 発火中に install exit 0 到達
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs > "$out" 2>&1
  local rc=$?
  # (1) install exit 0 (fail-open 最重要契約)
  [ "$rc" -eq 0 ] || return 1
  # (2) [install] DONE 到達 (§7.5 で abort しないこと)
  grep -q '^\[install\] DONE ' "$out" || return 1
  # (3) jq 存在時のみ D8 WARN 実発火を assert (jq 不在なら D8 は INFO fail-open)
  if command -v jq >/dev/null 2>&1; then
    grep -q '^\[self-doctor\] WARN D8: ' "$out" || return 1
  fi
  return 0
)

# ============================================================
# Case L: D6 UNDOCUMENTED-mismatch 一次判定 branch runtime coverage (S-42 review HIGH #3 新設)
# team-default preset で feature_draft_flow_guard_enabled=false に人工 mismatch。
# matrix presets.team-default = true 期待 + disabled_reason は harness-dev/advisory のみ
# 記載 → team-default での false は UNDOCUMENTED → hc-config.sh --summary rc=1 →
# self-doctor D6 一次 branch (rc != 0) が WARN 発火。
#
# self-doctor.sh L361 で HC_ALLOW_EXTERNAL_CONFIG=1 を hc-config.sh --summary に伝播
# (task-87 S-42 CRITICAL fix) するため、path guard は bypass され UNDOCUMENTED 検出のみ発火。
# ============================================================
_case_l() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-l"
  mkdir -p "$tgt"
  # team-default preset で fresh install (local.yml が team-default 8 toggle true で生成)
  bash "$INSTALL_SH" "$tgt" --preset=team-default --no-mcp --no-docs --no-doctor >/dev/null 2>&1 || return 1
  # sanity: team-default で生成
  grep -q '^default_preset: team-default$' "${tgt}/.claude/harness-config.local.yml" || return 1
  # 人工 mismatch: draft_flow_guard を false に (matrix 期待 true / disabled_reason 未記載)
  cat > "${tgt}/.claude/harness-config.local.yml" <<YMLEOF
default_preset: team-default
feature_draft_flow_guard_enabled: false
feature_task_rule_guard_enabled: true
feature_workflow_enforcement_enabled: true
feature_gateguard_enabled: true
review_required_design: true
review_required_test: true
review_required_module: true
review_required_system: true
YMLEOF
  local out="${TMP_DIR}/case-l-out.log"
  _run_doctor "$tgt" "$out"
  local rc=$?
  # D6 WARN 発火 (一次 branch: UNDOCUMENTED mismatch)
  grep -q '^\[self-doctor\] WARN D6: ' "$out" || return 1
  # UNDOCUMENTED mismatch 文言確認 (二次 heuristic 「enabled が 0」との branch 分離)
  grep -q 'UNDOCUMENTED mismatch' "$out" || return 1
  [ "$rc" -eq 1 ] || return 1
  _assert_triplet "$out" 1 || return 1
  return 0
)

# ============================================================
# 実行
# ============================================================
printf '\n=== self-doctor-smoke (task-87 Step 3) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "clean install で WARN 0 + exit 0 (D2 分岐 (a) INFO 側)"
else                         _record FAIL A "clean install で WARN 0 + exit 0 (D2 分岐 (a) INFO 側)"; fi

if _case_b 2>/dev/null; then _record PASS B "local.yml 削除で D1 WARN + exit 1 (3 点提示 format)"
else                         _record FAIL B "local.yml 削除で D1 WARN + exit 1 (3 点提示 format)"; fi

if _case_c 2>/dev/null; then _record PASS C "hook exec bit 落しで D5 WARN + exit 1 (3 点提示 format)"
else                         _record FAIL C "hook exec bit 落しで D5 WARN + exit 1 (3 点提示 format)"; fi

if _case_d 2>/dev/null; then _record PASS D "settings.local.json 重複 key で D8 WARN + exit 1 (3 点提示 format)"
else                         _record FAIL D "settings.local.json 重複 key で D8 WARN + exit 1 (3 点提示 format)"; fi

if _case_e 2>/dev/null; then _record PASS E "env 未設定は INFO のみ exit 0 (期待外 WARN 0)"
else                         _record FAIL E "env 未設定は INFO のみ exit 0 (期待外 WARN 0)"; fi

if _case_f 2>/dev/null; then _record PASS F "install.sh --no-doctor で self-doctor 非実行"
else                         _record FAIL F "install.sh --no-doctor で self-doctor 非実行"; fi

if _case_g 2>/dev/null; then _record PASS G "script 不在でも install.sh exit 0 (fail-open silent skip)"
else                         _record FAIL G "script 不在でも install.sh exit 0 (fail-open silent skip)"; fi

if _case_h 2>/dev/null; then _record PASS H "HC_FEATURE_SELF_DOCTOR_ENABLED=false で no-op + 出力なし + exit 0"
else                         _record FAIL H "HC_FEATURE_SELF_DOCTOR_ENABLED=false で no-op + 出力なし + exit 0"; fi

if _case_i 2>/dev/null; then _record PASS I "--preset=harness-dev で D6 WARN なし + exit 0 (preset-aware 実効性)"
else                         _record FAIL I "--preset=harness-dev で D6 WARN なし + exit 0 (preset-aware 実効性)"; fi

if _case_j 2>/dev/null; then _record PASS J "manifest 乖離 settings.json で D2 分岐 (b) WARN + exit 1"
else                         _record FAIL J "manifest 乖離 settings.json で D2 分岐 (b) WARN + exit 1"; fi

if _case_k 2>/dev/null; then _record PASS K "install fail-open DoD runtime 実測 (WARN 発火中に install exit 0 + DONE)"
else                         _record FAIL K "install fail-open DoD runtime 実測 (WARN 発火中に install exit 0 + DONE)"; fi

if _case_l 2>/dev/null; then _record PASS L "D6 UNDOCUMENTED-mismatch 一次判定 branch runtime coverage"
else                         _record FAIL L "D6 UNDOCUMENTED-mismatch 一次判定 branch runtime coverage"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
