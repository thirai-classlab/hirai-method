#!/usr/bin/env bash
# yml-triplet-pre-commit-smoke.sh — task-100 P3-3/I7 (Wave 5) smoke (5 case)
#
# 役割:
#   .claude/templates/githooks/pre-commit §4.5 yml triplet policy を機械検証。
#   harness-config.yml に新規 key を追加した状態で pre-commit を起動し、
#   consumer + smoke の存在 / 不在を組み合わせて BLOCK / PASS 判定 + bypass /
#   既存 key modification 通過を確認する。
#
# Case 一覧 (5 件、A-E):
#   A: 三点揃 (key + consumer + smoke)              → PASS (exit 0)
#   B: consumer 不在 (key + smoke のみ)             → BLOCK (exit 1、BLOCK message + key 名 grep)
#   C: smoke 不在 (key + consumer のみ)             → BLOCK (exit 1、BLOCK message + key 名 grep)
#   D: bypass env (HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false /
#      HC_YML_TRIPLET_CHECK_ENABLED=false / ECC_YML_TRIPLET_OFF=1)
#      → PASS (exit 0)、consumer/smoke 不在でも BLOCK しない
#   E: 既存 key の modification (value 変更のみ、新 key 追加なし) → PASS
#
# 重要制約 (feedback_set_e_in_sourced_libs 規範):
#   - file-top に set -euo pipefail を書かない
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 各 case は mktemp -d 配下の 独立 tmp repo で git init + staging + pre-commit 起動
#   - repo 本体 (SSoT) を汚さない (cd tmp_repo で pre-commit 内 $_pc_repo_root を切替)
#
# 依存:
#   - .claude/templates/githooks/pre-commit (task-92 base + task-100 §4.5 追加)
#   - .claude/hooks/lib/config-loader.sh (feature toggle load)
#   - .claude/hooks/lib/block-message.sh は本 pre-commit template 内 _pc_emit_* 代替使用
#
# 実行:
#   bash .claude/tests/yml-triplet-pre-commit-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PRE_COMMIT_SRC="${REPO_ROOT}/.claude/templates/githooks/pre-commit"

if [ ! -f "$PRE_COMMIT_SRC" ]; then
  printf 'ERROR: pre-commit template not found: %s\n' "$PRE_COMMIT_SRC" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'ERROR: git not found\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/yml-triplet-pre-commit-smoke.XXXXXX" 2>/dev/null || true)"
if [ -z "${TMP_DIR:-}" ] || [ ! -d "$TMP_DIR" ]; then
  printf 'ERROR: mktemp -d 失敗\n' >&2
  exit 1
fi
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

# HC_* env 残留 unset (session leak 防止)
_cleanup_envs() {
  unset HC_FEATURE_YML_TRIPLET_CHECK_ENABLED 2>/dev/null || true
  unset HC_YML_TRIPLET_CHECK_ENABLED 2>/dev/null || true
  unset ECC_YML_TRIPLET_OFF 2>/dev/null || true
  unset HC_PRECOMMIT_SKIP 2>/dev/null || true
  unset HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED 2>/dev/null || true
  unset HC_PRE_COMMIT_SMOKE_BUDGET_SEC 2>/dev/null || true
  unset HC_PRECOMMIT_LIB_BLOCK_CHECK_OFF 2>/dev/null || true
  unset GIT_DIR 2>/dev/null || true
  unset GIT_WORK_TREE 2>/dev/null || true
}

# ============================================================
# tmp git repo セットアップ helper
#   $1 = tmp_repo path (mkdir 済前提)
#   本 harness の .claude/ 全体を symlink 経由で参照させる代わりに、
#   pre-commit が必要とする最小 subset を rsync/cp で複製 (config-loader.sh +
#   harness-config.yml + tests/*-smoke.sh + hooks/lib/*)。
#   git init + user.email/name 設定 + pre-commit template 内 config-loader
#   source path 依存が解消される (repo_root 切替)。
# ============================================================
_setup_tmp_repo() {
  local tgt="$1"
  # 必要 dir 作成
  mkdir -p "${tgt}/.claude/hooks/lib" \
           "${tgt}/.claude/scripts/lib" \
           "${tgt}/.claude/tests" \
           "${tgt}/.claude/templates/githooks" \
           "${tgt}/.claude" \
           "${tgt}/docs/draft" \
           "${tgt}/docs/tasks"
  # config-loader.sh + block-message.sh + observability.sh + bypass-logger.sh 複製
  # (存在するもののみ)
  local _f
  for _f in config-loader.sh block-message.sh observability.sh bypass-logger.sh mode-loader.sh; do
    if [ -f "${REPO_ROOT}/.claude/hooks/lib/${_f}" ]; then
      cp "${REPO_ROOT}/.claude/hooks/lib/${_f}" "${tgt}/.claude/hooks/lib/${_f}"
    fi
  done
  # harness-config.yml + local.yml (base) 複製
  if [ -f "${REPO_ROOT}/.claude/harness-config.yml" ]; then
    cp "${REPO_ROOT}/.claude/harness-config.yml" "${tgt}/.claude/harness-config.yml"
  fi
  # curated smoke script 群 (fast smoke curated set の 3 本、bash -n 対象含む)
  # 本 smoke では fast smoke curated set 自体を実行させないため、pre-commit を
  # feature OFF (HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true 前提だが curated smoke
  # は簡易 stub で pass させる) にする代わりに、
  # 実用上: fast smoke curated set を pre-commit 内 skip させるため、
  # HC_PRECOMMIT_SKIP を使うと yml triplet check 自体も skip される (§3.2 R1)。
  # そこで curated smoke 3 本 (enforcement-mismatch / harness-config-local /
  # common-rules-import) を「即 exit 0 の stub smoke」に置き換え、bash -n bulk を
  # 空にする (hooks/*.sh scripts/*.sh install.sh は tmp 側に存在しない → compgen で
  # skip される)。
  cat >"${tgt}/.claude/tests/enforcement-mismatch-smoke.sh" <<'EOSMOKE'
#!/usr/bin/env bash
# stub smoke for tmp isolation
exit 0
EOSMOKE
  cat >"${tgt}/.claude/tests/harness-config-local-smoke.sh" <<'EOSMOKE'
#!/usr/bin/env bash
# stub smoke for tmp isolation
exit 0
EOSMOKE
  cat >"${tgt}/.claude/tests/common-rules-import-smoke.sh" <<'EOSMOKE'
#!/usr/bin/env bash
# stub smoke for tmp isolation
exit 0
EOSMOKE
  chmod 755 "${tgt}/.claude/tests/"*.sh
  # pre-commit template 複製 (本 smoke 対象、SSoT)
  cp "$PRE_COMMIT_SRC" "${tgt}/.githooks/pre-commit" 2>/dev/null \
    || { mkdir -p "${tgt}/.githooks"; cp "$PRE_COMMIT_SRC" "${tgt}/.githooks/pre-commit"; }
  chmod 755 "${tgt}/.githooks/pre-commit"
  # git init + user 設定 + base commit + hooksPath 設定
  # 注意: hooksPath を base commit 前に設定すると pre-commit が base commit を
  #       BLOCK してしまう (harness-config.yml 全 key が「新規」判定)。
  #       hooksPath は base commit 後に設定する。
  (
    cd "$tgt" || return 1
    git init -q 2>/dev/null || return 1
    git config user.email 'test@example.com'
    git config user.name 'smoke-test'
    # base commit 用に harness-config.yml + tests stub stage & commit
    # (pre-commit template も stage 対象、tests 側 stub の diff 混入回避)
    git add .claude/harness-config.yml .claude/tests/*.sh .githooks/pre-commit 2>/dev/null || return 1
    git commit -q -m 'base: initial harness-config.yml + tests stub' 2>/dev/null || return 1
    # base commit 後に hooksPath 設定 (以降の commit で pre-commit を発火)
    git config core.hooksPath .githooks
  ) || return 1
  return 0
}

# ============================================================
# Case A: 三点揃 (key + consumer + smoke) → PASS
#   1. harness-config.yml に新規 key `feature_case_a_test_enabled: true` 追加
#   2. .claude/hooks/case-a-hook.sh に `HC_FEATURE_CASE_A_TEST_ENABLED` consumer 追加
#   3. .claude/tests/case-a-smoke.sh に `HC_FEATURE_CASE_A_TEST_ENABLED` smoke 追加
#   4. 全て stage → pre-commit 起動 → exit 0
# ============================================================
_case_a() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/case-a"
  mkdir -p "$tgt"
  _setup_tmp_repo "$tgt" || return 1
  cd "$tgt" || return 1
  # (1) 新規 key を yml に追加
  printf '\nfeature_case_a_test_enabled: true  # case A test key\n' >> .claude/harness-config.yml
  # (2) consumer hook 追加
  mkdir -p .claude/hooks
  cat >.claude/hooks/case-a-hook.sh <<'EOF'
#!/usr/bin/env bash
# case A consumer hook
if [ "${HC_FEATURE_CASE_A_TEST_ENABLED:-true}" = "false" ]; then
  exit 0
fi
exit 0
EOF
  chmod 755 .claude/hooks/case-a-hook.sh
  # (3) smoke 追加
  cat >.claude/tests/case-a-feature-smoke.sh <<'EOF'
#!/usr/bin/env bash
# case A smoke: exercises HC_FEATURE_CASE_A_TEST_ENABLED
export HC_FEATURE_CASE_A_TEST_ENABLED=false
exit 0
EOF
  chmod 755 .claude/tests/case-a-feature-smoke.sh
  # (4) stage all + pre-commit 起動
  git add .claude/harness-config.yml .claude/hooks/case-a-hook.sh .claude/tests/case-a-feature-smoke.sh 2>/dev/null || return 1
  # fast smoke curated set を skip するため HC_PRECOMMIT_SKIP は使わない (それ自体が yml triplet も skip する)
  # 代わりに feature ON のまま、bash -n が空 (tmp .claude/hooks/*.sh は case-a-hook.sh のみ、syntax valid) で pass
  local outlog="${TMP_DIR}/case-a-out.log"
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  # pre-commit を直接起動 (git hooks 経由でなく)
  bash .githooks/pre-commit >"$outlog" 2>&1
  local _exit=$?
  if [ $_exit -ne 0 ]; then
    printf 'DEBUG Case A: exit=%d, log:\n' "$_exit" >&2
    cat "$outlog" >&2
    return 1
  fi
  # BLOCK message が出ていない
  ! grep -q '新規 key を追加したが consumer/smoke' "$outlog"
)

# ============================================================
# Case B: consumer 不在 → BLOCK
#   key + smoke のみ、consumer なし → BLOCK (exit 1)
#   BLOCK message に key 名 + 「consumer 不在」grep
# ============================================================
_case_b() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/case-b"
  mkdir -p "$tgt"
  _setup_tmp_repo "$tgt" || return 1
  cd "$tgt" || return 1
  printf '\nfeature_case_b_test_enabled: true  # case B test key\n' >> .claude/harness-config.yml
  # smoke のみ (consumer なし)
  cat >.claude/tests/case-b-feature-smoke.sh <<'EOF'
#!/usr/bin/env bash
# case B smoke: exercises HC_FEATURE_CASE_B_TEST_ENABLED
export HC_FEATURE_CASE_B_TEST_ENABLED=false
exit 0
EOF
  chmod 755 .claude/tests/case-b-feature-smoke.sh
  git add .claude/harness-config.yml .claude/tests/case-b-feature-smoke.sh 2>/dev/null || return 1
  local outlog="${TMP_DIR}/case-b-out.log"
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  bash .githooks/pre-commit >"$outlog" 2>&1
  local _exit=$?
  # BLOCK 期待 (exit 1)
  if [ $_exit -eq 0 ]; then
    printf 'DEBUG Case B: expected BLOCK but exit 0, log:\n' >&2
    cat "$outlog" >&2
    return 1
  fi
  # BLOCK message + key 名 + consumer 不在 grep
  grep -q '新規 key を追加したが consumer/smoke' "$outlog" || return 1
  grep -q 'feature_case_b_test_enabled' "$outlog" || return 1
  grep -q 'consumer 不在' "$outlog"
)

# ============================================================
# Case C: smoke 不在 → BLOCK
#   key + consumer のみ、smoke なし → BLOCK (exit 1)
#   BLOCK message に key 名 + 「smoke 不在」grep
# ============================================================
_case_c() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/case-c"
  mkdir -p "$tgt"
  _setup_tmp_repo "$tgt" || return 1
  cd "$tgt" || return 1
  printf '\nfeature_case_c_test_enabled: true  # case C test key\n' >> .claude/harness-config.yml
  # consumer のみ (smoke なし)
  mkdir -p .claude/hooks
  cat >.claude/hooks/case-c-hook.sh <<'EOF'
#!/usr/bin/env bash
# case C consumer hook
if [ "${HC_FEATURE_CASE_C_TEST_ENABLED:-true}" = "false" ]; then
  exit 0
fi
exit 0
EOF
  chmod 755 .claude/hooks/case-c-hook.sh
  git add .claude/harness-config.yml .claude/hooks/case-c-hook.sh 2>/dev/null || return 1
  local outlog="${TMP_DIR}/case-c-out.log"
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  bash .githooks/pre-commit >"$outlog" 2>&1
  local _exit=$?
  if [ $_exit -eq 0 ]; then
    printf 'DEBUG Case C: expected BLOCK but exit 0, log:\n' >&2
    cat "$outlog" >&2
    return 1
  fi
  grep -q '新規 key を追加したが consumer/smoke' "$outlog" || return 1
  grep -q 'feature_case_c_test_enabled' "$outlog" || return 1
  grep -q 'smoke 不在' "$outlog"
)

# ============================================================
# Case D: bypass env → PASS
#   key のみ (consumer + smoke 不在) でも bypass env で BLOCK 回避
#   3 系統検証:
#     D-0: HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false (yml feature toggle 正式名、
#          config-loader.sh 経由 export される env 名、SSoT bypass 経路)
#     D-1: HC_YML_TRIPLET_CHECK_ENABLED=false (旧名 alias、後方互換維持)
#     D-2: ECC_YML_TRIPLET_OFF=1 (env 系統 1 commit)
# ============================================================
_case_d() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/case-d"
  mkdir -p "$tgt"
  _setup_tmp_repo "$tgt" || return 1
  cd "$tgt" || return 1
  printf '\nfeature_case_d_test_enabled: true  # case D test key (bypass)\n' >> .claude/harness-config.yml
  git add .claude/harness-config.yml 2>/dev/null || return 1

  # D-0: HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false で bypass (SSoT feature toggle 経路)
  local outlog0="${TMP_DIR}/case-d0-out.log"
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  export HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false
  bash .githooks/pre-commit >"$outlog0" 2>&1
  local _exit0=$?
  unset HC_FEATURE_YML_TRIPLET_CHECK_ENABLED
  if [ $_exit0 -ne 0 ]; then
    printf 'DEBUG Case D-0 (HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false): expected PASS but exit %d, log:\n' "$_exit0" >&2
    cat "$outlog0" >&2
    return 1
  fi
  if grep -q '新規 key を追加したが consumer/smoke' "$outlog0"; then
    printf 'DEBUG Case D-0: BLOCK message unexpectedly present\n' >&2
    return 1
  fi

  # D-1: HC_YML_TRIPLET_CHECK_ENABLED=false で bypass (旧名 alias、後方互換)
  local outlog1="${TMP_DIR}/case-d1-out.log"
  export HC_YML_TRIPLET_CHECK_ENABLED=false
  bash .githooks/pre-commit >"$outlog1" 2>&1
  local _exit1=$?
  unset HC_YML_TRIPLET_CHECK_ENABLED
  if [ $_exit1 -ne 0 ]; then
    printf 'DEBUG Case D-1 (HC_YML_TRIPLET_CHECK_ENABLED=false): expected PASS but exit %d, log:\n' "$_exit1" >&2
    cat "$outlog1" >&2
    return 1
  fi
  # BLOCK message が出ていない
  if grep -q '新規 key を追加したが consumer/smoke' "$outlog1"; then
    printf 'DEBUG Case D-1: BLOCK message unexpectedly present\n' >&2
    return 1
  fi

  # D-2: ECC_YML_TRIPLET_OFF=1 で bypass
  local outlog2="${TMP_DIR}/case-d2-out.log"
  export ECC_YML_TRIPLET_OFF=1
  bash .githooks/pre-commit >"$outlog2" 2>&1
  local _exit2=$?
  unset ECC_YML_TRIPLET_OFF
  if [ $_exit2 -ne 0 ]; then
    printf 'DEBUG Case D-2 (ECC_YML_TRIPLET_OFF=1): expected PASS but exit %d, log:\n' "$_exit2" >&2
    cat "$outlog2" >&2
    return 1
  fi
  if grep -q '新規 key を追加したが consumer/smoke' "$outlog2"; then
    printf 'DEBUG Case D-2: BLOCK message unexpectedly present\n' >&2
    return 1
  fi
  return 0
)

# ============================================================
# Case E: 既存 key の modification (value 変更のみ) → PASS
#   base commit の harness-config.yml 内既存 key `feature_pre_commit_smoke_enabled`
#   の value を書き換えるだけ (新 key 追加なし) → 三点 check 対象外
#   → BLOCK しない
# ============================================================
_case_e() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/case-e"
  mkdir -p "$tgt"
  _setup_tmp_repo "$tgt" || return 1
  cd "$tgt" || return 1
  # 既存 key `feature_pre_commit_smoke_enabled` の value を true → false に変更
  # (SSoT の yml では既存 key、consumer/smoke 既に SSoT に存在)
  # macOS/Linux 両対応 sed
  if sed -i.bak 's/^feature_pre_commit_smoke_enabled: true/feature_pre_commit_smoke_enabled: false/' .claude/harness-config.yml 2>/dev/null; then
    rm -f .claude/harness-config.yml.bak
  fi
  # diff が発生していることを確認
  if ! git diff --cached --name-only 2>/dev/null | grep -q harness-config.yml; then
    # stage 前なので add
    git add .claude/harness-config.yml 2>/dev/null || return 1
  fi
  # 実際に diff があるか (base commit が既存 key を含むかは fixture 依存だが、
  # SSoT の harness-config.yml 全体を base commit したので diff あり)
  local outlog="${TMP_DIR}/case-e-out.log"
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  bash .githooks/pre-commit >"$outlog" 2>&1
  local _exit=$?
  if [ $_exit -ne 0 ]; then
    printf 'DEBUG Case E: expected PASS but exit %d, log:\n' "$_exit" >&2
    cat "$outlog" >&2
    return 1
  fi
  # BLOCK message 不在 (既存 key の modification は triplet check 対象外)
  ! grep -q '新規 key を追加したが consumer/smoke' "$outlog"
)

# ============================================================
# 実行
# ============================================================
printf '\n=== yml-triplet-pre-commit-smoke (task-100 P3-3/I7 Wave 5) ===\n\n'

if _case_a; then _record PASS A "三点揃 (key + consumer + smoke) → PASS"
else             _record FAIL A "三点揃 (key + consumer + smoke) → PASS"; fi

if _case_b; then _record PASS B "consumer 不在 → BLOCK (key + 'consumer 不在' grep)"
else             _record FAIL B "consumer 不在 → BLOCK (key + 'consumer 不在' grep)"; fi

if _case_c; then _record PASS C "smoke 不在 → BLOCK (key + 'smoke 不在' grep)"
else             _record FAIL C "smoke 不在 → BLOCK (key + 'smoke 不在' grep)"; fi

if _case_d; then _record PASS D "bypass env (HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false + HC_YML_TRIPLET_CHECK_ENABLED=false + ECC_YML_TRIPLET_OFF=1) → PASS"
else             _record FAIL D "bypass env (HC_FEATURE_YML_TRIPLET_CHECK_ENABLED=false + HC_YML_TRIPLET_CHECK_ENABLED=false + ECC_YML_TRIPLET_OFF=1) → PASS"; fi

if _case_e; then _record PASS E "既存 key の modification (value 変更のみ、新 key なし) → PASS"
else             _record FAIL E "既存 key の modification (value 変更のみ、新 key なし) → PASS"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
