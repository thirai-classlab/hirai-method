# Next Actions（副産物 / 派生 task 候補レジストリ）

> 本セッション中・タスク実装中に発生した「副産物 (byproduct)」「派生 task 候補」「次セッションでやるべきこと」を **必ず記録する公式 location**。
>
> `list.md`（着手中・完了タスク台帳）/ `parking-lot.md`（設計済 + 保留タスク）/ `docs/draft/`（未承認設計）とは **別レイヤ** で、informal な「TODO / 次アクション候補」を捕捉する registry。

## 目的

副産物が「memory に保存されるだけ」「会話履歴に流れて消える」「次セッションで recall されない」状態を **構造的に防ぐ**。

HIRAI メソッドの硬性ルール「設計なしのタスク追加禁止」は維持しつつ、その手前で **informal な記録経路** を提供する。

## 処理フロー

```
副産物発生 (task 実装中 / セッション中 / レビュー中)
    ↓
[必ず] next-actions.md に entry 追加
    ↓
判断:
    (a) 即着手すべき + 設計必要 → /new-draft <slug> で draft 起こし → 承認 → /new-task → list.md
    (b) 着手不可 + 設計済 → parking-lot.md へ移行 (保留タスクとして)
    (c) 不要 → 無視。次セッション以降に削除（理由を「処理結果」列に明記）
    ↓
next-actions.md からエントリ削除（移行先を「処理結果」列に明記）
```

## エントリフォーマット

| 列 | 内容 |
|---|---|
| **#** | 連番 |
| **記録日** | YYYY-MM-DD |
| **タイトル** | 1 行で何をすべきか |
| **発生源** | どのタスク / セッションで発生したか（commit hash / task ID） |
| **緊急度** | 🔴 高 (次セッションで対応) / 🟡 中 (近日) / 🟢 低 (任意) |
| **推奨処理** | (a) draft 起こし / (b) parking-lot 移行 / (c) 無視 |
| **処理結果** | （処理後に記入）移行先または削除理由 |

---

## エントリ一覧

| # | 記録日 | タイトル | 発生源 | 緊急度 | 推奨処理 | 処理結果 |
|---:|---|---|---|:---:|---|---|
| 1 | 2026-05-12 | PR 作成 (`feat/loop-mode` → `main`) — 本セッション 18 commits の merge 動線 | 本セッション task #1 完了 (HEAD `b58bbf0`) | 🔴 | (a) draft 起こし or (c) 直 `gh pr create` | ✅ → [`docs/draft/create-pr-feat-loop-mode.md`](../draft/create-pr-feat-loop-mode.md) → [task #2](task-2-create-pr-feat-loop-mode.md) (2026-05-12) |
| 2 | 2026-05-12 | context-budget hook の実発火検証 — CB-verify 修正 (`5846925`) の運用効果観察 | 本セッション CB-verify (#9) | 🟡 | (a) draft 起こし `context-budget-hook-verification` | ✅ → [`docs/draft/context-budget-hook-verification.md`](../draft/context-budget-hook-verification.md) → [task #3](task-3-context-budget-hook-verification.md) (2026-05-12) |
| 3 | 2026-05-12 | CLAUDE.md `Critical Operational Lessons` に教訓 2 件転載 — 並列 subagent git 競合 / `set -e` leak in sourced libs | 本セッション feedback memory 保存時 | 🟡 | (a) draft 起こし `critical-lessons-transfer` | ✅ → [`docs/draft/critical-lessons-transfer.md`](../draft/critical-lessons-transfer.md) → [task #4](task-4-critical-lessons-transfer.md) (2026-05-12) |
| 4 | 2026-05-12 | **副産物 discharge 機構の本格実装** — `_TASK_TEMPLATE.md` 拡張 + `workflow-guard.sh` 拡張 + `/discharge-byproduct` command 新設 + `.claude/rules/workflow.md` セクション追加 | 本セッション「タスク管理されていない」指摘 | 🔴 | (a) draft 起こし `byproduct-discharge-mechanism` | ✅ → [`docs/draft/byproduct-discharge-mechanism.md`](../draft/byproduct-discharge-mechanism.md) → [task #5](task-5-byproduct-discharge-mechanism.md) (2026-05-12、本セッションで W1+W3+W6 着手中) |
| 5 | 2026-05-12 | classlab_salesforce-mail 修復 — `docs/draft/mail-message-status.md` 承認 + `/new-task 2` 起動 + task #1 W8 残作業完了 | 別リポ調査結果 | 🟢 | **本リポ管理外**（別リポ側で対応） | — |
| 6 | 2026-05-12 | Loop モード自律進行強制 + 自律実行禁止リスト — subagent 待ち中停止 / push 等の破壊的操作自律実行 を構造解決 (W1 modes.md 規範強化済、W2-W6 hook 実装 + smoke + 配線が残) | 本セッション user 指摘 (複数回「Loop モード継続中。なぜ自動で実行を続けないのか?」+「本番反映 / push 自律禁止」) | 🔴 | (a) draft 起こし済 → 次セッションで `/new-task 6` 起動 → 実装 | ✅ → [`docs/draft/loop-auto-progress-enforcement.md`](../draft/loop-auto-progress-enforcement.md) (W1 modes.md 反映済 2026-05-12)、W2-W6 は task #6 として次セッションで実装予定 |

## ルール（運用）

1. **副産物発生時の即時記録**: タスク実装中 / レビュー / セッション中に「これは別 task として管理すべき」と判断した瞬間、**memory に保存する前に** next-actions.md に entry を追加する
2. **`/finish-task` 完了条件**: task 完了時、メインは本ファイルの新規 entry が「すべて (a)/(b)/(c) のいずれかに処理されている」ことを確認する（**未処理 entry が残った状態での task 完了は禁止**）— 将来 W4 拡張で `workflow-guard.sh` が自動検証する
3. **セッション終了時のチェック**: PM Agent Session End Protocol で本ファイルを読み込み、未処理 entry を user に提示 + 推奨処理を提案
4. **メイン専任**: 本ファイルの更新は **メインエージェントのみ**。サブエージェントは記録しない（メインが報告を受けて記録する）
5. **保管期限**: entry は処理結果記入後 30 日で削除可。ただし「(c) 無視」エントリは過去意思決定のトレーサビリティとして履歴セクションに移動

## 履歴セクション

処理完了済 / 不採用となった過去 entry を時系列で残す。

（まだ履歴なし）

## 関連

- [`list.md`](list.md) — 着手中・完了タスク台帳
- [`parking-lot.md`](parking-lot.md) — 設計済 + 保留タスク
- [`../draft/`](../draft/) — 未承認設計
- [`.claude/rules/workflow.md`](../../.claude/rules/workflow.md) — workflow 強制機構（副産物 discharge は将来 W4 拡張で組み込み予定）
