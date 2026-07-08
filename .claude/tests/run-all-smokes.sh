#!/usr/bin/env bash
# run-all-smokes.sh — 統合 smoke runner (task-74 Step 4a)
#
# 役割:
#   .claude/tests/*smoke*.sh を全件発見し順次実行、各々の PASS/FAIL/SKIP を集計する。
#   5 種別でグルーピング表示し、expected-fail manifest に登録された smoke は
#   EXPECTED-FAIL として別集計する。UNEXPLAINED-FAIL == 0 で exit 0。
#
# 5 種別:
#   parity      — SSoT drift 検出 (yml/settings/CommonRules の整合性)
#   behavior    — BLOCK/warn 挙動検証
#   budget      — 軽量性 regression (bytes/count 計測)
#   portability — cwd/install 差分 (cross-env 堅牢性)
#   stale-det   — 古い期待値検出 (自己改善系)
#
# expected-fail manifest:
#   _is_expected_fail / _get_expected_reason 関数に "smoke-name" で登録。
#   runner は smoke 全体が exit 1 した場合に manifest を参照し、
#   EXPECTED-FAIL vs UNEXPLAINED-FAIL を判定する。
#
# 実行:
#   bash .claude/tests/run-all-smokes.sh [OPTIONS]
#
# オプション:
#   --category <name>  指定種別のみ実行 (parity/behavior/budget/portability/stale-det)
#   --list             分類一覧を表示して終了
#   --verbose          各 smoke の全出力を表示
#
# 終了コード:
#   0 = UNEXPLAINED-FAIL == 0 (放置 fail なし)
#   1 = UNEXPLAINED-FAIL > 0  (説明のつかない fail 存在)
#
# 重要制約:
#   file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   declare -A (bash 4+) は使わない (macOS bash 3.2 対応)
#   実装本体は subshell 関数化で局所化する。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ============================================================
# 5 種別 smoke 分類 (bash 3.2 対応: case 文ベース)
# ============================================================
_get_smoke_category() {
  local name="$1"
  case "$name" in
    # parity: SSoT drift 検出
    action-space-count-smoke|\
    common-rules-import-smoke|\
    config-feature-toggles-smoke|\
    dead-hook-inventory-smoke|\
    effective-hook-matrix-smoke|\
    enforcement-mismatch-smoke|\
    harness-config-local-smoke|\
    hc-config-key-parity-smoke|\
    hc-config-local-yml-smoke|\
    hc-config-migration-smoke|\
    iter-min-3-smoke|\
    layer-b-context-isolation-smoke|\
    lib-block-message-smoke|\
    lib-observability-smoke|\
    normative-ssot-integrity-smoke|\
    review-required-min-count-smoke|\
    reviewer-count-guard-smoke|\
    rule-architecture-smoke|\
    settings-dispatcher-baseline-smoke|\
    wave-precheck-template-smoke)
      printf 'parity' ;;
    # budget: 軽量性 regression
    sessionstart-budget-smoke|\
    sessionstart-footprint-smoke)
      printf 'budget' ;;
    # portability: cwd/install 差分
    dual-mode-portability-smoke|\
    hook-cwd-robustness-smoke|\
    install-ci-matrix-smoke|\
    install-claude-md-autofill-smoke|\
    install-full-smoke|\
    install-local-yml-smoke|\
    install-mcp-servers-smoke|\
    install-pre-commit-smoke|\
    install-sh-sync-drift-smoke|\
    project-root-smoke|\
    self-doctor-smoke|\
    session-start-parallel-smoke|\
    yml-triplet-pre-commit-smoke)
      printf 'portability' ;;
    # stale-det: 古い期待値自己検出
    stale-harness-detect-smoke)
      printf 'stale-det' ;;
    # behavior: BLOCK/warn 挙動検証 (default)
    # cli 機能検証 (task-83) / task #96 P2-5 agent-router LLM fallback 子 toggle /
    # task-94 P2-3 emit_block_stop 契約 (Stop hook JSON stdout 非出力 + 4 label stderr) /
    # task-98 P3-1 ui-contract advisory hook / task-99 P3-2 hook-fire-audit behavior
    npx-cli-smoke|\
    agent-router-llm-fallback-smoke|\
    byproduct-discharge-guard-smoke|\
    hook-fire-audit-smoke|\
    ui-contract-smoke)
      printf 'behavior' ;;
    *)
      printf 'behavior' ;;
  esac
}

# ============================================================
# expected-fail manifest (bash 3.2 対応: case 文ベース)
#
# task-74 iter-1: manifest を「正当な expected fail」のみに縮小。
#   - environmental (preset 緩和): harness-dev preset で feature toggle OFF により
#     guard が advisory 化 / no-op 化する。team-default/strict では BLOCK/WARN する。
#     恒久 expected (preset 設計上の正常 fail)。
#   - flaky (quarantine): port contention / worktree timing 由来の間欠 fail。
#     恒久 expected ではなく next-actions #72 で root-cause 追跡対象。
#
# 削除済 (iter-1 で本来処理して PASS 化):
#   - stale-harness-detect-smoke: config-loader real bug fix (修正 1)
#   - autonomous-action-guard/audit-followups/loop-auto-progress: obsolete case skip 化 (修正 2)
#   - context-budget/wave-precheck-template/custom-pm-commands: spec-drift 決定論修正 (修正 3)
# ============================================================
_is_expected_fail() {
  local name="$1"
  # environmental (preset 緩和、恒久 expected): gateguard / workflow-guard /
  #   task-rule-guard / tool-call-slip-detector
  # flaky (quarantine、next-actions #72 で根本追跡): hc-config-web-ui / install-sh-sync-drift
  # 削除済 (task #91 Step 3): list-md-plan-first-reminder-smoke — 全 case per-case
  #   HC_FEATURE_TASK_RULE_GUARD_ENABLED=true 注入により harness-dev (yml false) でも
  #   13/13 PASS が成立し expected-fail 前提が解消 (旧 note「Case 1/7 が silent は正常」は失効)。
  case "$name" in
    gateguard-smoke|\
    workflow-guard-smoke|\
    task-rule-guard-smoke|\
    tool-call-slip-detector-smoke|\
    hc-config-web-ui-smoke|\
    install-sh-sync-drift-smoke)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# NB (fix 5, case 単位 parse の限界): 下記 reason の "Case N/M" は当該 smoke が
# fail する想定 case。現 runner は smoke 単位 (exit code) で EXPECTED-FAIL 判定するため、
# 列挙 case 以外が新たに fail しても smoke 全体 exit 1 として同じく EXPECTED-FAIL に
# 吸収され UNEXPLAINED にならない。本来は列挙 case 以外の fail を UNEXPLAINED 扱い
# すべきだが case 単位 parse は別 task。SMOKE-CLASSIFICATION.md §limitation に記録。
_get_expected_reason() {
  local name="$1"
  case "$name" in
    gateguard-smoke)
      printf '[environmental] harness-dev preset で gateguard が advisory 化 (feature_gateguard_enabled を OFF 設定)。team-default/strict では BLOCK される。enforcement_matrix.gateguard.disabled_reason 参照。expected fail case は Case 1/3 のみ。' ;;
    workflow-guard-smoke)
      printf '[environmental] harness-dev preset で workflow_guard が advisory 化 (feature_workflow_guard_enabled=false)。team-default/strict では BLOCK される。expected fail case は Case 2/3/5 のみ。' ;;
    task-rule-guard-smoke)
      printf '[environmental] harness-dev preset で task_rule_guard が advisory 化 (feature_task_rule_guard_enabled=false)。Case 1/4 は BLOCK 期待だが advisory で素通り。Case 12 は list-md-plan-first-reminder が同 feature で no-op。expected fail case は Case 1/4/12 のみ。' ;;
    tool-call-slip-detector-smoke)
      printf '[environmental] feature_tool_call_slip_detect_enabled=false (harness-config.yml、誤検出ループが主因と判明し 2026-06-01 切り分けで意図的 OFF) により hook が no-op。Case 1/2 の detection 期待は feature 有効時前提。feature ON 環境 (consuming repo) では PASS する。expected fail case は Case 1/2 のみ。' ;;
    hc-config-web-ui-smoke)
      printf '[flaky-quarantine] port contention / サーバ起動タイミングによる間欠 fail。同一 run で異なる case (S-02/S-39/S-45 等) が不定期 fail。単独再実行では PASS する場合が多い。恒久 expected ではなく next-actions #72 で root-cause 追跡 (web-ui port contention skip 強化)。' ;;
    install-sh-sync-drift-smoke)
      printf '[flaky-quarantine] git worktree 状態・rsync タイミング依存の間欠 fail (Case C/E)。単独実行では通常 PASS、parallel runner 実行時または dirty worktree で間欠 fail。恒久 expected ではなく next-actions #72 で root-cause 追跡 (install-sync sequential 実行化)。' ;;
    *)
      printf '(no reason recorded)' ;;
  esac
}

# ============================================================
# 引数解析
# ============================================================
FILTER_CATEGORY=""
LIST_ONLY=0
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --category)
      FILTER_CATEGORY="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      shift
      ;;
  esac
done

# ============================================================
# --list: 分類一覧表示
# ============================================================
if [ "$LIST_ONLY" = "1" ]; then
  printf '=== Smoke 5-category classification ===\n\n'
  for cat in parity behavior budget portability stale-det; do
    printf '[%s]\n' "$cat"
    for smoke_file in "$SCRIPT_DIR"/*smoke*.sh; do
      name=$(basename "$smoke_file" .sh)
      [ "$name" = "run-all-smokes" ] && continue
      mapped_cat=$(_get_smoke_category "$name")
      if [ "$mapped_cat" = "$cat" ]; then
        ef_mark=""
        _is_expected_fail "$name" && ef_mark=" [EXPECTED-FAIL]"
        printf '  %s%s\n' "$name" "$ef_mark"
      fi
    done
    printf '\n'
  done
  printf '=== Expected-fail manifest (task-74 iter-1 起点、task #91 で environmental 4 + flaky 2 に縮小、task-95 Wave 1 review 後 dead-hook-inventory 除外) ===\n\n'
  for name in gateguard-smoke workflow-guard-smoke task-rule-guard-smoke \
              tool-call-slip-detector-smoke \
              hc-config-web-ui-smoke install-sh-sync-drift-smoke; do
    reason=$(_get_expected_reason "$name")
    printf '[%s]\n  %s\n\n' "$name" "$reason"
  done
  exit 0
fi

# ============================================================
# 集計変数
# ============================================================
TOTAL_PASS=0
TOTAL_EXPECTED_FAIL=0
TOTAL_UNEXPLAINED_FAIL=0
TOTAL_SKIP=0

PASS_LIST=""
EXPECTED_FAIL_LIST=""
UNEXPLAINED_FAIL_LIST=""
SKIP_LIST=""

# ============================================================
# smoke 実行関数
# ============================================================
CURRENT_CATEGORY=""

run_smoke() {
  local smoke_file="$1"
  local name
  name=$(basename "$smoke_file" .sh)
  local cat
  cat=$(_get_smoke_category "$name")

  # category filter
  if [ -n "$FILTER_CATEGORY" ] && [ "$cat" != "$FILTER_CATEGORY" ]; then
    return
  fi

  # カテゴリ見出し (切替時)
  if [ "$cat" != "$CURRENT_CATEGORY" ]; then
    printf '\n--- [%s] ---\n' "$cat"
    CURRENT_CATEGORY="$cat"
  fi

  # web-ui smoke: network bind 不可環境 (sandbox/CI) では SKIP
  if [ "$name" = "hc-config-web-ui-smoke" ]; then
    if ! python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); s.close()" 2>/dev/null; then
      printf '  SKIP  %s (network bind unavailable)\n' "$name"
      TOTAL_SKIP=$((TOTAL_SKIP + 1))
      SKIP_LIST="${SKIP_LIST} ${name}"
      return
    fi
  fi

  # smoke 実行
  local out_file
  out_file=$(mktemp /tmp/smoke-runner-out.XXXXXX)
  local exit_code=0

  bash "$smoke_file" >"$out_file" 2>&1 || exit_code=$?

  if [ "$VERBOSE" = "1" ]; then
    cat "$out_file"
  fi

  if [ "$exit_code" = "0" ]; then
    printf '  PASS  %s\n' "$name"
    TOTAL_PASS=$((TOTAL_PASS + 1))
    PASS_LIST="${PASS_LIST} ${name}"
  else
    # expected-fail manifest 参照
    if _is_expected_fail "$name"; then
      local reason
      reason=$(_get_expected_reason "$name")
      printf '  EXPECTED-FAIL  %s\n' "$name"
      printf '    reason: %s\n' "$reason"
      TOTAL_EXPECTED_FAIL=$((TOTAL_EXPECTED_FAIL + 1))
      EXPECTED_FAIL_LIST="${EXPECTED_FAIL_LIST} ${name}"
    else
      printf '  UNEXPLAINED-FAIL  %s (exit=%d)\n' "$name" "$exit_code"
      # 出力の最後 5 行を表示 (診断支援)
      tail -5 "$out_file" | sed 's/^/    /'
      TOTAL_UNEXPLAINED_FAIL=$((TOTAL_UNEXPLAINED_FAIL + 1))
      UNEXPLAINED_FAIL_LIST="${UNEXPLAINED_FAIL_LIST} ${name}"
    fi
  fi

  rm -f "$out_file"
}

# ============================================================
# メイン: 種別順でスキャン・実行
# ============================================================
printf '=== run-all-smokes.sh (%s) ===\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'repo: %s\n' "$REPO_ROOT"

for cat in parity behavior budget portability stale-det; do
  CURRENT_CATEGORY=""
  for smoke_file in "$SCRIPT_DIR"/*smoke*.sh; do
    name=$(basename "$smoke_file" .sh)
    [ "$name" = "run-all-smokes" ] && continue
    mapped_cat=$(_get_smoke_category "$name")
    if [ "$mapped_cat" = "$cat" ]; then
      run_smoke "$smoke_file"
    fi
  done
done

# ============================================================
# 最終サマリー
# ============================================================
TOTAL=$((TOTAL_PASS + TOTAL_EXPECTED_FAIL + TOTAL_UNEXPLAINED_FAIL + TOTAL_SKIP))

printf '\n'
printf '=== run-all-smokes summary ===\n'
printf 'Total smokes run : %d\n' "$TOTAL"
printf 'PASS             : %d\n' "$TOTAL_PASS"
printf 'EXPECTED-FAIL    : %d (manifest 登録済、reason 付)\n' "$TOTAL_EXPECTED_FAIL"
printf 'UNEXPLAINED-FAIL : %d\n' "$TOTAL_UNEXPLAINED_FAIL"
printf 'SKIP             : %d\n' "$TOTAL_SKIP"

if [ -n "$EXPECTED_FAIL_LIST" ]; then
  printf '\n[EXPECTED-FAIL list]\n'
  for s in $EXPECTED_FAIL_LIST; do
    printf '  - %s\n' "$s"
  done
fi

if [ -n "$UNEXPLAINED_FAIL_LIST" ]; then
  printf '\n[UNEXPLAINED-FAIL list -- requires investigation]\n'
  for s in $UNEXPLAINED_FAIL_LIST; do
    printf '  - %s\n' "$s"
  done
fi

printf '\n'
if [ "$TOTAL_UNEXPLAINED_FAIL" -eq 0 ]; then
  printf 'EXIT 0: UNEXPLAINED-FAIL == 0 (放置 fail なし)\n'
  exit 0
else
  printf 'EXIT 1: UNEXPLAINED-FAIL == %d (調査必要)\n' "$TOTAL_UNEXPLAINED_FAIL"
  exit 1
fi
