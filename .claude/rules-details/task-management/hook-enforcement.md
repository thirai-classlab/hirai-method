> Layer A: [`task-management.md`](../../rules/task-management.md) §設計→承認→タスク追加フロー / Hook による強制 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# Hook 強制 詳細 (Layer B)

## 詳細シナリオ (PreToolUse、`task-rule-guard.sh`)

| シナリオ | 動作 | 備考 |
|---|---|---|
| `docs/tasks/task-<id>-<slug>.md` の Write、対応する `docs/draft/{<slug>.md, task-<slug>.md, <basename>}` が無い | **BLOCK** | 「先に `/new-draft` で設計を起こせ」と提示 |
| `docs/tasks/task-<id>-*.md` / `phase-<id>-*.md` の Write、同 `<id>` が既に存在 | **BLOCK** | 「別 ID を割り当てるか既存を Edit せよ」と提示 |
| `docs/tasks/` への命名規約外 Write (`task-` `phase-` で始まらない) | 警告 context 注入 (block しない) | 命名規約 hint |
| `docs/tasks/task-*.md` の **Edit** (既存編集) | context 注入 | 「list.md と同期更新せよ」 |
| `docs/tasks/parking-lot.md` の Edit | context 注入 | 必須 7 項目の hint |
| `list.md` `_TASK_TEMPLATE.md` `_DRAFT_TEMPLATE.md` の Edit/Write | exempt (素通り) | 台帳 / template は別系統 |
| サブエージェント実行中 | 全パス通過 | 多重ゲート防止 |

## subagent 通過理由

メイン専任の原則を機械強制するのは `delegation-guard.sh` (別 hook) の責務。`task-rule-guard.sh` は subagent context では全 path 通過し、メイン context での task ファイル創設 / 編集を主対象とする。

## 違反パターン例

- **設計 draft 不在のまま `/new-task` 強行** → BLOCK + 「`/new-draft <slug>` で設計を起こせ」案内
- **同 ID で別 slug を `/new-task`** → BLOCK + 既存 task.md path を案内
- **`docs/` 直下に直接設計書 Write** → `draft-flow-guard.sh` (別 hook) で BLOCK (本 hook 対象外)
