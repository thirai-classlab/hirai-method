> Layer A: [`workflow.md`](../../rules/workflow.md) §reviewer prompt 共通規約 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# reviewer prompt 共通規約 詳細 (Layer B)

reviewer prompt 共通規約の必須項目 5 (table) は Layer A 参照。本 file は起源 / 各項目の詳細手順 / OK-NG 例 / 既存規約との関係 / commands 連携 / bypass 運用詳細。

## 起源 (2026-05-28 user 直接指示)

PR #28 merge 後の session で user 直接指示「設計後,テスト設計後レビューする際プロジェクトの内容や、他のタスクの内容も鑑みてレビューするようにプロンプトを修正してください」を反映。task-51 iter 2 reviewer 6 並列レビューでも reviewer が single draft inside-out のみ評価し、他 task 重複 / 既存規範矛盾 / 既存実装再利用機会の検出が弱かった経験を踏まえ、reviewer prompt 共通規約として明文化する。

## 必須項目 5 (詳細手順、Layer A §「reviewer prompt 共通規約」table 補完)

1. **task ledger 確認 (`docs/tasks/list.md`)**:
   - 🔄 進行中 task: 並行で着手中の作業との重複 / 競合可能性
   - 🔲 未着手 task: 本対象が前提崩壊させないか / 順序整合性
   - 📝 計画中 task: master roadmap 経路 B (batch planning) との重複
   - ✅ 完了 task: 本対象が既に解決済の問題を再発明していないか

2. **依存先 task.md + draft.md (task-management.md 開発開始時必読義務 準拠)**:
   - 本対象 draft の「依存」section に列挙された task ID 全件
   - draft §「関連 / 派生」section のリンク先
   - 各 task の Task ゴール + 完了条件 + 影響範囲を確認

3. **副産物 registry (`docs/tasks/next-actions.md`)**:
   - 未処理 🔴 緊急 / 🟡 推奨 entry を全件 Read
   - 本対象が解決 / 関連 / 影響する entry を特定し、findings で「entry #N を本対象で解決可」のように参照

4. **既存規範 (`.claude/rules/*.md` Layer A 全 7 file)**:
   - `development-process.md` (TDD / 委譲ガード / Bash 制御 / 並列化義務 等)
   - `task-management.md` (採用 6 条 / parking-lot / 開発開始時必読義務)
   - `workflow.md` (14/10-stage / W1-W4 / 20 MECE / fan-out registry / 本規約)
   - `modes.md` (Normal/Loop / 9 遵守事項 / 自律実行禁止 11 カテゴリ)
   - `self-improvement.md` (L1-L5 + F1/F2)
   - `why-x5-output.md` (1 行 format)
   - `git-workflow.md` (branch 命名規約)
   - 本対象が上記規範と矛盾していないか / 規範更新が必要か判定

5. **プロジェクト構造 / SSoT (`README.md` + `docs/INVENTORY.md`)**:
   - architecture diagram / Layer A/B Strategy 等の最新版を確認
   - 本対象が SSoT を破壊していないか / 拡張すべき INVENTORY entry はあるか

6. **既存実装 patterns 探索 (Glob/Grep)**:
   - `.claude/hooks/` 配下: 類似 hook が既存なら本対象との関係を findings に明記
   - `.claude/commands/` 配下: 類似 command 再利用 / 拡張で対応可能なら再発明回避を推奨
   - `.claude/skills/` 配下: 類似 skill 流用 / 拡張可能性
   - 既存 utility (`.claude/scripts/` `.claude/hooks/lib/`) の流用機会

## OK 例 (適切な findings 反映)

- **「task-51 の Layer A/B 構造と本 draft の規範文書追加方針が整合 (Layer A 要約 + Layer B 詳細の 2 層構造で書く)」** — 既存規範整合性確認
- **「next-actions.md entry #56 (Layer A/B template 整備) が本 draft で解決される、本 PR merge 時に entry #56 を `→ 解決` status に更新せよ」** — 副産物連動
- **「既存 `.claude/hooks/task-rule-guard.sh` の Edit/Write block ロジックが本 draft の新 hook と重複、既存 hook 拡張で対応すべき」** — 既存実装再利用機会
- **「task-21 W3 が UserPromptSubmit 注入数削減を進行中、本 draft の新 hook (`hook-X.sh`) は UserPromptSubmit に注入を追加するため、task-21 W3 の進捗と矛盾」** — 他 task 競合検出
- **「README.md §2.6 Layer A/B Strategy table と本対象の path 規約が不整合、README 同期更新が必要」** — SSoT 整合性

## NG 例 (不適切なレビュー、本規約違反)

- **「本 draft 内の §3 採用案 architecture が clean (SOLID 準拠)」** — inside-out only、他 task 影響 / 既存実装再利用 等の観点が欠落
- **「security 観点: 入力検証 OK」** — single draft レベルの security 観点のみで、`.claude/rules/development-process.md` の cross-repo write 例外 / staging 戦略との整合確認なし
- **「実装提案: 新 file `.claude/hooks/new-hook.sh` を作成」** — 既存 `.claude/hooks/` 内に類似 hook 不在を Glob で確認せずに「新規作成」推奨
- **「task ledger 確認: 関連なし」 (実際は list.md を Read していない)** — Read 不在のまま「関連なし」と結論

## 既存規約との関係

- **behavior-preserving 原則** ([`module-review.md`](../../commands/module-review.md) Phase 3): 本規約と直交、両方適用。本規約は**レビュー範囲の拡張** (project context)、behavior-preserving は**修正提案の制約** (public API / DB schema 変更禁止)。
- **末尾 `confidence: 0.X`** (F3 confidence-gate): 本規約遵守度も confidence 算出に反映。項目 5 の Read 不在 / 不充分は confidence 0.6-0.7 程度に留まるべき (高すぎる confidence は不正確)。
- **採用 6 条 4 テスト設計レビュー** ([`task-management.md`](../../rules/task-management.md) 採用 6 条 4): main agent が reviewer 5+ 動的選定して prompt を構築する際、本規約 項目 5 を必ず含める。

## commands 連携

| command | 規約反映先 |
|---|---|
| `/design-review` Phase 3 prompt template | 「対象 draft 全文 + 観点 + findings format + confidence + **項目 5: プロジェクト整合性 + 他 task 影響確認**」 |
| `/test-design` Phase 3 agent prompt (tdd-guide / test-automator / qa-expert) | 「20 カテゴリ採用推奨 + **項目 5: プロジェクト整合性確認** (他 task のテスト戦略との重複検出 + 既存 test infrastructure 流用機会)」 |
| `/module-review` Phase 3 | 「3 観点 + 項目 5: モジュール変更が他 task / 既存規範 / SSoT に与える影響」 |
| `/system-review` Phase 3 | 「system-level 3 観点 + 項目 5 強化 (system 全体の cross-task 影響)」 |
| 採用 6 条 4 (main ad-hoc dispatch) | main agent が reviewer 5+ subagent dispatch 時、各 prompt 末尾に「**項目 5: プロジェクト整合性確認**: list.md / 依存先 task / next-actions / 既存規範 / README+INVENTORY / 既存実装 Glob を必ず実施」明記 |

## bypass の運用詳細

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` の**正当な使用ケース** (honor system):

- typo 1 行修正の `/module-review`
- comment-only refactor の review
- 既に直前の他 review (round-1) で project context 確認済の追加 round (round-2 以降、新規 finding 解消のみ目的)
- hot fix bypass (緊急障害対応で review skip)

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` の **NG ケース** (bypass 禁止):

- 新規 feature の `/design-review` 初回 (round-1)
- `.claude/rules/` 編集を含む change の review
- 採用 6 条 4 のテスト設計レビュー初回 (round-1)
- 規範変更 (`docs/draft/` 新規起案) の review
- 設計 / architecture 大幅変更の review

## Loop モード時の動作

Loop モード稼働中 (modes.md 遵守事項 2 例外条項) でも、本規約は**戦術判断扱い** (実装中の方式選択と同等で、user 中間確認不要)。reviewer subagent は Loop モードでも自律で項目 5 の全 Read を実施する。

`HC_REVIEW_PROJECT_CONTEXT_REQUIRED=false` 適用時のみ、reviewer が項目 5 を skip しても block しない (bypass.log に記録)。
