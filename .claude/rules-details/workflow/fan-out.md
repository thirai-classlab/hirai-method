> Layer A: [`workflow.md`](../../rules/workflow.md) §設計レビューの fan-out (W2) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# fan-out reviewer-registry 詳細 (Layer B)

`/design-review` の reviewer-registry 表 / 並列数制御 / 収束条件 / stack heuristic 絞り込み / 集約フォーマット / reviewer 最低数 3 体の理由。Layer A は要約のみ。

## reviewer-registry (`harness-config.yml`)

| キー | 起動対象 agent | 用途 |
|---|---|---|
| `reviewer_registry_design` | architect / architect-reviewer / code-architect / api-designer / ui-designer / database-reviewer / harness-optimizer | W2 `/design-review` |
| `reviewer_registry_security` | security-auditor / security-reviewer / penetration-tester | W2 `/design-review` |
| `reviewer_registry_test` | tdd-guide / test-automator / qa-expert / pr-test-analyzer | W1 `/test-design` |
| `reviewer_registry_impl` | code-reviewer / refactoring-specialist / 言語別 reviewer 群 | W3 `/module-review` `/system-review` |

env 上書き例: `export HC_REVIEWER_REGISTRY_DESIGN=$'architect\narchitect-reviewer'` (改行区切り) で cost 制御可。

## 並列数 / 反復制御

`review_required_design` (default true) / `review_min_count_design` (default 3) / `review_max_count_design` (default 7) / `review_iteration_max` (default 5) で制御。`hc-config.sh --get review_min_count_design` で現在値確認、`--set` で変更 (atomic backup)。値解決順 `env > harness-config.local.yml > harness-config.yml > default`。

## 収束条件 (反復ループ)

draft レビューは「修正 → 再レビュー」を **CRITICAL + HIGH + MEDIUM = 0** になるまで反復 (LOW は許容、cosmetic finding として記録のみ)。

| 規約 | 内容 |
|---|---|
| **reviewer 最低数** | **3 体以上** 並列起動 (default は reviewer-registry 全件 + stack heuristic 絞り込み、`N ≥ 3` 必須、不足で user escalation) |
| **件数取得 severity** | CRITICAL / HIGH / MEDIUM / LOW の 4 段階 |
| **収束条件** | CRITICAL = 0 ∧ HIGH = 0 ∧ MEDIUM = 0 (LOW は許容) |
| **反復上限** | 5 回 (default、超過時 user escalation) |
| **iteration 記録** | 各 iter の reviewer / 件数 / 修正 commit hash を draft §「レビューサイクル」table に append |
| **bypass** | `ECC_DESIGN_REVIEW_OFF=1` (反復 5 回上限超過時の user escalation 後の継続用) |

CRITICAL / HIGH / MEDIUM 全て 0 件 → draft「承認待ち」へ遷移可、1 件以上 → 「修正待ち」状態を明示し draft 修正 → 再 `/design-review` で round-N+1 review。

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
