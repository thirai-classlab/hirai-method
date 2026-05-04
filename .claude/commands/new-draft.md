---
description: docs/draft/ に設計 draft を起こす。設計→承認→タスク追加フローの起点。
---

# /new-draft — 設計 draft 起こし

`docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から生成。設計→承認→`/new-task` でタスク化、というフローの最初のステップ。

## 使い方

```
/new-draft <slug>                          # 例: link-card-componentize
/new-draft <slug> --title "<タイトル>"     # H1 を明示
/new-draft <slug> --origin "<起点>"        # 「ユーザー報告 / 監査 / 障害」等
```

## 引数

- `<slug>` — kebab-case（最終的な task ファイル名と揃える）

## 動作

### Phase 1: 既存確認

- `docs/draft/<slug>.md` が存在しないことを確認
- 存在する場合は中断（既存編集を促す）

### Phase 2: テンプレ展開

1. `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` をコピー
2. プレースホルダ置換:
   - `<設計タイトル>` → `--title` 引数 or slug を Title-Case 化
   - 起案日 → 今日
   - `<起点>` → `--origin` 引数 or 「user 依頼」

### Phase 3: 起案案内

```
📝 Draft 起こしました: docs/draft/<slug>.md

次の操作:
  1. ファイルを開いて H1〜セクション 9 を埋める
  2. mermaid 図 / 案比較 / Wave 分割 / リスク 等を充実させる
  3. user にレビュー・承認を依頼
  4. 承認後: /new-task <ID> <slug> でタスク化
```

## 設計テンプレの章立て

`_DRAFT_TEMPLATE.md` は以下の構成:

1. 真因サマリ / 課題サマリ
2. 解決アプローチ比較（複数案 + 推奨）
3. 採用案の詳細設計（Wave / Sub-task 分割）
4. リスクと緩和
5. 移行計画
6. 完了条件（DoD）
7. 工数見積
8. 承認履歴
9. 関連

## 関連

- `/new-task <id> <slug>` — 設計承認後にタスク化
- `/init-tasks` — テンプレ初期化
- rule: `.claude/rules/development-process.md` 「設計→承認→タスク追加フロー」
- 例: `docs/draft/task-<slug>.md`（`<slug>` は kebab-case の機能名）
