> Layer A: [`task-management.md`](../../rules/task-management.md) §タスク構造規範 — 採用 6 条 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 採用 6 条 詳細 (Layer B)

## 改定理由 (3 問題、task-33 実例観測)

1. **粒度過剰**: task-33 が 5 Phase × 14 Step で deliverable として scope 過大
2. **status 不可視**: list.md row が task 単位のみ、Step status が IDE 視点で追跡不可
3. **概要欄混在**: list.md 概要列が task overview / step description 区別なく記載

## 条 2 詳細 (Task 必須項目 5 件)

「観察可能」とは PASS/FAIL or 数値 or before/after diff のように第三者が客観確認できる粒度を指す:

- OK 例: 「全テスト 92/92 PASS」「list.md に新 entry 1 行追加」「Layer A size 元 33K → 目標 ~10K」
- NG 例: 「動くようにする」「整理する」「適切に処理」(検証不能)

依存先タスクは「**`task-N1, task-N2` 形式で ID 列挙**」 + 各依存先について Task header section に **影響内容 (1-2 文) + 依存先 task.md へのリンク** を記載。

## 条 3 詳細 (Step 必須項目 4 件)

「test PASS」のような曖昧表現ではなく、再現可能な検証コマンドを書く:

- OK 例: 「`bash .claude/tests/foo-smoke.sh` exit 0」「`grep -c '...' file.md` で 2 件以上」
- NG 例: 「動作確認」「テスト OK」「正常終了」

## 条 4 詳細 (テスト設計レビュー)

**動的選定の判定ヒント** (固定 registry 不採用、case-by-case):

- **常時 base 候補**: tdd-guide / test-automator / qa-expert / pr-test-analyzer
- **UI 含む** → ui-designer / accessibility-tester / e2e-runner 加味
- **DB schema / migration** → database-reviewer / postgres-pro 加味
- **API 変更** → api-designer / api-documenter 加味
- **言語特定** → 言語別 reviewer (python-reviewer / typescript-reviewer / go-reviewer / rust-reviewer 等) 加味
- **security 影響** → security-reviewer / security-auditor 加味
- 上記から **`review_min_count_test`〜`review_max_count_test` の範囲内**で動的選定 (青天井「5+」は task-64 で廃止)。起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` で上限を確認し、並列起動数 N が `min ≤ N ≤ max` に収まることを保証する

**ビジュアル検証 (browser/web UI、E2E とは別レイヤ、2026-05-27 採用、draft `ui-visual-verification-mandate.md`)**:

- `agent-browser` skill (vercel/agent browser) で実際にブラウザ描画 → screenshot 取得 → 目視確認
- 主要 breakpoint (320/768/1024/1440 等) / 主要状態 (hover/focus/active/error 等) / 両 theme (あれば) を撮影
- レイアウト / 配色 / タイポグラフィ / 余白 / レスポンシブ が設計意図通りか確認 (可能なら before/after 比較)
- E2E (機能フロー動作) とは別の品質軸。**両方 PASS で初めて UI Task 完了**、E2E のみ / 型チェックのみでは完了宣言しない
- 非対話 / CI 環境は Playwright screenshot で代替可。honor-system (機械強制 hook なし)

**yml 値による制御 (task-44/45/46、task-64 で enforcement 化 + local.yml 移行)**: reviewer 動的選定の下限 / 上限 / 反復は `review_min_count_test` / `review_max_count_test` / `review_iteration_max` で集中制御。**具体値は固定 default を散文に hardcode せず、起動前に `bash .claude/scripts/hc-config.sh --get review_max_count_test` (上限) / `--get review_min_count_test` (下限) / `--get review_iteration_max` (反復上限) で現在値を確認する**。値解決順: `env(HC_REVIEW_*)` > `harness-config.local.yml` (project override、`install.sh --update` 温存) > `harness-config.yml` (SSoT) > config-loader default。`bash .claude/scripts/hc-config.sh --set review_min_count_test=3` で安全に変更可 (atomic backup + type validation)。詳細は `docs/SELF_IMPROVEMENT.md` §「hc-config.sh による yml 編集」参照。

## 条 6 詳細 (list.md 表現規約)

**依存先列 format** (採用 6 条 2 連動): `task-N1, task-N2, task-N3` (カンマ区切り ID 列挙)、依存なしは `—` (long-dash) で空欄禁止。Task header section に各依存先について **影響内容 + リンク** 記載必須。

**OK/NG 例**:

- **OK 例 (Task 概要欄)**: 「recall_poc plan-first 不在事案の再発防止のため、task-management.md §plan-first を追加し batch planning 時の 📝 行先置きフロー 2 経路分岐を明文化する。完成すれば AI が batch planning 時に list.md plan-first 先置きを規範通り実行できるようになる。」
- **OK 例 (Step 概要欄)**: 「task-management.md §plan-first 新規 subsection 追加 (経路 A/B 分岐 + 凡例 📝 用途明文化)」
- **NG 例 (Task 概要欄)**: 「規範を追加」(目的 / 成果不明) / 「Phase 1 完了、Phase 2 進行中」(Step 状態を概要欄に書かない、それは Step Status 列の責務)
- **NG 例 (Step 概要欄)**: 「task-management.md §plan-first を追加することで AI が規範通り実行できるようになる」(Task 概要欄の規約を Step に流用しない、Step は work only)

## task-29 採用 5 条 supersede 経緯

task-29 採用 5 条 (`docs/draft/phase-step-task-structure.md`、2026-05-23 採用) は task → Phase → Step の 3 階層を規範化したが、task-33 実装で 5 Phase × 14 Step に肥大化し以下の問題を顕在化:

1. Phase 1 完遂時点での status 判定困難 (Phase 完了 = task 完了か Step 完了か曖昧)
2. Step status が IDE 視点で不可視 (list.md row が task 単位のみ)
3. 概要欄の Task / Step 区別なし

→ 2026-05-25 user 4 ターン連続承認で **Task = Phase = N Step (2 階層)** に圧縮し採用 6 条として規範化、task-29 採用 5 条を supersede。
