#!/usr/bin/env bash
# git-deny-mainline-policy-smoke.sh — task-77 Step 2 unit smoke for the
# policy-aware 3-tier protected branch push judgement in
# .claude/hooks/lib/delegation-guard/git-deny.sh (check_protected_branch_push).
#
# 設計 SSoT: docs/draft/git-integration-policy.md §3.3 (3 tier) / Step 7 smoke matrix (push 系 cell)。
#
# 検証形式:
#   git-deny.sh を source して check_protected_branch_push を直接呼び出す unit 形式。
#   block 時は関数が `exit 0` で {"decision":"block"} を stdout に出すため、各 assert は
#   subshell ( ... ) で実行して exit を局所化し、stdout を decision で判定する。
#
# 3 tier (mainline=${HC_MAINLINE_BRANCH:-main} / policy=${HC_MAINLINE_INTEGRATION_POLICY:-pr-required}):
#   Tier 1 (常時 block): stg* / release/* / main (main != mainline の時のみ)
#   Tier 2 (policy): mainline push は policy=local-merge-push の時のみ allow、他は block (fail-safe pr-required)
#   Tier 3 (素通し): feature branch 等
#
# 重要制約:
#   - file-top に `set -euo pipefail` を書かない (caller leak 防止教訓 feedback_set_e_in_sourced_libs)。
#   - current-branch fallback 経路は git stub で HEAD を制御する。
#
# 実行: bash .claude/tests/git-deny-mainline-policy-smoke.sh
# 終了コード: 0 = 全 case PASS / 1 = 1 件以上 FAIL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_DENY="$REPO_ROOT/.claude/hooks/lib/delegation-guard/git-deny.sh"

# subagent 短絡無関係 (本 smoke は git-deny.sh を直接 source する)
unset CLAUDE_HARNESS_ROLE
unset ECC_ALLOW_PROTECTED_BRANCH_PUSH
unset ECC_ALLOW_DESTRUCTIVE_GIT

# stub 用 dir を PATH 先頭に置き、current-branch fallback の `git rev-parse` を制御する。
STUB_DIR="$(mktemp -d)"
cleanup() { rm -rf "$STUB_DIR"; }
trap cleanup EXIT

# git stub: `git rev-parse --abbrev-ref HEAD` で STUB_CURRENT_BRANCH を返す。
# それ以外の git は本物に委譲する (本 smoke では rev-parse 以外不要だが安全のため)。
cat > "$STUB_DIR/git" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then
  printf '%s\n' "${STUB_CURRENT_BRANCH:-main}"
  exit 0
fi
exec /usr/bin/git "$@"
STUB
chmod +x "$STUB_DIR/git"
export PATH="$STUB_DIR:$PATH"

# shellcheck source=../hooks/lib/delegation-guard/git-deny.sh
source "$GIT_DENY"

PASS=0
FAIL=0
FAILED_CASES=()

# check_protected_branch_push を呼び、stdout の decision を返す。
# 引数: $1 = mainline ("" = 未設定/unset) / $2 = policy ("" = unset) /
#       $3 = cmd / $4 = current_branch (refspec 省略経路用、default main)。
# block 時に関数が `exit 0` するため、$( ... ) の command substitution subshell で
# 局所化する (本体 shell は exit しない)。env もこの subshell 内でのみ設定/unset する。
run_check() {
  local mainline="$1" policy="$2" cmd="$3" curbr="${4:-main}"
  local out
  out=$(
    if [ -n "$mainline" ]; then export HC_MAINLINE_BRANCH="$mainline"; else unset HC_MAINLINE_BRANCH; fi
    if [ -n "$policy" ]; then export HC_MAINLINE_INTEGRATION_POLICY="$policy"; else unset HC_MAINLINE_INTEGRATION_POLICY; fi
    export STUB_CURRENT_BRANCH="$curbr"
    check_protected_branch_push "$cmd" 2>/dev/null
  )
  printf '%s' "$out" | python3 -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    print(d.get("decision", "none"))
except Exception:
    print("none")
' 2>/dev/null
}

# block 期待: $1=label $2=mainline $3=policy $4=cmd [$5=current_branch]
expect_block() {
  local label="$1" decision
  decision=$(run_check "$2" "$3" "$4" "${5:-main}")
  if [ "$decision" = "block" ]; then
    PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("$label (decision=$decision, want=block)")
    printf "  FAIL: %s (decision=%s, want=block)\n" "$label" "$decision"
  fi
}

# allow / 素通し期待 (decision != block): $1=label $2=mainline $3=policy $4=cmd [$5=current_branch]
expect_allow() {
  local label="$1" decision
  decision=$(run_check "$2" "$3" "$4" "${5:-main}")
  if [ "$decision" != "block" ]; then
    PASS=$((PASS + 1)); printf "  PASS: %s\n" "$label"
  else
    FAIL=$((FAIL + 1)); FAILED_CASES+=("$label (decision=$decision, want=allow)")
    printf "  FAIL: %s (decision=%s, want=allow)\n" "$label" "$decision"
  fi
}

printf "===== git-deny-mainline-policy-smoke (task-77 Step 2) =====\n\n"

# expect_block / expect_allow 引数: label / mainline ("" = unset) / policy ("" = unset) / cmd [/ current_branch]

# --- 回帰: mainline 未設定 / default、main 保護維持 ---
printf "Regression (default fallback, main protected):\n"
# 回帰1: env unset (default) + policy 未設定 → main block
expect_block "回帰1: default (env unset) → push origin main block" \
  "" "" "git push origin main"
# 回帰2: HC_MAINLINE_BRANCH=main + policy=pr-required → main block
expect_block "回帰2: mainline=main + pr-required → push origin main block" \
  "main" "pr-required" "git push origin main"

# --- Tier 2: mainline policy 連動 ---
printf "\nTier 2 (mainline policy):\n"
# P2: policy=local-merge → mainline push block
expect_block "P2: mainline=main + local-merge → push origin main block" \
  "main" "local-merge" "git push origin main"
# P3: policy=local-merge-push → mainline (=main) push allow (明示 refspec)
expect_allow "P3: mainline=main + local-merge-push → push origin main allow (explicit refspec)" \
  "main" "local-merge-push" "git push origin main"
# P3: refspec 省略経路 (current branch=main) → allow
expect_allow "P3: mainline=main + local-merge-push → push (no refspec, current=main) allow" \
  "main" "local-merge-push" "git push" "main"

# --- Tier 1: stg* 常時 block (3 policy) ---
printf "\nTier 1 (stg* always block, all 3 policies):\n"
expect_block "stg×pr-required: push origin stg-x block" \
  "main" "pr-required" "git push origin stg-x"
expect_block "stg×local-merge: push origin stg-x block" \
  "main" "local-merge" "git push origin stg-x"
expect_block "stg×local-merge-push: push origin stg-x block (policy must not leak)" \
  "main" "local-merge-push" "git push origin stg-x"

# --- Tier 1: release/* 常時 block (新 arm、3 policy) ---
printf "\nTier 1 (release/* always block, new arm, all 3 policies):\n"
expect_block "rel×pr-required: push origin release/v1.0 block" \
  "main" "pr-required" "git push origin release/v1.0"
expect_block "rel×local-merge: push origin release/v1.0 block" \
  "main" "local-merge" "git push origin release/v1.0"
expect_block "rel×local-merge-push: push origin release/v1.0 block (policy must not leak)" \
  "main" "local-merge-push" "git push origin release/v1.0"

# --- 追従: mainline=develop ---
printf "\nMainline follow (mainline=develop):\n"
# develop push は policy 連動で allow (local-merge-push)
expect_allow "追従: mainline=develop + local-merge-push → push origin develop allow" \
  "develop" "local-merge-push" "git push origin develop"
# develop だが policy=local-merge → block (Tier2 fail-safe)
expect_block "追従: mainline=develop + local-merge → push origin develop block" \
  "develop" "local-merge" "git push origin develop"
# main は mainline=develop でも Tier1 常時 block (mainline 移動で main 無保護化しない)
expect_block "追従: mainline=develop + local-merge-push → push origin main 常時 block (Tier1)" \
  "develop" "local-merge-push" "git push origin main"
# 追従 refspec 省略経路: current=develop + local-merge-push → allow
expect_allow "追従: mainline=develop + local-merge-push → push (no refspec, current=develop) allow" \
  "develop" "local-merge-push" "git push" "develop"

# --- 不正値: fail-safe pr-required ---
printf "\nInvalid policy (fail-safe pr-required):\n"
expect_block "不正値: policy=yolo → mainline push block (fail-safe)" \
  "main" "yolo" "git push origin main"

# --- Tier 3: feature branch 素通し (回帰、task-39 緩和維持) ---
printf "\nTier 3 (feature branch passthrough, task-39 緩和維持):\n"
expect_allow "Tier3: push origin feature/test allow" \
  "main" "pr-required" "git push origin feature/test"
expect_allow "Tier3: push -u origin feat/task-77-x allow" \
  "main" "pr-required" "git push -u origin feat/task-77-x"
# Tier3 refspec 省略経路: current=feature branch → allow
expect_allow "Tier3: push (no refspec, current=feat/task-77-x) allow" \
  "main" "pr-required" "git push" "feat/task-77-x"

TOTAL=$((PASS + FAIL))
printf "\n===== Result =====\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d / %d\n" "$FAIL" "$TOTAL"
if [ "$FAIL" -gt 0 ]; then
  printf "\nFailed cases:\n"
  for c in "${FAILED_CASES[@]}"; do
    printf "  - %s\n" "$c"
  done
  exit 1
fi
exit 0
