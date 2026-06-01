> Layer A: [`workflow.md`](../../rules/workflow.md) §設計レビューの fan-out (W2) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# fan-out reviewer-registry 詳細 (Layer B)

`/design-review` の stack heuristic 絞り込み / 集約フォーマット / reviewer 最低数 3 体の理由。reviewer-registry 表・収束条件・並列数制御は Layer A 参照。

## stack heuristic 絞り込み

draft 本文を grep して以下キーワードを検出し、不要な reviewer を除外:

- `database` / `migration` / `RLS` 不在 → database-reviewer skip
- `API` / `endpoint` / `REST` / `GraphQL` 不在 → api-designer skip
- `UI` / `component` / `frontend` 不在 → ui-designer skip

`--skip-stack-filter` で全件起動、`--max-reviewers N` で上限指定可。

## 集約フォーマット

各 reviewer の SubagentStop 通知を受けたら findings を `docs/draft/<slug>-review.md` に append:

```markdown
## <reviewer-name> (iter <N>)
- [CRITICAL] <finding summary> — <修正コード提案>
- [HIGH] <finding summary> — <修正コード提案>
- [MEDIUM] <finding summary> — <修正コード提案>
- [LOW] <finding summary>

confidence: 0.X
```

全件完了後に severity 別件数サマリ表 + blocking findings (CRITICAL / HIGH / MEDIUM) + 各 reviewer の confidence score 一覧を提示。

## reviewer 最低数 3 体の理由

- 1 体 → 偏り過大 (1 視点のみ)
- 2 体 → 同意 / 不同意の二択判定不能 (合議制成立せず)
- 3 体 → 過半数判定可能 (2-1 で多数決成立)
- 5+ 体 → テスト設計レビュー (採用 6 条 4) と同水準、cost と quality のバランス

registry 件数不足で 3 体起動不能なら user escalation (`/design-review --max-reviewers 2 --escalate-low-count`)。
