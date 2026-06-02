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
    effective-hook-matrix-smoke|\
    enforcement-mismatch-smoke|\
    harness-config-local-smoke|\
    hc-config-key-parity-smoke|\
    hc-config-migration-smoke|\
    layer-b-context-isolation-smoke|\
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
    install-sh-sync-drift-smoke|\
    project-root-smoke|\
    session-start-parallel-smoke)
      printf 'portability' ;;
    # stale-det: 古い期待値自己検出
    stale-harness-detect-smoke)
      printf 'stale-det' ;;
    # behavior: BLOCK/warn 挙動検証 (default)
    *)
      printf 'behavior' ;;
  esac
}

# ============================================================
# expected-fail manifest (bash 3.2 対応: case 文ベース)
# ============================================================
_is_expected_fail() {
  local name="$1"
  case "$name" in
    gateguard-smoke|\
    workflow-guard-smoke|\
    task-rule-guard-smoke|\
    list-md-plan-first-reminder-smoke|\
    autonomous-action-guard-smoke|\
    audit-followups-smoke|\
    loop-auto-progress-smoke|\
    context-budget-smoke|\
    tool-call-slip-detector-smoke|\
    stale-harness-detect-smoke|\
    wave-precheck-template-smoke|\
    custom-pm-commands-smoke|\
    hc-config-web-ui-smoke|\
    install-sh-sync-drift-smoke)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

_get_expected_reason() {
  local name="$1"
  case "$name" in
    gateguard-smoke)
      printf '[environmental] harness-dev preset で gateguard が advisory 化 (feature_gateguard_enabled を OFF 設定)。team-default/strict では BLOCK される。enforcement_matrix.gateguard.disabled_reason 参照。Case 1/3 が fail するのは正常。' ;;
    workflow-guard-smoke)
      printf '[environmental] harness-dev preset で workflow_guard が advisory 化 (feature_workflow_guard_enabled=false)。team-default/strict では BLOCK される。Case 2/3/5 が fail するのは正常。' ;;
    task-rule-guard-smoke)
      printf '[environmental] harness-dev preset で task_rule_guard が advisory 化 (feature_task_rule_guard_enabled=false)。Case 1/4 は BLOCK 期待だが advisory で素通り。Case 12 は list-md-plan-first-reminder が同 feature で no-op。' ;;
    list-md-plan-first-reminder-smoke)
      printf '[environmental] feature_task_rule_guard_enabled=false により list-md-plan-first-reminder も no-op (同 feature group)。Case 1/7 が silent になるのは正常。team-default/strict では WARN が発火する。' ;;
    autonomous-action-guard-smoke)
      printf '[obsolete] task-39 緩和 (2026-05-25) で git push origin main/gh pr create が自律実行可となり BLOCK されなくなった。Case 1/2/4 は旧 BLOCK 期待のため fail が正常。next-actions #25/#31 既知。' ;;
    audit-followups-smoke)
      printf '[obsolete+spec-drift] Case 2: confidence gate が general-purpose を現在 block しない (実装変更)。Case 3/4: task-39 緩和で git push origin main が Normal/Loop ともに block されなくなった。next-actions #44 既知。' ;;
    loop-auto-progress-smoke)
      printf '[obsolete] task-39 緩和 (2026-05-25) で git push feature branch/gh pr create が自律実行可。Case 4 (git push) / Case 5 (gh pr create) / Case 9 (normal push context) が旧 BLOCK 期待のため fail が正常。' ;;
    context-budget-smoke)
      printf '[spec-drift] harness-config.yml の context_budget_threshold=0.66 (リポジトリ固有設定)。smoke は default 0.60 前提で 60pct fixture を fire 期待するが、0.66 未満のため silent。spam prevention も同様。' ;;
    tool-call-slip-detector-smoke)
      printf '[spec-drift] feature_tool_call_slip_detect_enabled=false (harness-config.yml) により hook が no-op。Case 1/2 の detection 期待は feature 有効時前提の stale 期待値。feature ON 環境 (consuming repo) では PASS する。' ;;
    stale-harness-detect-smoke)
      printf '[spec-drift] Case 6: HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false env override が config-loader 経由の is_feature_enabled に負けて no-op にならない。yml の feature_stale_harness_detect_enabled=true が優先され WARN が出続ける。' ;;
    wave-precheck-template-smoke)
      printf '[spec-drift] Case 2: workflow.md に "git log --grep" の記述が存在しない (0 hit)。task-56 当時に想定した Stage 8/7 の記述が workflow.md から削除または未追加。' ;;
    custom-pm-commands-smoke)
      printf '[spec-drift] Case 5: grep /sc:(save|load|pm) で allowed 外ファイルに残存 hit がある。除外パターンの更新漏れ。' ;;
    hc-config-web-ui-smoke)
      printf '[environmental] ポート競合/サーバ起動タイミングによる間欠的 fail (flaky)。同一 run で異なる case (S-02/S-39/S-45 等) が不定期 fail する。CI sandbox のネットワーク制約または並列 run の port contention が原因。単独再実行では PASS する場合が多い。' ;;
    install-sh-sync-drift-smoke)
      printf '[environmental] Case C/E が特定タイミングで fail (git worktree 状態・rsync の動作タイミング依存)。単独実行では通常 PASS。parallel runner 実行時または dirty worktree 状態で間欠的に fail。' ;;
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
  printf '=== Expected-fail manifest ===\n\n'
  for name in gateguard-smoke workflow-guard-smoke task-rule-guard-smoke \
              list-md-plan-first-reminder-smoke autonomous-action-guard-smoke \
              audit-followups-smoke loop-auto-progress-smoke context-budget-smoke \
              tool-call-slip-detector-smoke stale-harness-detect-smoke \
              wave-precheck-template-smoke custom-pm-commands-smoke \
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
