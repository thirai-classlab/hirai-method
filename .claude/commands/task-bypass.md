---
description: task-rule-guard の draft 名一致 / ID 重複 check を 1 ファイル分だけ pre-clear する。hot fix や緊急対応の例外用。
---

# /task-bypass

`task-rule-guard.sh` のチェックを **特定 slug 分だけ** スキップする bypass marker を作成する。

## 使い方

```
/task-bypass <slug>          # docs/tasks/task-<id>-<slug>.md の Write を 1 回だけ通す
/task-bypass --list          # 現在の cleared 一覧
/task-bypass --clear <slug>  # bypass marker 削除
/task-bypass --clear-all     # 全 marker 削除
```

## 引数

- `<slug>` — kebab-case のタスクスラグ（task-39-link-card.md なら `link-card`）

## 動作

1. `.claude/.taskguard-state/<slug>.cleared` を `touch`
2. 次の Write 時に task-rule-guard が marker を検知して通過
3. marker は手動削除するまで残る（永続）

## 出力例

```
✓ /task-bypass link-card
  marker: .claude/.taskguard-state/link-card.cleared
  次の Write は task-rule-guard を通過します。
  draft 不在・ID 重複でも通る点に注意。
```

## いつ使うか

| シーン | 推奨対応 |
|---|---|
| hot fix（draft 起こす時間がない緊急対応） | `/task-bypass <slug>` → 後追いで draft を埋める |
| 既存 task ファイルの大幅再構成（--force 相当） | `/task-bypass <slug>` |
| 別命名規約からのマイグレーション | `ECC_TASKGUARD=off` セッション全体 OFF |
| sub-agent からの自動生成 | bypass 不要（subagent passthrough で自動通過） |

## 全体 bypass

セッション全体で OFF にしたい場合:

```bash
export ECC_TASKGUARD=off
# 以降の Edit/Write はすべて task-rule-guard を素通り
```

## ガードの効果（強制対象）

`task-rule-guard.sh` は以下を強制:

- **ID 重複**: 同 ID の task-*.md / phase-*.md が既存なら BLOCK
- **draft 名一致**: docs/draft/{<slug>.md, task-<slug>.md, <basename>} のいずれかを要求、無ければ BLOCK
- **既存 Edit**: list.md と同期更新を促す additionalContext 注入（block しない）
- **parking-lot.md 編集**: 必須 7 項目 hint 注入（block しない）
- **命名規約外**: list.md 対応確認の警告（block しない）

## 関連

- `.claude/hooks/task-rule-guard.sh` — 実体
- `.claude/rules/development-process.md` — 設計→承認→タスク化フロー
- `/new-draft` `/new-task` — 正規ルートのコマンド
- `/init-tasks` — テンプレ初期化
