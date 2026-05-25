---
approval_required: true
approved_at: "2026-05-25"
---

# Draft: autonomous-action-guard-relaxation (main/stg 以外 push + PR 作成 自律実行可)

> Status: 起案 (2026-05-25)
> 起案者: user (本 session 末「main stg以外へのpush PRの作成は許可してください。prの承認のみGit hub上でユーザが行います」)
> 関連: 副産物 entry #24 / `.claude/hooks/autonomous-action-guard.sh` / `.claude/rules/modes.md` 遵守事項 8 / `.claude/hooks/delegation-guard.sh` の `protected-branch-push-deny` layer

## 1. 背景

本 session で task-35 完遂後 push 試行時、`autonomous-action-guard.sh` が `git push -u origin feat/list-md-plan-first-normative` を Loop モード自律実行禁止リスト (modes.md 遵守事項 8) で block。

しかし以下の事実から、現規範は過剰制約:
- 本 repo には既に `protected-branch-push-deny` layer (`delegation-guard.sh` の commit `ad2f7bc` 由来) で main / stg 系への push は別途 deny されている
- feature branch への push + PR 作成は preparation 範囲 (merge は user 明示承認必要だが、push と PR 作成は revert 容易)
- 本 session で push に 1 subagent + 複数試行コストを払い、最終的に Claude Code permission deny で user manual 委ねとなり、agent 経路を整備しても効果限定

→ autonomous-action-guard の禁止 pattern を **main/stg 系 push + PR merge のみ** に限定し、feature push + PR 作成は自律実行可とする。

## 2. 要件

- `git push origin <feature-branch>` (main/stg 以外) → agent 自律実行可
- `gh pr create` (target branch 問わず) → agent 自律実行可
- `git push origin main` / `git push origin stg*` → 既存 protected-branch-push-deny で block 維持 (二重ガード)
- `gh pr merge` → 引き続き user 明示承認必須 (autonomous-action-guard で block)
- `gh release create` / `git tag <name> origin|upstream` → 引き続き user 明示承認必須

ただし Claude Code permission system 自体の deny (memory `feedback_claude_permission_git_push_deny.md`) は本緩和では解消不可、agent 経路で push が真に動くかは別問題。

## 3. 設計案

### 案 A: autonomous-action-guard.sh の禁止 pattern 配列を直接削減

`AUTONOMOUS_RESTRICTED_PATTERNS` (default 配列) から:
- 削除: `^git[[:space:]]+push([[:space:]]|$)` 一般 push pattern
- 残存: `^gh[[:space:]]+pr[[:space:]]+merge` / `^gh[[:space:]]+release` / `git tag ... origin|upstream` 等

protected-branch-push-deny (`delegation-guard.sh`) との二重ガードで main/stg 系は別 layer で block 維持。

### 案 B: autonomous-action-guard.sh に「protected branch 指定 push のみ block」logic 追加

git push command を parse して target branch を抽出、main/stg 系のみ block。

- 強: 単一 hook で main/stg 系 push をカバー、protected-branch-push-deny との重複削減
- 弱: parse logic 追加で false positive リスク、`delegation-guard.sh` 既存 protected-branch-push-deny と重複

### 案 C: 案 A 採用 + protected-branch-push-deny 維持 (二重ガード継続)

二重ガードは defense-in-depth として運用上の安全性を高める。実装コスト最小。

## 4. 採用案 (案 C: 案 A + 二重ガード継続)

### 4.1 `autonomous-action-guard.sh` 変更

`AUTONOMOUS_RESTRICTED_PATTERNS` 配列から `git push` 一般 pattern を削除:

```bash
# Before
AUTONOMOUS_RESTRICTED_PATTERNS=(
    "^git[[:space:]]+push([[:space:]]|$)"
    "^gh[[:space:]]+pr[[:space:]]+(create|merge)"
    # ...
)

# After
AUTONOMOUS_RESTRICTED_PATTERNS=(
    # git push は protected-branch-push-deny (delegation-guard.sh) に委譲
    "^gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)"  # merge のみ block、create は許可
    # ...
)
```

### 4.2 protected-branch-push-deny 維持 (二重ガード)

`delegation-guard.sh` の既存 `check_protected_branch_push` 関数で `git push origin main|stg*` を block 維持。env override `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` も維持。

### 4.3 modes.md 遵守事項 8 table 更新

| カテゴリ | 対象コマンド | 例外 (準備として OK) |
|---|---|---|
| remote 反映 | ~~`git push` (any branch)~~ → `git push origin main\|stg*` のみ (protected-branch-push-deny) | feature branch への push は **自律実行可** (緩和) |
| PR / リリース | ~~`gh pr create`~~ / `gh pr merge` / `gh release` / `git tag <name> origin\|upstream` | `gh pr create` は **自律実行可** (緩和) |
| ... | (他カテゴリ不変) | ... |

### 4.4 新 smoke (7 cases、責務分担明示)

本 smoke は **autonomous-action-guard 単体の責務範囲** を検証する。main/stg 系 push の実 block は `delegation-guard.sh` の `protected-branch-push-deny` layer (別 hook) が担い、`.claude/tests/delegation-guard-deny-layers-smoke.sh` **48/48 PASS** で別途実証される (iter2 で HEAD:main 系 4 case + iter4 で --mirror/--all/--branches/--prune 4 case 追加)。本 smoke は autonomous-action-guard 緩和後に該当 pattern が **通過する**ことを確認し、実 block は別 layer に委譲されている責務分担を明示する。

- **Case 1**: `git push origin feature/foo` (feature branch、Loop mode) → **autonomous-action-guard 通過** (緩和効果、実際の push 可否は Claude Code permission system 側)
- **Case 2**: `git push origin main` (Loop mode) → **autonomous-action-guard 単体通過** (一般 push pattern 削除のため本 hook では block しない。実 block は `delegation-guard.sh` の `protected-branch-push-deny` layer が担当、smoke コメントで責務分担明示)
- **Case 3**: `git push origin stg-v1` (Loop mode) → **autonomous-action-guard 単体通過** (Case 2 と同責務分担、`delegation-guard.sh protected-branch-push-deny` で別 layer block)
- **Case 4**: `gh pr create --base main --head feat/foo` (Loop mode) → **autonomous-action-guard 通過** (緩和効果、PR 作成自律実行可)
- **Case 5**: `gh pr merge --merge` (Loop mode) → **autonomous-action-guard block** (user 明示承認必須維持、`gh pr merge` pattern 残存)
- **Case 6**: Loop mode + Normal mode 挙動差検証 (`git push feat/branch` を両 mode で実行) → **Loop mode 通過 / Normal mode は context inject (warn のみ、block しない)**。mode 別の hook 動作差を実証
- **Case 7**: Normal mode で `gh pr merge --merge` → **context inject (warn のみ、block しない)**。Normal mode では破壊的操作を block しない設計を実証 (Loop mode のみ block する責務分担)

**責務分担総括** (smoke 冒頭コメントに記載):
- autonomous-action-guard.sh = **漸減 layer** (緩和後は `gh pr merge` / release / tag push のみ block)
- delegation-guard.sh `protected-branch-push-deny` = **常時防御 layer** (main/stg 系 push を mode 問わず block)
- 二重ガード設計 (defense-in-depth) は intentional、本 smoke では autonomous-action-guard 単体責務のみ検証

## 5. リスク

- **二重ガード重複**: protected-branch-push-deny と autonomous-action-guard で main/stg 系 push を 2 度 block。冗長だが defense-in-depth で運用上安全
- **PR 作成過剰実行**: AI が draft PR を多数作成する可能性 → branch 命名規約 + PR title 規約で防止
- **誤 merge リスク**: `gh pr merge` は user 明示承認維持で対処、agent context で誤 merge 不可
- **`git push --force` / `--tags` / `--all` 等の variant は autonomous-action-guard 緩和の射程**: 緩和後、これら variant も autonomous-action-guard を通過する (一般 `git push` pattern 削除のため)。ただし以下の別 layer で防御:
  - **`git push --force` / `-f`**: `delegation-guard.sh` の `check_git_destructive` (10 patterns 中の destructive group) で block。bypass `ECC_ALLOW_GIT_DESTRUCTIVE=1`
  - **`git push --tags` で main/stg tag push**: 同 `protected-branch-push-deny` で `dst_basename` 解析時に main/stg* tag が含まれていれば block (既存実装で対応)
  - **`git push --all`**: 全 branch push、現状 `protected-branch-push-deny` の `git push --all` 専用解析は **未実装** (要 future task で smoke 追加検討、副産物 entry 候補 — `next-actions.md` 起票推奨)
  - intentional な設計分担: autonomous-action-guard = **漸減 layer** (緩和後は `gh pr merge` / release / tag push のみ block)、`delegation-guard.sh` = **常時防御 layer** (mode 問わず destructive / protected branch を block)。二重ガードは defense-in-depth として運用上の安全性を高める
- **Claude Code permission deny 残存**: 本緩和は autonomous-action-guard 層のみ、Claude Code permission system 自体は別途 push を deny する (memory `feedback_claude_permission_git_push_deny.md`)。本緩和実装後も agent 経路で push が動くかは別途検証必要

## 6. 完了条件 (DoD)

- [ ] `.claude/hooks/autonomous-action-guard.sh` `AUTONOMOUS_RESTRICTED_PATTERNS` 配列から `git push` 一般 pattern 削除 + `gh pr create` 削除 (`gh pr merge` は維持)
- [ ] `.claude/rules/modes.md` 遵守事項 8 table 更新 (緩和対象明示)
- [ ] 新 smoke `.claude/tests/autonomous-action-guard-relaxation-smoke.sh` **12 cases** PASS (R4 H1/H2 反映で iter2 で Case 8-12 拡張、`--force` / `--tags` / `--all` / `gh pr merge` flag variants 網羅)
- [ ] 既存 smoke regression 0 (`delegation-guard-deny-layers-smoke.sh` **48/48 PASS** 維持、iter2 で HEAD:main 系 4 case + iter4 で --mirror/--all/--branches/--prune 4 case 追加)
- [ ] 5+ reviewer iter cycle で strict 0-finding 収束 (採用 6 条 4)
- [ ] memory `feedback_claude_permission_git_push_deny.md` の実態確認 (本緩和後 agent 経路で push が動くか別途検証 task 起票)

## 7. 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/autonomous-action-guard.sh` + `.claude/rules/modes.md` + 新 smoke = 3 file |
| migration | なし |
| 環境変数 | 新規追加なし (既存 `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` + `ECC_ALLOW_PROTECTED_BRANCH_PUSH=1` で十分) |
| 互換性 | 既存 protected-branch-push-deny は不変、autonomous-action-guard が一部緩和のみ |

## 8. Phase 計画 (採用 6 条 4 準拠、Task = Phase = N Step)

- Step 1 (実装): autonomous-action-guard.sh 配列削減 + modes.md table 更新 (2 並列、独立 file 領域)
- Step 2 (テスト設計レビュー): 5+ reviewer 動的選定
- Step 3 (テスト合格): 新 smoke 12 cases PASS + 既存 smoke regression 0 (iter2/iter4 拡張: 5→12 cases + 40→48 cases)
- Step 4 (リファクタリング 3 観点): 配列削減のみで refactor 余地なし見込み (skip 想定)

## 9. 承認履歴

- 2026-05-25: 起案 (user 要望、本 session 末)
- 2026-05-25: **user 承認** (本 session 13th save-state、user 発言「draft 2 件レビュー + 承認 (parallel-subagent-enforcement / autonomous-action-guard-relaxation) → 問題ありません」)
- TBD: task #39 として起票 (`/new-task 39 autonomous-action-guard-relaxation`)
- TBD: 実装着手 (2 並列で本 draft 自身の dogfooding)
