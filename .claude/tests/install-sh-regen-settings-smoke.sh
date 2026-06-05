#!/usr/bin/env bash
# install-sh-regen-settings-smoke.sh — task-80 (install.sh settings.json 自動再生成)
#
# 目的:
#   install.sh の sync mode (--update / --force / --overwrite-all) が rsync 後に
#   generate-settings.sh で settings.json を自動再生成し:
#     - statusLine block が入る (dispatcher / statusLine 配線同期)
#     - 既存 permissions が verbatim 保持される (再生成前後で不変)
#     - 既存 settings.json 不在なら再生成 skip (settings.json を作らない / die しない)
#     - --dry-run では再生成しない
#   を満たすこと、および .claude/.gitignore に 6 state dir entry が含まれることを検証する。
#
# 採用案: B (rsync 後に settings.json を default 自動再生成)
#   SSoT: docs/draft/install-auto-regen-settings.md §3
#
# Case 一覧:
#   A: --update (既存 settings.json + permissions あり) → settings.json に .statusLine block が入る
#   B: 既存 permissions が再生成前後で不変 (verbatim 保持)
#   C: 既存 settings.json 不在なら再生成 skip (settings.json が作られない / die しない)
#   D: --dry-run --update では再生成しない (settings.json 不変)
#   E: 再生成済の echo メッセージが stdout に出る (動作痕跡)
#   F: .claude/.gitignore に 6 state dir entry が含まれる
#   G: --force でも再生成ガードが発火し fail-open で skip (die しない / 完走)。
#      注: --force は rm -rf .claude で破壊的リセット + settings.json を rsync exclude するため、
#      force 後の target に settings.json は無い → update と異なり permissions 保持の前提が
#      成立せず「既存不在 → skip」path を取る (= Case C の force 版)。
#
# overwrite-all の再生成 path について (accepted-risk、draft §6 DoD):
#   overwrite-all mode では settings.json が source で上書き済になるため、保持される
#   permissions は source 由来 (consuming repo permissions は失われる = task-79 既定) で
#   update とは別挙動。permissions 保持の再生成 path は update で担保し、
#   overwrite-all path は smoke 複雑化を避けて accepted-risk とする。
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - 各 case は per-case tmp dir で順序依存を排除
#   - target は /tmp 配下で cross-repo sandbox 制約の対象外 (smoke 専用)
#   - bash 3.2 互換 (連想配列 / mapfile 不使用)
#
# 前提:
#   - jq 必須 (generate-settings.sh が依存)。jq 不在環境では本 smoke を skip exit 0。
#
# 実行:
#   bash .claude/tests/install-sh-regen-settings-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS (または jq 不在 skip) / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
GITIGNORE="${REPO_ROOT}/.claude/.gitignore"

if [ ! -f "$INSTALL_SH" ]; then
    printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    printf 'ERROR: rsync not found (required by install.sh)\n' >&2
    exit 1
fi

# jq は generate-settings.sh の必須依存。不在なら自動再生成 case (A,B,D,E) は検証不能なので
# smoke を skip exit 0 する (jq 不在は install 側で WARN + skip = 別途 fail-open で担保済)。
if ! command -v jq >/dev/null 2>&1; then
    printf '\n=== install-sh-regen-settings-smoke ===\n\n'
    printf '  SKIP  jq not found — generate-settings.sh cannot run; skipping regen cases\n'
    printf '\n--- Result: SKIPPED (jq absent) ---\n'
    exit 0
fi

# 全 case 共通の root を 1 つだけ確保し、per-case subdir をその下に切る。
# trap で EXIT (正常終了 / FAIL) に加え INT TERM (Ctrl-C / kill) でも必ず削除し、
# /tmp に残骸が溜まらないようにする。
# 注: trap action は単純な rm のみで set -e / pipefail を caller に leak させない
# (file-top strict mode 不使用方針を踏襲、CLAUDE.md HIGH 教訓)。
TMP_BASE="$(mktemp -d /tmp/install-sh-regen-settings-smoke.XXXXXX)"
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

# ---- fixture builder ----
#
# Build a target dir with a baseline .claude/ install, then plant a settings.json
# with a distinctive permissions marker. install は settings.json を rsync exclude
# するため、fresh install の target には settings.json が無い → 自動再生成の「既存
# settings.json あり」前提を満たすために手動で配置する。
#
# 配置する settings.json:
#   - $schema + permissions (allow に "Bash(echo:*)" marker) + 空 hooks
#   - statusLine は **入れない** (再生成で追加されることを Case A で検証するため)
# 戻り: $TGT を caller で参照
_build_target_with_settings() {
    local case_id="$1"
    TGT="${TMP_BASE}/tgt-${case_id}-$$"
    mkdir -p "$TGT"
    (
        set -uo pipefail
        cd "$TGT" || exit 1
        # 初回 install (新規、git/mcp/docs 不要)
        bash "$INSTALL_SH" "$TGT" --no-mcp --no-docs >/dev/null 2>&1 || exit 1
        # 既存 settings.json を配置 (permissions marker 入り、statusLine なし)
        cat > .claude/settings.json <<'SETTINGS_EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": ["Bash(echo:*)", "Bash(REGEN_MARKER_KEEPME:*)"],
    "deny": []
  },
  "hooks": {}
}
SETTINGS_EOF
    ) || return 1
    return 0
}

# Build a target WITHOUT a settings.json (fresh install state = settings.json excluded)
_build_target_no_settings() {
    local case_id="$1"
    TGT="${TMP_BASE}/tgt-${case_id}-$$"
    mkdir -p "$TGT"
    (
        set -uo pipefail
        cd "$TGT" || exit 1
        bash "$INSTALL_SH" "$TGT" --no-mcp --no-docs >/dev/null 2>&1 || exit 1
        # fresh install は settings.json を配布しない (rsync exclude)。念のため除去。
        rm -f .claude/settings.json
    ) || return 1
    return 0
}

# ============================================================
# Case A: --update で既存 settings.json が再生成され .statusLine block が入る
# ============================================================
_case_a() (
    set -uo pipefail
    _build_target_with_settings a || return 1
    # 再生成前: statusLine は無い
    if jq -e '.statusLine' "$TGT/.claude/settings.json" >/dev/null 2>&1; then
        return 1   # 前提崩壊 (fixture が statusLine を持ってしまっている)
    fi
    bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs >/dev/null 2>&1 || return 1
    # 再生成後: statusLine block が存在し command に statusline.sh を含む
    jq -e '.statusLine.command | test("statusline\\.sh")' "$TGT/.claude/settings.json" >/dev/null 2>&1
)

# ============================================================
# Case B: 既存 permissions が再生成前後で不変 (verbatim 保持)
# ============================================================
_case_b() (
    set -uo pipefail
    _build_target_with_settings b || return 1
    local before after
    before="$(jq -cS '.permissions' "$TGT/.claude/settings.json")"
    bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs >/dev/null 2>&1 || return 1
    after="$(jq -cS '.permissions' "$TGT/.claude/settings.json")"
    # permissions が完全一致 (verbatim transcribe)
    [ "$before" = "$after" ] || return 1
    # marker が残っていること (二重確認)
    jq -e '.permissions.allow | index("Bash(REGEN_MARKER_KEEPME:*)")' "$TGT/.claude/settings.json" >/dev/null 2>&1
)

# ============================================================
# Case C: 既存 settings.json 不在なら再生成 skip (作られない / die しない)
# ============================================================
_case_c() (
    set -uo pipefail
    _build_target_no_settings c || return 1
    local out ec
    out="$(bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs 2>&1)"
    ec=$?
    # install は完走 (exit 0、die しない)
    [ "$ec" -eq 0 ] || return 1
    # settings.json は作られていない (skip)
    [ ! -f "$TGT/.claude/settings.json" ] || return 1
    # skip の NOTE メッセージが出ている
    printf '%s\n' "$out" | grep -qi 'settings.json 不在\|自動再生成 skip\|permissions 喪失回避'
)

# ============================================================
# Case D: --dry-run --update では再生成しない (settings.json 不変)
# ============================================================
_case_d() (
    set -uo pipefail
    _build_target_with_settings d || return 1
    local before after
    before="$(jq -cS '.' "$TGT/.claude/settings.json")"
    bash "$INSTALL_SH" "$TGT" --update --dry-run --no-mcp --no-docs >/dev/null 2>&1 || return 1
    after="$(jq -cS '.' "$TGT/.claude/settings.json")"
    # dry-run なので settings.json は完全に不変 (statusLine も追加されない)
    [ "$before" = "$after" ] || return 1
    # statusLine が依然として存在しない (再生成されていない確証)
    if jq -e '.statusLine' "$TGT/.claude/settings.json" >/dev/null 2>&1; then
        return 1
    fi
    return 0
)

# ============================================================
# Case E: 再生成済の echo メッセージが stdout に出る (動作痕跡)
# ============================================================
_case_e() (
    set -uo pipefail
    _build_target_with_settings e || return 1
    local out
    out="$(bash "$INSTALL_SH" "$TGT" --update --no-mcp --no-docs 2>&1)" || return 1
    printf '%s\n' "$out" | grep -qi 'settings.json 再生成済\|配線同期'
)

# ============================================================
# Case F: .claude/.gitignore に 6 state dir entry が含まれる
# ============================================================
_case_f() (
    set -uo pipefail
    [ -f "$GITIGNORE" ] || return 1
    local e
    for e in '.preset-history/' '.reviewer-count-state/' '.context-budget-state/' \
             '.workflow-state/' '.task-screenshots/' '.session-help-shown'; do
        grep -qxF "$e" "$GITIGNORE" || return 1
    done
    return 0
)

# ============================================================
# Case G: --force でも再生成ガードが発火し fail-open で skip (die しない / 完走)
# ============================================================
# 重要: --force は rm -rf "$TARGET/.claude" で .claude を破壊的リセットしてから rsync する。
# settings.json は rsync exclude のため、force 後の target には settings.json が存在しない
# → 再生成ガードは「既存 settings.json 不在 → skip」path を取る (update と異なり permissions
# 保持の前提自体が成立しない = force は from-scratch reset)。
# よって force で検証する behavior-preserving な invariant は「ガードが発火し fail-open で
# skip、settings.json を作らず die もせず install が完走する」こと (Case C の force 版)。
# overwrite-all path は smoke 複雑化を避け accepted-risk (header doc / draft §6 DoD 参照)。
_case_g() (
    set -uo pipefail
    # fixture で settings.json を置いても force が rm -rf で消すため、no-settings fixture で十分
    _build_target_no_settings g || return 1
    local out ec
    out="$(bash "$INSTALL_SH" "$TGT" --force --no-mcp --no-docs 2>&1)"
    ec=$?
    # install は完走 (exit 0、die しない)
    [ "$ec" -eq 0 ] || return 1
    # force は settings.json を rsync exclude するため再生成後も settings.json は不在 (skip)
    [ ! -f "$TGT/.claude/settings.json" ] || return 1
    # skip の NOTE メッセージが出ている (再生成ガードが force でも発火した証跡)
    printf '%s\n' "$out" | grep -qi 'settings.json 不在\|自動再生成 skip\|permissions 喪失回避'
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-sh-regen-settings-smoke ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "--update で settings.json に .statusLine が入る"
else                         _record FAIL A "--update で settings.json に .statusLine が入る"; fi

if _case_b 2>/dev/null; then _record PASS B "既存 permissions が再生成前後で不変"
else                         _record FAIL B "既存 permissions が再生成前後で不変"; fi

if _case_c 2>/dev/null; then _record PASS C "settings.json 不在なら再生成 skip (die しない)"
else                         _record FAIL C "settings.json 不在なら再生成 skip (die しない)"; fi

if _case_d 2>/dev/null; then _record PASS D "--dry-run --update では再生成しない"
else                         _record FAIL D "--dry-run --update では再生成しない"; fi

if _case_e 2>/dev/null; then _record PASS E "再生成済メッセージが stdout に出る"
else                         _record FAIL E "再生成済メッセージが stdout に出る"; fi

if _case_f 2>/dev/null; then _record PASS F ".claude/.gitignore に 6 state dir entry"
else                         _record FAIL F ".claude/.gitignore に 6 state dir entry"; fi

if _case_g 2>/dev/null; then _record PASS G "--force でも再生成ガード発火 + fail-open skip (die しない)"
else                         _record FAIL G "--force でも再生成ガード発火 + fail-open skip (die しない)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
    printf 'FAILED cases:%s\n' "$FAILED_CASES"
    exit 1
fi
exit 0
