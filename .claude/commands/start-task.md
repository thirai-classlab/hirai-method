---
description: タスク開始の定型化。docs/tasks/list.md からタスクを取得し、関連 design doc を読み、branch を切り、status を in_progress に更新する。
---

# /start-task — タスク開始フロー

`docs/tasks/list.md` の真実源と branch / status を同期させる。

## 使い方

```
/start-task 41                  # task-41-*.md を起動
/start-task 41 --branch feature/issue-41-snapshot   # branch 名指定
/start-task 41 --no-branch      # branch を切らない (main で進める)
```

## 動作

### Phase 0: 台帳の存在確認（auto-init）

1. `docs/tasks/list.md` が存在するか確認
2. 無ければ `bash .claude/scripts/init-tasks.sh` を実行してテンプレから初期化
3. それでも無ければ「`/init-tasks` を先に実行してください」と中断

### Phase 1: タスク存在確認

1. `docs/tasks/list.md` を読み、`#41` (or 指定 ID) のステータスを確認
2. `docs/tasks/task-41-*.md` の存在確認
   - **見つからない**: `docs/draft/` を探索 → 設計が draft 段階なら「**まず承認を得てください**」と中断
   - 承認済 draft はあるが task ファイル未生成: 「`/new-task <ID> <slug>` でタスクを起こしてください」と案内
3. ステータスが `done` / `in_progress` の場合は警告(再開 or 重複の意図確認)

### Phase 2: 依存タスク確認

`task-41-*.md` 内の "Depends on:" セクションを解析し、依存タスクの状態を確認:

- 依存タスクが未完了 → 警告して中断 / 強制続行を選択
- 依存タスクが parking-lot 行き → 設計再確認を促す

### Phase 3: branch 操作

CLAUDE.md "Autonomous Progression" のルールに従い:

```bash
# 既に同名 branch があれば checkout
git switch -c feature/issue-41-snapshot 2>/dev/null || git switch feature/issue-41-snapshot
```

`--no-branch` 指定時は main のまま進める。

### Phase 4: ステータス更新

`docs/tasks/list.md` の該当行を `todo` → `in_progress` に変更。
個別ファイル `task-41-*.md` の `Status:` 行も同期。

### Phase 5: 設計書サマリ + 着手点提示

```markdown
## #41 開始: <タスク名>

**設計書**: `docs/tasks/task-41-snapshot-content-version-management.md`
**Status**: `todo` → `in_progress` ✅
**Branch**: `feature/issue-41-snapshot` (current)
**依存**: #33 ✅ done / #38 ✅ done

### 設計サマリ(設計書の要約)
- Wave 1: スナップショット取得 (post.ts 改修)
- Wave 2: ロールバック CLI (rollback.ts 新設)
- ...

### 着手推奨
1. (TDD) Wave 1 のテスト観点出し → `Agent(/sc:test)`
2. その後 Red → Green → Refactor
```

## 制約

- **設計なしでタスクを開始しない**(development-process.md 違反、PreToolUse hook でも block される)
- ブランチ名は CLAUDE.md "Autonomous Progression" に従い main 直 push が許される範囲を尊重
- main 直編集を避けたい時は `--branch` 指定を user に確認

## 関連

- [`/finish-task`](finish-task.md) — タスク完了の対の動作
- [`development-process.md`](../rules/development-process.md) — 設計→承認→タスク化フロー
- [CLAUDE.md "Autonomous Progression"](../../CLAUDE.md#autonomous-progression自律進行ルール) — branch / push 範囲
- [`docs/tasks/list.md`](../../docs/tasks/list.md) — タスク台帳真実源
