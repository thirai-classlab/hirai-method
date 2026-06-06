#!/usr/bin/env bash
# project-rules-protection-smoke.sh — task-82 (project-rules/ companion + @import)
#
# 目的:
#   harness 7 rule から @import される project-rules/ companion 保護機構を検証する。
#   - 7 harness rule 末尾に `@../project-rules/<name>.md` 行が存在する
#   - `.claude/project-rules/<name>.md` 7 file が存在 (header 付き)
#   - install.sh が project-rules を create-if-absent (不在 target に作成)
#   - install.sh --update が既存 (編集済) project-rules を上書きしない (drift 保持)
#   - RSYNC_EXCLUDES / RSYNC_EXCLUDES_MINIMAL に project-rules/ exclude が含まれる
#
# Case 一覧:
#   A: 7 harness rule 各々に `@../project-rules/<name>.md` 行が存在する
#   B: `.claude/project-rules/<name>.md` 7 file が存在 (header 行含む)
#   C: install (default) で不在 target に project-rules 7 file が作成される
#   D: install.sh の RSYNC_EXCLUDES と RSYNC_EXCLUDES_MINIMAL に project-rules/ exclude
#   E: --update で既存 (編集済) project-rules を上書きしない (drift 内容が保持される)
#   F: --force でも既存 project-rules を上書きしない (project 所有保護)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 共通 tmp root + trap EXIT INT TERM、実行後 /tmp 残骸ゼロ
#   - target は /tmp 配下で cross-repo sandbox 制約の対象外 (smoke 専用)
#   - bash 3.2 互換 (連想配列 / mapfile 等を使わない)
#
# 実行:    bash .claude/tests/project-rules-protection-smoke.sh
# 終了コード: 0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
RULES_DIR="${REPO_ROOT}/.claude/rules"
PROJECT_RULES_DIR="${REPO_ROOT}/.claude/project-rules"

RULE_NAMES="development-process git-workflow modes self-improvement task-management why-x5-output workflow"

if [ ! -f "$INSTALL_SH" ]; then
    printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
    exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
    printf 'ERROR: rsync not found (required by install.sh)\n' >&2
    exit 1
fi

TMP_BASE="$(mktemp -d /tmp/project-rules-protection-smoke.XXXXXX)"
trap 'rm -rf "$TMP_BASE"' EXIT INT TERM

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

# ============================================================
# Case A: 7 harness rule 各々に @../project-rules/<name>.md 行が存在
# ============================================================
_case_a() (
    set -uo pipefail
    local name
    for name in $RULE_NAMES; do
        local f="$RULES_DIR/$name.md"
        [ -f "$f" ] || return 1
        grep -qF "@../project-rules/$name.md" "$f" || return 1
    done
)

# ============================================================
# Case B: project-rules/<name>.md 7 file が存在 (header 行含む)
# ============================================================
_case_b() (
    set -uo pipefail
    local name count=0
    for name in $RULE_NAMES; do
        local f="$PROJECT_RULES_DIR/$name.md"
        [ -f "$f" ] || return 1
        # header (project 固有ルール: <name>) を含むこと
        grep -qF "# project 固有ルール: $name" "$f" || return 1
        count=$((count + 1))
    done
    [ "$count" -eq 7 ]
)

# ============================================================
# Case C: install (default) で不在 target に project-rules 7 file 作成
# ============================================================
_case_c() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-c-$$"
    mkdir -p "$tgt"
    bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
    local name count=0
    for name in $RULE_NAMES; do
        [ -f "$tgt/.claude/project-rules/$name.md" ] || return 1
        count=$((count + 1))
    done
    [ "$count" -eq 7 ]
)

# ============================================================
# Case D: install.sh の両 RSYNC_EXCLUDES に project-rules/ exclude
# ============================================================
_case_d() (
    set -uo pipefail
    # RSYNC_EXCLUDES と RSYNC_EXCLUDES_MINIMAL の両方に project-rules/ exclude 行があること。
    # block 単位で抽出して各々に含まれることを確認する。
    awk '/^RSYNC_EXCLUDES=\(/{f=1} f{print} /^\)/{if(f)exit}' "$INSTALL_SH" \
        | grep -qF -- '--exclude=project-rules/' || return 1
    awk '/^RSYNC_EXCLUDES_MINIMAL=\(/{f=1} f{print} /^\)/{if(f)exit}' "$INSTALL_SH" \
        | grep -qF -- '--exclude=project-rules/' || return 1
)

# ============================================================
# Case E: --update で既存 (編集済) project-rules を上書きしない (drift 保持)
# ============================================================
_case_e() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-e-$$"
    mkdir -p "$tgt"
    # 初回 install で project-rules 配置
    bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
    local f="$tgt/.claude/project-rules/modes.md"
    [ -f "$f" ] || return 1
    # project 固有編集 (drift) を注入
    local marker="PROJECT-OWNED-OVERRIDE-MARKER-$$"
    printf '\n%s\n' "$marker" >> "$f"
    # --update でも上書きされないこと
    bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs >/dev/null 2>&1 || return 1
    grep -qF "$marker" "$f"
)

# ============================================================
# Case F: --overwrite-all でも既存 project-rules を上書きしない
#         (drift リセット mode でも project 所有は保護。--force は rm -rf .claude する
#          破壊的 mode のため対象外 = 設計どおり。protect 保証は update / overwrite-all)
# ============================================================
_case_f() (
    set -uo pipefail
    local tgt="${TMP_BASE}/tgt-f-$$"
    mkdir -p "$tgt"
    bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
    local f="$tgt/.claude/project-rules/workflow.md"
    [ -f "$f" ] || return 1
    local marker="OVERWRITE-ALL-PROTECT-MARKER-$$"
    printf '
%s
' "$marker" >> "$f"
    # --overwrite-all は local override を SSoT へ強制リセットする最も破壊的な「上書き」mode
    # だが rm -rf はせず rsync (RSYNC_EXCLUDES_MINIMAL) のみ。project-rules/ exclude により
    # project 所有 file は保護される → marker 保持を assert。
    bash "$INSTALL_SH" "$tgt" --overwrite-all --no-mcp --no-docs >/dev/null 2>&1 || return 1
    grep -qF "$marker" "$f"
)

# ============================================================
# 実行
# ============================================================
printf '\n=== project-rules-protection-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "7 harness rule に @../project-rules/<name>.md 行"
else                         _record FAIL A "7 harness rule に @../project-rules/<name>.md 行"; fi

if _case_b 2>/dev/null; then _record PASS B "project-rules/<name>.md 7 file 存在 (header 含)"
else                         _record FAIL B "project-rules/<name>.md 7 file 存在 (header 含)"; fi

if _case_c 2>/dev/null; then _record PASS C "install で不在 target に project-rules 7 file 作成"
else                         _record FAIL C "install で不在 target に project-rules 7 file 作成"; fi

if _case_d 2>/dev/null; then _record PASS D "両 RSYNC_EXCLUDES に project-rules/ exclude"
else                         _record FAIL D "両 RSYNC_EXCLUDES に project-rules/ exclude"; fi

if _case_e 2>/dev/null; then _record PASS E "--update で既存 project-rules を上書きしない"
else                         _record FAIL E "--update で既存 project-rules を上書きしない"; fi

if _case_f 2>/dev/null; then _record PASS F "--overwrite-all でも既存 project-rules を上書きしない"
else                         _record FAIL F "--overwrite-all でも既存 project-rules を上書きしない"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
    printf 'FAILED cases:%s\n' "$FAILED_CASES"
    exit 1
fi
exit 0
