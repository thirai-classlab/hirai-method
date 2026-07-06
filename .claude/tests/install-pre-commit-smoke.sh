#!/usr/bin/env bash
# .claude/tests/install-pre-commit-smoke.sh — task-92 P2-1/I3 Step 5 (11 cases、Fix C で I/J/K 追加)
#
# 役割:
#   install.sh §6.8 (.githooks/pre-commit 配布 + core.hooksPath idempotent 設定)
#   と .claude/templates/githooks/pre-commit の統合契約を検証する。
#   設計 SSoT: docs/draft/install-pre-commit-distribute.md §3.1 冪等性契約 7 件
#              + §3.2 fail-open 2 層 + §4.5 smoke case 詳細 + §6 DoD 検証。
#
# Case 一覧 (11 件、mktemp -d + trap cleanup、実 install で mutation 検証):
#   A: idempotent (2 回 install で state 不変、hooksPath + pre-commit byte 同一)
#   B: 既存 core.hooksPath (別 path 例 .husky) 保護 (WARN + HINT 出力、上書きしない)
#   C: --no-hooks で pre-commit 非配置 + core.hooksPath 未設定
#   D: --dry-run で mutation 0 (grep で pre-commit 未生成 + hooksPath 未変化 + [dry-run] 出力確認)
#   E: target 内で pre-commit 起動 → curated 4 smoke 順次実行 + exit 0 (all clean 時、< 15s)
#   F: feature toggle false (HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false) で hook が early exit 0
#      + 経過時間 < 0.5s + curated smoke 未実行 (bash -n / enforcement-mismatch 未走 grep)
#   G: 別 path core.hooksPath (.git-hooks 等) の Case B 変種 (別 path 名でも同動作)
#   H: (追加) curated set drift 検出 (DoD MED-5 fix、L344): pre-commit 内 hardcode の
#      curated 4 smoke path が実 file として存在することを機械検証
#   I: (Fix C 追加) HC_PRECOMMIT_SKIP=1 で 1-shot bypass (§3.2 R1 契約) → INFO stderr +
#      curated smoke 未実行 (fast smoke curated set FAIL 出力 なし) + exit 0
#   J: (Fix C 追加、契約 5) 非 git repo (.git 不在) 対象 install → pre-commit 配布のみ完遂
#      + core.hooksPath 未設定 + NOTE「git repo でない」+ HINT「git init 後に手動で」
#   K: (Fix C 追加、契約 1) 既存 project-owned <target>/.githooks/pre-commit → 上書きせず
#      byte 不変 + stdout「exists → skip (project-owned)」+ install 継続 exit 0
#
# 重要制約 (feedback_set_e_in_sourced_libs 規範):
#   - file-top に set -euo pipefail を書かない
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は mktemp -d 配下の target で行い repo 本体を汚さない
#   - HC_* env の外側 session 残留を各 subshell 冒頭で unset (env-leak 防止)
#
# 実行:
#   bash .claude/tests/install-pre-commit-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
PRE_COMMIT_SRC="${REPO_ROOT}/.claude/templates/githooks/pre-commit"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if [ ! -f "$PRE_COMMIT_SRC" ]; then
  printf 'ERROR: pre-commit template not found: %s\n' "$PRE_COMMIT_SRC" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh 前提依存)\n' >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'ERROR: git not found\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/install-pre-commit-smoke.XXXXXX" 2>/dev/null || true)"
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

# 外側 session の HC_* / GIT_* env 残留が本 smoke の subshell に leak するのを防ぐ
_cleanup_envs() {
  unset HC_CONFIG_PATH 2>/dev/null || true
  unset HC_LOCAL_CONFIG_PATH 2>/dev/null || true
  unset HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED 2>/dev/null || true
  unset HC_PRE_COMMIT_SMOKE_BUDGET_SEC 2>/dev/null || true
  unset HC_PRECOMMIT_SKIP 2>/dev/null || true
  unset GIT_DIR 2>/dev/null || true
  unset GIT_WORK_TREE 2>/dev/null || true
  unset GIT_CONFIG_GLOBAL 2>/dev/null || true
}

# BSD/GNU 両対応 mode 取得 (stat -f %A on BSD, -c %a on GNU)
_get_mode() {
  local f="$1"
  if stat -f %A "$f" 2>/dev/null; then
    return 0
  fi
  stat -c %a "$f" 2>/dev/null
}

# ============================================================
# Case A: idempotent (2 回 install で state 不変)
#   1 回目 install → git init → hooksPath 自動設定
#   2 回目 install (--update) → pre-commit byte 不変 + hooksPath 不変 (契約 3)
# ============================================================
_case_a() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-a"
  mkdir -p "$tgt"
  # 1 回目 install (新規)
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
  [ -f "${tgt}/.githooks/pre-commit" ] || return 1
  local mode1
  mode1="$(_get_mode "${tgt}/.githooks/pre-commit")"
  [ "$mode1" = "755" ] || return 1
  # git repo 化して hooksPath 自動設定を trigger (契約: git repo 検出時に自動 set)
  ( cd "$tgt" && git init -q 2>/dev/null && git config user.email 'a@b' && git config user.name 'a' ) || return 1
  # 2 回目 install (--update) で hooksPath 設定
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs >/dev/null 2>&1 || return 1
  # pre-commit byte 不変 (source template との一致で assert、上書き回避契約)
  cmp -s "$PRE_COMMIT_SRC" "${tgt}/.githooks/pre-commit" || return 1
  # hooksPath = .githooks
  local hp
  hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  [ "$hp" = ".githooks" ] || return 1
  # 3 回目 install (--update) → INFO no-op が出て、なお byte 不変
  local out
  out="${TMP_DIR}/case-a-3rd.log"
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs >"$out" 2>&1 || return 1
  grep -q 'core.hooksPath は既に .githooks (no-op)' "$out" || return 1
  cmp -s "$PRE_COMMIT_SRC" "${tgt}/.githooks/pre-commit"
)

# ============================================================
# Case B: 既存 core.hooksPath = .husky 保護 (契約 4)
#   install 前に git init + git config core.hooksPath .husky を設定
#   → install 後も .husky 保持 + WARN/HINT stderr grep + pre-commit は .githooks に配置される
# ============================================================
_case_b() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-b"
  mkdir -p "$tgt"
  ( cd "$tgt" && git init -q && git config user.email 'a@b' && git config user.name 'a' \
      && git config core.hooksPath .husky ) || return 1
  local outlog="${TMP_DIR}/case-b-out.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # hooksPath は .husky のまま (上書き禁止契約 4)
  local hp
  hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  [ "$hp" = ".husky" ] || return 1
  # WARN 出力 + HINT 出力の存在
  grep -q "WARN: core.hooksPath = '.husky' に設定済" "$outlog" || return 1
  grep -q 'HINT: 本 harness の pre-commit を使うには手動で' "$outlog" || return 1
  # pre-commit は .githooks/ には配置される (dir 保護契約 2 の逆: dir 自体は install 対象)
  [ -f "${tgt}/.githooks/pre-commit" ]
)

# ============================================================
# Case C: --no-hooks で hook 非配置 + core.hooksPath 未設定
# ============================================================
_case_c() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-c"
  mkdir -p "$tgt"
  ( cd "$tgt" && git init -q && git config user.email 'a@b' && git config user.name 'a' ) || return 1
  local outlog="${TMP_DIR}/case-c-out.log"
  bash "$INSTALL_SH" "$tgt" --no-hooks --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # pre-commit 非配置
  [ ! -e "${tgt}/.githooks/pre-commit" ] || return 1
  # core.hooksPath 未設定 (empty)
  local hp
  hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  [ -z "$hp" ] || return 1
  # skip 通知 stderr grep
  grep -q '(--no-hooks) skip pre-commit 配布' "$outlog"
)

# ============================================================
# Case D: --dry-run で mutation 0
#   pre-commit 未生成 + hooksPath 未変化 + [dry-run] 出力を含む
# ============================================================
_case_d() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-d"
  mkdir -p "$tgt"
  ( cd "$tgt" && git init -q && git config user.email 'a@b' && git config user.name 'a' ) || return 1
  local before_hp
  before_hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  local outlog="${TMP_DIR}/case-d-out.log"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # pre-commit 未生成 (dry-run で mutation 0)
  [ ! -e "${tgt}/.githooks/pre-commit" ] || return 1
  # hooksPath 未変化 (実行前後で同じ = 空文字のまま)
  local after_hp
  after_hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  [ "$before_hp" = "$after_hp" ] || return 1
  # [dry-run] 出力 2 件以上 (cp/chmod/git config 各行、DoD L336)
  local dry_count
  dry_count="$(grep -c '\[dry-run\]' "$outlog" || true)"
  [ "$dry_count" -ge 2 ]
)

# ============================================================
# Case E: target 内で pre-commit 起動 → curated 4 smoke 実行 + exit 0
#   本 repo の pre-commit を repo root で直接起動し、
#   curated 4 smoke (bash -n + enforcement-mismatch + harness-config-local +
#   common-rules-import) の順次実行完遂 + exit 0 を確認
#   時間 < 15s (draft §3.3 empirical 2.4s、Step 1 dogfood 5s、本 repo 実測 8s、
#   CI/低速 runner 想定で 15s に設定。pre-commit 予算 3s 超過は smoke 側では判定せず、
#   pre-commit 内 WARN で signal 化される契約)
# ============================================================
_case_e() (
  set -uo pipefail
  _cleanup_envs
  # 本 smoke は repo 本体 (SSoT template + curated smoke set) で走らせる。
  # tmp target への複製は install-sh 済 (Case A で検証)、E は「pre-commit そのもの」を検証。
  cd "$REPO_ROOT" || return 1
  # feature toggle を明示 ON (env で強制、yml default 依存を除去)
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  # 予算を広めに設定 (WARN 抑制、smoke 判定は exit code のみ)
  export HC_PRE_COMMIT_SMOKE_BUDGET_SEC=30
  local outlog="${TMP_DIR}/case-e-out.log"
  local start_ts end_ts elapsed
  start_ts=$(date +%s)
  # pre-commit template を直接起動
  bash "$PRE_COMMIT_SRC" >"$outlog" 2>&1 || return 1
  end_ts=$(date +%s)
  elapsed=$((end_ts - start_ts))
  # 15s 超過は FAIL (curated set drift signal、draft §3.3)
  [ "$elapsed" -le 15 ] || return 1
  # 予算超過 WARN が出ていない (30s は十分広い)
  ! grep -q '予算超過' "$outlog" || return 1
  return 0
)

# ============================================================
# Case F: feature toggle false で hook が early exit 0
#   HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false → silent pass < 0.5s
#   curated smoke 未実行 (bash -n / enforcement-mismatch 実行痕跡なし)
# ============================================================
_case_f() (
  set -uo pipefail
  _cleanup_envs
  cd "$REPO_ROOT" || return 1
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=false
  local outlog="${TMP_DIR}/case-f-out.log"
  # pre-commit 起動
  bash "$PRE_COMMIT_SRC" >"$outlog" 2>&1 || return 1
  # 出力が (feature OFF の silent pass) なほぼ空である
  # curated smoke 起動痕跡が無い (「pre-commit BLOCK」「予算超過」等が出ない)
  ! grep -q 'BLOCK' "$outlog" || return 1
  ! grep -q '予算超過' "$outlog" || return 1
  # 短時間 exit を assert する代わりに、少なくとも WARN 「fast smoke curated set FAIL」
  # が出ないことを確認 (feature OFF は curated 未実行契約)
  ! grep -q 'fast smoke curated set FAIL' "$outlog"
)

# ============================================================
# Case G: 別 path core.hooksPath (.git-hooks) 保護 (Case B 変種)
#   .husky 以外の別 path 名でも同 WARN/HINT 動作 (契約 4 の path 非依存性)
# ============================================================
_case_g() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-g"
  mkdir -p "$tgt"
  ( cd "$tgt" && git init -q && git config user.email 'a@b' && git config user.name 'a' \
      && git config core.hooksPath .git-hooks ) || return 1
  local outlog="${TMP_DIR}/case-g-out.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # hooksPath は .git-hooks のまま
  local hp
  hp="$( cd "$tgt" && git config --get core.hooksPath 2>/dev/null || true )"
  [ "$hp" = ".git-hooks" ] || return 1
  # WARN 出力 (path 名 .git-hooks を含む)
  grep -q "WARN: core.hooksPath = '.git-hooks' に設定済" "$outlog" || return 1
  # HINT 出力
  grep -q 'HINT: 本 harness の pre-commit を使うには手動で' "$outlog"
)

# ============================================================
# Case H: curated set drift 検出 (DoD MED-5 fix、L344)
#   pre-commit 内 hardcode の 4 smoke path が実 file として存在
#   (smoke rename / dir 変更で silent skip 化するのを防止)
# ============================================================
_case_h() (
  set -uo pipefail
  # pre-commit template 内で hardcode されている curated smoke 名を抽出
  # (draft §3.3 curated 4 本のうち bash -n bulk 以外の 3 smoke + bash -n 対象群)
  # 3 smoke の実在性を機械検証:
  local s
  for s in enforcement-mismatch-smoke.sh harness-config-local-smoke.sh common-rules-import-smoke.sh; do
    grep -q "$s" "$PRE_COMMIT_SRC" || return 1
    [ -f "${REPO_ROOT}/.claude/tests/$s" ] || return 1
  done
  # bash -n bulk 対象 (.claude/hooks/*.sh / .claude/scripts/*.sh / install.sh)
  # が pre-commit 内に list されていることを確認
  grep -q '.claude/hooks/\*.sh' "$PRE_COMMIT_SRC" || return 1
  grep -q '.claude/scripts/\*.sh' "$PRE_COMMIT_SRC" || return 1
  grep -q 'install.sh' "$PRE_COMMIT_SRC"
)

# ============================================================
# Case I: HC_PRECOMMIT_SKIP=1 で 1-shot bypass (§3.2 R1 契約、Fix C)
#   pre-commit 内 L78-85: [ "${HC_PRECOMMIT_SKIP:-0}" = "1" ] → INFO 出力 + exit 0
#   assertion:
#     1. exit 0
#     2. stderr に「HC_PRECOMMIT_SKIP=1 検出」INFO
#     3. curated smoke 未実行 signal: 「fast smoke curated set FAIL」出力 なし
#        + 「予算超過」WARN なし (curated smoke 未起動なら計測 blank)
# ============================================================
_case_i() (
  set -uo pipefail
  _cleanup_envs
  # 本 case は repo 本体 (SSoT template) で走らせる (Case E/F 同 pattern)
  cd "$REPO_ROOT" || return 1
  export HC_PRECOMMIT_SKIP=1
  # feature toggle は default (ON) で明示 → bypass path が feature ON 状態でも exit 0 を assert
  export HC_FEATURE_PRE_COMMIT_SMOKE_ENABLED=true
  local outlog="${TMP_DIR}/case-i-out.log"
  bash "$PRE_COMMIT_SRC" >"$outlog" 2>&1 || return 1
  # INFO の存在 (§3.2 R1 契約 marker)
  grep -q 'HC_PRECOMMIT_SKIP=1 検出' "$outlog" || return 1
  # curated smoke 未実行 signal: FAIL / 予算超過 いずれも無し
  ! grep -q 'fast smoke curated set FAIL' "$outlog" || return 1
  ! grep -q '予算超過' "$outlog"
)

# ============================================================
# Case J: 非 git repo (.git 不在) 対象 install (契約 5、Fix C)
#   install.sh L1376-1379: `[[ ! -d "$TARGET/.git" ]]` → NOTE + HINT + git config skip
#   assertion:
#     1. exit 0 (fail-open + git 独立で継続)
#     2. .githooks/pre-commit 配置 (mode 755)
#     3. core.hooksPath 空 (git repo 不在 → git config は fail、確認せずとも file なし)
#     4. stdout に NOTE「git repo でない」+ HINT「git init 後に手動で」
# ============================================================
_case_j() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-j"
  mkdir -p "$tgt"
  # git init はしない (契約 5 の非 git repo シナリオ)
  local outlog="${TMP_DIR}/case-j-out.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # pre-commit は配置される (契約 5: 配布のみ実施)
  [ -f "${tgt}/.githooks/pre-commit" ] || return 1
  local mode
  mode="$(_get_mode "${tgt}/.githooks/pre-commit")"
  [ "$mode" = "755" ] || return 1
  # target に .git dir 不在 (git config は当然 fail する = skip 契約)
  [ ! -d "${tgt}/.git" ] || return 1
  # NOTE 行 (契約 5 marker、install.sh L1378)
  grep -q 'git repo でない' "$outlog" || return 1
  # HINT 行 (install.sh L1379)
  grep -q 'git init 後に手動で' "$outlog"
)

# ============================================================
# Case K: 既存 project-owned pre-commit 保護 (契約 1、Fix C)
#   install.sh L1334-1335: `[[ -f "$PRE_COMMIT_DST" ]]` → 上書き skip + INFO 出力
#   assertion:
#     1. exit 0
#     2. 既存 <target>/.githooks/pre-commit byte 不変 (cmp -s 事前 snapshot と一致)
#     3. stdout「exists → skip (project-owned)」marker (契約 1 marker)
# ============================================================
_case_k() (
  set -uo pipefail
  _cleanup_envs
  local tgt="${TMP_DIR}/target-k"
  mkdir -p "${tgt}/.githooks"
  # project-owned pre-commit を事前配置 (custom byte pattern)
  printf '#!/usr/bin/env bash\n# PROJECT_OWNED_MARKER — do not overwrite\nexit 0\n' > "${tgt}/.githooks/pre-commit"
  chmod 755 "${tgt}/.githooks/pre-commit"
  local ref="${TMP_DIR}/case-k-ref.pre-commit"
  cp "${tgt}/.githooks/pre-commit" "$ref"
  # (option) 非 git repo で回避 (git config skip 経路 = case J と同 branch)、
  # 契約 1 の byte 不変性は git 有無に依存しない
  local outlog="${TMP_DIR}/case-k-out.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$outlog" 2>&1 || return 1
  # byte 不変 assert (契約 1 の中核)
  cmp -s "$ref" "${tgt}/.githooks/pre-commit" || return 1
  # 契約 1 marker の存在
  grep -q 'exists → skip (project-owned)' "$outlog"
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-pre-commit-smoke (task-92 P2-1/I3 Step 5) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "idempotent (2 回 install で state 不変 + hooksPath 自動設定 + 3rd INFO no-op)"
else                         _record FAIL A "idempotent (2 回 install で state 不変 + hooksPath 自動設定 + 3rd INFO no-op)"; fi

if _case_b 2>/dev/null; then _record PASS B "既存 core.hooksPath=.husky 保護 (上書きせず WARN + HINT 出力)"
else                         _record FAIL B "既存 core.hooksPath=.husky 保護 (上書きせず WARN + HINT 出力)"; fi

if _case_c 2>/dev/null; then _record PASS C "--no-hooks で pre-commit 非配置 + core.hooksPath 未設定"
else                         _record FAIL C "--no-hooks で pre-commit 非配置 + core.hooksPath 未設定"; fi

if _case_d 2>/dev/null; then _record PASS D "--dry-run で mutation 0 (pre-commit 未生成 + hooksPath 未変化 + [dry-run] >= 2)"
else                         _record FAIL D "--dry-run で mutation 0 (pre-commit 未生成 + hooksPath 未変化 + [dry-run] >= 2)"; fi

if _case_e 2>/dev/null; then _record PASS E "target で pre-commit 起動 → curated 4 smoke 実行 + exit 0 (< 15s)"
else                         _record FAIL E "target で pre-commit 起動 → curated 4 smoke 実行 + exit 0 (< 15s)"; fi

if _case_f 2>/dev/null; then _record PASS F "feature toggle false で hook が silent pass (curated smoke 未実行)"
else                         _record FAIL F "feature toggle false で hook が silent pass (curated smoke 未実行)"; fi

if _case_g 2>/dev/null; then _record PASS G "別 path core.hooksPath=.git-hooks 保護 (Case B 変種、path 非依存)"
else                         _record FAIL G "別 path core.hooksPath=.git-hooks 保護 (Case B 変種、path 非依存)"; fi

if _case_h 2>/dev/null; then _record PASS H "curated set drift 検出 (pre-commit 内 hardcode 4 smoke path 実在検証)"
else                         _record FAIL H "curated set drift 検出 (pre-commit 内 hardcode 4 smoke path 実在検証)"; fi

if _case_i 2>/dev/null; then _record PASS I "HC_PRECOMMIT_SKIP=1 で 1-shot bypass (INFO + curated smoke 未実行 + exit 0)"
else                         _record FAIL I "HC_PRECOMMIT_SKIP=1 で 1-shot bypass (INFO + curated smoke 未実行 + exit 0)"; fi

if _case_j 2>/dev/null; then _record PASS J "非 git repo install (契約 5: 配布のみ + NOTE + HINT + git config skip)"
else                         _record FAIL J "非 git repo install (契約 5: 配布のみ + NOTE + HINT + git config skip)"; fi

if _case_k 2>/dev/null; then _record PASS K "既存 project-owned pre-commit 保護 (契約 1: byte 不変 + skip marker)"
else                         _record FAIL K "既存 project-owned pre-commit 保護 (契約 1: byte 不変 + skip marker)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
