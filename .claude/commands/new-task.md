---
description: 承認済 draft からタスクファイルを生成し、list.md に行を追加する。設計→承認→タスク化フローの最終ステップ。
---

# /new-task — 新規タスクファイル作成

`docs/draft/<slug>.md` の承認済設計から `docs/tasks/task-<id>-<slug>.md` を起こし、`docs/tasks/list.md` に新規行を追加する。

## 前提

**設計→承認→タスク追加フロー**（rules/development-process.md）を厳守:
1. `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から起こす
2. user に承認を得る
3. **このコマンド**で task ファイルを生成 + list.md 行追加

設計が無い状態でこのコマンドは使わない（hook が block する）。

## 使い方

```
/new-task <id> <slug>                              # 既定: phase 推定 / 依存自動解析
/new-task <id> <slug> --phase "Phase 11"           # phase 明示
/new-task <id> <slug> --depends "#33,#38"          # 依存明示
/new-task <id> <slug> --draft docs/draft/foo.md    # 設計 draft 明示指定
/new-task <id> <slug> --no-draft                   # 設計なしで作成（hot fix 等の例外、要 user 承認）
```

## 引数

- `<id>` — タスク番号（連番、または "11.3a" 形式の sub-id 可）
- `<slug>` — kebab-case の短縮名（例: `link-card-componentize`）

## 動作

### Phase 1: 前提チェック

1. `docs/draft/<slug>.md` の存在 + ステータスが「承認済」か確認
2. 既存 `docs/tasks/task-<id>-*.md` が無いことを確認（衝突回避）
3. `docs/tasks/list.md` に同 ID の行が無いことを確認

### Phase 2: テンプレ展開

1. `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` をコピー
2. プレースホルダ置換:
   - `<ID>` → タスク番号
   - `<タスク名>` → draft の H1 タイトル
   - 起案日 → 今日
   - 設計起源 → draft への相対リンク

### Phase 3: list.md 行追加

`list.md` のタスクテーブルに以下を追加:

```markdown
| <id> | 🔲 | <Phase> | <概要> | <依存> | [task-<id>-<slug>.md](task-<id>-<slug>.md) |
```

`<概要>` は draft の「真因サマリ」または「目的」から 1 行抽出。

### Phase 4: draft の取り扱い

- draft は `docs/draft/<slug>.md` に **残す**（設計履歴として）
- task ファイルから「設計起源」リンクで参照

### Phase 5: 承認確認 + 着手提案

```
✅ Task #<id> 起こしました。
  - docs/tasks/task-<id>-<slug>.md
  - docs/tasks/list.md に行追加 (🔲 未着手)

次の操作:
  /start-task <id>     ← 着手するなら
  /finish-task         ← この task は不要なら delete + parking-lot へ
```

## 制約

- **設計なし起こしは原則禁止**（`--no-draft` は hot fix 等で user 承認下のみ）
- ID 重複時は中断（既存タスクが進行中の可能性）
- list.md と個別ファイルを **必ず同時更新**

## 関連

- `/init-tasks` — テンプレ初期化
- `/start-task <id>` — 着手フロー
- `/new-draft <slug>` — 設計 draft 起こし（このコマンドの前段）
- rule: `.claude/rules/development-process.md`
