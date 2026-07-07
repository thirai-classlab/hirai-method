#!/usr/bin/env bash
# ui-contract-smoke.sh — task-98 Step 5 smoke for ui-contract.sh + cross-file-contract-check.sh
#
# 設計起源:
#   docs/tasks/task-98-ui-contract-hook-cross-file-check.md
#   docs/draft/install-immediately-usable-redesign-20260618.md §3 I4 / §5 P3-1
#
# 対象:
#   .claude/hooks/ui-contract.sh (PostToolUse Edit/Write)
#   .claude/scripts/cross-file-contract-check.sh
#
# 検証範囲 (6 case A-F):
#   Case A: id mismatch fixture       — button.tsx id="submit" と index.html
#           querySelector("#save") で drift → cross-file-contract-check.sh が drift 検出 (rc=1)
#   Case B: symbol drift fixture       — import { Foo } from './bar' で bar.tsx に Foo export 不在
#           → drift 検出 (rc=1)
#   Case C: hook advisory 経路 (drift なし) — UI file 変更で hook が cross-file-check を呼び、
#           drift ゼロ (matched contract) なら hook stderr に WARN が出ない
#           (check_script は $TMP_ROOT/.claude/scripts/ に配置済 = fail-open 分岐を通らない)
#   Case D: bypass env ECC_UI_CONTRACT_OFF=1  — hook が cross-file-check を呼ばず即 PASS
#   Case E: fail-open                   — cross-file-contract-check.sh 不在時に hook が exit 0
#   Case F: hook advisory 経路 (drift 検出) — UI file 変更で hook が cross-file-check を呼び、
#           drift 検出時 hook stderr に emit_warn 経由 WARN が出る (rc=0 advisory 維持)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs)
#   - tmp project root を /tmp/ に配置、hook は PostToolUse なので empty JSON `{}` 出力必須
#   - hook は常に exit 0 (fail-open advisory)、drift 検出は stderr WARN として表面化
#
# 実行:
#   bash .claude/tests/ui-contract-smoke.sh
#
# 終了コード:
#   0 = 6/6 PASS / 1 = 1 件以上 FAIL

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/ui-contract.sh"
CHECK_SCRIPT="$REPO_ROOT/.claude/scripts/cross-file-contract-check.sh"

# clean env
unset ECC_UI_CONTRACT_OFF
unset HC_FEATURE_UI_CONTRACT_ENABLED
unset HC_UI_CONTRACT_EXTENSIONS
unset HC_CONTRACT_CHECK_ROOT
unset HC_CONTRACT_CONTRACTS_DIR

# tmp project root (fixture 配置用)
TMP_ROOT="$(mktemp -d /tmp/ui-contract-smoke.XXXXXX)"
mkdir -p "$TMP_ROOT/.git" "$TMP_ROOT/src" "$TMP_ROOT/.claude/contracts" "$TMP_ROOT/.claude/scripts"

# ui-contract.sh は project root 直下の .claude/scripts/cross-file-contract-check.sh を
# `resolve_project_root` (= run_hook 内 cwd = $TMP_ROOT に fallback) で解決する。
# Case C / F の advisory 経路 (hook → check → drift 判定 → WARN) を真に exercise するため、
# check script を $TMP_ROOT/.claude/scripts/ に配置する。
# 配置しないと Case C は line 113 fail-open 分岐で trivially PASS してしまい、
# 実 advisory 経路の regression を検出できない (task-98 finding #1)。
cp "$CHECK_SCRIPT" "$TMP_ROOT/.claude/scripts/cross-file-contract-check.sh"
chmod +x "$TMP_ROOT/.claude/scripts/cross-file-contract-check.sh" 2>/dev/null || true

trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0
FAILED_CASES=()

# hook input JSON (PostToolUse Edit/Write)
hook_input() {
  local tool="$1"
  local fp="$2"
  TOOL="$tool" FP="$fp" python3 -c '
import json, os
print(json.dumps({
    "tool_name": os.environ["TOOL"],
    "tool_input": {"file_path": os.environ["FP"]}
}))
'
}

# hook を tmp project root cwd で実行 (resolve_project_root が pwd fallback)
run_hook() {
  local tool="$1"
  local fp="$2"
  shift 2
  # 残りの引数は env 設定 (KEY=VALUE 形式)
  (
    cd "$TMP_ROOT" || exit 99
    if [ $# -gt 0 ]; then
      hook_input "$tool" "$fp" | env "$@" bash "$HOOK"
    else
      hook_input "$tool" "$fp" | bash "$HOOK"
    fi
  )
}

# === Case A: id mismatch fixture → cross-file-check が drift 検出 (rc=1) ===
caseA_id_mismatch() {
  local label="Case A: id mismatch (button.tsx#submit vs index.html #save) → drift 検出 rc=1"

  # fixture: button.tsx で id="submit" 定義、index.html で querySelector("#save") 参照 (drift)
  mkdir -p "$TMP_ROOT/src/caseA"
  cat > "$TMP_ROOT/src/caseA/button.tsx" <<'TSX'
export function Button() {
  return <button id="submit">Submit</button>;
}
TSX
  cat > "$TMP_ROOT/src/caseA/index.html" <<'HTML'
<html><body><div id="root"></div>
<script>
  const btn = document.querySelector("#save");
  btn && btn.addEventListener('click', () => {});
</script>
</body></html>
HTML

  local out rc=0
  out=$(HC_CONTRACT_CHECK_ROOT="$TMP_ROOT" bash "$CHECK_SCRIPT" --file "$TMP_ROOT/src/caseA/button.tsx" 2>&1) || rc=$?

  # drift ("id 'save' referenced ... but not defined") が 1 件以上 + rc=1
  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE "id 'save' referenced"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc out='$out')")
    printf "  FAIL: %s (rc=%d expected 1 with drift 'id save referenced')\n" "$label" "$rc"
    printf "    out: %s\n" "$out"
  fi
}

# === Case B: symbol drift fixture → import 未 export で drift 検出 ===
caseB_symbol_drift() {
  local label="Case B: symbol drift (import Foo from './bar' but bar.tsx no Foo export) → drift 検出 rc=1"

  mkdir -p "$TMP_ROOT/src/caseB"
  cat > "$TMP_ROOT/src/caseB/main.tsx" <<'TSX'
import { Foo } from './bar';
export function App() { return <Foo />; }
TSX
  cat > "$TMP_ROOT/src/caseB/bar.tsx" <<'TSX'
export const Baz = 42;
export function Qux() { return null; }
TSX

  local out rc=0
  out=$(HC_CONTRACT_CHECK_ROOT="$TMP_ROOT" bash "$CHECK_SCRIPT" --file "$TMP_ROOT/src/caseB/main.tsx" 2>&1) || rc=$?

  if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qE "symbol 'Foo' imported.*not exported"; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc out='$out')")
    printf "  FAIL: %s (rc=%d expected 1 with drift 'symbol Foo imported ... not exported')\n" "$label" "$rc"
    printf "    out: %s\n" "$out"
  fi
}

# === Case C: hook が UI file で発火 + drift なし → hook exit 0 + 空 stdout `{}` ===
# (visual artifact 不在確認は hook advisory 経路のため WARN の absence を確認)
caseC_hook_fires_no_drift() {
  local label="Case C: hook fires on UI file + no drift → exit 0, stdout={}, no WARN"

  # fixture: 一致した id contract (button.tsx / index.html 両方 id="submit")
  mkdir -p "$TMP_ROOT/src/caseC"
  cat > "$TMP_ROOT/src/caseC/button.tsx" <<'TSX'
export function Button() {
  return <button id="submit">Submit</button>;
}
TSX
  cat > "$TMP_ROOT/src/caseC/index.html" <<'HTML'
<html><body>
<button id="submit">SubmitFallback</button>
<script>
  const btn = document.querySelector("#submit");
</script>
</body></html>
HTML

  local out rc=0 stderr_file
  stderr_file="$TMP_ROOT/caseC_stderr.log"
  # hook 実行 (PostToolUse)
  out=$(run_hook Edit "$TMP_ROOT/src/caseC/button.tsx" 2>"$stderr_file") || rc=$?

  local stderr_content
  stderr_content=$(cat "$stderr_file" 2>/dev/null || true)

  # 検証:
  #   - rc == 0
  #   - stdout に `{}` (empty JSON) 含む
  #   - stderr に "[ui-contract] drift detail" or "[block-message] WARN why: UI cross-file" が **含まれない** (drift なし)
  local drift_seen=0
  if printf '%s' "$stderr_content" | grep -qE '(\[ui-contract\] drift detail|\[block-message\] WARN why: UI cross-file)'; then
    drift_seen=1
  fi

  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '^\{\}$' && [ "$drift_seen" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc stdout='$out' drift_seen=$drift_seen)")
    printf "  FAIL: %s (rc=%d stdout='%s' stderr='%s')\n" "$label" "$rc" "$out" "$stderr_content"
  fi
}

# === Case D: bypass env ECC_UI_CONTRACT_OFF=1 → hook 即 skip、drift 無視 ===
caseD_bypass_env() {
  local label="Case D: ECC_UI_CONTRACT_OFF=1 on drift fixture → hook exit 0, no drift WARN"

  # drift 発生する fixture (caseA と同構造) を配置
  mkdir -p "$TMP_ROOT/src/caseD"
  cat > "$TMP_ROOT/src/caseD/button.tsx" <<'TSX'
export function Button() { return <button id="submit">S</button>; }
TSX
  cat > "$TMP_ROOT/src/caseD/index.html" <<'HTML'
<html><body>
<script>
  const btn = document.querySelector("#missing_id");
</script>
</body></html>
HTML

  local out rc=0 stderr_file
  stderr_file="$TMP_ROOT/caseD_stderr.log"
  out=$(run_hook Edit "$TMP_ROOT/src/caseD/button.tsx" ECC_UI_CONTRACT_OFF=1 2>"$stderr_file") || rc=$?

  local stderr_content
  stderr_content=$(cat "$stderr_file" 2>/dev/null || true)

  local drift_seen=0
  if printf '%s' "$stderr_content" | grep -qE '(\[ui-contract\] drift detail|\[block-message\] WARN why: UI cross-file)'; then
    drift_seen=1
  fi

  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '^\{\}$' && [ "$drift_seen" -eq 0 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc stdout='$out' drift_seen=$drift_seen)")
    printf "  FAIL: %s (rc=%d stdout='%s' stderr='%s')\n" "$label" "$rc" "$out" "$stderr_content"
  fi
}

# === Case E: fail-open (cross-file-contract-check.sh 不在) → hook exit 0 ===
caseE_fail_open() {
  local label="Case E: cross-file-contract-check.sh 不在 → hook fail-open (exit 0, stdout={})"

  # tmp .claude を作り hook だけ配置 (check script 不在の isolated 環境)
  local iso_root
  iso_root="$(mktemp -d /tmp/ui-contract-smoke-iso.XXXXXX)"
  mkdir -p "$iso_root/.git" "$iso_root/.claude/hooks/lib" "$iso_root/.claude/scripts" "$iso_root/src"
  # hook + 必須 lib のみコピー、check script は配置しない
  cp "$REPO_ROOT/.claude/hooks/ui-contract.sh" "$iso_root/.claude/hooks/"
  # lib は簡易 stub (config-loader なしでも fail-open 動作)
  # UI fixture 配置 (実 file が必要 = jq path 判定を通すため)
  mkdir -p "$iso_root/src/caseE"
  cat > "$iso_root/src/caseE/button.tsx" <<'TSX'
export function Button() { return <button id="x">X</button>; }
TSX

  local out rc=0 stderr_file
  stderr_file="$iso_root/caseE_stderr.log"
  out=$(cd "$iso_root" && hook_input Edit "$iso_root/src/caseE/button.tsx" | bash "$iso_root/.claude/hooks/ui-contract.sh" 2>"$stderr_file") || rc=$?

  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '^\{\}$'; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc stdout='$out')")
    printf "  FAIL: %s (rc=%d stdout='%s' stderr='%s')\n" "$label" "$rc" "$out" "$(cat "$stderr_file" 2>/dev/null)"
  fi

  rm -rf "$iso_root"
}

# === Case F: hook が UI file で発火 + drift 検出 → hook exit 0 + stdout `{}` + stderr WARN ===
# (advisory 経路の WARN emission 全 path を exercise: hook → check → drift 検出 → emit_warn → stderr)
caseF_hook_fires_drift_detected() {
  local label="Case F: hook fires on UI file + drift detected → exit 0, stdout={}, stderr WARN"

  # fixture: id 不一致 (button.tsx id="submit" vs index.html querySelector("#missing"))
  # → cross-file-contract-check.sh が rc=1 を返し、hook が emit_warn 経由で stderr に WARN
  mkdir -p "$TMP_ROOT/src/caseF"
  cat > "$TMP_ROOT/src/caseF/button.tsx" <<'TSX'
export function Button() {
  return <button id="submit">Submit</button>;
}
TSX
  cat > "$TMP_ROOT/src/caseF/index.html" <<'HTML'
<html><body>
<script>
  const btn = document.querySelector("#missing");
</script>
</body></html>
HTML

  local out rc=0 stderr_file
  stderr_file="$TMP_ROOT/caseF_stderr.log"
  out=$(run_hook Edit "$TMP_ROOT/src/caseF/button.tsx" 2>"$stderr_file") || rc=$?

  local stderr_content
  stderr_content=$(cat "$stderr_file" 2>/dev/null || true)

  # 検証:
  #   - rc == 0 (advisory: BLOCK しない)
  #   - stdout に `{}` (empty JSON) 含む
  #   - stderr に "[block-message] WARN why: UI cross-file" (emit_warn 経路) 含む
  #   - stderr に "[ui-contract] drift detail" (詳細出力) 含む
  local warn_seen=0 detail_seen=0
  if printf '%s' "$stderr_content" | grep -qE '\[block-message\] WARN why: UI cross-file'; then
    warn_seen=1
  fi
  if printf '%s' "$stderr_content" | grep -qE '\[ui-contract\] drift detail'; then
    detail_seen=1
  fi

  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE '^\{\}$' \
     && [ "$warn_seen" -eq 1 ] && [ "$detail_seen" -eq 1 ]; then
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    FAILED_CASES+=("$label (rc=$rc stdout='$out' warn_seen=$warn_seen detail_seen=$detail_seen)")
    printf "  FAIL: %s (rc=%d stdout='%s' warn_seen=%d detail_seen=%d stderr='%s')\n" \
      "$label" "$rc" "$out" "$warn_seen" "$detail_seen" "$stderr_content"
  fi
}

printf "===== ui-contract-smoke (task-98 Step 5, 6 cases A-F) =====\n\n"

caseA_id_mismatch
caseB_symbol_drift
caseC_hook_fires_no_drift
caseD_bypass_env
caseE_fail_open
caseF_hook_fires_drift_detected

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
