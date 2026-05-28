#!/usr/bin/env bash
# layer-b-context-isolation-smoke.sh — task-51 Step 4 (TDD RED → GREEN)
#
# 設計起源: docs/tasks/task-51-context-bloat-reduction.md §TDD 戦略 RED
# iter 1 reviewer (tdd-guide / qa-expert / harness-optimizer) 共通指摘 CRITICAL C-1 対応
#
# Layer A / Layer B 2 層構造の isolation を 8 cases で検証:
#   Case 1: 各 .details.md frontmatter "paths: []" (空配列) — 6/6 PASS
#   Case 2: .claudeignore に "*.details.md" 存在 — WARN のみ (不在でも FAIL しない)
#   Case 3: Layer A→B link 各 file 1 件以上 (details.md 参照 grep)
#   Case 4: Layer B→A back-link 各 file 1 件以上 ("> Layer A:" grep)
#   Case 5: Layer B physical readable + 50 行以上
#   Case 6: Layer A 内 重要 keyword grep (file 別 keyword リスト)
#   Case 7: install.sh RSYNC_EXCLUDES に "*.details.md" 不在 (除外されていない = sync 対象)
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
#   - subagent staging 戦略で /tmp 経由でインストール済

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RULES_DIR="${REPO_ROOT}/.claude/rules"

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
# Case 1: 各 .details.md frontmatter "paths: []" (空配列)
# ============================================================
case1_layer_b_frontmatter_paths_empty() {
  local label="Case 1: Layer B frontmatter paths: [] (空配列) — 6/6"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_b="${RULES_DIR}/${f}.details.md"
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
# Case 2: .claudeignore に "*.details.md" 存在 (WARN のみ)
# ============================================================
case2_claudeignore_details_entry() {
  local label="Case 2: .claudeignore に *.details.md エントリ (任意対応)"
  local claudeignore="${REPO_ROOT}/.claudeignore"

  if [[ ! -f "$claudeignore" ]]; then
    _record_warn "$label — .claudeignore 不在 (WARN: 任意対応、FAIL にしない)"
    _record_pass "$label (WARN のみ、PASS 扱い)"
    return
  fi

  if grep -qF '*.details.md' "$claudeignore"; then
    _record_pass "$label (*.details.md エントリ存在)"
  else
    _record_warn "$label — .claudeignore に *.details.md 不在 (任意対応、FAIL にしない)"
    _record_pass "$label (WARN のみ、PASS 扱い)"
  fi
}

# ============================================================
# Case 3: Layer A→B link 各 file 1 件以上
# ============================================================
case3_layer_a_to_b_links() {
  local label="Case 3: Layer A→B link (details.md 参照) 各 file 1 件以上"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_a="${RULES_DIR}/${f}.md"
    if [[ ! -f "$layer_a" ]]; then
      fail_list+=("${f}.md: NOT FOUND")
      continue
    fi
    local count
    count=$(grep '\.details\.md' "$layer_a" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -lt 1 ]]; then
      fail_list+=("${f}.md: 0 refs to .details.md")
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
case4_layer_b_to_a_backlinks() {
  local label="Case 4: Layer B→A back-link (> Layer A:) 各 file 1 件以上"
  local fail_list=()

  for f in "${LAYER_A_FILES[@]}"; do
    local layer_b="${RULES_DIR}/${f}.details.md"
    if [[ ! -f "$layer_b" ]]; then
      fail_list+=("${f}.details.md: NOT FOUND")
      continue
    fi
    local count
    # Note: use '^> Layer A:' not '^\> Layer A:' — macOS BSD grep ERE treats \> as word boundary
    count=$(grep '^> Layer A:' "$layer_b" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -lt 1 ]]; then
      fail_list+=("${f}.details.md: 0 '> Layer A:' back-links")
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
    local layer_b="${RULES_DIR}/${f}.details.md"
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
# Case 7: install.sh RSYNC_EXCLUDES に "*.details.md" 不在
# ============================================================
case7_install_sh_no_details_exclude() {
  local label="Case 7: install.sh RSYNC_EXCLUDES に *.details.md 不在 (sync 対象確認)"
  local install_sh="${REPO_ROOT}/install.sh"

  if [[ ! -f "$install_sh" ]]; then
    _record_fail "$label (install.sh not found at $install_sh)"
    return
  fi

  # *.details.md が exclude pattern に含まれていないこと (exit 1 = 不在 = PASS)
  if grep -qE 'exclude.*details' "$install_sh"; then
    _record_fail "$label (*.details.md が RSYNC_EXCLUDES に含まれている — Layer B が sync 対象外になる)"
  else
    _record_pass "$label (*.details.md は exclude 対象外)"
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
    local layer_b="${RULES_DIR}/${f}.details.md"

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
printf "===== layer-b-context-isolation-smoke (task-51 Step 4, 8 cases) =====\n\n"

case1_layer_b_frontmatter_paths_empty
case2_claudeignore_details_entry
case3_layer_a_to_b_links
case4_layer_b_to_a_backlinks
case5_layer_b_readable_and_size
case6_layer_a_important_keywords
case7_install_sh_no_details_exclude
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
