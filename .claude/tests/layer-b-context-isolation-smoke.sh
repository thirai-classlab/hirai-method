#!/usr/bin/env bash
# layer-b-context-isolation-smoke.sh — task-51 Step 4 (A 案 redesign) + task-67 (断片化追従)
#
# 設計起源: docs/tasks/task-51-context-bloat-reduction.md §TDD 戦略 RED
# A 案 redesign (2026-05-28): Layer B (`.details.md`) を `.claude/rules/` から
#   `.claude/rules-details/` (Claude Code discover 対象外の別 dir) へ git mv 移動。
# task-67 (2026-06-01): 一部 rule の Layer B を `<rule>.details.md` 単一 file から
#   `<rule>/<topic>.md` 断片 dir 構造へ分割。本 smoke は両構造 (single-file / fragmented)
#   を自動判別して検証する。
#
# Layer A / Layer B 2 層構造の isolation を 8 cases で検証:
#   Case 1: Layer B frontmatter "paths: []" — single-file rule のみ (断片には frontmatter 不要)
#   Case 2: Layer B 物理 dir 存在 + `.claude/rules/` 配下に `.details.md` 0 件
#   Case 3: Layer A→B link 各 file 1 件以上 (../rules-details/ 参照)
#   Case 4: Layer B→A back-link 各 Layer B file 1 件以上 ("> Layer A:" + ../rules/)
#   Case 5: Layer B physical readable + 行数下限
#   Case 6: Layer A 内 重要 keyword grep
#   Case 7: install.sh `--exclude=rules-details` 不在 + SSoT comment 存在
#   Case 8: Layer A pointer (forward-link) 先の Layer B file が実在 (dangling 0 件)
#
# 実行:
#   bash .claude/tests/layer-b-context-isolation-smoke.sh
#
# 終了コード: 0 = 全 PASS / 1 = 1 件以上 FAIL
#
# 注意:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs.md 教訓)
#   - PyYAML 不要: bash + grep + awk のみ依存

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="${REPO_ROOT}/.claude/rules"
RULES_DETAILS_DIR="${REPO_ROOT}/.claude/rules-details"

PASS=0
FAIL=0
FAILED_CASES=()

_record_pass() { PASS=$((PASS + 1)); printf "  [PASS] %s\n" "$1"; }
_record_fail() {
  FAIL=$((FAIL + 1))
  FAILED_CASES+=("$1")
  printf "  [FAIL] %s\n" "$1"
}
_record_warn() { printf "  [WARN] %s\n" "$1"; }

# Layer A / Layer B の対象 6 ファイルペア
LAYER_A_FILES=(
  self-improvement
  development-process
  task-management
  workflow
  why-x5-output
  modes
)

# rule が断片化済 (fragmented) か single-file (.details.md) かを判別。
#   fragmented: `.claude/rules-details/<rule>/` dir が存在
#   single-file: `.claude/rules-details/<rule>.details.md` が存在
# echo "fragmented" / "single" / "none"
_layer_b_kind() {
  local rule="$1"
  if [[ -d "${RULES_DETAILS_DIR}/${rule}" ]]; then
    echo "fragmented"
  elif [[ -f "${RULES_DETAILS_DIR}/${rule}.details.md" ]]; then
    echo "single"
  else
    echo "none"
  fi
}

# rule の Layer B file 群を列挙 (single は 1 file、fragmented は dir 配下全 *.md)
_layer_b_files() {
  local rule="$1"
  local kind
  kind=$(_layer_b_kind "$rule")
  if [[ "$kind" == "fragmented" ]]; then
    find "${RULES_DETAILS_DIR}/${rule}" -maxdepth 1 -name '*.md' 2>/dev/null
  elif [[ "$kind" == "single" ]]; then
    echo "${RULES_DETAILS_DIR}/${rule}.details.md"
  fi
}

# ============================================================
# Case 1: single-file rule の frontmatter "paths: []" (空配列) — 防御深層
# ============================================================
# fragmented rule の断片は frontmatter 不要 (物理 dir 分離 Case 2 が主防御) のため skip。
case1_layer_b_frontmatter_paths_empty() {
  local label="Case 1: single-file Layer B frontmatter paths: [] (空配列) — 防御深層"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_FILES[@]}"; do
    local kind
    kind=$(_layer_b_kind "$f")
    [[ "$kind" != "single" ]] && continue
    checked=$((checked + 1))
    local layer_b="${RULES_DETAILS_DIR}/${f}.details.md"
    if ! awk '/^---$/{c++; next} c==1' "$layer_b" | grep -qE '^paths:\s*\[\s*\]'; then
      fail_list+=("${f}.details.md: 'paths: []' not found in frontmatter")
    fi
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} single-file rules checked)"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 2: Layer B 物理 dir 存在 + Claude Code discover scope 外確認
# ============================================================
case2_layer_b_physical_isolation() {
  local label="Case 2: Layer B 物理 dir 存在 + .claude/rules/ 配下 .details.md 0 件"
  local fail_list=()

  if [[ ! -d "$RULES_DETAILS_DIR" ]]; then
    fail_list+=("$RULES_DETAILS_DIR: directory not found")
  fi

  if [[ -d "$RULES_DIR" ]]; then
    local stray_count
    stray_count=$(find "$RULES_DIR" -maxdepth 2 -name '*.details.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$stray_count" -gt 0 ]]; then
      local stray_list
      stray_list=$(find "$RULES_DIR" -maxdepth 2 -name '*.details.md' 2>/dev/null | tr '\n' ' ')
      fail_list+=(".claude/rules/ 配下に *.details.md が ${stray_count} 件存在 (期待: 0 件): ${stray_list}")
    fi
  else
    fail_list+=("$RULES_DIR: directory not found")
  fi

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 3: Layer A→B link 各 file 1 件以上 (../rules-details/ 参照)
# ============================================================
case3_layer_a_to_b_links() {
  local label="Case 3: Layer A→B link (../rules-details/ 参照) 各 file 1 件以上"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    if [[ ! -f "$layer_a" ]]; then
      fail_list+=("${f}.md: NOT FOUND")
      continue
    fi
    local count
    count=$(grep '\.\./rules-details/' "$layer_a" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -lt 1 ]]; then
      fail_list+=("${f}.md: 0 refs to ../rules-details/")
    fi
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 4: Layer B→A back-link 各 Layer B file 1 件以上
# ============================================================
# single / fragmented 両対応: 該当 rule の全 Layer B file が "> Layer A:" + "../rules/"
# (fragmented は ../../rules/) を持つことを検証。
case4_layer_b_to_a_backlinks() {
  local label="Case 4: Layer B→A back-link (> Layer A: + rules/) 各 file 1 件以上"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_FILES[@]}"; do
    local kind
    kind=$(_layer_b_kind "$f")
    if [[ "$kind" == "none" ]]; then
      fail_list+=("${f}: Layer B 不在 (dir も .details.md も無し)")
      continue
    fi
    while IFS= read -r layer_b; do
      [[ -z "$layer_b" ]] && continue
      checked=$((checked + 1))
      local bn
      bn=$(basename "$layer_b")
      if ! grep -q '^> Layer A:' "$layer_b" 2>/dev/null; then
        fail_list+=("${f}/${bn}: 0 '> Layer A:' back-links")
        continue
      fi
      # single は ../rules/ 、fragmented は ../../rules/ 。共通 substring '/rules/' で検証。
      if ! grep -q '/rules/' "$layer_b" 2>/dev/null; then
        fail_list+=("${f}/${bn}: marker found but no 'rules/' path link")
      fi
    done < <(_layer_b_files "$f")
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} Layer B files checked)"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 5: Layer B physical readable + 行数下限
# ============================================================
# single-file は >50 行、fragmented 断片は >5 行 (断片は小さい、目標 <100 行)。
case5_layer_b_readable_and_size() {
  local label="Case 5: Layer B physical readable + 行数下限"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_FILES[@]}"; do
    local kind
    kind=$(_layer_b_kind "$f")
    [[ "$kind" == "none" ]] && { fail_list+=("${f}: Layer B 不在"); continue; }
    local min_lines=50
    [[ "$kind" == "fragmented" ]] && min_lines=5
    while IFS= read -r layer_b; do
      [[ -z "$layer_b" ]] && continue
      checked=$((checked + 1))
      local bn
      bn=$(basename "$layer_b")
      if [[ ! -r "$layer_b" ]]; then
        fail_list+=("${f}/${bn}: not readable")
        continue
      fi
      local lines
      lines=$(wc -l < "$layer_b")
      if [[ "$lines" -le "$min_lines" ]]; then
        fail_list+=("${f}/${bn}: ${lines} lines (need >${min_lines})")
      fi
    done < <(_layer_b_files "$f")
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} Layer B files checked)"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 6: Layer A 内 重要 keyword grep
# ============================================================
case6_layer_a_important_keywords() {
  local label="Case 6: Layer A 重要 keyword 存在"
  local fail_list=()

  _get_keywords() {
    case "$1" in
      task-management)   echo "採用 6 条|plan-first|依存先タスク" ;;
      modes)             echo "遵守事項 2 例外|自律実行禁止|5 層強制" ;;
      workflow)          echo "20 MECE|fan-out" ;;
      why-x5-output)     echo "何のため|何をやる|v10" ;;
      development-process) echo "staging|委譲必須要件" ;;
      self-improvement)  echo "L1|L4|F1|F2" ;;
      *)                 echo "" ;;
    esac
  }

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    if [[ ! -f "$layer_a" ]]; then
      fail_list+=("${f}.md: NOT FOUND")
      continue
    fi
    local kw_list
    kw_list=$(_get_keywords "$f")
    [[ -z "$kw_list" ]] && continue

    local OLD_IFS="$IFS"
    IFS='|'
    local kw_array
    set -f
    kw_array=($kw_list)
    set +f
    IFS="$OLD_IFS"

    for kw in "${kw_array[@]}"; do
      if ! grep -q "$kw" "$layer_a"; then
        fail_list+=("${f}.md: keyword '${kw}' not found")
      fi
    done
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 7: install.sh `--exclude=rules-details` 不在 + SSoT comment 存在
# ============================================================
case7_install_sh_no_rules_details_exclude() {
  local label="Case 7: install.sh '--exclude=rules-details' 不在 + SSoT comment 存在"
  local install_sh="${REPO_ROOT}/install.sh"
  local fail_list=()

  if [[ ! -f "$install_sh" ]]; then
    _record_fail "$label (install.sh not found at $install_sh)"
    return
  fi

  if grep -qE '\-\-exclude=.*rules-details' "$install_sh"; then
    fail_list+=("'--exclude=rules-details' が install.sh に存在 — Layer B が sync 対象外になる")
  fi

  if ! grep -q 'rules-details' "$install_sh"; then
    fail_list+=("install.sh に 'rules-details' SSoT comment / 言及不在 — A 案設計意図が未記載")
  fi

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (exclude 不在 + SSoT comment 存在)"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 8: Layer A pointer 先の Layer B file が実在 (dangling 0 件)
# ============================================================
# 旧 anchor 検証は断片化で廃止 (README link reference 規約: 断片ファイル直リンク)。
# fragmented rule: `(../rules-details/<rule>/<topic>.md)` 各リンク先実在を assert。
# single rule:     `(../rules-details/<rule>.details.md...)` リンク先実在を assert。
case8_pointer_target_exists() {
  local label="Case 8: Layer A pointer 先 Layer B file 実在 (dangling 0 件)"
  local fail_list=()
  local checked=0

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    [[ ! -f "$layer_a" ]] && { fail_list+=("${f}.md: NOT FOUND"); continue; }
    # ../rules-details/ で始まり .md で終わる相対 path を全抽出 (#anchor は除去)
    local targets
    targets=$(grep -oE '\.\./rules-details/[A-Za-z0-9._/-]+\.md' "$layer_a" | sed 's/#.*//' | sort -u || true)
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      checked=$((checked + 1))
      # layer_a は .claude/rules/ 配下、t は ../rules-details/... → .claude/rules-details/...
      local resolved="${RULES_DIR}/${t}"
      if [[ ! -f "$resolved" ]]; then
        fail_list+=("${f}.md: dangling pointer '${t}'")
      fi
    done <<< "$targets"
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label (${checked} pointers checked)"
  else
    _record_fail "$label (dangling: ${fail_list[*]})"
  fi
}

# ============================================================
# main
# ============================================================
printf "===== layer-b-context-isolation-smoke (task-51 Step 4 + task-67 断片化, 8 cases) =====\n\n"

case1_layer_b_frontmatter_paths_empty
case2_layer_b_physical_isolation
case3_layer_a_to_b_links
case4_layer_b_to_a_backlinks
case5_layer_b_readable_and_size
case6_layer_a_important_keywords
case7_install_sh_no_rules_details_exclude
case8_pointer_target_exists

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [[ "$FAIL" -gt 0 ]]; then
  printf "\nFailed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
  exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
