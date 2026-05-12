---
description: next-actions.md の指定 entry を処理 (draft 起こし / parking-lot 移行 / 無視) し処理結果列を更新する
args: <entry-number>
related: [/new-draft, /new-task, /task-bypass, .claude/rules/workflow.md, docs/tasks/next-actions.md]
---

# /discharge-byproduct — 副産物 entry の処理

`docs/tasks/next-actions.md` の **エントリ一覧** に記録された副産物 (byproduct) entry を、(a) draft 起こし / (b) parking-lot 移行 / (c) 無視 のいずれかで処理し、処理結果列を更新して entry を履歴セクションに移動する。

設計→承認→タスク追加フローの **前段** にある「副産物 discharge」ループを閉じるためのコマンド。

## 使い方

```
/discharge-byproduct <entry-number>
```

例:

```
/discharge-byproduct 4            # next-actions.md の # 4 entry を処理
```

## 引数

- `<entry-number>` — `docs/tasks/next-actions.md` の「エントリ一覧」table の `|  # |` 列に並ぶ整数。連番なので **未処理 entry のうち最大の番号 + 1** ではなく、**処理したい entry の現在の番号** を指定する。

## 動作

### Phase 1: 引数検証

1. `docs/tasks/next-actions.md` を Read
2. 「エントリ一覧」セクションを抽出し、指定 `<entry-number>` 行の存在を確認
3. 不在の場合: `❌ entry # <entry-number> が next-actions.md に見つかりません。/init-tasks で再生成 or 番号確認してください。` で中断
4. 既に処理結果列が **空でない** (`—` も含む) 場合: `⚠️  entry # <entry-number> は既に処理済 (処理結果: <既存値>)。再処理するなら手動で処理結果列を空に戻してから再実行してください。` で中断
5. **本リポ管理外** entry (例: 処理結果列が `—` 固定で「本リポ管理外」と推奨処理欄に明記) の場合: 「別リポで対応してください。本コマンドは本リポ entry のみ処理します」と user に提示して中断

### Phase 2: entry 読み取り

該当行から以下を抽出:

- **タイトル** — title 列の最初の `—` 区切り前 (例: `PR 作成 (feat/loop-mode → main)`)
- **発生源** — 発生源列
- **緊急度** — 🔴 / 🟡 / 🟢
- **推奨処理** — (a) / (b) / (c) の prefix

タイトルから **slug 候補** を kebab-case 化:

- 日本語 / 記号を除去
- 連続空白を `-` に
- 49 文字以内に切り詰め (`git-workflow.md` の branch 命名 regex に揃える)
- 例: `PR 作成 (feat/loop-mode → main)` → `create-pr-feat-loop-mode`

### Phase 3: 処理選択肢の提示

#### Normal モード (default)

user に以下を提示し、選択を待つ:

```
📋 entry # <N>: <タイトル>
    発生源: <発生源>
    緊急度: <緊急度>
    推奨処理: <推奨処理>

処理方法を選んでください:
  (a) draft 起こし    — /new-draft <slug 候補> を起動して docs/draft/<slug>.md 生成
  (b) parking-lot 移行 — docs/tasks/parking-lot.md に entry を transcribe (要設計書 link)
  (c) 無視             — 理由を入力してもらい、履歴に記録のみ

選択: (a / b / c)
slug (a の場合のみ、空なら推奨値): <slug 候補>
```

#### Loop モード時の挙動

- 緊急度 🔴 / 🟡: **(a) を default 採用**。slug は推奨値を使用。user 確認なしで進行
- 緊急度 🟢: user に提示して回答待ち (Loop モードでも保留判断は禁止 — 副産物が滞留しないよう必ず明示的処理を要求)

### Phase 4: 処理実行

#### (a) draft 起こし

1. `/new-draft <slug>` を **Skill tool 経由で起動** (内部 command 呼び出し)
   - `<slug>` は Phase 3 で確定した値
   - `--title <タイトル>` を渡す
   - `--origin <発生源>` を渡す
2. 生成された `docs/draft/<slug>.md` の path を保持
3. next-actions.md の処理結果列を更新:

```
✅ → [`docs/draft/<slug>.md`](../draft/<slug>.md) (YYYY-MM-DD)
```

4. user に通知:

```
📝 Draft 起こしました: docs/draft/<slug>.md
次の操作: 設計を埋めて user 承認後 /new-task <id> <slug>
```

#### (b) parking-lot 移行

1. `docs/tasks/parking-lot.md` に entry を append (必須 7 項目フォーマット):

```markdown
### 🧊 <タイトル>

**起案:** YYYY-MM-DD (next-actions.md entry # <N> から移行)
**保留日:** YYYY-MM-DD

**保留理由:**
<user に入力を求める>

**設計書:**
- (未起こし — parking-lot 入りには本来 docs/draft 起こしを推奨。理由を保留理由に明記すること)

**実装状態:**
- 未着手

**再検討トリガー (いずれか成立時に list.md へ移行):**
1. <user に入力を求める>

**代替現状:**
<user に入力を求める>

---
```

2. **設計書 link 必須** の制約上、user に「設計書 link 無しで parking-lot に入れる場合は理由を保留理由に明記してください。推奨は (a) draft 起こし → parking-lot 」と警告を提示
3. next-actions.md の処理結果列を更新:

```
🧊 → [`parking-lot.md`](parking-lot.md) #<N> (YYYY-MM-DD)
```

#### (c) 無視

1. user に **無視理由** を求める (空回答は禁止 → 再要求)
2. next-actions.md の処理結果列を更新:

```
❌ 無視: <理由> (YYYY-MM-DD)
```

### Phase 5: 履歴セクションへの移動

処理完了後 (a) / (b) / (c) いずれの場合も:

1. next-actions.md の「エントリ一覧」table から該当行を削除
2. 「履歴セクション」に移動 (時系列で append):

```markdown
| <N> | <記録日> | <タイトル> | <発生源> | <緊急度> | <推奨処理> | <処理結果> |
```

3. 「エントリ一覧」table の `#` 列はそのまま (番号の振り直しはしない — 履歴トレース可能性のため)

### Phase 6: 完了報告

```
✅ entry # <N> 処理完了
  処理方法: <a/b/c>
  処理結果: <移行先 link or 無視理由>
  next-actions.md 履歴セクションに移動済

次の操作:
  - (a) の場合: 設計を埋めて user 承認 → /new-task <id> <slug>
  - (b) の場合: 必要なら設計書 link を後追いで追加
  - (c) の場合: 同パターンの副産物発生時に同じ判断ができるよう CLAUDE.md / docs/tasks/ に教訓を記録
```

## エラーハンドリング

| シナリオ | 動作 |
|---|---|
| `<entry-number>` 不在 | `❌ entry # <N> が見つかりません` で中断 |
| `<entry-number>` 既処理 (処理結果列が空でない) | `⚠️  既に処理済 (処理結果: <既存値>)` で中断、再処理は手動 |
| 本リポ管理外 entry (例: 推奨処理欄に「本リポ管理外」明記) | 「別リポで対応してください」と user に提示して中断 |
| next-actions.md 自体が不在 | `❌ docs/tasks/next-actions.md が見つかりません。/init-tasks で再生成してください` で中断 |
| 「エントリ一覧」table の format 不正 (列数不一致 等) | format 不正の行を提示し、user に手動修復を依頼 |
| (a) で同 slug の draft が既存 | `/new-draft` 内部チェックで中断 → user に「既存 draft を編集するか別 slug にするか」を確認 |
| (b) で設計書 link 入力なし | warning を出して append は実行するが、保留理由に「設計書未起こし」を明記するよう user に要請 |
| (c) で無視理由が空 | `❌ 無視には理由が必要です。再入力してください` で再要求 |

## Loop モード時の挙動 (再掲)

- 緊急度 🔴 / 🟡 entry: **(a) draft 起こしを default 採用**。slug 推奨値で進行、user 確認省略
- 緊急度 🟢 entry: user に提示して回答待ち (副産物滞留防止のため Loop でも保留判断は禁止)
- 「本リポ管理外」 entry: Loop モードでも user に提示して中断 (誤処理防止)

## Normal モード時の挙動 (再掲)

- 全 entry で処理選択肢 (a)(b)(c) を user に提示して回答待ち
- slug 候補は提示するが user が上書き可能
- (c) 無視時の理由入力も user に求める

## 関連

- [`/new-draft`](new-draft.md) — (a) 処理で内部呼び出しされる設計 draft 起こしコマンド
- [`/new-task`](new-task.md) — (a) 処理後の draft 承認 → タスク化フロー
- [`/task-bypass`](task-bypass.md) — task-rule-guard の bypass (本コマンドとは別系統)
- [`.claude/rules/workflow.md`](../rules/workflow.md) — workflow 強制機構 (副産物 discharge は前段)
- [`docs/tasks/next-actions.md`](../../docs/tasks/next-actions.md) — 副産物 registry (本コマンドの対象 SSoT)
- [`docs/tasks/parking-lot.md`](../../docs/tasks/parking-lot.md) — (b) 移行先
- [`.claude/hooks/next-actions-surface.sh`](../hooks/next-actions-surface.sh) — SessionStart hook (未処理 entry 警告)
- [`.claude/hooks/byproduct-discharge-guard.sh`](../hooks/byproduct-discharge-guard.sh) — Stop hook (🔴 未処理 entry の BLOCK)
