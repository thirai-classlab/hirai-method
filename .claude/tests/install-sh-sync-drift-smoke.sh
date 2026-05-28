#!/usr/bin/env bash
# install-sh-sync-drift-smoke.sh — task-58 G1 (harness-sync-uncommitted-drift)
#
# 目的:
#   install.sh --update が sync drift 案内を出力すること、および
#   --update --commit (opt-in) で sync 対象 file のみ commit され
#   project file (root README.md 等) が staging に入らないことを検証する。
#
# 採用案: C ハイブリッド
#   - default (--update のみ): 案内 + 変更 file 一覧出力 (honor system、commit はしない)
#   - opt-in (--update --commit): sync 対象 path のみ git add → chore(harness): sync commit
#   - 制約: project file は完全に触らない、git reset 禁止 (HIGH 教訓)
#
# Case 一覧:
#   A: --update で sync 変更があると stdout に「sync drift」案内 + 変更 file 一覧が含まれる
#   B: --update で sync 変更があっても自動 commit はされない (case A と独立、HEAD 不変)
#   C: --update --commit で sync 対象 file のみ自動 commit される
#   D: --update --commit 時に project file (root README.md) が staging に入らない (smoke 必須)
#   E: --update で sync 変更が 0 件なら案内 silent (false positive 防止)
#   F: --update --commit 後の working tree から harness-sync 変更が staging を経て消えている
#   G: 非 git target でも --update --commit で fail せず graceful (commit skip + WARN)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 各 case は per-case tmp dir で順序依存を排除
#   - target は /tmp 配下で cross-repo sandbox 制約の対象外 (smoke 専用)
#
# 実行:
#   bash .claude/tests/install-sh-sync-drift-smoke.sh
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
    printf 'ERROR: rsync not found (required by install.sh)\n' >&2
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    printf 'ERROR: git not found (required for this smoke)\n' >&2
    exit 1
fi

TMP_BASE="$(mktemp -d /tmp/install-sh-sync-drift-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT

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

# ---- fixture builders ----

# Build a target dir with a git repo + a baseline .claude/ install
# 初回 install で全 file が commit されたクリーン状態にする。
# 戻り: $TGT を caller で参照
_build_baseline_target() {
    local case_id="$1"
    TGT="${TMP_BASE}/tgt-${case_id}-$$"
    mkdir -p "$TGT"

    (
        set -uo pipefail
        cd "$TGT" || exit 1
        git init -q
        git config user.email "smoke@test.local"
        git config user.name "smoke test"
        # 初回 install (新規)
        bash "$INSTALL_SH" "$TGT" --no-mcp --no-docs >/dev/null 2>&1 || exit 1
        # baseline commit (harness 全体を一度 commit してクリーン化)
        # CLAUDE.md.template を README にしておく (cleanup)
        echo "# project" > README.md
        git add -A >/dev/null 2>&1
        git commit -q -m "baseline: initial install" >/dev/null 2>&1 || exit 1
    ) || return 1
    return 0
}

# Make a real sync drift: modify a file inside SCRIPT_DIR's .claude/ briefly,
# rerun --update against target, then restore SCRIPT_DIR.
# 実 SSoT (repo 本体) を触ると本 repo に副作用が出るため、
# 代わりに target 側の .claude/ の同期対象 file を一度書き換えて
# 「次回 --update で SSoT 側の内容に巻き戻る」状況を作る。
# これで rsync が変更 path を target に書き戻し、git status で diff が見える。
_inject_target_drift() {
    local tgt="$1"
    # target 側の hooks/lib/config-loader.sh 末尾に余計な行を追記して baseline commit。
    # 次回 --update でこの行が SSoT 側 (元 file) に巻き戻されるため、
    # target で git status に modified が立つ。
    (
        set -uo pipefail
        cd "$tgt" || exit 1
        local f=".claude/hooks/lib/config-loader.sh"
        [ -f "$f" ] || exit 1
        printf '\n# drift marker line for smoke\n' >> "$f"
        git add "$f" >/dev/null 2>&1
        git commit -q -m "drift: add marker to config-loader" >/dev/null 2>&1 || exit 1
    )
}

# ============================================================
# Case A: --update で sync 変更 → stdout に sync drift 案内 + file list
# ============================================================
_case_a() (
    set -uo pipefail
    _build_baseline_target a || return 1
    _inject_target_drift "$TGT" || return 1
    # --update で巻き戻し → 案内が出るはず
    local out
    out="$(bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs 2>&1)"
    # 案内 marker と file list を検証 (両方必要)
    printf '%s\n' "$out" | grep -qi 'sync drift\|synced.*file\|harness-sync' \
        && printf '%s\n' "$out" | grep -q 'config-loader.sh'
)

# ============================================================
# Case B: --update 単独では自動 commit されない (HEAD 不変)
# ============================================================
_case_b() (
    set -uo pipefail
    _build_baseline_target b || return 1
    _inject_target_drift "$TGT" || return 1
    local head_before head_after
    head_before="$(cd "$TGT" && git rev-parse HEAD)"
    bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs >/dev/null 2>&1 || return 1
    head_after="$(cd "$TGT" && git rev-parse HEAD)"
    # HEAD が動いていないこと (自動 commit なし)
    [ "$head_before" = "$head_after" ] || return 1
    # ただし working tree には変更がある (sync 反映済、commit は user に委ねる)
    (cd "$TGT" && git status --short | grep -q '.')
)

# ============================================================
# Case C: --update --commit で sync 対象 file のみ自動 commit
# ============================================================
_case_c() (
    set -uo pipefail
    _build_baseline_target c || return 1
    _inject_target_drift "$TGT" || return 1
    local head_before head_after
    head_before="$(cd "$TGT" && git rev-parse HEAD)"
    bash "$INSTALL_SH" "$TGT" --update --commit --no-mcp --no-docs >/dev/null 2>&1 || return 1
    head_after="$(cd "$TGT" && git rev-parse HEAD)"
    # HEAD が進んでいる (新 commit が作られた)
    [ "$head_before" != "$head_after" ] || return 1
    # commit message が chore(harness): sync を含む
    local msg
    msg="$(cd "$TGT" && git log -1 --format=%s)"
    printf '%s' "$msg" | grep -qi 'harness.*sync\|sync.*harness\|chore.*harness'
)

# ============================================================
# Case D: --update --commit で project file (root README.md) が staging に
#         入らない (= 触られない) — 巻き込み防止の最重要 case
# ============================================================
_case_d() (
    set -uo pipefail
    _build_baseline_target d || return 1
    # baseline 後、root README.md を modify して uncommitted のまま放置
    (cd "$TGT" && echo "user-edit line" >> README.md)
    _inject_target_drift "$TGT" || return 1
    # README.md は uncommitted (user 作業中扱い) のまま --update --commit
    bash "$INSTALL_SH" "$TGT" --update --commit --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # 新 commit に README.md が含まれていないこと
    local files_in_commit
    files_in_commit="$(cd "$TGT" && git show --name-only --format='' HEAD)"
    if printf '%s\n' "$files_in_commit" | grep -qE '^README\.md$'; then
        return 1   # README.md が混入 = FAIL
    fi
    # 同時に README.md が working tree でまだ modified (user 作業中) のはず
    (cd "$TGT" && git status --short -- README.md | grep -q '^.M')
)

# ============================================================
# Case E: --update で sync 変更 0 件なら案内 silent (false positive 防止)
# ============================================================
_case_e() (
    set -uo pipefail
    _build_baseline_target e || return 1
    # drift を入れない → --update で何も変わらないはず
    local out
    out="$(bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs 2>&1)"
    # sync drift / synced files 案内が **出ていない** ことを検証
    if printf '%s\n' "$out" | grep -qi 'sync drift'; then
        return 1
    fi
    # 0 件 silent または明示「no sync changes」が出ても OK
    return 0
)

# ============================================================
# Case F: --update --commit 後、harness-sync 変更が working tree から消える
#         (staging を経て commit 済、tree clean)
# ============================================================
_case_f() (
    set -uo pipefail
    _build_baseline_target f || return 1
    _inject_target_drift "$TGT" || return 1
    bash "$INSTALL_SH" "$TGT" --update --commit --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # .claude/ 配下に未 commit 変更が残っていないこと
    local dirty
    dirty="$(cd "$TGT" && git status --short -- .claude/ | head -5)"
    [ -z "$dirty" ]
)

# ============================================================
# Case G: 非 git target でも --update --commit で fail せず graceful skip
# ============================================================
_case_g() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-g-$$"
    mkdir -p "$tgt"
    bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # git init せずに --update --commit (= 非 git repo)
    local out exit_code
    out="$(bash "$INSTALL_SH" "$tgt" --update --commit --no-mcp --no-docs 2>&1)"
    exit_code=$?
    # exit 0 で完走 (commit skip + WARN メッセージ)
    [ "$exit_code" -eq 0 ] || return 1
    printf '%s\n' "$out" | grep -qi 'not a git\|no git\|skip.*commit\|git.*not'
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-sh-sync-drift-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "--update で sync drift 案内 + file list"
else                         _record FAIL A "--update で sync drift 案内 + file list"; fi

if _case_b 2>/dev/null; then _record PASS B "--update 単独では自動 commit されない"
else                         _record FAIL B "--update 単独では自動 commit されない"; fi

if _case_c 2>/dev/null; then _record PASS C "--update --commit で chore(harness): sync 自動 commit"
else                         _record FAIL C "--update --commit で chore(harness): sync 自動 commit"; fi

if _case_d 2>/dev/null; then _record PASS D "--commit が project file (README.md) を巻き込まない"
else                         _record FAIL D "--commit が project file (README.md) を巻き込まない"; fi

if _case_e 2>/dev/null; then _record PASS E "sync 変更 0 件なら案内 silent"
else                         _record FAIL E "sync 変更 0 件なら案内 silent"; fi

if _case_f 2>/dev/null; then _record PASS F "--commit 後 .claude/ working tree clean"
else                         _record FAIL F "--commit 後 .claude/ working tree clean"; fi

if _case_g 2>/dev/null; then _record PASS G "非 git target でも --commit graceful skip"
else                         _record FAIL G "非 git target でも --commit graceful skip"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
    printf 'FAILED cases:%s\n' "$FAILED_CASES"
    exit 1
fi
exit 0
