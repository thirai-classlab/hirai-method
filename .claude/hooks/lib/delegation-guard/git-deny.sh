#!/usr/bin/env bash
# git-deny.sh — git destructive 10 patterns + protected branch push の 2 layer deny
#
# 提供関数:
#   check_git_destructive <cmd>         — 破壊的 git 操作の検出 + block 出力
#   check_protected_branch_push <cmd>   — main / stg 含む branch への push 検出 + block 出力

# --- git destructive deny (常時、Normal/Loop 両モード共通) ---
# 破壊的 git 操作は user 明示承認なしに実行禁止 (data loss / history rewrite 不可逆)。
# 設計起源: 2026-05-18 user 指示「mainAgentでgitコマンドは基本的(破壊的変更以外)に実行できるようにしてください」。
# bypass: ECC_ALLOW_DESTRUCTIVE_GIT=1 (1 セッション)。
check_git_destructive() {
  local cmd="$1"
  if [ "${ECC_ALLOW_DESTRUCTIVE_GIT:-}" = "1" ]; then
    return 0
  fi

  local git_destructive_re='^git[[:space:]]+([^|;&]*[[:space:]])?('
  git_destructive_re="${git_destructive_re}push[[:space:]]+[^|;&]*--force"
  # Note: `-f` の検出は intervening args の有無を optional group で許容
  # (旧 regex `[^|;&]*[[:space:]]-f` は effectively 2-space required で
  # `git push -f` single-space を取りこぼした、`.claude/tests/delegation-guard-deny-layers-smoke.sh`
  # で発見、2026-05-18 修正)。
  git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?-f([[:space:]]|$)"
  git_destructive_re="${git_destructive_re}|reset[[:space:]]+([^|;&]*[[:space:]])?--hard"
  git_destructive_re="${git_destructive_re}|branch[[:space:]]+([^|;&]*[[:space:]])?-D"
  git_destructive_re="${git_destructive_re}|clean[[:space:]]+-[A-Za-z]*f"
  git_destructive_re="${git_destructive_re}|checkout[[:space:]]+--[[:space:]]"
  git_destructive_re="${git_destructive_re}|restore[[:space:]]+([^|;&]*[[:space:]])?(--worktree|--source)"
  git_destructive_re="${git_destructive_re}|stash[[:space:]]+(drop|clear)"
  git_destructive_re="${git_destructive_re}|tag[[:space:]]+([^|;&]*[[:space:]])?-[df]([[:space:]]|$)"
  git_destructive_re="${git_destructive_re}|reflog[[:space:]]+expire"
  git_destructive_re="${git_destructive_re}|gc[[:space:]]+--prune=now"
  # iteration 3: R5 security-reviewer MEDIUM F-03/F-04/F-05 解消 (task-39 Step2)
  # `--mirror` (全 ref 強制反映、main 含む)、`--all` / `--branches` (全 branch 一括 push、main 含む)、
  # `--prune` (deletion を含むため destructive) を destructive 扱いに追加 (defense-in-depth 完全化)。
  git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?--mirror([[:space:]]|$)"
  git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?--all([[:space:]]|$)"
  git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?--branches([[:space:]]|$)"
  git_destructive_re="${git_destructive_re}|push[[:space:]]+([^|;&]*[[:space:]])?--prune([[:space:]]|$)"
  git_destructive_re="${git_destructive_re})"

  if printf '%s' "$cmd" | grep -qE "$git_destructive_re"; then
    local destructive_reason
    destructive_reason=$(printf '[git destructive guard] 破壊的 git 操作は禁止: %s\n\n破壊的操作の例:\n  - push --force / push -f (force push)\n  - push --mirror (全 ref 強制反映、main 含む)\n  - push --all / push --branches (全 branch 一括 push、main 含む)\n  - push --prune (remote-only branch 削除)\n  - reset --hard (history 破壊)\n  - branch -D <name> (force delete)\n  - clean -f / -fd / -fdx (untracked 削除)\n  - checkout -- <file> (file 復元)\n  - restore --worktree|--source (file 復元)\n  - stash drop|clear (stash 破壊)\n  - tag -d|-f (tag 削除/上書き)\n  - reflog expire (reflog 破壊)\n  - gc --prune=now (orphan commit gc)\n\nbypass (1 セッション): export ECC_ALLOW_DESTRUCTIVE_GIT=1\n\n設計起源: 2026-05-18 user 指示「mainAgentでgitコマンドは基本的(破壊的変更以外)に実行できるようにしてください」' "$cmd")
    jq -n --arg r "$destructive_reason" '{decision:"block", reason:$r}'
    exit 0
  fi
}

# --- protected branch push deny (常時、Normal/Loop 両モード共通) ---
# 保護ブランチへの push は user 明示承認なしに原則禁止
# (production-bound branch への暴発防止、レビュー未通過コードの production / staging 伝搬防止)。
# 設計起源: 2026-05-18 user 指示「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」。
# task-77 (2026-06-03): mainline_branch + mainline_integration_policy 3 段階で本流 push を policy 連動化。
#   設計 SSoT: docs/draft/git-integration-policy.md §3.3 (3 tier) / §3.4 (consumer)。
#
# 順序付き 3 tier 判定 (§3.3、必ずこの順序):
#   Tier 1 (常時 block、policy 非依存): stg* (部分一致) / release/* / main (literal、ただし main != mainline の時のみ)
#   Tier 2 (policy 条件付き): push 先 == mainline の時、policy == local-merge-push なら許可、それ以外 (不正/未知値含む) は block (fail-safe pr-required)
#   Tier 3 (素通し): 上記いずれにも該当しない branch (feature branch 等、task-39 緩和どおり)
#
# mainline / policy 参照 (config-loader が source 済、fail-safe default 込み):
#   mainline = ${HC_MAINLINE_BRANCH:-main} / policy = ${HC_MAINLINE_INTEGRATION_POLICY:-pr-required}
#
# bypass: ECC_ALLOW_PROTECTED_BRANCH_PUSH=1 (関数全体無効化、緊急用。policy 経路には流用しない、security M-1)。
#
# 検知パターン:
#   1. 明示 refspec: `git push origin main` / `git push -u origin release/stg-prod` /
#                    `git push origin HEAD:main` / `git push origin feat:refs/heads/stg-v1`
#   2. refspec 省略: `git push` / `git push origin` (current branch を git rev-parse で解決し判定)

# push 先 1 件 (dst_part / dst_basename) を 3 tier で判定し、block 理由 (文字列) を返す。
# allow / Tier3 素通しの場合は空文字を返す (= 違反なし)。
# 引数: $1 = dst_part (refspec dst、例: main / release/v1.0 / refs/heads/stg-v1 / develop)
#       $2 = source 表記 (block 理由メッセージ用、例: "origin main" / "(no refspec) current branch = main")
_classify_push_target() {
  local dst_part="$1"
  local src_label="$2"
  local mainline policy dst_basename
  mainline="${HC_MAINLINE_BRANCH:-main}"
  policy="${HC_MAINLINE_INTEGRATION_POLICY:-pr-required}"

  # `refs/heads/main` 等は basename を抽出。release/* 判定には full dst_part を使う。
  dst_basename="${dst_part##*/}"
  # 先頭の + (force push の別形式、destructive deny で別途 catch されるが念のため除去)
  dst_basename="${dst_basename#+}"
  dst_part="${dst_part#+}"

  # --- Tier 1: 常時 block (policy 非依存) ---
  # stg* (部分一致)
  case "$dst_basename" in
    *stg*)
      printf '%s (Tier1: dst basename %s contains stg)' "$src_label" "$dst_basename"
      return 0
      ;;
  esac
  # release/* (basename / full path どちらに現れても、release/ prefix を持つ ref を catch)
  case "$dst_part" in
    release/*)
      printf '%s (Tier1: %s matches release/*)' "$src_label" "$dst_part"
      return 0
      ;;
  esac
  case "$dst_basename" in
    release/*)
      printf '%s (Tier1: %s matches release/*)' "$src_label" "$dst_basename"
      return 0
      ;;
  esac
  # main (literal、ただし main != mainline の時のみ Tier1。main == mainline なら Tier2 へ落とす)
  if [ "$dst_basename" = "main" ] && [ "$mainline" != "main" ]; then
    printf '%s (Tier1: main is always protected when mainline=%s)' "$src_label" "$mainline"
    return 0
  fi

  # --- Tier 2: policy 条件付き (push 先 == mainline) ---
  if [ "$dst_basename" = "$mainline" ]; then
    if [ "$policy" = "local-merge-push" ]; then
      # 許可 (本流 push を policy で opt-in)
      return 0
    fi
    # pr-required / local-merge / 不正・未知値 は block (fail-safe pr-required)
    printf '%s (Tier2: mainline=%s push requires policy=local-merge-push, current policy=%s)' "$src_label" "$mainline" "$policy"
    return 0
  fi

  # --- Tier 3: 素通し ---
  return 0
}

check_protected_branch_push() {
  local cmd="$1"
  if [ "${ECC_ALLOW_PROTECTED_BRANCH_PUSH:-}" = "1" ]; then
    return 0
  fi
  if ! printf '%s' "$cmd" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
    return 0
  fi

  local mainline policy push_args protected_violation non_opt_token_count token dst_part
  mainline="${HC_MAINLINE_BRANCH:-main}"
  policy="${HC_MAINLINE_INTEGRATION_POLICY:-pr-required}"
  push_args=$(printf '%s' "$cmd" | sed -E 's|^git[[:space:]]+push[[:space:]]*||')
  protected_violation=""
  non_opt_token_count=0

  # shellcheck disable=SC2086
  for token in $push_args; do
    # option (--xxx, -x) は skip
    case "$token" in
      -*) continue ;;
    esac
    non_opt_token_count=$((non_opt_token_count + 1))

    # 最初の non-opt token は remote 名 (例: origin) なので skip
    if [ "$non_opt_token_count" -eq 1 ]; then
      continue
    fi

    # refspec 形式 `src:dst` なら dst を取る、それ以外はそのまま
    case "$token" in
      *:*) dst_part="${token##*:}" ;;
      *) dst_part="$token" ;;
    esac

    protected_violation=$(_classify_push_target "$dst_part" "$token")
    if [ -n "$protected_violation" ]; then
      break
    fi
  done

  # refspec 省略 (`git push` / `git push <remote>` only) の場合は current branch を確認
  if [ -z "$protected_violation" ] && [ "$non_opt_token_count" -le 1 ]; then
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ -n "$current_branch" ]; then
      protected_violation=$(_classify_push_target "$current_branch" "(no refspec) current branch = $current_branch")
    fi
  fi

  if [ -n "$protected_violation" ]; then
    local protected_reason
    protected_reason=$(printf '[protected branch push deny] 保護ブランチへの push は禁止: %s\n\n違反 token: %s\n\n判定 (3 tier、mainline=%s / policy=%s):\n  - Tier 1 (常時 block): stg* / release/* / main (mainline でない限り)\n  - Tier 2 (policy 条件付き): mainline (=%s) push は policy=local-merge-push の時のみ許可\n  - Tier 3 (素通し): feature branch 等\n\n本流 (mainline) push を許可するには:\n  1. harness-config.yml の mainline_integration_policy: local-merge-push を設定 (一次案内)\n  2. (緊急 / 二次) export ECC_ALLOW_PROTECTED_BRANCH_PUSH=1 で本 guard 全体を 1 セッション無効化\n\n推奨対応:\n  1. branch 切替後 push (git switch <branch> && git push -u origin <branch>)\n  2. PR 経由 (gh pr create で本流へは merge)\n\n設計起源: 2026-05-18 user 指示 + task-77 (docs/draft/git-integration-policy.md §3.3)' "$cmd" "$protected_violation" "$mainline" "$policy" "$mainline")
    jq -n --arg r "$protected_reason" '{decision:"block", reason:$r}'
    exit 0
  fi
}
