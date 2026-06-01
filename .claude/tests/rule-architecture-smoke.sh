#!/usr/bin/env bash
# rule-architecture-smoke.sh — task-67 Step 5
#
# 設計起源: docs/tasks/task-67-rule-architecture-restructure.md Step 5
# Layer A (.claude/rules/*.md) / Layer B (.claude/rules-details/<rule>/<topic>.md) の
# アーキテクチャ健全性を 5 asserts + 1 informational + 1 assert で検証する。
#
# Assert 1: dangling 0 — Layer A 内の (../rules-details/...) リンク先が全件実在
# Assert 2: auto-load isolation — rules-details/ 断片が rules/ 直下に混入していない +
#                                  旧 monolithic *.details.md が残存していない (全 6 rule 移行完了)
# Assert 3: back-link 健全性 — 各断片冒頭に "> Layer A: [" back-link header が存在
# Assert 4 (INFO): Layer A 行数報告 — 参考閾値 280 行超で WARN 出力 (hard-fail なし)
# Assert 5: orphan fragment 0 — 全断片が Layer A から 1 本以上 forward-link されている
# Assert 6: back-link path 解決 — 各断片の back-link path が実在するファイルに解決できる
#
# 実行:
#   bash .claude/tests/rule-architecture-smoke.sh
#
# 終了コード: 0 = 全 PASS (INFO WARN は exit 0) / 1 = 1 件以上 FAIL
#
# 注意:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs.md 教訓)
#   - PyYAML 不要: bash + grep + awk + wc のみ依存

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="${REPO_ROOT}/.claude/rules"
RULES_DETAILS_DIR="${REPO_ROOT}/.claude/rules-details"

PASS=0
FAIL=0
WARN=0
FAILED_CASES=()

_record_pass() { PASS=$((PASS + 1)); printf "  [PASS] %s\n" "$1"; }
_record_fail() {
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("$1")
  printf "  [FAIL] %s\n" "$1"
}
_record_warn() { WARN=$((WARN + 1)); printf "  [WARN] %s\n" "$1"; }
_record_info() { printf "  [INFO] %s\n" "$1"; }

# task-67 対象 Layer A 6 ファイル (git-workflow.md は対象外)
LAYER_A_RULES=(
  self-improvement
  development-process
  task-management
  workflow
  why-x5-output
  modes
)

# Layer A ファイルの行数報告閾値 (hard-fail なし、WARN のみ)
WARN_LINE_THRESHOLD=280

# ============================================================
# Assert 1: dangling 0
# ============================================================
# 全 .claude/rules/*.md 内の (../rules-details/...) リンクを抽出し、
# 各リンク先 file が実在することを assert。1 件でも不在なら FAIL。
assert1_dangling_zero() {
  local label="Assert 1: dangling 0 — Layer A リンク先 Layer B file 全件実在"
  local fail_list=()
  local checked=0
  local total_links=0

  for f in "${LAYER_A_RULES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    if [[ ! -f "$layer_a" ]]; then
      fail_list+=("${f}.md: Layer A file NOT FOUND")
      continue
    fi
    # ../rules-details/ で始まり .md で終わる相対 path を抽出、anchor (#...) は除去
    local targets
    targets=$(grep -oE '\.\./rules-details/[A-Za-z0-9._/-]+\.md' "$layer_a" 2>/dev/null \
      | sed 's/#.*//' | sort -u || true)
    local count
    count=$(printf '%s\n' "$targets" | grep -c '.' || true)
    total_links=$((total_links + count))

    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      checked=$((checked + 1))
      # layer_a は .claude/rules/ 配下、t は ../rules-details/... → .claude/rules-details/...
      local resolved="${RULES_DIR}/${t}"
      if [[ ! -f "$resolved" ]]; then
        fail_list+=("${f}.md: dangling → '${t}'")
      fi
    done <<< "$targets"
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} pointers checked, dangling: 0)"
  else
    printf "  [FAIL] %s\n" "$label"
    for item in "${fail_list[@]}"; do
      printf "         - %s\n" "$item"
    done
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (dangling: ${#fail_list[@]})")
  fi
}

# ============================================================
# Assert 2: auto-load isolation
# ============================================================
# (a) .claude/rules-details/ 配下の断片が .claude/rules/ 直下に存在しないこと
#     (断片が誤って Layer A 化していないこと)
# (b) 旧 .claude/rules-details/*.details.md (monolithic) が残存しないこと
#     (全 6 rule の断片化移行完了確認)
assert2_auto_load_isolation() {
  local label="Assert 2: auto-load isolation — 断片の Layer A 混入 0 件 + 旧 monolithic 残存 0 件"
  local fail_list=()

  # (a) rules/ 直下に .details.md が存在しないこと
  if [[ -d "$RULES_DIR" ]]; then
    local stray_count
    stray_count=$(find "$RULES_DIR" -maxdepth 2 -name '*.details.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$stray_count" -gt 0 ]]; then
      local stray_list
      stray_list=$(find "$RULES_DIR" -maxdepth 2 -name '*.details.md' 2>/dev/null | tr '\n' ' ')
      fail_list+=(".claude/rules/ 配下に *.details.md ${stray_count} 件 (期待: 0): ${stray_list}")
    fi
  else
    fail_list+=(".claude/rules/: directory not found")
  fi

  # (b) rules-details/ 直下 (subdir なし) に *.details.md が残存しないこと
  #     (全 6 rule が fragmented dir 構造に移行完了していることを確認)
  if [[ -d "$RULES_DETAILS_DIR" ]]; then
    local mono_count
    mono_count=$(find "$RULES_DETAILS_DIR" -maxdepth 1 -name '*.details.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$mono_count" -gt 0 ]]; then
      local mono_list
      mono_list=$(find "$RULES_DETAILS_DIR" -maxdepth 1 -name '*.details.md' 2>/dev/null | tr '\n' ' ')
      fail_list+=(".claude/rules-details/ 直下に monolithic *.details.md ${mono_count} 件残存 (期待: 0 — 全 6 rule 断片化完了): ${mono_list}")
    fi

    # rules-details/ 直下に 6 rule の subdir が存在することを確認
    local missing_dirs=()
    for f in "${LAYER_A_RULES[@]}"; do
      if [[ ! -d "${RULES_DETAILS_DIR}/${f}" ]]; then
        missing_dirs+=("${f}/")
      fi
    done
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
      fail_list+=("rules-details/ に subdir 不在: ${missing_dirs[*]}")
    fi
  else
    fail_list+=(".claude/rules-details/: directory not found")
  fi

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    printf "  [FAIL] %s\n" "$label"
    for item in "${fail_list[@]}"; do
      printf "         - %s\n" "$item"
    done
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label")
  fi
}

# ============================================================
# Assert 3: back-link 健全性
# ============================================================
# 各 .claude/rules-details/<rule>/<topic>.md 断片の冒頭に
# "> Layer A: [" back-link header が存在することを assert。
# README.md (index file) は検査対象外。
assert3_backlink_health() {
  local label="Assert 3: back-link 健全性 — 各断片冒頭に '> Layer A: [' header 存在"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_RULES[@]}"; do
    local frag_dir="${RULES_DETAILS_DIR}/${f}"
    if [[ ! -d "$frag_dir" ]]; then
      fail_list+=("${f}/: fragment dir not found")
      continue
    fi

    while IFS= read -r frag; do
      [[ -z "$frag" ]] && continue
      local bn
      bn=$(basename "$frag")
      # README.md はインデックスファイルのため back-link 不要
      [[ "$bn" == "README.md" ]] && continue
      checked=$((checked + 1))

      # "> Layer A: [" を冒頭 (最初の 10 行) で検索
      if ! head -10 "$frag" | grep -q '^> Layer A: \['; then
        fail_list+=("${f}/${bn}: '> Layer A: [' backlink not found in first 10 lines")
      fi
    done < <(find "$frag_dir" -maxdepth 1 -name '*.md' | sort)
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} fragments checked)"
  else
    printf "  [FAIL] %s\n" "$label"
    for item in "${fail_list[@]}"; do
      printf "         - %s\n" "$item"
    done
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (missing: ${#fail_list[@]})")
  fi
}

# ============================================================
# Assert 4 (INFO): Layer A 行数報告
# ============================================================
# 各 .claude/rules/*.md の行数を出力。
# 閾値 hard-fail は設けない (dense 操作 rule は SSoT 優先で超過が妥当なため)。
# 参考閾値 (WARN_LINE_THRESHOLD 行) 超過は WARN 出力。
assert4_layer_a_line_count_report() {
  local label="Assert 4 (INFO): Layer A 行数報告 (参考閾値: ${WARN_LINE_THRESHOLD} 行、hard-fail なし)"
  _record_info "$label"

  local warned=0
  for f in "${LAYER_A_RULES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    if [[ ! -f "$layer_a" ]]; then
      _record_info "  ${f}.md: NOT FOUND"
      continue
    fi
    local lines
    lines=$(wc -l < "$layer_a")
    if [[ "$lines" -gt "$WARN_LINE_THRESHOLD" ]]; then
      _record_warn "  ${f}.md: ${lines} lines (>${WARN_LINE_THRESHOLD} — SSoT 優先で許容、参考 WARN)"
      warned=$((warned + 1))
    else
      _record_info "  ${f}.md: ${lines} lines (OK)"
    fi
  done

  if [[ "$warned" -eq 0 ]]; then
    _record_info "全 ${#LAYER_A_RULES[@]} Layer A files が ${WARN_LINE_THRESHOLD} 行以下 (WARN なし)"
  else
    _record_info "${warned} file(s) が参考閾値 ${WARN_LINE_THRESHOLD} 行超 (hard-fail なし、SSoT 優先)"
  fi
}

# ============================================================
# Assert 5: orphan fragment 0
# ============================================================
# 全 .claude/rules-details/<rule>/<topic>.md 断片 (README.md 除く) が、
# 対応する Layer A .claude/rules/<rule>.md から
# "<rule>/<topic>.md" の形で 1 本以上 forward-link されていることを assert。
# されていない断片 (orphan) があれば FAIL + 断片 path 列挙。
#
# 検索方向: Layer B → Layer A (reverse) で orphan を検出。
# 補足: Assert 1 は Layer A → Layer B (forward) の dangling を検出。
#       Assert 5 は逆方向で Layer B に forward-link が当たっていないことを検出。
assert5_orphan_fragment_zero() {
  local label="Assert 5: orphan fragment 0 — 全断片が Layer A から 1 本以上 forward-link 済"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_RULES[@]}"; do
    local frag_dir="${RULES_DETAILS_DIR}/${f}"
    local layer_a="${RULES_DIR}/${f}.md"

    if [[ ! -d "$frag_dir" ]]; then
      fail_list+=("${f}/: fragment dir not found")
      continue
    fi
    if [[ ! -f "$layer_a" ]]; then
      fail_list+=("${f}.md: Layer A file NOT FOUND")
      continue
    fi

    while IFS= read -r frag; do
      [[ -z "$frag" ]] && continue
      local bn
      bn=$(basename "$frag")
      # README.md はインデックスファイルのため forward-link 必須対象外
      [[ "$bn" == "README.md" ]] && continue
      checked=$((checked + 1))

      # Layer A 内に "<rule>/<topic>.md" の形でリンクが存在するか確認
      # パターン: rules-details/<rule>/<topic>.md  (anchor 付き変形も含め grep)
      local search_pattern="${f}/${bn}"
      if ! grep -qF "$search_pattern" "$layer_a" 2>/dev/null; then
        fail_list+=("${f}/${bn}: orphan — '${search_pattern}' が ${f}.md に forward-link されていない")
      fi
    done < <(find "$frag_dir" -maxdepth 1 -name '*.md' | sort)
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} fragments checked, orphan: 0)"
  else
    printf "  [FAIL] %s\n" "$label"
    for item in "${fail_list[@]}"; do
      printf "         - %s\n" "$item"
    done
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (orphan: ${#fail_list[@]})")
  fi
}

# ============================================================
# Assert 6: back-link path 解決検証
# ============================================================
# 全断片冒頭の "> Layer A: [`...`](../../rules/<rule>.md)" の back-link path を
# 相対解決し、リンク先 file が実在することを assert。
# README.md は back-link 不要のため対象外。
# §section 名と Layer A heading の一致検証は追加しない
# (section rename で fragile + false positive のため)。
assert6_backlink_path_resolution() {
  local label="Assert 6: back-link path 解決 — 全断片の back-link が実在 file に解決"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_RULES[@]}"; do
    local frag_dir="${RULES_DETAILS_DIR}/${f}"
    if [[ ! -d "$frag_dir" ]]; then
      fail_list+=("${f}/: fragment dir not found")
      continue
    fi

    while IFS= read -r frag; do
      [[ -z "$frag" ]] && continue
      local bn
      bn=$(basename "$frag")
      # README.md は back-link 不要のため対象外
      [[ "$bn" == "README.md" ]] && continue

      # 冒頭 10 行から "> Layer A: [...](...)" のパスを抽出
      # 形式例: > Layer A: [`modes.md`](../../rules/modes.md) §...
      # grep で (...) 内の path 部分を抽出、anchor (#...) は除去
      local raw_path
      raw_path=$(head -10 "$frag" \
        | grep '^> Layer A: \[' \
        | grep -oE '\([^)]+\)' \
        | head -1 \
        | tr -d '()' \
        | sed 's/#.*//' \
        | tr -d ' ' \
        || true)

      if [[ -z "$raw_path" ]]; then
        # back-link 行が見つからない (Assert 3 が先に検出するが念のため)
        fail_list+=("${f}/${bn}: back-link path not found (cannot resolve)")
        continue
      fi

      checked=$((checked + 1))

      # 断片は .claude/rules-details/<rule>/<topic>.md に存在
      # raw_path が ../../rules/<rule>.md の場合:
      #   frag dir: .claude/rules-details/<rule>/
      #   ../../ → .claude/ の親の親 = REPO_ROOT
      #   よって resolved = REPO_ROOT/.claude/rules/<rule>.md ... ではなく
      #   frag の dirname からの相対解決を行う
      local frag_dir_abs
      frag_dir_abs="$(dirname "$frag")"
      # bash では realpath が使えない場合に備えて cd + pwd で解決
      local resolved
      resolved="$(cd "$frag_dir_abs" && cd "$(dirname "$raw_path")" 2>/dev/null && pwd)/$(basename "$raw_path")" 2>/dev/null || true

      if [[ -z "$resolved" ]] || [[ ! -f "$resolved" ]]; then
        fail_list+=("${f}/${bn}: back-link '${raw_path}' → resolved '${resolved:-<empty>}' — file NOT FOUND")
      fi
    done < <(find "$frag_dir" -maxdepth 1 -name '*.md' | sort)
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} back-links resolved, all exist)"
  else
    printf "  [FAIL] %s\n" "$label"
    for item in "${fail_list[@]}"; do
      printf "         - %s\n" "$item"
    done
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (unresolvable: ${#fail_list[@]})")
  fi
}

# ============================================================
# main
# ============================================================
printf "===== rule-architecture-smoke (task-67 Step 5, 5 asserts + 1 INFO) =====\n\n"

assert1_dangling_zero
printf "\n"
assert2_auto_load_isolation
printf "\n"
assert3_backlink_health
printf "\n"
assert4_layer_a_line_count_report
printf "\n"
assert5_orphan_fragment_zero
printf "\n"
assert6_backlink_path_resolution

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
if [[ "$WARN" -gt 0 ]]; then
  printf "WARN: %d (informational only, exit 0 if no FAIL)\n" "$WARN"
fi

if [[ "$FAIL" -gt 0 ]]; then
  printf "\nFailed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS (WARN: %d)\n" "$PASS" "$TOTAL" "$WARN"
  exit 1
fi

printf "\nsummary: %d/%d PASS (WARN: %d)\n" "$PASS" "$TOTAL" "$WARN"
exit 0
