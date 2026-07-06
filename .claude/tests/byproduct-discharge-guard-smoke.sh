#!/usr/bin/env bash
# byproduct-discharge-guard-smoke.sh — task-94 regression smoke for
#   .claude/hooks/byproduct-discharge-guard.sh (Stop hook)
#
# 目的 (task-94 P2-3 DoD):
#   Stop hook は task-94 で `emit_block_stop` (§3.1 event 別契約) 経由に移行する。
#   emit_block_stop は他の block variant と異なり **JSON stdout を出力しない**
#   ({decision:"block"} の Stop semantic 誤発火を実装層で排除)。本 smoke は
#   migration 前後を通じて維持されるべき semantic 契約を機械検証する。
#
# 検証観点 (finding-1 CRIT):
#   (a) BLOCK path が exit code 2 で終了する
#   (b) BLOCK 時に stdout は空 (JSON 非出力) — separate fd capture で立証
#   (c) BLOCK 時に stderr に 4 概念要素 (why/fix/silence/docs) が含まれる
#   (d) bypass env ECC_BYPASS_DISCHARGE_GUARD=1 で exit 0 に short-circuit
#
# 実行:
#   bash .claude/tests/byproduct-discharge-guard-smoke.sh
#
# 終了コード:
#   0 = 4/4 PASS / 1 = 1 件以上 FAIL
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に作って独立 docs ツリーを配置
#   - separate stdout/stderr fd capture で JSON stdout 非出力を厳格検証

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/byproduct-discharge-guard.sh"

if [ ! -f "$HOOK" ]; then
  printf 'FAIL: hook not found: %s\n' "$HOOK" >&2
  exit 1
fi

# clean env (前 session 由来の bypass state を排除)
unset ECC_BYPASS_DISCHARGE_GUARD
unset ECC_BYPASS_REASON
unset HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED

# feature toggle は smoke 全体で強制 ON (harness-config.yml default true 前提だが、
# consuming repo で feature OFF になっていても本 smoke は semantic 契約検証のため ON 固定)
export HC_FEATURE_BYPRODUCT_DISCHARGE_ENABLED=true

TMP_ROOT="$(mktemp -d /tmp/byproduct-discharge-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" "$TMP_ROOT/docs/tasks"
# hook は _project_dir/.claude/hooks/lib/next-actions-parser.sh 等を参照するため、
# 実 repo の .claude ツリーを symlink で共有 (tmp 側は docs/ のみ独立させる)。
ln -s "$REPO_ROOT/.claude" "$TMP_ROOT/.claude"

trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# === fixture: 🔴 未処理 entry 1 件を含む next-actions.md ===
cat > "$TMP_ROOT/docs/tasks/next-actions.md" <<'EOF'
# next-actions.md — 副産物 entry registry

## エントリ一覧

| # | 起案日 | タイトル | 発生源 | 緊急度 | 推奨処理 | 処理結果 |
|:---:|---|---|---|:---:|---|---|
| 1 | 2026-07-06 | smoke fixture 🔴 entry | task-94 smoke | 🔴 | draft 起こし | — |

## 処理履歴

(履歴セクション、対象外)
EOF

# === helper: hook を tmp project root cwd で separate fd capture 実行 ===
# stdout_file / stderr_file / rc の 3 出力
# HC_PROJECT_ROOT env で project root を明示注入 (project-root.sh 優先順位 1)
# — 空の .git dir では git rev-parse が実 repo root を返してしまうため必須。
run_hook_captured() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  # 残りの引数は env 設定 (KEY=VALUE 形式)
  local rc=0
  (
    cd "$TMP_ROOT" || exit 99
    # Stop hook は stdin 消費するので空を渡す。fd 1 と fd 2 を別 file に分離捕捉。
    if [ $# -gt 0 ]; then
      env HC_PROJECT_ROOT="$TMP_ROOT" "$@" bash "$HOOK" < /dev/null > "$stdout_file" 2> "$stderr_file"
    else
      env HC_PROJECT_ROOT="$TMP_ROOT" bash "$HOOK" < /dev/null > "$stdout_file" 2> "$stderr_file"
    fi
  ) || rc=$?
  return "$rc"
}

# === Case A: 🔴 未処理あり → BLOCK (exit 2) ===
caseA_block_exit2() {
  local label="Case A: 🔴 未処理 entry あり → BLOCK (exit 2)"
  local stdout_f="$TMP_ROOT/caseA.stdout"
  local stderr_f="$TMP_ROOT/caseA.stderr"
  local rc=0
  run_hook_captured "$stdout_f" "$stderr_f" || rc=$?

  if [ "$rc" -eq 2 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc expected 2)")
    printf "  FAIL: %s (rc=%d expected 2)\n" "$label" "$rc"
    printf "    stderr: %s\n" "$(head -c 200 "$stderr_f" 2>/dev/null || true)"
  fi
}

# === Case B: BLOCK 時 stdout 空 (JSON stdout 非出力) — separate fd capture ===
# emit_block_stop 契約: Stop hook では `{decision:"block"}` の主 tool 停止阻止
# semantic 誤発火を回避するため JSON stdout emission を明示 disable する。
# separate fd capture で stdout=empty を byte 数で厳格検証。
caseB_stdout_empty() {
  local label="Case B: BLOCK 時 stdout が空 (JSON 非出力 semantic 保証)"
  local stdout_f="$TMP_ROOT/caseB.stdout"
  local stderr_f="$TMP_ROOT/caseB.stderr"
  local rc=0
  run_hook_captured "$stdout_f" "$stderr_f" || rc=$?

  # exit 2 は Case A で検証済、ここは stdout のみを厳格検証
  local size
  size=$(wc -c < "$stdout_f" 2>/dev/null | tr -d ' ')
  size="${size:-0}"

  # JSON literal `{"decision":"block"` の混入も検出 (byte 0 でなくても JSON 出力
  # が完全欠落していれば post-migration 契約は満たすが、Stop hook では
  # emission そのものが禁止 = byte 0 が正)
  if [ "$size" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s (stdout size=0 bytes)\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (stdout size=$size, expected 0)")
    printf "  FAIL: %s (stdout size=%s expected 0)\n" "$label" "$size"
    printf "    stdout preview: %s\n" "$(head -c 200 "$stdout_f" 2>/dev/null || true)"
  fi
}

# === Case C: BLOCK 時 stderr が 4 概念要素 (why/fix/silence/docs) を含む ===
# task-94 §3.1 emit_block_stop 契約: stderr 4 行 label (why: / fix: / silence: / docs:)
# ただし migration 前は自然文 (「BLOCK: ...」/「推奨アクション:」/「Bypass:」/「詳細:」)
# のため、概念単位で寛容 assertion (BLOCK + fix 系 + bypass 系 + docs 系 の 4 markers)。
caseC_stderr_labels() {
  local label="Case C: BLOCK 時 stderr が 4 概念要素 (why/fix/silence/docs) を含む"
  local stdout_f="$TMP_ROOT/caseC.stdout"
  local stderr_f="$TMP_ROOT/caseC.stderr"
  local rc=0
  run_hook_captured "$stdout_f" "$stderr_f" || rc=$?

  local missing=""
  # (1) why 概念: post-migration "why:" or pre-migration "BLOCK"
  if ! grep -qE '(^\[block-message\].*why:|BLOCK)' "$stderr_f" 2>/dev/null; then
    missing="${missing}why "
  fi
  # (2) fix 概念: post-migration "fix:" or pre-migration "推奨アクション"
  if ! grep -qE '(^\[block-message\].*fix:|推奨アクション|/new-draft|/new-task)' "$stderr_f" 2>/dev/null; then
    missing="${missing}fix "
  fi
  # (3) silence 概念: post-migration "silence:" or pre-migration "Bypass" / bypass env 名
  if ! grep -qE '(^\[block-message\].*silence:|Bypass|ECC_BYPASS_DISCHARGE_GUARD)' "$stderr_f" 2>/dev/null; then
    missing="${missing}silence "
  fi
  # (4) docs 概念: post-migration "docs:" or pre-migration "詳細:" / rule path
  if ! grep -qE '(^\[block-message\].*docs:|詳細:|next-actions\.md|development-process\.md)' "$stderr_f" 2>/dev/null; then
    missing="${missing}docs "
  fi

  if [ -z "$missing" ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (missing labels: $missing)")
    printf "  FAIL: %s (missing: %s)\n" "$label" "$missing"
    printf "    stderr preview: %s\n" "$(head -c 300 "$stderr_f" 2>/dev/null || true)"
  fi
}

# === Case D: ECC_BYPASS_DISCHARGE_GUARD=1 で exit 0 short-circuit ===
caseD_bypass_env() {
  local label="Case D: ECC_BYPASS_DISCHARGE_GUARD=1 → exit 0 (bypass short-circuit)"
  local stdout_f="$TMP_ROOT/caseD.stdout"
  local stderr_f="$TMP_ROOT/caseD.stderr"
  local rc=0
  run_hook_captured "$stdout_f" "$stderr_f" ECC_BYPASS_DISCHARGE_GUARD=1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc expected 0)")
    printf "  FAIL: %s (rc=%d expected 0)\n" "$label" "$rc"
    printf "    stderr preview: %s\n" "$(head -c 200 "$stderr_f" 2>/dev/null || true)"
  fi
}

# === 実行 ===
printf '=== byproduct-discharge-guard-smoke (task-94 P2-3) ===\n'
caseA_block_exit2
caseB_stdout_empty
caseC_stderr_labels
caseD_bypass_env

TOTAL=$((PASS + FAIL))
printf '\n---\n'
printf 'Result: %d/%d PASS\n' "$PASS" "$TOTAL"

if [ "$FAIL" -gt 0 ]; then
  printf '\nFailed cases:\n'
  for c in "${FAILED_CASES[@]}"; do
    printf '  - %s\n' "$c"
  done
  exit 1
fi

exit 0
