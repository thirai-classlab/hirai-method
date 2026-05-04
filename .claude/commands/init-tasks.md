---
description: docs/tasks/ と docs/draft/ をテンプレートから自動生成（既存ファイルは温存）。SessionStart hook で自動実行されるが、明示的に走らせたい場合に。
---

# /init-tasks — タスク台帳の初期化

`docs/tasks/list.md` `parking-lot.md` `_TASK_TEMPLATE.md` および `docs/draft/_DRAFT_TEMPLATE.md` をテンプレートから配置する。

## 使い方

```
/init-tasks                # 不足分のみ作成（既存温存・冪等）
/init-tasks --force        # 全テンプレを上書き（破壊的、user 確認必須）
```

## 動作

`bash .claude/scripts/init-tasks.sh` を実行。

- **冪等**: 既存ファイルは絶対に上書きしない（`--force` 指定時のみ）
- **失敗安全**: テンプレが見つからなくてもセッションをブロックしない
- **自動実行**: SessionStart hook で `--quiet` モード自動呼出済（このコマンドは確認用）

## 出力例（新規プロジェクト）

```
[init-tasks] ✓ 作成: docs/tasks/list.md (タスク台帳)
[init-tasks] ✓ 作成: docs/tasks/parking-lot.md (Parking Lot)
[init-tasks] ✓ 作成: docs/tasks/_TASK_TEMPLATE.md (個別タスクひな型)
[init-tasks] ✓ 作成: docs/draft/_DRAFT_TEMPLATE.md (設計 draft ひな型)
[init-tasks] 完了（4 件処理）
```

## 出力例（整備済）

```
[init-tasks] = 既存温存: docs/tasks/list.md (タスク台帳)
[init-tasks] = 既存温存: docs/tasks/parking-lot.md (Parking Lot)
[init-tasks] = 既存温存: docs/tasks/_TASK_TEMPLATE.md (個別タスクひな型)
[init-tasks] = 既存温存: docs/draft/_DRAFT_TEMPLATE.md (設計 draft ひな型)
[init-tasks] 既に整備済（4 ファイル全て存在）
```

## 関連

- `/new-task <id> <slug>` — 個別タスクファイルを作成
- `/new-draft <slug>` — 設計 draft を作成
- rule: `.claude/rules/development-process.md`
- templates: `.claude/templates/docs/`
