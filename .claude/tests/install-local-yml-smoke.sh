#!/usr/bin/env bash
# .claude/tests/install-local-yml-smoke.sh — HOTFIX-1 (install-immediately-usable-redesign-20260618 §9.1 / §4.1 対策 B)
#                                            + task-85 (install-preset-auto-switch §3 Step 3、case H-M)
#
# 目的:
#   install.sh §6.4 consuming repo preset bootstrap を検証する。
#   consuming repo への install 時に harness-config.local.yml が create-if-absent
#   生成され (default_preset: team-default + guard toggle 8 件 individual true =
#   feature 4 + review_required 4)、既存 local.yml は verbatim 保持される (冪等)
#   ことを確認する。review_required 4 件は enforcement_matrix の team-default 期待
#   (presets.team-default: true) との自己矛盾防止に必須 (欠くと consuming repo で
#   enforcement-mismatch-smoke Case 3 が UNDOCUMENTED mismatch FAIL する)。
#   task-85 で --preset=<name> parameterize (advisory|team-default|strict|harness-dev)
#   を追加、preset 別生成 / reject / 既存保持 WARN / allowed set drift を case H-M で検証。
#
# Case 一覧:
#   A: 空 target に新規 install → local.yml 生成 + team-default + 8 toggle true
#      (--preset 無指定 default = HOTFIX-1 後方互換の regression 検証を兼ねる)
#   B: A の target に --update 再実行 → local.yml が byte 単位で不変 (冪等)
#   C: custom 内容の local.yml を事前配置 → --update 後も verbatim 保持
#   D: --dry-run では local.yml が生成されない (mutation ゼロ)
#   E: install.sh §6.4 に self-install guard (物理 path 比較) が存在する (静的検査)
#   F: 生成済 local.yml を config-loader.sh が実際に load し guard toggle が true 化
#   G: 生成 local.yml 下で target の enforcement-mismatch-smoke.sh が全 PASS
#      (preset=team-default と実効 toggle の自己矛盾なし = HOTFIX-1 regression 防止)
#   H: --preset=strict 新規 install → default_preset: strict + 8 toggle true
#   I: --preset=advisory 新規 install → default_preset: advisory + 8 toggle false
#      + target の enforcement-mismatch-smoke 全 PASS (Case G 同型)
#   J: --preset=harness-dev 新規 install → default_preset: harness-dev + 8 toggle false
#      + target の enforcement-mismatch-smoke 全 PASS
#   K: --preset=bogus → exit 64 reject + local.yml 非生成 + .claude/ 未配置 (arg parse 段で die)
#   L: 既存 local.yml + --update --preset=strict → byte 不変 (verbatim) + stderr に WARN「--preset は無視」
#   M: (静的) install.sh --preset allowed set == hc-config.sh _validate_default_preset の
#      allowed set (両 file から 4 値を抽出して sort 比較、drift 機械検出)
#   N: (task-92 §3.5) install mode + settings.json 不在 → source から verbatim seed cp
#      + stdout に "seeded settings.json from source (install mode" ログ + cmp -s で byte 一致
#   O: (task-71 H2) update mode + settings.json 不在 → 自動再生成 skip + NOTE
#      「既存 settings.json 不在のため自動再生成 skip」stderr 出力 (permissions 喪失回避契約)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下の target に対して行い、repo 本体を汚さない
#
# 実行:
#   bash .claude/tests/install-local-yml-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
CONFIG_LOADER="${REPO_ROOT}/.claude/hooks/lib/config-loader.sh"
HC_CONFIG_SH="${REPO_ROOT}/.claude/scripts/hc-config.sh"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh 前提依存)\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "/tmp/install-local-yml-smoke.XXXXXX")"
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

# config-loader 検証 case 用: 外側 session の HC_* env 残留が
# genuine env preset として local.yml を打ち消すのを防ぐ
_cleanup_envs() {
  unset HC_CONFIG_PATH 2>/dev/null || true
  unset HC_LOCAL_CONFIG_PATH 2>/dev/null || true
  unset HC_DEFAULT_PRESET 2>/dev/null || true
  unset HC_FEATURE_TASK_RULE_GUARD_ENABLED 2>/dev/null || true
  unset HC_FEATURE_DRAFT_FLOW_GUARD_ENABLED 2>/dev/null || true
  unset HC_FEATURE_WORKFLOW_ENFORCEMENT_ENABLED 2>/dev/null || true
  unset HC_FEATURE_GATEGUARD_ENABLED 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_DESIGN 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_TEST 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_MODULE 2>/dev/null || true
  unset HC_REVIEW_REQUIRED_SYSTEM 2>/dev/null || true
}

# Case A/B は同一 target を共用する (A: 新規 install → B: --update 冪等)。
# B は A の成果物に依存するため実行順を A → B に固定する。
TGT_AB="${TMP_DIR}/target-ab"

# ============================================================
# Case A: 空 target に新規 install → local.yml 生成 + 内容 assert
# ============================================================
_case_a() (
  set -uo pipefail
  mkdir -p "$TGT_AB"
  bash "$INSTALL_SH" "$TGT_AB" --no-mcp --no-docs >/dev/null 2>&1 || return 1
  local yml="${TGT_AB}/.claude/harness-config.local.yml"
  [ -f "$yml" ] || return 1
  grep -q '^default_preset: team-default$' "$yml" || return 1
  grep -q '^feature_task_rule_guard_enabled: true$' "$yml" || return 1
  grep -q '^feature_draft_flow_guard_enabled: true$' "$yml" || return 1
  grep -q '^feature_workflow_enforcement_enabled: true$' "$yml" || return 1
  grep -q '^feature_gateguard_enabled: true$' "$yml" || return 1
  # review_required 4 件: 欠くと enforcement-mismatch-smoke Case 3 FAIL (team-default 自己矛盾)
  grep -q '^review_required_design: true$' "$yml" || return 1
  grep -q '^review_required_test: true$' "$yml" || return 1
  grep -q '^review_required_module: true$' "$yml" || return 1
  grep -q '^review_required_system: true$' "$yml"
)

# ============================================================
# Case B: --update 再実行 → local.yml が byte 単位で不変 (冪等)
# ============================================================
_case_b() (
  set -uo pipefail
  local yml="${TGT_AB}/.claude/harness-config.local.yml"
  [ -f "$yml" ] || return 1
  local ref="${TMP_DIR}/case-b-ref.yml"
  cp "$yml" "$ref"
  bash "$INSTALL_SH" "$TGT_AB" --update >/dev/null 2>&1 || return 1
  cmp -s "$ref" "$yml"
)

# ============================================================
# Case C: custom local.yml を事前配置 → --update 後も verbatim 保持
# ============================================================
_case_c() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-c"
  mkdir -p "${tgt}/.claude"
  local yml="${tgt}/.claude/harness-config.local.yml"
  printf '# project custom override (smoke)\ndefault_preset: strict\ndocs_approved_dir: design\n' > "$yml"
  local ref="${TMP_DIR}/case-c-ref.yml"
  cp "$yml" "$ref"
  bash "$INSTALL_SH" "$tgt" --update >/dev/null 2>&1 || return 1
  cmp -s "$ref" "$yml"
)

# ============================================================
# Case D: --dry-run では local.yml 生成されない (mutation ゼロ)
# ============================================================
_case_d() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-d"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-mcp --no-docs >/dev/null 2>&1 || return 1
  [ ! -f "${tgt}/.claude/harness-config.local.yml" ]
)

# ============================================================
# Case E: install.sh §6.4 に self-install guard が存在 (静的検査)
# 実 self-install は L128 die + backup mv がある為 /tmp 外で再現不可、
# 物理 path 比較 (pwd -P) と bootstrap skip の存在を grep で保証する
# ============================================================
_case_e() (
  set -uo pipefail
  grep -q 'consuming repo preset bootstrap' "$INSTALL_SH" || return 1
  grep -q 'pwd -P' "$INSTALL_SH" || return 1
  grep -q 'preset bootstrap skip' "$INSTALL_SH"
)

# ============================================================
# Case F: 生成済 local.yml を config-loader が load → toggle true 化
# ============================================================
_case_f() (
  set -uo pipefail
  [ -f "$CONFIG_LOADER" ] || return 1
  local yml="${TGT_AB}/.claude/harness-config.yml"
  [ -f "$yml" ] || return 1
  _cleanup_envs
  export HC_CONFIG_PATH="$yml"
  # shellcheck source=/dev/null
  . "$CONFIG_LOADER"
  [ "${HC_DEFAULT_PRESET:-}" = "team-default" ] || return 1
  [ "${HC_FEATURE_TASK_RULE_GUARD_ENABLED:-}" = "true" ] || return 1
  [ "${HC_FEATURE_GATEGUARD_ENABLED:-}" = "true" ] || return 1
  # review_required も local.yml override で runtime true 化されること
  [ "${HC_REVIEW_REQUIRED_TEST:-}" = "true" ] || return 1
  [ "${HC_REVIEW_REQUIRED_DESIGN:-}" = "true" ]
)

# ============================================================
# Case G: 生成 local.yml 下で target の enforcement-mismatch-smoke が全 PASS
# team-default 宣言と実効 toggle の自己矛盾 (docs_claim=block ∧ 実効 false ∧
# team-default disabled_reason 不在 = Case 3 UNDOCUMENTED mismatch) を検出する。
# harness sync checklist は consuming repo に smoke 全 PASS を要求するため、
# install 直後にこれが FAIL する regression を本 case で恒久防止する。
# ============================================================
_case_g() (
  set -uo pipefail
  local smoke="${TGT_AB}/.claude/tests/enforcement-mismatch-smoke.sh"
  [ -f "$smoke" ] || return 1
  _cleanup_envs
  bash "$smoke" >/dev/null 2>&1
)

# ============================================================
# task-85 helper 群 (case H-M 用、既存 case A-G は無変更維持)
# ============================================================

# 生成 local.yml の guard toggle 8 件 (feature 4 + review_required 4) を一括 assert。
# $1: local.yml path / $2: 期待値 (true|false)
# key 集合は install.sh §6.4 printf 8 行 (task-85 Step 1b) と対応。
_assert_toggles8() {
  local yml="$1" expected="$2" key
  for key in \
    feature_task_rule_guard_enabled \
    feature_draft_flow_guard_enabled \
    feature_workflow_enforcement_enabled \
    feature_gateguard_enabled \
    review_required_design \
    review_required_test \
    review_required_module \
    review_required_system; do
    grep -q "^${key}: ${expected}\$" "$yml" || return 1
  done
  return 0
}

# Case H/I/J 共通 helper: --preset=<name> 新規 install →
# default_preset 行 + toggle 8 件を assert。
# $1: target dir / $2: preset 名 / $3: 期待 toggle 値 (true|false)
_preset_install_and_assert() (
  set -uo pipefail
  local tgt="$1" preset="$2" expected="$3"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --preset="$preset" --no-mcp --no-docs >/dev/null 2>&1 || return 1
  local yml="${tgt}/.claude/harness-config.local.yml"
  [ -f "$yml" ] || return 1
  grep -q "^default_preset: ${preset}\$" "$yml" || return 1
  _assert_toggles8 "$yml" "$expected"
)

# Case I/J 共通 helper: target の enforcement-mismatch-smoke 実走 (Case G 同型)。
# _preset_toggle_value (install.sh) と enforcement_matrix presets 行の乖離、
# advisory/harness-dev disabled_reason 不在 (Case 3/5 FAIL) を機械検出する。
# $1: target dir
_run_target_mismatch_smoke() (
  set -uo pipefail
  local smoke="$1/.claude/tests/enforcement-mismatch-smoke.sh"
  [ -f "$smoke" ] || return 1
  _cleanup_envs
  bash "$smoke" >/dev/null 2>&1
)

# ============================================================
# Case H: --preset=strict 新規 install → default_preset: strict + 8 toggle true
# ============================================================
_case_h() (
  set -uo pipefail
  _preset_install_and_assert "${TMP_DIR}/target-h" strict true
)

# ============================================================
# Case I: --preset=advisory 新規 install → default_preset: advisory
# + 8 toggle false + target の enforcement-mismatch-smoke 全 PASS
# (advisory disabled_reason 8 件 = task-85 Step 2 の regression 防止)
# ============================================================
_case_i() (
  set -uo pipefail
  _preset_install_and_assert "${TMP_DIR}/target-i" advisory false || return 1
  _run_target_mismatch_smoke "${TMP_DIR}/target-i"
)

# ============================================================
# Case J: --preset=harness-dev 新規 install → default_preset: harness-dev
# + 8 toggle false + target の enforcement-mismatch-smoke 全 PASS
# ============================================================
_case_j() (
  set -uo pipefail
  _preset_install_and_assert "${TMP_DIR}/target-j" harness-dev false || return 1
  _run_target_mismatch_smoke "${TMP_DIR}/target-j"
)

# ============================================================
# Case K: --preset=bogus → exit 64 reject + local.yml 非生成 + .claude/ 未配置
# (arg parse 段で die するため install 副作用ゼロ)
# ============================================================
_case_k() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-k"
  mkdir -p "$tgt"
  local rc=0
  bash "$INSTALL_SH" "$tgt" --preset=bogus --no-mcp --no-docs >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] || return 1
  [ ! -f "${tgt}/.claude/harness-config.local.yml" ] || return 1
  [ ! -d "${tgt}/.claude" ]
)

# ============================================================
# Case L: 既存 local.yml + --update --preset=strict → byte 不変 (verbatim)
# + stderr に WARN「--preset=strict は無視」(既存 local.yml 保持の明示通知)
# ============================================================
_case_l() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-l"
  mkdir -p "${tgt}/.claude"
  local yml="${tgt}/.claude/harness-config.local.yml"
  printf '# project custom override (smoke case L)\ndefault_preset: advisory\n' > "$yml"
  local ref="${TMP_DIR}/case-l-ref.yml"
  cp "$yml" "$ref"
  local errlog="${TMP_DIR}/case-l-stderr.log"
  bash "$INSTALL_SH" "$tgt" --update --preset=strict >/dev/null 2>"$errlog" || return 1
  cmp -s "$ref" "$yml" || return 1
  grep -q 'WARN: --preset=strict は無視' "$errlog"
)

# ============================================================
# Case M: (静的) install.sh --preset allowed set == hc-config.sh
# _validate_default_preset の allowed set (drift 機械検出、draft §4 リスク 3)
# 抽出: 両 file の case pattern 行 (`advisory|team-default|...)`) から
# `|` 区切り値を取り出し sort 比較。件数 4 も assert (抽出 regex 空振り防止)。
# ============================================================
_case_m() (
  set -uo pipefail
  [ -f "$HC_CONFIG_SH" ] || return 1
  local set_a set_b
  # install.sh: --preset arg parse の allowed case pattern (PRESET_EXPLICIT=true 行で一意特定)
  set_a="$(sed -n 's/^[[:space:]]*\([a-z|-]\{1,\}\))[[:space:]]*PRESET_EXPLICIT=true.*/\1/p' "$INSTALL_SH" | tr '|' '\n' | sort)"
  # hc-config.sh: _validate_default_preset() 関数内の `return 0` case pattern
  set_b="$(sed -n '/^_validate_default_preset()/,/^}/p' "$HC_CONFIG_SH" \
    | sed -n 's/^[[:space:]]*\([a-z|-]\{1,\}\))[[:space:]]*return 0.*/\1/p' | tr '|' '\n' | sort)"
  [ -n "$set_a" ] || return 1
  [ -n "$set_b" ] || return 1
  [ "$(printf '%s\n' "$set_a" | grep -c .)" -eq 4 ] || return 1
  [ "$set_a" = "$set_b" ]
)

# ============================================================
# Case N: (task-92 §3.5) install mode + settings.json 不在 → source から seed cp
# 契約 (install.sh L1000-1012): MODE=install かつ TARGET/.claude/settings.json 不在なら
#   `cp $SCRIPT_DIR/.claude/settings.json $TARGET/.claude/settings.json` を実行
# assertion:
#   1. 実行後 target `.claude/settings.json` が存在する (seed 成功)
#   2. stdout に「seeded settings.json from source (install mode」を含む log 行
#      (seed 契約が動作した proof、生成 pipeline 順序変更 regression 検出)
#   3. cmp -s で source と byte 一致 (jq 存在時 generate-settings.sh 再配線後も
#      manifest 由来 = source 由来 で一致するのが正常状態、drift signal 兼用)
# ============================================================
_case_settings_seed_install() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-n"
  mkdir -p "$tgt"
  local outlog="${TMP_DIR}/case-n-out.log"
  # install mode (default) + --no-hooks で pre-commit 副作用回避 (本 case は settings.json seed 検証)
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs --no-hooks >"$outlog" 2>&1 || return 1
  # 1. settings.json 実在
  [ -f "${tgt}/.claude/settings.json" ] || return 1
  # 2. seed log 行 (§3.5 契約 marker)
  grep -q 'seeded settings.json from source (install mode' "$outlog" || return 1
  # 3. byte-identical (source と一致 = seed + regen が同 manifest 由来で drift 0)
  cmp -s "${REPO_ROOT}/.claude/settings.json" "${tgt}/.claude/settings.json"
)

# ============================================================
# Case O: (task-71 H2) update mode + settings.json 不在 → NOTE + 自動再生成 skip
# 契約 (install.sh L1023-1024): MODE=update かつ target settings.json 不在なら
#   `NOTE: 既存 settings.json 不在のため自動再生成 skip (permissions 喪失回避)` を stderr 出力
#   generate-settings.sh は起動しない (fail-open、permissions 前提が成立しないため)
# setup:
#   1. install mode で target を初期化 (settings.json seed 済状態)
#   2. seeded settings.json を削除 (task-71 H2 想定シナリオ: user が手動で消したケース)
# assertion:
#   1. update 実行後 settings.json は依然 不在 (自動生成しない fail-open 契約)
#   2. stderr に「既存 settings.json 不在のため自動再生成 skip」の NOTE 行
# ============================================================
_case_settings_seed_update_note() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-o"
  mkdir -p "$tgt"
  # 1. install mode で初期化 (seed 済状態)
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs --no-hooks >/dev/null 2>&1 || return 1
  [ -f "${tgt}/.claude/settings.json" ] || return 1
  # 2. seeded settings.json を削除 (シナリオ再現)
  rm -f "${tgt}/.claude/settings.json"
  # 3. update 実行
  local outlog="${TMP_DIR}/case-o-out.log"
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs --no-hooks >"$outlog" 2>&1 || return 1
  # 4. settings.json は依然不在 (自動生成しない contract)
  [ ! -f "${tgt}/.claude/settings.json" ] || return 1
  # 5. NOTE 行 存在 (task-71 H2 exact string、stdout/stderr 統合 log を対象)
  grep -q '既存 settings.json 不在のため自動再生成 skip' "$outlog"
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-local-yml-smoke (HOTFIX-1 + task-85) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "新規 install で local.yml 生成 (team-default + 8 toggle true)"
else                         _record FAIL A "新規 install で local.yml 生成 (team-default + 8 toggle true)"; fi

if _case_b 2>/dev/null; then _record PASS B "--update 再実行で local.yml byte 不変 (冪等)"
else                         _record FAIL B "--update 再実行で local.yml byte 不変 (冪等)"; fi

if _case_c 2>/dev/null; then _record PASS C "custom local.yml 事前配置 → --update 後も verbatim 保持"
else                         _record FAIL C "custom local.yml 事前配置 → --update 後も verbatim 保持"; fi

if _case_d 2>/dev/null; then _record PASS D "--dry-run で local.yml 生成されない"
else                         _record FAIL D "--dry-run で local.yml 生成されない"; fi

if _case_e 2>/dev/null; then _record PASS E "install.sh §6.4 に self-install guard 存在 (静的)"
else                         _record FAIL E "install.sh §6.4 に self-install guard 存在 (静的)"; fi

if _case_f 2>/dev/null; then _record PASS F "config-loader が生成 local.yml を load (toggle true 化)"
else                         _record FAIL F "config-loader が生成 local.yml を load (toggle true 化)"; fi

if _case_g 2>/dev/null; then _record PASS G "target の enforcement-mismatch-smoke 全 PASS (team-default 自己矛盾なし)"
else                         _record FAIL G "target の enforcement-mismatch-smoke 全 PASS (team-default 自己矛盾なし)"; fi

if _case_h 2>/dev/null; then _record PASS H "--preset=strict 新規 install (default_preset: strict + 8 toggle true)"
else                         _record FAIL H "--preset=strict 新規 install (default_preset: strict + 8 toggle true)"; fi

if _case_i 2>/dev/null; then _record PASS I "--preset=advisory 新規 install (8 toggle false + target mismatch smoke 全 PASS)"
else                         _record FAIL I "--preset=advisory 新規 install (8 toggle false + target mismatch smoke 全 PASS)"; fi

if _case_j 2>/dev/null; then _record PASS J "--preset=harness-dev 新規 install (8 toggle false + target mismatch smoke 全 PASS)"
else                         _record FAIL J "--preset=harness-dev 新規 install (8 toggle false + target mismatch smoke 全 PASS)"; fi

if _case_k 2>/dev/null; then _record PASS K "--preset=bogus は exit 64 reject (local.yml 非生成 + .claude/ 未配置)"
else                         _record FAIL K "--preset=bogus は exit 64 reject (local.yml 非生成 + .claude/ 未配置)"; fi

if _case_l 2>/dev/null; then _record PASS L "既存 local.yml + --update --preset=strict → byte 不変 + WARN「--preset は無視」"
else                         _record FAIL L "既存 local.yml + --update --preset=strict → byte 不変 + WARN「--preset は無視」"; fi

if _case_m 2>/dev/null; then _record PASS M "install.sh / hc-config.sh の preset allowed set 一致 (静的 drift 検出)"
else                         _record FAIL M "install.sh / hc-config.sh の preset allowed set 一致 (静的 drift 検出)"; fi

if _case_settings_seed_install 2>/dev/null; then _record PASS N "install mode + settings.json 不在 → source seed cp (task-92 §3.5)"
else                                                _record FAIL N "install mode + settings.json 不在 → source seed cp (task-92 §3.5)"; fi

if _case_settings_seed_update_note 2>/dev/null; then _record PASS O "update mode + settings.json 不在 → NOTE + 自動再生成 skip (task-71 H2)"
else                                                    _record FAIL O "update mode + settings.json 不在 → NOTE + 自動再生成 skip (task-71 H2)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
