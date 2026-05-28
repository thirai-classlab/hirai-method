#!/usr/bin/env bash
# layer-b-context-isolation-smoke.sh — task-51 Step 4 (A 案 redesign 追従)
#
# 設計起源: docs/tasks/task-51-context-bloat-reduction.md §TDD 戦略 RED
# A 案 redesign (2026-05-28): Layer B (`.details.md`) を `.claude/rules/` から
#   `.claude/rules-details/` (Claude Code discover 対象外の別 dir) へ git mv 移動。
#   Claude Code 公式仕様 (code.claude.com/docs/en/memory.md) で `.claude/rules/*.md` は
#   再帰 discover + startup load、`paths:` は除外機構ではないと確定したため。
#
# Layer A / Layer B 2 層構造の isolation を 8 cases で検証:
#   Case 1: 各 .details.md frontmatter "paths: []" (空配列) — 防御深層 (Layer B が
#           誤って `.claude/rules/` 配下に戻された場合の保険、規約として keep)
#   Case 2: Layer B 物理 dir `.claude/rules-details/` 存在 + Claude Code discover scope
#           外確認 (`.claude/rules/` 配下に `.details.md` が 0 件)
#   Case 3: Layer A→B link 各 file 1 件以上 (../rules-details/<file>.details.md grep)
#   Case 4: Layer B→A back-link 各 file 1 件以上 ("> Layer A:" grep)
#   Case 5: Layer B physical readable + 50 行以上
#   Case 6: Layer A 内 重要 keyword grep (file 別 keyword リスト)
#   Case 7: install.sh `--exclude=rules-details` **不在** (Layer B も sync 対象) +
#           SSoT comment (`rules-details` 文字列) 存在
#   Case 8: Layer A anchor 参照が Layer B heading に存在 (link 切れ 0 件)
#
# 実行:
#   bash .claude/tests/layer-b-context-isolation-smoke.sh
#
# 終了コード:
#   0 = 全 PASS / 1 = 1 件以上 FAIL
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

# ============================================================
# Case 1: 各 .details.md frontmatter "paths: []" (空配列) — 防御深層
# ============================================================
# 規約として keep: Layer B が誤って `.claude/rules/` 配下に戻された場合の保険。
# A 案 redesign では物理 dir 分離 (Case 2) が主防御だが、frontmatter 規約も維持。
case1_layer_b_frontmatter_paths_empty() {
  local label="Case 1: Layer B frontmatter paths: [] (空配列) — 6/6 (防御深層)"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_b="${RULES_DETAILS_DIR}/${f}.details.md"
    if [[ ! -f "$layer_b" ]]; then
      fail_list+=("${f}.details.md: NOT FOUND")
      continue
    fi
    # frontmatter 内 (--- ブロック) の paths: [] を検証
    # awk: 最初の --- 以降〜2番目の --- の前まで を出力し grep
    if ! awk '/^---$/{c++; next} c==1' "$layer_b" | grep -qE '^paths:\s*\[\s*\]'; then
      fail_list+=("${f}.details.md: 'paths: []' not found in frontmatter")
    fi
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 2: Layer B 物理 dir 存在 + Claude Code discover scope 外確認
# ============================================================
# A 案 redesign 主防御: `.claude/rules-details/` dir が存在し、`.claude/rules/`
# 配下に `.details.md` が 0 件であることで Claude Code startup load 対象外を保証。
case2_layer_b_physical_isolation() {
  local label="Case 2: Layer B 物理 dir 存在 + .claude/rules/ 配下 .details.md 0 件"
  local fail_list=()

  # Subcheck 2a: `.claude/rules-details/` dir 存在
  if [[ ! -d "$RULES_DETAILS_DIR" ]]; then
    fail_list+=("$RULES_DETAILS_DIR: directory not found")
  fi

  # Subcheck 2b: `.claude/rules/` 配下に `.details.md` が 0 件
  # (find は dir 不在でも非ゼロ exit するため、存在チェック後に実行)
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
# Case 3: Layer A→B link 各 file 1 件以上
# ============================================================
# A 案では link が `../rules-details/<file>.details.md` 形式に変更
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
# Case 4: Layer B→A back-link 各 file 1 件以上
# ============================================================
# A 案では Layer B → Layer A back-link は `../rules/<file>.md` 形式。
# 検証は "> Layer A:" 行頭 marker で実施 (既存 SSoT format)。
case4_layer_b_to_a_backlinks() {
  local label="Case 4: Layer B→A back-link (> Layer A: + ../rules/) 各 file 1 件以上"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_b="${RULES_DETAILS_DIR}/${f}.details.md"
    if [[ ! -f "$layer_b" ]]; then
      fail_list+=("${f}.details.md: NOT FOUND")
      continue
    fi
    # marker 行 (`> Layer A:`) を count
    local marker_count
    marker_count=$(grep '^> Layer A:' "$layer_b" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$marker_count" -lt 1 ]]; then
      fail_list+=("${f}.details.md: 0 '> Layer A:' back-links")
      continue
    fi
    # `../rules/` path が同 file 内に存在することも検証 (path 形式整合)
    if ! grep -q '\.\./rules/' "$layer_b" 2>/dev/null; then
      fail_list+=("${f}.details.md: marker found but no '../rules/' path link")
    fi
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 5: Layer B physical readable + 50 行以上
# ============================================================
case5_layer_b_readable_and_size() {
  local label="Case 5: Layer B physical readable + 50 行以上 — 6/6"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_b="${RULES_DETAILS_DIR}/${f}.details.md"
    if [[ ! -r "$layer_b" ]]; then
      fail_list+=("${f}.details.md: not readable")
      continue
    fi
    local lines
    lines=$(wc -l < "$layer_b")
    if [[ "$lines" -le 50 ]]; then
      fail_list+=("${f}.details.md: ${lines} lines (need >50)")
    fi
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (failures: ${fail_list[*]})"
  fi
}

# ============================================================
# Case 6: Layer A 内 重要 keyword grep (file 別 keyword リスト)
# ============================================================
case6_layer_a_important_keywords() {
  local label="Case 6: Layer A 重要 keyword 存在"
  local fail_list=()

  # bash 3.2 compatible: declare -A 不可のため case 文で keyword リストを取得
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

    # | 区切りの keyword を IFS=| で分割して個別検証
    local OLD_IFS="$IFS"
    IFS='|'
    local kw_array
    # bash 3.2: read -ra array <<< はサポートしているが念のため安全な方法に
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
# A 案 redesign: `.claude/rules-details/` は exclude 対象外 (rsync -a で 4 リポへ
# 同期される必要あり)。同時に install.sh 内に `rules-details` SSoT comment が存在し、
# 設計意図が明示されていることも検証。
case7_install_sh_no_rules_details_exclude() {
  local label="Case 7: install.sh '--exclude=rules-details' 不在 + SSoT comment 存在"
  local install_sh="${REPO_ROOT}/install.sh"
  local fail_list=()

  if [[ ! -f "$install_sh" ]]; then
    _record_fail "$label (install.sh not found at $install_sh)"
    return
  fi

  # Subcheck 7a: `--exclude=rules-details` が**不在**であること
  if grep -qE '\-\-exclude=.*rules-details' "$install_sh"; then
    fail_list+=("'--exclude=rules-details' が install.sh に存在 — Layer B が sync 対象外になる")
  fi

  # Subcheck 7b: SSoT comment (`rules-details` 文字列、任意 context) 存在
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
# Case 8: Layer A anchor 参照が Layer B heading に存在 (link 切れ 0 件)
# ============================================================
# 検証ロジック (2 段階):
#   Step 1: anchor の最初のハイフン区切りトークンで case-insensitive heading grep
#   Step 2: 見つからない場合、anchor 内の日本語セグメント(2文字以上)で heading grep
case8_anchor_to_heading_integrity() {
  local label="Case 8: Layer A anchor 参照が Layer B heading に存在 (broken 0 件)"
  local fail_list=()

  _check_anchor() {
    local layer_b="$1"
    local anchor="$2"

    # Step 1: 最初のトークン (最初のハイフン境界まで) で case-insensitive grep
    local first_token="${anchor%%-*}"
    if grep -qi "## .*${first_token}" "$layer_b"; then
      return 0
    fi

    # Step 2: 日本語セグメント (2文字以上) で grep
    local jp_segment
    jp_segment=$(printf '%s' "$anchor" | grep -oE '[ぁ-ん一-龯ァ-ヴー]{2,}' | head -1 || true)
    if [[ -n "$jp_segment" ]] && grep -q "## .*${jp_segment}" "$layer_b"; then
      return 0
    fi

    return 1
  }

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    local layer_b="${RULES_DETAILS_DIR}/${f}.details.md"

    if [[ ! -f "$layer_a" || ! -f "$layer_b" ]]; then
      fail_list+=("${f}: file pair missing")
      continue
    fi

    # Layer A から details.md#<anchor> 参照を全件抽出
    local anchors
    anchors=$(grep -hoE '\.details\.md#[^)]+' "$layer_a" | sed 's/\.details\.md#//' || true)

    while IFS= read -r anchor; do
      [[ -z "$anchor" ]] && continue
      if ! _check_anchor "$layer_b" "$anchor"; then
        fail_list+=("${f}: broken anchor '#${anchor}'")
      fi
    done <<< "$anchors"
  done

  if [[ ${#fail_list[@]} -eq 0 ]]; then
    _record_pass "$label"
  else
    _record_fail "$label (broken anchors: ${fail_list[*]})"
  fi
}

# ============================================================
# main
# ============================================================
printf "===== layer-b-context-isolation-smoke (task-51 Step 4, 8 cases, A 案 redesign) =====\n\n"

case1_layer_b_frontmatter_paths_empty
case2_layer_b_physical_isolation
case3_layer_a_to_b_links
case4_layer_b_to_a_backlinks
case5_layer_b_readable_and_size
case6_layer_a_important_keywords
case7_install_sh_no_rules_details_exclude
case8_anchor_to_heading_integrity

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
