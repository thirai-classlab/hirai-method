#!/usr/bin/env bash
# new-task-batch-update-smoke.sh — task-34 Step 4 batch update verification
#
# 検証対象: .claude/scripts/new-task-helper.sh の update_or_append_task_row 関数
#
# Case 一覧 (採用 6 条準拠、Task 概要欄 3 要素規約):
#   Case 1 (update mode):
#     - 同 ID + 同 slug + 📝 既存 1 件 → status 🔲 へ update、行数増えず
#   Case 2 (append mode):
#     - 同 ID 不在 → 新規行 append
#   Case 3 (batch 先置き整合性 N=3):
#     - 📝 3 行先置き後、同 ID 連続実行で順次 🔲 update + 行重複なし
#   Case 3.5 (N=10 性能境界):
#     - N=10 で全体実行時間 10 秒以内
#
#   iter1 finding regression cases (CRIT 3 + HIGH 8):
#   Case 4 (C-01 / H-08): 同 ID + 別 slug + 📝 既存 → BLOCK (誤連番検知)
#   Case 5 (C-02): slug substring false match 防止 (foo vs foo-bar)
#   Case 6 (C-03): 同 ID + 同 slug で status 混在 (📝/🔲) → BLOCK
#   Case 7 (H-01): regex injection (slug 特殊文字) で破壊されない
#   Case 8 (H-04): 末尾改行なし list.md への append で前行結合しない
#   Case 9 (重複起動防止): 同 ID + 別 status (🔲 のみ) → BLOCK
#
# 設計制約:
#   - file-top に set -euo pipefail を書かない (Critical Lesson HIGH)
#   - 全体実行時間 10 秒以内 (M-02)
#
# 実行:
#   bash .claude/tests/new-task-batch-update-smoke.sh
#
# Exit:
#   0 = all cases PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/.claude/scripts/new-task-helper.sh"

if [ ! -f "$HELPER" ]; then
    echo "ERROR: helper not found: $HELPER" >&2
    exit 2
fi

TMP_ROOT="$(mktemp -d /tmp/new-task-batch-update-smoke.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

PASS=0
FAIL=0
FAILED_CASES=()

case_assert() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$name"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name (expected='$expected' actual='$actual')")
        printf "  FAIL: %s\n    expected: %s\n    actual:   %s\n" "$name" "$expected" "$actual"
    fi
}

case_assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -qF "$needle"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$name"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("$name (needle='$needle' not in actual)")
        printf "  FAIL: %s\n    needle: %s\n    haystack: %s\n" "$name" "$needle" "$haystack"
    fi
}

# === Case 1: update mode ===
case1_update_mode() {
    echo "=== Case 1: update mode (📝 既存 1 件 → 🔲 update) ==="
    local list="$TMP_ROOT/list1.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local row_new='| 1 | 🔲 | **Task: foo** | overview | [foo.md] |'
    bash "$HELPER" update_or_append_task_row 1 foo "$row_new" "$list" >/dev/null

    # 行数 1 維持
    local count
    count=$(grep -cE "^\| 1 \|" "$list" || true)
    case_assert "Case 1.1: 行数 1 維持" "1" "$count"

    # status 🔲 に変化
    if grep -qE "^\| 1 \| 🔲" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 1.2: status 🔲 へ update"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 1.2: status 🔲 へ update (実 content: $(cat "$list"))")
        printf "  FAIL: %s\n" "Case 1.2: status 🔲 へ update"
    fi

    # 📝 が残っていない
    if ! grep -qF "📝" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 1.3: 📝 完全置換"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 1.3: 📝 が残存")
        printf "  FAIL: %s\n" "Case 1.3: 📝 が残存"
    fi
}

# === Case 2: append mode ===
case2_append_mode() {
    echo "=== Case 2: append mode (同 ID 不在 → 新規 append) ==="
    local list="$TMP_ROOT/list2.md"
    cat > "$list" <<'EOF'
| 1 | 🔲 | **Task: foo** | overview | [foo.md] |
EOF
    local row_new='| 2 | 🔲 | **Task: bar** | overview | [bar.md] |'
    bash "$HELPER" update_or_append_task_row 2 bar "$row_new" "$list" >/dev/null

    local count
    count=$(grep -cE "^\| [0-9]+ \|" "$list" || true)
    case_assert "Case 2.1: 2 行に増加" "2" "$count"

    if grep -qE "^\| 2 \| 🔲.*Task: bar" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 2.2: 新規行 append"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 2.2: 新規行 append (実 content: $(cat "$list"))")
        printf "  FAIL: %s\n" "Case 2.2: 新規行 append"
    fi
}

# === Case 3: batch 先置き整合性 (N=3) ===
case3_batch_integrity_n3() {
    echo "=== Case 3: batch 先置き整合性 N=3 ==="
    local list="$TMP_ROOT/list3.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: alpha** | overview | [alpha.md] |
| 2 | 📝 | **Task: beta** | overview | [beta.md] |
| 3 | 📝 | **Task: gamma** | overview | [gamma.md] |
EOF
    bash "$HELPER" update_or_append_task_row 1 alpha '| 1 | 🔲 | **Task: alpha** | overview | [alpha.md] |' "$list" >/dev/null
    bash "$HELPER" update_or_append_task_row 2 beta '| 2 | 🔲 | **Task: beta** | overview | [beta.md] |' "$list" >/dev/null
    bash "$HELPER" update_or_append_task_row 3 gamma '| 3 | 🔲 | **Task: gamma** | overview | [gamma.md] |' "$list" >/dev/null

    local updated_count
    updated_count=$(grep -cE "^\| [0-9]+ \| 🔲" "$list" || true)
    case_assert "Case 3.1: N=3 全行 🔲 へ" "3" "$updated_count"

    local total_count
    total_count=$(grep -cE "^\| [0-9]+ \|" "$list" || true)
    case_assert "Case 3.2: 行数増えず (3 行)" "3" "$total_count"

    # 📝 0 件
    local pending_count
    pending_count=$(grep -cF "📝" "$list" || true)
    case_assert "Case 3.3: 📝 0 件" "0" "$pending_count"
}

# === Case 3.5: N=10 性能境界 ===
case3_5_performance_n10() {
    echo "=== Case 3.5: N=10 性能境界 (10 秒以内) ==="
    local list="$TMP_ROOT/list3_5.md"
    : > "$list"
    local i
    for i in $(seq 1 10); do
        printf '| %d | 📝 | **Task: t%d** | overview | [t%d.md] |\n' "$i" "$i" "$i" >> "$list"
    done

    local start_ts end_ts duration
    start_ts=$(date +%s)
    for i in $(seq 1 10); do
        bash "$HELPER" update_or_append_task_row "$i" "t$i" "| $i | 🔲 | **Task: t$i** | overview | [t$i.md] |" "$list" >/dev/null
    done
    end_ts=$(date +%s)
    duration=$((end_ts - start_ts))

    local updated_count
    updated_count=$(grep -cE "^\| [0-9]+ \| 🔲" "$list" || true)
    case_assert "Case 3.5.1: N=10 全行 update" "10" "$updated_count"

    if [ "$duration" -le 10 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s (%d sec)\n" "Case 3.5.2: 実行時間 10 秒以内" "$duration"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 3.5.2: 実行時間 (${duration} sec > 10 sec)")
        printf "  FAIL: %s (%d sec)\n" "Case 3.5.2: 実行時間" "$duration"
    fi
}

# === Case 4: C-01 / H-08 同 ID + 別 slug + 📝 → BLOCK ===
case4_id_diff_slug_pending_block() {
    echo "=== Case 4 (C-01/H-08): 同 ID + 別 slug + 📝 既存 → BLOCK ==="
    local list="$TMP_ROOT/list4.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    # 同 ID=1 + 別 slug=bar で呼び出し → BLOCK 期待
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 bar '| 1 | 🔲 | **Task: bar** | overview | [bar.md] |' "$list" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 4.1: exit 1 (BLOCK)"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 4.1: exit code (expected=1 actual=$exit_code, out=$out)")
        printf "  FAIL: %s (exit=%d)\n" "Case 4.1" "$exit_code"
    fi

    case_assert_contains "Case 4.2: 'BLOCK' message" "BLOCK" "$out"
    case_assert_contains "Case 4.3: '誤連番' message" "誤連番" "$out"

    # list.md は変更されていない (元の 1 行のまま)
    local count
    count=$(grep -cE "^\| 1 \|" "$list" || true)
    case_assert "Case 4.4: list.md 変更なし (1 行)" "1" "$count"

    if ! grep -qF "Task: bar" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 4.5: bar 行が append されていない"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 4.5: bar が append されている (誤連番検知失敗)")
        printf "  FAIL: %s\n" "Case 4.5"
    fi
}

# === Case 5: C-02 slug substring false match 防止 ===
case5_slug_substring_false_match() {
    echo "=== Case 5 (C-02): slug substring false match 防止 ==="
    # foo-bar 行が既存、foo で update → 別 slug + 📝 として BLOCK 期待
    local list="$TMP_ROOT/list5.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo-bar** | overview | [foo-bar.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    # foo は foo-bar に substring match してはならない → 同 ID + 別 slug + 📝 で BLOCK
    if [ "$exit_code" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 5.1: substring 誤マッチせず BLOCK"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 5.1: substring 誤マッチ (exit=$exit_code, out=$out)")
        printf "  FAIL: %s\n" "Case 5.1 (exit=$exit_code)"
    fi

    # foo-bar 行は更新されていない
    if grep -qE "^\| 1 \| 📝.*foo-bar" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 5.2: foo-bar 行は 📝 のまま"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 5.2: foo-bar が誤って 🔲 update された")
        printf "  FAIL: %s\n" "Case 5.2"
    fi
}

# === Case 6: C-03 status 混在 → BLOCK ===
case6_status_mixed_block() {
    echo "=== Case 6 (C-03): 同 ID + 同 slug で status 混在 → BLOCK ==="
    local list="$TMP_ROOT/list6.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
| 1 | 🔲 | **Task: foo (dup)** | overview | [foo.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 6.1: status 混在で BLOCK (exit 1)"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 6.1: status 混在で BLOCK されず (exit=$exit_code)")
        printf "  FAIL: %s\n" "Case 6.1 (exit=$exit_code)"
    fi

    case_assert_contains "Case 6.2: '混在' message" "混在" "$out"
}

# === Case 7: H-01 regex injection (slug 特殊文字) ===
case7_regex_injection_slug() {
    echo "=== Case 7 (H-01): regex injection (slug 特殊文字 .) ==="
    # slug に '.' が含まれる場合、escape されないと '.' が任意文字に match して誤動作
    local list="$TMP_ROOT/list7.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo.bar** | overview | [foo.bar.md] |
| 2 | 📝 | **Task: fooXbar** | overview | [fooXbar.md] |
EOF
    # slug=foo.bar で id=1 を update、id=2 (fooXbar) には影響しないこと
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 'foo.bar' '| 1 | 🔲 | **Task: foo.bar** | overview | [foo.bar.md] |' "$list" 2>&1)
    exit_code=$?

    case_assert "Case 7.1: exit 0 (正常 update)" "0" "$exit_code"

    # id=1 は 🔲 に変化、id=2 (fooXbar) は 📝 のまま (regex の '.' が誤って X に match していない)
    if grep -qE "^\| 1 \| 🔲" "$list" && grep -qE "^\| 2 \| 📝.*fooXbar" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 7.2: id=1 update + id=2 fooXbar 未影響"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 7.2: regex injection (content: $(cat "$list"))")
        printf "  FAIL: %s\n" "Case 7.2"
    fi
}

# === Case 8: H-04 末尾改行欠落 append ===
case8_no_trailing_eol_append() {
    echo "=== Case 8 (H-04): 末尾改行なし list.md への append ==="
    local list="$TMP_ROOT/list8.md"
    # printf で末尾改行なしを作る
    printf '%s' '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' > "$list"

    # 末尾改行確認
    local last_byte_before
    last_byte_before=$(tail -c 1 "$list" | od -An -c -N1 | tr -d ' ')

    # append (同 ID 不在の id=2)
    bash "$HELPER" update_or_append_task_row 2 bar '| 2 | 🔲 | **Task: bar** | overview | [bar.md] |' "$list" >/dev/null

    # 2 行に分かれているか (前行末尾結合されていない)
    local count
    count=$(grep -cE "^\| [0-9]+ \|" "$list" || true)
    case_assert "Case 8.1: 2 行に分割 append" "2" "$count"

    if grep -qE "^\| 2 \| 🔲.*Task: bar" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 8.2: bar 行が独立した行に存在"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 8.2: bar が前行と結合 (content: $(cat "$list"))")
        printf "  FAIL: %s\n" "Case 8.2"
    fi
}

# === Case 9: 同 ID + 別 status (🔲 のみ) → BLOCK ===
case9_same_id_completed_block() {
    echo "=== Case 9: 同 ID + 別 status (🔲 のみ) → BLOCK ==="
    local list="$TMP_ROOT/list9.md"
    cat > "$list" <<'EOF'
| 1 | 🔲 | **Task: foo** | overview | [foo.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 9.1: 重複起動防止 BLOCK"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 9.1: 重複起動 BLOCK 失敗 (exit=$exit_code, out=$out)")
        printf "  FAIL: %s\n" "Case 9.1 (exit=$exit_code)"
    fi
}

printf "===== new-task-batch-update-smoke (task-34 Step 4, 9 cases) =====\n\n"

case1_update_mode
case2_append_mode
case3_batch_integrity_n3
case3_5_performance_n10
case4_id_diff_slug_pending_block
case5_slug_substring_false_match
case6_status_mixed_block
case7_regex_injection_slug
case8_no_trailing_eol_append
case9_same_id_completed_block

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
    printf "Failed cases:\n"
    for c in "${FAILED_CASES[@]}"; do
        printf "  - %s\n" "$c"
    done
    printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
    exit 1
fi

printf "\nsummary: %d/%d PASS\n" "$PASS" "$TOTAL"
exit 0
