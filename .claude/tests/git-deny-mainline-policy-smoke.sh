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
# honor-system / smoke 境界 (draft §3.4 H-3 / qa M2):
#   本 smoke が検証するのは git-deny.sh の **hook 実行パス = push 判定 (block/allow)** のみ。
#   merge 実施有無 (pr-required で本流 merge しない / local-merge(-push) で merge する) と
#   mainline 存在確認 (P1/P2 behavioral + 存在 cell) は **merge が hook 非 gate (push のみ gate) の
#   設計判断 H-3 により honor-system で統治** され、finish-task.md Phase 4.5 / resume-state.md Phase 6
#   の norm 手順がカバーする。push-gate smoke (本 file) が hook 強制部分をカバーし、merge-commit
#   behavioral と存在確認は norm-smoke 境界 (qa M2 と同じ) で smoke 直接対象外。
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
# P1: refspec 省略 + policy=pr-required + current=mainline(main) → block
# (block 側 refspec-omit 経路の網羅、architect H4。現状 allow 側両経路 + Tier3 のみ検証で
#  block 側の refspec 省略経路が未検証だった)
expect_block "P1: mainline=main + pr-required → push (no refspec, current=main) block" \
  "main" "pr-required" "git push" "main"

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

# --- 2-guard: autonomous-action-guard が git push 系 pattern を持たないことを直接確認 ---
# (qa H1 / sec L-1 / architect H4) git-deny.sh が唯一の push gate であることの片側確認。
# 「block / allow が pass する」ではなく「autonomous-action-guard の DEFAULT_PATTERNS に
#  `git push` を捕捉する regex が存在しない」ことを source 後の変数 grep で直接 assert する
# (task-39 緩和で削除済の回帰防止)。
printf "\n2-guard (autonomous-action-guard has no git push pattern):\n"
AAG="$REPO_ROOT/.claude/hooks/autonomous-action-guard.sh"
# DEFAULT_PATTERNS だけを取り出す (hook 全体を実行せず変数定義行群を抽出)。
# 'DEFAULT_PATTERNS=' 開始の single-quote heredoc-like 複数行代入を sed で切り出し。
AAG_PATTERNS="$(sed -n "/^DEFAULT_PATTERNS=/,/'$/p" "$AAG")"
# `git ... push` を捕捉する regex 行が無いことを確認 (`git tag ... origin` は push でなく tag、別物)。
if printf '%s' "$AAG_PATTERNS" | grep -Eq 'git\[\[:space:\]\]\+push'; then
  FAIL=$((FAIL + 1)); FAILED_CASES+=("2-guard: autonomous-action-guard に git push pattern が存在する (want=不在)")
  printf "  FAIL: 2-guard: autonomous-action-guard に git push pattern が存在 (want=不在)\n"
else
  PASS=$((PASS + 1)); printf "  PASS: 2-guard: autonomous-action-guard に git push pattern が不在 (git-deny が唯一の push gate)\n"
fi

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
