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
#   Case 7 (H-01 + H-03): regex injection (slug 特殊文字) + backslash 保護
#   Case 8 (H-04): 末尾改行なし list.md への append で前行結合しない
#   Case 9 (重複起動防止): 同 ID + 別 status (🔲 のみ) → BLOCK
#
#   iter3 追加 (MUST FIX 7 件):
#   Case 9b (PR-001): 🔄 status → BLOCK
#   Case 9c (PR-001): ✅ status → BLOCK
#   Case 10 (QA-C01/H-RC-01): parallel race 3 subprocess 並列実行で 📝 残存 0 件
#   Case 11 (QA-C02): leading zero id ("01" vs "1") で silent duplicate 防止
#
#   iter4 追加 (CR-001 + MED-001):
#   Case 11.5 (CR-001): 18 桁超 id (overflow) → BLOCK exit 2 (silent APPEND corruption 防止)
#   Case 11.6 (MED-001): CR (\r) only row_content → BLOCK exit 2 (CR validation 拡張)
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

# === Case 7: H-01 regex injection + H-03 backslash 保護 ===
case7_extended_regex_and_backslash() {
    echo "=== Case 7 (H-01 + H-03): regex injection + backslash 保護 ==="
    # 7.1-7.3: slug に '.' が含まれる場合、escape されないと '.' が任意文字に match して誤動作
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

    # 7.3 (iter3 TDD-002): backslash 保護 direct assertion
    # row_content に backslash + ampersand を含めて update、awk ENVIRON 経由で
    # backslash 保持 + ampersand 保持を verify
    local list2="$TMP_ROOT/list7b.md"
    cat > "$list2" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local backslash_row='| 1 | 🔲 | **Task: foo** | overview \backslash & ampersand | [foo.md] |'
    bash "$HELPER" update_or_append_task_row 1 foo "$backslash_row" "$list2" >/dev/null

    local content
    content=$(cat "$list2")

    if printf '%s' "$content" | grep -qF '\backslash'; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 7.3: backslash 保持"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 7.3: backslash 消失 (content: $content)")
        printf "  FAIL: %s\n" "Case 7.3: backslash 消失"
    fi

    if printf '%s' "$content" | grep -qF '& ampersand'; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 7.4: ampersand 保持"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 7.4: ampersand 消失 (content: $content)")
        printf "  FAIL: %s\n" "Case 7.4: ampersand 消失"
    fi
}

# === Case 8: H-04 末尾改行欠落 append ===
case8_no_trailing_eol_append() {
    echo "=== Case 8 (H-04): 末尾改行なし list.md への append ==="
    local list="$TMP_ROOT/list8.md"
    # printf で末尾改行なしを作る
    printf '%s' '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' > "$list"

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
    echo "=== Case 9: 同 ID + 別 status (🔲) → BLOCK ==="
    local list="$TMP_ROOT/list9.md"
    cat > "$list" <<'EOF'
| 1 | 🔲 | **Task: foo** | overview | [foo.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 9.1: 重複起動防止 BLOCK (🔲)"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 9.1: 重複起動 BLOCK 失敗 (exit=$exit_code, out=$out)")
        printf "  FAIL: %s\n" "Case 9.1 (exit=$exit_code)"
    fi
}

# === Case 9b: iter3 PR-001 同 ID + 🔄 status → BLOCK ===
case9b_in_progress_status_block() {
    echo "=== Case 9b (iter3 PR-001): 同 ID + 🔄 status → BLOCK ==="
    local list="$TMP_ROOT/list9b.md"
    cat > "$list" <<'EOF'
| 1 | 🔄 | **Task: foo** | overview | [foo.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    case_assert "Case 9b.1: 🔄 status BLOCK exit 1" "1" "$exit_code"
    case_assert_contains "Case 9b.2: BLOCK message 含む" "BLOCK" "$out"

    local lc
    lc=$(wc -l < "$list" | tr -d ' ')
    case_assert "Case 9b.3: list.md 1 行維持" "1" "$lc"
}

# === Case 9c: iter3 PR-001 同 ID + ✅ status → BLOCK ===
case9c_completed_status_block() {
    echo "=== Case 9c (iter3 PR-001): 同 ID + ✅ status → BLOCK ==="
    local list="$TMP_ROOT/list9c.md"
    cat > "$list" <<'EOF'
| 1 | ✅ | **Task: foo** | overview | [foo.md] |
EOF
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row 1 foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" 2>&1)
    exit_code=$?

    case_assert "Case 9c.1: ✅ status BLOCK exit 1" "1" "$exit_code"
    case_assert_contains "Case 9c.2: BLOCK message 含む" "BLOCK" "$out"

    local lc
    lc=$(wc -l < "$list" | tr -d ' ')
    case_assert "Case 9c.3: list.md 1 行維持" "1" "$lc"
}

# === Case 10: iter3 QA-C01/H-RC-01 parallel race 3 subprocess ===
case10_parallel_race_3_processes() {
    echo "=== Case 10 (iter3 QA-C01/H-RC-01): parallel race 3 subprocess ==="
    local list="$TMP_ROOT/list10.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: a** | overview | [a.md] |
| 2 | 📝 | **Task: b** | overview | [b.md] |
| 3 | 📝 | **Task: c** | overview | [c.md] |
EOF
    # 3 並列で同時 update
    bash "$HELPER" update_or_append_task_row 1 a '| 1 | 🔲 | **Task: a** | overview | [a.md] |' "$list" >/dev/null 2>&1 &
    bash "$HELPER" update_or_append_task_row 2 b '| 2 | 🔲 | **Task: b** | overview | [b.md] |' "$list" >/dev/null 2>&1 &
    bash "$HELPER" update_or_append_task_row 3 c '| 3 | 🔲 | **Task: c** | overview | [c.md] |' "$list" >/dev/null 2>&1 &
    wait

    local pending_count
    pending_count=$(grep -cF "📝" "$list" 2>/dev/null || true)
    case_assert "Case 10.1: 3 並列 race 後 📝 残存 0 件" "0" "$pending_count"

    local box_count
    box_count=$(grep -cF "🔲" "$list" 2>/dev/null || true)
    case_assert "Case 10.2: 3 並列 race 後 🔲 3 件" "3" "$box_count"

    local total_lines
    total_lines=$(wc -l < "$list" | tr -d ' ')
    case_assert "Case 10.3: 行数 3 維持" "3" "$total_lines"
}

# === Case 11: iter3 QA-C02 leading zero id duplicate 防止 ===
case11_leading_zero_id_normalization() {
    echo "=== Case 11 (iter3 QA-C02): leading zero id 数値正規化 ==="
    # list.md に "| 1 | 📝 |" 行を作り、raw_id="01" で呼び出し → 同 id=1 として update
    # (旧実装は "01" を string で grep "^| 01 |" として APPEND してしまい silent duplicate を起こす)
    local list="$TMP_ROOT/list11.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    bash "$HELPER" update_or_append_task_row "01" foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list" >/dev/null

    # 行数 1 維持 (APPEND されていない、UPDATE された)
    local total
    total=$(grep -cE "^\| [0-9]+ \|" "$list" || true)
    case_assert "Case 11.1: 行数 1 維持 (silent duplicate なし)" "1" "$total"

    # status 🔲 に変化
    if grep -qE "^\| 1 \| 🔲" "$list"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "Case 11.2: status 🔲 へ update (raw_id='01' → id=1)"
    else
        FAIL=$((FAIL + 1))
        FAILED_CASES+=("Case 11.2: leading zero update 失敗 (content: $(cat "$list"))")
        printf "  FAIL: %s\n" "Case 11.2"
    fi

    # 11.3: 非数値 id → error (exit 2)
    local list_err="$TMP_ROOT/list11_err.md"
    cat > "$list_err" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local exit_code
    bash "$HELPER" update_or_append_task_row "abc" foo '| 1 | 🔲 | **Task: foo** | overview | [foo.md] |' "$list_err" >/dev/null 2>&1
    exit_code=$?
    case_assert "Case 11.3: 非数値 id → exit 2" "2" "$exit_code"

    # 11.4: row_content 改行 → error (exit 2)
    local list_nl="$TMP_ROOT/list11_nl.md"
    cat > "$list_nl" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local nl_row
    nl_row=$(printf '| 1 | 🔲 | **Task: foo** | line1\nline2 | [foo.md] |')
    bash "$HELPER" update_or_append_task_row 1 foo "$nl_row" "$list_nl" >/dev/null 2>&1
    exit_code=$?
    case_assert "Case 11.4: row_content 改行 → exit 2" "2" "$exit_code"
}

# === Case 11.5: iter4 CR-001 18 桁超 id (overflow) → BLOCK ===
case11_5_id_overflow_reject() {
    echo "=== Case 11.5 (iter4 CR-001): 18 桁超 id (overflow) → BLOCK exit 2 ==="
    local list="$TMP_ROOT/list11_5.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF

    # 26 桁 id (raw_id="99999999999999999999999999") → exit 2
    # 旧実装は $((10#$raw_id)) で signed 64-bit overflow → 負数化 → grep "^| -... |" 0 hit
    # → APPEND mode で同 ID で 2 行混入の silent corruption (CR-001)
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row \
        "99999999999999999999999999" foo "| 1 | 🔲 | **Task: foo** | overview | [foo.md] |" "$list" 2>&1)
    exit_code=$?
    case_assert "Case 11.5.1: 26 桁 id (overflow) → exit 2" "2" "$exit_code"
    case_assert_contains "Case 11.5.2: ERROR message 含む '18 桁'" "18 桁" "$out"

    # list.md 未変更確認 (overflow による silent APPEND corruption 防止)
    local line_count
    line_count=$(wc -l < "$list" | tr -d ' ')
    case_assert "Case 11.5.3: list.md 1 行維持 (silent APPEND なし)" "1" "$line_count"

    # 19 桁 (signed 64-bit 境界、9223372036854775807 = 19 桁 8e+18) → BLOCK
    local list_19="$TMP_ROOT/list11_5_19.md"
    cat > "$list_19" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local exit_19
    bash "$HELPER" update_or_append_task_row "1234567890123456789" foo \
        "| 1 | 🔲 | **Task: foo** | overview | [foo.md] |" "$list_19" >/dev/null 2>&1
    exit_19=$?
    case_assert "Case 11.5.4: 19 桁 id (signed 64-bit 境界) → exit 2" "2" "$exit_19"

    # 18 桁 (signed 64-bit 範囲内) → 正常動作 (BLOCK しない)
    # raw_id="123456789012345678" (18 桁、9.22e18 未満) → id=123456789012345678 へ正規化
    # list.md に id=123456789012345678 行がないので APPEND される (exit 0)
    local list_18="$TMP_ROOT/list11_5_18.md"
    cat > "$list_18" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local exit_18
    bash "$HELPER" update_or_append_task_row "123456789012345678" bar \
        "| 123456789012345678 | 🔲 | **Task: bar** | overview | [bar.md] |" "$list_18" >/dev/null 2>&1
    exit_18=$?
    case_assert "Case 11.5.5: 18 桁 id (境界内) → exit 0 (overflow しない)" "0" "$exit_18"

    # leading zero stripping 後の長さで判定 (確認: "001" (3 桁 raw) → "1" (1 桁) で OK)
    local list_lz="$TMP_ROOT/list11_5_lz.md"
    cat > "$list_lz" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local exit_lz
    bash "$HELPER" update_or_append_task_row "001" foo \
        "| 1 | 🔲 | **Task: foo** | overview | [foo.md] |" "$list_lz" >/dev/null 2>&1
    exit_lz=$?
    case_assert "Case 11.5.6: leading zero '001' → exit 0 (stripped 1 桁判定)" "0" "$exit_lz"
}

# === Case 11.6: iter4 MED-001 CR-only row_content → BLOCK ===
case11_6_cr_only_row_content_reject() {
    echo "=== Case 11.6 (iter4 MED-001): CR (\r) row_content → BLOCK exit 2 ==="
    local list="$TMP_ROOT/list11_6.md"
    cat > "$list" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF

    # row_content に CR (`\r`) 含む → exit 2
    # 旧実装は *$'\n'* のみ検出、CR-only は通過 → list.md に \r 混入 (cat -A で ^M 可視化)
    local out exit_code
    out=$(bash "$HELPER" update_or_append_task_row \
        1 foo $'| 1 | 🔲 | **Task: foo** | overview\rwith CR | [foo.md] |' "$list" 2>&1)
    exit_code=$?
    case_assert "Case 11.6.1: CR row_content → exit 2" "2" "$exit_code"
    case_assert_contains "Case 11.6.2: ERROR message 含む 'LF/CR'" "LF/CR" "$out"

    # list.md に CR 混入なし (未変更確認)
    local cr_count
    cr_count=$(tr -cd '\r' < "$list" | wc -c | tr -d ' ')
    case_assert "Case 11.6.3: list.md に CR 混入なし" "0" "$cr_count"

    # CRLF (混在) row_content も BLOCK
    local list_crlf="$TMP_ROOT/list11_6_crlf.md"
    cat > "$list_crlf" <<'EOF'
| 1 | 📝 | **Task: foo** | overview | [foo.md] |
EOF
    local exit_crlf
    bash "$HELPER" update_or_append_task_row \
        1 foo $'| 1 | 🔲 | **Task: foo** | overview\r\nwith CRLF | [foo.md] |' "$list_crlf" >/dev/null 2>&1
    exit_crlf=$?
    case_assert "Case 11.6.4: CRLF row_content → exit 2" "2" "$exit_crlf"
}

printf "===== new-task-batch-update-smoke (task-34 Step 4 iter4, 16 cases) =====\n\n"

case1_update_mode
case2_append_mode
case3_batch_integrity_n3
case3_5_performance_n10
case4_id_diff_slug_pending_block
case5_slug_substring_false_match
case6_status_mixed_block
case7_extended_regex_and_backslash
case8_no_trailing_eol_append
case9_same_id_completed_block
case9b_in_progress_status_block
case9c_completed_status_block
case10_parallel_race_3_processes
case11_leading_zero_id_normalization
case11_5_id_overflow_reject
case11_6_cr_only_row_content_reject

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
