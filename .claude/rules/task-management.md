<!--
task-21 W1.7: paths 条件付き受動 load を廃止し、常時参照 rule に格上げ。
理由: paths: ["docs/tasks/**", "docs/draft/**"] では当該 path を Read した
ターンしか context に load されず、設計→承認→タスク追加フローの認識が
落ちる事案 (recall_poc/docs/01-03 が docs/ 直下に直接 Write された)。
CLAUDE.md の Rules table で「(常時参照)」として明示し、毎セッション AI が
本 rule を読む状態にする。

task-26 W4: 設計→承認→タスク追加フロー / メイン専任 / Parking Lot の
SSoT として確立 (development-process.md / workflow.md から重複を本 file に
集約)。
-->

# タスク管理ルール

## メインエージェント専任（必須）

タスク管理はメインエージェントのみが行う。サブエージェントにタスク管理を委譲してはならない。

- `docs/tasks/list.md` のステータス更新 → メインが必ず実行
- 個別タスクファイルの作成・更新 → メインが必ず実行
- サブエージェント起動前にタスクを「進行中」に更新
- サブエージェント完了後にタスクを「完了」に更新

## 設計→承認→タスク追加フロー（必須）

**設計なしのタスク追加は禁止**。下記 4 ステップを厳守:

> **Loop モードでも本フローは免除されない** (task-21 W2.2)。`modes.md` 遵守事項 2「中間確認の停止」の禁止対象は **戦術判断のみ** で、設計文書の新規追加 / 仕様変更 / 戦略的判断 は引き続き user 承認必須 (例外条項あり、`modes.md` 遵守事項 2 参照)。Loop モードで「設計→承認」ステップを skip して `docs/` 直下に直接設計書を Write する行為は規範違反、`draft-flow-guard.sh` (commit `6ed9337`) が機械強制で BLOCK する。

1. **テンプレ初期化**（初回のみ・自動）: SessionStart hook で `docs/tasks/list.md` `parking-lot.md` `_TASK_TEMPLATE.md` および `docs/draft/_DRAFT_TEMPLATE.md` がテンプレートから自動生成される。明示実行は `/init-tasks`
2. **設計起こし**: `/new-draft <slug>` で `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から生成 → §1〜9 を埋める
3. **承認依頼**: ユーザーにレビュー・承認を依頼。承認履歴を draft の §8 に記録 (Loop モードでも必須、戦略判断は例外条項対象)
4. **タスク化**: 承認後に `/new-task <id> <slug>` を実行 — 以下が **同時に** 行われる:
   - `docs/tasks/task-<id>-<slug>.md` を `_TASK_TEMPLATE.md` から生成
   - `docs/tasks/list.md` に `🔲 未着手` 行を追加
   - draft は `docs/draft/<slug>.md` に保存（履歴として残す）

### テンプレートの場所

- `.claude/templates/docs/tasks/list.md` — タスク台帳ひな型（凡例・依存関係図・更新ルール込み）
- `.claude/templates/docs/tasks/parking-lot.md` — 保留タスクひな型（必須 7 項目フォーマット込み）
- `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` — 個別タスクひな型（背景 / 仕様 / 設計 / TDD / Wave / 完了条件 / 影響範囲）
- `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` — 設計 draft ひな型（真因 / 案比較 / Wave / リスク / DoD / 承認履歴）

### 自動生成のセーフティ

- **冪等**: 既存ファイルは絶対に上書きしない（`/init-tasks --force` のみ例外）
- **ID 重複検知**: `/new-task` は同 ID が既に存在する場合中断
- **設計欠落検知**: `/new-task` は対応 draft が無い場合中断（`--no-draft` で hot fix の例外）
- **fail-open**: SessionStart hook 失敗時もセッション継続

### Hook による強制（コマンド経由でなくても発動）

`.claude/hooks/task-rule-guard.sh` が PreToolUse で以下を **block** で強制する:

| シナリオ | 動作 |
|---|---|
| `docs/tasks/task-<id>-<slug>.md` の Write、対応する `docs/draft/{<slug>.md, task-<slug>.md, <basename>}` が無い | **BLOCK** — 「先に `/new-draft` で設計を起こせ」と提示 |
| `docs/tasks/task-<id>-*.md` / `phase-<id>-*.md` の Write、同 `<id>` が既に存在 | **BLOCK** — 「別 ID を割り当てるか既存を Edit せよ」と提示 |
| `docs/tasks/` への命名規約外 Write（`task-` `phase-` で始まらない） | 警告 context 注入（block しない） |
| `docs/tasks/task-*.md` の **Edit**（既存編集） | 「list.md と同期更新せよ」context 注入 |
| `docs/tasks/parking-lot.md` の Edit | 必須 7 項目の hint context 注入 |
| `list.md` `_TASK_TEMPLATE.md` `_DRAFT_TEMPLATE.md` の Edit/Write | exempt（素通り） |
| サブエージェント実行中 | 全パス通過（多重ゲート防止） |

### Bypass

| 方法 | 用途 |
|---|---|
| `ECC_TASKGUARD=off` | セッション全体で OFF |
| `/task-bypass <slug>` | 1 ファイル分 pre-clear（`.claude/.taskguard-state/<slug>.cleared`） |
| `/task-bypass --clear-all` | 全 marker 削除 |

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリに記録すること。

## チェックリスト

タスクを追加する際は以下を確認:

- [ ] `docs/draft/` に設計ドキュメントが存在するか
- [ ] ユーザーの承認を得たか
- [ ] `docs/tasks/list.md` の一覧テーブルを更新したか
- [ ] 個別タスクファイル（詳細リンク）を作成したか
- [ ] 設計ドキュメントへのリンクを含めたか

## 承認されていない設計

- 未承認の設計は常に `docs/draft/` に置く
- 承認済みの設計のみ `docs/tasks/` にリンクできる

## Parking Lot（今後検討タスク）

着手不可の保留タスクは [`docs/tasks/parking-lot.md`](../../docs/tasks/parking-lot.md) で管理する。テンプレは `.claude/templates/docs/tasks/parking-lot.md`。

**Parking Lot 運用ルール:**

- **追加条件**: 既存設計書（`docs/` 配下）または `docs/draft/` の承認済み設計へのリンクが必須。設計なし追加は禁止（通常タスクと同じ）
- **必須項目 7 つ**: 起案日 / 保留日 / 保留理由 / 設計書 / 実装状態 / 再検討トリガー / 代替現状
- **ステータス**: 🧊 保留 / 🔍 再検討予定 / ❌ 不採用
- **移行**: 再検討トリガー成立時に `parking-lot.md` から削除し、`list.md` に新規タスクとして追加（通常フロー = `/new-task`）
- **定期レビュー**: 🔍 エントリは四半期ごとに見直し。保留理由が消えていれば移行、未解消なら更新
- **不採用**: ❌ エントリは削除せず履歴として残す（過去意思決定のトレーサビリティ）

**`list.md` からの参照**: `list.md` 冒頭に parking-lot.md へのリンクを明記し、全タスク台帳として発見可能にする。

## タスク管理の関連コマンド

| コマンド | 役割 |
|---|---|
| `/init-tasks` | 台帳テンプレ初期化（SessionStart hook で自動実行） |
| `/new-draft <slug>` | 設計 draft 起こし（`_DRAFT_TEMPLATE.md` から） |
| `/new-task <id> <slug>` | 設計承認後にタスク化（`_TASK_TEMPLATE.md` から）+ list.md 行追加 |
| `/start-task <id>` | 着手（branch 切替 + status 同期） |
| `/finish-task <id>` | 完了（build/test/docs 検証 + done 化 + commit 提案） |
| `/task-bypass <slug>` | task-rule-guard を 1 ファイル分 bypass（hot fix 用） |
