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
# main / stg を含む branch への push は user 明示承認なしに禁止
# (production-bound branch への暴発防止、レビュー未通過コードの production / staging 伝搬防止)。
# 設計起源: 2026-05-18 user 指示「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」。
# bypass: ECC_ALLOW_PROTECTED_BRANCH_PUSH=1 (1 セッション)。
#
# 検知パターン:
#   1. 明示 refspec: `git push origin main` / `git push -u origin release/stg-prod` /
#                    `git push origin HEAD:main` / `git push origin feat:refs/heads/stg-v1`
#   2. refspec 省略: `git push` / `git push origin` (current branch を git rev-parse で解決し判定)
#
# 判定基準: refspec の dst basename が
#   - `main` 完全一致 → block
#   - `*stg*` 部分一致 → block (例: stg, stg-v1, release/stg-prod, feature/stg-test)
check_protected_branch_push() {
  local cmd="$1"
  if [ "${ECC_ALLOW_PROTECTED_BRANCH_PUSH:-}" = "1" ]; then
    return 0
  fi
  if ! printf '%s' "$cmd" | grep -qE '^git[[:space:]]+push([[:space:]]|$)'; then
    return 0
  fi

  local push_args protected_violation non_opt_token_count token dst_part dst_basename
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
    # `refs/heads/main` 等は basename を抽出
    dst_basename="${dst_part##*/}"
    # 先頭の + (force push の別形式、destructive deny で別途 catch されるが念のため除去)
    dst_basename="${dst_basename#+}"

    if [ "$dst_basename" = "main" ]; then
      protected_violation="$token (refspec dst = main)"
      break
    fi
    case "$dst_basename" in
      *stg*)
        protected_violation="$token (refspec dst '$dst_basename' contains 'stg')"
        break
        ;;
    esac
  done

  # refspec 省略 (`git push` / `git push <remote>` only) の場合は current branch を確認
  if [ -z "$protected_violation" ] && [ "$non_opt_token_count" -le 1 ]; then
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$current_branch" = "main" ]; then
      protected_violation="(no refspec) current branch = main"
    else
      case "$current_branch" in
        *stg*)
          protected_violation="(no refspec) current branch = $current_branch (contains 'stg')"
          ;;
      esac
    fi
  fi

  if [ -n "$protected_violation" ]; then
    local protected_reason
    protected_reason=$(printf '[protected branch push deny] main / stg を含む branch への push は禁止: %s\n\n違反 token: %s\n\n禁止対象 branch 例:\n  - main (完全一致)\n  - stg, stg-v1, release/stg-prod, feature/stg-test (stg を含む任意)\n\nbypass (1 セッション): export ECC_ALLOW_PROTECTED_BRANCH_PUSH=1\n\n推奨対応:\n  1. branch 切替後 push (git switch <branch> && git push -u origin <branch>)\n  2. PR 経由 (gh pr create で main / stg へは merge)\n\n設計起源: 2026-05-18 user 指示「gitの許可はmainとstgと含むブランチに対するpush、破壊的変更以外に対してを許可してください」' "$cmd" "$protected_violation")
    jq -n --arg r "$protected_reason" '{decision:"block", reason:$r}'
    exit 0
  fi
}
