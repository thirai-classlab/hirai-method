#!/usr/bin/env bash
# install-sh-overwrite-all-smoke.sh — task-79 (install.sh 全上書きモード)
#
# 目的:
#   install.sh --overwrite-all (全上書き mode) が:
#     - settings.local.json **のみ** を温存する
#     - settings.json / harness-config.local.yml / state dir 等の local override を上書きする
#     - --delete を使わない = target にしかない独自 file を残す (上書きのみ)
#     - --dry-run でプレビューのみ (実書込なし)
#   を満たし、かつ mode 排他 (--update/--force/--overwrite-all 同時指定で error) を検証する。
#
# 採用案: A (新 mode flag --overwrite-all、exclude=settings.local.json のみ、--delete なし)
#   SSoT: docs/draft/install-full-overwrite-mode.md §3
#
# Case 一覧:
#   A: --overwrite-all で settings.local.json が温存される (内容不変)
#   B: --overwrite-all で settings.json が source 内容に上書きされる (drift 巻き戻り)
#   C: --overwrite-all で state dir (.claude/.workflow-state/) が source 内容で上書きされる
#      (draft §3 核心「settings.local.json 以外の state dir も上書きする」を直接 assert。
#       旧 C (harness-config.local.yml 上書き) は source repo で local.yml が gitignore /
#       untracked のため fresh checkout では source 不在 → else 無条件 PASS に退化していた。
#       git-tracked な .workflow-state/SCHEMA.md を SSoT anchor に置換して実挙動を assert する。)
#   D: --delete 不使用 → target 独自 file (.claude/_target_only.txt) が残る
#   E: --dry-run --overwrite-all はプレビューのみ (実書込なし、drift が残る)
#   F: mode 排他 — --update --overwrite-all 同時指定で非 0 exit + conflict error
#   G: mode 排他 — --force --overwrite-all 同時指定で非 0 exit + conflict error
#   H: --overwrite-all は既存 .claude/ 不在で error (新規は default mode を促す)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 各 case は per-case tmp dir で順序依存を排除
#   - target は /tmp 配下で cross-repo sandbox 制約の対象外 (smoke 専用)
#   - bash 3.2 互換 (連想配列 / mapfile 不使用)
#
# 実行:
#   bash .claude/tests/install-sh-overwrite-all-smoke.sh
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

TMP_BASE="$(mktemp -d /tmp/install-sh-overwrite-all-smoke.XXXXXX)"
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

# ---- fixture builder ----
#
# Build a target dir with a baseline .claude/ install, then inject local drift:
#   - settings.local.json        : machine-local marker (should be PRESERVED)
#   - settings.json              : drift marker (should be OVERWRITTEN)
#   - .workflow-state/SCHEMA.md  : state-dir drift (should be OVERWRITTEN by source)
#   - .claude/_target_only.txt   : target-only file (should be KEPT, no --delete)
# 戻り: $TGT を caller で参照
#
# NOTE: 初回 install は default RSYNC_EXCLUDES で .workflow-state/ を exclude するため
# target には source の SCHEMA.md が配置されない。state-dir 上書きを検証する Case C は、
# drift file を手動で作り込んでから overwrite-all (RSYNC_EXCLUDES_MINIMAL = local.json のみ
# 温存) が source 内容へ巻き戻すことを assert する。
_build_drifted_target() {
    local case_id="$1"
    TGT="${TMP_BASE}/tgt-${case_id}-$$"
    mkdir -p "$TGT"
    (
        set -uo pipefail
        cd "$TGT" || exit 1
        # 初回 install (新規、git/mcp/docs 不要)
        bash "$INSTALL_SH" "$TGT" --no-mcp --no-docs >/dev/null 2>&1 || exit 1
        # machine-local 設定 (温存対象)
        printf '{"_local_marker":"PRESERVE_ME"}\n' > .claude/settings.local.json
        # settings.json drift (上書き対象) — source とは異なる内容
        printf '{"_drift_marker":"OVERWRITE_ME_SETTINGS"}\n' > .claude/settings.json
        # state dir drift (上書き対象) — overwrite-all は state dir も source 内容に巻き戻す
        mkdir -p .claude/.workflow-state
        printf '# DRIFTED_STATE_SCHEMA — must be overwritten by source\n' \
            > .claude/.workflow-state/SCHEMA.md
        # target 独自 file (--delete 不使用なら残るべき)
        printf 'target only — must survive overwrite-all\n' > .claude/_target_only.txt
    ) || return 1
    return 0
}

# ============================================================
# Case A: settings.local.json が温存される (内容不変)
# ============================================================
_case_a() (
    set -uo pipefail
    _build_drifted_target a || return 1
    bash "$INSTALL_SH" "$TGT" --overwrite-all --no-mcp --no-docs >/dev/null 2>&1 || return 1
    grep -q 'PRESERVE_ME' "$TGT/.claude/settings.local.json"
)

# ============================================================
# Case B: settings.json が source 内容に上書きされる (drift 巻き戻り)
# ============================================================
_case_b() (
    set -uo pipefail
    _build_drifted_target b || return 1
    bash "$INSTALL_SH" "$TGT" --overwrite-all --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # drift marker が消えていること = 上書きされた
    if grep -q 'OVERWRITE_ME_SETTINGS' "$TGT/.claude/settings.json" 2>/dev/null; then
        return 1
    fi
    # source の settings.json と一致すること (存在する場合)
    if [ -f "$REPO_ROOT/.claude/settings.json" ]; then
        cmp -s "$REPO_ROOT/.claude/settings.json" "$TGT/.claude/settings.json"
    else
        # source に settings.json がなければ「drift marker が消えた」だけで PASS
        return 0
    fi
)

# ============================================================
# Case C: state dir (.claude/.workflow-state/) が source 内容で上書きされる
#   draft §3 核心挙動「settings.local.json 以外の state dir も上書きする」を直接 assert。
#   RSYNC_EXCLUDES_MINIMAL は settings.local.json のみ温存 → state dir は exclude されない
#   = source の SCHEMA.md (git-tracked) が target の drift 版を巻き戻す。
# ============================================================
_case_c() (
    set -uo pipefail
    # source の state-dir anchor (git-tracked) が無ければ前提崩壊 → skip 扱いで FAIL せず
    # 報告できるよう、anchor 不在は明示 return 1 (通常の checkout では必ず存在する)。
    [ -f "$REPO_ROOT/.claude/.workflow-state/SCHEMA.md" ] || return 1
    _build_drifted_target c || return 1
    bash "$INSTALL_SH" "$TGT" --overwrite-all --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # drift marker が消えている = source で上書きされた
    if grep -q 'DRIFTED_STATE_SCHEMA' "$TGT/.claude/.workflow-state/SCHEMA.md" 2>/dev/null; then
        return 1
    fi
    # source の SCHEMA.md と一致すること (state dir も巻き戻る確証)
    cmp -s "$REPO_ROOT/.claude/.workflow-state/SCHEMA.md" "$TGT/.claude/.workflow-state/SCHEMA.md"
)

# ============================================================
# Case D: --delete 不使用 → target 独自 file が残る (上書きのみ)
# ============================================================
_case_d() (
    set -uo pipefail
    _build_drifted_target d || return 1
    bash "$INSTALL_SH" "$TGT" --overwrite-all --no-mcp --no-docs >/dev/null 2>&1 || return 1
    [ -f "$TGT/.claude/_target_only.txt" ] \
        && grep -q 'must survive' "$TGT/.claude/_target_only.txt"
)

# ============================================================
# Case E: --dry-run --overwrite-all はプレビューのみ (実書込なし)
# ============================================================
_case_e() (
    set -uo pipefail
    _build_drifted_target e || return 1
    # dry-run 実行 → settings.json の drift が残っているはず (実書込なし)
    local out
    out="$(bash "$INSTALL_SH" "$TGT" --overwrite-all --dry-run --no-mcp --no-docs 2>&1)" || return 1
    # drift marker がまだ生きている = 実書込されていない
    grep -q 'OVERWRITE_ME_SETTINGS' "$TGT/.claude/settings.json" || return 1
    # 出力に overwrite-all mode の痕跡があること
    printf '%s\n' "$out" | grep -qi 'overwrite-all\|dry-run'
)

# ============================================================
# Case F: mode 排他 — --update --overwrite-all 同時指定で error
# ============================================================
_case_f() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-f-$$"
    mkdir -p "$tgt"
    local out ec
    out="$(bash "$INSTALL_SH" "$tgt" --update --overwrite-all --no-mcp --no-docs 2>&1)"
    ec=$?
    [ "$ec" -ne 0 ] || return 1
    printf '%s\n' "$out" | grep -qi 'conflict\|mutually exclusive'
)

# ============================================================
# Case G: mode 排他 — --force --overwrite-all 同時指定で error
# ============================================================
_case_g() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-g-$$"
    mkdir -p "$tgt"
    local out ec
    out="$(bash "$INSTALL_SH" "$tgt" --force --overwrite-all --no-mcp --no-docs 2>&1)"
    ec=$?
    [ "$ec" -ne 0 ] || return 1
    printf '%s\n' "$out" | grep -qi 'conflict\|mutually exclusive'
)

# ============================================================
# Case H: --overwrite-all は既存 .claude/ 不在で error
# ============================================================
_case_h() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-h-$$"
    mkdir -p "$tgt"   # .claude/ を作らない
    local out ec
    out="$(bash "$INSTALL_SH" "$tgt" --overwrite-all --no-mcp --no-docs 2>&1)"
    ec=$?
    [ "$ec" -ne 0 ] || return 1
    printf '%s\n' "$out" | grep -qi 'requires existing\|\.claude'
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-sh-overwrite-all-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "settings.local.json が温存される"
else                         _record FAIL A "settings.local.json が温存される"; fi

if _case_b 2>/dev/null; then _record PASS B "settings.json が source で上書きされる"
else                         _record FAIL B "settings.json が source で上書きされる"; fi

if _case_c 2>/dev/null; then _record PASS C "state dir (.workflow-state) が source で上書きされる"
else                         _record FAIL C "state dir (.workflow-state) が source で上書きされる"; fi

if _case_d 2>/dev/null; then _record PASS D "--delete 不使用で target 独自 file が残る"
else                         _record FAIL D "--delete 不使用で target 独自 file が残る"; fi

if _case_e 2>/dev/null; then _record PASS E "--dry-run はプレビューのみ (実書込なし)"
else                         _record FAIL E "--dry-run はプレビューのみ (実書込なし)"; fi

if _case_f 2>/dev/null; then _record PASS F "--update --overwrite-all 排他 error"
else                         _record FAIL F "--update --overwrite-all 排他 error"; fi

if _case_g 2>/dev/null; then _record PASS G "--force --overwrite-all 排他 error"
else                         _record FAIL G "--force --overwrite-all 排他 error"; fi

if _case_h 2>/dev/null; then _record PASS H "既存 .claude/ 不在で error"
else                         _record FAIL H "既存 .claude/ 不在で error"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
    printf 'FAILED cases:%s\n' "$FAILED_CASES"
    exit 1
fi
exit 0
