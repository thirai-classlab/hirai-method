> Layer A: [`task-management.md`](../../rules/task-management.md) §Parking Lot | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# parking-lot 詳細 (Layer B)

## 必須 7 項目 format

```markdown
### 🧊 <task 名>

- **起案日**: YYYY-MM-DD
- **保留日**: YYYY-MM-DD
- **保留理由**: <なぜ着手不可か>
- **設計書**: [docs/draft/<slug>.md](...) or [docs/<existing>.md](...)
- **実装状態**: <現状把握、partial 実装あれば link>
- **再検討トリガー**: <何が起きたら 🔍 に昇格するか>
- **代替現状**: <保留中の代替手段 or 影響範囲>
```

## 定期レビュー

🔍 entry は四半期 (3 ヶ月) ごとに見直し:

- 保留理由が消えていれば → `list.md` に新規 task として追加 (`/new-task`)、parking-lot.md から削除
- 未解消なら → 再検討トリガー / 代替現状を更新

❌ 不採用 entry は削除せず履歴として残す (過去意思決定のトレーサビリティ)。
