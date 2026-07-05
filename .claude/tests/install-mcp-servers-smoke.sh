#!/usr/bin/env bash
# .claude/tests/install-mcp-servers-smoke.sh — task-90 Step 3
#
# 目的:
#   install.sh §3 .mcp.json 配布の csv filter 化 (Step 1 arg parse + Step 2 §3 rewrite)
#   を検証する。draft §3 Step 3 SSoT (docs/draft/mcp-json-minimal-default.md) に準拠。
#   - default 実行時に .mcp.json が serena + context7 の minimal 2 server で配布され
#     `${VAR}` env placeholder が 0 になること (Case A、DoD 1-2)
#   - --mcp-servers=all で source verbatim (7 server) 配布 (Case B、DoD 3)
#   - --mcp-servers=<csv> で任意 server subset 配布 (Case C)
#   - source .mcp.json に無い token は exit 64 fail-fast (Case D、DoD 4)
#   - --no-mcp と --mcp-servers 併用は exit 64 (Case E、Step 1 conflict 検証)
#   - 既存 .mcp.json は verbatim 保持 (Case F、冪等 + 非破壊)
#   - --dry-run で .mcp.json 非生成 (Case G、mutation 0)
#   - run-all-smokes.sh の portability カテゴリで discover される (Case H、登録検証)
#   - docs 反映 grep (Case I、install.sh header + §8 summary)
#   - jq 不在 fallback: WARN + 全 7 server 配布 (Case J、fail-open 契約 draft §3 D4)
#
# Case 一覧 (10 件):
#   A: default (--mcp-servers 無指定) → keys = serena + context7 のみ + placeholder 0
#   B: --mcp-servers=all → keys = 全 7 server (source と一致、jq -S diff 空)
#   C: --mcp-servers=serena,context7,github → keys = 指定 3 件
#   D: --mcp-servers=serena,typo → exit 64
#   E: --no-mcp --mcp-servers=all → exit 64 (併用禁止)
#   F: 既存 .mcp.json あり → verbatim 保持 (md5 不変)
#   G: --dry-run → .mcp.json 非生成
#   H: run-all-smokes.sh の portability カテゴリで discover される (静的検査)
#   I: docs 反映 grep (install.sh header + §8 summary で "mcp-servers" 出現、静的検査)
#   J: jq 不在 fallback (PATH shim で jq を PATH から除外) → WARN + 全 7 server 配布
#
# 重要制約 (install-local-yml-smoke.sh 先例踏襲):
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   - 各 case 実装は subshell 関数化 ( set -uo pipefail; ... ) で局所化
#   - macOS bash 3.2 + Linux bash 5.x 両対応 (declare -A 禁止)
#   - 実 install は必ず mktemp -d 配下 target に対して行い、repo 本体を汚さない
#
# scope note (task-90 Step 3 subagent):
#   本 subagent の担当 file は本 smoke と run-all-smokes.sh のみ。draft §3 Step 3 SSoT は
#   Case I の docs 反映に README.md も列挙するが、README 更新は本 subagent scope 外のため
#   Case I は install.sh header + §8 summary の 2 grep に scope 限定する。README 反映は
#   follow-up (最終報告に明記)。
#
# 実行:
#   bash .claude/tests/install-mcp-servers-smoke.sh
#
# 終了コード:
#   0 = 全 case PASS / 1 = 1 件以上 FAIL

# shellcheck disable=SC2030,SC2031
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_SH="${REPO_ROOT}/install.sh"
SOURCE_MCP="${REPO_ROOT}/.mcp.json"
RUN_ALL="${SCRIPT_DIR}/run-all-smokes.sh"

if [ ! -f "$INSTALL_SH" ]; then
  printf 'ERROR: install.sh not found: %s\n' "$INSTALL_SH" >&2
  exit 1
fi
if [ ! -f "$SOURCE_MCP" ]; then
  printf 'ERROR: source .mcp.json not found: %s\n' "$SOURCE_MCP" >&2
  exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
  printf 'ERROR: rsync not found (install.sh 前提依存)\n' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  # jq 不在では Case A/B/C の keys 検証が実行不能。本 smoke 実行前提として要求する。
  # (jq 不在 fallback の検証 = Case J は shim 環境で install.sh を走らせ smoke 側の
  #  検証には jq (host) を使うため、host jq 必須)。
  printf 'ERROR: jq not found (smoke 前提依存: .mcp.json keys 検証に必要)\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/install-mcp-servers-smoke.XXXXXX")"
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

# 生成 .mcp.json の keys を sort + newline 区切りで出力
_mcp_keys() {
  local yml="$1"
  jq -r '.mcpServers | keys | sort | .[]' "$yml" 2>/dev/null
}

# ============================================================
# Case A: default install → keys = serena + context7 + placeholder 0
# DoD 1-2 の直接検証。--mcp-servers 無指定時 install.sh の
# MCP_SERVERS="serena,context7" default が効き jq filter branch へ入る。
# ============================================================
_case_a() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-a"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --no-docs >/dev/null 2>&1 || return 1
  local mcp="${tgt}/.mcp.json"
  [ -f "$mcp" ] || return 1
  # keys 完全一致 (2 件・順序 sort 独立)
  local got expected
  got="$(_mcp_keys "$mcp")"
  expected="$(printf 'context7\nserena\n')"
  [ "$got" = "$expected" ] || return 1
  # placeholder ${...} が 0 件 (DoD 2)。grep -c は match 0 で rc=1 のため || true 必須
  # (feedback_set_e_in_sourced_libs 系: subshell 内 set -e 下でも保険)
  local ph_count
  ph_count="$(grep -c '\${' "$mcp" 2>/dev/null || true)"
  [ "$ph_count" = "0" ]
)

# ============================================================
# Case B: --mcp-servers=all → source verbatim (全 7 server)
# jq -S で正規化した mcpServers|keys が source と一致するかを diff で assert
# (DoD 3、後方互換 = 従来動作の恒久保証)
# ============================================================
_case_b() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-b"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --mcp-servers=all --no-docs >/dev/null 2>&1 || return 1
  local mcp="${tgt}/.mcp.json"
  [ -f "$mcp" ] || return 1
  # keys 7 件確認 (source と完全一致、順序独立)
  local got expected
  got="$(_mcp_keys "$mcp")"
  expected="$(_mcp_keys "$SOURCE_MCP")"
  [ "$got" = "$expected" ] || return 1
  # 追加 safety: keys 数が 7 (source と同数、拡張耐性)
  local n
  n="$(printf '%s\n' "$got" | grep -c .)"
  [ "$n" -eq 7 ]
)

# ============================================================
# Case C: --mcp-servers=serena,context7,github → keys = 指定 3 件
# subset 選択の代表 case (env 前提あり = github、env 不要 = serena/context7 混在)
# ============================================================
_case_c() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-c"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --mcp-servers=serena,context7,github --no-docs >/dev/null 2>&1 || return 1
  local mcp="${tgt}/.mcp.json"
  [ -f "$mcp" ] || return 1
  local got expected
  got="$(_mcp_keys "$mcp")"
  expected="$(printf 'context7\ngithub\nserena\n')"
  [ "$got" = "$expected" ] || return 1
  # github の Authorization ヘッダが source verbatim で保持されているか (subset 選択で
  # server の内容 (env / args) が損なわれないことを 1 point で確認)
  local auth
  auth="$(jq -r '.mcpServers.github.headers.Authorization' "$mcp" 2>/dev/null || true)"
  [ "$auth" = 'Bearer ${GITHUB_PAT}' ]
)

# ============================================================
# Case D: --mcp-servers=serena,typo → exit 64 (fail-fast typo 検出)
# Step 2 の jq set-diff による key 実在検証 (draft §3 D5) の直接検証。
# stderr に error + 'available' 一覧 が出るかも合わせて assert (診断支援)。
# ============================================================
_case_d() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-d"
  mkdir -p "$tgt"
  local errlog="${TMP_DIR}/case-d-stderr.log"
  local rc=0
  bash "$INSTALL_SH" "$tgt" --mcp-servers=serena,typo --no-docs >/dev/null 2>"$errlog" || rc=$?
  [ "$rc" -eq 64 ] || return 1
  # error message に typo token と available 一覧が含まれる (Step 2 実装、診断支援)
  grep -q "typo" "$errlog" || return 1
  grep -q "存在しません" "$errlog" || return 1
  # target に .mcp.json が生成されていない (fail-fast = 副作用 0)
  [ ! -f "${tgt}/.mcp.json" ]
)

# ============================================================
# Case E: --no-mcp --mcp-servers=all → exit 64 (Step 1 conflict 検証)
# 全 skip と選択配布は矛盾するため fail-fast (--commit + non-update と同 pattern)
# ============================================================
_case_e() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-e"
  mkdir -p "$tgt"
  local rc=0
  bash "$INSTALL_SH" "$tgt" --no-mcp --mcp-servers=all --no-docs >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 64 ] || return 1
  # target に .mcp.json 非生成 (arg parse 直後 die)
  [ ! -f "${tgt}/.mcp.json" ]
)

# ============================================================
# Case F: 既存 .mcp.json あり → verbatim 保持 (冪等 + 非破壊)
# custom .mcp.json を事前配置 → install 後も md5 不変。--mcp-servers=custom-only
# 指定でも既存 file には触らない (NOTE 出力のみ、Step 2 §3 実装)。
# ============================================================
_case_f() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-f"
  mkdir -p "$tgt"
  local mcp="${tgt}/.mcp.json"
  # user が意図的に置いた custom .mcp.json を模擬 (harness と関係ない 1 server)
  printf '{"mcpServers":{"my-custom":{"command":"echo","args":["hi"]}}}\n' > "$mcp"
  # 変更前 hash (portable: cksum、md5sum/md5 に依存しない)
  local ref
  ref="$(cksum < "$mcp")"
  # subset 指定でも既存 file は keep-as-is (--mcp-servers=serena 指定は NOTE のみ生成)
  bash "$INSTALL_SH" "$tgt" --mcp-servers=serena --no-docs >/dev/null 2>&1 || return 1
  local after
  after="$(cksum < "$mcp")"
  [ "$ref" = "$after" ] || return 1
  # 中身も念のため確認 (my-custom key が生き残っている = 上書きされていない)
  jq -e '.mcpServers | has("my-custom")' "$mcp" >/dev/null 2>&1
)

# ============================================================
# Case G: --dry-run → target に .mcp.json 非生成 (mutation 0、--dry-run 契約)
# ============================================================
_case_g() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-g"
  mkdir -p "$tgt"
  bash "$INSTALL_SH" "$tgt" --dry-run --no-docs >/dev/null 2>&1 || return 1
  [ ! -f "${tgt}/.mcp.json" ]
)

# ============================================================
# Case H: run-all-smokes.sh の portability カテゴリで discover される
# 静的 grep で本 smoke 名が portability の case ブランチに登録されているか確認。
# 登録漏れは run-all-smokes 全体走査で本 smoke が実行されない silent fail に繋がるため
# smoke 自身が自己登録を assert する (task-74 iter-1 の manifest 縮小方針と整合)。
# ============================================================
_case_h() (
  set -uo pipefail
  [ -f "$RUN_ALL" ] || return 1
  # run-all-smokes.sh の _get_smoke_category() を実際に呼び出し、本 smoke 名で
  # 'portability' が返ることを assert (case 文順序 / インデント / コメントに依存しない)。
  # 直接 source すると run-all-smokes 本体の while loop / smoke 実行までが走ってしまうため、
  # bash sub-shell で `set -- --list` を仮に渡しつつ、--list branch が exit 0 する前に
  # 抜けるのは制御困難 → 純関数だけ抽出して評価する形にする。
  # 抽出: `_get_smoke_category()` 定義から `^}` までを sed で切り出し、bash 関数として eval。
  local fn_src
  fn_src="$(sed -n '/^_get_smoke_category()/,/^}/p' "$RUN_ALL")"
  [ -n "$fn_src" ] || return 1
  # eval で関数登録 → 呼び出し。set -u 下でも local 未参照は問題なし。
  eval "$fn_src"
  local cat
  cat="$(_get_smoke_category install-mcp-servers-smoke 2>/dev/null || true)"
  [ "$cat" = "portability" ]
)

# ============================================================
# Case I: docs 反映 grep (install.sh header + §8 summary)
# Step 1 で header に 'mcp-servers' が追加され、Step 2 で §8 summary に
# 'MCP servers について (task-90)' block が追加されていることを行番号非依存で assert。
# NB (scope 限定): draft §3 Step 3 SSoT は README にも 'mcp-servers' 記載を要求するが、
#     本 subagent の担当 file は本 smoke + run-all-smokes.sh のみのため、Case I は
#     install.sh の 2 grep に scope 限定する。README 反映は follow-up (最終報告参照)。
# ============================================================
_case_i() (
  set -uo pipefail
  # install.sh header (Usage 行 + --mcp-servers option 説明) に "mcp-servers" が
  # 2 回以上出現。行番号 hardcode せず、pattern anchor で判定。
  local hdr_count
  hdr_count="$(sed -n '1,60p' "$INSTALL_SH" | grep -c 'mcp-servers' 2>/dev/null || true)"
  [ "$hdr_count" -ge 2 ] || return 1
  # §8 summary の Next steps ブロックに "MCP servers について (task-90)" 見出しが存在
  grep -q 'MCP servers について (task-90)' "$INSTALL_SH" || return 1
  # opt-in server 選択時の env 要件 list (Step 2 §8 summary 追記) が summary に存在
  # (github/salesforce/asana-pat/slack のいずれかを anchor に 1 行検出)
  grep -qE '(github|salesforce|asana-pat|slack)[[:space:]]*:.*\\?\$\{?[A-Z_]+\}?' "$INSTALL_SH" \
    || grep -qE 'GITHUB_PAT|SALESFORCE_|ASANA_PAT|SLACK_MCP_' "$INSTALL_SH"
)

# ============================================================
# Case J: jq 不在 fallback (PATH shim) → WARN + 全 7 server 配布
# 期待挙動 (draft §3 D4 fail-open 契約 = 機能優先):
#   - install.sh §3 の `elif command -v jq` branch が false に落ち、else branch
#     (jq 不在 fallback) に入る。
#   - stderr に 'jq 不在' WARN が出力される。
#   - target .mcp.json は source verbatim = 全 7 server が配布される (功能 regression 0)。
# 実装 (portable):
#   - $TMP_DIR/no-jq-bin にシステム tool の symlink を張り、jq のみ含めない。
#   - PATH=$TMP_DIR/no-jq-bin bash install.sh ... で install.sh を実行。
#   - install.sh が呼ぶ主要 external command (rsync/mktemp/grep/sed/find/git/cp/mv/rm/
#     mkdir/chmod/cat/head/tail/tr/sort/uniq/wc/awk/basename/dirname/readlink/stat/
#     printf/tee/diff/cmp/sleep/date/env/xargs/nl/which/bash/sh) を symlink 対象に含める。
#   - jq が /usr/bin/jq (Linux) と /opt/homebrew/bin/jq (macOS Homebrew) いずれの
#     PATH にあっても、shim dir が jq を含まない限り `command -v jq` は失敗する。
# ============================================================
_case_j() (
  set -uo pipefail
  local tgt="${TMP_DIR}/target-j"
  mkdir -p "$tgt"
  local shim_bin="${TMP_DIR}/no-jq-bin"
  mkdir -p "$shim_bin"
  # install.sh + rsync が要求する commands の symlink を PATH shim に張る (jq は含めない)
  local cmd cmd_path
  for cmd in \
    rsync mktemp grep egrep fgrep sed awk find git cp mv rm mkdir chmod chown \
    cat head tail tr sort uniq wc basename dirname readlink stat printf \
    tee diff cmp sleep date env xargs nl which bash sh ls file touch ln \
    id whoami tty hostname pwd true false test expr uname od cut; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    if [ -n "$cmd_path" ] && [ -x "$cmd_path" ]; then
      ln -sf "$cmd_path" "${shim_bin}/${cmd}" 2>/dev/null || true
    fi
  done
  # shim 環境で jq が探せないことを確認 (前提)
  # PATH="$shim_bin" のみだと bash builtin 経由の command -v は動くが、外部 jq は無い
  local jq_in_shim
  jq_in_shim="$(PATH="$shim_bin" bash -c 'command -v jq 2>/dev/null || true')"
  [ -z "$jq_in_shim" ] || return 1
  # install.sh を PATH shim 下で実行 (jq 不在) → --mcp-servers=serena,context7 指定でも
  # jq 不在 branch に落ちて全配布 fallback + WARN が期待挙動 (draft §3 D4)
  local outlog="${TMP_DIR}/case-j-stdout.log"
  local errlog="${TMP_DIR}/case-j-stderr.log"
  PATH="$shim_bin" bash "$INSTALL_SH" "$tgt" --mcp-servers=serena,context7 --no-docs \
    >"$outlog" 2>"$errlog" || return 1
  # WARN 出力確認 (stderr): 'jq 不在' 文字列
  grep -q 'jq 不在' "$errlog" || return 1
  # 全配布 fallback = 全 7 server が配布されている (source verbatim)。
  # ここは smoke 実行側 (host) の jq を絶対 path で使う (PATH shim 影響なし)
  local mcp="${tgt}/.mcp.json"
  [ -f "$mcp" ] || return 1
  local jq_host
  jq_host="$(command -v jq)"
  local got expected
  got="$("$jq_host" -r '.mcpServers | keys | sort | .[]' "$mcp" 2>/dev/null || true)"
  expected="$("$jq_host" -r '.mcpServers | keys | sort | .[]' "$SOURCE_MCP" 2>/dev/null || true)"
  [ -n "$got" ] || return 1
  [ "$got" = "$expected" ]
)

# ============================================================
# 実行
# ============================================================
printf '\n=== install-mcp-servers-smoke (task-90 Step 3) ===\n\n'

if _case_a 2>/dev/null; then _record PASS A "default install → keys = serena + context7 + placeholder 0"
else                         _record FAIL A "default install → keys = serena + context7 + placeholder 0"; fi

if _case_b 2>/dev/null; then _record PASS B "--mcp-servers=all → keys = source verbatim (7 server)"
else                         _record FAIL B "--mcp-servers=all → keys = source verbatim (7 server)"; fi

if _case_c 2>/dev/null; then _record PASS C "--mcp-servers=serena,context7,github → keys = 指定 3 件 + env verbatim"
else                         _record FAIL C "--mcp-servers=serena,context7,github → keys = 指定 3 件 + env verbatim"; fi

if _case_d 2>/dev/null; then _record PASS D "--mcp-servers=serena,typo → exit 64 + typo/存在しません error"
else                         _record FAIL D "--mcp-servers=serena,typo → exit 64 + typo/存在しません error"; fi

if _case_e 2>/dev/null; then _record PASS E "--no-mcp --mcp-servers=all → exit 64 (併用禁止 conflict)"
else                         _record FAIL E "--no-mcp --mcp-servers=all → exit 64 (併用禁止 conflict)"; fi

if _case_f 2>/dev/null; then _record PASS F "既存 .mcp.json あり → verbatim 保持 (cksum 不変 + custom key 維持)"
else                         _record FAIL F "既存 .mcp.json あり → verbatim 保持 (cksum 不変 + custom key 維持)"; fi

if _case_g 2>/dev/null; then _record PASS G "--dry-run → target に .mcp.json 非生成 (mutation 0)"
else                         _record FAIL G "--dry-run → target に .mcp.json 非生成 (mutation 0)"; fi

if _case_h 2>/dev/null; then _record PASS H "run-all-smokes.sh の portability カテゴリで discover される (静的)"
else                         _record FAIL H "run-all-smokes.sh の portability カテゴリで discover される (静的)"; fi

if _case_i 2>/dev/null; then _record PASS I "install.sh header + §8 summary で 'mcp-servers' 出現 (静的)"
else                         _record FAIL I "install.sh header + §8 summary で 'mcp-servers' 出現 (静的)"; fi

if _case_j 2>/dev/null; then _record PASS J "jq 不在 PATH shim → WARN + 全 7 server 配布 fallback (fail-open)"
else                         _record FAIL J "jq 不在 PATH shim → WARN + 全 7 server 配布 fallback (fail-open)"; fi

TOTAL=$((PASS + FAIL))
printf '\n--- Result: %d/%d PASS ---\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES"
  exit 1
fi
exit 0
