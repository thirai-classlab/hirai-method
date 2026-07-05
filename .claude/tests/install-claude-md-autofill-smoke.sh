#!/usr/bin/env bash
# .claude/tests/install-claude-md-autofill-smoke.sh — task-89 Step 4 (CLAUDE.md auto-fill)
#
# 目的:
#   install.sh §2 CLAUDE.md auto-fill (task-89、Step 2 実装) を検証する。
#   6 言語 (ts/py/go/rust/php/swift) + generic の manifest 検出、複数 manifest 優先順、
#   --lang override、既存 CLAUDE.md 不可侵 (default/update)、HINT 有無、--dry-run 非生成、
#   template 群不在 fallback、force mode 上書き の 14 case (>= 12) を担保する。
#
#   設計 SSoT: docs/draft/claude-md-auto-fill.md §3.1/3.2/3.3 + DoD §6。
#   Step 2 report の caveat (テンプレ line 4 の `<!-- TODO(auto-fill): ... -->` 由来の
#   1 hit) を回避するため、fillable placeholder 検出 pattern を `<[^!]` に refine する
#   (HTML comment `<!` を除外、Step 2 report 「(b) 対処案」)。
#
# Case 一覧:
#   A: package.json のみ → lang=ts + placeholder 0 + CommonRules 参照 + auto-fill 実質
#      (manifest 由来 name / npm run <script> が埋まる)
#   B: pyproject.toml のみ → lang=py + fastapi framework + pytest
#   C: go.mod のみ → lang=go + module full path + go build
#   D: Cargo.toml のみ → lang=rust + cargo build
#   E: composer.json のみ → lang=php + composer install
#   F: Package.swift のみ → lang=swift + swift build
#   G: 複数 manifest (package.json + go.mod) → first-win=ts (draft §3.1 priority)
#   H: --lang=go override (package.json あり) → go 検出 (manifest 無視)
#   I: 既存 CLAUDE.md あり (CommonRules 参照あり) → md5 一致 + .bak 非生成 + HINT 非出力
#   J: 既存 CLAUDE.md あり (CommonRules 参照なし) → md5 一致 + HINT 出力
#   K: --dry-run → CLAUDE.md 非生成 + [dry-run] echo
#   L: template 群不在 (ts template 意図的削除) → fallback CLAUDE.md.template + WARN
#   M: update mode で既存 CLAUDE.md 存在 → 「触らない」echo + md5 前後一致
#   N: --force で既存 CLAUDE.md → auto-fill 生成物で上書き (md5 変化 + manifest 由来 name)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - set -e は subshell 関数化 ( set -uo pipefail; ... ) でのみ使用
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下の target に対して行い、repo 本体を汚さない
#   - Case L の fake_src 経路は SCRIPT_DIR を切り替える唯一の手段 (source 側 templates を
#     touch せずに render 失敗を再現するため、rsync -a で 21MB 複製)。
#
# 実行:
#   bash .claude/tests/install-claude-md-autofill-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
TEMPLATE_SRC="${REPO_ROOT}/.claude/templates"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh + Case L fake_src 前提依存)\n' >&2
  exit 1
fi
# 前提: Step 1 で配布された 7 言語 template が存在する (欠落なら Step 1 未完 or drift)
for lang in ts py go rust php swift generic; do
  if [ ! -f "${TEMPLATE_SRC}/CLAUDE.md.example.${lang}.md" ]; then
    printf 'ERROR: template missing: %s/CLAUDE.md.example.%s.md (task-89 Step 1 未完)\n' \
      "$TEMPLATE_SRC" "$lang" >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d "/tmp/install-claude-md-autofill-smoke.XXXXXX")"
# trap は INT/TERM でも実行 (Ctrl-C / kill での TMP 残存を防ぐ、既存 smoke 前例踏襲)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

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

# md5 portable helper: Linux (md5sum) / macOS (md5 -q) 両対応。
# 単一列 hash を stdout に出力 (path は含めない)、失敗時は空文字列。
_md5() {
  local f="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$f" 2>/dev/null
  else
    printf ''
  fi
}

# auto-fill 生成物の共通 assert:
#   (1) CLAUDE.md 生成 (2) placeholder 0 (refined pattern) (3) CommonRules 参照
#   (4) lang echo (draft §3 SSoT 「lang=<id> (manifest 検出)」or 「(--lang override)」)
# $1: target dir / $2: expected lang / $3: install stdout log path
_assert_autofill_generated() {
  local tgt="$1" expected_lang="$2" log="$3"
  # 1. CLAUDE.md 生成
  [ -f "$tgt/CLAUDE.md" ] || return 1
  # 2. placeholder 0 (Step 2 report caveat: HTML comment `<!` を [^!] で除外、
  #    fillable placeholder = `<name>` / `<URL>` 等のみ検出)
  local ph_cnt
  ph_cnt=$(grep -cE '`<[^!]' "$tgt/CLAUDE.md" 2>/dev/null | head -1)
  [ "${ph_cnt:-1}" -eq 0 ] || return 1
  # 3. @.claude/CommonRules.md 参照 (draft §3.2 全 template 冒頭固定)
  grep -q '@.claude/CommonRules.md' "$tgt/CLAUDE.md" 2>/dev/null || return 1
  # 4. lang echo (install.sh §2 の DETECTED_LANG 出力)
  grep -qE "CLAUDE.md auto-fill: lang=${expected_lang}\\b" "$log" 2>/dev/null || return 1
  return 0
}

# ============================================================
# Case A: package.json のみ → ts 検出 + auto-fill 実質
# ============================================================
_case_a() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-a"
  mkdir -p "$tgt"
  printf '%s\n' '{"name":"dummy-ts","scripts":{"test":"jest","build":"tsc"}}' > "$tgt/package.json"
  local log="${TMP_DIR}/case-a.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "ts" "$log" || return 1
  # PROJECT_NAME 実装的に埋まる (draft §3.1 name 抽出)
  grep -q 'dummy-ts' "$tgt/CLAUDE.md" || return 1
  # scripts.{test,build} → npm run <key> (draft §3.1 ts commands)
  grep -q 'npm run test' "$tgt/CLAUDE.md" || return 1
  grep -q 'npm run build' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case B: pyproject.toml のみ → py 検出 + fastapi + pytest
# ============================================================
_case_b() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-b"
  mkdir -p "$tgt"
  cat > "$tgt/pyproject.toml" <<'EOF'
[project]
name = "dummy-py"
requires-python = ">=3.12"
dependencies = ["fastapi>=0.100"]
EOF
  local log="${TMP_DIR}/case-b.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "py" "$log" || return 1
  grep -q 'dummy-py' "$tgt/CLAUDE.md" || return 1
  grep -qi 'fastapi' "$tgt/CLAUDE.md" || return 1
  grep -q 'pytest' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case C: go.mod のみ → go 検出 + module full path + go build
# ============================================================
_case_c() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-c"
  mkdir -p "$tgt"
  cat > "$tgt/go.mod" <<'EOF'
module github.com/foo/dummy-go

go 1.22
EOF
  local log="${TMP_DIR}/case-c.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "go" "$log" || return 1
  grep -q 'github.com/foo/dummy-go' "$tgt/CLAUDE.md" || return 1
  grep -q 'go build ./\.\.\.' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case D: Cargo.toml のみ → rust 検出 + cargo build
# ============================================================
_case_d() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-d"
  mkdir -p "$tgt"
  cat > "$tgt/Cargo.toml" <<'EOF'
[package]
name = "dummy-rust"
version = "0.1.0"
edition = "2021"
EOF
  local log="${TMP_DIR}/case-d.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "rust" "$log" || return 1
  grep -q 'dummy-rust' "$tgt/CLAUDE.md" || return 1
  grep -q 'cargo build' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case E: composer.json のみ → php 検出 + composer install
# ============================================================
_case_e() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-e"
  mkdir -p "$tgt"
  cat > "$tgt/composer.json" <<'EOF'
{
  "name": "vendor/dummy-php",
  "require": {
    "php": "^8.2"
  }
}
EOF
  local log="${TMP_DIR}/case-e.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "php" "$log" || return 1
  grep -q 'vendor/dummy-php' "$tgt/CLAUDE.md" || return 1
  grep -q 'composer install' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case F: Package.swift のみ → swift 検出 + swift build
# ============================================================
_case_f() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-f"
  mkdir -p "$tgt"
  cat > "$tgt/Package.swift" <<'EOF'
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "dummy-swift",
    products: []
)
EOF
  local log="${TMP_DIR}/case-f.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "swift" "$log" || return 1
  grep -q 'dummy-swift' "$tgt/CLAUDE.md" || return 1
  grep -q 'swift build' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case G: 複数 manifest (package.json + go.mod) → first-win=ts
#         draft §3.1 priority table row 1 (ts) > row 3 (go)
# ============================================================
_case_g() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-g"
  mkdir -p "$tgt"
  printf '%s\n' '{"name":"dummy-multi","scripts":{"dev":"vite"}}' > "$tgt/package.json"
  cat > "$tgt/go.mod" <<'EOF'
module dummy-go-ignored

go 1.22
EOF
  local log="${TMP_DIR}/case-g.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  # ts が first-win で選択される
  _assert_autofill_generated "$tgt" "ts" "$log" || return 1
  grep -q 'dummy-multi' "$tgt/CLAUDE.md" || return 1
  # go 側は無視される (module 行の値が CLAUDE.md に混入しない)
  ! grep -q 'dummy-go-ignored' "$tgt/CLAUDE.md" || return 1
  # log にも lang=go の echo は発生しない
  ! grep -qE 'auto-fill: lang=go\b' "$log" || return 1
)

# ============================================================
# Case H: --lang=go override + package.json AND go.mod 共存 → go 検出
#         install.sh L109-119 arg parse + detect_project_lang() LANG_OVERRIDE 分岐
#         正常時 (package.json が優先) の first-win を強制で bypass することを検証。
#         package.json だけだと extract_manifest_fields.go は go.mod を読まず空 commands
#         を生成する (branch spec = manifest 由来 field は go.mod にのみ依存) ため、
#         override の意味を担保するため go.mod も併置し、そちらが読まれることを assert。
# ============================================================
_case_h() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-h"
  mkdir -p "$tgt"
  # package.json (first-win 優先候補) + go.mod (--lang=go で選択される候補) 共存
  printf '%s\n' '{"name":"ts-should-be-ignored"}' > "$tgt/package.json"
  cat > "$tgt/go.mod" <<'EOF'
module example.com/dummy-h

go 1.22
EOF
  local log="${TMP_DIR}/case-h.log"
  bash "$INSTALL_SH" "$tgt" --lang=go --no-mcp --no-docs >"$log" 2>&1 || return 1
  # override 経路: "lang=go (--lang override)" の echo (install.sh:645-649)
  grep -qE 'auto-fill: lang=go .*--lang override' "$log" || return 1
  # go template が使われる: "go build ./..." が含まれる (draft §3.1 go commands 固定)
  grep -q 'go build ./\.\.\.' "$tgt/CLAUDE.md" || return 1
  # go.mod 由来の module full path が入る (manifest 抽出は --lang 指定側で動作)
  grep -q 'example.com/dummy-h' "$tgt/CLAUDE.md" || return 1
  # placeholder 0 は変わらず保証
  local ph_cnt
  ph_cnt=$(grep -cE '`<[^!]' "$tgt/CLAUDE.md" 2>/dev/null | head -1)
  [ "${ph_cnt:-1}" -eq 0 ] || return 1
  # ts 側 manifest の name は混入しない (package.json は無視される)
  ! grep -q 'ts-should-be-ignored' "$tgt/CLAUDE.md" || return 1
  # ts detected の echo も出ない (override により detect_project_lang skip)
  ! grep -qE 'auto-fill: lang=ts\b' "$log" || return 1
)

# ============================================================
# Case I: 既存 CLAUDE.md あり (CommonRules 参照あり) → 不可侵 + HINT 非出力
#         draft §3.3 default mode + existing 「不可侵、.bak 退避廃止」
# ============================================================
_case_i() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-i"
  mkdir -p "$tgt"
  cat > "$tgt/CLAUDE.md" <<'EOF'
# Existing project CLAUDE.md (CommonRules 参照あり)

@.claude/CommonRules.md

## Overview

Some project-specific docs that must not be touched by install.
EOF
  local before
  before=$(_md5 "$tgt/CLAUDE.md")
  [ -n "$before" ] || return 1
  local log="${TMP_DIR}/case-i.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  local after
  after=$(_md5 "$tgt/CLAUDE.md")
  # md5 前後一致 (完全不可侵)
  [ "$before" = "$after" ] || return 1
  # HINT 非出力 (CommonRules 参照ありなので HINT 条件不成立)
  ! grep -q 'HINT:.*@.claude/CommonRules.md' "$log" || return 1
  # .bak 非生成 (subscbase-api 再発防止、draft §3.3 「.bak 退避廃止」)
  [ -z "$(find "$tgt" -maxdepth 1 -name 'CLAUDE.md.bak*' 2>/dev/null)" ] || return 1
)

# ============================================================
# Case J: 既存 CLAUDE.md あり (CommonRules 参照なし) → 不可侵 + HINT 出力
# ============================================================
_case_j() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-j"
  mkdir -p "$tgt"
  cat > "$tgt/CLAUDE.md" <<'EOF'
# Legacy project CLAUDE.md (no CommonRules import)

Some notes without harness reference.
EOF
  local before
  before=$(_md5 "$tgt/CLAUDE.md")
  [ -n "$before" ] || return 1
  local log="${TMP_DIR}/case-j.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  local after
  after=$(_md5 "$tgt/CLAUDE.md")
  # md5 前後一致 (完全不可侵、HINT でも自動編集しない)
  [ "$before" = "$after" ] || return 1
  # HINT 出力 (CommonRules 参照なしなので条件成立、install.sh:669-671)
  grep -q 'HINT:.*@.claude/CommonRules.md' "$log" || return 1
)

# ============================================================
# Case K: --dry-run → CLAUDE.md 非生成 + [dry-run] echo
#         draft §3.3 dry-run 契約 (run() helper 同型、file write 0)
# ============================================================
_case_k() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-k"
  mkdir -p "$tgt"
  printf '%s\n' '{"name":"dummy-dry"}' > "$tgt/package.json"
  local log="${TMP_DIR}/case-k.log"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-mcp --no-docs >"$log" 2>&1 || return 1
  # CLAUDE.md 非生成 (dry-run 契約)
  [ ! -f "$tgt/CLAUDE.md" ] || return 1
  # [dry-run] generate CLAUDE.md echo (install.sh:675-676)
  grep -qE '\[dry-run\] generate CLAUDE.md.*lang=ts' "$log" || return 1
)

# ============================================================
# Case L: template 群不在 → fallback CLAUDE.md.template + WARN
#         install.sh render_claude_md() は template 不在で return 1 → 呼び出し側で
#         fallback (`cp SCRIPT_DIR/CLAUDE.md → TARGET/CLAUDE.md.template`) + WARN 出力
#
#         source 側 template を touch せずに render 失敗を再現するため、install.sh + .claude/
#         + CLAUDE.md を fake_src へ rsync 複製し、fake_src の ts template のみ削除する。
#         21MB 複製は 1 回のみ (case L 単独)、CI 想定でも許容範囲。
# ============================================================
_case_l() (
  set -uo pipefail
  local fake_src="${TMP_DIR}/fake-src-l"
  mkdir -p "$fake_src"
  cp "$INSTALL_SH" "$fake_src/install.sh" || return 1
  rsync -a "${REPO_ROOT}/.claude/" "$fake_src/.claude/" >/dev/null 2>&1 || return 1
  # fallback で使う source CLAUDE.md も複製 (install.sh:663 の cp 元)
  cp "${REPO_ROOT}/CLAUDE.md" "$fake_src/CLAUDE.md" || return 1
  # install.sh の他の step (§4 .gitignore §3 .mcp.json 等) は source 参照を持つため
  # 存在するものは複製しておく (絶対必要なのは .gitignore、install.sh:738 で `run cp
  # $SCRIPT_DIR/.gitignore ...` が set -e 下で cp fail 時 install 全体を die させる)。
  # .mcp.json は --no-mcp で skip されるので不要。
  [ -f "${REPO_ROOT}/.gitignore" ] && cp "${REPO_ROOT}/.gitignore" "$fake_src/.gitignore"
  # ts template を意図的に削除 → render_claude_md 内 `[[ -f "$tmpl" ]] || return 1` fail
  rm -f "$fake_src/.claude/templates/CLAUDE.md.example.ts.md" || return 1
  local tgt="${TMP_DIR}/target-l"
  mkdir -p "$tgt"
  printf '%s\n' '{"name":"dummy-fallback"}' > "$tgt/package.json"
  local log="${TMP_DIR}/case-l.log"
  bash "$fake_src/install.sh" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  # fallback file 生成 (install.sh:681-683 の cp 経路)
  [ -f "$tgt/CLAUDE.md.template" ] || return 1
  # WARN 出力 (install.sh:681 の stderr echo — stdout+stderr 統合 log 内で grep 可能)
  grep -q 'auto-fill 失敗.*fallback' "$log" || return 1
  # 正常 auto-fill パスは通らないので CLAUDE.md は生成されない (existing CLAUDE.md 保護
  # branch でもない: 既存 CLAUDE.md 不在 → 674-685 の生成 branch → render 失敗 → 683 cp
  # のみで CLAUDE.md 本体は書かない設計)
  [ ! -f "$tgt/CLAUDE.md" ] || return 1
)

# ============================================================
# Case M: update mode + 既存 CLAUDE.md → 「触らない」echo + md5 前後一致
#         draft §3.3 update mode: 「生成しない (現行維持) + 既存あれば check/HINT のみ」
# ============================================================
_case_m() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-m"
  mkdir -p "$tgt"
  # まず default install で .claude/ + CLAUDE.md を下地作成 (package.json あり)
  printf '%s\n' '{"name":"dummy-m","scripts":{"test":"jest"}}' > "$tgt/package.json"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >/dev/null 2>&1 || return 1
  [ -f "$tgt/CLAUDE.md" ] || return 1
  local before
  before=$(_md5 "$tgt/CLAUDE.md")
  [ -n "$before" ] || return 1
  # update mode 実行
  local log="${TMP_DIR}/case-m.log"
  bash "$INSTALL_SH" "$tgt" --update --no-mcp --no-docs >"$log" 2>&1 || return 1
  local after
  after=$(_md5 "$tgt/CLAUDE.md")
  # md5 前後一致 (update mode は CLAUDE.md 不可侵、draft §3.3)
  [ "$before" = "$after" ] || return 1
  # update mode 分岐の echo (install.sh:638「(update mode) CLAUDE.md は触らない」)
  grep -q 'update mode.*CLAUDE.md は触らない' "$log" || return 1
  # auto-fill 側の echo は出ない
  ! grep -qE 'CLAUDE.md auto-fill: lang=' "$log" || return 1
)

# ============================================================
# Case N: --force で既存 CLAUDE.md → auto-fill 生成物で上書き
#         draft §3.3 force mode: 「auto-fill 生成物で上書き (backup なし)」
# ============================================================
_case_n() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-n"
  mkdir -p "$tgt"
  # 既存 CLAUDE.md を配置 (--force で上書き対象)
  cat > "$tgt/CLAUDE.md" <<'EOF'
# Old CLAUDE.md that will be overwritten by --force
UNIQUE_SENTINEL_OLD_CONTENT_TO_BE_REPLACED
EOF
  # manifest 配置 → ts 検出 + name が auto-fill される
  printf '%s\n' '{"name":"dummy-forced-new","scripts":{"test":"jest"}}' > "$tgt/package.json"
  local before
  before=$(_md5 "$tgt/CLAUDE.md")
  [ -n "$before" ] || return 1
  local log="${TMP_DIR}/case-n.log"
  bash "$INSTALL_SH" "$tgt" --force --no-mcp --no-docs >"$log" 2>&1 || return 1
  local after
  after=$(_md5 "$tgt/CLAUDE.md")
  # 上書きされる → md5 変化
  [ "$before" != "$after" ] || return 1
  # 旧 sentinel が消える + 新 name が入る
  ! grep -q 'UNIQUE_SENTINEL_OLD_CONTENT_TO_BE_REPLACED' "$tgt/CLAUDE.md" || return 1
  grep -q 'dummy-forced-new' "$tgt/CLAUDE.md" || return 1
  # CommonRules 参照 (auto-fill 生成物、draft §3.2)
  grep -q '@.claude/CommonRules.md' "$tgt/CLAUDE.md" || return 1
  # placeholder 0 (auto-fill 品質保証)
  local ph_cnt
  ph_cnt=$(grep -cE '`<[^!]' "$tgt/CLAUDE.md" 2>/dev/null | head -1)
  [ "${ph_cnt:-1}" -eq 0 ] || return 1
  # 再生成 echo (install.sh:660)
  grep -q 'CLAUDE.md 再生成' "$log" || return 1
)

# ============================================================
# Case O: framework 検出 false positive 回避 (JSON key literal 一致に絞る)
#         package.json に `react-router-dom` / `vite-plugin-express` のみ (react / express
#         直接依存なし) の場合、Framework 行は空 (`- **Language / Framework**: TypeScript`)。
#         旧実装 (grep -qw) は `-` を非 word 扱いで react-router-dom を react 誤検知していた
#         (2026-07-05 finding 2)。新実装 (jq has() / grep `"key":`) では drop される。
# ============================================================
_case_o() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-o"
  mkdir -p "$tgt"
  cat > "$tgt/package.json" <<'EOF'
{
  "name": "case-o-monorepo",
  "description": "Uses react-router but not react itself, also react-like patterns",
  "devDependencies": {
    "typescript": "5.0.0",
    "react-router-dom": "6.0.0",
    "vite-plugin-express": "1.0.0"
  }
}
EOF
  local log="${TMP_DIR}/case-o.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "ts" "$log" || return 1
  # Framework 行は空: 括弧 `(...)` が付かず `TypeScript` の直後は改行のみ
  # (line 23: `- **Language / Framework**: TypeScript{{FRAMEWORK_LINE}}`)
  grep -qE '^- \*\*Language / Framework\*\*: TypeScript[[:space:]]*$' "$tgt/CLAUDE.md" || return 1
  # 誤検知の証拠を否定: react / express の literal が Framework 行に混入しない
  ! grep -qE '^- \*\*Language / Framework\*\*: TypeScript \((.*(react|express).*)\)' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# Case P: py framework 検出 false positive 回避 (dep-context に絞る)
#         description 内の "fastapi" 言及や dep 以外の string は Framework 判定に載せない。
#         旧実装 (grep -qiw) は description 内 fastapi 言及も word match で誤検知していた
#         (2026-07-05 finding 2)。新実装 (dep 文脈 regex) では drop される。
# ============================================================
_case_p() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-p"
  mkdir -p "$tgt"
  cat > "$tgt/pyproject.toml" <<'EOF'
[project]
name = "case-p-cli"
description = "This project uses fastapi patterns internally but is a plain CLI (django-inspired)"
requires-python = ">=3.12"
dependencies = ["typer>=0.9", "rich>=13.0"]
EOF
  local log="${TMP_DIR}/case-p.log"
  bash "$INSTALL_SH" "$tgt" --no-mcp --no-docs >"$log" 2>&1 || return 1
  _assert_autofill_generated "$tgt" "py" "$log" || return 1
  # Framework 行は空 (fastapi / django いずれも dep 文脈で登場しない = 検出されない)
  grep -qE '^- \*\*Language / Framework\*\*: Python[[:space:]]*$' "$tgt/CLAUDE.md" || return 1
  ! grep -qE '^- \*\*Language / Framework\*\*: Python \((.*(fastapi|django|flask).*)\)' "$tgt/CLAUDE.md" || return 1
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-claude-md-autofill-smoke (task-89 Step 4) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "package.json 単体 → ts 検出 + name + npm run test/build 実質 auto-fill"
else                         _record FAIL A "package.json 単体 → ts 検出 + name + npm run test/build 実質 auto-fill"; fi

if _case_b 2>/dev/null; then _record PASS B "pyproject.toml 単体 → py 検出 + fastapi framework + pytest"
else                         _record FAIL B "pyproject.toml 単体 → py 検出 + fastapi framework + pytest"; fi

if _case_c 2>/dev/null; then _record PASS C "go.mod 単体 → go 検出 + module full path + go build"
else                         _record FAIL C "go.mod 単体 → go 検出 + module full path + go build"; fi

if _case_d 2>/dev/null; then _record PASS D "Cargo.toml 単体 → rust 検出 + cargo build"
else                         _record FAIL D "Cargo.toml 単体 → rust 検出 + cargo build"; fi

if _case_e 2>/dev/null; then _record PASS E "composer.json 単体 → php 検出 + composer install"
else                         _record FAIL E "composer.json 単体 → php 検出 + composer install"; fi

if _case_f 2>/dev/null; then _record PASS F "Package.swift 単体 → swift 検出 + swift build"
else                         _record FAIL F "Package.swift 単体 → swift 検出 + swift build"; fi

if _case_g 2>/dev/null; then _record PASS G "複数 manifest (package.json + go.mod) → first-win=ts"
else                         _record FAIL G "複数 manifest (package.json + go.mod) → first-win=ts"; fi

if _case_h 2>/dev/null; then _record PASS H "--lang=go override (package.json あり) → go 検出 + manifest 無視"
else                         _record FAIL H "--lang=go override (package.json あり) → go 検出 + manifest 無視"; fi

if _case_i 2>/dev/null; then _record PASS I "既存 CLAUDE.md あり (CommonRules 参照あり) → md5 一致 + .bak 非生成 + HINT 非出力"
else                         _record FAIL I "既存 CLAUDE.md あり (CommonRules 参照あり) → md5 一致 + .bak 非生成 + HINT 非出力"; fi

if _case_j 2>/dev/null; then _record PASS J "既存 CLAUDE.md あり (CommonRules 参照なし) → md5 一致 + HINT 出力"
else                         _record FAIL J "既存 CLAUDE.md あり (CommonRules 参照なし) → md5 一致 + HINT 出力"; fi

if _case_k 2>/dev/null; then _record PASS K "--dry-run → CLAUDE.md 非生成 + [dry-run] echo"
else                         _record FAIL K "--dry-run → CLAUDE.md 非生成 + [dry-run] echo"; fi

if _case_l 2>/dev/null; then _record PASS L "template 群不在 → fallback CLAUDE.md.template + WARN"
else                         _record FAIL L "template 群不在 → fallback CLAUDE.md.template + WARN"; fi

if _case_m 2>/dev/null; then _record PASS M "update mode + 既存 CLAUDE.md → 「触らない」echo + md5 前後一致"
else                         _record FAIL M "update mode + 既存 CLAUDE.md → 「触らない」echo + md5 前後一致"; fi

if _case_n 2>/dev/null; then _record PASS N "--force で既存 CLAUDE.md → auto-fill 生成物で上書き (md5 変化 + name 反映)"
else                         _record FAIL N "--force で既存 CLAUDE.md → auto-fill 生成物で上書き (md5 変化 + name 反映)"; fi

if _case_o 2>/dev/null; then _record PASS O "js framework 検出 false positive 回避 (react-router-dom → react 検出しない)"
else                         _record FAIL O "js framework 検出 false positive 回避 (react-router-dom → react 検出しない)"; fi

if _case_p 2>/dev/null; then _record PASS P "py framework 検出 false positive 回避 (description 内 fastapi → 検出しない)"
else                         _record FAIL P "py framework 検出 false positive 回避 (description 内 fastapi → 検出しない)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
