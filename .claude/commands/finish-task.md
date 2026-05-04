---
description: タスク完了の定型化。完了 3 点を検証し、list.md を done に更新、/preflight + /commit を促す。
---

# /finish-task — タスク完了フロー

task-flow.md の完了条件 3 点を機械的にチェックし、`docs/tasks/list.md` のステータス同期 + 後続アクション推奨まで実施。

## 使い方

```
/finish-task 41                # 現在の作業状態から #41 を完了処理
/finish-task 41 --skip-preflight   # /preflight を別途実行済の場合
```

## 動作

### Phase 1: 完了 3 条件の機械検証

development-process.md「タスク管理」より:

```markdown
- [ ] 実装が動作している
- [ ] テストが通っている
- [ ] 設計と実装の差分が docs/ に反映されている
```

具体チェック:

| 条件 | 検証コマンド | 自動判定 |
|------|-----------|---------|
| 実装が動作している | `npm run build` | exit 0 |
| テストが通っている | `npm run test` | 全 PASS |
| docs 反映 | `git diff main..HEAD -- docs/tasks/task-41-*.md` | 差分が non-empty |
| `list.md` 更新 | `grep -E '#41.*in_progress' docs/tasks/list.md` | hit |

### Phase 2: /preflight 自動起動 (--skip-preflight でなければ)

```
内部で /preflight を呼び出す → ❌ あれば中断、修正促す
```

### Phase 3: ステータス更新

- `docs/tasks/list.md` の `#41` 行: `in_progress` → `done`(完了日 + commit hash 候補メモ)
- `task-41-*.md` の `Status:` 行: `done` に変更
- `parking-lot.md` 移動候補があれば確認(設計が `done` だが実装が条件付きで延期 等)

### Phase 4: commit 提案

`/commit` を内部呼び出し or ユーザーに促す:

```
推奨 commit:
docs(tasks): #41 done — content version management + DB overwrite fail-safe (+47 tests, 409 S3 images rescued)
```

(既存 commit log のパターンに揃える: `docs(tasks): #N done — <summary> (...)`)

### Phase 5: 完了報告フォーマット

CLAUDE.md "Autonomous Progression" の報告フォーマットに沿う:

```
#41 <タスク名> 完了。
累計 +<N> tests、commit <count>、push 済 <URL>。
memory 同期しました。
```

## 制約

- 完了 3 条件のいずれか failed → `done` 化を**拒否**(`in_progress` のまま)
- `docs/tasks/list.md` と個別ファイルの両方を**同期** — 片方のみ更新は禁止
- 完了報告に **嘘をつかない**(test 数は実数値、commit hash は実ハッシュ)

## 関連

- [`/start-task`](start-task.md) — 対の動作
- [`/preflight`](preflight.md) — 完了前の必須検証
- [`/commit`](commit.md) — 後続の commit 生成
- [`development-process.md`](../rules/development-process.md) — 完了条件の定義
- [CLAUDE.md "Autonomous Progression"](../../CLAUDE.md#autonomous-progression自律進行ルール) — 完了報告フォーマット
