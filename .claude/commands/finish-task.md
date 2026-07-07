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

### Phase 1.5: UI task 検出時の visual artifact 検証 (task-98、採用 6 条 4)

`docs/tasks/task-<id>-*.md` の changes に UI 拡張子 (`.tsx` / `.jsx` / `.vue` / `.svelte` / `.html` / `.css` / `.scss`) が含まれる場合、以下のいずれかを満たすことを確認:

- **visual artifact 存在**: `ls docs/tasks/ 2>/dev/null | grep -E "task-<id>-.*visual-.*\.(png|jpg|jpeg)"` で 1 件以上 hit
- **明示 bypass log**: 対応 task.md の Step 完了条件に `skip: UI 変更だが view 影響なし (<reason>)` 形式で bypass 理由が明記されている

いずれも不成立なら **warn 出力** (BLOCK しない、advisory):

```
[finish-task] WARN: UI 拡張子変更を含む task で visual artifact 不在 (task-<id>)
- 採用 6 条 4「UI 含 task = E2E + ビジュアル検証必須」の DoD 未達
- 対処: agent-browser skill で screenshot 取得 → docs/tasks/task-<id>-visual-<state>.png 配置
- bypass: Step 完了条件に "skip: UI 変更だが view 影響なし" と明示
```

判定は honor system + advisory (Phase 1.5 は Phase 3 以降を止めない)。UI 変更検出コマンド:

```bash
git diff main..HEAD --name-only | grep -E '\.(tsx|jsx|vue|svelte|html|css|scss)$|^(src|apps/[^/]+)/(components|pages|app)/|^components/'
```

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

### Phase 4.5: 本流統合 (mainline_integration_policy 連動、2026-06-03 task #77)

完了 commit 後、`mainline_integration_policy` に応じて本流統合を分岐する。SSoT は `docs/draft/git-integration-policy.md` §3.2 挙動表。policy 値は `bash .claude/scripts/hc-config.sh --get mainline_integration_policy` で確認 (default `pr-required`、不正 / 未知値は fail-safe で `pr-required` 扱い)、本流ブランチは `--get mainline_branch` (default `main`)。

**auto-merge は機械的順序 gate** (honor-system でなく手順として実行):

1. **smoke 実行**: `bash .claude/tests/run-all-smokes.sh` (または該当 task の smoke)
2. **exit 0 確認**: smoke 非 0 / conflict / security CRITICAL のいずれかなら **stop** (本流統合せず user 報告、modes.md 停止条件)
3. **`local-merge` / `local-merge-push` のみ本流統合**: merge 前に **mainline 存在確認**を必ず行う (draft §3.1 / git-workflow H3 / security H-1):
   - **存在確認**: `git show-ref --verify --quiet refs/heads/<mainline>` (ローカル) または `git ls-remote --exit-code origin <mainline>` (remote)。**不在なら error 停止** (`mainline=<mainline>` が存在しないため統合せず user 報告)。`git checkout` 自体も不在で fail するが、明示チェックでクリーンに停止する (honor-system 手順)
   - **ローカル本流 merge**: 存在確認 OK なら `git checkout <mainline> && git merge --no-ff <feature>`
   - **conflict 時**: `git merge --abort` して user 報告・停止 (自動解決禁止)
4. **`local-merge-push` のみ remote 本流 push**: `git push origin <mainline>`
   - **push 拒否時** (non-fast-forward 等): auto-retry / rebase せず **hard stop** + user 通知

| policy | Phase 4.5 動作 |
|---|---|
| `pr-required` (default) | 本流 merge せず、従来どおり commit 提案 (Phase 4) + `gh pr create` で PR 提示。本流 merge / push は user |
| `local-merge` | smoke green → ローカル `<mainline>` に `--no-ff` merge まで。「remote 本流 push は user」案内で停止 |
| `local-merge-push` | smoke green → ローカル merge → remote `<mainline>` push まで自律 |

**安全弁**: `stg*` / `release*` への push は全 policy で常に user (本 Phase 対象外)。`git-deny.sh` Tier1 が hook gate。

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
